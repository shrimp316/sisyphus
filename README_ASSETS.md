# SISYPHUS 테스트용 아트 팩

첨부 레퍼런스의 반실사 페인터리 방향을 바탕으로 built-in `image_gen`에서 새 이미지를 제작했다. 레퍼런스 보드를 게임 텍스처로 사용하지 않는다. 생성 이미지의 알파를 보존한 채 프레임 분리·크기 조정·투명 여백 배치만 수행했다. 원본 생성 프롬프트는 `docs/image-prompts-*.json`에 있다.

## 폴더 구조와 산출물

```text
assets/
  character/sisyphus/
    idle/ push/ heavy_push/ brace/ exhausted/  # 개별 512×512 PNG 32장
    spriteframes/                            # 애니메이션별 시트 5장
  boulder/                                   # 384×384, 돌 4종
  terrain/                                   # 512×256 지형 11종 + 1024×1024 지하 암반
  background/                                # 2048×1024 원경 2종 + 투명 중경 1종
  props/                                     # 384×384, 소품 7종
  fx/dust/ gravel/ impact/ wind/ breath/ snow/ # 256×256 프레임 36장 + 시트 6장
  ui/icons/                                  # 128×128 아이콘 8종
  ui/markers/                                # 256×256 월드 마커 3종
  metadata/                                  # 기준점·FPS·배치 정보·파일 목록
godot/
  resources/spriteframes/                     # 통합 2개 + 개별 11개 .tres
  scenes/preview/                             # character / fx / ui / environment
scripts/asset_visuals.gd                      # 게임의 텍스처·애니메이션 연결
scripts/scenery_visuals.gd                    # 배경과 지면 아래 암반 렌더링
scripts/asset_preview.gd                      # 독립 프리뷰
```

필수 아트는 개별 PNG 105장과 시트 11장, 총 116장이다. 기존 폰트 등은 이 수량에서 제외한다. 정확한 경로·크기·SHA-256은 `assets/metadata/asset_manifest.json`을 참고한다. 원경 2장과 지하 암반 1장은 빈 공간을 채우는 완전 불투명 RGBA 이미지이며, 나머지 에셋은 투명 배경을 유지한다.

## 캐릭터 애니메이션

| 모션 | 프레임 | FPS | 게임 상태 |
|---|---:|---:|---|
| idle | 6 | 6 | 여유 있는 대기 |
| push | 8 | 8 | 일반 밀기 |
| heavy_push | 6 | 8 | 힘주어 밀기 / exert |
| brace | 6 | 8 | 버티기 / 미끄러짐 |
| exhausted | 6 | 6 | 체력이 낮은 휴식 |

모두 오른쪽을 바라보며 반복 재생한다. 캔버스는 512×512, 기준점은 **(256, 464)**, 발바닥 기준선은 **y=464**다. 애니메이션별 한 가지 배율을 적용하여 프레임마다 임의로 체형을 늘리지 않았다. 일반/강한 밀기는 손의 오른쪽 끝도 정렬했다. 자세에 따라 보이는 몸 높이는 달라진다.

2026-10-26: 게임 안의 밀기·힘주기·버티기는 돌의 실제 이동 거리 **2m당 좌우 발 한 주기**로 재생한다. 정지하면 발 자세를 유지하고, 동작을 바꾸어도 주기가 이어진다. 대기·탈진 호흡과 독립 프리뷰는 시간 기준으로 재생하며 위 표의 FPS는 리소스·프리뷰 기본값이다. `tests/motion_sync_verification.gd`에서 속도 변화, 정지, 동작 전환, 일시정지와 저장 복원을 검사한다.

2026-10-12: 일반 밀기 8장과 강한 밀기 6장을 양발 교대 보행으로 교체했다. 가까운 다리와 먼 다리가 각각 뒤로 밀기 → 발 들기 → 앞으로 내딛기를 수행한다. `tests/asset_visual_verification.gd`는 전체 프레임 순서와 반복 복귀를 검사하며, `--capture`에서 게임 화면의 `game-push-01..08`과 `game-exert-01..06`을 저장한다. 실제 다리 교대는 전체 시트를 별도로 육안 검토한다.

`AnimatedSprite2D`에는 `godot/resources/spriteframes/sisyphus.tres`를 지정하고 `centered=false`, `offset=Vector2(-256,-464)`를 사용한다. 좌우 반전은 기준점이 유지되도록 노드의 `scale.x`를 반전한다. 게임 본체는 기존 CanvasItem 렌더링을 유지하면서 같은 SpriteFrames에서 현재 프레임을 읽는다.

## 지형·돌·소품

- 돌: default / rough / wet / snow. 중심 (192,192), 기준 반지름 176px. 게임에서는 43px 반지름에서 시작해 이번 회차의 최고 고도에 따라 최대 49.45px(+15%)까지 표시한다. 저장된 회차 최고점을 사용하므로 왕복 이동으로 중복 성장하지 않으며 다음 회차에 초기화된다. 외형만 바뀌고 물리는 유지한다. 회전은 기존 이동 거리 기준을 유지해 성장·재개 시 각도가 튀지 않도록 한다.
- 기본 지형: rock_ground / gravel_ground / mud_ground / wet_rock / snow_ground.
- 특수 지형: steep_slope_up / convex_slope_up / concave_slope_down / ledge / foothold_rest_platform / small_stone_step.
- 소품: cairn_checkpoint / broken_signpost / dead_tree / small_tree / ruin_pillar / shrine_fragment / simple_arch_ruin.

