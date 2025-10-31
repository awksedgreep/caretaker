defmodule Caretaker.TR069.RPC.Download do
  @moduledoc """
  TR-069 Download RPC (ACS -> CPE).
  """

  @enforce_keys [:command_key, :file_type, :url, :file_size, :delay_seconds]
  defstruct [
    :command_key,
    :file_type,
    :url,
    :username,
    :password,
    :file_size,
    :target_file_name,
    :delay_seconds,
    :success_url,
    :failure_url
  ]

  @type t :: %__MODULE__{
          command_key: String.t(),
          file_type: String.t(),
          url: String.t(),
          username: String.t() | nil,
          password: String.t() | nil,
          file_size: non_neg_integer(),
          target_file_name: String.t() | nil,
          delay_seconds: non_neg_integer(),
          success_url: String.t() | nil,
          failure_url: String.t() | nil
        }

  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      command_key: Keyword.fetch!(opts, :command_key),
      file_type: Keyword.fetch!(opts, :file_type),
      url: Keyword.fetch!(opts, :url),
      username: Keyword.get(opts, :username),
      password: Keyword.get(opts, :password),
      file_size: Keyword.fetch!(opts, :file_size),
      target_file_name: Keyword.get(opts, :target_file_name),
      delay_seconds: Keyword.fetch!(opts, :delay_seconds),
      success_url: Keyword.get(opts, :success_url),
      failure_url: Keyword.get(opts, :failure_url)
    }
  end

  @doc "Encode body element (without SOAP Envelope) via Lather"
  @spec encode(t()) :: {:ok, iodata()}
  def encode(%__MODULE__{} = d) do
    map = %{
      "cwmp:Download" =>
        %{}
        |> Map.put("CommandKey", d.command_key)
        |> Map.put("FileType", d.file_type)
        |> Map.put("URL", d.url)
        |> put_optional("Username", d.username)
        |> put_optional("Password", d.password)
        |> Map.put("FileSize", Integer.to_string(d.file_size))
        |> put_optional("TargetFileName", d.target_file_name)
        |> Map.put("DelaySeconds", Integer.to_string(d.delay_seconds))
        |> put_optional("SuccessURL", d.success_url)
        |> put_optional("FailureURL", d.failure_url)
    }

    Lather.Xml.Builder.build_fragment(map)
  end

  @doc "Decode body element into struct via Lather"
  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) when is_binary(xml) do
    try do
      wrapped = "<root xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\">" <> xml <> "</root>"

      with {:ok, parsed} <- Lather.Xml.Parser.parse(wrapped) do
        root = parsed["root"] || %{}
        node = root["cwmp:Download"] || root["Download"] || %{}

        {:ok,
         %__MODULE__{
           command_key: node["CommandKey"] || "",
           file_type: node["FileType"] || "",
           url: node["URL"] || "",
           username: node["Username"],
           password: node["Password"],
           file_size: to_int(node["FileSize"], 0),
           target_file_name: node["TargetFileName"],
           delay_seconds: to_int(node["DelaySeconds"], 0),
           success_url: node["SuccessURL"],
           failure_url: node["FailureURL"]
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