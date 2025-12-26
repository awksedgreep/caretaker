defmodule Caretaker.USP.Transport.MQTT.Handler do
  @moduledoc """
  Tortoise MQTT handler for USP transport.

  This module implements the Tortoise311.Handler behaviour and forwards
  MQTT events to the parent process (Agent or Controller transport).
  """

  use Tortoise311.Handler
  require Logger

  defstruct [:parent]

  @impl true
  def init(opts) do
    parent = Keyword.fetch!(opts, :parent)
    {:ok, %__MODULE__{parent: parent}}
  end

  @impl true
  def connection(status, state) do
    case status do
      :up ->
        send(state.parent, {:tortoise, :connected})

      :down ->
        send(state.parent, {:tortoise, :disconnected})

      :terminating ->
        send(state.parent, {:tortoise, :terminating})
    end

    {:ok, state}
  end

  @impl true
  def subscription(status, topic, state) do
    case status do
      :up ->
        Logger.debug("USP MQTT subscribed to: #{topic}")

      :down ->
        Logger.debug("USP MQTT unsubscribed from: #{topic}")

      {:warn, reason} ->
        Logger.warning("USP MQTT subscription warning on #{topic}: #{inspect(reason)}")

      {:error, reason} ->
        Logger.error("USP MQTT subscription error on #{topic}: #{inspect(reason)}")
    end

    {:ok, state}
  end

  @impl true
  def handle_message(topic, payload, state) do
    send(state.parent, {:mqtt, topic, payload})
    {:ok, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end
end
