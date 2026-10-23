#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
image=${1:-kkong:3.10.0-sec20261023}
output=${2:-scan-after.json}
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  -v /data/build/litellm/trivy-cache:/root/.cache/ \
  -v "$PWD:/output" aquasec/trivy:latest image --scanners vuln \
  --severity HIGH,CRITICAL --format json --output "/output/$output" "$image"
python3 - "$output" <<'PY'
import json,sys
report=json.load(open(sys.argv[1]));v=[v for r in report.get('Results',[]) for v in r.get('Vulnerabilities',[])]
print('HIGH/CRITICAL:',len(v))
for x in v:print(x['VulnerabilityID'],x['PkgName'],x['InstalledVersion'],x.get('FixedVersion','NO FIX'))
PY
