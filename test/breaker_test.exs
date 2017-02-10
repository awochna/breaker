defmodule BreakerTest do
  use ExUnit.Case
  doctest Breaker

  test "get with unbroken circuit" do
    circuit = Breaker.new(%{url: "http://httpbin.org/"})
    response = circuit |> Breaker.get("/get") |> Task.await
    assert response.status_code == 200
  end

  test "get with broken circuit" do
    circuit = Breaker.new(%{url: "http://httpbin.org/"})
    Breaker.trip(circuit)
    response = circuit |> Breaker.get("/get") |> Task.await
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
    circuit |> Breaker.get("/status/500") |> Task.await
    assert Breaker.open?(circuit)
  end

  test "timed out request with error_threshold level of 0 trips circuit" do
    circuit = Breaker.new(%{url: "http://httpbin.org/", error_threshold: 0,
      timeout: 500})
    circuit |> Breaker.get("/delay/1") |> Task.await
    assert Breaker.open?(circuit)
  end

  test "request times out if new timeout is passed as option" do
    circuit = Breaker.new(%{url: "http://httpbin.org/"})
    response = circuit |> Breaker.get("/delay/1", [timeout: 500]) |> Task.await
    assert response.__struct__ == HTTPotion.ErrorResponse
  end

  describe "standard HTTP methods" do
    test "get" do
      circuit = Breaker.new(%{url: "http://httpbin.org/"})
      response = circuit |> Breaker.get("/get") |> Task.await
      assert response.status_code == 200
    end

    test "put" do
      circuit = Breaker.new(%{url: "http://httpbin.org/"})
      response = circuit |> Breaker.put("/put", [body: "hello"]) |> Task.await
      assert response.status_code == 200
    end

    test "put without body" do
      circuit = Breaker.new(%{url: "http://httpbin.org/"})
      response = circuit |> Breaker.put("/put") |> Task.await
      assert response.status_code == 200
    end

    test "head" do
      circuit = Breaker.new(%{url: "http://httpbin.org/"})
      response = circuit |> Breaker.head("/get") |> Task.await
      assert response.status_code == 200
    end

    test "post" do
      circuit = Breaker.new(%{url: "http://httpbin.org/"})
      response = circuit |> Breaker.post("/post", [body: "hello"]) |> Task.await
      assert response.status_code == 200
    end

    test "post without body" do
      circuit = Breaker.new(%{url: "http://httpbin.org/"})
      response = circuit |> Breaker.post("/post") |> Task.await
      assert response.status_code == 200
    end

    test "patch" do
      circuit = Breaker.new(%{url: "http://httpbin.org/"})
      response = circuit |> Breaker.patch("/patch", [body: "hello"]) |> Task.await
      assert response.status_code == 200
    end

    test "patch without body" do
      circuit = Breaker.new(%{url: "http://httpbin.org/"})
      response = circuit |> Breaker.patch("/patch") |> Task.await
      assert response.status_code == 200
    end

    test "delete" do
      circuit = Breaker.new(%{url: "http://httpbin.org/"})
      response = circuit |> Breaker.delete("/delete") |> Task.await
      assert response.status_code == 200
    end

    test "options" do
      circuit = Breaker.new(%{url: "http://httpbin.org/"})
      response = circuit |> Breaker.options("/get") |> Task.await
      assert response.status_code == 200
    end
  end

  describe "standard HTTP methods with broken circuit" do
    test "get" do
      circuit = Breaker.new(%{url: "http://httpbin.org/", open: true})
      response = circuit |> Breaker.get("/get") |> Task.await
      assert response.__struct__ == Breaker.OpenCircuitError
    end

    test "put" do
      circuit = Breaker.new(%{url: "http://httpbin.org/", open: true})
      response = circuit |> Breaker.put("/put", [body: "hello"]) |> Task.await
      assert response.__struct__ == Breaker.OpenCircuitError
    end

    test "head" do
      circuit = Breaker.new(%{url: "http://httpbin.org/", open: true})
      response = circuit |> Breaker.head("/get") |> Task.await
      assert response.__struct__ == Breaker.OpenCircuitError
    end

    test "post" do
      circuit = Breaker.new(%{url: "http://httpbin.org/", open: true})
      response = circuit |> Breaker.post("/post", [body: "hello"]) |> Task.await
      assert response.__struct__ == Breaker.OpenCircuitError
    end

    test "patch" do
      circuit = Breaker.new(%{url: "http://httpbin.org/", open: true})
      response = circuit |> Breaker.patch("/patch", [body: "hello"]) |> Task.await
      assert response.__struct__ == Breaker.OpenCircuitError
    end

    test "delete" do
      circuit = Breaker.new(%{url: "http://httpbin.org/", open: true})
      response = circuit |> Breaker.delete("/delete") |> Task.await
      assert response.__struct__ == Breaker.OpenCircuitError
    end

    test "options" do
      circuit = Breaker.new(%{url: "http://httpbin.org/", open: true})
      response = circuit |> Breaker.options("/get") |> Task.await
      assert response.__struct__ == Breaker.OpenCircuitError
    end
  end
end
