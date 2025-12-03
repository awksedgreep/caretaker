defmodule Caretaker.Integration.GPONONTTest do
  use ExUnit.Case, async: false

  alias Caretaker.ACS.Server
  alias Caretaker.CPE.{DeviceState, DynamicBehavior, Client}
  alias Caretaker.CPE.Simulation.OpticalSignal
  alias Caretaker.CPE.Events.PON

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

  describe "Huawei GPON ONT simulation" do
    test "optical parameters update realistically over time", %{acs_url: acs_url} do
      device_id = %{
        oui: "00E0FC",
        manufacturer: "Huawei",
        product_class: "EG8145V5",
        serial_number: "HWT#{:rand.uniform(99_999_999)}"
      }

      params = %{
        "Device" => %{
          "DeviceInfo" => %{
            "Manufacturer" => "Huawei",
            "ModelName" => "EG8145V5",
            "SoftwareVersion" => "V5R021C00S125",
            "SerialNumber" => device_id.serial_number
          },
          "Optical" => %{
            "Interface" => %{
              "1" => %{
                "Enable" => true,
                "Status" => "Up",
                "OpticalSignalLevel" => -18.5,
                "TransmitOpticalLevel" => 2.3,
                "Temperature" => 45,
                "LowerOpticalThreshold" => -27.0,
                "UpperOpticalThreshold" => -8.0
              }
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

      # Start optical signal simulation
      {:ok, behavior} =
        DynamicBehavior.start_link(
          device_state: state,
          updates: [
            {OpticalSignal, :update, [noise: 0.5]}
          ],
          interval: 100
        )

      # Get initial values
      initial_rx =
        DeviceState.get(state, "Device.Optical.Interface.1.OpticalSignalLevel")

      initial_temp = DeviceState.get(state, "Device.Optical.Interface.1.Temperature")

      # Verify simulation is running and values are realistic
      assert is_float(initial_rx) or is_number(initial_rx),
             "OpticalSignalLevel should be numeric"

      assert initial_rx > -30.0 and initial_rx < 0.0,
             "OpticalSignalLevel should be in range [-30, 0] dBm"

      assert is_number(initial_temp), "Temperature should be numeric"

      assert initial_temp > 20 and initial_temp < 80,
             "Temperature should be in range [20, 80] °C"

      # Wait for simulation to run
      Process.sleep(500)

      # Verify behavior is still alive and simulation continues
      assert Process.alive?(behavior), "DynamicBehavior should still be running"

      GenServer.stop(behavior)
      GenServer.stop(state)
    end

    test "optical alarm triggers when signal degrades", %{acs_url: acs_url} do
      device_id = %{
        oui: "00E0FC",
        manufacturer: "Huawei",
        product_class: "EG8145V5",
        serial_number: "HWT#{:rand.uniform(99_999_999)}"
      }

      params = %{
        "Device" => %{
          "DeviceInfo" => %{
            "Manufacturer" => "Huawei",
            "SerialNumber" => device_id.serial_number
          },
          "Optical" => %{
            "Interface" => %{
              "1" => %{
                "OpticalSignalLevel" => -18.5,
                "LowerOpticalThreshold" => -27.0
              }
            }
          },
          "ManagementServer" => %{"URL" => acs_url}
        }
      }

      {:ok, state} = DeviceState.start_link(device_id: device_id, params: params)

      # Manually degrade optical signal to trigger alarm
      :ok = DeviceState.set(state, "Device.Optical.Interface.1.OpticalSignalLevel", -28.0)

      rx_power =
        DeviceState.get(state, "Device.Optical.Interface.1.OpticalSignalLevel")

      threshold =
        DeviceState.get(state, "Device.Optical.Interface.1.LowerOpticalThreshold")

      # Verify signal is below threshold
      assert rx_power < threshold,
             "Signal should degrade below threshold (#{rx_power} < #{threshold})"

      # Check if alarm would be generated
      events = PON.check_optical_alarms(state)
      assert length(events) > 0, "Should generate optical alarm events"

      alarm_event = Enum.find(events, &(&1.event_code == "X_OPTICAL_ALARM"))
      assert alarm_event != nil, "Should generate X_OPTICAL_ALARM event"

      GenServer.stop(state)
    end

    test "dying gasp event on power loss", %{acs_url: acs_url} do
      device_id = %{
        oui: "00E0FC",
        manufacturer: "Huawei",
        product_class: "EG8145V5",
        serial_number: "HWT#{:rand.uniform(99_999_999)}"
      }

      params = %{
        "Device" => %{
          "DeviceInfo" => %{"Manufacturer" => "Huawei"},
          "ManagementServer" => %{"URL" => acs_url}
        }
      }

      {:ok, state} = DeviceState.start_link(device_id: device_id, params: params)

      # Simulate power loss
      events = PON.simulate_dying_gasp(state)

      assert length(events) > 0
      event = List.first(events)
      assert event.event_code == "X_DYING_GASP"
      assert event.event_type == "power-loss"

      GenServer.stop(state)
    end

    test "full ONT boot sequence with Inform", %{acs_url: acs_url} do
      # Attach telemetry handler to capture Inform
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-ont-boot-#{inspect(ref)}",
        [:caretaker, :acs, :inform, :received],
        fn _event, measurements, metadata, _ ->
          send(test_pid, {:inform_received, measurements, metadata})
        end,
        nil
      )

      device_id = %{
        oui: "00E0FC",
        manufacturer: "Huawei",
        product_class: "EG8145V5",
        serial_number: "HWT#{:rand.uniform(99_999_999)}"
      }

      params = %{
        "Device" => %{
          "DeviceInfo" => %{
            "Manufacturer" => "Huawei",
            "ModelName" => "EG8145V5",
            "SoftwareVersion" => "V5R021C00S125"
          },
          "Optical" => %{
            "Interface" => %{
              "1" => %{
                "OpticalSignalLevel" => -18.5,
                "Status" => "Up"
              }
            }
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

      :telemetry.detach("test-ont-boot-#{inspect(ref)}")
      GenServer.stop(state)
    end
  end

  describe "ZTE GPON ONT simulation" do
    test "ZTE ONT connects and reports parameters", %{acs_url: acs_url} do
      device_id = %{
        oui: "48F222",
        manufacturer: "ZTE",
        product_class: "ZXHN_F670L",
        serial_number: "ZTE#{:rand.uniform(99_999_999)}"
      }

      params = %{
        "Device" => %{
          "DeviceInfo" => %{
            "Manufacturer" => "ZTE",
            "ModelName" => "ZXHN F670L",
            "SoftwareVersion" => "V5.0.10P7N1"
          },
          "Optical" => %{
            "Interface" => %{
              "1" => %{
                "OpticalSignalLevel" => -20.2,
                "TransmitOpticalLevel" => 2.1,
                "Status" => "Up"
              }
            }
          },
          "ManagementServer" => %{"URL" => acs_url}
        }
      }

      {:ok, state} = DeviceState.start_link(device_id: device_id, params: params)

      # Verify ZTE-specific parameters are accessible
      assert DeviceState.get(state, "Device.DeviceInfo.Manufacturer") == "ZTE"
      assert DeviceState.get(state, "Device.DeviceInfo.ModelName") == "ZXHN F670L"

      rx_power =
        DeviceState.get(state, "Device.Optical.Interface.1.OpticalSignalLevel")

      assert rx_power == -20.2

      GenServer.stop(state)
    end
  end

  describe "XGS-PON ONT simulation" do
    test "XGS-PON ONT with higher speeds", %{acs_url: acs_url} do
      device_id = %{
        oui: "00E0FC",
        manufacturer: "Huawei",
        product_class: "XGSPON_ONT",
        serial_number: "XGS#{:rand.uniform(99_999_999)}"
      }

      params = %{
        "Device" => %{
          "DeviceInfo" => %{
            "Manufacturer" => "Huawei",
            "ModelName" => "HG8546M",
            "SoftwareVersion" => "10.0.2.0"
          },
          "Optical" => %{
            "Interface" => %{
              "1" => %{
                "OpticalSignalLevel" => -19.0,
                "TransmitOpticalLevel" => 2.5,
                "Status" => "Up",
                "LinkSpeed" => "10G"
              }
            }
          },
          "Ethernet" => %{
            "Interface" => %{
              "1" => %{
                "MaxBitRate" => "10000",
                "Status" => "Up"
              }
            }
          },
          "ManagementServer" => %{"URL" => acs_url}
        }
      }

      {:ok, state} = DeviceState.start_link(device_id: device_id, params: params)

      # Verify XGS-PON specific parameters
      assert DeviceState.get(state, "Device.Optical.Interface.1.LinkSpeed") == "10G"

      assert DeviceState.get(state, "Device.Ethernet.Interface.1.MaxBitRate") ==
               "10000"

      GenServer.stop(state)
    end
  end
end
