defmodule Caretaker.TR069.RPC.InformTest do
  use ExUnit.Case, async: true

  alias Caretaker.TR069.RPC.Inform

  @device_id %{
    manufacturer: "Acme",
    oui: "A1B2C3",
    product_class: "Router",
    serial_number: "XYZ123"
  }

  test "new/1 builds struct with defaults" do
    inform = Inform.new(device_id: @device_id)

    assert %Inform{} = inform
    assert inform.device_id == @device_id
    assert inform.events == []
    assert inform.max_envelopes == 1
    assert inform.retry_count == 0
    assert inform.parameter_list == []
    assert match?(%DateTime{}, inform.current_time)
  end

  test "new/1 applies provided values" do
    now = ~U[2025-01-01 00:00:00Z]

    inform =
      Inform.new(
        device_id: @device_id,
        events: ["1 BOOT"],
        max_envelopes: 5,
        current_time: now,
        retry_count: 2,
        parameter_list: [foo: "bar"]
      )

    assert inform.events == ["1 BOOT"]
    assert inform.max_envelopes == 5
    assert inform.current_time == now
    assert inform.retry_count == 2
    assert inform.parameter_list == [foo: "bar"]
  end
end
