# 《시지프스》 상세 구현 명세 v0.2

## 1. 프로젝트 개요

### 1.1 게임명

**가제: SISYPHUS / 시지프스**

### 1.2 장르

2D 물리 기반 등반 로그라이트  
+ 내러티브 이벤트  
+ 메타 성장  
+ 숙련형 컨트롤

### 1.3 핵심 컨셉

플레이어는 시지프스가 되어 거대한 돌을 산 위로 밀어 올린다.

돌은 무겁고 산은 가파르다.

잘못 힘을 주거나, 관성을 잃거나, 스태미나가 부족하거나, 미끄러짐을 제어하지 못하면 돌은 뒤로 굴러간다.

그러나 실패는 즉각적인 게임오버가 아니다.

플레이어는 돌을 다시 붙잡고 버틸 수 있으며, 작은 실수는 몇 미터 후퇴로 끝날 수도 있고 큰 실수는 산 아래까지 이어질 수도 있다.

결국 돌이 완전히 통제를 벗어나면 이번 RUN이 종료된다.

플레이어는 실패 과정에서 얻은 **기억**을 통해 조금씩 성장하고 다시 산을 오른다.

---

# 2. 게임의 핵심 문장

> 얼마나 남았는지는 알 수 없다.  
> 하지만 지금 올라가고 있다는 것은 알 수 있다.

게임 전체 디자인은 이 원칙을 따른다.

따라서 정상까지의 퍼센트, 전체 높이, 남은 거리 등은 표시하지 않는다.

대신 플레이어가 지금의 성취와 실패는 명확하게 이해할 수 있어야 한다.

---

# 3. 핵심 재미

게임의 재미 우선순위는 다음과 같다.

### 1순위 — 아슬아슬한 복구

돌이 뒤로 밀리기 시작했을 때 플레이어가 자신의 판단과 조작으로 다시 살려내는 순간.

### 2순위 — 관성과 힘을 제어하는 손맛

계속 강하게 미는 게임이 아니라 언제 힘을 주고 언제 빼야 하는지 판단하는 게임.

### 3순위 — 잃을 것이 커지는 긴장감

높이 올라갈수록 추락의 손실이 커진다.

### 4순위 — 산을 학습하는 숙련감

캐릭터뿐 아니라 플레이어 자신이 점점 지형을 이해한다.

### 5순위 — 작은 목표의 연속

“정상까지”가 아니라

> 저 턱까지만.  
> 저 나무까지만.  
> 저 능선까지만.

이라는 목표를 계속 제공한다.

### 6순위 — 실패 자체의 관전 재미

돌이 자신이 지나온 산을 거꾸로 굴러 내려가는 장면 자체가 하나의 강력한 연출이 된다.

---

# 4. 핵심 플레이 루프

```text
RUN 시작

↓

현재 지형 확인

↓

관성 확보

↓

돌 밀기

↓

경사 / 표면 / 날씨 판단

↓

힘 조절

↓

스태미나 관리

↓

Slip 관리

↓

위험 발생

├─ 복구 성공
│     ↓
│   계속 등반
│
└─ 복구 실패
      ↓
   부분 추락
      ↓
   다시 복구 시도
      ↓
   Runaway
      ↓
   완전 추락

↓

RUN 정산

↓

기억 획득

↓

영구 성장 / 새로운 사건 해금

↓

다음 RUN
```

---

# 5. 플랫폼 및 기술

## 엔진

Godot 4.x

## 화면

2D 횡스크롤.

## 기준 해상도

1920 × 1080.

Viewport Stretch를 사용하여 다른 해상도 대응.

## 목표 플랫폼

1차:

PC

2차:

Web

3차:

Mobile

---

# 6. 물리 구현 방식

## 6.1 완전한 자유 물리 사용 금지

돌을 `RigidBody2D`만으로 구현하지 않는다.

이유:

- 산의 긴 경로에서 물리 버그 가능성 증가
- 돌이 지형 틈에 끼일 가능성
- 재현 가능한 난이도 설계 어려움
- 모바일/Web에서 안정성 저하
- 밸런스 조정 어려움

대신 **1차원 Path 기반 준물리 시스템**을 사용한다.

---

# 7. 핵심 위치 변수

돌의 실질적인 위치는 하나의 Float 값으로 관리한다.

```gdscript
var distance: float = 0.0
```

예:

```text
0        산 아래
175      초기 경사
430      중턱
812      고지대
???      정상
```

플레이어에게 전체 산 길이는 알려주지 않는다.

화면상의 위치는 `Path2D`에서 가져온다.

```gdscript
global_position = mountain_path.curve.sample_baked(distance)
```

---

# 8. 돌 물리 변수

