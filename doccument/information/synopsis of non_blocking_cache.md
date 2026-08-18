
## 1. Introduction

When I started working on cache architecture, I first looked at how a blocking cache handles a cache miss. In a blocking cache, the cache has to wait for the missed data to return before handling another request. This can waste a lot of processor time, especially when the memory latency is high.

To overcome this limitation, I started studying **non-blocking caches**, which allow the cache to keep one or more misses outstanding while continuing to process other requests. This requires additional structures such as **MSHRs, request queues, refill logic, and write-back buffers**.

In this project, I am designing a non-blocking cache with support for multiple outstanding misses. My main focus is on understanding the **cache controller, MSHR table, miss handling, refill, write-back, and memory request flow**. I am first modeling the architecture in **SystemC** and then implementing it in **SystemVerilog RTL**.

The main goal of this work is to understand how a cache can continue working efficiently even when data from lower-level memory is still pending.

| Chapter | Title                                                                                                        | Main Questions I Answer                                                                                                  |
| ------: | ------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------ |
|   **1** | **[[# Motivation\|What Problem Am I Trying to Solve?]]**                                                     | Why do I need a cache? What problem does a blocking cache create? What is my objective?                                  |
|   **2** | **[[#How Dose Blocking cache works\|How Does a Blocking Cache Work?]]**                                      | What happens during a hit? What happens during a miss? Why does the cache have to wait?                                  |
|   **3** | **[[#Why Do I Need a Non-Blocking Cache?\|Why Do I Need a Non-Blocking Cache?]]**                            | What is the limitation of blocking cache? How can I continue working while a miss is pending? What is hit-under-miss?    |
|   **4** | **[[#How Does My Cache Architecture Work?\|How Does My Cache Architecture Work?]]**                          | What are the major blocks? How does a CPU request flow through my cache? How do the blocks communicate?                  |
|   **5** | **[[#How Do I Track Multiple Outstanding Misses? \|How Do I Track Multiple Outstanding Misses?]]**           | Why do I need an MSHR? What information does each MSHR entry store? How do I allocate and free an entry?                 |
|   **6** | **[[#How Does My Cache Controller Handle Requests?\|How Does My Cache Controller Handle Requests?]]**        | What happens on a hit? What happens on a miss? How does my FSM control the complete operation?                           |
|   **7** | **[[#How Do I Handle Memory Requests and Refill?\|How Do I Handle Memory Requests and Refill?]]**            | How is a request sent to memory? How do I track the response? How is the cache line refilled?                            |
|   **8** | **[[#How Do I Handle Eviction and Write-Back?\|How Do I Handle Eviction and Write-Back?]]**                  | When does a cache line need to be evicted? What happens when the line is dirty? Why do I use a write-back buffer?        |
|   **9** | **[[#How Do I Select a Cache Line for Replacement?\|How Do I Select a Cache Line for Replacement?]]**        | Why do I need replacement logic? Why did I choose Tree-PLRU? How does my replacement logic work?                         |
|  **10** | **[[#How Did I Model the Cache in SystemC?\|How Did I Model the Cache in SystemC?]]**                        | Why did I start with SystemC? How did I model the cache controller, MSHR and memory? What did I learn from the model?    |
|  **11** | **[[# How Did I Implement the Design in SystemVerilog?\|How Did I Implement the Design in SystemVerilog?]]** | How did I convert the architecture into RTL? What are my modules? How are they connected?                                |
|  **12** | **[[#verification\|#How Did I Verify My Design?]]**                                                          | What tests did I perform? How did I test multiple misses? How did I check refill, write-back and MSHR behavior?          |
|  **13** | **[[#What Results Did I Get?]]**                                                                             | Does the cache work correctly? How does it behave compared with a blocking cache? What are the performance observations? |
|  **14** | **[[#What Are the Current Limitations and What Can we Improve?]]**                                           | What is missing from my current design? What can I add in the future?                                                    |
|  **15** | **[[#Conclusion]]**                                                                                          | What did I learn? What did I successfully design and implement?                                                          |
|  **16** | **[[#References]]**                                                                                          | Books, papers, documentation and other resources used                                                                    |



# Motivation

When I started my case study on the **AMD MI300A**, I noticed that AMD is focusing heavily on memory, rather than simply trying to make the processor faster. This made me think about my first project, an **RV64 64-bit processor with a classic 5-stage pipeline**.

In my first project, I started by adding some latencies, such as a 3-cycle delay. Then I realized how important memory is in today's computing systems. The computation itself does not necessarily cost much, but bringing data to the processor can cost much more, especially in terms of **energy**.

In my first RV64 project, the PC stalls more often because the fetch result is not available, or because writeback is delayed, or because a read operation takes time. These are things we cannot completely avoid, but we can reduce their impact.

One of the ways we reduce this latency is by taking advantage of **spatial locality and temporal locality**. Instead of bringing only the exact data that the processor currently wants, we can bring additional nearby information because it might be needed in the future.

I want to give an example.

My smartphone contains a **Snapdragon 730G**, which was designed around 2020. It is a little old now, but it is still working very well. Workloads have changed significantly since then, yet this machine can still provide very good performance. The question that came to my mind was: **why?**

I started studying the processor more deeply, and I realized that Qualcomm uses **Kryo cores**, with Kryo Gold and Kryo Silver cores. These are based on ARM CPU IP, including the **Cortex-A76 and Cortex-A55**. The Cortex-A55 is an in-order machine, while the Cortex-A76 is an out-of-order machine.

The configuration uses **6 Cortex-A55 cores and 2 Cortex-A76 cores**.

More specifically, the **Cortex-A76** is an out-of-order processor with a **4-wide decode**, meaning that it can decode up to 4 instructions in the same cycle. We can say that the width of the pipeline is 4 in this machine.

If the processor needs 4 instructions per cycle, it needs to fetch **16 bytes of instruction data per cycle**. In addition, out of those 4 instructions, there may be 2 instructions that are load or store operations.

The Cortex-A76 can run at around **2.1 GHz**. So, in a simplified way, we can think about the memory demand as approximately:

**(4 + 2) × 2.1 × 10⁹ requests per second**

If we cannot fulfill this demand, the overall system can become **memory-bound**. No matter how powerful the processor is, if the memory system cannot supply data fast enough, we cannot fully utilize the computational capability of the processor.

This leads to my question:

**What should the ideal memory system look like?**

My belief is that any memory system makes a promise to the processor:

> **"Whenever the processor needs data, the memory system must provide it as fast as possible."**

That promise is what we have to fulfill.

To fulfill this promise, I decided to design a memory system that focuses not only on storing data, but also on **bringing the right data to the processor at the right time and reducing the cost of accessing that data**.

That is the motivation behind my memory-system design.

---
---
# How Dose Blocking cache works

When I was in my first year of engineering, I decided that I wanted to work in **RTL, microarchitecture, and digital design**.

In my second year, I designed my first cache memory: an **8 KB blocking cache**.

https://github.com/PranavBhongale/CACHE_MEMORY_8KB.git

When I started debugging the RTL using **GTKWave waveforms**, I began to realize one major problem with a blocking cache: **it stalls the entire machine if the requested data is not available.**

For example, suppose the processor requests data at address **A**. If the data is not present in the cache, we need to go to the LLC, bring the data back into the cache, and then serve the processor.

Let us assume that this entire operation takes **10 cycles** or sometimes 100's of cycles .

During those 10 cycles, suppose the processor also needs data at address **B**, and the data for B is already available in the memory hierarchy. A blocking cache still cannot serve that request because it is waiting for the previous miss to complete.

**That is the problem.**

To learn more about cache memory and how to improve its performance, I started studying different techniques from the book **_Computer Architecture: A Quantitative Approach_ by John Hennessy and David Patterson**.

I consider this book to be almost a **Bible for computer architecture and microarchitecture**. It presents many different approaches for improving cache performance. From those approaches, I decided to focus on one particular technique:

**Non-blocking cache design.**

But another question came to my mind:
**Do we always need non-blocking behavior?**
What if I say **no**?

After doing a case study on the **Snapdragon 730G**, I looked specifically at the **Cortex-A55** cores, which are designed as efficient cores. The Cortex-A55 is an **in-order processor**.

In an in-order processor, if one load or store operation stalls, we cannot simply move forward with later operations in the same way an out-of-order processor can. We cannot initiate another independent request freely while the previous operation is stalled. That limitation is fundamentally related to the in-order design.

But when I look specifically at the **L2 cache**, I believe that we need non-blocking behavior.

The reason is that the L2 cache is now becoming a shared point between the **L1 instruction cache (L1 I-cache)** and the **L1 data cache (L1 D-cache)**, which is the architecture I am implementing.

If an L1 cache misses and sends a request to the L2, the L2 should not necessarily become blocked while waiting for that request to complete. It should be able to accept and manage other outstanding requests.

For example, if the L1 I-cache generates one request and the L1 D-cache generates another request, the L2 should be able to handle both independently when possible.

Therefore, my conclusion is:

- A **blocking cache** can still be suitable for an **L1 I-cache**, provided that it is extremely fast.
- The **L1 D-cache** has a stronger need for handling multiple outstanding operations because data accesses can stall more frequently.
- At the **L2 cache**, non-blocking behavior becomes much more important because it has to serve requests coming from both **L1 I-cache and L1 D-cache**.
- Therefore, the L2 cache that I am implementing is designed as a **non-blocking cache**.

This is the point where my first blocking-cache design led me toward designing a **non-blocking L2 cache**.

---
# Why Do I Need a Non-Blocking Cache?

Talking about the **AMD MI300A**, AMD calls it an **Accelerated Processing Unit (APU)**. It integrates nearly **24 Zen 4 cores** and **3 CDNA-based compute complexes**, which are GPU compute architectures, across **12 chiplets**, along with **2 I/O dies** and nearly **128 GB of HBM memory**.

The fascinating thing about this architecture is that AMD includes **256 MB of Infinity Cache**, which significantly improves the available memory bandwidth, reaching up to around **17 TB/s**. That is an enormous amount of bandwidth.

This cache is **multi-banked and 16-way set-associative**, with approximately **2 MB per bank**. Even with such a large cache, the architecture still contains multiple levels of cache, including **L3, L2, and L1 instruction and data caches**.

Now, think about the complexity of each **Zen 4 core**. It is a **dual-threaded processor** supporting the **x86 ISA**, with a pipeline that can reach around **19 stages** and a pipeline width of more than **4 instructions per cycle**. It also supports **vector instructions**, making it suitable for multimedia and highly parallel workloads.

To keep such a powerful processor supplied with data, we need a **very sophisticated cache and memory architecture**.

Today, most high-performance processors use **out-of-order execution**. Suppose the processor needs to load data from address **A**, but the data is not present in the D-cache. An out-of-order processor does not necessarily have to stop completely. Instead, it can continue executing other independent instructions while the load request is waiting for the data to arrive.

This gives the processor the freedom to continue making progress and, at the same time, allows the memory system to handle multiple outstanding requests.

**This is the motivation behind designing my L2 cache as a non-blocking cache.**

Now, let's look at the **Snapdragon 730G SoC**.

The Snapdragon 730G contains **6 efficiency cores based on the Cortex-A55**, and interestingly, Qualcomm provides around **2 MB of shared L2 cache** for these efficiency cores.

Even though these are relatively simple and efficient cores, we can still see the use of a **shared L2 cache**.

One important advantage of a shared L2 cache is that it can reduce the overhead associated with maintaining cache coherence between multiple private L2 caches. Instead of maintaining separate L2 caches for every core, multiple cores can access a common cache.

However, once multiple cores and multiple L1 caches share the same L2 cache, the L2 cache needs to handle multiple requests and potentially multiple outstanding misses.

**This is another reason why a non-blocking L2 cache becomes important.**

So, whether we look at a high-performance architecture such as the **AMD MI300A** or a mobile SoC such as the **Snapdragon 730G**, the same fundamental idea appears:

> **As computational capability increases, the memory system must become capable of keeping the processor supplied with data.**

That is the motivation behind my design of a **non-blocking L2 cache**.

---
---
# How Does My Cache Architecture Work?

<img src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAs0AAAQmCAYAAADLHIL6AABYI3RFWHRteGZpbGUAJTNDbXhmaWxlJTNFJTBBJTIwJTIwJTNDZGlhZ3JhbSUyMGlkJTNEJTIyR3VxYng2eTRFel9NMW1pc3NqQkclMjIlMjBuYW1lJTNEJTIyUGFnZS0xJTIyJTNFJTBBJTIwJTIwJTIwJTIwJTNDbXhHcmFwaE1vZGVsJTIwZHglM0QlMjIxMjkzJTIyJTIwZHklM0QlMjIyMTczJTIyJTIwZ3JpZCUzRCUyMjElMjIlMjBncmlkU2l6ZSUzRCUyMjEwJTIyJTIwZ3VpZGVzJTNEJTIyMSUyMiUyMHRvb2x0aXBzJTNEJTIyMSUyMiUyMGNvbm5lY3QlM0QlMjIxJTIyJTIwYXJyb3dzJTNEJTIyMSUyMiUyMGZvbGQlM0QlMjIxJTIyJTIwcGFnZSUzRCUyMjElMjIlMjBwYWdlU2NhbGUlM0QlMjIxJTIyJTIwcGFnZVdpZHRoJTNEJTIyODUwJTIyJTIwcGFnZUhlaWdodCUzRCUyMjExMDAlMjIlMjBiYWNrZ3JvdW5kJTNEJTIyJTIzQjNGRjFFJTIyJTIwbWF0aCUzRCUyMjAlMjIlMjBzaGFkb3clM0QlMjIwJTIyJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTNDcm9vdCUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214Q2VsbCUyMGlkJTNEJTIyMCUyMiUyMCUyRiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214Q2VsbCUyMGlkJTNEJTIyMSUyMiUyMHBhcmVudCUzRCUyMjAlMjIlMjAlMkYlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0NteENlbGwlMjBpZCUzRCUyMjU0JTIyJTIwcGFyZW50JTNEJTIyMSUyMiUyMHN0eWxlJTNEJTIyd2hpdGVTcGFjZSUzRHdyYXAlM0JodG1sJTNEMSUzQmZpbGxDb2xvciUzRCUyM0U2RTZFNiUzQiUyMiUyMHZhbHVlJTNEJTIyJTIyJTIwdmVydGV4JTNEJTIyMSUyMiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214R2VvbWV0cnklMjBoZWlnaHQlM0QlMjI0ODAlMjIlMjB3aWR0aCUzRCUyMjQ0MCUyMiUyMHglM0QlMjIzMDUlMjIlMjB5JTNEJTIyNDMwJTIyJTIwYXMlM0QlMjJnZW9tZXRyeSUyMiUyMCUyRiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQyUyRm14Q2VsbCUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214Q2VsbCUyMGlkJTNEJTIyNTIlMjIlMjBlZGdlJTNEJTIyMSUyMiUyMHBhcmVudCUzRCUyMjElMjIlMjBzb3VyY2UlM0QlMjIyJTIyJTIwc3R5bGUlM0QlMjJlZGdlU3R5bGUlM0Rub25lJTNCc2hhcGUlM0RmbGV4QXJyb3clM0JodG1sJTNEMSUzQmV4aXRYJTNEMSUzQmV4aXRZJTNEMC43NSUzQmV4aXREeCUzRDAlM0JleGl0RHklM0QwJTNCZW50cnlYJTNEMCUzQmVudHJ5WSUzRDAuNzUlM0JlbnRyeUR4JTNEMCUzQmVudHJ5RHklM0QwJTNCZmlsbENvbG9yJTNEJTIzMzMwMDAwJTNCJTIyJTIwdGFyZ2V0JTNEJTIyMyUyMiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214R2VvbWV0cnklMjByZWxhdGl2ZSUzRCUyMjElMjIlMjBhcyUzRCUyMmdlb21ldHJ5JTIyJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDQXJyYXklMjBhcyUzRCUyMnBvaW50cyUyMiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214UG9pbnQlMjB4JTNEJTIyMjYwJTIyJTIweSUzRCUyMjgwMCUyMiUyMCUyRiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214UG9pbnQlMjB4JTNEJTIyMzEwJTIyJTIweSUzRCUyMjgzMCUyMiUyMCUyRiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQyUyRkFycmF5JTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDJTJGbXhHZW9tZXRyeSUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQyUyRm14Q2VsbCUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214Q2VsbCUyMGlkJTNEJTIyMiUyMiUyMHBhcmVudCUzRCUyMjElMjIlMjBzdHlsZSUzRCUyMndoaXRlU3BhY2UlM0R3cmFwJTNCaHRtbCUzRDElM0JmaWxsQ29sb3IlM0QlMjNDQ0NDQ0MlM0IlMjIlMjB2YWx1ZSUzRCUyMiUyNmx0JTNCZm9udCUyMHNpemUlM0QlMjZxdW90JTNCMyUyNnF1b3QlM0IlMjZndCUzQm1lbW9yeSUyMHdpdGglMjB2ZXJpYWJsZSUyMGxhdGVuY3klMjZhbXAlM0JuYnNwJTNCJTI2bHQlM0IlMkZmb250JTI2Z3QlM0IlMjIlMjB2ZXJ0ZXglM0QlMjIxJTIyJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhHZW9tZXRyeSUyMGhlaWdodCUzRCUyMjIxMCUyMiUyMHdpZHRoJTNEJTIyMTYwJTIyJTIweCUzRCUyMjQwJTIyJTIweSUzRCUyMjY0MCUyMiUyMGFzJTNEJTIyZ2VvbWV0cnklMjIlMjAlMkYlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0MlMkZteENlbGwlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0NteENlbGwlMjBpZCUzRCUyMjUwJTIyJTIwZWRnZSUzRCUyMjElMjIlMjBwYXJlbnQlM0QlMjIxJTIyJTIwc291cmNlJTNEJTIyMyUyMiUyMHN0eWxlJTNEJTIyZWRnZVN0eWxlJTNEbm9uZSUzQnNoYXBlJTNEZmxleEFycm93JTNCaHRtbCUzRDElM0JleGl0WCUzRDAuNjA2JTNCZXhpdFklM0QwLjAwNyUzQmV4aXREeCUzRDAlM0JleGl0RHklM0QwJTNCZW50cnlYJTNEMC43NSUzQmVudHJ5WSUzRDElM0JlbnRyeUR4JTNEMCUzQmVudHJ5RHklM0QwJTNCZXhpdFBlcmltZXRlciUzRDAlM0JmaWxsQ29sb3IlM0QlMjMzMzAwMDAlM0IlMjIlMjB0YXJnZXQlM0QlMjI0NSUyMiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214R2VvbWV0cnklMjByZWxhdGl2ZSUzRCUyMjElMjIlMjBhcyUzRCUyMmdlb21ldHJ5JTIyJTIwJTJGJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDJTJGbXhDZWxsJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhDZWxsJTIwaWQlM0QlMjI1MyUyMiUyMGVkZ2UlM0QlMjIxJTIyJTIwcGFyZW50JTNEJTIyMSUyMiUyMHNvdXJjZSUzRCUyMjMlMjIlMjBzdHlsZSUzRCUyMmVkZ2VTdHlsZSUzRG5vbmUlM0JzaGFwZSUzRGZsZXhBcnJvdyUzQmh0bWwlM0QxJTNCZXhpdFglM0QwJTNCZXhpdFklM0QwLjI1JTNCZXhpdER4JTNEMCUzQmV4aXREeSUzRDAlM0JlbnRyeVglM0QxJTNCZW50cnlZJTNEMC4yNSUzQmVudHJ5RHglM0QwJTNCZW50cnlEeSUzRDAlM0JmaWxsQ29sb3IlM0QlMjMzMzAwMDAlM0IlMjIlMjB0YXJnZXQlM0QlMjIyJTIyJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhHZW9tZXRyeSUyMHJlbGF0aXZlJTNEJTIyMSUyMiUyMGFzJTNEJTIyZ2VvbWV0cnklMjIlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0NBcnJheSUyMGFzJTNEJTIycG9pbnRzJTIyJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhQb2ludCUyMHglM0QlMjIzMjAlMjIlMjB5JTNEJTIyNzU4JTIyJTIwJTJGJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhQb2ludCUyMHglM0QlMjIyNjAlMjIlMjB5JTNEJTIyNjkzJTIyJTIwJTJGJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDJTJGQXJyYXklM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0MlMkZteEdlb21ldHJ5JTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDJTJGbXhDZWxsJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhDZWxsJTIwaWQlM0QlMjIzJTIyJTIwcGFyZW50JTNEJTIyMSUyMiUyMHN0eWxlJTNEJTIyd2hpdGVTcGFjZSUzRHdyYXAlM0JodG1sJTNEMSUzQmZpbGxDb2xvciUzRCUyM0NDQ0NDQyUzQiUyMiUyMHZhbHVlJTNEJTIyJTI2bHQlM0Jmb250JTIwc3R5bGUlM0QlMjZxdW90JTNCZm9udC1zaXplJTNBJTIwMThweCUzQiUyNnF1b3QlM0IlMjZndCUzQjQlMjB3YXklMjBzZXQlMjBhc3NvY2lhdGl2ZSUyME5PTl9CTE9DS0lORyUyMGNhY2hlJTIwbWVtb3J5JTIwTDIlMjBNRU1PUlklMjZhbXAlM0JuYnNwJTNCJTI2YW1wJTNCbmJzcCUzQiUyNmx0JTNCJTJGZm9udCUyNmd0JTNCJTIyJTIwdmVydGV4JTNEJTIyMSUyMiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214R2VvbWV0cnklMjBoZWlnaHQlM0QlMjIxNTAlMjIlMjB3aWR0aCUzRCUyMjI4MCUyMiUyMHglM0QlMjIzNzAlMjIlMjB5JTNEJTIyNzIwJTIyJTIwYXMlM0QlMjJnZW9tZXRyeSUyMiUyMCUyRiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQyUyRm14Q2VsbCUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214Q2VsbCUyMGlkJTNEJTIyMjAlMjIlMjBlZGdlJTNEJTIyMSUyMiUyMHBhcmVudCUzRCUyMjElMjIlMjBzb3VyY2UlM0QlMjI1JTIyJTIwc3R5bGUlM0QlMjJlZGdlU3R5bGUlM0Rub25lJTNCc2hhcGUlM0RmbGV4QXJyb3clM0JodG1sJTNEMSUzQmV4aXRYJTNEMC43NSUzQmV4aXRZJTNEMSUzQmV4aXREeCUzRDAlM0JleGl0RHklM0QwJTNCZW50cnlYJTNEMCUzQmVudHJ5WSUzRDAuMjUlM0JlbnRyeUR4JTNEMCUzQmVudHJ5RHklM0QwJTNCd2lkdGglM0Q5LjU4OTA0MTA5NTg5MDQxMiUzQmVuZFNpemUlM0QzLjI5ODYzMDEzNjk4NjMwMSUzQmVuZFdpZHRoJTNEOS45MTkzMDk0Mzg5MTkxMjIlM0JmaWxsQ29sb3IlM0QlMjMzMzAwMDAlM0IlMjIlMjB0YXJnZXQlM0QlMjIxNiUyMiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214R2VvbWV0cnklMjByZWxhdGl2ZSUzRCUyMjElMjIlMjBhcyUzRCUyMmdlb21ldHJ5JTIyJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDQXJyYXklMjBhcyUzRCUyMnBvaW50cyUyMiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214UG9pbnQlMjB4JTNEJTIyMzkwJTIyJTIweSUzRCUyMjI3NSUyMiUyMCUyRiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQyUyRkFycmF5JTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDJTJGbXhHZW9tZXRyeSUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQyUyRm14Q2VsbCUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214Q2VsbCUyMGlkJTNEJTIyMjIlMjIlMjBlZGdlJTNEJTIyMSUyMiUyMHBhcmVudCUzRCUyMjElMjIlMjBzb3VyY2UlM0QlMjI1JTIyJTIwc3R5bGUlM0QlMjJlZGdlU3R5bGUlM0Rub25lJTNCc2hhcGUlM0RmbGV4QXJyb3clM0JodG1sJTNEMSUzQmV4aXRYJTNEMSUzQmV4aXRZJTNEMC4yNSUzQmV4aXREeCUzRDAlM0JleGl0RHklM0QwJTNCZW50cnlYJTNEMCUzQmVudHJ5WSUzRDAuMjUlM0JlbnRyeUR4JTNEMCUzQmVudHJ5RHklM0QwJTNCd2lkdGglM0Q5LjE2NjY2NjY2NjY2NjY2OCUzQmVuZFNpemUlM0QzLjUwNDE2NjY2NjY2NjY2NyUzQmVuZFdpZHRoJTNEMTEuMDA2OTQ0NDQ0NDQ0NDQ1JTNCZmlsbENvbG9yJTNEJTIzMzMwMDAwJTNCJTIyJTIwdGFyZ2V0JTNEJTIyMTclMjIlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0NteEdlb21ldHJ5JTIwcmVsYXRpdmUlM0QlMjIxJTIyJTIwYXMlM0QlMjJnZW9tZXRyeSUyMiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ0FycmF5JTIwYXMlM0QlMjJwb2ludHMlMjIlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0NteFBvaW50JTIweCUzRCUyMjUzMCUyMiUyMHklM0QlMjI4MCUyMiUyMCUyRiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214UG9pbnQlMjB4JTNEJTIyNTMwJTIyJTIweSUzRCUyMjI3NSUyMiUyMCUyRiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQyUyRkFycmF5JTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDJTJGbXhHZW9tZXRyeSUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQyUyRm14Q2VsbCUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214Q2VsbCUyMGlkJTNEJTIyMjUlMjIlMjBlZGdlJTNEJTIyMSUyMiUyMHBhcmVudCUzRCUyMjElMjIlMjBzb3VyY2UlM0QlMjI1JTIyJTIwc3R5bGUlM0QlMjJlZGdlU3R5bGUlM0Rub25lJTNCc2hhcGUlM0RmbGV4QXJyb3clM0JodG1sJTNEMSUzQmV4aXRYJTNEMC4yNSUzQmV4aXRZJTNEMCUzQmV4aXREeCUzRDAlM0JleGl0RHklM0QwJTNCZW50cnlYJTNEMCUzQmVudHJ5WSUzRDAuMjUlM0JlbnRyeUR4JTNEMCUzQmVudHJ5RHklM0QwJTNCZmlsbENvbG9yJTNEJTIzMzMwMDAwJTNCJTIyJTIwdGFyZ2V0JTNEJTIyMjMlMjIlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0NteEdlb21ldHJ5JTIwcmVsYXRpdmUlM0QlMjIxJTIyJTIwYXMlM0QlMjJnZW9tZXRyeSUyMiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ0FycmF5JTIwYXMlM0QlMjJwb2ludHMlMjIlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0NteFBvaW50JTIweCUzRCUyMjMzMCUyMiUyMHklM0QlMjItMjAlMjIlMjAlMkYlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0NteFBvaW50JTIweCUzRCUyMjUyMCUyMiUyMHklM0QlMjItMjAlMjIlMjAlMkYlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0NteFBvaW50JTIweCUzRCUyMjU5MCUyMiUyMHklM0QlMjI1MiUyMiUyMCUyRiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQyUyRkFycmF5JTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDJTJGbXhHZW9tZXRyeSUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQyUyRm14Q2VsbCUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214Q2VsbCUyMGlkJTNEJTIyMjklMjIlMjBlZGdlJTNEJTIyMSUyMiUyMHBhcmVudCUzRCUyMjElMjIlMjBzb3VyY2UlM0QlMjI1JTIyJTIwc3R5bGUlM0QlMjJlZGdlU3R5bGUlM0Rub25lJTNCc2hhcGUlM0RmbGV4QXJyb3clM0JodG1sJTNEMSUzQmV4aXRYJTNEMCUzQmV4aXRZJTNEMCUzQmV4aXREeCUzRDAlM0JleGl0RHklM0QwJTNCZmlsbENvbG9yJTNEJTIzMzMwMDAwJTNCJTIyJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhHZW9tZXRyeSUyMHJlbGF0aXZlJTNEJTIyMSUyMiUyMGFzJTNEJTIyZ2VvbWV0cnklMjIlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0NteFBvaW50JTIweCUzRCUyMjI1MCUyMiUyMHklM0QlMjI0OS44OTY1NTE3MjQxMzc5MSUyMiUyMGFzJTNEJTIydGFyZ2V0UG9pbnQlMjIlMjAlMkYlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0MlMkZteEdlb21ldHJ5JTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDJTJGbXhDZWxsJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhDZWxsJTIwaWQlM0QlMjIzMSUyMiUyMGVkZ2UlM0QlMjIxJTIyJTIwcGFyZW50JTNEJTIyMSUyMiUyMHNvdXJjZSUzRCUyMjUlMjIlMjBzdHlsZSUzRCUyMmVkZ2VTdHlsZSUzRG5vbmUlM0JzaGFwZSUzRGZsZXhBcnJvdyUzQmh0bWwlM0QxJTNCZXhpdFglM0QwJTNCZXhpdFklM0QwLjc1JTNCZXhpdER4JTNEMCUzQmV4aXREeSUzRDAlM0JlbnRyeVglM0QxJTNCZW50cnlZJTNEMC43NSUzQmVudHJ5RHglM0QwJTNCZW50cnlEeSUzRDAlM0JmaWxsQ29sb3IlM0QlMjMzMzAwMDAlM0IlMjIlMjB0YXJnZXQlM0QlMjIyOCUyMiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214R2VvbWV0cnklMjByZWxhdGl2ZSUzRCUyMjElMjIlMjBhcyUzRCUyMmdlb21ldHJ5JTIyJTIwJTJGJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDJTJGbXhDZWxsJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhDZWxsJTIwaWQlM0QlMjI1JTIyJTIwcGFyZW50JTNEJTIyMSUyMiUyMHN0eWxlJTNEJTIyd2hpdGVTcGFjZSUzRHdyYXAlM0JodG1sJTNEMSUzQmZpbGxDb2xvciUzRCUyM0NDQ0NDQyUzQiUyMiUyMHZhbHVlJTNEJTIybWVtb3J5JTIwbWFuYWdlbWVudCUyMHVuaXQlMjZhbXAlM0JuYnNwJTNCJTIyJTIwdmVydGV4JTNEJTIyMSUyMiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214R2VvbWV0cnklMjBoZWlnaHQlM0QlMjIxMTAlMjIlMjB3aWR0aCUzRCUyMjEyMCUyMiUyMHglM0QlMjIzMDAlMjIlMjB5JTNEJTIyNTAlMjIlMjBhcyUzRCUyMmdlb21ldHJ5JTIyJTIwJTJGJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDJTJGbXhDZWxsJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhDZWxsJTIwaWQlM0QlMjIzNiUyMiUyMGVkZ2UlM0QlMjIxJTIyJTIwcGFyZW50JTNEJTIyMSUyMiUyMHNvdXJjZSUzRCUyMjE2JTIyJTIwc3R5bGUlM0QlMjJlZGdlU3R5bGUlM0Rub25lJTNCc2hhcGUlM0RmbGV4QXJyb3clM0JodG1sJTNEMSUzQmV4aXRYJTNEMC4yNSUzQmV4aXRZJTNEMSUzQmV4aXREeCUzRDAlM0JleGl0RHklM0QwJTNCZW50cnlYJTNEMCUzQmVudHJ5WSUzRDAuNSUzQmVudHJ5RHglM0QwJTNCZW50cnlEeSUzRDAlM0JmaWxsQ29sb3IlM0QlMjMzMzAwMDAlM0IlMjIlMjB0YXJnZXQlM0QlMjIzNSUyMiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214R2VvbWV0cnklMjByZWxhdGl2ZSUzRCUyMjElMjIlMjBhcyUzRCUyMmdlb21ldHJ5JTIyJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDQXJyYXklMjBhcyUzRCUyMnBvaW50cyUyMiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214UG9pbnQlMjB4JTNEJTIyNDMzJTIyJTIweSUzRCUyMjQ0MCUyMiUyMCUyRiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214UG9pbnQlMjB4JTNEJTIyMzgwJTIyJTIweSUzRCUyMjQ0MCUyMiUyMCUyRiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214UG9pbnQlMjB4JTNEJTIyMzgwJTIyJTIweSUzRCUyMjQ5MCUyMiUyMCUyRiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQyUyRkFycmF5JTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDJTJGbXhHZW9tZXRyeSUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQyUyRm14Q2VsbCUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214Q2VsbCUyMGlkJTNEJTIyMTYlMjIlMjBwYXJlbnQlM0QlMjIxJTIyJTIwc3R5bGUlM0QlMjJ3aGl0ZVNwYWNlJTNEd3JhcCUzQmh0bWwlM0QxJTNCZmlsbENvbG9yJTNEJTIzQjNCM0IzJTNCJTIyJTIwdmFsdWUlM0QlMjJpbnN0cnVjdGlvbiUyNmFtcCUzQm5ic3AlM0IlMjZsdCUzQmRpdiUyNmd0JTNCbWVtb3J5JTI2YW1wJTNCbmJzcCUzQiUyNmx0JTNCJTJGZGl2JTI2Z3QlM0IlMjIlMjB2ZXJ0ZXglM0QlMjIxJTIyJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhHZW9tZXRyeSUyMGhlaWdodCUzRCUyMjE4MCUyMiUyMHdpZHRoJTNEJTIyOTAlMjIlMjB4JTNEJTIyNDEwJTIyJTIweSUzRCUyMjIzMCUyMiUyMGFzJTNEJTIyZ2VvbWV0cnklMjIlMjAlMkYlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0MlMkZteENlbGwlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0NteENlbGwlMjBpZCUzRCUyMjIxJTIyJTIwZWRnZSUzRCUyMjElMjIlMjBwYXJlbnQlM0QlMjIxJTIyJTIwc291cmNlJTNEJTIyMTclMjIlMjBzdHlsZSUzRCUyMmVkZ2VTdHlsZSUzRG5vbmUlM0JzaGFwZSUzRGZsZXhBcnJvdyUzQmh0bWwlM0QxJTNCZXhpdFglM0QwJTNCZXhpdFklM0QwLjc1JTNCZXhpdER4JTNEMCUzQmV4aXREeSUzRDAlM0JlbnRyeVglM0QxJTNCZW50cnlZJTNEMC43NSUzQmVudHJ5RHglM0QwJTNCZW50cnlEeSUzRDAlM0JmaWxsQ29sb3IlM0QlMjMzMzAwMDAlM0IlMjIlMjB0YXJnZXQlM0QlMjI1JTIyJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhHZW9tZXRyeSUyMHJlbGF0aXZlJTNEJTIyMSUyMiUyMGFzJTNEJTIyZ2VvbWV0cnklMjIlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0NBcnJheSUyMGFzJTNEJTIycG9pbnRzJTIyJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhQb2ludCUyMHglM0QlMjI1MTAlMjIlMjB5JTNEJTIyMzY1JTIyJTIwJTJGJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhQb2ludCUyMHglM0QlMjI1MTAlMjIlMjB5JTNEJTIyMTMzJTIyJTIwJTJGJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDJTJGQXJyYXklM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0MlMkZteEdlb21ldHJ5JTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDJTJGbXhDZWxsJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhDZWxsJTIwaWQlM0QlMjIzOCUyMiUyMGVkZ2UlM0QlMjIxJTIyJTIwcGFyZW50JTNEJTIyMSUyMiUyMHNvdXJjZSUzRCUyMjE3JTIyJTIwc3R5bGUlM0QlMjJlZGdlU3R5bGUlM0Rub25lJTNCc2hhcGUlM0RmbGV4QXJyb3clM0JodG1sJTNEMSUzQmV4aXRYJTNEMC43NSUzQmV4aXRZJTNEMSUzQmV4aXREeCUzRDAlM0JleGl0RHklM0QwJTNCZW50cnlYJTNEMSUzQmVudHJ5WSUzRDAuNSUzQmVudHJ5RHglM0QwJTNCZW50cnlEeSUzRDAlM0JmaWxsQ29sb3IlM0QlMjMzMzAwMDAlM0IlMjIlMjB0YXJnZXQlM0QlMjIzNSUyMiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214R2VvbWV0cnklMjByZWxhdGl2ZSUzRCUyMjElMjIlMjBhcyUzRCUyMmdlb21ldHJ5JTIyJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDQXJyYXklMjBhcyUzRCUyMnBvaW50cyUyMiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214UG9pbnQlMjB4JTNEJTIyNjE4JTIyJTIweSUzRCUyMjQzMCUyMiUyMCUyRiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214UG9pbnQlMjB4JTNEJTIyNjcwJTIyJTIweSUzRCUyMjQzMCUyMiUyMCUyRiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214UG9pbnQlMjB4JTNEJTIyNjcwJTIyJTIweSUzRCUyMjQ5MCUyMiUyMCUyRiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQyUyRkFycmF5JTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDJTJGbXhHZW9tZXRyeSUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQyUyRm14Q2VsbCUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214Q2VsbCUyMGlkJTNEJTIyMTclMjIlMjBwYXJlbnQlM0QlMjIxJTIyJTIwc3R5bGUlM0QlMjJ3aGl0ZVNwYWNlJTNEd3JhcCUzQmh0bWwlM0QxJTNCZmlsbENvbG9yJTNEJTIzQjNCM0IzJTNCJTIyJTIwdmFsdWUlM0QlMjJkYXRhJTI2bHQlM0JkaXYlMjZndCUzQiUyNmFtcCUzQm5ic3AlM0JtZW1vcnklMjZsdCUzQiUyRmRpdiUyNmd0JTNCJTIyJTIwdmVydGV4JTNEJTIyMSUyMiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214R2VvbWV0cnklMjBoZWlnaHQlM0QlMjIxODAlMjIlMjB3aWR0aCUzRCUyMjkwJTIyJTIweCUzRCUyMjU1MCUyMiUyMHklM0QlMjIyMzAlMjIlMjBhcyUzRCUyMmdlb21ldHJ5JTIyJTIwJTJGJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDJTJGbXhDZWxsJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhDZWxsJTIwaWQlM0QlMjIxOSUyMiUyMGVkZ2UlM0QlMjIxJTIyJTIwcGFyZW50JTNEJTIyMSUyMiUyMHNvdXJjZSUzRCUyMjE2JTIyJTIwc3R5bGUlM0QlMjJlZGdlU3R5bGUlM0Rub25lJTNCc2hhcGUlM0RmbGV4QXJyb3clM0JodG1sJTNEMSUzQmV4aXRYJTNEMCUzQmV4aXRZJTNEMC43NSUzQmV4aXREeCUzRDAlM0JleGl0RHklM0QwJTNCZW50cnlYJTNEMC4yNSUzQmVudHJ5WSUzRDElM0JlbnRyeUR4JTNEMCUzQmVudHJ5RHklM0QwJTNCZmlsbENvbG9yJTNEJTIzMzMwMDAwJTNCJTIyJTIwdGFyZ2V0JTNEJTIyNSUyMiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214R2VvbWV0cnklMjByZWxhdGl2ZSUzRCUyMjElMjIlMjBhcyUzRCUyMmdlb21ldHJ5JTIyJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDQXJyYXklMjBhcyUzRCUyMnBvaW50cyUyMiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214UG9pbnQlMjB4JTNEJTIyMzMwJTIyJTIweSUzRCUyMjM2NSUyMiUyMCUyRiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQyUyRkFycmF5JTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDJTJGbXhHZW9tZXRyeSUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQyUyRm14Q2VsbCUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214Q2VsbCUyMGlkJTNEJTIyMjQlMjIlMjBlZGdlJTNEJTIyMSUyMiUyMHBhcmVudCUzRCUyMjElMjIlMjBzb3VyY2UlM0QlMjIyMyUyMiUyMHN0eWxlJTNEJTIyZWRnZVN0eWxlJTNEbm9uZSUzQnNoYXBlJTNEZmxleEFycm93JTNCaHRtbCUzRDElM0JleGl0WCUzRC0wLjAxMSUzQmV4aXRZJTNEMC43NyUzQmV4aXREeCUzRDAlM0JleGl0RHklM0QwJTNCZW50cnlYJTNEMC43NSUzQmVudHJ5WSUzRDAlM0JlbnRyeUR4JTNEMCUzQmVudHJ5RHklM0QwJTNCZXhpdFBlcmltZXRlciUzRDAlM0JmaWxsQ29sb3IlM0QlMjMzMzAwMDAlM0IlMjIlMjB0YXJnZXQlM0QlMjI1JTIyJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhHZW9tZXRyeSUyMHJlbGF0aXZlJTNEJTIyMSUyMiUyMGFzJTNEJTIyZ2VvbWV0cnklMjIlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0NBcnJheSUyMGFzJTNEJTIycG9pbnRzJTIyJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhQb2ludCUyMHglM0QlMjI2MTAlMjIlMjB5JTNEJTIyMTIwJTIyJTIwJTJGJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhQb2ludCUyMHglM0QlMjI1NzAlMjIlMjB5JTNEJTIyODAlMjIlMjAlMkYlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0NteFBvaW50JTIweCUzRCUyMjUxMCUyMiUyMHklM0QlMjIyMCUyMiUyMCUyRiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214UG9pbnQlMjB4JTNEJTIyMzkwJTIyJTIweSUzRCUyMjIwJTIyJTIwJTJGJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDJTJGQXJyYXklM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0MlMkZteEdlb21ldHJ5JTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDJTJGbXhDZWxsJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhDZWxsJTIwaWQlM0QlMjIyMyUyMiUyMHBhcmVudCUzRCUyMjElMjIlMjBzdHlsZSUzRCUyMndoaXRlU3BhY2UlM0R3cmFwJTNCaHRtbCUzRDElM0JmaWxsQ29sb3IlM0QlMjNCM0IzQjMlM0IlMjIlMjB2YWx1ZSUzRCUyMkklMkZPJTIyJTIwdmVydGV4JTNEJTIyMSUyMiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214R2VvbWV0cnklMjBoZWlnaHQlM0QlMjIxMzAlMjIlMjB3aWR0aCUzRCUyMjYwJTIyJTIweCUzRCUyMjY0MCUyMiUyMHklM0QlMjIyMCUyMiUyMGFzJTNEJTIyZ2VvbWV0cnklMjIlMjAlMkYlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0MlMkZteENlbGwlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0NteENlbGwlMjBpZCUzRCUyMjMyJTIyJTIwZWRnZSUzRCUyMjElMjIlMjBwYXJlbnQlM0QlMjIxJTIyJTIwc291cmNlJTNEJTIyMjglMjIlMjBzdHlsZSUzRCUyMmVkZ2VTdHlsZSUzRG5vbmUlM0JzaGFwZSUzRGZsZXhBcnJvdyUzQmh0bWwlM0QxJTNCZXhpdFglM0QxJTNCZXhpdFklM0QxJTNCZXhpdER4JTNEMCUzQmV4aXREeSUzRDAlM0JmaWxsQ29sb3IlM0QlMjMzMzAwMDAlM0IlMjIlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0NteEdlb21ldHJ5JTIwcmVsYXRpdmUlM0QlMjIxJTIyJTIwYXMlM0QlMjJnZW9tZXRyeSUyMiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214UG9pbnQlMjB4JTNEJTIyMzAwJTIyJTIweSUzRCUyMjE2MC4yNDEzNzkzMTAzNDQ4OCUyMiUyMGFzJTNEJTIydGFyZ2V0UG9pbnQlMjIlMjAlMkYlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0MlMkZteEdlb21ldHJ5JTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDJTJGbXhDZWxsJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhDZWxsJTIwaWQlM0QlMjIyOCUyMiUyMHBhcmVudCUzRCUyMjElMjIlMjBzdHlsZSUzRCUyMndoaXRlU3BhY2UlM0R3cmFwJTNCaHRtbCUzRDElM0JmaWxsQ29sb3IlM0QlMjNDQ0NDQ0MlM0IlMjIlMjB2YWx1ZSUzRCUyMiUyNmx0JTNCZm9udCUyMHN0eWxlJTNEJTI2cXVvdCUzQmZvbnQtc2l6ZSUzQSUyMDM2cHglM0IlMjZxdW90JTNCJTI2Z3QlM0JDUFUlMjZsdCUzQiUyRmZvbnQlMjZndCUzQiUyMiUyMHZlcnRleCUzRCUyMjElMjIlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0NteEdlb21ldHJ5JTIwaGVpZ2h0JTNEJTIyMTEwJTIyJTIwd2lkdGglM0QlMjIxNjAlMjIlMjB4JTNEJTIyOTAlMjIlMjB5JTNEJTIyNTAlMjIlMjBhcyUzRCUyMmdlb21ldHJ5JTIyJTIwJTJGJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDJTJGbXhDZWxsJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhDZWxsJTIwaWQlM0QlMjIzMyUyMiUyMHBhcmVudCUzRCUyMjElMjIlMjBzdHlsZSUzRCUyMnNoYXBlJTNEY2FsbG91dCUzQndoaXRlU3BhY2UlM0R3cmFwJTNCaHRtbCUzRDElM0JwZXJpbWV0ZXIlM0RjYWxsb3V0UGVyaW1ldGVyJTNCcG9zaXRpb24yJTNEMSUzQmZpbGxDb2xvciUzRG5vbmUlM0IlMjIlMjB2YWx1ZSUzRCUyMmluc3RydWN0aW9uJTIwYnVzJTI2YW1wJTNCbmJzcCUzQiUyMiUyMHZlcnRleCUzRCUyMjElMjIlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0NteEdlb21ldHJ5JTIwaGVpZ2h0JTNEJTIyODAlMjIlMjB3aWR0aCUzRCUyMjEyMCUyMiUyMHglM0QlMjIxNDAlMjIlMjB5JTNEJTIyLTMwJTIyJTIwYXMlM0QlMjJnZW9tZXRyeSUyMiUyMCUyRiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQyUyRm14Q2VsbCUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214Q2VsbCUyMGlkJTNEJTIyMzQlMjIlMjBwYXJlbnQlM0QlMjIxJTIyJTIwc3R5bGUlM0QlMjJzaGFwZSUzRGNhbGxvdXQlM0J3aGl0ZVNwYWNlJTNEd3JhcCUzQmh0bWwlM0QxJTNCcGVyaW1ldGVyJTNEY2FsbG91dFBlcmltZXRlciUzQmRpcmVjdGlvbiUzRHdlc3QlM0Jwb3NpdGlvbjIlM0QwJTNCZmlsbENvbG9yJTNEbm9uZSUzQiUyMiUyMHZhbHVlJTNEJTIyZGF0YSUyMGJ1cyUyMHJlYWQlMjBhbmQlMjB3cml0ZSUyNmFtcCUzQm5ic3AlM0IlMjIlMjB2ZXJ0ZXglM0QlMjIxJTIyJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhHZW9tZXRyeSUyMGhlaWdodCUzRCUyMjgwJTIyJTIwd2lkdGglM0QlMjIxMjAlMjIlMjB4JTNEJTIyMTYwJTIyJTIweSUzRCUyMjE3MCUyMiUyMGFzJTNEJTIyZ2VvbWV0cnklMjIlMjAlMkYlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0MlMkZteENlbGwlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0NteENlbGwlMjBpZCUzRCUyMjQwJTIyJTIwZWRnZSUzRCUyMjElMjIlMjBwYXJlbnQlM0QlMjIxJTIyJTIwc291cmNlJTNEJTIyMzUlMjIlMjBzdHlsZSUzRCUyMmVkZ2VTdHlsZSUzRG5vbmUlM0JzaGFwZSUzRGZsZXhBcnJvdyUzQmh0bWwlM0QxJTNCZXhpdFglM0QwLjI4OSUzQmV4aXRZJTNEMC4wMDclM0JleGl0RHglM0QwJTNCZXhpdER5JTNEMCUzQmVudHJ5WCUzRDAuNzUlM0JlbnRyeVklM0QxJTNCZW50cnlEeCUzRDAlM0JlbnRyeUR5JTNEMCUzQmV4aXRQZXJpbWV0ZXIlM0QwJTNCZmlsbENvbG9yJTNEJTIzMzMwMDAwJTNCJTIyJTIwdGFyZ2V0JTNEJTIyMTYlMjIlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0NteEdlb21ldHJ5JTIwcmVsYXRpdmUlM0QlMjIxJTIyJTIwYXMlM0QlMjJnZW9tZXRyeSUyMiUyMCUyRiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQyUyRm14Q2VsbCUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214Q2VsbCUyMGlkJTNEJTIyNDElMjIlMjBlZGdlJTNEJTIyMSUyMiUyMHBhcmVudCUzRCUyMjElMjIlMjBzb3VyY2UlM0QlMjIzNSUyMiUyMHN0eWxlJTNEJTIyZWRnZVN0eWxlJTNEbm9uZSUzQnNoYXBlJTNEZmxleEFycm93JTNCaHRtbCUzRDElM0JleGl0WCUzRDAuNzA5JTNCZXhpdFklM0QwLjAwMiUzQmV4aXREeCUzRDAlM0JleGl0RHklM0QwJTNCZW50cnlYJTNEMC4yNSUzQmVudHJ5WSUzRDElM0JlbnRyeUR4JTNEMCUzQmVudHJ5RHklM0QwJTNCZXhpdFBlcmltZXRlciUzRDAlM0JmaWxsQ29sb3IlM0QlMjMzMzAwMDAlM0IlMjIlMjB0YXJnZXQlM0QlMjIxNyUyMiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214R2VvbWV0cnklMjByZWxhdGl2ZSUzRCUyMjElMjIlMjBhcyUzRCUyMmdlb21ldHJ5JTIyJTIwJTJGJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDJTJGbXhDZWxsJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhDZWxsJTIwaWQlM0QlMjI0OCUyMiUyMGVkZ2UlM0QlMjIxJTIyJTIwcGFyZW50JTNEJTIyMSUyMiUyMHNvdXJjZSUzRCUyMjM1JTIyJTIwc3R5bGUlM0QlMjJlZGdlU3R5bGUlM0Rub25lJTNCc2hhcGUlM0RmbGV4QXJyb3clM0JodG1sJTNEMSUzQmV4aXRYJTNEMC41NjElM0JleGl0WSUzRDElM0JleGl0RHglM0QwJTNCZXhpdER5JTNEMCUzQmVudHJ5WCUzRDAuNzUlM0JlbnRyeVklM0QwJTNCZW50cnlEeCUzRDAlM0JlbnRyeUR5JTNEMCUzQmV4aXRQZXJpbWV0ZXIlM0QwJTNCZmlsbENvbG9yJTNEJTIzMzMwMDAwJTNCJTIyJTIwdGFyZ2V0JTNEJTIyNDYlMjIlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0NteEdlb21ldHJ5JTIwcmVsYXRpdmUlM0QlMjIxJTIyJTIwYXMlM0QlMjJnZW9tZXRyeSUyMiUyMCUyRiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQyUyRm14Q2VsbCUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214Q2VsbCUyMGlkJTNEJTIyMzUlMjIlMjBwYXJlbnQlM0QlMjIxJTIyJTIwc3R5bGUlM0QlMjJ3aGl0ZVNwYWNlJTNEd3JhcCUzQmh0bWwlM0QxJTNCZmlsbENvbG9yJTNEJTIzQjNCM0IzJTNCJTIyJTIwdmFsdWUlM0QlMjJBcmJpdHJhdGlvbiUyMGxvZ2ljJTI2YW1wJTNCbmJzcCUzQiUyMiUyMHZlcnRleCUzRCUyMjElMjIlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0NteEdlb21ldHJ5JTIwaGVpZ2h0JTNEJTIyNjAlMjIlMjB3aWR0aCUzRCUyMjIzMCUyMiUyMHglM0QlMjI0MTAlMjIlMjB5JTNEJTIyNDYwJTIyJTIwYXMlM0QlMjJnZW9tZXRyeSUyMiUyMCUyRiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQyUyRm14Q2VsbCUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214Q2VsbCUyMGlkJTNEJTIyNDIlMjIlMjBwYXJlbnQlM0QlMjIxJTIyJTIwc3R5bGUlM0QlMjJ3aGl0ZVNwYWNlJTNEd3JhcCUzQmh0bWwlM0QxJTNCZmlsbENvbG9yJTNEJTIzQjNCM0IzJTNCJTIyJTIwdmFsdWUlM0QlMjIlMjIlMjB2ZXJ0ZXglM0QlMjIxJTIyJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhHZW9tZXRyeSUyMGhlaWdodCUzRCUyMjIwJTIyJTIwd2lkdGglM0QlMjIxMjAlMjIlMjB4JTNEJTIyNDUwJTIyJTIweSUzRCUyMjU5MCUyMiUyMGFzJTNEJTIyZ2VvbWV0cnklMjIlMjAlMkYlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0MlMkZteENlbGwlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0NteENlbGwlMjBpZCUzRCUyMjQzJTIyJTIwcGFyZW50JTNEJTIyMSUyMiUyMHN0eWxlJTNEJTIyd2hpdGVTcGFjZSUzRHdyYXAlM0JodG1sJTNEMSUzQmZpbGxDb2xvciUzRCUyM0IzQjNCMyUzQiUyMiUyMHZhbHVlJTNEJTIyJTIyJTIwdmVydGV4JTNEJTIyMSUyMiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214R2VvbWV0cnklMjBoZWlnaHQlM0QlMjIyMCUyMiUyMHdpZHRoJTNEJTIyMTIwJTIyJTIweCUzRCUyMjQ1MCUyMiUyMHklM0QlMjI2MTAlMjIlMjBhcyUzRCUyMmdlb21ldHJ5JTIyJTIwJTJGJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDJTJGbXhDZWxsJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhDZWxsJTIwaWQlM0QlMjI0NCUyMiUyMHBhcmVudCUzRCUyMjElMjIlMjBzdHlsZSUzRCUyMndoaXRlU3BhY2UlM0R3cmFwJTNCaHRtbCUzRDElM0JmaWxsQ29sb3IlM0QlMjNCM0IzQjMlM0IlMjIlMjB2YWx1ZSUzRCUyMiUyMiUyMHZlcnRleCUzRCUyMjElMjIlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0NteEdlb21ldHJ5JTIwaGVpZ2h0JTNEJTIyMjAlMjIlMjB3aWR0aCUzRCUyMjEyMCUyMiUyMHglM0QlMjI0NTAlMjIlMjB5JTNEJTIyNjMwJTIyJTIwYXMlM0QlMjJnZW9tZXRyeSUyMiUyMCUyRiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQyUyRm14Q2VsbCUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214Q2VsbCUyMGlkJTNEJTIyNDUlMjIlMjBwYXJlbnQlM0QlMjIxJTIyJTIwc3R5bGUlM0QlMjJ3aGl0ZVNwYWNlJTNEd3JhcCUzQmh0bWwlM0QxJTNCZmlsbENvbG9yJTNEJTIzQjNCM0IzJTNCJTIyJTIwdmFsdWUlM0QlMjIlMjIlMjB2ZXJ0ZXglM0QlMjIxJTIyJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhHZW9tZXRyeSUyMGhlaWdodCUzRCUyMjIwJTIyJTIwd2lkdGglM0QlMjIxMjAlMjIlMjB4JTNEJTIyNDUwJTIyJTIweSUzRCUyMjY1MCUyMiUyMGFzJTNEJTIyZ2VvbWV0cnklMjIlMjAlMkYlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0MlMkZteENlbGwlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0NteENlbGwlMjBpZCUzRCUyMjQ3JTIyJTIwZWRnZSUzRCUyMjElMjIlMjBwYXJlbnQlM0QlMjIxJTIyJTIwc291cmNlJTNEJTIyNDYlMjIlMjBzdHlsZSUzRCUyMmVkZ2VTdHlsZSUzRG5vbmUlM0JzaGFwZSUzRGZsZXhBcnJvdyUzQmh0bWwlM0QxJTNCZXhpdFglM0QwLjE0MSUzQmV4aXRZJTNEMC4wMDklM0JleGl0RHglM0QwJTNCZXhpdER5JTNEMCUzQmVudHJ5WCUzRDAuMjUlM0JlbnRyeVklM0QxJTNCZW50cnlEeCUzRDAlM0JlbnRyeUR5JTNEMCUzQmV4aXRQZXJpbWV0ZXIlM0QwJTNCZmlsbENvbG9yJTNEJTIzMzMwMDAwJTNCJTIyJTIwdGFyZ2V0JTNEJTIyMzUlMjIlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0NteEdlb21ldHJ5JTIwcmVsYXRpdmUlM0QlMjIxJTIyJTIwYXMlM0QlMjJnZW9tZXRyeSUyMiUyMCUyRiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQyUyRm14Q2VsbCUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214Q2VsbCUyMGlkJTNEJTIyNDYlMjIlMjBwYXJlbnQlM0QlMjIxJTIyJTIwc3R5bGUlM0QlMjJ3aGl0ZVNwYWNlJTNEd3JhcCUzQmh0bWwlM0QxJTNCZmlsbENvbG9yJTNEJTIzQjNCM0IzJTNCJTIyJTIwdmFsdWUlM0QlMjIlMjIlMjB2ZXJ0ZXglM0QlMjIxJTIyJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhHZW9tZXRyeSUyMGhlaWdodCUzRCUyMjIwJTIyJTIwd2lkdGglM0QlMjIxMjAlMjIlMjB4JTNEJTIyNDUwJTIyJTIweSUzRCUyMjU3MCUyMiUyMGFzJTNEJTIyZ2VvbWV0cnklMjIlMjAlMkYlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0MlMkZteENlbGwlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0NteENlbGwlMjBpZCUzRCUyMjQ5JTIyJTIwZWRnZSUzRCUyMjElMjIlMjBwYXJlbnQlM0QlMjIxJTIyJTIwc291cmNlJTNEJTIyNDUlMjIlMjBzdHlsZSUzRCUyMmVkZ2VTdHlsZSUzRG5vbmUlM0JzaGFwZSUzRGZsZXhBcnJvdyUzQmh0bWwlM0QxJTNCZXhpdFglM0QwLjI1JTNCZXhpdFklM0QxJTNCZXhpdER4JTNEMCUzQmV4aXREeSUzRDAlM0JmaWxsQ29sb3IlM0QlMjMzMzAwMDAlM0IlMjIlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0NteEdlb21ldHJ5JTIwcmVsYXRpdmUlM0QlMjIxJTIyJTIwYXMlM0QlMjJnZW9tZXRyeSUyMiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214UG9pbnQlMjB4JTNEJTIyNDgwJTIyJTIweSUzRCUyMjcyMCUyMiUyMGFzJTNEJTIydGFyZ2V0UG9pbnQlMjIlMjAlMkYlM0UlMEElMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlMjAlM0MlMkZteEdlb21ldHJ5JTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDJTJGbXhDZWxsJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDbXhDZWxsJTIwaWQlM0QlMjI1MSUyMiUyMHBhcmVudCUzRCUyMjElMjIlMjBzdHlsZSUzRCUyMnNoYXBlJTNEY2FsbG91dCUzQndoaXRlU3BhY2UlM0R3cmFwJTNCaHRtbCUzRDElM0JwZXJpbWV0ZXIlM0RjYWxsb3V0UGVyaW1ldGVyJTNCcG9zaXRpb24yJTNEMC4yMSUzQmRpcmVjdGlvbiUzRHNvdXRoJTNCZmlsbENvbG9yJTNEbm9uZSUzQiUyMiUyMHZhbHVlJTNEJTIyQlVGRkVSJTIwRk9SJTIwQ0RDJTIwQU5EJTI2YW1wJTNCbmJzcCUzQiUyMEZMT1clMjBDT05UUk9MJTIyJTIwdmVydGV4JTNEJTIyMSUyMiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214R2VvbWV0cnklMjBoZWlnaHQlM0QlMjIxNDUlMjIlMjB3aWR0aCUzRCUyMjEyNSUyMiUyMHglM0QlMjI1NzAlMjIlMjB5JTNEJTIyNTYwJTIyJTIwYXMlM0QlMjJnZW9tZXRyeSUyMiUyMCUyRiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQyUyRm14Q2VsbCUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214Q2VsbCUyMGlkJTNEJTIyNTUlMjIlMjBwYXJlbnQlM0QlMjIxJTIyJTIwc3R5bGUlM0QlMjJzaGFwZSUzRGNhbGxvdXQlM0J3aGl0ZVNwYWNlJTNEd3JhcCUzQmh0bWwlM0QxJTNCcGVyaW1ldGVyJTNEY2FsbG91dFBlcmltZXRlciUzQnBvc2l0aW9uMiUzRDElM0JkaXJlY3Rpb24lM0Rub3J0aCUzQmZpbGxDb2xvciUzRG5vbmUlM0IlMjIlMjB2YWx1ZSUzRCUyMlRISVMlMjBJUyUyMFRIRSUyMFBBUlQlMjBJJTIwQU0lMjBERVNJR05JTkclMjZhbXAlM0JuYnNwJTNCJTIyJTIwdmVydGV4JTNEJTIyMSUyMiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214R2VvbWV0cnklMjBoZWlnaHQlM0QlMjIxNDAlMjIlMjB3aWR0aCUzRCUyMjE3NSUyMiUyMHglM0QlMjIxMzAlMjIlMjB5JTNEJTIyNDUwJTIyJTIwYXMlM0QlMjJnZW9tZXRyeSUyMiUyMCUyRiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQyUyRm14Q2VsbCUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214Q2VsbCUyMGlkJTNEJTIyNTglMjIlMjBwYXJlbnQlM0QlMjIxJTIyJTIwc3R5bGUlM0QlMjJ3aGl0ZVNwYWNlJTNEd3JhcCUzQmh0bWwlM0QxJTNCZmlsbENvbG9yJTNEJTIzQjNCM0IzJTNCJTIyJTIwdmFsdWUlM0QlMjIlMjZsdCUzQmZvbnQlMjBzdHlsZSUzRCUyNnF1b3QlM0Jmb250LXNpemUlM0ElMjAyNHB4JTNCJTI2cXVvdCUzQiUyNmd0JTNCUFJPQ0VTU09SJTIwVElMRSUyME9SR0FOSVpBVElPTiUyNmx0JTNCJTJGZm9udCUyNmd0JTNCJTIyJTIwdmVydGV4JTNEJTIyMSUyMiUzRSUwQSUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUyMCUzQ214R2VvbWV0cnklMjBoZWlnaHQlM0QlMjI2MCUyMiUyMHdpZHRoJTNEJTIyNjQwJTIyJTIweCUzRCUyMjcwJTIyJTIweSUzRCUyMi0xNDAlMjIlMjBhcyUzRCUyMmdlb21ldHJ5JTIyJTIwJTJGJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTIwJTNDJTJGbXhDZWxsJTNFJTBBJTIwJTIwJTIwJTIwJTIwJTIwJTNDJTJGcm9vdCUzRSUwQSUyMCUyMCUyMCUyMCUzQyUyRm14R3JhcGhNb2RlbCUzRSUwQSUyMCUyMCUzQyUyRmRpYWdyYW0lM0UlMEElM0MlMkZteGZpbGUlM0UlMEFMtOpqAAAQAElEQVR4AeydB5wURdrGn9mcWXbZBZagopgDJvTM2TNgDhhRz5yzgKIiKioqhjNHzhzOnM54+qlnFhVREUEyyy5h2Zy/ehoah2V2p2cndc88+5t3O1W99da/amaerq7uSXm9fWC7TAzUB9QH1AfUB9QH1AfUB9QH1Ac67wMp0J8IiIAIeJ6AKiACIiACIiAC0SUg0RxdvvIuAiIgAiIgAiIgAs4IKJWrCUg0u7p5FJwIiIAIiIAIiIAIiIAbCEg0u6EVFIMXCChGERABERABERCBJCbgKtH89NgqjNuvRiYG6gPqA+oD6gPqA1HpA/qOlc5wZx+gBnS7HneVaCasdXvui323PUcmBuoD6gPqA+oD6gPqA+oDSdAHqP2oAd1urhPNBDZ06FAko6nOanf1AfUB9QH1AfUB9YFk6wPUfl4wV4pmL4BTjCIgAiIgAgEJaKcIiIAIJCQBieaEbFZVSgREQAREQAREQAREoPsE1swp0bwmE+0RAREQAREQAREQAREQgdUISDSvhkMbIiACXiCgGEVABERABEQg1gQkmmNNXOWJgAiIgAiIgAiIACAGHiMg0eyxBlO4IiACIiACIiACIiACsScg0Rx75irRCwQUowiIgAiIgAiIgAj4EZBo9oOhVREQAREQARFIJAKqiwiIQOQISDRHjqU8iYAIiIAIiIAIiIAIJCgBiea4NawKFgEREAEREAEREAER8AoBiWavtJTiFAEREAE3ElBMIiACIpAkBCSak6ShVU0REAEREAEREAEREIHABJzslWh2QklpREAEREAEREAEREAEkpqARHNSN78qLwJeIKAYRUAEREAERCD+BCSa498GikAEREAEREAERCDRCah+nicg0ez5JlQFREAEREAEREAEREAEok1AojnahOXfCwQUowiIgAiIgAiIgAh0SUCiuUs8OigCIiACIiACXiGgOEVABKJJQKI5mnTlu1MC06dPxxFHHIFhw4Z1akceeSSuuOIKfP3112hra1vNl5P89E0f11xzDb799lu0t7ev5qPjRktLC7766isw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wtDnWxET30scwaYvTm1yMoWE9eO0JcbAk1GO6DK/E+MJINk5SRtuGt4AyM8nlknxGMwf604GTMeRZt4jwfVoWKz6kM/ns35afMiQIdGoRnR9yntSEJBoTopmdl8l+SXG0TYa10ONkHmYl8b1YPl5UxMfr8bpGRS1/BLomIePVuMcyLFjx4LCmmlpFBN8xjGFoM+34su7Y17/bfrhKBhH0/jYPPqg8YkC9M0ymMY/j73OqSJM69Q6qz+FC0fs7r77brz22muw/fExWqyL/fgvu9yOy3Dz0x/ryLqyzqHyZJuybjSu019X5qR9u8rPEyM+A5mchg4d2lVS6wdzmI6jiBR4dmLGyXh5LJjxCgHzMT/9BEvvf5xxMl7mD8WYh49m4zO7bX/sk/zhH4ovxtKZPzJhHqdlU/TY/Y6j2j7fmu8bij5eAerYP9hX+N6hD/Yh/5g4lYg/nsJY+IMm/sc6W+eJK6cjMQ9/LZMnr3Z9yL6retMn30fMy7ZlG3MfjfmYn8fs9uT+UN/DzE8/w4cPt96nbA+OctNXMNttt92sPGzHDTfccLXkdh2dtBnjt+NgvVZz5LcRTh+yubAsP5drrLJ8njA5iWeNzNohAlEmINEcZcByH3cCCkAEREAEREAEREAEwiYg0Rw2QjkQAREQAREQgWgTkH8REIF4E5BojncLqHwREAEREAEREAEREAHXE5BojkATyYUIiIAIiIAIiIAIiEBiE5BoTuz2Ve1EQAREwCkBpRMBERABEeiCgERzF3B0SAREQAREQAREQAREwEsEoherRHP02MqzCIiACIiACIiACIhAghCQaE6QhlQ1RMALBBSjCIiACIiACHiVgESzV1tOcYuACIiACIiACMSDgMpMUgISzUna8Kq2CIiACIiACIiACIiAcwISzc5ZKaUXCChGERABERABERABEYgCAYnmKECVSxEQAREQAREIh4DyioAIuI+ARLP72kQRiYAIiIAIiIAIiIAIuIyARHPIDaIMIiACIiACIiACIiACyUZAojnZWlz1FQEREAESkImACIiACIREQKI5JFxKLAIiIAIiIAIiIAIi4BYCsYxDojmWtFWWCIiACIiACIiACIiAJwlINHuy2RS0CHiBgGIUAREQAREQgcQhINGcOG2pmoiACIiACIiACESagPyJwEoCEs0rQWghAiIgAiIgAiIgAiIgAp0RkGjujIz2e4GAYhQBERABERABERCBmBBwnWj+Y9YUjBs/WiYG6gPqA+oD6gNJ0gf0nafv/eTuA9R+MVG9YRbiKtG83lYZ2HfkQpkYqA+oD6gPqA+oD6gPqA8kUR+gBgxT00Y9u6tE89Bh2XCbKR61ifqA+oD6gPqA+oD6gPpA9PtA1FVvmAW4SjSHWRdlFwEREAERCExAe0VABERABMIkINEcJkBlFwEREAEREAEREAERiAWB+JYh0Rxf/ipdBERABERABERABETAAwQkmj3QSApRBLxAQDGKgAiIgAiIQCITkGhO5NZV3URABERABERABEIhoLQi0CkBieZO0eiACIiACIiACIiACIiACKwgING8goP+e4GAYhQBERABERABERCBOBGQaI4TeBUrAiIgAiKQnARUaxEQAW8SkGj2ZrspahEQAREQAREQAREQgRgSkGheDbY2REAEREAEREAEREAERGBNAhLNazLRHhEQARHwNgFFLwIiIAIiEHECEs0RRyqHIiACIiACIiACIiAC4RJwW36JZre1iOIRAREQAREQAREQARFwHQGJZtc1iQISAS8QUIwiIAIiIAIikFwEJJqTq71VWxEQAREQAREQAZuAliIQAgGJ5hBgKakIiIAIiIAIiIAIiEByEpBoTs5290KtFaMIiIAIiIAIiIAIuIaARLNrmkKBiIAIiIAIJB4B1UgERCBRCEg0J0pLqh4iIAIiIAIiIAIiIAJRI5DUojlqVOVYBERABERABERABEQgoQhINCdUc6oyIiACSUhAVRYBERABEYgBAYnmGEBWESIgAiIgAiIgAiIgAl0RcP8xiWb3t5EiFAEREAEREAEREAERiDMBieY4N4CKFwEvEFCMIiACIiACIpDsBCSak70HqP4iIAIiIAIikBwEVEsRCIuARHNY+JRZBERABERABERABEQgGQhINCdDK3uhjopRBERABERABERABFxMQKLZxY2j0ERABERABLxFQNGKgAgkLgGJ5sRtW9VMBERABERABERABEQgQgSSSDRHiJjciIAIiIAIiIAIiIAIJB0Bieaka3JVWAREwNMEFLwIiIAIiEBcCEg0xwW7ChUBERABERABERCB5CXgxZpLNHux1RSzCIiACIiACIiACIhATAlINMcUtwoTAS8QUIwiIAIiIAIiIAIdCUg0dySibREQAREQAREQAe8TUA1EIMIEJJojDFTuREAEREAEREAEREAEEo+ARHPitakXaqQYRUAEREAEREAERMBTBCSaPdVcClYEREAERMA9BBSJCIhAMhGQaE6m1lZdRUAEREAEREAEREAEukUgYUVzt2gokwiIgAiIgAiIgAiIgAgEICDRHACKdomACIiASwgoDBEQAREQAZcQkGh2SUMoDBEQAREQAREQARFITAKJUSuJ5sRoR9VCBERABERABERABEQgigQkmqMIV65FwAsEFKMIiIAIiIAIiEBwAhLNwRkphQiIgMrXwcwAABAASURBVAiIgAiIgLsJKDoRiDoBieaoI1YBIiACIiACIiACIiACXicg0ez1FvRC/IpRBERABERABERABDxOQKLZAw04/dsmjNy1HOMOqpAlIAO2LdvYA11RIYpAUhNQ5UVABJKbgESzB9r/qzfq0atfKvY9LU+WgAzYtmxjD3RFhSgCIiACIiACSUsgQURz4rdf2QbpGDosW5aADNi2id+DVUMREAEREAER8DYBiWZvt5+iFwERSCQCqosIiIAIiIBrCUg0u7ZpFJgIiIAIiIAIiIAIeI9AokYs0ZyoLat6iUACEFi6sBWfPFOHSaOW4bbjF2PMHoswaodymRgkZB+4dp9FuO/sJfjPgzWomN2SAO9gVUEEEouARHNitadqIwJBCHjj8IzJTZhwTCVOGTgfz49ciin/qsWc5+tQ81EDGv7XKBODhOwDy95rwG+TavHGdVU4c/0FuPGQCsyZ2uyNN62iFIEkICDRnASNrCqKgJcIvHVfDS4ZWo6qb5uweXM7es1uRe78VhSa9R6mIjJADBKTQaHp34V17Sie14pNG9tR+Wkjzt5kgTXybA7p5U9A6yIQBwISzXGAriJFQAQCE3jvkRo8edlSrG8EctrvLfAFTqa9IpDwBNj3Cxa3YSNT0ydHLsNLty43a3qJgAjEk4BEczzpJ2bZqpUIdItAhRlRvvfspehX247sbnlQJhFIPAI5pkr9l7bhpeuW47U7q82WXiIgAvEiINEcL/IqVwREYDUCr92xHOv2TUXuanu1IQLxIuCecjNNKP2r2/DsVcvw5r01ZksvERCBeBCQaI4HdZUpAiKwBoEPJ9UifVbLGvu1QwREAMgyEAbUtOOJy5fiPw9JOBsceolAzAl4UjTHnJIKFAERiCqB6d82ITPT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85pMtEcEREAEREAEREAEREAEViMg0bwaDi9sKEYREAEREAEREAEREIFYE5BojjVxlScCIiACIgCIgQiIgAh4jIBEs8caTOGKgAiIgAiIgAiIgAjEnkAg0Rz7KFSiCIiACIiACIiACIiACLiYgESzixtHoYmACIRDQHlFQAREQAREIHIEJJojx1KeREAEREAEREAERCCyBOTNNQQkml3TFApEBERABERABERABETArQQkmt3aMorLCwQUowiIgAiIgAiIQJIQkGhOkoZWNUVABERABEQgMAHtFQERcEJAotkJJaURAREQAREQAREQARFIagISzS5vfoUnAiIgAiIgAiIgAiIQfwISzfFvA0UgAiIgAolOQPUTAREQAc8TkGj2fBOqAiIgAiIQHQLTp0/H+eefjyVLlnSrgIkTJ+LFF1/sVt5Amfz9ffXVVxg1ahQaGhoCJdW+BCHAvnfKKaeA7d1VlcLtq1351jERsAmkwF7TUgREQAREQAT8CKy33nq46667UFRU5LfXHatDhw7F+PHjkZWV5Y6AFIUIiEDCE9BIc8I3sSooAslBQLWMPAH/0TuO9HHUmTZs2DAcccQR4HGWymPcR+OoIEcHOcL84YcfYtKkSdZoM9OcfPLJVj6OEH/66aerjRQzPUeS6Y/GdfqjMS+Pd/RHPxxppnGdaWlMTx+Mj/EGOsbjMncS8G/PCRMmrBYk25ZtbBu32d9uvPFGzJw5E5deeql1ZYT77TRccns1R9oQgW4QkGjuBjRlEQEREIFkJEBRcvzxx+OFF17A4MGD8frrr1sC5cknnwRFLrf3339/UNxSVO+xxx4YMWKEJZTJq7q6GjfddJM1QpyRkcFdAY0CmQfoj37pn75o/v6YhnbfffdxYcU1ZswY3HLLLasE/fz587H11ltbsTL/yy+/rCkdFi33/vNvz0MPPRQVFRVWsDwJ4jH2CfYN9gW2Z05ODkaPHo111lkHt956q9UnA6WjGLccufufonMxAYlmFzeOQhMBERABNxEoKSkBp2xwSgSFaKDYKJZpgY4VFBQEnepBYfPtt99ixx13tFywvK6miDD9okWLQHHFuDbffHNL0E+ePNnKn5+fjyFDhljrtk9rQ/9cSSBQe2666aZWrOwLjz32mNUHuWPgwIFcrGFO062RUTtEIAgBieYggHRYBFYR0IoIJDmB3r17g6N6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lbvuumvVDXpMa19et6dmcASZ+XksUB5/f3Za20dneeiHl99nzpypkULCcKl17B/sN2xvhktBzL7DNNzmkiPMbHsuuc397APsP+wb3GZ++uE609AHfXGbaZmfZudhPq7zGNPYxjnNOuGyaWgZiIBEcyAq2pd8BFRjERABTxPgDYCnn346dtllF+upHp6ujIKPKQFO3eC0Ic5pPvDAA2NatgrzFgGJZm+1l6IVAREQAREIQIAjjByNtEccAyRJil2qZOgE7JFnjj5zPXQPypEsBCSak6WlVU8REAEREAEREAEREIFuE5Bo7ja6UDMqvQiIgAiIgAiIgAiIgFcJSDR7teUUtwiIgAjEg4DKFAEREIEkJSDRnKQNr2qLgAiIgAiIgAiIQLIS6E69JZq7Q015REAEREAEREAEREAEkoqARHNSNbcqKwJeIKAYRUAEREAERMB9BCSa3dcmikgEREAEREAERMDrBBR/whGQaE64JlWFREAEREAEREAEREAEIk1AojnSROXPCwQUowiIgAiIgAiIgAiERECiOSRcSiwCIiACIiACbiGgOERABGJJQKI5lrRVlgiIgAiIgAiIgAiIgCcJSDRHqdnkVgREQAREQAREQAREIHEISDQnTluqJiIgAiIQaQLyJwIiIAIisJKARPNKEFqIgAiIgAiIgAiIgAgkIoHI1EmiOTIc5UUEREAEREAEREAERCCBCUg0J3Djqmoi4AUCilEEREAEREAEvEBAotkLraQYRUAEREAEREAE3ExAsSUBAYnmJGhkVVEEREAEREAEREAERCA8AhLN4fFTbi8QUIwiIAIiIAIiIAIiECYBieYwASq7CIiACIiACMSCgMoQARGILwGJ5vjyV+kiIAIiIAIiIAIiIAIeICDRHJFGkhMREAEREAERH5AQFgAAEABJREFUEAEREIFEJiDRnMitq7qJgAiIQCgElFYEREAERKBTAhLNnaLRAREQAREQAREQAREQAa8RiFa8Es3RIiu/IiACIiACIiACIiACCUNAojlhmlIVEQEvEAg/xg8eqcGoHcplQRj87+na8GHLQ9QJuKU/f6r+EvW2VgHeJyDR7P02VA1EwPMEUnxAds/gH0dlpqYFc1rR8L9GWRAGf05rMbT0igcBL/bnOeovoXUVpU5KAsG/pZISiyotAiIQSwK5hSlIMwYHfz1MGhkQjIHBpFecCHixP8cJlYoVAU8RkGj2VHMpWAcElMSDBErXTkOTPo082HIKORAB9edAVLRPBLxPQF9T3m9D1UAEPE9g0JAMlJe3er4eqoAIkEBk+jM9yURABNxEQKLZTa2hWEQgSQmUDExF30FpqErS+qvaiUVA/Tmx2lO1EQGbgESzTSKEpZKKgAhEnsAB5+WjoX9q5B3LowjEgYD6cxygq0gRiDIBieYoA5Z7ERABZwT2OTUPPddLR7mz5EoVPgF5iCIB9ecowpVrEYgTAYnmOIFXsSIgAmsSOP+RIjQNTMNSh0/SWNOD9oiAewioP7unLRRJIhOIXd0kmmPHWiWJgAgEIdBnUBpu+bw3SnbJxPwBaVic5kNzkDw6LAJuJaD+7NaWUVwi0D0CEs3d46ZcIiACDgh0J0lxv1Rc9WoJTruvJ0r3ysT0PB9+NyPP8/umYmHvVMwvTpE5YJCZ0R36yhNpAl7pz+nqL5FuevlLQAISzQnYqKqSCCQCgW0PyMaYt0vxXPUATPiqD859qhgnP1iEUx8rljlgsN0ROYnQDRKmDm7vzzscrv7SRWfTIRGwCEg0Wxj0TwREwM0EyganYfPds7DdQdkYOkzmhEG/9dPd3KRJHZsb+3PZBuovSd0pVXlHBCSaHWFSItcSUGAiIAIiIAIiIAIiEAMCEs0xgKwiREAEREAERKArAjomAiLgfgISze5vI0UoAiIgAiIgAiIgAiIQZwISzUEbQAlEQAREQAREQAREQASSnYBEc7L3ANVfBEQgOQioliIgAiIgAmERkGgOC58yi4AIiIAIiIAIiIAIxIpAPMuRaI4nfZUtAiIgAiIgAiIgAiLgCQISzZ5oJgUpAl4goBhFQAREQAREIHEJSDQnbtuqZiIgAiIgAiIgAqESUHoR6ISARHMnYLRbBERABERABERABERABGwCEs02CS29QEAxioAIiIAIiIAIiEBcCEg0xwW7ChUBERABEUheAqq5CIiAFwlINHux1RSzCIiACIiACIiACIhATAlINHfArU0REAEREAEREAEREAER6EhAorkjEW2LgAiIgPcJqAYiIAIiIAIRJiDRHGGgcicCIiACIiACIiACIhAJAu7yIdHsrvZQNCIgAiIgAiIgAiIgAi4kINHswkZRSCLgBQKKUQREQAREQASSiYBEczK1tuoqAiIgAiIgAiLgT0DrIuCYgESzY1RKKAIiIAIiIAIiIAIikKwEJJqTteW9UG/FKAIiIAIiIAIiIAIuISDR7JKGUBgiIAIiIAKJSUC1EgERSAwCEs2J0Y6qhQiIgAiIgAiIgAiIQBQJJLlojiJZuRYBERABERABERABEUgYAhLNCdOUqogIiEDSElDFRUAEREAEok5AojnqiFWACIiACIiACIiACIhAMAJuPy7R7PYWUnwiIAIiIAIiIAIiIAJxJyDRHPcmUAAi4AUCilEEREAEREAEkpuARHNyt79qLwIiIAIiIALJQ0A1FYEwCEg0hwFPWUVABERABERABERABJKDgERzcrSzF2qpGEVABERABERABETAtQQkml3bNApMBERABETAewQUsQiIQKISkGhO1JZVvURABERABERABERABCJGIKlEc8SoyZEIiIAIiIAIiIAIiEBSEZBoTqrmVmVFQAQSgICqIAIiIAIiEAcCEs1xgK4iRUAEREAEREAERCC5CXiv9hLN3mszRSwCIiACIiACIiACIhBjAhLNMQau4kTACwQUY2IQ+GPWFIwbPzosu+7G0Rh7Qwe7fjSutW2cWV9p4ZblxfxknBi9BWBdvNgG4cbMPk4b69/XA/Tva64bFdZ7iXGScaL0l2Ssh0RzMra66iwCIpDwBNbbKgP7jlwYtk379WdMnTIFv/48Bb+ttGm/TMF0P/vDrP/80xTsc3n45UUi5o4+eg2ZiZ9/mIKBu8wKm0dH39wma693KNaBdYm0DdhxlsW+dKs/o8I+SLyOypz++8/4afIUTDV95BfT19nPfzd9errp+zN++xm0mb9NwZQff8bely1w5LOruMja6/0lWeOXaE7Wlle9RUAEEprA0GHZiITVVrdhw5p2bFDdjvVX2uDl7VjPNrNvXWMtze3Yat+siJQZibhtH5k5PvzngRoU1bbj9TuqUTY4LSoxer0z2bwiuSxdOw2v3VltsX/znmrk9kiJCvtwY66pasdG9cbq2q2+zn5u9e+qNgxaaeuYNO1twJC9I/O+8np/Sdb4JZqTteXjXW+VLwIi4AkCKSk+tDuI1GfStbY4SBjDJPOmtWD8YZVYqxUoNeWWNrZjwpGVZk2vaBNoNSdRtxxRgb5mSfZrm05002EVqJhjGiPahYfoPzUNjvp4SirQ0mQqEqJ/JU8cAhLNidOWqokIiIAIRJwAhYITmWA0M1pbnKSMeIgBHTaZkcMbhi1CcU0beq5MUWrCq/29BRNPWLxyT/gLeQhM4BZzctLyZytKDHOmKDL/8pa148aDKsyau16p6T5HojnVKKZmc+LlrugVTSwJmC4Qy+JUlgiIgAiIgJcIOBXNPvNt4qaR5huMOGuZ2YISc0ndn3d/I3q+e7kOr95R7b9b6xEk8My1Vfjt/QaUdRiV7d3ajppfmnHz4e4a7U9LBzp0k4A0eGKokeaAaJJmp/mYS9S6ql4iIAIiIALhEkhJdTYKR0HhlpHme09fgrmfNaKsOXDty2rbMemypfjxw4bACbS32wQ+/3cdXrllOcg4kJN+5qTll3fq8cSoZYEOx2VfmsORZvbx5sa4hKhCXUJAotklDaEwREAERCAggTjvTE2Fo0vXPh/Q2olIjWUVXrxpOb54uhb969s7LTbbHBnQAkw4uhLLFrlvjq0Jz5Ov2VObcdtxi9HPsM/oogb96trx1p3VeP/R2i5Sxe5Qmgm2897yVxw+n09zmv/CkZRrEs1J2eyqtAiIgAg4I5DiUDRzFC7eI83/91wdXriuCv3MSLLR8F1WkPOcc5a0YcIR7poq0GXQLj7IJ0vcYlj2aWpHQZA4081xntTcfdpi/PRx/Idu0zN8cDI9g31Kc5pN43XzlQjZJJoToRVVBxEQARGIEoHUNEqF4M6ZKp5zmn/5vBETjqm0Rpgzg4drpehrlNL8r5vwyIVLrW396z6BCUdVomlGC+wb/4J5yjUJ1jL8bzq0AotmtZit+L3SMn2OrqZQMGlOc/zayQ0lsw+4IQ7FIAIiEDcCKlgEOieQ6vBxXObKddyenlE5pxXjD6nAWuYae37nVQl4pH9DO95/sAYfPeGOqQIBg3T5zueur8LUd+pR1mgaIIRY+USNgqo23Dgsvk/USHcomn3t7dCc5hAaOAGTSjQnYKOqSiIgAiIQKQIpDm8E9MFnRHOkSg3ND5+Ukbe0HcWhZbNSp5r/nIN7x8mLMWNyk9nSKxQCX7xSj3/fsLzTG/+C+eptRptrfmuxTnqCpQ16vJsJnIpmDkdrpLmbkBMkm0RzgjSkqiECIiAC0SCQmg5qhaCufSYFf9DCLGL6uvHgCtT+2ozSMJ4RnWci7t8KcE5uPOpgivfka67hftuxleBofUYYNejf1I7f3m3ApMuXheGl+1kzsnzO5jS3A80m1u6XpJxeJyDR7PUW9Eb8ilIERMCjBFLTfM5Es6895iPNj1y0FNM/aEBZg1EzYfItMflbZ7eAc3PNql4OCPDXFfkri8Fu/HPgypqL/s4/q/HuI7VOkkc0TXq2sz4Oc2LVEuIUlIgGKmdxJyDRHPcmUAAiIAIi4F4CqQ7nNKPdZ0Rz+OLVKYk37q7GRw/VWE/KcJonWLp+zcAvZsTz+euXd5JUu20Ctw6vRP0fLej44zH28VCXpptZwvme0xfjx48aQs0eVnqONDvquW0caQ6rKGX2OAGJZo83oMIXAREQgWgScPrDDxyri9XTM758rR6PX7bMEsyckxzJ+pfVteP566vwzVv1kXSbUL74LOyf3qxHWb0jqem47nyixtpGmN50aCXKZ8buiRoZOT5H0zPaWtvxzJhlGLVDuettzB6LcOtxizFp1DJ88kwdli5sddwOStg5gYQRzZ1XUUdEQAREQAS6S4Bzmp3k9Vk3AkZWRAUq94/vm3DLUZUYaC6T80dKAqUJZx8fV9ff+L716Mq4PwotnHpEK+9Xr9fjubFVKKuJTlvz+dk9lrfhhhg+UcNnlFBqti8osn5G0GdNb0HD/xpdbzVmtH7Oc7X4aVItnrt8KU4eMM96JOMM3ewatJ27SmC6SleHdUwEREAERCCGBFxXVKrDOc1ob4/6LwIur2zD+EMq0bepHZGYR9sZ7EJzoLC2Hbccrh8+MShWveb/3oLb+Czshnbw5GLVgQiv9DZ6vG5ac8weRdezbyrSC4PLId7s2MPU1SvW0wwu5y1oRcncVmzRAsx7qwEXb7sQb91XY2qhV3cIBO8l3fGqPCIgAiIgAglBIC3DB6NhgtbFZxJF+xcBbzykAukLWtDLlBU0oDAT9DFlLPmpGfecuiRMT4mT/ZYjKtCrAaBojHat+jcD095vwGOXRv+JGn0HpaEpPdo1iq9/nym+0Izgb2DE85Nm5Pm9R6ItnE2BCfiSaE7ARlWVREAERCBSBDg9w+jH4O5MojbzhRw8YfdSXPa3csz6qhFtRkwtNC7KjS0yxp/F4HjwYrPO3/WjxGoy605exhUYshmQg7nyDlOF1bLxUWifP12Lt++XwOCj5WqmtaC41VxRMJTIjUaGNDKnNZpjTl7VJhFvt6RVmXUa245tSOOpSq4Z0X7r7mr8azSPmERReq23TQaWLO/Y+lEqLM5uOaWpX0077j17KSpms+fHOSCPFS/R7LEGU7giEC6BSOR/emwVbjywXpYEDGZObltDTAbqQy1GLT0/rjFqfaJxeTp6rpOLlEE5aF87G60Ds9DcPwuNZZmo65OJmtIMVPVKx8LcVMx38M1GsT3FDL/9nOrDTyk+/GDWvzcV+9bY92Z9svHxkzlWZ5Tgoxctw/X710Wtbm5/L12/Xx0+faEeFY3t+NGwIhdy+znNh1+M/Zruw28ZKZiWacxs1xqGwV5zDNsFeamo6JmOyqJ0LC5Ox9JeGVjGduydgWrTpvWmbbML0zH1vylRZf/c1a1oqAecxB2sXl44nmuC7GXa8crdlkSVq9v7dVfx8TvOYFrjZT4W1tinHSIgAiIQlMAOG56IM4+6VZbgDNYdsJkj0Uzk/uUAABAASURBVJyWkoa9tjs+av3h2ivuwfVX3osbrrkP48fej5vGPYCbb3gAt4x/ELfe/CBum/AQbr/tYRx66DHI4PB4kB7MccVdd9kVjzz6OB597HE89vgkPD7J2OOP48GHHsa99z2Au+6+BxPvuAvjx9+Gs4ffFrW6uf19dPYxt+GRR1YwIqtHDTNy476Hzf6HHn4cDz30GB588DH07dPPUX/JyczGBReMxJ13PIw7Jz6MO25/GBNvewgT2Y63PITbTJveatr2DrN9+Zl3BmIf0X2HHHoUagoLg/SaxDncq6ENVQvaI8rQ7f3YaXz8buuspSWaOyOj/SIgAkEJ7L333pAlNoN+/fs7EkH8Mtloo43i3h/WXXddMJZgnZeiee111lkj3n322Qf7778/hg0bhkMOOQSHH344jj766DXSqd8H7vcFBc5u0UxPT8dWW23lGq633347igYOBK9ABOs7iXA801QiJzMTvXv3dk0buOU9ZdB0+nLy2dJpZh0QgYAEtFMERCBhCFDcOKlMO5+e0Rr/OZLNzc1ob+MM5a6jpmjONKKh61Q6GiqB1NRURydZMP2lzUE7hVp+OOknTpyI2uJiVOXkhOPGM3kLMjIwbdo0z8TrhkAlmt3QCopBBERABFxKID0jw5kIMgKopaUl7rVgDO0OxDtFc0YQ0Rz3yngwgJSUFEf9xefzodVBO8USAa+UvPrqqyjbZhssLivDYlN4/Hu0CSJKL585wVy0iLfTRqmABHQr0ZyAjaoqiYAIuItARUUFXnnlFdx4440499xzMfzII3HYQQd5wj54/31HIoijuxSs8Sbf1NQEn4MgLNFsTggcJFWSEAhwpNlRcheONDPuQYMG4dlnn8VV112HfkOHYlpWFv4sLERl794oN6PQi3r2hNttbkEB6liZIFZTXY2ZM2cGSaXD/gQ8Kpr9q6B1ERABEXAngZ9//hlnn302ttl6a9xhBPP/vfQSfnr9dcz/7DNUfvONJyzfjESVOMCbk59vrrhTijpIHMUkjY2NjkSzz4yIOp16EsVwE851aorDkWZTc7eNNJuQVr04r/2FV17BHzNm4CUz+nzLXXfhwlGjcP0dd7je/rbHHnDykL4UM9Lfp08f6M85AYlm56yUUgREQAQcE5g0aRL2228//P7pp9ispQX5c+cibf58FJhLovxxCMuMNy8sTZhBX5lGNOcbC5owygmanIrm1FSkpaVFOZrkc5+Smuq40m4Wzf6VGDx4MHbeeWcce+yxnrhpjjfD+sev9cgRkGiOHEt5EgEREAGLwDPPPIObr78e6xuxnFVZ6Wjk08ro4X+N5nJ7WVlZ3GvgdHoGzIioRpoj31ycnuHkeoPPFO22GwFNSHp1k0CyZJNoTpaWVj1FQARiQmDevHkYZS7j9qmtBX99KyaFuqCQOeXl2GSTTeIeSbPDOc3w+SDRHPnmciqaYU6yvDLSHHlK8uhVAhLNXm05xS0CjggoUawJPPTQQ9hqvfWQG+uC41hea3Ex/rb99vDU9AwjmjU9I/KdhqLZqVeNNDslpXRuISDR7JaWUBwiIAIJQeCF559HzdSpCVEXp5WozsnB8Sec4DR5VNNpekZU8QZ1TtHsZHoGHYU00swMMhGIMwGJ5jg3gIoXARFIHAI//vgjstLTwV/bSpxadV2ThpISDFx3XRx88MFdJ4zRUf64CefLBi3OjDRrekZQSiEnoGh2ksmn6RlOMCmNywhINLusQTwYjkIWARFYSYC/rtXTjLqu3Ez4RZ0RzLVZWbh94kTX1NXpSHO7Ec2anhH5ZqNodjTSbESzpmdEnr88RpeARHN0+cq7CIhAEhHgr2u119cndI2bTe2WmtH0BaWlWHe77fDG22+jd+/eZq87Xt0faXZH/F6PgqLZaR00PcMpKaVzCwGJZre0hOIQARHwPAH+utbSJUuC1oO/1sVf7XL7L4vZ8VWaEeUKI5L/yM/Hn8YG77ILbr3jDjz44IMoKioKWt9YJnAqmjkaqukZkW+Z1LQ0R78gyadnaKQ58vzlMboEPCGao4tA3kVABEQgMgT461q+lpagzvhrXTvsuafrf1nM/vWzsRMm4PZ778Vb//kPfv3tNzz2xBPYbbfdgtYzHgkkmuNB/a8yOdLME5K/9nSy1t4OjTR3wka7XUtAotm1TaPAREAEEozAatUZNGiQJ35dbO+998Y+++yDHXbYAWuvvTbc/udYNGtOc1SakqLZqWOJZqeklM4tBCSa3dISikMEREAERCBsAi3NzfA58NJuRjo1PcMBqBCTaHpGiMA8mTx5g5ZoTt62V81FQAREIOEINLe0OBPNpuYSzQZChF9pqanOPJqTFo00O0OlVO4hINEcx7aY/m0TRu5SjnEHVcjEoFt9YOSu5WA/srtxrJafvVCn+Yixgq1yQiLQYkSzky+2NuNVj5wzECL80khzhIHKnasIOPlscVXAiRTMV2/Uo3hAKvY9LU8mBt3qA736pYL9KJbvi+WL2zDnl2b89NNPsSxWZYmAIwIUzZqe4QhVVBI5ndPM6TFdjDRHJTY5FYFwCUg0h0swzPz91k/H0GHZMjHoVh8o2yA9zB4YevaJJy5GZo4PQ4YMCT2zcohAlAk4Fc1t7e3Q9IzINwZH7/X0jMhzlUd3EJBodkc7eCcKRZrUBKZ83IgfP2zAprtkJjUHVd69BFpaWx3NaaZopsBzb028GZnj6RltbdBzmr3ZxskctURzMre+6i4C/8/eecBHUa1t/NkkhJbQIUAogoCigGBB7FiwYhcvelVARCliL98VRbBgBYWrWAAFu4IdC/aGehUUUXqV3mvoKd95BiZOlt3sbLK72dl9+M3JzJz6nv/sLs+++86ZMAmMuXUjUtOA5u0lmsNEp+oxIiBPc4xABxnG9Y2Apr3CMwwEbZ4iINHsqcslY0Wg7Ah89PRWbFmXj3Ouzyw7IzSyCIQgQCHmJqaZXk6FZ4SAWYJit57mggh7mktgqpqIQNgEJJrDRqYGIpB8BLauz8cr92w2ojnPumEx+Qhoxl4hoPCMsr1S4YS88AtO2Vqr0UUgPAISzeHxUu2wCahBIhB45Z5NaNouHUd1roi6TdMSYUqaQ4ISoBBz42nOM55OeZoj/yJISTGywhf6CrAGQ2kib4F6FIHoETCv7uh1rp5FQAS8T4A3//38/g5sWZuH06/J8P6ENIOEJkAxTEEWapKsF5ZoDtWhyi0CqXy4iUvRnJeba7XRHxHwCgGJZq9cKdkpAmVEgF7mEy6thHIVfGh7WoUyskLDioA7Am49zYppdscz3FqWp9l4m/NNw7x9idKYaY85370v8Xznzp3mTJsIeIdAIohm79CWpSLgMQK8+S+9og+rF+cqltlj127o0KG44oorkir9+9//Rs0aNTC/ShUsYKpaFQv90iJzzpSZmYkrr7wyqfjE4vUwYcIEbK1QAfMyMrCAyXBexGSux2KTlhj+S6tVw3ZzPGXq1KTkz/emxz5OZO4+AhLN+0BoJwIiUJSAdfPfwM3o1DMDM3/YpdCMoniicBb5LrOysnDcccclTTr++OPRt18/3HDjjejPdMMNuN4v9TPnTDea8mRiE6u5Xnzxxbj55putdJPZ33TTTbiRyfAm8xsM//79+4PHF154YdK8Nm3+fE9G/p2uHmNFQKI5VqQ1jgh4jADDMk7rXhlz/7dXMLsIU/TYDJPD3Pbt20NJDPQaiI/XQFJ86iTwJCWaE/jiamoiUFIC9s1//7q7KiaN3qbQjJKCVDsREAEREIGEISDRnDCXUhMRgZAEXFegl/nKB6rhm1e34cizKmiZOdfkVFEEREAERCBRCUg0J+qV1bxEoIQE7Jv/TutRGZ8ZL7OWmSshSDUTARGIEgF1KwJlQ0CiuWy4a1QRiEsC9s1/V9xfDVM+3oG0dGiZubi8UjJKBERABEQg1gQkmmNNPMHH0/S8TYBhGbz5r0X7dEwalaNYZm9fTlkvAiIgAiIQQQISzRGEqa5EwMsE7Jv/6GVeOmuPlpnz8sWU7aUloPYiIAIisB8Bieb9kChDBJKTAL3MvPmvfCUfPhudY63LrGXmkvO1oFmLgAiIgAjsT8B7onn/OShHBESglAScN//t2VWASaO0zFwpkaq5CIiACIhAghGQaE6wC6rpiEC4BJw3/7HtpFE5OPJsLTNHFtFM6lsEREAERMBbBCSavXW9ZK0IRJwAwzLsm//Y+WdaZo4YlERABERABEITSKoaEs1Jdbk1WREoSsB58x9LuMxcOS0zRxRKIiACIiACIlCEgERzERw6EYEEIuBiKvQyX3l/NfDmP1ZnaMbpvTJ4qCQCIiACIiACIuAgINHsgKFDEUgmAh+N3Ir0ij6cdnVla9r2MnNnXCPRbAEpgz8NsrNx3nnnlcHIGlIE4peALAtMgJ8VDRo0CFyo3KgQkGiOClZ1KgLxTcC6+e+ezeCazLaln43OgSWYfXaO9rEmkF9QgD9//x1tDzsMmzdvjvXwGk8ERMADBPjZwM8Iflbk5+d7wOLEMVGiOXGuZRnMREN6lQDDMpw3/9nLzCk0o+yvaKu8POSsXYvDjHD+5JNPyt4gWSACIhA3BPiZwM8GfkbwsyJuDEsSQySak+RCa5oiYBPwv/mP+Yxl1jJzJBEfqaUxo/Lu3ejZsycefPBBc6YtqgTUuQh4gAA/C/iZwM8GfkZ4wOSEM1GiOeEuqSYkAsUToJfZefMfa382etve0AyeKMUFgabGimyTRo4ciSuvvNIcaRMBEUhWAvwM4GcBPxP42ZCsHMp63vEumsuaj8YXgYQi4H/zHydnLTNXHjjstAo8VYojAnWNLc0LCvDdN9/guGOPNWfaREAEko0A3/v8DOBnAT8Tkm3+8TRfieZ4uhqyRQSiSCDQzX8cjqEZp2vFDKKIYip515mmaZu8PKxasgQtmjfH77//bnK0iYAIJDoBvtf5nud7n58B/CxI9DnH+/wkmuP9Csk+EYgQAYZlOG/+Y7daZo4UvJEOyc9HyrZtOPfcc/Hcc895w2hZKQIiUCICfI/zvc73PN/7JeokGo2SvE+J5iR/AWj6yUEg0M1/nPlnWmaOGDyTmhtLaxvxPHjwYPTv39+caRMBEUg0Anxv8z3O9zrf84k2Py/PR6LZy1dPtovAPwSKPaKXmWsy20/+Y2UtM0cK3kt8lEETY/Z7776LM8880xxpEwERSBQCfE/zvc33ON/riTKvRJmHRHOiXEnNQwSCELBv/uu078l/djXGMmuZOZtG7Pdvvv46LjrvvCIpNcXdR3INY+6hxuM8Z8YMtG7VCitXrjQ52kpD4IknnsB//vMf7Ny5M2g38+fPxw033IANGzbsV+eXX34pbM++JkyYsF+dUBnOds7+QrULVV6c3aHasry07dmH+5ScNVetWmW9l/me5nub73E3JFJTUop8hvAzhZ8tbtqqTvgE3H1Ch9+vWoiACMQBgWA3/9G0z7TMHDFENPnQD6+FAAAQAElEQVR8PmRUrRqyz/qmRoUVK7BuypQiqYkRwqbI1VbO1OLDDXYaAdfh6KPxrvE8myxtJSBAUbhmzRqr5bJly6x9uH/at2+Phx56CBUqRGYVmkj3F+58nPWbNWuGESNGoEYNt1LO2VrHoQjwvXu0ef3wvcz3NN/bodrY5fzM8P8c4WcLP2PsOsH2FSpVgs/nC1as/AAEJJoDQFFWYALK9R4BhmX43/zHWWiZOVKIfKpqBHOFqqFFM0dmrUCJZeGkg03lKrm56NevHwYOHGjOtIVLYNq0aTjiiCOs9OGHHxY2p5ju0aMHmK6++mps2bLFKhs/frx1Q+Yll1wC1mGm7Rl+44038NVXX2HcuHGgt5n5bM+6tieb+bzJi4n57IN5/u3s+vR+85j1mdgnx2Q7er4DlbE8WGJ79sPEtuyfdelB5zztfPbNMZh4zHLW4znttuvZ7VmmFB4Bvmf53uV7mO/l8FoDgT5DmOemnzQjmvmZ5aau6uwlING8l4P+ikDCEfjru134+f0dYCyz/+QYmqFl5vyplP68QYMG2F0GnpsDjOmMfxwzZgy6du1qzrQVQ6BIEQXf7Nmz0bZtW5xyyimgx9kWh6y4detW9OnTBy+88AKqVKmCFeYXgu3bt4PimqzJnH2wLtMFF1xg9dOtWzdQWDKPfTz88MOWJ3r69On4+OOPLVHNPo477jirL9bl+M52bMv0zDPPcAeK9XvuuQePPvpooVinPRT87Ivt6bV02mM1dPyh4GV79sP+WGT3T6HfunVryx72yb5Z7kxkQ68z58Mx69Spg4kTJzqr6NglAfv1w/cu38Mum0WsGj+r+JkVsQ6ToCOJ5iS4yJpichJ45e5NlmB23vxHElpmjhSik1q1aoXla9dGp/MQvWaZ8oMKCvDz5MngT/vmVJsLAnY4BsUDww8oAiks7aaZmZlFwhJ4Tg8ryylSt23bBrsP5gVKFNvsm2W8NhTg9nnDhg2ZHTRRAFPIX3jhhVboR5s2bdC8eXPQO85GtIeCn8cU4NwXlyh62Z79MJSE/f75559YuHAhFi1aZHnQ2Z5zq19//x/5yaZy5cogL9a7+eabC78c8FzJHQG+Dvhe5XuW7113rSJba4355YSfWZHtNbF7iy/RnNisNTsRiBmBj0bmIL2iD/43/9GAz7TMHDFEJWVnZ6Nx48bYHJXeQ3da2VRpnZeHtcuXY/jw4eZMWygCFJ//+9//0KVLF0swMkRisvniYbejKLUFLvP8z5kXKmVlZaGS+Smc9SiCGRJB4c1E7y7zg6UdO3Zg9erVhcUUuhT2dka49ixZssRuau05t4yMDGzatAn0iFuZxfzxb19MVRUFITD8ySet9yjfq3zPBqkW1Wx+RmXXqwd+ZkV1oATrXKI5wS6opiMCe2/+22R5mf1paJk5fyKRP+/RsyfyA3joIj9S4B5XmezdJgXyEppsbQ4C9LoyVIKhCgw1YKKIpceVHlVH1cJDCku2Ywb3POex22SHMjA0guMxHKO4thUrVgRFt12HopueZ/s83H2jRo2KNOEccnJyUK1aNVCAFykMcOLfPkAVZYUgUN98ueZ7lO/VEFWjVryrZk30vv76qPWfqB2nJOrENC8RSFYCwW7+Iw/GMmuZOZKIXrr88stR94AD8I9vMHpj+fe80GQsN4k3FtFzag61FUPAFsZcHcKuRo8www/ogbbznHuKZLuM+7p16xaGKjjruTmmYKVoL66u7Vm2Y5UZEz1v3jzYIRnFtQ1URs8y27MfCnD2yzjmpk2bokmTJlY8M9vR4x4oppntuTzasn2rjHCZPCa2UXJHgO9Nvkf5XuV71l2ryNXiZ1PDgw4CP6tC9KpiPwISzX5AdCoCXiZQ3M1/nFdhaAZPlKJGYNiwYTC/e2JLVbf3sZfelDmpqdieng7emHbXXXeVvsMk6IFhGBSMFIL2dClSeRMcxay9WoZdxj09+OvXr7dCOVjn9ttvt2KNWWYnxinTY80VMew8e89YYYZbUDjddtttVlgIPccUsMHa8UZEtmeb+++/H3fccQecQp9lbhPbsT37YX9sZ/dPrzfjmxk2wjlyrix3JrZnfcYysx5t57mzjo5DE+B7lLHtfM/yvRu6RWRqbDC/XPCzyfqMikyXSdWLRHNSXW5NNmEIBJlIsJv/WH3vMnM+HHZaBZ4qRZEAf8J+/4MP0OToo7G2fn1sSEvDniiNt8v0O8P0n1G7Nqb/+SfOOussk6PNDQEKPyb/ulzJgoLm8MMPL7I+MQUjV4647rrrLI8s69iCmzd22es0sz1DL7h35nMc1mc7lnPP6xWqHYU867ANE/tkX7Y97JPnzGc91ue5nQLVYz9MzvrshzYxv127dmDYBvPctrfH094dAT79j+9Zvnf5HuZ72V3L8Grxs2edabKqTh00P+EE8LOJn1EmS1uYBCSawwSm6iIQrwQ+HpkT9OY/2szQDC0zRxKxSfXq1cPYsWPxwMMP48ATTsDCypWxyHie12ZlYZ0RuGuqV4d/WhvmwyP4H+GslBS0NgLnt99+cxWTGpvZaxSvEaCn23mDIpelozeUojmac0n2vhlHzvcu38N8L/M9HQ4Tfmb4f47wnJ8x/KxZWKUKFlaqhAOOPRYPPf649ZnEz6ZwxlDdfwhINP/DQkci4FkCvPnv5Xs2Bbz5j5PSMnOkUDbptNNOw0uvvoq58+bhg48+wtCnnsKgRx/FA08+uV9asmGDayOXmJp/m3Tpv/6F999/3xxpE4GSE6B3ml5nepmZGFpCD3PJe1TLcAjwPfyvrl3B9zTf227b8jMj0GcJP2P4WfPhxx9j7vz5eH3CBPCzyG2/qheYgERzYC7KhRB4iUBxN/9xHlYsc68MwAf9K0MCvNmKa+meccYZ6NSp037JrWlzTcUNqanWwzKGDh1qzrSJgAh4ncDjxhPMLy58b/M97nY+gT5L+BnDzxp+5rjtR/VCE5BoDs1INUQgrgms+TsXwZ78R8MLl5m7xohmZih5lkC+sXxWuXJIqVoVn3/+OXjjlsnSVhwBlYmAhwjwPc33dqp5j/O9zve8h8xPeFMlmhP+EmuCiU5g+le7rLAM/yf/2fNmLLOWmbNpeHfPhxH8ZbzLjQ48ELNmzcLBBx/s3cnIchEQgaAE+N6ead7jfK/zPc/3ftDKKogpgbIUzTGdqAYTgUQkMO/X3UhNQ8An/9nztUIz5GW2cXhyv8JYvcCkUzt1AtfPNYfaREAEEpwA3+unnX46+N7nZ0CCT9cT05No9sRlkpEiEJjAvRNrgylwKaBl5oKRiWR+dPvif5irfD7cfMst4HJg0R1NvYuACMQTAa67zvc+PwP4WRBPtiWjLRLNyXjVNeeEItDg4HJB58PQDC0zFxRP3BfwoQe7KlTAK6+8Aj4II+4NloEiIAIRJ8D3Pj8D+FnAz4SID2B3qH1IAhLNIRGpggh4k4CWmfPmdaPVO8yfv9LSUK1ePcyZOxcnn3yyydEmAiKQrAT4GcDPAn4m8LOBnxHJyqIs5y3RXJb0NbYIuCNQolpWLLOWmSsRu7JstNYMPjslBUe0b49ffvkFaUY8myxtIiACSU6AnwX8TOBnAz8j+FmR5EhiPn2J5pgj14AiEH0CWmYu+oyjNQIfbHDllVeCD5eI1hjqVwTKhoBGjQQBfjbwM4KfFZHoT324JyDR7J6VaoqAZwgwllnLzHnmchUa2rRxYwwbNsx6aElhpg5EQAREwI8AH4LCzwp+ZvgV6TSKBCSaowjXS13L1sQiYIVmaJk5z13UH376CV27dvWc3TJYBEQg9gT4WcHPjNiPnLwjSjTH6bXfmVOA/3RcjXN9S/ZLzF85PxdXN16BXz4sejvAhEe24Ilu661ZzZ+6Gze0XYUNK/Osc+7Zxu6Tx8yzCv3+OPthEfu6pPLSQltoA21kmZ14zny7f+ee+SynbUx2G+7Zt20nj53j2H0Es5V92XXsvX9dMmKf7Jvj2SlQW7sebaXNdp/OPfNZbvfDPfsiMx4HSoFsYB/syx7T2Y59cUzunflujrXMnBtKqpOgBDQtERABEYgaAYnmqKEtXccVMnx46JssfFjQCE9MqYtaDVOtPc+ZX76yL6wBKI5v67AaZ/fNsPpkPzxmHsuK64xi8/9OXI073qhV2LZO4zQM7rwGFH5221A2s9yuW9w+s2ZK4VxpJ9MLf9dHjXqpAZudclXlQrtY92wzx3H/t8mqS/s+G5ODtp0qYNoXO6085x//tl0HVsWYWzdaVciZ/QXi73Yu7CiUDfWapRWxjfVn/7TLuuZsH25iaIaWmQuXmuqLgAiIgAiIQPEEYieai7dDpVEmsGFFHgoKCtD2tAqFI1Ew8mT+lN3cBU1sW6VWKpodmV5Y59wbMrFqYS6WzdlTmBcvB40OKYc1f+dagt627/ybMvHd69sLve7BbCWfbZsKsH1rfrAqYeeHsqH9uRVBkUyxzM7t+gce/g9v5rtJWmbODSXVEQEREAEREIHwCUg0h8/Mky0aHFQOdZum4eYjVxWGdNBzSw8uRVtxk7LF8rXNVoBeZ9ZtdkQ6XlySDe55Hk9p8oTtoCec3mB6lw8+pjxad6yAJoeVQ6gvCKxfuZoPlTIj99Zgn8XZUKtBGtYsziv8AmLXr1w1fBusWGYtMxfVl6M6FwEREAERSE4C4f+vnJyc4nbW95+3tjDOmDGwdliCv8EUkAw3uOeD2nC2Yaytf13/c1tcM3SBopvjBIrD9W8X7Pyrl7YVsZl95mz8x7O7dX2+Je45jp0YM+y2P3qZ+zxdw/I004NL7zHbHndJJVBQ89hO/rZ8PDIHt79eC+Rl1ynNnt7jUDbUzE61BD09+v71wxlby8yFQ0t1RUAERCCpCWjyJSAg0VwCaPHUhCKYcbd26vZwtWLNo1fZrstY3Wf6bYDtPS62oSm85M4qhbHDjG8ectG6kOEOptl+G8NCbBu4px0Z1f95KQaKab55XM39+rEz/PvjlwOKXoY5TPt8Z6EA55eFP7/ZVcRmu+34rQ3R6qTyVsw3vyTYfZd278YGjmELetan17lG/cDx26wbLDGWWcvMBaOjfBEQAREQAREoHYF/lErp+lHrOCdAj7K/t9YO2aCHszjzuYIDk7MOQzYodEO1dbaJ9fGHI7aCYpTC3E6tO5YHvcv+tlBk9xxaHW/ct7kwfMW/TknO3dpAnvSQfzl2G5ocVi7oTY/F2VAYmlFcJZWJgAiIgAiIgAiUiIBEc4mwea8RRRm9rBTPtvXTv96Jeb/uRiivJsMbPnp6axGPNIUnQypCtbXHivWeK4JwvhTNzrEbHlIOUz/ZYYVuOPN53OyIdDAE5d2hWwKWs044KaQN2woKu6N3m3HYE5/aK/QLC1weFC4zd+o/N3q6bKpqIiACIhAVAupUBBKNgERzol3RIPOhKHv85yw8e/3GwnjiR7uuw8PfZYW8mY9icsC7tcFl5+wYY8b+sj/2G2TIEmcH0j1UfAAAEABJREFUimkON4bavuGPXxachvALAL8o8AuDM98+ZrjG6kV5mGi+JNh5Jd2HsuGv74ougUdBX7tRWpFVStyOzdAMLTPnlpbqiYAIiIAIiED4BCSaw2cW8xYUrf4rVVCsBlr5gnHHdvwv242YVrfwp367zYcFjazY5AnbGgYVzM5+OGH2xfp2mAPHZn8sC5RY399m1qNtTDy2E+vadvLYOY49HvNYZrex9+yLyT6394zdDmQj+2BfLGc7JrsN95wT23H+PGdim0BzYZmd2I+zDfM5Bvtinzy3E/ujDcd3qWStxc16LGN7Z/1AfbKef9Iyc/5EdC4CIiACIiACkScg0Rx5pupRBGJKoDCWObzn3cTURg0mAlEhoE5FQAREIIYEJJpjCFtDiUCkCWiZuUgTVX8iIAIiIAIiEJhAtERz4NGUKwIiEFECrwzcjIOPSbceXBPRjtVZQhBYvHgxhgwZopQkDB544AHY6f7774d/uu+++8Ck10TZvSf4nkyID5cknYREc5JeeE07MQiUr+QLGpeeGDMs61l4d/w2bdqgd+/eCZ1atmyJv/74A+3atUvoebq5jo0aNcJvU6dixp9/YqZJc2bMwNyZMzGPadYszDdpoUkzDK/KlSolPS83TKNVh+9N736yJLflEs3Jff01+wQgkFZewcwJcBkjPoVOnTohkVNmZiZefPFFVN++HaNHjULDhg0Ter6hruUhhxyCOikpOMjwaGFSs23bcGBODpoybd2KJiYdYI5r7t6N7OzspGYVimUsyiP+hg/VocojQkCiOSIYE6sTPiGQS7zZy8txz3Pm2zPlg1KY75+cD0Hxr+NcI5plzrrsl+XO/q5uvKLw6X1c85jnbMe6dmIfdh7tu6HtKquNm/p2H8WNa9fRXgREIH4ILF++HL2uvhoHFBSgtjGrbm4urrvmGuSavTlNyq1cuXKAL/QXaNbYvWsX9E8ERCB8AhLN4TNLihb+j7LmY7O5TjOFqQ2AaxrbS8LZey6bxnIKWT7hjo+nZhkflc11oSlQWe6fKH5Zznqsz3R23ww8dtm6Ig8amTxhO5w2+Pfjfx6qvttx/fuN4Lm6EgERCJNAz+7dUXHLFtTY1662Ec/bli1Dn+uu25eTfLu0tDTAeJpDzdxnKuzZs8f81SYCIhAuAYnmcIklaX2uJcyn6304YmtIAjtzCkDBfMRZFVEhgx/RsOJu2Z4i1r8DeoX5sBQKc65hbJdTlG/bVIBlc/Z+wGdUT0HbThUw5taNRYS0Xd9/H6q+23H9+9W5CIhA2RGgR3ntvHnIys8vYkS93bvx63ffYdjQoUXyk+UkHE/zHsMq8lzUowgkPgGJ5sS/xhGbIUUvxTBFcXGdUihTMI/7v02gx9muy4d1MNnn9j7Yk/P4UBA+9MQppM+/KdNqFuyJflah409x9cMZ19GlDkVABMqIwENDhuDnr79G/SCiL2vbNjzz9NP4+OOPy8jCshvW8jS7Dc+Qp7nsLpRG9jQBiWZPXz53xker1lcvbYMzBtkZ98wwjXErsvHnN7sK6zgFtL9NWU1SUSlz78uR4Rfsy+7bGdJR0dS58NYqePb6jaCn2L8f//NQ9d2O69+vzkVABGJL4I033sC40aNRb8eOoAOnm5L6O3fi+n79MHfuXHOWPFs4olme5uR5XWimkSWwV6VEtk/1lqAElszcGyZhT4/hE4w9ttMEv8dy01PMx0KznLHN9FIzhthu79yvXpSH7Vv3/txKzzL7YptWJ5V3VrOOGSrSumN5ULRbGSH+FFc/nHFDDKNiERCBKBH46aefcNutt4KCuFyIMaqY8jrGE927Vy8UFBSYs+TYGJ5R4NLTvEee5uR4UWiWEScg0RxxpInb4VIjmus0TiuMU0aQf/QA/6fj6iKeYDtkg334N2t2ZLqVZYdLWCch/px7QyY+enorZv/k7i7wQPVLMm4Is1QsAiIQYQLLli3DNVdfjcZGAFd22TdvDNyyZAn69u7tsoX3q1meZhfT4F0mEs0uQKmKCAQgEBnRHKBjZSUWAYZI8CY+is9QM6OHmeKaMc12XQpp3uzX8JD9/USsz5UyHu26rsjKGBONKP7r28CimN7oc/pl4n/vB/+p1h6b+0D1SzIu+1ISARGIHYGru3VDZcdKGW5HrrdrF3786iuMGD7cbRNP15On2dOXT8Z7hIBEs0cuVKzN3Lo+HzcfuaowHpmC9uHvsqxVMGxbGB5hxx3beztu2b7hz87vVn85KIwZ62y3d+6Zz/65rJ3dhiKbcdEMr3DWtY87G9EcKHzDLvffB6pfknH9+9V54hDQTOKLwDU9emD9/PnIMl7mklhWd9s2jHjySUyaNKkkzT3Vhp5mN8Eo9DQn83rWnrqoMjbuCEg0x90lKXuD6JVlTDFjke3Ec+bb1lEU22XOPfOD1aFAdZY5z5nP/jmO3R/joekNZhn3I6bVLSLaGfLx0DdZsMdke9ZhXSYeM4/tmfzrM4+JdYKNy3IlERCB2BN48IEH8Mu336J+KeJvGfhV33icr+/bFwsWLIj9JGI4Ij3NboajaFZ4hhtSnq4j46NEQKI5SmDVrQiIgAiIQMkIvPbqq3j5hReQvXNnyTpwtKpqjmsY4dzn2mvNUeJu9DTvvZW6+DlSNMvTXDwjlYpAMAISzcHIKF8EokFAfYqACBRLYPLkybjzzjutlTLSiq3pvrBOfj42LFqE/v36uW/ksZoUzQrP8NhFk7meIyDR7LlLJoNFQAREIDEJLF26dO9KGUbkul0pwy2JesZr/d3nn+Ppp59228RT9Rie4WaJvUh5mj0FR8aKQIQISDRHCKS6EQEREAERKB2BHldeicycHFQvXTdBW2eZvoc9/ji++OKLoHW8WkBPc74L4yWaXUBSFREIQkCiOQgY72bLchEQARHwHgEuLbdh4cISr5ThZsZ8VFL2rl3o17cvFi9e7KaJZ+qE5WnOy/PMvGSoCMQTAYnmeLoaskUEREAEkpDAfYMGYcp33yE7N/ef2UfpiDcGVt+xA32uuy5KI5RNt5an2cXSfPI0l8310aiJQUCiOTGuo2YhAiIgAp4kMGTIEIx78UVUMh7gDWYGG/elTWa/eV/aYvZMW83ezcZHIu02FZn2mD0T5TgTfaw1jad1zfz5uPGGG0xpYmz0NOe7FM15Zv6JMWvNQgRiS6Akojm2Fmo0ERABERCBhCVwyimn4PiOHXH4+efj0HPOQYszzsCBp56KRieeiHrHHovaRx+N6kccgZRmzbC6QoWQHHJMjSUZGVhdqxZW1qiBpdWq4e8qVbCwcmXMr1gRc0wfM9PTsW7PHnw2aRJ276a0No08vlme5vzQUc30NEs0e/xiy/wyIyDRXGboNbAIiEDZEtDo8UCgQ4cOGDduHEY+8wyeHzUKLxiv87iXX8arb7yBNydMwNvvvov3PvwQDz36KCoasevG5kYNG2La9OmY/tdfmDFzJmbNno058+Zh3oIFWLBwIRYtXoy/lyzBrDlzkO6yTzfjlmUdSzS79DTnytNclpdKY3uYgESzhy+eTBcBERCBZCGQ78KLShZcqzg1NZWHSZWs8AyXjORpTrCXhqYTMwISzTFDrYFEQAREQARKSiAcoZeMopme5jyXnuY8l+K6pNdK7UQgUQlINCfqldW84oGAbBABEYgQAYpmxuOG6s7yNKck339tbj3NZEiWoTiqXAREYH8CyffJsj8D5YiACIiACMQ5gXDCM1JSky88g951t08E5KV2y5N1Af0VAREgAYlmUlASAREQARGIawL0jvpchB9wEhSQ3CdbSk1JAT3toeadmpKCPXu4EF+omioXARFwEpBodtLw4LFMFgEREIFkIODWM0rRmKyiOcWIYc4/1OuB9XJj8CCZUHaoXAS8RkCi2WtXTPaKgAiIQOIRCDkjy9McstbeCimpyReewZmnmXm7Ec2pKSmQaCYxJREIj4BEc3i8VFsEREAERKAMCFA0uxmWopHi0U3dRKtDDzvnH2peKT6fwjNCQVK5CAQgEFo0B2ikLBEQAREQARGIJQErPEMxzYXIedMf45J37NiBLVu2YMOGDWDYhRvRnG84fvHFF5g4cSLee+89jB8/Hq+//jpeeukljBkzBs899xyeeuop/N///R9WrFhROKYORCDZCUg0J/srQPMXgSQhoGl6m4DlaTZiL9QsKBrpcQ1VzyvlFMZNDjgAzZo2RVOzb9yoERo0aIDs7Gw0bdIELQ8+GG0POwxHH3UUKroMz6iblobHBg3C/bffjoeMMH787rvx5L334un77sNzDz6I0Q89hLGPPILxb7yBd955xyuoZKcIRJ2ARHPUEWsAERABERCB0hKwPM0uOikwdRJJNHP95XZt26KG+cJw8O7daJWbi7b5+TjCzJP71nv24NBdu3Cw8Thnb9qEdJMfaquxbRvqG+90nc2bUYf7rVtRJycHdbZvR9bOnahrxilIT8e/unbF9ddfH6o7lceWgEYrQwISzWUIX0OLgAiIgAi4I+DW08zeEkk0cz5jX3oJ6fXrY7PxJPM/bT6ghPnRSmvMOA1atsSQhx+O1hDqVwQ8SYDvP08aLqNFIO4IyCAREIGoEbA8zcbbGmqAAlMhNS3N/E2crUqVKhg9ZgzWlC+PzVGe1ibT/9bKlfHM88+bI20iIAJOAhLNTho6FgEREAERiEsClqfZpWWJ5mnmtA8++GA8+9xzWJqejh3MiELaZfpcUb48nho5EvWNZ9ucahMBEXAQkGh2wNChCIiACIhAfBKwRHOSeprtK3Lqqafivvvvx6rMTOTamRHcr8nIwK23345TTjklgr2qKxFIHAIpiTOVZJiJ5igCIiACyUkgnPCMRF6n+corr8TlV12FNUY4R/KVsKpCBRxrxHLfvn0j2a36EoGEIiDRnFCXU5MRAREQAQ8QKIGJbj3N7DrRYpo5J2e6a8AAtO/YEasrVXJml/h4XUoKMho0AMMyStyJGopAEhCQaE6Ci6wpioAIiIDXCYTjaU7EmGb/6/fMc8+hTosWWFuunH9RWOdbTe0VRjSPNP3x4SjmVJsIiEAQAv6iOUg1ZYuACIiACIhA2RGgp5lPwXNjQVqCrZ4RbM6jX3gBu6tXxwZfyRahY1w0vdXDR4xAy5Ytgw3jqfzp06fjwgsvRLdu3ZRizIDcyd9TL5gwjZVoDhOYqouACHiBgGxMNAIUzUjyGwH9r2ndunUxaswYLDGimR5j//JQ54yLvqJ7d1xwwQWhqnqm/PPPP0e9evVwxRVXKMWYAbmTv2deLCUwVKK5BNDURAREQAREILYE3IZn0KpkCM/gPJmOOOIIjHzmGayoWBFcMo55btLa8uVx8OGHY8Ddd7up7qk6Bx54IDp16pQYyUPzIHdPvVBKYKxEcwmgqYkIiIAIiEBsCdDTXJCfH3JQPtykXCnjfEMOEmcVzj33XNxy221YnZkJzh8h/m00nunc6tXxtBHbIaqqWAREwHSZoDsAABAASURBVEFAotkBQ4ciEAYBVRUBEYghAYpmn8vxkvGGtt59+uCciy7CqoyMYintMKVLUlKslTKqVatmzrSJgAi4JSDR7JaU6omACIiACJQZgbxc3rbmYngjCJMpPMNJZMhDD6HlUUdhTYUKzuzCY3qh+QCT+x94AB06dNiXr50IiIBbAhLNbkmpngiIgAiIQJkRyM3LgxtPs8/nQzJ6mrHvH28MrNSwIdalpu7L+WfHlTLOPO88a1WJf3J1JAIi4JaARLNbUmVQT0OKgAiIgAjsJeDa02xEc7J6mkmqgvEycym6TZUrYyMz9qV15cqhTvPmePTxx/flaCcCIhAuAYnmcImpvgiIgAiIQDgEIlI3NzfXlacZRjQns6eZsLmKwfOjRmGJ8TZvMxmbTdpYvjxGPvusOdImAiJQUgISzSUlp3YiIAIiIAIxI7Bjxw5w7Yw8MyITjxmjy2Sy/tmMaE5mT7MN4oQTTsCjjz1mLUW30nifRzz1FBo3bmwXay8CIhA2AUCiuQTQ1EQEREAERKB0BIYOHRrWwyem/vYbtmRkYIFJ802aZ9KcypXBNNvs7bQ5PR1vvfVWWH0n6oMwJk6ciKzsbDQwYvmll16KORNe49K9StRaBOKLgERzfF0PWSMCIlACAmriTQJZWVk47rjjXKUuXbrg5ptvxk0mcc90yy23wD8x/+KLL3bVp9uxvVyv62WX4dJLL405D15bb74qZbUIBCcg0RycjUpEQAREQASiTKB9+/ZQSjwGUX7ZJGr3mlecE5BojvMLJPNEQAREQAREQAREQATKnoBEc9lfA1ngBQKyUQREQAREQAREIKkJSDQn9eXX5EVABERABJKJgOYqAiJQcgISzSVnp5YiIAIiIAIiIAIiIAJJQkCiOW4utAwRAREQAREQAREQARGIVwISzfF6ZWSXCIiACHiRgGwWAREQgQQlINGcoBdW0xIBERABERABERABESgZgUCtJJoDUVGeCIiACIiACIiACIiACDgISDQ7YOhQBETACwRkowiIgAiIgAjEnoBEc+yZa0QREAEREAEREIFkJ6D5e46ARLPnLpkMFgEREAEREAEREAERiDUBieZYE9d4XiAgG0VABERABERABESgCAGJ5iI4dCICIiACIiACiUJA8xABEYgkAYnmSNJUXyIgAiIgAiIgAiIgAglJQKK5jC6rhhUBERABERABERABEfAOAYlm71wrWSoCIiAC8UZA9oiACIhA0hCQaE6aS62JioAIiIAIiIAIiIAI7E/AXY5EsztOUav13evbcf95a5XEoESvAb5+ovbiVMciEEUCP/74I2bOnIm7775bKQEZ8Np+/vnnUXwFqWsRiD0BiebYMy8c8fJ7q+Lqx6rhjF4ZSmJQotcAXz98HRW+qBLwQFNKTAJZWVmoWrUqDj74YKUEZLB8+XLMmTMnMV+8mlXSEpBoLuNL3/7cilASg9K8Bsr4JazhRaBEBA488EBkZ2fjiiuuUEpABp06dUJeXh7uuOOOEr0+ErCRppQABCSaE+AiagoiIAIiIAIiEG8EjjjiCIwfPx7fffddvJkme0SgRAQkmkuETY0SioAmIwIiIAIiEHECHTp0QGpqKm677Tbs2LEj4v2rQxGINQGJ5lgT13giIAIiIAIiEAUC8dZlWloa+vTpg4yMDAwYMCDezJM9IhA2AYnmsJGpgQiIgAiIgAiIgBsC11xzDRYvXoxp06bh9ddfd9NEdUQgbglINMfk0mgQERABERABEUg+AlwhhcK5efPmlrd5wYIFyQdBM04YAhLNCXMpNREREAERiDIBdS8CJSBA0Txx4kQrVOOuu+4qQQ9qIgLxQUCiOT6ug6wQAREQAREQgYQkUKdOHVA479q1C5UrV8bQoUMTcp6alHcIlNRSieaSklM7ERABERABERABVwQomkePHo0777wTL774Ir7//ntX7VRJBOKJgERzPF0N2SICSU9AAERABBKRQMOGDXHZZZfhgw8+wJAhQ8AwjZ07d0L/RMBLBCSavXS1ZKsIiIAIiIAIeJQAvc2jRo3CqaeeipNOOsm6MdCjUwlttmokJIGUhJyVJiUCIiACIiACIhBXBA488EB07twZDNN44IEH8Ndff+GNN96IKxtljAgURyCluEKViUACEtCUREAEREAEyogAvc0Uzbm5uXjwwQctb/PChQvLyBoNKwLhEZBoDo+XaouACIiACIhAHBDwpgmHHHIITjzxRMvbfOSRR+K2226z4pu9ORtZnWwEJJqT7YprviIgAiIgAiJQhgRsbzNN4GO2K1asiGHDhvFUSQTimoBEcxQuj7oUAREQAREQAREITKBdu3Zo27attfQca3A1jTFjxuCHH37gaczS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Zp/h2uF6MFUsJJDEormQgQ5EQAREQAREQAREYD8CFLz0DFPgMoaYFbjv2bMnuHQbxSq9vfQac5UNljNxRYthw4aB9Xjun2zR+9NPP/kXuT6nTfSCc2w2KokdbKfknoBEs3tWqikCIiAC8UdAFomACESVAFfFoHBmDDHXSeae58znwBTW33zzDXgjHsuZKGgpZm1PNev5J9ZhiIV/vttzjks72A+FPM/d2OEfG831o+k5dztuMteTaE7mq6+5i4AIiIAIiIAIhCRAgWyvm8w9z52N6HHmahosY+JDVihi7ToUz1988UWRUA2Ws55/X8OHDweT3ZZ7tp8yZQq457md2JZ9sC/mubFjwYIF1nrTtJOJ5/79sq9YJy+MJ9HshaskG0VABERABERABERABMqUgERzmeLX4CLgBQKyUQREQAREQAREQKJZrwEREAEREAEREIHEJ6AZikApCUg0lxKgmouACIiACIiACIiACCQ+AYnmxL/GXpihbBQBERABERABERCBuCYg0RzXl0fGiYAIiIAIeIeALBUBEUhkAhLNiXx1NTcREAEREAEREAEREIGIEEga0RwRWupEBERABERABERABEQgKQlINCflZdekRUAEPEpAZouACIiACJQRAYnmMgKvYUVABERABERABEQgOQl4c9YSzd68brJaBERABDxPYPHixRgyZEhU04ABA+AmRduOsur/gQceAFOsx+e19fwLVBMQAT8CEs1+QHQqAslOQPMXgVgQaNOmDXr37h3VVLduXcydORNL5s4tNrEO60bbnrLof9HChVi8aFFUOQebF69xLF5LGkMEYkVAojlWpDWOCIiACIhAIYFOnToh2qlp06aonpuLA3fuLDaxDutG255Y9//+u+8idcsW+DZvxqcffxx13oHmV3jBY3+gEUUg4gQkmiOOVB2KgAiIgAiIQNkSeHLYMHw3aRLq79plpc8mTsTzzz9ftkZpdBHwOAGJZo9fQE+aL6NFQAREQASiRuCDDz7AyKeeQr0dO6wxfOZv3W3b8NCQIfjmm2/MmTYREIGSEJBoLgk1tREBERABEUh6AvEIYNq0aejXty/q79yJdIeBFcxxg9270ee667B06VJzpk0ERCBcAhLN4RJTfREQAREQARGIQwIbN25Er5490bCgAJkB7Ktm8qps347rrrnGHGkTAREIl0CCiuZwMah+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LW5kN3ToUOzYscNubu1DjVvaMTh/2kI2nBcTj52c7DH4vnz00UcL58BfPBh+xetvGbvvD+d11VVXYfDgwUXev/uKtYtjAhLNcXxxktm0TavzsHJBLjauzMP2LfnIy01mGpq7lwmkpKSga9euaNeunSXO+J98sPnwP1MKlIMPPhgUc8HqtW7dGm3btsX//vc/0JNp1wtnLLtNafYUrvSUHnDAAWDoSDh9lXSudjvyCTYmH6s9bNgwMNEr77SLTxSk6KbAoQCiEKMX3VmnuONwGO/evRuMia5bty4o4oP1W79+fdDT/K9//StYFSufjw2nMKXXmoKficf8BYAhORR4o0aNAoUbX28MWWEoSGZmJp588km8//77Vj/84+jL+vLg3xfrME2bNg38hYMinCFC/JLCvtie5Uyc4+WXXw7GmNPLz8QYbtrqrMe6gRLrPP7449b7hHbQk8/rc80111hfeiguTzvtNPCXl5dffrmwi3DGLekYX3/9NXr37l04N9pH5oHm9vnnn4NietCgQdZczjjjDMtWPojHOtj3h58BTPyS4PP59uVq5wUCEs1euEpJaONPE7bjxlYrcV3TFbii1nJcmL4EF6QtQZdKS/Hv6svQve5yXNdkBW44ZCVuP2oV7um4Gg92Xothl63DM9dtwNg7NuGtB7fgwxFb8dmYHHz3+nb874Md+OOLnZj90y4smr4HK+fnYgNF+eZ8ifIkfI3FcsoZGRm48cYbQW/sf//736BhGiznzXNNmjQBQw+C2VipUiXUq1cPq1atAkMcnPXcjuVs4+aYY9GDe+SRR1qeNO7PO+88K0SEgoceWDf92HVKOle7XaNGjUAxaPfnZk/BTC8pRRiPGZZBlm7aOuu4ZcyY6sWLF1te7HBtdY7HY/bFmyX5herVV1+1RFlX82WMXnL2/e2331pfoCjQGG/O+Gl6mBkKwtccrw/jt932xXpM9ITzy0fPnj2tEKGHH34Y7IuClSKddr3wwgs48cQTwfhyhsgw0dZTTjnFupmVddhXcckeg3O66aabrJtIDz30UOsLAEOT/u///g+M76eIp7eZfYY7brhj8NcchtQcdthh4FicF+2jcOd14Bxphz2vatWqWV8weBMsveUHHXSQ9WV58uTJlvi36/3444/gFyn2Yedp7w0CKd4wM0mtTOJp79lVgKY7C3CISW32FODwAqBN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lDkBieYyvwQyQAREIBYEcnJy9vMS2OEYdRo2xLz583HppZfGwhSNIQIiIAIi4EECEs2lv2jqQQREwAMEcrZuLSKa7XCMzuedhx8mT0ZaWpoHZiETRUAEREAEyoqARHNZkde4IiACMSWwzeFpnlOuHBiOMWLECDz99NMxtSN+B5NlIiACIiACxRGQaC6OjspEQAQShsD2HTuQa2bzR2oqsho2xIKFC8E1n02WNhEQAREQgUQhEMV5SDRHEa66FgERiB8CfNrgdmPO+RdcgO9/+AEpKfr4Mzi0iYAIiIAIuCSg/zVcglI1ERCBUhMo0w7eefll/Pe//7VSmRqiwUVABERABDxJQKLZk5dNRouACIRLoPUxx+Diiy8Ot5nqi4AIiIAfAZ0mK4Ggonnm3Km46bbrlMQg5q8BvvaS9Q2peYuACIiACIiACMQngYCiudnh6Tj5liVKYlBmrwG+BkvyllEbERABERABERABEYgGgYCiuf25FaEkBmX9GojGC159ioAIiIAHCMhEERCBOCQQUDTHoZ0ySQREQAREQAREQAREQATKjIBEc7joVV8EREAEREAEREAERCDpCEg0J90l14RFQAREABADERABERCB8AhINIfHS7VFQAREQAREQAREQATig0BMrZBojiluDSYCIiACIiACIiACIuBFAhLNXrxqslkEvEBANoqACIiACIhAAhGQaE6gi6mpiIAIiIAIiIAIRJaAehMBm4BEs01CexEQAREQAREQAREQAREIQkCiOQgYZXuBgGwUAREQAREQAREQgdgQkGiODWeNIgIiIAIiIAKBCShXBETAEwQkmj1xmWSkCIiACIiACIiACIhAWRKQaC6evkpFQAREQAREQAREQAREABLNehGIgAiIQMIT0ARFQAREQARKS0CiubQE1V4EREAEREAEREAERCD6BMp4BInmMr4AGl4EREAEREAEREAERCD+CUg0x/81koUi4AUCslEEREAEREAEEpqARHNCX15NTgREQAREQAREwD0B1RSB4AQkmoOzUYkIiIAIFEtgzpw5uPXWW5XEQK8BvQYi+hrgZ0uxHz4qLBMCEs1lgl2DloSA2ohAPBFo06YNrr76aiUx0GtAr4GovAb4GRNPn3myBVpyTi8CERABESgJgU6dOkFJDErwGtDrRu8d16+Bknw2qU30CMjTHD226lkEREAEREAEREAERCBBCEg0Oy+kjkVABERABERABERABEQgAAGJ5gBQlCUCIiACXiYg20VABERABCJPQKI58kzVowiIgAiIgAiIgAiIQOkIxF1riea4uyQySAREQAREQAREQAREIN4ISDTH2xWRPSLgBQKyUQREQAREQASSjIBEc5JdcE1XBERABERABERgLwH9FYFwCEg0h0NLdUVABERABERABERABJKSgERzUl52L0xaNoqACIiACIiACIhA/BCQaI6fayFLREAEREAEEo2A5iMCIpAwBCSaE+ZSaiIiIAIiIAIiIAIiIALRIpDMojlaTNWvCIiACIiACIiACIhAghGQaE6wC6rpiIAIJBsBzVcEREAERCAWBCSaY0FZY4iACIiACIiACIiACAQn4IESiWYPXCSZKAIiIAIiIAIiIAIiULYEJJrLlr9GFwEvEJCNIiACIiACIpD0BCSak/4lIAAiIAIiIAIikAwENEcRKB0BiebS8VNrERABERABERABERCBJCAg0ZwEF9kLU5SNIiACIiACIiACIhDPBCSa4/nqyDYREAEREAEvEZCtIiACCUxAojmBL66mJgIiIAIiIAIiIAIiEBkCySOaI8NLvYiACIiACIiACIiACCQhAYnmJLzomrIIiIB3CchyERABERCBsiEg0Vw23DWqCIiACIiACIiACCQrAU/OW6LZk5dNRouACIiACIiACIiACMSSgERzLGlrLBHwAgHZKAIiIAIiIAIisB8Bieb9kChDBERABERABETA6wRkvwhEmoBEc6SJqj8REAEREAEREAEREIGEIyDRnHCX1AsTko0iIAIiIAIiIAIi4C0CEs3eul6yVgREQAREIF4IyA4REIGkIiDRnFSXW5MVAREQAREQAREQAREoCYFEFc0lYaE2IiACIiACIiACIiACIhCQgERzQCzKFAEREIF4ICAbREAEREAE4oWARHO8XAnZIQIiIAIiIAIiIAKJSCBB5iTRnCAXUtMQAREQAREQAREQARGIHgGJ5uixVc8i4AUCslEEREAEREAERMAFAYlmF5BURQREQAREQAREIJ4JyDYRiD4BieboM9YIIpCQBH7/60dc0eNiJTHQa0CvAb0G9BpImNcA/28L9p+2RHMwMsqPGAF1lHgEmh2ejuP6zVcSA70G9BrQa0CvgYR7DfD/uED/c0s0B6KiPBEQgWIJtD+3IpTEIMleA3rN632v10ASvQYC/Sco0RyIivJEQAREQAREQAREQAREwEEgMUSzY0I6FAEREAEREAEREAEREIFIE5BojjRR9ScCIiACJSSgZiIgAiIgAvFLQKI5fq+NLBMBERABERABERABrxFIWHv/HwAA///JK/WIAAAABklEQVQDACS2e3tT/dksAAAAAElFTkSuQmCC" style="cursor:pointer;max-width:100%;" onclick="(function(img){if(img.wnd!=null&&!img.wnd.closed){img.wnd.focus();}else{var r=function(evt){if(evt.data=='ready'&&evt.source==img.wnd){img.wnd.postMessage(decodeURIComponent(img.getAttribute('src')),'*');window.removeEventListener('message',r);}};window.addEventListener('message',r);img.wnd=window.open('https://viewer.diagrams.net/?client=1&page=0&edit=_blank');}})(this);"/>


Whenever data is transferred through the memory hierarchy, it must eventually pass through the **Memory Management Unit (MMU)** because we need to manage virtual addresses and translate them into physical addresses. This is another fascinating part of computer architecture that I learned about, including the **page table, page-table walker, and TLB structure**.

I am not going deeply into virtual memory in this design, but understanding these components helped me understand how modern processors manage memory.

So, what does my current design look like?

The **L1 instruction cache** is connected to an **arbiter**, and the arbiter is connected to a **buffer**. The **L1 data cache** is also connected to the same arbiter.

This raises an important question:

**How does my arbiter behave?**

More specifically:

**What is the arbitration policy?**

The arbiter in my design uses a **fixed-priority arbitration policy**. The **L1 instruction cache has the highest priority**, followed by the **L1 data cache**.

In other words:

**L1 I-cache → Highest Priority**  
**L1 D-cache → Lower Priority**

Why did I choose this approach?

If the data cache is stalled for a longer period of time, I believe that is acceptable because I am assuming an **out-of-order processor**. The processor can tolerate data-access latency to some extent by continuing to execute other independent instructions.

But the instruction path is different.

There is no equivalent mechanism that can completely hide an instruction-fetch delay. If the **fetch unit cannot fetch the next instruction**, the processor cannot continue normally because the following stages depend on the instruction stream.

If instruction fetch stalls, the pipeline can eventually stall as well.

Therefore, I want to make the **instruction path as fast as possible**, with low-latency access and minimal waiting time.

This is why I give the **L1 instruction cache higher priority in the arbiter**.

I do not claim that fixed-priority arbitration is universally the best approach. Other policies, such as **round-robin, weighted priority, or dynamic arbitration**, could provide better fairness or throughput depending on the workload.

However, considering the overall architecture and my assumption of an **out-of-order processor**, I believe that giving the instruction path fixed priority is a reasonable and potentially optimal design choice for my system.

The fundamental idea is simple:

> **Data latency can sometimes be hidden by out-of-order execution, but instruction-fetch latency directly affects the ability of the processor to make forward progress.**

Therefore, my arbitration policy is designed to protect the **instruction-fetch path first** and allow the data path to tolerate more latency.

![[Pasted image 20260816234215.png]]
## Module L1​_interface
This design unit is implemented in `L1​_interface.sv`
This file depends on: `Dependencies are not calculated in the Documentation View`
### Parameters and Ports
#### Parameters

|Name|Type|Default Value|Description|
|---|---|---|---|
|`ADDR​_W`|`int`|`64`||
|`L1​_LINE​_BYTES`|`int`|`32`||
|`L2​_LINE​_BYTES`|`int`|`64`||
|`L1​_LINE​_BITS`|`int`|`L1_LINE_BYTES * 8`||
|`L2​_LINE​_BITS`|`int`|`L2_LINE_BYTES * 8`||
|`MSHR​_ENTRIES`|`int`|`8`||
|`TAG​_W`|`int`|`3`||
|`GTAG​_W`|`int`|`TAG_W + 1`||

#### Ports

|Name|Direction|Type|Description|
|---|---|---|---|
|`clk`|`input`|`wire logic`|Clock / Reset|
|`rst​_n`|`input`|`wire logic`||
|`i​_req`|`input`|`wire pkg::l2​_req​_t`|request from L1 instruction cache memory|
|`i​_req​_ready`|`output`|`logic`|IF l2 is ready then we have to accept the data|
|`i​_resp`|`output`|`pkg::l2​_resp​_t`|same for this|
|`i​_resp​_ready`|`input`|`wire logic`|valid ready handsake|
|`d​_req`|`input`|`wire pkg::l2​_req​_t`|request from data cache|
|`d​_req​_ready`|`output`|`logic`|L2 is ready then request come|
|`d​_resp`|`output`|`pkg::l2​_resp​_t`|responce to the l1_data memory|
|`d​_resp​_ready`|`input`|`wire logic`|give responce when ready is there|
|`l2​_req​_valid`|`output`|`logic`|L2 Request Channel|
|`l2​_req`|`output`|`pkg::l2​_if​_req​_t`||
|`l2​_req​_ready`|`input`|`wire logic`||
|`l2​_resp​_valid`|`input`|`wire logic`|L2 Response Channel|
|`l2​_resp`|`input`|`wire pkg::l2​_if​_resp​_t`||
|`l2​_resp​_ready`|`output`|`logic`||

### Always Blocks
- `unnamed : always_comb`
    - Request Arbitration Fixed Priority: I$ > D$

- `unnamed : always_comb`
    - Response Routing

---

When I started designing the cache, I initially thought that I needed to implement a **buffer specifically for Clock Domain Crossing (CDC)**.

CDC is a very important aspect of modern processor and SoC design. Most modern SoCs are **Globally Asynchronous and Locally Synchronous (GALS)**, meaning that different parts of the system can operate in different clock domains while remaining locally synchronous within each domain.
To safely transfer information between different clock domains, we need a specific type of buffer. One common approach is an **asynchronous FIFO**, which uses separate read and write pointers to safely transfer data between clock domains.
However, implementing a complete CDC infrastructure is itself a large project. Since I am working on this architecture as an individual, I realized that trying to implement every part of a modern SoC at once would make the project unnecessarily large and difficult to manage.
Therefore, I decided to keep CDC as a future extension of the design.
In the current implementation, I still have a **buffer**, but it is a simple synchronous buffer and does not include dedicated CDC support.
This allows me to focus on the core objective of the project: **designing and understanding the non-blocking cache architecture**, while keeping CDC as a separate area for future development.

How did I decide what should be the size of the buffer ? 
    -->  I think the answer is in the famous little law of queueing 
    In mathematical [queueing theory](https://en.wikipedia.org/wiki/Queueing_theory "Queueing theory"),  is a theorem by [John Little](https://en.wikipedia.org/wiki/John_Little_\(academic\) "John Little (academic)") which states that the long-term average number of customers (_L_) in a [stationary](https://en.wikipedia.org/wiki/Stationary_process "Stationary process") system is equal to the long-term average effective arrival rate (_λ_) multiplied by the average time that a customer spends in the system (_W_). Expressed algebraically the law is

       L=λW
this is the way to decide what should be the size of buffer  but for that we  need to do lot's of simulation workload analysis

![[Pasted image 20260816234420.png]]

## Module buffer
This design unit is implemented in `buffer.sv`
This file depends on: `Dependencies are not calculated in the Documentation View`
### Parameters and Ports
#### Parameters

|Name|Type|Default Value|Description|
|---|---|---|---|
|`T`|`type`|`logic [31:0]`||
|`DEPTH`|`int`|`8`||

#### Ports

|Name|Direction|Type|Description|
|---|---|---|---|
|`clk`|`input`|`wire logic`||
|`rst​_n`|`input`|`wire logic`||
|`in​_valid`|`input`|`wire logic`|Input Interface|
|`in​_data`|`input`|`wire buffer.T`||
|`in​_ready`|`output`|`logic`||
|`out​_valid`|`output`|`logic`|Output Interface|
|`out​_data`|`output`|`buffer.T`||
|`out​_ready`|`input`|`wire logic`||

### Always Blocks
- `process : always_ff`
- `reset : always_comb`

---

Talking about the **cache top module** in RTL, I wanted to make the architecture flexible from the beginning.
For communication between different blocks, I created **packed transaction structures** inside `pkg.sv`. I chose this approach because if I want to change the structure of any transaction in the future, I only need to modify the package instead of changing the interface definition across every module.
This gives the hardware design much more **flexibility and scalability**.

I also wanted the entire cache architecture to be **parameterized**. If I want to increase the cache size, change the number of ways, modify the cache-line size, or change another architectural parameter, I should not have to redesign the entire RTL.

For example, if I change a parameter in the **top module**, that change should propagate through the cache architecture and automatically adjust the relevant components.

This is one of the things I really like about parameterized RTL design:

> **Changing one parameter at the top should be capable of changing the entire cache architecture without rewriting the underlying modules.**

For me, this is not just about reducing the amount of code. It is about building the cache as a **scalable hardware architecture**, where the same RTL can be adapted to different cache configurations simply by changing parameters.

That is why I chose a **parameterized, package-based transaction architecture** for my cache design.

Here is my TOP module : 
![[Pasted image 20260817072448.png]] 

this is small black box of cache top if someone using sigasi studio they can visualise it

## Module cache​_top
This design unit is implemented in `cache​_top.sv`
This file depends on: `Dependencies are not calculated in the Documentation View`

### Parameters and Ports
#### Parameters

|Name|Type|Default Value|Description|
|---|---|---|---|
|`ADDR​_W`|`int`|`64`||
|`L1​_LINE​_BYTES`|`int`|`32`||
|`L2​_LINE​_BYTES`|`int`|`64`||
|`MSHR​_ENTRIES`|`int`|`8`||
|`TAG​_W`|`int`|`3`|this are the MSHR tag_ form which MSHR entries does this data belong|
|`LLC​_ADDR​_W`|`int`|`64`||
|`LLC​_LINE​_BYTES`|`int`|`64`||
|`L2​_MSHR​_ENTRIES`|`int`|`8`||
|`LLC​_TAG​_W`|`int`|`3`|there is also MSHR at the side of LLC|
|`TM​_TAG​_BITS`|`int`|`47`||
|`MSHR​_MAX​_SEC`|`int`|`3`||
|`NUM​_WAYS`|`int`|`4`||
|`NUM​_SETS`|`int`|`2048`||
|`INDEX​_BITS`|`int`|`11`||
|`WAY​_BITS`|`int`|`$clog2(NUM_WAYS)`||
|`L1​_LINE​_BITS`|`int`|`L1_LINE_BYTES * 8`||
|`L2​_LINE​_BITS`|`int`|`L2_LINE_BYTES * 8`||
|`REQ​_DEPTH`|`int`|`MSHR_ENTRIES`||
|`RESP​_DEPTH`|`int`|`MSHR_ENTRIES`||
|`LLC​_LINE​_BITS`|`int`|`LLC_LINE_BYTES * 8`|512|
|`GTAG​_W`|`int`|`TAG_W + 1`||
|`TM​_INDEX​_BITS`|`int`|`$clog2(NUM_SETS)`||
|`TM​_ADDR​_BITS`|`int`|`64`||

#### Ports

|Name|Direction|Type|Description|
|---|---|---|---|
|`clk`|`input`|`wire logic`|clock and reset_n|
|`rst​_n`|`input`|`wire logic`||
|`cpu​_req​_valid`|`input`|`wire logic`|cpu side L1 side|
|`cpu​_req`|`input`|`wire pkg::l2​_if​_req​_t`||
|`cpu​_req​_ready`|`output`|`logic`||
|`cpu​_resp`|`output`|`pkg::l2​_if​_resp​_t`||
|`cpu​_resp​_valid`|`output`|`logic`||
|`cpu​_resp​_ready`|`input`|`wire logic`||
|`mem​_req​_valid`|`output`|`logic`||
|`mem​_req`|`output`|`pkg::l2​_llc​_req​_t`||
|`mem​_req​_ready`|`input`|`wire logic`||
|`mem​_resp​_valid`|`input`|`wire logic`||
|`mem​_resp`|`input`|`wire pkg::l2​_llc​_resp​_t`||
|`mem​_resp​_ready`|`output`|`logic`||

### Instantiations

- `controller` : `srrip_controller`
- `MSHR​_CONTROL` : `MSHR_CONTROL_AND_TABLE`
- `global​_control` : `global_control`
- `data​_array` : `data_array`
- `tag​_compare` : `tag_compare`
- `tag​_memory` : `tag_memory`

---
### Why I Use SRRIP as the Replacement Policy


![[Pasted image 20260817073959.png]]

**what we have to make a system smart or intelligent?**
My smartphone's SoC, the **Snapdragon 730G**, fetches the same instructions, decodes them in the same way, uses the same arbitration, and accesses the same memory system. Nothing fundamentally changes from 2020 to today. That is not adaptive, even though workloads have changed completely.

From 2020 to today, the growth of **AI workloads** has added a significant amount of new computational demand.

But the semiconductor itself is rigid.
So, how do we make silicon intelligent?

The answer is **prediction**.

To adapt to changing workloads, we can use advanced **prefetching techniques, adaptive replacement policies, branch prediction, Quality of Service (QoS), adaptive routing policies**, and other prediction-based techniques. These mechanisms make the system more intelligent and capable of adapting to different workloads.

In my cache, I am not adding prefetching, but I am implementing a really good **cache replacement policy**.

In my first **8 KB cache**, I used **PLRU (Pseudo-LRU — Pseudo-Least Recently Used)** as the replacement policy. It works well for most types of workloads because, most of the time, workloads exhibit **locality**.

**What problem did I solve?**

The answer is: **the limitations of PLRU.**
PLRU tends to give higher priority to cache lines that have been used recently. This works very well for most workloads because most workloads exhibit **temporal locality**.

But what if I have a workload where I need to **read files and transfer them to another location**? This type of workload is common in servers and can involve large amounts of streaming data.
Here, the problem with PLRU becomes visible. Recently accessed data may be given a higher priority even though it is unlikely to be reused. As a result, useful cache lines can be evicted.
This is a limitation that cannot be effectively solved by simply using PLRU.
Therefore, we need something better, such as **SRRIP (Static Re-Reference Interval Prediction)**.

SRRIP algorithm

as in above image  there is table of this SRRIP GOT  the state bit from each set and line
```
    localparam logic [RrpvBits-1:0] RrpvMax  = 2'd3;  // "distant"  (never used again soon)
    localparam logic [RrpvBits-1:0] RrpvLong = 2'd2;  // SRRIP insertion value (long re-ref interval)
    localparam logic [RrpvBits-1:0] RrpvNear = 2'd0;  // set on hit (near-immediate re-reference)    
```
this are the state of each line 
# How Do I Select a Cache Line for Replacement?
![[Pasted image 20260817083738.png]]

![[Pasted image 20260817102543.png]]

## Module srrip​_controller

This design unit is implemented in `srrip​_controller.sv`
This file depends on: `Dependencies are not calculated in the Documentation View`
### Parameters and Ports

#### Parameters

|Name|Type|Default Value|Description|
|---|---|---|---|
|`NUM​_SETS`|`int`|`2048`||
|`NUM​_WAYS`|`int`|`4`||
|`INDEX​_BITS`|`int`|`11`||
|`WAY​_BITS`|`int`|`$clog2(NUM_WAYS)`||

#### Ports

|Name|Direction|Type|Description|
|---|---|---|---|
|`clk`|`input`|`wire logic`||
|`rst​_n`|`input`|`wire logic`|active-low sync reset|
|`req​_valid`|`input`|`wire logic`|a lookup is happening this cycle|
|`index`|`input`|`wire logic [INDEX​_BITS-1:0]`|set index|
|`hit`|`input`|`wire logic`|1 = hit, 0 = miss|
|`hit​_way`|`input`|`wire logic [WAY​_BITS-1:0]`|valid only when hit==1 (0 on miss, per spec)|
|`victim​_way`|`output`|`logic [WAY​_BITS-1:0]`|valid only when hit==0 (the way to evict/fill)|
|`victim​_valid`|`output`|`logic`||

### Always Blocks
- `unnamed : always_comb`
- `srrip : always_ff`


# How Do I Track Multiple Outstanding Misses? 

Now, this is the **heart of the project**.
So, what do I have to do?

If I am sending data to the **L1 cache**, can I request other data from the **LLC** at the same time? Can I store data in the **data array** while also receiving another request from the L1 cache?
These operations are independent, and we have to make it possible for them to happen concurrently.
This will improve the overall **throughput** of the cache and is the fundamental idea behind **non-blocking behavior**.
If two operations are independent, **we should be able to perform them at the same time** instead of making one operation wait for the other to finish.

![[Pasted image 20260817110059.png]]


The table shown above represents **one entry in the MSHR table**. In my design, I have **8 entries in the MSHR table**.

There is one thing that I am not optimizing in my current design: I am **not adding a separate buffer for eviction data**.

When a cache miss occurs, we first need to find a **victim cache line**. If the victim line is dirty, we need to write it back to the lower level of the memory hierarchy. This introduces some additional overhead.

So, practically, for **one cache miss**, there can be **two memory requests**:

1. **Writeback request** — if the victim line is dirty.
2. **Refill request** — to fetch the requested cache line from the LLC.

This writeback path is the additional overhead that I am currently handling within the MSHR entry rather than using a separate eviction buffer.

In modern cache designs, an **eviction buffer** is important. In my design, I am adding the **eviction entries to the same MSHR table** and using them to write back dirty data.

This is not the most optimized approach, but considering the **complexity of the overall design**, I believe it is acceptable for my current implementation.

THE FSM OF MSHR :
there is nothing like one FSM  each entry in the MSHR table is one FSM so pratically there are 8 FSM  
```
000 MSHR_IDLE
001 MSHR_WB_SEND
010 MSHR_WB_WAIT
011 MSHR_FILL_SEND
100 MSHR_FILL_WAIT
101 MSHR_COMMIT
110 MSHR_RESP
```

each FSM is working differently 

![[Pasted image 20260817133404.png]]

The FSMs are independent, but there is one problem: what if there are **8 FSMs**, and two of them are in the **MSHR_FILL_SEND** state at the same time?

Even though the FSMs are independent, the **I/O interface is shared**. Two FSMs cannot send requests to the LLC in the same cycle.

The solution I used in my design is **fixed-priority arbitration based on the MSHR index**.

I give fixed priority to **MSHR[0]**, then **MSHR[1]**, and so on. Therefore, only one MSHR entry can access the LLC interface in a given cycle.

This is the idea behind **independent FSMs with centralized control of the data flow**.

> **The FSMs operate independently, but arbitration ensures that shared resources are accessed in a controlled manner.**


FSM state transition diagram for one MSHR Line

![[Pasted image 20260817162221.png]]
The IO diagram of MSHR BLOCK 
![[Pasted image 20260817164020.png]]

## Module MSHR​_CONTROL​_AND​_TABLE
This design unit is implemented in `MSHR​_CONTROL​_AND​_TABLE.sv`
This file depends on: `Dependencies are not calculated in the Documentation View`
### Parameters and Ports
#### Parameters

| Name               | Type  | Default Value | Description |
| ------------------ | ----- | ------------- | ----------- |
| `TM​_NUM​_WAYS`    | `int` | `4`           |             |
| `TM​_TAG​_BITS`    | `int` | `47`          |             |
| `TM​_INDEX​_BITS`  | `int` | `11`          |             |
| `TM​_OFFSET​_BITS` | `int` | `6`           |             |
| `TM​_ADDR​_BITS`   | `int` | `64`          |             |
| `GTAG​_W`          | `int` | `TM_TAG_BITS` |             |
| `L1​_LINE​_BITS`   | `int` | `256`         |             |
| `LLC​_LINE​_BITS`  | `int` | `512`         |             |
| `MSHR​_ENTRIES`    | `int` | `8`           |             |

#### Ports

|Name|Direction|Type|Description|
|---|---|---|---|
|`clk`|`input`|`wire logic`|CLOCK AND RESET|
|`rst​_n`|`input`|`wire logic`||
|`alloc​_req`|`input`|`wire logic`|ALLOCATE / SECONDARY MERGE PORT Driven by Global Control|
|`alloc​_index`|`input`|`wire logic [TM​_INDEX​_BITS-1:0]`||
|`alloc​_tag`|`input`|`wire logic [TM​_TAG​_BITS-1:0]`||
|`alloc​_way`|`input`|`wire logic [1:0]`||
|`alloc​_victim​_dirty`|`input`|`wire logic`||
|`alloc​_victim​_tag`|`input`|`wire logic [TM​_TAG​_BITS-1:0]`||
|`alloc​_victim​_data`|`input`|`wire logic [511:0]`||
|`alloc​_gtag`|`input`|`wire logic [GTAG​_W-1:0]`||
|`alloc​_op`|`input`|`wire pkg::req​_op​_t`||
|`alloc​_sub​_sel`|`input`|`wire logic`||
|`alloc​_wdata`|`input`|`wire logic [L1​_LINE​_BITS-1:0]`||
|`alloc​_wmask`|`input`|`wire logic [L1​_LINE​_BITS/8-1:0]`||
|`alloc​_ready`|`output`|`logic`|ALLOCATION OUTPUT|
|`alloc​_secondary​_hit`|`output`|`logic`||
|`alloc​_full​_and​_write​_conflict`|`output`|`logic`||
|`llc​_req​_valid`|`output`|`logic`|LLC FACING PORT|
|`llc​_req`|`output`|`pkg::l2​_llc​_req​_t`||
|`llc​_req​_ready`|`input`|`wire logic`||
|`llc​_resp​_valid`|`input`|`wire logic`||
|`llc​_resp`|`input`|`wire pkg::l2​_llc​_resp​_t`||
|`llc​_resp​_ready`|`output`|`logic`||
|`commit​_valid`|`output`|`logic`|FILL COMMIT PORT Tell Global Control to write tag/data array|
|`commit​_index`|`output`|`logic [TM​_INDEX​_BITS-1:0]`||
|`commit​_way`|`output`|`logic [1:0]`||
|`commit​_tag`|`output`|`logic [TM​_TAG​_BITS-1:0]`||
|`commit​_data`|`output`|`logic [LLC​_LINE​_BITS-1:0]`||
|`commit​_dirty`|`output`|`logic`||
|`resp​_valid`|`output`|`logic`|UPSTREAM RESPONSE|
|`resp`|`output`|`pkg::l2​_if​_resp​_t`||
|`resp​_ready`|`input`|`wire logic`||

### Always Blocks

- `unnamed : always_ff`
    - MSHR STATE / REGISTER UPDATE
- `FSM : always_comb`
    - COMBINATIONAL CONTROL

The most important thing I learned from my first **RISC-V processor** project was **backpressure**—how to propagate it through the entire system, how memory can stall the processor, and how the processor can, in turn, stall the instruction memory.

So, when do we need backpressure?

My understanding is that we need backpressure when there is **no predictable latency**.

I want to give an example.

Take a **6-stage multiplier**. If I send data to the multiplier, it will produce the result after exactly **6 cycles**. This is a guaranteed response after 6 cycles. Therefore, I know that I need to wait 6 cycles, and after those 6 cycles, the multiplier will provide the result.

In this case, there is no need for a **valid-ready handshake** just to handle the fixed latency.

But what about memory?

If the processor sends a request to the **L1 or L2 cache**, there is no guarantee that the response will arrive in a predictable number of cycles. The request could hit immediately, or it could experience a cache miss and take many more cycles.

That unpredictability creates the need for **backpressure**.

To solve this problem, we need a **valid-ready protocol**.

In other words, I should transfer information only when the **data is valid** and the **receiver is ready** to accept it.

In my design, every request and response, or every **packed transaction structure**, uses a **valid-ready handshake**.

I have implemented this handshake mechanism across **all I/O interfaces** in my design.

---
# How Does My Cache Controller Handle Requests?

In most memory systems, we create a **hierarchical FSM**.

In my design, the **Global FSM** is the main FSM that handles the overall **input and output flow**. It coordinates the **SRRIP replacement logic, data array, tag memory, dirty/valid metadata, and the MSHR FSMs**.

This hierarchical approach allows the individual components, such as the MSHR FSMs, to operate independently while the **Global FSM manages and coordinates the overall data flow**.

![[Pasted image 20260817170933.png]]

When a request comes to the **L1 cache**, the Global Control FSM moves into the **GC_TAG_WAIT** state. In this state, we send a request to read all four tags.

Then, in the **TAG_COMPARE** state, we compare the tag results. Based on the result, we decide what needs to be done.

If it is a **hit**, we update the **SRRIP** state and move to the **DATA** state. In this state, I grab the requested data from the data array and then move to the **RESPONSE** state, where the response is sent back to the L1 cache.

If it is a **miss**, we get the **victim way** from the SRRIP replacement logic. If the victim line is dirty, we retrieve that data, store it in the appropriate structure, and then move to the **ALLOCATE** state.

In the **ALLOCATE** state, we wait for a free MSHR entry. Once we get an available MSHR entry, I hand over the required information to the MSHR. From this point onward, the **MSHR takes over the miss handling process**.

The Global Control FSM then returns to the **IDLE** state, where it waits for the next request or response.
In module global control i make a structure field which in pkg file which store the data which need to give to MSHR and IO 

![[Pasted image 20260817174145.png]]

This is not a really good image to look at, but the **clear version of the diagram is available in the PDF in the `drawing` folder**, along with the Drawio files.

## Module global​_control
This design unit is implemented in `global​_control.sv`
This file depends on: `Dependencies are not calculated in the Documentation View`
### Parameters and Ports
#### Parameters

|Name|Type|Default Value|Description|
|---|---|---|---|
|`ADDR​_W`|`int`|`64`||
|`L1​_LINE​_BYTES`|`int`|`32`||
|`L2​_LINE​_BYTES`|`int`|`64`||
|`L1​_LINE​_BITS`|`int`|`L1_LINE_BYTES * 8`||
|`L2​_LINE​_BITS`|`int`|`L2_LINE_BYTES * 8`||
|`MSHR​_ENTRIES`|`int`|`8`||
|`TAG​_W`|`int`|`3`||
|`GTAG​_W`|`int`|`TAG_W + 1`||
|`REQ​_DEPTH`|`int`|`MSHR_ENTRIES`|REQUEST / RESPONSE QUEUES|
|`RESP​_DEPTH`|`int`|`MSHR_ENTRIES`||
|`LLC​_ADDR​_W`|`int`|`64`|LLC PARAMETERS|
|`LLC​_LINE​_BYTES`|`int`|`64`||
|`LLC​_LINE​_BITS`|`int`|`LLC_LINE_BYTES * 8`||
|`L2​_MSHR​_ENTRIES`|`int`|`8`||
|`LLC​_TAG​_W`|`int`|`3`||
|`TM​_NUM​_SETS`|`int`|`2048`|TAG MEMORY PARAMETERS|
|`TM​_NUM​_WAYS`|`int`|`4`||
|`TM​_INDEX​_BITS`|`int`|`11`||
|`TM​_TAG​_BITS`|`int`|`47`||
|`TC​_TAG​_BITS`|`int`|`TM_TAG_BITS`||
|`INDEX​_BITS`|`int`|`TM_INDEX_BITS`||
|`LINE​_BITS`|`int`|`L2_LINE_BITS`||
|`MSHR​_MAX​_SEC`|`int`|`3`||

#### Ports

|Name|Direction|Type|Description|
|---|---|---|---|
|`clk`|`input`|`wire logic`|CLOCK AND RESET|
|`rst​_n`|`input`|`wire logic`||
|`l2​_req​_valid`|`input`|`wire logic`|UPSTREAM / L1 FACING PORT|
|`l2​_req`|`input`|`wire pkg::l2​_if​_req​_t`||
|`l2​_req​_ready`|`output`|`logic`||
|`l2​_resp​_valid`|`output`|`logic`||
|`l2​_resp`|`output`|`pkg::l2​_if​_resp​_t`||
|`l2​_resp​_ready`|`input`|`wire logic`||
|`tm​_read​_enable`|`output`|`logic`|TAG MEMORY PORT|
|`tm​_index`|`output`|`logic [TM​_INDEX​_BITS-1:0]`||
|`tm​_tag​_way0`|`input`|`wire logic [TM​_TAG​_BITS-1:0]`||
|`tm​_tag​_way1`|`input`|`wire logic [TM​_TAG​_BITS-1:0]`||
|`tm​_tag​_way2`|`input`|`wire logic [TM​_TAG​_BITS-1:0]`||
|`tm​_tag​_way3`|`input`|`wire logic [TM​_TAG​_BITS-1:0]`||
|`tm​_tag​_valid`|`input`|`wire logic [TM​_NUM​_WAYS-1:0]`||
|`tm​_write​_enable`|`output`|`logic`|TAG MEMORY WRITE|
|`tm​_write​_way`|`output`|`logic [1:0]`||
|`tm​_tag​_in`|`output`|`logic [TM​_TAG​_BITS-1:0]`||
|`tm​_valid​_in`|`output`|`logic`||
|`tc​_req​_tag`|`output`|`logic [TC​_TAG​_BITS-1:0]`|TAG COMPARE PORT|
|`tc​_hit`|`input`|`wire logic`||
|`tc​_miss`|`input`|`wire logic`||
|`tc​_hit​_way`|`input`|`wire logic [1:0]`||
|`tc​_way​_0`|`output`|`logic [TC​_TAG​_BITS-1:0]`||
|`tc​_way​_1`|`output`|`logic [TC​_TAG​_BITS-1:0]`||
|`tc​_way​_2`|`output`|`logic [TC​_TAG​_BITS-1:0]`||
|`tc​_way​_3`|`output`|`logic [TC​_TAG​_BITS-1:0]`||
|`tag​_valid`|`output`|`logic [3:0]`||
|`sr​_req​_valid`|`output`|`logic`|SRRIP REPLACEMENT CONTROLLER|
|`sr​_index`|`output`|`logic [INDEX​_BITS-1:0]`||
|`sr​_hit`|`output`|`logic`||
|`sr​_hit​_way`|`output`|`logic [1:0]`||
|`sr​_victim​_way`|`input`|`wire logic [1:0]`||
|`sr​_victim​_valid`|`input`|`wire logic`||
|`da​_rd​_en`|`output`|`logic`|DATA ARRAY READ PORT|
|`da​_rd​_set`|`output`|`logic [INDEX​_BITS-1:0]`||
|`da​_rd​_way`|`output`|`logic [1:0]`||
|`da​_rd​_data`|`input`|`wire logic [LINE​_BITS-1:0]`||
|`da​_rd​_valid`|`input`|`wire logic`||
|`da​_rd​_dirty`|`input`|`wire logic`||
|`da​_wr​_en`|`output`|`logic`|DATA ARRAY WRITE PORT|
|`da​_wr​_set`|`output`|`logic [INDEX​_BITS-1:0]`||
|`da​_wr​_way`|`output`|`logic [1:0]`||
|`da​_wr​_data`|`output`|`logic [LINE​_BITS-1:0]`||
|`da​_wr​_valid`|`output`|`logic`||
|`da​_wr​_dirty`|`output`|`logic`||
|`mshr​_alloc​_req`|`output`|`logic`|MSHR TABLE ALLOCATION / SECONDARY MERGE PORT|
|`mshr​_alloc​_index`|`output`|`logic [TM​_INDEX​_BITS-1:0]`||
|`mshr​_alloc​_tag`|`output`|`logic [TM​_TAG​_BITS-1:0]`||
|`mshr​_alloc​_way`|`output`|`logic [1:0]`||
|`mshr​_alloc​_victim​_dirty`|`output`|`logic`||
|`mshr​_alloc​_victim​_tag`|`output`|`logic [TM​_TAG​_BITS-1:0]`||
|`mshr​_alloc​_victim​_data`|`output`|`logic [LINE​_BITS-1:0]`||
|`mshr​_alloc​_gtag`|`output`|`logic [GTAG​_W-1:0]`||
|`mshr​_alloc​_op`|`output`|`pkg::req​_op​_t`||
|`mshr​_alloc​_sub​_sel`|`output`|`logic`||
|`mshr​_alloc​_wdata`|`output`|`logic [L1​_LINE​_BITS-1:0]`||
|`mshr​_alloc​_wmask`|`output`|`logic [L1​_LINE​_BYTES-1:0]`||
|`mshr​_alloc​_ready`|`input`|`wire logic`|MSHR ALLOCATION RESPONSE|
|`mshr​_alloc​_secondary​_hit`|`input`|`wire logic`||
|`mshr​_alloc​_full​_and​_write​_conflict`|`input`|`wire logic`||
|`mshr​_commit​_valid`|`input`|`wire logic`|MSHR TABLE FILL COMMIT PORT|
|`mshr​_commit​_index`|`input`|`wire logic [TM​_INDEX​_BITS-1:0]`||
|`mshr​_commit​_way`|`input`|`wire logic [1:0]`||
|`mshr​_commit​_tag`|`input`|`wire logic [TM​_TAG​_BITS-1:0]`||
|`mshr​_commit​_data`|`input`|`wire logic [LINE​_BITS-1:0]`||
|`mshr​_commit​_dirty`|`input`|`wire logic`||
|`mshr​_resp​_valid`|`input`|`wire logic`|MSHR RESPONSE PORT MSHR -> Global Control -> L1 Global control arbitrates the response.|
|`mshr​_resp`|`input`|`wire pkg::l2​_if​_resp​_t`||
|`mshr​_resp​_ready`|`output`|`logic`||

### Always Blocks

- `unnamed : always_ff`
- `unnamed : always_comb`

# How Do I Handle Eviction and Write-Back?

When do we need **write-back**?

What does a programmer want? A **clear and unified memory system**. In a memory hierarchy, we have to give the illusion of a single, unified memory to the processor, ASIC, GPU, NPU, and other compute units. They should all see what appears to be one single memory.

I have an example:

Suppose **Processor A** modifies the data at address **X**. Now, this processor requests another piece of data that maps to the same set, but that data is not present in the cache.
What do we do?
We need to bring the new data into the cache, so we need to find a cache line to replace. Let us assume that the replacement policy selects **line X** as the victim.

But we cannot simply erase line X because it has been **modified**.

What happens if we do?

It will result in **data corruption**, which is unacceptable.

Therefore, we need to **write back the modified data to the lower level of the memory hierarchy first**, and only then can we replace the cache line and accept the new request.

This is one of the mechanisms that helps maintain the illusion that there is **only one unified memory**.

When we talk about **multiprocessor systems**, we need another mechanism to maintain this illusion across multiple caches. That mechanism is called **cache coherence**.

Cache coherence is a really fascinating concept, and it is one of the things I studied this summer.
In my current design, I am **not implementing a cache-coherence protocol**. It is another major part of the memory system that needs to be implemented in a complete multiprocessor design.
This is one of the reasons I call my current design a **viable design** rather than a complete production-level memory system.

![[Pasted image 20260817201712.png]]

in this diagram when global  control allocate the data to MSHR  which is in Ideal state in  that we give certain information to it like 
```
   assign mshr_alloc_index = cur_current.index ;
   assign mshr_alloc_tag = cur_current.tag;
   assign mshr_alloc_op = cur_current.req.op ;
   assign mshr_alloc_way  = cur_current.victim_way ;
   assign mshr_alloc_victim_dirty = cur_current.need_wb ;
   assign mshr_alloc_victim_data = cur_current.victim_data ;
   assign mshr_alloc_victim_tag = cur_current.victim_tag ;
   assign mshr_alloc_gtag = cur_current.req.gtag ;
   assign mshr_alloc_sub_sel = cur_current.req.sub_sel ;
   assign mshr_alloc_wdata = cur_current.req.wdata ; 
   assign mshr_alloc_wmask = cur_current.req.wmask ;
```

Which state the **MSHR** goes to is decided by whether the **victim line is dirty or not**.

If the victim line is dirty, we have to go to the **`MSHR_WB_SEND`** state, where we send the dirty data back to the LLC. After that, we send another request to the LLC to fetch the new data.

If the victim line is **not dirty**, then everything is much simpler. We only need to send one request to the LLC to fetch the new data, which can be handled in just a few states, as described above.

Now, let's consider a corner case.

Suppose the **L1 cache wants to write back some data**, but somehow that data has already been evicted from the cache. What do we do? How can we write back the data in that situation?

In this case, we first need to **bring the required data back from the LLC**, and then we can perform the writeback.

This creates an additional overhead.

Therefore, when selecting a victim line, if the victim line is dirty, we may need to perform a **writeback operation as well**. This can sometimes result in **two memory requests for a single cache miss**.

This is why a **good replacement policy really matters**. A better replacement policy can help us avoid evicting useful or frequently needed cache lines and, consequently, reduce unnecessary writebacks and memory traffic

for my design if VICTIM is dirty MSHR need two extra state it is seen in diagram very clearly 

---
# How Do I Handle Memory Requests and Refill?

















---
# How Did I Model the Cache in SystemC?

###  Why Did I Choose This Before RTL?

I want to share the experience I had when I started designing the RTL for my **RV64 5-stage pipeline processor**.

In that project, I decided to first write the architecture in **C++** using classes and object-oriented programming. I used this approach to create a **golden model**.

But then I faced a major problem.

One interesting thing about **RTL and digital design** is that they are inherently **concurrent**. When the adder is running, the fetch unit can be running at the same time, and the cache memory can also be operating in parallel. All of these operations can happen concurrently within the same cycle.

So, the question was:

**How do we simulate this concurrent behavior?**

My first thought was: since this is similar to parallel processing, can we create **multiple threads** to model these concurrent hardware operations?

When I tried this approach, however, it introduced a lot of complexity into the programming itself.

Then I thought about another approach: using a **`for` loop**, where each operation could be executed one iteration at a time. But this still does not naturally represent the true concurrent behavior of hardware.

To solve these problems, I found that there is a **dedicated library for C++ that is designed specifically for modeling concurrent hardware behavior: SystemC**.

SystemC provides constructs such as **`SC_MODULE`**, **`SC_THREAD`**, and **`SC_CTHREAD`**, along with an object-oriented structure for representing hardware components and their concurrent behavior.

This is why I decided to start with **SystemC before moving to RTL**. It allows me to model the architecture, concurrency, communication, and timing behavior at a higher level before implementing the final design in RTL.

Another experience I had was during **verification and debugging**.

When I started designing the **PC generation block**, it contained a **2-bit branch predictor, a Branch Target Buffer (BTB), and a PC register**.

Whatever we design in digital systems can be represented using a **finite-state machine**, or more broadly, it follows the principles of **finite automata theory**. The fundamental idea is that the output of a system depends on a particular combination of **inputs and its internal state (memory)**.

The system takes an input, combines it with its previous state, and produces an output based on both. This is a fundamental concept in **computational theory**, and ultimately, we are trying to build computer systems that implement this same principle.

To verify my PC generation block, I created a **self-checking testbench**. I also took some help from **Claude AI** while developing it.

But I faced an interesting problem.

To verify a system like this, we need a **really good testbench**. A self-checking testbench needs to be intelligent enough to understand the expected behavior of the design.

The behavior of the testbench has to be similar to the behavior of the **PC generation block**.

The output of the PC generation block depends on the **TLB entries, the state of the 2-bit branch predictors, the BTB entries, and the previous inputs**.

So, we can say that the output depends not only on the current input, but also on **previous inputs and the internal state of the system**.

Therefore, the testbench must remember and maintain all of this state as well.
This becomes a problem for verification because the more state-dependent the design becomes, the more complex the reference model and self-checking mechanism need to be.
To solve this, we need another approach:
but
We have a **golden model**. So, can we simply compare the output of the golden model with the output of the **cycle-accurate RTL**?
This problem can be addressed using **SystemC**, which provides mechanisms for interfacing with SystemVerilog through **DPI (Direct Programming Interface)**.

This means that **SystemVerilog can call C/C++ functions**, allowing us to communicate with the golden model and compare its output against the cycle-accurate RTL behavior.
In this way, we can run the golden model alongside the RTL and compare their outputs **cycle by cycle**.
This gives us another powerful approach to verification: instead of making the testbench reproduce the entire internal behavior of the RTL, we can use the **golden model as the reference** and continuously compare its expected results with the actual RTL results.

# example in my current design:
i want to give a example of SRRIP which is i did in  current project : 
```
#include <systemc>
#include "../golden_model/SRRIP/srrip_controller_interface.h"
using namespace sc_core;
using namespace sc_dt;

static sc_signal<bool> clk_sig;
static sc_signal<bool> rst_n_sig;
static sc_signal<bool> req_valid_sig;
static sc_signal<sc_uint<INDEX_BITS>> index_sig;
static sc_signal<bool> hit_sig;
static sc_signal<sc_uint<2>> hit_way_sig;      // NOTE: tracks WAY_BITS -- update if NUM_WAYS changes
static sc_signal<sc_uint<2>> victim_way_sig;   // NOTE: same as above
static sc_signal<bool> victim_valid_sig;
static srrip_controller *dut = nullptr;
extern "C"
void rrip_init()
{
    std::cout << "rrip_init()" << std::endl;
    dut = new srrip_controller("SRRIP");
    dut->clk(clk_sig);
    dut->rst_n(rst_n_sig);
    dut->req_valid(req_valid_sig);
    dut->index(index_sig);
    dut->hit(hit_sig);
    dut->hit_way(hit_way_sig);
    dut->victim_way(victim_way_sig);
    dut->victim_valid(victim_valid_sig);
    sc_start(SC_ZERO_TIME);

}
extern "C"
void rrip_clock(int clk)

{
    clk_sig.write(clk);
    sc_start(SC_ZERO_TIME);

}
extern "C"
void rrip_reset(int rst)
{
    rst_n_sig.write(rst ? true : false);
    sc_start(SC_ZERO_TIME);

}
extern "C"
void rrip_drive(
    int req_valid,
    int index,
    int hit,
    int hit_way
)
{
    req_valid_sig.write(req_valid);
    index_sig.write(index);
    hit_sig.write(hit);
    hit_way_sig.write(hit_way);
    sc_start(SC_ZERO_TIME);   // let combinational logic settle on the new inputs

}
// Read outputs back out. Call this AFTER the golden model has been
// clocked for this transaction -- i.e. after rrip_clock() has already
// fired for the posedge that samples the inputs set in rrip_drive().

extern "C"
void rrip_sample(
    int *victim_way,

    int *victim_valid
)
{
    *victim_way   = victim_way_sig.read().to_uint();
    *victim_valid = victim_valid_sig.read();
}

extern "C"
void rrip_finish()
{
    std::cout << "rrip_finish()" << std::endl;
    delete dut;
    dut = nullptr;
}
```

this is wrapper function which convert the C++ systemc model into plain c funtion that systemverilog  can call 
```
module srrip_tb;

    // Parameters (must be declared before any signal that sizes off them)
    parameter int NUM_SETS   = 2048;
    parameter int NUM_WAYS   = 4;
    parameter int INDEX_BITS = 11;
    parameter int WAY_BITS   = $clog2(NUM_WAYS);
    // DUT signals
    logic                  clk = 1'b0;
    logic                  rst_n;        // active-low sync reset
    logic                  req_valid;    // a lookup is happening this cycle
    logic [INDEX_BITS-1:0] index;        // set index
    logic                  hit;          // 1 = hit, 0 = miss
    logic [WAY_BITS-1:0]   hit_way;      
    logic [WAY_BITS-1:0]   victim_way;  
    logic                  victim_valid;

    // DPI-C imports (golden model)
    import "DPI-C" function void rrip_init();
    import "DPI-C" function void rrip_reset(input int rst);
    import "DPI-C" function void rrip_clock(input int clk);         
    import "DPI-C" function void rrip_drive(                  
        input int req_valid,
        input int index,
        input int hit,
        input int hit_way
    );
    import "DPI-C" function void rrip_sample(                   
        output int victim_way,
        output int victim_valid
    );
    import "DPI-C" function void rrip_finish();
    int victim_way_golden;
    int victim_valid_golden;
    // DUT instantiation
    srrip_controller #(
        .NUM_SETS  (NUM_SETS),
        .NUM_WAYS  (NUM_WAYS),
        .INDEX_BITS(INDEX_BITS),
        .WAY_BITS  (WAY_BITS)

    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .req_valid   (req_valid),
        .index       (index),
        .hit         (hit),
        .hit_way     (hit_way),
        .victim_way  (victim_way),
        .victim_valid(victim_valid)

    );

    // Clock generation — the single source of truth for the golden
    // model's clock. rrip_drive/rrip_sample never toggle it themselves.

    initial begin
        forever begin
            #5 clk = ~clk;
            rrip_clock(int'(clk));
        end
    end

    // Reset task — synchronized to the clock, not a raw #delay
    task automatic reset();
        rst_n = 0;
        rrip_reset(0);
        repeat (2) @(negedge clk);
        rrip_reset(1);
        rst_n = 1;
    endtask
    // Drive one transaction and check DUT vs golden model

    task automatic send_transaction(
        input int req,
        input int idx,
        input int hit_i,
        input int way
    );

        begin
            @(negedge clk); 
            req_valid = (req == 1);
            index     = INDEX_BITS'(idx);
            hit       = (hit_i == 1);
            hit_way   = WAY_BITS'(way);

            rrip_drive(req, idx, hit_i, way);   
            @(posedge clk);   
            rrip_sample(victim_way_golden, victim_valid_golden); 
            if (hit_i == 0 &&
                (victim_way   !== WAY_BITS'(victim_way_golden) ||
                 victim_valid !== 1'(victim_valid_golden))) begin
                $display("--------------------------------");
                $display("req_valid = %0d", req_valid);
                $display("index     = %0d", index);
                $display("hit       = %0d", hit);
                $display("hit_way   = %0d", hit_way);
                $display("RTL victim_way    = %0d", victim_way);
                $display("SC  victim_way    = %0d", victim_way_golden);
                $display("RTL victim_valid  = %0d", victim_valid);
                $display("SC  victim_valid  = %0d", victim_valid_golden);
                $error("Mismatch!");
            end
        end
    endtask
    // Test sequence

    initial begin

        rrip_init();

        reset();
        send_transaction(1,0,1,3);
        send_transaction(1,0,0,0);
        send_transaction(1,1,0,0);
        send_transaction(1,5,0,0);
        send_transaction(1,1024,0,0);
        send_transaction(1,2047,0,0);
        send_transaction(1,2047,0,0);
        send_transaction(1,1023,0,0);
        send_transaction(1,1024,0,0);
        repeat(1000) begin
    send_transaction(
        $urandom_range(0,1),
        $urandom_range(0,2047),
        $urandom_range(0,1),
        $urandom_range(0,3)

    );
end
       repeat(100)
          send_transaction(1,0,0,0);
     @(negedge clk);
        req_valid = 1'b0;   // go idle so the rest of the run isn't a phantom hit storm
    end
    // flush/report the golden model at end of run
    final begin
        rrip_finish();
    end
    // stop the simulation after some time
    initial begin
        #50000;
        $finish;

    end
    initial begin

        $dumpfile("srrip_tb.vcd");
        $dumpvars(0, srrip_tb);

    end
endmodule
```

this is just a example that how we connect systemC module  to testbench 



# How Did I Implement the Design in SystemVerilog?
### This is the strongest part of my skill set: How to Design Synthesizable RTL

One of the most important concepts in any hardware design is the **level of abstraction** and **black-box modeling**. At the moment, I am working at the **RTL level**.

When I designed my first **8 KB cache**, during Diwali, I initially gave ChatGPT a prompt: _“Generate a 4-way set-associative 8 KB cache memory.”_ It generated nearly 1,000 lines of code. I ran the design through Verilator, and surprisingly, it took me almost a day just to debug and remove the linting errors. Even after that, the design still did not work, so I eventually dropped that approach.

Then I started again with a different approach. Instead of having **one large module**, I divided the design into **smaller modules**, with each module having its own well-defined behavior. This made it much easier to verify each module independently.

For example, the job of the **data memory** is simply to store data and provide that data when it is requested. With this approach, it becomes much easier to verify the design and understand how the individual modules communicate and work together.

I then divided the cache into a **top-level module that defines the overall behavior** and several **smaller submodules**, each responsible for a specific function. This modular approach makes the design easier to understand, debug, verify, and maintain, while also helping me keep the RTL **synthesizable**.

so:
# what i have in current module ?
### My Design Is Hierarchical

I created the **golden model in SystemC**, which contains the same modules and hierarchy that I want to implement. I first capture and verify the behavior of the design in SystemC, and then I implement the same hierarchy using **SystemVerilog**.

Some people may think this is simply a **copy-and-paste process**—like converting SystemC code into SystemVerilog. But my experience says that it is not.

We need to **imagine what we are actually building**, what kind of hardware the RTL will create, how the modules will communicate, what the approximate latency should be, and how the design can be made **synthesizable**.

Translating the behavior from a high-level model into actual hardware is a completely different challenge. **It is not just copying code; it is understanding the hardware behind the code and then describing that hardware in synthesizable RTL.**


# verification
This is something that **most semiconductor industries invest up to 70–80% of their entire project budget in**, and it is extremely important.

Imagine this: most of the time, whenever I look at smartphones, laptops, or tablets, they all contain silicon, and I rarely see a case where a smartphone suddenly stops working without any physical damage.

Industries are designing **reliable SoCs and processors**—but how?

If we develop an application or a website, we usually write it in languages such as **Java or JavaScript**. If the application does not work properly or suddenly crashes, developers can fix the problem and simply release a new version. That process is relatively easy.

But **silicon is rigid**. Once the hardware is manufactured, the logic is physically implemented in the chip. We cannot simply update the hardware in the same way we update software. If we need to fundamentally change the hardware, in many cases, **we have to design and manufacture a new chip**.

That is why **verification, validation, reliability, and signoff are such critical parts of semiconductor design**.

### What did I use for verification in this project?
**UVM? No.**

I learned a little about **Universal Verification Methodology (UVM)**, but the designs I am working on are relatively small and specific rather than being an entire SoC. For this type of project, I felt that a complete UVM environment would add unnecessary complexity.
Another important reason is the **simulation tool** I use, which does not support UVM-based verification. That made it difficult to implement a UVM environment for this project.

Instead, I designed a **task-based verification testbench**. This approach gives me much more flexibility when creating different test scenarios, and I was able to dedicate significant time to verification.

Even though the testbench is relatively simple, I compensate for that with **extensive verification, hierarchical verification, and independent module-level testing**. This helped me reduce the risk of logical errors and gave me confidence in the design.

I understand that this is **not the standard verification methodology used in large semiconductor projects**, where UVM and more advanced verification environments are commonly used. However, given the **scope of my project, the tools available to me, and the time I had for verification**, this approach was practical and effective.





# What Results Did I Get?

**Performance modeling is an important part of a cache project.** Before writing even a single line of RTL, we need to understand how much performance the proposed architecture can deliver.

We need to ask questions such as:

- How much performance can my current design achieve?
- Do I need another architectural approach or algorithm to improve performance?
- What will be the impact on **power**?
- How much additional **area** will it require?
- Will the improvement in performance justify the additional hardware complexity?

There are many such trade-offs, and we need to consider all of them before making architectural decisions.

If I want to estimate the **actual performance of the architecture**, I need a performance model. This is where **SystemC** becomes extremely useful.

For example, consider an **Intel Raptor Lake Core i7/i5-class processor** that can generate approximately **two load/store operations per cycle**. If we assume a clock frequency of around **2.5 GHz**, that corresponds to roughly:

**2 × 2.5 GHz = 5 billion memory operations per second.**

Think about that number: **5 billion requests every second.**

The challenge is that we cannot evaluate the performance of a cache simply by running a small RTL simulation for a short amount of time. To obtain meaningful performance results, we may need to model billions of memory accesses and sufficiently long workloads.

Suppose an RTL simulator takes **1 second to simulate 500 clock cycles**. At that simulation speed, modeling billions of cycles would become impractical—it could take **months or even longer**, depending on the design and simulator.

This is one of the major challenges of using RTL for **architectural performance modeling**. RTL is designed to describe cycle-accurate hardware behavior, not to execute billions of cycles as quickly as possible.

This is where **SystemC provides a major advantage**. I can build a higher-level, cycle-accurate model of the cache architecture, run large numbers of memory transactions much faster than a detailed RTL simulation, and evaluate architectural decisions before committing them to RTL.

That is the approach I am using in my project: **first model and evaluate the architecture in SystemC, then implement the validated architecture in synthesizable SystemVerilog RTL.**

and also i impliment some c code to generate the graph some libraries of C++  
like  
the codes are in the scripts folder  the  instructions are also there to how to run the simulation some CMAKE scripts which help to run lot of files and structure way of running 
it will create executable file file might be there if we run this also we can get the result in GNUPLOT   

![[Pasted image 20260818211519.png]]

![[Pasted image 20260818211606.png]]

![[Pasted image 20260818211904.png]]

```
=== Performance summary ===
  total requests completed: 10013
  hits:                     7855
  misses:                   2158
  overall hit rate:         78.448%
  avg latency (cycles):     6.8475
```


this are the result what i got 





# What Are the Current Limitations and What Can we Improve?

### Design Trade-offs and Limitations

If someone takes a close look at the architecture and the FSMs I designed, they may notice a limitation in my cache. Some of the states in the **MSHR FSM** behave more like **commit states**: we commit the received data and then send it to the L1 cache. Ideally, if we can forward the data to the L1 cache **as soon as it arrives**, that would reduce the latency and improve the overall performance.

When I started designing this cache, I initially thought I could build a **pipelined, non-blocking cache**. From my experience, pipelining a combinational datapath is relatively straightforward, but pipelining a **finite-state-machine-based design** is much more challenging.

As my understanding of the design increased, I realized that FSM pipelining was one of the most difficult parts of the project. It could significantly increase the development and debugging time.

Since I also had a limited amount of time to complete the project, I made a design trade-off: **I dropped the idea of a fully pipelined cache and focused on implementing the non-blocking behavior.**

I successfully implemented the **non-blocking cache**, but as a consequence, some states in the **Global FSM** introduce additional latency. These additional states can make it easier to meet the target **clock frequency**, but they do not necessarily improve **throughput**.

In other words, I optimized the design for **non-blocking behavior and manageable implementation complexity**, rather than trying to achieve both a fully pipelined FSM and maximum throughput within the available development time.

above are my mistake that i make 

### Real-World Limitation

Everyone in the technology industry knows that **Hopper changed the world of AI**. NVIDIA introduced a new generation of computing with it. But what if I say **no**?

Back in **2013**, SK hynix developed the first HBM (High Bandwidth Memory) and integrated it into an AMD GPU. Later, Samsung began mass-producing HBM. Today, modern server systems such as **AMD Helios** and **NVIDIA Vera Rubin** are difficult to imagine without HBM.

At first, some readers may wonder:

> **What does HBM have to do with my current cache architecture?**

There is actually a strong connection.

The way HBM works relies heavily on **memory banking**. Banking allows multiple memory accesses to be handled in parallel and provides the bandwidth required by modern compute systems. **Banking is also an important architectural technique when designing scalable cache memories.**

In my current cache design, I do not have **banking**. Because of this, my memory architecture has a scalability limitation. I cannot simply increase the cache size from **512 KB to 2 MB** and assume that I will automatically get a performance benefit.

As the cache grows, the number of accesses and the amount of data that need to be handled also increase. Without proper banking and parallel access paths, the larger cache can become a bottleneck.

Therefore, one of the real limitations of my current architecture is that **the memory is not banked**. To make the cache truly scalable—from hundreds of kilobytes to multiple megabytes—I would need to introduce a proper **banked memory architecture** and evaluate how it affects **bandwidth, latency, area, and power**.


**Real-World Multicore Systems and the Limitations of My Design**

For my college project, I used an **ESP32**. I bought it for just around **₹300**, which is surprisingly inexpensive. Out of curiosity, I started studying its architecture and found that it contains a small SoC with **two RISC-V processors**, along with I/O, RAM, ROM, a power controller, an oscillator, and other supporting components.

Just think about that: a device costing around ₹300 contains **two RISC-V processors**, memory, I/O, and an entire SoC infrastructure.

To design a processor capable of running real-world applications, relying on a **single core** is no longer sufficient. From around **1996–1999**, as the performance improvements from increasing single-core performance started reaching their limits, the industry began moving toward **multicore systems**.

Today, server processors can contain **dozens of CPU cores**, and even my laptop processor has multiple cores, with each core supporting multiple threads.

However, multicore systems introduce another major problem: **memory consistency and coherence**. All processors must observe a consistent view of memory rather than seeing multiple conflicting copies of the same data.

To solve this problem, we need mechanisms such as **cache coherence protocols**, including **MESI, MOESI**, and others.

My current cache design does not implement any cache-coherence mechanism. This is a significant limitation, and a real multicore cache system would need to implement such a protocol.

---

**Making Hardware Intelligent**

In my first topic, I mentioned that we need to make hardware **intelligent—not just smart**.

My current cache can be considered **smart**, but it is not yet truly intelligent.

To make it more intelligent, I would need to add mechanisms such as a **hardware prefetcher**. Based on observed data-access patterns and data flow, the prefetcher could predict which data will be needed in the future and bring it into the cache before the processor requests it. This could potentially reduce cache misses and memory latency.

Another important concept is **Quality of Service (QoS)**.

For example, in an arbitration system, we need to decide:

> **Which request should be completed first?**

In my current design, I have implemented a simple form of prioritization by giving **fixed priority to the instruction cache over the data cache**. This helps keep the instruction-fetch path fast.

However, this is not sufficient for a larger and more complex memory system. A real SoC needs **fine-grained QoS control**, where different types of requests can receive different priorities depending on their latency requirements, bandwidth requirements, and importance.

This becomes especially important in modern **SoCs, PCs, smartphones, and laptops**, where CPUs, GPUs, NPUs, peripherals, and other hardware blocks may all compete for access to the same memory system
# Conclusion

This project started as an attempt to design a cache, but it became much more than that. Through the process, I learned that **modern processor performance is not determined by computation alone; the memory system plays an equally critical role**. As processor performance continues to increase, efficiently moving data to and from the compute units becomes one of the biggest challenges in computer architecture.

I started with a basic **8 KB blocking cache** and gradually moved toward a **non-blocking L2 cache architecture** with MSHRs, SRRIP replacement, arbitration, hierarchical FSMs, valid-ready handshaking, and SystemC-based performance modeling. Each stage exposed a new architectural problem and helped me understand why modern processors require increasingly sophisticated memory systems.

One of the biggest lessons I learned is that **hardware design is not simply writing RTL code**. It requires understanding the architecture, modeling the behavior, considering latency, throughput, area, power, scalability, and finally translating that understanding into synthesizable hardware.

I also learned the importance of **hierarchical design and verification**. Building a golden model in SystemC and then implementing the same architecture in SystemVerilog taught me that translating a behavioral model into hardware is not a copy-and-paste process. We have to understand what physical hardware the RTL will create and how that hardware will behave cycle by cycle.

At the same time, this project helped me understand my design's limitations. The current architecture does not include **cache coherence, memory banking, prefetching, advanced QoS, or a fully pipelined cache datapath**. These are not failures of the project; they represent the next engineering problems that need to be solved to move from a functional cache toward a more realistic modern memory subsystem.

The most important takeaway for me is that **computer architecture is a continuous process of identifying bottlenecks and finding ways to remove them**. A processor may have powerful compute units, but without an efficient memory hierarchy, that computational power cannot be fully utilized.

So, this project is not the final version of a cache. **It is my first step toward understanding how modern CPUs, GPUs, NPUs, and SoCs are built—and how the memory system ultimately determines how effectively all that computation can be used.**


# References
- **Computer Architecture** — Prof. Onur Mutlu, ETH Zürich, through the [SAFARI Research Group](https://www.safari-research.org/?utm_source=chatgpt.com).
- **VLSI Design and Front-End Design** — [Enics Labs](https://enicslabs.com/?utm_source=chatgpt.com).
- **Computer Architecture: A Quantitative Approach** — John L. Hennessy and David A. Patterson. This book was one of my primary references for studying computer architecture and microarchitecture.

