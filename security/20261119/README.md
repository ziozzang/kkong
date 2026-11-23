# kkong 3.10.1 보안 갱신 (2026-11-19): nginx 1.31.9 + distroless 실행 이미지

11월에 공개된 nginx·XML 파서 보안 수정을 반영해 다시 빌드했습니다. 실행 이미지는 Google distroless(Debian 13)로 바꿔 크기를 절반 가까이 줄였습니다. 버전은 3.10.0에서 **3.10.1**로 올렸고, 이미지 이름은 `kkong:3.10.1-sec20261119`입니다.

## 보정판 b (2026-11-23): `kkong:3.10.1-sec20261119b`

**root로 실행하면 `getpwnam("nobody") failed`로 기동하지 못하던 문제를 고쳤습니다.** 컨테이너를 root로 띄우는 경우가 대상입니다(`--user 0`, 일부 쿠버네티스·compose 설정). 첫 판(`sec20261119`)은 이 경우 실행되지 않으므로 b판을 쓰세요.

- 원인: 계정 파일(`/etc/passwd`, `/etc/group`)을 새로 쓰면서 distroless 원본의 `nobody` 항목을 빠뜨렸습니다. root로 시작한 nginx는 작업 프로세스를 기본 사용자 `nobody`/그룹 `nogroup`으로 내리려 합니다. 그런데 `kong` 명령도 내부에서 nginx를 띄우므로 처음부터 실패했습니다.
- 수정: distroless 원본 계정 파일을 그대로 두고 `kong`(10001)과 `nogroup`(65534)만 덧붙였습니다. 이제 root로 띄우면 주 프로세스는 root이고, 요청을 처리하는 작업 프로세스는 `kong`(10001)으로 돕니다. 기본 실행(UID 10001)도 그대로 됩니다.
- 함께 바꾼 것: distroless 기반을 최신 digest(`532c7a94…`)로 올렸습니다. 기반에 들어 있던 Debian OpenSSL(libssl3)은 지웠습니다. Kong·nginx·luasec는 모두 자체 빌드한 OpenSSL 3.5.9(`/usr/local/kong/lib`)를 쓰므로 이 라이브러리는 아무도 쓰지 않았습니다. 이 라이브러리에는 11-19 이후 공개된 수정 없는 HIGH(CVE-2026-124709, QUIC 서비스 거부)가 있었습니다.
- 결과: 위 시험을 모두 다시 통과했고, root 실행 시험을 추가했습니다. Trivy는 CRITICAL 0, HIGH 1(아래 perl-base 항목, 해당 없음)입니다.
- 참고: 65534 같은 임의 UID로 실행할 때는 `/usr/local/kong`에 쓸 수 없어 실패합니다. Ubuntu판·공식 Kong 이미지도 같은 동작이며, 이때는 `KONG_PREFIX`를 쓰기 가능한 볼륨으로 지정하세요.
- 이미지 ID `sha256:47fb95fbc47cec52e1df2f222b7d1ef6b5277b79075b5559aa22dac67b16f7a8`, 보관 파일 `kkong-3.10.1-sec20261119b.tgz` SHA-256 `eeb9bf368f31f8d072518c9e0eee6dcb1b1073e99769a2f36ccd360969c3521a`. 시험 로그는 `evidence/b/`.

## 무엇이 바뀌었나

| 구성요소 | 이전(10-23) → 이번 | 이유 |
|---|---|---|
| nginx | 1.31.8 → **1.31.9** (2026-11-18) | 보안 수정 10건. 심각(major) 3건: HTTP/2 흐름 제어 메모리 손상(CVE-2026-123007), TLS 1.3 요청 본문 무한 반복(CVE-2026-118899), 메일 프록시 해제 후 사용(CVE-2026-113425). 그 밖에 HTTP/2·HTTP/3·resolver 해제 후 사용, try_files+alias 버퍼 넘침, stream SNI 우회 등 |
| OpenResty Lua 모듈 | 1.31.1.1 번들 → **1.31.8.1** 번들 | double-free, 해제 후 사용(tcp_finalize), 재시도 무한 반복 등 메모리·안정성 수정. LuaJIT 2.1-20261023, ngx_lua 0.10.32rc7, stream_lua 0.0.20rc3, resty-core 0.1.35rc2, cjson 2.1.0.20, resty-cli 0.36 |
| Expat(XML 파서) | 2.9.0+PR1431 → **2.10.0** (2026-11-02) | 보안 수정 4건(CVE-2026-113351, -115506, -117610, -118370). 따로 넣던 PR1431은 2.10.0에 포함돼 뺐습니다 |
| 신뢰 CA 묶음 | Ubuntu 묶음에서 2개 비활성 → **Mozilla 2026-11-05 묶음** | 인증서 118개, emSign Root CA C1/C3 없음 |
| 실행 OS | Ubuntu 26.04 → **distroless cc-debian13** (nonroot, 오늘 받은 최신 digest) | 셸·패키지 관리자 없는 최소 이미지 |
| Kong 버전 | 3.10.0 → **3.10.1** | `kong version`, 관리 API `version`, 서버 헤더 `kong/3.10.1` |

Kong 상류(Kong/kong master)는 10-23 이후 보안 코드 변경이 없습니다(11-17 CI 수정 1건). Kong 자체 패치 20개는 새 소스에 그대로 적용됩니다.

## distroless에 더한 것

Kong 명령(`kong start`, `kong health`)은 내부에서 셸 명령과 perl로 된 `resty` 실행기를 부릅니다. 그래서 다음만 Debian 13 패키지에서 개별 파일로 복사했습니다. 모두 glibc 외 의존성이 없습니다.

