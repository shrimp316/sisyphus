# 산과 환경 데이터

> 아래 수치는 v0.1 기반 2단계의 저장 호환·구현 이력이다. 새 회차에 적용하는 v0.2 물리와 변경 범위는 [v0.2 반영 안내](v02-alignment.ko.md) 및 현재 스크립트를 기준으로 한다.

2단계에서는 외부 플러그인 없이 Godot Resource로 수제 구간을 정의한다.

## 산 생성

- 원본 데이터: `data/chunks/zone_{1..5}_{stone|soil|gravel}.tres`, 총 15종.
- Resource 스크립트: `scripts/mountain_chunk.gd`.
- 한 구역은 해당 구역의 후보 3종을 먼저 한 번씩 섞어 배치하고, 네 번째 구간을 추가로 선택한다.
- 구간 하나는 50m이며 오르막과 평평한 쉼터로 구성된다. 구역마다 4개 구간, 산 전체는 20개 구간이다.
- 난이도 5 구간이 3개 연속 나오지 않도록 후보를 제한한다.
- 회차 생성용 난수는 돌의 물리나 소리용 난수와 분리한다. 같은 시드는 같은 구간 배열과 날씨를 만든다.

`start_angle`과 `end_angle`은 현재 같은 값을 사용한다. 곡선형 경사 보간은 아직 구현하지 않았으므로 두 값을 다르게 설정하지 않는다. 구간별 오르막 길이와 경사·지형을 함께 설계해 빗길에서도 통과 가능한 후보만 사용한다.

## 지형과 날씨

| 지형 | 접지력 | 구름 저항 배율 | 미끄러움 |
|---|---:|---:|---:|
| 돌 | 1.00 | 1.00 | 0.60 |
| 흙 | 0.85 | 1.15 | 0.80 |
| 자갈 | 0.75 | 1.30 | 1.20 |

접지력은 밀기와 제동 힘에 적용한다. 구름 저항은 기본값 0.20에 지형 배율을 곱하며, 항상 이동 방향의 반대로 작용한다. 미끄러짐 누적은 기존 돌길을 기준으로 `미끄러움 / 0.60`을 곱한다.

날씨는 **맑음 80%, 비 20%**로 회차 시작 시 결정한다. 비는 접지력에 ×0.8, 미끄러짐 누적에 ×1.4를 적용한다. 명세의 바람은 이번 두 가지 날씨 구성에서 제외하고 맑음에 비중을 합쳤다. 회차 도중 갑작스러운 날씨 변경이나 확률성 추락은 없다.

지형은 경로의 색과 흙 선·자갈 입자로 구분한다. 빗길은 낮아진 하늘 채도, 빗줄기, 젖은 표면으로 표시한다. 현재 지형·날씨와 높은 미끄러짐 경고를 HUD에서 확인할 수 있다.

## 저장 호환

저장 파일명은 기존 `sisyphus-v1.json`을 유지하며 내부 저장 버전은 2로 기록한다. 현재 회차 상태와 별도로 `world`에 생성 버전·시드·날씨·순서가 정해진 구간 정의·지형 수치를 보관한다. 복원 시 현재 Resource 목록으로 산을 다시 생성하지 않고 저장된 정의를 사용한다.

버전 1 저장은 이전의 고정 산과 기존 물리 배율로 복원한다. 그 회차를 종료하고 새 회차를 시작하면 2단계 산이 생성된다. 임시 파일에 쓰기를 마친 후 원본 저장 파일을 교체하며, 쓰기에 실패하면 게임을 닫지 않고 재시도할 수 있게 안내한다.

## 검증용 실행

개발 중 특정 산과 날씨를 재현할 때만 사용하는 옵션이다. 기존 저장을 불러올 때는 저장된 산이 우선한다.

```powershell
& '.\.tools\godot\Godot_v4.5.1-stable_win64.exe' --path . --log-file "$PWD/.tools/environment-preview.log" -- --seed=2431 --weather=rain --save-path=res://.tools/environment-preview.json
```

## 공식 참고 자료

- [Godot Resource](https://docs.godotengine.org/en/stable/tutorials/scripting/resources.html)
- [RandomNumberGenerator](https://docs.godotengine.org/en/stable/classes/class_randomnumbergenerator.html)
- [DirAccess 파일 이름 변경](https://docs.godotengine.org/en/stable/classes/class_diraccess.html#class-diraccess-method-rename-absolute)
