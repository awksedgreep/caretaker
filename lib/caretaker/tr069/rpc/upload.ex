defmodule Caretaker.TR069.RPC.Upload do
  @moduledoc """
  TR-069 Upload RPC (ACS -> CPE).
  """

  @enforce_keys [:command_key, :file_type, :url, :delay_seconds]
  defstruct [
    :command_key,
    :file_type,
    :url,
    :username,
    :password,
    :delay_seconds
  ]

  @type t :: %__MODULE__{
          command_key: String.t(),
          file_type: String.t(),
          url: String.t(),
          username: String.t() | nil,
          password: String.t() | nil,
          delay_seconds: non_neg_integer()
        }

  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      command_key: Keyword.fetch!(opts, :command_key),
      file_type: Keyword.fetch!(opts, :file_type),
      url: Keyword.fetch!(opts, :url),
      username: Keyword.get(opts, :username),
      password: Keyword.get(opts, :password),
      delay_seconds: Keyword.fetch!(opts, :delay_seconds)
    }
  end

  @doc "Encode body via Lather"
  @spec encode(t()) :: {:ok, iodata()}
  def encode(%__MODULE__{} = u) do
    map = %{
      "cwmp:Upload" =>
        %{}
        |> Map.put("CommandKey", u.command_key)
        |> Map.put("FileType", u.file_type)
        |> Map.put("URL", u.url)
        |> put_optional("Username", u.username)
        |> put_optional("Password", u.password)
        |> Map.put("DelaySeconds", Integer.to_string(u.delay_seconds))
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
        node = root["cwmp:Upload"] || root["Upload"] || %{}

        {:ok,
         %__MODULE__{
           command_key: node["CommandKey"] || "",
           file_type: node["FileType"] || "",
           url: node["URL"] || "",
           username: node["Username"],
           password: node["Password"],
           delay_seconds: to_int(node["DelaySeconds"], 0)
         }}
      end
    rescue
      e -> {:error, {:decode_failed, e}}
    end
  end

  defp put_optional(map, _k, nil), do: map
  defp put_optional(map, k, v), do: Map.put(map, k, v)

  defp to_int(nil, d), do: d
  defp to_int(<<>>, d), do: d
  defp to_int(v, _d) when is_integer(v), do: v
  defp to_int(v, _d) when is_binary(v), do: String.to_integer(v)
end