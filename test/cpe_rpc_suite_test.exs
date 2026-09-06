defmodule Caretaker.CPE.RPCSuiteTest do
  use ExUnit.Case, async: false

  alias Caretaker.CPE.{Client, DeviceState}

  setup do
    port = random_port()

    # Start dependencies
    _ = start_supervised(Caretaker.PubSub)
    _ = start_supervised(Caretaker.ACS.Session)
    _ = start_supervised({Finch, name: Caretaker.Finch})

    # Start the ACS server
    {:ok, _} = start_supervised({Bandit, plug: Caretaker.ACS.Server, port: port})

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

    %{device_state: device_state, acs_url: "http://localhost:#{port}/cwmp"}
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
      assert {:ok, _result} =
               Client.run_session(ctx.acs_url,
                 device_state: ctx.device_state,
                 device_id: device_id
               )

      # Skip auto-queued GetParameterValues (there might be 2 - one from upsert, one from Inform)
      assert_receive {:telemetry, %{rpc: "GetParameterValues"}}

      # Verify telemetry shows NextLevel was true
      assert_receive {:telemetry,
                      %{rpc: "GetParameterNames", next_level: true, param_count: count}},
                     1000

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
      assert {:ok, _result} =
               Client.run_session(ctx.acs_url,
                 device_state: ctx.device_state,
                 device_id: device_id
               )

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
      assert {:ok, _result} =
               Client.run_session(ctx.acs_url,
                 device_state: ctx.device_state,
                 device_id: device_id
               )

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

      assert Enum.all?(names, fn %{name: name} ->
               String.starts_with?(name, "Device.DeviceInfo.")
             end)

      assert Enum.any?(names, fn %{name: name} -> name == "Device.DeviceInfo.Manufacturer" end)
    end

    test "empty path returns root parameters", ctx do
      names = DeviceState.get_parameter_names(ctx.device_state, "", true)

      assert length(names) > 0
      # Should have "Device." at minimum
      assert Enum.any?(names, fn %{name: name} -> name == "Device." end)
    end
  end

  describe "DeviceState parameter attributes" do
    test "get_parameter_attributes returns default attributes", ctx do
      attrs =
        DeviceState.get_parameter_attributes(ctx.device_state, ["Device.DeviceInfo.Manufacturer"])

      assert length(attrs) == 1
      attr = hd(attrs)
      assert attr.name == "Device.DeviceInfo.Manufacturer"
      assert attr.notification == 0
      assert attr.access_list == ["Subscriber"]
    end

    test "set_parameter_attributes updates notification", ctx do
      # Set notification to active (2)
      DeviceState.set_parameter_attributes(ctx.device_state, [
        %{
          name: "Device.DeviceInfo.SoftwareVersion",
          notification_change: true,
          notification: 2,
          access_list_change: false,
          access_list: []
        }
      ])

      attrs =
        DeviceState.get_parameter_attributes(ctx.device_state, [
          "Device.DeviceInfo.SoftwareVersion"
        ])

      attr = hd(attrs)
      assert attr.notification == 2
    end

    test "set_parameter_attributes updates access_list", ctx do
      DeviceState.set_parameter_attributes(ctx.device_state, [
        %{
          name: "Device.DeviceInfo.Description",
          notification_change: false,
          notification: 0,
          access_list_change: true,
          access_list: ["Subscriber", "Admin"]
        }
      ])

      attrs =
        DeviceState.get_parameter_attributes(ctx.device_state, ["Device.DeviceInfo.Description"])

      attr = hd(attrs)
      assert attr.access_list == ["Subscriber", "Admin"]
    end

    test "get_parameter_attributes expands path with trailing dot", ctx do
      attrs = DeviceState.get_parameter_attributes(ctx.device_state, ["Device.DeviceInfo."])

      # Should return multiple parameters under DeviceInfo
      assert length(attrs) > 5
      assert Enum.all?(attrs, fn a -> String.starts_with?(a.name, "Device.DeviceInfo.") end)
    end
  end

  describe "DeviceState object management" do
    test "add_object_instance creates new instance", ctx do
      # The fiber_ont profile already defines Device.IP.Interface.1 and .2,
      # so the new instance must not collide with them.
      {:ok, instance} = DeviceState.add_object_instance(ctx.device_state, "Device.IP.Interface.")

      assert instance == 3
      assert DeviceState.get(ctx.device_state, "Device.IP.Interface.1") != nil

      next = DeviceState.get_next_instance_number(ctx.device_state, "Device.IP.Interface.")
      assert next == 4
    end

    test "add_object_instance increments instance numbers", ctx do
      {:ok, inst1} = DeviceState.add_object_instance(ctx.device_state, "Device.Test.")
      {:ok, inst2} = DeviceState.add_object_instance(ctx.device_state, "Device.Test.")
      {:ok, inst3} = DeviceState.add_object_instance(ctx.device_state, "Device.Test.")

      assert inst1 == 1
      assert inst2 == 2
      assert inst3 == 3
    end

    test "delete_object_instance removes instance", ctx do
      {:ok, inst} = DeviceState.add_object_instance(ctx.device_state, "Device.Deletable.")

      # Set some parameters in the instance
      DeviceState.set(ctx.device_state, "Device.Deletable.#{inst}.Name", "TestInstance")

      # Verify it exists
      assert DeviceState.get(ctx.device_state, "Device.Deletable.#{inst}.Name") == "TestInstance"

      # Delete the instance
      :ok = DeviceState.delete_object_instance(ctx.device_state, "Device.Deletable.#{inst}.")

      # Verify it's gone
      assert DeviceState.get(ctx.device_state, "Device.Deletable.#{inst}.Name") == nil
    end

    test "delete_object_instance returns error for non-existent path", ctx do
      result = DeviceState.delete_object_instance(ctx.device_state, "Device.NonExistent.999.")
      assert result == {:error, :not_found}
    end

    test "get_next_instance_number returns 1 for new paths", ctx do
      next = DeviceState.get_next_instance_number(ctx.device_state, "Device.NewObject.")
      assert next == 1
    end
  end

  describe "GetParameterAttributes RPC" do
    test "returns attributes for requested parameters", ctx do
      :ok =
        :telemetry.attach(
          "test-gpa",
          [:caretaker, :cpe_client, :rpc, :responded],
          fn _event, _measurements, metadata, _ ->
            send(self(), {:telemetry, metadata})
          end,
          nil
        )

      device_id = DeviceState.device_id(ctx.device_state)
      dev_key = {device_id.oui, device_id.product_class, device_id.serial_number}
      Caretaker.ACS.Session.upsert(dev_key, device_id, "urn:dslforum-org:cwmp-1-0")

      {:ok, gpa_body} =
        Caretaker.TR069.RPC.GetParameterAttributes.new(["Device.DeviceInfo.Manufacturer"])
        |> Caretaker.TR069.RPC.GetParameterAttributes.encode()

      Caretaker.ACS.Session.queue_command(dev_key, gpa_body)

      assert {:ok, _} =
               Client.run_session(ctx.acs_url,
                 device_state: ctx.device_state,
                 device_id: device_id
               )

      assert_receive {:telemetry, %{rpc: "GetParameterValues"}}
      assert_receive {:telemetry, %{rpc: "GetParameterAttributes", param_count: count}}
      assert count >= 1

      :telemetry.detach("test-gpa")
    end
  end

  describe "SetParameterAttributes RPC" do
    test "updates attributes and returns success", ctx do
      :ok =
        :telemetry.attach(
          "test-spa",
          [:caretaker, :cpe_client, :rpc, :responded],
          fn _event, _measurements, metadata, _ ->
            send(self(), {:telemetry, metadata})
          end,
          nil
        )

      device_id = DeviceState.device_id(ctx.device_state)
      dev_key = {device_id.oui, device_id.product_class, device_id.serial_number}
      Caretaker.ACS.Session.upsert(dev_key, device_id, "urn:dslforum-org:cwmp-1-0")

      {:ok, spa_body} =
        Caretaker.TR069.RPC.SetParameterAttributes.encode(%{
          parameters: [
            %{
              name: "Device.DeviceInfo.Description",
              notification_change: true,
              notification: 2,
              access_list_change: false,
              access_list: []
            }
          ]
        })

      Caretaker.ACS.Session.queue_command(dev_key, spa_body)

      assert {:ok, _} =
               Client.run_session(ctx.acs_url,
                 device_state: ctx.device_state,
                 device_id: device_id
               )

      assert_receive {:telemetry, %{rpc: "GetParameterValues"}}
      assert_receive {:telemetry, %{rpc: "SetParameterAttributes"}}

      # Verify the attribute was updated
      attrs =
        DeviceState.get_parameter_attributes(ctx.device_state, ["Device.DeviceInfo.Description"])

      assert hd(attrs).notification == 2

      :telemetry.detach("test-spa")
    end
  end

  describe "AddObject RPC" do
    test "creates new object instance", ctx do
      :ok =
        :telemetry.attach(
          "test-ao",
          [:caretaker, :cpe_client, :rpc, :responded],
          fn _event, _measurements, metadata, _ ->
            send(self(), {:telemetry, metadata})
          end,
          nil
        )

      device_id = DeviceState.device_id(ctx.device_state)
      dev_key = {device_id.oui, device_id.product_class, device_id.serial_number}
      Caretaker.ACS.Session.upsert(dev_key, device_id, "urn:dslforum-org:cwmp-1-0")

      {:ok, ao_body} =
        Caretaker.TR069.RPC.AddObject.new("Device.Services.VoIPService.")
        |> Caretaker.TR069.RPC.AddObject.encode()

      Caretaker.ACS.Session.queue_command(dev_key, ao_body)

      assert {:ok, _} =
               Client.run_session(ctx.acs_url,
                 device_state: ctx.device_state,
                 device_id: device_id
               )

      assert_receive {:telemetry, %{rpc: "GetParameterValues"}}
      assert_receive {:telemetry, %{rpc: "AddObject", instance_number: inst, object_path: path}}
      assert inst == 1
      assert path == "Device.Services.VoIPService."

      :telemetry.detach("test-ao")
    end
  end

  describe "DeleteObject RPC" do
    test "removes object instance", ctx do
      # First create an instance to delete
      {:ok, inst} = DeviceState.add_object_instance(ctx.device_state, "Device.Deletable.")
      DeviceState.set(ctx.device_state, "Device.Deletable.#{inst}.Name", "ToDelete")

      :ok =
        :telemetry.attach(
          "test-do",
          [:caretaker, :cpe_client, :rpc, :responded],
          fn _event, _measurements, metadata, _ ->
            send(self(), {:telemetry, metadata})
          end,
          nil
        )

      device_id = DeviceState.device_id(ctx.device_state)
      dev_key = {device_id.oui, device_id.product_class, device_id.serial_number}
      Caretaker.ACS.Session.upsert(dev_key, device_id, "urn:dslforum-org:cwmp-1-0")

      {:ok, do_body} =
        Caretaker.TR069.RPC.DeleteObject.new("Device.Deletable.#{inst}.")
        |> Caretaker.TR069.RPC.DeleteObject.encode()

      Caretaker.ACS.Session.queue_command(dev_key, do_body)

      assert {:ok, _} =
               Client.run_session(ctx.acs_url,
                 device_state: ctx.device_state,
                 device_id: device_id
               )

      assert_receive {:telemetry, %{rpc: "GetParameterValues"}}
      assert_receive {:telemetry, %{rpc: "DeleteObject", object_path: path}}
      assert path == "Device.Deletable.#{inst}."

      # Verify instance is gone
      assert DeviceState.get(ctx.device_state, "Device.Deletable.#{inst}.Name") == nil

      :telemetry.detach("test-do")
    end
  end

  defp random_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_address, port}} = :inet.sockname(socket)
    :ok = :gen_tcp.close(socket)
    port
  end
end
