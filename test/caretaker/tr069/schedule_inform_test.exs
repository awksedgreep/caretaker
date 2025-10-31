defmodule Caretaker.TR069.ScheduleInformTest do
  use ExUnit.Case, async: true

  alias Caretaker.CWMP.SOAP
  alias Caretaker.TR069.RPC.{ScheduleInform, ScheduleInformResponse}

  test "ScheduleInform encode/decode and response" do
    s = ScheduleInform.new(delay_seconds: 120, command_key: "CKS")
    {:ok, body} = ScheduleInform.encode(s)
    {:ok, env} = SOAP.encode_envelope(body, %{id: "SI1"})
    {:ok, %{body: %{rpc: "ScheduleInform", xml: xml}}} = SOAP.decode_envelope(IO.iodata_to_binary(env))
    assert {:ok, %ScheduleInform{delay_seconds: 120, command_key: "CKS"}} = ScheduleInform.decode(xml)

    {:ok, body2} = ScheduleInformResponse.encode(%ScheduleInformResponse{})
    {:ok, env2} = SOAP.encode_envelope(body2, %{id: "SI2"})
    {:ok, %{body: %{rpc: "ScheduleInformResponse", xml: xml2}}} = SOAP.decode_envelope(IO.iodata_to_binary(env2))
    assert {:ok, %ScheduleInformResponse{}} = ScheduleInformResponse.decode(xml2)
  end
end