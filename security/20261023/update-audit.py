#!/usr/bin/env python3
"""Summarize the saved public advisory responses; does not query credentials."""
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent
rows = json.loads((ROOT / 'advisory-assessment.json').read_text())
rows = [r for r in rows if r['component'] in ('OpenSSL', 'PCRE2')]
nginx = {
 'CVE-2026-15176': 'alias/rewrite 조합에서 조건부 영향. 코드 수정 반영',
 'CVE-2026-93479': '원본 1.31.0은 도입 범위 밖. 업그레이드 시 중간 취약판을 건너뛰어 수정된 1.31.8 사용',
 'CVE-2026-95101': 'HTTP/3 미컴파일로 실행 경로 없음. 소스 수정도 포함',
 'CVE-2026-97629': 'TLS session ticket 키 교체 사용 시 조건부 영향. 코드 수정 반영',
 'CVE-2026-97205': 'AIO 미컴파일로 해당 조합 실행 경로 없음. 소스 수정 포함',
 'CVE-2026-90439': 'HTTP/3 미컴파일로 실행 경로 없음. 소스 수정 포함',
 'CVE-2026-42533': 'map/regex 조합에서 조건부 영향. 코드 수정 반영',
 'CVE-2026-60005': 'slice 모듈 미컴파일. 소스 수정 포함',
 'CVE-2026-56434': 'SSI 사용 시 조건부 영향. 코드 수정 반영',
 'CVE-2026-42530': 'HTTP/3 미컴파일. 소스 수정 포함',
 'CVE-2026-42055': 'proxy-v2/gRPC의 입력 조건에 따라 영향. 코드 수정 반영',
 'CVE-2026-48142': 'charset 모듈 사용 조건에 따라 영향. 코드 수정 반영',
 'CVE-2026-9256': 'rewrite 지시문 조합에서 조건부 영향. 코드 수정 반영',
 'CVE-2026-49975': '상류가 추가한 max_headers 검사 코드는 원본 포크에도 이미 존재함을 소스로 확인',
}
for cve, result in nginx.items():
 rows.append(dict(component='nginx', id=cve, before='1.31.0', after='1.31.8', assessment=result, source='https://nginx.org/en/security_advisories.html'))
# These earlier nginx fixes were already included by the fork's 1.31.0 source.
for cve in ['CVE-2026-42926','CVE-2026-42945','CVE-2026-42946','CVE-2026-42934','CVE-2026-40460','CVE-2026-40701','CVE-2026-27654','CVE-2026-27784','CVE-2026-32647','CVE-2026-27651','CVE-2026-28753','CVE-2026-28755','CVE-2026-1642']:
 rows.append(dict(component='nginx',id=cve,before='1.31.0',after='1.31.8',assessment='공식 영향 범위는 1.31.0 미만. 원본 코어가 이미 수정 판에 포함됨',source='https://nginx.org/en/security_advisories.html'))
for cve, published, affected in json.loads((ROOT/'evidence/expat-CNA-index.json').read_text()):
 if published and published[:10] > '2026-10-23':
  continue
 rows.append(dict(component='Expat',id=cve,before='2.6.4',after='2.9.0 + PR 1431',
  assessment='공식 CNA 영향 범위를 원문 필드에 보존. 32-bit 전용·콜백 재진입·에러 복구 등 조건별 문제이며 변경 이력의 수정 판 2.9.0까지 반영. 새 버전에서 도입된 문제는 이전 2.6.4에 무조건 영향 있다고 보지 않음',
  affected_ranges=affected,source='https://www.cve.org/CVERecord?id='+cve))
