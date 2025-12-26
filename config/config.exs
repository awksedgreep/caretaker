import Config

config :logger, level: :info

# Nipper MQTT broker configuration for testing
config :nipper,
  listeners: [
    default: [port: 1883, name: :mqtt]
  ]
