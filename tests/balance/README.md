# 1막 현재 성장·난이도 실험

이 실험은 **현재 구현된 `Progression`과 세 가지 일반 강화만** 측정한다. 배포용 물리와 저장 파일은 변경하지 않는다. 미구현 숙련의 석판, EXP 소비 재화, 특수 능력, 프레스티지는 실험에 포함하지 않는다. 결과는 명시된 자동 입력 정책의 결과이며 인간 집단의 완주율이나 플레이 시간을 뜻하지 않는다.

## 이번에 실제로 실행한 결과

[분석 보고서](../../docs/act1-balance-report.ko.md) · [전체 집계 JSON](results/analysis/summary.json) · [XP·레벨 CSV](results/analysis/xp_events.csv)

본 예비 실험은 단일 등반 300회와 캠페인 12개의 87회 등반, 총 387회다. 사후 진단 6회를 별도로 실행해 최종 집계는 **393회 등반·303개 단일 등반·15개 캠페인**이다. 캠페인 안의 등반은 90회이며 고유 산 seed는 32개다. 사후 진단은 후보 3종의 실제 레벨업과 성공한 캠페인 산의 초기 강화 차이를 확인한 것으로, 독립적인 확증 표본이 아니다. 100seed full 설정은 실행하지 않았다.

원시 결과는 `results/current-pilot/results.jsonl`과 `results/followup/results.jsonl`, 각각의 실행 증거는 `manifest.json`에 있다. 최종 집계를 다시 만들려면 두 JSONL을 함께 전달한다. 기존 회귀 336개·새 Godot 하네스 43개·Python 집계 검사 13개가 통과했다. 범위 수정 전 실행은 결과에 포함하지 않는다.

## 실행

프로젝트 루트에서 Python 3.11 이상과 프로젝트에서 사용하는 Godot 4.5.1로 실행한다. Python 외부 패키지는 필요하지 않다.

선택적인 `plot_results.py` 그림 생성만 `matplotlib`이 필요하다. 시뮬레이션과 통계 집계에는 필요하지 않다.

```powershell
# 작은 실행 확인
python tests/balance/run_experiments.py --engine .tools/godot/Godot_v4.5.1-stable_win64_console.exe --config tests/balance/experiments_smoke.json --output-dir tests/balance/results/smoke-new --workers 1

# 예비 실험 전체: 300개 단일 등반 + 12개 반복 도전 시작점
python tests/balance/run_experiments.py --engine .tools/godot/Godot_v4.5.1-stable_win64_console.exe --config tests/balance/experiments_pilot.json --output-dir tests/balance/results/current-pilot-new --workers 3

# 완료한 실측 JSONL만 집계
python tests/balance/analyze.py tests/balance/results/current-pilot-new/results.jsonl --output-dir tests/balance/results/current-analysis-new

# 통계 집계 검증. 이 테스트의 합성 fixture는 실측 결과가 아니다.
python -m unittest discover -s tests/balance -p test_analyze.py -v

# 현재 구현 전용 하네스 검증
& .tools/godot/Godot_v4.5.1-stable_win64_console.exe --headless --path . --script tests/balance/verify_harness.gd

# 제공한 최종 원시 결과 재집계
python tests/balance/analyze.py tests/balance/results/current-pilot/results.jsonl tests/balance/results/followup/results.jsonl --output-dir tests/balance/results/reanalysis

# 선택적인 그림 생성
python tests/balance/plot_results.py tests/balance/results/analysis/summary.json tests/balance/results/baseline-new.png
```

Godot 직접 실행도 가능하다.

```powershell
& .tools/godot/Godot_v4.5.1-stable_win64_console.exe --headless --path . --script tests/balance/simulator.gd -- --config tests/balance/experiments_smoke.json --output tests/balance/results/direct-smoke.jsonl
```

기존 출력 폴더는 runner가 덮어쓰지 않는다. 새 폴더를 사용한다. runner는 seed 단위 작업을 worker에 분배하고 Windows에서는 창을 숨겨 실행한다. 각 worker JSONL은 즉시 flush되지만, 전체 worker 종료 코드·로그·예상 종료 표본 수·실행 전후 소스 해시가 확인되어야 `results.jsonl`이 만들어진다. 실행 중 simulator, controller, 정책, production script, 지형 `.tres`를 수정하면 병합을 거부한다. runner의 wall-clock 제한은 worker당 기본 4시간이며, 게임 안의 시간 제한과 별개다.

