defmodule Breaker.Agent do
  @moduledoc """
  Maintains the state for a particular circuit breaker.

  This Agent holds the constantly changing state properties of the circuit
  and the information required to calculate those.
  """

  @doc """
  Start a new circuit breaker state holder.

  The internal state looks like the following:

  ```
  %{
    open: false,
    error_threshold: 0.05,
    window_length: 10,
    bucket_length: 1000,
    sum: %{
      total: 0,
      errors: 0
    },
    window: [
      %{
        total: 0,
        errors: 0
      },
      ...
    ]
  }
  ```

  ## Parameters: ##

  * `options`: An options map. It should contain the following keys:
    * `open`: A boolean indicating if the circuit is open or not.
    * `error_threshold`: The percent of requests allowed to fail, as a float.
    * `window_length`: The number of buckets in the health calculation window.
    * `bucket_length`: The number of milliseconds for each bucket.

  ## Examples: ##

      iex> {:ok, circuit} = Breaker.Agent.start_link(%{misses: 0})
      iex> is_pid(circuit)
      true

  """
  def start_link(options \\ %{}) do
    options = options
    |> Map.put_new(:open, false)
    |> Map.put_new(:error_threshold, 0.05)
    |> Map.put_new(:window_length, 10)
    |> Map.put_new(:bucket_length, 1000)
    |> Map.put_new(:window, [%{total: 0, errors: 0}])
    |> Map.put_new(:sum, %{total: 0, errors: 0})
    Agent.start_link(fn -> options end)
  end

  @doc """
  Check if the circuit is open (broken).

  ## Parameters: ##

  * `circuit`: The Agent containing the circuit's state.

  ## Examples: ##

      iex> {:ok, circuit} = Breaker.Agent.start_link(%{open: false})
      iex> Breaker.Agent.open?(circuit)
      false

      iex> {:ok, circuit} = Breaker.Agent.start_link(%{open: true})
      iex> Breaker.Agent.open?(circuit)
      true

  """
  def open?(circuit) do
    Agent.get(circuit, &Map.get(&1, :open))
  end

  @doc """
  Manually trip the circuit, setting it to an "open" status.

  ## Paramaters: ##

  * `circuit`: The Agent containing the circuit's state.

  ## Examples: ##

      iex> {:ok, circuit} = Breaker.Agent.start_link(%{open: false})
      iex> Breaker.Agent.trip(circuit)
      iex> Breaker.Agent.open?(circuit)
      true

      iex> {:ok, circuit} = Breaker.Agent.start_link(%{open: true})
      iex> Breaker.Agent.trip(circuit)
      iex> Breaker.Agent.open?(circuit)
      true

  """
  def trip(circuit) do
    Agent.update(circuit, &Map.put(&1, :open, true))
  end

  @doc """
  Reset an open breaker.

  ## Parameters: ##

  * `circuit`: The Agent containing the circuit's state.

  ## Examples: ##

      iex> {:ok, circuit} = Breaker.Agent.start_link(%{open: true})
      iex> Breaker.Agent.reset(circuit)
      iex> Breaker.Agent.open?(circuit)
      false

      iex> {:ok, circuit} = Breaker.Agent.start_link(%{open: false})
      iex> Breaker.Agent.reset(circuit)
      iex> Breaker.Agent.open?(circuit)
      false

  """
  def reset(circuit) do
    Agent.update(circuit, &Map.put(&1, :open, false))
  end

  @doc """
  Count a response in the current bucket of the window.

  ## Parameters: ##

  * `circuit`: The Agent containing the circuit's state.
  * `response`: The received %HTTPotion.Response{}

  ## Examples: ##

      iex> window = [%{total: 0, errors: 0}]
      iex> {:ok, circuit} = Breaker.Agent.start_link(%{window: window})
      iex> Breaker.Agent.count(circuit, %{status_code: 200})
      :ok

      iex> window = [%{total: 1, errors: 0}]
      iex> {:ok, circuit} = Breaker.Agent.start_link(%{window: window})
      iex> Breaker.Agent.count(circuit, %{status_code: 500})
      :ok

      iex> window = [%{total: 0, errors: 0}, %{total: 2, errors: 1}]
      iex> {:ok, circuit} = Breaker.Agent.start_link(%{window: window})
      iex> Breaker.Agent.count(circuit, %{status_code: 200})
      :ok

  """
  def count(circuit, response) do
    case response.status_code do
      200 ->
        Agent.update(circuit, fn(circuit) ->
          circuit
          |> Map.update!(:window, fn([current | rest]) ->
            current = Map.update!(current, :total, &(&1 + 1))
            [current | rest]
          end)
          |> Map.update!(:sum, fn(sum) ->
            Map.update!(sum, :total, &(&1 + 1))
          end)
        end)
      500 ->
        Agent.update(circuit, fn(circuit) ->
          circuit
          |> Map.update!(:window, fn([current | rest]) ->
            current = current
            |> Map.update!(:total, &(&1 + 1))
            |> Map.update!(:errors, &(&1 + 1))
            [current | rest]
          end)
          |> Map.update!(:sum, fn(sum) ->
            sum
            |> Map.update!(:total, &(&1 + 1))
            |> Map.update!(:errors, &(&1 + 1))
          end)
        end)
    end
  end

  @doc """
  Calculate if the circuit should be open or closed.

  ## Parameters: ##

  * `circuit`: The Agent containing the circuit's state.
  
  ## Examples: ##

      iex> sum = %{total: 10, errors: 10}
      iex> options = %{error_threshold: 0.05, sum: sum, open: false}
      iex> {:ok, circuit} = Breaker.Agent.start_link(options)
      iex> Breaker.Agent.open?(circuit)
      false
      iex> Breaker.Agent.calculate_status(circuit)
      iex> Breaker.Agent.open?(circuit)
      true

  """
  def calculate_status(circuit) do
    state = Agent.get(circuit, &(&1))
    error_rate = state.sum.errors / state.sum.total
    Agent.update(circuit, &Map.update!(&1, :open, fn(_) ->
      error_rate > state.error_threshold
    end))
  end

  @doc """
  Roll the window, creating a new bucket and possible pushing out an old one,
  updating the sum values as necessary.

  ## Parameters: ##

  * `circuit`: The Agent containing the circuit's state.

  ## Examples: ##

      iex> options = %{window: [%{total: 1, errors: 0}]}
      iex> {:ok, circuit} = Breaker.Agent.start_link(options)
      iex> Breaker.Agent.roll(circuit)
      :ok

  """
  def roll(circuit) do
    Agent.update(circuit, fn(state) ->
      state = Map.update!(state, :window, &([%{total: 0, errors: 0} | &1]))
      cond do
        length(state.window) > state.window_length ->
          {removed, window} = List.pop_at(state.window, -1)
          state
          |> Map.put(:window, window)
          |> Map.update!(:sum, fn(sum) ->
            sum
            |> Map.update!(:total, &(&1 - removed.total))
            |> Map.update!(:errors, &(&1 - removed.errors))
          end)
        true ->
          state
      end
    end)
  end
end
