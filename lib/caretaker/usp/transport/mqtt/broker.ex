defmodule Caretaker.USP.Transport.MQTT.Broker do
  @moduledoc """
  Embedded MQTT broker for USP-over-MQTT.

  This is the **default** broker for USP-over-MQTT: run it in your supervision
  tree and the agent/controller transports connect to it on `localhost:1883`
  with no external infrastructure.

      children = [
        Caretaker.USP.Transport.MQTT.Broker,          # embedded broker (default)
        {Caretaker.USP.Controller, endpoint_id: "self::acs"},
        # ...agent/controller MQTT transports default to localhost:1883
      ]

  To use an **external** broker (EMQX, Mosquitto, HiveMQ, a shared bus, or for
  clustering/HA) instead, simply omit this from the tree and point the transports
  at it:

      {Caretaker.USP.Transport.MQTT.Controller, controller: c, broker_host: "mqtt.corp", broker_port: 1883}

  Built on `mqttx`'s server. It is a straightforward routing broker suitable for
  self-contained deployments and modest fleets; for carrier-scale connection
  counts or high availability, prefer an external broker.

  ## Options

    - `:port` - listen port (default 1883)
    - `:transport` - mqttx server transport (default `MqttX.Transport.ThousandIsland`)
    - `:name` - registry name (default `#{inspect(__MODULE__)}.Registry`)
  """

  use Supervisor

  @default_port 1883

  @doc false
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: supervisor_name(opts))
  end

  @impl true
  def init(opts) do
    registry = Keyword.get(opts, :name, Registry)
    port = Keyword.get(opts, :port, @default_port)
    transport = Keyword.get(opts, :transport, MqttX.Transport.ThousandIsland)

    children = [
      {__MODULE__.Registry, name: registry},
      %{
        id: __MODULE__.Server,
        start:
          {MqttX.Server, :start_link,
           [__MODULE__.Handler, [registry: registry], [port: port, transport: transport]]}
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp supervisor_name(opts) do
    case Keyword.get(opts, :name) do
      nil -> __MODULE__
      name -> Module.concat(name, "Supervisor")
    end
  end

  # ==========================================================================
  # Subscription registry: owns the topic Router and delivers PUBLISH packets
  # to matching subscriber connections, cleaning up when a connection dies.
  # ==========================================================================
  defmodule Registry do
    @moduledoc false
    use GenServer
    alias MqttX.Server.Router

    def start_link(opts) do
      name = Keyword.fetch!(opts, :name)
      GenServer.start_link(__MODULE__, %{}, name: name)
    end

    @doc "Register `conn` (a connection pid) as a subscriber to `filter`."
    def subscribe(server, filter, conn), do: GenServer.cast(server, {:subscribe, filter, conn})

    @doc "Deliver `payload` on `topic` to every matching subscriber."
    def publish(server, topic, payload), do: GenServer.cast(server, {:publish, topic, payload})

    @impl true
    def init(_), do: {:ok, %{router: Router.new(), filters: %{}}}

    @impl true
    def handle_cast({:subscribe, filter, conn}, state) do
      Process.monitor(conn)
      router = Router.subscribe(state.router, filter, conn, qos: 1)
      filters = Map.update(state.filters, conn, MapSet.new([filter]), &MapSet.put(&1, filter))
      {:noreply, %{state | router: router, filters: filters}}
    end

    @impl true
    def handle_cast({:publish, topic, payload}, state) do
      state.router
      |> Router.match(topic)
      |> Enum.each(fn {conn, _opts} -> send(conn, {:deliver, topic, payload}) end)

      {:noreply, state}
    end

    @impl true
    def handle_info({:DOWN, _ref, :process, conn, _reason}, state) do
      router =
        state.filters
        |> Map.get(conn, MapSet.new())
        |> Enum.reduce(state.router, fn filter, r -> Router.unsubscribe(r, filter, conn) end)

      {:noreply, %{state | router: router, filters: Map.delete(state.filters, conn)}}
    end

    @impl true
    def handle_info(_msg, state), do: {:noreply, state}
  end

  # ==========================================================================
  # mqttx server handler: accept connections, record subscriptions in the
  # Registry, hand each PUBLISH to the Registry for fan-out, and turn delivery
  # messages back into outgoing PUBLISH packets.
  # ==========================================================================
  defmodule Handler do
    @moduledoc false
    use MqttX.Server

    @impl true
    def init(opts), do: %{registry: Keyword.fetch!(opts, :registry)}

    @impl true
    def handle_connect(_client_id, _credentials, state), do: {:ok, state}

    @impl true
    def handle_subscribe(topics, %{registry: reg} = state) do
      conn = self()
      Enum.each(topics, fn t -> Registry.subscribe(reg, topic_filter(t), conn) end)
      {:ok, Enum.map(topics, fn _ -> 1 end), state}
    end

    @impl true
    def handle_publish(topic, payload, _opts, %{registry: reg} = state) do
      Registry.publish(reg, topic, payload)
      {:ok, state}
    end

    @impl true
    def handle_info({:deliver, topic, payload}, state), do: {:publish, topic, payload, state}
    def handle_info(_msg, state), do: {:ok, state}

    @impl true
    def handle_disconnect(_reason, _state), do: :ok

    defp topic_filter(%{topic: f}), do: topic_filter(f)
    defp topic_filter(f) when is_binary(f), do: f
    defp topic_filter(f) when is_list(f), do: MqttX.Topic.flatten(f)
  end
end
