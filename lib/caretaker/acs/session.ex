defmodule Caretaker.ACS.Session do
  @moduledoc """
  In-memory per-device session/queue for ACS commands.

  Sessions are keyed by DeviceId (OUI/ProductClass/Serial). We also keep a binding of
  caller keys (e.g., {:ip, remote_ip}) -> DeviceKey to correlate empty POSTs.
  """
  use GenServer

  @type command :: iodata()
  @type caller_key :: term()
  @type device_id :: %{
          required(:oui) => String.t(),
          required(:product_class) => String.t(),
          required(:serial_number) => String.t()
        }
  @type device_key :: {String.t(), String.t(), String.t()}

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

  # Public API (IP-aware)

  @spec upsert_from_ip(:inet.ip_address(), device_id(), String.t()) :: :ok
  def upsert_from_ip(ip, device_id, cwmp_ns) do
    GenServer.call(__MODULE__, {:upsert_from_ip, ip, device_id, cwmp_ns})
  end

  @spec queue_for_ip(:inet.ip_address(), command()) :: :ok
  def queue_for_ip(ip, cmd) do
    GenServer.cast(__MODULE__, {:enqueue_for_ip, ip, cmd})
  end

  @spec next_for_ip(:inet.ip_address()) :: {:ok, command()} | :empty
  def next_for_ip(ip) do
    GenServer.call(__MODULE__, {:dequeue_for_ip, ip})
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
    GenServer.call(__MODULE__, {:device_key_for_ip, ip})
  end

  # Server callbacks

  @impl true
  def handle_call(
        {:upsert_from_ip, ip, device_id, cwmp_ns},
        _from,
        %{sessions: sessions, bindings: bindings} = state
      ) do
    dev_key = device_key(device_id)
    sess = Map.get(sessions, dev_key, %{queue: :queue.new(), device_id: nil, cwmp_ns: nil})
    sess = %{sess | device_id: device_id, cwmp_ns: cwmp_ns}

    {:reply, :ok,
     %{
       state
       | sessions: Map.put(sessions, dev_key, sess),
         bindings: Map.put(bindings, {:ip, ip}, dev_key)
     }}
  end

  @impl true
  def handle_call({:dequeue_for_ip, ip}, _from, %{sessions: sessions, bindings: bindings} = state) do
    case Map.get(bindings, {:ip, ip}) do
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
  def handle_call({:device_key_for_ip, ip}, _from, %{bindings: bindings} = state) do
    {:reply, Map.get(bindings, {:ip, ip}), state}
  end

  @impl true
  def handle_cast({:enqueue_for_ip, ip, cmd}, %{sessions: sessions, bindings: bindings} = state) do
    case Map.get(bindings, {:ip, ip}) do
      nil ->
        {:noreply, state}

      dev_key ->
        sess = Map.get(sessions, dev_key, %{queue: :queue.new(), device_id: nil, cwmp_ns: nil})
        q = :queue.in(cmd, sess.queue)
        {:noreply, %{state | sessions: Map.put(sessions, dev_key, %{sess | queue: q})}}
    end
  end

  @impl true
  def handle_cast({:upsert_dev, dev_key, device_id, cwmp_ns}, %{sessions: sessions} = state) do
    sess = Map.get(sessions, dev_key, %{queue: :queue.new(), device_id: nil, cwmp_ns: nil})
    sess = %{sess | device_id: device_id, cwmp_ns: cwmp_ns}
    {:noreply, %{state | sessions: Map.put(sessions, dev_key, sess)}}
  end

  @impl true
  def handle_cast({:enqueue_dev, dev_key, cmd}, %{sessions: sessions} = state) do
    sess = Map.get(sessions, dev_key, %{queue: :queue.new(), device_id: nil, cwmp_ns: nil})
    q = :queue.in(cmd, sess.queue)
    {:noreply, %{state | sessions: Map.put(sessions, dev_key, %{sess | queue: q})}}
  end

  # Helpers
  defp device_key(%{oui: oui, product_class: pc, serial_number: sn}), do: {ouistr(oui), pc, sn}
  defp ouistr(oui) when is_binary(oui), do: oui
  defp ouistr(oui), do: to_string(oui)
end
