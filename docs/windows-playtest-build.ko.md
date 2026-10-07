# Windows 플레이 테스트 배포

Windows x86_64 참가자가 Godot 설치 없이 실행할 수 있는 ZIP을 만든다. 연습 코스와 F3를 포함하기 위해 Godot 4.5.1 **Debug 내보내기**를 사용한다. 정식 출시 빌드가 아니며 코드 서명은 하지 않았다. 게임 물리는 v0.2 핵심 조작 MVP와 같다.

## 빌드

이 작업 폴더에는 공식 Godot 4.5.1 에디터와 Windows 템플릿이 준비돼 있다. 프로젝트 루트에서 실행한다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\build-playtest.ps1
```

매번 `builds/SISYPHUS-v0.2-Windows-날짜-고유번호/`와 같은 이름의 ZIP, ZIP의 SHA256 파일을 새로 만든다. 게임, 실행 도구, 참가자 안내, 엔진 라이선스만 명시적으로 복사한다. 이전 참가자의 결과나 저장은 패키지에 포함하지 않는다. 기존 빌드나 참가자 기록을 삭제하지 않는다.

ZIP 전체를 참가자에게 전달하고 서로 다른 참가자 번호 01~10을 배정한다. 파일 전송은 진행자가 직접 한다. [참가자 안내](playtest-participant.ko.md)는 ZIP의 `START-HERE.txt`에도 들어 있다. 압축을 모두 푼 뒤 `Playtest.cmd`로 시작한다. `SISYPHUS.exe` 직접 실행은 일반 게임을 열지만 참가자별 기록 절차를 거치지 않는다.

참가자는 연습과 본 테스트를 차례로 실행한다. 본 테스트는 비교 가능한 조건을 위해 시드 42·맑음으로 고정한다. 저장·실행 로그·응답은 `playtest-results`에 남으며 자동 전송하지 않는다. 진행자가 받은 결과를 합치는 절차는 [플레이 테스트 기록](playtest-v02.ko.md)에 있다.

## 다른 개발 PC에서 준비할 파일

- `.tools/godot/Godot_v4.5.1-stable_win64_console.exe`: 공식 일반 Windows 에디터
- `.tools/export-templates/windows_debug_x86_64.exe`, `windows_release_x86_64.exe`: 같은 버전의 공식 export templates에서 추출
- `.tools/GODOT-LICENSE.txt`, `.tools/GODOT-COPYRIGHT.txt`: 같은 버전의 엔진 라이선스 고지

템플릿 원본은 [Godot 4.5.1 공식 배포](https://github.com/godotengine/godot-builds/releases/tag/4.5.1-stable)의 `Godot_v4.5.1-stable_export_templates.tpz`다. 이번 빌드에서는 공식 `SHA512-SUMS.txt`와 아래 SHA512가 일치함을 확인한 뒤 Windows 실행 파일을 추출했다.

```text
8a65c73541184fbcf1a7afedb37c9c15ed0f3babdaafe36ff47ccc515548ac84bc7563ba5b94c253e6085b121ac608b7e03d35dfc0b2c8c690a646a8755b57e5
```

`export_presets.cfg`는 프로젝트 안의 템플릿 경로를 사용한다. [공식 Windows 내보내기 문서](https://docs.godotengine.org/en/4.5/tutorials/export/exporting_for_windows.html)와 [명령줄 내보내기 문서](https://docs.godotengine.org/en/4.5/tutorials/editor/command_line_tutorial.html)를 따른다. EXE와 PCK는 함께 배포하며 에디터·개발 테스트·원본 문서는 게임 데이터에 포함하지 않는다.

## 범위

실행 대상은 Windows 10/11 x64다. 현재 PC의 실행 검증은 모든 참가자 PC의 그래픽 드라이버·실행 정책 호환성을 보장하지 않는다. 실행이 차단되면 표시된 메시지를 진행자에게 전달한다. 보호 기능을 끄거나 관리자 권한으로 실행할 필요는 없다.

자동 검증과 배포 준비는 참가자 10명의 실제 평가를 대신하지 않는다. 결과가 도착하기 전 재미 기준은 미검증 상태로 유지한다.
