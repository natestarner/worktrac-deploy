# Infrastructure as code (Bicep)

`backend.bicep` describes one backend Container App: size, replicas, probes, scale rules,
custom domains and every env var. `lower.bicepparam` and `prod.bicepparam` hold each
environment's values. Secrets are never in these files: they're read from environment
variables that the workflows fill from GitHub secrets, and a missing one fails the build
rather than deploying an empty value.

## Status

- **Lower:** every deploy applies these files (`deploy-lower.yml`, step "Deploy backend (apply
  Bicep)"). It logs the what-if summary first, as a record of what the apply changed.
- **Prod:** not yet. `deploy-prod.yml` (on the `production` branch) still runs
  `az containerapp update`. Its switch is a separate PR to `production`.

The `Infra — Preview Bicep changes` workflow runs `az deployment group what-if` on every PR
touching `infra/`. It reports which settings applying the files would change, by path and never
by value. what-if can't compare secret values, so it lists every secret env var as changed; a
second step compares those itself (`tools/compare-secret-env.py`) and prints only "match" or
"MISMATCH" per name. Adoption was proven on 2026-11-02: both apps showed only those
uncomparable secrets, and every secret matched.

## Secrets

An env var marked `secret: true` in a `.bicepparam` file is stored as a **Container App secret**
(named like the env var, lowercased with `-`: `spring-datasource-url`), and the env var only
references it (`secretRef`). The values never appear in the app's template, so the portal, `az
containerapp show` and anyone with Reader see names, not values. The app's environment is the same.

Changing only a secret's value doesn't start a new revision on its own, so `backend.bicep` also
sets `SECRETS_FINGERPRINT`, a one-way hash of all the secret values together: rotate a GitHub
secret, redeploy, and the hash changes, which forces the new revision that picks it up.

`tools/compare-secret-env.py` (the preview's secret check) reads secretRef values with `az
containerapp secret list --show-values` inside the runner and still prints only match/MISMATCH.

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
