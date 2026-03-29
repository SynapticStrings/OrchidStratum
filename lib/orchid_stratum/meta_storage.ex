defmodule OrchidStratum.MetaStorage do
  @moduledoc """
  A Meta Store records the outcome of a step execution indexed by the step's
  content-addressable key. Each entry is a `MetaItem` that carries the
  dehydrated outputs (with heavy payloads replaced by `{:ref, ...}` tuples)
  plus provenance metadata.

  ## Responsibilities

  - Persist a `MetaItem` keyed by a binary step key (`put/3`).
  - Retrieve a `MetaItem` by step key (`get/2`).
  - Delete a `MetaItem` by step key (`delete/3`) — used by GC and
    manual cache invalidation.

  ## Store Reference

  Like `OrchidStratum.BlobStorage`, every callback receives an opaque
  `store_ref` as its first argument. The reference is the second element of
  the `{module, store_ref}` configuration tuple held in Orchid's baggage
  under the `:meta_store` key.
  """

  defmodule MetaItem do
    @moduledoc "Struct representing a single cached step result in the Meta Store."
    @type t :: %__MODULE__{
            dehydrated_outputs: any(),
            step_implementation: Orchid.Step.implementation(),
            created_at: integer() | Time.t()
          }
    defstruct [:dehydrated_outputs, :step_implementation, :created_at]

    @doc """
    Extracts the dehydrated outputs from a `MetaItem`.

    This is a thin accessor used by `OrchidStratum.BypassHook` when serving
    a cache hit, keeping the hook decoupled from the internal struct layout.
    """
    @spec get_dehydrated_outputs(t()) :: any()
    def get_dehydrated_outputs(%__MODULE__{} = meta_item) do
      meta_item.dehydrated_outputs
    end
  end
end