```gdscript
var distance: float
var velocity: float
var acceleration: float

var mass: float = 1.0

var current_slope: float
var current_surface: SurfaceData

var runaway: bool = false
```

---

# 9. 기본 이동 공식

매 Physics Frame:

```text
Acceleration =
PlayerPush
+ MomentumBonus
- GravityForce
- SurfaceResistance
- EnvironmentResistance
```

Godot 예:

```gdscript
func calculate_acceleration() -> float:

    var push := sisyphus.get_push_force()

    var gravity :=
        gravity_strength * sin(current_slope)

    var resistance :=
        current_surface.resistance

    var momentum :=
        get_momentum_modifier()

    return push * momentum \
        - gravity \
        - resistance
```

업데이트:

```gdscript
velocity += acceleration * delta

velocity = clamp(
    velocity,
    -max_fall_speed,
    max_forward_speed
)

distance += velocity * delta
```

---

# 10. 기본 조작

| 키 | 기능 |
|---|---|
| D / → | 기본 밀기 |
| Shift | 강하게 밀기 |
| Space | 버티기 |
| E | 이벤트 상호작용 |
| ESC | 메뉴 |

MVP에서는 버튼을 이것 이상 늘리지 않는다.

---

# 11. 기본 밀기

D 입력.

특징:

- 안전함
- 스태미나 효율 좋음
- Slip 상승 적음
- 일반 등반용

기준값:

```text
PushForce = 1.0
StaminaDrain = 1.0/s
SlipModifier = ×1.0
```

---

# 12. 강하게 밀기

D + Shift.

```text
PushForce ×1.65

StaminaDrain ×3.0

SlipGain ×1.8
```

목적:

- 급경사 돌파
- 관성 생성
- 돌턱 통과
- 긴급 복구

하지만 계속 사용하면 위험해진다.

즉 Shift는 단순한 달리기 버튼이 아니다.

---

# 13. 관성 시스템

이 게임의 가장 중요한 시스템 중 하나.

돌은 정지 상태에서 움직이기 가장 어렵다.

이미 일정 속도를 가지고 있다면 훨씬 적은 힘으로 이동할 수 있다.

### 권장 속도 영역

```text
후퇴        -MAX ← 0

정지        0

저속        0 ~ 0.45

적정        0.45 ~ 1.2

고속        1.2 ~ 1.7

위험        1.7+
```

---

# 14. Sweet Spot

적정 속도 상태에서는 효율 보너스를 받는다.

```text
Velocity = 0.45 ~ 1.2
```

효과:

```text
Push Efficiency +10%

Stamina Drain -20%

Slip Gain -10%
```

따라서 플레이어는 단순히 빠르게 가는 것이 아니라

**좋은 속도를 유지하는 법**

을 학습하게 된다.

---

# 15. 정지 페널티

속도:

```text
0 ~ 0.15
```

일 때 돌을 다시 움직이려면 큰 힘이 필요하다.

```text
RequiredForce ×1.25
```

따라서 급경사 중간에서 멈추는 것은 위험하다.

---

# 16. 고속 페널티

```text
Velocity > 1.5
```

이면:

```text
SlipGain 증가
Control 감소
돌턱 충돌 위험 증가
```

따라서 최대 속도가 항상 최적은 아니다.

---

# 17. 스태미나

기본값:

```text
100
```

범위:

```text
0 ~ MaxStamina
```

---

# 18. 스태미나 소비

기본 밀기:

```text
-1 / sec
```

강하게 밀기:

```text
-3 / sec
```

버티기:

```text
-4 / sec
```

경사 Modifier 적용:

```text
Drain =
BaseDrain
× SlopeModifier
× ActionModifier
```

예:

```text
10°  ×0.8
20°  ×1.0
30°  ×1.3
40°  ×1.7
```

---

# 19. 스태미나 회복

완전 정지:

```text
+7 / sec
```

안전 발판:

```text
+10 / sec
```

약한 경사에서 힘을 놓고 있음:

```text
+3 / sec
```

---

# 20. 스태미나 부족

0이 되어도 행동 불능이 되지는 않는다.

```text
50~100
Push ×1.00

20~50
Push ×0.85

1~20
Push ×0.65

0
Push ×0.45
```

호흡 소리가 크게 변한다.

---

# 21. 호흡 시스템

호흡은 별도의 입력을 요구하지 않는다.

캐릭터 내부적으로 일정한 Cycle을 가진다.

기본:

```text
흡입 2초
유지 1초
내쉼 3초
```

총 약 6초.

---

# 22. 호흡 보너스

내쉬는 타이밍 중 Shift 입력:

```text
Push +20%

Stamina Cost -20%
```

초보자는 무시해도 플레이 가능하다.

