defmodule Breaker do
  @moduledoc """
  A circuit-breaker wrapped around HTTPotion to make requests to external
  resources and help your application gracefully fail.

  Also defines the `%Breaker{}` struct which represents a request circuit
  breaker, used with this module.
  """

  @enforce_keys [:url]
  defstruct url: nil, headers: [], timeout: 3000, status: nil

  @doc """
  Create a new circuit-breaker with the given options map.

  Available options are:

  * `url`: The base url to use for the breaker. This is ideally a single
    external resource, complete with protocal, domain name, port, and an
    optional subpath. Required.
  * `headers`: A keyword list of headers, passed to HTTPotion.
  * `timeout`: How long to wait until considering the request timed out.
    Passed to HTTPotion.
  * `open`: Boolean defining if the circuit is broken. Defaults to false.
  * `error_threshold`: The percent of requests allowed to fail, as a float.
    Defaults to 0.05 (5%)
  * `window_length`: The number of buckets in the health calculation window.
    Defaults to 10.
  * `bucket_length`: The number of milliseconds for each bucket. Defaults to
    1000, meaning health is caluculated over the past 10 seconds using the
    defaults.

  Examples:

      iex> options = %{url: "http://localhost:8080/"}
      iex> circuit = Breaker.new(options)
      iex> is_map(circuit)
      true
      iex> circuit.__struct__
      Breaker

  """
  def new(options) do
    {:ok, agent} = options
    |> Map.take([:open, :error_threshold])
    |> Breaker.Agent.start_link()
    %Breaker{url: options.url}
    |> Map.merge(Map.take(options, [:timeout, :headers]))
    |> Map.put(:status, agent)
  end

  @doc """
  Trip the circuit.

  This sets the "open" status to true and has no effect if the "open" status
  is already true.

  This has the effect of cutting off communications using the circuit and
  starts the restoration process to test if the external source is healthy.

  Examples:

      iex> circuit = Breaker.new(%{url: "http://localhost:8080/"})
      iex> response = Breaker.get(circuit, "/get")
      iex> response.status_code
      200
      iex> Breaker.trip(circuit)
      iex> response = Breaker.get(circuit, "/get")
      iex> response.status_code
      500

  """
  def trip(circuit) do
    Breaker.Agent.trip(circuit.status)
  end

  @doc """
  Reset the circuit breaker.

  Examples:

      iex> options = %{url: "http://localhost:8080/", open: true}
      iex> circuit = Breaker.new(options)
      iex> Breaker.open?(circuit)
      true
      iex> Breaker.reset(circuit)
      iex> Breaker.open?(circuit)
      false

  """
  def reset(circuit) do
    Breaker.Agent.reset(circuit.status)
  end

  @doc """
  Ask if the circuit is open or not.

  Examples:

      iex> options = %{url: "http://localhost:8080/"}
      iex> circuit = Breaker.new(options)
      iex> Breaker.open?(circuit)
      false

  """
  def open?(circuit) do
    Breaker.Agent.open?(circuit.status)
  end

  @doc ~S"""
  Send a GET request to the path on the address.

  Examples:

      iex> options = %{url: "http://localhost:8080/"}
      iex> circuit = Breaker.new(options)
      iex> response = Breaker.get(circuit, "/ip")
      iex> response.body
      "{\n  \"origin\": \"127.0.0.1\"\n}"

  """
  def get(circuit, path) do
    %{status: agent, url: url} = circuit
    cond do
      Breaker.Agent.open?(agent) ->
        # This should respond in a HTTPotion-transparent way.
        %{status_code: 500}
      true ->
        request_address = URI.merge(url, path)
        response = HTTPotion.get(request_address)
        Breaker.Agent.count(agent, response)
        Breaker.Agent.calculate_status(agent)
        response
    end
  end
end
