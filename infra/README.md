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