- `perl-base`(resty 실행기), `dash`(`/bin/sh`), coreutils의 `ln chmod rm cat tr env`, 라이브러리 `libyaml`, `libcrypt`.
- 패키지 관리자, `ls`·`mkdir`·`wget` 같은 일반 도구, bash는 없습니다. 진입점은 POSIX sh로 옮겼습니다(`entrypoint.sh`, Docker secrets용 `*_FILE` 처리 유지).
- 처음에는 busybox를 넣었지만, 수정판이 없는 HIGH 12건이 나와서 dash+coreutils로 바꿨습니다.

실행 사용자는 `kong`(UID/GID 10001)입니다. 기본값은 DB-less이고, 관리 API는 loopback 주소에만 열립니다. 쓰기 가능한 곳은 `/usr/local/kong`(소켓·로그) 폴더 하나이고, 실행 파일과 라이브러리는 root 소유입니다.

## 검사·시험 결과 (모두 이 이미지에서 실행)

| 항목 | 결과 |
|---|---|
| Trivy 0.76.2, HIGH/CRITICAL, OS+언어 패키지, 무시 목록 없음 | CRITICAL 0, HIGH 1 (아래 설명) |
| DB-less 기동, 관리 API·상태·라우트, 프록시 GET/POST, 요청 밀수 회귀 경로, 없는 라우트 404, `kong health` | 통과 |
| TLS 인증서 처리 중 Lua 대기·재개 21회 | 통과 |
| HTTPS 업스트림: 정상 200, 이름 불일치 502, 신뢰 안 되는 인증서 502 | 통과 |
| 시스템 CA로 `https://example.com` 검증 | 통과 |
| 상류 호스트 이름 검증 63건 | 통과 |

**남은 HIGH 1건 (CVE-2026-9538, perl-base)**: Perl의 `Archive::Tar` 모듈(tar 파일 처리) 문제입니다. 이 모듈은 `perl-modules` 패키지에 들어 있고 `perl-base`에는 파일이 없으므로, 이 이미지에서는 해당 코드가 존재하지 않습니다. Debian은 수정을 미룬(fix_deferred) 상태입니다. 검사 결과를 숨기지 않으려고 무시 목록에 넣지 않았습니다.

Trivy는 직접 컴파일한 nginx·OpenSSL·Lua 코드는 인식하지 못합니다. 그래서 그 부분은 소스 판과 공식 공지를 직접 대조했습니다. **Expat CVE-2025-66382**(처리 시간 서비스 거부)는 상류에 확정 수정이 아직 없어 남아 있습니다. 10-23 판과 같은 상태입니다.

미검증: PostgreSQL·하이브리드 모드 전체 동작, 전체 플러그인 회귀, 장기 부하, arm64. WebAssembly 실행기와 관리 웹 UI는 빌드에서 제외했습니다(10-23과 같음). 기동 로그의 `ngx.sleep(0) … delayed events patch` 경고는 10-23부터 있던 것입니다.

## 크기

| 판 | 풀린 크기 | 압축 보관 |
|---|---|---|
| 10-23 b (Ubuntu) | 385.7 MiB | 120.9 MiB |
| 10-23 c (Wolfi, 비교용) | 327.6 MiB | 113.5 MiB |
| **11-19 (distroless)** | **213.2 MiB** | **61.0 MiB** |

## 다시 빌드·확인

```bash
cd /data/build/kkong
python3 security/20261119/repack-runtime.py      # 공식 원본 SHA-256 확인 후 소스 묶음 재생성
bash security/20261119/build.sh                   # Bazel 빌드(CPU 4, 12 GiB) + 이미지 포장
I=kkong:3.10.1-sec20261119
bash security/20261119/scan.sh $I security/20261119/evidence/scan.json
KKONG_TEST_WORK=$PWD/security/20261119/evidence/smoke bash security/20261119/smoke.sh $I
KKONG_TEST_WORK=$PWD/security/20261119/evidence/tls bash security/20261119/tls-yield.sh $I
python3 security/20261119/tls-upstream.py $I d
bash security/20261119/system-tls.sh $I
```

이미지 포장만 다시 할 때는 `KKONG_SKIP_BAZEL=1`을 씁니다. 시험용 상대 서버는 공식 `python:3.14-slim`을 씁니다(모델 호출 없음).

## 기술 메모

- 이미지 ID `sha256:1050954866bb0aace39a6b73134c50ee810971193e09f13a194ee45cdb641502`
- 보관 파일 `kkong-3.10.1-sec20261119.tgz` SHA-256 `1093c584afce1544dc1b750b4bad30045da676c5d5691e7123919797b7e698d2`
- 소스 묶음 `vendor/openresty/openresty-1.29.2.3-nginx-1.31.9-sec20261119.tar.gz` SHA-256 `0df79fab810b1ff596d64eb0d90f41b203f4b1ff6dc00f6268b8fc2e0eb374d7`
- 원본 서명 확인: nginx-1.31.9(Sergey Kandaurov), openresty-1.31.8.1(Yichun Zhang), expat-2.10.0(Sebastian Pipping)
- 기반: `gcr.io/distroless/cc-debian13:nonroot@sha256:cb87acc574abe719b6e5c547384defa2f7b1f24af9605d3f618cf852495d8be2`, `debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2`
- Trivy `aquasec/trivy@sha256:8f6bb947dbc528902e11f2f5be52f7b519f6a39d5d148f41166f2040499768fb`, 검사 시각 2026-11-19T01:32Z
- Mozilla CA 묶음 SHA-256 `427c064216761a1e72a8b30f0d954d08cb6e4435a82091fb865afd20c8497285`
- 시험 로그·검사 JSON: `security/20261119/evidence/` (저장소에는 넣지 않음)
