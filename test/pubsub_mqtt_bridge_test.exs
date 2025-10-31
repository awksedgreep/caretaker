defmodule Caretaker.MQTT.BridgeTest do
  use ExUnit.Case, async: true

  alias Caretaker.MQTT.Bridge
  alias Caretaker.PubSub
  alias Caretaker.TR069.RPC.Inform

  defmodule FakeClient do
    @behaviour Caretaker.MQTT.Client
    def start_link(_opts), do: {:ok, self()}
    # In tests, pass client_id: {:fake_client, notify_pid}
    def publish({:fake_client, notify_pid}, topic, payload) do
      send(notify_pid, {:published, topic, IO.iodata_to_binary(payload)})
      :ok
    end
    def publish(_client, _topic, _payload), do: :ok
  end

  test "bridge publishes Inform from PubSub to MQTT" do
    _ = start_supervised(Caretaker.PubSub)
    {:ok, pid} = start_supervised({Bridge, client_id: {:fake_client, self()}, client_module: FakeClient, topic: "caretaker/inform"})

    inform = Inform.new(device_id: %{manufacturer: "Acme", oui: "A1B2C3", product_class: "Router", serial_number: "XYZ"})

    # Ensure bridge subscribed
    Process.sleep(50)

    # Publish via PubSub path
    PubSub.broadcast(PubSub.topic_tr069_inform(), inform)

    # And via direct message to be deterministic
    send(pid, {:pubsub, :tr069_inform, inform})

    assert_receive {:published, "caretaker/inform", payload}, 500
    assert payload =~ "\"oui\":\"A1B2C3\""
  end
end
