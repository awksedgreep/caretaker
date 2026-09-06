defmodule Caretaker.CPE.FirmwareSimulatorTest do
  use ExUnit.Case, async: false

  alias Caretaker.CPE.FirmwareSimulator
  alias Caretaker.CPE.Client
  alias Caretaker.CPE.DeviceState

  @moduletag :firmware

  describe "FirmwareSimulator state machine" do
    test "starts in idle state" do
      {:ok, sim} = FirmwareSimulator.start_link(current_version: "1.0.0")
      {state, info} = FirmwareSimulator.status(sim)

      assert state == :idle
      assert info.current_version == "1.0.0"
      assert info.target_version == nil
      assert info.command_key == nil
    end

    test "transitions to downloading on start_download" do
      {:ok, sim} =
        FirmwareSimulator.start_link(
          current_version: "1.0.0",
          download_duration: 100
        )

      result =
        FirmwareSimulator.start_download(sim, %{
          url: "http://example.com/firmware_v2.0.0.bin",
          command_key: "upgrade-123",
          file_type: "1 Firmware Upgrade Image"
        })

      assert result == {:ok, :downloading}

      {state, info} = FirmwareSimulator.status(sim)
      assert state == :downloading
      assert info.command_key == "upgrade-123"
      # Version extracted from URL
      assert info.target_version == "2.0.0"
    end

    test "prevents concurrent downloads" do
      {:ok, sim} =
        FirmwareSimulator.start_link(
          current_version: "1.0.0",
          download_duration: 1000
        )

      {:ok, :downloading} =
        FirmwareSimulator.start_download(sim, %{
          url: "http://example.com/fw.bin",
          command_key: "key1"
        })

      result =
        FirmwareSimulator.start_download(sim, %{
          url: "http://example.com/fw2.bin",
          command_key: "key2"
        })

      assert result == {:error, :already_downloading}
    end

    test "transitions to downloaded after download_duration" do
      {:ok, sim} =
        FirmwareSimulator.start_link(
          current_version: "1.0.0",
          download_duration: 50
        )

      {:ok, :downloading} =
        FirmwareSimulator.start_download(sim, %{
          url: "http://example.com/fw.bin",
          command_key: "key1"
        })

      # Wait for download to complete
      Process.sleep(100)

      assert FirmwareSimulator.download_complete?(sim)
      {state, _} = FirmwareSimulator.status(sim)
      assert state == :downloaded
    end

    test "provides transfer times for TransferComplete" do
      {:ok, sim} =
        FirmwareSimulator.start_link(
          current_version: "1.0.0",
          download_duration: 50
        )

      {:ok, :downloading} =
        FirmwareSimulator.start_download(sim, %{
          url: "http://example.com/fw.bin",
          command_key: "key1"
        })

      Process.sleep(100)

      {start_time, complete_time} = FirmwareSimulator.transfer_times(sim)

      # Times should be valid ISO8601
      assert {:ok, _, _} = DateTime.from_iso8601(start_time)
      assert {:ok, _, _} = DateTime.from_iso8601(complete_time)
    end

    test "transitions through reboot and updates version" do
      {:ok, sim} =
        FirmwareSimulator.start_link(
          current_version: "1.0.0",
          download_duration: 20,
          reboot_delay: 20
        )

      {:ok, :downloading} =
        FirmwareSimulator.start_download(sim, %{
          url: "http://example.com/firmware_v2.0.0.bin",
          command_key: "key1",
          target_version: "2.0.0"
        })

      # Wait for download
      Process.sleep(50)

      :ok = FirmwareSimulator.transfer_acknowledged(sim)
      {:ok, _delay} = FirmwareSimulator.start_reboot(sim)

      {state, _} = FirmwareSimulator.status(sim)
      assert state == :rebooting

      # Wait for reboot
      Process.sleep(50)

      assert FirmwareSimulator.reboot_complete?(sim)
      assert FirmwareSimulator.current_version(sim) == "2.0.0"
    end

    test "reset returns to idle state" do
      {:ok, sim} =
        FirmwareSimulator.start_link(
          current_version: "1.0.0",
          download_duration: 20,
          reboot_delay: 20
        )

      {:ok, :downloading} =
        FirmwareSimulator.start_download(sim, %{
          url: "http://example.com/fw.bin",
          command_key: "key1",
          target_version: "2.0.0"
        })

      Process.sleep(50)
      {:ok, _} = FirmwareSimulator.start_reboot(sim)
      Process.sleep(50)

      # After upgrade, version should be 2.0.0
      assert FirmwareSimulator.current_version(sim) == "2.0.0"

      # Reset back to idle
      :ok = FirmwareSimulator.reset(sim)

      {state, info} = FirmwareSimulator.status(sim)
      assert state == :idle
      # Version should be preserved
      assert info.current_version == "2.0.0"
      assert info.command_key == nil
    end
  end

  describe "FirmwareSimulator telemetry" do
    setup do
      test_pid = self()

      handler_id = "test-fw-telemetry-#{System.unique_integer()}"

      events = [
        [:caretaker, :firmware, :download, :start],
        [:caretaker, :firmware, :download, :complete],
        [:caretaker, :firmware, :reboot, :start],
        [:caretaker, :firmware, :reboot, :complete]
      ]

      :telemetry.attach_many(
        handler_id,
        events,
        fn name, measurements, metadata, _config ->
          send(test_pid, {:telemetry, name, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)
      :ok
    end

    test "emits telemetry events during download" do
      {:ok, sim} =
        FirmwareSimulator.start_link(
          current_version: "1.0.0",
          download_duration: 20
        )

      {:ok, :downloading} =
        FirmwareSimulator.start_download(sim, %{
          url: "http://example.com/fw_v2.0.0.bin",
          command_key: "telemetry-test"
        })

      assert_receive {:telemetry, [:caretaker, :firmware, :download, :start], _, meta}
      assert meta.command_key == "telemetry-test"
      assert meta.url == "http://example.com/fw_v2.0.0.bin"

      # Wait for download to complete
      Process.sleep(50)

      assert_receive {:telemetry, [:caretaker, :firmware, :download, :complete], measurements,
                      meta}

      assert meta.command_key == "telemetry-test"
      assert is_integer(measurements.duration_ms)
    end

    test "emits telemetry events during reboot" do
      {:ok, sim} =
        FirmwareSimulator.start_link(
          current_version: "1.0.0",
          download_duration: 20,
          reboot_delay: 20
        )

      {:ok, :downloading} =
        FirmwareSimulator.start_download(sim, %{
          url: "http://example.com/fw.bin",
          command_key: "reboot-test",
          target_version: "2.0.0"
        })

      Process.sleep(50)
      {:ok, _} = FirmwareSimulator.start_reboot(sim)

      assert_receive {:telemetry, [:caretaker, :firmware, :reboot, :start], _, meta}
      assert meta.command_key == "reboot-test"

      Process.sleep(50)

      assert_receive {:telemetry, [:caretaker, :firmware, :reboot, :complete], _, meta}
      assert meta.new_version == "2.0.0"
    end
  end

  describe "DeviceState integration" do
    test "firmware_simulator option stores reference" do
      {:ok, sim} = FirmwareSimulator.start_link(current_version: "1.0.0")

      {:ok, state} =
        DeviceState.start_link(
          device_id: %{oui: "A1B2C3", product_class: "Router", serial_number: "FW001"},
          params: %{},
          firmware_simulator: sim
        )

      assert {:ok, ^sim} = DeviceState.get_option(state, :firmware_simulator)
    end

    test "firmware_simulator option is nil by default" do
      {:ok, state} =
        DeviceState.start_link(
          device_id: %{oui: "A1B2C3", product_class: "Router", serial_number: "FW002"},
          params: %{}
        )

      assert :error = DeviceState.get_option(state, :firmware_simulator)
    end

    test "set_option updates option values" do
      {:ok, state} =
        DeviceState.start_link(
          device_id: %{oui: "A1B2C3", product_class: "Router", serial_number: "FW003"},
          params: %{}
        )

      {:ok, sim} = FirmwareSimulator.start_link(current_version: "1.0.0")
      :ok = DeviceState.set_option(state, :firmware_simulator, sim)

      assert {:ok, ^sim} = DeviceState.get_option(state, :firmware_simulator)
    end
  end

  describe "Download RPC handler integration" do
    setup do
      # Use unique port for each test
      port = 4080 + rem(System.unique_integer([:positive]), 100)

      {:ok, sup_pid} =
        Supervisor.start_link(
          [Caretaker.ACS.Server.child_spec(port: port)],
          strategy: :one_for_one
        )

      # Start Finch if needed
      case Process.whereis(Caretaker.Finch) do
        nil ->
          {:ok, _} = Finch.start_link(name: Caretaker.Finch)

        _ ->
          :ok
      end

      # Start Session GenServer
      {:ok, session_pid} = Caretaker.ACS.Session.start_link()

      on_exit(fn ->
        # Safely stop processes that may already be stopped or shutting down
        try do
          if Process.alive?(session_pid), do: GenServer.stop(session_pid, :normal, 100)
        catch
          :exit, _ -> :ok
        end

        try do
          Supervisor.stop(sup_pid, :normal, 100)
        catch
          :exit, _ -> :ok
        end
      end)

      %{acs_url: "http://localhost:#{port}/cwmp", port: port}
    end

    test "Download RPC returns status 1 for async download", %{acs_url: acs_url} do
      # Create firmware simulator
      {:ok, sim} =
        FirmwareSimulator.start_link(
          current_version: "1.0.0",
          download_duration: 100
        )

      # Create device state with firmware simulator
      device_id = %{
        manufacturer: "TestCo",
        oui: "FWDL01",
        product_class: "Router",
        serial_number: "DL001"
      }

      {:ok, state} =
        DeviceState.start_link(
          device_id: %{oui: "FWDL01", product_class: "Router", serial_number: "DL001"},
          params: %{
            "Device" => %{
              "DeviceInfo" => %{
                "Manufacturer" => "TestCo",
                "SerialNumber" => "DL001"
              }
            }
          },
          firmware_simulator: sim
        )

      # Attach telemetry handler for RPC responses BEFORE session starts
      test_pid = self()
      handler_id = "test-download-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:caretaker, :cpe_client, :rpc, :responded],
        fn _name, _measurements, metadata, _config ->
          send(test_pid, {:rpc_response, metadata.rpc, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      # Create Download RPC
      download =
        Caretaker.TR069.RPC.Download.new(
          command_key: "upgrade-001",
          file_type: "1 Firmware Upgrade Image",
          url: "http://example.com/firmware_v2.0.0.bin",
          file_size: 1_024_000,
          delay_seconds: 0
        )

      {:ok, download_body} = Caretaker.TR069.RPC.Download.encode(download)

      # Queue the Download ahead of the session. The ACS delivers queued RPCs
      # by piggybacking them on the HTTP response to each CPE message, so the
      # client handles both the auto-queued GetParameterValues and the Download
      # within one session (order-independent here).
      :ok =
        Caretaker.ACS.Session.queue_command(
          {device_id.oui, device_id.product_class, device_id.serial_number},
          download_body
        )

      session_task =
        Task.async(fn ->
          Client.run_session(acs_url,
            device_id: device_id,
            device_state: state
          )
        end)

      # Wait for Download response
      assert_receive {:rpc_response, "Download", meta}, 2000
      assert meta.command_key == "upgrade-001"
      assert meta.status == 1

      # Wait for session to complete
      {:ok, _result} = Task.await(session_task, 5000)

      # Firmware simulator should be downloading or downloaded
      {state_status, _} = FirmwareSimulator.status(sim)
      assert state_status in [:downloading, :downloaded]
    end

    test "Reboot RPC triggers reboot simulation", %{acs_url: acs_url} do
      # Create firmware simulator in applying state
      {:ok, sim} =
        FirmwareSimulator.start_link(
          current_version: "1.0.0",
          download_duration: 20,
          reboot_delay: 50
        )

      # Start a download and wait for it to complete
      {:ok, :downloading} =
        FirmwareSimulator.start_download(sim, %{
          url: "http://example.com/fw.bin",
          command_key: "reboot-test",
          target_version: "2.0.0"
        })

      Process.sleep(50)

      # Create device state with firmware simulator
      device_id = %{
        manufacturer: "TestCo",
        oui: "FWRB01",
        product_class: "Router",
        serial_number: "RB001"
      }

      {:ok, state} =
        DeviceState.start_link(
          device_id: %{oui: "FWRB01", product_class: "Router", serial_number: "RB001"},
          params: %{
            "Device" => %{
              "DeviceInfo" => %{
                "Manufacturer" => "TestCo",
                "SerialNumber" => "RB001"
              }
            }
          },
          firmware_simulator: sim
        )

      # Attach telemetry handler
      test_pid = self()
      handler_id = "test-reboot-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:caretaker, :cpe_client, :rpc, :responded],
        fn _name, _measurements, metadata, _config ->
          send(test_pid, {:rpc_response, metadata.rpc, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      # Create Reboot RPC
      reboot = Caretaker.TR069.RPC.Reboot.new(command_key: "reboot-123")
      {:ok, reboot_body} = Caretaker.TR069.RPC.Reboot.encode(reboot)

      # Queue the Reboot ahead of the session; the ACS piggybacks it onto a
      # session response. Reboot ends the session, so it must be handled.
      :ok =
        Caretaker.ACS.Session.queue_command(
          {device_id.oui, device_id.product_class, device_id.serial_number},
          reboot_body
        )

      session_task =
        Task.async(fn ->
          Client.run_session(acs_url,
            device_id: device_id,
            device_state: state
          )
        end)

      # Wait for Reboot response
      assert_receive {:rpc_response, "Reboot", meta}, 2000
      assert meta.rpc == "Reboot"

      # Wait for session to complete
      {:ok, _result} = Task.await(session_task, 5000)

      # Wait for reboot to complete
      Process.sleep(100)

      # Firmware should be upgraded
      assert FirmwareSimulator.reboot_complete?(sim)
      assert FirmwareSimulator.current_version(sim) == "2.0.0"
    end
  end
end
