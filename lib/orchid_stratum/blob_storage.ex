defmodule OrchidStratum.BlobStorage do
  @moduledoc """
  ...
  """

  @type store_ref :: term()

  @type blob_key :: binary()

  @type raw_data :: term()

  @callback exists?(store :: store_ref(), content_hash :: blob_key()) :: boolean()

  @callback get(store :: store_ref(), content_hash :: blob_key()) :: {:ok, raw_data()} | :miss

  @callback put(store :: store_ref(), content_hash :: blob_key(), payload :: raw_data()) :: :ok
end
