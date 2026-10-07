# 《SISYPHUS》 게임 시스템 명세 v0.1

## 0. 게임 한 줄 정의

> 거대한 돌을 산 정상까지 밀어 올리는 과정에서 수없이 추락하고, 그 실패의 기억으로 시지프스 자신이 변화하는 2D 물리 로그라이트.

장르:

**2D Physics + Roguelite + Narrative**

핵심 감정:

**“이번에는 조금 더 올라갈 수 있을 것 같다.”**

핵심 철학:

**성장하는 것은 돌도 산도 아니라, 반복을 바라보는 플레이어의 태도다.**

---

# 1. 핵심 게임 루프

```text
[산 아래]
   ↓
돌 밀기
   ↓
경사 / 지형 / 날씨
   ↓
체력 관리
   ↓
이벤트
   ↓
선택
   ↓
계속 등반
   ↓
실수 / 체력 고갈 / 지형 실패
   ↓
돌 추락
   ↓
회수 시도
   ↓
실패
   ↓
산 아래까지 추락
   ↓
이번 회차 정산
   ↓
기억 획득
   ↓
능력 / 철학 / 사건 변화
   ↓
다시 돌 밀기
```

게임 오버라는 개념은 없다.

**추락 자체가 한 사이클의 종료다.**

---

# 2. 플레이 단위

한 번의 등반을 `RUN`이라 정의한다.

### 초기 목표 플레이타임

초반 RUN:

**5~8분**

중후반:

**10~15분**

산 정상까지 한 번에 성공할 경우:

**약 15분**

단, 숙련자는 더 빠르게 올라갈 수 있다.

---

# 3. 기본 조작

PC 기준.

| 입력 | 행동 |
|---|---|
| → / D | 돌 밀기 |
| Shift | 힘주기 |
| Space | 버티기 |
| E | 이벤트 상호작용 |
| ESC | 메뉴 |

캐릭터를 직접 좌우로 움직이는 시스템은 사용하지 않는다.

시지프스는 기본적으로 돌 뒤에 붙어 움직인다.

즉 플레이어가 조종하는 것은 사실상

**돌에 가하는 힘과 자세**

이다.

---

# 4. 핵심 물리 시스템

완전한 `RigidBody2D` 물리게임으로 만들지 않는다.

대신 돌은 산 위의 위치를 나타내는 하나의 값으로 관리한다.

```text
distance = 현재 산을 얼마나 올라갔는가
```

예:

```text
0m      산 아래
350m    중턱
750m    고지대
1000m   정상
```

돌의 핵심 변수:

```gdscript
var distance: float
var velocity: float
var acceleration: float
```

산은 `Path2D + Curve2D`로 제작한다.

```text
MountainPath
 ├─ 0m
 ├─ 100m
 ├─ 200m
 ├─ ...
 └─ Summit
```

현재 distance를 이용해 화면상의 실제 위치를 계산한다.

```gdscript
position = mountain_path.sample_baked(distance)
```

---

# 5. 돌 이동 공식

매 Physics Frame마다 계산한다.

기본 공식:

```text
가속도 =
플레이어의 밀기 힘
- 경사 중력
- 구름 저항
- 환경 저항
```

개념식:

```text
A = Push - Gravity - Resistance
```

Godot 구현 예:

```gdscript
func update_boulder(delta):

    var slope_angle = mountain.get_slope_angle(distance)

    var gravity_force = GRAVITY * sin(slope_angle)

    var push_force = player.get_push_force()

    var resistance = surface.get_resistance()

    acceleration = push_force - gravity_force - resistance

    velocity += acceleration * delta

    velocity = clamp(
        velocity,
        -MAX_FALL_SPEED,
        MAX_PUSH_SPEED
    )

    distance += velocity * delta
```

---

# 6. 경사

산의 난이도를 결정하는 가장 중요한 변수.

기본 범위:

```text
5° ~ 45°
```

예:

| 경사 | 의미 |
|---|---|
| 5° | 거의 평지 |
| 10° | 매우 쉬움 |
| 20° | 일반 |
| 30° | 어려움 |
| 35° | 위험 |
| 40° | 매우 위험 |
| 45° | 특수구간 |

경사 중력:

```text
gravity = G × sin(angle)
```

경사가 급할수록 돌을 밀기 어려워진다.

---

# 7. 플레이어 스탯

기본 능력치는 3개만 사용한다.

## 힘 POWER

돌을 미는 힘.

```text
PushForce =
BasePush
× PowerMultiplier
× StaminaMultiplier
× Traction
```

