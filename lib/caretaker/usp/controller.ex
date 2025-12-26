defmodule Caretaker.USP.Controller do
  @moduledoc """
  USP Controller implementation for server-side TR-369 support.

  The Controller is the server-side component that manages USP Agents,
  similar to the ACS in TR-069. It handles:

  - Agent registration and deregistration
  - Sending requests to agents (Get, Set, Add, Delete, Operate)
  - Receiving notifications from agents
  - Managing per-agent sessions and command queues

  ## Integration with TR-069 Components

  The Controller reuses existing TR-069 ACS components:
  - `Caretaker.ACS.DeviceDetection` for agent identification
  - `Caretaker.Quirks` for vendor-specific behaviors
  - `Caretaker.ACS.ParameterMapping` for canonical parameter names

  ## Example

      # Start a controller
      {:ok, controller} = Caretaker.USP.Controller.start_link(
        endpoint_id: "self::acs.example.com"
      )

      # Send a Get request to an agent
      {:ok, response} = Caretaker.USP.Controller.get(
        controller,
        "os::ACME-Router-12345",
        ["Device.DeviceInfo."]
      )

  """

  use GenServer
  require Logger

  alias Caretaker.USP.{Proto, Record, Telemetry}
  alias Caretaker.Proto.Usp.{Msg, Header, Body, Response, Request}

  @type agent_id :: String.t()
  @type session :: %{
          agent_id: agent_id(),
          connected_at: DateTime.t(),
          last_message_at: DateTime.t(),
          pending_requests: map(),
          command_queue: :queue.queue()
        }

  @type state :: %{
          endpoint_id: String.t(),
          agents: %{agent_id() => session()},
          transport: module() | nil,
          transport_state: term()
        }

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts a USP Controller.

  ## Options

  - `:endpoint_id` - The controller's endpoint ID (required)
  - `:transport` - Transport module (optional, for actual network communication)
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
  Gets the controller's endpoint ID.
  """
  @spec endpoint_id(GenServer.server()) :: String.t()
  def endpoint_id(controller) do
    GenServer.call(controller, :get_endpoint_id)
  end

  @doc """
  Lists all connected agents.
  """
  @spec list_agents(GenServer.server()) :: [agent_id()]
  def list_agents(controller) do
    GenServer.call(controller, :list_agents)
  end

  @doc """
  Gets information about a specific agent.
  """
  @spec get_agent(GenServer.server(), agent_id()) :: {:ok, map()} | {:error, :not_found}
  def get_agent(controller, agent_id) do
    GenServer.call(controller, {:get_agent, agent_id})
  end

  @doc """
  Handles an incoming message from an agent.

  This is used when the Controller receives a message (Register, Notify, etc.)
  from an agent through the transport layer.
  """
  @spec handle_agent_message(GenServer.server(), agent_id(), Msg.t()) ::
          {:ok, Msg.t() | nil} | {:error, term()}
  def handle_agent_message(controller, agent_id, msg) do
    GenServer.call(controller, {:handle_agent_message, agent_id, msg})
  end

  @doc """
  Handles an incoming record from an agent.
  """
  @spec handle_agent_record(GenServer.server(), Record.t()) ::
          {:ok, Record.t() | nil} | {:error, term()}
  def handle_agent_record(controller, record) do
    GenServer.call(controller, {:handle_agent_record, record})
  end

  @doc """
  Sends a Get request to an agent and waits for response.

  This is a synchronous operation that blocks until the response is received.
  For async operations, use `queue_get/3`.
  """
  @spec get(GenServer.server(), agent_id(), [String.t()], keyword()) ::
          {:ok, Msg.t()} | {:error, term()}
  def get(controller, agent_id, param_paths, opts \\ []) do
    GenServer.call(controller, {:get, agent_id, param_paths, opts})
  end

  @doc """
  Sends a Set request to an agent.
  """
  @spec set(GenServer.server(), agent_id(), [{String.t(), keyword()}], keyword()) ::
          {:ok, Msg.t()} | {:error, term()}
  def set(controller, agent_id, updates, opts \\ []) do
    GenServer.call(controller, {:set, agent_id, updates, opts})
  end

  @doc """
  Sends an Add request to an agent.
  """
  @spec add(GenServer.server(), agent_id(), [{String.t(), keyword()}], keyword()) ::
          {:ok, Msg.t()} | {:error, term()}
  def add(controller, agent_id, creates, opts \\ []) do
    GenServer.call(controller, {:add, agent_id, creates, opts})
  end

  @doc """
  Sends a Delete request to an agent.
  """
  @spec delete(GenServer.server(), agent_id(), [String.t()], keyword()) ::
          {:ok, Msg.t()} | {:error, term()}
  def delete(controller, agent_id, obj_paths, opts \\ []) do
    GenServer.call(controller, {:delete, agent_id, obj_paths, opts})
  end

  @doc """
  Sends an Operate request to an agent.
  """
  @spec operate(GenServer.server(), agent_id(), String.t(), map(), keyword()) ::
          {:ok, Msg.t()} | {:error, term()}
  def operate(controller, agent_id, command, input_args \\ %{}, opts \\ []) do
    GenServer.call(controller, {:operate, agent_id, command, input_args, opts})
  end

  @doc """
  Queues a Get request for an agent (async).

  Returns the message ID which can be used to match the response later.
  """
  @spec queue_get(GenServer.server(), agent_id(), [String.t()]) ::
          {:ok, String.t()} | {:error, term()}
  def queue_get(controller, agent_id, param_paths) do
    GenServer.call(controller, {:queue_get, agent_id, param_paths})
  end

  @doc """
  Gets the next queued command for an agent.

  Used by transport layer to get commands to send to agents.
  """
  @spec next_command(GenServer.server(), agent_id()) ::
          {:ok, Msg.t()} | {:empty, nil} | {:error, :not_found}
  def next_command(controller, agent_id) do
    GenServer.call(controller, {:next_command, agent_id})
  end

  @doc """
  Registers a response callback for a pending request.

  Used internally to match responses to requests.
  """
  @spec register_pending_request(GenServer.server(), agent_id(), String.t(), pid()) :: :ok
  def register_pending_request(controller, agent_id, msg_id, caller) do
    GenServer.call(controller, {:register_pending, agent_id, msg_id, caller})
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    endpoint_id = Keyword.fetch!(opts, :endpoint_id)
    transport = Keyword.get(opts, :transport)

    state = %{
      endpoint_id: endpoint_id,
      agents: %{},
      transport: transport,
      transport_state: nil
    }

    Logger.debug("USP Controller started: #{endpoint_id}")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_endpoint_id, _from, state) do
    {:reply, state.endpoint_id, state}
  end

  @impl true
  def handle_call(:list_agents, _from, state) do
    agent_ids = Map.keys(state.agents)
    {:reply, agent_ids, state}
  end

  @impl true
  def handle_call({:get_agent, agent_id}, _from, state) do
    case Map.get(state.agents, agent_id) do
      nil -> {:reply, {:error, :not_found}, state}
      session -> {:reply, {:ok, session}, state}
    end
  end

  @impl true
  def handle_call({:handle_agent_message, agent_id, msg}, _from, state) do
    Telemetry.emit_controller_message_received(msg, %{agent_id: agent_id})

    case process_agent_message(agent_id, msg, state) do
      {:ok, response, new_state} ->
        if response do
          Telemetry.emit_controller_message_sent(response, %{agent_id: agent_id})
        end
        {:reply, {:ok, response}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:handle_agent_record, record}, _from, state) do
    agent_id = record.from_id

    case Record.extract_message(record) do
      {:ok, msg} ->
        Telemetry.emit_controller_message_received(msg, %{agent_id: agent_id})

        case process_agent_message(agent_id, msg, state) do
          {:ok, response, new_state} ->
            response_record = if response do
              Telemetry.emit_controller_message_sent(response, %{agent_id: agent_id})
              Record.response_for(record, response)
            else
              nil
            end
            {:reply, {:ok, response_record}, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, :no_payload} ->
        # Handle connect/disconnect records
        case Record.record_type(record) do
          type when type in [:websocket_connect, :mqtt_connect, :stomp_connect] ->
            new_state = register_agent(agent_id, state)
            {:reply, {:ok, nil}, new_state}

          :disconnect ->
            new_state = unregister_agent(agent_id, state)
            {:reply, {:ok, nil}, new_state}

          _ ->
            {:reply, {:ok, nil}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get, agent_id, param_paths, opts}, from, state) do
    msg = Proto.build_get(param_paths, opts)
    send_request_to_agent(agent_id, msg, from, state)
  end

  @impl true
  def handle_call({:set, agent_id, updates, opts}, from, state) do
    msg = Proto.build_set(updates, opts)
    send_request_to_agent(agent_id, msg, from, state)
  end

  @impl true
  def handle_call({:add, agent_id, creates, opts}, from, state) do
    msg = Proto.build_add(creates, opts)
    send_request_to_agent(agent_id, msg, from, state)
  end

  @impl true
  def handle_call({:delete, agent_id, obj_paths, opts}, from, state) do
    msg = Proto.build_delete(obj_paths, opts)
    send_request_to_agent(agent_id, msg, from, state)
  end

  @impl true
  def handle_call({:operate, agent_id, command, input_args, opts}, from, state) do
    msg = Proto.build_operate(command, input_args, opts)
    send_request_to_agent(agent_id, msg, from, state)
  end

  @impl true
  def handle_call({:queue_get, agent_id, param_paths}, _from, state) do
    msg = Proto.build_get(param_paths)
    new_state = queue_command(agent_id, msg, state)
    {:reply, {:ok, Proto.message_id(msg)}, new_state}
  end

  @impl true
  def handle_call({:next_command, agent_id}, _from, state) do
    case Map.get(state.agents, agent_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      session ->
        case :queue.out(session.command_queue) do
          {{:value, msg}, new_queue} ->
            new_session = %{session | command_queue: new_queue}
            new_state = put_in(state.agents[agent_id], new_session)
            {:reply, {:ok, msg}, new_state}

          {:empty, _} ->
            {:reply, {:empty, nil}, state}
        end
    end
  end

  @impl true
  def handle_call({:register_pending, agent_id, msg_id, caller}, _from, state) do
    case Map.get(state.agents, agent_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      session ->
        new_pending = Map.put(session.pending_requests, msg_id, caller)
        new_session = %{session | pending_requests: new_pending}
        new_state = put_in(state.agents[agent_id], new_session)
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_info({:response_timeout, agent_id, msg_id}, state) do
    case get_in(state.agents, [agent_id, :pending_requests, msg_id]) do
      nil ->
        {:noreply, state}

      caller ->
        GenServer.reply(caller, {:error, :timeout})
        new_state = update_in(state.agents[agent_id].pending_requests, &Map.delete(&1, msg_id))
        {:noreply, new_state}
    end
  end

  # ============================================================================
  # Message Processing
  # ============================================================================

  defp process_agent_message(agent_id, %Msg{header: header, body: body} = msg, state) do
    msg_id = header.msg_id

    case body.msg_body do
      {:request, request} ->
        # Agent sending a request (Register, Notify, Deregister)
        process_agent_request(agent_id, request, msg_id, state)

      {:response, _response} ->
        # Agent responding to a Controller request
        process_agent_response(agent_id, msg_id, msg, state)

      {:error, error} ->
        # Agent sending an error
        Logger.warning("Received error from agent #{agent_id}: #{error.err_msg}")
        process_agent_response(agent_id, msg_id, msg, state)
    end
  end

  defp process_agent_request(agent_id, %Request{req_type: req_type}, msg_id, state) do
    case req_type do
      {:register, register} ->
        handle_register(agent_id, register, msg_id, state)

      {:deregister, _deregister} ->
        handle_deregister(agent_id, msg_id, state)

      {:notify, notify} ->
        handle_notify(agent_id, notify, msg_id, state)

      _ ->
        # Controller doesn't expect other request types from agents
        {:error, :unexpected_request}
    end
  end

  defp process_agent_response(agent_id, msg_id, msg, state) do
    # Look up pending request and deliver response
    case get_in(state.agents, [agent_id, :pending_requests, msg_id]) do
      nil ->
        Logger.debug("Received response for unknown request #{msg_id} from #{agent_id}")
        {:ok, nil, state}

      caller ->
        GenServer.reply(caller, {:ok, msg})
        new_state = update_in(state.agents[agent_id].pending_requests, &Map.delete(&1, msg_id))
        {:ok, nil, new_state}
    end
  end

  # ============================================================================
  # Request Handlers
  # ============================================================================

  defp handle_register(agent_id, _register, msg_id, state) do
    Logger.info("Agent registered: #{agent_id}")
    Telemetry.emit_agent_connected(agent_id)

    new_state = register_agent(agent_id, state)

    # Build RegisterResp
    alias Caretaker.Proto.Usp.{RegisterResp, RegisteredPathResult, OperationStatus, OperationSuccess}

    response = %Msg{
      header: %Header{
        msg_id: msg_id,
        msg_type: :REGISTER_RESP
      },
      body: %Body{
        msg_body: {:response, %Response{
          resp_type: {:register_resp, %RegisterResp{
            registered_path_results: [
              %RegisteredPathResult{
                requested_path: "Device.",
                oper_status: %OperationStatus{
                  oper_status: {:oper_success, %OperationSuccess{}}
                }
              }
            ]
          }}
        }}
      }
    }

    {:ok, response, new_state}
  end

  defp handle_deregister(agent_id, msg_id, state) do
    Logger.info("Agent deregistered: #{agent_id}")
    Telemetry.emit_agent_disconnected(agent_id)

    new_state = unregister_agent(agent_id, state)

    # Build DeregisterResp
    alias Caretaker.Proto.Usp.{DeregisterResp, DeregisteredPathResult, OperationStatus, OperationSuccess}

    response = %Msg{
      header: %Header{
        msg_id: msg_id,
        msg_type: :DEREGISTER_RESP
      },
      body: %Body{
        msg_body: {:response, %Response{
          resp_type: {:deregister_resp, %DeregisterResp{
            deregistered_path_results: [
              %DeregisteredPathResult{
                requested_path: "Device.",
                oper_status: %OperationStatus{
                  oper_status: {:oper_success, %OperationSuccess{}}
                }
              }
            ]
          }}
        }}
      }
    }

    {:ok, response, new_state}
  end

  defp handle_notify(agent_id, notify, msg_id, state) do
    # Log the notification
    case notify.notification do
      {:value_change, vc} ->
        Logger.debug("Value change from #{agent_id}: #{vc.param_path} = #{vc.param_value}")

      {:event, event} ->
        Logger.debug("Event from #{agent_id}: #{event.event_name}")

      {:obj_creation, oc} ->
        Logger.debug("Object created on #{agent_id}: #{oc.obj_path}")

      {:obj_deletion, od} ->
        Logger.debug("Object deleted on #{agent_id}: #{od.obj_path}")

      {:oper_complete, oc} ->
        Logger.debug("Operation complete on #{agent_id}: #{oc.command_name}")

      {:on_board_req, _} ->
        Logger.debug("Onboard request from #{agent_id}")

      _ ->
        :ok
    end

    # Update last message timestamp
    new_state = update_agent_activity(agent_id, state)

    # Send NotifyResp if requested
    response = if notify.send_resp do
      Proto.build_notify_resp(notify.subscription_id, msg_id: msg_id)
    else
      nil
    end

    {:ok, response, new_state}
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp register_agent(agent_id, state) do
    session = %{
      agent_id: agent_id,
      connected_at: DateTime.utc_now(),
      last_message_at: DateTime.utc_now(),
      pending_requests: %{},
      command_queue: :queue.new()
    }

    put_in(state.agents[agent_id], session)
  end

  defp unregister_agent(agent_id, state) do
    # Cancel any pending request timeouts
    case Map.get(state.agents, agent_id) do
      nil ->
        state

      session ->
        # Reply with error to all pending requests
        Enum.each(session.pending_requests, fn {_msg_id, caller} ->
          GenServer.reply(caller, {:error, :agent_disconnected})
        end)

        update_in(state.agents, &Map.delete(&1, agent_id))
    end
  end

  defp update_agent_activity(agent_id, state) do
    case Map.get(state.agents, agent_id) do
      nil -> state
      session ->
        new_session = %{session | last_message_at: DateTime.utc_now()}
        put_in(state.agents[agent_id], new_session)
    end
  end

  defp queue_command(agent_id, msg, state) do
    case Map.get(state.agents, agent_id) do
      nil ->
        # Auto-register if not connected
        session = %{
          agent_id: agent_id,
          connected_at: DateTime.utc_now(),
          last_message_at: DateTime.utc_now(),
          pending_requests: %{},
          command_queue: :queue.in(msg, :queue.new())
        }
        put_in(state.agents[agent_id], session)

      session ->
        new_queue = :queue.in(msg, session.command_queue)
        new_session = %{session | command_queue: new_queue}
        put_in(state.agents[agent_id], new_session)
    end
  end

  defp send_request_to_agent(agent_id, msg, from, state) do
    msg_id = Proto.message_id(msg)

    # Ensure agent is registered
    new_state = case Map.get(state.agents, agent_id) do
      nil -> register_agent(agent_id, state)
      _ -> state
    end

    # Register pending request
    new_pending = Map.put(new_state.agents[agent_id].pending_requests, msg_id, from)
    new_session = %{new_state.agents[agent_id] | pending_requests: new_pending}
    final_state = put_in(new_state.agents[agent_id], new_session)

    # Set timeout
    timeout = 30_000
    Process.send_after(self(), {:response_timeout, agent_id, msg_id}, timeout)

    # Queue the message for transport
    # In a real implementation, this would send through the transport layer
    final_state_with_queue = queue_command(agent_id, msg, final_state)

    Telemetry.emit_controller_message_sent(msg, %{agent_id: agent_id})

    # For now, we don't reply immediately - the caller will wait for the response
    {:noreply, final_state_with_queue}
  end
end