숙련자는 캐릭터의 숨소리를 듣고 타이밍을 맞춘다.

UI 게이지는 표시하지 않는다.

피드백:

- 호흡 소리
- 등 움직임
- 어깨 움직임
- 미세한 카메라 진동

---

# 23. Slip 시스템

미끄러짐을 랜덤 확률로 처리하지 않는다.

모든 위험은 누적값으로 계산한다.

```gdscript
var slip_meter: float = 0.0
```

범위:

```text
0 ~ 100
```

---

# 24. Slip 증가

```text
SlipGain =
SlopeFactor
× SurfaceFactor
× ForceFactor
× SpeedFactor
```

예:

```text
경사 10° → 낮음

경사 35° → 높음

자갈 → ×1.3

젖은 바위 → ×1.5

Shift → ×1.8

고속 → ×1.4
```

---

# 25. Slip 자연 회복

힘을 약하게 줄 때:

```text
-4 / sec
```

정지:

```text
-10 / sec
```

안전 발판:

```text
-20 / sec
```

---

# 26. Slip 단계

```text
0~40
안전

40~70
주의

70~90
위험

90~99
임계

100
SLIP 발생
```

---

# 27. Slip 발생

Slip 100:

시지프스가 약 0.7초 균형을 잃는다.

이 시간 동안:

```text
PushForce ×0.1
```

돌은 거의 중력만 받는다.

즉 급경사에서는 즉시 뒤로 움직이기 시작한다.

---

# 28. 버티기

돌이 후진할 때 Space.

```text
velocity < 0
```

이면 활성화.

버티기 힘:

```text
BraceForce =
BaseBrace
× BalanceStat
× SurfaceGrip
```

효과:

후진 가속도를 감소시킨다.

---

# 29. 버티기의 목적

플레이어에게 다음 상황을 제공해야 한다.

```text
돌이 미끄러짐

↓

후진

↓

Space

↓

스태미나 급감

↓

속도 감소

↓

돌 정지

↓

다시 Push

↓

복구 성공
```

게임의 대표적인 클러치 상황이다.

---

# 30. 추락 단계

모든 실패를 즉시 RUN 종료시키지 않는다.

### Stage 0

```text
velocity >= 0
```

정상.

### Stage 1 — 밀림

```text
0 > velocity > -0.8
```

쉽게 복구 가능.

### Stage 2 — 후퇴

```text
-0.8 ~ -2.0
```

버티기 필요.

### Stage 3 — 추락

```text
-2.0 ~ -4.0
```

일반적인 복구 매우 어려움.

### Stage 4 — RUNAWAY

```text
velocity <= -4.0
```

돌 통제 상실.

---

# 31. 부분 추락

산에는 자연적인 홈과 안전지대가 존재한다.

돌이 뒤로 굴러가다가 해당 구간에 걸리면:

```text
velocity = 0
```

따라서 실패 결과가 다양하다.

예:

```text
작은 실수
→ 3m 후퇴

중간 실수
→ 20m 후퇴

큰 실수
→ 80m 후퇴

완전 실패
→ 산 아래
```

---

# 32. RUNAWAY

돌이 완전히 통제에서 벗어난 상태.

입력 제한.

시지프스는 돌을 따라갈 수 없다.

카메라는 돌을 따라간다.

UI 제거.

음악 제거.

남는 소리:

- 바람
- 돌 회전
- 충돌
- 돌이 튀는 소리

돌은 플레이어가 지나온 구간을 빠르게 역주행한다.

---

# 33. RUNAWAY 연출

카메라 Zoom Out.

```text
1.0
↓
0.9
↓
0.8
```

고도가 높았다면 더 멀리 보여준다.

목적은 플레이어가:

> 내가 저만큼 올라왔었구나.

를 시각적으로 느끼게 하는 것.

---

# 34. 추락 스킵

첫 번째 RUNAWAY:

스킵 불가.

두 번째부터:

키 입력 시 빠른 연출.

단 완전 암전하지 않고 최소 1~2초 정도는 추락을 보여준다.

---

# 35. 산 구조

산 전체를 Procedural Generation으로 만들지 않는다.

**수제 Chunk + 제한 랜덤 조합**

방식을 사용한다.

---

# 36. Chunk

하나의 Chunk 길이:

```text
20~60m
```

각 Chunk에는:

```text
Path Curve

Surface

Difficulty

RestPoint

EventSlot

VisualSet

Tags
```

가 존재한다.

---

# 37. Chunk Resource

```gdscript
class_name MountainChunkData
extends Resource

@export var id: String

@export var length: float

@export var difficulty: int

@export var start_angle: float

@export var end_angle: float

@export var surface_id: String

@export var tags: Array[String]

@export var event_slots: int

@export var rest_points: Array[float]
```

