defmodule Caretaker.TR069.RPC.Registry do
  @moduledoc """
  Registry mapping between CWMP RPC XML local-names and modules.
  """

  @type rpc_name :: String.t()
  @type rpc_module :: module()

  @mappings %{
    "Inform" => Caretaker.TR069.RPC.Inform,
    "InformResponse" => Caretaker.TR069.RPC.InformResponse,
    "GetParameterNames" => Caretaker.TR069.RPC.GetParameterNames,
    "GetParameterNamesResponse" => Caretaker.TR069.RPC.GetParameterNamesResponse,
    "GetParameterValues" => Caretaker.TR069.RPC.GetParameterValues,
    "GetParameterValuesResponse" => Caretaker.TR069.RPC.GetParameterValuesResponse,
    "SetParameterValues" => Caretaker.TR069.RPC.SetParameterValues,
    "SetParameterValuesResponse" => Caretaker.TR069.RPC.SetParameterValuesResponse,
    "GetParameterAttributes" => Caretaker.TR069.RPC.GetParameterAttributes,
    "GetParameterAttributesResponse" => Caretaker.TR069.RPC.GetParameterAttributesResponse,
    "SetParameterAttributes" => Caretaker.TR069.RPC.SetParameterAttributes,
    "SetParameterAttributesResponse" => Caretaker.TR069.RPC.SetParameterAttributesResponse,
    "AddObject" => Caretaker.TR069.RPC.AddObject,
    "AddObjectResponse" => Caretaker.TR069.RPC.AddObjectResponse,
    "DeleteObject" => Caretaker.TR069.RPC.DeleteObject,
    "DeleteObjectResponse" => Caretaker.TR069.RPC.DeleteObjectResponse,
    "Download" => Caretaker.TR069.RPC.Download,
    "DownloadResponse" => Caretaker.TR069.RPC.DownloadResponse,
    "Reboot" => Caretaker.TR069.RPC.Reboot,
    "RebootResponse" => Caretaker.TR069.RPC.RebootResponse,
    "GetRPCMethods" => Caretaker.TR069.RPC.GetRPCMethods,
    "GetRPCMethodsResponse" => Caretaker.TR069.RPC.GetRPCMethodsResponse,
    "TransferComplete" => Caretaker.TR069.RPC.TransferComplete,
    "TransferCompleteResponse" => Caretaker.TR069.RPC.TransferCompleteResponse,
    "Fault" => Caretaker.TR069.RPC.Fault
  }

  @spec module_for(rpc_name()) :: {:ok, rpc_module()} | :error
  def module_for(name) when is_binary(name) do
    case Map.fetch(@mappings, name) do
      {:ok, mod} -> {:ok, mod}
      :error -> :error
    end
  end

  @spec name_for(rpc_module()) :: {:ok, rpc_name()} | :error
  def name_for(mod) when is_atom(mod) do
    case Enum.find(@mappings, fn {_k, v} -> v == mod end) do
      {name, ^mod} -> {:ok, name}
      _ -> :error
    end
  end
end
