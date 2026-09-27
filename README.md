# korean-asahi

Apple Silicon(M1, 16K 페이지 커널) Debian trixie + KDE Plasma에서 x86_64 앱을
box64로 돌리는 구성. 두 가지를 스크립트로 재현한다.

- **b64wine**: box64 + x86_64/WoW64 Wine → 카카오톡 PC(32비트, Themida 보호)
- **hoffice**: box64 + 한컴오피스 for Linux(amd64 deb) → 한글/한워드/한셀/한쇼

둘 다 fcitx5 한글 입력, KDE 메뉴·아이콘·파일 연결까지 설정한다.

## 사용

```bash
git clone https://github.com/gg582/korean-asahi.git
cd korean-asahi

# 1) box64 + Wine + 카카오톡 (Wine 빌드 포함, 처음엔 오래 걸림)
scripts/setup-b64wine.sh

# 2) 한컴오피스
scripts/setup-hoffice.sh
```

설치 파일(카카오톡 설치기, 한컴오피스 deb)은 각 회사의 공식 주소에서 받아
`downloads/`에 둔다(git에는 포함하지 않음). 한컴오피스 이용 조건은 한컴의
라이선스를 직접 확인할 것.

인자 없이 실행하면 모든 단계를 순서대로 한다. 각 단계는 이미 된 일을 건너뛰므로
다시 실행해도 안전하고, `setup-b64wine.sh menus` 처럼 단계만 골라 실행할 수 있다
(단계 목록은 각 스크립트 머리말). sudo가 필요한 단계(`deps`, `install`)는
비밀번호를 묻는다.

실행: KDE 메뉴의 "카카오톡", "한글 2022 Beta" 등, 또는 파일 더블클릭.
터미널에서는 `b64wine 프로그램.exe`(alias), `~/.local/bin/hoffice hwp 문서.hwp`.

## 설치되는 것

| 위치 | 내용 |
|---|---|
| `~/.local/opt/box64/bin/box64` | box64 `ac9b13a`, `-DM1=ON` 빌드 (시스템 `/usr/bin/box64`는 그대로) |
| `~/.local/opt/wine-box64` | Wine `df15af3` x86_64 + WoW64(i386), 공식 x86 wine-mono/gecko |
| `~/.local/opt/llvm-mingw` | PE 크로스 컴파일러 (빌드용) |
| `~/builds/` | Wine 소스, 네이티브 tools, 빌드 디렉터리, amd64 libglvnd sysroot |
| `~/.wine-b64` | b64wine 프리픽스 (arm64 Wine의 `~/.wine`과 분리), 카카오톡 |
| `~/.local/bin/b64wine`, `~/.bashrc` alias | Wine 실행 래퍼 |
| `~/.box64rc` `[KakaoTalk.exe]` | Vox3.dll 우회 (아래) |
| `/opt/hnc/hoffice11` | 한컴오피스 (deb에서 추출, 패키지 설치는 안 함) |
| `~/.local/opt/hoffice-libs` | OpenSSL 1.1, ICU 63 (amd64, 구 Debian에서) |
| `~/.local/bin/hoffice` | 한컴오피스 실행 래퍼 |
| `~/.local/share/{applications,icons,mime}` | 메뉴 항목, 아이콘, MIME, 기본 앱 |

## 알아둘 점

**카카오톡 / box64**
- `Vox3.dll`(Themida) 안의 `pop dword [ebp+0x4ec8]`(`8f 85 c8 4e 00 00`,
  `0x11291abe`)를 box64 ARM64 dynarec가 인터프리터와 다른 값으로 실행해
  `"Vox3.dll" failed to initialize`로 죽는다(`BOX64_DYNAREC_TEST`로 확인).
  `~/.box64rc`에서 그 4K 페이지만 인터프리터로 돌려 우회한다(로그인 창까지 ~30초).
  카카오톡 업데이트로 Vox3.dll이 바뀌면 주소를 다시 찾아야 할 수 있다.
  box64 upstream은 AI 작성 PR을 받지 않으므로 고치려면 이슈로 보고할 것.
- 시스템 `/usr/share/wine/mono`(arm64 Wine 패키지)의 x86_64 DLL은 ARM64EC
  하이브리드라 box64에서 크래시 → 이 Wine은 공식 x86 wine-mono를 자기
  `share/wine`에 둔다.
- Wine 로컬 패치 `scripts/patches/wine-winemenubuilder-loader.patch`: winemenubuilder가
  메뉴·파일/프로토콜 연결에 `wine` 대신 `$WINEMENUBUILDER_LOADER`(b64wine)를 쓰게
  한다. 이게 없으면 메뉴의 카카오톡이 시스템 arm64 Wine으로 실행된다.

**한컴오피스**
- 번들 Qt 5.11.3에는 fcitx/XIM 플러그인이 없고 ibus만 있다. 세션의
  `QT_IM_MODULE=fcitx`면 조용히 compose로 떨어져 한글이 안 쳐진다 →
  래퍼가 `QT_IM_MODULE=ibus`로 고정, fcitx5가 ibus인 척 응답한다.
- Qt ibus 플러그인은 PATH에 `ibus-daemon` 실행 파일이 있어야만 켜진다(실행은 안 함).
  그래서 `ibus` 패키지를 설치한다(입력기는 계속 fcitx5). amd64 실기에서 한글이
  되던 이유가 이것(같은 deb, ibus 패키지 설치됨, .desktop에 `QT_IM_MODULE=ibus`).
- deb의 MIME 정의 중 표준 형식을 재정의하는 것(`*.pdf`, `*.docx`, `*.potx`, `*.thmx`)과
  표준 형식 재선언은 설치하지 않는다(PDF가 뷰어에서 안 열리게 되는 문제 방지).
  기본 앱은 한컴 고유 형식(hwp/hwpx/cell/show …)만 한컴으로, docx/xlsx/pptx/pdf는
  기존 기본 앱 유지.

## 환경

Debian 13 (trixie) arm64, Asahi 16K 페이지 커널, KDE Plasma(Wayland) + fcitx5,
MacBook Pro 13" M1에서 검증. 경로는 환경 변수로 바꿀 수 있다(각 스크립트 머리말).

## 라이선스

MIT (`LICENSE`). 스크립트와 조사는 AI(Claude)의 도움을 받아 작성했다.
box64, Wine, 카카오톡, 한컴오피스는 각자의 라이선스를 따른다.
