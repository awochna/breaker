defmodule BreakerBench do
  use Benchfella

  bench "create a breaker" do
    Breaker.new(%{url: "http://localhost:8080"})
    :ok
  end
end
