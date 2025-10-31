defmodule Caretaker.PubSub do
  @moduledoc """
  Minimal local PubSub for Caretaker using a GenServer.

  Topics:
  - :tr069_inform — published with %Caretaker.TR069.RPC.Inform{} when a device sends Inform
  """
  use GenServer

  @type topic :: atom()

  def child_spec(opts \\ []) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(state), do: {:ok, state}

  @spec subscribe(topic()) :: :ok
  def subscribe(topic) when is_atom(topic) do
    GenServer.call(__MODULE__, {:subscribe, topic, self()})
  end

  @spec unsubscribe(topic()) :: :ok
  def unsubscribe(topic) when is_atom(topic) do
    GenServer.call(__MODULE__, {:unsubscribe, topic, self()})
  end

  @spec broadcast(topic(), any()) :: :ok
  def broadcast(topic, message) when is_atom(topic) do
    GenServer.cast(__MODULE__, {:broadcast, topic, message})
  end

  @impl true
  def handle_call({:subscribe, topic, pid}, _from, state) do
    subs = Map.get(state, topic, MapSet.new()) |> MapSet.put(pid)
    {:reply, :ok, Map.put(state, topic, subs)}
  end

  def handle_call({:unsubscribe, topic, pid}, _from, state) do
    subs = Map.get(state, topic, MapSet.new()) |> MapSet.delete(pid)
    {:reply, :ok, Map.put(state, topic, subs)}
  end

  @impl true
  def handle_cast({:broadcast, topic, message}, state) do
    for pid <- Map.get(state, topic, MapSet.new()), do: send(pid, {:pubsub, topic, message})
    {:noreply, state}
  end

  @spec topic_tr069_inform() :: topic()
  def topic_tr069_inform, do: :tr069_inform
end
