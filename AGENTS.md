# AGENTS.md - OrchidStratum Developer Guide

## Project Overview

**OrchidStratum** is an Elixir library providing a deterministic, content-addressable caching layer for the [Orchid](https://hex.pm/packages/orchid) workflow engine. It enables massive performance gains by bypassing redundant computations via payload dehydration/hydration and pluggable storage adapters.

## Project Type

- **Language**: Elixir (~> 1.18)
- **Package**: Hex (https://hex.pm/packages/orchid_stratum)
- **Dependencies**: Only `orchid` (core workflow engine)
- **Build Tool**: Mix

---

## Essential Commands

### Development

```bash
# Run tests
mix test

# Run tests with coverage
mix test --cover

# Run a specific test file
mix test test/orchid_stratum_test.exs

# Run iex with project loaded
mix iex -S mix
```

### Documentation

```bash
# Generate documentation (requires ex_doc)
mix docs

# Open generated docs in browser (after docs generated)
open doc/index.html  # macOS
xdg-open doc/index.html  # Linux
```

### Release

```bash
# Build the package for Hex
mix hex.build

# Publish to Hex
mix hex.publish
```

---

## Code Organization

```
lib/
├── orchid_stratum.ex              # Main entry point (apply_cache/4)
├── orchid_stratum/
│   ├── bypass_hook.ex            # Core caching hook (Orchid.Runner.Hook)
│   ├── hash_key_builder.ex        # SHA-256 key derivation
│   ├── blob_storage.ex           # Behaviour for blob storage
│   ├── blob_storage/
│   │   └── ets_adapter.ex        # ETS implementation of BlobStorage
│   ├── meta_storage.ex           # Behaviour + MetaItem struct
│   └── meta_storage/
│       └── ets_adapter.ex        # ETS implementation of MetaStorage

test/
├── orchid_stratum_test.exs        # Integration tests
└── test_helper.exs                # ExUnit startup
```

---

## Architecture & Control Flow

### Two-Tier Storage Model

1. **Meta Store** (`OrchidStratum.MetaStorage`): Records lightweight `MetaItem` structs indexed by step key (hash of step identity + inputs)
2. **Blob Store** (`OrchidStratum.BlobStorage`): Stores actual payloads indexed by content hash (SHA-256 of payload)

### Caching Flow

1. `OrchidStratum.apply_cache/4` wraps steps with `cache: true` option and adds `BypassHook` to global hooks stack
2. On step execution, `BypassHook.call/2` derives a cache key via `HashKeyBuilder.step_key/4`
3. Hook checks Meta Store for cached `MetaItem`:
   - **Cache hit**: Verifies all blob refs still exist, returns dehydrated outputs immediately
   - **Cache miss**: Hydrates any `{:ref, ...}` inputs, executes step, dehydrates outputs (stores blobs + creates MetaItem)

### Dehydration/Hydration

- **Dehydration**: Heavy payloads replaced with `{:ref, blob_store, hash}` tuples
- **Hydration**: `{:ref, ...}` tuples resolved back to original payloads before step execution

---

## Key Patterns & Conventions

### Store Configuration

Both stores use `{module, store_ref}` tuples passed via Orchid's baggage:

```elixir
opts = [
  baggage: %{
    meta_store: {OrchidStratum.MetaStorage.EtsAdapter, meta_ref},
    blob_store: {OrchidStratum.BlobStorage.EtsAdapter, blob_ref}
  },
  global_hooks_stack: [OrchidStratum.BypassHook]
]
```

### Step Options

| Option | Purpose |
|--------|---------|
| `cache: true` | Enables caching for this step |
| `cache_keys: [:opt_a, :opt_b]` | Only listed options included in cache key derivation |

### Cache Key Derivation

Step keys are SHA-256 hashes of:
1. Step implementation (module atom or anonymous function fingerprint)
2. Input param hashes (sorted by param name)
3. Filtered step options (only those in `cache_keys`)

This ensures deterministic, collision-resistant keys independent of map/list ordering.

### Adapter Implementation

Adapters must implement `Orchid.Repo` behaviour. ETS adapters expose these callbacks:

- `init/0` - Creates ETS table, returns reference
- `get(store_ref, key)` - Returns `{:ok, val}` or `:miss`
- `put(store_ref, key, val)` - Returns `:ok`
- `exists?(store_ref, key)` - For BlobStore (returns boolean)
- `delete(store_ref, key)` - For MetaStore (optional)

---

## Testing Patterns

Tests use **session-based isolation** with separate ETS tables per session:

1. **Custom test adapters** (e.g., `MetaStore`, `BlobStore` in test file) accept session name as store reference
2. Each test session gets its own ETS table (e.g., `:session_alpha_Meta`, `:session_alpha_Blob`)
3. Cache hits/misses verified via:
   - Process message assertions (`send(opts[:test_pid], :step_executed)`)
   - Direct store lookups to verify stored data
   - Reference tuple structure verification

### Running Tests

```bash
mix test                    # All tests
mix test --trace           # Show detailed output
mix test test/file.exs:123 # Run specific line
```

---

## Important Gotchas

### ETS Lifecycle

**CRITICAL**: ETS tables created by `init/0` are NOT supervised. If the calling process exits, the table is garbage-collected. For production:
- Wrap adapters in supervised `GenServer`
- Use durable stores (Mnesia, S3, custom NIF)

### Blob Store Reference in Refs

The `{:ref, blob_store, hash}` tuple contains the **exact** `{Module, store_ref}` tuple to support multi-tenant/multi-session scenarios. Never modify the ref tuple structure.

### Cache Key Stability

- Input params are sorted by name before hashing—ensures consistent keys regardless of map order
- Only `cache_keys:` declared options affect the key—runtime options (`:test_pid`, `:timeout`) excluded by design

### Hash Function

Uses SHA-256 via `:crypto.hash/2` over Erlang term binary format. Keys are 32-byte binaries.

---

## Dependencies & External Contracts

### Orchid (Core Dependency)

This library depends on `orchid` (version ~> 0.6). Key Orchid types used:
- `Orchid.Step.t()` - Step specification
- `Orchid.Param.t()` - Parameter struct with name/payload
- `Orchid.Recipe.t()` - Recipe struct
- `Orchid.Runner.Hook` - Hook behaviour for intercepting execution
- `Orchid.WorkflowCtx` - Workflow context access (baggage)
- `Orchid.Repo` - Unified storage behaviour (since v0.2.0)

### Hex Package Config

Package is published to Hex with:
- License: MIT
- Files: `lib/`, `.formatter.exs`, `mix.exs`, `README.md`, `CHANGELOG.md`, `LICENSE`
