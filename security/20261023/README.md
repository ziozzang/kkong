# kkong 보안 갱신 컨테이너 (2026-10-23)

Kong 3.10.0 포크를 최신 보안 수정이 적용된 nginx 1.31 계열에서 실행하도록 갱신했다. 보안 수정은 로컬 브랜치 `security/20261023`에 보존하며 원격 push는 하지 않았다.

| 구성요소 | 이전 → 이번 이미지 | 바꾼 이유·영향 판단 |
|---|---|---|
| nginx | 1.31.0 → 1.31.8 | 정규식·요청 처리·TLS 세션 등의 공개 보안 수정 반영. HTTP/3처럼 빌드하지 않은 기능의 수정도 소스에 포함 |
| OpenResty Lua 모듈 | 1.29.2.3 번들 → 공식 1.31.1.1의 모듈 | Lua 처리 중 메모리 접근·종료 오류 수정. 포크의 TLS 대기·재개 패치는 유지 |
| LuaJIT | 2.1-20260311 → 2.1-20260415 | 공식 새 번들에 포함된 런타임 수정 반영 |
| OpenSSL | 3.4.1 → 3.5.9 LTS | 인증서·암호·TLS 관련 공개 권고 반영. 새 주 버전 4.x 대신 장기 지원 3.5 사용 |
| PCRE2 | 10.45 → 10.49 | 정규식 JIT 등의 잘못된 메모리 접근 수정 |
| Expat | 2.6.4 → 2.9.0 + 유지보수자 PR 1431 | XML 파싱의 메모리·처리시간 문제와 파서 초기화 회귀 수정. 미해결 문제는 아래에 별도 기재 |
| Brotli | 1.1.0 → 1.2.1 | 10월 21일 공개된 CVE-2026-111497 수정. nginx는 압축 인코더를 사용하지만 소스의 디코더도 함께 갱신 |
| Kong 코어 | 상류 보안 수정 2건 추가 | 요청 밀수 방지와 하이브리드 모드의 노드·호스트 이름 검증. 출처 커밋은 각 커밋 메시지와 SOURCES.md에 기록 |
| Lua 라이브러리 | HTTP 0.18.0, OpenSSL 1.9.0, session 4.2.0, AWS 1.7.2 등 | 관련 런타임 API와 수정 반영. HTTP 0.18은 본문 없는 POST/PUT/PATCH를 더 엄격하게 처리하므로 사용자 플러그인은 확인 필요 |
| Rust / ATC router | Rust 1.82.0 → 1.99.1, ATC 1.7.1 유지, crossbeam-epoch 0.9.18 → 0.9.20 | RUSTSEC-2026-0204 수정. 컴파일러·Cargo도 공식 안정판으로 갱신했고 최신 Cargo를 지원하도록 rules_rust 0.67.0과 rules_cc 0.0.14을 적용했다. 해당 crate는 ATC의 개발·벤치마크 의존 경로지만 잠금 파일도 갱신. 91개 crate 재조회 결과 알려진 권고 0개 |
| 실행 OS | Debian 13 비교 이미지 → Ubuntu 26.04.1 LTS | Debian 비교 이미지의 HIGH/CRITICAL 46개 패키지 항목을 해소. Ubuntu 기본 이미지의 불필요한 Pebble 실행 파일도 실제로 제거 |
| LuaRocks / 기타 | LuaRocks 3.12.2, Ada 2.9.2, Snappy 1.2.1, LMDB 등 유지 | 공개 권고·최근 릴리스를 대조했으며 이 판에 적용해야 하는 확정된 추가 보안 수정을 찾지 못함. 전체 판은 inventory.json과 installed-rocks.tsv 참조 |

## 이미지 범위

amd64의 프록시·관리 API용 이미지다. 기본 사용자는 `kong`(UID/GID 10001), DB-less 모드이며 관리 API는 컨테이너의 loopback 주소에만 열린다. 익명 사용 통계 전송은 껐다.

실험적 WebAssembly 실행기(ngx_wasm_module, Wasmtime 26, Wasmer 3, V8 12)와 Kong Manager 웹 UI는 빌드하지 않는다. 이 기능이 필요한 경우 별도 업그레이드·검증이 필요하다. 이 이미지가 그 기능을 제공한다고 보면 안 된다. 포크의 기존 OpenResty 버전 라벨은 호환성을 위해 유지했으며 실제 내장 nginx·Lua 모듈 판은 따로 확인했다.

## 확인 방법과 결과

