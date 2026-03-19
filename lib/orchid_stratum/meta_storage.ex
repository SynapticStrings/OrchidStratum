defmodule OrchidStratum.MetaStorage do
  @moduledoc """
  Behaviour for **Meta Store** adapters.

  A Meta Store records the outcome of a step execution indexed by the step's
  content-addressable key. Each entry is a `MetaItem` that carries the
  dehydrated outputs (with heavy payloads replaced by `{:ref, ...}` tuples)
  plus provenance metadata.

  ## Responsibilities

  - Persist a `MetaItem` keyed by a binary step key (`put/3`).
  - Retrieve a `MetaItem` by step key (`get/2`).
  - Delete a `MetaItem` by step key (`delete/3`) — used by GC and
    manual cache invalidation.

  ## Store Reference

  Like `OrchidStratum.BlobStorage`, every callback receives an opaque
  `store_ref` as its first argument. The reference is the second element of
  the `{module, store_ref}` configuration tuple held in Orchid's baggage
  under the `:meta_store` key.
  """

  defmodule MetaItem do
    @moduledoc "Struct representing a single cached step result in the Meta Store."
    @type t :: %__MODULE__{
            dehydrated_outputs: any(),
            step_implementation: Orchid.Step.implementation(),
            created_at: integer() | Time.t()
          }
    defstruct [:dehydrated_outputs, :step_implementation, :created_at]

    @doc """
    Extracts the dehydrated outputs from a `MetaItem`.

    This is a thin accessor used by `OrchidStratum.BypassHook` when serving
    a cache hit, keeping the hook decoupled from the internal struct layout.
    """
    @spec get_dehydrated_outputs(t()) :: any()
    def get_dehydrated_outputs(%__MODULE__{} = meta_item) do
      meta_item.dehydrated_outputs
    end
  end

  @typedoc """
  An opaque reference to a Meta Store instance, passed as the first argument to every callback.
  The concrete type is defined by the adapter.
  """
  @type store_ref :: term()

  @typedoc """
  A binary content-addressable key identifying a cached step execution.
  Produced by `OrchidStratum.HashKeyBuilder.step_key/4`.
  """
  @type step_key :: binary()

  @doc """
  Retrieves the `MetaItem` associated with `step_key`.

  Returns `{:ok, meta_item}` on a cache hit, or `:miss` if no entry exists.
  """
  @callback get(store :: store_ref(), step_key()) :: {:ok, MetaItem.t()} | :miss

  @doc """
  Persists `meta_entry` under `step_key`.

  Implementations should be **idempotent**: a second `put` with the same key
  may overwrite the existing entry without error.

  Returns `:ok` on success.
  """
  @callback put(store :: store_ref(), step_key(), meta_entry :: MetaItem.t()) :: :ok

  @doc """
  Removes the entry for `step_key` from the store.

  If the key does not exist the call must still return `:ok` (i.e. deletes are
  idempotent).
  """
  @callback delete(store :: store_ref(), step_key()) :: :ok
end

defmodule OrchidStratum.MetaStorage.GC do
  @moduledoc """
  Optional behaviour for Meta Store adapters that support garbage collection.

  Implementing this behaviour is **not** required for a functioning cache — it
  is an extension that adapters opt into when they can reason about entry
  lifecycle (e.g. TTL-based expiry, LRU eviction, capacity limits).

  ## When to Implement

  Implement `OrchidStratum.MetaStorage.GC` alongside `OrchidStratum.MetaStorage`
  when your adapter backs a bounded store (ETS with a size cap, a Redis
  instance with `maxmemory` set, a Mnesia table with a retention policy, etc.).

  ## Example

      defmodule MyApp.MetaStorage.EtsAdapterWithTTL do
        @behaviour OrchidStratum.MetaStorage
        @behaviour OrchidStratum.MetaStorage.GC

        # ... MetaStorage callbacks ...

        @impl OrchidStratum.MetaStorage.GC
        def garbage_collect(opts) do
          ttl_ms = Keyword.get(opts, :ttl_ms, :timer.hours(24))
          cutoff = System.system_time(:millisecond) - ttl_ms

          :ets.select_delete(:my_meta_table, [
            {{:_, %{created_at: :"$1"}}, [{:<, :"$1", cutoff}], [true]}
          ])

          :ok
        end
      end
  """

  @callback garbage_collect(opts :: term()) :: :ok
end
