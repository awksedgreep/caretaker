defmodule Caretaker.USP.Transport.WebSocket.Paths do
  @moduledoc """
  USP WebSocket URL path structure per TR-369 specification.

  ## Path Structure

  USP over WebSocket uses endpoint paths:

  ```
  /usp/
  ├── controller/<controller_id>   # Controller WebSocket endpoint
  └── agent/<agent_id>             # Agent WebSocket endpoint
  ```

  ## Connection Flow

  1. **Agent → Controller Connection**:
     - Agent connects to: `ws://host:port/usp/controller/<controller_id>`
     - Agent sends USP Records as binary WebSocket frames
     - Response Records returned on same connection

  2. **Controller → Agent Connection** (if needed):
     - Controller connects to: `ws://host:port/usp/agent/<agent_id>`
     - Used for controller-initiated connections

  ## WebSocket Subprotocol

  USP WebSocket connections should use the `v1.usp` subprotocol.

  """

  @path_prefix "/usp"
  @subprotocol "v1.usp"

  @doc """
  Returns the path prefix.
  """
  @spec prefix() :: String.t()
  def prefix, do: @path_prefix

  @doc """
  Returns the USP WebSocket subprotocol identifier.
  """
  @spec subprotocol() :: String.t()
  def subprotocol, do: @subprotocol

  @doc """
  Builds the WebSocket path for a controller endpoint.

  ## Examples

      iex> Caretaker.USP.Transport.WebSocket.Paths.controller_path("self::acs.example.com")
      "/usp/controller/self::acs.example.com"

  """
  @spec controller_path(String.t()) :: String.t()
  def controller_path(controller_id) do
    "#{@path_prefix}/controller/#{controller_id}"
  end

  @doc """
  Builds the WebSocket path for an agent endpoint.

  ## Examples

      iex> Caretaker.USP.Transport.WebSocket.Paths.agent_path("os::ACME-Router-123")
      "/usp/agent/os::ACME-Router-123"

  """
  @spec agent_path(String.t()) :: String.t()
  def agent_path(agent_id) do
    "#{@path_prefix}/agent/#{agent_id}"
  end

  @doc """
  Builds a full WebSocket URL for a controller.

  ## Examples

      iex> Caretaker.USP.Transport.WebSocket.Paths.controller_url("localhost", 8080, "self::acs")
      "ws://localhost:8080/usp/controller/self::acs"

      iex> Caretaker.USP.Transport.WebSocket.Paths.controller_url("acs.example.com", 443, "self::acs", secure: true)
      "wss://acs.example.com:443/usp/controller/self::acs"

  """
  @spec controller_url(String.t(), non_neg_integer(), String.t(), keyword()) :: String.t()
  def controller_url(host, port, controller_id, opts \\ []) do
    scheme = if Keyword.get(opts, :secure, false), do: "wss", else: "ws"
    "#{scheme}://#{host}:#{port}#{controller_path(controller_id)}"
  end

  @doc """
  Builds a full WebSocket URL for an agent.
  """
  @spec agent_url(String.t(), non_neg_integer(), String.t(), keyword()) :: String.t()
  def agent_url(host, port, agent_id, opts \\ []) do
    scheme = if Keyword.get(opts, :secure, false), do: "wss", else: "ws"
    "#{scheme}://#{host}:#{port}#{agent_path(agent_id)}"
  end

  @doc """
  Parses an endpoint ID from a WebSocket path.

  ## Examples

      iex> Caretaker.USP.Transport.WebSocket.Paths.parse_endpoint_from_path("/usp/agent/os::device-123")
      {:ok, {:agent, "os::device-123"}}

      iex> Caretaker.USP.Transport.WebSocket.Paths.parse_endpoint_from_path("/usp/controller/self::acs")
      {:ok, {:controller, "self::acs"}}

  """
  @spec parse_endpoint_from_path(String.t()) ::
          {:ok, {:agent | :controller, String.t()}} | {:error, :invalid_path}
  def parse_endpoint_from_path(path) do
    case String.split(path, "/", trim: true) do
      ["usp", "agent", endpoint_id] ->
        {:ok, {:agent, endpoint_id}}

      ["usp", "controller", endpoint_id] ->
        {:ok, {:controller, endpoint_id}}

      _ ->
        {:error, :invalid_path}
    end
  end

  @doc """
  Validates a WebSocket path format.
  """
  @spec valid_path?(String.t()) :: boolean()
  def valid_path?(path) do
    case parse_endpoint_from_path(path) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Checks if the given subprotocol list contains the USP subprotocol.
  """
  @spec has_usp_subprotocol?([String.t()]) :: boolean()
  def has_usp_subprotocol?(subprotocols) when is_list(subprotocols) do
    @subprotocol in subprotocols
  end
end
