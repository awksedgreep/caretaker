defmodule Caretaker.Proto.Usp.MsgType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:ERROR, 0)
  field(:GET, 1)
  field(:GET_RESP, 2)
  field(:NOTIFY, 3)
  field(:SET, 4)
  field(:SET_RESP, 5)
  field(:OPERATE, 6)
  field(:OPERATE_RESP, 7)
  field(:ADD, 8)
  field(:ADD_RESP, 9)
  field(:DELETE, 10)
  field(:DELETE_RESP, 11)
  field(:GET_SUPPORTED_DM, 12)
  field(:GET_SUPPORTED_DM_RESP, 13)
  field(:GET_INSTANCES, 14)
  field(:GET_INSTANCES_RESP, 15)
  field(:NOTIFY_RESP, 16)
  field(:GET_SUPPORTED_PROTO, 17)
  field(:GET_SUPPORTED_PROTO_RESP, 18)
  field(:REGISTER, 19)
  field(:REGISTER_RESP, 20)
  field(:DEREGISTER, 21)
  field(:DEREGISTER_RESP, 22)
end

defmodule Caretaker.Proto.Usp.ObjAccessType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:OBJ_READ_ONLY, 0)
  field(:OBJ_ADD_DELETE, 1)
  field(:OBJ_ADD_ONLY, 2)
  field(:OBJ_DELETE_ONLY, 3)
end

defmodule Caretaker.Proto.Usp.ParamAccessType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:PARAM_READ_ONLY, 0)
  field(:PARAM_READ_WRITE, 1)
  field(:PARAM_WRITE_ONLY, 2)
end

defmodule Caretaker.Proto.Usp.ParamValueType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:PARAM_UNKNOWN, 0)
  field(:PARAM_BASE_64, 1)
  field(:PARAM_BOOLEAN, 2)
  field(:PARAM_DATE_TIME, 3)
  field(:PARAM_DECIMAL, 4)
  field(:PARAM_HEX_BINARY, 5)
  field(:PARAM_INT, 6)
  field(:PARAM_LONG, 7)
  field(:PARAM_STRING, 8)
  field(:PARAM_UNSIGNED_INT, 9)
  field(:PARAM_UNSIGNED_LONG, 10)
end

defmodule Caretaker.Proto.Usp.CmdType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:CMD_SYNC, 0)
  field(:CMD_ASYNC, 1)
end

defmodule Caretaker.Proto.Usp.Msg do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:header, 1, type: Caretaker.Proto.Usp.Header)
  field(:body, 2, type: Caretaker.Proto.Usp.Body)
end

defmodule Caretaker.Proto.Usp.Header do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:msg_id, 1, type: :string, json_name: "msgId")
  field(:msg_type, 2, type: Caretaker.Proto.Usp.MsgType, json_name: "msgType", enum: true)
end

defmodule Caretaker.Proto.Usp.Body do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof(:msg_body, 0)

  field(:request, 1, type: Caretaker.Proto.Usp.Request, oneof: 0)
  field(:response, 2, type: Caretaker.Proto.Usp.Response, oneof: 0)
  field(:error, 3, type: Caretaker.Proto.Usp.Error, oneof: 0)
end

defmodule Caretaker.Proto.Usp.Request do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof(:req_type, 0)

  field(:get, 1, type: Caretaker.Proto.Usp.Get, oneof: 0)

  field(:get_supported_dm, 2,
    type: Caretaker.Proto.Usp.GetSupportedDM,
    json_name: "getSupportedDm",
    oneof: 0
  )

  field(:get_instances, 3,
    type: Caretaker.Proto.Usp.GetInstances,
    json_name: "getInstances",
    oneof: 0
  )

  field(:set, 4, type: Caretaker.Proto.Usp.Set, oneof: 0)
  field(:add, 5, type: Caretaker.Proto.Usp.Add, oneof: 0)
  field(:delete, 6, type: Caretaker.Proto.Usp.Delete, oneof: 0)
  field(:operate, 7, type: Caretaker.Proto.Usp.Operate, oneof: 0)
  field(:notify, 8, type: Caretaker.Proto.Usp.Notify, oneof: 0)

  field(:get_supported_protocol, 9,
    type: Caretaker.Proto.Usp.GetSupportedProtocol,
    json_name: "getSupportedProtocol",
    oneof: 0
  )

  field(:register, 10, type: Caretaker.Proto.Usp.Register, oneof: 0)
  field(:deregister, 11, type: Caretaker.Proto.Usp.Deregister, oneof: 0)
