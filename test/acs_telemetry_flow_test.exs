defmodule Caretaker.ACS.TelemetryFlowTest do
  use ExUnit.Case, async: false
  import Plug.Test

  @handler {__MODULE__, :test}

  setup do
    _ = start_supervised(Caretaker.PubSub)
    _ = start_supervised(Caretaker.ACS.Session)

    :telemetry.attach_many(
      @handler,
      [
        [:caretaker, :acs, :inform, :received],
        [:caretaker, :acs, :queue, :enqueue],
        [:caretaker, :acs, :queue, :dequeue]
      ],
      &__MODULE__.handle_event/4,
      %{}
    )

    on_exit(fn -> :telemetry.detach(@handler) end)
    :ok
  end

  def handle_event(event, _meas, meta, _cfg) do
    send(self(), {:evt, event, meta})
  end

  test "inform received and queue events fire" do
    xml = File.read!("test/fixtures/tr069/inform.xml")

    # Inform
    conn1 = conn(:post, "/cwmp", xml)
    _ = Caretaker.ACS.Server.call(conn1, Caretaker.ACS.Server.init([]))

    assert_receive {:evt, [:caretaker, :acs, :inform, :received], %{device_id: _}}, 200

    assert_receive {:evt, [:caretaker, :acs, :queue, :enqueue], %{rpc: :get_parameter_values}},
                   200

    # Empty POST should dequeue
    conn2 = conn(:post, "/cwmp", "")
    _ = Caretaker.ACS.Server.call(conn2, Caretaker.ACS.Server.init([]))

    assert_receive {:evt, [:caretaker, :acs, :queue, :dequeue], %{rpc: :next}}, 200
  end
end
