import Config

config :logger, level: :info

# Per-environment configuration (test env configures the embedded MQTT broker).
if File.exists?(Path.join(__DIR__, "#{config_env()}.exs")) do
  import_config "#{config_env()}.exs"
end
