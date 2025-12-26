defmodule Caretaker.USP.ControllerTest do
  use ExUnit.Case, async: true

  alias Caretaker.USP.{Controller, Proto, Record, Agent}

  describe "start_link/1" do
    test "starts a controller with endpoint ID" do
      {:ok, controller} = Controller.start_link(endpoint_id: "self::acs.example.com")
      assert Controller.endpoint_id(controller) == "self::acs.example.com"
    end
  end

  describe "list_agents/1" do
    test "returns empty list initially" do
      {:ok, controller} = Controller.start_link(endpoint_id: "self::controller")
      assert Controller.list_agents(controller) == []
    end
  end

  describe "handle_agent_message/3 - Register" do
    setup do
      {:ok, controller} = Controller.start_link(endpoint_id: "self::controller")
      {:ok, controller: controller}
    end

    test "handles Register message", %{controller: controller} do
      register_msg = Proto.build_register(["Device."])
      agent_id = "os::ACME-Router-12345"

      {:ok, response} = Controller.handle_agent_message(controller, agent_id, register_msg)

      assert response.header.msg_type == :REGISTER_RESP
      assert agent_id in Controller.list_agents(controller)
    end
  end

  describe "handle_agent_message/3 - Notify" do
    setup do
      {:ok, controller} = Controller.start_link(endpoint_id: "self::controller")
      agent_id = "os::ACME-Router-12345"

      # Register the agent first
      register_msg = Proto.build_register(["Device."])
      {:ok, _} = Controller.handle_agent_message(controller, agent_id, register_msg)

      {:ok, controller: controller, agent_id: agent_id}
    end

    test "handles ValueChange notification", %{controller: controller, agent_id: agent_id} do
      notify_msg = Proto.build_notify_value_change(
        "sub-1",
        "Device.DeviceInfo.SoftwareVersion",
        "2.0.0",
        send_resp: true
      )

      {:ok, response} = Controller.handle_agent_message(controller, agent_id, notify_msg)

      assert response.header.msg_type == :NOTIFY_RESP
    end

    test "handles Event notification without response", %{controller: controller, agent_id: agent_id} do
      notify_msg = Proto.build_notify_event(
        "sub-2",
        "Device.",
        "Boot!",
        %{},
        send_resp: false
      )

      {:ok, response} = Controller.handle_agent_message(controller, agent_id, notify_msg)

      assert response == nil
    end
  end

  describe "handle_agent_record/2" do
    setup do
      {:ok, controller} = Controller.start_link(endpoint_id: "self::controller")
      {:ok, controller: controller}
    end

    test "handles a record and returns a response record", %{controller: controller} do
      register_msg = Proto.build_register(["Device."])
      agent_id = "os::ACME-Router-12345"

      record = Record.new(register_msg,
        to_id: "self::controller",
        from_id: agent_id
      )

      {:ok, response_record} = Controller.handle_agent_record(controller, record)

      assert response_record.to_id == agent_id
      assert response_record.from_id == "self::controller"

      {:ok, response_msg} = Record.extract_message(response_record)
      assert response_msg.header.msg_type == :REGISTER_RESP
    end
  end

  describe "queue_get/3" do
    setup do
      {:ok, controller} = Controller.start_link(endpoint_id: "self::controller")
      agent_id = "os::ACME-Router-12345"
      {:ok, controller: controller, agent_id: agent_id}
    end

    test "queues a Get request", %{controller: controller, agent_id: agent_id} do
      {:ok, msg_id} = Controller.queue_get(controller, agent_id, ["Device.DeviceInfo."])

      assert is_binary(msg_id)
      assert String.starts_with?(msg_id, "msg-")
    end

    test "next_command returns queued message", %{controller: controller, agent_id: agent_id} do
      {:ok, _msg_id} = Controller.queue_get(controller, agent_id, ["Device.DeviceInfo."])

      {:ok, msg} = Controller.next_command(controller, agent_id)

      assert msg.header.msg_type == :GET
    end

    test "next_command returns empty when queue is empty", %{controller: controller, agent_id: agent_id} do
      # Register agent first
      register_msg = Proto.build_register(["Device."])
      {:ok, _} = Controller.handle_agent_message(controller, agent_id, register_msg)

      {:empty, nil} = Controller.next_command(controller, agent_id)
    end
  end

  describe "get_agent/2" do
    setup do
      {:ok, controller} = Controller.start_link(endpoint_id: "self::controller")
      {:ok, controller: controller}
    end

    test "returns error for unknown agent", %{controller: controller} do
      assert {:error, :not_found} = Controller.get_agent(controller, "unknown")
    end

    test "returns agent info for registered agent", %{controller: controller} do
      agent_id = "os::ACME-Router-12345"
      register_msg = Proto.build_register(["Device."])
      {:ok, _} = Controller.handle_agent_message(controller, agent_id, register_msg)

      {:ok, info} = Controller.get_agent(controller, agent_id)

      assert info.agent_id == agent_id
      assert info.connected_at
    end
  end

  describe "Controller-Agent integration" do
    test "agent can respond to controller request" do
      # Start controller
      {:ok, controller} = Controller.start_link(endpoint_id: "self::controller")

      # Start agent
      {:ok, agent} = Agent.start_link(
        endpoint_id: "os::ACME-Router-12345",
        initial_params: %{
          "Device" => %{
            "DeviceInfo" => %{"Manufacturer" => "TestCorp"}
          }
        }
      )

      agent_id = Agent.endpoint_id(agent)

      # Agent registers with controller
      register_msg = Agent.build_register_message(agent)
      {:ok, register_resp} = Controller.handle_agent_message(controller, agent_id, register_msg)
      assert register_resp.header.msg_type == :REGISTER_RESP

      # Controller queues a Get request
      {:ok, _msg_id} = Controller.queue_get(controller, agent_id, ["Device.DeviceInfo.Manufacturer"])

      # Agent retrieves and processes the queued command
      {:ok, get_msg} = Controller.next_command(controller, agent_id)
      {:ok, get_resp} = Agent.handle_message(agent, get_msg)

      # Agent sends response back to controller
      {:ok, _} = Controller.handle_agent_message(controller, agent_id, get_resp)

      # Verify the response was a GetResp
      assert get_resp.header.msg_type == :GET_RESP
    end
  end
end
