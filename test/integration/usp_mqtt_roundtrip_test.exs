defmodule Caretaker.USP.MQTT.RoundtripTest do
  @moduledoc """
  Live USP-over-MQTT round-trip against an embedded mqttx broker: a Controller
  transport sends a Get to an Agent transport, the Agent answers, and the
  Controller receives the response — the end-to-end path nipper/Tortoise311
  interop previously prevented (#38).
  """
  use ExUnit.Case, async: false

  alias Caretaker.USP.Transport.MQTT

  setup do
    port = 1900 + rem(System.unique_integer([:positive]), 2000)
    # Dogfood the embedded broker that ships as the default for USP-over-MQTT.
    start_supervised!({Caretaker.USP.Transport.MQTT.Broker, port: port})
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
