defmodule Caretaker.TR181.ModelPathsTest do
  use ExUnit.Case, async: true
  alias Caretaker.TR181.Model

  test "put_path builds nested maps" do
    acc = %{}
    acc = Model.put_path(acc, "Device.DeviceInfo.SerialNumber", "ABC123")
    acc = Model.put_path(acc, "Device.DeviceInfo.HardwareVersion", "1.0")

    assert acc == %{
             "Device" => %{
               "DeviceInfo" => %{
                 "SerialNumber" => "ABC123",
                 "HardwareVersion" => "1.0"
               }
             }
           }
  end

  test "normalize_params casts and nests" do
    list = [
      %{name: "Device.DeviceInfo.UpTime", value: "3600", type: "xsd:int"},
      %{name: "Device.DeviceInfo.Upgradable", value: "true", type: "xsd:boolean"}
    ]

    assert {:ok, nested} = Model.normalize_params(list)

    assert nested == %{
             "Device" => %{
               "DeviceInfo" => %{
                 "UpTime" => 3600,
                 "Upgradable" => true
               }
             }
           }
  end

  test "to_parameter_values infers types and round-trips" do
    nested = %{
      "Device" => %{
        "DeviceInfo" => %{
          "SerialNumber" => "ABC123",
          "UpTime" => 3600,
          "Upgradable" => false
        }
      }
    }

    type_map = %{"Device.DeviceInfo.UpTime" => "xsd:int"}

    list = Model.to_parameter_values(nested, type_map)

    # Ensure required entries present with types
    assert Enum.any?(
             list,
             &(&1.name == "Device.DeviceInfo.SerialNumber" and &1.type == "xsd:string")
           )

    assert Enum.any?(
             list,
             &(&1.name == "Device.DeviceInfo.UpTime" and &1.type == "xsd:int" and
                 &1.value == "3600")
           )

    assert Enum.any?(
             list,
             &(&1.name == "Device.DeviceInfo.Upgradable" and &1.type == "xsd:boolean" and
                 &1.value == "false")
           )

    # Round-trip
    assert {:ok, nested2} = Model.from_parameter_values(list)
    assert nested2 == nested
  end
end