기본 지형의 보행면 기준은 y=64다. 실제 게임은 기존 경사선을 따라 텍스처를 변형해 그리므로 시각 교체 때문에 충돌 경로가 달라지지 않는다. 특수 모듈의 배치 기준·상단 윤곽은 `environment_assets.json`에 기록한다. `Sprite2D`/`Polygon2D`에서 사용할 수 있으며, 새로운 스테이지에 배치할 때는 별도 충돌 형상을 설계해야 한다. 소품은 하단 기준점 (192,352)을 쓴다. 돌탑/쉼터 그림 자체가 새 부활 체크포인트를 만들지는 않는다.

## 배경과 지면 아래 공간

| 파일 | 크기 | 배경 | 용도 |
|---|---|---|---|
| `assets/background/sky_mountains.png` | 2048×1024 | 불투명 | 낮은 고도의 하늘과 먼 산 |
| `assets/background/sky_summit.png` | 2048×1024 | 불투명 | 정상 부근의 하늘과 산악 원경 |
| `assets/background/midground_ridge.png` | 2048×1024 | 투명 | 원경과 플레이 지형 사이의 능선 |
| `assets/terrain/rock_subsurface.png` | 1024×1024 | 불투명 | 보행면 아래를 채우는 암반 질감 |

이 네 장은 화면 장식용이며 충돌 형상이나 저장된 산의 경사를 정의하지 않는다. 원경과 중경은 카메라에 따라 서로 다른 속도로 이동하고, 지하 암반은 기존 보행면 아래에만 그린다. 맑음·비와 고도에 따른 색조는 렌더러에서 처리한다.

`tests/scenery_verification.gd`는 에셋의 크기·불투명/투명 조건과 렌더링 전후 산·돌·난수 상태의 보존을 검사한다. `--capture`로 실행하면 시작점·175m·440m·800m·정상 부근의 맑음/비 화면, 축소·세로 화면, 에셋을 사용할 수 없을 때의 대체 렌더링까지 13장을 `.tools/scenery-captures/`에 저장한다. 대체 렌더링 검사는 메모리의 텍스처 캐시만 바꾸며 원본 PNG를 건드리지 않는다. 캡처는 지형 가장자리, 하단 빈 공간, 반복 경계 등을 육안 검토하는 자료다.

## FX와 UI

| FX | 프레임 | FPS | 기준점 | 재생 |
|---|---:|---:|---|---|
| dust | 6 | 10 | (128,224) | 이동 중 반복 |
| gravel | 6 | 12 | (128,224) | 미끄러짐 중 반복 |
| impact | 6 | 14 | (128,224) | 충돌 시 1회 |
| wind | 6 | 6 | (128,128) | 환경 반복 |
| breath | 6 | 6 | (128,128) | 호흡 반복 |
| snow | 6 | 8 | (128,224) | 프리뷰에서 반복 |

FX는 `AnimatedSprite2D`와 `fx.tres`, UI는 `TextureRect` 또는 `Sprite2D`에 연결한다. 아이콘은 stamina / slip / brace / push_burst / checkpoint / height_marker / warning_wind / warning_rockfall 8종이다. 월드 마커는 previous_record / event / rest_point 3종이며 배치 기준은 `ui_assets.json`에 있다.

## Godot 프리뷰

Godot 4.5.1에서 프로젝트를 열고 다음 씬을 F6으로 실행한다.

- `godot/scenes/preview/character_preview.tscn`
- `godot/scenes/preview/fx_preview.tscn`
- `godot/scenes/preview/ui_preview.tscn`
- `godot/scenes/preview/environment_preview.tscn`

캐릭터/FX: ←/→ 또는 숫자키로 모션 선택, **F** 좌우 반전, **Space** 일시정지, **+/-** 재생 속도. 화면에서 실제 FPS와 프레임 번호, 발/효과 기준선을 확인한다. 프리뷰는 플레이 저장 파일을 읽거나 쓰지 않는다.

리소스 재생성이 필요하면 PNG 임포트 후 실행한다.

```powershell
godot --headless --path . --editor --import
godot --headless --path . --script tools/generate-godot-assets.gd
```

`tools/pack-character-assets.py`, `tools/pack-fx-assets.py` 등은 이미지 생성 도구가 아니라 RGBA 원본의 형식을 정리하는 도구다. 다시 실행하려면 원본 생성 이미지의 경로를 적은 입력 JSON이 필요하다. 일상적인 프로젝트 사용에는 이미 포함된 PNG와 `.tres`만 있으면 된다.

## 남은 개선 항목

- 테스트용 생성 아트이므로 최종 수작업 애니메이션 리터칭, 머리카락/손·발 형태의 프레임 간 미세 차이 정리가 남아 있다.
- 애니메이션별 자세는 구분되지만 완성형 걷기 보행주기·물리 기반 손 IK·급경사 발 IK는 포함하지 않는다.
- 눈 지형/눈 돌/눈 FX, 낙석·이벤트 경고 등 현재 v0.2에 대응 시스템이 없는 에셋은 프리뷰와 리소스로 제공한다. 새 게임 시스템을 추가한 것으로 간주하지 않는다.
- 곡선 경사·절벽 모듈의 충돌 형상, 타일 접합부의 최종 아트 다듬기, 더 많은 파괴/구르기 프레임은 후속 작업이다.
- 모바일 터치 조작과 실제 참가자 플레이테스트는 이 에셋 제작 범위에 포함되지 않는다.
