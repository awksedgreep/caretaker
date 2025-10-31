defmodule Caretaker.TR069.RPC.GetParameterAttributes do
  @moduledoc """
  TR-069 GetParameterAttributes (ACS -> CPE)
  """

  @enforce_keys [:names]
  defstruct [:names]

  @type t :: %__MODULE__{names: [String.t()]}

  @spec new([String.t()]) :: t()
  def new(names), do: %__MODULE__{names: names}

  @doc "Encode body via Lather"
  @spec encode(t()) :: {:ok, iodata()}
  def encode(%__MODULE__{names: names}) do
    map = %{
      "cwmp:GetParameterAttributes" => %{
        "ParameterNames" => Enum.map(names, fn n -> %{"string" => n} end)
      }
    }

    Lather.Xml.Builder.build_fragment(map)
  end

  @doc "Decode body via Lather"
  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) when is_binary(xml) do
    try do
      wrapped = "<root xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\">" <> xml <> "</root>"
      with {:ok, parsed} <- Lather.Xml.Parser.parse(wrapped) do
        root = parsed["root"] || %{}
        node = root["cwmp:GetParameterAttributes"] || root["GetParameterAttributes"] || %{}
        plist = node["ParameterNames"] || []
        names = normalize_string_list(plist)
        {:ok, %__MODULE__{names: names}}
      end
    rescue
      e -> {:error, {:decode_failed, e}}
    end
  end

  defp normalize_string_list(val) do
    base =
      case val do
        l when is_list(l) -> Enum.flat_map(l, &normalize_string_list/1)
        %{} = m -> List.wrap(m["string"]) |> Enum.flat_map(&normalize_string_list/1)
        v when is_binary(v) -> [v]
        _ -> []
      end

    base
    |> Enum.flat_map(fn s ->
      s
      |> String.split(~r/\s+/, trim: true)
    end)
  end
end