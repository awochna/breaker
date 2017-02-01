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

  Available options are:

  * `addr`: The base address to use for the breaker. This is ideally a single
    external resource, complete with protocal, domain name, port, and an
    optional subpath. Required.
  * `open`: Boolean defining if the circuit is broken. Defaults to false.
  * `tolerance`: The number of successive failures required to trip the circuit.
    Default: 2
  * `recovery`: Settings for the circuit recovery, a map of the following:
    * `type`: Currently, only `:timed` is implemented. Default.
    * `wait`: Used in the `timed` option, the number of milliseconds before
      attempting another request. Default: 30000

  Examples:

      iex> {:ok, circuit} = Breaker.start_link(%{addr: "http://localhost:8080/"})
      iex> is_pid(circuit)
      true

  """
  def start_link(options) do
    options = options
              |> Map.put_new(:open, false)
              |> Map.put_new(:tolerance, 2)
              |> Map.put_new(:recovery, %{type: :timed, wait: 30000})
              |> Map.put_new(:misses, 0)
              |> Map.put_new(:hits, 0)
    GenServer.start_link(__MODULE__, options)
  end

  @doc """
  Trip the circuit.

  This sets the "open" status to true and has no effect if the "open" status
  is already true.

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

      iex> {:ok, circuit} = Breaker.start_link(%{addr: "http://localhost:8080/", open: true})
      iex> Breaker.open?(circuit)
      true
      iex> Breaker.reset(circuit)
      iex> Breaker.open?(circuit)
      false

  """
  def reset(circuit) do
    GenServer.cast(circuit, :reset)
  end

  @doc """
  Ask if the circuit is open or not.

  Examples:

      iex> {:ok, circuit} = Breaker.start_link(%{addr: "http://localhost:8080/"})
      iex> Breaker.open?(circuit)
      false

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
  # GenServer interface

  def handle_call(:status, _from, circuit) do
    {:reply, circuit.open, circuit}
  end
  def handle_call({:get, path}, _from, circuit) do
    cond do
      circuit.open ->
        {:reply, %{status_code: 500}, circuit}
      true ->
        request_address = URI.merge(circuit.addr, path)
        response = HTTPotion.get(request_address)
        circuit = circuit
        |> Breaker.record(response)
        |> Breaker.calculate_status
        {:reply, response, circuit}
    end
  end

  def handle_cast(:trip, circuit) do
    circuit = Map.put(circuit, :open, true)
    {:noreply, circuit}
  end
  def handle_cast(:reset, circuit) do
    circuit = Map.put(circuit, :open, false)
    {:noreply, circuit}
  end

  #####
  # Private interface

  @doc """
  Mark a response as a hit or a miss.

  A miss is a 500 currently, but this should also include a timeout error.

  The `circuit` passed is the state Map, not the PID.

  Returns new circuit state.

  The current implementation is extremely naive, we reset our count of `misses`
  when we get a confirmed hit.

  ## Parameters: ##

  * `circuit`: Map of circuit state.
  * `response`: Response from external request.

  ## Examples: ##

      iex> circuit = %{misses: 0}
      iex> Breaker.record(circuit, %{status_code: 500})
      %{misses: 1}

      iex> circuit = %{misses: 1}
      iex> Breaker.record(circuit, %{status_code: 200})
      %{misses: 0}

  """
  def record(circuit, %{status_code: 500}) do
    Map.update!(circuit, :misses, &(&1 + 1))
  end
  def record(circuit, _response) do
    Map.put(circuit, :misses, 0)
  end

  @doc """
  Calculate if the breaker should be open or closed.

  ## Parameters: ##

  * `circuit`: The circuit state map.

  ## Examples: ##

      iex> circuit = %{misses: 0, tolerance: 1, open: true}
      iex> Breaker.calculate_status(circuit)
      %{misses: 0, tolerance: 1, open: false}

      iex> circuit = %{misses: 2, tolerance: 1, open: false}
      iex> Breaker.calculate_status(circuit)
      %{misses: 2, tolerance: 1, open: true}

      iex> circuit = %{misses: 1, tolerance: 1, open: false}
      iex> Breaker.calculate_status(circuit)
      %{misses: 1, tolerance: 1, open: false}

  """
  def calculate_status(circuit) do
    cond do
      circuit.misses > circuit.tolerance ->
        Map.put(circuit, :open, true)
      true ->
        Map.put(circuit, :open, false)
    end
  end
end
