# 숙련·메인화면·프레스티지 MVP 검증 기록

이 문서는 실제 실행한 검사와 검증 범위의 한계를 분리한다. 구현 브랜치는 `codex/mastery-prestige-mvp`이며, 아래 범위의 MVP 코드·자동 검사·로컬 Chromium 브라우저 증거를 독립 검토했다. 정식 사이트 배포 승인이나 모든 브라우저·기기의 호환성 보증은 아니다.

최종 회귀는 **1,463개 통과**, 이전 원본 SHA 계측은 **예상한 거부 1건**이다. 실행 전후 소스가 같고 현재 파일·개별 로그의 SHA도 기록과 일치한다. `main.tscn`과 지형 `.tres`도 소스 보존 범위에 포함한다. [최종 회귀](../../tests/mvp/results/final-regression.json)의 1,463개는 기존 379 + 성장 113 + 프로필 저장 109 + 물리 155 + 저장 계약 167 + UI 265 + 씬 통합 242 + 저장 실패 18 + S190 재생·환경 15이며, 구현 전 400개와 중복 합산하지 않는다.

## 기준과 물리 회귀

구현 전 `d4ba73b`를 격리해 기존 400개 검사를 통과했다. 현재 변경된 물리에는 기존 379개와 신규 능력 155개를 별도로 실행해 모두 통과했다. 기존 v0.2 계측 21개는 원본 컨트롤러 SHA를 엄격히 요구하여 변경된 소스를 의도대로 거부했다. 따라서 **현재 400개가 통과했다고 합산하지 않는다.** 원본을 보존한 독립 fixture와의 중립 물리 비교가 새로운 확장 지점의 검증을 담당한다.

| 범위 | 결과 | 근거 |
|---|---:|---|
| 구현 전 격리 기준 | 400/400 | [baseline.json](../../tests/mvp/results/baseline.json) |
| 현재 기존 회귀 | 379/379 | [phase-b-independent.json](../../tests/mvp/results/phase-b-independent.json) |
| 신규 능력·중립 물리 | 155/155 | 같은 독립 검증 JSON 및 `phase-b-logs/mastery_physics.txt` |
| 이전 원본 SHA 계측 | 예상한 소스 변경 거부 | `phase-b-logs/instrumentation.txt`; 통과 검사에 포함하지 않음 |

379개는 physics 115, stamina/brace 124, 기존 progression 50, web 호환 24, 지형 v0.2 quick 23, balance harness 43이다. 원래 `Progression`은 기존 게임과 보존 실험을 위해 남아 있으며 MVP에서는 별도 EXP 지갑을 사용한다. 신규 155개에는 미구매 상태와 보존 컨트롤러의 비교, 30/144FPS, Slip/Runaway 경계, STR10·BRE07·BRE10와 특별 능력의 조건·저장 상태 검사가 있다. 이 검사들은 고정 입력 자동 검사이며 인간 조작 평가가 아니다.

원본 소스는 `tests/mvp/fixtures/legacy_boulder_controller.gd`에 클래스명만 바꾸어 보존했다. Phase A에서 발견한 CSV 번역 import 오류와 CRLF 해시 거부, 각각의 해결·재시도 기록도 지우지 않았다. 상세는 [Phase A](phase-a.md)에 있다.

## 성장 데이터와 저장 계약

| 범위 | 독립 재실행 | 실제 검증 내용 |
|---|---:|---|
| 성장 프로필 | 113/113 | 35개 ID, 단계별 자격, 순차 구매, EXP 부족·중복 차단, 30개 일반 구매와 효과 재계산 |
| 프로필 저장·프레스티지 | 109/109 | JSON 복원, 잘못된 상태의 원자 거부, 회차 token 기반 중복 commit 차단, 말쿠트 ×5 |
| 전체 저장 payload 계약 | 167/167 | world/run/능력 타입·범위, 프로필 능력 요약 일치, 마일스톤 10노드, 프레스티지 phase와 token 관계 |

근거: [프로필 리뷰](../../tests/mvp/results/mastery-profile-review.json), [저장 계약 리뷰](../../tests/mvp/results/save-contract-review.json), 해당 독립 로그. 이 단위 검증만으로 브라우저 IndexedDB/localStorage의 내구성이나 화면 전환을 검증했다고 주장하지 않는다.

기존 정식 저장은 `user://sisyphus-v1.json`, MVP는 `user://sisyphus-mvp-v1.json`과 별도의 브라우저 key를 사용한다. 정식 저장의 기존 level/rank/XP를 자동 구매 노드로 변환하지 않는다. 최고 기록 가져오기는 사용자 확인과 백업 성공을 거쳐 별도로 검증해야 한다.

## 실제 씬 통합과 저장 실패

