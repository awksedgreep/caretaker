defmodule Caretaker.TR069.TypesTest do
  use ExUnit.Case, async: true

  alias Caretaker.TR069.Types

  test "valid_oui?/1 returns true for 6-character binaries" do
    assert Types.valid_oui?("A1B2C3")
    assert Types.valid_oui?("abcdef")
    assert Types.valid_oui?("123456")
  end

  test "valid_oui?/1 returns false for non-6-length or non-binary values" do
    refute Types.valid_oui?("")
    refute Types.valid_oui?("123")
    refute Types.valid_oui?("1234567")
    refute Types.valid_oui?(nil)
    refute Types.valid_oui?(123)
  end
end