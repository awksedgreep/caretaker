defmodule Caretaker.USP.AgentTest do
  use ExUnit.Case, async: true

  alias Caretaker.USP.{Agent, Proto, Record}

  describe "start_link/1" do
    test "starts an agent with endpoint ID" do
      {:ok, agent} = Agent.start_link(endpoint_id: "os::ACME-Router-12345")
      assert Agent.endpoint_id(agent) == "os::ACME-Router-12345"
    end

    test "starts an agent with initial parameters" do
      {:ok, agent} = Agent.start_link(
        endpoint_id: "os::ACME-Router-12345",
        initial_params: %{
          "Device" => %{
            "DeviceInfo" => %{
              "Manufacturer" => "TestCorp"
            }
          }
        }
      )

      state = Agent.get_state(agent)
      assert state["DeviceInfo"]["Manufacturer"] == "TestCorp"
    end
  end

  describe "handle_message/2 - Get" do
    setup do
      {:ok, agent} = Agent.start_link(
        endpoint_id: "os::ACME-Router-12345",
        initial_params: %{
          "Device" => %{
            "DeviceInfo" => %{
              "Manufacturer" => "Acme",
              "ModelName" => "SuperRouter",
              "SoftwareVersion" => "1.0.0"
            }
          }
        }
      )
      {:ok, agent: agent}
    end

    test "handles Get request", %{agent: agent} do
      get_msg = Proto.build_get(["Device.DeviceInfo.Manufacturer"])

      {:ok, response} = Agent.handle_message(agent, get_msg)

      assert response.header.msg_type == :GET_RESP
      assert Proto.response?(response)
    end

    test "handles Get request for tree", %{agent: agent} do
      get_msg = Proto.build_get(["Device.DeviceInfo."])

      {:ok, response} = Agent.handle_message(agent, get_msg)

      assert response.header.msg_type == :GET_RESP
    end
  end

  describe "handle_message/2 - Set" do
    setup do
      {:ok, agent} = Agent.start_link(
        endpoint_id: "os::ACME-Router-12345",
        initial_params: %{
          "Device" => %{
            "DeviceInfo" => %{
              "SoftwareVersion" => "1.0.0"
            }
          }
        }
      )
      {:ok, agent: agent}
    end

    test "handles Set request", %{agent: agent} do
      set_msg = Proto.build_set([
        {"Device.DeviceInfo.", [SoftwareVersion: "2.0.0"]}
      ])

      {:ok, response} = Agent.handle_message(agent, set_msg)

      assert response.header.msg_type == :SET_RESP
    end
  end

  describe "handle_message/2 - Add" do
    setup do
      {:ok, agent} = Agent.start_link(endpoint_id: "os::ACME-Router-12345")
      {:ok, agent: agent}
    end

    test "handles Add request", %{agent: agent} do
      add_msg = Proto.build_add([
        {"Device.NAT.PortMapping.", [ExternalPort: "8080"]}
      ])

      {:ok, response} = Agent.handle_message(agent, add_msg)

      assert response.header.msg_type == :ADD_RESP
    end
  end

  describe "handle_message/2 - Delete" do
    setup do
      {:ok, agent} = Agent.start_link(endpoint_id: "os::ACME-Router-12345")
      {:ok, agent: agent}
    end

    test "handles Delete request", %{agent: agent} do
      delete_msg = Proto.build_delete(["Device.NAT.PortMapping.1."])

      {:ok, response} = Agent.handle_message(agent, delete_msg)

      assert response.header.msg_type == :DELETE_RESP
    end
  end

  describe "handle_message/2 - Operate" do
    setup do
      {:ok, agent} = Agent.start_link(endpoint_id: "os::ACME-Router-12345")
      {:ok, agent: agent}
    end

    test "handles Operate request", %{agent: agent} do
      operate_msg = Proto.build_operate(
        "Device.IP.Diagnostics.IPPing()",
        %{Host: "8.8.8.8"}
      )

      {:ok, response} = Agent.handle_message(agent, operate_msg)

      assert response.header.msg_type == :OPERATE_RESP
    end
  end

  describe "handle_message/2 - GetSupportedDM" do
    setup do
      {:ok, agent} = Agent.start_link(endpoint_id: "os::ACME-Router-12345")
      {:ok, agent: agent}
    end

    test "handles GetSupportedDM request", %{agent: agent} do
      msg = Proto.build_get_supported_dm(["Device."])

      {:ok, response} = Agent.handle_message(agent, msg)

      assert response.header.msg_type == :GET_SUPPORTED_DM_RESP
    end
  end

  describe "handle_message/2 - GetInstances" do
    setup do
      {:ok, agent} = Agent.start_link(endpoint_id: "os::ACME-Router-12345")
      {:ok, agent: agent}
    end

    test "handles GetInstances request", %{agent: agent} do
      msg = Proto.build_get_instances(["Device.WiFi.SSID."])

      {:ok, response} = Agent.handle_message(agent, msg)

      assert response.header.msg_type == :GET_INSTANCES_RESP
    end
  end

  describe "handle_record/2" do
    setup do
      {:ok, agent} = Agent.start_link(
        endpoint_id: "os::ACME-Router-12345",
        initial_params: %{
          "Device" => %{
            "DeviceInfo" => %{"Manufacturer" => "Acme"}
          }
        }
      )
      {:ok, agent: agent}
    end

    test "handles a record and returns a response record", %{agent: agent} do
      get_msg = Proto.build_get(["Device.DeviceInfo."])
      record = Record.new(get_msg,
        to_id: "os::ACME-Router-12345",
        from_id: "self::controller"
      )

      {:ok, response_record} = Agent.handle_record(agent, record)

      assert response_record.to_id == "self::controller"
      assert response_record.from_id == "os::ACME-Router-12345"

      {:ok, response_msg} = Record.extract_message(response_record)
      assert response_msg.header.msg_type == :GET_RESP
    end
  end

  describe "connect/2 and disconnect/1" do
    setup do
      {:ok, agent} = Agent.start_link(endpoint_id: "os::ACME-Router-12345")
      {:ok, agent: agent}
    end

    test "connects and disconnects", %{agent: agent} do
      assert :ok = Agent.connect(agent, "self::controller")
      assert :ok = Agent.disconnect(agent)
    end
  end

  describe "build_register_message/1" do
    setup do
      {:ok, agent} = Agent.start_link(endpoint_id: "os::ACME-Router-12345")
      {:ok, agent: agent}
    end

    test "builds a Register message", %{agent: agent} do
      msg = Agent.build_register_message(agent)

      assert msg.header.msg_type == :REGISTER
      assert Proto.request?(msg)
    end
  end

  describe "set_parameter/3" do
    setup do
      {:ok, agent} = Agent.start_link(
        endpoint_id: "os::ACME-Router-12345",
        initial_params: %{
          "Device" => %{
            "DeviceInfo" => %{"SoftwareVersion" => "1.0.0"}
          }
        }
      )
      {:ok, agent: agent}
    end

    test "sets a parameter", %{agent: agent} do
      assert :ok = Agent.set_parameter(agent, "Device.DeviceInfo.SoftwareVersion", "2.0.0")
    end
  end
end
