defmodule BreakerHealthyRequestBench do
  use Benchfella

  setup_all do
    HTTPotion.start
    breaker = Breaker.new(%{url: "http://localhost:8080/"})
    {:ok, breaker}
  end

  bench "get request", [breaker: bench_context] do
    task = Breaker.get(breaker, "/status/200")
    Breaker.error?(Task.await(task))
  end
end
