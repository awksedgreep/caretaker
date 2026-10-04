defmodule Caretaker.ACS.GetRPCMethodsTest do
  use ExUnit.Case, async: false

  import Plug.Test
  import ExUnit.CaptureLog

  alias Caretaker.ACS.{Server, Session, Tasks}
  alias Caretaker.CWMP.SOAP
  alias Caretaker.HTTP.Auth, as: ClientAuth

  alias Caretaker.TR069.RPC.{
    GetParameterValues,
    GetParameterValuesResponse,
    GetRPCMethodsResponse
  }

  @discovery File.read!(Path.join(__DIR__, "fixtures/tr069/get_rpc_methods.xml"))
  @inform File.read!(Path.join(__DIR__, "fixtures/tr069/inform.xml"))
  @methods ["Inform", "GetRPCMethods", "TransferComplete"]
  @device %{oui: "A1B2C3", product_class: "Router", serial_number: "XYZ123"}
  @namespace "urn:dslforum-org:cwmp-1-1"

  test "discovery echoes the ID and all supported CWMP namespaces without authentication" do
    for version <- 0..4 do
      namespace = "urn:dslforum-org:cwmp-1-#{version}"
      request = String.replace(@discovery, @namespace, namespace)
      response = post(request)

      assert response.status == 200
      assert Plug.Conn.get_resp_header(response, "content-type") == [SOAP.content_type()]
      assert_discovery_response(response.resp_body, namespace)
    end
  end

  test "discovery defaults an unknown CWMP namespace to 1-0" do
    request = String.replace(@discovery, @namespace, "urn:dslforum-org:cwmp-1-99")
    response = post(request)
    assert response.status == 200
    assert_discovery_response(response.resp_body, "urn:dslforum-org:cwmp-1-0")
  end

  test "Inform, discovery and polling preserve a queued task through acknowledgment" do
    start_supervised!(Caretaker.PubSub)
    start_supervised!(Session)
    start_supervised!(Tasks)

    path = "Device.DeviceInfo.Manufacturer"
    {:ok, task_id} = Tasks.submit_get(@device, [path])
    {:ok, %{cwmp_id: task_cwmp_id, state: :queued}} = Tasks.get(task_id)

    inform = post(String.replace(@inform, "urn:dslforum-org:cwmp-1-0", @namespace))
    assert inform.status == 200
    assert {:ok, %{body: %{rpc: "InformResponse"}}} = SOAP.decode_envelope(inform.resp_body)
    sid = inform.resp_cookies["caretaker_sid"].value

    # Change the peer address so subsequent requests must use the session cookie.
    options = [sid: sid, remote_ip: {192, 0, 2, 7}]
    assert {:ok, %{state: :queued}} = Tasks.get(task_id)
    discovery = post(@discovery, options)
    assert discovery.status == 200
    assert_discovery_response(discovery.resp_body, @namespace)
    assert {:ok, %{state: :queued, delivered_at: nil, completed_at: nil}} = Tasks.get(task_id)

    command = post("", options)
    assert command.status == 200

    assert {:ok,
            %{
              header: %{id: ^task_cwmp_id, cwmp_ns: @namespace},
              body: %{rpc: "GetParameterValues", xml: xml}
            }} =
             SOAP.decode_envelope(command.resp_body)

    assert {:ok, %{names: [^path]}} = GetParameterValues.decode(xml)
    assert {:ok, %{state: :delivered}} = Tasks.get(task_id)

    {:ok, body} =
      GetParameterValuesResponse.encode(%{
        parameters: [%{name: path, value: "Acme", type: "xsd:string"}]
      })

    {:ok, acknowledgment} = SOAP.encode_envelope(body, %{id: task_cwmp_id, cwmp_ns: @namespace})
    probe = post(acknowledgment, options)

    assert {:ok, %{state: :applied, result: %{"parameters" => %{^path => "Acme"}}}} =
             Tasks.get(task_id)

    # The automatic DeviceInfo probe follows the task, then its response ends the session.
    assert probe.status == 200

    assert {:ok, %{header: %{id: probe_id}, body: %{rpc: "GetParameterValues"}}} =
             SOAP.decode_envelope(probe.resp_body)

    refute probe_id == task_cwmp_id
    {:ok, acknowledgment} = SOAP.encode_envelope(body, %{id: probe_id, cwmp_ns: @namespace})
    assert post(acknowledgment, options).status == 204
    assert post("", options).status == 204
  end

  for scheme <- [:basic, :digest] do
    test "discovery respects #{scheme} authentication without disclosing credentials" do
      username = "discovery-test-user"
      password = "discovery-test-password"

      opts =
        Server.init(
          auth: %{scheme: unquote(scheme), realm: "acs", username: username, password: password}
        )

      logs =
        capture_log(fn ->
          challenged = post(@discovery, server_opts: opts)
          assert challenged.status == 401
          [challenge] = Plug.Conn.get_resp_header(challenged, "www-authenticate")

          invalid =
            ClientAuth.authorization(
              challenge,
              %{username: username, password: "wrong-test-password"},
              :post,
              "/cwmp"
            )

          rejected = post(@discovery, server_opts: opts, authorization: invalid)
          assert rejected.status == 401

          authorization =
            ClientAuth.authorization(
              challenge,
              %{username: username, password: password},
              :post,
              "/cwmp"
            )

          accepted = post(@discovery, server_opts: opts, authorization: authorization)
          assert accepted.status == 200
          assert_discovery_response(accepted.resp_body, @namespace)

          for response <- [challenged, rejected, accepted],
              secret <- [username, password, authorization] do
            refute response.resp_body =~ secret
            refute inspect(response.resp_headers) =~ secret
          end
        end)

      refute logs =~ username
      refute logs =~ password
      refute logs =~ Base.encode64(username <> ":" <> password)
      refute logs =~ "wrong-test-password"
    end
  end

  test "standalone ACS listener answers method discovery over HTTP" do
    server = start_supervised!(Server.child_spec(port: 0))
    {:ok, {_address, port}} = ThousandIsland.listener_info(server)
    start_supervised!({Finch, name: __MODULE__.Finch})

    request =
      Finch.build(
        :post,
        "http://127.0.0.1:#{port}/cwmp",
        [{"content-type", "text/xml"}],
        @discovery
      )

    assert {:ok, response} = Finch.request(request, __MODULE__.Finch)
    assert response.status == 200
    assert {"content-type", SOAP.content_type()} in response.headers
    assert_discovery_response(response.body, @namespace)
  end

  defp post(body, options \\ []) do
    request =
      conn(:post, "/cwmp", body)
      |> Map.put(:remote_ip, Keyword.get(options, :remote_ip, {127, 0, 0, 1}))
      |> Plug.Conn.put_req_header("content-type", "text/xml; charset=utf-8")

    request =
      case options[:sid] do
        nil -> request
        sid -> put_req_cookie(request, "caretaker_sid", sid)
      end

    request =
      case options[:authorization] do
        nil -> request
        authorization -> Plug.Conn.put_req_header(request, "authorization", authorization)
      end

    Server.call(request, Keyword.get(options, :server_opts, Server.init([])))
  end

  defp assert_discovery_response(xml, namespace) do
    assert {:ok,
            %{
              header: %{id: "methods-test", cwmp_ns: ^namespace},
              body: %{rpc: "GetRPCMethodsResponse", xml: body}
            }} =
             SOAP.decode_envelope(xml)

    assert {:ok, %{methods: @methods}} = GetRPCMethodsResponse.decode(body)

    {document, []} = :xmerl_scan.string(String.to_charlist(xml), namespace_conformant: true)

    path =
      ~c"string(//*[local-name()='MethodList']/@*[local-name()='arrayType' and namespace-uri()='http://schemas.xmlsoap.org/soap/encoding/'])"

    assert {:xmlObj, :string, ~c"xsd:string[3]"} = :xmerl_xpath.string(path, document)
  end
end
