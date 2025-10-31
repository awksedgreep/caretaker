defmodule Caretaker.TR069.RPC.AutonomousTransferComplete do
  @moduledoc """
  TR-069 AutonomousTransferComplete (CPE -> ACS).
  """

  @enforce_keys [:command_key, :start_time, :complete_time, :fault_code, :fault_string, :is_download, :file_type]
  defstruct [
    :command_key,
    :start_time,
    :complete_time,
    :fault_code,
    :fault_string,
    :is_download,
    :file_type
  ]

  @type t :: %__MODULE__{
          command_key: String.t(),
          start_time: String.t(),
          complete_time: String.t(),
          fault_code: integer(),
          fault_string: String.t(),
          is_download: boolean(),
          file_type: String.t()
        }

  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      command_key: Keyword.fetch!(opts, :command_key),
      start_time: Keyword.fetch!(opts, :start_time),
      complete_time: Keyword.fetch!(opts, :complete_time),
      fault_code: Keyword.get(opts, :fault_code, 0),
      fault_string: Keyword.get(opts, :fault_string, ""),
      is_download: Keyword.get(opts, :is_download, true),
      file_type: Keyword.get(opts, :file_type, "")
    }
  end

  @doc "Encode body via Lather"
  @spec encode(t()) :: {:ok, iodata()}
  def encode(%__MODULE__{} = t) do
    map = %{
      "cwmp:AutonomousTransferComplete" => %{
        "CommandKey" => t.command_key,
        "StartTime" => t.start_time,
        "CompleteTime" => t.complete_time,
        "IsDownload" => if(t.is_download, do: "1", else: "0"),
        "FileType" => t.file_type,
        "FaultStruct" => %{
          "FaultCode" => Integer.to_string(t.fault_code),
          "FaultString" => t.fault_string
        }
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
        node = root["cwmp:AutonomousTransferComplete"] || root["AutonomousTransferComplete"] || %{}
        f = node["FaultStruct"] || %{}

        {:ok,
         %__MODULE__{
           command_key: node["CommandKey"] || "",
           start_time: node["StartTime"] || "",
           complete_time: node["CompleteTime"] || "",
           is_download: (node["IsDownload"] in ["1", 1, true]),
           file_type: node["FileType"] || "",
           fault_code: to_int(f["FaultCode"], 0),
           fault_string: f["FaultString"] || ""
         }}
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