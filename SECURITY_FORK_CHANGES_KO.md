# kkong 변경 정리

## 개요

이 문서는 `kkong` 리포에서 upstream Kong 대비 어떤 보안/런타임 변경이
들어갔는지 집중적으로 정리한 한국어 요약 문서다.

리포의 목적은 다음과 같다.

- Kong를 더 최신 nginx/OpenResty 런타임에서 검증
- TLS 핸드셰이크 관련 회귀를 패치
- 재현 가능한 일반화 테스트로 변경 효과를 검증

이 문서는 개인 도메인이나 개인 운영 정보 없이, 코드 변경과 검증 관점만
설명한다.

## 핵심 변경

### 1. 런타임 상향

주요 런타임 기준은 다음과 같이 바뀌었다.

- OpenResty 기준: `1.27.1.2` -> `1.29.2.5`
- nginx 코어 기준: custom porting으로 `1.31.1.x` 라인 검증
- Kong nginx dependency metadata: `1.31.1.5`

관련 파일:

- `.requirements`
- `build/openresty/repositories.bzl`
- `kong/meta.lua`

### 2. OpenResty 소스 오버라이드

upstream OpenResty tarball을 그대로 쓰지 않고, nginx `1.31.1` 계열이
반영된 로컬 repacked tarball을 참조하도록 변경했다.

이 repack에는 `ngx.pipe` 지원을 위해 필요한 nginx `socket_cloexec`
코어 패치도 함께 포함했다.

관련 파일:

- `build/openresty/repositories.bzl`

### 3. TLS yield 회귀 패치

가장 중요한 수정은 TLS certificate phase의 Lua yield/resume 회귀와
`ngx.pipe` 런타임 가용성을 함께 복원한 것이다.

핵심 패치 파일:

- `build/openresty/patches/nginx-1.27.1_12-ssl-lua-yield-retry.patch`

이 패치는 nginx/OpenSSL 핸드셰이크 재시도 경로를 복원한다.

추가로 repacked OpenResty에는 nginx `socket_cloexec` 코어 패치가 포함되어
있어 upstream integration harness에서 요구하는 `ngx.pipe`가 정상 동작한다.

복원 대상:

- `SSL_ERROR_WANT_X509_LOOKUP`
- `SSL_ERROR_PENDING_SESSION`
- `SSL_ERROR_WANT_CLIENT_HELLO_CB`
- `SSL_ERROR_WANT_RETRY_VERIFY`

이 변경들이 없으면 `ssl_certificate_by_lua` 진입 후 yield가 발생하는
경로에서 TLS EOF 형태의 실패가 발생할 수 있고, 일부 integration spec은
`ngx.pipe` 미지원 상태로 실행 전 중단될 수 있다.

### 4. 템플릿 충돌 방지 수정

Kong nginx 템플릿 쪽에서는 `lua_ssl_verify_depth`가 중복 선언되지 않도록
가드를 추가했다.

관련 파일:

- `kong/templates/nginx_kong_inject.lua`
- `kong/templates/nginx_kong_stream_inject.lua`

### 5. 더 이상 필요 없는 예전 패치 제거

이전 upstream 보완용 패치 중 일부는 최신 소스에 이미 반영되어 있으므로
삭제했다.

대표 예:

- `build/openresty/patches/ngx_lua-0.10.28_02-fix-invalid-hostname.patch`

## 변경 범주별 파일

주요 변경 범주는 다음과 같다.

### 빌드/런타임 정의

- `.requirements`
- `build/openresty/repositories.bzl`
- `build/repositories.bzl`
- `build/luarocks/BUILD.luarocks.bazel`
- `kong/meta.lua`

### OpenResty/nginx 패치셋

- `build/openresty/patches/`

특히 중요한 파일:

- `build/openresty/patches/nginx-1.27.1_12-ssl-lua-yield-retry.patch`

### Kong nginx 템플릿

- `kong/templates/nginx_kong_inject.lua`
- `kong/templates/nginx_kong_stream_inject.lua`
- `kong/templates/nginx_kong.lua`
- `kong/templates/nginx_kong_stream.lua`

## 테스트 및 검증

### 1. upstream 스타일 회귀 스펙

추가 파일:

- `spec/02-integration/05-proxy/35-ssl-yield-regression_spec.lua`

검증 내용:

- exact SNI direct TLS 인증서 선택
- wildcard SNI direct TLS 인증서 선택
- TLS 핸드셰이크 이후 실제 프록시 라우팅
- `postgres`
- `off` DB-less

테스트 데이터는 모두 일반화되어 있다.

- `exact.example.test`
- `edge.tls.example.test`
- `*.tls.example.test`

### 2. self-contained smoke script

추가 파일:

- `scripts/run-ssl-yield-regression.sh`

이 스크립트는 다음을 직접 수행한다.

- self-signed 인증서 생성
- DB-less Kong 기동
- PostgreSQL-backed Kong 기동
- direct TLS 핸드셰이크 검증
- 프록시 응답 검증

실행 예:

```bash
./scripts/run-ssl-yield-regression.sh
```

### 3. 확인된 결과

이 리포에서 확인하려는 핵심 결과는 다음이다.

- `ssl_certificate_by_lua` 경로가 최신 custom runtime에서도 즉시 깨지지 않음
- SNI 기준 exact/wildcard 인증서 선택이 동작함
- TLS handshake 후 실제 프록시 요청도 정상 처리됨

## 문서

영문 포팅 문서:

- `PORTING_1_31_1.md`

본 한국어 변경 요약:

- `SECURITY_FORK_CHANGES_KO.md`

## 주의사항

- 이 리포는 일반 upstream mirror가 아니다.
- 보안 목적의 runtime porting과 검증을 위한 security fork다.
- 따라서 upstream release line과 1:1 동일 동작을 보장하는 저장소로 보면 안 된다.
