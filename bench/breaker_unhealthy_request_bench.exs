defmodule BreakerUnhealthyRequestBench do
  use Benchfella

  setup_all do
    HTTPotion.start
    breaker = Breaker.new(%{url: "http://localhost:8080/"})
    {:ok, breaker}
  end

  bench "get request with breaker", [breaker: bench_context] do
    task = Breaker.get(breaker, "/status/500")
    Breaker.error?(Task.await(task))
  end

  bench "get request without breaker" do
    response = HTTPotion.get("http://localhost:8080/status/500")
    Breaker.error?(response)
  end
end