---

# 38. 산 생성 구조

산은 내부적으로 여러 Zone으로 구분된다.

예:

```text
ZONE 1
산기슭

ZONE 2
메마른 바위

ZONE 3
절벽

ZONE 4
안개

ZONE 5
구름 위

ZONE 6
???
```

플레이어에게 Zone 번호는 표시하지 않는다.

---

# 39. 난이도 진행

내부 변수:

```text
height_ratio =
distance / mountain_length
```

단 이 값은 플레이어에게 절대 표시하지 않는다.

추천 Difficulty:

```text
1 + pow(height_ratio, 1.35) × 4
```

---

# 40. 산 랜덤 생성 규칙

다음 조합은 금지한다.

```text
고난도 Chunk 3연속

강풍 + 얼음 + 40° 이상 급경사

안전지대 없이 150m 이상

동일 Chunk 연속

동일 Surface 4연속
```

---

# 41. 지형 — 기본 바위

```text
Grip 1.0

Resistance 1.0

Slip ×1.0
```

기본 지형.

---

# 42. 자갈

```text
Grip 0.75

Resistance 1.15

Slip ×1.3
```

강한 입력에 민감하다.

Shift 사용:

```text
추가 Slip ×1.3
```

전략:

천천히 일정한 힘 유지.

---

# 43. 진흙

```text
Grip 0.9

Resistance 1.5
```

속도가 낮을수록 저항 증가.

따라서 멈추면 불리하다.

전략:

관성 유지.

---

# 44. 젖은 바위

```text
Grip 0.55

Resistance 0.85

Slip ×1.5
```

쉽게 굴러가지만 제어하기 어렵다.

---

# 45. 얼음

후반부 특수 지형.

```text
Grip 0.3

Resistance 0.6
```

초기 MVP에서는 제외 가능.

---

# 46. 돌턱

짧은 순간 높은 Push가 필요한 장애물.

예:

```text
RequiredPush ×1.6
```

좋은 호흡 타이밍 + Shift 사용 권장.

성공:

돌이 턱을 넘어가며 강한 충돌 피드백.

```text
쿵
```

---

# 47. 급경사

경사 진입 전에 속도를 만들어야 한다.

경사 내부에서 정지하면 매우 불리.

플레이어에게 자연스럽게:

**“진입 전에 준비한다.”**

라는 습관을 가르친다.

---

# 48. 오목 경사

```text
\        /
 \      /
  \____/
```

내리막 관성을 이용해 다음 오르막을 통과할 수 있다.

고급 플레이에서는 일부러 약간 뒤로 이동한 뒤 반동을 이용할 수도 있다.

---

# 49. 볼록 경사

```text
     ___
   /
 /
```

정상 직전 가장 힘든 구조.

마지막 Burst 타이밍을 요구한다.

---

# 50. 발판

산에 자연스럽게 존재하는 휴식 지점.

돌이 홈에 안정적으로 걸린다.

효과:

```text
Stamina Recovery 증가

Slip Recovery 증가

Backward Gravity 감소
```

---

# 51. 발판 종류

### 안전 발판

충분히 넓음.

완전 휴식 가능.

### 작은 발판

돌 위치가 정확해야 함.

### 부서지는 발판

일정 시간 이상 머무르면 파괴.

예:

```text
5초
```

따라서:

> 더 쉬어갈 것인가?

라는 선택을 만든다.

---

# 52. 반동 밀기

고급 플레이 기술.

일부러 돌을 조금 뒤로 보낸다.

```text
뒤로 이동

↓

중력 가속

↓

적절한 순간 Push

↓

관성 전환

↓

급경사 돌파
```

게임에서 직접 튜토리얼로 설명하지 않는다.

플레이어가 발견하도록 한다.

후반 이벤트나 기억 능력으로 힌트 제공 가능.

---

# 53. 날씨

RUN 시작 시 결정.

초기:

```text
맑음
비
바람
```

---

# 54. 비

```text
Wet Surface 확률 증가

Grip -15%
```

하지만 산 전체에 균일 적용하지 않는다.

---

# 55. 바람

완전 랜덤이 아니다.

강풍 약 3초 전:

- 바람 소리 증가
- 먼지 움직임
- 옷자락 흔들림

플레이어가 예측 가능해야 한다.

---

# 56. 낙석

화면 상단에서 미리 표시.

랜덤 즉사 금지.

선택:

```text
멈춰 기다린다

VS

빠르게 통과한다
```

---

# 57. 순간 판단 빈도

이상적인 플레이에서:

**5~10초마다 한 번의 작은 판단**

이 발생해야 한다.

예:

