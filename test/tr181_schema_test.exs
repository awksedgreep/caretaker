defmodule Caretaker.TR181.SchemaTest do
  use ExUnit.Case, async: true

  alias Caretaker.TR181.{Model, Schema}
  alias Caretaker.TR181.Model.Validate

  test "validate nested map against default schema" do
    nested = %{
      "Device" => %{
        "DeviceInfo" => %{
          "Manufacturer" => "Acme",
          "SerialNumber" => "1234",
          "UpTime" => 10
        }
      }
    }

    assert :ok = Validate.validate(nested, Schema.default())
  end

  test "validate errors for missing required and min bound" do
    nested = %{
      "Device" => %{
        "DeviceInfo" => %{
          "UpTime" => -1
        }
      }
    }

    assert {:error, errs} = Validate.validate(nested, Schema.default())
    assert {"Device.DeviceInfo.Manufacturer", :required} in errs
    assert {"Device.DeviceInfo.SerialNumber", :required} in errs
    assert {"Device.DeviceInfo.UpTime", {:min, 0}} in errs
  end

  test "from_parameter_values uses casting and builds nested map" do
    params = [
      %{name: "Device.DeviceInfo.UpTime", value: "20", type: "xsd:int"}
    ]

    assert {:ok, nested} = Model.from_parameter_values(params)
    assert nested["Device"]["DeviceInfo"]["UpTime"] == 20
  end
end
