# 검증 기록

## 2026-10-26 경사·후퇴·SLIP 강화

세대 6 새 산의 경사 증가, 후퇴 속도별 밀기 전달력 감소, SLIP의 1회 하강 충격·스태미나 손실을 검증했다. 상세 동작은 [밸런스 변경 안내](physics-balance.ko.md)를 참고한다. 기존 작업의 선택 쉼터 받침 배치를 보존했다.

신규 `physics_balance_verification.gd`는 115개 검사를 통과했다. 입력 해제 시 경사에 따른 가속, 역방향 관성 유지, Space 우선, SLIP 발동 프레임의 밀기 차단, 0.7초 잠금과 단발 비용, 소진, 폭주 전후 경계, 저장 복원 및 30/144 FPS 결과 일치를 확인했다. 48개 시드의 정상 높이 증가와 세대 1~6 저장, 명시적인 맑음·비 각각 16개 시드의 경사 상한·재현성도 확인했다. 변경 전 컨트롤러로 첫 103개 검사를 실행하면 28개가 실패해 새 동작을 구별함을 확인했다.

독립 검토에서 강제 날씨를 지형 생성 뒤에 적용하던 문제를 발견했다. 날씨를 생성 전에 확정하도록 수정하고 테스트를 추가했다. 지형 21개, 쉼터 통합 37개, 스태미나·버티기 124개, v0.2 핵심 25개, 성장 50개, 모션 29개, 웹 호환 24개도 통과했다. 잘못된 JSON을 주입하는 웹 저장 검사는 예상된 오류 로그를 포함한다.

GPU 돌 성장 검사 106개가 통과했으며, 경사와 쉼터 경계에서 캐릭터·돌의 표시를 캡처로 확인했다. 로컬 Web 릴리스 내보내기도 성공했다. 로그는 `.tools/balance-*.log`, `.tools/physics-balance-new.log`, 캡처는 `.tools/boulder-growth/`에 있다. 게임 난도의 체감은 실제 플레이로 추가 조정할 수 있다.

독립 검증자가 강제 날씨 수정 이후 v0.2 종합 검사를 다시 실행해 27개 모두 통과했다(`.tools/balance-final-v02.log`). 기본 능력치로 시드 1·42·1547의 맑음·비 여섯 경우 모두 정상 1000m에 도달했다. 위 최종 검사 집계는 GPU 검사를 채택하고 같은 항목의 헤드리스 중복 실행을 제외해 **558개 통과, 실패 0개**다.

## 2026-10-26 선택 쉼터 받침

새 산 생성 세대 5는 받침을 49.75m부터 100m 간격으로 949.75m까지 10개 배치한다. 쉼터 20개와 기존 경사는 유지한다. `shelter_verification.gd` 33개, `terrain_generation_tests.gd` 19개, `boulder_growth_verification.gd` 90개가 통과했다. 96개 시드의 배치·기존 지형 일치, 맑음·비와 기본·최대 강화에서 회수·일반 쉼터 통과·자연 감속·회복·폭주 우선순위, 모든 쉼터의 레벨업 선택, 생성 세대 1~5의 저장 복원, 새 등반 적용과 기존 돌 성장 보존을 확인했다.

```powershell
$shelterEngine = Join-Path $PWD '.tools/godot/Godot_v4.5.1-stable_win64_console.exe'
& $shelterEngine --headless --path . --script res://tests/shelter_verification.gd
& $shelterEngine --headless --path . --script res://tests/terrain_generation_tests.gd
& $shelterEngine --headless --path . --script res://tests/boulder_growth_verification.gd
```

로그는 `.tools/selective-*.log`에 저장했다. 새 통합 검사의 저장은 매번 `.tools/shelters-*`에 격리한다. `shelter_verification.gd`를 GPU에서 `--capture`로 실행하면 받침·일반 쉼터와 현재·최대 돌 크기의 화면 4장을 해당 폴더에 저장한다. 최초 저장 비교 검사에서 JSON 숫자 문자열 표현 차이에 따른 실패를 파싱값 비교로 수정했으며 재실행은 모두 통과했다. 실제 플레이의 난도·손맛은 별도 검증 대상이다.

