# Suave-LOBDEX

Proof of concept for a central limit order book (CLOB) style DEX built on Suave.

Due to Suave's unique features it's possible to build a limit order book that runs in real time, with built in privacy features.


## DEX Design

Bids and asks are stored in a heap and matched up in real time.

Although events are emitted on callbacks, all the core logic runs in a kettle.  As a result, data could be emitted via an API call precompile in order to provide a real time view of the book, or alternatively nothing could be emitted and you'd have a fully private dark pool.

The current implementation is only a bare bones proof of concept, it only contains basic logic for storing and matching orders.  There are glaring security holes with regard to accessing the orders, and no checks that ensure orders are valid.  Additional features would be needed to ensure that users had funds available to place the orders, and an L1 settlement mechanism is needed as well.


## Dependencies
1. <a href=https://book.getfoundry.sh/getting-started/installation>Foundry</a>

2. <a href=https://github.com/flashbots/suave-geth>Suave</a>


## Usage

### Build

```shell
$ forge build
```

### Test

In a background window run Suave:

```shell
$ suave --suave.dev
```

Then use the ffi flag with Forge.

```shell
$ forge test --ffi
```
