defmodule Caretaker.USP.WebSocket.IntegrationTest do
  @moduledoc """
  Integration tests for USP over WebSocket transport.

  These tests verify the WebSocket transport layer components work correctly.
  """

  use ExUnit.Case, async: true

  alias Caretaker.USP.{Proto, Record}
  alias Caretaker.USP.Transport.WebSocket.Paths

  describe "USP message encoding for WebSocket transport" do
    test "messages are correctly encoded/decoded for WebSocket transport" do
      # Build a Get message
      get_msg = Proto.build_get(["Device.DeviceInfo."], [])
      msg_id = Proto.message_id(get_msg)

      # Wrap in a Record with endpoint IDs
      record =
        Record.new(get_msg,
          to_id: "os::test-agent",
          from_id: "self::test-controller"
        )

      # Encode the record (this is what gets sent as binary WebSocket frame)
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

    test "Set message encodes correctly for WebSocket" do
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

    test "Notify message encodes correctly for WebSocket" do
      notify_msg =
        Proto.build_notify_value_change(
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

    test "WebSocket connect record encodes correctly" do
      connect_record = Record.new_websocket_connect(from_id: "os::agent-123")

      {:ok, encoded} = Record.encode(connect_record)
      {:ok, decoded} = Record.decode(encoded)

      assert decoded.from_id == "os::agent-123"
    end
  end

  describe "WebSocket path structure" do
    test "controller path follows USP WebSocket binding specification" do
      controller_id = "self::acs.example.com"

      assert Paths.controller_path(controller_id) ==
               "/usp/controller/self::acs.example.com"
    end

    test "agent path follows USP WebSocket binding specification" do
      agent_id = "os::ACME-Router-123"

      assert Paths.agent_path(agent_id) == "/usp/agent/os::ACME-Router-123"
    end

    test "controller URL is built correctly" do
      url = Paths.controller_url("localhost", 8080, "self::acs")
      assert url == "ws://localhost:8080/usp/controller/self::acs"

      secure_url = Paths.controller_url("acs.example.com", 443, "self::acs", secure: true)
      assert secure_url == "wss://acs.example.com:443/usp/controller/self::acs"
    end

    test "agent URL is built correctly" do
      url = Paths.agent_url("localhost", 8080, "os::device-123")
      assert url == "ws://localhost:8080/usp/agent/os::device-123"

      secure_url = Paths.agent_url("device.local", 443, "os::device-123", secure: true)
      assert secure_url == "wss://device.local:443/usp/agent/os::device-123"
    end

    test "parses agent endpoint from path" do
      {:ok, {:agent, agent_id}} =
        Paths.parse_endpoint_from_path("/usp/agent/os::device-123")

      assert agent_id == "os::device-123"
    end

    test "parses controller endpoint from path" do
      {:ok, {:controller, controller_id}} =
        Paths.parse_endpoint_from_path("/usp/controller/self::acs")

      assert controller_id == "self::acs"
    end

    test "returns error for invalid path" do
      assert {:error, :invalid_path} = Paths.parse_endpoint_from_path("/invalid/path")
    end

    test "validates path format" do
      assert Paths.valid_path?("/usp/agent/os::test")
      assert Paths.valid_path?("/usp/controller/self::acs")
      refute Paths.valid_path?("/invalid/path/format")
      refute Paths.valid_path?("/usp/unknown/os::test")
    end

    test "returns USP WebSocket subprotocol" do
      assert Paths.subprotocol() == "v1.usp"
    end

    test "checks for USP subprotocol in list" do
      assert Paths.has_usp_subprotocol?(["v1.usp", "other"])
      assert Paths.has_usp_subprotocol?(["v1.usp"])
      refute Paths.has_usp_subprotocol?(["other", "another"])
      refute Paths.has_usp_subprotocol?([])
    end
  end

  describe "WebSocket transport module structure" do
    test "Server module is loaded and has expected functions" do
      alias Caretaker.USP.Transport.WebSocket.Server

      assert Code.ensure_loaded?(Server)

      exports = Server.__info__(:functions)
      assert {:start_link, 1} in exports
      assert {:stop, 1} in exports
      assert {:connected_agents, 1} in exports
    end

    test "Client module is loaded and has expected functions" do
      alias Caretaker.USP.Transport.WebSocket.Client

      assert Code.ensure_loaded?(Client)

      exports = Client.__info__(:functions)
      assert {:start_link, 1} in exports
      assert {:register, 1} in exports
      assert {:notify, 2} in exports
      assert {:disconnect, 1} in exports
      assert {:connected?, 1} in exports
    end

    test "Handler module implements WebSock behaviour" do
      alias Caretaker.USP.Transport.WebSocket.Handler

      assert Code.ensure_loaded?(Handler)

      behaviours = Handler.__info__(:attributes)[:behaviour] || []
      assert WebSock in behaviours
    end

    test "Paths module has path prefix" do
      assert Paths.prefix() == "/usp"
    end
  end

  describe "WebSocket vs MQTT path comparison" do
    test "WebSocket and MQTT use similar endpoint ID format" do
      agent_id = "os::ACME-Router-123"
      controller_id = "self::acs.example.com"

      # Both use the same endpoint ID format
      ws_agent_path = Paths.agent_path(agent_id)
      ws_controller_path = Paths.controller_path(controller_id)

      mqtt_topics = Caretaker.USP.Transport.MQTT.Topics

      mqtt_agent_topic = mqtt_topics.agent_request(agent_id)
      mqtt_controller_topic = mqtt_topics.controller_request(controller_id)

      # Both extract the same endpoint ID
      {:ok, {:agent, ^agent_id}} = Paths.parse_endpoint_from_path(ws_agent_path)
      {:ok, {:agent, ^agent_id}} = mqtt_topics.parse_endpoint_from_topic(mqtt_agent_topic)

      {:ok, {:controller, ^controller_id}} = Paths.parse_endpoint_from_path(ws_controller_path)
      {:ok, {:controller, ^controller_id}} = mqtt_topics.parse_endpoint_from_topic(mqtt_controller_topic)
    end
  end
end
