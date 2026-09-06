defmodule Caretaker.Quirks.MikrotikTest do
  use ExUnit.Case, async: true

  alias Caretaker.Quirks
  alias Caretaker.Quirks.Mikrotik

  describe "vendor identification" do
    test "identifies MikroTik by primary OUI" do
      assert Quirks.get_quirks("D4CA6D") == Mikrotik
    end

    test "identifies MikroTik by secondary OUI" do
      assert Quirks.get_quirks("2CC81B") == Mikrotik
      assert Quirks.get_quirks("E48D8C") == Mikrotik
    end

    test "OUI lookup is case-insensitive" do
      assert Quirks.get_quirks("d4ca6d") == Mikrotik
      assert Quirks.get_quirks("D4CA6D") == Mikrotik
      assert Quirks.get_quirks("d4CA6d") == Mikrotik
    end

    test "returns nil for unknown OUI" do
      assert Quirks.get_quirks("UNKNOWN") == nil
      assert Quirks.get_quirks("000000") == nil
    end

    test "vendor name is MikroTik" do
      assert Mikrotik.vendor_name() == "MikroTik"
    end
  end

  describe "parameter support detection" do
    test "supports basic device info parameters" do
      assert Mikrotik.supported_parameter?("Device.DeviceInfo.Manufacturer")
      assert Mikrotik.supported_parameter?("Device.DeviceInfo.ModelName")
      assert Mikrotik.supported_parameter?("Device.DeviceInfo.SoftwareVersion")
      assert Mikrotik.supported_parameter?("Device.DeviceInfo.SerialNumber")
    end

    test "supports management server parameters" do
      assert Mikrotik.supported_parameter?("Device.ManagementServer.URL")
      assert Mikrotik.supported_parameter?("Device.ManagementServer.Username")
      assert Mikrotik.supported_parameter?("Device.ManagementServer.Password")
      assert Mikrotik.supported_parameter?("Device.ManagementServer.PeriodicInformEnable")
      assert Mikrotik.supported_parameter?("Device.ManagementServer.PeriodicInformInterval")
    end

    test "supports MikroTik-specific extensions" do
      assert Mikrotik.supported_parameter?("Device.DeviceInfo.X_MIKROTIK_BoardName")
      assert Mikrotik.supported_parameter?("Device.DeviceInfo.X_MIKROTIK_Architecture")
      assert Mikrotik.supported_parameter?("Device.DeviceInfo.X_MIKROTIK_License")
    end

    test "supports indexed interface parameters" do
      assert Mikrotik.supported_parameter?("Device.Ethernet.Interface.1.Enable")
      assert Mikrotik.supported_parameter?("Device.Ethernet.Interface.5.Status")
      assert Mikrotik.supported_parameter?("Device.Ethernet.Interface.10.MACAddress")
      assert Mikrotik.supported_parameter?("Device.IP.Interface.2.IPv4Address.1.IPAddress")
    end

    test "does not support WiFi configuration" do
      refute Mikrotik.supported_parameter?("Device.WiFi.Radio.1.Enable")
      refute Mikrotik.supported_parameter?("Device.WiFi.Radio.1.Channel")
      refute Mikrotik.supported_parameter?("Device.WiFi.SSID.1.SSID")
      refute Mikrotik.supported_parameter?("Device.WiFi.AccessPoint.1.Security.X_COMPLEX")
    end

    test "does not support firewall configuration" do
      refute Mikrotik.supported_parameter?("Device.Firewall.Config")
      refute Mikrotik.supported_parameter?("Device.Firewall.Level")
    end

    test "does not support QoS configuration" do
      refute Mikrotik.supported_parameter?("Device.QoS.Classification.1.Enable")
      refute Mikrotik.supported_parameter?("Device.QoS.Queue.1.Enable")
    end
  end

  describe "parameter notes" do
    test "provides notes for PeriodicInformInterval" do
      notes = Mikrotik.parameter_notes("Device.ManagementServer.PeriodicInformInterval")

      assert length(notes) > 0
      assert Enum.any?(notes, &String.contains?(&1, "60 seconds"))
    end

    test "provides notes for ProvisioningCode" do
      notes = Mikrotik.parameter_notes("Device.DeviceInfo.ProvisioningCode")

      assert length(notes) > 0
      assert Enum.any?(notes, &String.contains?(&1, "Note"))
    end

    test "returns empty list for parameters without notes" do
      notes = Mikrotik.parameter_notes("Device.DeviceInfo.Manufacturer")
      assert notes == []
    end
  end

  describe "request/response transformation" do
    test "transform_request returns envelope unchanged" do
      envelope = %{body: "test", headers: %{}}
      assert Mikrotik.transform_request(envelope) == envelope
    end

    test "transform_response returns envelope unchanged" do
      envelope = %{body: "test", headers: %{}}
      assert Mikrotik.transform_response(envelope) == envelope
    end
  end

  describe "script generation" do
    test "generates firewall rule script" do
      script =
        Mikrotik.generate_script(:firewall_rule, %{
          chain: "input",
          protocol: "tcp",
          dst_port: 22,
          action: "accept"
        })

      assert String.contains?(script, "/ip firewall filter add")
      assert String.contains?(script, ~s(chain="input"))
      assert String.contains?(script, ~s(protocol="tcp"))
      assert String.contains?(script, ~s(dst-port="22"))
      assert String.contains?(script, ~s(action="accept"))
    end

    test "generates DHCP server script" do
      script =
        Mikrotik.generate_script(:dhcp_server, %{
          network: "192.168.88.0/24",
          gateway: "192.168.88.1"
        })

      assert String.contains?(script, "/ip dhcp-server network add")
      assert String.contains?(script, ~s(gateway="192.168.88.1"))
    end

    test "generates NAT masquerade script" do
      script =
        Mikrotik.generate_script(:nat_masquerade, %{
          out_interface: "ether1"
        })

      assert String.contains?(script, "/ip firewall nat add")
      assert String.contains?(script, "chain=srcnat")
      assert String.contains?(script, ~s(out-interface="ether1"))
      assert String.contains?(script, "action=masquerade")
    end

    test "generates static route script" do
      script =
        Mikrotik.generate_script(:static_route, %{
          dst_address: "10.0.0.0/8",
          gateway: "192.168.1.1"
        })

      assert String.contains?(script, "/ip route add")
      assert String.contains?(script, ~s(dst-address="10.0.0.0/8"))
      assert String.contains?(script, ~s(gateway="192.168.1.1"))
    end

    test "generates WiFi security script" do
      script =
        Mikrotik.generate_script(:wifi_security, %{
          profile_name: "secure-wifi",
          passphrase: "MySecurePassword123",
          interface: "wlan1"
        })

      assert String.contains?(script, "/interface wireless security-profiles add")
      assert String.contains?(script, ~s(name="secure-wifi"))
      assert String.contains?(script, ~s(wpa2-pre-shared-key="MySecurePassword123"))
      assert String.contains?(script, ~s(/interface wireless set "wlan1"))
    end

    test "generates system identity script" do
      script = Mikrotik.generate_script(:system_identity, %{name: "MyRouter"})

      assert String.contains?(script, "/system identity set")
      assert String.contains?(script, ~s(name="MyRouter"))
    end

    test "returns empty string for unknown script type" do
      script = Mikrotik.generate_script(:unknown_type, %{})
      assert script == ""
    end
  end

  describe "alternative approaches" do
    test "suggests script for WiFi configuration" do
      {:script, msg, example} = Mikrotik.alternative_approach("Device.WiFi.Radio.1.Channel")

      assert String.contains?(msg, "wireless")
      assert String.contains?(example, "/interface wireless")
    end

    test "suggests script for firewall configuration" do
      {:script, msg, example} = Mikrotik.alternative_approach("Device.Firewall.Config")

      assert String.contains?(msg, "firewall")
      assert String.contains?(example, "/ip firewall")
    end

    test "suggests script for NAT configuration" do
      {:script, msg, example} = Mikrotik.alternative_approach("Device.NAT.PortMapping.1.Enable")

      assert String.contains?(msg, "NAT")
      assert String.contains?(example, "/ip firewall nat")
    end

    test "indicates read-only for stats parameters" do
      {:read_only, msg} =
        Mikrotik.alternative_approach("Device.Ethernet.Interface.1.Stats.BytesSent")

      assert String.contains?(msg, "read-only")
    end

    test "returns unsupported for truly unsupported parameters" do
      result = Mikrotik.alternative_approach("Device.Some.Random.Parameter")
      assert result == :unsupported
    end
  end

  describe "reboot requirements" do
    test "management server changes do not require reboot" do
      refute Mikrotik.requires_reboot?("Device.ManagementServer.URL")
      refute Mikrotik.requires_reboot?("Device.ManagementServer.PeriodicInformInterval")
    end

    test "time configuration does not require reboot" do
      refute Mikrotik.requires_reboot?("Device.Time.NTPServer1")
    end

    test "most parameters do not require reboot" do
      refute Mikrotik.requires_reboot?("Device.DeviceInfo.ProvisioningCode")
      refute Mikrotik.requires_reboot?("Device.Ethernet.Interface.1.Enable")
    end
  end

  describe "version checking" do
    test "minimum version is 6.45" do
      assert Mikrotik.minimum_version() == "6.45"
    end

    test "recommended version is 7.12" do
      assert Mikrotik.recommended_version() == "7.12"
    end

    test "adequate_version? accepts valid versions" do
      assert Mikrotik.adequate_version?("6.45")
      assert Mikrotik.adequate_version?("6.46")
      assert Mikrotik.adequate_version?("7.0")
      assert Mikrotik.adequate_version?("7.12.1")
    end

    test "adequate_version? rejects old versions" do
      refute Mikrotik.adequate_version?("6.44")
      refute Mikrotik.adequate_version?("6.0")
      refute Mikrotik.adequate_version?("5.99")
    end

    test "adequate_version? handles invalid versions" do
      refute Mikrotik.adequate_version?("invalid")
      refute Mikrotik.adequate_version?("")
    end
  end

  describe "supported parameters list" do
    test "returns non-empty list of supported parameters" do
      params = Mikrotik.supported_parameters()

      assert is_list(params)
      assert length(params) > 0
    end

    test "all listed parameters are supported" do
      params = Mikrotik.supported_parameters()

      # Sample check - all listed params should be supported
      sample = Enum.take(params, 10)

      Enum.each(sample, fn param ->
        assert Mikrotik.supported_parameter?(param),
               "Parameter #{param} should be supported"
      end)
    end
  end

  describe "integration with Quirks module" do
    test "can be retrieved via Quirks.get_quirks" do
      assert Quirks.get_quirks("D4CA6D") == Mikrotik
    end

    test "parameter support check works through Quirks" do
      assert Quirks.supported_parameter?("D4CA6D", "Device.ManagementServer.URL") == true
      assert Quirks.supported_parameter?("D4CA6D", "Device.WiFi.Radio.1.Channel") == false
    end

    test "parameter notes work through Quirks" do
      notes = Quirks.parameter_notes("D4CA6D", "Device.ManagementServer.PeriodicInformInterval")
      assert length(notes) > 0
    end

    test "vendor info includes MikroTik details" do
      info = Quirks.vendor_info("D4CA6D")

      assert info.name == "MikroTik"
      assert info.quirks_module == Mikrotik
      assert info.supported_parameters_count > 0
    end

    test "registered OUIs includes MikroTik OUIs" do
      ouis = Quirks.registered_ouis()

      assert "D4CA6D" in ouis
      assert "2CC81B" in ouis
      assert "E48D8C" in ouis
    end
  end
end
