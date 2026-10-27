# MVP 정식 웹 배포

사용자가 main 병합과 최신 MVP의 정식 웹 배포를 승인함에 따라 `.github/workflows/deploy-web.yml`은 `MVP Web` 프리셋의 Release 결과를 GitHub Pages에 배포한다. 이전 문서의 “정식 Web 진입점 유지” 설명은 이 전환 이전 작업의 기록이다.

`MVP Web`의 `mastery_mvp` 기능 태그는 기존 `project.godot`의 `run/main_scene.mastery_mvp` 설정을 통해 `scenes/mvp/main_mvp.tscn`을 선택한다. 기본 로컬 진입점과 기존 `Web` 프리셋은 수정하지 않는다. 현재 일반 숙련 해금은 150/400/700m이며, 석판·메인 메뉴·프레스티지 MVP가 웹 기본 화면이 된다.

배포 산출물은 계속 `builds/web/`에 모은다. MVP HTML 셸에서 링크하는 Godot 및 Noto Sans KR·Hahmlet·Pretendard·GFS Didot 라이선스를 함께 복사한다. 외부 폰트 CDN은 사용하지 않는다.

배포 페이지와 같은 디렉터리의 `version.json`에는 빌드한 Git 커밋 SHA, 프리셋, Godot 버전, 진입 씬, 실제 노드 데이터에서 읽은 일반 해금 거리가 기록된다. 배포 후 이 파일의 `commit`을 Actions의 커밋과 비교하고, 실제 페이지에서 MVP 메인 메뉴와 석판을 확인한다. 워크플로 수정 또는 로컬 Release export만으로 원격 배포 성공을 판정하지 않는다.

MVP는 기존 `sisyphus-mvp-v1.json` 저장과 별도 웹 mirror 키를 사용한다. 예전 게임의 저장을 자동 변환하거나 삭제하지 않는다. 배포 URL이 바뀌면 URL 디렉터리를 포함하는 mirror 키도 달라질 수 있으므로 저장 위치에 관한 자세한 내용은 [저장 형식](save-format.md)을 따른다.
