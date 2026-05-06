defmodule Caretaker.CPE.ConnectionRequestServer do
  @moduledoc """
  HTTP server for handling ACS-initiated connection requests.

  This module provides a single HTTP endpoint that handles connection requests
  for all simulated CPE devices in a fleet. Each device has a unique URL path
  based on its serial number.

  ## How It Works

  1. Each device reports its `ConnectionRequestURL` in every Inform:
     `http://host:7547/cr/FLEET0-000001`

  2. When the ACS wants to trigger a device, it sends:
     `GET http://host:7547/cr/FLEET0-000001`

  3. This server receives the request, authenticates it, and triggers
     a "6 CONNECTION REQUEST" event on the matching device.

  4. The device then initiates a new Inform session to the ACS.

  ## Usage

      # Start the connection request server for a fleet
      {:ok, server} = ConnectionRequestServer.start_link(
        fleet: fleet_pid,
        port: 7547,
        auth: %{username: "acs", password: "secret"}
      )

      # Get the base URL for device connection request URLs
      base_url = ConnectionRequestServer.base_url(server)
      # => "http://192.168.1.50:7547"

      # Each device's ConnectionRequestURL will be:
      # "http://192.168.1.50:7547/cr/FLEET0-000001"

  ## Authentication

  Supports Basic authentication. The ACS must provide valid credentials
  in the Authorization header.
  """

  use GenServer
  require Logger

  @default_port 7547

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Start the connection request server.

  Options:
  - `fleet` - Fleet pid or name (required)
  - `port` - HTTP port to listen on (default: 7547)
  - `auth` - Authentication config `%{username: String.t(), password: String.t()}` (optional)
  - `host` - Hostname/IP for URL generation (default: "localhost")
  - `name` - Optional GenServer name
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    init_opts = Keyword.drop(opts, [:name])

    case name do
      nil -> GenServer.start_link(__MODULE__, init_opts)
      name -> GenServer.start_link(__MODULE__, init_opts, name: name)
    end
  end

  @doc """
  Stop the connection request server.
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(server) do
    GenServer.stop(server, :normal)
  end

  @doc """
  Get the base URL for connection request URLs.
  """
  @spec base_url(GenServer.server()) :: String.t()
  def base_url(server) do
    GenServer.call(server, :base_url)
  end

  @doc """
  Get the full connection request URL for a specific device.
  """
  @spec device_url(GenServer.server(), String.t()) :: String.t()
  def device_url(server, serial_number) do
    GenServer.call(server, {:device_url, serial_number})
  end

  @doc """
  Get the port the server is listening on.
  """
  @spec port(GenServer.server()) :: non_neg_integer()
  def port(server) do
    GenServer.call(server, :port)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    fleet = Keyword.fetch!(opts, :fleet)
    port = Keyword.get(opts, :port, @default_port)
    auth = Keyword.get(opts, :auth)
    host = Keyword.get(opts, :host, "localhost")

    # Build the Plug with fleet and auth config
    plug_opts = %{
      fleet: fleet,
      auth: auth
    }

    # Start Bandit HTTP server
    case Bandit.start_link(
           plug: {Caretaker.CPE.ConnectionRequestServer.Router, plug_opts},
           port: port,
           ip: {0, 0, 0, 0}
         ) do
      {:ok, bandit_pid} ->
        state = %{
          fleet: fleet,
          port: port,
          auth: auth,
          host: host,
          bandit_pid: bandit_pid
        }

        :telemetry.execute(
          [:caretaker, :connection_request, :server, :started],
          %{port: port},
          %{host: host}
        )

        Logger.info("Connection Request Server started on port #{port}")
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:base_url, _from, state) do
    url = "http://#{state.host}:#{state.port}"
    {:reply, url, state}
  end

  @impl true
  def handle_call({:device_url, serial_number}, _from, state) do
    url = "http://#{state.host}:#{state.port}/cr/#{serial_number}"
    {:reply, url, state}
  end

  @impl true
  def handle_call(:port, _from, state) do
    {:reply, state.port, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.bandit_pid && Process.alive?(state.bandit_pid) do
      Supervisor.stop(state.bandit_pid)
    end

    :telemetry.execute(
      [:caretaker, :connection_request, :server, :stopped],
      %{},
      %{port: state.port}
    )

    :ok
  end
end

defmodule Caretaker.CPE.ConnectionRequestServer.Router do
  @moduledoc false
  use Plug.Router

  require Logger

  plug(:match)
  plug(:dispatch)

  # GET /cr/:serial - Connection request for a specific device
  get "/cr/:serial" do
    opts = conn.private[:plug_opts] || %{}
    fleet = opts[:fleet]
    auth_config = opts[:auth]

    conn = Plug.Conn.fetch_query_params(conn)

    case authenticate(conn, auth_config) do
      :ok ->
        handle_connection_request(conn, fleet, conn.params["serial"])

      {:error, :unauthorized} ->
        :telemetry.execute(
          [:caretaker, :connection_request, :auth, :failed],
          %{},
          %{serial: conn.params["serial"]}
        )

        conn
        |> put_resp_header("www-authenticate", ~s(Basic realm="CPE"))
        |> send_resp(401, "Unauthorized")
    end
  end

  # Health check endpoint
  get "/health" do
    send_resp(conn, 200, "OK")
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp handle_connection_request(conn, fleet, serial) do
    :telemetry.execute(
      [:caretaker, :connection_request, :received],
      %{},
      %{serial: serial}
    )

    case Caretaker.CPE.Fleet.trigger_connection_request(fleet, serial) do
      :ok ->
        :telemetry.execute(
          [:caretaker, :connection_request, :triggered],
          %{},
          %{serial: serial}
        )

        Logger.debug("Connection request triggered for device #{serial}")
        send_resp(conn, 200, "")

      {:error, :not_found} ->
        :telemetry.execute(
          [:caretaker, :connection_request, :not_found],
          %{},
          %{serial: serial}
        )

        send_resp(conn, 404, "Device not found")

      {:error, :no_behavior} ->
        send_resp(conn, 503, "Device not ready")
    end
  end

  defp authenticate(_conn, nil), do: :ok

  defp authenticate(conn, %{username: expected_user, password: expected_pass}) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Basic " <> encoded] ->
        case Base.decode64(encoded) do
          {:ok, credentials} ->
            case String.split(credentials, ":", parts: 2) do
              [^expected_user, ^expected_pass] -> :ok
              _ -> {:error, :unauthorized}
            end

          :error ->
            {:error, :unauthorized}
        end

      _ ->
        {:error, :unauthorized}
    end
  end

  defp authenticate(_conn, _), do: :ok

  # Plug callback to store opts
  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    conn
    |> Plug.Conn.put_private(:plug_opts, opts)
    |> super(opts)
  end
end
