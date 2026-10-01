---
name: stage-writeup
description: >
  Write or update results/stageN/README.md after a scaling-lab load test, in the
  same format as earlier stages. Use when a stage's load test is done, for
  "write up stage N", "write up the results" or "update the stage README".
---

# Stage write-up

Each stage gets `results/stageN/README.md`. Write-ups must be comparable across stages, so follow the existing format exactly. Read `results/stage1/README.md` and the previous stage's README first and match their style.

## Inputs to gather

1. The previous stage's README: its headline numbers and its "Next" section (what this stage set out to test).
2. Raw results in `results/stageN/`: k6 `results.csv` (columns `vus,req_per_s,requests,fail_pct,p50_ms,p95_ms,p99_ms,max_ms`), per-step k6 JSON, vmstat logs.
3. What changed in infra or app since the last stage: `git diff` against the previous stage's commit in `infra/`, `app/`, `loadtest/`.
4. Any evidence gathered while debugging (CloudWatch, `pg_stat_activity`, logs). Ask the user if not in the repo.

If raw data for a claim is missing, ask. Never invent or estimate numbers.

## Structure

1. **Title:** `# Stage N results: <short architecture name>`
2. **Headline:** one or two bold sentences. The main number, compared with the previous stage, and the main limit or open problem.
3. **Setup:** "Same as stage N-1 (data, user loop, load generator, pass/fail rule), except:" then a table with columns `| | Stage N-1 | Stage N |`, only rows that changed. Stage 1 lists the full setup instead.
4. **Results:** table `| Users | Req/s | Errors | p50 | p95 | p99 | Max | Pass |`, numbers right-aligned (`---:`). One row per step from `results.csv`. Name the run if there were several, and say in one line how other runs compared.
5. **What limited it** (cause found) or **What we checked** (cause not found): evidence for each suspect, with the source file or tool. For checks, use a table `| Suspect | Evidence | Verdict |`.
6. **Where it points (unconfirmed)**: only if the cause is not proven. Label guesses as guesses.
7. **Caveats:** only new ones; don't repeat stage 1's.
8. **Next:** the one change or experiment the next stage or run will do.
9. **Raw data:** list the files in `results/stageN/` the write-up relies on.

## Formatting rules

- Pass = p95 < 500 ms **and** errors < 1%. Mark ✅ or ❌, and add the reason after ❌ (`❌ errors`, `❌ p95`).
- Latency: `ms` with 2 significant figures below 100 ms (`2.3 ms`, `56 ms`), whole ms to 999 (`197 ms`), then seconds (`3.4 s`, `31.8 s`).
- Thousands separators for users and req/s (`7,500`, `1,963`). Errors as `%` with up to 2 decimals.
- Bold the row for the highest passing step.
- Plain, short sentences. Explain each finding with its evidence and source.

## Finish

Show the user the draft and point out anything uncertain. Commit only when they approve. Then remind them to run `terraform destroy` if the infrastructure is still up.
