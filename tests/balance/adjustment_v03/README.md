# v0.3 실험 분석 도구

Python 3.11 이상과 Godot 4.5.1을 사용한다. 처음 복제한 프로젝트는 Godot에서 한 번 열어 스크립트·리소스 import를 완료한 뒤 실행한다. 예시의 `.tools/godot/...exe`는 로컬 설치 경로이므로 자신의 엔진 실행 파일 경로로 바꿀 수 있다. Python 외부 패키지는 필요하지 않다.

production과 이전 결과를 수정하지 않는 별도 분석기다. v0.2의 읽기·분위수·Wilson 구간·기본 계측 CSV 행 함수를 재사용하지만, v0.2 집계 진입점은 호출하지 않는다. 기존 runner의 `--script`로 새 하네스를 실행하며 runner 자체는 수정하지 않는다. 대량 실행은 전체 실험 담당자가 조정한다.

```powershell
# 새로운 실행 폴더를 지정한다. script/config는 확정한 v0.3 파일을 사용한다.
python tests/balance/run_experiments.py --engine .tools/godot/Godot_v4.5.1-stable_win64_console.exe --script tests/balance/adjustment_v03/simulator.gd --config <확정-config.json> --output-dir tests/balance/results/act1-adjustment-v03/<새-실행> --workers 3

# 완료한 실행만 나열한다. 분석 출력은 실행 폴더와 별도 위치다.
python tests/balance/adjustment_v03/analyze.py tests/balance/results/act1-adjustment-v03/<완료-실행>/results.jsonl --output-dir tests/balance/results/act1-adjustment-v03 --evidence <완료한-독립증명.json>

python -m unittest discover -s tests/balance/adjustment_v03 -p test_analyze.py -v

# 작성자의 완료한 recovery-bound 자료와 독립 자원 부등식 대조
python tests/balance/adjustment_v03/verify_proof_review.py
```

`--evidence`는 반복 지정 가능하다. 해당 파일을 읽어 해시만 기록하며, 아직 없는 증명·결과를 생성하지 않는다. 실행 manifest가 `complete`가 아니면 입력을 거부한다. 출력에 다른 분석 계열의 manifest, 실행 manifest 또는 소유를 확인할 수 없는 기존 CSV가 있으면 덮어쓰지 않는다. `summary.md`는 분석기가 작성하지 않는다. 동일 v0.3 분석 폴더의 재집계는 가능하다.

## 결과와 표본의 의미

| 파일 | 내용 |
|---|---|
| `metrics.csv` | 고정 성장 단일 등반·독립 캠페인의 완주율, 검열, 시간·위험·XP 통계 |
| `bands.csv` | 200m와250m 두 구획의 도달·통과·위험·자원 노출 |
| `stamina.csv`, `slip.csv`, `terrain.csv` | 기존 계측 정의의 스태미나·Slip·후퇴·노면 노출 |
| `stalls.csv`, `replays/` | 실제 관측 정체와 원시 기록 발췌; 물리 불가능 판정 아님 |
| `gate_telemetry.csv` | 회차·관문별 원시 진입·통과·회복 예산과 입력 계측 |
| `gates.csv` | 관문별 진입 조건부 통과율과 자원 통계. 단일 등반과 캠페인 내부 회차 분리 |
| `xp.csv` | 실제 XP 지급과 캠페인 구매 사건. 미래 노드 지갑 계산 없음 |
| `unlock_geometry.csv` | 실제 segment와 미래250/500/750m 해금의 위치 충돌 검토. 미래 구매를 실행한 결과가 아님 |
| `first_attempt.csv` | 독립 캠페인의 첫 회차 및 명시한 첫 회차 성장 실험 |
| `ablations.csv` | `per_stat_ablation` 또는 `ablation_stat`으로 지정한 능력 비교 셀의 관측 통계 |
| `campaigns.csv` | 독립 캠페인별 실제 시간·회차·검열·성장 |
| `campaign_progression.csv`, `campaign-review.json` | 첫 회차250/750m XP, 첫 구매·재구매, 초기/정상 회차의 관문 진입 rank, 명시적 다음 회차 ledger 보존 확인 |
| `diagnostic_fixtures.csv`, `fixture_metrics.csv`, `fixture_gate_telemetry.csv`, `fixture_gates.csv` | 진입 상태를 설정한 국소 실험. `diagnostic_target` 도달율을 정상 완주율과 분리 |
| `manifest.json` | 원시 입력·의존 분석 코드·출력·추가 증거 해시, 실제 표본 수, 계측 metadata |

