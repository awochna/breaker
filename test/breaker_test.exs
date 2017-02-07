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

  test "request times out if new timeout is passed as option" do
    circuit = Breaker.new(%{url: "http://httpbin.org/"})
    response = Breaker.get(circuit, "/delay/1", [timeout: 500])
    assert response.__struct__ == HTTPotion.ErrorResponse
  end

  describe "standard HTTP methods" do
    test "get" do
      circuit = Breaker.new(%{url: "http://httpbin.org/"})
      response = Breaker.get(circuit, "/get")
      assert response.status_code == 200
    end

    test "put" do
      circuit = Breaker.new(%{url: "http://httpbin.org/"})
      response = Breaker.put(circuit, "/put", [body: "hello"])
      assert response.status_code == 200
    end

    test "head" do
      circuit = Breaker.new(%{url: "http://httpbin.org/"})
      response = Breaker.head(circuit, "/get")
      assert response.status_code == 200
    end

    test "post" do
      circuit = Breaker.new(%{url: "http://httpbin.org/"})
      response = Breaker.post(circuit, "/post", [body: "hello"])
      assert response.status_code == 200
    end

    test "patch" do
      circuit = Breaker.new(%{url: "http://httpbin.org/"})
      response = Breaker.patch(circuit, "/patch", [body: "hello"])
      assert response.status_code == 200
    end

    test "delete" do
      circuit = Breaker.new(%{url: "http://httpbin.org/"})
      response = Breaker.delete(circuit, "/delete")
      assert response.status_code == 200
    end

    test "options" do
      circuit = Breaker.new(%{url: "http://httpbin.org/"})
      response = Breaker.options(circuit, "/get")
      assert response.status_code == 200
    end
  end
end
