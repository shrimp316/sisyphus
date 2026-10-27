# 숙련·메인화면·프레스티지 MVP

기존 산과 배포 진입점을 보존하면서 EXP 직접 소비, 숙련 35노드, 첫 거리 해금 안내, 메인 메뉴, 최초·반복 프레스티지와 말쿠트 ×5를 연결했다. 새 성장 수치는 `data/mastery/`에 있고 효과는 공통 계산 계층과 `MasteryBoulder`에서 적용한다. 미구매 상태의 기존 물리 일치를 별도로 검사한다.

## 실행

Godot 4.5.1에서 `scenes/mvp/main_mvp.tscn`을 실행한다. CLI에서는 아래처럼 지정한다.

```powershell
godot --path . --scene res://scenes/mvp/main_mvp.tscn
python tests/mvp/build_web.py --godot .tools/godot/Godot_v4.5.1-stable_win64_console.exe
python -m http.server 8766 --bind 127.0.0.1 --directory builds/mvp-web
```

`MVP Web`의 `mastery_mvp` 기능 태그만 새 진입점을 선택한다. 기본 `main.tscn`, 기존 `Web`·`Windows Playtest` 프리셋과 정식 배포 workflow는 유지한다. 내보내기 템플릿 경로는 로컬 `.tools/export-templates/`를 가리키므로 다른 환경에서는 공식 4.5.1 템플릿 경로를 설정한다. JSON 외부 설정은 프리셋 include filter에 포함한다. 이 작업은 원격 배포를 수행하지 않는다.

D/→ 밀기, Shift 힘주기, Space 버티기, Tab 석판, Esc 메뉴, M 음소거, F11 전체 화면이다. 250/500/750m 첫 해금에서는 물리 시간을 멈추고 구매할 수 있다. 안내를 닫으면 같은 물리 상태에서 재개하며 이후 구매는 정지한 쉼터에서만 가능하다. 석판 조회는 메인 메뉴에서도 가능하다.

## 구현과 자료

- `scripts/mastery_progression.gd`: 지갑·구매·자격·프레스티지 프로필.
- `scripts/mastery_effects.gd`, `mastery_boulder.gd`: 수치 및 조건부·회차 능력.
- `scripts/mvp/mastery_main.gd`, `save_contract.gd`: 실제 게임 연결·일시정지·저장·연출 단계.
- `scenes/mvp/main_menu.tscn`, `mastery_board.tscn`, `mastery_node.tscn`: 데이터 기반 UI.
- [35노드 슬롯](mastery-slots.csv), [사용 에셋](assets-used.csv), [누락·미사용](assets-unused.md).
- [저장·이전 규칙](save-format.md), [검증 결과와 제한](verification.md).
- [S190 비교](../../tests/mvp/results/s190/summary.md): 테스트 전용, 기본 게임에 적용하지 않음.

숙련 전용 원본 CSV 3종이 없으므로 기존 공용 PNG와 재사용 컴포넌트로 매핑했다. 원본 PNG는 변경하지 않았다. 다른 막, 말쿠트 외 세피라 구매, 캐릭터 분리 rig 신규 제작은 구현 범위에 포함하지 않는다. S190 소수 시드 결과를 인간 플레이 시간이나 120~180분 캠페인 달성으로 해석하지 않는다.

## 자동 검사와 브라우저 QA

`tests/mvp/run_checks.py`로 기존 회귀와 신규 검사를 실행한다. 브라우저 QA 인공 저장은 `tests/mvp/create_web_fixtures.gd`로 생성하고 `tests/mvp/fixtures/web/README.md`를 따른다. `web_qa.html`은 로컬 테스트 helper이며 게임 프리셋에 포함되지 않는다. 인공 정상 도달 fixture로 저장 전환을 검사한 결과와 실제 입력을 재생한 물리 테스트는 구분한다.
