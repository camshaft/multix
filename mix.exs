defmodule Multix.Mixfile do
  use Mix.Project

  def project do
    [
      app: :multix,
      version: "0.1.0",
      elixir: "~> 1.3",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [applications: [:logger]]
  end

  defp deps do
    [
      {:mix_test_watch, ">= 0.0.0", only: :dev},
      {:nile, ">= 0.1.3"}
    ]
  end
end
