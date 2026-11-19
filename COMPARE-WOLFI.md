# Kong 실행 환경 비교: Ubuntu b판과 Wolfi c판

2026-10-23에 Wolfi 시험판 c를 만들고 Ubuntu 보정판 b와 같은 시험으로 비교했다. **기본 배포판은 Ubuntu b판을 유지한다.** c판은 실행 환경을 줄일 수 있는지 확인하는 비교용이며 실제 서비스에 배포하거나 원격 저장소로 push하지 않았다.

| 비교 항목 | b판: Ubuntu | c판: Wolfi | 읽는 방법 |
|---|---|---|---|
| 이미지 이름 | `kkong:3.10.0-sec20261023b` | `kkong:3.10.0-sec20261023c-wolfi` | 둘 다 amd64 |
| 이미지 크기: 풀린 레이어 합계 | 385.71 MiB (404,451,486바이트) | 327.58 MiB (343,493,024바이트) | c판은 58.13 MiB, 약 15.07% 작음. 실제 공유 디스크 점유량과 다름 |
| 압축 보관 파일 | 120.91 MiB (126,788,249바이트) | 113.50 MiB (119,010,863바이트) | 기존 b 보관본과 이번 c 보관본의 실측. 압축 설정을 통일한 벤치마크는 아님 |
| 설치 OS 패키지 수 | 95개 | 26개 | 각 OS 설치 장부에서 셈. 패키지를 나누는 방식이 달라 공격면 감소율로 바로 환산할 수 없음 |
| Trivy HIGH / CRITICAL | 0 / 0 | 0 / 0 | 같은 도구·취약점 DB, 무시 목록이나 수정 가능 여부 필터 없음 |
| 언어 패키지 취약점 | 검출 항목 0개 | 검출 항목 0개 | OS·언어 양쪽 검사. Trivy가 인식한 언어 패키지 파일 자체가 0개여서 Lua·직접 컴파일 라이브러리의 안전을 보증하지 않음 |
| 신뢰 CA 묶음 | 인증서 118개, emSign C1/C3 0건 | 인증서 118개, emSign C1/C3 0건 | 두 판 모두 제거 반영. b판에는 신뢰 해제된 원본 `.crt` 2개가 남아 있으나 신뢰 목록과 활성 연결에서는 제외됨 |
| CA 갱신 방식 | Ubuntu 묶음에서 두 루트를 비활성화 | Wolfi apk 묶음을 Mozilla 2026-10-20 묶음으로 교체 | c판도 기반 이미지 갱신만으로 해결됐다고 주장하지 않음. 후속 CA 갱신은 보정 자료와 함께 재빌드·재검사 필요 |
| 실행 파일 | 기존 Bazel 빌드 | 같은 파일 재사용 | `/usr/local` 일반 파일 2,699개의 SHA-256이 전부 같음. nginx 1.31.8, 내장 OpenSSL 3.5.9 등 유지 |
| 기본 사용자·노출 설정 | UID 10001, DB-less, 관리 API loopback | 동일 (GID도 10001) | 익명 통계·관리 웹 UI 비활성 |
| 재현성 | Ubuntu 기반 digest 고정 | Wolfi 기반 digest 고정, b 실행 파일 이미지 ID 검사 | 두 판 모두 갱신 저장소의 OS 패키지는 완전히 고정하지 않음. digest 고정만으로 향후 빌드의 바이트 동일성을 보장하지 않음 |
| 지원 범위 | 기존 기본 실행 환경 | 이번 시험 범위의 실행 확인 | 어느 판도 이 사용자 포크에 대한 공급업체 지원을 확보한 것은 아님 |
| 주의할 점 | 더 많은 OS 패키지와 기존 유지보수 절차 | apk·다른 glibc·명령 도구 구성에 맞춘 유지보수 필요 | c판 glibc는 2.44. 전체 플러그인과 장기 부하에서 호환성은 추가 확인 필요 |

## 실제 동작 확인

다음 시험을 **b판과 c판 모두에서 다시 실행해 통과**했다. 컨테이너 시험은 격리된 내부 네트워크와 CPU·메모리 제한을 사용했다.

- DB-less 기동과 `kong health`, 관리 API·상태·라우트 조회 200.
- 프록시 GET 200, POST 본문 보존, `Connection: content-length` 요청 밀수 회귀 경로, 없는 라우트 404.
- TLS 인증서 처리 중 Lua 대기·재개와 HTTP 응답 21회.
- 상류 호스트 이름 검증 63개 사례. 전체 Busted 실행이 아닌 기존 경량 실행기 사용.
- HTTPS 업스트림: 올바른 인증서 200, 이름 불일치 502, 신뢰되지 않은 인증서 502. 서비스에 명시적으로 시험 CA를 지정했다. 시스템 신뢰 저장소는 별도 외부 HTTPS 시험으로 확인했다.
- 시스템 CA 묶음을 명시한 Lua HTTPS 클라이언트에서 `https://example.com` 인증서 검증과 응답 200. 체인 깊이 5를 명시했다.
- 이미지 전체 파일 장부에서 모든 `cacert.pem`을 탐색했다. c판에는 해당 이름의 파일이 0개다. 시스템 묶음 118개의 인증서를 개별 해석해 금지한 두 루트가 없음을 확인했다. `/etc/ssl/cert.pem`, `ca-bundle.crt` 등은 검증한 묶음으로 연결된다.

