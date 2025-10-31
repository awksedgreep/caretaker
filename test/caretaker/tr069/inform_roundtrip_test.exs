defmodule Caretaker.TR069.InformRoundtripTest do
  use ExUnit.Case

  @tag :skip
  test "Inform to InformResponse round-trip using Lather is pending" do
    assert Code.ensure_loaded?(Lather)
  end
end
