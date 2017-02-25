defmodule BreakerBench do
  use Benchfella

  bench "create a breaker" do
    Breaker.start_link([url: "http://httpbin.org/"])
    :ok
  end
end
