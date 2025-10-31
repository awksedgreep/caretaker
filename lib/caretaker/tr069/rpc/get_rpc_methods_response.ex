defmodule Caretaker.TR069.RPC.GetRPCMethodsResponse do
  @moduledoc """
  TR-069 GetRPCMethodsResponse (ACS -> CPE) with MethodList.
  """

  @enforce_keys [:methods]
  defstruct [:methods]

  @type t :: %__MODULE__{methods: [String.t()]}

  @spec new([String.t()]) :: t()
  def new(list), do: %__MODULE__{methods: list}

  @doc "Encode MethodList via Lather"
  @spec encode(t()) :: {:ok, iodata()}
  def encode(%__MODULE__{methods: list}) do
    map = %{
      "cwmp:GetRPCMethodsResponse" => %{
        "MethodList" => Enum.map(list, fn m -> %{"string" => m} end)
      }
    }

    Lather.Xml.Builder.build_fragment(map)
  end

  @doc "Decode MethodList via Lather"
  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) when is_binary(xml) do
    try do
      wrapped = "<root xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\">" <> xml <> "</root>"
      with {:ok, parsed} <- Lather.Xml.Parser.parse(wrapped) do
        root = parsed["root"] || %{}
        node = root["cwmp:GetRPCMethodsResponse"] || root["GetRPCMethodsResponse"] || %{}
        ml = node["MethodList"] || []
        methods = normalize_string_list(ml)
        {:ok, %__MODULE__{methods: methods}}
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