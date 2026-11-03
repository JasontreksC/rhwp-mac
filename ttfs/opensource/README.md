# ttfs/opensource — 오픈소스 대체 폰트 (Git 추적)

`ttfs/` 루트와 `hwp/`, `windows/` 하위는 한컴·Microsoft 저작권 폰트를 로컬에 두는 자리라 `.gitignore` 처리한다.
이 디렉터리는 **재배포 가능한 오픈소스(SIL OFL 1.1) 폰트**만 담아 Git으로 추적한다.

| 파일 | 폰트 | 라이선스 | 용도 |
| --- | --- | --- | --- |
| `NotoSansKR-Regular.ttf` | Noto Sans KR Regular (wght 400, 한글·라틴·글머리·도형 subset) | `NotoSansKR-OFL.txt` | KS 기호와 Box Drawing 글리프 보강 |
| `NotoSansKR-ExtraLight.ttf` | Noto Sans KR ExtraLight (wght 200, 한글·라틴 subset) | `NotoSansKR-OFL.txt` | 한컴 돋움·굴림 계열의 획 두께에 맞춘 대체 |
| `SourceHanSerifK-OldHangul-subset.otf` | Source Han Serif K Old Hangul subset | `SourceHanSerifK-OFL.txt` | 옛한글·세로쓰기 shaping 입력 |

`NotoSansKR-ExtraLight.ttf`는 family 이름을 `Noto Sans KR ExtraLight`로 독립시켰다. `Noto Sans KR`의 weight 변형으로
등록하면 일반 `Noto Sans KR` 요청까지 이 폰트로 가로채는 부작용이 있기 때문이다.

출처는 Google Fonts `ofl/notosanskr` 가변 폰트와 Adobe·Google의 Source Han Serif K다. 이 폴더의 폰트는 시험 입력과
대체 글꼴 후보이며, 앱에 번들할지는 글꼴 공급 방침(4단계)에서 따로 정한다.
