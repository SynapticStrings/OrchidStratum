defmodule OrchidStratum do
  @moduledoc """
  `OrchidStratum` is a deterministic, content-addressable caching layer for the
  [Orchid](https://hex.pm/packages/orchid) workflow engine.

  It intercepts step execution via `OrchidStratum.BypassHook` and routes results
  through a two-tier storage system:

  - **Meta Store** (`OrchidStratum.MetaStorage`) — records a lightweight
    `MetaItem` per step execution, indexed by a hash of the step's identity and
    its inputs.
  - **Blob Store** (`OrchidStratum.BlobStorage`) — stores the actual heavy
    payloads, keyed by their content hash, and replaces them in the workflow
    graph with cheap `{:ref, store, hash}` tuples (*dehydration*).

  On a subsequent run with identical inputs the hook resolves the cached
  `MetaItem`, verifies that every referenced blob is still present, and returns
  the stored outputs — **without executing the step at all**.

  ## Architecture Overview

  ```plain
  Orchid.run(recipe, inputs, opts)
  │
  ▼
  OrchidStratum.BypassHook (global hook)
  │
  ├─ cache miss ──► Step.run/2 ──► dehydrate outputs ──► MetaStore.put + BlobStore.put
  │
  └─ cache hit ──► MetaStore.get ──► blob integrity check ──► return dehydrated outputs
  ```


  ## Quick Start

  ### 1. Initialise stores

    meta_ref = OrchidStratum.MetaStorage.EtsAdapter.init()
    blob_ref = OrchidStratum.BlobStorage.EtsAdapter.init()

    meta_conf = {OrchidStratum.MetaStorage.EtsAdapter, meta_ref}
    blob_conf  = {OrchidStratum.BlobStorage.EtsAdapter, blob_ref}

  ### 2a. Wrap an existing recipe automatically

    {cached_recipe, opts} =
      OrchidStratum.apply_cache(recipe, meta_conf, blob_conf, orchid_opts)

    Orchid.run(cached_recipe, inputs, opts)

  ### 2b. Or wire everything up by hand

    steps = [
      {MyStep, :in, :out, [cache: true]}
    ]

    opts = [
      baggage: %{meta_store: meta_conf, blob_store: blob_conf},
      global_hooks_stack: [OrchidStratum.BypassHook]
    ]

    Orchid.run(Recipe.new(steps), inputs, opts)

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
  """

  @doc """
  Attaches caching to every step in an `Orchid.Recipe` or list of Orchid steps.

  This is the high-level entry point. It delegates to the list-based
  `apply_cache/4` and merges the required baggage and hook into `orchid_opts`.

  Returns `{updated_recipe, updated_orchid_opts}` ready to be passed directly
  to `Orchid.run/3`.

  ## Arguments

  - `recipe_or_steps` — an `%Orchid.Recipe{}` struct or orchid steps.
  - `meta_conf` — a `{module, store_ref}` tuple for the Meta Store adapter.
  - `blob_conf` — a `{module, store_ref}` tuple for the Blob Store adapter.
  - `old_orchid_opts` — the existing keyword options for `Orchid.run/3`.
  Pre-existing baggage keys and hooks are preserved.

  ## Example

      {recipe_or_steps, opts} =
        OrchidStratum.apply_cache(recipe_or_steps, meta_conf, blob_conf, [baggage: %{foo: :bar}])

      Orchid.run(recipe_or_steps, inputs, opts)
  """
  @spec apply_cache(
          [Orchid.Step.t()] | Orchid.Recipe.t(),
          {module(), term()},
          {module(), term()},
          keyword()
        ) ::
          {[Orchid.Step.t()] | Orchid.Recipe.t(), keyword()}
  def apply_cache(%Orchid.Recipe{} = recipe, meta_conf, blob_conf, old_orchid_opts) do
    {new_steps, new_orchid_opts} =
      apply_cache(recipe.steps, meta_conf, blob_conf, old_orchid_opts)

    {%{recipe | steps: new_steps}, new_orchid_opts}
  end

  def apply_cache([_ | _] = steps, meta_conf, blob_conf, old_orchid_opts) do
    new_steps =
      Orchid.Recipe.walk(steps, fn step ->
        case step do
          {impl, in_keys, out_keys} ->
            {impl, in_keys, out_keys, cache: true}

          {impl, in_keys, out_keys, old_step_opts} ->
            {impl, in_keys, out_keys,
             [cache: true, cache_keys: Keyword.keys(old_step_opts)] ++ old_step_opts}
        end
      end)

    {new_steps, add_options(old_orchid_opts, meta_conf, blob_conf)}
  end

  # Merges OrchidStratum-specific baggage and prepends the BypassHook into the
  # existing hooks stack, preserving any caller-supplied hooks that follow it.
  defp add_options(old_orchid_opts, meta_conf, blob_conf) do
    {old_hooks_stack, old_orchid_opts_without_hooks} =
      Keyword.pop(old_orchid_opts, :global_hooks_stack, [])

    {old_baggage, clean_orchid_opts} = Keyword.pop(old_orchid_opts_without_hooks, :baggage, %{})

    clean_orchid_opts ++
      [
        baggage: %{old_baggage | meta_store: meta_conf, blob_store: blob_conf},
        global_hooks_stack: [OrchidStratum.BypassHook] ++ old_hooks_stack
      ]
  end
end