별도 검증자가 v0.2 종합 quick 23개, 영구 성장 50개, 돌 성장 90개, 쉼터 GPU 37개를 직접 실행해 **200개 모두 통과**했다. 위 구현자 표적 검사 142개와는 일부 중복되는 별도 실행 결과다. 시드 42의 맑음·비 자동 등반은 모두 정상 1000m에 도달했으며 시뮬레이션 시간은 각각 912.28초·913.24초였다. GPU 화면 4장에서 받침 유무와 돌 확대 표시를 직접 확인했다. 캡처는 `.tools/shelters-9111077/`, 로그는 `.tools/verifier-shelter-gpu.log`에 있다.

Windows 실행 ZIP `builds/SISYPHUS-v0.2-Windows-20261026-203601-188230.zip`(55,187,295바이트)을 생성했다. 내보낸 실행 파일의 헤드리스 시작 검사도 오류 없이 통과했다(`.tools/shelter-package-smoke.log`). 공개 웹 배포는 이번 작업에 포함하지 않았다.

## 2026-10-26 회차 최고 고도에 따른 돌 외형 성장

돌의 외형을 이번 회차 최고 고도에 따라 최대 15% 확대한다. 저장된 `peak`를 이용하므로 저장 형식과 물리는 바뀌지 않는다. 캐릭터의 명목 손 접점은 실제 지면을 따라 탐색하며 발과 FX는 같은 지면 좌표를 사용한다. 프레임별 관절 변형을 추가한 것은 아니다.

최종 `boulder_growth_verification.gd --capture` 106개, 모션 29개, 영구 성장 50개, 웹 호환 24개가 모두 통과했다(총 209개). 크기 상한·고도 비율·왕복·저장 재개·새 회차 초기화·물리 불변과 0~45도 지형 및 쉼터 경계 접점을 검사했다. GPU 캡처 8장으로 같은 위치의 기본/최대 크기, 경계, 대체 렌더링을 비교했다. Web Release 내보내기도 성공했다.

첫 GPU 검사에서 테스트 종료 시 ObjectDB 경고가 발생해 노드 해제 후 프레임을 기다리도록 테스트를 수정했으며 최종 검사에서는 재현되지 않았다. 로그는 `.tools/boulder-growth-gpu-release.log`, `.tools/boulder-growth-*_verification.log`, `.tools/boulder-growth-web_compatibility_tests.log`에, 캡처는 `.tools/boulder-growth/`에 보관한다. 공개 브라우저 수동 플레이는 이번 검증에 포함하지 않았다.

## 2026-10-26 Slip 중 버티기 전용 구간

Slip 동안 남아 있던 10% 추진력을 제거하고 Space 유지로 버티도록 변경했다. 확대된 스태미나·버티기 검사는 수정 전 124개 중 4개 실패, 수정 후 124개 모두 통과했다. 실제 Slip 발생 시간, 밀기·Shift 차단, 종료 후 입력 재개, 30/144 FPS 일치를 추가로 확인했다.

기존 core 132개, v02 core 25개, 모션 29개, 종합 27개, 웹 호환 24개, GPU UI 25개를 포함해 총 386개 검사가 통과했다. GPU UI에는 화면 캡처 7개와 Slip 남은 시간·모션·안내 우선순위 검사가 포함된다. 별도 검토자가 코드·로그·카운트다운 캡처를 검토했다. 근거는 `.tools/slip-hold-*.log`와 `.tools/screenshots-v02/03a-slip-countdown.png`다. 공개 브라우저 수동 플레이는 이번 검증에 포함하지 않았다.

## 2026-10-26 스태미나 소진과 Slip 버티기 수정

`tests/stamina_brace_verification.gd`는 수정 전 컨트롤러에서 100개 중 56개 실패, 수정 후 100개 모두 통과했다. 물리 세대 1~4의 소진, 입력 유지 중 회복·추진 반복 방지, 키 해제 후 회복, 관성·중력 유지, Slip 중 Space 우선순위, 스태미나 비용, 저장 복원, 30/144 FPS 일치를 확인했다.

