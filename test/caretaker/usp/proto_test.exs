defmodule Caretaker.USP.ProtoTest do
  use ExUnit.Case, async: true

  alias Caretaker.USP.Proto
  alias Caretaker.Proto.Usp.{Msg, Header, Body, Request, Get}

  describe "build_get/2" do
    test "creates a Get request with parameter paths" do
      msg = Proto.build_get(["Device.DeviceInfo.Manufacturer", "Device.DeviceInfo.ModelName"])

      assert %Msg{} = msg
      assert msg.header.msg_type == :GET
      assert is_binary(msg.header.msg_id)

      {:request, %Request{req_type: {:get, get}}} = msg.body.msg_body
      assert get.param_paths == ["Device.DeviceInfo.Manufacturer", "Device.DeviceInfo.ModelName"]
    end

    test "accepts custom message ID" do
      msg = Proto.build_get(["Device."], msg_id: "test-123")

      assert msg.header.msg_id == "test-123"
    end

    test "accepts max_depth option" do
      msg = Proto.build_get(["Device."], max_depth: 2)

      {:request, %Request{req_type: {:get, get}}} = msg.body.msg_body
      assert get.max_depth == 2
    end
  end

  describe "build_set/2" do
    test "creates a Set request with updates" do
      msg =
        Proto.build_set([
          {"Device.WiFi.SSID.1.", [SSID: "TestNetwork", Enable: "true"]}
        ])

      assert msg.header.msg_type == :SET

      {:request, %Request{req_type: {:set, set}}} = msg.body.msg_body
      assert length(set.update_objs) == 1

      [update_obj] = set.update_objs
      assert update_obj.obj_path == "Device.WiFi.SSID.1."
      assert length(update_obj.param_settings) == 2
    end

    test "accepts allow_partial option" do
      msg = Proto.build_set([{"Device.", []}], allow_partial: true)

      {:request, %Request{req_type: {:set, set}}} = msg.body.msg_body
      assert set.allow_partial == true
    end
  end

  describe "build_add/2" do
    test "creates an Add request" do
      msg =
        Proto.build_add([
          {"Device.NAT.PortMapping.", [ExternalPort: "8080", InternalPort: "80"]}
        ])

      assert msg.header.msg_type == :ADD

      {:request, %Request{req_type: {:add, add}}} = msg.body.msg_body
      assert length(add.create_objs) == 1
    end
  end

  describe "build_delete/2" do
    test "creates a Delete request" do
      msg = Proto.build_delete(["Device.NAT.PortMapping.1."])

      assert msg.header.msg_type == :DELETE

      {:request, %Request{req_type: {:delete, delete}}} = msg.body.msg_body
      assert delete.obj_paths == ["Device.NAT.PortMapping.1."]
    end
  end

  describe "build_operate/3" do
    test "creates an Operate request" do
      msg =
        Proto.build_operate(
          "Device.IP.Diagnostics.IPPing()",
          %{Host: "8.8.8.8", NumberOfRepetitions: "4"}
        )

      assert msg.header.msg_type == :OPERATE

      {:request, %Request{req_type: {:operate, operate}}} = msg.body.msg_body
      assert operate.command == "Device.IP.Diagnostics.IPPing()"
      assert operate.input_args["Host"] == "8.8.8.8"
    end
  end

  describe "build_error/3" do
    test "creates an Error message" do
      msg = Proto.build_error(7000, "Message failed")

      assert msg.header.msg_type == :ERROR

      {:error, error} = msg.body.msg_body
      assert error.err_code == 7000
      assert error.err_msg == "Message failed"
    end
  end

  describe "encode/1 and decode/1" do
    test "round-trips a Get message" do
      original = Proto.build_get(["Device.DeviceInfo."], msg_id: "test-roundtrip")

      assert {:ok, binary} = Proto.encode(original)
      assert is_binary(binary)
      assert byte_size(binary) > 0

      assert {:ok, decoded} = Proto.decode(binary)
      assert decoded.header.msg_id == "test-roundtrip"
      assert decoded.header.msg_type == :GET
    end

    test "round-trips a Set message" do
      original =
        Proto.build_set(
          [
            {"Device.WiFi.SSID.1.", [SSID: "TestNetwork"]}
          ],
          msg_id: "set-test"
        )

      assert {:ok, binary} = Proto.encode(original)
      assert {:ok, decoded} = Proto.decode(binary)

      assert decoded.header.msg_id == "set-test"
      assert decoded.header.msg_type == :SET
    end
  end

  describe "wrap_in_record/2 and unwrap_from_record/1" do
    test "wraps and unwraps a message in a record" do
      msg = Proto.build_get(["Device."], msg_id: "record-test")

      record =
        Proto.wrap_in_record(msg,
          to_id: "os::agent-123",
          from_id: "self::controller"
        )

      assert record.version == "1.3"
      assert record.to_id == "os::agent-123"
      assert record.from_id == "self::controller"
      assert record.payload_security == :PLAINTEXT

      assert {:ok, unwrapped} = Proto.unwrap_from_record(record)
      assert unwrapped.header.msg_id == "record-test"
    end

    test "encodes and decodes record" do
      msg = Proto.build_get(["Device.DeviceInfo."])
      record = Proto.wrap_in_record(msg, to_id: "agent", from_id: "controller")

      assert {:ok, binary} = Proto.encode_record(record)
      assert {:ok, decoded_record} = Proto.decode_record(binary)

      assert decoded_record.to_id == "agent"
      assert decoded_record.from_id == "controller"

      assert {:ok, decoded_msg} = Proto.unwrap_from_record(decoded_record)
      assert decoded_msg.header.msg_type == :GET
    end
  end

  describe "message helpers" do
    test "message_type/1 returns the message type" do
      get_msg = Proto.build_get(["Device."])
      set_msg = Proto.build_set([{"Device.", []}])

      assert Proto.message_type(get_msg) == :GET
      assert Proto.message_type(set_msg) == :SET
    end

    test "message_id/1 returns the message ID" do
      msg = Proto.build_get(["Device."], msg_id: "my-id")

      assert Proto.message_id(msg) == "my-id"
    end

    test "request?/1 identifies request messages" do
      get_msg = Proto.build_get(["Device."])
      error_msg = Proto.build_error(7000, "Error")

      assert Proto.request?(get_msg) == true
      assert Proto.request?(error_msg) == false
    end

    test "error?/1 identifies error messages" do
      get_msg = Proto.build_get(["Device."])
      error_msg = Proto.build_error(7000, "Error")

      assert Proto.error?(get_msg) == false
      assert Proto.error?(error_msg) == true
    end
  end

  describe "generate_msg_id/0" do
    test "generates unique IDs" do
      id1 = Proto.generate_msg_id()
      id2 = Proto.generate_msg_id()

      assert is_binary(id1)
      assert is_binary(id2)
      assert id1 != id2
      assert String.starts_with?(id1, "msg-")
    end
  end
end