`tests/mvp/test_mvp_integration.gd`는 실제 MVP 씬을 생성하고 고유 `user://mvp-integration-*` 저장만 사용한다. 첫 해금 중 물리·Slip timer 정지와 구매, 불안전한 위치 구매 차단, 자연 Runaway 이후 일반 재도전, 프레스티지 각 phase의 파일 저장·재생성, commit 경계 재실행을 다룬다. 정상 도달 자체는 수동 도착 fixture이며, 해당 테스트를 1,000m 자연 완주 검사로 부르지 않는다.

최종 씬 통합 242개를 별도의 새 저장 이름으로 독립 실행하여 통과했다. 실제 메뉴의 `continue` dispatch와 프레스티지 presentation 복구, SPC01의 다음 50m 범위·노면·돌턱 경계, SPC03의 60 임계값도 포함한다. 실행 당시 `mastery_main.gd` SHA는 `05230b64e863bb424c10dcd15e7056dc8d28aea94297e718a101101e6720d73d`이며 [독립 로그](../../tests/mvp/results/integration-final-independent.txt)에 결과를 보존했다.

추가로 실제 native 파일 쓰기에 `ERR_CANT_CREATE`를 주입한 18개 검사가 통과했다. 50m 보상 저장 실패 시 같은 렌더링 frame의 다음 120Hz 스텝을 실행하지 않고, 이전 파일을 보존하며, 저장 재시도에도 XP를 중복 지급하지 않는다. 프레스티지 commit 쓰기 실패 후에도 메모리 보상은 한 번이고 재시도 후 영구 보상도 한 번이다. 근거: [storage-faults.json](../../tests/mvp/results/storage-faults.json). 정상 도착은 fixture이며 브라우저 저장 용량 오류를 실제로 발생시킨 시험은 아니다.

## UI와 에셋

최종 UI 컴포넌트 자동 검사 기록은 265개 통과다. 1920×1080·1280×720·960×540의 Control 경계와 데이터 연결 등을 확인한 결과이며, 실제 렌더링·브라우저 시각 검수와 구분한다. 근거: [ui-components.json](../../tests/mvp/results/ui-components.json).

MainMenu 원본 CSV 27개 항목과 대응 파일, 세피로트 PNG 19개를 확인했다. 숙련 전용 제작 CSV는 없어서 재사용 노드와 명시적 fallback 매핑을 사용한다. 원본 PNG를 수정하지 않는 원칙과 최종 사용 목록은 [에셋 감사](asset-audit.json), [사용 목록](assets-used.csv)을 따른다. 현재 SVG/PNG 제공 여부가 10~12개 캐릭터 분리 rig의 완성을 뜻하지는 않는다.

특별 5개 flag는 효과·UI 자동 검사 후 모두 활성화했다. SPC02/04/05의 조건부 효과는 물리 검사, SPC01/03의 범위·임계값은 씬 통합 검사에 포함된다. 최종 flag 상태로 성장 113개와 프로필 저장 109개를 독립 재실행하여 통과했다. 화면에서의 시각적 전달과 조작성 평가는 자동 슬롯 검사와 별도다.

## S190 테스트 전용 비교

새 능력의 S190 비교는 기존 배포 산에 적용하지 않은 별도 harness다. 같은 clear 날씨·generation6·시드101/202/303과 두 별도 회복 대응 정책을 사용했다. 관문 750m 진입 fixture 36회, 0m에서 시작한 고정 성장 전체 경로 36회, 호흡 계열 제거 대조 6회를 실행했다.

- 주 실험 72회와 추가 대조 6회의 원시 입력 SHA·step 수를 확인했다.
- 대표 4개 원시 입력을 처음부터 재생해 물리·능력·환경 ledger가 일치했다. 환경 부분 quota·입력 유지·재진입 검사를 포함해 15개가 통과했다.
- 30노드 완성 빌드는 두 정책 모두 진입 fixture 3/3, 전체 경로 3/3 성공했다.
- 18노드 중 근력 집중·숙련 회복 대응의 전체 경로에서만 1/3 성공했고 나머지 중간 빌드 셀은 0/3이었다. 이것은 유한 정책의 실패이며 특정 노드 필수성 증명이 아니다.
- 근력10·지구력10을 고정하고 호흡 계열을 제거하면 6/6→5/6 성공이었다. 양쪽 성공한 5쌍은 호흡 제거 후 1.27~4.16초 느렸다. 투자도 3,840→2,560EXP로 감소하므로 동일 예산 최적화 비교가 아니다.

고정 빌드는 실제 EXP 지급·구매 API로 만들었지만 준비용 거리 지급은 인공 fixture다. 실제 XP 캠페인, 인간 시간, 폭넓은 시드 안정성을 검증한 결과가 아니다. 18노드끼리도 균형은 1,200EXP, 집중 구성은 1,660EXP다. 새 호흡 회복·구제를 이전 무강화 자원 상한에 넣지 않았으며 기존 증명을 성장 빌드에 재사용하지 않는다. 환경 quota는 일반 controller snapshot에 저장되지 않으므로 이 실험의 중간 관문 checkpoint 복원도 주장하지 않는다.

