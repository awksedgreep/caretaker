defmodule Caretaker.ACS.TelemetryTest do
  use ExUnit.Case, async: true

  @handler_id {Caretaker.ACS.Telemetry, :acs_request}

  setup do
    on_exit(fn ->
      :telemetry.detach(@handler_id)
    end)

    :ok
  end

  test "attach_default_handlers attaches handlers and prevents duplicate attachment" do
    assert :ok = Caretaker.ACS.Telemetry.attach_default_handlers()

    # Verify handler exists for both events
    for event <- [
          [:caretaker, :acs, :request, :start],
          [:caretaker, :acs, :request, :stop]
        ] do
      handlers = :telemetry.list_handlers(event)
      assert Enum.any?(handlers, fn h -> h.id == @handler_id end)
    end

    # Second attach should report already exists
    assert {:error, :already_exists} = Caretaker.ACS.Telemetry.attach_default_handlers()
  end
end