end

defmodule Caretaker.Proto.Usp.Response do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof(:resp_type, 0)

  field(:get_resp, 1, type: Caretaker.Proto.Usp.GetResp, json_name: "getResp", oneof: 0)

  field(:get_supported_dm_resp, 2,
    type: Caretaker.Proto.Usp.GetSupportedDMResp,
    json_name: "getSupportedDmResp",
    oneof: 0
  )

  field(:get_instances_resp, 3,
    type: Caretaker.Proto.Usp.GetInstancesResp,
    json_name: "getInstancesResp",
    oneof: 0
  )

  field(:set_resp, 4, type: Caretaker.Proto.Usp.SetResp, json_name: "setResp", oneof: 0)
  field(:add_resp, 5, type: Caretaker.Proto.Usp.AddResp, json_name: "addResp", oneof: 0)
  field(:delete_resp, 6, type: Caretaker.Proto.Usp.DeleteResp, json_name: "deleteResp", oneof: 0)

  field(:operate_resp, 7,
    type: Caretaker.Proto.Usp.OperateResp,
    json_name: "operateResp",
    oneof: 0
  )

  field(:notify_resp, 8, type: Caretaker.Proto.Usp.NotifyResp, json_name: "notifyResp", oneof: 0)

  field(:get_supported_protocol_resp, 9,
    type: Caretaker.Proto.Usp.GetSupportedProtocolResp,
    json_name: "getSupportedProtocolResp",
    oneof: 0
  )

  field(:register_resp, 10,
    type: Caretaker.Proto.Usp.RegisterResp,
    json_name: "registerResp",
    oneof: 0
  )

  field(:deregister_resp, 11,
    type: Caretaker.Proto.Usp.DeregisterResp,
    json_name: "deregisterResp",
    oneof: 0
  )
end

defmodule Caretaker.Proto.Usp.Get do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:param_paths, 1, repeated: true, type: :string, json_name: "paramPaths")
  field(:max_depth, 2, type: :uint32, json_name: "maxDepth")
end

defmodule Caretaker.Proto.Usp.GetResp do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:req_path_results, 1,
    repeated: true,
    type: Caretaker.Proto.Usp.RequestedPathResult,
    json_name: "reqPathResults"
  )
end

defmodule Caretaker.Proto.Usp.RequestedPathResult do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:requested_path, 1, type: :string, json_name: "requestedPath")
  field(:err_code, 2, type: :fixed32, json_name: "errCode")
  field(:err_msg, 3, type: :string, json_name: "errMsg")

  field(:resolved_path_results, 4,
    repeated: true,
    type: Caretaker.Proto.Usp.ResolvedPathResult,
    json_name: "resolvedPathResults"
  )
end

defmodule Caretaker.Proto.Usp.ResolvedPathResult.ResultParamsEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Caretaker.Proto.Usp.ResolvedPathResult do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:resolved_path, 1, type: :string, json_name: "resolvedPath")

  field(:result_params, 2,
    repeated: true,
    type: Caretaker.Proto.Usp.ResolvedPathResult.ResultParamsEntry,
    json_name: "resultParams",
    map: true
  )
end

defmodule Caretaker.Proto.Usp.Set do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:allow_partial, 1, type: :bool, json_name: "allowPartial")

  field(:update_objs, 2,
    repeated: true,
    type: Caretaker.Proto.Usp.UpdateObject,
    json_name: "updateObjs"
  )
end

defmodule Caretaker.Proto.Usp.UpdateObject do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:obj_path, 1, type: :string, json_name: "objPath")

  field(:param_settings, 2,
    repeated: true,
    type: Caretaker.Proto.Usp.UpdateParamSetting,
    json_name: "paramSettings"
  )
end

defmodule Caretaker.Proto.Usp.UpdateParamSetting do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:param, 1, type: :string)
  field(:value, 2, type: :string)
  field(:required, 3, type: :bool)
end

defmodule Caretaker.Proto.Usp.SetResp do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:updated_obj_results, 1,
    repeated: true,
    type: Caretaker.Proto.Usp.UpdatedObjectResult,
    json_name: "updatedObjResults"
  )
end