예:

```text
POWER 1 = ×1.00
POWER 2 = ×1.08
POWER 3 = ×1.16
...
```

권장 공식:

```text
PowerMultiplier = 1 + POWER × 0.08
```

---

## 지구력 ENDURANCE

최대 스태미나와 회복속도.

```text
MAX_STAMINA =
100 + ENDURANCE × 12
```

---

## 균형 BALANCE

미끄러짐 저항과 버티기 성능.

```text
Grip =
SurfaceGrip × (1 + BALANCE × 0.05)
```

---

# 8. 스태미나

범위:

```text
0 ~ 100+
```

일반 밀기:

```text
초당 -1
```

경사가 높을수록:

```text
Drain =
BaseDrain
× SlopeModifier
```

힘주기:

```text
초당 -4
```

정지:

```text
초당 +5
```

완전히 멈춘 상태:

```text
초당 +8
```

---

# 9. 스태미나가 낮을 때

스태미나는 플레이어를 멈추게 하는 게 아니라

**효율을 낮춘다.**

```text
100~50
Push ×1.0

50~20
Push ×0.85

20~1
Push ×0.65

0
Push ×0.50
```

따라서 완전히 행동 불능이 되는 상황은 없다.

---

# 10. 힘주기

Shift.

일종의 위험한 가속 버튼.

```text
Push ×1.65
Stamina Drain ×3
Slip Gain ×2
```

주 사용처:

- 급경사
- 순간적인 돌파
- 추락 직전
- 기록 갱신

항상 Shift를 누르면 오히려 플레이가 어려워진다.

---

# 11. 미끄러짐 시스템

랜덤 확률로 넘어지는 시스템은 사용하지 않는다.

대신 `SLIP_METER`를 사용한다.

```text
0 ───────── 100
안전          미끄러짐
```

계산:

```text
SlipGain =
Slope
× SurfaceSlipperiness
× PushIntensity
```

예:

```text
마른 돌길
×0.6

흙
×0.8

젖은 돌
×1.2

얼음
×1.8
```

Slip Meter가 100이 되면:

```text
SLIP 상태
```

발동.

약 1초 동안 힘을 잃는다.

이 순간 돌이 뒤로 움직이기 시작할 수 있다.

---

# 12. 버티기

Space.

뒤로 굴러가는 돌을 막는 기술.

조건:

```text
velocity < 0
```

효과:

```text
후진 가속도 감소
```

대신 스태미나를 매우 많이 소모한다.

개념식:

```text
BrakeForce =
Balance
× SurfaceGrip
```

따라서

```text
미끄러짐
↓
돌 후퇴
↓
Space
↓
버티기
↓
다시 밀기
```

라는 핵심 플레이가 발생한다.

---

# 13. 추락 단계

돌이 뒤로 움직인다고 즉시 실패하지 않는다.

세 단계가 있다.

### 1단계 — 흔들림

```text
velocity > -1
```

복구 쉬움.

### 2단계 — 후퇴

```text
-1 ~ -4
```

Space를 이용해 복구 가능.

### 3단계 — 폭주

```text
velocity < -4
```

`RUNAWAY`

상태 진입.

---

# 14. RUNAWAY

돌이 시지프스의 통제를 벗어난 상태.

이 순간부터 플레이어 입력이 거의 무효화된다.

돌이 빠르게 산 아래로 굴러간다.

카메라는 돌을 따라간다.

음악은 끊긴다.

효과음만 남는다.

```text
쿵

쿵

쿵

쿵
```

플레이어는 자신이 올라온 길이 빠르게 사라지는 것을 보게 된다.

이 장면은 스킵 가능하다.

단 최초 추락은 스킵 불가.

---

# 15. 산 구성

산 하나를 통째로 랜덤 생성하지 않는다.

**수제 Chunk를 랜덤 조합한다.**

예:

```text
Mountain
 ├─ Chunk_001
 ├─ Chunk_014
 ├─ Chunk_008
 ├─ Chunk_021
 ├─ Chunk_003
 └─ Summit
```

Chunk 하나:

```text
길이 20~60m
```

---

# 16. Chunk 데이터 구조

Godot Resource 사용.

```gdscript
class_name MountainChunk
extends Resource

@export var id: String

@export var length: float

@export var start_angle: float
@export var end_angle: float

@export var surface_type: String

@export var difficulty: int

@export var event_slots: Array

@export var tags: Array[String]
```

예:

