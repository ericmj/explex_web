defmodule HexWeb.Mixfile do
  use Mix.Project

  def project do
    [app: :hex_web,
     version: "0.0.1",
     elixir: "~> 1.0",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     aliases: aliases,
     deps: deps]
  end

  def application do
    [applications: [:logger, :plug, :cowboy, :ecto, :postgrex, :poison, :bcrypt, :httpoison, :ex_aws,
                    :porcelain],
     mod: {HexWeb, []},
     env: []]
  end

  defp deps do
    [{:plug,      "~> 0.11"},
     {:cowboy,    "~> 1.0"},
     {:ecto,      github: "elixir-lang/ecto"},
     {:postgrex,  ">= 0.0.0"},
     {:poison,    "~> 1.2"},
     {:porcelain, "~> 2.0"},
     {:earmark,   "~> 0.1"},
     {:gen_smtp,  "~> 0.9.0"},
     {:bcrypt,    github: "opscode/erlang-bcrypt"},
     {:httpoison, "~> 0.7.0"},
     {:sweet_xml, "~> 0.2.1"},
     {:ex_aws,    "~> 0.4.0"}
   ]
  end

  defp aliases do
    [test: &test/1,
     "app.start": &app_start/1,
     "ecto.create": &ecto_create/1,
     "ecto.drop": &ecto_drop/1,
     "ecto.migrate": &ecto_migrate/1,
     "ecto.rollback": &ecto_rollback/1]
  end

  defp test(args) do
    env([env: :test, level: :warn], fn ->
      Mix.Task.run "ecto.drop", ["HexWeb.Repo"]
      Mix.Task.run "ecto.create", ["HexWeb.Repo"]
      Mix.Task.run "ecto.migrate", ["HexWeb.Repo"]
      HexWeb.Repo.stop
      Mix.Task.reenable "app.start"
      Mix.Task.run "app.start", args
      Mix.Task.run "test", args
    end)
  end

  defp app_start(args) do
    Mix.Task.run "app.start", args
    # Work around bug in 1.0 that stops logger even if --no-start is passed
    {:ok, _} = Application.ensure_all_started(:logger)
  end

  defp ecto_create(args) do
    Mix.Task.run "ecto.create", args ++ ["--no-start"]
  end

  defp ecto_drop(args) do
    Mix.Task.run "ecto.drop", args ++ ["--no-start"]
  end

  defp ecto_migrate(args) do
    env([level: :warn], fn ->
      # Workaround for task bug
      Mix.Task.run "app.start", ["--no-start"]
      Mix.Task.run "ecto.migrate", args
    end)
  end

  defp ecto_rollback(args) do
    env([level: :warn], fn ->
      # Workaround for task bug
      Mix.Task.run "app.start", ["--no-start"]
      Mix.Task.run "ecto.rollback", args
    end)
  end

  defp env(opts, fun) do
    old_level = Logger.level
    old_env = Mix.env
    Logger.configure(level: opts[:level])
    if opts[:env], do: Mix.env(opts[:env])

    try do
      fun.()
    after
      # If application start fails we need to restart logger because app.start
      # stops it
      {:ok, _} = Application.ensure_all_started(:logger)
      Logger.configure(level: old_level)
      Mix.env(old_env)
    end
  end
end
