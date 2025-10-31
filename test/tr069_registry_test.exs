defmodule Caretaker.TR069.RPC.RegistryTest do
  use ExUnit.Case, async: true

  alias Caretaker.TR069.RPC.Registry
  alias Caretaker.TR069.RPC.{Inform, InformResponse}

  test "module_for/1 returns module by RPC name" do
    assert {:ok, Inform} = Registry.module_for("Inform")
    assert {:ok, InformResponse} = Registry.module_for("InformResponse")
    assert :error = Registry.module_for("Unknown")
  end

  test "name_for/1 returns name by module" do
    assert {:ok, "Inform"} = Registry.name_for(Inform)
    assert {:ok, "InformResponse"} = Registry.name_for(InformResponse)
    assert :error = Registry.name_for(__MODULE__)
  end
end