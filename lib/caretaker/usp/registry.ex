defmodule Caretaker.USP.Registry do
  @moduledoc """
  Registry for USP message types and their handlers.

  Similar to `Caretaker.TR069.RPC.Registry`, this module provides
  a mapping between USP message types and their corresponding modules.

  ## Message Type Categories

  ### Request Messages (Controller → Agent)
  - `:GET` - Read parameter values
  - `:SET` - Write parameter values
  - `:ADD` - Create object instances
  - `:DELETE` - Remove object instances
  - `:OPERATE` - Execute commands
  - `:GET_SUPPORTED_DM` - Get data model information
  - `:GET_INSTANCES` - Get object instances
  - `:GET_SUPPORTED_PROTO` - Get supported protocol versions

  ### Response Messages (Agent → Controller)
  - `:GET_RESP` - Response to Get
  - `:SET_RESP` - Response to Set
  - `:ADD_RESP` - Response to Add
  - `:DELETE_RESP` - Response to Delete
  - `:OPERATE_RESP` - Response to Operate
  - `:GET_SUPPORTED_DM_RESP` - Response to GetSupportedDM
  - `:GET_INSTANCES_RESP` - Response to GetInstances
  - `:GET_SUPPORTED_PROTO_RESP` - Response to GetSupportedProtocol

  ### Notification Messages (Agent → Controller)
  - `:NOTIFY` - Value change, event, or object creation/deletion
  - `:REGISTER` - Agent registration
  - `:DEREGISTER` - Agent deregistration

  ### Acknowledgment Messages
  - `:NOTIFY_RESP` - Acknowledgment of Notify
  - `:REGISTER_RESP` - Acknowledgment of Register
  - `:DEREGISTER_RESP` - Acknowledgment of Deregister

  ### Error Message
  - `:ERROR` - Error response

  """

  @request_types [:GET, :SET, :ADD, :DELETE, :OPERATE, :GET_SUPPORTED_DM, :GET_INSTANCES, :GET_SUPPORTED_PROTO]
  @response_types [:GET_RESP, :SET_RESP, :ADD_RESP, :DELETE_RESP, :OPERATE_RESP, :GET_SUPPORTED_DM_RESP, :GET_INSTANCES_RESP, :GET_SUPPORTED_PROTO_RESP]
  @notification_types [:NOTIFY, :REGISTER, :DEREGISTER]
  @ack_types [:NOTIFY_RESP, :REGISTER_RESP, :DEREGISTER_RESP]

  @type_to_response %{
    GET: :GET_RESP,
    SET: :SET_RESP,
    ADD: :ADD_RESP,
    DELETE: :DELETE_RESP,
    OPERATE: :OPERATE_RESP,
    GET_SUPPORTED_DM: :GET_SUPPORTED_DM_RESP,
    GET_INSTANCES: :GET_INSTANCES_RESP,
    GET_SUPPORTED_PROTO: :GET_SUPPORTED_PROTO_RESP,
    NOTIFY: :NOTIFY_RESP,
    REGISTER: :REGISTER_RESP,
    DEREGISTER: :DEREGISTER_RESP
  }

  @doc """
  Returns all request message types.
  """
  @spec request_types() :: [atom()]
  def request_types, do: @request_types

  @doc """
  Returns all response message types.
  """
  @spec response_types() :: [atom()]
  def response_types, do: @response_types

  @doc """
  Returns all notification message types.
  """
  @spec notification_types() :: [atom()]
  def notification_types, do: @notification_types

  @doc """
  Returns all acknowledgment message types.
  """
  @spec ack_types() :: [atom()]
  def ack_types, do: @ack_types

  @doc """
  Returns all message types.
  """
  @spec all_types() :: [atom()]
  def all_types do
    @request_types ++ @response_types ++ @notification_types ++ @ack_types ++ [:ERROR]
  end

  @doc """
  Checks if a message type is a request.
  """
  @spec request?(atom()) :: boolean()
  def request?(type), do: type in @request_types

  @doc """
  Checks if a message type is a response.
  """
  @spec response?(atom()) :: boolean()
  def response?(type), do: type in @response_types

  @doc """
  Checks if a message type is a notification.
  """
  @spec notification?(atom()) :: boolean()
  def notification?(type), do: type in @notification_types

  @doc """
  Checks if a message type is an acknowledgment.
  """
  @spec ack?(atom()) :: boolean()
  def ack?(type), do: type in @ack_types

  @doc """
  Checks if a message type is an error.
  """
  @spec error?(atom()) :: boolean()
  def error?(:ERROR), do: true
  def error?(_), do: false

  @doc """
  Gets the corresponding response type for a request type.

  ## Examples

      iex> Caretaker.USP.Registry.response_type_for(:GET)
      {:ok, :GET_RESP}

      iex> Caretaker.USP.Registry.response_type_for(:GET_RESP)
      {:error, :not_a_request}

  """
  @spec response_type_for(atom()) :: {:ok, atom()} | {:error, :not_a_request}
  def response_type_for(type) do
    case Map.fetch(@type_to_response, type) do
      {:ok, resp_type} -> {:ok, resp_type}
      :error -> {:error, :not_a_request}
    end
  end

  @doc """
  Gets the corresponding request type for a response type.

  ## Examples

      iex> Caretaker.USP.Registry.request_type_for(:GET_RESP)
      {:ok, :GET}

  """
  @spec request_type_for(atom()) :: {:ok, atom()} | {:error, :not_a_response}
  def request_type_for(resp_type) do
    case Enum.find(@type_to_response, fn {_k, v} -> v == resp_type end) do
      {req_type, _} -> {:ok, req_type}
      nil -> {:error, :not_a_response}
    end
  end

  @doc """
  Maps a message type atom to its string name.

  ## Examples

      iex> Caretaker.USP.Registry.type_to_string(:GET)
      "Get"

      iex> Caretaker.USP.Registry.type_to_string(:GET_RESP)
      "GetResp"

  """
  @spec type_to_string(atom()) :: String.t()
  def type_to_string(type) do
    type
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join()
  end

  @doc """
  Maps a string message name to its type atom.

  ## Examples

      iex> Caretaker.USP.Registry.string_to_type("Get")
      {:ok, :GET}

      iex> Caretaker.USP.Registry.string_to_type("GetResp")
      {:ok, :GET_RESP}

  """
  @spec string_to_type(String.t()) :: {:ok, atom()} | {:error, :unknown_type}
  def string_to_type(name) do
    type = name
    |> Macro.underscore()
    |> String.upcase()
    |> String.to_atom()

    if type in all_types() do
      {:ok, type}
    else
      {:error, :unknown_type}
    end
  end

  @doc """
  Gets the TR-069 equivalent RPC name for a USP message type.

  ## Examples

      iex> Caretaker.USP.Registry.tr069_equivalent(:GET)
      "GetParameterValues"

      iex> Caretaker.USP.Registry.tr069_equivalent(:SET)
      "SetParameterValues"

  """
  @spec tr069_equivalent(atom()) :: String.t() | nil
  def tr069_equivalent(:GET), do: "GetParameterValues"
  def tr069_equivalent(:GET_RESP), do: "GetParameterValuesResponse"
  def tr069_equivalent(:SET), do: "SetParameterValues"
  def tr069_equivalent(:SET_RESP), do: "SetParameterValuesResponse"
  def tr069_equivalent(:ADD), do: "AddObject"
  def tr069_equivalent(:ADD_RESP), do: "AddObjectResponse"
  def tr069_equivalent(:DELETE), do: "DeleteObject"
  def tr069_equivalent(:DELETE_RESP), do: "DeleteObjectResponse"
  def tr069_equivalent(:GET_SUPPORTED_DM), do: "GetParameterNames"
  def tr069_equivalent(:GET_SUPPORTED_DM_RESP), do: "GetParameterNamesResponse"
  def tr069_equivalent(:REGISTER), do: "Inform"
  def tr069_equivalent(:REGISTER_RESP), do: "InformResponse"
  def tr069_equivalent(:NOTIFY), do: "Inform"
  def tr069_equivalent(:ERROR), do: "Fault"
  def tr069_equivalent(_), do: nil
end
