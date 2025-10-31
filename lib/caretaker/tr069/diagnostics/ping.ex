defmodule Caretaker.TR069.Diagnostics.Ping do
  @moduledoc """
  Helpers to build SetParameterValues for TR-181 Ping diagnostics.
  Writes under Device.IP.Diagnostics.PingDiagnostics.* and requests start via DiagnosticsState = "Requested".
  """

  alias Caretaker.TR069.RPC.SetParameterValues

  @enforce_keys [:host]
  defstruct host: nil, repetitions: 4, timeout: 1000, data_block_size: 56, interface: nil, dscp: nil, parameter_key: ""

  @type t :: %__MODULE__{
          host: String.t(),
          repetitions: pos_integer(),
          timeout: pos_integer(),
          data_block_size: pos_integer(),
          interface: String.t() | nil,
          dscp: integer() | nil,
          parameter_key: String.t()
        }

  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      host: Keyword.fetch!(opts, :host),
      repetitions: Keyword.get(opts, :repetitions, 4),
      timeout: Keyword.get(opts, :timeout, 1000),
      data_block_size: Keyword.get(opts, :data_block_size, 56),
      interface: Keyword.get(opts, :interface),
      dscp: Keyword.get(opts, :dscp),
      parameter_key: Keyword.get(opts, :parameter_key, "")
    }
  end

  @doc "Build SetParameterValues body to start Ping diagnostics"
  @spec build_spv(t()) :: {:ok, iodata()}
  def build_spv(%__MODULE__{} = cfg) do
    base = "Device.IP.Diagnostics.PingDiagnostics."

    params =
      [
        %{name: base <> "Host", value: cfg.host, type: "xsd:string"},
        %{name: base <> "NumberOfRepetitions", value: Integer.to_string(cfg.repetitions), type: "xsd:int"},
        %{name: base <> "Timeout", value: Integer.to_string(cfg.timeout), type: "xsd:int"},
        %{name: base <> "DataBlockSize", value: Integer.to_string(cfg.data_block_size), type: "xsd:int"},
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