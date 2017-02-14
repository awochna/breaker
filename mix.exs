defmodule Breaker.Mixfile do
  use Mix.Project

  def project do
    [
      app: :breaker,
      version: "0.1.1",
      elixir: "~> 1.3",
      test_coverage: [tool: Coverex.Task, coveralls: true],
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      name: "breaker",
      source_url: "https://github.com/awochna/breaker",
      docs: [
        main: "readme",
        extras: ["README.md"]
      ],
      package: package(),
      description: description(),
      deps: deps()
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
      {:credo, "~> 0.5", only: [:dev, :test]},
      {:earmark, "~> 1.1", only: [:dev, :docs]},
      {:ex_doc, "~> 0.14", only: [:dev, :docs]},
      {:httpotion, "~> 3.0.2"},
      {:inch_ex, only: :docs},
      {:poison, "~> 2.0", only: [:dev, :test, :docs]}
    ]
  end

  defp description do
    """
    A circuit breaker for HTTP requests to external services in Elixir.
    """
  end

  defp package do
    [
      name: :breaker,
      maintainers: ["Alex Wochna"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/awochna/breaker",
        "Docs" => "https://hexdocs.pm/breaker"
      }
    ]
  end
end
