defmodule Caretaker.USP.Transport.MQTT.Handler do
  @moduledoc """
  mqttx client handler for USP transport.

  mqttx clients deliver events through `handle_mqtt_event/3` (running in the
  client's connection process). This handler forwards them to the owning
  transport process (`:parent` in the handler state) as plain messages:

    - `{:mqtt, topic, payload}` for an incoming PUBLISH
    - `{:mqtt_status, :connected}` / `{:mqtt_status, :disconnected}`

  so the Agent/Controller transports can drive their own lifecycle.
  """


  @type state :: %{parent: pid()}

  @doc "mqttx client event callback."
  @spec handle_mqtt_event(atom(), term(), state()) :: state()
  def handle_mqtt_event(:message, {topic, payload, _packet}, %{parent: parent} = state) do
    send(parent, {:mqtt, topic, payload})
    state
  end

  def handle_mqtt_event(:connected, _data, %{parent: parent} = state) do
    send(parent, {:mqtt_status, :connected})
    state
  end

  def handle_mqtt_event(:disconnected, _reason, %{parent: parent} = state) do
    send(parent, {:mqtt_status, :disconnected})
    state
  end

  def handle_mqtt_event(_event, _data, state), do: state
end