defmodule Caretaker.Proto.Usp.UpdatedObjectResult do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:requested_path, 1, type: :string, json_name: "requestedPath")
  field(:oper_status, 2, type: Caretaker.Proto.Usp.OperationStatus, json_name: "operStatus")

  field(:updated_inst_results, 3,
    repeated: true,
    type: Caretaker.Proto.Usp.UpdatedInstanceResult,
    json_name: "updatedInstResults"
  )
end

defmodule Caretaker.Proto.Usp.UpdatedInstanceResult.UpdatedParamsEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Caretaker.Proto.Usp.UpdatedInstanceResult do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:affected_path, 1, type: :string, json_name: "affectedPath")

  field(:param_errs, 2,
    repeated: true,
    type: Caretaker.Proto.Usp.ParameterError,
    json_name: "paramErrs"
  )

  field(:updated_params, 3,
    repeated: true,
    type: Caretaker.Proto.Usp.UpdatedInstanceResult.UpdatedParamsEntry,
    json_name: "updatedParams",
    map: true
  )
end

defmodule Caretaker.Proto.Usp.ParameterError do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:param, 1, type: :string)
  field(:err_code, 2, type: :fixed32, json_name: "errCode")
  field(:err_msg, 3, type: :string, json_name: "errMsg")
end

defmodule Caretaker.Proto.Usp.Add do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:allow_partial, 1, type: :bool, json_name: "allowPartial")

  field(:create_objs, 2,
    repeated: true,
    type: Caretaker.Proto.Usp.CreateObject,
    json_name: "createObjs"
  )
end

defmodule Caretaker.Proto.Usp.CreateObject do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:obj_path, 1, type: :string, json_name: "objPath")

  field(:param_settings, 2,
    repeated: true,
    type: Caretaker.Proto.Usp.CreateParamSetting,
    json_name: "paramSettings"
  )
end

defmodule Caretaker.Proto.Usp.CreateParamSetting do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:param, 1, type: :string)
  field(:value, 2, type: :string)
  field(:required, 3, type: :bool)
end

defmodule Caretaker.Proto.Usp.AddResp do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:created_obj_results, 1,
    repeated: true,
    type: Caretaker.Proto.Usp.CreatedObjectResult,
    json_name: "createdObjResults"
  )
end

defmodule Caretaker.Proto.Usp.CreatedObjectResult do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:requested_path, 1, type: :string, json_name: "requestedPath")
  field(:oper_status, 2, type: Caretaker.Proto.Usp.OperationStatus, json_name: "operStatus")

  field(:created_inst_results, 3,
    repeated: true,
    type: Caretaker.Proto.Usp.CreatedInstanceResult,
    json_name: "createdInstResults"
  )
end

defmodule Caretaker.Proto.Usp.CreatedInstanceResult.UniqueKeysEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Caretaker.Proto.Usp.CreatedInstanceResult do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:instantiated_path, 1, type: :string, json_name: "instantiatedPath")

  field(:param_errs, 2,
    repeated: true,
    type: Caretaker.Proto.Usp.ParameterError,
    json_name: "paramErrs"
  )

  field(:unique_keys, 3,
    repeated: true,
    type: Caretaker.Proto.Usp.CreatedInstanceResult.UniqueKeysEntry,
    json_name: "uniqueKeys",
    map: true
  )
end

defmodule Caretaker.Proto.Usp.Delete do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:allow_partial, 1, type: :bool, json_name: "allowPartial")
  field(:obj_paths, 2, repeated: true, type: :string, json_name: "objPaths")
end

defmodule Caretaker.Proto.Usp.DeleteResp do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:deleted_obj_results, 1,
    repeated: true,
    type: Caretaker.Proto.Usp.DeletedObjectResult,
    json_name: "deletedObjResults"
  )
end

defmodule Caretaker.Proto.Usp.DeletedObjectResult do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:requested_path, 1, type: :string, json_name: "requestedPath")
  field(:oper_status, 2, type: Caretaker.Proto.Usp.OperationStatus, json_name: "operStatus")
  field(:affected_paths, 3, repeated: true, type: :string, json_name: "affectedPaths")

  field(:unaffected_path_errs, 4,
    repeated: true,
    type: Caretaker.Proto.Usp.UnaffectedPathError,
    json_name: "unaffectedPathErrs"
  )
end

