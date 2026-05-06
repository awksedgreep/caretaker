defmodule Caretaker.USP.Proto do
  @moduledoc """
  Wrapper module for USP Protocol Buffer types.

  This module provides convenient access to USP message types and
  helper functions for encoding/decoding USP messages.

  ## Message Types

  USP defines several message types for Controller-Agent communication:

  - `Get` / `GetResp` - Read parameter values
  - `Set` / `SetResp` - Write parameter values
  - `Add` / `AddResp` - Create object instances
  - `Delete` / `DeleteResp` - Remove object instances
  - `Operate` / `OperateResp` - Execute commands
  - `Notify` / `NotifyResp` - Agent notifications
  - `GetSupportedDM` / `GetSupportedDMResp` - Data model info
  - `GetInstances` / `GetInstancesResp` - Object instances
  - `Register` / `RegisterResp` - Agent registration
  - `Deregister` / `DeregisterResp` - Agent deregistration
  - `Error` - Error response

  ## USP Records

  USP Messages are wrapped in Records for transport. Records provide:
  - Endpoint identification (to_id, from_id)
  - Security options (TLS, signatures)
  - Session context for message segmentation

  ## Examples

      # Create a Get request
      get = Caretaker.USP.Proto.build_get(["Device.DeviceInfo."])

      # Encode to binary
      {:ok, binary} = Caretaker.USP.Proto.encode(get)

      # Decode from binary
      {:ok, msg} = Caretaker.USP.Proto.decode(binary)

  """

  # Core message types
  alias Caretaker.Proto.Usp.{Msg, Header, Body, Request, Error}
  # Request types
  alias Caretaker.Proto.Usp.{
    Get,
    Set,
    Add,
    Delete,
    Operate,
    GetSupportedDM,
    GetInstances,
    Register
  }

  # Record types
  alias Caretaker.Proto.UspRecord.Record

  @doc """
  Encodes a USP Message to binary protobuf format.

  ## Examples

      iex> msg = Caretaker.USP.Proto.build_get(["Device.DeviceInfo."])
      iex> {:ok, binary} = Caretaker.USP.Proto.encode(msg)
      iex> is_binary(binary)
      true

  """
  @spec encode(Msg.t()) :: {:ok, binary()} | {:error, term()}
  def encode(%Msg{} = msg) do
    {:ok, Msg.encode(msg)}
  rescue
    e -> {:error, e}
  end

  @doc """
  Encodes a USP Record to binary protobuf format.
  """
  @spec encode_record(Record.t()) :: {:ok, binary()} | {:error, term()}
  def encode_record(%Record{} = record) do
    {:ok, Record.encode(record)}
  rescue
    e -> {:error, e}
  end

  @doc """
  Decodes a binary protobuf to a USP Message.

  ## Examples

      iex> msg = Caretaker.USP.Proto.build_get(["Device.DeviceInfo."])
      iex> {:ok, binary} = Caretaker.USP.Proto.encode(msg)
      iex> {:ok, decoded} = Caretaker.USP.Proto.decode(binary)
      iex> decoded.header.msg_type
      :GET

  """
  @spec decode(binary()) :: {:ok, Msg.t()} | {:error, term()}
  def decode(binary) when is_binary(binary) do
    {:ok, Msg.decode(binary)}
  rescue
    e -> {:error, e}
  end

  @doc """
  Decodes a binary protobuf to a USP Record.
  """
  @spec decode_record(binary()) :: {:ok, Record.t()} | {:error, term()}
  def decode_record(binary) when is_binary(binary) do
    {:ok, Record.decode(binary)}
  rescue
    e -> {:error, e}
  end

  @doc """
  Generates a unique message ID.
  """
  @spec generate_msg_id() :: String.t()
  def generate_msg_id do
    "msg-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  @doc """
  Builds a Get request message.

  ## Parameters

  - `param_paths` - List of TR-181 parameter paths to retrieve
  - `opts` - Options:
    - `:msg_id` - Custom message ID (auto-generated if not provided)
    - `:max_depth` - Maximum depth for partial paths (default: 0 = unlimited)

  ## Examples

      iex> msg = Caretaker.USP.Proto.build_get(["Device.DeviceInfo.Manufacturer"])
      iex> msg.header.msg_type
      :GET

  """
  @spec build_get([String.t()], keyword()) :: Msg.t()
  def build_get(param_paths, opts \\ []) when is_list(param_paths) do
    msg_id = Keyword.get(opts, :msg_id, generate_msg_id())
    max_depth = Keyword.get(opts, :max_depth, 0)

    %Msg{
      header: %Header{
        msg_id: msg_id,
        msg_type: :GET
      },
      body: %Body{
        msg_body:
          {:request,
           %Request{
             req_type:
               {:get,
                %Get{
                  param_paths: param_paths,
                  max_depth: max_depth
                }}
           }}
      }
    }
  end

  @doc """
  Builds a Set request message.

  ## Parameters

  - `updates` - List of `{obj_path, params}` tuples where params is a keyword list
  - `opts` - Options:
    - `:msg_id` - Custom message ID
    - `:allow_partial` - Allow partial success (default: false)

  ## Examples

      iex> msg = Caretaker.USP.Proto.build_set([
      ...>   {"Device.WiFi.SSID.1.", [SSID: "MyNetwork"]}
      ...> ])
      iex> msg.header.msg_type
      :SET

  """
  @spec build_set([{String.t(), keyword()}], keyword()) :: Msg.t()
  def build_set(updates, opts \\ []) when is_list(updates) do
    msg_id = Keyword.get(opts, :msg_id, generate_msg_id())
    allow_partial = Keyword.get(opts, :allow_partial, false)

    alias Caretaker.Proto.Usp.{UpdateObject, UpdateParamSetting}

    update_objs =
      Enum.map(updates, fn {obj_path, params} ->
        param_settings =
          Enum.map(params, fn {param, value} ->
            %UpdateParamSetting{
              param: to_string(param),
              value: to_string(value),
              required: true
            }
          end)

        %UpdateObject{
          obj_path: obj_path,
          param_settings: param_settings
        }
      end)

    %Msg{
      header: %Header{
        msg_id: msg_id,
        msg_type: :SET
      },
      body: %Body{
        msg_body:
          {:request,
           %Request{
             req_type:
               {:set,
                %Set{
                  allow_partial: allow_partial,
                  update_objs: update_objs
                }}
           }}
      }
    }
  end

  @doc """
  Builds an Add request message to create object instances.

  ## Parameters

  - `creates` - List of `{obj_path, params}` tuples
  - `opts` - Options:
    - `:msg_id` - Custom message ID
    - `:allow_partial` - Allow partial success (default: false)

  """
  @spec build_add([{String.t(), keyword()}], keyword()) :: Msg.t()
  def build_add(creates, opts \\ []) when is_list(creates) do
    msg_id = Keyword.get(opts, :msg_id, generate_msg_id())
    allow_partial = Keyword.get(opts, :allow_partial, false)

    alias Caretaker.Proto.Usp.{CreateObject, CreateParamSetting}

    create_objs =
      Enum.map(creates, fn {obj_path, params} ->
        param_settings =
          Enum.map(params, fn {param, value} ->
            %CreateParamSetting{
              param: to_string(param),
              value: to_string(value),
              required: true
            }
          end)

        %CreateObject{
          obj_path: obj_path,
          param_settings: param_settings
        }
      end)

    %Msg{
      header: %Header{
        msg_id: msg_id,
        msg_type: :ADD
      },
      body: %Body{
        msg_body:
          {:request,
           %Request{
             req_type:
               {:add,
                %Add{
                  allow_partial: allow_partial,
                  create_objs: create_objs
                }}
           }}
      }
    }
  end

  @doc """
  Builds a Delete request message.
  """
  @spec build_delete([String.t()], keyword()) :: Msg.t()
  def build_delete(obj_paths, opts \\ []) when is_list(obj_paths) do
    msg_id = Keyword.get(opts, :msg_id, generate_msg_id())
    allow_partial = Keyword.get(opts, :allow_partial, false)

    %Msg{
      header: %Header{
        msg_id: msg_id,
        msg_type: :DELETE
      },
      body: %Body{
        msg_body:
          {:request,
           %Request{
             req_type:
               {:delete,
                %Delete{
                  allow_partial: allow_partial,
                  obj_paths: obj_paths
                }}
           }}
      }
    }
  end

  @doc """
  Builds an Operate request message to execute a command.
  """
  @spec build_operate(String.t(), map(), keyword()) :: Msg.t()
  def build_operate(command, input_args \\ %{}, opts \\ []) do
    msg_id = Keyword.get(opts, :msg_id, generate_msg_id())
    command_key = Keyword.get(opts, :command_key, "")
    send_resp = Keyword.get(opts, :send_resp, true)

    string_args = Map.new(input_args, fn {k, v} -> {to_string(k), to_string(v)} end)

    %Msg{
      header: %Header{
        msg_id: msg_id,
        msg_type: :OPERATE
      },
      body: %Body{
        msg_body:
          {:request,
           %Request{
             req_type:
               {:operate,
                %Operate{
                  command: command,
                  command_key: command_key,
                  send_resp: send_resp,
                  input_args: string_args
                }}
           }}
      }
    }
  end

  @doc """
  Builds a GetSupportedDM request message.
  """
  @spec build_get_supported_dm([String.t()], keyword()) :: Msg.t()
  def build_get_supported_dm(obj_paths, opts \\ []) when is_list(obj_paths) do
    msg_id = Keyword.get(opts, :msg_id, generate_msg_id())

    %Msg{
      header: %Header{
        msg_id: msg_id,
        msg_type: :GET_SUPPORTED_DM
      },
      body: %Body{
        msg_body:
          {:request,
           %Request{
             req_type:
               {:get_supported_dm,
                %GetSupportedDM{
                  obj_paths: obj_paths,
                  first_level_only: Keyword.get(opts, :first_level_only, false),
                  return_commands: Keyword.get(opts, :return_commands, true),
                  return_events: Keyword.get(opts, :return_events, true),
                  return_params: Keyword.get(opts, :return_params, true),
                  return_unique_key_sets: Keyword.get(opts, :return_unique_key_sets, false)
                }}
           }}
      }
    }
  end

  @doc """
  Builds a GetInstances request message.
  """
  @spec build_get_instances([String.t()], keyword()) :: Msg.t()
  def build_get_instances(obj_paths, opts \\ []) when is_list(obj_paths) do
    msg_id = Keyword.get(opts, :msg_id, generate_msg_id())

    %Msg{
      header: %Header{
        msg_id: msg_id,
        msg_type: :GET_INSTANCES
      },
      body: %Body{
        msg_body:
          {:request,
           %Request{
             req_type:
               {:get_instances,
                %GetInstances{
                  obj_paths: obj_paths,
                  first_level_only: Keyword.get(opts, :first_level_only, false)
                }}
           }}
      }
    }
  end

  @doc """
  Builds a Register request message.
  """
  @spec build_register([String.t()], keyword()) :: Msg.t()
  def build_register(paths, opts \\ []) when is_list(paths) do
    msg_id = Keyword.get(opts, :msg_id, generate_msg_id())
    allow_partial = Keyword.get(opts, :allow_partial, false)

    alias Caretaker.Proto.Usp.RegistrationPath

    reg_paths =
      Enum.map(paths, fn path ->
        %RegistrationPath{path: path}
      end)

    %Msg{
      header: %Header{
        msg_id: msg_id,
        msg_type: :REGISTER
      },
      body: %Body{
        msg_body:
          {:request,
           %Request{
             req_type:
               {:register,
                %Register{
                  allow_partial: allow_partial,
                  reg_paths: reg_paths
                }}
           }}
      }
    }
  end

  @doc """
  Builds an Error response message.
  """
  @spec build_error(non_neg_integer(), String.t(), keyword()) :: Msg.t()
  def build_error(err_code, err_msg, opts \\ []) do
    msg_id = Keyword.get(opts, :msg_id, generate_msg_id())

    %Msg{
      header: %Header{
        msg_id: msg_id,
        msg_type: :ERROR
      },
      body: %Body{
        msg_body:
          {:error,
           %Error{
             err_code: err_code,
             err_msg: err_msg,
             param_errs: []
           }}
      }
    }
  end

  # ============================================================================
  # Response Builders (Agent → Controller)
  # ============================================================================

  @doc """
  Builds a GetResp response message.

  ## Parameters

  - `results` - List of `{requested_path, resolved_results}` tuples where
    resolved_results is a list of `{resolved_path, params_map}` tuples
  - `opts` - Options including `:msg_id`

  ## Examples

      iex> results = [
      ...>   {"Device.DeviceInfo.", [
      ...>     {"Device.DeviceInfo.", %{
      ...>       "Manufacturer" => "Acme",
      ...>       "ModelName" => "Router1"
      ...>     }}
      ...>   ]}
      ...> ]
      iex> msg = Caretaker.USP.Proto.build_get_resp(results)
      iex> msg.header.msg_type
      :GET_RESP

  """
  @spec build_get_resp([{String.t(), [{String.t(), map()}]}], keyword()) :: Msg.t()
  def build_get_resp(results, opts \\ []) when is_list(results) do
    msg_id = Keyword.get(opts, :msg_id, generate_msg_id())

    alias Caretaker.Proto.Usp.{GetResp, RequestedPathResult, ResolvedPathResult, Response}

    req_path_results =
      Enum.map(results, fn {requested_path, resolved_results} ->
        resolved =
          Enum.map(resolved_results, fn {resolved_path, params} ->
            %ResolvedPathResult{
              resolved_path: resolved_path,
              result_params: Map.new(params, fn {k, v} -> {to_string(k), to_string(v)} end)
            }
          end)

        %RequestedPathResult{
          requested_path: requested_path,
          err_code: 0,
          err_msg: "",
          resolved_path_results: resolved
        }
      end)

    %Msg{
      header: %Header{
        msg_id: msg_id,
        msg_type: :GET_RESP
      },
      body: %Body{
        msg_body:
          {:response,
           %Response{
             resp_type:
               {:get_resp,
                %GetResp{
                  req_path_results: req_path_results
                }}
           }}
      }
    }
  end

  @doc """
  Builds a SetResp response message.
  """
  @spec build_set_resp(
          [{String.t(), :success | {:error, non_neg_integer(), String.t()}}],
          keyword()
        ) :: Msg.t()
  def build_set_resp(results, opts \\ []) when is_list(results) do
    msg_id = Keyword.get(opts, :msg_id, generate_msg_id())

    alias Caretaker.Proto.Usp.{
      SetResp,
      UpdatedObjectResult,
      OperationStatus,
      OperationSuccess,
      OperationFailure,
      Response
    }

    updated_results =
      Enum.map(results, fn
        {path, :success} ->
          %UpdatedObjectResult{
            requested_path: path,
            oper_status: %OperationStatus{
              oper_status: {:oper_success, %OperationSuccess{}}
            },
            updated_inst_results: []
          }

        {path, {:error, code, msg}} ->
          %UpdatedObjectResult{
            requested_path: path,
            oper_status: %OperationStatus{
              oper_status: {:oper_failure, %OperationFailure{err_code: code, err_msg: msg}}
            },
            updated_inst_results: []
          }
      end)

    %Msg{
      header: %Header{
        msg_id: msg_id,
        msg_type: :SET_RESP
      },
      body: %Body{
        msg_body:
          {:response,
           %Response{
             resp_type:
               {:set_resp,
                %SetResp{
                  updated_obj_results: updated_results
                }}
           }}
      }
    }
  end

  @doc """
  Builds an AddResp response message.
  """
  @spec build_add_resp(
          [{String.t(), {:ok, String.t()} | {:error, non_neg_integer(), String.t()}}],
          keyword()
        ) :: Msg.t()
  def build_add_resp(results, opts \\ []) when is_list(results) do
    msg_id = Keyword.get(opts, :msg_id, generate_msg_id())

    alias Caretaker.Proto.Usp.{
      AddResp,
      CreatedObjectResult,
      CreatedInstanceResult,
      OperationStatus,
      OperationSuccess,
      OperationFailure,
      Response
    }

    created_results =
      Enum.map(results, fn
        {path, {:ok, instance_path}} ->
          %CreatedObjectResult{
            requested_path: path,
            oper_status: %OperationStatus{
              oper_status: {:oper_success, %OperationSuccess{}}
            },
            created_inst_results: [
              %CreatedInstanceResult{
                instantiated_path: instance_path,
                param_errs: [],
                unique_keys: %{}
              }
            ]
          }

        {path, {:error, code, msg}} ->
          %CreatedObjectResult{
            requested_path: path,
            oper_status: %OperationStatus{
              oper_status: {:oper_failure, %OperationFailure{err_code: code, err_msg: msg}}
            },
            created_inst_results: []
          }
      end)

    %Msg{
      header: %Header{
        msg_id: msg_id,
        msg_type: :ADD_RESP
      },
      body: %Body{
        msg_body:
          {:response,
           %Response{
             resp_type:
               {:add_resp,
                %AddResp{
                  created_obj_results: created_results
                }}
           }}
      }
    }
  end

  @doc """
  Builds a DeleteResp response message.
  """
  @spec build_delete_resp(
          [{String.t(), :success | {:error, non_neg_integer(), String.t()}}],
          keyword()
        ) :: Msg.t()
  def build_delete_resp(results, opts \\ []) when is_list(results) do
    msg_id = Keyword.get(opts, :msg_id, generate_msg_id())

    alias Caretaker.Proto.Usp.{
      DeleteResp,
      DeletedObjectResult,
      OperationStatus,
      OperationSuccess,
      OperationFailure,
      Response
    }

    deleted_results =
      Enum.map(results, fn
        {path, :success} ->
          %DeletedObjectResult{
            requested_path: path,
            oper_status: %OperationStatus{
              oper_status: {:oper_success, %OperationSuccess{}}
            },
            affected_paths: [path],
            unaffected_path_errs: []
          }

        {path, {:error, code, msg}} ->
          %DeletedObjectResult{
            requested_path: path,
            oper_status: %OperationStatus{
              oper_status: {:oper_failure, %OperationFailure{err_code: code, err_msg: msg}}
            },
            affected_paths: [],
            unaffected_path_errs: []
          }
      end)

    %Msg{
      header: %Header{
        msg_id: msg_id,
        msg_type: :DELETE_RESP
      },
      body: %Body{
        msg_body:
          {:response,
           %Response{
             resp_type:
               {:delete_resp,
                %DeleteResp{
                  deleted_obj_results: deleted_results
                }}
           }}
      }
    }
  end

  @doc """
  Builds a Notify message for value changes.
  """
  @spec build_notify_value_change(String.t(), String.t(), String.t(), keyword()) :: Msg.t()
  def build_notify_value_change(subscription_id, param_path, param_value, opts \\ []) do
    msg_id = Keyword.get(opts, :msg_id, generate_msg_id())
    send_resp = Keyword.get(opts, :send_resp, false)

    alias Caretaker.Proto.Usp.{Notify, ValueChange, Response}

    %Msg{
      header: %Header{
        msg_id: msg_id,
        msg_type: :NOTIFY
      },
      body: %Body{
        msg_body:
          {:request,
           %Request{
             req_type:
               {:notify,
                %Notify{
                  subscription_id: subscription_id,
                  send_resp: send_resp,
                  notification:
                    {:value_change,
                     %ValueChange{
                       param_path: param_path,
                       param_value: param_value
                     }}
                }}
           }}
      }
    }
  end

  @doc """
  Builds a Notify message for events.
  """
  @spec build_notify_event(String.t(), String.t(), String.t(), map(), keyword()) :: Msg.t()
  def build_notify_event(subscription_id, obj_path, event_name, params \\ %{}, opts \\ []) do
    msg_id = Keyword.get(opts, :msg_id, generate_msg_id())
    send_resp = Keyword.get(opts, :send_resp, false)

    alias Caretaker.Proto.Usp.{Notify, Event}

    string_params = Map.new(params, fn {k, v} -> {to_string(k), to_string(v)} end)

    %Msg{
      header: %Header{
        msg_id: msg_id,
        msg_type: :NOTIFY
      },
      body: %Body{
        msg_body:
          {:request,
           %Request{
             req_type:
               {:notify,
                %Notify{
                  subscription_id: subscription_id,
                  send_resp: send_resp,
                  notification:
                    {:event,
                     %Event{
                       obj_path: obj_path,
                       event_name: event_name,
                       params: string_params
                     }}
                }}
           }}
      }
    }
  end

  @doc """
  Builds a NotifyResp acknowledgment message.
  """
  @spec build_notify_resp(String.t(), keyword()) :: Msg.t()
  def build_notify_resp(subscription_id, opts \\ []) do
    msg_id = Keyword.get(opts, :msg_id, generate_msg_id())

    alias Caretaker.Proto.Usp.{NotifyResp, Response}

    %Msg{
      header: %Header{
        msg_id: msg_id,
        msg_type: :NOTIFY_RESP
      },
      body: %Body{
        msg_body:
          {:response,
           %Response{
             resp_type:
               {:notify_resp,
                %NotifyResp{
                  subscription_id: subscription_id
                }}
           }}
      }
    }
  end

  @doc """
  Wraps a USP Message in a Record for transport.

  ## Parameters

  - `msg` - The USP Message to wrap
  - `opts` - Options:
    - `:to_id` - Destination endpoint ID
    - `:from_id` - Source endpoint ID
    - `:version` - USP version (default: "1.3")

  """
  @spec wrap_in_record(Msg.t(), keyword()) :: Record.t()
  def wrap_in_record(%Msg{} = msg, opts \\ []) do
    alias Caretaker.Proto.UspRecord.NoSessionContextRecord

    {:ok, payload} = encode(msg)

    %Record{
      version: Keyword.get(opts, :version, "1.3"),
      to_id: Keyword.get(opts, :to_id, ""),
      from_id: Keyword.get(opts, :from_id, ""),
      payload_security: :PLAINTEXT,
      record_type:
        {:no_session_context,
         %NoSessionContextRecord{
           payload: payload
         }}
    }
  end

  @doc """
  Unwraps a USP Message from a Record.
  """
  @spec unwrap_from_record(Record.t()) :: {:ok, Msg.t()} | {:error, term()}
  def unwrap_from_record(%Record{} = record) do
    case record.record_type do
      {:no_session_context, %{payload: payload}} ->
        decode(payload)

      {:session_context, %{payload: payload}} ->
        decode(payload)

      _ ->
        {:error, :unsupported_record_type}
    end
  end

  @doc """
  Extracts the message type from a USP Message.
  """
  @spec message_type(Msg.t()) :: atom()
  def message_type(%Msg{header: %Header{msg_type: type}}), do: type

  @doc """
  Extracts the message ID from a USP Message.
  """
  @spec message_id(Msg.t()) :: String.t()
  def message_id(%Msg{header: %Header{msg_id: id}}), do: id

  @doc """
  Checks if a message is a request.
  """
  @spec request?(Msg.t()) :: boolean()
  def request?(%Msg{body: %Body{msg_body: {:request, _}}}), do: true
  def request?(_), do: false

  @doc """
  Checks if a message is a response.
  """
  @spec response?(Msg.t()) :: boolean()
  def response?(%Msg{body: %Body{msg_body: {:response, _}}}), do: true
  def response?(_), do: false

  @doc """
  Checks if a message is an error.
  """
  @spec error?(Msg.t()) :: boolean()
  def error?(%Msg{body: %Body{msg_body: {:error, _}}}), do: true
  def error?(_), do: false
end
