defmodule Breaker do
  @moduledoc """
  A circuit-breaker wrapped around HTTPotion to make requests to external
  resources and help your application gracefully fail.
  """

  use GenServer

  #####
  # External Interface

  @doc """
  Create a new circuit-breaker with the given options map.

  Examples:

      iex> {:ok, circuit} = Breaker.start_link(%{addr: "http://localhost:8080/"})
      iex> is_pid(circuit)
      true

  """
  def start_link(options) do
    options = options
              |> Map.put_new(:open, true)
    GenServer.start_link(__MODULE__, options)
  end

  @doc """
  Trip the circuit.

  This sets the "open" status to false and has no effect if the "open" status
  is already false.

  This has the effect of cutting off communications using the circuit and
  starts the restoration process to test if the external source is healthy.

  Examples:

      iex> {:ok, circuit} = Breaker.start_link(%{addr: "http://localhost:8080/"})
      iex> response = Breaker.get(circuit, "/get")
      iex> response.status_code
      200
      iex> Breaker.trip(circuit)
      iex> response = Breaker.get(circuit, "/get")
      iex> response.status_code
      500

  """
  def trip(circuit) do
    GenServer.cast(circuit, :trip)
  end

  @doc """
  Reset the circuit breaker.

  Examples:

      iex> {:ok, circuit} = Breaker.start_link(%{addr: "http://localhost:8080/", open: false})
      iex> Breaker.open?(circuit)
      false
      iex> Breaker.reset(circuit)
      iex> Breaker.open?(circuit)
      true

  """
  def reset(circuit) do
    GenServer.cast(circuit, :reset)
  end

  @doc """
  Ask if the circuit is open or not.

  Examples:

      iex> {:ok, circuit} = Breaker.start_link(%{addr: "http://localhost:8080/"})
      iex> Breaker.open?(circuit)
      true

  """
  def open?(circuit) do
    GenServer.call(circuit, :status)
  end

  @doc ~S"""
  Send a GET request to the path on the address.

  Examples:

      iex> {:ok, circuit} = Breaker.start_link(%{addr: "http://localhost:8080/"})
      iex> response = Breaker.get(circuit, "/ip")
      iex> response.body
      "{\n  \"origin\": \"127.0.0.1\"\n}"

  """
  def get(circuit, path) do
    GenServer.call(circuit, {:get, path})
  end

  #####
  # Internal interface

  def handle_call(:status, _from, circuit) do
    {:reply, circuit.open, circuit}
  end
  def handle_call({:get, path}, _from, circuit) do
    cond do
      circuit.open ->
        request_address = URI.merge(circuit.addr, path)
        response = HTTPotion.get(request_address)
        {:reply, response, circuit}
      true ->
        {:reply, %{status_code: 500}, circuit}
    end
  end

  def handle_cast(:trip, circuit) do
    circuit = Map.put(circuit, :open, false)
    {:noreply, circuit}
  end
  def handle_cast(:reset, circuit) do
    circuit = Map.put(circuit, :open, true)
    {:noreply, circuit}
  end
end