defmodule Caretaker.Proto.Usp.UnaffectedPathError do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:unaffected_path, 1, type: :string, json_name: "unaffectedPath")
  field(:err_code, 2, type: :fixed32, json_name: "errCode")
  field(:err_msg, 3, type: :string, json_name: "errMsg")
end

defmodule Caretaker.Proto.Usp.Operate.InputArgsEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Caretaker.Proto.Usp.Operate do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:command, 1, type: :string)
  field(:command_key, 2, type: :string, json_name: "commandKey")
  field(:send_resp, 3, type: :bool, json_name: "sendResp")

  field(:input_args, 4,
    repeated: true,
    type: Caretaker.Proto.Usp.Operate.InputArgsEntry,
    json_name: "inputArgs",
    map: true
  )
end

defmodule Caretaker.Proto.Usp.OperateResp do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof(:operation_resp, 0)

  field(:operation_results, 1, type: :string, json_name: "operationResults")

  field(:req_output_args, 2,
    type: Caretaker.Proto.Usp.OutputArgs,
    json_name: "reqOutputArgs",
    oneof: 0
  )

  field(:cmd_failure, 3,
    type: Caretaker.Proto.Usp.CommandFailure,
    json_name: "cmdFailure",
    oneof: 0
  )
end

defmodule Caretaker.Proto.Usp.OutputArgs.OutputArgsEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Caretaker.Proto.Usp.OutputArgs do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:output_args, 1,
    repeated: true,
    type: Caretaker.Proto.Usp.OutputArgs.OutputArgsEntry,
    json_name: "outputArgs",
    map: true
  )
end

defmodule Caretaker.Proto.Usp.CommandFailure do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:err_code, 1, type: :fixed32, json_name: "errCode")
  field(:err_msg, 2, type: :string, json_name: "errMsg")
end

defmodule Caretaker.Proto.Usp.Notify do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof(:notification, 0)

  field(:subscription_id, 1, type: :string, json_name: "subscriptionId")
  field(:send_resp, 2, type: :bool, json_name: "sendResp")
  field(:event, 3, type: Caretaker.Proto.Usp.Event, oneof: 0)

  field(:value_change, 4,
    type: Caretaker.Proto.Usp.ValueChange,
    json_name: "valueChange",
    oneof: 0
  )

  field(:obj_creation, 5,
    type: Caretaker.Proto.Usp.ObjectCreation,
    json_name: "objCreation",
    oneof: 0
  )

  field(:obj_deletion, 6,
    type: Caretaker.Proto.Usp.ObjectDeletion,
    json_name: "objDeletion",
    oneof: 0
  )

  field(:oper_complete, 7,
    type: Caretaker.Proto.Usp.OperationComplete,
    json_name: "operComplete",
    oneof: 0
  )

  field(:on_board_req, 8,
    type: Caretaker.Proto.Usp.OnBoardRequest,
    json_name: "onBoardReq",
    oneof: 0
  )
end

defmodule Caretaker.Proto.Usp.Event.ParamsEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Caretaker.Proto.Usp.Event do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:obj_path, 1, type: :string, json_name: "objPath")
  field(:event_name, 2, type: :string, json_name: "eventName")
  field(:params, 3, repeated: true, type: Caretaker.Proto.Usp.Event.ParamsEntry, map: true)
end

defmodule Caretaker.Proto.Usp.ValueChange do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:param_path, 1, type: :string, json_name: "paramPath")
  field(:param_value, 2, type: :string, json_name: "paramValue")
end

defmodule Caretaker.Proto.Usp.ObjectCreation.UniqueKeysEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Caretaker.Proto.Usp.ObjectCreation do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:obj_path, 1, type: :string, json_name: "objPath")

  field(:unique_keys, 2,
    repeated: true,
    type: Caretaker.Proto.Usp.ObjectCreation.UniqueKeysEntry,
    json_name: "uniqueKeys",
    map: true
  )
end

defmodule Caretaker.Proto.Usp.ObjectDeletion do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:obj_path, 1, type: :string, json_name: "objPath")
end

defmodule Caretaker.Proto.Usp.OperationComplete do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof(:operation_resp, 0)

  field(:obj_path, 1, type: :string, json_name: "objPath")
  field(:command_name, 2, type: :string, json_name: "commandName")
  field(:command_key, 3, type: :string, json_name: "commandKey")

  field(:req_output_args, 4,
    type: Caretaker.Proto.Usp.OutputArgs,
    json_name: "reqOutputArgs",
    oneof: 0
  )

  field(:cmd_failure, 5,
    type: Caretaker.Proto.Usp.CommandFailure,
    json_name: "cmdFailure",
    oneof: 0
  )