평균·중앙값·p25·p75·p90의 `n`은 유효 관측값 개수다. 결측을0으로 채우지 않는다. 성공 조건부 완주 시간에서 실패·시간제한은 제외하지만 완주율 분모에는 남긴다. 관문에 들어가지 못한 회차는 진입 조건부 통과율의 실패로 세지 않는다. 진입 전 사망·도달 실패는 전체 등반 결과에서 별도로 확인한다.

한 회차의 같은 관문 재진입은 `entries`에 기록하며, 관문 표본을 여러 개로 늘리지 않는다. 캠페인의 여러 회차는 상관된 관측이므로 관문 통과 비율에 독립 표본 Wilson 구간을 붙이지 않는다. 단일 등반·독립 캠페인 표본의 구간도 자동 정책과 지정 seed 분포의 실험 요약이며 인간 성공률이 아니다.

회복 기회는 환경의 유한 시간 할당이며 새 캐릭터 능력이 아니다. `seconds_budget`·`seconds_remaining`·`seconds_used`는 초, `recovered_amount`는 실제 회복량이다. 스태미나가 가득 차도 조건을 만족하는 입력 해제 시간은 할당을 소비하므로 `recovery_events`는 실제 양수 회복 사건만 세는 값이 아니다. 예산이 남았거나 출구 스태미나가 양수라는 사실만으로 안전한 후퇴·재진입을 보장하지 않는다. 유한 기회가 재진입·정체로 다시 채워지지 않는지는 별도 검증한다.

관문별 `entry_seconds`·진입 스태미나는 첫 진입, `exit_seconds`는 최초 전방 통과다. 시각은 모두 해당 회차 시작 기준이다. `entries`는 최초 진입을 포함한 총진입수이고, `entry_history`가 각 진입을 보존한다. XP 사건·구매의 `seconds`는 캠페인 누적 시각이므로 시각을 바로 비교하지 않는다. CSV는 원본 시각을 그대로 보존하며, 회차 시작 시각을 보정한 뒤 조인해야 한다.

`entry_seconds`는 물리 스텝 시작 상태보다1/120초 늦게 찍힌다. `exit_seconds-entry_seconds`로 구한 관문 통과 시간은 첫 스텝 직전부터 잰 시간보다 약8.33ms 짧다. 원시 시각을 바꾸거나 회차 전체시간을 보정하지 않는다. direct 계측은 누적 XP 상한6,150 뒤 획득0인50m 사건도 남길 수 있으므로, 분석기는 이를 `milestone_no_award`로 보존하고 양수 `xp_award`와 구분한다.

능력 제거 실험은 `ablation_stat`, `ablation_reference`, `growth_id`와 실제 rank를 설정에 명시한다. 서로 다른 ablation 요인은 같은 job 이름이더라도 분리한다. 분석기는 관측 통계를 출력하며, 투자량·seed·날씨·정책이 맞지 않는 셀에 인과적 효과나 임의의 상대 개선률을 붙이지 않는다. 일반 정책과 회복 대응 정책은 별도 policy 이름으로 비교한다.

