# Cache Memory

Set-associative cache subsystem I'm building out at both the SystemC (golden model) and
SystemVerilog (RTL) level, with cosimulation tying the two together so the RTL gets
cross-checked against something other than my own assumptions.

## Design philosophy

- **Golden model first.** Anything non-trivial gets a reference model before I trust the RTL.
  If the RTL and the model disagree, the model isn't automatically right, but at least I have
  two independent implementations to argue with each other instead of one implementation
  arguing with my own assumptions.
- **Don't touch the DUT to instrument the DUT.** Measurement and traffic generation live in the
  testbench/harness. If I need visibility into something the design doesn't already expose,
  that's a signal to add a probe in the environment, not to bend the design to make measurement
  easier.
- **Directed before random.** Correctness gets nailed down on specific, named cases first,
  before synthetic random traffic ever touches the DUT. Random traffic is for stressing
  something I already trust, not for discovering whether I trust it.
- **Tool compatibility is a hard constraint, not a style preference.** If the simulator can't
  run it, it doesn't matter how clean it looks — code gets rewritten to fit the toolchain, not
  waived with a comment.

## What's in here

- **L2 cache (SystemC)** — `l2_cache_top.cpp`, exercised by `tb_l2_cache_top.cpp`
- **RTL components** — Verilator-compatible SystemVerilog implementing pieces of the cache
  (e.g. a replacement-policy controller), cosimulated against a reference model where one exists
- **L1/L2 interface (RTL)** — `L1_L2_TOP_INTERFACE`, exercised by `top_l1_interface_tb.sv`

## L2 Cache (SystemC)

`l2_cache_top.cpp` is the DUT, pulled into the testbench via a relative include
(`../top/l2_cache_top.cpp`).

`tb_l2_cache_top.cpp` has 7 directed correctness tests:
- read miss / fill
- read hit
- write-back merge
- eviction / writeback
- secondary-miss MSHR merge

On top of correctness, I added a performance-modeling layer around the same DUT — no changes
to the cache code itself, only the surrounding environment:
- a synthetic random-traffic generator, so I'm not limited to the 7 directed tests for
  generating performance stats (traffic-generator approach over trace-replay — didn't have a
  trace on hand and wanted knobs I control directly)
- real-time graphing via a C++ pipe into a live gnuplot window (picked over a browser dashboard
  or matplotlib-cpp — lowest friction for a live view while iterating)

Built on Windows, MSYS2 UCRT64, SystemC 3.0.2-Accellera.

## RTL Components

Cache-related RTL lives here as Verilator-compatible SystemVerilog. Where a block has
non-trivial logic — a replacement policy, for example — it gets cosimulated against a SystemC
golden model over DPI-C rather than being trusted standalone. The point isn't that the model is
automatically "correct" — it's having two independent implementations to check against each
other instead of one implementation checking against my own assumptions.

## L1/L2 Interface (RTL)

`L1_L2_TOP_INTERFACE` — MSHR-based outstanding-request tracking between the L1 side (separate
I$/D$ ports) and the L2 interface, with gtag-tagged requests/responses so completions can be
matched back to the right outstanding miss.

Tested with `top_l1_interface_tb.sv`, also under Verilator.

## RTL constraints

All SystemVerilog here is written to be Verilator-compatible: no inline task initializers, no
unsupported casts, package imports go inside the module rather than at file scope. Anything
that doesn't hold to that gets rewritten, not waived.

## Status

- L2 cache correctness: 7/7 directed tests passing, perf-modeling harness in place
- RTL components: cosimulated against reference models where applicable
- L1/L2 interface: MSHR tracking + gtag matching in place

## TODO
- [ ] Integrate cosimulated RTL policy blocks into the L2 cache itself (currently verified
      standalone against their reference models, not yet integrated)
- [ ] Extend perf-modeling traffic generator / graphs to the RTL side, not just the SystemC L2 model