end

defmodule Caretaker.Proto.Usp.OnBoardRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:oui, 1, type: :string)
  field(:product_class, 2, type: :string, json_name: "productClass")
  field(:serial_number, 3, type: :string, json_name: "serialNumber")

  field(:agent_supported_protocol_versions, 4,
    type: :string,
    json_name: "agentSupportedProtocolVersions"
  )
end

defmodule Caretaker.Proto.Usp.NotifyResp do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:subscription_id, 1, type: :string, json_name: "subscriptionId")
end

defmodule Caretaker.Proto.Usp.GetSupportedDM do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:obj_paths, 1, repeated: true, type: :string, json_name: "objPaths")
  field(:first_level_only, 2, type: :bool, json_name: "firstLevelOnly")
  field(:return_commands, 3, type: :bool, json_name: "returnCommands")
  field(:return_events, 4, type: :bool, json_name: "returnEvents")
  field(:return_params, 5, type: :bool, json_name: "returnParams")
  field(:return_unique_key_sets, 6, type: :bool, json_name: "returnUniqueKeySets")
end

defmodule Caretaker.Proto.Usp.GetSupportedDMResp do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:req_obj_results, 1,
    repeated: true,
    type: Caretaker.Proto.Usp.RequestedObjectResult,
    json_name: "reqObjResults"
  )
end

defmodule Caretaker.Proto.Usp.RequestedObjectResult do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:req_obj_path, 1, type: :string, json_name: "reqObjPath")
  field(:err_code, 2, type: :fixed32, json_name: "errCode")
  field(:err_msg, 3, type: :string, json_name: "errMsg")
  field(:data_model_inst_uri, 4, type: :string, json_name: "dataModelInstUri")

  field(:supported_objs, 5,
    repeated: true,
    type: Caretaker.Proto.Usp.SupportedObjectResult,
    json_name: "supportedObjs"
  )
end

defmodule Caretaker.Proto.Usp.SupportedObjectResult do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:supported_obj_path, 1, type: :string, json_name: "supportedObjPath")
  field(:access, 2, type: Caretaker.Proto.Usp.ObjAccessType, enum: true)
  field(:is_multi_instance, 3, type: :bool, json_name: "isMultiInstance")

  field(:supported_params, 4,
    repeated: true,
    type: Caretaker.Proto.Usp.SupportedParamResult,
    json_name: "supportedParams"
  )

  field(:supported_commands, 5,
    repeated: true,
    type: Caretaker.Proto.Usp.SupportedCommandResult,
    json_name: "supportedCommands"
  )

  field(:supported_events, 6,
    repeated: true,
    type: Caretaker.Proto.Usp.SupportedEventResult,
    json_name: "supportedEvents"
  )

  field(:divergent_paths, 7, repeated: true, type: :string, json_name: "divergentPaths")

  field(:unique_key_sets, 8,
    repeated: true,
    type: Caretaker.Proto.Usp.SupportedUniqueKeySet,
    json_name: "uniqueKeySets"
  )
end

defmodule Caretaker.Proto.Usp.SupportedParamResult do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:param_name, 1, type: :string, json_name: "paramName")
  field(:access, 2, type: Caretaker.Proto.Usp.ParamAccessType, enum: true)

  field(:value_type, 3,
    type: Caretaker.Proto.Usp.ParamValueType,
    json_name: "valueType",
    enum: true
  )

  field(:value_change, 4, type: :string, json_name: "valueChange")
end

defmodule Caretaker.Proto.Usp.SupportedCommandResult do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:command_name, 1, type: :string, json_name: "commandName")
  field(:input_arg_names, 2, repeated: true, type: :string, json_name: "inputArgNames")
  field(:output_arg_names, 3, repeated: true, type: :string, json_name: "outputArgNames")
  field(:command_type, 4, type: Caretaker.Proto.Usp.CmdType, json_name: "commandType", enum: true)
end

defmodule Caretaker.Proto.Usp.SupportedEventResult do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:event_name, 1, type: :string, json_name: "eventName")
  field(:arg_names, 2, repeated: true, type: :string, json_name: "argNames")
