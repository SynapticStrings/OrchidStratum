defmodule OrchidStratum.BypassHook do
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

  defp process_hash(ctx, next_fn, meta_store, blob_store) do
    cache_used_key = Keyword.get(ctx.step_opts, :cache_keys, [])

    step_key =
      HashKeyBuilder.step_key(ctx.step_implementation, ctx.inputs, ctx.step_opts, cache_used_key)

    with {:ok, cached_meta} <- dispatch_store(meta_store, :get, [step_key]),
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

  defp all_blobs_exist?(dehydrated_outputs, output_keys, blob_store) do
    params =
      dehydrated_outputs
      |> Orchid.Runner.Hooks.Core.align_output_names(output_keys)
      |> List.wrap()

    Enum.all?(params, fn
      # match current blob_store
      %Orchid.Param{payload: {:ref, ^blob_store, hash}} ->
        dispatch_store(blob_store, :exists?, [hash])

      _non_ref ->
        true
    end)
  end

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

        dispatch_store(meta_store, :put, [step_key, meta_entry])
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
    case dispatch_store(store_spec, :get, [hash]) do
      {:ok, data} ->
        %{param | payload: data}

      :miss ->
        raise "Hydration failed! Blob #{inspect(hash)} missing from #{inspect(store_spec)}"
    end
  end

  defp hydrate_param(param), do: param

  defp dehydrate_params(%Orchid.Param{} = param, blob_store), do: dehydrate_param(param, blob_store)
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
        :ok = dispatch_store(blob_store, :put, [hash, payload])

        # 将特定的 store (带 id) 存入 Payload Reference 中
        %{param | payload: {:ref, blob_store, hash}}
    end
  end

  # --- Store Dispatch Helper ---

  # 匹配带有 session/instance 的设定，如 {MyStore, "session_1"}
  defp dispatch_store({mod, instance}, fun, args) do
    apply(mod, fun, [instance | args])
  end

  # 兼容传统用法，如果没有写 {Module, ID}，默认把模块名当做 instance 传入
  defp dispatch_store(mod, fun, args) when is_atom(mod) do
    apply(mod, fun, [mod | args])
  end
end
