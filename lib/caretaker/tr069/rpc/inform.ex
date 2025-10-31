defmodule Caretaker.TR069.RPC.Inform do
  @moduledoc """
  TR-069 Inform RPC.
  """

  @enforce_keys [:device_id, :events, :max_envelopes, :current_time, :retry_count]
  defstruct [:device_id, :events, :max_envelopes, :current_time, :retry_count, parameter_list: []]

  @type device_id :: %{
          manufacturer: String.t(),
          oui: String.t(),
          product_class: String.t(),
          serial_number: String.t()
        }

  @type t :: %__MODULE__{
          device_id: device_id(),
          events: [String.t()],
          max_envelopes: pos_integer(),
          current_time: NaiveDateTime.t() | DateTime.t() | String.t(),
          retry_count: non_neg_integer(),
          parameter_list: list()
        }

  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      device_id: Keyword.fetch!(opts, :device_id),
      events: Keyword.get(opts, :events, []),
      max_envelopes: Keyword.get(opts, :max_envelopes, 1),
      current_time: Keyword.get(opts, :current_time, DateTime.utc_now()),
      retry_count: Keyword.get(opts, :retry_count, 0),
      parameter_list: Keyword.get(opts, :parameter_list, [])
    }
  end

  @doc "Encode to SOAP body structure. Full envelope should be built in Caretaker.CWMP.SOAP."
  @spec encode(t()) :: {:ok, iodata()} | {:error, term()}
  def encode(_inform) do
    # TODO: Use Lather to build body node
    {:error, :not_implemented}
  end

  @doc "Decode from SOAP xml to struct"
  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(_xml) do
    # TODO: Use Lather to parse Inform
    {:error, :not_implemented}
  end
end
