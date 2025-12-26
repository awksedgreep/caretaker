defmodule Caretaker.USP.Transport.MQTT.Topics do
  @moduledoc """
  USP MQTT topic structure per TR-369 specification.

  ## Topic Structure

  USP over MQTT uses a hierarchical topic structure:

  ```
  usp/
  ├── controller/<controller_id>/
  │   └── request              # Controller receives requests here
  └── agent/<agent_id>/
      ├── request              # Agent receives requests here
      └── notify               # Agent sends notifications here
  ```

  ## Message Flow

  1. **Agent → Controller (Register, Notify)**:
     - Agent publishes to: `usp/controller/<controller_id>/request`
     - Response topic in payload: `usp/agent/<agent_id>/request`

  2. **Controller → Agent (Get, Set, etc.)**:
     - Controller publishes to: `usp/agent/<agent_id>/request`
     - Response topic in payload: `usp/controller/<controller_id>/request`

  ## MQTT v5 Response Topics

  When using MQTT v5, the response topic is included in the MQTT properties
  rather than being derived from the USP Record.

  """

  @topic_prefix "usp"

  @doc """
  Returns the topic prefix.
  """
  @spec prefix() :: String.t()
  def prefix, do: @topic_prefix

  @doc """
  Builds the topic for an agent to receive requests.

  ## Examples

      iex> Caretaker.USP.Transport.MQTT.Topics.agent_request("os::ACME-Router-123")
      "usp/agent/os::ACME-Router-123/request"

  """
  @spec agent_request(String.t()) :: String.t()
  def agent_request(agent_id) do
    "#{@topic_prefix}/agent/#{agent_id}/request"
  end

  @doc """
  Builds the topic for an agent to send notifications.
  """
  @spec agent_notify(String.t()) :: String.t()
  def agent_notify(agent_id) do
    "#{@topic_prefix}/agent/#{agent_id}/notify"
  end

  @doc """
  Builds the topic for a controller to receive messages.
  """
  @spec controller_request(String.t()) :: String.t()
  def controller_request(controller_id) do
    "#{@topic_prefix}/controller/#{controller_id}/request"
  end

  @doc """
  Builds a wildcard subscription topic for a controller to receive
  all agent notifications.
  """
  @spec controller_notify_subscription() :: String.t()
  def controller_notify_subscription do
    "#{@topic_prefix}/agent/+/notify"
  end

  @doc """
  Builds a wildcard subscription topic for an agent to receive
  requests from any controller.
  """
  @spec agent_request_subscription(String.t()) :: String.t()
  def agent_request_subscription(agent_id) do
    agent_request(agent_id)
  end

  @doc """
  Parses an endpoint ID from a topic.

  ## Examples

      iex> Caretaker.USP.Transport.MQTT.Topics.parse_endpoint_from_topic("usp/agent/os::device-123/request")
      {:ok, {:agent, "os::device-123"}}

      iex> Caretaker.USP.Transport.MQTT.Topics.parse_endpoint_from_topic("usp/controller/self::acs/request")
      {:ok, {:controller, "self::acs"}}

  """
  @spec parse_endpoint_from_topic(String.t()) :: {:ok, {:agent | :controller, String.t()}} | {:error, :invalid_topic}
  def parse_endpoint_from_topic(topic) do
    case String.split(topic, "/") do
      [@topic_prefix, "agent", endpoint_id, _type] ->
        {:ok, {:agent, endpoint_id}}

      [@topic_prefix, "controller", endpoint_id, _type] ->
        {:ok, {:controller, endpoint_id}}

      _ ->
        {:error, :invalid_topic}
    end
  end

  @doc """
  Builds the response topic for a given request topic.

  Given the topic a message was received on, returns the topic
  to publish the response to.
  """
  @spec response_topic_for(String.t(), String.t()) :: String.t()
  def response_topic_for(received_topic, responder_id) do
    case parse_endpoint_from_topic(received_topic) do
      {:ok, {:agent, _agent_id}} ->
        # Request came from an agent, respond to controller
        controller_request(responder_id)

      {:ok, {:controller, _controller_id}} ->
        # Request came from a controller, respond to agent
        agent_request(responder_id)

      {:error, _} ->
        # Fallback: assume responder is an agent
        agent_request(responder_id)
    end
  end

  @doc """
  Validates a topic format.
  """
  @spec valid_topic?(String.t()) :: boolean()
  def valid_topic?(topic) do
    case parse_endpoint_from_topic(topic) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end
end
