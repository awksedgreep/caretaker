defmodule Caretaker.CWMP.SOAP do
  @moduledoc """
  Helpers for CWMP SOAP envelopes and headers using Lather.

  This module will provide convenience functions to build and parse CWMP
  envelopes. Where not yet implemented, functions return {:error, :not_implemented}.
  """

  @type cwmp_id :: String.t()
  @type header_opts :: %{
          optional(:id) => cwmp_id,
          optional(:hold_requests) => boolean(),
          optional(:no_more_requests) => boolean(),
          optional(:session_timeout) => non_neg_integer()
        }

  @doc "Encode a CWMP SOAP envelope from a body map or struct and header options"
  @spec encode_envelope(map() | struct(), header_opts()) :: {:ok, iodata()} | {:error, term()}
  def encode_envelope(_body, _headers \\ %{}) do
    # TODO: Build SOAP via Lather builder functions
    {:error, :not_implemented}
  end

  @doc "Decode a CWMP SOAP envelope xml into header and body maps"
  @spec decode_envelope(binary()) :: {:ok, %{header: map(), body: map()}} | {:error, term()}
  def decode_envelope(_xml) do
    # TODO: Parse SOAP via Lather
    {:error, :not_implemented}
  end

  @doc "CWMP SOAP content type"
  @spec content_type() :: String.t()
  def content_type, do: "text/xml; charset=utf-8"
end