```text
ID:
rock_slope_03

Length:
35m

Angle:
20 → 29°

Surface:
STONE

Difficulty:
3

Tags:
steep
dry
```

---

# 17. 산 구역

전체 산을 5개 구역으로 나눈다.

```text
0~20%
황량한 산기슭

20~40%
돌길

40~60%
절벽

60~80%
안개 지대

80~100%
신들의 산
```

각 구역은 별도의 Chunk Pool을 사용한다.

---

# 18. 지형 타입

## 돌

```text
Grip 1.0
Resistance 1.0
```

표준 지형.

---

## 흙

```text
Grip 0.85
Resistance 1.15
```

---

## 자갈

```text
Grip 0.75
Resistance 1.3
```

힘주기 사용 시 미끄러짐 증가.

---

## 젖은 돌

```text
Grip 0.6
```

---

## 얼음

```text
Grip 0.35
```

특수 구역.

---

# 19. 날씨

RUN 시작 시 하나 선택.

초기에는:

```text
맑음 70%
비 20%
바람 10%
```

후반에는 더 다양한 날씨 해금.

비:

```text
Grip ×0.8
```

바람:

일정 주기로

```text
PushForce ±10~30%
```

안개:

앞쪽 지형 표시 감소.

---

# 20. 산에는 체크포인트가 없다

중요.

```text
Checkpoint = 없음
```

산 중간에서 저장도 없다.

돌이 떨어지면 정말 떨어진다.

단 플레이어가 게임을 종료한 경우에만 현재 RUN 상태를 임시 저장한다.

---

# 21. 이벤트 시스템

산 곳곳에 Event Slot 존재.

예:

```text
350m
EVENT
```

접근하면 돌이 자연스럽게 홈에 걸려 정지한다.

플레이어가 E를 누르면 이벤트 시작.

이벤트 동안 돌은 움직이지 않는다.

---

# 22. 이벤트 데이터

```gdscript
class_name MountainEvent
extends Resource

@export var id: String
@export var title: String
@export var text: String

@export var choices: Array[EventChoice]

@export var conditions: Dictionary

@export var once_only: bool
```

Choice:

```gdscript
class_name EventChoice
extends Resource

@export var text: String

@export var stat_changes: Dictionary
@export var philosophy_changes: Dictionary

@export var memory_reward: int
```

---

# 23. 이벤트 예시 1 — 나무

처음 발견:

> 산 중턱에 작은 나무 한 그루가 있다.

선택:

```text
[잠시 쉰다]

[계속 올라간다]
```

쉰다:

```text
Stamina +100%
수용 +1
```

계속 올라간다:

```text
희망 +1
```

---

10번째 만남:

텍스트 변경.

> 이 나무를 전에 본 것 같다.

---

30번째 만남:

> 이 나무도 나처럼 이 산을 떠나지 않는다.

---

# 24. 이벤트 예시 2 — 다른 시지프스

다른 남자가 작은 돌을 밀고 있다.

선택:

```text
도와준다

무시한다

그의 돌을 밀어 떨어뜨린다
```

결과:

```text
도와준다
→ 수용

무시
→ 체념

떨어뜨린다
→ 반항
```

---

# 25. 이벤트 예시 3 — 신

신:

> 힘든가?

선택:

```text
그렇다.

아니다.

대답하지 않는다.
```

선택에 따라 철학 스탯 변화.

---

# 26. 이벤트 예시 4 — 버려진 돌

더 작은 돌 하나가 있다.

선택:

```text
내 돌을 버리고 작은 돌을 가져간다.

지금 돌을 계속 민다.
```

첫 번째 선택 시 실제로:

```text
BoulderMass -40%
```

하지만:

```text
MemoryReward -50%
```

정상 엔딩 일부 잠김.

---

# 27. 메타 자원 — 기억

돈이나 골드는 존재하지 않는다.

유일한 영구 자원:

# 기억

표기:

```text
MEMORY
```

---

# 28. 기억 획득

RUN 종료 시 계산.

기본:

```text
최고 고도
새로운 이벤트
새로운 지형
이전 기록 돌파
특수 선택
```

예:

```text
최고 높이        +12
새 사건 발견      +3
최고 기록         +5
새 인물 만남      +3

총 기억            23
```

---

# 29. 반복 파밍 방지

같은 높이 반복 시 보상 감소.

```text
RepeatedHeightReward ×0.3
```

새로운 경험을 발견해야 기억을 많이 얻는다.

즉:

**반복 플레이지만 반복 행동만 해서는 효율이 낮다.**

