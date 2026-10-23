# 확인한 공개 근거 (2026-10-23)

- nginx 권고·판별 범위: https://nginx.org/en/security_advisories.html
- nginx 1.31.8 (2026-10-21) 및 1.31.7 보안 수정: https://nginx.org/en/CHANGES
- OpenSSL 권고와 영향 판: https://openssl-library.org/news/vulnerabilities/
- PCRE2 권고: https://github.com/PCRE2Project/pcre2/security/advisories
- Expat 수정 이력: https://github.com/libexpat/libexpat/blob/R_2_9_0/expat/Changes
- OpenResty 최신 모듈 묶음: https://openresty.org/en/ann-1031001001.html
- Kong 상류 보안 공지: https://github.com/Kong/kong/discussions/14867
- Kong 공개 GitHub 권고 목록: https://github.com/Kong/kong/security/advisories (목록 조회는 비어 있었고 CVE-2026-1907의 직접 GHSA 주소도 404였음. CNA 기록과 코드 변경도 함께 확인)
- Kong 상류 비교 기준: https://github.com/Kong/kong/commit/21032122ab80c973f368f6bc539f53985e7164e8
- 요청 밀수 수정: https://github.com/Kong/kong/commit/af0acd7f44025ad9613aa69064c732dd48c6fdcc
- 하이브리드 입력 검증: https://github.com/Kong/kong/commit/7e727db0a3043f4fe97a54331913795694a14892
- Rust 권고: https://rustsec.org/advisories/RUSTSEC-2026-0204.html
- NVD 대조: https://nvd.nist.gov/vuln/detail/CVE-2026-103111
- Enterprise 전용 JWT 문제(이 OSS 트리에는 해당 MCP OAuth2/DataKit 구현 없음): https://nvd.nist.gov/vuln/detail/CVE-2026-14916

원문과 조회 응답은 로컬 evidence/에 보존한다. 스캐너의 패키지 인식 범위 밖인 C·Lua 라이브러리는 이 근거와 소스 판을 직접 대조한다.

- Brotli 1.2.1 보안 릴리스: https://github.com/google/brotli/releases/tag/v1.2.1
- Brotli CNA 기록: https://www.cve.org/CVERecord?id=CVE-2026-111497
- Kong SQL 삽입 CNA 기록: https://www.cve.org/CVERecord?id=CVE-2026-1907
- Kong 요청 밀수 CNA 기록: https://www.cve.org/CVERecord?id=CVE-2026-6338 (Enterprise 대상 공지. 공유 요청 처리 코드는 보수적으로 추가 수정)
- SAML Enterprise 전용: https://www.cve.org/CVERecord?id=CVE-2026-14917
- 이 이미지에 없는 Operator/KIC: https://www.cve.org/CVERecord?id=CVE-2026-16543
- Expat 파서 초기화 수정(유지보수자, 2026-10-19 공개): https://github.com/libexpat/libexpat/pull/1431
- Expat 미해결 DoS: https://github.com/libexpat/libexpat/issues/1076
- Expat 미해결·미확인 목록: https://github.com/libexpat/libexpat/issues/1160
- 아직 채택하지 않은 외부 기여자의 Expat 개선 제안: https://github.com/libexpat/libexpat/pull/1433

- Rust 안정판과 구성요소 SHA-256: https://static.rust-lang.org/dist/channel-rust-stable.toml (2026-10-15, 1.99.1)
- Cargo 보안 수정 내역: https://doc.rust-lang.org/stable/cargo/CHANGELOG.html
- rules_rust의 WORKSPACE 호환 판: https://github.com/bazelbuild/rules_rust/releases/tag/0.67.0
