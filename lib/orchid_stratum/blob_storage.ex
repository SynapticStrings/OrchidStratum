defmodule OrchidStratum.BlobStorage do
  @moduledoc """
  ...
  """

  @type blob_key :: binary()

  @type raw_data :: term()

  @callback exists?(content_hash :: blob_key()) :: boolean()

  @callback get(content_hash :: blob_key()) :: {:ok, raw_data()} | :miss

  @callback put(content_hash :: blob_key(), payload :: raw_data()) :: :ok
end
