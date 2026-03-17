defmodule OrchidStratum.BypassHook do
  @behaviour Orchid.Runner.Hook

  alias OrchidStratum.HashKeyBuilder

  @spec call(Orchid.Runner.Context.t(), Orchid.Runner.Hook.next_fn()) ::
          Orchid.Runner.Hook.hook_result()
  def call(ctx, next_fn) do
    is_cacheable = Keyword.get(ctx.step_opts, :cache, false)

    # Put global content into workflow ctx
    meta_mod = Orchid.WorkflowCtx.get_baggage(ctx.workflow_ctx, :meta_store)
    blob_mod = Orchid.WorkflowCtx.get_baggage(ctx.workflow_ctx, :blob_store)

    case {is_cacheable, meta_mod, blob_mod} do
      {true, meta_mod, blob_mod} when not (is_nil(meta_mod) or is_nil(blob_mod)) ->
        process_hash(ctx, next_fn, meta_mod, blob_mod)

      _ ->
        next_fn.(ctx)
    end
  end

  defp process_hash(ctx, next_fn, meta_mod, blob_mod) do
    cache_used_key = Keyword.get(ctx.step_opts, :cache_keys, [])

    step_key =
      HashKeyBuilder.step_key(ctx.step_implementation, ctx.inputs, ctx.step_opts, cache_used_key)

    with {:ok, cached_meta} <- apply(meta_mod, :get, [step_key]),
         true <- all_blobs_exist?(cached_meta, blob_mod) do
      # Directly return our lightweight cached reference structure
      {:ok, cached_meta.dehydrated_outputs}
    else
      # miss or false
      _ -> execute_and_hash(ctx, next_fn, meta_mod, blob_mod, step_key)
    end
  end

  defp all_blobs_exist?(%{dehydrated_outputs: dehydrated_outputs}, blob_mod) do
    params =
      case dehydrated_outputs do
        %Orchid.Param{} = single -> [single]
        list when is_list(list) -> list
        map when is_map(map) -> Map.values(map)
      end

    Enum.all?(params, fn
      %Orchid.Param{payload: {:ref, ^blob_mod, hash}} ->
        apply(blob_mod, :exists?, [hash])

      _non_ref ->
        true
    end)
  end

  defp execute_and_hash(ctx, next_fn, meta_mod, blob_mod, step_key) do
    # Hydrate inputs and preserve original map/list/struct shape
    hydrated_inputs = hydrate_params(ctx.inputs, blob_mod)

    next_fn.(%{ctx | inputs: hydrated_inputs})
    |> case do
      {:ok, res} ->
        # Maintain exact return shape but with dehydrated reference payloads
        dehydrated_outputs = dehydrate_params(res, blob_mod)

        meta_entry = %{
          dehydrated_outputs: dehydrated_outputs,
          created_at: System.system_time(:millisecond)
        }

        apply(meta_mod, :put, [step_key, meta_entry])

        {:ok, dehydrated_outputs}

      err_or_special ->
        err_or_special
    end
  end

  # --- State Transformation Helpers ---

  defp hydrate_params(%Orchid.Param{} = param, blob_mod) do
    hydrate_param(param, blob_mod)
  end

  defp hydrate_params(params, blob_mod) when is_list(params) do
    Enum.map(params, &hydrate_param(&1, blob_mod))
  end

  defp hydrate_params(params, blob_mod) when is_map(params) do
    Map.new(params, fn {k, v} -> {k, hydrate_param(v, blob_mod)} end)
  end

  defp hydrate_param(%Orchid.Param{payload: {:ref, store_mod, hash}} = param, _blob_mod) do
    case store_mod.get(hash) do
      {:ok, data} ->
        %{param | payload: data}

      :miss ->
        raise "Hydration failed! Blob #{inspect(hash)} missing from #{inspect(store_mod)}"
    end
  end

  defp hydrate_param(param, _blob_mod), do: param

  defp dehydrate_params(%Orchid.Param{} = param, blob_mod) do
    dehydrate_param(param, blob_mod)
  end

  defp dehydrate_params(params, blob_mod) when is_list(params) do
    Enum.map(params, &dehydrate_param(&1, blob_mod))
  end

  defp dehydrate_params(params, blob_mod) when is_map(params) do
    Map.new(params, fn {k, v} -> {k, dehydrate_param(v, blob_mod)} end)
  end

  defp dehydrate_param(%Orchid.Param{payload: payload} = param, blob_mod) do
    # If it's somehow already a ref (e.g., a pass-through step), skip hashing
    case payload do
      {:ref, ^blob_mod, _hash} ->
        param

      _actual_data ->
        hash = HashKeyBuilder.payload_hash(payload)
        :ok = blob_mod.put(hash, payload)

        %{param | payload: {:ref, blob_mod, hash}}
    end
  end
end
