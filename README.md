# Breaker #

[![Hex.pm](https://img.shields.io/hexpm/v/breaker.svg)](https://hex.pm/packages/breaker)
[![Build Status](https://travis-ci.org/awochna/breaker.svg?branch=master)](https://travis-ci.org/awochna/breaker)
[![Coverage Status](https://coveralls.io/repos/github/awochna/breaker/badge.svg?branch=master)](https://coveralls.io/github/awochna/breaker?branch=master)
[![Inline docs](https://inch-ci.org/github/awochna/breaker.svg)](https://inch-ci.org/github/awochna/breaker)
[![Ebert](https://ebertapp.io/github/awochna/breaker.svg)](https://ebertapp.io/github/awochna/breaker)

A Circuit Breaker in Elixir for making async HTTP(S) requests to external resources.
Uses [HTTPotion](https://github.com/myfreeweb/httpotion) to make requests.

The following README documentation is for the `master` branch.
Maybe you're looking for the [0.1.1 docs](http://hexdocs.pm/breaker/0.1.1/)?

## Installation ##

Add this project as a dependency in your mix.exs file:

```
defp deps do
  [
    {:breaker, "~> 0.1.1"}
  ]
end
```

And then run:

    $ mix deps.get

## Simple Usage ##

To create a circuit breaker for an external resource, do something like the following:

```
{:ok, user_service} = Breaker.start_link([url: "http://example.com/users/"])
```

Then, you can use it and Breaker to make HTTP calls:

### GET example ###

You can make a request for some data you know you'll need later:

```
# Makes a GET request to "http://example.com/users/42"
user_request = Breaker.get(user_service, "/42")

# do some other things, then later, when you need it

user = Task.await(user_request)
```

### POST example ###

Say you need to create a new user and ensure the response from the other
service was good.

```
body = build_new_user_body(new_user)
request = Breaker.post(user_service, "/", [body: body])

# do some other things,

# then ensure you got a good response from your request,
# otherwise put it in Redis or something for later
response = Task.await(request)
cond do
  Breaker.error?(response) ->
    # put this request in Redis for later
  # other possible responses, like 403 or 422
  response.status_code == 200 ->
    # yay, continue
end
```

### Other HTTP Methods ###

Breaker has a function for each of the HTTP methods: `GET`, `POST`, `PUT`, `PATCH`, `HEAD`, `DELETE`, and `OPTIONS`.

They follow the same easy convention as HTTPotion: `Breaker.get/3`, `Breaker.put/3`, etc.

### Naming your Breaker ###

`Breaker.start_link` can accept an extra parameter and will pass it directly to GenServer as a name to register the process.

```
Breaker.start_link([url: "http://example.com/users/"], :user_service)
# Now you can just use the registered name
user_request = Breaker.get(:user_service, "/42")
```

This makes it easier to use application-wide breakers and supervision trees.

### Other Helpful Functions ###

* `Breaker.open?/1` takes a breaker and returns a boolean, asking if it is open (won't allow network flow)
* `Breaker.error?/1` takes a response and returns a boolean, asking if the response was some sort of error (Status Code of 500, timeout, `Breaker.OpenCircuitError`)
* `Breaker.trip/1` sets the breaker's status to open, disallowing network flow.
* `Breaker.reset/1` sets the breaker's status to closed, allowing network flow.

You probably don't want to make use of `Breaker.trip/1` and `Breaker.reset/1` because the breaker's status will be recalculated after a request and override what you've manually set.
This could be useful to push through a request, even to a service that is down or unhealthy.

## Configuration ##

You can configure your new breaker with a few different options.
The following options affect each request made:

* `url`: Required, the base URL for your external serivce, like "http://your-domain.com/users/" for your user service, or "http://users.your-domain.com/"
* `headers`: Any headers (like in HTTPotion) that should be included in EVERY request made by the circuit breaker.
This could be something like an authentication token or a service identifier for logs.
The default is `[]`.
* `timeout`: The number of ms before giving up on a request. This is passed to HTTPotion and has a default of `3000`, or 3 seconds.

The following options affect how the breaker's status is calculated:

* `error_threshold`: The percent (as a float) of requests that are allowed to be bad (bad = 500 or timeout).
The default is `0.05` or 5%.
Once this threshold is broken, the breaker trips and more requests will return `%Breaker.OpenCircuitError{}` responses.
* `bucket_length`: The breaker uses multiple buckets in a health window to determine the `error_rate`.
This setting specifies, in ms, how long a bucket should be.
The default is `1000` or 1 second.
* `window_length`: The length (in buckets) of the health window.
This number, multiplied by `bucket_length` is the total number of ms used to calculate health.
The default is `10`.

## Understanding 'buckets' and 'windows' ##

The breaker uses multiple 'buckets' in a 'window' to determine health and roll out old requests.
Buckets are measured in time (ms) and windows are measured in buckets.
This means that using the defaults, health is calculated based on responses received in the last 10 seconds of operation.
I highly encourage you to play with these settings to accomodate your individual traffic.

To give an example, say your application is happily going along, processing requests and making requests of an external service, the User Serivce.
It's making an average of 1 request per second, using the default `bucket_length` and `window_length`.
Then, it hits a dreaded 500 error.
At this point, it's error rate was 0%, but just jumped to 10%, above the default `error_threshold`.
Now, when you make a new request, the breaker is open, and instead of waiting up to 3 seconds to get a 500 error, the request fails fast, returning a `%Breaker.OpenCircuitError{}`.
In about 9 more seconds, the bucket that contained our 500 error will be rotated out, closing the circuit and leaving us with a clean slate.

If our very next request now times out or gives a 500 (because the external service still isn't working properly), then we have an error rate of 100% and the circuit opens for another 10 seconds.

If, instead, the service had recovered while the circuit was open, then we only have (at most) about 10 seconds of missed requests.
Hopefully, we have designed our application such that those requests to not be absolutely required, or we've stashed them in a queue somewhere for processing later.

The above is a greatly simplified example because normally you'll want to create a breaker for something that you'll need to make calls against at a much higher rate.
Basically, keep the following things in mind when configuring your breaker:

* `bucket_length` should be long enough that, on average, you'll have 5 or more requests in that period of time.
* `window_length` should be high enough that you give the external service time to recover, but low enough that errors from awhile ago aren't bogging down your application's performance or features now.
The default might just be good enough unless you've found a reason to change it.
* `error_threshold` should be low enough that your users aren't dealing with a really slow experience.
It will need to be higher if `bucket_length` and `window_length` aren't enough to get a good sample of the requets.
In the above example, it would have probably been acceptable to have an `error_threshold` of something like `0.2` (20%) so I can tolerate more than 1 error before breaking the circuit.

## Contributing ##

Bug reports are welcome and contributions are encouraged.
If something isn't working the way it should or a convention isn't being followed, that's a bug.
If there isn't documentation for something, I consider that a bug, too.

Please note that this project is released with a Contributor Code of Conduct. By participating in this project, you agree to abide by its terms.

## License ##

This project is released under the MIT license, as detailed in the included `license.txt` file.
