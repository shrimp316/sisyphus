# 1막 난이도 조정 실험 v0.2

배포용 코드와 기존 결과를 보존하면서 쉼터 이동 중 회복(A), 중후반 연속 경사(B), 거리별 Slip 위험(C)을 실험한다. D 복합 후보는 A~C 실측 이후에 구성한다. 현재 세 강화의 2% 효과와 현재 XP·레벨업·쉼터 선택 규칙을 성장 비교 기준으로 사용한다. 숙련의 석판은 구현하지 않는다.

이번 목표는 **무강화 상태로 계속 등반하는 경우에는 완벽한 조작으로도 정상을 통과할 수 없고, 충분한 여러 성장 조합은 통과 가능한 구조**다. 이는 테스트 목표이며 아직 입증된 결과를 뜻하지 않는다. 앞선 명세의 “무강화 완주율 0%가 목표는 아님”보다 후속 사용자 지시가 우선한다. 성장 전에도 초반 통과·EXP 확보·안전한 강화·후퇴·회복·재시도 기회가 있어야 하며, rank를 직접 검사해 진행을 금지하는 장벽은 만들지 않는다.

다음 실험을 분리한다.

- `fixed_zero`: 무강화를 끝까지 유지하는 단일 등반.
- `first_attempt_growth`: 첫 회차 안에서 실제 XP로 강화하는 등반.
- `repeat_campaign`: 일반 추락 후 산을 새로 생성하고 실제 성장을 유지하는 반복 도전.
- `build_bottleneck`: 동일 포인트/여러 강화 조합의 병목 비교.

정책 실패, 제한시간 종료, 정체 감지는 **물리적 불가능의 증명과 별도**다. 정상에 도달한 실행은 그 조건의 가능성 증거지만, 어떤 정책도 통과하지 못했다는 결과만으로 불가능을 결론짓지 않는다. 물리 상한 계산·유한 입력 탐색·원시 재현 기록의 적용 범위를 각각 명시한다.

## 실행과 보존

원시 SHA-256은 줄바꿈을 포함한 파일 바이트에 민감하다. Windows에서 재현용 checkout을 만들 때는 `git -c core.autocrlf=false clone <저장소-URL> <새-폴더>`를 권장한다. controller factory가 검사하는 production 컨트롤러는 저장소의 LF 바이트로 유지해야 한다. `tests/balance/.gitattributes`는 기존 simulator를 `text eol=crlf`, runner를 `text eol=lf`로 지정하여 측정 당시 checkout의 줄바꿈을 재현한다. 새 v0.2 도구·결과에는 `-text`를 지정해 원시 바이트를 보존한다. production 파일의 속성이나 내용은 변경하지 않는다.

실행 manifest의 source SHA-256은 **측정 당시 작업 폴더의 바이트**를 뜻하며 Git blob 해시와 다른 개념이다. 기존 simulator는 Git에 LF로 저장되고 checkout에서는 CRLF로 재현된다. 일부 기존 production 리소스·스크립트도 측정 폴더에 CRLF로 존재했으므로, LF checkout의 원시 SHA-256이 실행 manifest와 다를 수 있다. 이는 내용 변경의 증거로 단독 해석하지 않으며, 줄바꿈을 정규화한 내용 대조와 원시 바이트 대조를 구분한다. 실행 전후 소스 불변 검사는 각 새 실행의 실제 checkout 바이트를 기준으로 수행한다. 생성 컨트롤러의 고정 원본 SHA-256 검사는 이 차이를 자동으로 허용하지 않는다.

프로젝트 루트에서 기존 runner에 새 script를 지정한다. 출력 폴더는 새 이름을 사용하며, 존재하면 runner가 거부한다.

```powershell
python tests/balance/run_experiments.py --engine .tools/godot/Godot_v4.5.1-stable_win64_console.exe --script tests/balance/adjustment_v02/simulator.gd --config <실험설정.json> --output-dir tests/balance/results/act1-adjustment-v02/<새-dataset> --workers 3

python tests/balance/adjustment_v02/analyze.py tests/balance/results/act1-adjustment-v02/<새-dataset>/results.jsonl --output-dir tests/balance/results/act1-adjustment-v02

python -m unittest discover -s tests/balance/adjustment_v02 -p test_analyze.py -v

# 독립 잠재량 경계 검사 5,760개 + 정확한 유리수 스태미나 DP
python tests/balance/adjustment_v02/verify_proof_review.py
```

집계 입력에 완료한 여러 `results.jsonl`을 나열할 수 있다. 미완료 worker 파일을 최종 결과로 합치지 않는다. 중복된 동일 job/seed/run은 기존 집계 검증에서 거부한다. 1차 목표는 조건당 10개 seed, 2차는 선정한 유망 조건당 100개 이상이다. 계획과 실측 횟수는 구분하고 실제 수행 범위는 `manifest.json`의 `observed_counts`와 각 실행 manifest로 확인한다. 자동 정책 표본은 인간 집단 표본이 아니다.

