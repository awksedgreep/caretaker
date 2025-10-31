defmodule Caretaker.TR181.ModelValidateTest do
  use ExUnit.Case, async: true
  alias Caretaker.TR181.Model.Validate

  test "required, type, min/max, enum rules" do
    schema = %{
      "Device.DeviceInfo.SerialNumber" => [:required, {:type, "xsd:string"}],
      "Device.DeviceInfo.UpTime" => [{:type, "xsd:int"}, {:min, 0}],
      "Device.DeviceInfo.Mode" => [{:enum, ["A", "B", "C"]}]
    }

    good = %{
      "Device" => %{
        "DeviceInfo" => %{
          "SerialNumber" => "ABC",
          "UpTime" => 10,
          "Mode" => "B"
        }
      }
    }

    assert :ok == Validate.validate(good, schema)

    bad = %{
      "Device" => %{
        "DeviceInfo" => %{
          "UpTime" => -5,
          "Mode" => "Z"
        }
      }
    }

    assert {:error, errs} = Validate.validate(bad, schema)
    assert {"Device.DeviceInfo.SerialNumber", :required} in errs
    assert {"Device.DeviceInfo.UpTime", {:min, 0}} in errs
    assert {"Device.DeviceInfo.Mode", {:enum, ["A", "B", "C"]}} in errs
  end

  test "flatten treats structs as terminal values (e.g., DateTime)" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    schema = %{
      "Device.DeviceInfo.CurrentLocalTime" => [{:type, "xsd:dateTime"}]
    }

    nested = %{
      "Device" => %{
        "DeviceInfo" => %{
          "CurrentLocalTime" => now
        }
      }
    }

    assert :ok == Validate.validate(nested, schema)
  end
end