기존 core 132개, v02 core 25개, 성장 50개, 모션 29개, v02 종합 27개도 모두 통과했다. 종합 검사는 변경하지 않은 이전 저장 골든 상태 30개와 시드·날씨 조합 6개의 정상 등반을 포함한다. 별도 검토자가 코드와 실행 로그를 검토했다. 로그는 `.tools/stamina-brace-*.log`에 보관한다.

추가로 실제 Compatibility 렌더러의 UI 검사 11개, 웹 저장·라이프사이클 호환 검사 24개가 통과했다. 전체 398개 검사에서 실패 0이며 Web Release 내보내기도 성공했다. 이번 수정의 공개 브라우저 수동 플레이는 수행하지 않았다.

검증일: 2026-10-07. Godot `4.5.1.stable.official.f62fdbde1`, Windows, Compatibility 렌더러.

## 2026-10-26: 돌 이동과 발동작 동기화

`tests/motion_sync_verification.gd` 29개 검사 통과. 실제 이동량 비례, 정지·턱 막힘, 8/6프레임 동작 전환, 물리 결과 보존, 강화 선택 중 정지, 추락·회수·새 회차·저장 복원과 정상의 마지막 자세를 확인했다. GPU 실행은 속도 0/0.3/1/1.8m/s의 전후 화면 8장까지 총 37개 검사 통과. 기존 성장 50개와 에셋 59개 검사도 통과했다.

```powershell
$motionEngine = Join-Path $PWD '.tools/godot/Godot_v4.5.1-stable_win64_console.exe'
& $motionEngine --headless --path . --script tests/motion_sync_verification.gd
& $motionEngine --path . --rendering-method gl_compatibility --script tests/motion_sync_verification.gd -- --capture
```

저장은 `.tools/motion-sync-*`에 자동 격리된다. 이 모션 변경 당시 쉼터·받침 배치와 물리는 변경하지 않았다. 이후 적용한 [선택 받침 배치](shelter-balance-notes.ko.md)는 위 검증 기록을 참고한다.

## 2026-10-26: 구간 경험치와 영구 성장

- 성장·물리 강화·선택 입력·저장 이전 검사 50개 통과. 회차 내 중복 XP, 미사용 선택권 재접속, 강화 상한, 최대 스태미나 100 초과 복원, 버전 1~3에서 누락되거나 낮은 peak 처리도 확인했다.
- 기존 v0.2 물리 27개, UI 11개, 웹 저장 호환성 24개, 별도 프로세스 저장 이전·복원 9개 검사 통과.
- 실제 Compatibility GPU에서 경험치 HUD와 쉼터 선택 화면을 캡처해 확인했다. Web Release 빌드 성공. 실제 참가자의 성장 속도와 손맛은 추가 플레이 테스트 대상이다.

```powershell
$growthEngine = Join-Path $PWD '.tools/godot/Godot_v4.5.1-stable_win64_console.exe'
& $growthEngine --headless --path . --script tests/progression_verification.gd
# GPU 화면 확인: headless 없이 실행한다. 테스트 저장은 자동 격리된다.
& $growthEngine --path . --rendering-method gl_compatibility --script tests/progression_verification.gd -- --capture
```

## 2026-10-12: 암반 음영의 카메라 이동 회귀 검사

`tests/scenery_motion_verification.gd`는 암반 텍스처를 메모리에서 불투명 흰색 1×1 이미지로 바꾸어 그림의 무늬와 필터링을 제외하고 음영 변화만 측정한다. 시드 42의 175m·440m에서 경사와 쉼터 주변의 고정 월드 좌표 6곳을 선택하고, 맑음·비 각각 카메라 수평/수직 ±80px 이동과 줌 0.8 이후 같은 지점을 화면에 재투영한다. RGB 채널의 최대 차이 허용치는 `3/255`다. 플레이 저장이나 원본 PNG는 변경하지 않는다.

수정 전 렌더러는 이동 20개 조합 중 8개가 실패했으며 최대 차이는 `17/255`였다. 수정 후에는 **20개 조합 모두 통과**했다. 평행이동 16개 조합의 차이는 0, 줌 변경 4개 조합은 `1/255`였다. 별도 `scenery_verification.gd`의 정적·세로·축소·대체 렌더링 검사도 51개 검사와 13개 캡처에서 실패 0이었다. 이는 검사한 지점의 음영 안정성에 대한 근거이며 모든 장치에서 장시간 플레이를 검증한 결과는 아니다.

