defmodule EventBus.MixProject do
  use Mix.Project

  def project do
    [
      app: :event_bus,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:oban, "~> 2.19"},
      {:oban_pro, "~> 1.5", repo: "oban"},
      {:nimble_ownership, "~> 1.0"}
    ]
  end
end