runner는 기본 하네스와 기존 CLI의 동작을 유지한다. 새 `--script`에서 문자열로 참조한 `res://` GDScript/JSON/리소스 의존성을 재귀적으로 해시하며 production script와 지형 리소스도 기록한다. 별도 검증·증명 도구는 실행 하네스에서 참조하지 않는 한 이 목록에 섞이지 않는다. 동적 파일명으로 읽는 새 의존성을 도입하면 runner의 해시 수집도 갱신해야 한다. 실행 전후 해시가 바뀌면 최종 병합을 거부한다. Windows worker는 창을 숨겨 실행하며, worker당 wall time 상한과 시뮬레이션 내부 상한은 서로 다르다.

기존 `tests/balance/results/`의 이전 dataset은 수정하지 않는다. 집계기는 `summary.md`를 생성하거나 수정하지 않으며 보고서 작성자가 실측 근거를 검토해 작성한다. 출력 위치에 runner manifest가 있으면 원본 실행 정보는 보존하고 `analysis` 항목을 추가한다.

## 계측과 실제 게임의 구분

v0.2의 변경은 테스트 하네스에서만 적용한다. production 적분·판정에서 파생한 계측 또는 테스트용 hook은 “그대로 실행한 production”과 구분해 기록한다. 후보 계수, 적용 거리, 지형 배치, 리소스 해시, 정책 설정은 원시 결과/manifest에 남긴다. 기존 `1/120초`, Slip `0.7초`, Runaway `-4m/s`, 돌턱 판정, XP 중복 방지, 정상·추락·저장 호환성은 별도 회귀 검사 대상이다.

`controller_factory.gd`는 production 컨트롤러 SHA-256과 계측할 코드 위치를 검사한 뒤 `_step_v02` 소스에서 지정한 계수 위치만 바꾼 테스트 클래스를 생성한다. 생성 함수는 production 소스를 바탕으로 계수를 변경한 **실험용 복사본**이며, 원래 함수의 직접 호출과 구분한다. 생성 소스는 `generated_controller.gd`, 원본·생성 해시와 치환 위치는 instrumentation metadata로 검토한다. 계수 1과 baseline 지형에서 production과 동등한 결과인지는 별도 검증해야 한다.

상속한 첫 metadata의 일반적인 `controller` 설명보다 별도 **instrumentation 블록이 우선**한다. 분석 manifest의 `controller_semantics`와 `metadata_precedence`도 이를 명시하며 생성 소스와 독립 proof-review 아티팩트의 해시를 보존한다. 독립 상한 검토의 승인 범위와 미입증 항목은 `proof-review.md`를 참조한다.

회복 감소는 우선 쉼터에서 이동하며 입력을 해제했을 때만 적용한다. 정지 회복은 별도 측정한다. 후보 B는 쉼터 간 거리와 실제 배치를 `geometry_layout`에 기록한다. Slip 위험은 실제 축적·감소에서 발생해야 하며 특정 위치에서 강제 이벤트를 주입하지 않는다. 정책은 입력 주기·오류·상태 접근을 기록하며, 120Hz 정확한 상태를 읽는 optimized 정책을 인간의 숙련으로 해석하지 않는다.

## 결과 파일

| 파일 | 의미 |
|---|---|
| `metrics.csv` | 조건별 단일 등반과 독립 캠페인의 완주율, Wilson 95% 구간, 시간·최고 거리·위험·XP 통계 |
| `bands.csv` | 같은 관측을 250m×4구간, 200m×5구역으로 각각 집계. `band_width_m`로 분리 |
| `stamina.csv` | 회차별 소비·회복·고갈 노출·평균 스태미나와 쉼터 방문별 입출구 상태·회복·정지 휴식 |
| `slip.csv` | Slip 개별 발생/회복 결과, 후퇴 복구 사건, 입력별 노출과 집계 |
| `stalls.csv` | 관찰된 정체 사건과 원시 replay 경로. 물리 불가능 판정은 포함하지 않음 |
| `campaigns.csv` | 독립 캠페인당 시간·회차·상태·성장·실제 사용 seed |
| `terrain.csv`, `geometry.csv` | 노면×경사×날씨별 이벤트/노출과 seed별 실제 구간·쉼터 배치 |
| `manifest.json` | 입력 파일 SHA-256, 실행 manifest, 원시 metadata, 실제 표본 수, seed, 집계 정의 |
| `replays/*.json` | 정체 당시 실제 입력 기록·물리 상태·산 배치와 원시 JSONL 출처 |
| `summary.md` | 실측과 별도 물리 증거를 함께 검토한 보고서; 집계기가 자동 작성하지 않음 |

`n`, 평균, 중앙값, p25·p75·p90은 기존 표준 라이브러리 통계 함수를 재사용한다. 시간 평균은 관찰 시간과 성공 표본의 완주 시간을 구분한다. 중도절단은 완주율 분모에는 남기되 자연 추락/Slip 이후 Runaway/복구 성공으로 바꾸지 않는다. Slip 복구 사건과 같은 회차 내 반복 이벤트는 서로 상관되므로 사건 비율에 독립 표본 Wilson 구간을 붙이지 않는다. 이벤트가 계측되지 않은 값은 null이며, 관측된 0과 구분한다.