프로젝트 루트에서 GPU가 있는 환경으로 실행한다. 픽셀을 읽으므로 `--headless`를 붙이지 않는다. `--capture`를 생략해도 측정은 수행하며, 추가하면 비교 화면 24장을 저장한다.

```powershell
$sceneryEngine = Join-Path $PWD '.tools/godot/Godot_v4.5.1-stable_win64_console.exe'
& $sceneryEngine --path . --resolution 1280x720 --rendering-method gl_compatibility --log-file .tools/scenery-motion.log --script res://tests/scenery_motion_verification.gd -- --capture
```

측정값은 `.tools/scenery-motion-fixed/measurements.json`에 저장된다. `--baseline`은 개발 중 수정 전 코드와 비교하는 선택적 내부 모드다. 이 모드는 Git에 포함되지 않는 `.tools/scenery_visuals-motion-baseline.gd`가 필요하며, 해당 파일은 커밋 `2b0a388`의 `scripts/scenery_visuals.gd`에서 첫 줄 `class_name SceneryVisuals`만 제거한 복사본이다. 기본 실행에는 이 파일이 필요하지 않다. 내부 비교 결과는 `.tools/scenery-motion-baseline/`에 별도로 저장된다.

## 브라우저 Web 빌드

단일 스레드 Web Release 빌드를 로컬 HTTP 서버의 `/sisyphus/` 하위 경로에서 검증했다. 독립 웹 호환성 검사 24개와 데스크톱 UI 13개·저장 오류 처리 10개·별도 프로세스 재개 3개가 통과했다. 웹 저장·라이프사이클 처리와 기존 Windows 동작을 함께 확인했다.

실제 앱 내 Chromium 브라우저에서 게임 로딩, 한글 표시, Enter 시작, D 밀기, Esc 메뉴, 저장 버튼의 시작 화면 복귀를 확인했다. **41m에서 저장한 뒤 `/sisyphus/index.html`로 다시 접속하여 같은 지형·41m 위치로 재개**했다. 마지막 실행의 콘솔 오류·경고는 없었다. 캡처는 `.tools/web-browser-final.jpg`다.

검증 중 캔버스가 브라우저 전체 높이로 늘어나 게임이 잘리는 문제를 고정 1920×1080 캔버스와 반응형 CSS로 수정했다. 글꼴의 기본 굵기 100은 웹에서 400으로 지정했다. 브라우저 저장 보조 경로는 JavaScript의 전역 실행 문맥과 명시적 브라우저 전역 객체를 사용하도록 바꾼 뒤 실제 저장 성공과 재접속을 확인했다. 앞선 저장 실패의 정확한 문맥 원인은 확정하지 않았다.

