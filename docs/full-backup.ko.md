# 전체 자료 백업 및 복원

2026-10-07 사용자의 전체 GitHub 업로드 요청에 따라 소스 저장소와 GitHub Releases를 함께 사용한다.

[전체 다운로드](https://github.com/shrimp316/sisyphus/releases/tag/v0.2-full-backup-20261007) · [웹 플레이](https://shrimp316.github.io/sisyphus/)

## 다운로드 구성

| 파일 | 내용 |
|---|---|
| SISYPHUS-Windows-v0.2.zip | 최신 아트 112장이 적용된 Windows x86_64 플레이테스트 실행본. 압축 해제 후 Playtest.cmd 실행 |
| SISYPHUS-Web-v0.2.zip | 현재 Web 빌드. HTTP 서버에서 index.html 실행 |
| SISYPHUS-ArtPack-v0.2.zip | PNG, SpriteFrames, 독립 Godot 프리뷰 프로젝트 |
| SISYPHUS-Workspace.zip | 소스·문서·첨부 원본·생성 원본·이전/현재 빌드·검증 캡처·로그·테스트 데이터·.godot 캐시 등 전체 작업 파일 |
| SISYPHUS-Toolchain.zip | 실제 사용한 Godot 엔진 및 내보내기 템플릿. .tools 내부 원래 위치로 복원 |
| snapshot-manifest.json | 백업 시점의 모든 파일 경로·크기·SHA-256과 빈 폴더 목록 |
| SHA256SUMS.txt | 다운로드 파일별 SHA-256 |
| verification.json | 백업 파일 누락·중복·변조 검증 결과 |
| security-scan.json | 텍스트 및 민감 파일명 검사 범위와 결과 |

큰 실행 파일과 전체 백업은 Releases에 보관한다. 일반 Git clone에는 소스·최종 아트·문서·원본 참고 자료가 내려온다.

## 전체 작업 환경 복원

1. `SISYPHUS-Workspace.zip`과 `SISYPHUS-Toolchain.zip`을 같은 새 폴더에 압축 해제한다. 두 ZIP은 서로 다른 파일 집합을 담는다.
2. `project.godot` 또는 `Play.cmd`로 실행한다. Godot 에디터에서 열면 캐시를 다시 만들 수 있다.
3. 원본 이미지 생성 결과는 `.tools/generated-originals/`에 있다. `path-map.json`에 기존 생성 경로와 백업 내 경로를 대응시켰다. 재정리 도구를 실행할 때는 입력 JSON의 이미지 경로를 복원한 위치로 바꾼다.
4. `snapshot-manifest.json`과 `SHA256SUMS.txt`로 다운로드 및 파일 무결성을 확인한다. 빈 폴더는 manifest의 `directories` 목록을 이용해 필요할 때 만든다.

백업에서 제외한 경로는 `.git/`과 백업 산출물 자신인 `builds/full-upload/`뿐이다. Git 이력은 이 GitHub 저장소에 별도로 보존되어 있다. 백업 생성 이후의 새 로그나 후속 작업은 이 스냅샷에 자동으로 추가되지 않는다.

## 기획·대화·이미지 원본

- `docs/references/`: 사용자 첨부 명세 6개와 참고 이미지 4개. 같은 내용으로 반복 첨부한 에셋 명세 4개도 각각 보관했다.
- `docs/conversation-messages.json`: Codex 기록 조회 API에서 제공한 사용자·어시스턴트 공개 메시지 74개, 11개 턴. 조회 가능한 페이지를 모두 읽었다. 이미지 내용은 별도 원본 파일로 보관한다. 도구 실행 기록과 내부 추론은 포함하지 않으며, 현재 업로드 턴은 내보내기 시점까지 포함한다.
- `docs/work-history.ko.md`: 구현 경과와 결정 사항 요약.
- `.tools/generated-originals/`: 이 작업의 이미지 생성 원본 45개. 선택하지 않은 변형 이미지도 포함한다.

개인 컴퓨터 전체나 전역 설정을 수집한 백업은 아니다. 이 프로젝트 작업 폴더와 이 대화에서 명시적으로 제공·생성된 자료가 대상이다. 테스트 기록은 개발 중 만든 검증용 데이터이며 실제 참가자 테스트 결과는 아직 없다.

## 배포본 검증

최신 Windows 패키지는 Godot 4.5.1의 디버그 내보내기이며 서명되지 않았다. 실제 내보낸 EXE에서 아트·폰트·리소스 검사 19개와 GPU 실행 검사 8개를 통과했다. Godot 및 폰트 라이선스를 함께 포함한다. 원래 만들어 둔 이전 빌드도 전체 Workspace 백업에 보존한다.

GitHub Releases의 개별 첨부 파일은 2GiB 미만으로 구성했다. [GitHub 공식 제한 안내](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
