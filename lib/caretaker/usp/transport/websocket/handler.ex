defmodule Caretaker.USP.Transport.WebSocket.Handler do
  @moduledoc """
  WebSocket handler for USP transport.

  This module implements the WebSock behaviour and handles WebSocket
  connections for USP message exchange. It can be used by both Controller
  and Agent WebSocket servers.

  ## Usage with Plug

      # In your Plug router
      get "/usp/controller/:controller_id" do
        conn
        |> WebSockAdapter.upgrade(
          Caretaker.USP.Transport.WebSocket.Handler,
          %{controller: controller_pid, endpoint_id: controller_id},
          []
        )
        |> halt()
      end

  """

  @behaviour WebSock

  require Logger

  alias Caretaker.USP.{Record, Telemetry}

  defstruct [
    :parent,
    :endpoint_id,
    :remote_endpoint_id,
    :connected_at
  ]

  @type t :: %__MODULE__{
          parent: pid() | nil,
          endpoint_id: String.t() | nil,
          remote_endpoint_id: String.t() | nil,
          connected_at: DateTime.t() | nil
        }

  @impl WebSock
  def init(opts) do
    parent = opts[:parent]
    endpoint_id = opts[:endpoint_id]

    state = %__MODULE__{
      parent: parent,
      endpoint_id: endpoint_id,
      remote_endpoint_id: nil,
      connected_at: DateTime.utc_now()
    }

    Logger.debug("USP WebSocket connection opened for #{endpoint_id}")

    if parent do
      send(parent, {:websocket, :connected, self()})
    end

    Telemetry.emit_transport_connect(:websocket, endpoint_id)

    {:ok, state}
  end

  @impl WebSock
  def handle_in({data, opcode: :binary}, state) do
    # USP Records are sent as binary frames
    case Record.decode(data) do
      {:ok, record} ->
        handle_incoming_record(record, state)

      {:error, reason} ->
        Logger.warning("Failed to decode USP Record: #{inspect(reason)}")
        {:ok, state}
    end
  end

  @impl WebSock
  def handle_in({data, opcode: :text}, state) do
    # USP should use binary frames, but handle text for debugging
    Logger.debug("Received text frame (expected binary): #{inspect(data)}")
    {:ok, state}
  end

  @impl WebSock
  def handle_in({_data, opcode: :ping}, state) do
    # WebSock handles pong automatically
    {:ok, state}
  end

  @impl WebSock
  def handle_in({_data, opcode: :pong}, state) do
    {:ok, state}
  end

  @impl WebSock
  def handle_info({:send_record, record}, state) do
    case Record.encode(record) do
      {:ok, data} ->
        {:push, {:binary, data}, state}

      {:error, reason} ->
        Logger.error("Failed to encode USP Record: #{inspect(reason)}")
        {:ok, state}
    end
  end

  @impl WebSock
  def handle_info({:close, reason}, state) do
    Logger.debug("Closing WebSocket: #{inspect(reason)}")
    {:stop, :normal, state}
  end

  @impl WebSock
  def handle_info(msg, state) do
    Logger.debug("USP WebSocket received: #{inspect(msg)}")
    {:ok, state}
  end

  @impl WebSock
  def terminate(reason, state) do
    Logger.debug("USP WebSocket terminated: #{inspect(reason)}")

    if state.parent do
      send(state.parent, {:websocket, :disconnected, self()})
    end

    Telemetry.emit_transport_disconnect(:websocket, state.endpoint_id)

    :ok
  end

  # Private functions

  defp handle_incoming_record(record, state) do
    # Update remote endpoint ID from first message
    state =
      if is_nil(state.remote_endpoint_id) do
        %{state | remote_endpoint_id: record.from_id}
      else
        state
      end

    # Forward to parent process
    if state.parent do
      send(state.parent, {:websocket, :message, record, self()})
    end

    {:ok, state}
  end
end
