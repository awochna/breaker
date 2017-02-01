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

  test "single failure with tolerance level of 0 trips circuit" do
    {:ok, circuit} = Breaker.start_link(%{addr: "http://localhost:8080/", tolerance: 0})
    Breaker.get(circuit, "/status/500")
    assert Breaker.open?(circuit)
  end

end
