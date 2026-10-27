# MVP 에셋 사용·누락 범위

메인화면·석판 컴포넌트의 `data/ui/mvp_assets.json` 카탈로그를 기준으로 확인했다. 다른 게임 화면에서의 사용 여부는 이 목록의 범위에 포함하지 않는다. 원본 PNG는 수정·삭제·이름 변경하지 않았다.

- 메인 CSV: `assets/MainMenu/Data/sisyphus_main_asset_inventory_v1.csv` (27행). CSV의 작업 상태 문자열은 파일 존재 여부와 구분한다.
- 카탈로그: 20개 텍스처 경로; 실제 누락 0개.
- 메인 PNG: 32개 중 18개 사용, 14개 이 카탈로그에서 미사용.
- 세피로트 PNG: 19개 중 2개 공용 노드 표시로 사용, 17개 이 카탈로그에서 미사용.

## 누락된 석판 원본 매핑

다음 명세상 권장 CSV 3개는 프로젝트에서 발견되지 않았다. 기존 CSV를 만들어낸 것으로 표시하지 않는다.

- `mastery_asset_mapping_v11.csv`
- `mastery_node_layout_v11.csv`
- `mastery_asset_requests_v11.csv`

대신 `mastery-slots.csv`는 실제 코드의 35개 노드 ID·좌표·선행 관계를 문서화한 **구현 매핑**이다. 원본 디자인 CSV의 복원본이 아니다. 석판 전용 개별 아이콘/프레임 대신 기존 `node_branch_available.png`와 `node_core_completed.png`를 재사용하며, 구매 상태는 텍스트·색·테두리로 표시한다. 특별 노드의 공용 텍스처 파일명이 completed여도 실제 구매 여부를 의미하지 않는다.

## 사용한 카탈로그 경로

- `sky` → `res://assets/MainMenu/Background/main_bg_sky.png`
- `far` → `res://assets/MainMenu/Background/main_bg_mountains_far.png`
- `mid` → `res://assets/MainMenu/Background/main_bg_mountains_mid.png`
- `ruins` → `res://assets/MainMenu/Background/main_bg_ruins.png`
- `slope` → `res://assets/MainMenu/Background/main_bg_slope.png`
- `foreground` → `res://assets/MainMenu/Background/main_bg_foreground.png`
- `boulder` → `res://assets/MainMenu/Character/main_boulder.png`
- `boulder_shadow` → `res://assets/MainMenu/Character/main_boulder_shadow.png`
- `sisyphus` → `res://assets/MainMenu/Character/main_sisyphus_rig.png`
- `progress_panel` → `res://assets/MainMenu/UI/main_panel_progress.png`
- `primary_base` → `res://assets/MainMenu/UI/main_btn_primary_base.png`
- `primary_hover` → `res://assets/MainMenu/UI/main_btn_primary_hover.png`
- `primary_pressed` → `res://assets/MainMenu/UI/main_btn_primary_pressed.png`
- `primary_disabled` → `res://assets/MainMenu/UI/main_btn_primary_disabled.png`
- `secondary_base` → `res://assets/MainMenu/UI/main_btn_secondary_base.png`
- `secondary_hover` → `res://assets/MainMenu/UI/main_btn_secondary_hover.png`
- `secondary_pressed` → `res://assets/MainMenu/UI/main_btn_secondary_pressed.png`
- `secondary_disabled` → `res://assets/MainMenu/UI/main_btn_secondary_disabled.png`
- `node_branch` → `res://assets/ui/sephirot/node_branch_available.png`
- `node_core` → `res://assets/ui/sephirot/node_core_completed.png`

## 메인 CSV 파일 대응

누락 없음. 확장자 없는 `CH-01: main_sisyphus_rig`는 실제 `main_sisyphus_rig.png`와 `.json` 묶음으로 대응한다. 메타데이터의 단일 스프라이트 대체 구현이며 분리 파츠 리깅 완성을 의미하지 않는다. wildcard 상태 파일도 실제 대응 파일로 확인했다.

## 메인 PNG 미사용 목록

- `assets/MainMenu/Background/main_bg_fog_strip.png`
- `assets/MainMenu/Character/main_foot_contact_shadow.png`
- `assets/MainMenu/FX/main_dust_atlas.png`
- `assets/MainMenu/FX/main_godray_soft.png`
- `assets/MainMenu/FX/main_grain_tile.png`
- `assets/MainMenu/FX/main_transition_mask.png`
- `assets/MainMenu/Preview/main_asset_board_reference.png`
- `assets/MainMenu/Preview/main_preview_art_reference.png`
- `assets/MainMenu/UI/main_act_emblem_locked.png`
- `assets/MainMenu/UI/main_act_emblem_open.png`
- `assets/MainMenu/UI/main_act_emblem_selected.png`
- `assets/MainMenu/UI/main_logo_sisyphus.png`
- `assets/MainMenu/UI/main_modal_frame.png`
- `assets/MainMenu/UI/main_notification_marker.png`