```text
힘을 더 줄까?

지금 쉬어야 하나?

관성을 유지할까?

Shift를 쓸까?

Slip을 낮출까?

발판까지 밀어붙일까?

낙석을 기다릴까?

후퇴해서 반동을 받을까?
```

---

# 58. 진행도 시스템

진행도는 존재한다.

하지만 전체 진행률을 알려주지 않는다.

금지:

```text
72%

720 / 1000m

정상까지 280m

Zone 4 / 6
```

---

# 59. HUD의 진행도

표시:

```text
742m
```

이것만 사용한다.

높이는 절대적인 기록일 뿐 정상과의 관계를 알려주지 않는다.

---

# 60. 작은 진행 목표

항상 화면 안이나 화면 가까이에 작은 목적지가 보여야 한다.

예:

- 발판
- 돌턱
- 능선
- 나무
- 동굴
- NPC
- 폐허
- 신전

플레이어는 자연스럽게

> 저기까지만.

이라는 생각을 하게 된다.

---

# 61. 이전 최고 기록

최고 기록 숫자를 HUD에 지속적으로 표시하지 않는다.

대신 실제 세계에서 표현한다.

예:

이전 기록:

```text
623m
```

다음 RUN에서 623m 근처에 도착하면:

- 오래된 손자국
- 시지프스가 쌓은 작은 돌탑
- 긁힌 바위
- 이전에 떨어뜨린 천조각

등이 등장한다.

텍스트 설명 없음.

---

# 62. 최고점 통과 연출

이전 최고점을 넘어가면:

현재 고도 숫자가 약 0.5초 강조.

```text
624m
```

별도 메시지:

```text
NEW RECORD!
```

같은 게임적 문구는 사용하지 않는다.

---

# 63. 환경을 통한 진행감

높이 올라갈수록 환경이 바뀐다.

```text
풀

↓

나무

↓

돌

↓

안개

↓

눈

↓

구름

↓

별

↓

???
```

따라서 플레이어는 수치를 몰라도:

> 꽤 많이 올라왔다.

를 느낀다.

---

# 64. 가짜 정상

산 전체에서 1~2회 사용.

플레이어 시야에서는 능선 끝이 정상처럼 보인다.

힘겹게 도착.

카메라가 올라간다.

그 뒤로 더 거대한 산이 드러난다.

남발 금지.

목적:

**끝이 있다고 믿었던 기대를 한 번 뒤집는다.**

---

# 65. 실제 정상

정상은 존재한다.

즉 게임이 무한 생성되는 것은 아니다.

다만 플레이어는:

- 존재 여부
- 거리
- 높이

를 알 수 없다.

---

# 66. 고도 UI 변화

초반에는 기본적으로:

```text
742m
```

표시.

게임 진행 후:

```text
고도 표시 끄기
```

옵션 해금 가능.

진엔딩 루트에서는 특정 순간 고도 표시가 자동으로 사라진다.

상징:

처음에는 숫자가 중요했지만 마지막에는 더 이상 중요하지 않다.

---

# 67. 이벤트

산의 특정 위치에 Event Slot 존재.

이벤트 진입 시 돌이 자연스럽게 홈에 걸린다.

플레이어가 E 입력 시 발생.

---

# 68. 이벤트 종류

### 환경

나무  
꽃  
시체  
버려진 돌  
폐허

### 인물

다른 시지프스  
여행자  
노인  
아이

### 신

신의 목소리  
신전  
제단

### 기억

과거의 흔적  
이전 RUN의 장소

---

# 69. 이벤트 Resource

```gdscript
class_name MountainEventData
extends Resource

@export var id: String

@export var text: String

@export var choices: Array[EventChoiceData]

@export var minimum_height: float

@export var required_tags: Array[String]

@export var once_only: bool
```

---

# 70. 이벤트 예시 — 나무

첫 만남:

> 산 중턱에 작은 나무 한 그루가 있다.

선택:

```text
잠시 쉰다.

계속 올라간다.
```

쉰다:

```text
Stamina Full

Accept +1
```

계속:

```text
Hope +1
```

반복 만남에 따라 문장이 변화한다.

---

# 71. 철학 변수

네 가지 숨겨진 값.

```text
HOPE

ACCEPT

DEFIANCE

RESIGN
```

정확한 숫자는 플레이어에게 공개하지 않는다.

---

# 72. 희망

> 정상에 도달한다면 모든 것이 바뀔 것이다.

게임 효과:

높은 고도에서 Push 상승.

대신 큰 추락의 심리적 페널티가 큼.

---

# 73. 수용

> 돌은 다시 떨어질 것이다.

게임 효과:

휴식 효율 증가.

추락 이후 Memory 획득량 증가.

