defmodule OrchidStratum.BlobStorage do
  @moduledoc """
  ...
  """

  @type blob_key :: binary()

  @type raw_data :: term()

  @callback blob_exists?(content_hash :: blob_key()) :: boolean()

  @callback blob_get(content_hash :: blob_key()) :: {:ok, raw_data()} | :miss

  @callback blob_put(content_hash :: blob_key(), payload :: raw_data()) :: :ok
end
