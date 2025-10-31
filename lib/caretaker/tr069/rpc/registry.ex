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
    "GetParameterValues" => Caretaker.TR069.RPC.GetParameterValues,
    "SetParameterValues" => Caretaker.TR069.RPC.SetParameterValues,
    "AddObject" => Caretaker.TR069.RPC.AddObject,
    "DeleteObject" => Caretaker.TR069.RPC.DeleteObject,
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
