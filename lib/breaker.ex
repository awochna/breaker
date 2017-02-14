defmodule Breaker do
  @moduledoc """
  A circuit-breaker wrapped around `HTTPotion` to make requests to external
  resources and help your application gracefully fail.

  Also defines the `%Breaker{}` struct which represents a request circuit
  breaker, used with this module.

  Defines a function for each HTTP method (ie `Breaker.get()`) that returns a
  Task that will execute the HTTP request (using `HTTPotion`) and record the
  response in the circuit breaker.
  """

  @typedoc """
  A %Breaker{} struct containing information for the circuit.

  It holds:

  * `url`: The base url associated with the breaker.
  * `headers`: Additional headers to use when making requests.
  * `timeout`: The time to wait (in ms) before giving up on a request.
  * `status`: The process containing the circuit breaker's counts and state.
  """
  @type t :: %Breaker{
    url: String.t,
    headers: [...],
    timeout: number,
    status: pid
  }

  @enforce_keys [:url]
  defstruct url: nil, headers: [], timeout: 3000, status: nil

  @doc """
  Create a new circuit-breaker with the given options map.

  Available options are:

  * `url`: The base url to use for the breaker. This is ideally a single
    external resource, complete with protocal, domain name, port, and an
    optional subpath. Required.
  * `headers`: A keyword list of headers, passed to `HTTPotion`.
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
  @spec new(%{url: String.t}) :: Breaker.t
  def new(options) do
    {:ok, agent} = options
    |> Map.take([:open, :error_threshold])
    |> Breaker.Agent.start_link()
    %Breaker{url: Map.get(options, :url)}
    |> Map.merge(Map.take(options, [:timeout, :headers]))
    |> Map.put(:status, agent)
  end

  @doc """
  Checks if the given response is either a `%Breaker.OpenCircuitError{}`, a
  timeout, or has a 500 status code.

  ## Parameters: ##

  * `response`: The response recieved from one of the HTTP method calls.

  ## Examples: ##

      iex> Breaker.error?(%Breaker.OpenCircuitError{})
      true

      iex> Breaker.error?(%HTTPotion.ErrorResponse{})
      true

      iex> Breaker.error?(%HTTPotion.Response{status_code: 500})
      true

      iex> Breaker.error?(%HTTPotion.Response{status_code: 200})
      false

  """
  @spec error?(%Breaker.OpenCircuitError{} | %HTTPotion.ErrorResponse{} |
  %HTTPotion.Response{}) :: boolean
  def error?(response) do
    response.__struct__ == Breaker.OpenCircuitError ||
    response.__struct__ == HTTPotion.ErrorResponse ||
    response.status_code == 500
  end

  @doc """
  Trip the circuit.

  This sets the "open" status to true and has no effect if the "open" status
  is already true.

  This has the effect of cutting off communications using the circuit and
  starts the restoration process to test if the external source is healthy.

  Examples:

      iex> circuit = Breaker.new(%{url: "http://httpbin.org/"})
      iex> response = Breaker.get(circuit, "/get") |> Task.await
      iex> response.status_code
      200
      iex> Breaker.trip(circuit)
      iex> Breaker.get(circuit, "/get") |> Task.await
      %Breaker.OpenCircuitError{message: "circuit is open"}

  """
  @spec trip(Breaker.t) :: :ok
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
  @spec reset(Breaker.t) :: :ok
  def reset(circuit), do: Breaker.Agent.reset(circuit.status)

  @doc """
  Ask if the circuit is open or not.

  Examples:

      iex> options = %{url: "http://httpbin.org/"}
      iex> circuit = Breaker.new(options)
      iex> Breaker.open?(circuit)
      false

  """
  @spec open?(Breaker.t) :: boolean
  def open?(circuit), do: Breaker.Agent.open?(circuit.status)

  #####
  # Request calls

  @doc """
  Make an async GET request to the specified path using the given breaker.

  Task returning alias for `make_request(circuit, path, :get, options)`.

  ## Examples: ##

      iex> breaker = Breaker.new(%{url: "http://httpbin.org/"})
      iex> request = Breaker.get(breaker, "/get")
      iex> response = Task.await(request)
      iex> response.status_code
      200

  """
  @spec get(Breaker.t, String.t, []) :: Task.t
  def get(circuit, path, options \\ []) do
    Task.async(__MODULE__, :make_request, [circuit, path, :get, options])
  end

  @doc """
  Make an async PUT request to the specified path using the given breaker.

  Task returning alias for `make_request(circuit, path, :put, options)`.
  """
  @spec put(Breaker.t, String.t, []) :: Task.t
  def put(circuit, path, options \\ []) do
    Task.async(__MODULE__, :make_request, [circuit, path, :put, options])
  end

  @doc """
  Make an async HEAD request to the specified path using the given breaker.

  Task returning alias for `make_request(circuit, path, :head, options)`.
  """
  @spec head(Breaker.t, String.t, []) :: Task.t
  def head(circuit, path, options \\ []) do
    Task.async(__MODULE__, :make_request, [circuit, path, :head, options])
  end

  @doc """
  Make an async POST request to the specified path using the given breaker.

  Task returning alias for `make_request(circuit, path, :post, options)`.
  """
  @spec post(Breaker.t, String.t, []) :: Task.t
  def post(circuit, path, options \\ []) do
    Task.async(__MODULE__, :make_request, [circuit, path, :post, options])
  end

  @doc """
  Make an async PATCH request to the specified path using the given breaker.

  Task returning alias for `make_request(circuit, path, :patch, options)`.
  """
  @spec patch(Breaker.t, String.t, []) :: Task.t
  def patch(circuit, path, options \\ []) do
    Task.async(__MODULE__, :make_request, [circuit, path, :patch, options])
  end

  @doc """
  Make an async DELETE request to the specified path using the given breaker.

  Task returning alias for `make_request(circuit, path, :delete, options)`.
  """
  @spec delete(Breaker.t, String.t, []) :: Task.t
  def delete(circuit, path, options \\ []) do
    Task.async(__MODULE__, :make_request, [circuit, path, :delete, options])
  end

  @doc """
  Make an async OPTIONS request to the specified path using the given breaker.

  Task returning alias for `make_request(circuit, path, :options, options)`.
  """
  @spec options(Breaker.t, String.t, []) :: Task.t
  def options(circuit, path, options \\ []) do
    Task.async(__MODULE__, :make_request, [circuit, path, :options, options])
  end

  @doc """
  Make an HTTP(S) request using the specified breaker, using the given method.

  This function isn't probably one you would want to use on your own and
  instead, use the method-specific functions (`Breaker.get()`). They return
  Tasks and are async, while this is sync.

  ## Parameters: ##

  * `circuit`: The circuit to make the request with.
  * `path`: The request path, this is add to the circuit's `url`.
  * `method`: An atom specifying the HTTP method, used by HTTPotion.
  * `options`: Extra options to pass to HTTPotion. The circuit's `timeout` and
    `headers` are also added to this.

  ## Examples: ##

      iex> breaker = Breaker.new(%{url: "http://httpbin.org/"})
      iex> response = Breaker.make_request(breaker, "/get", :get)
      iex> response.status_code
      200

  """
  @spec make_request(Breaker.t, String.t, atom, []) :: %HTTPotion.Response{} |
  %HTTPotion.ErrorResponse{} | %Breaker.OpenCircuitError{}
  def make_request(circuit, path, method, options \\ []) do
    %{status: agent, url: url} = circuit
    if Breaker.Agent.open?(agent) do
      %Breaker.OpenCircuitError{}
    else
      headers = options
      |> Keyword.get(:headers, [])
      |> Keyword.merge(circuit.headers, fn(_key, v1, _v2) -> v1 end)
      options = options
      |> Keyword.put_new(:timeout, circuit.timeout)
      |> Keyword.put(:headers, headers)
      request_address = URI.merge(url, path)
      response = HTTPotion.request(method, request_address, options)
      Breaker.Agent.count(agent, response)
      Breaker.Agent.recalculate(agent)
      response
    end
  end
end
