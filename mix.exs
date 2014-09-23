defmodule HexWeb.Mixfile do
  use Mix.Project

  def project do
    [app: :hex_web,
     version: "0.0.1",
     elixir: "~> 1.0",
     config_path: "config/#{Mix.env}.exs",
     deps: deps]
  end

  def application do
    [applications: [:plug, :cowboy, :ecto, :postgrex, :jazz, :bcrypt, :mini_s3,
                    :logger, :porcelain],
     mod: {HexWeb, []},
     env: []]
  end

  defp deps do
    [{:plug,      github: "elixir-lang/plug"},
     {:ecto,      github: "elixir-lang/ecto"},
     {:jazz,      github: "meh/jazz"},
     {:bcrypt,    github: "opscode/erlang-bcrypt"},
     {:mini_s3,   github: "ericmj/mini_s3", branch: "hex-fixes"},
     {:porcelain, github: "alco/porcelain"},
     {:cowboy,    github: "ninenines/cowboy", override: true},
     {:cowlib,    github: "ninenines/cowlib", override: true},
     {:ranch,     github: "ninenines/ranch", override: true},
     {:poolboy,   github: "devinus/poolboy", override: true},
     {:postgrex,  github: "ericmj/postgrex", override: true},
     {:decimal,   github: "ericmj/decimal", override: true},
     {:earmark,   github: "pragdave/earmark", only: :dev},
     {:gen_smtp,  github: "Vagabond/gen_smtp"}
   ]
  end
end
