defmodule Caretaker.USP.Telemetry do
  @moduledoc """
  Telemetry instrumentation for USP protocol operations.

  ## Events

  ### Message Encoding/Decoding

  - `[:caretaker, :usp, :encode, :start]` - Message encoding started
  - `[:caretaker, :usp, :encode, :stop]` - Message encoding completed
  - `[:caretaker, :usp, :encode, :exception]` - Message encoding failed
  - `[:caretaker, :usp, :decode, :start]` - Message decoding started
  - `[:caretaker, :usp, :decode, :stop]` - Message decoding completed
  - `[:caretaker, :usp, :decode, :exception]` - Message decoding failed

  ### Agent Events

  - `[:caretaker, :usp, :agent, :message_received]` - Agent received a message
  - `[:caretaker, :usp, :agent, :message_sent]` - Agent sent a message
  - `[:caretaker, :usp, :agent, :register]` - Agent registered with controller
  - `[:caretaker, :usp, :agent, :deregister]` - Agent deregistered

  ### Controller Events

  - `[:caretaker, :usp, :controller, :message_received]` - Controller received a message
  - `[:caretaker, :usp, :controller, :message_sent]` - Controller sent a message
  - `[:caretaker, :usp, :controller, :agent_connected]` - Agent connected to controller
  - `[:caretaker, :usp, :controller, :agent_disconnected]` - Agent disconnected

  ### Transport Events

  - `[:caretaker, :usp, :transport, :connect]` - Transport connection established
  - `[:caretaker, :usp, :transport, :disconnect]` - Transport connection closed
  - `[:caretaker, :usp, :transport, :error]` - Transport error occurred

  ## Metadata

  All events include:
  - `:msg_type` - The USP message type (e.g., `:GET`, `:SET`)
  - `:msg_id` - The message ID
  - `:endpoint_id` - The endpoint ID (where applicable)

  """

  @doc """
  Wraps a function with telemetry span for encoding.
  """
  @spec span_encode(atom(), map(), (-> result)) :: result when result: var
  def span_encode(msg_type, metadata \\ %{}, fun) do
    :telemetry.span(
      [:caretaker, :usp, :encode],
      Map.merge(%{msg_type: msg_type}, metadata),
      fn ->
        result = fun.()
        {result, %{}}
      end
    )
  end

  @doc """
  Wraps a function with telemetry span for decoding.
  """
  @spec span_decode(map(), (-> result)) :: result when result: var
  def span_decode(metadata \\ %{}, fun) do
    :telemetry.span(
      [:caretaker, :usp, :decode],
      metadata,
      fn ->
        result = fun.()
        msg_type = extract_msg_type(result)
        {result, %{msg_type: msg_type}}
      end
    )
  end

  @doc """
  Emits an event for agent message received.
  """
  def emit_agent_message_received(msg, metadata \\ %{}) do
    :telemetry.execute(
      [:caretaker, :usp, :agent, :message_received],
      %{count: 1},
      Map.merge(message_metadata(msg), metadata)
    )
  end

  @doc """
  Emits an event for agent message sent.
  """
  def emit_agent_message_sent(msg, metadata \\ %{}) do
    :telemetry.execute(
      [:caretaker, :usp, :agent, :message_sent],
      %{count: 1},
      Map.merge(message_metadata(msg), metadata)
    )
  end

  @doc """
  Emits an event for agent registration.
  """
  def emit_agent_register(endpoint_id, metadata \\ %{}) do
    :telemetry.execute(
      [:caretaker, :usp, :agent, :register],
      %{count: 1},
      Map.merge(%{endpoint_id: endpoint_id}, metadata)
    )
  end

  @doc """
  Emits an event for agent deregistration.
  """
  def emit_agent_deregister(endpoint_id, metadata \\ %{}) do
    :telemetry.execute(
      [:caretaker, :usp, :agent, :deregister],
      %{count: 1},
      Map.merge(%{endpoint_id: endpoint_id}, metadata)
    )
  end

  @doc """
  Emits an event for controller message received.
  """
  def emit_controller_message_received(msg, metadata \\ %{}) do
    :telemetry.execute(
      [:caretaker, :usp, :controller, :message_received],
      %{count: 1},
      Map.merge(message_metadata(msg), metadata)
    )
  end

  @doc """
  Emits an event for controller message sent.
  """
  def emit_controller_message_sent(msg, metadata \\ %{}) do
    :telemetry.execute(
      [:caretaker, :usp, :controller, :message_sent],
      %{count: 1},
      Map.merge(message_metadata(msg), metadata)
    )
  end

  @doc """
  Emits an event for agent connected to controller.
  """
  def emit_agent_connected(endpoint_id, metadata \\ %{}) do
    :telemetry.execute(
      [:caretaker, :usp, :controller, :agent_connected],
      %{count: 1},
      Map.merge(%{endpoint_id: endpoint_id}, metadata)
    )
  end

  @doc """
  Emits an event for agent disconnected from controller.
  """
  def emit_agent_disconnected(endpoint_id, metadata \\ %{}) do
    :telemetry.execute(
      [:caretaker, :usp, :controller, :agent_disconnected],
      %{count: 1},
      Map.merge(%{endpoint_id: endpoint_id}, metadata)
    )
  end

  @doc """
  Emits an event for transport connection.
  """
  def emit_transport_connect(transport, endpoint_id, metadata \\ %{}) do
    :telemetry.execute(
      [:caretaker, :usp, :transport, :connect],
      %{count: 1},
      Map.merge(%{transport: transport, endpoint_id: endpoint_id}, metadata)
    )
  end

  @doc """
  Emits an event for transport disconnection.
  """
  def emit_transport_disconnect(transport, endpoint_id, metadata \\ %{}) do
    :telemetry.execute(
      [:caretaker, :usp, :transport, :disconnect],
      %{count: 1},
      Map.merge(%{transport: transport, endpoint_id: endpoint_id}, metadata)
    )
  end

  @doc """
  Emits an event for transport error.
  """
  def emit_transport_error(transport, reason, metadata \\ %{}) do
    :telemetry.execute(
      [:caretaker, :usp, :transport, :error],
      %{count: 1},
      Map.merge(%{transport: transport, reason: reason}, metadata)
    )
  end

  # Private helpers

  defp message_metadata(%{header: header}) do
    %{
      msg_type: header.msg_type,
      msg_id: header.msg_id
    }
  end

  defp message_metadata(_), do: %{}

  defp extract_msg_type({:ok, %{header: header}}), do: header.msg_type
  defp extract_msg_type(_), do: :unknown
end
