defmodule OrchidStratum.MetaStorage do
  @moduledoc """
  ...
  """

  @type step_key :: binary()
  @type meta :: term()

  @callback get(step_key()) :: {:ok, meta()} | :miss

  @callback put(step_key(), meta_entry :: meta()) :: :ok

  @callback delete(step_key()) :: :ok

end

defmodule OrchidStratum.MetaStorage.GC do
  @moduledoc "GC feature."
  @callback garbage_collect(opts :: term()) :: :ok
end
