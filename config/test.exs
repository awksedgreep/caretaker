import Config

# Embedded MQTT broker used only by the USP-over-MQTT transport tests.
# See #38 for the planned migration to the mqttx broker.
config :nipper,
  listeners: [
    default: [port: 1883, name: :mqtt]
  ]
