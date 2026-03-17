defmodule OrchidStratum.BypassHookTest do
  use ExUnit.Case

  alias Orchid.{Recipe, Param}

  # ==========================================
  # 1. Dummy Storage Backends (ETS)
  # ==========================================

  defmodule MetaStore do
    @behaviour OrchidStratum.MetaStorage

    def init, do: :ets.new(__MODULE__, [:set, :public, :named_table])

    @impl true
    def get(key) do
      case :ets.lookup(__MODULE__, key) do
        [{^key, val}] -> {:ok, val}
        [] -> :miss
      end
    end

    @impl true
    def put(key, val) do
      :ets.insert(__MODULE__, {key, val})
      :ok
    end

    @impl true
    def delete(key) do
      :ets.delete(__MODULE__, key)
    end
  end

  defmodule BlobStore do
    @behaviour OrchidStratum.BlobStorage

    def init, do: :ets.new(__MODULE__, [:set, :public, :named_table])

    @impl true
    def get(key) do
      case :ets.lookup(__MODULE__, key) do
        [{^key, val}] -> {:ok, val}
        [] -> :miss
      end
    end

    @impl true
    def put(key, val) do
      :ets.insert(__MODULE__, {key, val})
      :ok
    end

    @impl true
    def exists?(key) do
      :ets.member(__MODULE__, key)
    end
  end

  # ==========================================
  # 2. Dummy Steps for Pipeline Execution
  # ==========================================

  defmodule StepOne do
    use Orchid.Step

    def run(input, opts) do
      # Send a message to the test process to track execution
      send(opts[:test_pid], :step_one_executed)

      payload = Param.get_payload(input)
      {:ok, Param.new(:mid, :data, payload <> " -> StepOne")}
    end
  end

  defmodule StepTwo do
    use Orchid.Step

    def run(input, opts) do
      send(opts[:test_pid], :step_two_executed)

      payload = Param.get_payload(input)
      {:ok, Param.new(:out, :data, payload <> " -> StepTwo")}
    end
  end

  # ==========================================
  # 3. The Test Cases
  # ==========================================

  setup do
    :telemetry.attach(
        "orchid-step-exception-logger",
        [:orchid, :step, :exception],
        &Orchid.Runner.Hooks.Telemetry.error_handler/4,
        %{}
      )

    # Initialize our in-memory cache stores
    MetaStore.init()
    BlobStore.init()

    :ok
  end

  test "pipeline cache miss, execution, hydration, and subsequent cache hit" do
    # 1. Setup the inputs and recipe
    inputs =[Param.new(:in, :data, "Start")]

    steps = [
      {StepOne, :in, :mid,[cache: true, test_pid: self()]},
      {StepTwo, :mid, :out,[cache: true, test_pid: self()]}
    ]

    recipe = Recipe.new(steps, name: :test_recipe)

    # 2. Setup the runtime options with our BypassHook and Baggage
    opts = [
      baggage: %{
        meta_store: {MetaStore, []},
        blob_store: {BlobStore, []}
      },
      global_hooks_stack: [OrchidStratum.BypassHook]
    ]

    # --- FIRST RUN (Cache Miss) ---
    assert {:ok, results1} = Orchid.run(recipe, inputs, opts)

    # Prove both steps executed
    assert_received :step_one_executed
    assert_received :step_two_executed

    # Prove the output is dehydrated (a lightweight reference)
    out_param = results1[:out]
    assert {:ref, BlobStore, hash} = out_param.payload

    # Prove the actual final data was safely stored in the BlobStore
    assert {:ok, "Start -> StepOne -> StepTwo"} = BlobStore.get(hash)


    # --- SECOND RUN (Cache Hit) ---
    # Running the exact same pipeline with identical inputs
    assert {:ok, results2} = Orchid.run(recipe, inputs, opts)

    # Prove NEITHER step executed because the cache caught them
    refute_received :step_one_executed
    refute_received :step_two_executed

    # Prove we get back the exact same reference hash
    assert results1[:out] == results2[:out]


    # --- THIRD RUN (Cache Invalidation) ---
    # Change the input slightly to ensure the cache invalidates (Merkle DAG property)
    new_inputs =[Param.new(:in, :data, "Different_Start")]

    assert {:ok, _results3} = Orchid.run(recipe, new_inputs, opts)

    # Prove both steps execute again because the input hash changed
    assert_received :step_one_executed
    assert_received :step_two_executed
  end
end
