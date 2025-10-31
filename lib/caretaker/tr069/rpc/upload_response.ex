defmodule Caretaker.TR069.RPC.UploadResponse do
  @moduledoc """
  TR-069 UploadResponse (CPE -> ACS).
  """

  @enforce_keys [:status, :start_time, :complete_time]
  defstruct [:status, :start_time, :complete_time]

  @type t :: %__MODULE__{status: integer(), start_time: String.t(), complete_time: String.t()}

  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      status: Keyword.get(opts, :status, 0),
      start_time: Keyword.get(opts, :start_time, ""),
      complete_time: Keyword.get(opts, :complete_time, "")
    }
  end

  @doc "Encode body via Lather"
  @spec encode(t()) :: {:ok, iodata()}
  def encode(%__MODULE__{} = r) do
    map = %{
      "cwmp:UploadResponse" => %{
        "Status" => Integer.to_string(r.status),
        "StartTime" => r.start_time,
        "CompleteTime" => r.complete_time
      }
    }

    Lather.Xml.Builder.build_fragment(map)
  end

  @doc "Decode body via Lather"
  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) when is_binary(xml) do
    try do
      wrapped = "<root xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\">" <> xml <> "</root>"
      with {:ok, parsed} <- Lather.Xml.Parser.parse(wrapped) do
        root = parsed["root"] || %{}
        node = root["cwmp:UploadResponse"] || root["UploadResponse"] || %{}
        {:ok, %__MODULE__{status: to_int(node["Status"], 0), start_time: node["StartTime"] || "", complete_time: node["CompleteTime"] || ""}}
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