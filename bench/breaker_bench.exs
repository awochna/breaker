defmodule BreakerBench do
  use Benchfella

  bench "create a breaker" do
    Breaker.new(%{url: "http://httpbin.org/"})
    :ok
  end
end
