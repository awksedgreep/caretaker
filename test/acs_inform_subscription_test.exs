defmodule Caretaker.ACS.InformSubscriptionTest do
  use ExUnit.Case, async: false

  alias Caretaker.ACS
  alias Caretaker.PubSub
  alias Caretaker.TR069.RPC.Inform

  setup do
    start_supervised!(PubSub)
    :ok
  end

  defp inform do
    %Inform{
      device_id: %{oui: "AABBCC", product_class: "Router", serial_number: "SN-1"},
      events: ["1 BOOT"],
      max_envelopes: 1,
      current_time: "",
      retry_count: 0,
      source_ip: "198.51.100.9"
    }
  end

  test "on_inform runs the callback for each Inform" do
    me = self()
    {:ok, listener} = ACS.on_inform(fn i -> send(me, {:got, i.source_ip}) end)

    PubSub.broadcast(PubSub.topic_tr069_inform(), inform())
    assert_receive {:got, "198.51.100.9"}, 500

    :ok = ACS.stop_inform_listener(listener)
  end

  test "subscribe_informs delivers {:caretaker_inform, inform} to the caller" do
    {:ok, _} = ACS.subscribe_informs()
    PubSub.broadcast(PubSub.topic_tr069_inform(), inform())
    assert_receive {:caretaker_inform, %Inform{source_ip: "198.51.100.9"}}, 500
  end

  test "a raising callback does not crash the listener" do
    me = self()
    {:ok, listener} = ACS.on_inform(fn _ -> raise "boom" end)
    PubSub.broadcast(PubSub.topic_tr069_inform(), inform())
    Process.sleep(50)
    assert Process.alive?(listener)
    # a second listener still works after the first raised
    {:ok, _} = ACS.on_inform(fn i -> send(me, {:ok2, i.source_ip}) end)
    PubSub.broadcast(PubSub.topic_tr069_inform(), inform())
    assert_receive {:ok2, "198.51.100.9"}, 500
  end
end
