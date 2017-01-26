defmodule BreakerTest do
  use ExUnit.Case
  doctest Breaker

  test "get with unbroken circuit" do
    {:ok, circuit} = Breaker.start_link(%{addr: "http://localhost:8080/"})
    response = Breaker.get(circuit, "/get")
    assert response.status_code == 200
  end

  test "get with broken circuit" do
    {:ok, circuit} = Breaker.start_link(%{addr: "http://localhost:8080/"})
    Breaker.trip(circuit)
    response = Breaker.get(circuit, "/get")
    assert response.status_code == 500
  end

end
