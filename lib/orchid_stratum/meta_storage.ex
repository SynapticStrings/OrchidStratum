defmodule OrchidStratum.MetaStorage do
  @moduledoc """
  ...
  """

  defmodule MetaItem do
    @type t :: %__MODULE__{
            dehydrated_outputs: any(),
            created_at: integer() | Time.t()
          }
    defstruct [:dehydrated_outputs, :created_at]

    def get_dehydrated_outputs(%__MODULE__{} = meta_item) do
      meta_item.dehydrated_outputs
    end
  end

  @type step_key :: binary()

  @callback get(step_key()) :: {:ok, MetaItem.t()} | :miss

  @callback put(step_key(), meta_entry :: MetaItem.t()) :: :ok

  @callback delete(step_key()) :: :ok
end

defmodule OrchidStratum.MetaStorage.GC do
  @moduledoc "GC feature."
  @callback garbage_collect(opts :: term()) :: :ok
end
