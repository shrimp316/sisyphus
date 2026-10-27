# 숙련의 석판 v1.2 — 별도 승인이 필요한 실제 통합

이번 구현은 `godot/scenes/mastery/mastery_preview.tscn`으로 실행하는 독립 프리뷰다. 게임의 메인 씬, 물리, EXP, 구매, 저장, 기존 Web preset은 교체하지 않는다. 프리뷰의 진행 정보는 새로운 메모리 객체이며 저장 파일을 읽거나 쓰지 않는다.

## 현재 모델과 UI의 차이

| 항목 | 현재 게임 | 이번 프리뷰 / 통합 전 결정 |
|---|---|---|
| 계열 | strength / endurance / recovery | strength / endurance / breath를 표시하며 breath는 recovery에 대응 |
| 일반 성장 | 각 10랭크, 총 30강화점 | 노드 30개가 랭크 순서를 표현; 독립적인 새 능력 30개를 만들지 않음 |
| 재화 | `total_xp` 누적 경험치, `pending_points()` 미사용 강화점 | EXP 차감 없음; 기존 모델의 `choose(kind)`를 별도 메모리 객체에만 호출 |
| 실제 구매 | `main.choose_upgrade(kind)`가 저장 차단·게임 화면·일시정지·안전한 쉼터를 검사 | live 연결 없음. 이후 UI는 이 진입점만 호출해야 하며 `progression.choose()`를 우회 호출하면 안 됨 |
| 첫 도달 | 저장된 best/기록 정보 | mock의 최초 도달 flags는 회차 거리 감소와 독립. 실제 기존 저장 이력에서 복구할 규칙 검토 필요 |
| 특별 노드 | 기존 Progression에는 특별 랭크 없음 | 5개 플레이스홀더. 첫 정상 회차는 기록만, 다음 회차는 자격만 표시. 비용·효과·구매 미구현 |
| 정상 회차 | 현재 저장 포맷에 해당 전용 필드 없음 | `first_summit_run_number`는 mock 메모리 전용. 저장 필드 추가하지 않음 |
| 프레스티지 | 이번 작업 범위 밖 | 프리뷰의 purchased reset만 제공. 영구 자격 유지 여부를 시연하며 실제 프레스티지로 보고하지 않음 |
| 2~4막 | 이번 자료에 능력/비용/게이트 미정 | 비문 원문 보존, 페이지당 35슬롯 스키마만 준비. 140개 완성 UI 또는 실제 성장으로 보고하지 않음 |

## 통합 승인이 필요한 변경

1. 메인 메뉴에서 프리뷰를 정식 석판으로 여는 경로 및 기존 `_draw_upgrade_choice()`와의 상호 배제. 화면 표시 동안 `main._input()`/물리 입력 전달을 별도로 제어해야 한다. Control의 이벤트 소비만으로 기존 `_input()`까지 차단된다고 보장할 수 없다.
2. live 어댑터의 조회 전용 스냅샷과 `main.choose_upgrade(kind)` 호출 연결. 안전한 쉼터 밖에서는 정보 조회만 할지, 돌아가서 강화하도록 안내할지 UX 결정이 필요하다.
3. 영구 해금 이력 및 첫 정상 회차를 저장할 데이터 계약. 상위 저장 version 4, progression snapshot version 1, `user://sisyphus-v1.json`, 브라우저 미러를 유지한 마이그레이션 설계와 별도 검증이 선행되어야 한다.
4. 특별 5개의 문자·효과·비용 및 구매 시점. 현재 자격 표시와 실제 구매를 구분하며, 구형 extensionText를 특별 노드에 사용하지 않는다.
5. 프레스티지 시 실제 구매/랭크 초기화와 영구 해금 보존 범위, 기존 다른 MVP 성장 구현과의 관계.
6. 2~4막의 실제 위치·조건·효과 데이터 승인. 공통 씬은 재사용하되 미정값을 1막 규칙으로 복제하지 않는다.

현재 자료 및 코드 검증으로 해결할 수 있는 독립 프리뷰 작업은 진행했고, 위 항목은 게임 동작/경제/저장 변경이므로 요청된 승인 경계에 따라 적용하지 않는다.

## 엔진 동작 참고

입력·포커스·장식 레이어의 mouse filter는 [Godot 4.5 Control 문서](https://docs.godotengine.org/en/4.5/classes/class_control.html)를 기준으로 확인했다. 독립 Web 빌드는 [Godot 4.5 Web export 문서](https://docs.godotengine.org/en/4.5/tutorials/export/exporting_for_web.html)의 Compatibility/WebGL 2 및 단일 스레드 구성을 사용한다. SubViewport 캡처는 [공식 문서](https://docs.godotengine.org/en/4.5/classes/class_subviewport.html)의 오프스크린 렌더이며, OS 창 조작 검증과 구분한다.
