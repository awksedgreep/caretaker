defmodule Caretaker.ACS.ServerNoSessionTest do
  use ExUnit.Case, async: false
  import Plug.Test
  # import Plug.Conn

  @handler {__MODULE__, :no_session}

  setup do
    _ = start_supervised(Caretaker.PubSub)

    :telemetry.attach(
      @handler,
      [:caretaker, :acs, :queue, :enqueue],
      &__MODULE__.handle_event/4,
      %{}
    )

    on_exit(fn -> :telemetry.detach(@handler) end)
    :ok
  end

  def handle_event(event, _meas, meta, _cfg) do
    send(self(), {:evt, event, meta})
  end

  test "maybe_enqueue_gpv returns :ok and does not enqueue when Session is not running" do
    xml = File.read!("test/fixtures/tr069/inform.xml")

    conn = conn(:post, "/cwmp", xml)
    conn = Caretaker.ACS.Server.call(conn, Caretaker.ACS.Server.init([]))

    assert conn.status == 200
    assert Plug.Conn.get_resp_header(conn, "content-type") == [Caretaker.CWMP.SOAP.content_type()]
    assert conn.resp_body =~ "<cwmp:InformResponse>"

    refute_receive {:evt, [:caretaker, :acs, :queue, :enqueue], _}, 200
  end
end
