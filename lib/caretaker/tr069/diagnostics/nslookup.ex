defmodule Caretaker.TR069.Diagnostics.NSLookup do
  @moduledoc """
  Helpers to build SetParameterValues for TR-181 NSLookup diagnostics.
  Writes under Device.DNS.Diagnostics.NSLookupDiagnostics.*
  """

  alias Caretaker.TR069.RPC.SetParameterValues

  @enforce_keys [:host_name]
  defstruct host_name: nil, dns_server: nil, timeout: 2000, number_of_repetitions: 1, interface: nil, parameter_key: ""

  @type t :: %__MODULE__{
          host_name: String.t(),
          dns_server: String.t() | nil,
          timeout: pos_integer(),
          number_of_repetitions: pos_integer(),
          interface: String.t() | nil,
          parameter_key: String.t()
        }

  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      host_name: Keyword.fetch!(opts, :host_name),
      dns_server: Keyword.get(opts, :dns_server),
      timeout: Keyword.get(opts, :timeout, 2000),
      number_of_repetitions: Keyword.get(opts, :number_of_repetitions, 1),
      interface: Keyword.get(opts, :interface),
      parameter_key: Keyword.get(opts, :parameter_key, "")
    }
  end

  @doc "Build SetParameterValues body to start NSLookup diagnostics"
  @spec build_spv(t()) :: {:ok, iodata()}
  def build_spv(%__MODULE__{} = cfg) do
    base = "Device.DNS.Diagnostics.NSLookupDiagnostics."

    params =
      [
        %{name: base <> "HostName", value: cfg.host_name, type: "xsd:string"},
        %{name: base <> "Timeout", value: Integer.to_string(cfg.timeout), type: "xsd:int"},
        %{name: base <> "NumberOfRepetitions", value: Integer.to_string(cfg.number_of_repetitions), type: "xsd:int"},
        %{name: base <> "DiagnosticsState", value: "Requested", type: "xsd:string"}
      ]
      |> maybe_add(cfg.dns_server, base <> "DNSServer", "xsd:string")
      |> maybe_add(cfg.interface, base <> "Interface", "xsd:string")

    SetParameterValues.new(params, parameter_key: cfg.parameter_key)
    |> SetParameterValues.encode()
  end

  defp maybe_add(list, nil, _name, _type), do: list
  defp maybe_add(list, val, name, type), do: list ++ [%{name: name, value: to_string(val), type: type}]
end