import Config

config :hexpm,
  user_confirm: true,
  user_agent_req: true,
  secret: "796f75666f756e64746865686578",
  support_email: "support@hex.pm",
  store_impl: Hexpm.Store.Local,
  cdn_impl: Hexpm.CDN.Local,
  billing_impl: Hexpm.Billing.Local,
  pwned_impl: Hexpm.Pwned.Local

config :hexpm, ecto_repos: [Hexpm.RepoBase]

config :ex_aws,
  json_codec: Jason

config :bcrypt_elixir, log_rounds: 4

config :hexpm, HexpmWeb.Endpoint,
  url: [host: "localhost"],
  root: Path.dirname(__DIR__),
  render_errors: [view: HexpmWeb.ErrorView, accepts: ~w(html json elixir erlang)]

config :hexpm, Hexpm.RepoBase,
  priv: "priv/repo",
  migration_timestamps: [type: :utc_datetime_usec]

config :sasl, sasl_error_logger: false

config :hexpm, Hexpm.Emails.Mailer, adapter: Hexpm.Emails.Bamboo.SESAdapter

config :phoenix, :template_engines, md: HexpmWeb.MarkdownEngine

config :phoenix, stacktrace_depth: 20

config :phoenix, :generators,
  migration: true,
  binary_id: false

config :phoenix, :format_encoders,
  elixir: HexpmWeb.ElixirFormat,
  erlang: HexpmWeb.ErlangFormat,
  json: Jason

config :phoenix, :json_library, Jason

config :mime, :types, %{
  "application/vnd.hex+json" => ["json"],
  "application/vnd.hex+elixir" => ["elixir"],
  "application/vnd.hex+erlang" => ["erlang"]
}

config :rollbax, enabled: false

config :logger, :console, format: "[$level] $metadata$message\n"

import_config "#{Mix.env()}.exs"
