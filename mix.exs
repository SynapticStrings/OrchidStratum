defmodule OrchidStratum.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/SynapticStrings/OrchidStratum"

  def project do
    [
      app: :orchid_stratum,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:orchid, "~> 0.6"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    A deterministic, content-addressable caching layer for the Orchid workflow engine.
    Enables massive performance gains by bypassing redundant computations via payload
    dehydration/hydration and pluggable storage adapters.
    """
  end

  defp package do
    [
      name: "orchid_stratum",
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Orchid Core" => "https://hex.pm/packages/orchid"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}",
      source_url: @source_url,
      groups_for_modules: groups_for_modules()
    ]
  end

  def groups_for_modules do
    [
      "Meta Storage Behaviour": [
        OrchidStratum.MetaStorage,
        OrchidStratum.MetaStorage.GC,
        OrchidStratum.MetaStorage.MetaItem
      ],
      "Blob Storage Behaviour": [
        OrchidStratum.BlobStorage
      ],
      "Orchid Integration": [
        OrchidStratum.BypassHook,
        OrchidStratum.HashKeyBuilder
      ],
      "Default Adapters": [
        OrchidStratum.MetaStorage.EtsAdapter,
        OrchidStratum.BlobStorage.EtsAdapter
      ]
    ]
  end
end
