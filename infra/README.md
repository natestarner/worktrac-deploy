# Infrastructure as code (Bicep)

`backend.bicep` describes one backend Container App: size, replicas, probes, scale rules,
custom domains and every env var. `lower.bicepparam` and `prod.bicepparam` hold each
environment's values. Secrets are never in these files: they're read from environment
variables that the workflows fill from GitHub secrets, and a missing one fails the build
rather than deploying an empty value.

## Status

- **Lower:** every deploy applies these files (`deploy-lower.yml`, step "Deploy backend (apply
  Bicep)"). It logs the what-if summary first, as a record of what the apply changed.
- **Prod:** every deploy applies these files too (`deploy-prod.yml` on the `production` branch,
  step "Deploy backend (apply Bicep)"), since 2026-11-14. Before the switch, the preview against
  the live prod app showed only the 19 uncomparable secrets, and every one matched.

The `Infra — Preview Bicep changes` workflow runs `az deployment group what-if` on every PR
touching `infra/`. It reports which settings applying the files would change, by path and never
by value. what-if can't compare secret values, so it lists every secret env var as changed; a
second step compares those itself (`tools/compare-secret-env.py`) and prints only "match" or
"MISMATCH" per name. Adoption was proven on 2026-11-02: both apps showed only those
uncomparable secrets, and every secret matched.

## Alerts (prod)

`monitoring.bicep` + `prod.monitoring.bicepparam` hold production's alerts and the action group
that emails them (`huddle-prod-alerts`, to the admin address). `deploy-prod.yml`'s
`deploy-monitoring-prod` job applies them on every push to `production`, so change a rule here,
not in the portal. Prod only: lower scales to zero, so its normal state would trip "stopped
reporting".

| Rule | Fires when | Kind |
|---|---|---|
| `-5xx` | 10+ responses with a 5xx in 5 min | metric |
| `-restarts` | any container restart (crash, OOM kill, liveness) | metric |
| `-memory` | memory averages over 97% for 15 min (85-92% is normal) | metric |
| `-dtu` | database over 80% DTU for 15 min | metric |
| `-storage` | database over 80% of its max size | metric |
| `-email-stuck` | an email has waited over 15 min | log search, every 15 min |
| `-email-failed` | an outbox row gave up (muted 1h after firing) | log search, every 15 min |
| `-pool-saturated` | requests waited for a DB connection 3 of 5 minutes | log search, every 15 min |
| `-silent` | no `health-metrics` line for 10 min: down or hung | log search, every 10 min |

About $2.50/month: the five metric rules fall in the free 10, and log search rules cost
$0.50/month at a 15-minute frequency and $1.00 at 10 (eastus, 2026-11-14). The log rules parse the
backend's `health-metrics` line; its keys are an API (worktrac-source
`docs/azure-read-only-access.md`).

## Rules

- **Anything left out is removed.** Azure replaces a Container App's whole `template` on every
  apply, so an env var, probe or scale rule missing from here is deleted from the live app.
- **Keep env vars in the live order.** what-if compares arrays by position, so a reordering
  shows as a change.
- **Change infra here, not in the portal or with `az`, and that includes env vars, which no longer
  live in `deploy-lower.yml`.** A hand-made change is overwritten
  by the next apply. The preview shows any drift.

## Previewing locally

You need write-level Azure access (what-if needs it), the Bicep CLI (`az bicep install`), and
every variable that the `.bicepparam` file reads, exported in your shell:

```bash
az deployment group what-if -g worktrac-rg -p infra/lower.bicepparam
```
