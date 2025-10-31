defmodule Caretaker.TR069.RPC.ScheduleInform do
  @moduledoc """
  TR-069 ScheduleInform (ACS -> CPE)
  """

  @enforce_keys [:delay_seconds, :command_key]
  defstruct [:delay_seconds, :command_key]

  @type t :: %__MODULE__{delay_seconds: non_neg_integer(), command_key: String.t()}

  @spec new(keyword()) :: t()
  def new(opts), do: %__MODULE__{delay_seconds: Keyword.fetch!(opts, :delay_seconds), command_key: Keyword.fetch!(opts, :command_key)}

  @doc "Encode body via Lather"
  @spec encode(t()) :: {:ok, iodata()}
  def encode(%__MODULE__{} = s) do
    map = %{"cwmp:ScheduleInform" => %{"DelaySeconds" => Integer.to_string(s.delay_seconds), "CommandKey" => s.command_key}}
    Lather.Xml.Builder.build_fragment(map)
  end

  @doc "Decode body via Lather"
  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) when is_binary(xml) do
    try do
      wrapped = "<root xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\">" <> xml <> "</root>"
      with {:ok, parsed} <- Lather.Xml.Parser.parse(wrapped) do
        root = parsed["root"] || %{}
        node = root["cwmp:ScheduleInform"] || root["ScheduleInform"] || %{}
        {:ok, %__MODULE__{delay_seconds: to_int(node["DelaySeconds"], 0), command_key: node["CommandKey"] || ""}}
      end
    rescue
      e -> {:error, {:decode_failed, e}}
    end
  end

  defp to_int(nil, d), do: d
  defp to_int(<<>>, d), do: d
  defp to_int(v, _d) when is_integer(v), do: v
  defp to_int(v, _d) when is_binary(v), do: String.to_integer(v)
end