---

# 74. 반항

> 나는 이 규칙을 받아들이지 않는다.

게임 효과:

비정상 루트 해금.

예:

- 절벽 지름길
- 제단 파괴
- 돌 교체
- 금지된 길

---

# 75. 체념

> 어차피 다시 떨어진다.

효과:

Stamina 소비 감소.

대신 최대 Push 감소.

안정적이지만 느린 플레이.

---

# 76. 영구 자원 — 기억

게임에는 기본적으로 골드가 없다.

영구 자원:

**MEMORY**

---

# 77. 기억 획득

RUN 종료:

```text
최고 고도

이전 기록 돌파

처음 본 지형

새 이벤트

특별 선택

첫 번째 복구

대형 추락 생존
```

등을 평가.

---

# 78. 기억 반복 파밍 제한

같은 행동을 반복하면 보상 감소.

예:

```text
이미 방문한 고도
×0.25

이미 본 이벤트
0

새 Event
+3

신기록
+5
```

즉 실패를 반복한다고 자동으로 강해지는 구조가 아니다.

---

# 79. 영구 성장

세 가지 육체 스탯.

```text
POWER

ENDURANCE

BALANCE
```

---

# 80. POWER

Push 힘.

```text
Multiplier =
1 + POWER × 0.06
```

강화 한 번당 약 6%.

과도한 메타 성장 방지.

---

# 81. ENDURANCE

```text
MaxStamina =
100 + ENDURANCE × 8
```

회복에도 약간 영향.

---

# 82. BALANCE

```text
BraceForce 증가

SlipGain 감소
```

추천:

레벨당 SlipGain 약 -3%.

---

# 83. 능력형 기억

숫자 상승보다 행동 변화형 업그레이드를 중요시한다.

예:

### 경사의 기억

앞으로 약 8m의 위험 경사를 시각적으로 미묘하게 인지.

### 젖은 돌의 기억

젖은 바위 SlipGain -10%.

### 깊은 호흡

호흡 Burst Window +0.3초.

### 익숙한 무게

정지 상태 초기 Push 페널티 감소.

### 버티는 다리

Brace Stamina Drain -15%.

---

# 84. RUN 시작

화려한 준비 화면 없음.

추락 종료.

잠깐 암전.

```text
RUN 17
```

약 1초.

다시 산 아래.

시지프스가 돌에 손을 댄다.

조작 가능.

---

# 85. HUD

최대한 단순하게.

좌측 위:

```text
742m
```

하단:

```text
STAMINA
███████░░░
```

Slip은 위험할 때만 표시.

```text
SLIP
████████░░
```

---

# 86. Slip UI

평상시 숨김.

```text
Slip > 40
```

에서 서서히 나타남.

따라서 HUD가 상시 복잡하지 않는다.

---

# 87. 화면 피드백

위험 상태를 숫자만으로 전달하지 않는다.

Slip 상승:

- 발 미끄러짐
- 돌 긁는 소리
- 화면 미세 진동
- 먼지 증가

Stamina 부족:

- 호흡 증가
- 자세 무너짐
- Push Animation 느려짐

---

# 88. 카메라

기본 위치:

돌보다 진행 방향 쪽을 조금 더 보여준다.

```text
Sisyphus ●

        Camera Center
```

앞의 지형을 읽을 수 있어야 한다.

---

# 89. 카메라 Look Ahead

속도에 따라:

```text
CameraOffset =
velocity × look_ahead_factor
```

빠르게 갈수록 앞쪽을 더 보여준다.

---

# 90. 오디오

오디오는 핵심 게임 시스템이다.

레이어:

```text
호흡

발소리

돌 마찰

돌 회전

바람

환경

음악
```

---

# 91. 동적 사운드

Stamina 낮음:

호흡음 증가.

Slip 높음:

마찰음 증가.

높은 속도:

돌 회전음 증가.

RUNAWAY:

음악 제거.

---

# 92. Game State

```gdscript
enum RunState {

    START,

    ASCENDING,

    EVENT,

    SLIPPING,

    FALLING,

    RUNAWAY,

    SUMMIT,

    RESULT

}
```

---

# 93. 기본 Scene 구조

```text
Main
│
├── GameManager
├── RunManager
├── MetaManager
├── SaveManager
├── EventManager
├── AudioManager
│
├── Mountain
│   ├── Path2D
│   ├── ChunkContainer
│   ├── VisualContainer
│   └── EventContainer
│
├── Boulder
├── Sisyphus
├── Camera2D
│
└── UI
    ├── HUD
    ├── EventUI
    ├── ResultUI
    └── PauseUI
```

---

# 94. BoulderController

`boulder_controller.gd`

담당:

