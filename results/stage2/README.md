# Stage 2 results: app instance + RDS

**Moving Postgres to RDS raised throughput (~1,960 req/s at 15,000 users vs a ~1,400 req/s ceiling in stage 1),
but a small share of requests became very slow (15–30 s) from ~7,500 users. The cause is not found yet.**

## Setup

Same as stage 1 (data, user loop, load generator, pass/fail rule), except:

| | Stage 1 | Stage 2 |
|---|---|---|
| Postgres | on the app instance | RDS `db.t4g.micro` (2 vCPU, 1 GB), Postgres 16, private subnets |
| App instance | nginx + Node + Postgres | nginx + Node (`t4g.small`) |
| DB connection | localhost, no TLS, password in code | TLS (verified against the RDS CA), password from Secrets Manager |

## Results (run 2)

| Users | Req/s | Errors | p50 | p95 | p99 | Max | Pass |
|---:|---:|---:|---:|---:|---:|---:|:---:|
| 1,000 | 140 | 0% | 2.3 ms | 3.3 ms | 6.5 ms | 152 ms | ✅ |
| 5,000 | 698 | 0% | 2.2 ms | 4.9 ms | 197 ms | 3.4 s | ✅ |
| 7,500 | 986 | 0% | 2.3 ms | 91 ms | 14.8 s | 15.8 s | ✅ |
| 10,000 | 1,223 | 1.5% | 2.5 ms | 121 ms | 31.8 s | 32.3 s | ❌ errors |
| 12,500 | 1,636 | 1.4% | 2.9 ms | 132 ms | 17.6 s | 18.0 s | ❌ errors |
| 15,000 | 1,963 | 2.0% | 5.6 ms | 343 ms | 17.8 s | 18.1 s | ❌ errors |

Run 1 (`run1-results.csv`) showed the same shape. Its 1,000-user step also had a slow tail (p99 500 ms),
because it started right after seeding: the database was still warming up.

## What we checked

| Suspect | Evidence | Verdict |
|---|---|---|
| RDS CPU | peaked ~73% (CloudWatch) | not the cause |
| RDS disk | ~1 ms write latency, queue depth < 0.4 | not the cause |
| RDS memory (1 GB, ~100 MB swap in use) | `pg_stat_activity` sampled every second: only **1** sample waiting on a disk read; mostly running (512) or waiting for the client (`ClientRead`, 294) | **not the cause** (our first guess, disproven) |
| RDS busy-ness | usually 0–5 active queries at once, ~20 at the 15,000 peak | database mostly idle |
| App instance CPU | Node workers mostly well under one core until 15,000 users | not the cause below 15,000 |
| Load generator | spare CPU and memory throughout (`run2/loadgen-vmstat.log`) | not the cause |
| TCP listen queues | 0 overflows / drops | not the cause |
| nginx `worker_connections` | ~22,000 alerts, but only at 10,000+ users | explains the **errors**, not the slowness at 7,500 |

## Where it points (unconfirmed)

The delay is inside the app instance, between nginx and the database: in Node or its connection pool.
- Postgres often waited **for Node** to send the rest of a query (`ClientRead`).
- At times one Node worker was nearly idle while the other was busy (e.g. 3% vs 30% CPU): one worker seems to stall.

Leading suspect: connection churn. The `pg` pool closes connections idle for 10 s; every new connection to RDS
does a TLS handshake that parses the RDS CA bundle, which can block a worker. Stage 1 used local connections without TLS.

## Next

Instrument the app per request (time waiting for a pool connection, query time, total) and rerun the 7,500 and 10,000 steps.

Raw data: `run1-results.csv`, `run2/` (k6 reports per step, load generator CPU/memory).
