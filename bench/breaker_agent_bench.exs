defmodule BreakerAgentBench do
  use Benchfella

  before_each_bench _ do
    Breaker.Agent.start_link()
  end

  after_each_bench pid do
    Agent.stop(pid)
  end

  bench "ask if open", [pid: bench_context] do
    Breaker.Agent.open?(pid)
    :ok
  end

  bench "manually trip circuit", [pid: bench_context] do
    Breaker.Agent.trip(pid)
  end

  bench "manually reset circuit", [pid: bench_context] do
    Breaker.Agent.reset(pid)
  end

  bench "manually recalculate the circuit's status", [pid: bench_context] do
    Breaker.Agent.recalculate(pid)
  end

  bench "count a hit", [pid: bench_context] do
    Breaker.Agent.count(pid, %HTTPotion.Response{status_code: 200})
  end

  bench "count a miss", [pid: bench_context] do
    Breaker.Agent.count(pid, %HTTPotion.Response{status_code: 500})
  end

  bench "count a timeout", [pid: bench_context] do
    Breaker.Agent.count(pid, %HTTPotion.ErrorResponse{})
  end

  bench "roll the health window", [pid: bench_context] do
    Breaker.Agent.roll(pid)
  end
end
