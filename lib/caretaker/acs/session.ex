defmodule Caretaker.ACS.Session do
  @moduledoc """
  In-memory per-device session/queue for ACS commands.

  Sessions are keyed by DeviceId (OUI/ProductClass/Serial). We also keep a binding of
  caller keys (e.g., {:ip, remote_ip}) -> DeviceKey to correlate empty POSTs.

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

  def child_spec(opts \\ []) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  def start_link(_opts \\ []),
    do: GenServer.start_link(__MODULE__, %{sessions: %{}, bindings: %{}}, name: __MODULE__)

  @impl true
  def init(state), do: {:ok, state}

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
  def handle_call(
        {:upsert_for_caller, caller_key, device_id, cwmp_ns},
        _from,
        %{sessions: sessions, bindings: bindings} = state
      ) do
    dev_key = device_key(device_id)

    sess =
      Map.get(sessions, dev_key, %{
        queue: :queue.new(),
        device_id: nil,
        cwmp_ns: nil,
        device_context: nil
      })

    sess = %{sess | device_id: device_id, cwmp_ns: cwmp_ns}

    {:reply, :ok,
     %{
       state
       | sessions: Map.put(sessions, dev_key, sess),
         bindings: Map.put(bindings, caller_key, dev_key)
     }}
  end

  @impl true
  def handle_call(
        {:upsert_for_caller_with_context, caller_key, device_id, cwmp_ns, device_context},
        _from,
        %{sessions: sessions, bindings: bindings} = state
      ) do
    dev_key = device_key(device_id)

    sess =
      Map.get(sessions, dev_key, %{
        queue: :queue.new(),
        device_id: nil,
        cwmp_ns: nil,
        device_context: nil
      })

    sess = %{sess | device_id: device_id, cwmp_ns: cwmp_ns, device_context: device_context}

    {:reply, :ok,
     %{
       state
       | sessions: Map.put(sessions, dev_key, sess),
         bindings: Map.put(bindings, caller_key, dev_key)
     }}
  end

  @impl true
  def handle_call(
        {:enqueue_for_caller, caller_key, cmd},
        _from,
        %{sessions: sessions, bindings: bindings} = state
      ) do
    case Map.get(bindings, caller_key) do
      nil ->
        {:reply, :ok, state}

      dev_key ->
        sess =
          Map.get(sessions, dev_key, %{
            queue: :queue.new(),
            device_id: nil,
            cwmp_ns: nil,
            device_context: nil
          })

        q = :queue.in(cmd, sess.queue)
        {:reply, :ok, %{state | sessions: Map.put(sessions, dev_key, %{sess | queue: q})}}
    end
  end

  @impl true
  def handle_call(
        {:dequeue_for_caller, caller_key},
        _from,
        %{sessions: sessions, bindings: bindings} = state
      ) do
    case Map.get(bindings, caller_key) do
      nil ->
        {:reply, :empty, state}

      dev_key ->
        case Map.get(sessions, dev_key) do
          %{queue: q} = sess ->
            case :queue.out(q) do
              {{:value, cmd}, q2} ->
                {:reply, {:ok, cmd},
                 %{state | sessions: Map.put(sessions, dev_key, %{sess | queue: q2})}}

              {:empty, _} ->
                {:reply, :empty, state}
            end

          nil ->
            {:reply, :empty, state}
        end
    end
  end

  @impl true
  def handle_call({:dequeue_dev, dev_key}, _from, %{sessions: sessions} = state) do
    case Map.get(sessions, dev_key) do
      %{queue: q} = sess ->
        case :queue.out(q) do
          {{:value, cmd}, q2} ->
            {:reply, {:ok, cmd},
             %{state | sessions: Map.put(sessions, dev_key, %{sess | queue: q2})}}

          {:empty, _} ->
            {:reply, :empty, state}
        end

      nil ->
        {:reply, :empty, state}
    end
  end

  @impl true
  def handle_call({:device_key_for_caller, caller_key}, _from, %{bindings: bindings} = state) do
    {:reply, Map.get(bindings, caller_key), state}
  end

  @impl true
  def handle_call(
        {:cwmp_ns_for_caller, caller_key},
        _from,
        %{bindings: bindings, sessions: sessions} = state
      ) do
    case Map.get(bindings, caller_key) do
      nil ->
        {:reply, nil, state}

      dev_key ->
        case Map.get(sessions, dev_key) do
          %{cwmp_ns: ns} -> {:reply, ns, state}
          _ -> {:reply, nil, state}
        end
    end
  end

  @impl true
  def handle_call(
        {:device_context_for_caller, caller_key},
        _from,
        %{bindings: bindings, sessions: sessions} = state
      ) do
    case Map.get(bindings, caller_key) do
      nil ->
        {:reply, nil, state}

      dev_key ->
        case Map.get(sessions, dev_key) do
          %{device_context: ctx} -> {:reply, ctx, state}
          _ -> {:reply, nil, state}
        end
    end
  end

  @impl true
  def handle_cast({:upsert_dev, dev_key, device_id, cwmp_ns}, %{sessions: sessions} = state) do
    sess =
      Map.get(sessions, dev_key, %{
        queue: :queue.new(),
        device_id: nil,
        cwmp_ns: nil,
        device_context: nil
      })

    sess = %{sess | device_id: device_id, cwmp_ns: cwmp_ns}
    {:noreply, %{state | sessions: Map.put(sessions, dev_key, sess)}}
  end

  @impl true
  def handle_cast({:enqueue_dev, dev_key, cmd}, %{sessions: sessions} = state) do
    sess =
      Map.get(sessions, dev_key, %{
        queue: :queue.new(),
        device_id: nil,
        cwmp_ns: nil,
        device_context: nil
      })

    q = :queue.in(cmd, sess.queue)
    {:noreply, %{state | sessions: Map.put(sessions, dev_key, %{sess | queue: q})}}
  end

  # Helpers
  defp device_key(%{oui: oui, product_class: pc, serial_number: sn}), do: {ouistr(oui), pc, sn}
  defp ouistr(oui) when is_binary(oui), do: oui
  defp ouistr(oui), do: to_string(oui)
end
