# Stage 2 results: app instance + RDS

**Moving Postgres to its own managed database raised the limit from ~10,000 to ~15,000 users (~2,090 req/s, up from ~1,400).
The app instance's CPU is the new limit.**

> ⚠️ **Restart the database after seeding, before measuring.** Loading 2.5M rows pushes the 1 GB database into
> swap, and swap made ~1% of requests take 10–30 s. A restart clears it. See [The swap problem](#the-swap-problem).

## Setup

Same as stage 1 (data, user loop, load generator, pass/fail rule), except:

| | Stage 1 | Stage 2 |
|---|---|---|
| Postgres | on the app instance | RDS `db.t4g.micro` (2 vCPU, 1 GB), Postgres 16, private subnets |
| App instance | nginx + Node + Postgres | nginx + Node (`t4g.small`) |
| DB connection | localhost, no TLS, password in code | TLS (verified against the RDS CA), password from Secrets Manager |
| Before measuring | – | database restarted after seeding |

## Results (final run)

| Users | Req/s | Errors | p50 | p95 | p99 | Max | Pass |
|---:|---:|---:|---:|---:|---:|---:|:---:|
| 1,000 | 141 | 0% | 2.4 ms | 3.5 ms | 7.6 ms | 403 ms | ✅ |
| 5,000 | 700 | 0% | 2.2 ms | 3.8 ms | 21 ms | 507 ms | ✅ |
| 7,500 | 1,051 | 0% | 2.3 ms | 5.5 ms | 48 ms | 505 ms | ✅ |
| 10,000 | 1,398 | 0% | 2.5 ms | 14 ms | 135 ms | 484 ms | ✅ |
| 12,500 | 1,749 | 0% | 2.7 ms | 20 ms | 106 ms | 592 ms | ✅ |
| **15,000** | **2,089** | **0%** | **5.4 ms** | **179 ms** | **362 ms** | **1.0 s** | ✅ |
| 17,500 | 2,332 | 0% | 173 ms | 927 ms | 1.4 s | 3.0 s | ❌ p95 |

Compared with stage 1 at the same load: at 15,000 users stage 1 had collapsed (p95 4.4 s); stage 2 still has p95 179 ms.
Runs 4 and 5 (also restarted, stopped at 10,000 users) gave similar numbers (p99 75–82 ms at 10,000).

## What limited it

At 17,500 users the **app instance ran out of CPU**: Node used ~160% and nginx ~36% of its 200% (2 cores).

| Users | App instance CPU (avg / max) | RDS CPU (max) | RDS swap |
|---:|---:|---:|---:|
| 10,000 | 37% / 55% | 53% | 6 MB |
| 15,000 | 50% / 69% | 76% | 6 MB |
| 17,500 | 65% / **99%** | 81% | 6 MB |

The database has some headroom left, but not much: it will be the shared bottleneck once there are several app instances (stage 3).

nginx's connection limit (8,192 per worker), which caused errors in stage 1 and in the swapping runs, was never hit here: with fast responses, connections don't pile up.

Sources: `final/results.csv`, `final/app/vmstat.log`, `final/app/pidstat.log`, CloudWatch (RDS `CPUUtilization`, `SwapUsage`).

## The swap problem

The first runs (1–3) had a slow tail: ~1% of requests took 10–30 s from 7,500 users, with errors from 10,000.

**Cause:** after the bulk seed, the 1 GB database had ~100 MB of its memory swapped to disk. Some queries then took seconds *inside Postgres*. Each slow query held one of Node's 10 database connections, normal bursts of requests queued behind them (up to ~4,000 per worker), and the queue snowballed.

**How we proved it:** we predicted each result before the run.

| Run | Condition | RDS swap | p99 @ 10,000 users | Slow queries logged by RDS |
|---|---|---:|---:|---:|
| 3 | right after seeding | ~100 MB | 19.4 s | (not measured) |
| 4 | after a database restart | ~1 MB | 75 ms | 4 |
| 5 | repeat of 4, nothing changed | 2–8 MB | 82 ms | – |
| 6 | re-seeded, no restart | 111–115 MB | 12.8 s | 356 (up to 6.3 s) |

Ruled out along the way, with evidence: DNS, TCP connection retries, nginx → Node, Secrets Manager, lock waits, RDS CPU and disk.

**Our mistake on the way:** we first ruled memory out because Postgres never reported waiting on disk. But swapping happens below Postgres, so it can't see it. Lesson: before ruling something out, check that the measurement could have detected it.

## Caveats

- The load generator was close to its memory limit at 17,500 users (133 MB free). k6 wasn't killed, and the app instance was clearly CPU-bound, so we don't think it changed the result.
- Swap is a property of this small (Free plan) database and of our bulk seed, not of a long-running app. A real deployment should still check `SwapUsage`.

## Next

Stage 3: put an ALB in front of **two** app instances and see whether capacity doubles, or the shared database becomes the limit.

## Raw data

- `final/`: the run above (k6 reports per step, `loadgen-vmstat.log`), and `final/app/` (app instance `vmstat.log`, `pidstat.log`)
- `run1-results.csv`, `run2/`: the first runs, with the slow tail
- `run3/` – `run6/`: the swap investigation. `app/` holds the temporary diagnostics (`app.log.gz`: pool, connection and event-loop timings; `nginx-slow.log.gz`; `nstat-delta.txt`; `capture.txt`: connection and DNS packets). `run4/` and `run6/` have the RDS slow-query log (`rds-postgresql.log`)
