# Breaker #

[![Build Status](https://travis-ci.org/awochna/breaker.svg?branch=master)](https://travis-ci.org/awochna/breaker)

A Circuit Breaker in Elixir for making HTTP(S) requests to external resources.
Uses [HTTPotion](https://github.com/myfreeweb/httpotion) to make requests.

Currently, this is still very basic and a work in progress, but the final product will:

* Fail requests to a bad service.
* Provide multiple options for handling recovery, potentially including:
  * A basic timed recovery (let another request through in **x** seconds)
  * An exponential backoff recovery (try again later no sooner than **x** seconds and no later than **y** seconds from the last failure, with an exponentially increasing time gap)
  * A percent-based recovery (only let **x**% of requests through, until **y** successive requests)
  * A rate-limiting recovery (only allow **x** requests in **y** seconds, until **z** successive requests)

Not all of the above may be implemented, depending on time and complexity.

## Contributing ##

Bug reports are welcome and contributions are encouraged.
If something isn't working the way it should or a convention isn't being followed, that's a bug.
If there isn't documentation for something, I consider that a bug, too.

Please note that this project is released with a Contributor Code of Conduct. By participating in this project, you agree to abide by its terms.

## License ##

This project is released under the MIT license, as detailed in the included `license.txt` file.
