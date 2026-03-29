defmodule OrchidStratum.BlobStorage.EtsAdapter do
  @moduledoc """
  In-process ETS-backed adapter for `OrchidStratum.BlobStorage`.

  This is the default Blob Store implementation. It stores all payloads in a
  single public ETS table, which makes it suitable for development, testing,
  and single-node deployments where cross-node replication is not required.

  > #### Lifecycle ⚠️ {: .warning}
  > The ETS table is **not** linked to any supervision tree. If the process
  > that called `init/0` exits, the table is garbage-collected by the BEAM.
  > For long-lived production use, create the table inside a supervised
  > `GenServer` or use a more durable adapter (e.g. Mnesia, a Rust NIF store).

  ### Usage

      blob_ref_current = OrchidStratum.BlobStorage.EtsAdapter.init()

      # meta_conf
      {OrchidStratum.BlobStorage.EtsAdapter, blob_ref_current}
  """

    @behaviour Orchid.Repo
    @behaviour Orchid.Repo.ContentAddressable

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