```text
distance

velocity

acceleration

current_slope

current_surface

momentum

fall_state

runaway
```

Signal:

```gdscript
signal started_falling

signal recovered

signal runaway_started

signal reached_distance(distance)
```

---

# 95. SisyphusController

`sisyphus_controller.gd`

담당:

```text
Input

Push

Burst

Brace

Stamina

Slip

Breathing

Stats
```

---

# 96. MountainManager

담당:

```text
Chunk 생성

Path 생성

Surface 정보

Slope 계산

Rest Point

Event Slot

Visual Zone
```

---

# 97. RunManager

담당:

```text
RUN 번호

현재 State

현재 최고 고도

RUN 기록

Runaway

Result
```

---

# 98. MetaManager

담당:

```text
Memory

Stats

Unlock

Philosophy

Endings

Events Seen

Best Height
```

---

# 99. Save Data

```json
{
  "save_version": 1,

  "total_runs": 17,

  "best_height": 742.3,

  "memory": 28,

  "stats": {
    "power": 2,
    "endurance": 3,
    "balance": 2
  },

  "philosophy": {
    "hope": 4,
    "accept": 3,
    "defiance": 2,
    "resign": 1
  },

  "events_seen": [
    "tree_01",
    "traveler_01"
  ],

  "unlocks": [
    "memory_slope",
    "memory_breath"
  ],

  "endings": []
}
```

---

# 100. 정상 도달

정상 도달 시:

음악 종료.

바람만 남음.

돌이 정상에 올라간다.

UI 제거.

즉시

```text
CLEAR
```

같은 문구를 띄우지 않는다.

잠깐의 정적 후 캐릭터의 철학 상태에 따라 엔딩 분기.

---

# 101. 엔딩 구조

희망 / 수용 / 반항 / 체념에 대응하는 엔딩을 각각 둔다.

모든 엔딩은:

**“다시는 돌을 밀지 않는다.”**

라는 단순한 종료보다 반복이라는 게임 구조와 연결되는 방향으로 제작한다.

---

# 102. 진엔딩

조건 예:

```text
4개 철학 엔딩 확인

Core Event 20개 이상

RUN 40 이상
```

새 RUN 시작.

플레이어가 아무 입력을 하지 않는다.

그러나 잠시 뒤 시지프스가 스스로 돌을 밀기 시작한다.

HUD가 나타나지 않는다.

플레이어 Input 비활성.

카메라가 천천히 멀어진다.

시지프스는 계속 산을 오른다.

게임 종료.

---

# 103. 난이도 원칙

메타 업그레이드 없이도 이론적으로 정상 도달 가능해야 한다.

메타 성장은:

```text
진행 허가
```

가 아니라

```text
실수 허용량
```

을 증가시킨다.

숙련자가 새로운 Save에서 RUN 1 정상에 도달할 수 있어야 한다.

---

# 104. 실패 설계 원칙

실패했을 때 플레이어가:

> 게임이 날 죽였다.

가 아니라

> 거기서 너무 힘을 줬다.

> 조금 더 쉬었어야 했다.

> 저 발판을 지나치면 안 됐다.

라고 생각해야 한다.

따라서:

- 숨겨진 확률 즉사 금지
- 예고 없는 강풍 금지
- 보이지 않는 낙석 금지
- 강제 실패 이벤트 금지

---

# 105. 이상적인 30초 플레이

고도:

```text
437m
```

상태:

```text
STAMINA 72

SLIP 5

VELOCITY 0.55
```

앞에 급경사.

플레이어가 평지에서 Shift.

```text
0.55
→
0.9
→
1.25
```

경사 진입.

Shift 해제.

관성 사용.

```text
1.25
1.05
0.82
0.61
```

중간부터 자갈.

Slip:

```text
15
28
43
61
```

힘을 줄인다.

Slip 감소.

호흡:

```text
후우—
```

다음 돌턱에서 Shift.

```text
쿵
```

돌턱 통과.

하지만 Slip:

```text
83
```

힘을 빼지만 돌이 멈추기 시작.

```text
0.3
0.1
-0.15
```

Space.

버티기.

```text
-0.15
-0.08
0
```

Stamina:

```text
34
```

3m 앞 안전 발판.

마지막 힘으로 밀어 넣는다.

돌 고정.

시지프스가 돌에 기대어 숨을 쉰다.

Stamina 회복.

그리고 카메라 너머로 다음 능선이 보인다.

이 30초가 재미있어야 한다.

---

# 106. MVP 범위

첫 번째 실제 플레이 빌드에서는 다음까지만 만든다.

