defmodule BreakerHealthyRequestBench do
  use Benchfella

  setup_all do
    HTTPotion.start
    Breaker.start_link(%{url: "http://localhost:8080/"})
  end

  bench "get request", [breaker: bench_context] do
    task = Breaker.get(breaker, "/status/200")
    Breaker.error?(Task.await(task))
  end
end
