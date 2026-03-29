# Changelog

## [0.2.0] - Refactored

### 🚀 Highlights

**Unified Storage Architecture**: The storage abstraction has been completely overhauled. We extracted the storage behaviours from `OrchidStratum` and generalized them into `Orchid.Repo` in the core engine. This unified foundation allows external applications and plugins to share the same standard for out-of-core memory, large payload storage, and caching, without being forced to depend on the `OrchidStratum` caching layer.

### 🔄 Changed

- **`OrchidStratum` Adapters:** All built-in storage adapters (Meta and Blob) have been refactored to implement the unified `Orchid.Repo` behaviour instead of custom ones.
- **`OrchidStratum.MetaItem`:** Decoupled from storage behaviours. It is now a pure struct (`%OrchidStratum.MetaItem{}`) used exclusively by Stratum's caching hooks to manage data dehydration/hydration.

## [0.1.0] - Created lib