250m와 200m 구간의 노출 합계를 서로 더하면 동일 시간을 이중 계산하게 된다. 각 구획은 독립된 관점이다. `eventual_fall_after_entry`는 해당 구간 도달 뒤 이후 어디에서든 발생한 추락, `terminal_origin_in_band`는 해당 구간에서 시작한 추락이다. 완료 회차와 검열 회차의 구간 통과 시간 표본 수가 다를 수 있다.

캠페인의 여러 회차를 독립 단일 등반 완주 표본으로 합치지 않는다. 사건 원시 로그에는 캠페인 식별자를 보존한다. 현재 구현의 총 XP는 소비 재화가 아닌 누적 레벨업 기준이다. 첫 회차 안에서 강화해 정상에 도달하는 경로와 최초 상태를 끝까지 고정한 경로를 같은 완주율로 합치지 않는다.

`gate_route.gd`의 이상적 전 경로 증거는 `policy_variant=gate_oracle_1p195`로 기본 optimized와 분리한다. 이 빠른 경로는 관측 wrapper를 생략하므로 일부 구간·스태미나·Slip 사건·정체 계측이 없다. 측정된 완주·시간·XP·위험 횟수는 포함하되, 빠진 계측은 manifest의 `partial_instrumentation_runs`에 명시하고 관련 CSV에서 제외하거나 `instrumentation_unavailable`로 표시한다. 결측을 사건0회로 바꾸지 않는다. 입력 해시와 정책 소스 해시가 있는 명시적 gate witness metadata만 이 부분 계측 형식으로 허용한다.

정체 기록은 설정된 관찰 창에서 진행이 부족했다는 사실을 뜻한다. `stalls.csv`의 `physical_proof_status=not_assessed`는 원시 기록만으로 증명하지 않았다는 표시다. replay는 기록된 시작/종료 상태와 입력 이력을 그대로 보존한다. 입력 탐색에 상한이 있다면 탐색 실패의 결론도 그 상한으로 제한한다. 성장 장벽 후보 채택에는 별도의 불가능 상한, 성장한 복수 빌드의 통과 실행, 장벽 이전 XP/안전 강화, 후퇴·회복 가능성의 증거가 필요하다.

후퇴 사건의 `recovered`는 속도가 다시 0 이상이 되었음을 뜻한다. 이전 위치를 되찾았거나 지속적인 전진에 성공했다는 뜻이 아니므로 집계에서는 `rollback_velocity_recovery`로 표시한다. 돌턱 앞 진동은 높은 속도복구 비율과 장시간 정체가 동시에 나타날 수 있다. Slip 복구도 차단 시간이 끝나고 속도가 0 이상인 상태를 뜻하며, 이후 안전을 보장하지 않는다. 정지 체류 시간 `stationary_seconds`는 입력 상태와 무관하고 `stationary_rest_seconds`는 입력을 놓고 쉬는 시간이다.

원시 JSONL의 정체를 재현하려면 다음처럼 실행한다. `replays/*.json`은 사건을 보존한 검토용 발췌이며 재생 도구의 입력은 원래 JSONL이다.

```powershell
& .tools/godot/Godot_v4.5.1-stable_win64_console.exe --headless --path . --script tests/balance/adjustment_v02/replay.gd -- --input <완료-dataset/results.jsonl> --job <job_id> --seed <seed>
```

최종 보고서의 집계 입력은 아래 7개다. 각 실행 manifest가 `complete`가 된 다음 실행한다. 초기 oracle 정책의 `gate-route-fixed.jsonl`, `gate-route-campaigns/`는 정책 결함의 보조 자료로만 보존하며 이 집계에서 제외한다.

```powershell
$v02Results = "tests/balance/results/act1-adjustment-v02"
python tests/balance/adjustment_v02/analyze.py `
  "$v02Results/abc-pilot/results.jsonl" `
  "$v02Results/d-pilot/results.jsonl" `
  "$v02Results/gate-pilot/results.jsonl" `
  "$v02Results/gate-campaigns/results.jsonl" `
  "$v02Results/gate-route-fixed-efficient-entry.jsonl" `
  "$v02Results/gate-route-campaigns-ledge-aware/results.jsonl" `
  "$v02Results/gate-expanded/results.jsonl" `
  --output-dir $v02Results
```

집계기는 oracle 입력 gzip을 해제하여 원시 입력 SHA-256과 step 수를 다시 확인하고, metadata에 보존한 정책 소스의 해시도 확인한다. 압축 파일 해시와 별도 증명·진단 자료 해시를 manifest에 남긴다. 0건인 `stalls.csv`는 사건을 만들어 넣지 않고 재생·기간·판정 열이 있는 헤더만 보존한다. D의 9개 캠페인도 독립 캠페인 표본에 포함하며, 각 캠페인의 1회차를 단일 고정 성장 표본에 중복 합산하지 않는다.
