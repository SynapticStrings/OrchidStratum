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
