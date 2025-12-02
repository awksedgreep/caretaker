defmodule Caretaker.CPE.DeviceStateTest do
  use ExUnit.Case, async: true

  alias Caretaker.CPE.DeviceState

  setup do
    device_id = %{
      oui: "A1B2C3",
      product_class: "TestDevice",
      serial_number: "TEST001"
    }

    params = %{
      "Device" => %{
        "DeviceInfo" => %{
          "Manufacturer" => "TestVendor",
          "SerialNumber" => "TEST001",
          "SoftwareVersion" => "1.0.0",
          "UpTime" => 3600
        },
        "ManagementServer" => %{
          "URL" => "http://acs.test.com/",
          "PeriodicInformEnable" => true,
          "PeriodicInformInterval" => 300
        }
      }
    }

    {:ok, state} = DeviceState.start_link(device_id: device_id, params: params)
    {:ok, state: state, device_id: device_id}
  end

  test "get parameter by path", %{state: state} do
    assert DeviceState.get(state, "Device.DeviceInfo.Manufacturer") == "TestVendor"
    assert DeviceState.get(state, "Device.DeviceInfo.UpTime") == 3600
    assert DeviceState.get(state, "Device.ManagementServer.PeriodicInformEnable") == true
  end

  test "get returns nil for non-existent path", %{state: state} do
    assert DeviceState.get(state, "Device.DoesNotExist") == nil
    assert DeviceState.get(state, "Device.DeviceInfo.NonExistent") == nil
  end

  test "set parameter by path", %{state: state} do
    assert :ok = DeviceState.set(state, "Device.DeviceInfo.SoftwareVersion", "2.0.0")
    assert DeviceState.get(state, "Device.DeviceInfo.SoftwareVersion") == "2.0.0"
  end

  test "set creates intermediate keys", %{state: state} do
    assert :ok = DeviceState.set(state, "Device.NewSection.NewParam", "value")
    assert DeviceState.get(state, "Device.NewSection.NewParam") == "value"
  end

  test "get_tree returns subtree", %{state: state} do
    tree = DeviceState.get_tree(state, "Device.DeviceInfo.")
    assert tree["Manufacturer"] == "TestVendor"
    assert tree["SerialNumber"] == "TEST001"
    assert tree["SoftwareVersion"] == "1.0.0"
    assert Map.has_key?(tree, "UpTime")
  end

  test "get_tree with empty path returns full tree", %{state: state} do
    tree = DeviceState.get_tree(state, "")
    assert Map.has_key?(tree, "Device")
    assert Map.has_key?(tree["Device"], "DeviceInfo")
  end

  test "to_parameter_list flattens parameters", %{state: state} do
    list = DeviceState.to_parameter_list(state)

    assert length(list) > 0

    # Find specific parameters
    manufacturer = Enum.find(list, fn p -> p.name == "Device.DeviceInfo.Manufacturer" end)
    assert manufacturer.value == "TestVendor"
    assert manufacturer.type == "xsd:string"

    uptime = Enum.find(list, fn p -> p.name == "Device.DeviceInfo.UpTime" end)
    assert uptime.value == "3600"
    assert uptime.type == "xsd:int"

    enable = Enum.find(list, fn p -> p.name == "Device.ManagementServer.PeriodicInformEnable" end)
    assert enable.value == "true"
    assert enable.type == "xsd:boolean"
  end

  test "get_parameters with path prefix", %{state: state} do
    params = DeviceState.get_parameters(state, "Device.DeviceInfo.")

    assert length(params) == 4
    assert Enum.all?(params, fn p -> String.starts_with?(p.name, "Device.DeviceInfo.") end)

    manuf = Enum.find(params, fn p -> p.name == "Device.DeviceInfo.Manufacturer" end)
    assert manuf.value == "TestVendor"
  end

  test "update_parameters updates multiple params", %{state: state} do
    updates = [
      %{name: "Device.DeviceInfo.SoftwareVersion", value: "3.0.0"},
      %{name: "Device.DeviceInfo.UpTime", value: 7200},
      %{name: "Device.ManagementServer.PeriodicInformInterval", value: 600}
    ]

    assert :ok = DeviceState.update_parameters(state, updates)

    assert DeviceState.get(state, "Device.DeviceInfo.SoftwareVersion") == "3.0.0"
    assert DeviceState.get(state, "Device.DeviceInfo.UpTime") == 7200
    assert DeviceState.get(state, "Device.ManagementServer.PeriodicInformInterval") == 600
  end

  test "device_id returns device identification", %{state: state, device_id: device_id} do
    assert DeviceState.device_id(state) == device_id
  end

  test "load_profile from JSON file", %{state: state} do
    # Load fiber ONT profile
    profile_path = Path.join([:code.priv_dir(:caretaker), "profiles", "fiber_ont.json"])

    assert :ok = DeviceState.load_profile(state, profile_path)

    # Verify some parameters from the profile
    assert DeviceState.get(state, "Device.DeviceInfo.Manufacturer") == "FiberVendor"
    assert DeviceState.get(state, "Device.DeviceInfo.ModelName") == "GPON-ONU-1000"
    assert DeviceState.get(state, "Device.DeviceInfo.SoftwareVersion") == "2.1.5"
  end

  test "load_profile handles missing file", %{state: state} do
    assert {:error, {:file_read, _}} = DeviceState.load_profile(state, "nonexistent.json")
  end

  test "type inference in parameter list", %{state: state} do
    # Set various types
    DeviceState.set(state, "Device.Test.IntValue", 42)
    DeviceState.set(state, "Device.Test.BoolValue", false)
    DeviceState.set(state, "Device.Test.FloatValue", 3.14)
    DeviceState.set(state, "Device.Test.StringValue", "hello")

    list = DeviceState.to_parameter_list(state)

    int_param = Enum.find(list, fn p -> p.name == "Device.Test.IntValue" end)
    assert int_param.type == "xsd:int"

    bool_param = Enum.find(list, fn p -> p.name == "Device.Test.BoolValue" end)
    assert bool_param.type == "xsd:boolean"

    float_param = Enum.find(list, fn p -> p.name == "Device.Test.FloatValue" end)
    assert float_param.type == "xsd:double"

    string_param = Enum.find(list, fn p -> p.name == "Device.Test.StringValue" end)
    assert string_param.type == "xsd:string"
  end
end
