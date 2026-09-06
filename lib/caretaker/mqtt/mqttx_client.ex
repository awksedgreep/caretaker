defmodule Caretaker.MQTT.MqttxClient do
  @moduledoc """
  mqttx-backed MQTT client implementation of `Caretaker.MQTT.Client`.

  `start_link/1` connects to a broker and returns `{:ok, client_pid}`; pass that
  pid as the bridge's `:client_id` so `publish/3` can address the connection.
  """
  @behaviour Caretaker.MQTT.Client

  @impl true
  def start_link(opts) do
    client_id = opts |> Keyword.fetch!(:client_id) |> to_string()
    host = Keyword.get(opts, :host, "localhost")
    port = Keyword.get(opts, :port, 1883)

    MqttX.Client.connect(
      client_id: client_id,
      host: host,
      port: port,
      clean_session: true,
      await_connect: Keyword.get(opts, :await_connect, false)
    )
  end

  @impl true
  def publish(client, topic, payload) when is_pid(client) do
    case MqttX.Client.publish(client, topic, IO.iodata_to_binary(payload), qos: 0) do
      :ok -> :ok
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