---

# 30. 영구 성장

기억을 사용해 능력을 해금한다.

단순한

```text
공격력 +10%
```

같은 업그레이드보다

**행동 자체를 변화시키는 능력**

위주로 설계한다.

---

# 31. 기억 트리

## 육체

### 굳은살

```text
Slip Gain -10%
```

### 익숙한 무게

```text
Push +5%
```

### 깊은 호흡

```text
Stamina Recovery +20%
```

### 버티는 다리

```text
Brace Cost -20%
```

---

## 경험

### 경사의 기억

앞으로 10m의 경사 표시.

### 비의 기억

비가 오기 전 시지프스가 하늘을 바라봄.

### 위험 감각

Slip Meter가 70 이상이면 화면 효과.

### 익숙한 길

이미 지나간 Chunk에서:

```text
Stamina Drain -10%
```

---

# 32. 철학 시스템

별도의 4개 숨겨진 수치.

```text
HOPE       희망

ACCEPT     수용

DEFIANCE   반항

RESIGN     체념
```

플레이어에게 정확한 숫자는 보여주지 않는다.

대신 행동과 대사가 변화한다.

---

# 33. 희망

철학:

> 정상에 도달하면 모든 것이 달라질 것이다.

특성:

고도가 높을수록 힘 증가.

```text
PushBonus =
HeightRatio × HopeLevel
```

정상 근처에서 가장 강력하다.

대신 추락했을 때:

```text
Memory Reward 감소
```

---

# 34. 수용

철학:

> 돌은 다시 떨어질 것이다.

특성:

정지 중 스태미나 회복 증가.

추락 후 기억 획득 증가.

안정적인 빌드.

---

# 35. 반항

철학:

> 나는 이 형벌의 규칙을 받아들이지 않는다.

특성:

위험한 행동 해금.

예:

```text
절벽 지름길

신의 제단 파괴

돌 깨기

금지된 길
```

높은 리스크 / 높은 보상.

---

# 36. 체념

철학:

> 어차피 떨어진다.

스태미나 소비 감소.

하지만:

```text
최대 Push 감소
```

매우 안정적이지만 느리다.

---

# 37. 철학 임계치

각 철학:

```text
0~15
```

해금:

```text
3
7
12
```

예:

희망 7:

> 정상은 가까워지고 있다.

80% 이상 고도에서

```text
Push +15%
```

---

# 38. RUN 시작 화면

매번 거창한 화면을 보여주지 않는다.

추락 후 화면 암전.

```text
RUN 17
```

잠시 후.

시지프스가 다시 돌 앞에 선다.

바로 게임 시작.

---

# 39. HUD

최소한으로 유지한다.

좌측 상단:

```text
421m
```

하단:

```text
STAMINA
████████░░
```

필요할 때만:

```text
SLIP
```

표시.

---

# 40. 정상은 HUD에 표시하지 않는다

다음과 같은 UI는 금지.

```text
421 / 1000m
```

대신:

```text
421m
```

만 표시한다.

플레이어는 정상까지 얼마나 남았는지 정확히 모른다.

---

# 41. 최고 기록

최고 기록을 넘으면 작은 효과만 발생.

예:

```text
427m
```

숫자가 잠깐 밝아진다.

아무 문구도 나오지 않는다.

---

# 42. 정상

distance가:

```text
MountainLength
```

에 도달하면 정상.

음악이 멈춘다.

바람 소리.

시지프스가 돌을 정상에 올린다.

화면에:

아무것도 뜨지 않는다.

약간의 정적 후 이벤트 진행.

---

# 43. 엔딩 1 — 희망

조건:

```text
HOPE >= 12
```

시지프스가 정상에서 아래를 바라본다.

그리고 미소를 짓는다.

그러나 돌이 천천히 움직인다.

다시 산 아래로 떨어진다.

시지프스가 따라 내려간다.

```text
RUN 32
```

게임 재개.

---

# 44. 엔딩 2 — 체념

조건:

```text
RESIGN >= 12
```

특정 이벤트에서:

```text
[돌을 두고 간다]
```

해금.

시지프스가 돌 옆에 앉는다.

화면 암전.

게임 재실행 시:

그는 여전히 앉아 있다.

플레이어가:

```text
[다시 일어난다]
```

를 선택하면 게임 재개.

---

# 45. 엔딩 3 — 반항

조건:

```text
DEFIANCE >= 12
```

특수 위치:

```text
신들의 제단
```

에서:

```text
돌을 깨뜨린다.
```

