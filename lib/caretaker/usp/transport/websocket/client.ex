defmodule Caretaker.USP.Transport.WebSocket.Client do
  @moduledoc """
  WebSocket client for USP Agent.

  Connects a USP Agent to a Controller's WebSocket endpoint and handles
  message routing between them.

  ## Example

      # Start an agent with WebSocket transport
      {:ok, agent} = Caretaker.USP.Agent.start_link(
        endpoint_id: "os::ACME-Router-123"
      )

      {:ok, client} = Caretaker.USP.Transport.WebSocket.Client.start_link(
        agent: agent,
        controller_host: "localhost",
        controller_port: 8080,
        controller_id: "self::acs.example.com"
      )

  """

  use GenServer
  require Logger

  alias Caretaker.USP.{Agent, Proto, Record, Telemetry}
  alias Caretaker.USP.Transport.WebSocket.Paths

  @type state :: %{
          agent: pid(),
          agent_id: String.t(),
          controller_id: String.t(),
          controller_host: String.t(),
          controller_port: non_neg_integer(),
          secure: boolean(),
          conn: Mint.HTTP.t() | nil,
          websocket: Mint.WebSocket.t() | nil,
          ref: reference() | nil,
          connected: boolean(),
          buffer: binary()
        }

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the WebSocket client for an Agent.

  ## Options

  - `:agent` - The Agent process (required)
  - `:controller_host` - Controller hostname (required)
  - `:controller_port` - Controller port (default: 8080)
  - `:controller_id` - Controller's endpoint ID (required)
  - `:secure` - Use wss:// (default: false)
  - `:name` - Optional GenServer name

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Sends a Register message to the controller.
  """
  @spec register(GenServer.server()) :: :ok | {:error, term()}
  def register(client) do
    GenServer.call(client, :register)
  end

  @doc """
  Sends a Notify message to the controller.
  """
  @spec notify(GenServer.server(), map()) :: :ok | {:error, term()}
  def notify(client, notification) do
    GenServer.call(client, {:notify, notification})
  end

  @doc """
  Disconnects from the controller.
  """
  @spec disconnect(GenServer.server()) :: :ok
  def disconnect(client) do
    GenServer.call(client, :disconnect)
  end

  @doc """
  Returns the connection status.
  """
  @spec connected?(GenServer.server()) :: boolean()
  def connected?(client) do
    GenServer.call(client, :connected?)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    agent = Keyword.fetch!(opts, :agent)
    controller_host = Keyword.fetch!(opts, :controller_host)
    controller_id = Keyword.fetch!(opts, :controller_id)
    controller_port = Keyword.get(opts, :controller_port, 8080)
    secure = Keyword.get(opts, :secure, false)

    agent_id = Agent.endpoint_id(agent)

    state = %{
      agent: agent,
      agent_id: agent_id,
      controller_id: controller_id,
      controller_host: controller_host,
      controller_port: controller_port,
      secure: secure,
      conn: nil,
      websocket: nil,
      ref: nil,
      connected: false,
      buffer: <<>>
    }

    # Connect to controller
    send(self(), :connect)

    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case connect_to_controller(state) do
      {:ok, new_state} ->
        Logger.info("USP Agent WebSocket connected to #{state.controller_id}")
        Telemetry.emit_transport_connect(:websocket, state.agent_id)
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("USP Agent WebSocket connection failed: #{inspect(reason)}")
        # Retry after delay
        Process.send_after(self(), :connect, 5000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(message, %{conn: nil} = state) do
    Logger.debug("Received message without connection: #{inspect(message)}")
    {:noreply, state}
  end

  @impl true
  def handle_info(message, state) do
    case Mint.WebSocket.stream(state.conn, message) do
      {:ok, conn, responses} ->
        state = %{state | conn: conn}
        handle_responses(responses, state)

      {:error, conn, reason, _responses} ->
        Logger.error("WebSocket stream error: #{inspect(reason)}")
        Telemetry.emit_transport_disconnect(:websocket, state.agent_id)
        # Attempt to reconnect
        Process.send_after(self(), :connect, 5000)
        {:noreply, %{state | conn: conn, connected: false, websocket: nil}}

      :unknown ->
        Logger.debug("Unknown message: #{inspect(message)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_call(:register, _from, state) do
    if state.connected do
      register_msg = Agent.build_register_message(state.agent)
      result = send_to_controller(register_msg, state)
      {:reply, result, state}
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  @impl true
  def handle_call({:notify, notification}, _from, state) do
    if state.connected do
      notify_msg =
        case notification do
          %{type: :value_change, path: path, value: value, subscription_id: sub_id} ->
            Proto.build_notify_value_change(sub_id, path, value)

          %{
            type: :event,
            obj_path: path,
            event_name: name,
            params: params,
            subscription_id: sub_id
          } ->
            Proto.build_notify_event(sub_id, path, name, params)

          _ ->
            nil
        end

      result =
        if notify_msg do
          send_to_controller(notify_msg, state)
        else
          {:error, :invalid_notification}
        end

      {:reply, result, state}
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  @impl true
  def handle_call(:disconnect, _from, state) do
    state = close_connection(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:connected?, _from, state) do
    {:reply, state.connected, state}
  end

  @impl true
  def terminate(_reason, state) do
    close_connection(state)
    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp connect_to_controller(state) do
    http_scheme = if state.secure, do: :https, else: :http
    websocket_scheme = if state.secure, do: :wss, else: :ws
    path = Paths.controller_path(state.controller_id)

    with {:ok, conn} <-
           Mint.HTTP.connect(http_scheme, state.controller_host, state.controller_port),
         {:ok, conn, ref} <-
           Mint.WebSocket.upgrade(websocket_scheme, conn, path, [
             {"sec-websocket-protocol", Paths.subprotocol()}
           ]) do
      {:ok, %{state | conn: conn, ref: ref, connected: false}}
    end
  end

  defp handle_responses(responses, state) do
    Enum.reduce(responses, {:noreply, state}, fn response, {_, acc_state} ->
      handle_response(response, acc_state)
    end)
  end

  defp handle_response({:status, ref, status}, %{ref: ref} = state) do
    if status != 101 do
      Logger.warning("WebSocket upgrade failed with status #{status}")
    end

    {:noreply, state}
  end

  defp handle_response({:headers, ref, headers}, %{ref: ref} = state) do
    case complete_websocket_handshake(state.conn, ref, headers) do
      {:ok, conn, websocket} ->
        Logger.debug("WebSocket connection established")
        {:noreply, %{state | conn: conn, websocket: websocket, connected: true}}

      {:error, conn, reason} ->
        Logger.error("WebSocket handshake failed: #{inspect(reason)}")
        {:noreply, %{state | conn: conn}}
    end
  end

  defp handle_response({:data, ref, data}, %{ref: ref, websocket: websocket} = state)
       when not is_nil(websocket) do
    case Mint.WebSocket.decode(websocket, data) do
      {:ok, websocket, frames} ->
        state = %{state | websocket: websocket}
        handle_frames(frames, state)

      {:error, websocket, reason} ->
        Logger.error("WebSocket decode error: #{inspect(reason)}")
        {:noreply, %{state | websocket: websocket}}
    end
  end

  defp handle_response({:done, ref}, %{ref: ref} = state) do
    Logger.debug("WebSocket request complete")
    {:noreply, state}
  end

  defp handle_response({:error, ref, reason}, %{ref: ref} = state) do
    Logger.error("WebSocket error: #{inspect(reason)}")
    Telemetry.emit_transport_disconnect(:websocket, state.agent_id)
    Process.send_after(self(), :connect, 5000)
    {:noreply, %{state | connected: false, websocket: nil}}
  end

  defp handle_response(_response, state) do
    {:noreply, state}
  end

  defp handle_frames(frames, state) do
    Enum.reduce(frames, {:noreply, state}, fn frame, {_, acc_state} ->
      handle_frame(frame, acc_state)
    end)
  end

  defp handle_frame({:binary, data}, state) do
    case Record.decode(data) do
      {:ok, record} ->
        handle_incoming_record(record, state)

      {:error, reason} ->
        Logger.warning("Failed to decode USP Record: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  defp handle_frame({:text, _data}, state) do
    Logger.debug("Received unexpected text frame")
    {:noreply, state}
  end

  defp handle_frame({:ping, _data}, state) do
    # Respond with pong
    case send_frame({:pong, <<>>}, state) do
      {:ok, state} -> {:noreply, state}
      {:error, _} -> {:noreply, state}
    end
  end

  defp handle_frame({:pong, _data}, state) do
    {:noreply, state}
  end

  defp handle_frame({:close, _code, _reason}, state) do
    Logger.info("WebSocket closed by server")
    Telemetry.emit_transport_disconnect(:websocket, state.agent_id)
    Process.send_after(self(), :connect, 5000)
    {:noreply, %{state | connected: false, websocket: nil}}
  end

  defp handle_frame(_frame, state) do
    {:noreply, state}
  end

  defp handle_incoming_record(record, state) do
    case Record.extract_message(record) do
      {:ok, msg} ->
        case Agent.handle_message(state.agent, msg) do
          {:ok, response} when not is_nil(response) ->
            send_response(response, record, state)
            {:noreply, state}

          {:error, reason} ->
            Logger.warning("Agent failed to handle message: #{inspect(reason)}")
            {:noreply, state}
        end

      {:error, reason} ->
        Logger.warning("Failed to extract message: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  defp send_to_controller(msg, state) do
    record =
      Record.new(msg,
        to_id: state.controller_id,
        from_id: state.agent_id
      )

    case Record.encode(record) do
      {:ok, data} ->
        case send_frame({:binary, data}, state) do
          {:ok, _state} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_response(msg, request_record, state) do
    response_record = Record.response_for(request_record, msg)

    case Record.encode(response_record) do
      {:ok, data} ->
        send_frame({:binary, data}, state)

      {:error, reason} ->
        Logger.error("Failed to encode response: #{inspect(reason)}")
    end
  end

  defp send_frame(_frame, %{websocket: nil}) do
    {:error, :not_connected}
  end

  defp send_frame(frame, state) do
    case Mint.WebSocket.encode(state.websocket, frame) do
      {:ok, websocket, data} ->
        case Mint.WebSocket.stream_request_body(state.conn, state.ref, data) do
          {:ok, conn} ->
            {:ok, %{state | conn: conn, websocket: websocket}}

          {:error, _conn, reason} ->
            {:error, reason}
        end

      {:error, _websocket, reason} ->
        {:error, reason}
    end
  end

  @spec complete_websocket_handshake(Mint.HTTP.t(), reference(), Mint.Types.headers()) ::
          {:ok, Mint.HTTP.t(), Mint.WebSocket.t()}
          | {:error, Mint.HTTP.t(), Mint.WebSocket.error()}
  defp complete_websocket_handshake(conn, ref, headers) do
    apply(Mint.WebSocket, :new, [conn, ref, 101, headers])
  end

  defp close_connection(%{conn: nil} = state), do: state

  defp close_connection(state) do
    # Send close frame if connected
    if state.websocket do
      send_frame({:close, 1000, ""}, state)
    end

    # Close the HTTP connection
    if state.conn do
      Mint.HTTP.close(state.conn)
    end

    Telemetry.emit_transport_disconnect(:websocket, state.agent_id)

    %{state | conn: nil, websocket: nil, connected: false}
  end
end
