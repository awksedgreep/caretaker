defmodule Caretaker.ACS.Tasks do
  @moduledoc """
  Task registry for the northbound ACS API.

  A *task* is one queued TR-069 change or read for a device, tracked through a
  lifecycle so an external change agent can submit work, learn its outcome, and
  cancel or expire it safely. Tasks are correlated to the CWMP session by the
  `cwmp:ID` the ACS puts on the request the device eventually answers.

  Lifecycle: `queued -> delivered -> applied | faulted`, plus `expired` (TTL
  reached before delivery) and `cancelled`. Every task reaches exactly one
  terminal state (`applied | faulted | expired | cancelled`).

  This registry depends on `Caretaker.ACS.Session` (the per-device command
  queue) and works with `Caretaker.ACS.Server`, which reports delivery and
  completion back here. Presence tracking subscribes to `Caretaker.PubSub`.

  ## Options (`start_link/1`)

    - `:webhook_url` - POST terminal-state events here (CR-5); optional
    - `:webhook_secret` - HMAC-SHA256 signing key for webhook bodies
    - `:default_ttl_ms` - default task TTL (default 6h); expiry is opt-out
    - `:retention_ms` - how long terminal tasks are kept (default 90 days)
    - `:rate_limit` - accepted submissions per second (default 50)
    - `:name` - GenServer name (default `#{inspect(__MODULE__)}`)
  """

  use GenServer

  alias Caretaker.ACS.Session
  alias Caretaker.HTTP
  alias Caretaker.TR069.RPC.{GetParameterValues, SetParameterValues}

  @default_ttl_ms :timer.hours(6)
  @default_retention_ms :timer.hours(24) * 90
  @default_rate_limit 50
  @sweep_interval :timer.seconds(30)

  @type device_id :: %{
          required(:oui) => String.t(),
          required(:product_class) => String.t(),
          required(:serial_number) => String.t()
        }
  @type task_id :: String.t()

  # ============================================================================
  # Client API
  # ============================================================================

  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Queue a SetParameterValues task. `parameters` is a list of maps with :path/:value and optional :type."
  @spec submit_set(device_id(), [map()], keyword()) ::
          {:ok, task_id()} | {:error, term()}
  def submit_set(device_id, parameters, opts \\ []) do
    GenServer.call(__MODULE__, {:submit, :set, device_id, parameters, opts})
  end

  @doc "Queue a GetParameterValues task over `paths`."
  @spec submit_get(device_id(), [String.t()], keyword()) ::
          {:ok, task_id()} | {:error, term()}
  def submit_get(device_id, paths, opts \\ []) do
    GenServer.call(__MODULE__, {:submit, :get, device_id, paths, opts})
  end

  @doc "Fetch a task by id."
  @spec get(task_id()) :: {:ok, map()} | {:error, :not_found}
  def get(task_id) do
    GenServer.call(__MODULE__, {:get, task_id})
  end

  @doc "Cancel a not-yet-delivered task."
  @spec cancel(task_id()) ::
          {:ok, :cancelled} | {:error, :not_found | {:already, atom()}}
  def cancel(task_id) do
    GenServer.call(__MODULE__, {:cancel, task_id})
  end

  @doc "Cancel every not-yet-delivered task carrying `tag`. Returns the count cancelled."
  @spec cancel_by_tag(term()) :: {:ok, non_neg_integer()}
  def cancel_by_tag(tag) do
    GenServer.call(__MODULE__, {:cancel_by_tag, tag})
  end

  @doc "Presence for one device: last inform, inform interval, reachability."
  @spec presence(device_id()) :: map()
  def presence(device_id) do
    GenServer.call(__MODULE__, {:presence, device_id})
  end

  @doc "Presence for many devices at once."
  @spec presence_bulk([device_id()]) :: [map()]
  def presence_bulk(device_ids) do
    GenServer.call(__MODULE__, {:presence_bulk, device_ids})
  end

  @doc "Force a device to check in now, reporting whether the connection request itself succeeded."
  @spec connection_request(device_id()) :: map()
  def connection_request(device_id) do
    GenServer.call(__MODULE__, {:connection_request, device_id})
  end

  @doc "Documented throughput limits."
  @spec limits() :: map()
  def limits do
    GenServer.call(__MODULE__, :limits)
  end

  @doc "Reserve one unit of submission budget. `:ok`, or `{:error, {:rate_limited, retry_after_seconds}}`."
  @spec take_token() :: :ok | {:error, {:rate_limited, non_neg_integer()}}
  def take_token do
    GenServer.call(__MODULE__, :take_token)
  end

  # -- called by Caretaker.ACS.Server, keyed by cwmp:ID --

  @spec mark_delivered(String.t()) :: :ok
  def mark_delivered(cwmp_id),
    do: GenServer.cast(__MODULE__, {:mark_delivered, cwmp_id})

  @spec complete(String.t(), map()) :: :ok
  def complete(cwmp_id, data),
    do: GenServer.cast(__MODULE__, {:complete, cwmp_id, data})

  @spec fault(String.t(), map()) :: :ok
  def fault(cwmp_id, data),
    do: GenServer.cast(__MODULE__, {:fault, cwmp_id, data})

  @doc "Task as a JSON-friendly status map (CR-3 shape)."
  @spec to_status(map()) :: map()
  def to_status(task) do
    %{
      "task_id" => task.id,
      "device_id" => device_id_string(task.device_id),
      "type" => Atom.to_string(task.type),
      "state" => Atom.to_string(task.state),
      "submitted_at" => iso(task.submitted_at),
      "delivered_at" => iso(task.delivered_at),
      "completed_at" => iso(task.completed_at),
      "tag" => task.tag,
      "fault" => task.fault && %{"code" => task.fault.code, "message" => task.fault.message},
      "result" => task.result
    }
  end

  @doc "Build the composite device id string \"OUI-ProductClass-SerialNumber\"."
  @spec device_id_string(device_id()) :: String.t()
  def device_id_string(%{oui: oui, product_class: pc, serial_number: sn}),
    do: "#{oui}-#{pc}-#{sn}"

  @doc "Parse \"OUI-ProductClass-SerialNumber\" into a device_id map (serial keeps any dashes)."
  @spec parse_device_id(String.t()) :: {:ok, device_id()} | {:error, :invalid_device_id}
  def parse_device_id(str) when is_binary(str) do
    case String.split(str, "-", parts: 3) do
      [oui, pc, sn] when oui != "" and pc != "" and sn != "" ->
        {:ok, %{oui: oui, product_class: pc, serial_number: sn}}

      _ ->
        {:error, :invalid_device_id}
    end
  end

  # ============================================================================
  # Server
  # ============================================================================

  @impl true
  def init(opts) do
    # Presence tracking is optional: only subscribe when PubSub is running.
    if Process.whereis(Caretaker.PubSub) do
      Caretaker.PubSub.subscribe(Caretaker.PubSub.topic_tr069_inform())
    end

    limit = Keyword.get(opts, :rate_limit, @default_rate_limit)

    state = %{
      tasks: %{},
      by_cwmp: %{},
      by_idem: %{},
      presence: %{},
      webhook_url: Keyword.get(opts, :webhook_url),
      webhook_secret: Keyword.get(opts, :webhook_secret),
      default_ttl_ms: Keyword.get(opts, :default_ttl_ms, @default_ttl_ms),
      retention_ms: Keyword.get(opts, :retention_ms, @default_retention_ms),
      rate: %{limit: limit, tokens: limit * 1.0, last: now_ms()}
    }

    Process.send_after(self(), :sweep, @sweep_interval)
    {:ok, state}
  end

  @impl true
  def handle_call({:submit, type, device_id, spec, opts}, _from, state) do
    with :ok <- require_session(),
         {:ok, device_id} <- normalize_device_id(device_id),
         {:idem, nil} <- {:idem, idem_lookup(state, opts)},
         {:ok, body} <- build_body(type, spec) do
      cwmp_id = gen_cwmp_id()
      task_id = gen_task_id()
      ttl_ms = Keyword.get(opts, :ttl_ms, state.default_ttl_ms)
      tag = Keyword.get(opts, :tag)
      idem = Keyword.get(opts, :idempotency_key)
      dev_key = device_key(device_id)

      :ok = Session.queue_command(dev_key, IO.iodata_to_binary(body), ttl_ms: ttl_ms, tag: tag, id: cwmp_id)

      task = %{
        id: task_id,
        cwmp_id: cwmp_id,
        device_id: device_id,
        device_key: dev_key,
        type: type,
        state: :queued,
        spec: spec,
        result: nil,
        fault: nil,
        submitted_at: DateTime.utc_now(),
        delivered_at: nil,
        completed_at: nil,
        ttl_ms: ttl_ms,
        expires_at_mono: ttl_deadline(ttl_ms),
        tag: tag,
        idempotency_key: idem
      }

      :telemetry.execute([:caretaker, :acs, :task, :submitted], %{}, %{type: type, task_id: task_id})

      state =
        state
        |> put_in([:tasks, task_id], task)
        |> put_in([:by_cwmp, cwmp_id], task_id)
        |> maybe_index_idem(idem, task_id)

      {:reply, {:ok, task_id}, state}
    else
      {:idem, existing} when is_map(existing) ->
        # Same key: same payload returns the existing task; different payload is a conflict.
        if same_payload?(existing, type, spec) do
          {:reply, {:ok, existing.id}, state}
        else
          {:reply, {:error, :idempotency_conflict}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get, task_id}, _from, state) do
    case Map.fetch(state.tasks, task_id) do
      {:ok, task} -> {:reply, {:ok, task}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:cancel, task_id}, _from, state) do
    case Map.fetch(state.tasks, task_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, %{state: :queued} = task} ->
        _ = Session.cancel_by_id(task.cwmp_id)
        {:reply, {:ok, :cancelled}, transition(state, task, :cancelled)}

      {:ok, %{state: other}} ->
        {:reply, {:error, {:already, other}}, state}
    end
  end

  @impl true
  def handle_call({:cancel_by_tag, tag}, _from, state) do
    _ = Session.cancel_by_tag(tag)

    {state, count} =
      state.tasks
      |> Map.values()
      |> Enum.filter(&(&1.tag == tag and &1.state == :queued))
      |> Enum.reduce({state, 0}, fn task, {acc, n} ->
        {transition(acc, task, :cancelled), n + 1}
      end)

    {:reply, {:ok, count}, state}
  end

  @impl true
  def handle_call({:presence, device_id}, _from, state) do
    {:reply, presence_for(state, device_id), state}
  end

  @impl true
  def handle_call({:presence_bulk, device_ids}, _from, state) do
    {:reply, Enum.map(device_ids, &presence_for(state, &1)), state}
  end

  @impl true
  def handle_call({:connection_request, device_id}, _from, state) do
    {:reply, do_connection_request(device_id), state}
  end

  @impl true
  def handle_call(:limits, _from, state) do
    {:reply,
     %{
       "tasks_per_second" => state.rate.limit,
       "default_ttl_seconds" => div(state.default_ttl_ms, 1000),
       "retention_seconds" => div(state.retention_ms, 1000)
     }, state}
  end

  @impl true
  def handle_call(:take_token, _from, state) do
    {result, rate} = take(state.rate)
    {:reply, result, %{state | rate: rate}}
  end

  @impl true
  def handle_cast({:mark_delivered, cwmp_id}, state) do
    {:noreply, with_task(state, cwmp_id, fn s, task ->
       if task.state == :queued do
         transition(s, task, :delivered)
       else
         s
       end
     end)}
  end

  @impl true
  def handle_cast({:complete, cwmp_id, data}, state) do
    {:noreply, with_task(state, cwmp_id, fn s, task ->
       if terminal?(task.state) do
         s
       else
         result = if task.type == :get, do: %{"parameters" => normalize_result(data)}, else: nil
         transition(s, %{task | result: result}, :applied)
       end
     end)}
  end

  @impl true
  def handle_cast({:fault, cwmp_id, data}, state) do
    {:noreply, with_task(state, cwmp_id, fn s, task ->
       if terminal?(task.state) do
         s
       else
         fault = %{code: to_string(data[:code] || data["code"] || ""), message: to_string(data[:message] || data["message"] || "")}
         transition(s, %{task | fault: fault}, :faulted)
       end
     end)}
  end

  @impl true
  def handle_info({:pubsub, :tr069_inform, %Caretaker.TR069.RPC.Inform{} = inform}, state) do
    dev_key = device_key(inform.device_id)

    entry = %{
      last_inform: DateTime.utc_now(),
      inform_interval: inform_interval(inform),
      device_id: Map.take(inform.device_id, [:oui, :product_class, :serial_number])
    }

    {:noreply, put_in(state, [:presence, dev_key], entry)}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = now_ms()

    # Expire queued tasks past their TTL.
    state =
      state.tasks
      |> Map.values()
      |> Enum.filter(&(&1.state == :queued and &1.expires_at_mono != :infinity and now >= &1.expires_at_mono))
      |> Enum.reduce(state, fn task, acc -> transition(acc, task, :expired) end)

    # Purge terminal tasks past the retention window.
    cutoff = DateTime.add(DateTime.utc_now(), -div(state.retention_ms, 1000), :second)

    state =
      state.tasks
      |> Map.values()
      |> Enum.filter(fn t -> terminal?(t.state) and t.completed_at && DateTime.compare(t.completed_at, cutoff) == :lt end)
      |> Enum.reduce(state, fn t, acc -> purge(acc, t) end)

    Process.send_after(self(), :sweep, @sweep_interval)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # ============================================================================
  # Helpers
  # ============================================================================

  defp require_session do
    if Process.whereis(Session), do: :ok, else: {:error, :session_unavailable}
  end

  defp normalize_device_id(%{oui: _, product_class: _, serial_number: _} = d), do: {:ok, d}

  defp normalize_device_id(%{} = d) do
    with {:ok, oui} <- fetch_any(d, [:oui, "oui"]),
         {:ok, pc} <- fetch_any(d, [:product_class, "product_class", "productClass"]),
         {:ok, sn} <- fetch_any(d, [:serial_number, "serial_number", "serialNumber"]) do
      {:ok, %{oui: oui, product_class: pc, serial_number: sn}}
    else
      _ -> {:error, :invalid_device_id}
    end
  end

  defp normalize_device_id(str) when is_binary(str), do: parse_device_id(str)
  defp normalize_device_id(_), do: {:error, :invalid_device_id}

  defp fetch_any(map, keys) do
    Enum.find_value(keys, :error, fn k ->
      case Map.fetch(map, k) do
        {:ok, v} when is_binary(v) and v != "" -> {:ok, v}
        _ -> nil
      end
    end)
  end

  defp build_body(:get, paths) when is_list(paths) do
    names = Enum.map(paths, &to_string/1)

    if names == [] do
      {:error, :no_paths}
    else
      GetParameterValues.encode(GetParameterValues.new(names))
    end
  end

  defp build_body(:set, params) when is_list(params) do
    with {:ok, normalized} <- normalize_set_params(params) do
      SetParameterValues.encode(SetParameterValues.new(normalized))
    end
  end

  defp build_body(_, _), do: {:error, :invalid_parameters}

  defp normalize_set_params([]), do: {:error, :no_parameters}

  defp normalize_set_params(params) do
    Enum.reduce_while(params, {:ok, []}, fn p, {:ok, acc} ->
      with {:ok, name} <- fetch_any(p, [:path, "path", :name, "name"]),
           {:ok, value} <- fetch_value(p) do
        type = p[:type] || p["type"]
        {:cont, {:ok, [%{name: name, value: value, type: xsd_type(type)} | acc]}}
      else
        _ -> {:halt, {:error, :invalid_parameters}}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      other -> other
    end
  end

  defp fetch_value(p) do
    case {Map.fetch(p, :value), Map.fetch(p, "value")} do
      {{:ok, v}, _} -> {:ok, to_string(v)}
      {_, {:ok, v}} -> {:ok, to_string(v)}
      _ -> :error
    end
  end

  # A caller-supplied type is honored; "xsd:" is added when missing. No type
  # defaults to xsd:string (values arrive as strings; see #19).
  defp xsd_type(nil), do: "xsd:string"
  defp xsd_type(""), do: "xsd:string"
  defp xsd_type("xsd:" <> _ = t), do: t
  defp xsd_type(t) when is_binary(t), do: "xsd:" <> t

  defp idem_lookup(state, opts) do
    case Keyword.get(opts, :idempotency_key) do
      nil -> nil
      key -> state.by_idem[key] && state.tasks[state.by_idem[key]]
    end
  end

  defp maybe_index_idem(state, nil, _task_id), do: state
  defp maybe_index_idem(state, key, task_id), do: put_in(state, [:by_idem, key], task_id)

  defp same_payload?(task, type, spec), do: task.type == type and task.spec == spec

  defp with_task(state, cwmp_id, fun) do
    case state.by_cwmp[cwmp_id] do
      nil ->
        state

      task_id ->
        case Map.fetch(state.tasks, task_id) do
          {:ok, task} -> fun.(state, task)
          :error -> state
        end
    end
  end

  defp transition(state, task, new_state) do
    now = DateTime.utc_now()

    task =
      task
      |> Map.put(:state, new_state)
      |> maybe_stamp(:delivered_at, new_state == :delivered, now)
      |> maybe_stamp(:completed_at, terminal?(new_state), now)

    :telemetry.execute([:caretaker, :acs, :task, new_state], %{}, %{task_id: task.id})

    state = put_in(state, [:tasks, task.id], task)
    if terminal?(new_state), do: dispatch_webhook(state, task)
    state
  end

  defp maybe_stamp(task, _key, false, _now), do: task
  defp maybe_stamp(task, key, true, now), do: Map.update!(task, key, fn cur -> cur || now end)

  defp purge(state, task) do
    state
    |> update_in([:tasks], &Map.delete(&1, task.id))
    |> update_in([:by_cwmp], &Map.delete(&1, task.cwmp_id))
    |> update_in([:by_idem], fn m -> if task.idempotency_key, do: Map.delete(m, task.idempotency_key), else: m end)
  end

  defp terminal?(s), do: s in [:applied, :faulted, :expired, :cancelled]

  defp normalize_result(%{parameters: params}) when is_list(params) do
    Map.new(params, fn p -> {p.name, p.value} end)
  end

  defp normalize_result(_), do: %{}

  # -- presence --

  defp presence_for(state, device_id) do
    with {:ok, device_id} <- normalize_device_id(device_id) do
      dev_key = device_key(device_id)

      case state.presence[dev_key] do
        nil ->
          %{
            "device_id" => device_id_string(device_id),
            "last_inform" => nil,
            "inform_interval_seconds" => nil,
            "reachable" => false
          }

        p ->
          %{
            "device_id" => device_id_string(device_id),
            "last_inform" => iso(p.last_inform),
            "inform_interval_seconds" => p.inform_interval,
            "reachable" => reachable?(p)
          }
      end
    else
      _ -> %{"device_id" => inspect(device_id), "error" => "invalid_device_id"}
    end
  end

  # Reachable if the device informed within ~2 inform intervals (or 1h when unknown).
  defp reachable?(%{last_inform: nil}), do: false

  defp reachable?(%{last_inform: last, inform_interval: interval}) do
    window = (interval || 3600) * 2
    DateTime.diff(DateTime.utc_now(), last, :second) <= window
  end

  defp inform_interval(%Caretaker.TR069.RPC.Inform{parameter_list: params}) when is_list(params) do
    Enum.find_value(params, fn
      %{name: "Device.ManagementServer.PeriodicInformInterval", value: v} -> parse_int(v)
      {"Device.ManagementServer.PeriodicInformInterval", v} -> parse_int(v)
      _ -> nil
    end)
  end

  defp inform_interval(_), do: nil

  defp parse_int(v) when is_integer(v), do: v

  defp parse_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} -> i
      _ -> nil
    end
  end

  defp parse_int(_), do: nil

  # -- connection request (CR-6) --

  defp do_connection_request(device_id) do
    with {:ok, device_id} <- normalize_device_id(device_id),
         {:ok, url} <- connection_request_url(device_id) do
      :ok = HTTP.ensure_finch()
      req = Finch.build(:get, url)

      case Finch.request(req, HTTP.finch(), receive_timeout: 5_000) do
        {:ok, %Finch.Response{status: status}} when status in 200..299 ->
          %{"requested" => true, "session_established" => true}

        {:ok, %Finch.Response{status: 401}} ->
          %{"requested" => true, "session_established" => false, "reason" => "auth_required"}

        {:ok, %Finch.Response{status: status}} ->
          %{"requested" => true, "session_established" => false, "reason" => "http_#{status}"}

        {:error, reason} ->
          %{"requested" => false, "session_established" => false, "reason" => inspect(reason)}
      end
    else
      {:error, :no_connection_request_url} ->
        %{"requested" => false, "session_established" => false, "reason" => "no_connection_request_url"}

      {:error, reason} ->
        %{"requested" => false, "session_established" => false, "reason" => to_string(reason)}
    end
  end

  defp connection_request_url(device_id) do
    with pid when not is_nil(pid) <- Process.whereis(Caretaker.TR181.Store),
         model when is_map(model) <- Caretaker.TR181.Store.get(device_key(device_id)),
         url when is_binary(url) and url != "" <-
           get_in(model, ["Device", "ManagementServer", "ConnectionRequestURL"]) do
      {:ok, url}
    else
      _ -> {:error, :no_connection_request_url}
    end
  end

  # -- webhook (CR-5) --

  defp dispatch_webhook(%{webhook_url: nil}, _task), do: :ok

  defp dispatch_webhook(%{webhook_url: url, webhook_secret: secret}, task) do
    payload =
      Jason.encode!(%{
        "event" => "task.completed",
        "task_id" => task.id,
        "device_id" => device_id_string(task.device_id),
        "state" => Atom.to_string(task.state),
        "fault" => task.fault && %{"code" => task.fault.code, "message" => task.fault.message},
        "completed_at" => iso(task.completed_at)
      })

    Task.start(fn -> post_webhook(url, secret, payload, 0) end)
    :ok
  end

  defp post_webhook(_url, _secret, _payload, attempt) when attempt >= 5, do: :error

  defp post_webhook(url, secret, payload, attempt) do
    :ok = HTTP.ensure_finch()

    headers =
      [{"content-type", "application/json"}] ++
        if(secret, do: [{"x-caretaker-signature", sign(secret, payload)}], else: [])

    case Finch.request(Finch.build(:post, url, headers, payload), HTTP.finch(), receive_timeout: 5_000) do
      {:ok, %Finch.Response{status: status}} when status in 200..299 ->
        :ok

      _ ->
        Process.sleep(trunc(:math.pow(2, attempt) * 200))
        post_webhook(url, secret, payload, attempt + 1)
    end
  end

  defp sign(secret, payload) do
    "sha256=" <> (:crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode16(case: :lower))
  end

  # -- rate limit (CR-9) --

  defp take(%{limit: limit, tokens: tokens, last: last} = rate) do
    now = now_ms()
    refill = (now - last) / 1000 * limit
    tokens = min(limit * 1.0, tokens + refill)

    if tokens >= 1.0 do
      {:ok, %{rate | tokens: tokens - 1.0, last: now}}
    else
      retry_after = max(1, round((1.0 - tokens) / limit))
      {{:error, {:rate_limited, retry_after}}, %{rate | tokens: tokens, last: now}}
    end
  end

  # -- misc --

  defp device_key(%{oui: oui, product_class: pc, serial_number: sn}), do: {oui, pc, sn}

  defp ttl_deadline(:infinity), do: :infinity
  defp ttl_deadline(ms) when is_integer(ms), do: now_ms() + ms

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp gen_task_id, do: "tsk_" <> Base.encode32(:crypto.strong_rand_bytes(15), padding: false)
  defp gen_cwmp_id, do: Base.encode16(:crypto.strong_rand_bytes(8), case: :upper)

  defp iso(nil), do: nil
  defp iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
end
