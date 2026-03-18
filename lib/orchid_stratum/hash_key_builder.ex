defmodule OrchidStratum.HashKeyBuilder do
  @moduledoc ~S"""
  Builds deterministic, content-addressable cache keys for steps and payloads.

  All keys are raw binary SHA-256 digests produced by `:crypto.hash/2` over
  the Erlang external term format of a canonical data structure. This ensures
  that keys are both compact and collision-resistant.

  ## Step Key Derivation

  The step key is derived from three components:

  1. **Implementation identity** — the module atom (converted to a string) or,
     for anonymous functions, a tuple of `{module, name, arity, env}` that
     captures the closure's compile-time environment.
  2. **Input hashes** — the SHA-256 fingerprint of each input `Param`'s
     payload, sorted ascending by parameter name to ensure key stability
     regardless of map/list ordering.
  3. **Filtered options** — only step options whose keys appear in `cache_keys`
     are included. Runtime-only options (e.g. `:test_pid`, `:timeout`) are
     excluded so they do not generate spurious cache misses.

  Formally:

  ```plain
  StepKey = SHA256[term_to_binary(
    Impl || InputHash(es) || SortedAndFilteredOptions
  )]
  ```

  where `InputHashes` is the ordered list `[h_1, h_2, ..., h_n]` with `h_i = SHA256[term_to_binary(payload_i)]`.

  ## Blob Key Derivation

  A blob key identifies a specific output slot of a step:

  ```plain
  BlobKey_k = SHA256[term_to_binary(
    {StepKey, k}
  )]
  ```

  where `k` is the output key name (an atom). This construction guarantees
  that two steps with identical inputs but different output names never collide.

  ## Reference Payloads

  When a `Param` already carries a `{:ref, _mod, ref_key}` payload, the
  `ref_key` itself is used as the input fingerprint verbatim (no additional
  hashing). Because ref keys are already content-addressable, double-hashing
  would waste CPU cycles without improving correctness.
  """

  @type key_type :: binary()

  @hash_algo :sha256

  @doc """
  Computes the step-level cache key.

  The key is a binary SHA-256 digest that uniquely identifies the combination
  of step implementation, input content, and cache-relevant options.

  ## Arguments

  - `impl` — the step implementation: either a module atom (`MyApp.Step`) or
    an anonymous function of arity 2.
  - `inputs` — one of:
    - a single `%Orchid.Param{}` struct,
    - a list of `%Orchid.Param{}` structs, or
    - a map of `{key => %Orchid.Param{}}` entries.
  - `opts` — the full keyword options list attached to the step.
  - `cache_keys` — list of option keys from `opts` that influence step output.
    Only these keys are folded into the hash. Defaults to `[]`.

  ## Example

      step_key = OrchidStratum.HashKeyBuilder.step_key(
        MyStep,
        [%Orchid.Param{name: :in, payload: "hello"}],
        [mode: :fast, test_pid: self()],
        [:mode]   # :test_pid is excluded from the key
      )

      is_binary(step_key)  #=> true
      byte_size(step_key)  #=> 32
  """
  @spec step_key(
          Orchid.Step.implementation(),
          [Orchid.Param.t()] | Orchid.Param.t() | %{optional(any()) => Orchid.Param.t()},
          keyword(),
          [atom()]
        ) :: key_type()
  def step_key(impl, inputs, opts, cache_keys \\ []) do
    impl_term = normalize_impl(impl)

    input_hashes =
      inputs
      |> extract_params()
      |> Enum.sort_by(& &1.name)
      |> Enum.map(&hash_param/1)

    filtered_opts =
      opts
      |> Keyword.take(cache_keys)
      |> Enum.sort()

    hash_term = {impl_term, input_hashes, filtered_opts}

    :crypto.hash(@hash_algo, :erlang.term_to_binary(hash_term))
  end

  @doc """
  Derives a blob key for a specific named output slot of a step.

  The blob key is a SHA-256 digest of the tuple `{step_key, key_name}`,
  which binds the content identity of the step (encoded in `step_key`) to a
  particular output name. This means two steps that produce identical data
  under different output keys will still get distinct blob keys.

  ## Arguments

  - `step_key` — the binary step-level key returned by `step_key/4`.
  - `key_name` — the atom identifying the output slot (e.g. `:embeddings`).

  ## Example

      blob_key = OrchidStratum.HashKeyBuilder.blob_key(step_key, :embeddings)
      byte_size(blob_key)  #=> 32
  """
  @spec blob_key(key_type(), Orchid.Step.io_key()) :: key_type()
  def blob_key(step_key, key_name) do
    {step_key, key_name}
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(@hash_algo, &1))
  end

  @doc """
  Produces an input fingerprint for a single `Param`.

  - If the `Param` payload is a `{:ref, _mod, ref_key}` tuple, `ref_key` is
    returned as-is, because it is already a content-addressable binary.
  - Otherwise the payload is serialised with `:erlang.term_to_binary/1` and
    hashed with SHA-256.

  This function is used internally by `step_key/4` to build the ordered list
  of input fingerprints, but it is public so that adapters and tests can
  inspect individual param hashes.

  ## Example

      h1 = OrchidStratum.HashKeyBuilder.hash_param(%Orchid.Param{name: :x, payload: 42})
      h2 = OrchidStratum.HashKeyBuilder.hash_param(%Orchid.Param{name: :x, payload: 42})
      h1 == h2  #=> true
  """
  @spec hash_param(Orchid.Param.t()) :: binary()
  def hash_param(%Orchid.Param{payload: {:ref, _mod, ref_key}}) do
    # For ref-based payloads, hash the reference key itself
    # (the ref key should already be content-addressable)
    ref_key
  end

  def hash_param(%Orchid.Param{} = param) do
    :crypto.hash(@hash_algo, :erlang.term_to_binary(param.payload))
  end

  @doc """
  Computes a raw content hash of an arbitrary payload term.

  Used by `OrchidStratum.BypassHook` to derive the Blob Store key before
  persisting a new output payload. The result is a 32-byte binary SHA-256
  digest suitable for use as a `OrchidStratum.BlobStorage.blob_key()`.

  ## Example

      key = OrchidStratum.HashKeyBuilder.payload_hash(%{tensor: <<1, 2, 3>>})
      byte_size(key)  #=> 32
  """
  @spec payload_hash(Orchid.Param.payload()) :: key_type()
  def payload_hash(payload) do
    :crypto.hash(@hash_algo, :erlang.term_to_binary(payload))
  end

  # --- Internal Helpers ---

  defp extract_params(%Orchid.Param{} = param), do: [param]
  defp extract_params(inputs) when is_list(inputs), do: inputs
  defp extract_params(inputs) when is_map(inputs), do: Map.values(inputs)

  defp normalize_impl(mod) when is_atom(mod), do: Atom.to_string(mod)

  defp normalize_impl(fun) when is_function(fun, 2) do
    info = Function.info(fun)
    # Use module + name + arity as identity for named functions
    # For anonymous functions, this includes the unique env hash
    {info[:module], info[:name], info[:arity], info[:env]}
    |> :erlang.term_to_binary()
  end
end