## 세피로트 PNG 미사용 목록

- `assets/ui/sephirot/bottom_bar.png`
- `assets/ui/sephirot/btn_back.png`
- `assets/ui/sephirot/btn_back_disabled.png`
- `assets/ui/sephirot/btn_back_hover.png`
- `assets/ui/sephirot/fx_particles.png`
- `assets/ui/sephirot/fx_point_light.png`
- `assets/ui/sephirot/fx_select.png`
- `assets/ui/sephirot/fx_thread_light.png`
- `assets/ui/sephirot/node_branch_completed.png`
- `assets/ui/sephirot/node_branch_seal.png`
- `assets/ui/sephirot/node_branch_unlocked.png`
- `assets/ui/sephirot/node_core_available.png`
- `assets/ui/sephirot/node_core_unlocked.png`
- `assets/ui/sephirot/thread_glow.png`
- `assets/ui/sephirot/thread_lock.png`
- `assets/ui/sephirot/thread_segment.png`
- `assets/ui/sephirot/top_bar.png`

## 그 밖의 원본 PNG

Phase A 감사 목록의 나머지 122개 PNG는 이 메인화면·석판 카탈로그에 추가하지 않았다. 기존 등반 화면에서 사용되는 자산까지 게임 전체에서 미사용이라고 판정한 목록은 아니다. 전체 경로·크기·원시 해시는 `asset-audit.csv`에 보존되어 있다.

