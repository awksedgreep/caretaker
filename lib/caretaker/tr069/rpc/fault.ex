defmodule Caretaker.TR069.RPC.Fault do
  @moduledoc """
  TR-069 Fault representation.
  """

  defstruct [:code, :string, detail: %{}]

  @type t :: %__MODULE__{code: integer(), string: String.t(), detail: map()}
end
