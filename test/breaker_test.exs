defmodule BreakerTest do
  use ExUnit.Case
  doctest Breaker

  test "get with unbroken circuit" do
    circuit = Breaker.new(%{url: "http://httpbin.org/"})
    response = Breaker.get(circuit, "/get") |> Task.await
    assert response.status_code == 200
  end

  test "get with broken circuit" do
    circuit = Breaker.new(%{url: "http://httpbin.org/"})
    Breaker.trip(circuit)
    response = Breaker.get(circuit, "/get") |> Task.await
    assert response.__struct__ == Breaker.OpenCircuitError
  end

  test "multiple requests via Tasks" do
    circuit = Breaker.new(%{url: "http://httpbin.org/"})
    [Breaker.get(circuit, "/get"), Breaker.get(circuit, "/ip")]
    |> Enum.map(&Task.await/1)
    |> Enum.each(fn(response) -> assert response.status_code == 200 end)
  end

  test "single failure with error_threshold level of 0 trips circuit" do
    circuit = Breaker.new(%{url: "http://httpbin.org/", error_threshold: 0})
    Breaker.get(circuit, "/status/500") |> Task.await
    assert Breaker.open?(circuit)
  end

  test "timed out request with error_threshold level of 0 trips circuit" do
    circuit = Breaker.new(%{url: "http://httpbin.org/", error_threshold: 0,
      timeout: 500})
    Breaker.get(circuit, "/delay/1") |> Task.await
    assert Breaker.open?(circuit)
  end

  test "request times out if new timeout is passed as option" do
    circuit = Breaker.new(%{url: "http://httpbin.org/"})
    response = Breaker.get(circuit, "/delay/1", [timeout: 500]) |> Task.await
    assert response.__struct__ == HTTPotion.ErrorResponse
  end

  describe "standard HTTP methods" do
    test "get" do
      circuit = Breaker.new(%{url: "http://httpbin.org/"})
      response = Breaker.get(circuit, "/get") |> Task.await
      assert response.status_code == 200
    end

    test "put" do
      circuit = Breaker.new(%{url: "http://httpbin.org/"})
      response = Breaker.put(circuit, "/put", [body: "hello"]) |> Task.await
      assert response.status_code == 200
    end

    test "put without body" do
      circuit = Breaker.new(%{url: "http://httpbin.org/"})
      response = Breaker.put(circuit, "/put") |> Task.await
      assert response.status_code == 200
    end

    test "head" do
      circuit = Breaker.new(%{url: "http://httpbin.org/"})
      response = Breaker.head(circuit, "/get") |> Task.await
      assert response.status_code == 200
    end

    test "post" do
      circuit = Breaker.new(%{url: "http://httpbin.org/"})
      response = Breaker.post(circuit, "/post", [body: "hello"]) |> Task.await
      assert response.status_code == 200
    end

    test "post without body" do
      circuit = Breaker.new(%{url: "http://httpbin.org/"})
      response = Breaker.post(circuit, "/post") |> Task.await
      assert response.status_code == 200
    end

    test "patch" do
      circuit = Breaker.new(%{url: "http://httpbin.org/"})
      response = Breaker.patch(circuit, "/patch", [body: "hello"]) |> Task.await
      assert response.status_code == 200
    end

    test "patch without body" do
      circuit = Breaker.new(%{url: "http://httpbin.org/"})
      response = Breaker.patch(circuit, "/patch") |> Task.await
      assert response.status_code == 200
    end

    test "delete" do
      circuit = Breaker.new(%{url: "http://httpbin.org/"})
      response = Breaker.delete(circuit, "/delete") |> Task.await
      assert response.status_code == 200
    end

    test "options" do
      circuit = Breaker.new(%{url: "http://httpbin.org/"})
      response = Breaker.options(circuit, "/get") |> Task.await
      assert response.status_code == 200
    end
  end

  describe "standard HTTP methods with broken circuit" do
    test "get" do
      circuit = Breaker.new(%{url: "http://httpbin.org/", open: true})
      response = Breaker.get(circuit, "/get") |> Task.await
      assert response.__struct__ == Breaker.OpenCircuitError
    end

    test "put" do
      circuit = Breaker.new(%{url: "http://httpbin.org/", open: true})
      response = Breaker.put(circuit, "/put", [body: "hello"]) |> Task.await
      assert response.__struct__ == Breaker.OpenCircuitError
    end

    test "head" do
      circuit = Breaker.new(%{url: "http://httpbin.org/", open: true})
      response = Breaker.head(circuit, "/get") |> Task.await
      assert response.__struct__ == Breaker.OpenCircuitError
    end

    test "post" do
      circuit = Breaker.new(%{url: "http://httpbin.org/", open: true})
      response = Breaker.post(circuit, "/post", [body: "hello"]) |> Task.await
      assert response.__struct__ == Breaker.OpenCircuitError
    end

    test "patch" do
      circuit = Breaker.new(%{url: "http://httpbin.org/", open: true})
      response = Breaker.patch(circuit, "/patch", [body: "hello"]) |> Task.await
      assert response.__struct__ == Breaker.OpenCircuitError
    end

    test "delete" do
      circuit = Breaker.new(%{url: "http://httpbin.org/", open: true})
      response = Breaker.delete(circuit, "/delete") |> Task.await
      assert response.__struct__ == Breaker.OpenCircuitError
    end

    test "options" do
      circuit = Breaker.new(%{url: "http://httpbin.org/", open: true})
      response = Breaker.options(circuit, "/get") |> Task.await
      assert response.__struct__ == Breaker.OpenCircuitError
    end
  end
end
