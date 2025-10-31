defmodule CaretakerTest do
  use ExUnit.Case

  test "telemetry prefix" do
    assert Caretaker.telemetry_prefix() == [:caretaker]
  end
end
