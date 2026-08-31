# FPGA-Based NASDAQ ITCH Limit Order Book

A hardware implementation of a single-stock limit order book and Best Bid and Offer (BBO) engine targeting an FPGA. The design receives a 64-bit streamed NASDAQ ITCH data input, parses market-data messages, maintains order-level and price-level state in BRAM, and produces the current BBO.

The project was developed as a learning and portfolio project focused on FPGA architecture, memory-efficient data structures, and low-latency market-data processing.

## Overview

The system processes ITCH messages through a hardware pipeline:

```text
64-bit ITCH Input
       │
       ▼
   ITCH Parser
       │
       ▼
     FIFO
       │
       ▼
 Reference Table
       │
       ▼
     FIFO
       │
       ▼
   Price Table
       │
       ▼
      BBO
```

The implementation is designed around BRAM-based storage to allow the order book to maintain a large number of orders while keeping the processing architecture suitable for high-throughput FPGA operation.

## Supported ITCH Messages

The parser currently supports:

* Add Order
* Delete Order
* Cancel Order
* Execute Order
* Replace Order

The input is streamed as 64-bit words. The current design assumes valid market data and that frames are either back-to-back or begin at the start of a 64-bit input word.

## Order Book Architecture

### Reference Table

The reference table maintains the state of individual orders.

Each order is stored using a **144-bit entry**, with an 8192-entry table:

```text
8192 × 144 bits
```

The order reference number is hashed to an initial table location. **Linear probing** is then used to resolve collisions by searching subsequent entries until the required order is found or an empty location is reached.

The reference table is implemented using BRAM and is used for operations including:

* Add Order
* Cancel
* Delete
* Execute
* Replace

If an order cannot be found, the current implementation drops the operation.

### Price Table

The price-level system uses a **bucket-based structure** rather than linear probing.

The price space is divided into **256 buckets**, with each bucket containing eight price positions:

```text
256 buckets × 8 price positions = 2048 price levels
```

The bucket structure associates each price with an address in the price table. The price itself is not stored in the price table; instead, the corresponding address identifies where the quantity for that price level is stored.

The price table contains:

```text
2048 × 96 bits
```

and stores the aggregated share quantity for each price level.

This bucketed structure reduces the amount of searching required when locating a price level while keeping the price-level storage separate from the order-level reference table.

### BBO Generation

The system maintains the top 10 price levels on **both the bid and ask sides**.

Maintaining these leading levels avoids repeatedly scanning the entire 2048-entry price table after every update. The best level from each side is selected from the maintained top-10 entries and provided as the BBO output.

The BBO consists of:

```text
Best Bid Price
Best Bid Shares

Best Ask Price
Best Ask Shares
```


## Memory Architecture

The main storage structures are implemented using FPGA block RAM:

| Structure       | Dimensions | Purpose                           |
| --------------- | ---------: | --------------------------------- |
| Reference Table | 8192 × 144 | Individual order state            |
| Price Table     |  2048 × 96 | Aggregated shares at price levels |
| FIFOs           | BRAM-based | Pipeline buffering                |

The current synthesis uses:

```text
48 / 50 BRAMs
```

or approximately **96% of the available block RAM** on the target device.

LUTS and DSP slices yet to be fully determined.

## Target Hardware

The design targets the:

**Digilent Cmod A7-35T**

The current implementation has been synthesised successfully and is presently targeting approximately:

```text
Clock frequency: 150 MHz
Clock period:    6.67 ns
```

## Timing

The current critical path is approximately:

```text
9.2 ns
```

The primary timing bottleneck is currently associated with a **32-bit subtraction operation** used when modifying order quantities during operations such as cancellation, execution, or deletion.

Timing optimisation is an ongoing part of the project, with increasing the achievable clock frequency being a future objective.

## Latency

The architecture is designed as a pipelined streaming system.

The current estimated average processing latency is approximately:

```text
~20 clock cycles
```

This has not yet been formally benchmarked and should therefore be treated as an approximate figure rather than a measured performance result.

At 150 MHz, one clock cycle is approximately 6.67 ns.

## Verification

Initial verification has included:

* Five orders processed back-to-back
* Random order sequences
* Testing of the complete processing path
* Testing of order-book updates through the parser and storage architecture

Further verification is planned using a **Python reference model**. The FPGA implementation will be compared against the software model to validate order-level state, price-level aggregation, and BBO output across larger and more varied test sequences.

## Current Limitations

The current implementation makes several simplifying assumptions:

* Input market data is assumed to be valid.
* ITCH frames are assumed to start at the beginning of a 64-bit input word or follow immediately after another frame.
* Orders that cannot be found during an operation are currently dropped.
* Comprehensive software-model verification is still in development.
* Timing and latency optimisation are ongoing.
* The implementation currently targets a single stock.

## Future Work

Planned improvements include:

* Develop a Python reference implementation for automated verification.
* Perform larger-scale randomised testing.
* Benchmark end-to-end processing latency.
* Optimise the 32-bit subtraction critical path.
* Increase the maximum achievable clock frequency.
* Perform more extensive hardware testing.
* Investigate further reductions in BRAM utilisation.

## Tools

* **VHDL** — RTL implementation
* **Xilinx Vivado** — synthesis and timing analysis
* **Digilent Cmod A7-35T** — target FPGA hardware
* **Python** — planned reference model and verification

## Project Goals

The primary goal of the project is to explore how a software-style limit order book can be implemented as a hardware data path while considering:

* FPGA memory architecture
* BRAM utilisation
* Hash tables and collision resolution
* Streaming data processing
* Pipeline design
* Order-level versus price-level state
* Timing closure
* Low-latency market-data processing

The project is particularly relevant to **FPGA-based electronic trading and high-frequency trading infrastructure**, where deterministic latency, throughput, and efficient memory utilisation are important design considerations.
