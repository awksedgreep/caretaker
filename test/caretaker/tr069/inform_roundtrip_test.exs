defmodule Caretaker.TR069.InformRoundtripTest do
  use ExUnit.Case

  alias Caretaker.CWMP.SOAP
  alias Caretaker.TR069.RPC.{Inform, InformResponse}
  alias Caretaker.PubSub

  @fixtures Path.join([__DIR__, "../../fixtures/tr069"]) |> Path.expand()

  test "decode Inform, publish to PubSub, and respond with InformResponse" do
    xml = File.read!(Path.join(@fixtures, "inform.xml"))

    assert {:ok, %{header: %{id: id, cwmp_ns: ns}, body: %{rpc: "Inform", xml: body_xml}}} =
             SOAP.decode_envelope(xml)

    assert id == "ID123"
    assert ns == "urn:dslforum-org:cwmp-1-0"

    assert {:ok, inform} = Inform.decode(body_xml)

    # PubSub: subscribe and broadcast inform
    start_supervised!(Caretaker.PubSub)
    PubSub.subscribe(PubSub.topic_tr069_inform())
    :ok = PubSub.broadcast(PubSub.topic_tr069_inform(), inform)

    # Receive pubsub message
    assert_receive {:pubsub, :tr069_inform, %Inform{} = got}, 100
    assert got.device_id.oui == "A1B2C3"

    # Build InformResponse and envelope echoing ID
    {:ok, body} = InformResponse.encode(%InformResponse{max_envelopes: 1})
    {:ok, resp_xml} = SOAP.encode_envelope(body, %{id: id, cwmp_ns: ns})
    resp_bin = IO.iodata_to_binary(resp_xml)

    expected = File.read!(Path.join(@fixtures, "inform_response.xml"))
    assert resp_bin =~ "<cwmp:InformResponse>"
    assert resp_bin =~ "<MaxEnvelopes>1</MaxEnvelopes>"
    assert resp_bin =~ "<cwmp:ID mustUnderstand=\"1\">ID123</cwmp:ID>"
    assert resp_bin =~ "xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\""

    # Loose comparison due to whitespace/attribute order differences
    for token <- ["Envelope", "Body", "InformResponse", "MaxEnvelopes"] do
      assert String.contains?(resp_bin, token)
      assert String.contains?(expected, token)
    end
  end
end
