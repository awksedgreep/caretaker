defmodule Caretaker.TR069.RPC.GetParameterNamesTest do
  use ExUnit.Case, async: true

  alias Caretaker.TR069.RPC.GetParameterNames

  test "encode and decode request" do
    req = GetParameterNames.new("Device.", true)
    assert {:ok, body} = GetParameterNames.encode(req)
    xml = IO.iodata_to_binary(body)
    assert xml =~ "<cwmp:GetParameterNames>"
    assert xml =~ "<ParameterPath>Device.</ParameterPath>"
    assert xml =~ "<NextLevel>1</NextLevel>"

    assert {:ok, ^req} = GetParameterNames.decode(xml)
  end
end
