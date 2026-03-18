defmodule OrchidStratum.BlobStorage do
  @moduledoc """
  Behaviour for **Blob Store** adapters.

  A Blob Store is responsible for persisting and retrieving raw payload data
  (tensors, audio frames, binary chunks, arbitrary Elixir terms, etc.) using a
  content-derived key — typically the SHA-256 hash of the serialised payload.

  ## Responsibilities

  - Store an arbitrary term under a binary content key (`put/3`).
  - Retrieve a term by its content key (`get/2`).
  - Answer existence queries without deserialising the value (`exists?/2`),
  which is used by `OrchidStratum.BypassHook` to verify cache integrity
  before committing to a cache hit.

  ## Store Reference

  Every callback receives a `store_ref` as its first argument. The concrete
  shape of this term is entirely up to the adapter:

  - `OrchidStratum.BlobStorage.EtsAdapter` uses an ETS table reference
  (`:ets.tid()`).
  - A hypothetical S3 adapter might use a `%{bucket: "...", region: "..."}` map.

  The store reference is carried through the workflow as the first element of
  the `{module, store_ref}` configuration tuple kept in Orchid's baggage under
  the `:blob_store` key.

  ## Implementing a Custom Adapter

    defmodule MyApp.BlobStorage.S3Adapter do
      @behaviour OrchidStratum.BlobStorage

      @impl true
      def exists?(cfg, key), do: S3.head_object(cfg.bucket, key) == :ok

      @impl true
      def get(cfg, key) do
        case S3.get_object(cfg.bucket, key) do
          {:ok, body} -> {:ok, :erlang.binary_to_term(body)}
          _           -> :miss
        end
      end

      @impl true
      def put(cfg, key, payload) do
        :ok = S3.put_object(cfg.bucket, key, :erlang.term_to_binary(payload))
      end
    end
  """

  @typedoc """
  An opaque reference to a store instance.

  The concrete type is determined by the adapter. It is always passed as the
  first argument to every callback.
  """
  @type store_ref :: term()

  @typedoc """
  A binary content-addressable key — typically the raw bytes of a SHA-256 digest.
  """
  @type blob_key :: binary()

  @typedoc """
  An arbitrary Elixir term stored as a blob (e.g. a tensor, audio buffer, map).
  """
  @type raw_data :: term()

  @doc """
  Returns `true` if a blob with the given `content_hash` exists in the store.

  This **must not** deserialise the stored value. It is called on every cached
  step before a cache hit is confirmed, so it must be cheap.
  """
  @callback exists?(store :: store_ref(), content_hash :: blob_key()) :: boolean()

  @doc """
  Retrieves the blob associated with `content_hash`.

  Returns `{:ok, raw_data}` on success or `:miss` if no entry is found.
  """
  @callback get(store :: store_ref(), content_hash :: blob_key()) :: {:ok, raw_data()} | :miss

  @doc """
  Persists `payload` under the given `content_hash`.

  Implementations should be **idempotent**: storing the same key twice with the
  same value must not fail or corrupt state.

  Returns `:ok` on success.
  """
  @callback put(store :: store_ref(), content_hash :: blob_key(), payload :: raw_data()) :: :ok
end
