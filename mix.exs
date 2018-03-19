defmodule Hexpm.MixProject do
  use Mix.Project

  def project() do
    [
      app: :hexpm,
      version: "0.0.1",
      elixir: "~> 1.6",
      elixirc_paths: elixirc_paths(Mix.env()),
      xref: xref(),
      compilers: [:phoenix] ++ Mix.compilers(),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def application() do
    [
      mod: {Hexpm.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "test/support/fake.ex", "test/support/factory.ex"]
  defp elixirc_paths(_), do: ["lib"]

  defp xref() do
    [exclude: [Hex.Registry, Hex.Resolver]]
  end

  defp deps() do
    [
      {:bamboo, "~> 0.7"},
      {:bcrypt_elixir, "~> 1.0"},
      {:corsica, "~> 1.0"},
      {:cowboy, "~> 1.0"},
      {:earmark, "~> 1.0"},
      {:ex_aws_s3, "~> 2.0"},
      {:ex_aws_ses, "~> 2.0"},
      {:ex_aws, "~> 2.0"},
      {:ex_machina, "~> 2.0", only: [:dev, :test]},
      {:hackney, "~> 1.7"},
      {:jiffy, "~> 0.14"},
      {:mox, "~> 0.3.1", only: :test},
      {:phoenix_ecto, "~> 3.1"},
      {:phoenix_html, "~> 2.3"},
      {:phoenix_live_reload, "~> 1.0", only: :dev},
      {:phoenix, "~> 1.3"},
      {:plug_attack, "~> 0.3"},
      {:plug, "~> 1.2"},
      {:porcelain, "~> 2.0"},
      {:postgrex, ">= 0.0.0"},
      {:rollbax, "~> 0.5", only: :prod},
      {:sbroker, "~> 1.0"},
      {:sweet_xml, "~> 0.5"},
      {:hex_erl, github: "hexpm/hex_erl", branch: "master"}
    ]
  end

  defp aliases() do
    [
      "ecto.reset": ["ecto.drop", "ecto.create", "ecto.migrate"],
      "ecto.setup": ["ecto.drop", "ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      test: ["ecto.migrate", "test"]
    ]
  end
end
