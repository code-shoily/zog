defmodule Zog.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/code-shoily/zog"

  def project do
    [
      app: :zog,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix], flags: [:no_opaque]],

      # Hex
      description: "NIF Powered Graph Algorithms for Elixir",
      package: package(),

      # Docs
      name: "Zog",
      source_url: @source_url,
      docs: docs(),
      # Test Coverage
      test_coverage: [tool: ExCoveralls],
      # Suppress warnings for Erlang modules
      elixirc_options: [
        no_warn_undefined: [
          # Erlang stdlib modules (xmerl)
          :xmerl_scan,
          :xmerl_xpath
        ]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.40", runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.1", only: [:dev, :test]},
      {:benchee, "~> 1.3", only: :dev},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:jump_credo_checks, "~> 0.4", only: [:dev], runtime: false},
      {:zigler, "~> 0.16.0", runtime: false},
      {:yog_ex, "~> 0.98"},
      {:libgraph, "~> 0.16", optional: true}
    ]
  end

  # ====================================================
  # Private helpers
  # ====================================================

  defp package do
    [
      name: "zog",
      files:
        ~w(lib priv/zog/src priv/zog/build.zig priv/zog/build.zig.zon .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => @source_url <> "/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md"
      ],
      groups_for_modules: [
        "Core & Entrypoints": [
          Zog,
          Zog.SoA
        ],
        "Native Resource": [
          Zog.ResourceGraph
        ],
        Algorithms: [
          Zog.Centrality,
          Zog.Community,
          Zog.Community.Result,
          Zog.Community.Dendrogram,
          Zog.Connectivity,
          Zog.Flow,
          Zog.Generator,
          Zog.IO,
          Zog.MST,
          Zog.Metrics,
          Zog.Pathfinding,
          Zog.Property
        ]
      ]
    ]
  end
end
