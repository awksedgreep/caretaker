defmodule Caretaker.USP.MQTT.IntegrationTest do
  @moduledoc """
  Integration tests for USP over MQTT transport.

  These tests verify the MQTT transport layer components work correctly.
  Full end-to-end MQTT tests require an external MQTT broker (e.g., Mosquitto)
  due to protocol compatibility issues between Nipper and Tortoise311.
  """

  use ExUnit.Case, async: true

  alias Caretaker.USP.{Proto, Record}
  alias Caretaker.USP.Transport.MQTT.Topics

  describe "USP message encoding for MQTT transport" do
    test "messages are correctly encoded/decoded for MQTT transport" do
      # Build a Get message
      get_msg = Proto.build_get(["Device.DeviceInfo."], [])
      msg_id = Proto.message_id(get_msg)

      # Wrap in a Record with endpoint IDs
      record =
        Record.new(get_msg,
          to_id: "os::test-agent",
          from_id: "self::test-controller"
        )

      # Encode the record (this is what gets sent over MQTT)
      {:ok, encoded} = Record.encode(record)
      assert is_binary(encoded)
      assert byte_size(encoded) > 0

      # Decode it back (this is what the receiver does)
      {:ok, decoded_record} = Record.decode(encoded)
      assert decoded_record.to_id == "os::test-agent"
      assert decoded_record.from_id == "self::test-controller"

      # Extract the message
      {:ok, decoded_msg} = Record.extract_message(decoded_record)
      assert Proto.message_id(decoded_msg) == msg_id
    end

    test "Set message encodes correctly for MQTT" do
      # build_set expects [{obj_path, [{param, value}, ...]}]
      set_msg = Proto.build_set([{"Device.WiFi.", [{"SSID", "TestNetwork"}]}], [])
      msg_id = Proto.message_id(set_msg)

      record =
        Record.new(set_msg,
          to_id: "os::router-001",
          from_id: "self::acs-server"
        )

      {:ok, encoded} = Record.encode(record)
      {:ok, decoded_record} = Record.decode(encoded)
      {:ok, decoded_msg} = Record.extract_message(decoded_record)

      assert Proto.message_id(decoded_msg) == msg_id
    end

    test "Notify message encodes correctly for MQTT" do
      notify_msg = Proto.build_notify_value_change(
        "subscription-1",
        "Device.DeviceInfo.SoftwareVersion",
        "2.0.0"
      )

      record =
        Record.new(notify_msg,
          to_id: "self::controller",
          from_id: "os::agent-123"
        )

      {:ok, encoded} = Record.encode(record)
      {:ok, decoded_record} = Record.decode(encoded)

      assert decoded_record.from_id == "os::agent-123"
      assert decoded_record.to_id == "self::controller"
    end
  end

  describe "MQTT topic structure" do
    test "agent request topic follows USP MQTT binding specification" do
      agent_id = "os::ACME-Router-123"

      assert Topics.agent_request(agent_id) == "usp/agent/os::ACME-Router-123/request"
    end

    test "agent notify topic follows USP MQTT binding specification" do
      agent_id = "os::ACME-Router-123"

      assert Topics.agent_notify(agent_id) == "usp/agent/os::ACME-Router-123/notify"
    end

    test "controller request topic follows USP MQTT binding specification" do
      controller_id = "self::acs.example.com"

      assert Topics.controller_request(controller_id) ==
               "usp/controller/self::acs.example.com/request"
    end

    test "controller notify subscription uses wildcard" do
      assert Topics.controller_notify_subscription() == "usp/agent/+/notify"
    end

    test "parses agent endpoint from topic" do
      {:ok, {:agent, agent_id}} =
        Topics.parse_endpoint_from_topic("usp/agent/os::device-123/request")

      assert agent_id == "os::device-123"
    end

    test "parses controller endpoint from topic" do
      {:ok, {:controller, controller_id}} =
        Topics.parse_endpoint_from_topic("usp/controller/self::acs/request")

      assert controller_id == "self::acs"
    end

    test "returns error for invalid topic" do
      assert {:error, :invalid_topic} = Topics.parse_endpoint_from_topic("invalid/topic")
    end

    test "validates topic format" do
      assert Topics.valid_topic?("usp/agent/os::test/request")
      assert Topics.valid_topic?("usp/controller/self::acs/request")
      refute Topics.valid_topic?("invalid/topic/format")
    end

    test "response_topic_for returns correct topic" do
      # When agent receives from controller, response goes to controller
      response_topic = Topics.response_topic_for(
        "usp/controller/self::acs/request",
        "os::device-123"
      )
      assert response_topic == "usp/agent/os::device-123/request"

      # When controller receives from agent, response goes to agent
      response_topic = Topics.response_topic_for(
        "usp/agent/os::device-123/request",
        "self::acs"
      )
      assert response_topic == "usp/controller/self::acs/request"
    end
  end

  describe "MQTT transport module structure" do
    test "Agent transport module is loaded and has expected functions" do
      alias Caretaker.USP.Transport.MQTT.Agent

      # Verify module is loaded
      assert Code.ensure_loaded?(Agent)

      # Check functions exist (start_link/1, register/1, notify/2, disconnect/1)
      exports = Agent.__info__(:functions)
      assert {:start_link, 1} in exports
      assert {:register, 1} in exports
      assert {:notify, 2} in exports
      assert {:disconnect, 1} in exports
    end

    test "Controller transport module is loaded and has expected functions" do
      alias Caretaker.USP.Transport.MQTT.Controller

      # Verify module is loaded
      assert Code.ensure_loaded?(Controller)

      # Check functions exist
      exports = Controller.__info__(:functions)
      assert {:start_link, 1} in exports
      # get/set have default args, so they appear with lower arities too
      assert {:disconnect, 1} in exports
      assert {:send_message, 3} in exports
    end

    test "Handler module implements Tortoise311.Handler behaviour" do
      alias Caretaker.USP.Transport.MQTT.Handler

      # Check that the module uses the Handler behaviour
      behaviours = Handler.__info__(:attributes)[:behaviour] || []
      assert Tortoise311.Handler in behaviours
    end
  end
end
