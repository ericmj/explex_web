use Mix.Config

config :hex_web,
  password_work_factor: 4,

  port:          "4000",
  url:           System.get_env("HEX_URL"),
  app_host:      System.get_env("APP_HOST"),

  s3_url:        System.get_env("HEX_S3_URL") || "https://s3.amazonaws.com",
  s3_bucket:     System.get_env("HEX_S3_BUCKET"),
  docs_bucket:   System.get_env("HEX_DOCS_BUCKET"),
  logs_bucket:   System.get_env("HEX_LOGS_BUCKET"),
  docs_url:      System.get_env("HEX_DOCS_URL"),
  cdn_url:       System.get_env("HEX_CDN_URL"),

  email_host:    System.get_env("HEX_EMAIL_HOST"),
  ses_endpoint:  System.get_env("HEX_SES_ENDPOINT") || "email-smtp.us-west-2.amazonaws.com",
  ses_port:      System.get_env("HEX_SES_PORT") || "587",
  ses_user:      System.get_env("HEX_SES_USERNAME"),
  ses_pass:      System.get_env("HEX_SES_PASSWORD"),

  secret:        System.get_env("HEX_SECRET")

config :hex_web, HexWeb.Repo,
  adapter: Ecto.Adapters.Postgres,
  extensions: [{HexWeb.JSON.Extension, library: Poison}]

config :ex_aws,
  access_key_id:     {:system, "HEX_S3_ACCESS_KEY"},
  secret_access_key: {:system, "HEX_S3_SECRET_KEY"}

config :ex_aws, :s3,
  scheme: "http://",
  host: "s3.amazonaws.com",
  region: "us-east-1"

config :logger,
  level: :debug

config :logger, :console,
  format: "$date $time [$level] $message\n"

import_config "#{Mix.env}.exs"
