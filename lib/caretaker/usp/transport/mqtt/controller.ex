defmodule Caretaker.USP.Transport.MQTT.Controller do
  @moduledoc """
  MQTT transport for USP Controller.

  Connects a USP Controller to an MQTT broker and handles message routing
  between the Controller and Agents.

  ## Example

      # Start a controller with MQTT transport
      {:ok, controller} = Caretaker.USP.Controller.start_link(
        endpoint_id: "self::acs.example.com"
      )

      {:ok, transport} = Caretaker.USP.Transport.MQTT.Controller.start_link(
        controller: controller,
        broker_host: "localhost",
        broker_port: 1883
      )

      # Send a Get request to an agent
      {:ok, response} = Caretaker.USP.Transport.MQTT.Controller.get(
        transport,
        "os::ACME-Router-123",
        ["Device.DeviceInfo."]
      )

  """

  use GenServer
  require Logger

  alias Caretaker.USP.{Controller, Proto, Record, Telemetry}
  alias Caretaker.USP.Transport.MQTT.Topics

  @type state :: %{
          controller: pid(),
          controller_id: String.t(),
          client_id: String.t(),
          broker_host: String.t(),
          broker_port: non_neg_integer(),
          connected: boolean(),
          pending_requests: map()
        }

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the MQTT transport for a Controller.

  ## Options

  - `:controller` - The Controller process (required)
  - `:broker_host` - MQTT broker hostname (default: "localhost")
  - `:broker_port` - MQTT broker port (default: 1883)
  - `:name` - Optional GenServer name

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Sends a Get request to an agent and waits for response.
  """
  @spec get(GenServer.server(), String.t(), [String.t()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def get(transport, agent_id, param_paths, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    GenServer.call(transport, {:get, agent_id, param_paths, opts}, timeout)
  end

  @doc """
  Sends a Set request to an agent.
  """
  @spec set(GenServer.server(), String.t(), [{String.t(), keyword()}], keyword()) ::
          {:ok, map()} | {:error, term()}
  def set(transport, agent_id, updates, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    GenServer.call(transport, {:set, agent_id, updates, opts}, timeout)
  end

  @doc """
  Sends a raw USP message to an agent.
  """
  @spec send_message(GenServer.server(), String.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def send_message(transport, agent_id, msg) do
    GenServer.call(transport, {:send_message, agent_id, msg})
  end

  @doc """
  Disconnects from the MQTT broker.
  """
  @spec disconnect(GenServer.server()) :: :ok
  def disconnect(transport) do
    GenServer.call(transport, :disconnect)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    controller = Keyword.fetch!(opts, :controller)
    broker_host = Keyword.get(opts, :broker_host, "localhost")
    broker_port = Keyword.get(opts, :broker_port, 1883)

    controller_id = Controller.endpoint_id(controller)
    client_id = "usp-controller-#{:erlang.phash2(controller_id)}"

    state = %{
      controller: controller,
      controller_id: controller_id,
      client_id: client_id,
      broker_host: broker_host,
      broker_port: broker_port,
      connected: false,
      pending_requests: %{}
    }

    # Connect to MQTT broker
    send(self(), :connect)

    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case connect_to_broker(state) do
      {:ok, new_state} ->
        Logger.info("USP Controller MQTT connected: #{state.controller_id}")
        Telemetry.emit_transport_connect(:mqtt, state.controller_id)
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("USP Controller MQTT connection failed: #{inspect(reason)}")
        # Retry after delay
        Process.send_after(self(), :connect, 5000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:mqtt, topic, payload}, state) do
    # Received a message from MQTT
    Logger.debug("USP Controller received MQTT message on #{topic}")

    case Record.decode(payload) do
      {:ok, record} ->
        handle_incoming_record(record, topic, state)

      {:error, reason} ->
        Logger.warning("Failed to decode USP Record: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:tortoise, :connected}, state) do
    Logger.debug("USP Controller MQTT connected")
    {:noreply, %{state | connected: true}}
  end

  @impl true
  def handle_info({:tortoise, :disconnected}, state) do
    Logger.debug("USP Controller MQTT disconnected")
    Telemetry.emit_transport_disconnect(:mqtt, state.controller_id)
    # Attempt to reconnect
    Process.send_after(self(), :connect, 5000)
    {:noreply, %{state | connected: false}}
  end

  @impl true
  def handle_info({:request_timeout, msg_id}, state) do
    case Map.pop(state.pending_requests, msg_id) do
      {nil, _} ->
        {:noreply, state}

      {from, new_pending} ->
        GenServer.reply(from, {:error, :timeout})
        {:noreply, %{state | pending_requests: new_pending}}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("USP Controller MQTT received: #{inspect(msg)}")
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
  def handle_call(:disconnect, _from, state) do
    Tortoise311.Connection.disconnect(state.client_id)
    {:reply, :ok, %{state | connected: false}}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp connect_to_broker(state) do
    # Subscribe to controller request topic and all agent notifications
    controller_topic = Topics.controller_request(state.controller_id)
    notify_topic = Topics.controller_notify_subscription()

    tortoise_opts = [
      client_id: state.client_id,
      handler: {Caretaker.USP.Transport.MQTT.Handler, [parent: self()]},
      server: {Tortoise311.Transport.Tcp, host: state.broker_host, port: state.broker_port},
      subscriptions: [{controller_topic, 1}, {notify_topic, 1}]
    ]

    case Tortoise311.Connection.start_link(tortoise_opts) do
      {:ok, _pid} ->
        {:ok, %{state | connected: true}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_incoming_record(record, _topic, state) do
    agent_id = record.from_id

    case Record.extract_message(record) do
      {:ok, msg} ->
        msg_id = Proto.message_id(msg)

        # Check if this is a response to a pending request
        case Map.pop(state.pending_requests, msg_id) do
          {nil, _} ->
            # Not a response, forward to controller
            Controller.handle_agent_message(state.controller, agent_id, msg)
            {:noreply, state}

          {from, new_pending} ->
            # Response to pending request
            GenServer.reply(from, {:ok, msg})
            {:noreply, %{state | pending_requests: new_pending}}
        end

      {:error, reason} ->
        Logger.warning("Failed to extract message: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  defp send_request_and_wait(agent_id, msg, from, state) do
    msg_id = Proto.message_id(msg)

    record =
      Record.new(msg,
        to_id: agent_id,
        from_id: state.controller_id
      )

    topic = Topics.agent_request(agent_id)

    case publish(topic, record, state) do
      :ok ->
        # Register pending request
        new_pending = Map.put(state.pending_requests, msg_id, from)

        # Set timeout
        Process.send_after(self(), {:request_timeout, msg_id}, 30_000)

        {:noreply, %{state | pending_requests: new_pending}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp publish(topic, record, state) do
    case Record.encode(record) do
      {:ok, payload} ->
        case Tortoise311.publish(state.client_id, topic, payload, qos: 1) do
          :ok -> :ok
          {:ok, _ref} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
