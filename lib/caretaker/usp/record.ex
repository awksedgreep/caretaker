defmodule Caretaker.USP.Record do
  @moduledoc """
  USP Record handling for transport layer.

  USP Records wrap USP Messages for transport over various Message Transfer
  Protocols (MTPs) like WebSocket, MQTT, STOMP, and CoAP.

  ## Record Structure

  A USP Record contains:
  - `version` - USP protocol version (e.g., "1.3")
  - `to_id` - Destination endpoint ID
  - `from_id` - Source endpoint ID
  - `payload_security` - Security mode (PLAINTEXT, TLS12, TLS13)
  - `mac_signature` - Optional MAC signature for payload integrity
  - `sender_cert` - Optional sender certificate
  - `record_type` - One of:
    - `no_session_context` - Standalone message
    - `session_context` - Message with session/sequence tracking
    - `websocket_connect` - WebSocket connection establishment
    - `mqtt_connect` - MQTT connection establishment
    - `stomp_connect` - STOMP connection establishment
    - `disconnect` - Disconnection message

  ## Endpoint ID Format

  Endpoint IDs follow the format: `<authority>::<instance-id>`

  Examples:
  - Agent: `os::012345-MyDevice-0050C2345678`
  - Controller: `self::acs.example.com`

  ## Examples

      # Create a record for a Get request
      msg = Caretaker.USP.Proto.build_get(["Device.DeviceInfo."])
      record = Caretaker.USP.Record.new(msg,
        to_id: "os::agent-123",
        from_id: "self::controller"
      )

      # Encode for transport
      {:ok, binary} = Caretaker.USP.Record.encode(record)

      # Decode received record
      {:ok, record} = Caretaker.USP.Record.decode(binary)
      {:ok, msg} = Caretaker.USP.Record.extract_message(record)

  """

  alias Caretaker.Proto.UspRecord.{
    Record,
    NoSessionContextRecord,
    SessionContextRecord,
    WebSocketConnectRecord,
    MQTTConnectRecord,
    DisconnectRecord
  }
  alias Caretaker.Proto.Usp.Msg
  alias Caretaker.USP.Proto

  @type endpoint_id :: String.t()
  @type record :: Record.t()

  @default_version "1.3"

  @doc """
  Creates a new USP Record wrapping a message.

  ## Options

  - `:to_id` - Destination endpoint ID (required for routing)
  - `:from_id` - Source endpoint ID
  - `:version` - USP version (default: "1.3")
  - `:payload_security` - Security mode (default: :PLAINTEXT)

  ## Examples

      iex> msg = Caretaker.USP.Proto.build_get(["Device."])
      iex> record = Caretaker.USP.Record.new(msg, to_id: "agent", from_id: "controller")
      iex> record.to_id
      "agent"

  """
  @spec new(Msg.t(), keyword()) :: Record.t()
  def new(%Msg{} = msg, opts \\ []) do
    {:ok, payload} = Proto.encode(msg)

    %Record{
      version: Keyword.get(opts, :version, @default_version),
      to_id: Keyword.get(opts, :to_id, ""),
      from_id: Keyword.get(opts, :from_id, ""),
      payload_security: Keyword.get(opts, :payload_security, :PLAINTEXT),
      mac_signature: <<>>,
      sender_cert: <<>>,
      record_type: {:no_session_context, %NoSessionContextRecord{payload: payload}}
    }
  end

  @doc """
  Creates a new USP Record with session context.

  Session context is used for message segmentation and retransmission.

  ## Options

  - `:to_id` - Destination endpoint ID
  - `:from_id` - Source endpoint ID
  - `:session_id` - Session identifier
  - `:sequence_id` - Message sequence number
  - `:expected_id` - Expected next sequence from peer
  - `:retransmit_id` - Retransmission request ID

  """
  @spec new_with_session(Msg.t(), keyword()) :: Record.t()
  def new_with_session(%Msg{} = msg, opts \\ []) do
    {:ok, payload} = Proto.encode(msg)

    session_context = %SessionContextRecord{
      session_id: Keyword.get(opts, :session_id, 0),
      sequence_id: Keyword.get(opts, :sequence_id, 0),
      expected_id: Keyword.get(opts, :expected_id, 0),
      retransmit_id: Keyword.get(opts, :retransmit_id, 0),
      payload_sar_state: :NONE,
      payloadrec_sar_state: :NONE,
      payload: payload
    }

    %Record{
      version: Keyword.get(opts, :version, @default_version),
      to_id: Keyword.get(opts, :to_id, ""),
      from_id: Keyword.get(opts, :from_id, ""),
      payload_security: Keyword.get(opts, :payload_security, :PLAINTEXT),
      mac_signature: <<>>,
      sender_cert: <<>>,
      record_type: {:session_context, session_context}
    }
  end

  @doc """
  Creates a WebSocket connect record.
  """
  @spec new_websocket_connect(keyword()) :: Record.t()
  def new_websocket_connect(opts \\ []) do
    %Record{
      version: Keyword.get(opts, :version, @default_version),
      to_id: Keyword.get(opts, :to_id, ""),
      from_id: Keyword.get(opts, :from_id, ""),
      payload_security: :PLAINTEXT,
      record_type: {:websocket_connect, %WebSocketConnectRecord{}}
    }
  end

  @doc """
  Creates an MQTT connect record.
  """
  @spec new_mqtt_connect(String.t(), keyword()) :: Record.t()
  def new_mqtt_connect(subscribed_topic, opts \\ []) do
    %Record{
      version: Keyword.get(opts, :version, @default_version),
      to_id: Keyword.get(opts, :to_id, ""),
      from_id: Keyword.get(opts, :from_id, ""),
      payload_security: :PLAINTEXT,
      record_type: {:mqtt_connect, %MQTTConnectRecord{
        version: Keyword.get(opts, :mqtt_version, :V5),
        subscribed_topic: subscribed_topic
      }}
    }
  end

  @doc """
  Creates a disconnect record.
  """
  @spec new_disconnect(keyword()) :: Record.t()
  def new_disconnect(opts \\ []) do
    %Record{
      version: Keyword.get(opts, :version, @default_version),
      to_id: Keyword.get(opts, :to_id, ""),
      from_id: Keyword.get(opts, :from_id, ""),
      payload_security: :PLAINTEXT,
      record_type: {:disconnect, %DisconnectRecord{
        reason_code: Keyword.get(opts, :reason_code, 0),
        reason: Keyword.get(opts, :reason, "")
      }}
    }
  end

  @doc """
  Encodes a USP Record to binary.
  """
  @spec encode(Record.t()) :: {:ok, binary()} | {:error, term()}
  def encode(%Record{} = record) do
    {:ok, Record.encode(record)}
  rescue
    e -> {:error, e}
  end

  @doc """
  Decodes a binary to a USP Record.
  """
  @spec decode(binary()) :: {:ok, Record.t()} | {:error, term()}
  def decode(binary) when is_binary(binary) do
    {:ok, Record.decode(binary)}
  rescue
    e -> {:error, e}
  end

  @doc """
  Extracts the USP Message from a Record.

  Returns `{:ok, msg}` for records containing a message payload,
  or `{:error, :no_payload}` for connect/disconnect records.
  """
  @spec extract_message(Record.t()) :: {:ok, Msg.t()} | {:error, term()}
  def extract_message(%Record{record_type: {:no_session_context, %{payload: payload}}}) do
    Proto.decode(payload)
  end

  def extract_message(%Record{record_type: {:session_context, %{payload: payload}}}) do
    Proto.decode(payload)
  end

  def extract_message(%Record{record_type: {type, _}})
      when type in [:websocket_connect, :mqtt_connect, :stomp_connect, :uds_connect, :disconnect] do
    {:error, :no_payload}
  end

  @doc """
  Gets the record type.
  """
  @spec record_type(Record.t()) :: atom()
  def record_type(%Record{record_type: {type, _}}), do: type

  @doc """
  Checks if the record contains a message payload.
  """
  @spec has_payload?(Record.t()) :: boolean()
  def has_payload?(%Record{record_type: {:no_session_context, _}}), do: true
  def has_payload?(%Record{record_type: {:session_context, _}}), do: true
  def has_payload?(_), do: false

  @doc """
  Checks if the record is a connect record.
  """
  @spec connect?(Record.t()) :: boolean()
  def connect?(%Record{record_type: {type, _}})
      when type in [:websocket_connect, :mqtt_connect, :stomp_connect, :uds_connect] do
    true
  end
  def connect?(_), do: false

  @doc """
  Checks if the record is a disconnect record.
  """
  @spec disconnect?(Record.t()) :: boolean()
  def disconnect?(%Record{record_type: {:disconnect, _}}), do: true
  def disconnect?(_), do: false

  @doc """
  Gets the session context from a record, if present.
  """
  @spec session_context(Record.t()) :: {:ok, map()} | {:error, :no_session_context}
  def session_context(%Record{record_type: {:session_context, ctx}}) do
    {:ok, %{
      session_id: ctx.session_id,
      sequence_id: ctx.sequence_id,
      expected_id: ctx.expected_id,
      retransmit_id: ctx.retransmit_id
    }}
  end
  def session_context(_), do: {:error, :no_session_context}

  @doc """
  Creates a response record for a given request record.

  Swaps the to_id and from_id and wraps the response message.
  """
  @spec response_for(Record.t(), Msg.t()) :: Record.t()
  def response_for(%Record{} = request, %Msg{} = response_msg) do
    new(response_msg,
      to_id: request.from_id,
      from_id: request.to_id,
      version: request.version,
      payload_security: request.payload_security
    )
  end

  @doc """
  Validates endpoint ID format.

  Endpoint IDs should follow the pattern: `<authority>::<instance-id>`
  """
  @spec valid_endpoint_id?(String.t()) :: boolean()
  def valid_endpoint_id?(id) when is_binary(id) do
    case String.split(id, "::", parts: 2) do
      [authority, instance] when byte_size(authority) > 0 and byte_size(instance) > 0 ->
        true
      _ ->
        false
    end
  end
  def valid_endpoint_id?(_), do: false

  @doc """
  Parses an endpoint ID into authority and instance components.
  """
  @spec parse_endpoint_id(String.t()) :: {:ok, {String.t(), String.t()}} | {:error, :invalid_format}
  def parse_endpoint_id(id) when is_binary(id) do
    case String.split(id, "::", parts: 2) do
      [authority, instance] when byte_size(authority) > 0 and byte_size(instance) > 0 ->
        {:ok, {authority, instance}}
      _ ->
        {:error, :invalid_format}
    end
  end

  @doc """
  Builds an endpoint ID from authority and instance.
  """
  @spec build_endpoint_id(String.t(), String.t()) :: String.t()
  def build_endpoint_id(authority, instance) do
    "#{authority}::#{instance}"
  end

  @doc """
  Builds an agent endpoint ID.

  Agent endpoint IDs typically use "os" as the authority with a device identifier.
  """
  @spec agent_endpoint_id(String.t(), String.t(), String.t()) :: String.t()
  def agent_endpoint_id(oui, product_class, serial_number) do
    build_endpoint_id("os", "#{oui}-#{product_class}-#{serial_number}")
  end

  @doc """
  Builds a controller endpoint ID.

  Controller endpoint IDs typically use "self" as the authority with a domain or identifier.
  """
  @spec controller_endpoint_id(String.t()) :: String.t()
  def controller_endpoint_id(identifier) do
    build_endpoint_id("self", identifier)
  end
end
