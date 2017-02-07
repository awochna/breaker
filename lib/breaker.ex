defmodule Breaker do
  @moduledoc """
  A circuit-breaker wrapped around HTTPotion to make requests to external
  resources and help your application gracefully fail.

  Also defines the `%Breaker{}` struct which represents a request circuit
  breaker, used with this module.
  """

  use HTTPotion.Base

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

      iex> options = %{url: "http://httpbin.org/"}
      iex> circuit = Breaker.new(options)
      iex> is_map(circuit)
      true
      iex> circuit.__struct__
      Breaker
      iex> is_pid(circuit.status)
      true

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

      iex> circuit = Breaker.new(%{url: "http://httpbin.org/"})
      iex> response = Breaker.get(circuit, "/get")
      iex> response.status_code
      200
      iex> Breaker.trip(circuit)
      iex> Breaker.get(circuit, "/get")
      %Breaker.OpenCircuitError{message: "circuit is open"}

  """
  def trip(circuit), do: Breaker.Agent.trip(circuit.status)

  @doc """
  Reset the circuit breaker.

  Examples:

      iex> options = %{url: "http://httpbin.org/", open: true}
      iex> circuit = Breaker.new(options)
      iex> Breaker.open?(circuit)
      true
      iex> Breaker.reset(circuit)
      iex> Breaker.open?(circuit)
      false

  """
  def reset(circuit), do: Breaker.Agent.reset(circuit.status)

  @doc """
  Ask if the circuit is open or not.

  Examples:

      iex> options = %{url: "http://httpbin.org/"}
      iex> circuit = Breaker.new(options)
      iex> Breaker.open?(circuit)
      false

  """
  def open?(circuit), do: Breaker.Agent.open?(circuit.status)

  @doc ~S"""
  Send a GET request to the path on the address.

  Examples:

      iex> options = %{url: "http://httpbin.org/"}
      iex> circuit = Breaker.new(options)
      iex> response = Breaker.get(circuit, "/get")
      iex> response.status_code
      200

  """
  def old_get(circuit, path) do
    %{status: agent, url: url} = circuit
    cond do
      Breaker.Agent.open?(agent) ->
        %Breaker.OpenCircuitError{}
      true ->
        request_address = URI.merge(url, path)
        response = HTTPotion.get(request_address, [timeout: circuit.timeout])
        Breaker.Agent.count(agent, response)
        Breaker.Agent.recalculate(agent)
        response
    end
  end

  #####
  # HTTPotion integration

  def get(circuit, path, options \\ []) do
    make_request(circuit, path, :get, options)
  end

  def put(circuit, path, options \\ []) do
    make_request(circuit, path, :put, options)
  end

  def head(circuit, path, options \\ []) do
    make_request(circuit, path, :head, options)
  end

  def post(circuit, path, options \\ []) do
    make_request(circuit, path, :post, options)
  end

  def patch(circuit, path, options \\ []) do
    make_request(circuit, path, :patch, options)
  end

  def delete(circuit, path, options \\ []) do
    make_request(circuit, path, :delete, options)
  end

  def options(circuit, path, options \\ []) do
    make_request(circuit, path, :options, options)
  end

  defp make_request(circuit, path, method, options \\ []) do
    %{status: agent, url: url} = circuit
    cond do
      Breaker.Agent.open?(agent) ->
        %Breaker.OpenCircuitError{}
      true ->
        headers = options
        |> Keyword.get(:headers, [])
        |> Keyword.merge(circuit.headers, fn(_key, v1, _v2) -> v1 end)
        options = options
        |> Keyword.put_new(:timeout, circuit.timeout)
        |> Keyword.put(:headers, headers)
        request_address = URI.merge(url, path)
        response = request(method, request_address, options)
        Breaker.Agent.count(agent, response)
        Breaker.Agent.recalculate(agent)
        response
    end
  end
end