근거: [S190 요약](../../tests/mvp/results/s190/summary.md), [실행 manifest](../../tests/mvp/results/s190/manifest.json), [호흡 대조](../../tests/mvp/results/s190-breath-ablation/summary.json). 물리 구현자와 별도 검증자가 테스트 코드와 해석을 교차 검토했다.

## 로컬 브라우저와 export

별도 실행자가 Godot 4.5.1 debug Web을 로컬 Chromium에서 조작한 [브라우저 기록](../../tests/mvp/results/browser/README.md)과 [manifest](../../tests/mvp/results/browser/manifest.json)를 검토했다. 메인 화면·새 게임, D/Shift/Space로 약 8m 이동, Esc 저장과 실제 reload 후 이어하기, 인공 250m 저장의 해금 화면과 STR01 구매(150→120 EXP), 구매 후 reload, 음소거 설정 저장을 확인했다. 독립 검토자는 manifest의 모든 파일 SHA와 960 일반 창·실제 디스플레이 전체 화면 이미지를 대조했다.

인공 `PRESTIGE_COMMIT` 저장을 이어 연출 중 실제 reload하고 다시 이어하기로 새 회차에 진입했다. 완료 후 한 번 더 reload한 [저장 요약](../../tests/mvp/results/browser/save-after-reloads.json)은 거리 0, EXP 0, 구매 0, 프레스티지 1, 실 1, 말쿠트 활성, 음소거 설정 유지를 기록한다. 이는 실제 브라우저의 저장 전환 검사이며 정상까지 인간이 완주한 증거는 아니다. 모든 연출 phase의 중단 경계와 반복 프레스티지는 별도 native 통합 검사가 담당한다. 마지막 게임 페이지에서 수집된 console error/warn은 0건이다.

1920×1080·960×540 일반 창과 실제 1920×1080 디스플레이의 전체 화면은 확인했다. MVP 전용 셸의 resize/CSS 수정 후 증거다. **960×540 viewport 에뮬레이션과 OS 전체 화면의 동시 조합에서는 사분면 렌더링이 남았으며 성공으로 세지 않았다.** 도구 또는 게임 중 어느 쪽 원인인지 확정하지 않았고, 실제 저해상도 디스플레이의 전체 화면은 미검증이다. 960 일반 창은 세로 스크롤을 사용한다.

[깨끗한 export](../../tests/mvp/results/clean-export.json)는 커밋 `e94e1d5` archive와 최종 MVP 셸 수정만을 별도 폴더에 넣어 import/export를 실행했다. 두 명령 exit 0, 오류 로그 0이며, 소스 폴더를 참조할 수 없는 빈 디렉터리에서 export된 PCK의 리소스·기본 MVP 진입·UI 구성 **32개**가 통과했다. 테스트 스크립트 없는 기본 진입도 오류 없이 실행했다. 이 32개는 회귀 1,463개와 별도이며 native headless PCK 검사 자체를 브라우저 렌더링 검사로 부르지 않는다. `build_web.py --qa`도 전체 실행을 마쳤다. [도구 실행 결과](../../tests/mvp/results/build-helper.json)에 exit 0, 예상하지 않은 오류 0건, 라이선스 3개 복사 성공을 기록했다. 이 실행은 로컬 export이며 배포하지 않았다.

원본 PNG 173개는 바이트가 같으며 기존 `main.tscn`, `main.gd`, 산 생성 코드, 정식 Web 셸과 배포 workflow는 줄바꿈 정규화 후 기준 커밋과 같다. [보존 결과](../../tests/mvp/results/original-preservation.json)를 따른다. MVP는 별도 feature의 진입 씬·export preset·저장 이름을 사용한다. 정식 사이트에는 배포하지 않았다.

## 검증하지 않은 범위

- Safari·Firefox·모바일, 실제 저해상도 전체 화면과 위 viewport 에뮬레이션 동시 조합의 원인 규명.
- 브라우저 저장 용량 부족, OS 전원 손실, 모든 브라우저 종료 타이밍의 내구성.
- 실제 사용자 정식 저장을 이용한 최고 기록 가져오기·백업 실패의 전체 UI 경로.
- 인간의 자연 완주 시간·난이도와 대규모 시드 균형. S190의 준비된 성장 실험을 실제 성장 캠페인으로 확대 해석하지 않는다.

독립 검토 범위에서 출판을 막는 새 코드 결함은 발견하지 않았다. 위 미검증 항목과 관측된 화면 조합의 한계를 공개한 상태로 MVP 구현 및 검증 기록을 제공할 수 있다.
