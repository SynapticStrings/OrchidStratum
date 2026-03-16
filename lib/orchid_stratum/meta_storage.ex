defmodule OrchidStratum.MetaStorage do
  @moduledoc """
  ...
  """

  @type step_key :: binary()
  @type meta :: term()

  @callback get(step_key(), get_opts :: any()) :: {:ok, meta()} | :miss

  @callback put(step_key(), meta_entry :: meta()) :: :ok

  @callback delete(step_key()) :: :ok

  # TODO
  # 确定设置blabla
  # @callback garbage_collect(opts()) :: :ok
end