- 공식 Bazel `//build:kong --config=release`로 소스에서 빌드했다. 컨테이너 포장은 공식 `build/package/nfpm.yaml`의 파일 배치를 따라 `.proto` 정의까지 포함한다.
- Trivy `--scanners vuln --severity HIGH,CRITICAL`: 비교 이미지 46개 항목 → 최종 이미지 0개 항목. 수정 가능 항목을 숨기는 옵션이나 무시 목록은 쓰지 않았다. `scan-before.json`, `scan-after.json`은 저장소 최상위의 로컬 산출물이다.
- DB-less 기동, 관리 API·상태·라우트 조회, 실제 upstream GET/POST, 요청 밀수 수정 경로, 없는 라우트의 404, `kong health`를 시험한다.
- `ssl_certificate_by_lua`에서 `ngx.sleep`으로 대기하는 TLS 연결 21회를 시험한다.
- 상류 호스트 이름 검증 63개 사례는 해당 테스트 파일을 작은 Lua 실행기로 실행한다(Busted 전체 실행은 아님).
- Expat 2.9.0 + PR 1431은 상류 `make check`의 5,220개 검사에서 실패 0개였다.
- `repack-runtime.py`로 공개 원본을 다시 묶은 결과는 저장한 커스텀 소스 tar의 SHA-256과 일치한다.
- PostgreSQL·하이브리드 전체 동작, 전체 플러그인 회귀·성능 시험과 arm64는 미검증이다. 기본 기동 로그에는 기존 커스텀 nginx의 delayed-events 패치 부재에 따른 `ngx.sleep(0)` 성능 경고가 남는다.

Trivy는 직접 컴파일한 C·Lua 코드를 패키지로 인식하지 못할 수 있다. 따라서 **스캔 0개는 모든 취약점이 없다는 뜻이 아니다.** 소스 판과 공식 권고를 별도로 대조한 결과는 `advisory-assessment.json`, `SOURCES.md`에 있다.

## 남는 공개 보안 문제

Expat 상류의 [CVE-2025-66382 / 이슈 1076](https://github.com/libexpat/libexpat/issues/1076)은 모든 배포판에 남은 서비스 거부 문제이며, 2026-10-23 기준 공개된 확정 수정이 없다. 약 2 MiB의 악성 XML로 긴 처리시간이 생길 수 있다고 유지보수자가 공지했다. 이 이미지에는 LuaExpat도 설치되므로 XML 처리 경로가 영향을 받을 수 있다. XML 처리 플러그인의 입력 크기·접근 범위를 제한하고 추후 상류 수정을 반영해야 한다. 완전 해결로 표시하지 않았다.

[이슈 1160](https://github.com/libexpat/libexpat/issues/1160)의 미공개·미확인 항목은 세부 정보와 수정이 없어 영향 여부를 확정할 수 없다. 10월 22일 외부 기여자가 올린 [PR 1433](https://github.com/libexpat/libexpat/pull/1433)은 별도의 XML 엔터티 처리시간 개선 제안이다. 아직 상류 승인·병합된 수정이 아니며 2.9.0에 그대로 적용되지도 않아 이미지에는 넣지 않았다. 유지보수자의 PR 1431은 별도로 출처를 남기고 상류 테스트를 통과시켜 포함했다.

## 다시 빌드·검사

```bash
./security/20261023/build.sh
./security/20261023/scan.sh
./security/20261023/smoke.sh
./security/20261023/tls-yield.sh
```

기본 빌드는 Bazel 출력과 `runtime/`를 비워 이전 라이브러리가 섞이는 것을 막는다. 다운로드 캐시는 `.work/cache`에 두며 빌드 CPU는 4개, 메모리는 12 GiB로 제한한다. 부하평균이 40 이상이면 대기한다. `KKONG_CPUS`로 쓸 CPU를 지정할 수 있다. 검토된 증분 빌드에만 `KKONG_CLEAN=0`을 사용할 수 있다.

Ubuntu와 빌드용 Debian 이미지는 digest로 고정했다. 보안 패키지는 각 배포판의 갱신 저장소에서 설치하므로 나중에 다시 빌드하면 OS 패키지와 이미지 digest는 달라질 수 있다. 소스와 산출 이미지의 SHA-256은 별도로 보존한다.

```bash
docker load -i kkong-3.10.0-sec20261023.tgz
# config.yml은 _format_version: "3.0"인 선언형 설정 파일이며 UID 10001이 읽을 수 있어야 한다.
docker run --rm --name kkong --ulimit nofile=4096:4096 \
  -p 127.0.0.1:8000:8000 \
  -v "$PWD/config.yml:/config/config.yml:ro" \
  -e KONG_DECLARATIVE_CONFIG=/config/config.yml \
  kkong:3.10.0-sec20261023
```

소스 재묶음은 저장소 최상위에서 `python3 security/20261023/repack-runtime.py`로 수행한다. 공식 배포본 SHA-256을 확인한 뒤 nginx 변경과 OpenResty 모듈 갱신을 적용한다. 다운로드한 근거 원문·시험 로그는 로컬 `evidence/`에 남기며 비밀값이나 개인 인증 자료는 포함하지 않는다.
