defmodule Caretaker.ACS.ParameterMappingTest do
  use ExUnit.Case, async: true

  alias Caretaker.ACS.ParameterMapping

  describe "to_device_path/2" do
    test "maps Mikrotik parameters" do
      device_type = {:mikrotik, :routeros}

      assert ParameterMapping.to_device_path("Device.Model", device_type) ==
               "Device.DeviceInfo.ModelName"

      assert ParameterMapping.to_device_path("WAN.IPAddress", device_type) ==
               "Device.IP.Interface.1.IPv4Address.1.IPAddress"

      assert ParameterMapping.to_device_path("WiFi.SSID", device_type) ==
               "Device.WiFi.SSID.1.SSID"
    end

    test "maps GPON ONT parameters" do
      device_type = {:gpon_ont, :huawei}

      assert ParameterMapping.to_device_path("PON.RxPower", device_type) ==
               "Device.Optical.Interface.1.OpticalSignalLevel"

      assert ParameterMapping.to_device_path("PON.TxPower", device_type) ==
               "Device.Optical.Interface.1.TransmitOpticalLevel"

      assert ParameterMapping.to_device_path("PON.Temperature", device_type) ==
               "Device.Optical.Interface.1.Temperature"
    end

    test "maps cable modem parameters" do
      device_type = {:cable_modem, :arris}

      assert ParameterMapping.to_device_path("DOCSIS.Status", device_type) ==
               "Device.Docsis.Status"

      assert ParameterMapping.to_device_path("DOCSIS.DS1.SNR", device_type) ==
               "Device.Docsis.Downstream.1.SNR"
    end

    test "returns canonical name unchanged if no mapping exists" do
      device_type = {:mikrotik, :routeros}

      assert ParameterMapping.to_device_path("Some.Unmapped.Parameter", device_type) ==
               "Some.Unmapped.Parameter"
    end
  end

  describe "from_device_path/2" do
    test "reverse maps Mikrotik parameters" do
      device_type = {:mikrotik, :routeros}

      assert ParameterMapping.from_device_path("Device.DeviceInfo.ModelName", device_type) ==
               "Device.Model"

      assert ParameterMapping.from_device_path(
               "Device.IP.Interface.1.IPv4Address.1.IPAddress",
               device_type
             ) ==
               "WAN.IPAddress"
    end

    test "reverse maps GPON ONT parameters" do
      device_type = {:gpon_ont, :huawei}

      assert ParameterMapping.from_device_path(
               "Device.Optical.Interface.1.OpticalSignalLevel",
               device_type
             ) ==
               "PON.RxPower"
    end

    test "returns device path unchanged if no reverse mapping exists" do
      device_type = {:mikrotik, :routeros}

      assert ParameterMapping.from_device_path("Some.Unknown.Path", device_type) ==
               "Some.Unknown.Path"
    end
  end

  describe "supported_parameters/1" do
    test "returns list of supported parameters for Mikrotik" do
      params = ParameterMapping.supported_parameters({:mikrotik, :routeros})

      assert "Device.Model" in params
      assert "WAN.IPAddress" in params
      assert "WiFi.SSID" in params
      assert length(params) > 10
    end

    test "returns list of supported parameters for GPON ONT" do
      params = ParameterMapping.supported_parameters({:gpon_ont, :huawei})

      assert "PON.RxPower" in params
      assert "PON.TxPower" in params
      assert "Device.Model" in params
    end

    test "returns empty list for unknown device type" do
      params = ParameterMapping.supported_parameters({:unknown, :device})

      assert params == []
    end
  end

  describe "supported?/2" do
    test "checks if parameter is supported" do
      device_type = {:mikrotik, :routeros}

      assert ParameterMapping.supported?("Device.Model", device_type)
      assert ParameterMapping.supported?("WAN.IPAddress", device_type)
      refute ParameterMapping.supported?("UnknownParameter", device_type)
    end
  end

  describe "to_device_paths/2" do
    test "batch converts canonical names to device paths" do
      device_type = {:mikrotik, :routeros}
      canonical_names = ["Device.Model", "WAN.IPAddress", "WiFi.SSID"]

      mappings = ParameterMapping.to_device_paths(canonical_names, device_type)

      assert {"Device.Model", "Device.DeviceInfo.ModelName"} in mappings

      assert {"WAN.IPAddress", "Device.IP.Interface.1.IPv4Address.1.IPAddress"} in mappings

      assert {"WiFi.SSID", "Device.WiFi.SSID.1.SSID"} in mappings
      assert length(mappings) == 3
    end
  end

  describe "from_device_paths/2" do
    test "batch converts device paths to canonical names" do
      device_type = {:gpon_ont, :huawei}

      device_paths = [
        "Device.Optical.Interface.1.OpticalSignalLevel",
        "Device.Optical.Interface.1.TransmitOpticalLevel"
      ]

      mappings = ParameterMapping.from_device_paths(device_paths, device_type)

      assert {"Device.Optical.Interface.1.OpticalSignalLevel", "PON.RxPower"} in mappings

      assert {"Device.Optical.Interface.1.TransmitOpticalLevel", "PON.TxPower"} in mappings

      assert length(mappings) == 2
    end
  end
end
