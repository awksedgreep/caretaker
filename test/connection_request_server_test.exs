defmodule Caretaker.CPE.ConnectionRequestServerTest do
  use ExUnit.Case, async: false

  alias Caretaker.CPE.ConnectionRequestServer
  alias Caretaker.CPE.Fleet

  @moduletag :capture_log

  setup do
    # Start a fleet with behaviors enabled
    {:ok, fleet} = Fleet.start_link(
      acs_url: "http://localhost:4000/cwmp",
      count: 3,
      connection_delay: 0,
      behaviors: [value_change_events: true]
    )

    {:ok, _} = Fleet.spawn_devices(fleet)

    # Get a unique port for this test
    port = Enum.random(17000..18000)

    on_exit(fn ->
      if Process.alive?(fleet), do: Fleet.stop_all(fleet)
    end)

    {:ok, fleet: fleet, port: port}
  end

  describe "start_link/1" do
    test "starts server on specified port", %{fleet: fleet, port: port} do
      {:ok, server} = ConnectionRequestServer.start_link(
        fleet: fleet,
        port: port
      )

      assert is_pid(server)
      assert Process.alive?(server)
      assert ConnectionRequestServer.port(server) == port

      ConnectionRequestServer.stop(server)
    end

    test "starts server with authentication", %{fleet: fleet, port: port} do
      {:ok, server} = ConnectionRequestServer.start_link(
        fleet: fleet,
        port: port,
        auth: %{username: "acs", password: "secret"}
      )

      assert is_pid(server)
      ConnectionRequestServer.stop(server)
    end
  end

  describe "base_url/1" do
    test "returns correct base URL", %{fleet: fleet, port: port} do
      {:ok, server} = ConnectionRequestServer.start_link(
        fleet: fleet,
        port: port,
        host: "192.168.1.100"
      )

      assert ConnectionRequestServer.base_url(server) == "http://192.168.1.100:#{port}"
      ConnectionRequestServer.stop(server)
    end
  end

  describe "device_url/2" do
    test "returns correct device-specific URL", %{fleet: fleet, port: port} do
      {:ok, server} = ConnectionRequestServer.start_link(
        fleet: fleet,
        port: port,
        host: "192.168.1.100"
      )

      url = ConnectionRequestServer.device_url(server, "FLEET0-000001")
      assert url == "http://192.168.1.100:#{port}/cr/FLEET0-000001"

      ConnectionRequestServer.stop(server)
    end
  end

  describe "connection request handling" do
    test "triggers connection request event on device", %{fleet: fleet, port: port} do
      {:ok, server} = ConnectionRequestServer.start_link(
        fleet: fleet,
        port: port
      )

      # Make HTTP request to trigger connection request
      {:ok, response} = http_get("http://localhost:#{port}/cr/FLEET0-000001")

      assert response.status == 200

      # Verify the device has a pending event
      {:ok, device} = Fleet.get_device(fleet, "FLEET0-000001")
      assert device.last_inform != nil

      ConnectionRequestServer.stop(server)
    end

    test "returns 404 for non-existent device", %{fleet: fleet, port: port} do
      {:ok, server} = ConnectionRequestServer.start_link(
        fleet: fleet,
        port: port
      )

      {:ok, response} = http_get("http://localhost:#{port}/cr/NONEXISTENT-999999")

      assert response.status == 404

      ConnectionRequestServer.stop(server)
    end

    test "returns 404 for invalid paths", %{fleet: fleet, port: port} do
      {:ok, server} = ConnectionRequestServer.start_link(
        fleet: fleet,
        port: port
      )

      {:ok, response} = http_get("http://localhost:#{port}/invalid/path")

      assert response.status == 404

      ConnectionRequestServer.stop(server)
    end
  end

  describe "health check" do
    test "returns 200 OK on /health", %{fleet: fleet, port: port} do
      {:ok, server} = ConnectionRequestServer.start_link(
        fleet: fleet,
        port: port
      )

      {:ok, response} = http_get("http://localhost:#{port}/health")

      assert response.status == 200
      assert response.body == "OK"

      ConnectionRequestServer.stop(server)
    end
  end

  describe "authentication" do
    test "rejects unauthenticated requests when auth is configured", %{fleet: fleet, port: port} do
      {:ok, server} = ConnectionRequestServer.start_link(
        fleet: fleet,
        port: port,
        auth: %{username: "acs", password: "secret"}
      )

      {:ok, response} = http_get("http://localhost:#{port}/cr/FLEET0-000001")

      assert response.status == 401

      ConnectionRequestServer.stop(server)
    end

    test "accepts correctly authenticated requests", %{fleet: fleet, port: port} do
      {:ok, server} = ConnectionRequestServer.start_link(
        fleet: fleet,
        port: port,
        auth: %{username: "acs", password: "secret"}
      )

      credentials = Base.encode64("acs:secret")
      headers = [{"authorization", "Basic #{credentials}"}]

      {:ok, response} = http_get("http://localhost:#{port}/cr/FLEET0-000001", headers)

      assert response.status == 200

      ConnectionRequestServer.stop(server)
    end

    test "rejects wrong credentials", %{fleet: fleet, port: port} do
      {:ok, server} = ConnectionRequestServer.start_link(
        fleet: fleet,
        port: port,
        auth: %{username: "acs", password: "secret"}
      )

      credentials = Base.encode64("acs:wrongpassword")
      headers = [{"authorization", "Basic #{credentials}"}]

      {:ok, response} = http_get("http://localhost:#{port}/cr/FLEET0-000001", headers)

      assert response.status == 401

      ConnectionRequestServer.stop(server)
    end

    test "allows requests when no auth configured", %{fleet: fleet, port: port} do
      {:ok, server} = ConnectionRequestServer.start_link(
        fleet: fleet,
        port: port
        # No auth configured
      )

      {:ok, response} = http_get("http://localhost:#{port}/cr/FLEET0-000001")

      assert response.status == 200

      ConnectionRequestServer.stop(server)
    end
  end

  describe "telemetry events" do
    test "emits connection_request.received event", %{fleet: fleet, port: port} do
      {:ok, server} = ConnectionRequestServer.start_link(
        fleet: fleet,
        port: port
      )

      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-cr-received-#{inspect(ref)}",
        [:caretaker, :connection_request, :received],
        fn _event, _measurements, metadata, _ ->
          send(test_pid, {:telemetry, :received, metadata})
        end,
        nil
      )

      {:ok, _} = http_get("http://localhost:#{port}/cr/FLEET0-000001")

      assert_receive {:telemetry, :received, %{serial: "FLEET0-000001"}}, 1_000

      :telemetry.detach("test-cr-received-#{inspect(ref)}")
      ConnectionRequestServer.stop(server)
    end

    test "emits connection_request.triggered event", %{fleet: fleet, port: port} do
      {:ok, server} = ConnectionRequestServer.start_link(
        fleet: fleet,
        port: port
      )

      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-cr-triggered-#{inspect(ref)}",
        [:caretaker, :connection_request, :triggered],
        fn _event, _measurements, metadata, _ ->
          send(test_pid, {:telemetry, :triggered, metadata})
        end,
        nil
      )

      {:ok, _} = http_get("http://localhost:#{port}/cr/FLEET0-000001")

      assert_receive {:telemetry, :triggered, %{serial: "FLEET0-000001"}}, 1_000

      :telemetry.detach("test-cr-triggered-#{inspect(ref)}")
      ConnectionRequestServer.stop(server)
    end

    test "emits connection_request.not_found event for missing device", %{fleet: fleet, port: port} do
      {:ok, server} = ConnectionRequestServer.start_link(
        fleet: fleet,
        port: port
      )

      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-cr-not-found-#{inspect(ref)}",
        [:caretaker, :connection_request, :not_found],
        fn _event, _measurements, metadata, _ ->
          send(test_pid, {:telemetry, :not_found, metadata})
        end,
        nil
      )

      {:ok, _} = http_get("http://localhost:#{port}/cr/NONEXISTENT")

      assert_receive {:telemetry, :not_found, %{serial: "NONEXISTENT"}}, 1_000

      :telemetry.detach("test-cr-not-found-#{inspect(ref)}")
      ConnectionRequestServer.stop(server)
    end

    test "emits server.started event", %{fleet: fleet, port: port} do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-cr-started-#{inspect(ref)}",
        [:caretaker, :connection_request, :server, :started],
        fn _event, measurements, _metadata, _ ->
          send(test_pid, {:telemetry, :started, measurements})
        end,
        nil
      )

      {:ok, server} = ConnectionRequestServer.start_link(
        fleet: fleet,
        port: port
      )

      assert_receive {:telemetry, :started, %{port: ^port}}, 1_000

      :telemetry.detach("test-cr-started-#{inspect(ref)}")
      ConnectionRequestServer.stop(server)
    end
  end

  describe "Fleet.trigger_connection_request/2" do
    test "triggers 6 CONNECTION REQUEST event", %{fleet: fleet} do
      # Get a device with behavior
      devices = Fleet.list_devices(fleet)
      device = hd(devices)

      :ok = Fleet.trigger_connection_request(fleet, device.serial_number)

      # Verify the event was added
      {:ok, updated_device} = Fleet.get_device(fleet, device.serial_number)
      assert updated_device.last_inform != nil
    end

    test "returns error for non-existent device", %{fleet: fleet} do
      result = Fleet.trigger_connection_request(fleet, "NONEXISTENT-123456")
      assert result == {:error, :not_found}
    end
  end

  # ============================================================================
  # HTTP Helper using Finch
  # ============================================================================

  defp http_get(url, headers \\ []) do
    ensure_finch_started()

    req = Finch.build(:get, url, headers)

    case Finch.request(req, Caretaker.Finch, receive_timeout: 5_000) do
      {:ok, %Finch.Response{status: status, body: body, headers: resp_headers}} ->
        {:ok, %{status: status, body: body, headers: resp_headers}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_finch_started do
    case Process.whereis(Caretaker.Finch) do
      nil ->
        {:ok, _} = Supervisor.start_link([{Finch, name: Caretaker.Finch}], strategy: :one_for_one)
        :ok

      _pid ->
        :ok
    end
  end
end
