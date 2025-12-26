defmodule Caretaker.Proto.UspRecord.PayloadSecurity do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :PLAINTEXT, 0
  field :TLS12, 1
  field :TLS13, 2
end

defmodule Caretaker.Proto.UspRecord.PayloadSARState do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :NONE, 0
  field :BEGIN, 1
  field :INPROCESS, 2
  field :COMPLETE, 3
end

defmodule Caretaker.Proto.UspRecord.MQTTVersion do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :V3_1_1, 0
  field :V5, 1
end

defmodule Caretaker.Proto.UspRecord.STOMPVersion do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :V1_2, 0
end

defmodule Caretaker.Proto.UspRecord.Record do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof :record_type, 0

  field :version, 1, type: :string
  field :to_id, 2, type: :string, json_name: "toId"
  field :from_id, 3, type: :string, json_name: "fromId"

  field :payload_security, 4,
    type: Caretaker.Proto.UspRecord.PayloadSecurity,
    json_name: "payloadSecurity",
    enum: true

  field :mac_signature, 5, type: :bytes, json_name: "macSignature"
  field :sender_cert, 6, type: :bytes, json_name: "senderCert"

  field :no_session_context, 7,
    type: Caretaker.Proto.UspRecord.NoSessionContextRecord,
    json_name: "noSessionContext",
    oneof: 0

  field :session_context, 8,
    type: Caretaker.Proto.UspRecord.SessionContextRecord,
    json_name: "sessionContext",
    oneof: 0

  field :websocket_connect, 9,
    type: Caretaker.Proto.UspRecord.WebSocketConnectRecord,
    json_name: "websocketConnect",
    oneof: 0

  field :mqtt_connect, 10,
    type: Caretaker.Proto.UspRecord.MQTTConnectRecord,
    json_name: "mqttConnect",
    oneof: 0

  field :stomp_connect, 11,
    type: Caretaker.Proto.UspRecord.STOMPConnectRecord,
    json_name: "stompConnect",
    oneof: 0

  field :uds_connect, 12,
    type: Caretaker.Proto.UspRecord.UDSConnectRecord,
    json_name: "udsConnect",
    oneof: 0

  field :disconnect, 13, type: Caretaker.Proto.UspRecord.DisconnectRecord, oneof: 0
end

defmodule Caretaker.Proto.UspRecord.NoSessionContextRecord do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :payload, 1, type: :bytes
end

defmodule Caretaker.Proto.UspRecord.SessionContextRecord do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :session_id, 1, type: :uint64, json_name: "sessionId"
  field :sequence_id, 2, type: :uint64, json_name: "sequenceId"
  field :expected_id, 3, type: :uint64, json_name: "expectedId"
  field :retransmit_id, 4, type: :uint64, json_name: "retransmitId"

  field :payload_sar_state, 5,
    type: Caretaker.Proto.UspRecord.PayloadSARState,
    json_name: "payloadSarState",
    enum: true

  field :payloadrec_sar_state, 6,
    type: Caretaker.Proto.UspRecord.PayloadSARState,
    json_name: "payloadrecSarState",
    enum: true

  field :payload, 7, type: :bytes
end

defmodule Caretaker.Proto.UspRecord.WebSocketConnectRecord do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3
end

defmodule Caretaker.Proto.UspRecord.MQTTConnectRecord do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :version, 1, type: Caretaker.Proto.UspRecord.MQTTVersion, enum: true
  field :subscribed_topic, 2, type: :string, json_name: "subscribedTopic"
end

defmodule Caretaker.Proto.UspRecord.STOMPConnectRecord do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :version, 1, type: Caretaker.Proto.UspRecord.STOMPVersion, enum: true
  field :subscribed_destination, 2, type: :string, json_name: "subscribedDestination"
end

defmodule Caretaker.Proto.UspRecord.UDSConnectRecord do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3
end

defmodule Caretaker.Proto.UspRecord.DisconnectRecord do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :reason_code, 1, type: :uint32, json_name: "reasonCode"
  field :reason, 2, type: :string
end