해금.

돌이 산산조각난다.

그러나 잠시 후 화면 밖에서

더 큰 돌이 떨어진다.

---

# 46. 엔딩 4 — 수용

조건:

```text
ACCEPT >= 12
```

정상에서 돌이 떨어질 때

시지프스가 쫓아가지 않는다.

그는 잠시 풍경을 바라본다.

그리고 천천히 산 아래로 걸어간다.

---

# 47. 진엔딩 — 부조리

조건:

```text
4개 철학 엔딩 확인

Core Event 20개 이상 발견

RUN 50+
```

다음 RUN.

화면:

```text
RUN 51
```

플레이어가 돌 앞에 선다.

하지만 아무 입력도 하지 않아도

시지프스가 스스로 돌을 밀기 시작한다.

플레이어의 조작 UI가 사라진다.

카메라가 천천히 멀어진다.

시지프스는 계속 산을 오른다.

마지막 문장:

> 우리는 시지프스를 행복한 인간으로 상상해야 한다.

게임 종료.

이후 다시 시작하면 정상 플레이 가능.

---

# 48. 난이도 설계

초기 캐릭터 상태에서도 정상 도달은 이론적으로 가능해야 한다.

메타 성장 없이 불가능한 벽을 만들지 않는다.

즉:

```text
성장 = 필수

X
```

```text
성장 = 실수를 허용해주는 장치

O
```

숙련자는 RUN 1에서도 정상 도달 가능.

---

# 49. 산 생성 알고리즘

산 생성 시 높이 구간별 Chunk Pool 사용.

Pseudo:

```gdscript
for section in sections:

    while section_length < target_length:

        var candidates = chunk_pool.filter(
            func(chunk):
                return chunk.difficulty <= allowed_difficulty
        )

        var selected = candidates.pick_random()

        add_chunk(selected)
```

중요:

완전 랜덤 금지.

연속 급경사 제한.

예:

```text
Difficulty 5 Chunk

3연속 등장 금지
```

---

# 50. Difficulty Curve

높이 비율:

```text
h = distance / mountain_length
```

추천:

```text
difficulty =
1 + pow(h, 1.3) × 4
```

결과:

```text
0%
Difficulty 1

25%
Difficulty 2

50%
Difficulty 3

75%
Difficulty 4

100%
Difficulty 5
```

---

# 51. Boulder Controller

파일:

```text
boulder_controller.gd
```

책임:

```text
distance

velocity

acceleration

surface

slope

runaway

brace
```

---

# 52. Player Controller

파일:

```text
sisyphus_controller.gd
```

책임:

```text
stamina

push_force

lean

brace

slip_meter

stats
```

---

# 53. Mountain Manager

```text
mountain_manager.gd
```

책임:

```text
Chunk 생성

거리 → 위치 변환

현재 경사 계산

현재 Surface 반환

Event 위치 관리
```

---

# 54. Run Manager

```text
run_manager.gd
```

상태:

```gdscript
enum RunState {

    START,

    ASCENDING,

    EVENT,

    SLIPPING,

    RUNAWAY,

    SUMMIT,

    END

}
```

---

# 55. Event Manager

```text
event_manager.gd
```

담당:

```text
이벤트 조건 검사

이벤트 중복 방지

선택 결과 적용

철학 변화

Memory 지급
```

---

# 56. Meta Manager

```text
meta_manager.gd
```

담당:

```text
Memory

Unlock

철학 수치

발견 이벤트

엔딩

총 RUN
```

---

# 57. Scene 구조

```text
Main
│
├── GameManager
│
├── RunManager
│
├── MetaManager
│
├── EventManager
│
├── Mountain
│   ├── Path2D
│   └── Environment
│
├── Boulder
│
├── Sisyphus
│
├── Camera2D
│
├── WorldObjects
│
├── AudioManager
│
└── CanvasLayer
    ├── HUD
    ├── EventUI
    └── RunResult
```

---

# 58. 저장 데이터

JSON 또는 Godot Resource.

```json
{
  "save_version": 1,

  "total_runs": 18,

  "best_height": 674.3,

  "memory": 42,

  "stats": {
    "power": 3,
    "endurance": 2,
    "balance": 4
  },

  "philosophy": {
    "hope": 4,
    "accept": 7,
    "defiance": 2,
    "resign": 1
  },

  "events_seen": [
    "tree_01",
    "god_01",
    "other_sisyphus_02"
  ],

  "endings": []
}
```

---

# 59. 사운드 시스템

