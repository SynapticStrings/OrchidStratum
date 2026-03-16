defmodule OrchidStratum.MixProject do
  use Mix.Project

  def project do
    [
      app: :orchid_stratum,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # I don't know is it essential to use OTP.
  # def application do
  #   [
  #     extra_applications: [:logger],
  #     mod: {OrchidStratum.Application, []}
  #   ]
  # end

  defp deps do
    [
      {:orchid, "~> 0.5"}
    ]
  end
end
