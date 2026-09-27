# korean-asahi

[English](#english) | [한국어](#한국어)

---

## English

Setup scripts for running x86_64 Korean desktop apps with box64 on Apple Silicon
(M1, 16K-page kernel) Debian trixie + KDE Plasma. Two setups are reproduced:

- **b64wine**: box64 + x86_64/WoW64 Wine → KakaoTalk PC (32-bit, Themida-protected)
- **hoffice**: box64 + Hancom Office for Linux (amd64 deb) → Hangul/Hword/Hcell/Hshow

Both come with fcitx5 Korean input and KDE menu entries, icons and file associations.

### Usage

```bash
git clone https://github.com/gg582/korean-asahi.git
cd korean-asahi

# 1) box64 + Wine + KakaoTalk (builds Wine, takes a while the first time)
scripts/setup-b64wine.sh

# 2) Hancom Office
scripts/setup-hoffice.sh
```

The installers (KakaoTalk installer, Hancom Office deb) are downloaded from each
vendor's official URL into `downloads/` (not part of the repository). Check
Hancom's license terms for Hancom Office yourself.

Without arguments every step runs in order. Each step skips work that is already
done, so re-running is safe, and single steps can be run, e.g.
`setup-b64wine.sh menus` (step lists are at the top of each script). Steps that
need sudo (`deps`, `install`) ask for the password.

Launch: "카카오톡", "한글 2022 Beta" etc. in the KDE menu, or double-click a file.
From a terminal: `b64wine program.exe` (alias), `~/.local/bin/hoffice hwp doc.hwp`.

### What gets installed

| Location | Contents |
|---|---|
| `~/.local/opt/box64/bin/box64` | box64 `ac9b13a`, built with `-DM1=ON` (system `/usr/bin/box64` untouched) |
| `~/.local/opt/wine-box64` | Wine `df15af3` x86_64 + WoW64 (i386), official x86 wine-mono/gecko |
| `~/.local/opt/llvm-mingw` | PE cross compilers (build only) |
| `~/builds/` | Wine source, native tools, build tree, amd64 libglvnd sysroot |
| `~/.wine-b64` | b64wine prefix (separate from the arm64 Wine's `~/.wine`), KakaoTalk |
| `~/.local/bin/b64wine`, `~/.bashrc` alias | Wine launcher |
| `~/.box64rc` `[KakaoTalk.exe]` | Vox3.dll workaround (below) |
| `/opt/hnc/hoffice11` | Hancom Office (extracted from the deb, package not installed) |
| `~/.local/opt/hoffice-libs` | OpenSSL 1.1, ICU 63 (amd64, from older Debian releases) |
| `~/.local/bin/hoffice` | Hancom Office launcher |
| `~/.local/share/{applications,icons,mime}` | menu entries, icons, MIME types, default apps |

### Notes

**KakaoTalk / box64**
- box64's ARM64 dynarec executes `pop dword [ebp+0x4ec8]` (`8f 85 c8 4e 00 00`,
  `0x11291abe`) inside `Vox3.dll` (Themida) with a different result than the
  interpreter, and KakaoTalk dies with `"Vox3.dll" failed to initialize`
  (confirmed with `BOX64_DYNAREC_TEST`). `~/.box64rc` runs only that 4K page in
  the interpreter (~30 s to the login window). A KakaoTalk update that changes
  Vox3.dll may move the address. box64 upstream does not accept AI-written PRs,
  so report it as an issue if you want it fixed there.
- The x86_64 DLLs in the system `/usr/share/wine/mono` (arm64 Wine package) are
  ARM64EC hybrids and crash under box64, so this Wine keeps the official x86
  wine-mono in its own `share/wine`.
- Local Wine patch `scripts/patches/wine-winemenubuilder-loader.patch`: makes
  winemenubuilder write `$WINEMENUBUILDER_LOADER` (b64wine) instead of `wine`
  into menu entries and file/protocol associations. Without it, KakaoTalk in the
  menu would start with the system arm64 Wine.

**Hancom Office**
- The bundled Qt 5.11.3 has no fcitx/XIM plugin, only ibus. With the session's
  `QT_IM_MODULE=fcitx` it silently falls back to compose and Korean cannot be
  typed, so the launcher forces `QT_IM_MODULE=ibus` and fcitx5 answers as ibus.
- Qt's ibus plugin only enables itself when an `ibus-daemon` executable exists in
  PATH (it is never started), so the `ibus` package is installed (fcitx5 stays the
  input method). This is why Korean input worked on a real amd64 machine (same
  deb, ibus package installed, `QT_IM_MODULE=ibus` in the .desktop files).
- MIME definitions in the deb that redefine standard formats (`*.pdf`, `*.docx`,
  `*.potx`, `*.thmx`) and re-declarations of standard types are not installed
  (otherwise PDFs would stop opening in the PDF viewer). Hancom becomes the
  default app only for Hancom's own formats (hwp/hwpx/cell/show …); docx, xlsx,
  pptx and pdf keep their existing defaults.

### Environment

Tested on Debian 13 (trixie) arm64, Asahi 16K-page kernel, KDE Plasma (Wayland)
+ fcitx5, MacBook Pro 13" M1. Paths can be changed with environment variables
(see the top of each script).

### License

MIT (`LICENSE`). The scripts and the investigation were written with AI (Claude)
assistance. box64, Wine, KakaoTalk and Hancom Office are under their own licenses.

---

## 한국어

Apple Silicon(M1, 16K 페이지 커널) Debian trixie + KDE Plasma에서 x86_64 한국
데스크톱 앱을 box64로 돌리는 구성. 두 가지를 스크립트로 재현한다.

- **b64wine**: box64 + x86_64/WoW64 Wine → 카카오톡 PC(32비트, Themida 보호)
- **hoffice**: box64 + 한컴오피스 for Linux(amd64 deb) → 한글/한워드/한셀/한쇼

둘 다 fcitx5 한글 입력, KDE 메뉴·아이콘·파일 연결까지 설정한다.

### 사용

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

### 설치되는 것

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

### 알아둘 점

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

### 환경

Debian 13 (trixie) arm64, Asahi 16K 페이지 커널, KDE Plasma(Wayland) + fcitx5,
MacBook Pro 13" M1에서 검증. 경로는 환경 변수로 바꿀 수 있다(각 스크립트 머리말).

### 라이선스

MIT (`LICENSE`). 스크립트와 조사는 AI(Claude)의 도움을 받아 작성했다.
box64, Wine, 카카오톡, 한컴오피스는 각자의 라이선스를 따른다.
