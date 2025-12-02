defmodule Caretaker.CPE.RPCSuiteTest do
  use ExUnit.Case, async: false

  alias Caretaker.CPE.{Client, DeviceState}

  @port 4053
  @acs_url "http://localhost:4053/cwmp"

  setup do
    # Start dependencies
    _ = start_supervised(Caretaker.PubSub)
    _ = start_supervised(Caretaker.ACS.Session)
    _ = start_supervised({Finch, name: Caretaker.Finch})

    # Start the ACS server
    {:ok, _} = start_supervised({Bandit, plug: Caretaker.ACS.Server, port: @port})

    # Create device state with profile
    device_id = %{
      manufacturer: "Caretaker",
      oui: "000000",
      product_class: "CaretakerCPE",
      serial_number: "000000"
    }

    {:ok, device_state} = DeviceState.start_link(device_id: device_id)

    profile_path = Path.join([File.cwd!(), "priv", "profiles", "fiber_ont.json"])
    :ok = DeviceState.load_profile(device_state, profile_path)

    on_exit(fn ->
      if Process.alive?(device_state), do: Agent.stop(device_state)
    end)

    %{device_state: device_state}
  end

  describe "GetParameterNames" do
    test "with NextLevel=true returns immediate children only", ctx do
      # Attach telemetry
      :ok =
        :telemetry.attach(
          "test-gpn-next-level",
          [:caretaker, :cpe_client, :rpc, :responded],
          fn _event, _measurements, metadata, _ ->
            send(self(), {:telemetry, metadata})
          end,
          nil
        )

      # Get device_id from state (must match what Client will use)
      device_id = DeviceState.device_id(ctx.device_state)
      dev_key = {device_id.oui, device_id.product_class, device_id.serial_number}

      # Manually upsert session first
      Caretaker.ACS.Session.upsert(dev_key, device_id, "urn:dslforum-org:cwmp-1-0")

      # Enqueue GetParameterNames with NextLevel=true
      {:ok, gpn_body} =
        Caretaker.TR069.RPC.GetParameterNames.new("Device.", true)
        |> Caretaker.TR069.RPC.GetParameterNames.encode()

      Caretaker.ACS.Session.queue_command(dev_key, gpn_body)

      # Pass device_id to ensure Inform uses the same identity
      assert {:ok, _result} = Client.run_session(@acs_url, device_state: ctx.device_state, device_id: device_id)

      # Skip auto-queued GetParameterValues (there might be 2 - one from upsert, one from Inform)
      assert_receive {:telemetry, %{rpc: "GetParameterValues"}}

      # Verify telemetry shows NextLevel was true
      assert_receive {:telemetry, %{rpc: "GetParameterNames", next_level: true, param_count: count}}, 1000
      assert count > 0, "Expected immediate children of Device."

      :telemetry.detach("test-gpn-next-level")
    end

    test "with NextLevel=false returns all leaf parameters", ctx do
      :ok =
        :telemetry.attach(
          "test-gpn-full-tree",
          [:caretaker, :cpe_client, :rpc, :responded],
          fn _event, _measurements, metadata, _ ->
            send(self(), {:telemetry, metadata})
          end,
          nil
        )

      # Get device_id from state (must match what Client will use)
      device_id = DeviceState.device_id(ctx.device_state)
      dev_key = {device_id.oui, device_id.product_class, device_id.serial_number}

      # Manually upsert session first
      Caretaker.ACS.Session.upsert(dev_key, device_id, "urn:dslforum-org:cwmp-1-0")

      # Enqueue GetParameterNames with NextLevel=false
      {:ok, gpn_body} =
        Caretaker.TR069.RPC.GetParameterNames.new("Device.DeviceInfo.", false)
        |> Caretaker.TR069.RPC.GetParameterNames.encode()

      Caretaker.ACS.Session.queue_command(dev_key, gpn_body)

      # Pass device_id to ensure Inform uses the same identity
      assert {:ok, _result} = Client.run_session(@acs_url, device_state: ctx.device_state, device_id: device_id)

      # Skip the auto-queued GetParameterValues
      assert_receive {:telemetry, %{rpc: "GetParameterValues"}}

      # Verify all leaf parameters returned
      assert_receive {:telemetry,
                      %{rpc: "GetParameterNames", next_level: false, param_count: count}}

      # Should return multiple leaf parameters under Device.DeviceInfo
      assert count > 5, "Expected multiple leaf parameters, got #{count}"

      :telemetry.detach("test-gpn-full-tree")
    end
  end

  describe "GetRPCMethods" do
    test "returns list of supported RPC methods", ctx do
      :ok =
        :telemetry.attach(
          "test-grm",
          [:caretaker, :cpe_client, :rpc, :responded],
          fn _event, _measurements, metadata, _ ->
            send(self(), {:telemetry, metadata})
          end,
          nil
        )

      # Get device_id from state (must match what Client will use)
      device_id = DeviceState.device_id(ctx.device_state)
      dev_key = {device_id.oui, device_id.product_class, device_id.serial_number}

      # Manually upsert session first
      Caretaker.ACS.Session.upsert(dev_key, device_id, "urn:dslforum-org:cwmp-1-0")

      # Enqueue GetRPCMethods
      {:ok, grm_body} =
        %Caretaker.TR069.RPC.GetRPCMethods{}
        |> Caretaker.TR069.RPC.GetRPCMethods.encode()

      Caretaker.ACS.Session.queue_command(dev_key, grm_body)

      # Pass device_id to ensure Inform uses the same identity
      assert {:ok, _result} = Client.run_session(@acs_url, device_state: ctx.device_state, device_id: device_id)

      # Skip the auto-queued GetParameterValues
      assert_receive {:telemetry, %{rpc: "GetParameterValues"}}

      # Verify response includes method list
      assert_receive {:telemetry, %{rpc: "GetRPCMethods", method_count: count}}
      assert count >= 5, "Expected at least 5 supported methods"

      :telemetry.detach("test-grm")
    end
  end

  describe "DeviceState get_parameter_names" do
    test "NextLevel=true returns immediate children", ctx do
      names = DeviceState.get_parameter_names(ctx.device_state, "Device.", true)

      # Should return partial paths like "Device.DeviceInfo.", "Device.ManagementServer."
      assert length(names) > 0
      assert Enum.all?(names, fn %{name: name} -> String.ends_with?(name, ".") end)
      assert Enum.any?(names, fn %{name: name} -> name == "Device.DeviceInfo." end)
    end

    test "NextLevel=false returns all leaf parameters", ctx do
      names = DeviceState.get_parameter_names(ctx.device_state, "Device.DeviceInfo.", false)

      # Should return full paths like "Device.DeviceInfo.Manufacturer"
      assert length(names) > 5
      assert Enum.all?(names, fn %{name: name} -> String.starts_with?(name, "Device.DeviceInfo.") end)
      assert Enum.any?(names, fn %{name: name} -> name == "Device.DeviceInfo.Manufacturer" end)
    end

    test "empty path returns root parameters", ctx do
      names = DeviceState.get_parameter_names(ctx.device_state, "", true)

      assert length(names) > 0
      # Should have "Device." at minimum
      assert Enum.any?(names, fn %{name: name} -> name == "Device." end)
    end
  end
end
