defmodule Caretaker.USP.MQTT.RoundtripTest do
  @moduledoc """
  Live USP-over-MQTT round-trip against an embedded mqttx broker: a Controller
  transport sends a Get to an Agent transport, the Agent answers, and the
  Controller receives the response — the end-to-end path nipper/Tortoise311
  interop previously prevented (#38).
  """
  use ExUnit.Case, async: false

  alias Caretaker.USP.Transport.MQTT

  # A minimal but real relay broker. mqttx supplies the protocol, transport and
  # a topic Router, but the fan-out is the handler's job: track subscriptions in
  # a shared Router (an Agent, since callbacks run in per-connection processes)
  # and, on publish, tell each matching subscriber connection to emit the
  # message (its handle_info returns {:publish, ...}).
  defmodule Broker do
    use MqttX.Server
    alias MqttX.Server.Router

    @impl true
    def init(opts), do: %{router: Keyword.fetch!(opts, :router)}

    @impl true
    def handle_connect(_client_id, _credentials, state), do: {:ok, state}

    @impl true
    def handle_subscribe(topics, %{router: agent} = state) do
      conn = self()

      granted =
        Enum.map(topics, fn t ->
          filter = topic_filter(t)
          Agent.update(agent, fn r -> Router.subscribe(r, filter, conn, qos: 1) end)
          1
        end)

      {:ok, granted, state}
    end

    @impl true
    def handle_publish(topic, payload, _opts, %{router: agent} = state) do
      agent
      |> Agent.get(fn r -> Router.match(r, topic) end)
      |> Enum.each(fn {conn, _opts} -> send(conn, {:deliver, topic, payload}) end)

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

  setup do
    port = 1900 + rem(System.unique_integer([:positive]), 2000)

    {:ok, router} = Agent.start_link(fn -> MqttX.Server.Router.new() end)
    {:ok, broker} = MqttX.Server.start_link(Broker, [router: router], port: port)

    on_exit(fn ->
      if Process.alive?(broker), do: Process.exit(broker, :normal)
      if Process.alive?(router), do: Agent.stop(router)
    end)

    %{port: port}
  end

  test "Controller transport gets a parameter from an Agent transport over MQTT", %{port: port} do
    agent_endpoint = "os::AABBCC-Router-MQTT1"
    controller_endpoint = "self::acs.test"

    {:ok, agent} =
      Caretaker.USP.Agent.start_link(
        endpoint_id: agent_endpoint,
        initial_params: %{"Device" => %{"DeviceInfo" => %{"Manufacturer" => "Acme"}}}
      )

    {:ok, controller} = Caretaker.USP.Controller.start_link(endpoint_id: controller_endpoint)

    {:ok, agent_tx} =
      MQTT.Agent.start_link(
        agent: agent,
        controller_id: controller_endpoint,
        broker_host: "localhost",
        broker_port: port
      )

    {:ok, controller_tx} =
      MQTT.Controller.start_link(
        controller: controller,
        broker_host: "localhost",
        broker_port: port
      )

    # let both transports connect and subscribe
    assert eventually(fn -> connected?(agent_tx) and connected?(controller_tx) end)

    # Register the agent so the controller knows about it
    :ok = MQTT.Agent.register(agent_tx)
    assert eventually(fn -> agent_endpoint in Caretaker.USP.Controller.list_agents(controller) end)

    # Controller reads a parameter from the agent, end to end over MQTT
    {:ok, response} =
      MQTT.Controller.get(controller_tx, agent_endpoint, ["Device.DeviceInfo."], timeout: 10_000)

    assert Caretaker.USP.Proto.message_type(response) == :GET_RESP
  end

  defp connected?(pid), do: :sys.get_state(pid).connected

  defp eventually(fun, retries \\ 100) do
    cond do
      fun.() -> true
      retries == 0 -> false
      true -> Process.sleep(25); eventually(fun, retries - 1)
    end
  end
end
