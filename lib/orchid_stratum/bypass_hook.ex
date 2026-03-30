defmodule OrchidStratum.BypassHook do
  @moduledoc """
  An `Orchid.Runner.Hook` that transparently intercepts step execution and
  serves results from cache when possible.

  ## How It Works

  For every step in the workflow, the hook:

  1. **Checks cacheability** — the step must have `cache: true` in its options,
     and both `:meta_store` and `:blob_store` must be present in the workflow
     baggage. If either condition is false the step is executed normally.

  2. **Derives a cache key** — delegates to `OrchidStratum.HashKeyBuilder.step_key/4`.

  3. **Probes the Meta Store** — if a `MetaItem` exists for the key and every
     referenced blob is still reachable in the Blob Store, the cached outputs
     are returned immediately (**cache hit**).

  4. **Executes the step on a miss** — hydrates any `{:ref, ...}` inputs back
     to their raw payloads, calls the underlying step, then dehydrates the
     outputs (storing payloads in the Blob Store and replacing them with
     `{:ref, blob_store, hash}` tuples) and persists a new `MetaItem`.

  ## Enabling the Hook

  The hook is registered as a global hook in Orchid options:

      opts = [
        baggage: %{
          meta_store: {MyMetaAdapter, meta_ref},
          blob_store: {MyBlobAdapter, blob_ref}
        },
        global_hooks_stack: [OrchidStratum.BypassHook]
      ]

  Or use `OrchidStratum.apply_cache/4` to have this wired automatically.

  ## Per-Step Control

  | Step option | Effect |
  |---|---|
  | `cache: true` | Enables caching for this step. |
  | `cache: false` (default) | Step is always executed; hook is a no-op. |
  | `cache_keys: [:opt_a]` | Only `:opt_a` from the step's opts is included in the cache key. |

  ## Dehydration Contract

  Dehydrated outputs carry payloads of the form `{:ref, blob_store, hash}`.
  The `blob_store` component is the **exact store configuration tuple**
  `{Module, store_ref}` so that the hook can route blob lookups to the correct
  adapter instance, even in multi-session or multi-tenant scenarios.

  Blob integrity is verified with `BlobStorage.exists?/2` before every cache
  hit, ensuring the hook is safe against store eviction or external deletion.
  """
  @behaviour Orchid.Runner.Hook

  alias OrchidStratum.{HashKeyBuilder, MetaStorage.MetaItem}

  @spec call(Orchid.Runner.Context.t(), Orchid.Runner.Hook.next_fn()) ::
          Orchid.Runner.Hook.hook_result()
  def call(ctx, next_fn) do
    is_cacheable = Keyword.get(ctx.step_opts, :cache, false)

    meta_store = Orchid.WorkflowCtx.get_baggage(ctx.workflow_ctx, :meta_store)
    blob_store = Orchid.WorkflowCtx.get_baggage(ctx.workflow_ctx, :blob_store)

    case {is_cacheable, meta_store, blob_store} do
      {true, meta_store, blob_store} when not (is_nil(meta_store) or is_nil(blob_store)) ->
        process_hash(ctx, next_fn, meta_store, blob_store)

      _ ->
        next_fn.(ctx)
    end
  end

  # Derives the step key, checks the meta store, and either returns cached
  # outputs or falls through to actual execution.
  defp process_hash(ctx, next_fn, meta_store, blob_store) do
    cache_used_key = Keyword.get(ctx.step_opts, :cache_keys, [])

    step_key =
      HashKeyBuilder.step_key(ctx.step_implementation, ctx.inputs, ctx.step_opts, cache_used_key)

    with {:ok, cached_meta} <- Orchid.Repo.dispatch_store(meta_store, :get, [step_key]),
         maybe_dehydrated_outputs = MetaItem.get_dehydrated_outputs(cached_meta),
         true <- all_blobs_exist?(maybe_dehydrated_outputs, ctx.out_keys, blob_store) do
      # if telemetry enabled, send an event
      {:ok, maybe_dehydrated_outputs}
    else
      # miss or false
      _state ->
        # if telemetry enabled, send an event
        execute_and_hash(ctx, next_fn, meta_store, blob_store, step_key)
    end
  end

  # Verifies that every {:ref, blob_store, hash} in the cached outputs still
  # has a backing blob. Returns true only if all refs resolve.
  defp all_blobs_exist?(dehydrated_outputs, output_keys, blob_store) do
    params =
      dehydrated_outputs
      |> Orchid.Runner.Hooks.Core.align_output_names(output_keys)
      |> List.wrap()

    Enum.all?(params, fn
      # match current blob_store
      %Orchid.Param{payload: {:ref, ^blob_store, hash}} ->
        Orchid.Repo.dispatch_store(blob_store, :exists?, [hash])

      _non_ref ->
        true
    end)
  end

  # Executes the step, dehydrates its outputs, and persists a new MetaItem.
  defp execute_and_hash(ctx, next_fn, meta_store, blob_store, step_key) do
    hydrated_inputs = hydrate_params(ctx.inputs)

    next_fn.(%{ctx | inputs: hydrated_inputs})
    |> case do
      {:ok, res} ->
        dehydrated_outputs = dehydrate_params(res, blob_store)

        meta_entry = %MetaItem{
          dehydrated_outputs: dehydrated_outputs,
          step_implementation: ctx.step_implementation,
          created_at: System.system_time(:millisecond)
        }

        Orchid.Repo.dispatch_store(meta_store, :put, [step_key, meta_entry])
        {:ok, dehydrated_outputs}

      err_or_special ->
        err_or_special
    end
  end

  # --- State Transformation Helpers ---

  defp hydrate_params(%Orchid.Param{} = param), do: hydrate_param(param)
  defp hydrate_params(params) when is_list(params), do: Enum.map(params, &hydrate_param/1)

  defp hydrate_params(params) when is_map(params) do
    Map.new(params, fn {k, v} -> {k, hydrate_param(v)} end)
  end

  defp hydrate_param(%Orchid.Param{payload: {:ref, store_spec, hash}} = param) do
    case Orchid.Repo.dispatch_store(store_spec, :get, [hash]) do
      {:ok, data} ->
        %{param | payload: data}

      :miss ->
        raise "Hydration failed! Blob #{inspect(hash)} missing from #{inspect(store_spec)}"
    end
  end

  defp hydrate_param(param), do: param

  defp dehydrate_params(%Orchid.Param{} = param, blob_store),
    do: dehydrate_param(param, blob_store)

  defp dehydrate_params(params, blob_store) when is_list(params) do
    Enum.map(params, &dehydrate_param(&1, blob_store))
  end

  defp dehydrate_params(params, blob_store) when is_map(params) do
    Map.new(params, fn {k, v} -> {k, dehydrate_param(v, blob_store)} end)
  end

  defp dehydrate_param(%Orchid.Param{payload: payload} = param, blob_store) do
    case payload do
      {:ref, ^blob_store, _hash} ->
        param

      _raw_data_or_other_ref_mod ->
        hash = HashKeyBuilder.payload_hash(payload)
        :ok = Orchid.Repo.dispatch_store(blob_store, :put, [hash, payload])

        %{param | payload: {:ref, blob_store, hash}}
    end
  end
end
