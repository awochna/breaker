defmodule Breaker.OpenCircuitError do
  @moduledoc """
  Defines the struct returned when a request is made, but the circuit is open.
  """

  defstruct message: "circuit is open"
end
