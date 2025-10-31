defmodule Caretaker.MQTT.TortoiseClient do
  @moduledoc """
  Tortoise311-backed MQTT client implementation.
  """
  @behaviour Caretaker.MQTT.Client

  @impl true
  def start_link(opts) do
    client_id = Keyword.fetch!(opts, :client_id)
    host = Keyword.get(opts, :host, "localhost") |> String.to_charlist()
    port = Keyword.get(opts, :port, 1883)

    Tortoise311.Connection.start_link(
      client_id: client_id,
      server: {Tortoise311.Transport.Tcp, host: host, port: port},
      handler: {Tortoise311.Handler.Logger, []}
    )
  end

  @impl true
  def publish(client_id, topic, payload) do
    bin = IO.iodata_to_binary(payload)
    case Tortoise311.publish(client_id, topic, bin, qos: 0) do
      :ok -> :ok
      {:error, _} = err -> err
    end
  end
end