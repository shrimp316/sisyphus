# SISYPHUS 테스트용 아트 팩

첨부 레퍼런스의 반실사 페인터리 방향을 바탕으로 built-in `image_gen`에서 새 이미지를 제작했다. 레퍼런스 보드를 게임 텍스처로 사용하지 않는다. 생성 이미지의 알파를 보존한 채 프레임 분리·크기 조정·투명 여백 배치만 수행했다. 원본 생성 프롬프트는 `docs/image-prompts-*.json`에 있다.

## 폴더 구조와 산출물

```text
assets/
  character/sisyphus/
    idle/ push/ heavy_push/ brace/ exhausted/  # 개별 512×512 PNG 32장
    spriteframes/                            # 애니메이션별 시트 5장
  boulder/                                   # 384×384, 돌 4종
  terrain/                                   # 512×256, 지형 11종
  props/                                     # 384×384, 소품 7종
  fx/dust/ gravel/ impact/ wind/ breath/ snow/ # 256×256 프레임 36장 + 시트 6장
  ui/icons/                                  # 128×128 아이콘 8종
  ui/markers/                                # 256×256 월드 마커 3종
  metadata/                                  # 기준점·FPS·배치 정보·파일 목록
godot/
  resources/spriteframes/                     # 통합 2개 + 개별 11개 .tres
  scenes/preview/                             # character / fx / ui / environment
scripts/asset_visuals.gd                      # 게임의 텍스처·애니메이션 연결
scripts/asset_preview.gd                      # 독립 프리뷰
```

필수 아트는 개별 PNG 101장과 시트 11장, 총 112장이다. 기존 폰트 등은 이 수량에서 제외한다. 정확한 경로·크기·SHA-256은 `assets/metadata/asset_manifest.json`을 참고한다.

## 캐릭터 애니메이션

| 모션 | 프레임 | FPS | 게임 상태 |
|---|---:|---:|---|
| idle | 6 | 6 | 여유 있는 대기 |
| push | 8 | 8 | 일반 밀기 |
| heavy_push | 6 | 8 | 힘주어 밀기 / exert |
| brace | 6 | 8 | 버티기 / 미끄러짐 |
| exhausted | 6 | 6 | 체력이 낮은 휴식 |

모두 오른쪽을 바라보며 반복 재생한다. 캔버스는 512×512, 기준점은 **(256, 464)**, 발바닥 기준선은 **y=464**다. 애니메이션별 한 가지 배율을 적용하여 프레임마다 임의로 체형을 늘리지 않았다. 일반/강한 밀기는 손의 오른쪽 끝도 정렬했다. 자세에 따라 보이는 몸 높이는 달라진다.

`AnimatedSprite2D`에는 `godot/resources/spriteframes/sisyphus.tres`를 지정하고 `centered=false`, `offset=Vector2(-256,-464)`를 사용한다. 좌우 반전은 기준점이 유지되도록 노드의 `scale.x`를 반전한다. 게임 본체는 기존 CanvasItem 렌더링을 유지하면서 같은 SpriteFrames에서 현재 프레임을 읽는다.

## 지형·돌·소품

- 돌: default / rough / wet / snow. 중심 (192,192), 기준 반지름 176px. 게임에서는 기존 43px 반지름에 맞춰 표시하고 이동량에 따라 회전한다.
- 기본 지형: rock_ground / gravel_ground / mud_ground / wet_rock / snow_ground.
- 특수 지형: steep_slope_up / convex_slope_up / concave_slope_down / ledge / foothold_rest_platform / small_stone_step.
- 소품: cairn_checkpoint / broken_signpost / dead_tree / small_tree / ruin_pillar / shrine_fragment / simple_arch_ruin.

기본 지형의 보행면 기준은 y=64다. 실제 게임은 기존 경사선을 따라 텍스처를 변형해 그리므로 시각 교체 때문에 충돌 경로가 달라지지 않는다. 특수 모듈의 배치 기준·상단 윤곽은 `environment_assets.json`에 기록한다. `Sprite2D`/`Polygon2D`에서 사용할 수 있으며, 새로운 스테이지에 배치할 때는 별도 충돌 형상을 설계해야 한다. 소품은 하단 기준점 (192,352)을 쓴다. 돌탑/쉼터 그림 자체가 새 부활 체크포인트를 만들지는 않는다.

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
