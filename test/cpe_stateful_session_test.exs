defmodule Caretaker.CPE.StatefulSessionTest do
  use ExUnit.Case, async: false

  alias Caretaker.CPE.{Client, DeviceState}

  setup do
    port = random_port()

    # Start dependencies
    _ = start_supervised(Caretaker.PubSub)
    _ = start_supervised(Caretaker.ACS.Session)
    _ = start_supervised({Finch, name: Caretaker.Finch})

    # Start the ACS server using the regular ACS.Server
    {:ok, _} = start_supervised({Bandit, plug: Caretaker.ACS.Server, port: port})

    # Create device state with default device_id
    device_id = %{
      oui: "000000",
      product_class: "CaretakerCPE",
      serial_number: "000000"
    }

    {:ok, device_state} = DeviceState.start_link(device_id: device_id)

    # Load fiber_ont profile
    profile_path = Path.join([File.cwd!(), "priv", "profiles", "fiber_ont.json"])
    :ok = DeviceState.load_profile(device_state, profile_path)

    on_exit(fn ->
      if Process.alive?(device_state), do: Agent.stop(device_state)
    end)

    %{device_state: device_state, acs_url: "http://localhost:#{port}/cwmp"}
  end

  test "CPE client with DeviceState responds to GetParameterValues", ctx do
    # Attach telemetry handler to track RPC responses
    :ok =
      :telemetry.attach_many(
        "test-stateful-gpv",
        [
          [:caretaker, :cpe_client, :session, :start],
          [:caretaker, :cpe_client, :session, :stop],
          [:caretaker, :cpe_client, :rpc, :responded]
        ],
        fn event, measurements, metadata, _ ->
          send(self(), {:telemetry, event, measurements, metadata})
        end,
        nil
      )

    # Enqueue GetParameterValues for the device
    Caretaker.ACS.Session.queue_command(
      {"000000", "CaretakerCPE", "000000"},
      Caretaker.TR069.RPC.GetParameterValues.new([
        "Device.DeviceInfo.",
        "Device.ManagementServer."
      ])
    )

    # Run a session with device_state (no device_id needed when using defaults)
    assert {:ok, _result} =
             Client.run_session(
               ctx.acs_url,
               device_state: ctx.device_state,
               timeout: 5000
             )

    # Verify session telemetry
    assert_receive {:telemetry, [:caretaker, :cpe_client, :session, :start], _, _}

    # Verify GetParameterValues response with profile data
    assert_receive {:telemetry, [:caretaker, :cpe_client, :rpc, :responded], _,
                    %{rpc: "GetParameterValues", param_count: count}}

    # Should have returned multiple parameters from the profile (not just 2 hardcoded ones)
    assert count > 2, "Expected more than 2 parameters from DeviceState, got #{count}"

    assert_receive {:telemetry, [:caretaker, :cpe_client, :session, :stop], _, _}

    :telemetry.detach("test-stateful-gpv")
  end

  test "DeviceState provides profile values", ctx do
    # Verify profile was loaded
    manufacturer = DeviceState.get(ctx.device_state, "Device.DeviceInfo.Manufacturer")
    assert manufacturer != nil
    assert is_binary(manufacturer) or is_boolean(manufacturer)

    # Verify we can get a tree of parameters
    device_info = DeviceState.get_tree(ctx.device_state, "Device.DeviceInfo")
    assert is_map(device_info)
    assert map_size(device_info) > 0

    # Verify we can update parameters
    :ok = DeviceState.set(ctx.device_state, "Device.DeviceInfo.SoftwareVersion", "test-version")

    assert DeviceState.get(ctx.device_state, "Device.DeviceInfo.SoftwareVersion") ==
             "test-version"
  end

  defp random_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_address, port}} = :inet.sockname(socket)
    :ok = :gen_tcp.close(socket)
    port
  end
end