`manifest.json`에는 실행 명령, worker별 실제 등반 수, wall time, 설정 및 의존 파일 SHA-256을 보관한다. Godot JSONL metadata에는 엔진 버전, Git revision, 정책, 설정과 측정 의미를 저장한다. 결과를 재현할 때 해당 엔진 버전과 소스 해시를 맞춘다. Godot RNG는 엔진 버전 간 동일 수열을 보장하지 않는다. 공식 참고: [CLI](https://docs.godotengine.org/en/4.5/tutorials/editor/command_line_tutorial.html), [RandomNumberGenerator](https://docs.godotengine.org/en/4.5/classes/class_randomnumbergenerator.html).

## 실험 설계

| 설정 | 조건 | 예비 표본 수 |
|---|---|---:|
| `experiments_baseline_pilot.json` | 4정책 × 세 강화 각각 0/3/5/8/10 × 3산 seed | 60 |
| `experiments_isolated_pilot.json` | 4정책 × 힘/최대스태미나/회복 한 계열만 5/10 × 3seed | 72 |
| `experiments_candidates_pilot.json` | 보수/균형/높은 난이도 × 4정책 × 각각 0/8 × 3seed | 72 |
| `experiments_sensitivity_pilot.json` | 8개 단일 변수 × 일반/숙련 × 각각 0/8 × 3seed | 96 |
| `experiments_campaigns_pilot.json` | 4정책 × 3강화 전략 × 1시작 seed | 12 캠페인 |
| `experiments_pilot.json` | 위 설정을 합친 예비 실험 | 312 시작 표본 |
| `experiments_full.json` | 조건별 100seed, 단일 계열 3/5/8/10 포함 | 13,600 시작 표본 |

설정에 존재하는 표본 수는 **실행 계획**이다. 실제 수행 수는 완료한 dataset manifest와 집계의 `observed_counts`로 판단한다. 100seed full 설정을 제공했다는 이유로 실행했다고 보고하지 않는다. 캠페인은 여러 등반을 포함하므로 실제 등반 수는 시작 표본 수보다 클 수 있다.

예비 단일 등반 seed는 `[101,202,303]`, 캠페인 시작 seed는 `[101]`이다. full은 `[1001,...,1100]`을 파일에 명시했다. 캠페인 재도전 산 seed는 `1 + ((시작seed-1 + 회차인덱스*104729) mod 2147483646)`이며 실제 값은 `run_seeds`에 저장한다. 정책 오류 RNG는 산 RNG와 분리된다.

단일 등반 상한은 1,800초다. 캠페인은 10,800초 또는 30회차, 최초 정상 도달 중 먼저 발생하는 조건에 종료한다. 단일 등반 timeout은 자연 추락으로 바꾸지 않으며 캠페인도 그 시점에서 중도절단한다. 일반 추락에만 새 산을 생성하고, 최고 기록·누적 XP·강화는 유지한다. 메뉴, 로딩, 사람의 구매 고민 시간은 누적 플레이 시간에 포함되지 않는다.

## 실제 성장의 의미

현재 효과는 힘 rank당 추진 배율 +2%, 지구력 rank당 최대 스태미나 +2%, 회복 rank당 회복 배율 +2%다. 각 rank는 0~10이다. 단일 등반의 지정 rank는 효과를 분리하기 위한 fixture이며, 그 등반에서 실제 XP를 획득해 구매한 것으로 취급하지 않는다. `ranks_are_fixture`와 `growth_id`로 구분한다. 단일 계열 비교의 0rank 대조군은 baseline을 사용한다. 예비 실험에서 단일 계열 중간 rank 3/8은 측정하지 않으며 full 설정에만 있다.

반복 도전은 rank 0과 XP 0에서 시작해 현재 `Progression.award_distance()`와 `choose()`를 사용한다. 이번 회차에서 최초 50m 구간당 20XP, 개인 최초 기록 구간당 10XP를 받는다. 왕복으로 동일 구간을 다시 지나도 추가 XP는 없다. XP는 소비하지 않고 레벨업 포인트를 지급한다. 최대 누적 XP는 6,150, 최대 레벨은 31이다.

누적 강화 포인트 `p`에 필요한 XP는 `60*p + 5*p*(p-1)`이다. 따라서 세 계열 각각 rank8에 필요한 최소 누적 XP는 4,200, 각각 rank9는 5,130이다. 이는 현재 일반 강화의 레벨업 임계치이며 향후 소비형 비용이 아니다. 실제 강화 선택은 쉼터에서 속도 절댓값 0.05m/s 이하일 때만 가능하다. XP가 충분해도 정차하지 못하면 미사용 포인트가 남을 수 있다.

전략은 균등(가장 낮은 rank 우선), 추진 중심(힘10→지구력10→회복10), 안정 중심(지구력·회복을 힘보다 약 3rank 앞서게 배분)이다. 동률 선택 순서도 코드에 고정되어 있다. 구매 및 선택 기록은 `purchases.csv`, 50m별 XP·레벨 변화는 `xp_events.csv`, 회차 끝 곡선은 `xp_curve.csv`로 확인한다.

## 입력 정책과 한계

정책 설정은 `policies.json`, 입력 결정 로직은 `simulator.gd`의 `decide()`다. 입력은 다음 판단까지 유지한다. 오류는 매 판단 시 독립 확률로 쉬기/힘주기/버티기 중 하나를 선택하며 정상 결정과 우연히 같을 수 있다.

| 정책 | 명목 판단 주기 | 판단당 오류 확률 | 특징 |
|---|---:|---:|---|
| novice | 0.55초 | 9% | 낮은 스태미나까지 힘주기, 늦은 후퇴 대응 |
| regular | 0.25초 | 2.5% | 스태미나·Slip 기준, 쉼터 회복, 돌턱 앞 힘주기 |
| skilled | 0.12초 | 0.8% | 경사·속도·돌턱을 고려한 힘주기 제한 |
| optimized | 1/120초 | 0% | 정확한 상태와 힘 조건을 사용한 비현실적 조작 |

주기는 1/120초 정수 tick으로 반올림되므로 숙련의 실제 주기는 14/120초다. 실제 주기는 결과의 `decision_cadence_seconds`에 저장된다. optimized는 인간용 난이도 평가와 분리해야 한다. 완주하면 그 정책의 실행 가능성을 입증하지만, 실패한다고 물리적 불가능을 입증하지는 않는다. 이름이 숙련이라고 항상 일반보다 더 잘하는 것도 보장하지 않는다. 정책은 인간 데이터에 보정하지 않은 휴리스틱이다.

모든 적분과 판정은 production `BoulderController`를 상속해 실행한다. `balance_controller.gd`는 테스트용 경사 스태미나 배율 hook만 추가한다. 산 생성도 실제 `MountainManager`를 사용한다. 신규 지형 generation6이 기본이며 저장 파일을 읽거나 변경하지 않는다. 구세대 지형 비교는 명시적인 generation 설정/검증을 사용하고 신규 seed 결과와 혼합하지 않는다.

`feasibility.gd`와 `candidate_feasibility.gd`는 완전 회복 상태의 한 스텝 출발/돌턱 탐침이다. `ledge_diagnostics.gd`는 본 실험에서 반복 막힌 상태와 별도 초기 조건을 비교한다. 이들은 전체 경로 통과 가능성을 증명하지 않는다. 각 스크립트를 `--headless --path . --script tests/balance/<이름>.gd`로 실행하면 `results/`의 해당 진단 JSON을 갱신한다.

## 통계·출력 해석

`summary.json`과 CSV에는 표본 수, 평균, 중앙값, p25/p75/p90을 저장한다. 분위수는 `(n-1)*p` 선형 보간이다. 완주율은 제한시간 내 성공 비율이며 중도절단도 분모에 남긴다. Wilson 95% 구간을 함께 제공한다. 3seed에서 0/3 또는 3/3은 모집단 확률 0%/100%라는 뜻이 아니다. 캠페인 1seed는 전략 간 분산을 평가하기에 부족하다.

- `metrics.csv`: 단일 조건/캠페인 조건별 통계. 완료 시간 평균은 성공 표본만 사용한다. 모든 표본의 관찰 시간 평균과 구분한다.
- `bands.csv`: 250m 구간별 도달 수·최초 통과 시간·후퇴·위험·쉼터 체류. `terminal_origin_in_this_band`는 해당 구간에서 시작한 추락, `eventual_fall_after_reaching_band`는 그 구간 도달 후 이후 어디서든 발생한 추락이다. timeout은 추락으로 세지 않는다.
- `terrain.csv`: 노면×경사 구간별 이벤트 수와 실제 노출 1시간당 빈도. 관찰되지 않은 노면이나 짧은 노출을 위험 순위로 과해석하지 않는다.
- `xp_events.csv`: 회차 내 최초 50m 보상마다 시간, 도달 거리, 획득 XP, 누적 XP, 레벨, 미사용 포인트.
- `xp_curve.csv`, `fall_xp.csv`: 회차별 누적 성장 곡선과 추락 표본의 최고 거리·보상. 추락 위치와 최고 도달 거리는 서로 다르다.
- `growth_thresholds.csv`: 캠페인에서 세 계열 모두 목표 rank에 도달한 실제 시각. 도달하지 못했으면 null/빈 값이며 0초가 아니다.
- `current_xp_thresholds.csv`: 현재 레벨1~31의 정확한 XP 임계치.
- `paired_comparisons.csv`: 같은 정책·산 seed·날씨·세대끼리 비교한 차이. 성장 효과는 무강화 baseline, 난이도 후보는 동일 성장 baseline과 비교한다. 시간 차이는 두 표본 모두 완주했을 때만 계산한다.
- `current_xp_rate_projections_NOT_measured.csv`: 관찰된 XP/시간이 계속 일정하다고 가정한 단순 선형 환산. 실제 목표 rank 도달 시간과 혼동하지 않는다. 성장·최초 기록 보너스·XP상한·선택 기회가 바뀌므로 외삽은 제한적이다.
- `first_summit_curve.csv`: 캠페인 Kaplan–Meier 곡선. 정체 timeout은 비정보적 중도절단 가정을 위반할 수 있다. 작은 표본을 인간 첫 완주 시간 분포로 해석하지 않는다.

구간/노면 노출과 후퇴 거리에는 runaway 이후 연출을 제외한다. 총 등반 시간에는 연출이 포함되며 `fall_animation_seconds`·`fall_descent_m`로 따로 기록한다. 쉼터 체류는 통과 시간을 포함하고, `shelter_rest_seconds`는 정차해 입력을 놓은 시간이다. 방문당 체류/휴식은 pooled 총시간÷총방문수다. Slip·고갈·돌턱 막힘은 에피소드 수다. `failure_association_counts_NOT_causal`는 종료 전 시간상 연관이며 인과관계를 증명하지 않는다. 없는 계측 값은 null로 남긴다.

집계는 캠페인의 여러 회차를 서로 독립된 완주 표본으로 합치지 않는다. 같은 job/seed/run을 중복 입력하면 거부한다. 실제 강화가 아닌 mode, schema2 이전 metadata도 거부한다. 범위 변경 전에 시작한 결과는 `.tools/balance-superseded/`에 보존하며 최종 dataset에서 제외한다.

## 후보 계수

모든 후보는 테스트 인스턴스의 값만 변경한다. 단일 변수 실험은 추진 -5%, 경사 +1°, 접지 -5%, Slip 증가 +10%, 경사 스태미나 소비 +10%, 돌턱 요구 +5%, 쉼터 길이6m, 받침 제거를 각각 적용한다. Slip 감소 속도는 현재 hook에 없어 측정하지 않는다.

| 후보 | baseline 대비 변경 | 검토할 위험 |
|---|---|---|
| 보수 | 경사+0.3°, 경사 소비×1.03 | 적은 차이가 정책 잡음에 묻힐 수 있음 |
| 균형 | 추진×0.98, 경사+0.7°, 소비×1.05, Slip증가×1.05, 돌턱×1.03 | 초반부터 동시 부담 증가 |
| 높은 난이도 | 추진×0.96, 경사+1.2°, 소비×1.10, Slip증가×1.10, 돌턱×1.05, 쉼터6m | 회복 부족과 정체·불가능 구간 위험 |

위 표는 실험 가설이며 채택 권고가 아니다. `push_scale`은 플레이어 추진 배율만 바꾸며 돌턱 기준의 `BASE_PUSH` 상수는 바꾸지 않는다. `slip_scale`은 노면의 Slip 증가분만 바꾸고 감소 속도는 유지한다. `drain_scale`은 경사 소비 배율이다. 경사 offset은 청크 시작/끝 경사에 적용하며 쉼터 평탄 구조는 실제 생성 경로를 사용한다. 결과·물리 가능성 점검·인간 플레이테스트를 함께 보고 후보를 결정한다.