more=[
 ('Brotli','CVE-2026-111497','1.1.0','1.2.1','취약 디코더가 포함된 소스 판. 이 nginx는 인코더를 사용하나 라이브러리 전체를 수정 판으로 교체','https://github.com/google/brotli/releases/tag/v1.2.1'),
 ('Brotli','CVE-2025-6176','1.1.0','1.2.1','Python/Scrapy 래퍼의 출력량 제한 관련 권고. 해당 Python 래퍼는 이미지에 없고 Brotli 소스도 최신으로 교체','https://github.com/google/brotli/releases'),
 ('Kong','CVE-2026-1907','fork 3.10.0','upstream 7e727db0a','하이브리드 제어 평면에 노출되는 공유 코드가 존재하므로 영향 있음. 노드 식별자·호스트 이름 검증을 소스에서 가져옴','https://www.cve.org/CVERecord?id=CVE-2026-1907'),
 ('Kong','CVE-2026-6338','fork 3.10.0','upstream af0acd7f4','CNA 대상 제품은 Enterprise. 공유 요청 처리 경로에도 상류 요청 밀수 수정을 보수적으로 반영. 비공개 Enterprise 수정과 1:1 동일하다고 단정하지 않음','https://www.cve.org/CVERecord?id=CVE-2026-6338'),
 ('Kong','CVE-2026-14916','OSS','OSS','Enterprise MCP OAuth2/DataKit JWT 검증 코드가 없어 비해당','https://www.cve.org/CVERecord?id=CVE-2026-14916'),
 ('Kong','CVE-2026-14917','OSS','OSS','SAML Enterprise 플러그인이 없어 비해당','https://www.cve.org/CVERecord?id=CVE-2026-14917'),
 ('Kong Operator','CVE-2026-16543','not included','not included','Operator/KIC는 이 저장소·이미지의 구성요소가 아님','https://www.cve.org/CVERecord?id=CVE-2026-16543'),
 ('Kong Insomnia','CVE-2025-1087','not included','not included','Insomnia 데스크톱 앱은 이미지에 없음','https://www.cve.org/CVERecord?id=CVE-2025-1087'),
 ('crossbeam-epoch','RUSTSEC-2026-0204','0.9.18','0.9.20','ATC 벤치마크의 개발 의존 경로. 실행 이미지에서 호출하지 않지만 잠금 파일까지 수정','https://rustsec.org/advisories/RUSTSEC-2026-0204.html'),
 ('Expat','PR-1431','2.9.0','2.9.0 + maintainer PR','XML_ParserReset의 누적 메모리 계수·설정 초기화 회귀. 10월 19일 공개된 유지보수자 수정과 회귀 테스트 적용','https://github.com/libexpat/libexpat/pull/1431'),
 ('Expat','CVE-2025-66382','2.6.4','UNFIXED in 2.9.0','LuaExpat을 통해 XML 처리에 영향 가능. 확정 공개 패치가 없어 미해결로 보존. 입력 크기·노출 범위 제한 필요','https://github.com/libexpat/libexpat/issues/1076'),
 ('Expat','PR-1433','2.9.0','not applied','외부 기여자의 미병합 엔터티 처리 개선 제안. 상류 확정 수정이 아니며 2.9.0과 충돌해 포함하지 않음','https://github.com/libexpat/libexpat/pull/1433'),
]
for component,ident,before,after,assessment,source in more:
 rows.append(dict(component=component,id=ident,before=before,after=after,assessment=assessment,source=source))
for cve in ['CVE-2026-5222','CVE-2026-5223','CVE-2025-15661','CVE-2026-55199','CVE-2026-55200','CVE-2026-33056']:
 rows.append(dict(component='Rust/Cargo build toolchain',id=cve,before='1.82.0',after='1.99.1',assessment='빌드 도구의 crate 취득·Git/SSH·압축 해제 관련 공개 보안 수정. 실행 이미지에는 Cargo를 넣지 않으며 빌드 도구도 공식 안정판으로 교체',source='https://doc.rust-lang.org/stable/cargo/CHANGELOG.html'))
(ROOT/'advisory-assessment.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
print('Saved',len(rows),'component/advisory assessments')
