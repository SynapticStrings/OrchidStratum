# OrchidStratum

OrchidStratum is a deterministic, content-addressable caching layer designed for the [Orchid](https://hex.pm/packages/orchid) workflow engine. 

The reason for this name is that the processed data, like Stratum, is deposited.

It is specially designed for **incremental generation**, **machine learning pipelines**, and **real-time audio/video rendering engines**, enabling massive performance gains by bypassing redundant computations.

## Features

* **Content-Addressable Cache**: Deterministic caching based on payload hashes.
* **Dehydration & Hydration**: Automatically swaps heavy payloads with lightweight references (`{:ref, store, hash}`) during workflow transitions, drastically reducing memory overhead.
* **Pluggable Storage Adapters**: Easily connect to ETS, Mnesia, or custom Rust NIF-backed out-of-core memory.

## Installation

```elixir
def deps do
  [
    {:orchid, "~> 0.5"},
    {:orchid_stratum, "~> 0.2"}
  ]
end
```

## Quick Start

### 1. Initialise stores

```elixir
meta_ref = OrchidStratum.MetaStorage.EtsAdapter.init()
blob_ref = OrchidStratum.BlobStorage.EtsAdapter.init()

meta_conf = {OrchidStratum.MetaStorage.EtsAdapter, meta_ref}
blob_conf  = {OrchidStratum.BlobStorage.EtsAdapter, blob_ref}
```

### 2a. Wrap an existing recipe automatically

```elixir
{cached_recipe, opts} =
  OrchidStratum.apply_cache(recipe, meta_conf, blob_conf, orchid_opts)

Orchid.run(cached_recipe, inputs, opts)
```

### 2b. Or wire everything up by hand

```elixir
steps = [
  {MyStep, :in, :out, [cache: true]}
]

opts = [
  baggage: %{meta_store: meta_conf, blob_store: blob_conf},
  global_hooks_stack: [OrchidStratum.BypassHook]
]

Orchid.run(Recipe.new(steps), inputs, opts)
```

## Cache Key Semantics

The cache key for a step is deterministic and is derived from:

1. The step's **implementation identity** (module atom or anonymous function
  fingerprint).
2. The **content hashes** of all input `Param` payloads, sorted by parameter
  name.
3. A **filtered subset of step options** — only keys declared in
  `cache_keys:` are included, so runtime-only options (e.g. `:test_pid`)
  never pollute the key space.

See `OrchidStratum.HashKeyBuilder` for the full derivation formula.

## Dehydration & Hydration

When a step produces outputs:

- Each `Param` payload is hashed with SHA-256 and stored in the Blob Store.
- The payload inside the `Param` is **replaced** by `{:ref, blob_store, hash}`.

When a step receives inputs that contain `{:ref, ...}` tuples:

- The hook fetches the original data from the Blob Store before calling the
step (*hydration*), so the step implementation always sees raw payloads.

This design keeps the Orchid workflow graph lean while the heavy data lives
in a dedicated store.