- `UI design/메인 UI/sisyphus_main_ui_16x9.png`
- `assets/background/midground_ridge.png`
- `assets/background/sky_mountains.png`
- `assets/background/sky_summit.png`
- `assets/boulder/boulder_default.png`
- `assets/boulder/boulder_rough.png`
- `assets/boulder/boulder_snow.png`
- `assets/boulder/boulder_wet.png`
- `assets/character/sisyphus/brace/brace_01.png`
- `assets/character/sisyphus/brace/brace_02.png`
- `assets/character/sisyphus/brace/brace_03.png`
- `assets/character/sisyphus/brace/brace_04.png`
- `assets/character/sisyphus/brace/brace_05.png`
- `assets/character/sisyphus/brace/brace_06.png`
- `assets/character/sisyphus/exhausted/exhausted_01.png`
- `assets/character/sisyphus/exhausted/exhausted_02.png`
- `assets/character/sisyphus/exhausted/exhausted_03.png`
- `assets/character/sisyphus/exhausted/exhausted_04.png`
- `assets/character/sisyphus/exhausted/exhausted_05.png`
- `assets/character/sisyphus/exhausted/exhausted_06.png`
- `assets/character/sisyphus/heavy_push/heavy_push_01.png`
- `assets/character/sisyphus/heavy_push/heavy_push_02.png`
- `assets/character/sisyphus/heavy_push/heavy_push_03.png`
- `assets/character/sisyphus/heavy_push/heavy_push_04.png`
- `assets/character/sisyphus/heavy_push/heavy_push_05.png`
- `assets/character/sisyphus/heavy_push/heavy_push_06.png`
- `assets/character/sisyphus/idle/idle_01.png`
- `assets/character/sisyphus/idle/idle_02.png`
- `assets/character/sisyphus/idle/idle_03.png`
- `assets/character/sisyphus/idle/idle_04.png`
- `assets/character/sisyphus/idle/idle_05.png`
- `assets/character/sisyphus/idle/idle_06.png`
- `assets/character/sisyphus/push/push_01.png`
- `assets/character/sisyphus/push/push_02.png`
- `assets/character/sisyphus/push/push_03.png`
- `assets/character/sisyphus/push/push_04.png`
- `assets/character/sisyphus/push/push_05.png`
- `assets/character/sisyphus/push/push_06.png`
- `assets/character/sisyphus/push/push_07.png`
- `assets/character/sisyphus/push/push_08.png`
- `assets/character/sisyphus/spriteframes/sisyphus_brace_sheet.png`
- `assets/character/sisyphus/spriteframes/sisyphus_exhausted_sheet.png`
- `assets/character/sisyphus/spriteframes/sisyphus_heavy_push_sheet.png`
- `assets/character/sisyphus/spriteframes/sisyphus_idle_sheet.png`
- `assets/character/sisyphus/spriteframes/sisyphus_push_sheet.png`
- `assets/fx/breath/breath_01.png`
- `assets/fx/breath/breath_02.png`
- `assets/fx/breath/breath_03.png`
- `assets/fx/breath/breath_04.png`
- `assets/fx/breath/breath_05.png`
- `assets/fx/breath/breath_06.png`
- `assets/fx/breath/breath_sheet.png`
- `assets/fx/dust/dust_01.png`
- `assets/fx/dust/dust_02.png`
- `assets/fx/dust/dust_03.png`
- `assets/fx/dust/dust_04.png`
- `assets/fx/dust/dust_05.png`
- `assets/fx/dust/dust_06.png`
- `assets/fx/dust/dust_sheet.png`
- `assets/fx/gravel/gravel_01.png`
- `assets/fx/gravel/gravel_02.png`
- `assets/fx/gravel/gravel_03.png`
- `assets/fx/gravel/gravel_04.png`
- `assets/fx/gravel/gravel_05.png`
- `assets/fx/gravel/gravel_06.png`
- `assets/fx/gravel/gravel_sheet.png`
- `assets/fx/impact/impact_01.png`
- `assets/fx/impact/impact_02.png`
- `assets/fx/impact/impact_03.png`
- `assets/fx/impact/impact_04.png`
- `assets/fx/impact/impact_05.png`
- `assets/fx/impact/impact_06.png`
- `assets/fx/impact/impact_sheet.png`
- `assets/fx/snow/snow_01.png`
- `assets/fx/snow/snow_02.png`
- `assets/fx/snow/snow_03.png`
- `assets/fx/snow/snow_04.png`
- `assets/fx/snow/snow_05.png`
- `assets/fx/snow/snow_06.png`
- `assets/fx/snow/snow_sheet.png`
- `assets/fx/wind/wind_01.png`
- `assets/fx/wind/wind_02.png`
- `assets/fx/wind/wind_03.png`
- `assets/fx/wind/wind_04.png`
- `assets/fx/wind/wind_05.png`
- `assets/fx/wind/wind_06.png`
- `assets/fx/wind/wind_sheet.png`
- `assets/props/broken_signpost.png`
- `assets/props/cairn_checkpoint.png`
- `assets/props/dead_tree.png`
- `assets/props/ruin_pillar.png`
- `assets/props/shrine_fragment.png`
- `assets/props/simple_arch_ruin.png`
- `assets/props/small_tree.png`
- `assets/terrain/concave_slope_down.png`
- `assets/terrain/convex_slope_up.png`
- `assets/terrain/foothold_rest_platform.png`
- `assets/terrain/gravel_ground.png`
- `assets/terrain/ledge.png`
- `assets/terrain/mud_ground.png`
- `assets/terrain/rock_ground.png`
- `assets/terrain/rock_subsurface.png`
- `assets/terrain/small_stone_step.png`
- `assets/terrain/snow_ground.png`
- `assets/terrain/steep_slope_up.png`
- `assets/terrain/wet_rock.png`
- `assets/ui/icons/brace_icon.png`
- `assets/ui/icons/checkpoint_icon.png`
- `assets/ui/icons/height_marker_icon.png`
- `assets/ui/icons/push_burst_icon.png`
- `assets/ui/icons/slip_icon.png`
- `assets/ui/icons/stamina_icon.png`
- `assets/ui/icons/warning_rockfall_icon.png`
- `assets/ui/icons/warning_wind_icon.png`
- `assets/ui/markers/event_marker.png`
- `assets/ui/markers/previous_record_marker.png`
- `assets/ui/markers/rest_point_marker.png`
- `docs/references/character-reference.png`
- `docs/references/concept-reference.png`
- `docs/references/environment-reference.png`
- `docs/references/fx-ui-reference.png`
- `tests/balance/results/current-pilot/baseline.png`

## 검증 범위

UI 자동 검사는 35개 ID 연결, 27개 선행 연결선의 레이어 순서, 입력 투과, 실제 SubViewport 크기 변경에 따른 1920×1080·1280×720·960×540 배치를 검사한다. 브라우저에서의 최종 시각 검수와 클릭 흐름은 별도 통합 검증 대상이다.

## 재현 명령

```powershell
& .tools/godot/Godot_v4.5.1-stable_win64_console.exe --headless --path . --script tests/mvp/test_mvp_ui.gd
& .tools/godot/Godot_v4.5.1-stable_win64_console.exe --path . --rendering-method gl_compatibility --script tests/mvp/test_mastery_connections_render.gd
```

첫 검사는 265개 구성·데이터·레이아웃·펄스 항목을 통과했다. 두 번째는 실제 렌더러가 필요하며 headless 실행은 거부한다. 1920×1080 렌더의 STR01–STR02 사이 픽셀(267,259)이 연결선 금색과 일치했고 27개 연결선이 생성됐다. `tests/mvp/results/mastery-board-render.png`와 `mastery-connections-render.json`에 증거를 기록했다. 이는 Windows GL 렌더 검증이며 브라우저 클릭 흐름 전체의 대체 검증은 아니다.
