defmodule Caretaker.TR069.ParameterArrayEncodingTest do
  use ExUnit.Case, async: true

  alias Caretaker.CWMP.SOAP
  alias Caretaker.TR069.RPC.{GetParameterValues, GetRPCMethodsResponse, SetParameterValues}

  @soap_encoding "http://schemas.xmlsoap.org/soap/encoding/"
  @xsi "http://www.w3.org/2001/XMLSchema-instance"
  @cwmp "urn:dslforum-org:cwmp-1-1"

  for key <- ["", "key<&>"] do
    test "SetParameterValues preserves argument order and typed values with key #{inspect(key)}" do
      key = unquote(key)

      parameters = [
        %{
          name: "Device.ManagementServer.ConnectionRequestUsername",
          value: "test<&>user",
          type: "xsd:string"
        },
        %{
          name: "Device.ManagementServer.ConnectionRequestPassword",
          value: "",
          type: "xsd:string"
        },
        %{
          name: "Device.ManagementServer.PeriodicInformInterval",
          value: "300",
          type: "xsd:unsignedInt"
        }
      ]

      {:ok, body} =
        SetParameterValues.encode(SetParameterValues.new(parameters, parameter_key: key))

      rpc = parse_rpc(body)

      # Inspect the XML sequence: a map-based round trip cannot detect this bug.
      assert Enum.map(xpath(rpc, "*"), &string(&1, "local-name(.)")) == [
               "ParameterList",
               "ParameterKey"
             ]

      [list] = xpath(rpc, "*[1]")
      assert_array(list, "cwmp:ParameterValueStruct[3]", "ParameterValueStruct", 3)

      assert string(list, "@*[local-name()='type' and namespace-uri()='#{@xsi}']") ==
               "cwmp:ParameterValueList"

      assert string(rpc, "ParameterKey") == key

      actual =
        Enum.map(xpath(list, "ParameterValueStruct"), fn parameter ->
          %{
            name: string(parameter, "Name"),
            value: string(parameter, "Value"),
            type: string(parameter, "Value/@*[local-name()='type' and namespace-uri()='#{@xsi}']")
          }
        end)

      assert actual == parameters
    end
  end

  test "empty SetParameterValues has a zero-length array with no phantom parameter" do
    {:ok, body} = SetParameterValues.encode(SetParameterValues.new([]))
    [list] = body |> parse_rpc() |> xpath("ParameterList")
    assert_array(list, "cwmp:ParameterValueStruct[0]", "ParameterValueStruct", 0)
  end

  test "GetParameterValues declares SOAP array metadata matching its direct string children" do
    for names <- [
          [],
          ["Device.DeviceInfo."],
          ["Device.DeviceInfo.Manufacturer", "Device.WiFi.SSID.1.SSID"]
        ] do
      {:ok, body} = GetParameterValues.encode(GetParameterValues.new(names))
      [list] = body |> parse_rpc() |> xpath("ParameterNames")
      assert_array(list, "xsd:string[#{length(names)}]", "string", length(names))

      assert string(list, "@*[local-name()='type' and namespace-uri()='#{@xsi}']") ==
               "cwmp:ParameterNames"

      assert Enum.map(xpath(list, "string"), &string(&1, ".")) == names
      assert {:ok, %{names: ^names}} = GetParameterValues.decode(IO.iodata_to_binary(body))
    end
  end

  test "GetRPCMethodsResponse declares SOAP array metadata matching its methods" do
    for methods <- [[], ["Inform"], ["Inform", "GetRPCMethods", "TransferComplete"]] do
      {:ok, body} = GetRPCMethodsResponse.encode(GetRPCMethodsResponse.new(methods))
      [list] = body |> parse_rpc() |> xpath("MethodList")
      assert_array(list, "xsd:string[#{length(methods)}]", "string", length(methods))
      assert Enum.map(xpath(list, "string"), &string(&1, ".")) == methods
      assert {:ok, %{methods: ^methods}} = GetRPCMethodsResponse.decode(IO.iodata_to_binary(body))
    end
  end

  defp parse_rpc(body) do
    {:ok, envelope} = SOAP.encode_envelope(body, %{id: "array-test", cwmp_ns: @cwmp})
    {document, []} = :xmerl_scan.string(String.to_charlist(envelope), namespace_conformant: true)
    [rpc] = xpath(document, "/*[local-name()='Envelope']/*[local-name()='Body']/*")
    assert string(rpc, "namespace-uri(.)") == @cwmp
    rpc
  end

  defp assert_array(list, type, child, count) do
    assert string(list, "@*[local-name()='arrayType' and namespace-uri()='#{@soap_encoding}']") ==
             type

    assert xpath(list, "@arrayType") == []
    assert length(xpath(list, child)) == count
    assert length(xpath(list, "*")) == count
  end

  defp xpath(node, path), do: :xmerl_xpath.string(String.to_charlist(path), node)

  defp string(node, path) do
    {:xmlObj, :string, value} = xpath(node, "string(#{path})")
    List.to_string(value)
  end
end