```text
산 1개

Path 기반 돌 이동

Push

Shift Burst

Momentum

Stamina

Slip

Brace

부분 추락

Runaway

바위 / 자갈 / 진흙 / 젖은 바위

급경사

돌턱

발판

고도 UI

Camera

기본 Sound
```

이 시점에는:

- 로그라이크
- 이벤트
- 철학
- 기억
- 엔딩

을 넣지 않는다.

---

# 107. MVP 성공 기준

10명의 테스트 플레이어 기준으로 다음 현상이 나타나야 한다.

### A

플레이어가 자연스럽게 Shift를 계속 누르면 위험하다는 것을 이해한다.

### B

한 번 이상 돌을 미끄러뜨렸다가 직접 복구한다.

### C

다음 발판을 자신의 목표로 삼는다.

### D

실패 후:

> 한 번만 더.

라는 생각이 든다.

### E

다른 사람의 추락 장면을 보는 것도 재미있다.

이 중 4개 이상이 충족되지 않는다면 메타 시스템 개발을 보류한다.

---

# 108. Phase 2

MVP 재미 검증 성공 후 추가.

```text
Chunk 랜덤 조합

Weather

Visual Zone

최고점 흔적

부분 Procedural Generation

호흡 Timing

고급 지형
```

---

# 109. Phase 3

다음으로:

```text
Memory

Meta Upgrade

Save

Run Result

Progression
```

추가.

---

# 110. Phase 4

마지막에:

```text
Event

Philosophy

Narrative

Fake Summit

Ending

True Ending
```

추가.

---

# 111. 개발 우선순위

가장 먼저 만들어야 할 코드는:

```text
1. MountainPath

2. Boulder Distance Movement

3. Slope Calculation

4. Push

5. Momentum

6. Gravity

7. Stamina

8. Slip

9. Brace

10. Partial Fall

11. Runaway
```

여기까지가 사실상 게임의 심장이다.

---

# 112. 핵심 검증 장면

개발 중 언제든 테스트할 수 있도록 별도의 Debug Mountain을 만든다.

```text
평지

↓

20° 경사

↓

안전 발판

↓

자갈 30°

↓

돌턱

↓

35° 경사

↓

좁은 발판

↓

젖은 바위 30°
```

약 90초짜리 테스트 코스.

새로운 밸런스를 적용할 때마다 이 코스를 플레이한다.

---

# 113. Debug UI

개발 빌드에서 F3:

```text
DISTANCE

VELOCITY

ACCELERATION

SLOPE

PUSH FORCE

GRAVITY FORCE

STAMINA

SLIP

SURFACE

RUN STATE
```

표시.

Release Build에서는 제거.

---

# 114. 개발상 가장 중요한 수치

초기 튜닝에서는 다음 다섯 개를 집중적으로 조정한다.

```text
PushForce

GravityStrength

MomentumBonus

SlipGain

BraceForce
```

게임의 손맛 대부분이 이 다섯 값으로 결정된다.

---

# 115. 하지 말아야 할 것

초기 개발 중 다음 기능은 추가하지 않는다.

```text
전투

아이템 파밍

장비 등급

랜덤 무기

상점

퀘스트 로그

제작

스킬 슬롯

펫

복잡한 NPC 시스템

온라인 기능
```

게임의 본질이 약해질 가능성이 높다.

---

# 116. 최종 게임 구조

플레이어의 경험 변화는 다음과 같아야 한다.

### 첫 30분

> 돌이 왜 이렇게 무거워?

### 1시간

> 여기선 관성을 유지해야 하는구나.

### 3시간

> 저 경사 전에 체력 좀 채워야겠다.

### 5시간

> 비 오는 날 이 길은 위험한데 다른 루트가 있나?

### 후반

> 이번에는 정상보다 저쪽 길로 가보고 싶다.

### 엔딩 이후

> 얼마나 올라왔는지는 이제 별로 중요하지 않다.

---

# 117. 게임 디자인 핵심 원칙

## 미시적 진행은 명확하게 한다.

현재 속도.

현재 스태미나.

현재 위험.

다음 발판.

현재 고도.

모두 플레이어가 이해할 수 있어야 한다.

## 거시적 진행은 의도적으로 흐리게 한다.

정상까지 거리.

산의 전체 크기.

남은 구역.

최종 RUN 수.

모두 감춘다.

---

# 118. 프로젝트를 한 문장으로 정의하면

**《시지프스》는 돌을 정상까지 밀어 올리는 게임이 아니라, 언제 밀고 언제 버티며 언제 힘을 빼야 하는지를 배우는 게임이다.**

그리고 그 과정을 수없이 반복하다 보면,

처음에는 정상만 바라보던 플레이어가 점점

**‘올라가는 행위 자체’를 플레이하게 되는 것.**

그것이 이 게임의 최종 목표다.