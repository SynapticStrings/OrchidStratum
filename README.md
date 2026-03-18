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
    {:orchid_stratum, "~> 0.1"}
  ]
end
```
