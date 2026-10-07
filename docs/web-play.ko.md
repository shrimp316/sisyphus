# 브라우저에서 시지프스 플레이

게임 주소: **https://shrimp316.github.io/sisyphus/**

공개 저장소: https://github.com/shrimp316/sisyphus

배포된 게임 페이지를 PC 브라우저로 열고 시작 버튼을 누른다. 첫 실행에서는 게임 데이터를 내려받으므로 잠시 기다린다. 키보드 조작을 사용하는 빌드이며, 터치 조작은 지원하지 않는다.

| 키 | 기능 |
|---|---|
| D / → | 밀기 |
| 밀기 + Shift | 힘주기 |
| Space | 버티기 |
| Esc | 메뉴 |
| M | 소리 켜기·끄기 |

페이지를 한 번 클릭하면 게임에 키보드 입력과 소리가 전달된다. 소리가 없으면 게임 영역을 클릭하고 M 설정을 확인한다. 사용 브라우저가 WebAssembly와 WebGL 2.0을 지원해야 한다. 우선 데스크톱 Chrome·Edge·Firefox에서 확인하며 모든 기기에서의 실행을 보장하지 않는다.

진행 기록은 해당 브라우저에 저장되며 다른 PC나 Windows 실행 파일과 자동으로 공유되지 않는다. 비공개 모드나 사이트 데이터 삭제 후에는 기록이 유지되지 않을 수 있다. 종료 전에 게임의 저장 기능으로 저장 완료를 확인한다.

## 개발용 Web 빌드

Windows 프로젝트 폴더에서 다음을 실행한다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-web.ps1
```

필요한 로컬 입력은 `.tools/godot/Godot_v4.5.1-stable_win64_console.exe`, `.tools/export-templates/web_nothreads_debug.zip`, `.tools/export-templates/web_nothreads_release.zip`이다. 두 템플릿은 [Godot 4.5.1 공식 릴리스](https://github.com/godotengine/godot/releases/tag/4.5.1-stable)의 `Godot_v4.5.1-stable_export_templates.tpz` 안에 있다. 다운로드 무결성은 같은 릴리스의 `SHA512-SUMS.txt`로 검증한다.

출력은 `builds/web/index.html`과 함께 생성되는 JS·WASM·PCK 파일이다. 파일 이름을 바꾸거나 일부만 옮기지 않는다. `.nojekyll`, Godot 라이선스 문서, 글꼴 라이선스(`FONT-LICENSE.txt`)도 함께 생성한다. 로컬에서는 `file://`로 직접 열지 않고 이 폴더를 HTTP 서버로 제공한다. 실제 호스팅에서는 HTTPS를 사용한다.

Web 프리셋은 Compatibility 렌더러, 단일 스레드, 확장 기능 끄기, PWA 끄기를 사용한다. 별도의 COOP/COEP 헤더나 서비스 워커 없이 정적 호스팅에서 동작하도록 구성했다. 세부 조건은 [Godot Web 내보내기 공식 문서](https://docs.godotengine.org/en/4.5/tutorials/export/exporting_for_web.html)를 따른다.

Node.js가 설치된 개발 PC에서는 `node tools/serve-web.cjs`를 실행하고 `http://127.0.0.1:8765/sisyphus/`를 연다. 이 미리보기 서버는 이 PC에서만 접근할 수 있으며, GitHub 프로젝트 페이지와 같은 하위 경로에서 파일을 제공한다.

## GitHub Pages 배포

저장소의 Settings → Pages에서 **GitHub Actions**를 배포 소스로 선택한다. `.github/workflows/deploy-web.yml`은 `main`에 푸시하거나 수동 실행하면 다음 작업을 수행한다.

1. 공식 Godot 4.5.1 Linux 편집기·템플릿을 다운로드하고 고정된 공식 SHA-512 값과 대조한다.
2. 프로젝트를 가져온 뒤 Web 릴리스 빌드를 생성한다.
3. `builds/web`만 GitHub Pages 아티팩트로 전달하고 배포한다.

참가자 결과, 로컬 저장, 실행 로그, `.tools`, Windows 배포 파일은 웹 아티팩트에 포함하지 않는다. 게임 패키지에는 테스트·문서·도구·배포 원본 HTML 폴더를 제외한다. 웹 페이지 자체는 별도 HTML 셸로 생성된다.

배포 성공 여부와 주소는 Actions의 배포 작업 및 Pages 설정에서 확인한다. 저장소 공개 여부와 Pages 제공 범위는 계정·저장소 설정에 따라 결정된다. 이 문서 자체는 사이트 게시 완료를 의미하지 않는다. 작업 구성은 [GitHub Pages 공식 워크플로 안내](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)를 참고한다.
