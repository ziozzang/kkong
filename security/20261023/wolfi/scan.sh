#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
image=${1:?image}
output=${2:?output relative to repository root}
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
 -v /data/build/litellm/trivy-cache:/root/.cache -v "$PWD:/output" \
 aquasec/trivy@sha256:790fd66d1697395d8693d1acaa1ea702406a20f109b6fc7bac8db623eca6c06c \
 image --scanners vuln --pkg-types os,library --severity HIGH,CRITICAL \
 --format json --output "/output/$output" "$image"
