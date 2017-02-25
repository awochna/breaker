defmodule BreakerTest do
  use ExUnit.Case, async: true
  doctest Breaker

  @options [url: "http://httpbin.org"]
  @broken [url: "http://httpbin.org", open: true]

  test "fails without a url" do
    Process.flag(:trap_exit, true)
    Breaker.start_link([])
    assert_receive({:EXIT, _, :missing_url})
  end

  test "accepts a name and can be called using the name" do
    Breaker.start_link(@options, :httpbin)
    refute Breaker.open?(:httpbin)
  end

  test "get with unbroken circuit" do
    {:ok, circuit} = Breaker.start_link(@options)
    response = circuit |> Breaker.get("/get") |> Task.await
    assert response.status_code == 200
  end

  test "get with broken circuit" do
    {:ok, circuit} = Breaker.start_link(@options)
    Breaker.trip(circuit)
    response = circuit |> Breaker.get("/get") |> Task.await
    assert response.__struct__ == Breaker.OpenCircuitError
  end

  test "multiple requests via Tasks" do
    {:ok, circuit} = Breaker.start_link(@options)
    [Breaker.get(circuit, "/get"), Breaker.get(circuit, "/ip")]
    |> Enum.map(&Task.await/1)
    |> Enum.each(fn(response) -> assert response.status_code == 200 end)
  end

  test "single failure with error_threshold level of 0 trips circuit" do
    options = @options ++ [error_threshold: 0]
    {:ok, circuit} = Breaker.start_link(options)
    circuit |> Breaker.get("/status/500") |> Task.await
    assert Breaker.open?(circuit)
  end

  test "timed out request with error_threshold level of 0 trips circuit" do
    options = @options ++ [error_threshold: 0, timeout: 500]
    {:ok, circuit} = Breaker.start_link(options)
    circuit |> Breaker.get("/delay/1") |> Task.await
    assert Breaker.open?(circuit)
  end

  test "request times out if new timeout is passed as option" do
    {:ok, circuit} = Breaker.start_link(@options)
    response = circuit |> Breaker.get("/delay/1", [timeout: 500]) |> Task.await
    assert response.__struct__ == HTTPotion.ErrorResponse
  end

  test "merges specified headers" do
    options = @options ++ [headers: ["Authorization": "some auth string"]]
    {:ok, circuit} = Breaker.start_link(options)
    request = Breaker.get(circuit, "/headers", [headers: ["Accepts": "application/json"]])
    response = Task.await(request)
    json = Poison.decode!(response.body)
    assert json["headers"]["Authorization"] == "some auth string"
    assert json["headers"]["Accepts"] == "application/json"
  end

  describe "internals" do
    test "the breaker has a window to record hits and misses" do
      {:ok, circuit} = Breaker.start_link(@options)
      [current_bucket | _] = window = get_window(circuit)
      assert length(window) == 1
      assert current_bucket.total == 0
      assert current_bucket.errors == 0
    end

    test "the breaker can count a positive response in the current bucket" do
      {:ok, circuit} = Breaker.start_link(@options)
      [then | _] = get_window(circuit)
      Breaker.count(circuit, %HTTPotion.Response{status_code: 200})
      [now | _] = get_window(circuit)
      assert then.total == 0
      assert now.total == 1
    end

    test "the breaker can count an error response in the current bucket" do
      {:ok, circuit} = Breaker.start_link(@options)
      [then | _] = get_window(circuit)
      Breaker.count(circuit, %HTTPotion.Response{status_code: 500})
      [now | _] = get_window(circuit)
      assert then.total == 0
      assert then.errors == 0
      assert now.total == 1
      assert now.errors == 1
    end

    test "the breaker counts %HTTPotion.ErrorResponse{} as an error" do
      {:ok, circuit} = Breaker.start_link(@options)
      [then | _] = get_window(circuit)
      Breaker.count(circuit, %HTTPotion.ErrorResponse{})
      [now | _] = get_window(circuit)
      assert then.errors == 0
      assert now.errors == 1
    end

    test "the breaker's window can be rolled, creating a new current bucket" do
      {:ok, circuit} = Breaker.start_link(@options)
      then = get_window(circuit)
      Breaker.roll(circuit)
      now = get_window(circuit)
      assert length(then) == 1
      assert length(now) == 2
    end

    test "the circuit won't create more than window_length buckets" do
      options = @options ++ [window_length: 2]
      {:ok, circuit} = Breaker.start_link(options)
      Breaker.roll(circuit)
      then = get_window(circuit)
      Breaker.roll(circuit)
      now = get_window(circuit)
      assert length(then) == 2
      assert length(now) == 2
    end

    test "counting a positive response updates the values in `sum`" do
      {:ok, circuit} = Breaker.start_link(@options)
      then = get_sum(circuit)
      Breaker.count(circuit, %HTTPotion.Response{status_code: 200})
      now = get_sum(circuit)
      assert then.total == 0
      assert now.total == 1
    end

    test "counting an error response updates the values in `sum`" do
      {:ok, circuit} = Breaker.start_link(@options)
      then = get_sum(circuit)
      Breaker.count(circuit, %HTTPotion.Response{status_code: 500})
      now = get_sum(circuit)
      assert then.total == 0
      assert then.errors == 0
      assert now.total == 1
      assert now.errors == 1
    end

    test "rolling a bucket out of the window removes those values from `sum`" do
      options = @options ++ [window_length: 2]
      {:ok, circuit} = Breaker.start_link(options)
      Breaker.count(circuit, %HTTPotion.Response{status_code: 200})
      Breaker.count(circuit, %HTTPotion.Response{status_code: 500})
      then = get_sum(circuit)
      Breaker.roll(circuit)
      Breaker.roll(circuit)
      now = get_sum(circuit)
      assert then.total == 2
      assert then.errors == 1
      assert now.total == 0
      assert now.errors == 0
    end

    test "rolls the window after the given `bucket_length`" do
      options = @options ++ [bucket_length: 500]
      {:ok, circuit} = Breaker.start_link(options)
      :timer.sleep(750)
      window = get_window(circuit)
      assert length(window) == 2
    end

    test "manual rolling also recalculates the circuit's status" do
      options = @options ++ [sum: %{total: 50, errors: 50}]
      {:ok, circuit} = Breaker.start_link(options)
      refute Breaker.open?(circuit)
      Breaker.roll(circuit)
      assert Breaker.open?(circuit)
    end

    test "automatic rolling also recalculates the circuit's status" do
      options = @broken ++ [bucket_length: 500]
      {:ok, circuit} = Breaker.start_link(options)
      :timer.sleep(750)
      refute Breaker.open?(circuit)
    end
  end

  describe "standard HTTP methods" do
    test "get" do
      {:ok, circuit} = Breaker.start_link(@options)
      response = circuit |> Breaker.get("/get") |> Task.await
      assert response.status_code == 200
    end

    test "put" do
      {:ok, circuit} = Breaker.start_link(@options)
      response = circuit |> Breaker.put("/put", [body: "hello"]) |> Task.await
      assert response.status_code == 200
    end

    test "put without body" do
      {:ok, circuit} = Breaker.start_link(@options)
      response = circuit |> Breaker.put("/put") |> Task.await
      assert response.status_code == 200
    end

    test "head" do
      {:ok, circuit} = Breaker.start_link(@options)
      response = circuit |> Breaker.head("/get") |> Task.await
      assert response.status_code == 200
    end

    test "post" do
      {:ok, circuit} = Breaker.start_link(@options)
      response = circuit |> Breaker.post("/post", [body: "hello"]) |> Task.await
      assert response.status_code == 200
    end

    test "post without body" do
      {:ok, circuit} = Breaker.start_link(@options)
      response = circuit |> Breaker.post("/post") |> Task.await
      assert response.status_code == 200
    end

    test "patch" do
      {:ok, circuit} = Breaker.start_link(@options)
      response = circuit |> Breaker.patch("/patch", [body: "hello"]) |> Task.await
      assert response.status_code == 200
    end

    test "patch without body" do
      {:ok, circuit} = Breaker.start_link(@options)
      response = circuit |> Breaker.patch("/patch") |> Task.await
      assert response.status_code == 200
    end

    test "delete" do
      {:ok, circuit} = Breaker.start_link(@options)
      response = circuit |> Breaker.delete("/delete") |> Task.await
      assert response.status_code == 200
    end

    test "options" do
      {:ok, circuit} = Breaker.start_link(@options)
      response = circuit |> Breaker.options("/get") |> Task.await
      assert response.status_code == 200
    end
  end

  describe "standard HTTP methods with broken circuit" do
    test "get" do
      {:ok, circuit} = Breaker.start_link(@broken)
      response = circuit |> Breaker.get("/get") |> Task.await
      assert response.__struct__ == Breaker.OpenCircuitError
    end

    test "put" do
      {:ok, circuit} = Breaker.start_link(@broken)
      response = circuit |> Breaker.put("/put", [body: "hello"]) |> Task.await
      assert response.__struct__ == Breaker.OpenCircuitError
    end

    test "head" do
      {:ok, circuit} = Breaker.start_link(@broken)
      response = circuit |> Breaker.head("/get") |> Task.await
      assert response.__struct__ == Breaker.OpenCircuitError
    end

    test "post" do
      {:ok, circuit} = Breaker.start_link(@broken)
      response = circuit |> Breaker.post("/post", [body: "hello"]) |> Task.await
      assert response.__struct__ == Breaker.OpenCircuitError
    end

    test "patch" do
      {:ok, circuit} = Breaker.start_link(@broken)
      response = circuit |> Breaker.patch("/patch", [body: "hello"]) |> Task.await
      assert response.__struct__ == Breaker.OpenCircuitError
    end

    test "delete" do
      {:ok, circuit} = Breaker.start_link(@broken)
      response = circuit |> Breaker.delete("/delete") |> Task.await
      assert response.__struct__ == Breaker.OpenCircuitError
    end

    test "options" do
      {:ok, circuit} = Breaker.start_link(@broken)
      response = circuit |> Breaker.options("/get") |> Task.await
      assert response.__struct__ == Breaker.OpenCircuitError
    end
  end

  defp get_window(circuit), do: :sys.get_state(circuit).window

  defp get_sum(circuit), do: :sys.get_state(circuit).sum
end
