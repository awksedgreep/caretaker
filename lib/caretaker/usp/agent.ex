defmodule Caretaker.USP.Agent do
  @moduledoc """
  USP Agent implementation for device-side TR-369 support.

  The Agent is the device-side component that responds to Controller requests,
  similar to the CPE in TR-069. It manages device state and handles:

  - Get requests (read parameters)
  - Set requests (write parameters)
  - Add requests (create object instances)
  - Delete requests (remove object instances)
  - Operate requests (execute commands)
  - GetSupportedDM requests (data model discovery)
  - GetInstances requests (instance enumeration)

  ## Integration with TR-069 Components

  The Agent reuses existing TR-069 components:
  - `Caretaker.CPE.DeviceState` for parameter storage
  - `Caretaker.TR181.Model` for data model operations
  - Device profiles from `priv/profiles/`

  ## Example

      # Start an agent with a fiber ONT profile
      {:ok, agent} = Caretaker.USP.Agent.start_link(
        endpoint_id: "os::012345-GPON-ABC123",
        profile: :fiber_ont
      )

      # Handle a Get request
      get_msg = Caretaker.USP.Proto.build_get(["Device.DeviceInfo."])
      {:ok, response} = Caretaker.USP.Agent.handle_message(agent, get_msg)

  """

  use GenServer
  require Logger

  alias Caretaker.USP.{Proto, Record, Telemetry}
  alias Caretaker.CPE.DeviceState
  alias Caretaker.Proto.Usp.{Msg, Header, Body, Request}

  @type state :: %{
          endpoint_id: String.t(),
          device_state: pid(),
          controller_id: String.t() | nil,
          connected: boolean(),
          subscriptions: map()
        }

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts a USP Agent.

  ## Options

  - `:endpoint_id` - The agent's endpoint ID (required)
  - `:profile` - Device profile to load (:fiber_ont, :cable_modem, or custom)
  - `:initial_params` - Initial parameter values (merged with profile)
  - `:name` - Optional GenServer name

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    _endpoint_id = Keyword.fetch!(opts, :endpoint_id)
    name = Keyword.get(opts, :name)

    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Handles an incoming USP Message and returns a response.
  """
  @spec handle_message(GenServer.server(), Msg.t()) :: {:ok, Msg.t()} | {:error, term()}
  def handle_message(agent, %Msg{} = msg) do
    GenServer.call(agent, {:handle_message, msg})
  end

  @doc """
  Handles an incoming USP Record and returns a response Record.
  """
  @spec handle_record(GenServer.server(), Record.t()) ::
          {:ok, Record.t() | nil} | {:error, term()}
  def handle_record(agent, record) do
    GenServer.call(agent, {:handle_record, record})
  end

  @doc """
  Gets the agent's endpoint ID.
  """
  @spec endpoint_id(GenServer.server()) :: String.t()
  def endpoint_id(agent) do
    GenServer.call(agent, :get_endpoint_id)
  end

  @doc """
  Gets the current device state.
  """
  @spec get_state(GenServer.server()) :: map()
  def get_state(agent) do
    GenServer.call(agent, :get_device_state)
  end

  @doc """
  Sets a parameter value and optionally sends a ValueChange notification.
  """
  @spec set_parameter(GenServer.server(), String.t(), term()) :: :ok | {:error, term()}
  def set_parameter(agent, path, value) do
    GenServer.call(agent, {:set_parameter, path, value})
  end

  @doc """
  Builds a Register message for this agent.
  """
  @spec build_register_message(GenServer.server()) :: Msg.t()
  def build_register_message(agent) do
    GenServer.call(agent, :build_register_message)
  end

  @doc """
  Connects the agent to a controller.
  """
  @spec connect(GenServer.server(), String.t()) :: :ok
  def connect(agent, controller_id) do
    GenServer.call(agent, {:connect, controller_id})
  end

  @doc """
  Disconnects the agent from the controller.
  """
  @spec disconnect(GenServer.server()) :: :ok
  def disconnect(agent) do
    GenServer.call(agent, :disconnect)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    endpoint_id = Keyword.fetch!(opts, :endpoint_id)
    profile = Keyword.get(opts, :profile)
    initial_params = Keyword.get(opts, :initial_params, %{})

    # Parse endpoint ID to extract device info
    device_id = parse_endpoint_id(endpoint_id)

    # Start device state
    {:ok, device_state} = start_device_state(device_id, profile, initial_params)

    state = %{
      endpoint_id: endpoint_id,
      device_id: device_id,
      device_state: device_state,
      controller_id: nil,
      connected: false,
      subscriptions: %{}
    }

    Logger.debug("USP Agent started: #{endpoint_id}")
    {:ok, state}
  end

  @impl true
  def handle_call({:handle_message, msg}, _from, state) do
    Telemetry.emit_agent_message_received(msg, %{endpoint_id: state.endpoint_id})

    case process_message(msg, state) do
      {:ok, response, new_state} ->
        Telemetry.emit_agent_message_sent(response, %{endpoint_id: state.endpoint_id})
        {:reply, {:ok, response}, new_state}

      {:error, reason} ->
        error_msg = Proto.build_error(7000, "Message processing failed: #{inspect(reason)}")
        {:reply, {:ok, error_msg}, state}
    end
  end

  @impl true
  def handle_call({:handle_record, record}, _from, state) do
    case Record.extract_message(record) do
      {:ok, msg} ->
        Telemetry.emit_agent_message_received(msg, %{endpoint_id: state.endpoint_id})

        case process_message(msg, state) do
          {:ok, response, new_state} ->
            response_record = Record.response_for(record, response)
            Telemetry.emit_agent_message_sent(response, %{endpoint_id: state.endpoint_id})
            {:reply, {:ok, response_record}, new_state}

          {:error, reason} ->
            error_msg = Proto.build_error(7000, "Message processing failed: #{inspect(reason)}")
            response_record = Record.response_for(record, error_msg)
            {:reply, {:ok, response_record}, state}
        end

      {:error, :no_payload} ->
        # Connect/disconnect records don't need message processing
        {:reply, {:ok, nil}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_endpoint_id, _from, state) do
    {:reply, state.endpoint_id, state}
  end

  @impl true
  def handle_call(:get_device_state, _from, state) do
    params = DeviceState.get_tree(state.device_state, "Device.")
    {:reply, params, state}
  end

  @impl true
  def handle_call({:set_parameter, path, value}, _from, state) do
    result = DeviceState.set(state.device_state, path, value)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:build_register_message, _from, state) do
    msg = Proto.build_register(["Device."])
    {:reply, msg, state}
  end

  @impl true
  def handle_call({:connect, controller_id}, _from, state) do
    Telemetry.emit_agent_register(state.endpoint_id, %{controller_id: controller_id})
    new_state = %{state | controller_id: controller_id, connected: true}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:disconnect, _from, state) do
    Telemetry.emit_agent_deregister(state.endpoint_id, %{controller_id: state.controller_id})
    new_state = %{state | controller_id: nil, connected: false}
    {:reply, :ok, new_state}
  end

  # ============================================================================
  # Message Processing
  # ============================================================================

  defp process_message(%Msg{header: header, body: body}, state) do
    msg_id = header.msg_id

    case body.msg_body do
      {:request, request} ->
        process_request(request, msg_id, state)

      {:response, _response} ->
        # Agents typically don't receive responses
        {:error, :unexpected_response}

      {:error, _error} ->
        # Agents typically don't receive errors
        {:error, :unexpected_error}
    end
  end

  defp process_request(%Request{req_type: req_type}, msg_id, state) do
    case req_type do
      {:get, get} ->
        handle_get(get, msg_id, state)

      {:set, set} ->
        handle_set(set, msg_id, state)

      {:add, add} ->
        handle_add(add, msg_id, state)

      {:delete, delete} ->
        handle_delete(delete, msg_id, state)

      {:operate, operate} ->
        handle_operate(operate, msg_id, state)

      {:get_supported_dm, get_dm} ->
        handle_get_supported_dm(get_dm, msg_id, state)

      {:get_instances, get_inst} ->
        handle_get_instances(get_inst, msg_id, state)

      {:notify, _notify} ->
        # Controller shouldn't send Notify to Agent
        {:error, :unexpected_notify}

      {:register, _register} ->
        # Controller shouldn't send Register to Agent
        {:error, :unexpected_register}

      {:deregister, _deregister} ->
        # Controller shouldn't send Deregister to Agent
        {:error, :unexpected_deregister}

      {:get_supported_protocol, _} ->
        handle_get_supported_protocol(msg_id, state)

      _ ->
        {:error, :unsupported_request}
    end
  end

  # ============================================================================
  # Request Handlers
  # ============================================================================

  defp handle_get(get, msg_id, state) do
    results =
      Enum.map(get.param_paths, fn path ->
        case get_parameters_for_path(path, state) do
          {:ok, params} ->
            {path, [{path, params}]}

          {:error, _reason} ->
            {path, []}
        end
      end)

    response = Proto.build_get_resp(results, msg_id: msg_id)
    {:ok, response, state}
  end

  defp handle_set(set, msg_id, state) do
    results =
      Enum.flat_map(set.update_objs, fn update_obj ->
        Enum.map(update_obj.param_settings, fn setting ->
          full_path = update_obj.obj_path <> setting.param
          :ok = DeviceState.set(state.device_state, full_path, setting.value)
          {full_path, :success}
        end)
      end)

    response = Proto.build_set_resp(results, msg_id: msg_id)
    {:ok, response, state}
  end

  defp handle_add(add, msg_id, state) do
    results =
      Enum.map(add.create_objs, fn create_obj ->
        # For now, simulate creating an instance
        instance_num = :rand.uniform(1000)
        instance_path = create_obj.obj_path <> "#{instance_num}."

        # Set initial parameters
        Enum.each(create_obj.param_settings, fn setting ->
          DeviceState.set(state.device_state, instance_path <> setting.param, setting.value)
        end)

        {create_obj.obj_path, {:ok, instance_path}}
      end)

    response = Proto.build_add_resp(results, msg_id: msg_id)
    {:ok, response, state}
  end

  defp handle_delete(delete, msg_id, state) do
    results =
      Enum.map(delete.obj_paths, fn path ->
        # For now, simulate successful deletion
        {path, :success}
      end)

    response = Proto.build_delete_resp(results, msg_id: msg_id)
    {:ok, response, state}
  end

  defp handle_operate(operate, msg_id, state) do
    # Basic operation handling
    alias Caretaker.Proto.Usp.{OperateResp, OutputArgs, Response}

    response = %Msg{
      header: %Header{
        msg_id: msg_id,
        msg_type: :OPERATE_RESP
      },
      body: %Body{
        msg_body:
          {:response,
           %Response{
             resp_type:
               {:operate_resp,
                %OperateResp{
                  operation_results: operate.command,
                  operation_resp:
                    {:req_output_args,
                     %OutputArgs{
                       output_args: %{"Status" => "Success"}
                     }}
                }}
           }}
      }
    }

    {:ok, response, state}
  end

  defp handle_get_supported_dm(_get_dm, msg_id, state) do
    alias Caretaker.Proto.Usp.{GetSupportedDMResp, RequestedObjectResult, Response}

    # Return basic data model info
    response = %Msg{
      header: %Header{
        msg_id: msg_id,
        msg_type: :GET_SUPPORTED_DM_RESP
      },
      body: %Body{
        msg_body:
          {:response,
           %Response{
             resp_type:
               {:get_supported_dm_resp,
                %GetSupportedDMResp{
                  req_obj_results: [
                    %RequestedObjectResult{
                      req_obj_path: "Device.",
                      err_code: 0,
                      err_msg: "",
                      data_model_inst_uri: "urn:broadband-forum-org:tr-181-2-16-0",
                      supported_objs: []
                    }
                  ]
                }}
           }}
      }
    }

    {:ok, response, state}
  end

  defp handle_get_instances(_get_inst, msg_id, state) do
    alias Caretaker.Proto.Usp.{GetInstancesResp, Response}

    response = %Msg{
      header: %Header{
        msg_id: msg_id,
        msg_type: :GET_INSTANCES_RESP
      },
      body: %Body{
        msg_body:
          {:response,
           %Response{
             resp_type:
               {:get_instances_resp,
                %GetInstancesResp{
                  req_path_results: []
                }}
           }}
      }
    }

    {:ok, response, state}
  end

  defp handle_get_supported_protocol(msg_id, state) do
    alias Caretaker.Proto.Usp.{GetSupportedProtocolResp, Response}

    response = %Msg{
      header: %Header{
        msg_id: msg_id,
        msg_type: :GET_SUPPORTED_PROTO_RESP
      },
      body: %Body{
        msg_body:
          {:response,
           %Response{
             resp_type:
               {:get_supported_protocol_resp,
                %GetSupportedProtocolResp{
                  agent_supported_protocol_versions: "1.0,1.1,1.2,1.3"
                }}
           }}
      }
    }

    {:ok, response, state}
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp start_device_state(device_id, profile, initial_params) do
    profile_params = load_profile(profile)
    merged_params = deep_merge(profile_params, initial_params)

    DeviceState.start_link(
      device_id: device_id,
      params: merged_params
    )
  end

  defp parse_endpoint_id(endpoint_id) do
    # Endpoint ID format: authority::instance
    # Instance format varies, but for agents typically: OUI-ProductClass-SerialNumber
    case String.split(endpoint_id, "::", parts: 2) do
      [_authority, instance] ->
        parts = String.split(instance, "-", parts: 3)

        case parts do
          [oui, product_class, serial] ->
            %{oui: oui, product_class: product_class, serial_number: serial}

          [oui, serial] ->
            %{oui: oui, product_class: "Generic", serial_number: serial}

          [id] ->
            %{oui: "000000", product_class: "USP", serial_number: id}
        end

      _ ->
        %{oui: "000000", product_class: "USP", serial_number: endpoint_id}
    end
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn
      _key, left_val, right_val when is_map(left_val) and is_map(right_val) ->
        deep_merge(left_val, right_val)

      _key, _left_val, right_val ->
        right_val
    end)
  end

  defp deep_merge(_left, right), do: right

  defp load_profile(nil), do: %{}
  defp load_profile(:fiber_ont), do: load_profile_file("fiber_ont.json")
  defp load_profile(:cable_modem), do: load_profile_file("cable_modem.json")
  defp load_profile(name) when is_atom(name), do: load_profile_file("#{name}.json")
  defp load_profile(params) when is_map(params), do: params

  defp load_profile_file(filename) do
    path = Application.app_dir(:caretaker, ["priv", "profiles", filename])

    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, params} -> params
          _ -> %{}
        end

      _ ->
        %{}
    end
  end

  defp get_parameters_for_path(path, state) do
    if String.ends_with?(path, ".") do
      {:ok, flatten_tree(DeviceState.get_tree(state.device_state, path), path)}
    else
      case DeviceState.get(state.device_state, path) do
        nil -> {:error, :not_found}
        value -> {:ok, %{path => to_string(value)}}
      end
    end
  end

  defp flatten_tree(tree, prefix) when is_map(tree) do
    Enum.reduce(tree, %{}, fn {key, value}, acc ->
      full_key = prefix <> key

      case value do
        v when is_map(v) ->
          Map.merge(acc, flatten_tree(v, full_key <> "."))

        v ->
          Map.put(acc, full_key, to_string(v))
      end
    end)
  end
end