`regular_recovery`·`skilled_recovery`는 기존 입력 주기·오류·버티기·Slip 대응·쉼터 휴식 기준을 유지한 별도 정책이다. 오르막에서 스태미나가 용량50%보다 적고 속도가0.9보다 크면 입력을 놓고, 그렇지 않으면 밀며 속도1 미만에서 Shift를 사용한다. 입력 해제 뒤 스태미나 증가가 관찰되지 않으면2초간 회복 시도를 쉬고 전진한다. 정확한 힘·미래 지형·남은 회복 할당은 읽지 않는다. 기존 네 정책과 동일한 정책으로 합치지 않는다.

직접 `_step_v02`를 호출한 자료는 `instrumentation_mode=direct_partial`, 관측 wrapper 자료는 `full_observer`로 분리한다. 직접 호출의 원시 입력 해시·gzip을 검증하며 생략된 bands·stamina·Slip 사건·정체 계측은 manifest에 결측으로 기록한다. `entry_fixture`가 있는 행, `diagnostic_target` 상태, metadata의 `stop_after_m`을 가진 작업은 전체 등반 분모에서 제외하고 진단 전용 CSV에 넣는다. 진입 fixture 없이0m에서 시작했어도 중간 종료 목표의 성공·시간제한을 전체 등반 성공률에 섞지 않는다. `diagnostic_target`은 지정 국소 거리 도달이며 `completed=false`를 유지한다. 관문을 통과했어도 정상을 완주했다고 세지 않는다.

## 증거 경계

v0.3은 source-derived 테스트 계측이다. 상속 metadata의 일반적인 controller 설명보다 실제 instrumentation의 원본·생성 소스 해시와 적용 계수가 우선한다. 정책 실패·정체·유한 입력 탐색 실패와 모든 허용 입력의 물리 불가능 증명을 분리한다. 진입 fixture의 성공도 0m에서 출발하는 전체 경로 성공과 다르다.

[독립 상한 검토](proof-review.md)는190m/B80·255m/B140 및 별도로 재계산한39°/114m/B0·39°/127m/B10·40°/125m/B10의 명시 조건에 한정한다. `verify_proof_review.py`는 정확한 유리수 경계648개, 반복 회복 스케줄120개와 최종 고갈을 검사하고 `proof-review.json`에 재계산값·검토대상 해시를 남긴다. 실제 게임·다른 조건·회복최소0·안전 퇴각에 자동으로 적용하지 않는다.

현재 XP는 누적 포인트 기준이다. 향후140개 노드, 영구 해금 자격, 프레스티지 초기화, 근력·지구력·호흡의 새 효과는 [설계 메모](design-notes.md)의 미구현 제안이다. 각8~9강을 첫 정상의 필수 기준으로 사용하지 않는다. 실제 획득 XP·현재 강화와 미래 지갑·노드 구매를 같은 측정 열에 섞지 않는다.

줄바꿈을 포함한 작업 폴더 바이트가 SHA-256의 대상이다. 생성 코드·정책·입력의 원시 해시와 Git 저장 시 정규화된 blob을 구분한다. 기존 runner의 실행 전후 소스 검사는 실제 checkout이 실행 동안 변하지 않았는지 검사한다. 분석 도구 수정 후에는 새 분석 코드 해시와 출력 해시가 남도록 재집계한다.

다른 경로로 복제한 저장소에서 원시 입력을 분석·재생할 때는 기록된 이전 머신의 절대경로 대신 `tests/balance/results/act1-adjustment-v03/` 이하 suffix를 현재 checkout에 연결한다. Windows 역슬래시는 정규화하고, `.`·`..` 성분이나 지정 폴더 밖으로 향하는 경로는 거부한다. 원시 JSONL의 경로 문자열과 파일 해시는 수정하지 않는다. 분석기의 `original_reference`는 원래 경로를 보존하고, 연결된 gzip의 압축 해시·해제한 입력 SHA-256·step 수를 다시 검증한다. v0.3 `replay.gd`도 같은 방식으로 경로를 찾는다. v0.2 도구는 변경하지 않았다.

