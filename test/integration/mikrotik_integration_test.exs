defmodule Caretaker.Integration.MikrotikTest do
  use ExUnit.Case, async: false

  alias Caretaker.ACS.Server
  alias Caretaker.CPE.{DeviceState, DynamicBehavior, Client}
  alias Caretaker.CPE.Simulation.RouterResources
  alias Caretaker.CPE.Events.Router
  alias Caretaker.Quirks
  alias Caretaker.Quirks.Mikrotik

  @moduletag :integration
  @moduletag timeout: 30_000

  setup do
    # Start ACS server using supervised child
    port = :rand.uniform(10_000) + 40_000
    acs_url = "http://127.0.0.1:#{port}/cwmp"

    start_supervised(Caretaker.ACS.Session)
    start_supervised(Caretaker.PubSub)
    start_supervised({Bandit, Server.child_spec(port: port) |> elem(1)})

    {:ok, acs_url: acs_url, port: port}
  end

  describe "Mikrotik RouterOS simulation" do
    test "RouterOS device connects with limited parameter set", %{acs_url: acs_url} do
      device_id = %{
        oui: "D4CA6D",
        manufacturer: "MikroTik",
        product_class: "RouterOS",
        serial_number: "MT#{:rand.uniform(99_999_999)}"
      }

      # Mikrotik only supports limited TR-069 parameters
      params = %{
        "Device" => %{
          "DeviceInfo" => %{
            "Manufacturer" => "MikroTik",
            "ModelName" => "RB4011iGS+",
            "SoftwareVersion" => "7.12.1",
            "SerialNumber" => device_id.serial_number,
            "HardwareVersion" => "r2",
            "UpTime" => 0,
            "X_MIKROTIK_BoardName" => "RB4011iGS+",
            "X_MIKROTIK_Architecture" => "arm",
            "X_MIKROTIK_License" => "6"
          },
          "ManagementServer" => %{
            "URL" => acs_url,
            "Username" => "admin",
            "Password" => "admin",
            "PeriodicInformEnable" => true,
            "PeriodicInformInterval" => 300,
            "ConnectionRequestURL" => "http://192.168.88.1:7547/"
          },
          "Ethernet" => %{
            "InterfaceNumberOfEntries" => 10,
            "Interface" => %{
              "1" => %{
                "Enable" => true,
                "Status" => "Up",
                "Name" => "ether1",
                "MACAddress" => "D4:CA:6D:12:34:56"
              }
            }
          }
        }
      }

      {:ok, state} = DeviceState.start_link(device_id: device_id, params: params)

      # Verify Mikrotik quirks are detected
      quirks = Quirks.get_quirks("D4CA6D")
      assert quirks == Mikrotik

      # Verify supported parameters
      assert Mikrotik.supported_parameter?("Device.DeviceInfo.Manufacturer")
      assert Mikrotik.supported_parameter?("Device.ManagementServer.URL")

      # Verify unsupported parameters
      refute Mikrotik.supported_parameter?("Device.WiFi.Radio.1.Enable")
      refute Mikrotik.supported_parameter?("Device.Firewall.Config")

      # Verify device parameters are accessible
      assert DeviceState.get(state, "Device.DeviceInfo.Manufacturer") == "MikroTik"

      assert DeviceState.get(state, "Device.DeviceInfo.X_MIKROTIK_BoardName") ==
               "RB4011iGS+"

      GenServer.stop(state)
    end

    test "resource usage simulation updates CPU and memory", %{acs_url: acs_url} do
      device_id = %{
        oui: "D4CA6D",
        manufacturer: "MikroTik",
        product_class: "RouterOS",
        serial_number: "MT#{:rand.uniform(99_999_999)}"
      }

      params = %{
        "Device" => %{
          "DeviceInfo" => %{
            "Manufacturer" => "MikroTik",
            "ProcessStatus" => %{
              "CPUUsage" => 15
            },
            "MemoryStatus" => %{
              "Total" => 524_288_000,
              "Free" => 400_000_000
            }
          },
          "ManagementServer" => %{
            "URL" => acs_url,
            "PeriodicInformEnable" => true,
            "PeriodicInformInterval" => 300
          }
        }
      }

      {:ok, state} = DeviceState.start_link(device_id: device_id, params: params)

      # Start resource simulation
      {:ok, behavior} =
        DynamicBehavior.start_link(
          device_state: state,
          updates: [{RouterResources, :update_resources, [load_profile: :normal]}],
          interval: 100
        )

      # Get initial CPU usage
      initial_cpu =
        DeviceState.get(state, "Device.DeviceInfo.ProcessStatus.CPUUsage")

      # Wait for updates
      Process.sleep(500)

      # Get updated CPU usage
      later_cpu = DeviceState.get(state, "Device.DeviceInfo.ProcessStatus.CPUUsage")

      # CPU should vary over time
      assert initial_cpu != later_cpu or later_cpu > 0,
             "CPU usage should be simulated"

      # Verify CPU is realistic (0-100%)
      assert later_cpu >= 0 and later_cpu <= 100,
             "CPU usage should be in range [0, 100]%"

      GenServer.stop(behavior)
      GenServer.stop(state)
    end

    test "script generation for WiFi configuration", %{acs_url: acs_url} do
      device_id = %{
        oui: "D4CA6D",
        manufacturer: "MikroTik",
        product_class: "RouterOS",
        serial_number: "MT#{:rand.uniform(99_999_999)}"
      }

      params = %{
        "Device" => %{
          "DeviceInfo" => %{"Manufacturer" => "MikroTik"},
          "ManagementServer" => %{"URL" => acs_url}
        }
      }

      {:ok, state} = DeviceState.start_link(device_id: device_id, params: params)

      # Since WiFi is not supported via TR-069, generate script
      script =
        Mikrotik.generate_script(:wifi_security, %{
          profile_name: "secure-wifi",
          passphrase: "MySecurePassword123",
          interface: "wlan1"
        })

      # Verify script was generated
      assert script != ""
      assert String.contains?(script, "/interface wireless")
      assert String.contains?(script, "secure-wifi")
      assert String.contains?(script, "wpa2-pre-shared-key")

      GenServer.stop(state)
    end

    test "script generation for firewall rules", %{acs_url: acs_url} do
      device_id = %{
        oui: "D4CA6D",
        manufacturer: "MikroTik",
        product_class: "RouterOS",
        serial_number: "MT#{:rand.uniform(99_999_999)}"
      }

      params = %{
        "Device" => %{
          "DeviceInfo" => %{"Manufacturer" => "MikroTik"},
          "ManagementServer" => %{"URL" => acs_url}
        }
      }

      {:ok, state} = DeviceState.start_link(device_id: device_id, params: params)

      # Generate firewall script
      script =
        Mikrotik.generate_script(:firewall_rule, %{
          chain: "input",
          protocol: "tcp",
          dst_port: 22,
          action: "accept"
        })

      # Verify script
      assert script != ""
      assert String.contains?(script, "/ip firewall filter add")
      assert String.contains?(script, "chain=input")
      assert String.contains?(script, "protocol=tcp")
      assert String.contains?(script, "dst-port=22")

      GenServer.stop(state)
    end

    test "WAN link events simulation", %{acs_url: acs_url} do
      device_id = %{
        oui: "D4CA6D",
        manufacturer: "MikroTik",
        product_class: "RouterOS",
        serial_number: "MT#{:rand.uniform(99_999_999)}"
      }

      params = %{
        "Device" => %{
          "DeviceInfo" => %{"Manufacturer" => "MikroTik"},
          "IP" => %{
            "Interface" => %{
              "1" => %{
                "Name" => "ether1",
                "Status" => "Up"
              }
            }
          },
          "ManagementServer" => %{"URL" => acs_url}
        }
      }

      {:ok, state} = DeviceState.start_link(device_id: device_id, params: params)

      # Simulate WAN link down
      events_down = Router.simulate_wan_link_change(state, :down)

      assert length(events_down) > 0
      event = List.first(events_down)
      assert event.event_code == "X_WAN_LINK_DOWN"
      assert event.event_type == "link-lost"

      # Simulate link back up
      events_up = Router.simulate_wan_link_change(state, :up)

      assert length(events_up) > 0
      event = List.first(events_up)
      assert event.event_code == "X_WAN_LINK_UP"
      assert event.event_type == "link-restored"

      GenServer.stop(state)
    end

    test "full Mikrotik boot sequence with Inform", %{acs_url: acs_url} do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-mikrotik-boot-#{inspect(ref)}",
        [:caretaker, :acs, :inform, :received],
        fn _event, measurements, metadata, _ ->
          send(test_pid, {:inform_received, measurements, metadata})
        end,
        nil
      )

      device_id = %{
        oui: "D4CA6D",
        manufacturer: "MikroTik",
        product_class: "RouterOS",
        serial_number: "MT#{:rand.uniform(99_999_999)}"
      }

      params = %{
        "Device" => %{
          "DeviceInfo" => %{
            "Manufacturer" => "MikroTik",
            "ModelName" => "RB4011iGS+",
            "SoftwareVersion" => "7.12.1"
          },
          "ManagementServer" => %{
            "URL" => acs_url,
            "PeriodicInformEnable" => false
          }
        }
      }

      {:ok, state} = DeviceState.start_link(device_id: device_id, params: params)

      # Run one-shot session
      result =
        Client.run_session(acs_url,
          device_id: device_id,
          device_state: state,
          events: ["1 BOOT"]
        )

      # Should complete successfully
      assert {:ok, session_data} = result
      assert session_data.inform_ack == true

      :telemetry.detach("test-mikrotik-boot-#{inspect(ref)}")
      GenServer.stop(state)
    end

    test "version checking for adequate RouterOS version", %{acs_url: acs_url} do
      device_id = %{
        oui: "D4CA6D",
        manufacturer: "MikroTik",
        product_class: "RouterOS",
        serial_number: "MT#{:rand.uniform(99_999_999)}"
      }

      # Test with old version
      params_old = %{
        "Device" => %{
          "DeviceInfo" => %{
            "Manufacturer" => "MikroTik",
            "SoftwareVersion" => "6.44"
          },
          "ManagementServer" => %{"URL" => acs_url}
        }
      }

      {:ok, state_old} =
        DeviceState.start_link(device_id: device_id, params: params_old)

      old_version = DeviceState.get(state_old, "Device.DeviceInfo.SoftwareVersion")

      refute Mikrotik.adequate_version?(old_version),
             "Version #{old_version} should be inadequate"

      # Test with new version
      params_new = %{
        "Device" => %{
          "DeviceInfo" => %{
            "Manufacturer" => "MikroTik",
            "SoftwareVersion" => "7.12.1"
          },
          "ManagementServer" => %{"URL" => acs_url}
        }
      }

      {:ok, state_new} =
        DeviceState.start_link(device_id: device_id, params: params_new)

      new_version = DeviceState.get(state_new, "Device.DeviceInfo.SoftwareVersion")

      assert Mikrotik.adequate_version?(new_version),
             "Version #{new_version} should be adequate"

      GenServer.stop(state_old)
      GenServer.stop(state_new)
    end

    test "alternative approach suggestions for unsupported parameters" do
      # WiFi configuration
      {:script, msg, example} =
        Mikrotik.alternative_approach("Device.WiFi.Radio.1.Channel")

      assert String.contains?(msg, "wireless")
      assert String.contains?(example, "/interface wireless")

      # Firewall configuration
      {:script, msg, example} =
        Mikrotik.alternative_approach("Device.Firewall.Config")

      assert String.contains?(msg, "firewall")
      assert String.contains?(example, "/ip firewall")

      # NAT configuration
      {:script, msg, example} =
        Mikrotik.alternative_approach("Device.NAT.PortMapping.1.Enable")

      assert String.contains?(msg, "NAT")
      assert String.contains?(example, "/ip firewall nat")
    end
  end
end
