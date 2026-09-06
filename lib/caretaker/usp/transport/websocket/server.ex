defmodule Caretaker.USP.Transport.WebSocket.Server do
  @moduledoc """
  WebSocket server for USP Controller.

  Provides a WebSocket endpoint for USP Agents to connect to. The server
  accepts connections, upgrades them to WebSocket, and routes messages
  to the USP Controller.

  ## Example

      # Start a controller with WebSocket transport
      {:ok, controller} = Caretaker.USP.Controller.start_link(
        endpoint_id: "self::acs.example.com"
      )

      {:ok, server} = Caretaker.USP.Transport.WebSocket.Server.start_link(
        controller: controller,
        port: 8080
      )

      # Agents can now connect to ws://localhost:8080/usp/controller/self::acs.example.com

  """

  use GenServer
  require Logger

  alias Caretaker.USP.{Controller, Proto, Record, Telemetry}
  alias Caretaker.USP.Transport.WebSocket.Paths

  @type state :: %{
          controller: pid(),
          controller_id: String.t(),
          port: non_neg_integer(),
          server_pid: pid() | nil,
          connections: map()
        }

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the WebSocket server for a Controller.

  ## Options

  - `:controller` - The Controller process (required)
  - `:port` - Port to listen on (default: 8080)
  - `:name` - Optional GenServer name

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Sends a Get request to an agent.
  """
  @spec get(GenServer.server(), String.t(), [String.t()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def get(server, agent_id, param_paths, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    GenServer.call(server, {:get, agent_id, param_paths, opts}, timeout)
  end

  @doc """
  Sends a Set request to an agent.
  """
  @spec set(GenServer.server(), String.t(), [{String.t(), keyword()}], keyword()) ::
          {:ok, map()} | {:error, term()}
  def set(server, agent_id, updates, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    GenServer.call(server, {:set, agent_id, updates, opts}, timeout)
  end

  @doc """
  Sends a raw USP message to an agent.
  """
  @spec send_message(GenServer.server(), String.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def send_message(server, agent_id, msg) do
    GenServer.call(server, {:send_message, agent_id, msg})
  end

  @doc """
  Returns list of connected agent IDs.
  """
  @spec connected_agents(GenServer.server()) :: [String.t()]
  def connected_agents(server) do
    GenServer.call(server, :connected_agents)
  end

  @doc """
  Stops the WebSocket server.
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(server) do
    GenServer.stop(server)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    controller = Keyword.fetch!(opts, :controller)
    port = Keyword.get(opts, :port, 8080)

    controller_id = Controller.endpoint_id(controller)

    state = %{
      controller: controller,
      controller_id: controller_id,
      port: port,
      server_pid: nil,
      connections: %{},
      pending_requests: %{}
    }

    # Start the HTTP server
    send(self(), :start_server)

    {:ok, state}
  end

  @impl true
  def handle_info(:start_server, state) do
    plug_opts = [
      controller: state.controller,
      controller_id: state.controller_id,
      parent: self()
    ]

    bandit_opts = [
      plug: {__MODULE__.Plug, plug_opts},
      port: state.port,
      scheme: :http
    ]

    case Bandit.start_link(bandit_opts) do
      {:ok, pid} ->
        Logger.info("USP WebSocket server started on port #{state.port}")
        Telemetry.emit_transport_connect(:websocket, state.controller_id)
        {:noreply, %{state | server_pid: pid}}

      {:error, reason} ->
        Logger.error("Failed to start WebSocket server: #{inspect(reason)}")
        {:stop, reason, state}
    end
  end

  @impl true
  def handle_info({:websocket, :connected, ws_pid}, state) do
    Logger.debug("WebSocket client connected: #{inspect(ws_pid)}")
    # Connection will be registered when first message arrives with agent ID
    {:noreply, state}
  end

  @impl true
  def handle_info({:websocket, :disconnected, ws_pid}, state) do
    # Find and remove the connection
    {agent_id, connections} =
      Enum.reduce(state.connections, {nil, %{}}, fn {aid, pid}, {found, acc} ->
        if pid == ws_pid do
          {aid, acc}
        else
          {found, Map.put(acc, aid, pid)}
        end
      end)

    if agent_id do
      Logger.info("Agent disconnected via WebSocket: #{agent_id}")
      Telemetry.emit_transport_disconnect(:websocket, agent_id)
    end

    {:noreply, %{state | connections: connections}}
  end

  @impl true
  def handle_info({:websocket, :message, %{from_id: agent_id} = record, ws_pid}, state) do

    # Track the latest socket for this agent, including a reconnection where a
    # new socket arrives before the old one's disconnect has been processed.
    state =
      if Map.get(state.connections, agent_id) != ws_pid do
        Logger.info("Agent connected via WebSocket: #{agent_id}")
        %{state | connections: Map.put(state.connections, agent_id, ws_pid)}
      else
        state
      end

    # Handle the message
    case Record.extract_message(record) do
      {:ok, msg} ->
        handle_incoming_message(msg, agent_id, state)

      {:error, reason} ->
        Logger.warning("Failed to extract message: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:request_timeout, msg_id}, state) do
    case Map.pop(state.pending_requests, msg_id) do
      {nil, _} ->
        {:noreply, state}

      {{from, _agent_id}, new_pending} ->
        GenServer.reply(from, {:error, :timeout})
        {:noreply, %{state | pending_requests: new_pending}}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("USP WebSocket server received: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def handle_call({:get, agent_id, param_paths, opts}, from, state) do
    msg = Proto.build_get(param_paths, opts)
    send_request_and_wait(agent_id, msg, from, state)
  end

  @impl true
  def handle_call({:set, agent_id, updates, opts}, from, state) do
    msg = Proto.build_set(updates, opts)
    send_request_and_wait(agent_id, msg, from, state)
  end

  @impl true
  def handle_call({:send_message, agent_id, msg}, from, state) do
    send_request_and_wait(agent_id, msg, from, state)
  end

  @impl true
  def handle_call(:connected_agents, _from, state) do
    {:reply, Map.keys(state.connections), state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.server_pid && Process.alive?(state.server_pid) do
      Supervisor.stop(state.server_pid)
    end

    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp handle_incoming_message(msg, agent_id, state) do
    msg_id = Proto.message_id(msg)

    # A pending entry is {from, expected_agent_id}. Only the agent a request was
    # sent to may answer it, so another connection cannot spoof from_id to
    # hijack a pending request.
    case Map.get(state.pending_requests, msg_id) do
      {from, ^agent_id} ->
        GenServer.reply(from, {:ok, msg})
        {:noreply, %{state | pending_requests: Map.delete(state.pending_requests, msg_id)}}

      _ ->
        Controller.handle_agent_message(state.controller, agent_id, msg)
        {:noreply, state}
    end
  end

  defp send_request_and_wait(agent_id, msg, from, state) do
    case Map.get(state.connections, agent_id) do
      nil ->
        {:reply, {:error, :agent_not_connected}, state}

      ws_pid ->
        msg_id = Proto.message_id(msg)

        record =
          Record.new(msg,
            to_id: agent_id,
            from_id: state.controller_id
          )

        send(ws_pid, {:send_record, record})

        # Register pending request, tagged with the target agent id
        new_pending = Map.put(state.pending_requests, msg_id, {from, agent_id})

        # Set timeout
        Process.send_after(self(), {:request_timeout, msg_id}, 30_000)

        {:noreply, %{state | pending_requests: new_pending}}
    end
  end
end

defmodule Caretaker.USP.Transport.WebSocket.Server.Plug do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias Caretaker.USP.Transport.WebSocket.{Handler, Paths}

  @impl Plug
  def init(opts), do: opts

  # Echo the v1.usp subprotocol when the client offers it, as TR-369 requires.
  defp negotiate_usp_subprotocol(conn) do
    offered =
      conn
      |> get_req_header("sec-websocket-protocol")
      |> Enum.flat_map(&String.split(&1, ",", trim: true))
      |> Enum.map(&String.trim/1)

    if Paths.subprotocol() in offered do
      put_resp_header(conn, "sec-websocket-protocol", Paths.subprotocol())
    else
      conn
    end
  end

  @impl Plug
  def call(conn, opts) do
    path = conn.request_path
    expected_controller_id = opts[:controller_id]

    case Paths.parse_endpoint_from_path(path) do
      {:ok, {:controller, ^expected_controller_id}} ->
        # Upgrade to WebSocket
        handler_opts = %{
          parent: opts[:parent],
          endpoint_id: expected_controller_id
        }

        conn
        |> negotiate_usp_subprotocol()
        |> WebSockAdapter.upgrade(Handler, handler_opts, [])
        |> halt()

      {:ok, _} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(404, "Not found")
        |> halt()

      {:error, _} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(400, "Invalid USP path")
        |> halt()
    end
  end
end