end

defmodule Caretaker.Proto.Usp.SupportedUniqueKeySet do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key_names, 1, repeated: true, type: :string, json_name: "keyNames")
end

defmodule Caretaker.Proto.Usp.GetInstances do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:obj_paths, 1, repeated: true, type: :string, json_name: "objPaths")
  field(:first_level_only, 2, type: :bool, json_name: "firstLevelOnly")
end

defmodule Caretaker.Proto.Usp.GetInstancesResp do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:req_path_results, 1,
    repeated: true,
    type: Caretaker.Proto.Usp.RequestedPathResult,
    json_name: "reqPathResults"
  )
end

defmodule Caretaker.Proto.Usp.CurrInstance.UniqueKeysEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Caretaker.Proto.Usp.CurrInstance do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:instantiated_obj_path, 1, type: :string, json_name: "instantiatedObjPath")

  field(:unique_keys, 2,
    repeated: true,
    type: Caretaker.Proto.Usp.CurrInstance.UniqueKeysEntry,
    json_name: "uniqueKeys",
    map: true
  )
end

defmodule Caretaker.Proto.Usp.GetSupportedProtocol do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:controller_supported_protocol_versions, 1,
    type: :string,
    json_name: "controllerSupportedProtocolVersions"
  )
end

defmodule Caretaker.Proto.Usp.GetSupportedProtocolResp do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:agent_supported_protocol_versions, 1,
    type: :string,
    json_name: "agentSupportedProtocolVersions"
  )
end

defmodule Caretaker.Proto.Usp.Register do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:allow_partial, 1, type: :bool, json_name: "allowPartial")

  field(:reg_paths, 2,
    repeated: true,
    type: Caretaker.Proto.Usp.RegistrationPath,
    json_name: "regPaths"
  )
end

defmodule Caretaker.Proto.Usp.RegistrationPath do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:path, 1, type: :string)
end

defmodule Caretaker.Proto.Usp.RegisterResp do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:registered_path_results, 1,
    repeated: true,
    type: Caretaker.Proto.Usp.RegisteredPathResult,
    json_name: "registeredPathResults"
  )
end

defmodule Caretaker.Proto.Usp.RegisteredPathResult do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:requested_path, 1, type: :string, json_name: "requestedPath")
  field(:oper_status, 2, type: Caretaker.Proto.Usp.OperationStatus, json_name: "operStatus")
end

defmodule Caretaker.Proto.Usp.Deregister do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:paths, 1, repeated: true, type: :string)
end

defmodule Caretaker.Proto.Usp.DeregisterResp do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:deregistered_path_results, 1,
    repeated: true,
    type: Caretaker.Proto.Usp.DeregisteredPathResult,
    json_name: "deregisteredPathResults"
  )
end

defmodule Caretaker.Proto.Usp.DeregisteredPathResult do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:requested_path, 1, type: :string, json_name: "requestedPath")
  field(:oper_status, 2, type: Caretaker.Proto.Usp.OperationStatus, json_name: "operStatus")
end

defmodule Caretaker.Proto.Usp.Error do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:err_code, 1, type: :fixed32, json_name: "errCode")
  field(:err_msg, 2, type: :string, json_name: "errMsg")

  field(:param_errs, 3,
    repeated: true,
    type: Caretaker.Proto.Usp.ParamError,
    json_name: "paramErrs"
  )
end

defmodule Caretaker.Proto.Usp.ParamError do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:param_path, 1, type: :string, json_name: "paramPath")
  field(:err_code, 2, type: :fixed32, json_name: "errCode")
  field(:err_msg, 3, type: :string, json_name: "errMsg")
end

defmodule Caretaker.Proto.Usp.OperationStatus do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof(:oper_status, 0)

  field(:oper_success, 1,
    type: Caretaker.Proto.Usp.OperationSuccess,
    json_name: "operSuccess",
    oneof: 0
  )

  field(:oper_failure, 2,
    type: Caretaker.Proto.Usp.OperationFailure,
    json_name: "operFailure",
    oneof: 0
  )
end

defmodule Caretaker.Proto.Usp.OperationSuccess do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3
end

defmodule Caretaker.Proto.Usp.OperationFailure do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:err_code, 1, type: :fixed32, json_name: "errCode")
  field(:err_msg, 2, type: :string, json_name: "errMsg")
end
