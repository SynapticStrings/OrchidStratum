defmodule OrchidStratum.BypassHookTest do
  use ExUnit.Case

  alias Orchid.{Recipe, Param}

  # ==========================================
  # 1. Dummy Storage Backends (Session Based)
  # ==========================================

  defmodule MetaStore do
    @behaviour OrchidStratum.MetaStorage

    # 允许初始化特定的 Session ETS 表
    def init(session_name), do: :ets.new(session_to_table(session_name), [:set, :public, :named_table])

    # 第一个参数变成了 store_ref (ets_table_name)
    @impl true
    def get(session_name, key) do
      case :ets.lookup(session_to_table(session_name), key) do
        [{^key, val}] -> {:ok, val}
        [] -> :miss
      end
    end

    @impl true
    def put(session_name, key, val) do
      :ets.insert(session_to_table(session_name), {key, val})
      :ok
    end

    @impl true
    def delete(session_name, key) do
      :ets.delete(session_to_table(session_name), key)
    end

    defp session_to_table(session_name), do: :"#{session_name}_Meta"
  end

  defmodule BlobStore do
    @behaviour OrchidStratum.BlobStorage

    def init(session_name), do: :ets.new(session_to_table(session_name), [:set, :public, :named_table])

    @impl true
    def get(session_name, key) do
      case :ets.lookup(session_to_table(session_name), key) do
        [{^key, val}] -> {:ok, val}
        [] -> :miss
      end
    end

    @impl true
    def put(session_name, key, val) do
      :ets.insert(session_to_table(session_name), {key, val})
      :ok
    end

    @impl true
    def exists?(session_name, key) do
      :ets.member(session_to_table(session_name), key)
    end

    defp session_to_table(session_name), do: :"#{session_name}_Blob"
  end

  # ==========================================
  # 2. Dummy Steps (保持不变)
  # ==========================================
  defmodule StepOne do
    use Orchid.Step
    def run(input, opts) do
      send(opts[:test_pid], :step_one_executed)
      {:ok, Param.new(:mid, :data, Param.get_payload(input) <> " -> StepOne")}
    end
  end

  defmodule StepTwo do
    use Orchid.Step
    def run(input, opts) do
      send(opts[:test_pid], :step_two_executed)
      {:ok, Param.new(:out, :data, Param.get_payload(input) <> " -> StepTwo")}
    end
  end

  # ==========================================
  # 3. Multi-Session Test Case
  # ==========================================

  setup do
    MetaStore.init(:session_alpha)
    BlobStore.init(:session_alpha)

    MetaStore.init(:session_beta)
    BlobStore.init(:session_beta)

    :ok
  end

  test "multi-session cache isolation" do
    inputs = [Param.new(:in, :data, "Start")]
    steps = [
      {StepOne, :in, :mid, [cache: true, test_pid: self()]},
      {StepTwo, :mid, :out, [cache: true, test_pid: self()]}
    ]
    recipe = Recipe.new(steps, name: :test_recipe)

    # ---------- SESSION ALPHA ----------
    opts_alpha = [
      baggage: %{
        # 配置形式变成了 {Module, Session_Identifier}
        meta_store: {MetaStore, :session_alpha},
        blob_store: {BlobStore, :session_alpha}
      },
      global_hooks_stack: [OrchidStratum.BypassHook]
    ]

    # Session Alpha: 首次运行，缓存未命中
    assert {:ok, results_alpha1} = Orchid.run(recipe, inputs, opts_alpha)
    assert_received :step_one_executed
    assert_received :step_two_executed

    # 验证生成的 Reference 中包含了 Session 标识
    out_param = results_alpha1[:out]
    assert {:ref, {BlobStore, :session_alpha}, hash} = out_param.payload
    assert {:ok, "Start -> StepOne -> StepTwo"} = BlobStore.get(:session_alpha, hash)

    # Session Alpha: 第二次运行，应该是缓存命中
    assert {:ok, _} = Orchid.run(recipe, inputs, opts_alpha)
    refute_received :step_one_executed # Prove Cache Hit


    # ---------- SESSION BETA ----------
    opts_beta = [
      baggage: %{
        meta_store: {MetaStore, :session_beta},
        blob_store: {BlobStore, :session_beta}
      },
      global_hooks_stack: [OrchidStratum.BypassHook]
    ]

    # Session Beta: 尽管 input 相同，但这是个全新的 Session，应该是缓存未命中
    assert {:ok, results_beta} = Orchid.run(recipe, inputs, opts_beta)

    # 证明步骤由于跨 Session 被重新执行了
    assert_received :step_one_executed
    assert_received :step_two_executed

    # Session Beta 的结果被存储在属于自己的空间里
    out_param_beta = results_beta[:out]
    assert {:ref, {BlobStore, :session_beta}, hash_beta} = out_param_beta.payload

    # 因为输入相同，Content Hash 是相同的，但隔离存放在不同的 Session ETS 里
    assert hash == hash_beta
    assert {:ok, "Start -> StepOne -> StepTwo"} = BlobStore.get(:session_beta, hash_beta)
  end
end
