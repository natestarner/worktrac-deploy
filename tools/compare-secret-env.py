"""Check that each secret env var the Bicep would set equals the value live on the app.

what-if can't compare values that come from secure parameters, so it reports every secret
as changed whether it is or not. This closes that gap. It prints each name with "match" or
"MISMATCH", never a value, and exits 1 if anything differs.

Usage: python3 tools/compare-secret-env.py <build-params.json> <containerapp-show.json>
  build-params.json:      output of `az bicep build-params --file infra/<env>.bicepparam --stdout`
  containerapp-show.json: output of `az containerapp show -o json`
"""
import json
import sys


def main(params_path, live_path):
    with open(params_path, encoding="utf-8") as f:
        params = json.loads(json.load(f)["parametersJson"])["parameters"]
    with open(live_path, encoding="utf-8") as f:
        live = json.load(f)

    wanted = params["secretEnv"]["value"]
    live_env = {
        e["name"]: e.get("value")
        for e in live["properties"]["template"]["containers"][0]["env"]
    }

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