GitHub Actions의 공식 Godot 다운로드 해시 검증, 최소 작업 권한, Web 배포 파일 범위와 라이선스 포함을 독립 검토했다. 공개 범위 승인 후 [shrimp316/sisyphus](https://github.com/shrimp316/sisyphus)에 게시했다. [첫 배포 작업](https://github.com/shrimp316/sisyphus/actions/runs/37604845759)은 커밋 `27bc98e`에서 빌드·배포 모두 성공했다.

공개 HTTPS 주소 **https://shrimp316.github.io/sisyphus/**에 실제 접속하여 게임 로딩, Enter 시작, Esc 메뉴, 저장 후 시작 화면 복귀를 확인했다. 새로고침 후 같은 산에서 '이어 오르기'가 표시됐다. 마지막 브라우저 콘솔 오류·경고는 없었다. 공개 페이지의 검증 화면은 `.tools/web-public-final.jpg`에 보관한다. 실제 청취 품질, 모바일 터치, 여러 브라우저와 참가자 10명의 재미 평가는 별도 검증 대상이다.

재현 명령은 [웹 실행·배포 안내](web-play.ko.md)에 있다. 독립 테스트는 `tests/web_compatibility_tests.gd`, 결과 로그는 `.tools/web-compatibility.log`에 있다.

## Windows 참가자 배포 준비

게임 물리는 변경하지 않고 설치가 필요 없는 Windows x86_64 Debug 배포본과 참가자 기록 도구를 추가했다. 이 단계는 실제 참가자 10명의 평가 완료를 뜻하지 않는다.

| 검증 | 결과 |
|---|---|
| Windows PowerShell 5.1 실행 도구 검사 | 구현자 25개 통과 |
| 실행 도구 독립 검증 | 20개 통과 |
| 결과 집계 검사 | 구현자 11개, 독립 검증자 11개 통과 |
| 공식 엔진 템플릿 원본 | 공식 SHA512 값과 일치 |
| 내보낸 실행 파일의 GPU 검사 | 일반 8개 + 연습 8개 통과, 화면 가독성 검토 |
| 최종 ZIP | 의도한 파일 8개만 포함, SHA256 일치, QA 실행 파일·PCK와 동일 |

독립 검증자는 프로젝트 원본이 없는 한글·공백 경로에 EXE와 PCK를 복사하여 연습·일반 코스를 실행했다. 실행 도구가 만든 실제 인자를 사용해 참가자별·코스별 저장과 같은 세션 재개를 확인했다. 참가자 번호와 경로 입력 검증, 새 세션 분리, 다른 빌드의 저장을 조용히 이어 쓰지 않는 동작도 검사했다.

배포본 검사는 패킹된 컨트롤러의 이동, 코드로 전달한 F3 이벤트, 렌더링과 저장을 확인한다. 운영체제의 실제 키보드를 사람이 눌러 시험한 것으로 해석하지 않는다.

연습 코스 GPU 캡처의 종료 시 ObjectDB 경고가 한 번 발생했지만 검사와 프로세스는 성공했고, 별도 종료 재검사 7개에서는 경고가 재현되지 않았다. 경고가 전혀 없었다고 간주하지 않으며 실제 참가자 실행에서 반복되면 로그로 추적한다. 근거는 `.tools/launcher-independent.log`, `.tools/summary-independent.log`, `.tools/패키지 검증 공간/gpu-final-normal.log`, `gpu-final-practice.log`, `gpu-practice-teardown.log`에 있다.

집계에서는 최신 완료 세션만 선택하고 `unknown`을 과거의 긍정적 답으로 채우지 않으며, 연습·미완료·잘못된 기록을 구분했다. 자기보고와 진행자의 직접 관찰, 서로 다른 빌드의 결과를 분리한다. 빈 폴더는 참가자 0명으로 보고하며 재미 기준을 자동 통과시키지 않는다. 테스트용 응답은 모두 `.tools` 안의 합성 자료다.

재현:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\playtest_launcher_tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\playtest_summary_tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\build-playtest.ps1
```

[Windows 빌드 안내](windows-playtest-build.ko.md)와 [참가자 평가 진행·집계 안내](playtest-v02.ko.md)를 함께 사용한다. 샌드박스에서 인증서 저장소 및 에디터 설정 저장 경고가 발생했지만 내보내기 프로세스는 종료 코드 0으로 EXE·PCK를 생성했다. 모든 Windows PC의 호환성과 사람의 손맛 평가는 아직 확인하지 않았다.

## v0.2 핵심 조작 MVP — 현재 빌드

구현자와 별도 검증자가 아래 결과를 확인했다. 아래의 1·2단계 기록은 이전 빌드의 이력이다.

| 검증 | 결과 |
|---|---|
| 구현자 핵심 조작 검사 | 25개 통과 |
| 기존 물리 회귀 검사 | 132개 통과 |
| 최종 독립 코어 검사 | 23개 통과, 실패 0 |
| 이전 v1/v2 실제 실행 기록 비교 | 30개 상태 일치 |
| 새 저장의 별도 프로세스 쓰기·복원 | 1 + 2개 통과 |
| UI·추락 재개·디버그 저장 보호 | 11 + 3 + 2개 통과 |
| 최종 실제 GPU 렌더링 검사 | 일반 17개 + 테스트 코스 5개 통과, 화면 8장 검토 |

최종 생성 규칙을 적용한 **96개 시드**에서 동일 Chunk 연속 금지, 난이도 4 이상 3연속 금지, 같은 지형 4연속 금지, 쉼터 간격 150m 이하를 확인했다. 관성의 적정 속도·출발·고속 페널티, 저속 진흙 저항, 부분 추락 회수, -4m/s 폭주 경계, 돌턱 통과와 재접근도 검사했다.

기본 능력치와 조절된 자동 입력으로 98m 테스트 코스를 **90.008초**에 통과했다. Shift를 계속 누르는 비교에서는 300초 동안 스태미나를 소진하고 56.98m 부근 돌턱을 넘지 못했다. 최종 일반 산 시드 42는 맑음 **907.842초**, 비 **908.625초**에 정상에 도착했다. 모두 시뮬레이션 시간이며 사람의 평균 플레이타임이나 재미를 입증하지 않는다.

새 저장은 이미 넘은 돌턱, 부분 추락 횟수, 홈 정의, 고정 물리 계산의 잔여 시간까지 별도 프로세스에서 복원한 뒤 동일 입력으로 같은 결과를 냈다. 이전 물리는 변경 전 실제 실행에서 얻은 `tests/fixtures/pre_v02_legacy.json`과 비교했다.

최종 GPU 화면은 `.tools/screenshots-v02/`에 있다. 최소 HUD, Slip 표시 경계, F3 가독성, 부분 추락과 폭주 화면, 테스트 코스를 확인했다. 정식 Release 내보내기는 실행하지 않았으며 F3의 개발 빌드 제한은 코드와 개발 실행에서 확인했다. 오디오 청취와 **10명 플레이 테스트는 아직 수행하지 않았다**. [플레이 테스트 기록표](playtest-v02.ko.md)로 A~E 기준을 확인한 뒤 기억·성장 단계로 진행한다.

현재 빌드의 재현 명령:

```powershell
$engine = Join-Path $PWD '.tools/godot/Godot_v4.5.1-stable_win64_console.exe'
& $engine --headless --path . --log-file "$PWD/.tools/v02-core.log" --script res://tests/v02_core_tests.gd
& $engine --headless --path . --log-file "$PWD/.tools/v02-independent-final.log" --script res://tests/v02_verification.gd -- --quick
& $engine --headless --path . --log-file "$PWD/.tools/v02-continuation-write.log" --script res://tests/v02_verification.gd -- --continuation-write
& $engine --headless --path . --log-file "$PWD/.tools/v02-continuation-read.log" --script res://tests/v02_verification.gd -- --continuation-read
$uiSavePath = 'res://.tools/v02-ui-' + [guid]::NewGuid().ToString('N') + '.json'
& $engine --headless --path . --log-file "$PWD/.tools/v02-ui.log" --script res://tests/v02_ui_verification.gd -- --save-path=$uiSavePath
& $engine --headless --path . --log-file "$PWD/.tools/v02-ui-resume.log" --script res://tests/v02_ui_verification.gd -- --save-path=$uiSavePath --resume-check
& $engine --headless --path . --log-file "$PWD/.tools/v02-ui-guard.log" --script res://tests/v02_ui_verification.gd -- --save-path=$uiSavePath --debug-course --guard-check
```

`--quick`은 일반 완주 표본을 시드 42로 한정하며 나머지 코어·96시드 생성 검사는 그대로 실행한다. 제거하면 시드 1·42·1547의 맑음·비 6경로를 검사한다. UI 재현은 실행 묶음마다 새 테스트 전용 저장 경로를 만들며 표시된 순서대로 실행한다.

최종 근거: `.tools/v02-independent-final.log`, `.tools/v02-continuation-write.log`, `.tools/v02-continuation-read.log`, `.tools/v02-ui-gpu-delivery.log`, `.tools/v02-debug-gpu-delivery.log`.

## 2단계: 산·지형·날씨

| 검증 | 결과 |
|---|---|
| 기존 핵심 물리 | 132개 검사, 실패 0 |
| 구현자의 산·환경 검사 | 2,530개 검사, 실패 0 |
| 독립 산·환경 검증 | 28개 검사, 실패 0 |
| 이전 저장 호환 + 새 버전의 별도 프로세스 복원 | 6 + 3개 검사, 실패 0 |
| 손상된 저장 및 쓰기 실패 처리 | 10개 검사, 실패 0 |
| UI 회귀 검사 + 실제 GPU 캡처 | 12 + 12개 검사, 실패 0 |
| 별도 프로세스의 UI 저장 복원 | 3개 검사, 실패 0 |

독립 검증자는 128개 시드에서 구역별 후보, 구간 길이, 15종 포함, 난이도 5의 3연속 금지와 결정성을 확인했다. 표본에는 서로 다른 배치 127개와 맑음 105회·비 23회가 포함됐다. 이는 표본 결과이며 설정 확률 80%·20%를 바꾸지 않는다.

7개 시드 × 맑음·비의 **14개 등반 시뮬레이션 모두 기본 능력으로 정상에 도달**했다. 독립 검증자의 조작 패턴에서는 약 532~543초, 구현자의 별도 8개 시뮬레이션에서는 약 492~516초였다. 두 검사는 서로 다른 조작 패턴을 사용한다. 전자는 15개 구간 종류를 모든 경로에서 확인한다. 이 결과는 검사한 경로의 통과 가능성에 대한 근거이며 전체 플레이어의 평균 시간이나 재미를 뜻하지 않는다.

동일 경사에서 지형별 추진력과 미끄러짐 차이, 비의 접지력·제동 감소, 30/144FPS 일치, 지속 버티기의 스태미나 소모, 쉼터에서의 정확한 정지를 확인했다. 저장된 구간·지형 정의가 현재 카탈로그와 달라도 저장값으로 복원되는지 검사했다. 버전 1의 진행 중 회차는 이전 산·물리를 유지하고, 다음 회차에서 새 산으로 넘어간다. 새 저장을 다시 불러올 때 다른 개발용 시드·날씨 옵션을 지정해도 저장된 산을 우선한다.

실제 GPU에서 기존 6개 화면과 맑음·비 × 돌·흙·자갈 6개 화면을 캡처했다. 지형 색·무늬, 빗줄기, 한글 안내가 읽히는지 별도로 확인했다. 오디오 청취 품질은 확인하지 않았다.

추가 검증 명령은 프로젝트 루트에서 실행한다. 아래의 저장 경로는 모두 테스트 전용이다.

```powershell
$engine = Join-Path $PWD '.tools/godot/Godot_v4.5.1-stable_win64_console.exe'
& $engine --headless --path . --log-file "$PWD/.tools/environment-tests.log" --script res://tests/environment_tests.gd
& $engine --headless --path . --log-file "$PWD/.tools/stage2-independent.log" --script res://tests/stage2_verification.gd
& $engine --headless --path . --log-file "$PWD/.tools/migration-write.log" --script res://tests/migration_verification.gd -- --save-path=res://.tools/qa-migration-save.json --seed=2431 --weather=rain
& $engine --headless --path . --log-file "$PWD/.tools/migration-resume.log" --script res://tests/migration_verification.gd -- --save-path=res://.tools/qa-migration-save.json --seed=987 --weather=clear --migration-resume
& $engine --headless --path . --log-file "$PWD/.tools/save-robustness.log" --script res://tests/save_robustness_verification.gd -- --save-path=res://.tools/qa-invalid-save.json
```

로그: `.tools/environment-tests.log`, `stage2-independent.log`, `migration-write.log`, `migration-resume.log`, `save-robustness.log`, `stage2-ui.log`, `stage2-capture-final.log`, `stage2-ui-resume.log`. 최종 회색 돌길을 반영한 GPU 재검증에서도 24개 검사와 12개 캡처가 통과했다. 손상된 JSON과 쓰기 실패 검사는 의도적으로 오류를 만들어 처리 결과를 확인하므로 해당 로그의 예상 오류 메시지를 테스트 실패와 구분해야 한다.

## 1단계 결과 기록

| 검증 | 결과 |
|---|---|
| 프로젝트 가져오기 / 파싱 | 통과 |
| 핵심 물리 테스트 | 132개 검사, 실패 0 |
| 별도 검증자의 물리 테스트 | 실패 0 |
| UI 상태와 입력 처리 | 실패 0 |
| 별도 프로세스의 저장 복원 | 3개 검사, 실패 0 |
| 실제 GPU 렌더링 | 1280×800에서 6개 상태 캡처 확인 |

검증 대상은 첫 구현 단계이며 전체 로그라이트 MVP에 대한 완료 판정이 아니다.

## 확인한 동작

- 밀기는 초반 경사를 이긴다. 입력을 놓으면 중력으로 후퇴한다.
- 힘주기만 누르고 밀기 입력을 하지 않으면 추진력이 생기지 않는다.
- 버티기는 오르막 추진력을 만들지 않고 스태미나를 소비한다.
- 미끄러짐 게이지가 임계치에 도달하면 1초 동안 제어가 제한된다.
- -4m/s 아래에서 폭주가 시작되고 입력으로 취소할 수 없다.
- 쉼터에서 회복 가능하며 새 회차는 거리·속도·스태미나를 초기화한다.
- 같은 입력 이력에서 30/60FPS 및 30/144FPS의 물리 결과가 일치한다.
- 기본 능력으로 밀기·힘주기·쉼터 회복을 사용하는 자동 조작이 **592초**에 정상에 도달했다. 성장으로만 넘을 수 있는 벽은 확인되지 않았다.
- Enter 시작, Esc 일시정지, 포커스 이탈 시 자동 정지, 재개, 결과 화면 재시작이 동작한다.
- 첫 추락은 E로 건너뛸 수 없고 첫 추락 완료 이후에만 스킵할 수 있다.
- 일시정지 메뉴 뒤에 있는 결과 화면의 버튼은 클릭 대상으로 남지 않는다.
- 정상 도착 후 3초 동안 UI와 재시작 입력을 숨기고 이후 재시작을 허용한다.
- 종료 저장 후 별도 실행에서 회차, 추락 횟수, 거리, 속도, 스태미나, 미끄러짐과 타이머를 복원한다.

시작 화면, 게임, 일시정지, 추락 결과, 정상의 정적, 정상 결과 화면을 실제 GPU 렌더링으로 확인했다. 캡처와 실행 로그는 `.tools/`에 있으며 Git에는 포함하지 않는다.

## 재현

프로젝트 루트에서 PowerShell로 실행한다. 검증용 엔진이 없으면 경로를 설치한 Godot 콘솔 실행 파일로 바꾼다.

```powershell
$engine = Join-Path $PWD '.tools/godot/Godot_v4.5.1-stable_win64_console.exe'
& $engine --headless --path . --log-file "$PWD/.tools/import.log" --editor --quit
& $engine --headless --path . --log-file "$PWD/.tools/core-tests.log" --script res://tests/core_tests.gd
& $engine --headless --path . --log-file "$PWD/.tools/independent-verification.log" --script res://tests/integration_verification.gd
& $engine --headless --path . --log-file "$PWD/.tools/ui-verify.log" --script res://tests/ui_verification.gd -- --save-path=res://.tools/qa-reproduce.json
& $engine --headless --path . --log-file "$PWD/.tools/ui-resume-verify.log" --script res://tests/ui_verification.gd -- --save-path=res://.tools/qa-reproduce.json --resume-check
```

UI 검증은 테스트 전용 저장 파일을 사용한다. 마지막 두 명령은 같은 경로로 순서대로 실행해야 한다. 화면 캡처를 재현하려면 `.tools/screenshots/` 폴더를 만들고 UI 검증 명령에서 `--headless`를 제외한 뒤 마지막 사용자 인자에 `--capture`를 추가한다.

## 검증 한계

이 환경의 샌드박스에서는 Godot가 Windows 인증서 저장소와 기본 셰이더 캐시에 접근하지 못한다는 엔진 메시지가 발생했다. 게임은 네트워크를 사용하지 않으며 물리 검사와 실제 GPU 렌더링은 수행됐다.

자동 UI 검사는 입력 이벤트와 상태 전이를 호출해 검사한다. 실제 키보드를 이용한 장시간 플레이, 소리의 청취 품질, 손맛, 목표 플레이타임은 별도 플레이 테스트가 필요하다. 592초는 지정된 자동 조작의 시뮬레이션 시간이며 평균 플레이타임을 뜻하지 않는다.
