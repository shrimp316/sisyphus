# 공통 폰트와 UI 타이포그래피 v1.1

1920×1080을 디자인 기준으로 공통 Godot Theme와 역할별 서체를 추가하고, 현재 구현된 MVP 메뉴·숙련의 석판·세피로트 표시·HUD·정상/프레스티지 연출에 연결했다. 물리, EXP, 프레스티지 진행과 저장 규칙을 변경하는 작업은 포함하지 않는다. 원화 PNG·SVG 및 기존 로고 이미지 파일은 수정하지 않았다.

## 서체 및 배포 조건

| 서체 | 원본 폰트 버전 | 사용 굵기 | 공식 배포처 및 고지 |
|---|---|---|---|
| Hahmlet | 1.002 | Regular, Medium, SemiBold, Bold | [공식 저장소](https://github.com/hyper-type/hahmlet/tree/f9c5dac25d88015e9f0953253cec1a71854b7d24/fonts/otf), [OFL](../../assets/fonts/licenses/Hahmlet-OFL.txt) |
| Pretendard | 1.309 | Regular, Medium, SemiBold | [공식 저장소](https://github.com/orioncactus/pretendard/tree/7aeb0698819be2b4097dae8ec8fe6a795e5cf3ae/packages/pretendard/dist/public/static), [OFL](../../assets/fonts/licenses/Pretendard-OFL.txt) |
| GFS Didot | 1.0 | Regular | [Google Fonts 배포본](https://github.com/google/fonts/tree/e7db6ca603fd4862010383ff17ffd6cc4ffac1c0/ofl/gfsdidot), [OFL](../../assets/fonts/licenses/GFSDidot-OFL.txt) |

세 서체는 SIL Open Font License 1.1 원문과 각 저작권·예약 이름 고지를 함께 포함한다. 폰트 8개는 변형하거나 서브셋하지 않은 공식 원본이며 합계 7,051,964바이트다. 파일별 SHA-256과 출처 커밋은 [manifest](../../assets/fonts/licenses/font-manifest.json), 상세 설명은 [라이선스 안내](../../assets/fonts/licenses/README.md)에 있다. 기존 `NotoSansKR.ttf`와 기존 OFL도 보존한다.

Hahmlet 원본은 완성형 한글 2,788자를 지원하고 그리스어를 포함하지 않으므로, Hahmlet 역할에는 굵기에 맞는 번들 Pretendard fallback을 명시한다. GFS Didot은 필수 고대 그리스어를 지원하나 한글은 없으므로 한글용 Pretendard fallback을 지정한다. Pretendard 원본은 완성형 한글 11,172자와 필수 그리스어·기호를 포함한다. 아홉 개 번들 폰트의 Godot 가져오기 설정에서 시스템 글꼴 fallback을 끄고, 폰트 로드 실패 시 번들 Noto와 GFS Didot을 사용한다. CDN이나 운영체제 폰트 다운로드에 의존하지 않는다.

## 적용 범위

[공통 Theme](../../ui/themes/sisyphus_theme.tres)는 Label과 Button에 별도의 Type Variation을 사용한다. 제목·섹션·메뉴·노드·본문·HUD·툴팁·그리스어·서사는 [typography 리소스](../../ui/themes/typography/)로 분리했고, 버튼의 기존 텍스처와 StyleBox를 유지한다. 색상은 상태에 따라 변경할 수 있다. 제목은 약한 외곽선과 그림자를 사용한다.

| 화면 | 적용 |
|---|---|
| 메인 메뉴 | 메뉴 버튼, 막/기록 패널, 안내·서사 문구에 역할별 Theme 적용 |
| 숙련의 석판 | 제목·계열·노드 상세명·설명·비용·해금 조건에 역할별 적용. 35개 노드 데이터는 동적 표시하며 기존 노드 프레임은 유지 |
| 세피로트·프레스티지 | 현재 존재하는 말쿠트/운명의 실 화면과 정상·프레스티지 문구에 제목·수치·본문·서사 역할 적용 |
| HUD | 기본 게임과 MVP 모두 번들 Pretendard를 사용. MVP의 거리·EXP 수치는 기존 Canvas 확대 규칙을 거쳐 디자인 기준 28px이며, 다른 수동 Canvas 안내는 기존 필드별 크기를 따른다 |
| 아직 없는 UI | 막 선택·기록의 전당 등 미구현 화면은 새로 만들지 않고 공통 Theme Variation만 준비 |

기존 MVP 메인 화면의 `ΣΙΣΥΦΟΣ`는 원래 이미지가 아닌 Noto 기반 텍스트 Label이었다. 그 글꼴과 표시를 예외로 유지했다. 별도로 제공된 로고 PNG는 오른쪽이 잘린 상태여서 수정하거나 교체하지 않았다. 추후 완전한 로고 원화가 준비되면 별도 UI 작업으로 연결할 수 있다.

주요 변경 파일은 `assets/fonts/{hahmlet,pretendard,gfs_didot,licenses}/`, `ui/themes/`, `scripts/mvp/typography.gd`, `scripts/mvp/ui_theme.gd`, 메뉴·석판·HUD 관련 `scripts/mvp/` 화면 코드 및 `tests/mvp/` 타이포그래피 검사·샘플 씬이다. 실제 변경 목록은 해당 feature 브랜치의 Git diff를 기준으로 한다.

## 글리프, 크기 및 화면 검증

- Godot 글꼴 및 Theme 검사 **948개** 통과. 필수 `ΣΙΣΥΦΟΣ`, `ΩΘΗΣΙΣ`, `ἄνθρωπος`, `ἀρετή`, 한글, 숫자·특수기호와 아홉 폰트의 시스템 fallback 비활성화를 검사했다. 같은 폰트 파일을 쓰는 역할들은 리소스 인스턴스도 공유한다. 고대 그리스어는 NFC와 분해형 NFD도 확인했다. 글리프 보유 검사는 모든 조합의 실제 렌더링을 보장하지 않는다.
- 디자인 좌표와 글꼴 지표 기반 레이아웃 검사 **970개** 통과: 1920×1080, 1600×900, 1280×720. 별도의 MVP UI **265개**, 화면 통합 **244개**, 정상·프레스티지 화면 **8개** 검사를 통과했다. [시스템 fallback 차단 후 독립 검사](../../tests/mvp/results/typography-v11/independent/post-no-system/review.json), [후속 HUD 검증](../../tests/mvp/results/typography-v11/independent/post-hud/review.json), [연출 검사](../../tests/mvp/results/typography-v11/presentation.txt).
- Windows의 실제 Godot 렌더러 SubViewport로 샘플·메뉴·석판을 세 해상도에서 시각 검토했다. 인공 프로필을 사용한 캡처이며 OS 창 크기 변경이나 모든 입력 상태를 검증한 것은 아니다. [1920/1280 독립 검토](../../tests/mvp/results/typography-v11/independent/final-review.json), [1600 독립 검토](../../tests/mvp/results/typography-v11/independent/native-1600/review.json).
- Windows Chromium Web에서 실제 게임 메뉴·석판·세피로트·HUD를 1280×720 CSS viewport에서 확인하고, 별도 샘플을 1920×1080과 1280×720에서 확인했다. 테스트용 임시 프로필을 사용했다. Web 1600×900은 위 headless 레이아웃 검사 범위이며 실제 브라우저 스크린샷 검증은 하지 않았다. Linux는 실행하지 않았으므로 Windows·Linux·Web의 렌더 일치가 입증된 것은 아니다. [최종 Web 기록 및 해시](../../tests/mvp/results/typography-v11/web/manifest-final.json).
- 누락된 Theme/폰트, 불완전한 Theme와 실제 외부 폰트 리소스 의존성 누락을 주입하여 번들된 기존 Noto 기반 비상 fallback을 검사했다. [손상 주입 로그](../../tests/mvp/results/typography-v11/independent/missing-dependency-probe.txt)의 로더 오류는 의도된 시험 출력이다. 모든 비상 폰트까지 제거된 경우는 보장하지 않는다.

기본 게임·MVP 전체 회귀 **1,502개 통과**. 이는 시스템 fallback 가져오기 설정 변경 직전의 실행이며, 이후 글꼴·레이아웃·UI·통합 대상 2,425개를 다시 통과했다. 리소스 공유 검사 2개를 추가한 뒤 폰트 검사 948개만 별도로 재실행했다. 과거 결과는 바이트 단위로 복원했다. [전체 회귀](../../tests/mvp/results/typography-v11/regression-final/report.json), [기존 증거 보존](../../tests/mvp/results/typography-v11/regression-final/prior-evidence-preservation.json).

## 화면 비교

아래 이미지는 서로 다른 시점·테스트 프로필에서 캡처했으므로 동일 조건의 픽셀 차이 측정이 아니다. 기존 시각 언어 보존과 새 글꼴의 표시 확인을 위한 자료다.

| 화면 | 적용 전 | 적용 후 |
|---|---|---|
| 메뉴 | [기존 1920](../../tests/mvp/results/browser/menu-1920.png) | [Windows 1920](../../tests/mvp/results/typography-v11/independent/post-no-system/native/menu-1920.png), [Web 1280](../../tests/mvp/results/typography-v11/web/menu-final.jpg) |
| 숙련의 석판 | [기존 1920](../../tests/mvp/results/browser/board-1920.png) | [Windows 1920](../../tests/mvp/results/typography-v11/independent/post-no-system/native/board-1920.png), [Windows 1600](../../tests/mvp/results/typography-v11/independent/post-no-system/native/board-1600.png), [Web 1280](../../tests/mvp/results/typography-v11/web/board-final.jpg) |
| 그리스어·한글 샘플 | — | [Windows 1280](../../tests/mvp/results/typography-v11/independent/post-no-system/native/sample-1280.png), [Web 1920](../../tests/mvp/results/typography-v11/web/sample-final-1920.jpg) |
| HUD·세피로트 | 기존 구현 | [Web HUD 1280](../../tests/mvp/results/typography-v11/web/hud-final.jpg), [Web 세피로트 1280](../../tests/mvp/results/typography-v11/web/sephirot-final.jpg) |

## Web 용량과 남은 검증

최종 Web `.pck`는 기존 32,937,928바이트에서 38,101,984바이트로 **5,164,056바이트 증가**했다. 같은 측정의 `.wasm`은 양쪽 모두 36,145,869바이트였다. 번들 원본 크기와 패키지 증가량은 압축·기존 자산 구성 때문에 같지 않다. [최종 빌드 manifest](../../tests/mvp/results/typography-v11/web/manifest-final.json)에 각 파일의 SHA-256을 기록했다.

남은 항목은 Linux 실제 렌더, Web 1600×900 실화면, 전체 OS 창·전체 화면 조합, 완전한 로고 원화 연결과 실제 사용자 문자열에 대한 추가 가독성 검증이다. 웹 서브셋은 이번에는 적용하지 않았다. 일부 고전 그리스어 문자의 조합과 예상 밖의 동적 문자열은 추가 검증이 필요하다.
