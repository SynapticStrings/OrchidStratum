defmodule OrchidStratum.MetaStorage.EtsAdapter do
  @moduledoc """
  ### Usage

      meta_ref_current = OrchidStratum.MetaStorage.EtsAdapter.init()

      # meta_conf
      {OrchidStratum.MetaStorage.EtsAdapter, meta_ref_current}
  """
  @behaviour OrchidStratum.MetaStorage

  def init do
    :ets.new(__MODULE__, [:set, :public])
  end

  @impl true
  def get(ets_ref, key) do
    case :ets.lookup(ets_ref, key) do
      [{^key, val}] -> {:ok, val}
      [] -> :miss
    end
  end

  @impl true
  def put(ets_ref, key, val) do
    :ets.insert(ets_ref, {key, val})

    :ok
  end

  @impl true
  def delete(ets_ref, key) do
    :ets.delete(ets_ref, key)

    :ok
  end
end