## 실제 설정과 데이터셋 연결

아래는 설정·실행 방식·저장 위치의 연결이다. 실행 여부와 완료 횟수는 각 실행 manifest를 확인하며, 이 표에 이름이 있다는 사실만으로 완료로 간주하지 않는다. 완료 데이터만 최종 집계에 넣는다.

| 설정 (`adjustment_v03/` 기준) | script | 저장 폴더 (`results/act1-adjustment-v03/` 기준) | 의미 |
|---|---|---|---|
| `experiments_factors.json` | `diagnostic.gd` | `factors-pilot` | 진입 fixture 단일 요인·복합 가설 |
| `experiments_angle_followup.json` | `diagnostic.gd` | `angle-fixtures` | 39° 진입 fixture |
| `experiments_full_pilot.json` | `simulator.gd` | `full-pilot` | observer 포함 전체 경로·200/250m 계측 |
| `experiments_angle_full.json` | `diagnostic.gd` | `angle-full` | 직접 물리 호출 전체 경로, 일부 계측 결측 |
| `experiments_expansion.json` | `diagnostic.gd` | `expanded` | 선정한 고정 성장·정책 셀의 확대 표본 |
| `experiments_ablations.json` | `diagnostic.gd` | `ablations` | 다른 rank를 고정한 각 능력 기여 비교 |
| `experiments_campaigns.json` | `diagnostic.gd` | `campaigns` | 현재 XP와 구매 규칙의 독립 캠페인 |

`diagnostic.gd`라는 파일명만으로 모든 행을 진입 fixture로 취급하지 않는다. `entry_fixture`/`stop_after_m`이 없는 전체 경로·캠페인은 직접 호출 방식의 정상 표본이다. 물리 함수는 source-derived 생성 코드의 `_step_v02`이고, 입력 cadence와 오류는 각 정책 설정을 따른다. `simulator.gd`는 관측 wrapper를 통해 추가 계측하므로 그 mode와 분리한다.

예를 들어 전체 경로 파일럿을 다시 실행하려면 기존 결과가 없는 새 위치를 쓴다.

```powershell
python tests/balance/run_experiments.py --engine .tools/godot/Godot_v4.5.1-stable_win64_console.exe --script tests/balance/adjustment_v03/simulator.gd --config tests/balance/adjustment_v03/experiments_full_pilot.json --output-dir tests/balance/results/act1-adjustment-v03/rerun-full-pilot --workers 3
```

7개 실행이 모두 `complete`인 경우의 통합 집계 명령은 다음과 같다. 실제 검증 아티팩트는 `--evidence`로 추가한다.

```powershell
$v03Results = "tests/balance/results/act1-adjustment-v03"
python tests/balance/adjustment_v03/analyze.py `
  "$v03Results/factors-pilot/results.jsonl" `
  "$v03Results/angle-fixtures/results.jsonl" `
  "$v03Results/full-pilot/results.jsonl" `
  "$v03Results/angle-full/results.jsonl" `
  "$v03Results/expanded/results.jsonl" `
  "$v03Results/ablations/results.jsonl" `
  "$v03Results/campaigns/results.jsonl" `
  --output-dir $v03Results `
  --evidence "$v03Results/generated_controller.gd" `
  --evidence "$v03Results/proof-review.json" `
  --evidence "$v03Results/angle-bound-verification.json"
```

`factor-analysis`·`angle-analysis`·`full-analysis`는 단계별 집계 출력이며 원시 표본이 아니다. 이 CSV를 다시 입력하거나 국소 fixture를 전체 경로로 합치지 않는다. smoke·재생·독립 재검증 자료도 동일 입력의 반복 검증일 수 있으므로 최종 성공률 분모에 추가하지 않는다. 실행별 원시 입력과 최종 분석 코드는 각각 해시로 연결한다.
