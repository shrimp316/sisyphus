# MVP v1.0 — Phase A 조사와 기준 검증

기준 커밋은 `d4ba73bf49501f1be5a7d9c28a81a59025abda3d`, 작업 브랜치는 `codex/mastery-prestige-mvp`다. 이 문서는 구현 이전 상태와 기준 검사를 기록한다. 새 성장·UI·프레스티지의 완료 보고서는 아니다.

## 기존 구조

- 진입 씬은 루트 `main.tscn` 하나의 `Node2D`이며 `scripts/main.gd`가 화면·입력·그리기·저장을 처리한다. 별도의 숙련/프레스티지/세피로트 게임 씬은 기준 커밋에 없다. `godot/scenes/preview/`의 네 씬은 에셋 미리보기다.
- 물리는 `scripts/boulder_controller.gd`, 산 생성은 `scripts/mountain_manager.gd`와 `mountain_chunk.gd`다. 120Hz, D/Shift/Space, Slip 0.7초와 Runaway -4m/s가 기존 기준이다.
- `scripts/progression.gd`는 50m마다 회차 20XP와 신규 기록 10XP, 누적 상한 6,150, level 1~31 및 세 계열 rank 0~10을 사용한다. EXP 지갑과 35노드는 아직 기준 구현에 없다.
- 기준 저장 위치는 `user://sisyphus-v1.json`, 최상위 형식은 version 4이며 world/run/progression을 함께 저장한다. 브라우저 mirror는 `sisyphus:v02:`와 페이지·save path로 분리한다. 저장은 `.tmp` 후 rename 방식이다. 기존 저장을 자동 새 구매 상태로 변환해서는 안 된다.
- 기준 화면은 1920×1080, 초기 창 1280×720, canvas_items stretch, GL Compatibility이며 Web 대상이다.

## 에셋 조사

`rg --files`의 프로젝트 비무시 파일을 조사했다. `.git`, `.godot`, `.tools`와 생성된 감사 CSV 자체는 집계 대상이 아니다. 전체 PNG는 173개, CSV는 155개다. CSV 대부분은 기존 밸런스 실험 결과이며 UI 제작 목록과 구분했다.

- 메인화면 제작 목록은 `assets/MainMenu/Data/sisyphus_main_asset_inventory_v1.csv`다. `UI design/메인 UI/`의 동명 파일과 바이트가 같다. 27개 목록 항목의 wildcard 상태 파일과 확장자 없는 rig 묶음을 해석하면 모두 대응 파일이 있다. MainMenu PNG는 32개다.
- `main_sisyphus_rig.json`은 단일 sprite fallback이라고 명시한다. 10~12개 분리 파츠 리깅이 완성됐다고 해석하지 않는다. 원본 목록의 진행 상태 열은 여전히 ‘미착수’여서 실제 파일 존재와 별도로 기록했다.
- 세피로트 PNG 19개는 `assets/ui/sephirot/`에 있다. 상·하단 bar, core/branch 상태, thread/FX, back 버튼 상태를 제공한다. 이름·크기·SHA는 감사 JSON/CSV에 기록했다.
- 숙련 전용 `mastery_asset_mapping_v11.csv`, `mastery_node_layout_v11.csv`, `mastery_asset_requests_v11.csv` 및 다른 이름의 숙련 제작 목록은 발견하지 못했다. 실제 제공 파일이라고 꾸미지 않고 공통 노드 컴포넌트와 교체 가능한 매핑을 사용해야 한다.
- 원본 PNG는 수정·삭제·이름 변경하지 않았다. Phase A의 텍스트 참조 여부는 사용 확정 판정이 아니다. 동적으로 만든 경로도 있으므로 최종 사용/미사용 목록은 실제 UI 선택과 대조해야 한다.

상세: [asset-audit.json](asset-audit.json), [asset-audit.csv](asset-audit.csv). 통합에서 선택한 파일과 SHA는 별도 `assets-used.csv`에 기록한다.

## 물리 기준 보존

기준 커밋의 컨트롤러 git blob SHA256은 `30a312b144383be64fc6fe35b8ad107ebba9a90672d9dda941f9ef8018279944`다. 이를 `tests/mvp/fixtures/legacy_boulder_controller.gd`에 보존했고 전역 클래스명만 `LegacyBoulderController`로 바꿨다. 그 외 바이트는 동일하다. 미구매 상태의 신규 컨트롤러를 이 독립 원본과 비교한다.

## 기준 실행 결과

동시 구현의 영향을 피하려고 기준 커밋을 `.tools/mvp-baseline`에 격리한 뒤 Godot 4.5.1로 실행했다. 기존 테스트가 사용하는 저장 fixture도 해당 격리 프로젝트의 고유 `.tools/progression-*`, `.tools/web-compat-*` 경로이며 실제 저장은 사용하지 않았다.

| 검사 | 통과 |
|---|---:|
| physics_balance_verification | 115 |
| stamina_brace_verification | 124 |
| progression_verification | 50 |
| web_compatibility_tests | 24 |
| v02_verification --quick | 23 |
| balance/verify_harness | 43 |
| adjustment_v02/verify_instrumentation | 21 |
| 합계 | 400 |

각 최종 실행은 exit 0, 실패 0이었다. 검사 목록·명령·로그 SHA와 원시 로그는 [baseline.json](../../tests/mvp/results/baseline.json) 및 `tests/mvp/results/baseline-logs/`에 보존했다.

준비 중 두 문제도 숨기지 않고 기록했다. 첫 fresh editor import는 실험 결과 CSV를 번역으로 가져오며 `optimized_translation.cpp:136` 오류를 낸 후 종료코드 3221226356으로 실패했다. 결과/문서 디렉터리에 import 제외용 `.gdignore` 메타데이터를 적용한 격리 재실행은 exit 0으로 끝났다. 또한 git archive의 CRLF 변환 때문에 원본 SHA를 엄격히 검사하는 계측 검사가 처음 거부했다. 줄바꿈만 다른 것을 확인한 뒤 격리 컨트롤러를 기준 git blob의 정확한 LF 바이트로 복원하여 21개 검사를 통과했다. 원래 실패 로그도 남겼고 작업 중 production 컨트롤러는 건드리지 않았다.

## 다음 검증의 범위

400개는 구현 이전 기준이다. 새 EXP 지갑·마일스톤 일시정지·35개 슬롯·저장 이관·조건부 능력·프레스티지 트랜잭션·브라우저 화면은 각 구현 이후 별도로 검증한다. 기존 무강화 물리 일치, 30/144FPS, Slip/Runaway, 원본 저장 보존, 원본 PNG SHA를 독립 확인해야 한다. S190은 테스트 전용이며 기존의 무강화 상한을 성장한 새 회복 능력에 확대 적용하지 않는다.
