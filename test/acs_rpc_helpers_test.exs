defmodule Caretaker.ACS.RPC.HelpersTest do
  use ExUnit.Case, async: true

  alias Caretaker.ACS.RPC.Helpers
  alias Caretaker.TR069.RPC.{GetParameterValues, SetParameterValues}

  describe "get_parameters/2" do
    test "generates GetParameterValues with mapped parameters for Mikrotik" do
      device_type = {:mikrotik, :routeros}
      canonical_names = ["Device.Model", "WAN.IPAddress"]

      rpc = Helpers.get_parameters(canonical_names, device_type)

      assert %GetParameterValues{} = rpc
      assert "Device.DeviceInfo.ModelName" in rpc.names
      assert "Device.IP.Interface.1.IPv4Address.1.IPAddress" in rpc.names
    end

    test "generates GetParameterValues with mapped parameters for GPON ONT" do
      device_type = {:gpon_ont, :huawei}
      canonical_names = ["PON.RxPower", "PON.TxPower"]

      rpc = Helpers.get_parameters(canonical_names, device_type)

      assert %GetParameterValues{} = rpc
      assert "Device.Optical.Interface.1.OpticalSignalLevel" in rpc.names

      assert "Device.Optical.Interface.1.TransmitOpticalLevel" in rpc.names
    end
  end

  describe "get_device_info/1" do
    test "generates GetParameterValues for device info" do
      device_type = {:mikrotik, :routeros}

      rpc = Helpers.get_device_info(device_type)

      assert %GetParameterValues{} = rpc
      assert "Device.DeviceInfo.Manufacturer" in rpc.names
      assert "Device.DeviceInfo.ModelName" in rpc.names
      assert "Device.DeviceInfo.SerialNumber" in rpc.names
      assert "Device.DeviceInfo.SoftwareVersion" in rpc.names
    end
  end

  describe "get_pon_status/1" do
    test "generates GetParameterValues for PON status" do
      device_type = {:gpon_ont, :huawei}

      rpc = Helpers.get_pon_status(device_type)

      assert %GetParameterValues{} = rpc
      assert "Device.Optical.Interface.1.Status" in rpc.names
      assert "Device.Optical.Interface.1.OpticalSignalLevel" in rpc.names

      assert "Device.Optical.Interface.1.TransmitOpticalLevel" in rpc.names
    end

    test "returns error for non-PON device" do
      device_type = {:mikrotik, :routeros}

      assert Helpers.get_pon_status(device_type) == {:error, :not_pon_device}
    end

    test "works for XGS-PON ONT" do
      device_type = {:xgspon_ont, :huawei}

      rpc = Helpers.get_pon_status(device_type)

      assert %GetParameterValues{} = rpc
    end
  end

  describe "get_docsis_status/1" do
    test "generates GetParameterValues for DOCSIS status" do
      device_type = {:cable_modem, :arris}

      rpc = Helpers.get_docsis_status(device_type)

      assert %GetParameterValues{} = rpc
      assert "Device.Docsis.Status" in rpc.names
      assert "Device.Docsis.BootState" in rpc.names
    end

    test "returns error for non-cable modem device" do
      device_type = {:mikrotik, :routeros}

      assert Helpers.get_docsis_status(device_type) == {:error, :not_cable_modem}
    end
  end

  describe "get_wan_info/1" do
    test "generates GetParameterValues for WAN info" do
      device_type = {:mikrotik, :routeros}

      rpc = Helpers.get_wan_info(device_type)

      assert %GetParameterValues{} = rpc
      assert "Device.IP.Interface.1.IPv4Address.1.IPAddress" in rpc.names

      assert "Device.IP.Interface.1.IPv4Address.1.SubnetMask" in rpc.names
    end
  end

  describe "get_wifi_config/1" do
    test "generates GetParameterValues for WiFi config" do
      device_type = {:mikrotik, :routeros}

      rpc = Helpers.get_wifi_config(device_type)

      assert %GetParameterValues{} = rpc
      assert "Device.WiFi.Radio.1.Enable" in rpc.names
      assert "Device.WiFi.SSID.1.SSID" in rpc.names
      assert "Device.WiFi.Radio.1.Channel" in rpc.names
    end
  end

  describe "set_parameters/3" do
    test "generates SetParameterValues with mapped parameters" do
      device_type = {:mikrotik, :routeros}
      params = [{"WiFi.SSID", "NewNetwork"}, {"WiFi.Channel", "6"}]

      rpc = Helpers.set_parameters(params, device_type, "TestKey")

      assert %SetParameterValues{} = rpc
      assert rpc.parameter_key == "TestKey"
      assert length(rpc.parameters) == 2

      assert Enum.any?(rpc.parameters, fn %{name: path, value: value} ->
               path == "Device.WiFi.SSID.1.SSID" and value == "NewNetwork"
             end)

      assert Enum.any?(rpc.parameters, fn %{name: path, value: value} ->
               path == "Device.WiFi.Radio.1.Channel" and value == "6"
             end)
    end

    test "infers correct XSD types" do
      device_type = {:mikrotik, :routeros}

      params = [
        {"WiFi.SSID", "MyNetwork"},
        {"WiFi.Channel", "6"},
        {"WiFi.Enabled", "true"}
      ]

      rpc = Helpers.set_parameters(params, device_type)

      # Find the mapped parameters
      ssid_param =
        Enum.find(rpc.parameters, fn %{name: path} ->
          String.contains?(path, "SSID")
        end)

      channel_param =
        Enum.find(rpc.parameters, fn %{name: path} ->
          String.contains?(path, "Channel")
        end)

      enabled_param =
        Enum.find(rpc.parameters, fn %{name: path} ->
          String.contains?(path, "Enable")
        end)

      assert %{type: type} = ssid_param
      assert type == "xsd:string"

      assert %{type: type} = channel_param
      assert type == "xsd:int"

      # Note: "true" as string will be detected as string, not boolean
      assert %{type: type} = enabled_param
      assert type in ["xsd:string", "xsd:boolean"]
    end
  end

  describe "configure_wifi/3" do
    test "generates SetParameterValues for WiFi with SSID only" do
      device_type = {:mikrotik, :routeros}

      rpc = Helpers.configure_wifi("MyNetwork", nil, device_type)

      assert %SetParameterValues{} = rpc
      assert rpc.parameter_key == "ConfigureWiFi"

      assert Enum.any?(rpc.parameters, fn %{value: value} ->
               value == "MyNetwork"
             end)

      assert Enum.any?(rpc.parameters, fn %{value: value} ->
               value == "true"
             end)
    end

    test "generates SetParameterValues for WiFi with SSID and password" do
      device_type = {:gpon_ont, :huawei}

      rpc = Helpers.configure_wifi("MyNetwork", "MyPassword", device_type)

      assert %SetParameterValues{} = rpc
      assert length(rpc.parameters) == 3

      assert Enum.any?(rpc.parameters, fn %{value: value} ->
               value == "MyPassword"
             end)
    end
  end

  describe "configure_wan/4" do
    test "generates SetParameterValues for WAN configuration" do
      device_type = {:mikrotik, :routeros}

      rpc = Helpers.configure_wan("192.168.1.100", "255.255.255.0", "192.168.1.1", device_type)

      assert %SetParameterValues{} = rpc
      assert rpc.parameter_key == "ConfigureWAN"
      assert length(rpc.parameters) == 3

      assert Enum.any?(rpc.parameters, fn %{value: value} ->
               value == "192.168.1.100"
             end)

      assert Enum.any?(rpc.parameters, fn %{value: value} ->
               value == "255.255.255.0"
             end)

      assert Enum.any?(rpc.parameters, fn %{value: value} ->
               value == "192.168.1.1"
             end)
    end
  end

  describe "parameter_supported?/2" do
    test "checks if parameter is supported" do
      device_type = {:mikrotik, :routeros}

      assert Helpers.parameter_supported?("WiFi.SSID", device_type)
      refute Helpers.parameter_supported?("DOCSIS.Status", device_type)
    end
  end

  describe "supported_parameters/1" do
    test "returns list of supported parameters" do
      device_type = {:mikrotik, :routeros}

      params = Helpers.supported_parameters(device_type)

      assert is_list(params)
      assert "WiFi.SSID" in params
      assert "WAN.IPAddress" in params
    end
  end
end
