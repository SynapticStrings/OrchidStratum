defmodule OrchidStratum.BlobStorage.EtsAdapter do
  @moduledoc """
  ### Usage

      blob_ref_current = OrchidStratum.BlobStorage.EtsAdapter.init()

      # meta_conf
      {OrchidStratum.BlobStorage.EtsAdapter, blob_ref_current}
  """

  @behaviour OrchidStratum.BlobStorage

    def init, do: :ets.new(__MODULE__, [:set, :public])

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
    def exists?(ets_ref, key) do
      :ets.member(ets_ref, key)
    end
end
