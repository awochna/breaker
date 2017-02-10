defmodule Breaker.Agent do
  @moduledoc """
  Maintains the state for a particular circuit breaker.

  This Agent holds the constantly changing state properties of the circuit
  and the information required to calculate those.
  """

  @typedoc """
  Complex map holding a circuit's state.

  Includes the current state, error_threshold, and counts.
  """
  @type t :: %{open: boolean, error_threshold: float, window_length: number, bucket_length: number, sum: %{total: number, errors: number}, window: [%{total: number, errors: number}]}

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
  @spec start_link(%{}) :: {:ok, pid}
  def start_link(options \\ %{}) do
    options = options
    |> Map.put_new(:open, false)
    |> Map.put_new(:error_threshold, 0.05)
    |> Map.put_new(:window_length, 10)
    |> Map.put_new(:bucket_length, 1000)
    |> Map.put_new(:window, [%{total: 0, errors: 0}])
    |> Map.put_new(:sum, %{total: 0, errors: 0})
    {:ok, agent} = Agent.start_link(fn -> options end)
    :timer.apply_interval(options.bucket_length, __MODULE__, :roll, [agent])
    {:ok, agent}
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
  @spec open?(pid) :: boolean
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
  @spec trip(pid) :: :ok
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
  @spec reset(pid) :: :ok
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
      iex> Breaker.Agent.count(circuit, %HTTPotion.Response{status_code: 200})
      :ok

      iex> window = [%{total: 1, errors: 0}]
      iex> {:ok, circuit} = Breaker.Agent.start_link(%{window: window})
      iex> Breaker.Agent.count(circuit, %HTTPotion.Response{status_code: 500})
      :ok

      iex> window = [%{total: 0, errors: 0}, %{total: 2, errors: 1}]
      iex> {:ok, circuit} = Breaker.Agent.start_link(%{window: window})
      iex> Breaker.Agent.count(circuit, %HTTPotion.Response{status_code: 200})
      :ok

  """
  @spec count(pid, %HTTPotion.Response{} | %HTTPotion.ErrorResponse{}) :: :ok
  def count(circuit, response) do
    cond do
      response.__struct__ == HTTPotion.ErrorResponse ->
        Agent.update(circuit, __MODULE__, :count_miss, [])
      response.status_code == 500 ->
        Agent.update(circuit, __MODULE__, :count_miss, [])
      true ->
        Agent.update(circuit, __MODULE__, :count_hit, [])
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
      iex> Breaker.Agent.recalculate(circuit)
      iex> Breaker.Agent.open?(circuit)
      true

  """
  @spec recalculate(pid) :: :ok
  def recalculate(circuit) do
    Agent.update(circuit, __MODULE__, :calculate_status, [])
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
  @spec roll(pid) :: :ok
  def roll(circuit) do
    Agent.update(circuit, __MODULE__, :roll_window, [])
  end

  @doc """
  Count a miss (error) in the current window and the sum of the passed Map.

  ## Examples: ##

      iex> circuit = %{window: [%{total: 0, errors: 0}], sum: %{total: 0, errors: 0}}
      iex> Breaker.Agent.count_miss(circuit)
      %{window: [%{total: 1, errors: 1}], sum: %{total: 1, errors: 1}}

  """
  @spec count_miss(Breaker.Agent.t) :: Breaker.Agent.t
  def count_miss(circuit) do
    circuit
    |> add_to_current_window(:error)
    |> add_to_sum(:error)
  end

  @doc """
  Count a hit (sucessful request) in the current window and sums of the passed Map.

  ## Examples: ##

      iex> circuit = %{window: [%{total: 0, errors: 0}], sum: %{total: 0, errors: 0}}
      iex> Breaker.Agent.count_hit(circuit)
      %{window: [%{total: 1, errors: 0}], sum: %{total: 1, errors: 0}}

  """
  @spec count_hit(Breaker.Agent.t) :: Breaker.Agent.t
  def count_hit(circuit) do
    circuit
    |> add_to_current_window(:total)
    |> add_to_sum(:total)
  end

  @doc """
  Roll the calculation window for the given Breaker.Agent.t.

  This creates a new current bucket, pushing the existing ones down the line,
  potentially removes the oldest one (if `window_length` has been reached), and
  recalculates the status of the breaker.
  """
  @spec roll_window(Breaker.Agent.t) :: Breaker.Agent.t
  def roll_window(state) do
    state
    |> shift_window()
    |> trim_window()
    |> calculate_status()
  end

  @doc """
  Recalculates if the given Breaker.Agent state should be open or closed.

  Checks the total number of requests and errors in the rolling window and
  trips the circuit if it's higher than `error_threshold`.
  """
  @spec calculate_status(Breaker.Agent.t) :: Breaker.Agent.t
  def calculate_status(state) do
    cond do
      state.sum.total == 0 ->
        Map.put(state, :open, false)
      true ->
        error_rate = state.sum.errors / state.sum.total
        Map.put(state, :open, error_rate > state.error_threshold)
    end
  end

  @spec shift_window(Breaker.Agent.t) :: Breaker.Agent.t
  defp shift_window(state) do
    Map.update!(state, :window, &([%{total: 0, errors: 0} | &1]))
  end

  @spec trim_window(Breaker.Agent.t) :: Breaker.Agent.t
  defp trim_window(state) do
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
  end

  @spec add_to_current_window(Breaker.Agent.t, atom) :: Breaker.Agent.t
  defp add_to_current_window(circuit, :total) do
    Map.update!(circuit, :window, fn([current | rest]) ->
      [Map.update!(current, :total, &(&1 + 1)) | rest]
    end)
  end
  defp add_to_current_window(circuit, :error) do
    Map.update!(circuit, :window, fn([current | rest]) ->
      current = current
      |> Map.update!(:total, &(&1 + 1))
      |> Map.update!(:errors, &(&1 + 1))
      [current | rest]
    end)
  end

  @spec add_to_sum(Breaker.Agent.t, atom) :: Breaker.Agent.t
  defp add_to_sum(circuit, :total) do
    Map.update!(circuit, :sum, fn(sum) ->
      Map.update!(sum, :total, &(&1 + 1))
    end)
  end
  defp add_to_sum(circuit, :error) do
    Map.update!(circuit, :sum, fn(sum) ->
      sum
      |> Map.update!(:total, &(&1 + 1))
      |> Map.update!(:errors, &(&1 + 1))
    end)
  end
end
