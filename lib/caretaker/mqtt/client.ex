defmodule Caretaker.MQTT.Client do
  @moduledoc """
  Behaviour for MQTT client used by Caretaker bridges.
  """

  @callback start_link(keyword()) :: GenServer.on_start()
  @callback publish(client :: pid() | atom(), topic :: String.t(), payload :: iodata()) :: :ok | {:error, term()}
end