defmodule Caretaker.TR069.RPC.InformResponseTest do
  use ExUnit.Case, async: true

  alias Caretaker.TR069.RPC.InformResponse

  test "new/1 default and encode/decode" do
    resp = InformResponse.new([])
    assert %InformResponse{max_envelopes: 1} = resp

    assert {:ok, body} = InformResponse.encode(resp)
    xml = IO.iodata_to_binary(body)
    assert xml =~ "<cwmp:InformResponse>"
    assert xml =~ "<MaxEnvelopes>1</MaxEnvelopes>"

    assert {:ok, %InformResponse{max_envelopes: 1}} = InformResponse.decode(xml)
  end

  test "encode custom max_envelopes" do
    assert {:ok, body} = InformResponse.encode(%InformResponse{max_envelopes: 5})
    assert IO.iodata_to_binary(body) =~ "<MaxEnvelopes>5</MaxEnvelopes>"
  end
end
