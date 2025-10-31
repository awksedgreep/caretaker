defmodule Caretaker.TR069.RPC.ScheduleDownload do
  @moduledoc """
  TR-069 ScheduleDownload (ACS -> CPE)
  """

  @enforce_keys [:command_key, :file_type, :url, :time_windows]
  defstruct [
    :command_key,
    :file_type,
    :url,
    :username,
    :password,
    :file_size,
    :target_file_name,
    :time_windows
  ]

  @type time_window :: %{start_time: String.t(), end_time: String.t(), window_mode: String.t()}
  @type t :: %__MODULE__{
          command_key: String.t(),
          file_type: String.t(),
          url: String.t(),
          username: String.t() | nil,
          password: String.t() | nil,
          file_size: non_neg_integer() | nil,
          target_file_name: String.t() | nil,
          time_windows: [time_window()]
        }

  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      command_key: Keyword.fetch!(opts, :command_key),
      file_type: Keyword.fetch!(opts, :file_type),
      url: Keyword.fetch!(opts, :url),
      username: Keyword.get(opts, :username),
      password: Keyword.get(opts, :password),
      file_size: Keyword.get(opts, :file_size),
      target_file_name: Keyword.get(opts, :target_file_name),
      time_windows: Keyword.get(opts, :time_windows, [])
    }
  end

  @doc "Encode body via Lather"
  @spec encode(t()) :: {:ok, iodata()}
  def encode(%__MODULE__{} = s) do
    tw_structs =
      Enum.map(s.time_windows, fn %{start_time: st, end_time: et, window_mode: wm} ->
        %{"StartTime" => st, "EndTime" => et, "WindowMode" => wm}
      end)

    map = %{
      "cwmp:ScheduleDownload" =>
        %{}
        |> Map.put("CommandKey", s.command_key)
        |> Map.put("FileType", s.file_type)
        |> Map.put("URL", s.url)
        |> put_opt("Username", s.username)
        |> put_opt("Password", s.password)
        |> put_opt("FileSize", (s.file_size && Integer.to_string(s.file_size)))
        |> put_opt("TargetFileName", s.target_file_name)
        |> Map.put("TimeWindowList", %{"TimeWindowStruct" => tw_structs})
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
        node = root["cwmp:ScheduleDownload"] || root["ScheduleDownload"] || %{}

        twl = node["TimeWindowList"] || []

        elems =
          case twl do
            %{} = m ->
              # Either nested under TimeWindowStruct or directly the struct map
              inner = m["TimeWindowStruct"]
              cond do
                is_list(inner) -> inner
                is_map(inner) -> [inner]
                true -> [m]
              end

            l when is_list(l) ->
              Enum.flat_map(l, fn
                %{"TimeWindowStruct" => v} when is_list(v) -> v
                %{"TimeWindowStruct" => v} when is_map(v) -> [v]
                %{} = v -> [v]
                _ -> []
              end)

            _ -> []
          end

        tw = Enum.map(elems, &tw_map/1)

        {:ok,
         %__MODULE__{
           command_key: node["CommandKey"] || "",
           file_type: node["FileType"] || "",
           url: node["URL"] || "",
           username: node["Username"],
           password: node["Password"],
           file_size: to_int_opt(node["FileSize"]),
           target_file_name: node["TargetFileName"],
           time_windows: tw
         }}
      end
    rescue
      e -> {:error, {:decode_failed, e}}
    end
  end

  defp tw_map(%{"TimeWindowStruct" => m}), do: tw_map(m)
  defp tw_map(%{} = m) do
    %{
      start_time: m["StartTime"] || "",
      end_time: m["EndTime"] || "",
      window_mode: m["WindowMode"] || ""
    }
  end

  defp put_opt(map, _k, nil), do: map
  defp put_opt(map, k, v), do: Map.put(map, k, v)

  defp to_int_opt(nil), do: nil
  defp to_int_opt(<<>>), do: nil
  defp to_int_opt(v) when is_integer(v), do: v
  defp to_int_opt(v) when is_binary(v), do: String.to_integer(v)
end