이 게임에서는 그래픽보다 중요하다.

레이어:

```text
돌 마찰음

발소리

호흡

바람

심장박동

음악
```

스태미나 감소:

호흡 증가.

Slip 상승:

돌 긁히는 소리 증가.

Runaway:

음악 완전히 제거.

오직:

```text
돌

바람

충돌
```

만 남긴다.

---

# 60. 카메라

기본:

돌 기준 약간 앞쪽.

```text
Boulder
     ↓

   ●

        [Camera Center]
```

올라가는 방향을 조금 더 보여준다.

---

추락 시:

Camera Zoom Out.

플레이어가 자신이 올라온 거리를 한 번에 볼 수 있도록 한다.

---

# 61. 게임 재미의 핵심

플레이어에게 필요한 판단은 계속 이것이어야 한다.

```text
지금 힘을 더 줘야 하나?

조금 쉬어야 하나?

버텨야 하나?

이번 경사를 밀어붙일까?

안전하게 갈까?

저 이벤트를 볼까?

아니면 계속 올라갈까?
```

따라서 전투나 아이템 파밍은 넣지 않는다.

---

# 62. 절대 넣지 말아야 할 것

초기 버전에서는 다음 시스템을 넣지 않는다.

```text
인벤토리

장비 등급

무기

적 전투

퀘스트 목록

골드

상점 NPC

제작 시스템

복잡한 스킬 슬롯
```

이것들이 들어가면

**“돌을 미는 행위”**

라는 게임의 중심이 약해진다.

---

# 63. MVP

첫 번째 구현 목표는 딱 이것이다.

```text
산 1개

Chunk 15개

지형 3개

날씨 2개

스탯 3개

Memory

업그레이드 8개

이벤트 8개

철학 4개

Runaway

정상

엔딩 2개
```

---

# 64. MVP 플레이 루프

처음 구현할 때 다음 순서로 만든다.

```text
Path2D 생성
↓
돌 이동
↓
경사 계산
↓
Push
↓
Stamina
↓
후진
↓
Brace
↓
Runaway
↓
산 아래 Reset
```

여기까지 만들어졌을 때

**이미 게임이 재미있는지 확인해야 한다.**

재미가 없다면 이벤트나 로그라이크 요소를 추가하면 안 된다.

---

# 65. 두 번째 구현

핵심 물리가 재미있다면:

```text
Chunk 시스템

Surface

날씨

Slip Meter

Camera

사운드
```

추가.

---

# 66. 세 번째 구현

그다음:

```text
RUN

Memory

Meta Upgrade

Save
```

추가.

---

# 67. 마지막 구현

마지막에:

```text
이벤트

철학

대사 변화

엔딩

진엔딩
```

을 붙인다.

---

# 68. 가장 중요한 밸런스 원칙

플레이어가 실패했을 때:

> 게임이 나를 죽였다.

가 아니라

> 아, 거기서 힘을 너무 줬구나.

라고 느껴야 한다.

따라서 추락 원인은 항상

**플레이어가 이해할 수 있어야 한다.**

랜덤 즉사 금지.

보이지 않는 확률 금지.

---

# 69. 이상적인 플레이 상황

경사 35°.

스태미나:

```text
31%
```

돌이 점점 느려진다.

```text
0.8m/s

0.5m/s

0.2m/s
```

플레이어가 Shift.

돌이 다시 움직인다.

그러나 Slip:

```text
63

71

84

92
```

플레이어가 Shift를 놓는다.

하지만 이미 늦었다.

Slip 100.

시지프스가 미끄러진다.

돌:

```text
-0.5m/s

-1.4m/s

-2.7m/s
```

Space.

시지프스가 버틴다.

스태미나:

```text
18

12

7

3
```

돌:

```text
-0.3m/s
```

멈춘다.

시지프스가 숨을 헐떡인다.

잠시 뒤 다시 돌을 민다.

---

**이 15초가 재미있다면 게임은 성공한다.**

---

# 70. 게임의 진짜 성장 구조

일반 로그라이크:

```text
죽음
↓
강해짐
↓
더 멀리 감
```

《시지프스》:

```text
추락
↓
기억
↓
이해
↓
조금 다르게 올라감
↓
다시 추락
```

그리고 마지막에는 플레이어에게 이런 감각을 주는 것이 목표다.

처음:

> 이번에는 정상까지 가야지.

중반:

> 이번엔 지난번보다는 올라가자.

후반:

> 오늘은 어디까지 갈까.

마지막:

> 그냥 다시 밀자.