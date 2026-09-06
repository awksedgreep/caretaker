defmodule Caretaker.ACS.Session do
  @moduledoc """
  In-memory per-device session/queue for ACS commands.

  Sessions are keyed by DeviceId (OUI/ProductClass/Serial). We also keep a
  binding of caller keys (a session cookie, or a peer address/port) -> DeviceKey
  to correlate the requests of one CWMP session.

  Bindings are transient: they are dropped after `binding_ttl` milliseconds
  without activity (default 5 minutes) so that a long-running ACS does not
  accumulate one entry per TCP connection. Device sessions (and their queued
  commands) are kept until the device is forgotten with `forget/1`.

  Enhanced with device type detection and context for device-specific handling.
  """
  use GenServer

  alias Caretaker.ACS.DeviceDetection

  @type command :: iodata()
  @type caller_key :: term()
  @type device_id :: %{
          required(:oui) => String.t(),
          required(:product_class) => String.t(),
          required(:serial_number) => String.t()
        }
  @type device_key :: {String.t(), String.t(), String.t()}
  @type device_context :: %{
          device_type: DeviceDetection.device_type(),
          quirks_module: module() | nil,
          detected_at: DateTime.t()
        }

  @default_binding_ttl :timer.minutes(5)
  # Queued commands expire by default so a change can never be delivered days
  # later, outside any maintenance window (see #35). Callers may override per
  # command; expiry is opt-out, not opt-in.
  @default_command_ttl :timer.hours(6)
  @default_sweep_interval :timer.minutes(1)

  def child_spec(opts \\ []) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  @doc """
  Start the session store.

  Options:
  - `binding_ttl` - idle time in ms after which a caller binding is dropped
  - `sweep_interval` - how often expired bindings are swept, in ms
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    state = %{
      sessions: %{},
      bindings: %{},
      binding_ttl: Keyword.get(opts, :binding_ttl, @default_binding_ttl),
      command_ttl: Keyword.get(opts, :command_ttl, @default_command_ttl),
      sweep_interval: Keyword.get(opts, :sweep_interval, @default_sweep_interval)
    }

    Process.send_after(self(), :sweep, state.sweep_interval)
    {:ok, state}
  end

  # Public API (caller-key aware)

  @spec upsert_for_caller(caller_key(), device_id(), String.t()) :: :ok
  def upsert_for_caller(caller_key, device_id, cwmp_ns) do
    GenServer.call(__MODULE__, {:upsert_for_caller, caller_key, device_id, cwmp_ns})
  end

  @spec upsert_for_caller_with_context(caller_key(), device_id(), String.t(), device_context()) ::
          :ok
  def upsert_for_caller_with_context(caller_key, device_id, cwmp_ns, device_context) do
    GenServer.call(
      __MODULE__,
      {:upsert_for_caller_with_context, caller_key, device_id, cwmp_ns, device_context}
    )
  end

  @doc "Bind an additional caller key (e.g. a session cookie) to the device bound to `existing_key`."
  @spec bind_alias(caller_key(), caller_key()) :: :ok | {:error, :not_found}
  def bind_alias(existing_key, new_key) do
    GenServer.call(__MODULE__, {:bind_alias, existing_key, new_key})
  end

  @typedoc "Options for a queued command: :ttl_ms (integer or :infinity) and :tag."
  @type queue_opts :: [ttl_ms: non_neg_integer() | :infinity, tag: term()]

  @spec queue_for_caller(caller_key(), command(), queue_opts()) :: :ok
  def queue_for_caller(caller_key, cmd, opts \\ []) do
    GenServer.call(__MODULE__, {:enqueue_for_caller, caller_key, cmd, opts})
  end

  @spec next_for_caller(caller_key()) :: {:ok, command(), map()} | :empty
  def next_for_caller(caller_key) do
    GenServer.call(__MODULE__, {:dequeue_for_caller, caller_key})
  end

  @spec device_key_for_caller(caller_key()) :: device_key | nil
  def device_key_for_caller(caller_key) do
    GenServer.call(__MODULE__, {:device_key_for_caller, caller_key})
  end

  @spec cwmp_ns_for_caller(caller_key()) :: String.t() | nil
  def cwmp_ns_for_caller(caller_key) do
    GenServer.call(__MODULE__, {:cwmp_ns_for_caller, caller_key})
  end

  @spec device_context_for_caller(caller_key()) :: device_context() | nil
  def device_context_for_caller(caller_key) do
    GenServer.call(__MODULE__, {:device_context_for_caller, caller_key})
  end

  @doc "Drop the binding for a caller key (end of a CWMP session)."
  @spec unbind(caller_key()) :: :ok
  def unbind(caller_key), do: GenServer.call(__MODULE__, {:unbind, caller_key})

  @doc "Drop a device session and every binding pointing at it."
  @spec forget(device_key()) :: :ok
  def forget(dev_key), do: GenServer.call(__MODULE__, {:forget, dev_key})

  @doc "Number of live bindings and device sessions (for monitoring and tests)."
  @spec stats() :: %{bindings: non_neg_integer(), sessions: non_neg_integer()}
  def stats, do: GenServer.call(__MODULE__, :stats)

  @spec upsert_from_ip(:inet.ip_address(), device_id(), String.t()) :: :ok
  def upsert_from_ip(ip, device_id, cwmp_ns) do
    upsert_for_caller({:ip, ip}, device_id, cwmp_ns)
  end

  @spec upsert_from_ip_with_context(
          :inet.ip_address(),
          device_id(),
          String.t(),
          device_context()
        ) :: :ok
  def upsert_from_ip_with_context(ip, device_id, cwmp_ns, device_context) do
    upsert_for_caller_with_context({:ip, ip}, device_id, cwmp_ns, device_context)
  end

  @spec queue_for_ip(:inet.ip_address(), command(), queue_opts()) :: :ok
  def queue_for_ip(ip, cmd, opts \\ []) do
    queue_for_caller({:ip, ip}, cmd, opts)
  end

  @spec next_for_ip(:inet.ip_address()) :: {:ok, command(), map()} | :empty
  def next_for_ip(ip) do
    next_for_caller({:ip, ip})
  end

  # Back-compat generic API (device_key)
  @spec upsert(device_key(), device_id(), String.t()) :: :ok
  def upsert(dev_key, device_id, cwmp_ns),
    do: GenServer.cast(__MODULE__, {:upsert_dev, dev_key, device_id, cwmp_ns})

  @spec queue_command(device_key(), command(), queue_opts()) :: :ok
  def queue_command(dev_key, cmd, opts \\ []),
    do: GenServer.cast(__MODULE__, {:enqueue_dev, dev_key, cmd, opts})

  @doc """
  Cancel every not-yet-delivered queued command carrying `tag`, across all
  devices. Returns the number of commands removed. This is the fleet-wide kill
  switch for a batch of queued changes (#35).
  """
  @spec cancel_by_tag(term()) :: {:ok, non_neg_integer()}
  def cancel_by_tag(tag), do: GenServer.call(__MODULE__, {:cancel_by_tag, tag})

  @doc "Remove the not-yet-delivered queued command with the given correlation id."
  @spec cancel_by_id(term()) :: {:ok, non_neg_integer()}
  def cancel_by_id(id), do: GenServer.call(__MODULE__, {:cancel_by_id, id})

  @spec next_command(device_key()) :: {:ok, command(), map()} | :empty
  def next_command(dev_key), do: GenServer.call(__MODULE__, {:dequeue_dev, dev_key})

  @spec device_key_for_ip(:inet.ip_address()) :: device_key | nil
  def device_key_for_ip(ip) do
    device_key_for_caller({:ip, ip})
  end

  @spec cwmp_ns_for_ip(:inet.ip_address()) :: String.t() | nil
  def cwmp_ns_for_ip(ip) do
    cwmp_ns_for_caller({:ip, ip})
  end

  @spec device_context_for_ip(:inet.ip_address()) :: device_context() | nil
  def device_context_for_ip(ip) do
    device_context_for_caller({:ip, ip})
  end

  # Server callbacks

  @impl true
  def handle_call({:upsert_for_caller, caller_key, device_id, cwmp_ns}, _from, state) do
    dev_key = device_key(device_id)
    sess = %{session(state, dev_key) | device_id: device_id, cwmp_ns: cwmp_ns}
    {:reply, :ok, put_session(state, dev_key, sess) |> bind(caller_key, dev_key)}
  end

  @impl true
  def handle_call(
        {:upsert_for_caller_with_context, caller_key, device_id, cwmp_ns, device_context},
        _from,
        state
      ) do
    dev_key = device_key(device_id)

    sess = %{
      session(state, dev_key)
      | device_id: device_id,
        cwmp_ns: cwmp_ns,
        device_context: device_context
    }

    {:reply, :ok, put_session(state, dev_key, sess) |> bind(caller_key, dev_key)}
  end

  @impl true
  def handle_call({:bind_alias, existing_key, new_key}, _from, state) do
    case lookup(state, existing_key) do
      nil -> {:reply, {:error, :not_found}, state}
      dev_key -> {:reply, :ok, bind(state, new_key, dev_key)}
    end
  end

  @impl true
  def handle_call({:enqueue_for_caller, caller_key, cmd, opts}, _from, state) do
    case lookup(state, caller_key) do
      nil ->
        {:reply, :ok, state}

      dev_key ->
        sess = session(state, dev_key)
        q = :queue.in(entry(cmd, opts, state), sess.queue)
        {:reply, :ok, put_session(state, dev_key, %{sess | queue: q}) |> touch(caller_key)}
    end
  end

  @impl true
  def handle_call({:dequeue_for_caller, caller_key}, _from, state) do
    case lookup(state, caller_key) do
      nil ->
        {:reply, :empty, state}

      dev_key ->
        {reply, state} = dequeue(state, dev_key)
        {:reply, reply, touch(state, caller_key)}
    end
  end

  @impl true
  def handle_call({:dequeue_dev, dev_key}, _from, state) do
    {reply, state} = dequeue(state, dev_key)
    {:reply, reply, state}
  end

  @impl true
  def handle_call({:device_key_for_caller, caller_key}, _from, state) do
    {:reply, lookup(state, caller_key), state}
  end

  @impl true
  def handle_call({:cwmp_ns_for_caller, caller_key}, _from, state) do
    {:reply, session_field(state, caller_key, :cwmp_ns), state}
  end

  @impl true
  def handle_call({:device_context_for_caller, caller_key}, _from, state) do
    {:reply, session_field(state, caller_key, :device_context), state}
  end

  @impl true
  def handle_call({:unbind, caller_key}, _from, state) do
    {:reply, :ok, %{state | bindings: Map.delete(state.bindings, caller_key)}}
  end

  @impl true
  def handle_call({:forget, dev_key}, _from, state) do
    bindings =
      state.bindings
      |> Enum.reject(fn {_k, {dk, _ts}} -> dk == dev_key end)
      |> Map.new()

    {:reply, :ok, %{state | sessions: Map.delete(state.sessions, dev_key), bindings: bindings}}
  end

  @impl true
  def handle_call({:cancel_by_id, id}, _from, state) do
    {sessions, removed} =
      Enum.reduce(state.sessions, {%{}, 0}, fn {dev_key, sess}, {acc, n} ->
        kept = :queue.filter(fn e -> entry_id(e) != id end, sess.queue)
        dropped = :queue.len(sess.queue) - :queue.len(kept)
        {Map.put(acc, dev_key, %{sess | queue: kept}), n + dropped}
      end)

    {:reply, {:ok, removed}, %{state | sessions: sessions}}
  end

  @impl true
  def handle_call({:cancel_by_tag, tag}, _from, state) do
    {sessions, removed} =
      Enum.reduce(state.sessions, {%{}, 0}, fn {dev_key, sess}, {acc, n} ->
        kept = :queue.filter(fn e -> entry_tag(e) != tag end, sess.queue)
        dropped = :queue.len(sess.queue) - :queue.len(kept)
        {Map.put(acc, dev_key, %{sess | queue: kept}), n + dropped}
      end)

    if removed > 0 do
      :telemetry.execute([:caretaker, :acs, :queue, :cancelled], %{count: removed}, %{tag: tag})
    end

    {:reply, {:ok, removed}, %{state | sessions: sessions}}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, %{bindings: map_size(state.bindings), sessions: map_size(state.sessions)}, state}
  end

  @impl true
  def handle_cast({:upsert_dev, dev_key, device_id, cwmp_ns}, state) do
    sess = %{session(state, dev_key) | device_id: device_id, cwmp_ns: cwmp_ns}
    {:noreply, put_session(state, dev_key, sess)}
  end

  @impl true
  def handle_cast({:enqueue_dev, dev_key, cmd, opts}, state) do
    sess = session(state, dev_key)
    q = :queue.in(entry(cmd, opts, state), sess.queue)
    {:noreply, put_session(state, dev_key, %{sess | queue: q})}
  end

  @impl true
  def handle_info(:sweep, state) do
    cutoff = now_ms() - state.binding_ttl

    bindings =
      state.bindings
      |> Enum.reject(fn {_k, {_dk, ts}} -> ts < cutoff end)
      |> Map.new()

    Process.send_after(self(), :sweep, state.sweep_interval)
    {:noreply, %{state | bindings: bindings}}
  end

  # Helpers

  defp new_session do
    %{queue: :queue.new(), device_id: nil, cwmp_ns: nil, device_context: nil}
  end

  defp session(state, dev_key), do: Map.get(state.sessions, dev_key, new_session())

  defp put_session(state, dev_key, sess),
    do: %{state | sessions: Map.put(state.sessions, dev_key, sess)}

  defp bind(state, caller_key, dev_key),
    do: %{state | bindings: Map.put(state.bindings, caller_key, {dev_key, now_ms()})}

  defp touch(state, caller_key) do
    case Map.get(state.bindings, caller_key) do
      nil -> state
      {dev_key, _ts} -> bind(state, caller_key, dev_key)
    end
  end

  defp lookup(state, caller_key) do
    case Map.get(state.bindings, caller_key) do
      nil -> nil
      {dev_key, _ts} -> dev_key
    end
  end

  defp session_field(state, caller_key, field) do
    case lookup(state, caller_key) do
      nil ->
        nil

      dev_key ->
        case Map.get(state.sessions, dev_key) do
          nil -> nil
          sess -> Map.get(sess, field)
        end
    end
  end

  defp dequeue(state, dev_key) do
    case Map.get(state.sessions, dev_key) do
      %{queue: q} = sess ->
        {result, q2} = pop_live(q, dev_key)
        {result, put_session(state, dev_key, %{sess | queue: q2})}

      nil ->
        {:empty, state}
    end
  end

  # Pop the first non-expired command, discarding any expired ones ahead of it.
  defp pop_live(q, dev_key) do
    case :queue.out(q) do
      {{:value, entry}, q2} ->
        if expired?(entry) do
          :telemetry.execute([:caretaker, :acs, :queue, :expired], %{count: 1}, %{
            device_key: dev_key,
            tag: entry_tag(entry)
          })

          pop_live(q2, dev_key)
        else
          {{:ok, entry_cmd(entry), %{id: entry_id(entry), tag: entry_tag(entry)}}, q2}
        end

      {:empty, _} ->
        {:empty, q}
    end
  end

  # -- command entries (cmd + expiry + tag) --

  defp entry(cmd, opts, state) do
    ttl = Keyword.get(opts, :ttl_ms, state.command_ttl)

    expires_at =
      case ttl do
        :infinity -> :infinity
        ms when is_integer(ms) -> now_ms() + ms
      end

    %{cmd: cmd, expires_at: expires_at, tag: Keyword.get(opts, :tag), id: Keyword.get(opts, :id)}
  end

  defp expired?(%{expires_at: :infinity}), do: false
  defp expired?(%{expires_at: deadline}), do: now_ms() >= deadline
  # Tolerate any legacy raw command still sitting in a queue.
  defp expired?(_), do: false

  defp entry_cmd(%{cmd: cmd}), do: cmd
  defp entry_cmd(cmd), do: cmd

  defp entry_tag(%{tag: tag}), do: tag
  defp entry_tag(_), do: nil

  defp entry_id(%{id: id}), do: id
  defp entry_id(_), do: nil

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp device_key(%{oui: oui, product_class: pc, serial_number: sn}), do: {ouistr(oui), pc, sn}
  defp ouistr(oui) when is_binary(oui), do: oui
  defp ouistr(oui), do: to_string(oui)
end
