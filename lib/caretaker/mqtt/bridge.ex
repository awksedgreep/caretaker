defmodule Caretaker.MQTT.Bridge do
  @moduledoc """
  Bridge that subscribes to internal PubSub for Inform messages and publishes them to an MQTT topic.
  """
  use GenServer

  alias Caretaker.PubSub

  @type opts :: [
          {:topic, String.t()},
          {:client_id, atom() | pid()},
          {:client_module, module()}
        ]

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @impl true
  def init(opts) do
    topic = Keyword.get(opts, :topic, "caretaker/inform")
    client_id = Keyword.fetch!(opts, :client_id)
    client_mod = Keyword.get(opts, :client_module, Caretaker.MQTT.TortoiseClient)

    PubSub.subscribe(PubSub.topic_tr069_inform())

    state = %{topic: topic, client_id: client_id, client_mod: client_mod}
    {:ok, state}
  end

  @impl true
  def handle_info(
        {:pubsub, :tr069_inform, %Caretaker.TR069.RPC.Inform{} = inform},
        %{topic: mqtt_topic} = state
      ) do
    payload = Jason.encode!(Caretaker.TR069.RPC.Inform.to_map(inform))
    :ok = state.client_mod.publish(state.client_id, mqtt_topic, payload)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
