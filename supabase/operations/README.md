# One-off operations

Scripts here are not migrations. `supabase db push` never runs them; each needs its own review and explicit approval before anyone applies it.

- `20261022_private_media.sql`: makes the private media buckets non-public. Held until signed-URL gallery, history, playback, refresh, owner access and cross-owner denial are verified with a compatible client (issue #57). Not applied.
- `20261022_repair_cron.sql`: proposed repair that routes the scheduled HTTP jobs through `public.invoke_mindfriend_cron` with a cron secret and pauses them until each workload is reviewed. It requires a matching `CRON_SECRET` in Vault and the edge secrets. Not applied: on 8 November 2026 production had no `invoke_mindfriend_cron` function, and jobs 58, 59, 60, 67, 68, 69, 76 and 77 were still active with the exact pre-repair command hashes the script checks.
