defmodule Caretaker.TR069.Diagnostics.TraceRoute do
  @moduledoc """
  Helpers to build SetParameterValues for TR-181 TraceRoute diagnostics.
  Writes under Device.IP.Diagnostics.TraceRouteDiagnostics.*
  """

  alias Caretaker.TR069.RPC.SetParameterValues

  @enforce_keys [:host]
  defstruct host: nil, timeout: 5000, data_block_size: 56, max_hop_count: 30, dscp: nil, interface: nil, parameter_key: ""

  @type t :: %__MODULE__{
          host: String.t(),
          timeout: pos_integer(),
          data_block_size: pos_integer(),
          max_hop_count: pos_integer(),
          dscp: integer() | nil,
          interface: String.t() | nil,
          parameter_key: String.t()
        }

  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      host: Keyword.fetch!(opts, :host),
      timeout: Keyword.get(opts, :timeout, 5000),
      data_block_size: Keyword.get(opts, :data_block_size, 56),
      max_hop_count: Keyword.get(opts, :max_hop_count, 30),
      dscp: Keyword.get(opts, :dscp),
      interface: Keyword.get(opts, :interface),
      parameter_key: Keyword.get(opts, :parameter_key, "")
    }
  end

  @doc "Build SetParameterValues body to start TraceRoute diagnostics"
  @spec build_spv(t()) :: {:ok, iodata()}
  def build_spv(%__MODULE__{} = cfg) do
    base = "Device.IP.Diagnostics.TraceRouteDiagnostics."

    params =
      [
        %{name: base <> "Host", value: cfg.host, type: "xsd:string"},
        %{name: base <> "Timeout", value: Integer.to_string(cfg.timeout), type: "xsd:int"},
        %{name: base <> "DataBlockSize", value: Integer.to_string(cfg.data_block_size), type: "xsd:int"},
        %{name: base <> "MaxHopCount", value: Integer.to_string(cfg.max_hop_count), type: "xsd:int"},
        %{name: base <> "DiagnosticsState", value: "Requested", type: "xsd:string"}
      ]
      |> maybe_add(cfg.interface, base <> "Interface", "xsd:string")
      |> maybe_add(cfg.dscp, base <> "DSCP", "xsd:int")

    SetParameterValues.new(params, parameter_key: cfg.parameter_key)
    |> SetParameterValues.encode()
  end

  defp maybe_add(list, nil, _name, _type), do: list
  defp maybe_add(list, val, name, type), do: list ++ [%{name: name, value: to_string(val), type: type}]
end