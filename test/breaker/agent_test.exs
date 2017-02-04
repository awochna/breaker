defmodule BreakerAgentTest do
  use ExUnit.Case
  doctest Breaker.Agent

  test "the state agent can be initialized on it's own" do
    {:ok, agent} = Breaker.Agent.start_link()
    assert is_pid(agent)
  end

  test "the state agent has a window to record hits and misses" do
    {:ok, agent} = Breaker.Agent.start_link()
    [current_bucket | _] = window = get_window(agent)
    assert length(window) == 1
    assert current_bucket.total == 0
    assert current_bucket.total == 0
  end

  test "the state agent can count a response in the current bucket" do
    {:ok, agent} = Breaker.Agent.start_link()
    then = get_current_bucket(agent)
    Breaker.Agent.count(agent, %{status_code: 200})
    now = get_current_bucket(agent)
    assert then.total == 0
    assert now.total == 1
  end

  test "the state agent can count an error response in the current bucket" do
    {:ok, agent} = Breaker.Agent.start_link()
    then = get_current_bucket(agent)
    Breaker.Agent.count(agent, %{status_code: 500})
    now = get_current_bucket(agent)
    assert then.total == 0
    assert then.errors == 0
    assert now.total == 1
    assert now.errors == 1
  end
    
  test "the state agent's window can be rolled, creating a new current bucket" do
    {:ok, agent} = Breaker.Agent.start_link()
    then = get_window(agent)
    Breaker.Agent.roll(agent)
    now = get_window(agent)
    assert length(then) == 1
    assert length(now) == 2
  end

  test "the state agent won't create more than window_length buckets" do
    {:ok, agent} = Breaker.Agent.start_link(%{window_length: 2})
    Breaker.Agent.roll(agent)
    then = get_window(agent)
    Breaker.Agent.roll(agent)
    now = get_window(agent)
    assert length(then) == 2
    assert length(now) == 2
  end

  test "counting a response updates the values in `sum`" do
    {:ok, agent} = Breaker.Agent.start_link()
    then = get_sum(agent)
    Breaker.Agent.count(agent, %{status_code: 200})
    now = get_sum(agent)
    assert then.total == 0
    assert now.total == 1
  end

  test "counting an error response updates the values in `sum`" do
    {:ok, agent} = Breaker.Agent.start_link()
    then = get_sum(agent)
    Breaker.Agent.count(agent, %{status_code: 500})
    now = get_sum(agent)
    assert then.total == 0
    assert then.errors == 0
    assert now.total == 1
    assert now.errors == 1
  end

  test "rolling a bucket out of the window removes those values from `sum`" do
    {:ok, agent} = Breaker.Agent.start_link(%{window_length: 2})
    Breaker.Agent.count(agent, %{status_code: 200})
    Breaker.Agent.count(agent, %{status_code: 500})
    then = get_sum(agent)
    Breaker.Agent.roll(agent)
    Breaker.Agent.roll(agent)
    now = get_sum(agent)
    assert then.total == 2
    assert then.errors == 1
    assert now.total == 0
    assert now.errors == 0
  end

  defp get_window(agent), do: Agent.get(agent, &(&1.window))
  
  defp get_sum(agent), do: Agent.get(agent, &(&1.sum))

  defp get_current_bucket(agent), do: agent |> get_window() |> List.first()
end
