defmodule Caretaker.USP.Transport.MQTT.Agent do
  @moduledoc """
  MQTT transport for USP Agent.

  Connects a USP Agent to an MQTT broker and handles message routing
  between the Agent and Controllers.

  ## Example

      # Start an agent with MQTT transport
      {:ok, agent} = Caretaker.USP.Agent.start_link(
        endpoint_id: "os::ACME-Router-123"
      )

      {:ok, transport} = Caretaker.USP.Transport.MQTT.Agent.start_link(
        agent: agent,
        broker_host: "localhost",
        broker_port: 1883,
        controller_id: "self::acs.example.com"
      )

  """

  use GenServer
  require Logger

  alias Caretaker.USP.{Agent, Proto, Record, Telemetry}
  alias Caretaker.USP.Transport.MQTT.Topics

  @type state :: %{
          agent: pid(),
          agent_id: String.t(),
          controller_id: String.t(),
          client_id: String.t(),
          broker_host: String.t(),
          broker_port: non_neg_integer(),
          connected: boolean()
        }

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the MQTT transport for an Agent.

  ## Options

  - `:agent` - The Agent process (required)
  - `:broker_host` - MQTT broker hostname (default: "localhost")
  - `:broker_port` - MQTT broker port (default: 1883)
  - `:controller_id` - The controller's endpoint ID (required)
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
  def register(transport) do
    GenServer.call(transport, :register)
  end

  @doc """
  Sends a Notify message to the controller.
  """
  @spec notify(GenServer.server(), map()) :: :ok | {:error, term()}
  def notify(transport, notification) do
    GenServer.call(transport, {:notify, notification})
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
    agent = Keyword.fetch!(opts, :agent)
    controller_id = Keyword.fetch!(opts, :controller_id)
    broker_host = Keyword.get(opts, :broker_host, "localhost")
    broker_port = Keyword.get(opts, :broker_port, 1883)

    agent_id = Agent.endpoint_id(agent)
    client_id = "usp-agent-#{:erlang.phash2(agent_id)}"

    state = %{
      agent: agent,
      agent_id: agent_id,
      controller_id: controller_id,
      client_id: client_id,
      broker_host: broker_host,
      broker_port: broker_port,
      connected: false
    }

    # Connect to MQTT broker
    send(self(), :connect)

    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case connect_to_broker(state) do
      {:ok, new_state} ->
        Logger.info("USP Agent MQTT connected: #{state.agent_id}")
        Telemetry.emit_transport_connect(:mqtt, state.agent_id)
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("USP Agent MQTT connection failed: #{inspect(reason)}")
        # Retry after delay
        Process.send_after(self(), :connect, 5000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:mqtt, _client_id, topic, payload}, state) do
    # Received a message from MQTT
    Logger.debug("USP Agent received MQTT message on #{topic}")

    case Record.decode(payload) do
      {:ok, record} ->
        handle_incoming_record(record, topic, state)

      {:error, reason} ->
        Logger.warning("Failed to decode USP Record: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:tortoise, _client_id, :connected}, state) do
    Logger.debug("USP Agent MQTT connected")
    {:noreply, %{state | connected: true}}
  end

  @impl true
  def handle_info({:tortoise, _client_id, :disconnected}, state) do
    Logger.debug("USP Agent MQTT disconnected")
    Telemetry.emit_transport_disconnect(:mqtt, state.agent_id)
    # Attempt to reconnect
    Process.send_after(self(), :connect, 5000)
    {:noreply, %{state | connected: false}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("USP Agent MQTT received: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def handle_call(:register, _from, state) do
    # Build and send Register message
    register_msg = Agent.build_register_message(state.agent)
    result = send_to_controller(register_msg, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:notify, notification}, _from, state) do
    # Build and send Notify message
    notify_msg = case notification do
      %{type: :value_change, path: path, value: value, subscription_id: sub_id} ->
        Proto.build_notify_value_change(sub_id, path, value)

      %{type: :event, obj_path: path, event_name: name, params: params, subscription_id: sub_id} ->
        Proto.build_notify_event(sub_id, path, name, params)

      _ ->
        nil
    end

    result = if notify_msg do
      send_to_controller(notify_msg, state)
    else
      {:error, :invalid_notification}
    end

    {:reply, result, state}
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
    subscribe_topic = Topics.agent_request(state.agent_id)

    tortoise_opts = [
      client_id: state.client_id,
      handler: {Caretaker.USP.Transport.MQTT.Handler, [parent: self()]},
      server: {Tortoise311.Transport.Tcp, host: state.broker_host, port: state.broker_port},
      subscriptions: [{subscribe_topic, 1}]
    ]

    case Tortoise311.Connection.start_link(tortoise_opts) do
      {:ok, _pid} ->
        {:ok, %{state | connected: true}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_incoming_record(record, _topic, state) do
    # Extract message and process with agent
    case Record.extract_message(record) do
      {:ok, msg} ->
        case Agent.handle_message(state.agent, msg) do
          {:ok, response} when not is_nil(response) ->
            # Send response back
            send_response(response, record, state)

          {:ok, nil} ->
            :ok

          {:error, reason} ->
            Logger.warning("Agent failed to handle message: #{inspect(reason)}")
        end

      {:error, reason} ->
        Logger.warning("Failed to extract message from record: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  defp send_to_controller(msg, state) do
    record = Record.new(msg,
      to_id: state.controller_id,
      from_id: state.agent_id
    )

    topic = Topics.controller_request(state.controller_id)
    publish(topic, record, state)
  end

  defp send_response(msg, request_record, state) do
    response_record = Record.response_for(request_record, msg)
    topic = Topics.controller_request(request_record.from_id)
    publish(topic, response_record, state)
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
