defmodule Caretaker.TR181.ModelTest do
  use ExUnit.Case, async: true

  alias Caretaker.TR181.Model

  test "type mapping and casting" do
    assert Model.type_for_xsd("xsd:string") == :string
    assert {:ok, 5} = Model.cast("5", "xsd:int")
    assert {:ok, 0} = Model.cast("0", "xsd:unsignedInt")
    assert {:error, :negative} = Model.cast("-1", "xsd:unsignedInt")
    assert {:ok, true} = Model.cast("true", "xsd:boolean")
    assert {:ok, false} = Model.cast("0", "xsd:boolean")
    assert {:ok, ~U[2025-01-01 00:00:00Z]} = Model.cast("2025-01-01T00:00:00Z", "xsd:dateTime")
  end

  test "normalize parameter list to nested map" do
    params = [
      %{name: "Device.DeviceInfo.Manufacturer", value: "Acme", type: "xsd:string"},
      %{name: "Device.DeviceInfo.SerialNumber", value: "1234", type: "xsd:string"},
      %{name: "Device.DeviceInfo.UpTime", value: "15", type: "xsd:int"}
    ]

    assert {:ok, nested} = Model.normalize_params(params)

    assert nested == %{
             "Device" => %{
               "DeviceInfo" => %{
                 "Manufacturer" => "Acme",
                 "SerialNumber" => "1234",
                 "UpTime" => 15
               }
             }
           }
  end

  test "flatten nested map to ParameterValueStruct list" do
    nested = %{
      "Device" => %{
        "DeviceInfo" => %{
          "Manufacturer" => "Acme",
          "UpTime" => 15
        }
      }
    }

    list = Model.to_parameter_values(nested)
    assert Enum.any?(list, &(&1.name == "Device.DeviceInfo.Manufacturer" and &1.value == "Acme" and &1.type == "xsd:string"))
    assert Enum.any?(list, &(&1.name == "Device.DeviceInfo.UpTime" and &1.value == "15" and &1.type == "xsd:int"))
  end
end