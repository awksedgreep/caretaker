defmodule Caretaker.TR069.RPC.GetParameterValuesResponse do
  @moduledoc """
  Encoder/decoder for GetParameterValuesResponse.
  """

  @type param :: %{name: String.t(), value: String.t(), type: String.t()}
  @type t :: %{parameters: [param()]}

  @spec encode(t()) :: {:ok, iodata()} | {:error, term()}
  def encode(%{parameters: params}) do
    start = System.monotonic_time()

    :telemetry.execute([:caretaker, :tr069, :rpc, :encode, :start], %{}, %{
      rpc: :get_parameter_values_response
    })

    # Build as repeated ParameterValueStruct elements under ParameterList
    pvs =
      Enum.map(params, fn %{name: n, value: v, type: t} ->
        %{"ParameterValueStruct" => %{"Name" => n, "Value" => %{"@xsi:type" => t, "#text" => v}}}
      end)

    map = %{
      "cwmp:GetParameterValuesResponse" => %{
        "ParameterList" => pvs
      }
    }

    case Lather.Xml.Builder.build_fragment(map) do
      {:ok, _frag} = ok ->
        :telemetry.execute(
          [:caretaker, :tr069, :rpc, :encode, :stop],
          %{duration: System.monotonic_time() - start},
          %{rpc: :get_parameter_values_response}
        )

        ok

      error ->
        error
    end
  end

  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) when is_binary(xml) do
    start = System.monotonic_time()

    :telemetry.execute([:caretaker, :tr069, :rpc, :decode, :start], %{}, %{
      rpc: :get_parameter_values_response
    })

    try do
      # Ensure xsi/xsd prefixes are tolerated
      wrapped =
        "<root xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\">" <>
          xml <> "</root>"

      with {:ok, parsed} <- Lather.Xml.Parser.parse(wrapped) do
        root = parsed["root"] || %{}

        node =
          root["cwmp:GetParameterValuesResponse"] || root["GetParameterValuesResponse"] || %{}

        plist = node["ParameterList"] || %{}
        pv = plist["ParameterValueStruct"] || []

        list =
          pv
          |> List.wrap()
          |> Enum.map(&parameter_value_struct/1)

        res = {:ok, %{parameters: list}}

        :telemetry.execute(
          [:caretaker, :tr069, :rpc, :decode, :stop],
          %{duration: System.monotonic_time() - start},
          %{rpc: :get_parameter_values_response}
        )

        res
      end
    rescue
      e -> {:error, {:decode_failed, e}}
    end
  end

  @doc """
  Normalize a parsed `ParameterValueStruct` node into `%{name, value, type}`.

  Handles `Value` elements with text, with only an `xsi:type` attribute (empty
  value), and bare text without attributes.
  """
  @spec parameter_value_struct(map()) :: param()
  def parameter_value_struct(item) when is_map(item) do
    %{
      name: text(item["Name"]),
      value: text(item["Value"]),
      type: value_type(item["Value"])
    }
  end

  @doc "Extract the text of a parsed element, tolerating attribute maps."
  @spec text(term()) :: String.t()
  def text(%{"#text" => v}) when is_binary(v), do: v
  def text(v) when is_binary(v), do: v
  def text(_), do: ""

  defp value_type(%{"@xsi:type" => t}) when is_binary(t), do: t
  defp value_type(_), do: ""
end
