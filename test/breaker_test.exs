defmodule BreakerTest do
  use ExUnit.Case
  doctest Breaker

  test "get with unbroken circuit" do
    circuit = Breaker.new(%{url: "http://localhost:8080/"})
    response = Breaker.get(circuit, "/get")
    assert response.status_code == 200
  end

  test "get with broken circuit" do
    circuit = Breaker.new(%{url: "http://localhost:8080/"})
    Breaker.trip(circuit)
    response = Breaker.get(circuit, "/get")
    assert response.status_code == 500
  end

  test "single failure with error_threshold level of 0 trips circuit" do
    circuit = Breaker.new(%{url: "http://localhost:8080/", error_threshold: 0})
    Breaker.get(circuit, "/status/500")
    assert Breaker.open?(circuit)
  end
end
