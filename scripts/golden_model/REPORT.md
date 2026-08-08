# L2 Cache Golden Model

## Why this exists

Before I trust any RTL, I want a reference that I know is right. That's what this Golden Model is — a cycle-accurate SystemC implementation of the L2 cache that I can run every RTL request through and compare, cycle for cycle, against what the hardware actually does. If the two diverge, I know the RTL has a bug and not the other way around.

The model doesn't try to be synthesizable or efficient. It's built to be obviously correct and easy to poke at when something goes wrong. It's a non-blocking L2 with multiple outstanding misses tracked through MSHRs, and it walks through the full pipeline — tag lookup, victim selection, refill, dirty write-back, and the handshake with the LLC.

## What I wanted out of it

I built this with a few things in mind: I needed something I could trust as ground truth while writing the RTL, something that would let me validate cache behavior before committing to hardware, and something simple enough that when RTL output doesn't match, I can actually find why within a reasonable amount of debugging. It also had to be structured so I could extend it later without tearing up the verification flow around it.

## How it's organized

I kept the module boundaries the same as the RTL, block for block, so comparisons stay one-to-one:

Global Control, Tag Memory, Tag Compare, Data Array, an SRRIP replacement controller, the MSHR table, and the L1/LLC interfaces. Each of these lives as its own piece and only talks to the others through the top-level cache module.

### Global Control

This is the piece that runs everything else. It takes in requests, drives the tag lookup, figures out hit vs. miss, picks a victim line when it needs one, allocates MSHR entries, schedules refills, handles dirty write-backs, and sends the response back out. Every other module is essentially reacting to what Global Control tells it to do.

### MSHR

Right now I'm running with 8 MSHR entries, which is what lets the cache have that many misses in flight at once. Each entry carries the request address, index, tag, the victim way it picked, whether that victim was dirty, who the original requester was, any secondary reads that got merged in, and the current state of that transaction.

The merging matters more than it sounds — if a second read comes in for a line that's already being fetched, it just attaches to the existing MSHR entry instead of firing off a duplicate memory request. Saves bandwidth and avoids a class of bugs I'd rather not chase.

### Tag Memory and Tag Compare

Tag Memory holds the tags, valid bits, and dirty bits. Tag Compare is the piece that actually checks an incoming address against what's stored and decides hit or miss. Simple on paper, but this is where most subtle correctness bugs like to hide, so I kept it as its own isolated block rather than folding it into Global Control.

### Data Array

This is where the actual cache line data lives. Current numbers:

- 512 KB total capacity
- 4-way set associative
- 2048 sets
- 64B line size

### SRRIP Replacement

Victim selection runs on SRRIP — Static Re-Reference Interval Prediction. It picks which way to evict and updates the re-reference metadata after every access.

### Top-Level Integration

Everything above gets wired together here, with the interfaces out to the L1 cache on one side and the LLC on the other. This is also the level at which I hook the RTL comparison in during verification.

## How I'm verifying it

The environment is self-checking — I don't want to be eyeballing waveforms to catch a mismatch. It runs the model through hits, misses, refills, dirty write-backs, SRRIP eviction decisions, secondary-miss merging, several outstanding misses at once, and the memory responses coming back for all of it. Results get checked automatically against expected behavior rather than by hand.

## What's in scope right now

This version is deliberately just a single non-blocking L2, nothing more. I'm not modeling multi-core coherence, snooping, directory protocols, prefetching, QoS scheduling, or a multi-banked cache yet — those are all things I want to add later, but pulling them in now would make it harder to trust as a baseline while the core pipeline is still settling.

## Where this leaves things

This Golden Model is the thing I lean on to know whether my RTL is actually correct or just looks correct. Between the cycle-accurate behavior, the module-for-module match with the RTL, and the self-checking verification around it, it's doing what I built it to do — catch bugs before they become RTL bugs I have to debug blind.

