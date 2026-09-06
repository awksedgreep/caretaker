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

  @spec queue_for_caller(caller_key(), command()) :: :ok
  def queue_for_caller(caller_key, cmd) do
    GenServer.call(__MODULE__, {:enqueue_for_caller, caller_key, cmd})
  end

  @spec next_for_caller(caller_key()) :: {:ok, command()} | :empty
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

  @spec queue_for_ip(:inet.ip_address(), command()) :: :ok
  def queue_for_ip(ip, cmd) do
    queue_for_caller({:ip, ip}, cmd)
  end

  @spec next_for_ip(:inet.ip_address()) :: {:ok, command()} | :empty
  def next_for_ip(ip) do
    next_for_caller({:ip, ip})
  end

  # Back-compat generic API (device_key)
  @spec upsert(device_key(), device_id(), String.t()) :: :ok
  def upsert(dev_key, device_id, cwmp_ns),
    do: GenServer.cast(__MODULE__, {:upsert_dev, dev_key, device_id, cwmp_ns})

  @spec queue_command(device_key(), command()) :: :ok
  def queue_command(dev_key, cmd), do: GenServer.cast(__MODULE__, {:enqueue_dev, dev_key, cmd})

  @spec next_command(device_key()) :: {:ok, command()} | :empty
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
  def handle_call({:enqueue_for_caller, caller_key, cmd}, _from, state) do
    case lookup(state, caller_key) do
      nil ->
        {:reply, :ok, state}

      dev_key ->
        sess = session(state, dev_key)
        q = :queue.in(cmd, sess.queue)
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
  def handle_call(:stats, _from, state) do
    {:reply, %{bindings: map_size(state.bindings), sessions: map_size(state.sessions)}, state}
  end

  @impl true
  def handle_cast({:upsert_dev, dev_key, device_id, cwmp_ns}, state) do
    sess = %{session(state, dev_key) | device_id: device_id, cwmp_ns: cwmp_ns}
    {:noreply, put_session(state, dev_key, sess)}
  end

  @impl true
  def handle_cast({:enqueue_dev, dev_key, cmd}, state) do
    sess = session(state, dev_key)
    q = :queue.in(cmd, sess.queue)
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
        case :queue.out(q) do
          {{:value, cmd}, q2} -> {{:ok, cmd}, put_session(state, dev_key, %{sess | queue: q2})}
          {:empty, _} -> {:empty, state}
        end

      nil ->
        {:empty, state}
    end
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp device_key(%{oui: oui, product_class: pc, serial_number: sn}), do: {ouistr(oui), pc, sn}
  defp ouistr(oui) when is_binary(oui), do: oui
  defp ouistr(oui), do: to_string(oui)
end
