defmodule BreakerTest do
  use ExUnit.Case
  doctest Breaker

  test "get with unbroken circuit" do
    circuit = Breaker.new(%{url: "http://httpbin.org/"})
    response = Breaker.get(circuit, "/get")
    assert response.status_code == 200
  end

  test "get with broken circuit" do
    circuit = Breaker.new(%{url: "http://httpbin.org/"})
    Breaker.trip(circuit)
    response = Breaker.get(circuit, "/get")
    assert response.__struct__ == Breaker.OpenCircuitError
  end

  test "single failure with error_threshold level of 0 trips circuit" do
    circuit = Breaker.new(%{url: "http://httpbin.org/", error_threshold: 0})
    Breaker.get(circuit, "/status/500")
    assert Breaker.open?(circuit)
  end

  test "timed out request with error_threshold level of 0 trips circuit" do
    circuit = Breaker.new(%{url: "http://httpbin.org/", error_threshold: 0,
      timeout: 500})
    Breaker.get(circuit, "/delay/1")
    assert Breaker.open?(circuit)
  end
end
