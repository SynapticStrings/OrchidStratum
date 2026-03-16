defmodule OrchidStratum.HashKeyBuilder do
  @moduledoc ~S"""
  Builds deterministic, content-addressable cache keys for steps.

  ## Key Derivation

  The step key is derived from three components:

  1. **Implementation identity** — module name or function reference
  2. **Input hashes** — SHA-256 of each input Param's payload (sorted by key name)
  3. **Filtered options** — only options declared as cache-relevant

  $$\mathrm{StepKey} = \mathrm{SHA256}(\mathrm{Impl} \| \mathrm{InputHashes} \| \mathrm{SortedOpts})$$

  For individual output slots:

  $$\mathrm{BlobKey}_n = \mathrm{SHA256}(\mathrm{StepKey} \| n)$$
  """

  @type key_type :: binary()

  @hash_algo :sha256

  @doc """
  Computes the step-level cache key.

  ## Arguments

  * `impl` - The step implementation (module or function).
  * `inputs` - List of `%Orchid.Param{}` structs (already prepared/resolved).
  * `opts` - The step's keyword options.
  * `cache_keys` - List of option keys that affect the output.
    Only these keys are included in the hash. Defaults to `[]`.
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
  Derives a blob key for the specific output of a step.
  """
  @spec blob_key(key_type(), Orchid.Step.io_key()) :: key_type()
  def blob_key(step_key, key_name) do
    {step_key, key_name}
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(@hash_algo, &1))
  end

  @doc """
  Hashes a single Param's payload for use as an input fingerprint.
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
  Computes a pure content hash of a payload for global deduplication.
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
