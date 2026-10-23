#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
expected=sha256:baf23aefd0afc2a343256b76b101d751b57b5cc03cd57c980d8fc31dc4c1091f
actual=$(docker image inspect kkong:3.10.0-sec20261023b --format '{{.Id}}')
[[ "$actual" == "$expected" ]] || { echo 'b판 이미지 ID 불일치' >&2; exit 1; }
echo '796f1389bfea13c0ed78f663b765baaff54a508e5483786bd6ece73c5e3e3cbe  mozilla-cacert-20261020.pem' | sha256sum -c -
docker build --network default -t kkong:3.10.0-sec20261023c-wolfi .
