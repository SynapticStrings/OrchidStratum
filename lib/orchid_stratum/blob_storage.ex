defmodule OrchidStratum.BlobStorage do
  @moduledoc """
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
  """
end
