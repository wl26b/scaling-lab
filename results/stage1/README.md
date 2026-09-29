# Stage 1 results: single instance

**One `t4g.small` (2 vCPU ARM, 2 GB RAM) running nginx + Node + Postgres handles about 10,000 concurrent users.**
It breaks between 10,000 and 15,000, when its 2 CPU cores are fully used.

## Setup

| | |
|---|---|
| App instance | `t4g.small`, unlimited CPU credits, ap-southeast-1. nginx → Node (2 cluster workers, pool of 10 DB connections each) → Postgres 16, all on one instance |
| Data | 50,000 users, 500,000 posts, ~2,000,000 likes |
| Load generator | `m7i-flex.large` (2 vCPU, 8 GB), k6, same subnet, hits the app's private IP |
| User loop | load feed → 2–5 s → open a post → 1–3 s → like (15%) → create post (2%) → 5–10 s |
| Each step | 1 min ramp-up, 3 min hold, 20 s ramp-down |
| Pass | p95 < 500 ms and < 1% errors |

## Results

| Users | Req/s | Errors | p50 | p95 | p99 | Max | Pass |
|---:|---:|---:|---:|---:|---:|---:|:---:|
| 10 | 1.4 | 0% | 2.4 ms | 3.3 ms | 6.4 ms | 14 ms | ✅ |
| 50 | 7 | 0% | 2.2 ms | 3.3 ms | 6.1 ms | 13 ms | ✅ |
| 100 | 14 | 0% | 2.0 ms | 3.0 ms | 6.9 ms | 77 ms | ✅ |
| 250 | 35 | 0% | 1.8 ms | 2.7 ms | 4.5 ms | 25 ms | ✅ |
| 500 | 70 | 0% | 1.7 ms | 2.7 ms | 5.2 ms | 26 ms | ✅ |
| 1,000 | 140 | 0% | 1.6 ms | 2.6 ms | 4.5 ms | 30 ms | ✅ |
| 2,000 | 280 | 0% | 1.6 ms | 2.8 ms | 8.1 ms | 190 ms | ✅ |
| 3,000 | 420 | 0% | 1.5 ms | 3.1 ms | 24 ms | 421 ms | ✅ |
| 4,000 | 560 | 0% | 1.6 ms | 3.7 ms | 35 ms | 506 ms | ✅ |
| 5,000 | 700 | 0% | 1.7 ms | 4.4 ms | 29 ms | 624 ms | ✅ |
| 7,500 | 1,049 | 0% | 2.2 ms | 11 ms | 86 ms | 1.9 s | ✅ |
| **10,000** | **1,397** | 0% | 3.5 ms | 56 ms | 166 ms | 3.0 s | ✅ |
| 15,000 | 1,391 | 0.01% | 3.5 s | 4.4 s | 16.7 s | 29.8 s | ❌ |
| 20,000 | – | – | – | – | – | – | load generator ran out of memory |

Raw data: `run1-10-to-5000.csv`, `run2-7500-to-20000.csv`.

## What limited it

1. **CPU.** Throughput stopped growing at ~1,400 req/s: 10,000 and 15,000 users got the same req/s. Past that, requests queue and latency jumps from milliseconds to seconds.
   CPU use by program, as % of one core (200% = both cores full). Source: `run2-app-cpu-by-program.txt`.

   | Users | Postgres | Node | nginx | ≈ Total |
   |---:|---:|---:|---:|---:|
   | 7,500 | 70% | 49% | 12% | 130% |
   | 10,000 | 93% | 61% | 15% | 170% |
   | 15,000 | 96% | 79% | 23% | 200% |

   **Postgres is the biggest consumer**, and it competes with Node and nginx for the same 2 cores.
2. **nginx connection limit.** At 15,000 users nginx logged ~18,000 `8192 worker_connections are not enough` alerts (2 workers × 8,192). Each virtual user holds a keep-alive connection, so this limit sits right where the CPU limit is.
3. **Load generator memory.** At 20,000 users k6 reached 7.5 GB and was killed by the OOM killer. Testing beyond 15,000 needs a bigger load generator (blocked by the Free plan) or several.

## Caveats

- "Users" = concurrently active users who mostly sit idle (~0.14 req/s each). Daily active users could be many times higher.
- No auth, global feed (not a follow graph), uniformly random data. A real app would do more work per request.
- Each step holds for only 3 minutes; slow problems (disk filling, memory leaks, autovacuum) wouldn't show.

## What's next

Stage 2 moves Postgres to its own managed instance (RDS), giving Node and nginx the app instance's 2 cores to themselves.
