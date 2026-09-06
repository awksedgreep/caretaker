defmodule Caretaker.ACS do
  @moduledoc """
  Public entry points for the ACS.

  ## Inform subscription

  Every Inform the ACS receives is broadcast to subscribers. This is the
  documented, stable way for a consumer to self-discover devices and react to
  events (boot, value change, connection request) without depending on internal
  modules.

  Each broadcast delivers a `Caretaker.TR069.RPC.Inform` struct carrying:

    - `device_id` — `%{oui, product_class, serial_number, manufacturer}`
    - `events` — event codes (e.g. `"0 BOOTSTRAP"`, `"1 BOOT"`, `"4 VALUE CHANGE"`,
      `"6 CONNECTION REQUEST"`)
    - `parameter_list` — the parameters the CPE reported, as
      `%{name:, value:, type:}` entries
    - `source_ip` — the CPE's TCP source address as a string (set by the ACS)
    - `current_time`, `retry_count`, `max_envelopes`

  ### Callback style

      {:ok, _pid} = Caretaker.ACS.on_inform(fn inform ->
        MyApp.Inventory.observe(inform.device_id, inform.source_ip, inform.parameter_list)
      end)

  The returned process runs the function for each Inform; stop it with
  `Caretaker.ACS.stop_inform_listener/1`.

  ### Mailbox style

  To receive Informs as messages in the current process instead:

      Caretaker.ACS.subscribe_informs()
      # then handle {:caretaker_inform, %Caretaker.TR069.RPC.Inform{}} messages

  The underlying PubSub message shape is `{:pubsub, :tr069_inform, inform}`;
  `subscribe_informs/0` re-emits it as `{:caretaker_inform, inform}` via a small
  relay so consumers depend on this documented tuple, not the internal topic.
  """

  use GenServer

  @type inform :: Caretaker.TR069.RPC.Inform.t()

  @doc """
  Subscribe the calling process to Informs. Messages arrive as
  `{:caretaker_inform, inform}`. Returns `{:ok, listener_pid}`; the listener
  forwards to the caller and stops when the caller dies.
  """
  @spec subscribe_informs() :: {:ok, pid()}
  def subscribe_informs do
    owner = self()
    on_inform(fn inform -> send(owner, {:caretaker_inform, inform}) end, monitor: owner)
  end

  @doc """
  Run `fun` for every Inform the ACS receives. Returns `{:ok, listener_pid}`.

  Options:
    - `:monitor` - a pid to monitor; the listener stops when it dies.
  """
  @spec on_inform((inform() -> any()), keyword()) :: {:ok, pid()}
  def on_inform(fun, opts \\ []) when is_function(fun, 1) do
    GenServer.start(__MODULE__, {fun, Keyword.get(opts, :monitor)})
  end

  @doc "Stop an Inform listener started by `on_inform/2` or `subscribe_informs/0`."
  @spec stop_inform_listener(pid()) :: :ok
  def stop_inform_listener(pid) when is_pid(pid), do: GenServer.stop(pid, :normal)

  # -- listener process --

  @impl true
  def init({fun, monitor}) do
    Caretaker.PubSub.subscribe(Caretaker.PubSub.topic_tr069_inform())
    ref = if is_pid(monitor), do: Process.monitor(monitor)
    {:ok, %{fun: fun, monitor_ref: ref}}
  end

  @impl true
  def handle_info({:pubsub, :tr069_inform, %Caretaker.TR069.RPC.Inform{} = inform}, state) do
    # A raising callback must not take the listener down.
    try do
      state.fun.(inform)
    rescue
      _ -> :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{monitor_ref: ref} = state) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}
end
