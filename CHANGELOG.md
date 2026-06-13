# Changelog

## [0.2.1] - Unreleased

### ➕ Added

- **`BypassHook` payload stabilizer**: Added optional `payload_stabilizer` callback via baggage. Callers can inject a function `(payload -> stable_payload)` that runs on every step output before ETS dehydration. This prevents issues where backend-managed data (e.g. Ortex ONNX tensors backed by an inference arena) becomes a dangling reference after the arena is freed.

```elixir
baggage: %{
  meta_store: {...},
  blob_store: {...},
  payload_stabilizer: &Nx.backend_transfer(&1, Nx.BinaryBackend)
}
```

OrchidStratum itself does not depend on Nx — the stabilizer is caller-injected and entirely optional.

## [0.2.0] - Refactored

### 🚀 Highlights

**Unified Storage Architecture**: The storage abstraction has been completely overhauled. We extracted the storage behaviours from `OrchidStratum` and generalized them into `Orchid.Repo` in the core engine. This unified foundation allows external applications and plugins to share the same standard for out-of-core memory, large payload storage, and caching, without being forced to depend on the `OrchidStratum` caching layer.

### 🔄 Changed

- **`OrchidStratum` Adapters:** All built-in storage adapters (Meta and Blob) have been refactored to implement the unified `Orchid.Repo` behaviour instead of custom ones.
- **`OrchidStratum.MetaItem`:** Decoupled from storage behaviours. It is now a pure struct (`%OrchidStratum.MetaItem{}`) used exclusively by Stratum's caching hooks to manage data dehydration/hydration.

## [0.1.0] - Created lib
