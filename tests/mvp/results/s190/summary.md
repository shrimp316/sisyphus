# MVP 석판 효과와 S190의 제한된 비교

같은 clear 날씨·generation6·시드101/202/303과 두 회복 대응 정책을 사용했다. 관문 진입36회와 0m 전체 경로36회를 분리한다. 실제 지갑 지급·구매 API로 고정 빌드를 만들었지만 준비용 거리 지급은 인공 fixture다. 자연 XP 캠페인이나 인간 플레이 결과가 아니다.

S190의 환경 회복 기회는80/7초, 초당7이며 기존 BRE01 배율을 받는다. BRE05/07/10 등 신규 능력의 추가 회복은 환경 할당과 별개다. 기존 무강화 불가능 증명을 성장 빌드에 재사용하지 않는다. 두 정책 모두 v0.3의 별도 regular_recovery/skilled_recovery이며 일반 regular/skilled 정책과 합치지 않는다.

| 출발 | 빌드 | EXP | 정책 | 목표 도달 | 평균 최고점 | 성공 조건부 시간(초) |
|---|---|---:|---|---:|---:|---:|
| 750m 진입 | zero | 0 | regular_recovery | 0/3 | 869.34 | — |
| 750m 진입 | zero | 0 | skilled_recovery | 0/3 | 886.53 | — |
| 750m 진입 | balanced18 | 1200 | regular_recovery | 0/3 | 914.94 | — |
| 750m 진입 | balanced18 | 1200 | skilled_recovery | 0/3 | 931.12 | — |
| 750m 진입 | strength18 | 1660 | regular_recovery | 0/3 | 925.94 | — |
| 750m 진입 | strength18 | 1660 | skilled_recovery | 0/3 | 937.31 | — |
| 750m 진입 | endurance18 | 1660 | regular_recovery | 0/3 | 912.09 | — |
| 750m 진입 | endurance18 | 1660 | skilled_recovery | 0/3 | 933.91 | — |
| 750m 진입 | breath18 | 1660 | regular_recovery | 0/3 | 905.15 | — |
| 750m 진입 | breath18 | 1660 | skilled_recovery | 0/3 | 924.34 | — |
| 750m 진입 | all30 | 3840 | regular_recovery | 3/3 | 940.00 | 127.84 |
| 750m 진입 | all30 | 3840 | skilled_recovery | 3/3 | 940.00 | 125.07 |
| 0m 출발 | zero | 0 | regular_recovery | 0/3 | 874.42 | — |
| 0m 출발 | zero | 0 | skilled_recovery | 0/3 | 886.16 | — |
| 0m 출발 | balanced18 | 1200 | regular_recovery | 0/3 | 919.72 | — |
| 0m 출발 | balanced18 | 1200 | skilled_recovery | 0/3 | 931.82 | — |
| 0m 출발 | strength18 | 1660 | regular_recovery | 0/3 | 931.42 | — |
| 0m 출발 | strength18 | 1660 | skilled_recovery | 1/3 | 957.68 | 632.37 |
| 0m 출발 | endurance18 | 1660 | regular_recovery | 0/3 | 917.91 | — |
| 0m 출발 | endurance18 | 1660 | skilled_recovery | 0/3 | 934.15 | — |
| 0m 출발 | breath18 | 1660 | regular_recovery | 0/3 | 909.37 | — |
| 0m 출발 | breath18 | 1660 | skilled_recovery | 0/3 | 924.35 | — |
| 0m 출발 | all30 | 3840 | regular_recovery | 3/3 | 1000.00 | 626.57 |
| 0m 출발 | all30 | 3840 | skilled_recovery | 3/3 | 1000.00 | 628.40 |

진입 fixture의 목표는940m이며 정상 완주가 아니다. 전체 경로의 목표는1,000m다. 실패는 시험한 유한 정책의 실패이며 특정 노드의 필요조건을 증명하지 않는다.18노드 구성끼리도 balanced18은1,200EXP, 집중 구성은1,660EXP로 비용이 같지 않다. 미세 입력 최적화나 광범위 시드 안정성은 조사하지 않았다.

압축 원시 입력72개의 SHA·step·명령 범위, 실제 구매 노드수·지출, 환경 기회시간 보존을 검증했다. 능력별 inertia/rescue 카운터는 전체 회차, gate core/environment 회복량은 관문 내부 범위다. 상세 수치는 summary.json과 results.jsonl에 보존했다.

## 호흡 계열 제거 대조

근력10·지구력10을 고정하고 호흡10개를 제거한 추가6회는5/6 완주, 기준30노드는6/6 완주였다. 양쪽 완주한5쌍에서는 호흡 제거가1.27~4.16초 느렸다. 일반 회복 대응 정책 seed303은 제거 시939.84m에서 실패했다.

환경으로 실제 회복한 양은84→80으로 감소했고, 기준의 관성 회복은 전체 회차0~2였다. 이6개 기준 회차에서 BRE10 구제는 사용하지 않았다. 계열 전체를 제거한 비교여서 개별 노드 하나의 효과로 단정하지 않는다. 투자도3,840→2,560EXP로 줄었으므로 같은 예산 배분 비교가 아니다. 호흡의 실효 증거지만 필수성이나 인간 성과의 증명은 아니다. 상세는 ../s190-breath-ablation/summary.json에 보존했다.
