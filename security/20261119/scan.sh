#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
image=${1:?image}
output=${2:?output relative to repository root}
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
 -v /data/build/litellm/trivy-cache:/root/.cache -v "$PWD:/output" \
 aquasec/trivy@sha256:8f6bb947dbc528902e11f2f5be52f7b519f6a39d5d148f41166f2040499768fb \
 image --scanners vuln --pkg-types os,library --severity HIGH,CRITICAL \
 --format json --output "/output/$output" "$image"
