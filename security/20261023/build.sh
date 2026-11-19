#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
image=${KKONG_IMAGE:-kkong:3.10.0-sec20261023}
cache="$PWD/.work/cache"
mkdir -p "$cache"
# Wait if the host is already busy. Four visible CPUs also cap nproc inside Bazel's make rules.
while python3 -c 'import os,sys;sys.exit(0 if os.getloadavg()[0]>=40 else 1)'; do
  echo 'Host load is at least 40; waiting 30 seconds.'
  sleep 30
done
docker build -t kkong-builder:sec20261023 -f security/20261023/Builder.Dockerfile security/20261023
name="kkong-build-sec20261023-$$"
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT
docker run --name "$name" --cpus=4 --cpuset-cpus="${KKONG_CPUS:-0-3}" --memory=12g \
  -e KKONG_CLEAN="${KKONG_CLEAN:-1}" -v "$PWD:/src" -v "$cache:/root/.cache" kkong-builder:sec20261023 bash -euc '
    git config --global url.https://github.com/openldap/openldap.git.insteadOf https://git.openldap.org/openldap/openldap.git
    if [ "$KKONG_CLEAN" = 1 ]; then bazel --output_user_root=/root/.cache/kkong-bazel clean; fi
    bazel --output_user_root=/root/.cache/kkong-bazel build --config=release --jobs=4 --//:wasmx=false --//:skip_webui=true //build:kong --verbose_failures
    rm -rf runtime
    mkdir -p runtime
    cp -aL bazel-bin/build/kong-dev/. runtime/
    cp -a kong/include/. runtime/kong/include/
    find runtime -type f \( -name "*.a" -o -name "*.la" \) -delete
    rm -rf runtime/openresty/luajit/include
  '
docker build --pull -t "$image" -f security/20261023/Dockerfile .
printf '%s\n' "$image"
