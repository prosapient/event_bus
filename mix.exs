defmodule EventBus.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/prosapient/event_bus"

  def project do
    [
      app: :event_bus,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      docs: docs(),
      aliases: aliases(),
      preferred_cli_env: preferred_cli_env(),
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(env) when env in [:test, :test_pro], do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description do
    """
    Internal event bus for decoupling domain logic across contexts, backed by Oban.
    Works with both Oban (OSS) and Oban Pro.
    """
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{GitHub: @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}"
    ]
  end

  defp deps do
    [
      {:oban, "~> 2.19"},
      {:nimble_ownership, "~> 1.0"},
      {:postgrex, "~> 0.17", optional: true},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ] ++ pro_deps()
  end

  # oban_pro lives in Oban's private repo (requires a commercial license).
  # We only declare it in envs where it's actually used — that way `mix
  # deps.get` in :test (and in consumer projects without Pro) never tries
  # to resolve it against the private repo.
  defp pro_deps do
    if Mix.env() in [:dev, :test_pro] do
      [{:oban_pro, "~> 1.5", repo: "oban"}]
    else
      []
    end
  end

  defp aliases do
    [
      "test.oss": ["cmd MIX_ENV=test mix test"],
      "test.pro": ["cmd MIX_ENV=test_pro mix test"],
      "test.all": ["test.oss", "test.pro"]
    ]
  end

  defp preferred_cli_env do
    [
      "test.oss": :test,
      "test.pro": :test_pro,
      "test.all": :test
    ]
  end
end