처음 시험용 Python 이미지의 기본 진입점이 실행되어 프록시 시험이 실패한 것은 시험기에 명시적인 Python 진입점을 주어 수정했다. 최초 TLS 업스트림 시험은 Lua용 CA 설정만 주어 실패했으며 Kong 서비스의 `ca_certificates`에 시험 CA를 지정해 정상/오류 사례를 다시 확인했다. 외부 Lua HTTPS 초기 시험은 기본 인증서 체인 깊이에서 실패해 깊이 5를 명시했다. 이 과정에서 b/c 제품 파일은 바꾸지 않았다. 최종 통과 로그는 아래 근거 폴더에 있다.

## 남는 위험과 판단

**이번 결과는 c판의 크기·패키지 수 감소를 뒷받침한다. 취약점 수 개선은 두 판 모두 0이므로 확인되지 않았다.** 운영 기본판 교체의 근거로는 부족하다.

직접 컴파일한 nginx·OpenSSL·Lua 라이브러리와 Rust ATC 구성은 b판 그대로다. 기존 소스 감사·구성 목록은 `security/20261023/inventory.json`, `advisory-assessment.json`, `SOURCES.md`를 따른다. 특히 확정 수정이 공개되지 않은 **Expat CVE-2025-66382는 그대로 남는다.** Trivy 0건이 모든 보안 문제 해결을 의미하지 않는다.

PostgreSQL·하이브리드 전체 동작, 전체 플러그인·사용자 플러그인, 장기 부하·성능, arm64는 미검증이다. WebAssembly 실행기와 Kong Manager UI는 b판과 동일하게 제외했다. 기존 `ngx.sleep(0)` 성능 경고도 남는다. Expat의 소스 테스트 5,220개는 앞선 빌드 결과이며 이번에는 재실행하지 않았다.

Wolfi는 컨테이너용 최소 배포판으로 별도의 패키지 생태계를 쓴다. 이번 사용자 포크는 Wolfi의 공식 Kong 제품 이미지가 아니므로 Chainguard의 지원·보증이 자동으로 적용된다고 볼 수 없다. 공식 설명: [Wolfi 안내](https://edu.chainguard.dev/open-source/wolfi/), [wolfi-base 사용법](https://images.chainguard.dev/directory/image/wolfi-base/overview).

## 산출물과 다시 확인하는 방법

- 보관 파일: `/data/build/kkong/kkong-3.10.0-sec20261023c-wolfi.tgz`, 같은 이름의 `.sha256`.
- Dockerfile·빌드·CA·시험 스크립트: `security/20261023/wolfi/`.
- 스캔 JSON: `security/20261023/wolfi/scan-b.json`, `scan-c.json`.
- 파일·패키지·CA 비교: `security/20261023/wolfi/evidence/audit.json`, `payload-b.json`, `payload-c.json`, `packages-*.txt`.
- 시험 로그·결과: 같은 `evidence/` 폴더의 `*-b.log`, `*-c.log`, `b/`, `c/`.

```bash
cd /data/build/kkong
sha256sum -c kkong-3.10.0-sec20261023c-wolfi.tgz.sha256
docker load -i kkong-3.10.0-sec20261023c-wolfi.tgz
bash security/20261023/wolfi/build.sh
bash security/20261023/wolfi/scan.sh kkong:3.10.0-sec20261023c-wolfi security/20261023/wolfi/scan-c.json
KKONG_TEST_WORK="$PWD/security/20261023/wolfi/evidence/c" bash security/20261023/wolfi/smoke.sh kkong:3.10.0-sec20261023c-wolfi
KKONG_TEST_WORK="$PWD/security/20261023/wolfi/evidence/c" bash security/20261023/wolfi/tls-yield.sh kkong:3.10.0-sec20261023c-wolfi
python3 security/20261023/wolfi/tls-upstream.py kkong:3.10.0-sec20261023c-wolfi c
bash security/20261023/wolfi/system-tls.sh kkong:3.10.0-sec20261023c-wolfi
python3 security/20261023/wolfi/audit.py
```

기동·TLS 시험은 이미 로컬에 있는 `litellm:v1.106.2-sec20261023b`의 Python만 시험용으로 사용한다. 모델 호출은 없다. 자동 생성한 시험 개인키는 시험 후 삭제했다.

기술 메모:
- Wolfi 기반: `cgr.dev/chainguard/wolfi-base@sha256:f15fea2f49cb14dceaea491fcbde0d35e0c190126a744ac05a9838440d47d994`.
- 실행 파일 원본 b 이미지 ID: `sha256:baf23aefd0afc2a343256b76b101d751b57b5cc03cd57c980d8fc31dc4c1091f`.
- 최종 c 이미지 ID: `sha256:8f1b7fe5d88a6625c4ff679f00403673da18b01edd8ebdfc9acfc2e4b3084fdd`.
- 보관 파일 SHA-256: `faf212fd5b36d476436382f9c5bf6089bf432d71133930a224dfa52f43818770`.
- Mozilla 묶음 SHA-256: `796f1389bfea13c0ed78f663b765baaff54a508e5483786bd6ece73c5e3e3cbe`.
- Trivy 0.76.1, 검사 DB 갱신 시각 `2026-10-22T19:14:47Z`, b/c 동일. 스캐너 digest와 DB 자료도 `evidence/`에 보관했다.
