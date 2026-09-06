defmodule Caretaker.ACS.SessionTTLTest do
  use ExUnit.Case, async: false

  alias Caretaker.ACS.Session

  @dev {"OUI0", "PC", "SN-TTL"}
  @device_id %{oui: "OUI0", product_class: "PC", serial_number: "SN-TTL"}
  @ns "urn:dslforum-org:cwmp-1-0"

  setup do
    start_supervised!(Session)
    :ok
  end

  test "a command past its TTL is never delivered" do
    Session.upsert(@dev, @device_id, @ns)
    :ok = Session.queue_command(@dev, "cmd-a", ttl_ms: 0)

    # ttl_ms: 0 means the deadline is now; it must not be delivered
    assert :empty = Session.next_command(@dev)
  end

  test "a live command is delivered; a later expired one is skipped" do
    Session.upsert(@dev, @device_id, @ns)
    :ok = Session.queue_command(@dev, "live", ttl_ms: 60_000)
    :ok = Session.queue_command(@dev, "stale", ttl_ms: 0)
    :ok = Session.queue_command(@dev, "live2", ttl_ms: 60_000)

    assert {:ok, "live", _} = Session.next_command(@dev)
    # "stale" is dropped, "live2" delivered
    assert {:ok, "live2", _} = Session.next_command(@dev)
    assert :empty = Session.next_command(@dev)
  end

  test "ttl_ms: :infinity never expires" do
    Session.upsert(@dev, @device_id, @ns)
    :ok = Session.queue_command(@dev, "forever", ttl_ms: :infinity)
    assert {:ok, "forever", _} = Session.next_command(@dev)
  end

  test "cancel_by_tag removes matching queued commands across devices" do
    d2 = {"OUI0", "PC", "SN-TTL-2"}
    Session.upsert(@dev, @device_id, @ns)
    Session.upsert(d2, %{@device_id | serial_number: "SN-TTL-2"}, @ns)

    :ok = Session.queue_command(@dev, "keep", ttl_ms: 60_000, tag: "pass-1")
    :ok = Session.queue_command(@dev, "drop-a", ttl_ms: 60_000, tag: "pass-2")
    :ok = Session.queue_command(d2, "drop-b", ttl_ms: 60_000, tag: "pass-2")

    assert {:ok, 2} = Session.cancel_by_tag("pass-2")

    assert {:ok, "keep", _} = Session.next_command(@dev)
    assert :empty = Session.next_command(@dev)
    assert :empty = Session.next_command(d2)
  end

  test "the default TTL is finite (expiry is opt-out, not opt-in)" do
    # A tiny default makes the point without waiting: with default_command_ttl 0,
    # a command queued without an explicit ttl still expires.
    stop_supervised(Session)
    start_supervised!({Session, command_ttl: 0})

    Session.upsert(@dev, @device_id, @ns)
    :ok = Session.queue_command(@dev, "no-explicit-ttl")
    assert :empty = Session.next_command(@dev)
  end
end
