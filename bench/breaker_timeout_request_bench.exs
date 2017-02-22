defmodule BreakerTimeoutRequestBench do
  use Benchfella

  setup_all do
    HTTPotion.start
    breaker = Breaker.new(%{url: "http://localhost:8080/", timeout: 500})
    {:ok, breaker}
  end

  bench "get request", [breaker: bench_context] do
    task = Breaker.get(breaker, "/delay/1")
    Breaker.error?(Task.await(task))
  end
end
