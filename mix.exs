defmodule Breaker.Mixfile do
  use Mix.Project

  def project do
    [
      app: :breaker,
      version: "0.1.0",
      elixir: "~> 1.4",
      test_coverage: [tool: Coverex.Task, coveralls: true],
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps(),
      name: "breaker",
      source_url: "https://github.com/awochna/breaker",
      docs: [
        extras: ["README.md"]
      ]
   ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [
      applications: [:httpotion],
      extra_applications: [:logger]
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:my_dep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:my_dep, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:benchfella, "~> 0.3.0", only: :dev},
      {:coverex, "~> 1.4.10", only: :test},
      {:earmark, "~> 1.1", only: :dev},
      {:ex_doc, "~> 0.14", only: :dev},
      {:httpotion, "~> 3.0.2"}
    ]
  end
end
