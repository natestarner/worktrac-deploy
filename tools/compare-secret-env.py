"""Check that each secret env var the Bicep would set equals the value live on the app.

what-if can't compare values that come from secure parameters, so it reports every secret
as changed whether it is or not. This closes that gap. It prints each name with "match" or
"MISMATCH", never a value, and exits 1 if anything differs.

A live env var is either a plain value (how every secret was stored before 2026-11-14) or a
`secretRef` naming one of the app's secrets (how backend.bicep stores them since). For a
secretRef, the value is read from the app's secrets with `az containerapp secret list
--show-values`, inside the runner, and only compared, never printed.

Usage: python3 tools/compare-secret-env.py <build-params.json> <containerapp-show.json>
  build-params.json:      output of `az bicep build-params --file infra/<env>.bicepparam --stdout`
  containerapp-show.json: output of `az containerapp show -o json`
"""
import json
import subprocess
import sys


def live_secret_values(live):
    """The app's secrets by name, with values. Only called when some env var uses secretRef."""
    out = subprocess.run(
        ["az", "containerapp", "secret", "list",
         "--name", live["name"], "--resource-group", live["resourceGroup"],
         "--show-values", "-o", "json"],
        capture_output=True, text=True, check=True,
    )
    return {s["name"]: s.get("value") for s in json.loads(out.stdout)}


def main(params_path, live_path):
    with open(params_path, encoding="utf-8") as f:
        params = json.loads(json.load(f)["parametersJson"])["parameters"]
    with open(live_path, encoding="utf-8") as f:
        live = json.load(f)

    wanted = params["secretEnv"]["value"]
    live_env_entries = live["properties"]["template"]["containers"][0]["env"]

    secrets = None
    live_env = {}
    for e in live_env_entries:
        if e.get("secretRef"):
            if secrets is None:
                secrets = live_secret_values(live)
            live_env[e["name"]] = secrets.get(e["secretRef"])
        else:
            live_env[e["name"]] = e.get("value")

    mismatches = 0
    for name in sorted(wanted):
        if name not in live_env:
            status = "MISSING on the live app"
            mismatches += 1
        elif live_env[name] == wanted[name]:
            status = "match"
        else:
            status = "MISMATCH"
            mismatches += 1
        print(f"  {status:<8} {name}")
    return 1 if mismatches else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
