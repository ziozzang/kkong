# kkong 보안 감사 요약 (Kong 1.31.x 포크)

## 1. Methodology (요약)

- `upstream/master` 대비 포크 델타를 먼저 식별 (`git diff upstream/master..HEAD`)
- 지정된 고위험 영역(SSL yield patch, OpenResty override, 템플릿, 메타데이터, 스모크 스크립트, CI, 빌드)을 우선 정적 분석
- 위험 패턴 검색(`pull_request_target`, secret 노출 패턴, `loadstring`/`os.execute`류, 무결성 해시 패턴)
- vendored OpenResty tarball 내부를 직접 열어(nginx 버전 매크로/핸드셰이크 코드) 교차검증
- 최근 GitHub Actions 실패 로그(Dependabot) 확인

제약:
- `make test-custom ...35-ssl-yield-regression_spec.lua` 실행을 시도했으나, sandbox DNS 문제로 Bazel 다운로드 실패하여 동적 재현 일부 미완료.

## 2. Findings 요약표

| ID | 제목 | Severity | Status | 위치(핵심) |
|---|---|---|---|---|
| KKONG-AUDIT-001 | vendored OpenResty 아카이브 경로에서 명시적 무결성 검증 부재 | Medium | Confirmed | `build/openresty/repositories.bzl:43-51,107-142` |
| KKONG-AUDIT-002 | TLS WANT_* 재시도 분기에서 event-loop spin 가능성(가설) | Medium | Suspected | `build/openresty/patches/nginx-1.27.1_12-ssl-lua-yield-retry.patch:8-34,43-109` |
| KKONG-AUDIT-003 | invalid-hostname 패치 제거 문서와 실제 상태 불일치 | Low | Confirmed | `PORTING_1_31_0.md:17-18`, `build/openresty/patches/ngx_lua-0.10.28_02-fix-invalid-hostname.patch` |
| KKONG-AUDIT-004 | `pull_request_target`+PR checkout+secret 노출 전형 패턴 | Informational | Cleared | `.github/workflows/*.yml` |
| KKONG-AUDIT-005 | `lua_ssl_verify_depth` 가드 변경으로 TLS 약화 유도 가능성 | Informational | Cleared | `kong/templates/nginx_kong_inject.lua`, `...stream_inject.lua` |
| KKONG-AUDIT-006 | 스모크 스크립트 임시파일/셸 인젝션 위험 | Informational | Cleared (caveat) | `scripts/run-ssl-yield-regression.sh` |
| KKONG-AUDIT-007 | 버전 메타데이터 불일치/오인 가능성 | Informational | Cleared | `.requirements`, `kong/meta.lua`, vendored `nginx.h` |
| KKONG-AUDIT-008 | `kong.conf.default` 위험 기본값 변경 여부 | Informational | Cleared | `kong.conf.default` |

## 3. 핵심 판단

### KKONG-AUDIT-001 (Confirmed, Medium)
- 포크는 upstream의 `http_archive(urls+sha256)` 대신 vendored tarball 추출 방식으로 전환.
- 이 경로에서 OpenResty 아카이브에 대한 별도 sha 검증 로직이 보이지 않음.
- 영향: 아카이브 생성/반입 파이프라인이 침해되면 공급망 리스크가 확대될 수 있음.

### KKONG-AUDIT-002 (Suspected, Medium)
- TLS yield patch는 WANT_* 에러를 `NGX_AGAIN` 재시도로 복원함.
- 다만 WANT_READ/WRITE 분기와 달리 ready flag clear가 없어 특정 조건에서 busy retry 가능성이 의심됨.
- 동적 재현은 이번 환경 제약으로 미완료.

### KKONG-AUDIT-003 (Confirmed, Low)
- 포팅 문서는 invalid-hostname 패치 제거를 서술하지만, 실제 파일이 존재하고 patch 목록 생성 로직에도 포함됨.
- 직접 취약점이라기보다 감사/운영 추적성 저하 이슈.

## 4. 실행한 점검 케이스(요약)

- 델타/히스토리: `git diff`, `git log`(파일 단위 포함)
- 패턴 검색:
  - `pull_request_target`, `write-all`, secrets 관련
  - `loadstring|load\(|os.execute|io.popen|ngx.exec`
  - `sha256|integrity|urls|http://`
  - `mktemp|eval|/tmp`
- 아카이브 검증:
  - `tar -tzf`로 경로 확인
  - `tar -xOf ... nginx.h`로 `NGINX_VERSION "1.31.0"` 확인
  - `tar -xOf ... ngx_event_openssl.c`로 patch hunk 문맥 확인
- CI:
  - workflow runs 조회
  - 실패 run(Dependabot) 로그 확인: lockfile/pinned requirement 부재로 실패

## 5. Residual Risk / 미커버 영역

- WANT_* 재시도 경로의 고부하 동작(무한 재시도/CPU spin) 동적 재현 미완료
- vendored tarball 생성 provenance(서명/attestation) 외부 검증 미수행
- 모든 workflow를 실제 공격 시나리오로 실행해보는 동적 검증은 미수행

## 6. Tracking 체크리스트

- [ ] vendored OpenResty 아카이브 경로에 강제 무결성/출처 검증(해시+서명/attestation) 추가
- [ ] TLS WANT_* 분기에 대한 고부하 회귀 테스트 추가(이벤트 루프 spin 여부 포함)
- [ ] invalid-hostname 패치 관련 문서/실제 patch 정책 정합화
- [ ] `openresty-...as1292.tar.gz` 생성 절차/원본 커밋/검증 흐름 문서화
- [ ] 워크플로 트리거/secret 사용 방식 변경 시 정기 재감사
