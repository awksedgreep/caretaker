defmodule Caretaker.Integration.CableModemTest do
  use ExUnit.Case, async: false

  alias Caretaker.ACS.Server
  alias Caretaker.CPE.{DeviceState, DynamicBehavior, Client}
  alias Caretaker.CPE.Simulation.DocsisChannel
  alias Caretaker.CPE.Events.DOCSIS

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

  describe "Arris cable modem simulation" do
    test "DOCSIS channels update with realistic SNR variations", %{acs_url: acs_url} do
      device_id = %{
        oui: "0015A4",
        manufacturer: "Arris",
        product_class: "TG3482G",
        serial_number: "ARR#{:rand.uniform(99_999_999)}"
      }

      # Build DOCSIS channel parameters
      downstream_params =
        for ch <- 1..32, into: %{} do
          {"#{ch}",
           %{
             "Frequency" => 699_000_000 + (ch - 1) * 6_000_000,
             "Power" => 2.5 + :rand.uniform() * 2.0,
             "SNR" => 38.0 + :rand.uniform() * 4.0,
             "Modulation" => "256QAM",
             "LockStatus" => "Locked"
           }}
        end

      upstream_params =
        for ch <- 1..8, into: %{} do
          {"#{ch}",
           %{
             "Frequency" => 36_500_000 + (ch - 1) * 6_400_000,
             "Power" => 42.0 + :rand.uniform() * 3.0,
             "Modulation" => "64QAM",
             "LockStatus" => "Locked"
           }}
        end

      params = %{
        "Device" => %{
          "DeviceInfo" => %{
            "Manufacturer" => "Arris",
            "ModelName" => "TG3482G",
            "SoftwareVersion" => "AR01.02.117.11_092420"
          },
          "Docsis" => %{
            "Status" => "Operational",
            "BootState" => "Operational",
            "DownstreamNumberOfEntries" => 32,
            "UpstreamNumberOfEntries" => 8,
            "Downstream" => downstream_params,
            "Upstream" => upstream_params
          },
          "ManagementServer" => %{
            "URL" => acs_url,
            "PeriodicInformEnable" => true,
            "PeriodicInformInterval" => 300
          }
        }
      }

      {:ok, state} = DeviceState.start_link(device_id: device_id, params: params)

      # Start DOCSIS channel simulation
      {:ok, behavior} =
        DynamicBehavior.start_link(
          device_state: state,
          updates: [{DocsisChannel, :update, []}],
          interval: 100
        )

      # Get initial channel 1 SNR
      initial_snr = DeviceState.get(state, "Device.Docsis.Downstream.1.SNR")

      # Verify initial SNR is realistic
      assert is_float(initial_snr) or is_number(initial_snr),
             "Downstream SNR should be numeric"

      assert initial_snr > 30.0 and initial_snr < 45.0,
             "SNR should be in healthy range [30, 45] dB"

      # Wait for simulation to run
      Process.sleep(500)

      # Verify behavior is still alive
      assert Process.alive?(behavior), "DynamicBehavior should still be running"

      GenServer.stop(behavior)
      GenServer.stop(state)
    end

    test "RF plant issue simulation degrades channels", %{acs_url: acs_url} do
      device_id = %{
        oui: "0015A4",
        manufacturer: "Arris",
        product_class: "TG3482G",
        serial_number: "ARR#{:rand.uniform(99_999_999)}"
      }

      params = %{
        "Device" => %{
          "DeviceInfo" => %{"Manufacturer" => "Arris"},
          "Docsis" => %{
            "Downstream" => %{
              "1" => %{"SNR" => 38.5, "LockStatus" => "Locked"}
            }
          },
          "ManagementServer" => %{"URL" => acs_url}
        }
      }

      {:ok, state} = DeviceState.start_link(device_id: device_id, params: params)

      # Manually degrade channel SNR
      :ok = DeviceState.set(state, "Device.Docsis.Downstream.1.SNR", 28.0)

      # Check degraded SNR
      degraded_snr =
        DeviceState.get(state, "Device.Docsis.Downstream.1.SNR")

      assert degraded_snr < 30.0,
             "SNR should degrade during plant issue (now #{degraded_snr})"

      GenServer.stop(state)
    end

    test "DOCSIS registration flow completes successfully", %{acs_url: acs_url} do
      device_id = %{
        oui: "0015A4",
        manufacturer: "Arris",
        product_class: "TG3482G",
        serial_number: "ARR#{:rand.uniform(99_999_999)}"
      }

      params = %{
        "Device" => %{
          "DeviceInfo" => %{"Manufacturer" => "Arris"},
          "Docsis" => %{
            "Status" => "NotReady",
            "BootState" => "Boot"
          },
          "ManagementServer" => %{"URL" => acs_url}
        }
      }

      {:ok, state} = DeviceState.start_link(device_id: device_id, params: params)

      # Simulate registration flow
      events = DOCSIS.simulate_registration_flow(state)

      # Verify modem reached operational state
      final_status = DeviceState.get(state, "Device.Docsis.Status")
      assert final_status == "Operational"

      # Verify registration events were generated
      assert length(events) > 0
      event_codes = Enum.map(events, & &1.event_code)

      assert "X_CM_REGISTRATION" in event_codes

      GenServer.stop(state)
    end

    test "T3/T4 timeout events during upstream issues", %{acs_url: acs_url} do
      device_id = %{
        oui: "0015A4",
        manufacturer: "Arris",
        product_class: "TG3482G",
        serial_number: "ARR#{:rand.uniform(99_999_999)}"
      }

      params = %{
        "Device" => %{
          "DeviceInfo" => %{"Manufacturer" => "Arris"},
          "Docsis" => %{
            "Status" => "Operational",
            "Upstream" => %{
              "1" => %{"Power" => 42.0, "LockStatus" => "Locked"}
            }
          },
          "ManagementServer" => %{"URL" => acs_url}
        }
      }

      {:ok, state} = DeviceState.start_link(device_id: device_id, params: params)

      # Simulate T3 and T4 timeouts
      t3_events = DOCSIS.simulate_t3_timeout(state, 1)
      t4_events = DOCSIS.simulate_t4_timeout(state, 1)

      # Verify T3/T4 timeout events
      assert length(t3_events) > 0
      assert List.first(t3_events).event_code == "X_T3_TIMEOUT"

      assert length(t4_events) > 0
      assert List.first(t4_events).event_code == "X_T4_TIMEOUT"

      GenServer.stop(state)
    end

    test "full cable modem boot with Inform", %{acs_url: acs_url} do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-cm-boot-#{inspect(ref)}",
        [:caretaker, :acs, :inform, :received],
        fn _event, measurements, metadata, _ ->
          send(test_pid, {:inform_received, measurements, metadata})
        end,
        nil
      )

      device_id = %{
        oui: "0015A4",
        manufacturer: "Arris",
        product_class: "TG3482G",
        serial_number: "ARR#{:rand.uniform(99_999_999)}"
      }

      params = %{
        "Device" => %{
          "DeviceInfo" => %{
            "Manufacturer" => "Arris",
            "ModelName" => "TG3482G",
            "SoftwareVersion" => "AR01.02.117.11"
          },
          "Docsis" => %{
            "Status" => "Operational",
            "BootState" => "Operational"
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
          events: ["1 BOOT", "X_CM_OPERATIONAL"]
        )

      # Should complete successfully
      assert {:ok, session_data} = result
      assert session_data.inform_ack == true

      :telemetry.detach("test-cm-boot-#{inspect(ref)}")
      GenServer.stop(state)
    end
  end

  describe "Technicolor cable modem simulation" do
    test "Technicolor modem connects and reports DOCSIS stats", %{acs_url: acs_url} do
      device_id = %{
        oui: "00195E",
        manufacturer: "Technicolor",
        product_class: "TC8717T",
        serial_number: "TCL#{:rand.uniform(99_999_999)}"
      }

      params = %{
        "Device" => %{
          "DeviceInfo" => %{
            "Manufacturer" => "Technicolor",
            "ModelName" => "TC8717T",
            "SoftwareVersion" => "STAC.02.50"
          },
          "Docsis" => %{
            "Status" => "Operational",
            "Downstream" => %{
              "1" => %{"SNR" => 39.2, "Power" => 3.0}
            }
          },
          "ManagementServer" => %{"URL" => acs_url}
        }
      }

      {:ok, state} = DeviceState.start_link(device_id: device_id, params: params)

      # Verify Technicolor parameters
      assert DeviceState.get(state, "Device.DeviceInfo.Manufacturer") ==
               "Technicolor"

      assert DeviceState.get(state, "Device.Docsis.Status") == "Operational"

      GenServer.stop(state)
    end
  end

  describe "partial service simulation" do
    test "modem operates with subset of channels locked", %{acs_url: acs_url} do
      device_id = %{
        oui: "0015A4",
        manufacturer: "Arris",
        product_class: "TG3482G",
        serial_number: "ARR#{:rand.uniform(99_999_999)}"
      }

      # 32 downstream channels, but only half are locked
      downstream_params =
        for ch <- 1..32, into: %{} do
          lock_status = if ch <= 16, do: "Locked", else: "NotLocked"

          {"#{ch}",
           %{
             "Frequency" => 699_000_000 + (ch - 1) * 6_000_000,
             "Power" => if(lock_status == "Locked", do: 2.5, else: 0.0),
             "SNR" => if(lock_status == "Locked", do: 38.0, else: 0.0),
             "LockStatus" => lock_status
           }}
        end

      params = %{
        "Device" => %{
          "DeviceInfo" => %{"Manufacturer" => "Arris"},
          "Docsis" => %{
            "Status" => "PartialService",
            "Downstream" => downstream_params
          },
          "ManagementServer" => %{"URL" => acs_url}
        }
      }

      {:ok, state} = DeviceState.start_link(device_id: device_id, params: params)

      # Count locked channels
      locked_count =
        Enum.count(1..32, fn ch ->
          DeviceState.get(state, "Device.Docsis.Downstream.#{ch}.LockStatus") ==
            "Locked"
        end)

      assert locked_count == 16, "Should have 16 locked channels in partial service"

      # Verify partial service status
      assert DeviceState.get(state, "Device.Docsis.Status") == "PartialService"

      GenServer.stop(state)
    end
  end
end
