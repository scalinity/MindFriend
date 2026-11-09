# CI speedup log: scalinity/MindFriend / ci.yml

## Baseline (8 November 2026, n=28 successful of 67 completed PR runs, `ci_timing.sh -w ci.yml -L 150`)
Runs span 30 October to 9 November 2026. Only 28 of the last 67 PR runs succeeded (38 failed during repair work), so n is small.

| Run metric | n | p50 | p90 | max |
|---|---:|---:|---:|---:|
| Wall-clock (first job queued to last job done) | 28 | 9m37s | 53m25s | 1h10m |
| Pre-job hold (run created to first job queued) | 28 | 0s | 1s | 1s |
| Billable job-minutes per run | 28 | 10 | 20 | 23 |

| Job | n | Queued at | Done at | Waiting p50 / p90 | Setup p50 / p90 | Running p50 / p90 | Finished last | Runner |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| ios-tests | 14 | +0s | +17m41s | 2m31s / 49m57s | 10s / 14s | 15m00s / 19m47s | 50% | macos-latest |
| ios-build | 14 | +0s | +8m25s | 3s / 2m25s | 10s / 13s | 7m44s / 9m22s | 50% | macos-latest |
| sql-tests | 14 | +0s | +49s | 2s / 2s | 5s / 7s | 42s / 44s | 0% | ubuntu-latest |
| deno-tests | 14 | +0s | +20s | 2s / 2s | 7s / 9s | 11s / 12s | 0% | ubuntu-latest |
| validate | 14 | +0s | +7s | 2s / 2s | 5s / 6s | 0s / 0s | 0% | ubuntu-latest |

`ios-build` and `validate` belong to an earlier version of the workflow; the current `ci.yml` has `ios-tests` (macOS), `deno-tests` and `sql-tests` (Ubuntu).

Critical path: `ios-tests` (no `needs:`), p50 17m41s from queue to done, p90 dominated by waiting for a macOS runner (49m57s).

Inside `ios-tests` (run 42559164669, 19m51s): checkout/setup 17 s, Swift package resolution 1m26s, compile of the app and both test bundles 13m07s, unit tests 19 s, UI tests ~3 min, result bundle and upload ~1 min.

Triggers: `on: [push, pull_request]` with no branch filter and no `concurrency:` group, so every PR commit runs the whole workflow twice (one `push`, one `pull_request` run), each with its own macOS job, and superseded runs keep their runner.

Default-branch cache: none (`gh cache list` is empty); no cache step exists. Miss rate: n/a.
Reruns: 7 of 67 (10.4%), mostly "Failed to terminate/launch com.mindfriend.app" simulator failures on busy runners.
Billable job-min/run p50: 10 (the repository is public, so standard hosted runners cost nothing).

## Changes
| # | Commit | Change | Signal it targets | Critical path p50 / p90 before -> after | n | Cost delta | Kept |
|---|---|---|---|---|---|---|---|

### Considered and not applied
- **Cache Swift package checkouts** (setup, up to 1m26s). The resolved packages are 3.5 GB, of which 3.2 GB is `sentry-cocoa`'s six prebuilt framework variants (SwiftPM downloads every binary target although the app links one). Caching them would take about a third of the repository's 10 GB cache allowance to save at most ~1 minute, minus the multi-gigabyte restore. Not applied.
- **Faster or larger macOS runners** (waiting and running). They cost money; not proposed without approval.
