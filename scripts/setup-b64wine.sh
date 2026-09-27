#!/bin/bash
# setup-b64wine.sh - reproduce the box64 + x86_64 (WoW64) Wine setup used by
# b64wine on Asahi Linux (16K pages), and install KakaoTalk into it.
#
# Usage: setup-b64wine.sh [step ...]      (no argument: all steps in order)
#
# Steps (each one skips work that is already done, so re-running is safe):
#   deps        amd64 multiarch -dev packages and native build tools (sudo)
#   glvnd       amd64 libglvnd libs/headers extracted into a build-only sysroot
#   llvm-mingw  llvm-mingw toolchain (PE compilers for i386/x86_64)
#   wine-src    upstream Wine source snapshot
#   wine-tools  native (aarch64) Wine build tools
#   wine        x86_64 host + i386/x86_64 PE (WoW64) Wine build and install
#   addons      official x86 wine-mono and wine-gecko
#   box64       box64 built for Apple M1
#   launcher    ~/.local/bin/b64wine, bash alias, ~/.box64rc KakaoTalk section
#   kakaotalk   download the KakaoTalk installer and install it silently
#   menus       (re)generate the prefix's KDE menu entries and file/protocol
#               associations so they start programs through b64wine
#
# Environment: JOBS (default: nproc), WINEPREFIX (default: ~/.wine-b64),
# OPT (default: ~/.local/opt), BUILDS (default: ~/builds), BOX64_SRC (default:
# ~/box64-src), DOWNLOADS (default: <repo>/downloads).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPT="${OPT:-$HOME/.local/opt}"                    # installed toolchains/runtimes
BUILDS="${BUILDS:-$HOME/builds}"                  # sources and build trees
DOWNLOADS="${DOWNLOADS:-$SCRIPT_DIR/../downloads}"  # installers (not in git)
JOBS="${JOBS:-$(nproc)}"

WINE_COMMIT=df15af3                 # upstream wine, 11.18 + git
LLVM_MINGW_TAG=20260922
WINE_MONO_VERSION=11.3.0            # must match dlls/mscoree WINE_MONO_VERSION
WINE_GECKO_VERSION=2.47.4           # must match dlls/appwiz.cpl GECKO_VERSION
BOX64_SRC="${BOX64_SRC:-$HOME/box64-src}"
BOX64_REPO=https://github.com/ptitSeb/box64.git
BOX64_COMMIT=ac9b13a
KAKAO_URL=https://app-pc.kakaocdn.net/talk/win32/KakaoTalk_Setup.exe

WINE_SRC="$BUILDS/wine-$WINE_COMMIT"
WINE_TOOLS="$BUILDS/wx64-tools"
WINE_BUILD="$BUILDS/wx64-build"
WINE_ROOT="$OPT/wine-box64"
GLVND_SYSROOT="$BUILDS/amd64-glvnd-sysroot"
LLVM_MINGW="$OPT/llvm-mingw"
BOX64_BIN="$OPT/box64/bin/box64"

export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-b64}"

log() { printf '\n=== %s\n' "$*"; }
skip() { printf '    (already done: %s)\n' "$*"; }

step_deps() {
    log "deps: amd64 multiarch -dev packages and build tools"
    if ! dpkg --print-foreign-architectures | grep -qx amd64; then
        sudo dpkg --add-architecture amd64
        sudo apt-get update
    fi
    # libgl-dev/libegl-dev/libsdl2-dev:amd64 are left out on purpose: they pull
    # amd64 Mesa, which cannot match the Asahi arm64 Mesa version (see 'glvnd').
    sudo apt-get install -y --no-install-recommends \
        gcc-x86-64-linux-gnu pkgconf bison flex gettext make cmake git curl \
        xz-utils python3 libfreetype-dev \
        libx11-dev:amd64 libxext-dev:amd64 libxrender-dev:amd64 \
        libxrandr-dev:amd64 libxinerama-dev:amd64 libxcursor-dev:amd64 \
        libxi-dev:amd64 libxcomposite-dev:amd64 libxfixes-dev:amd64 \
        libxxf86vm-dev:amd64 libfreetype-dev:amd64 libfontconfig-dev:amd64 \
        libgnutls28-dev:amd64 libvulkan-dev:amd64 libpulse-dev:amd64 \
        libasound2-dev:amd64 libdbus-1-dev:amd64 libkrb5-dev:amd64 \
        libusb-1.0-0-dev:amd64
}

step_glvnd() {
    log "glvnd: amd64 libEGL/libGL for linking only (box64 wraps the native ones at runtime)"
    if [ -e "$GLVND_SYSROOT/usr/lib/x86_64-linux-gnu/libEGL.so" ]; then
        skip "$GLVND_SYSROOT"; return
    fi
    mkdir -p "$GLVND_SYSROOT/debs"
    (cd "$GLVND_SYSROOT/debs" &&
        apt-get download libglvnd0:amd64 libegl1:amd64 libgl1:amd64 libglx0:amd64 \
            libopengl0:amd64 libegl-dev:amd64 libgl-dev:amd64 libglx-dev:amd64 \
            libglvnd-dev:amd64 &&
        for f in *.deb; do dpkg-deb -x "$f" ..; done)
}

step_llvm_mingw() {
    log "llvm-mingw $LLVM_MINGW_TAG"
    local name="llvm-mingw-$LLVM_MINGW_TAG-ucrt-ubuntu-22.04-aarch64"
    if [ -x "$OPT/$name/bin/x86_64-w64-mingw32-clang" ]; then
        skip "$OPT/$name"
    else
        mkdir -p "$OPT"
        curl -fL "https://github.com/mstorsjo/llvm-mingw/releases/download/$LLVM_MINGW_TAG/$name.tar.xz" |
            tar xJ -C "$OPT"
    fi
    ln -sfn "$name" "$LLVM_MINGW"
}

step_wine_src() {
    log "wine source $WINE_COMMIT"
    if [ -f "$WINE_SRC/configure" ]; then
        skip "$WINE_SRC download"
    else
        mkdir -p "$WINE_SRC"
        curl -fL "https://gitlab.winehq.org/wine/wine/-/archive/$WINE_COMMIT/wine-$WINE_COMMIT.tar.gz" |
            tar xz -C "$WINE_SRC" --strip-components=1
    fi
    # Local patches (patches/wine-*.patch):
    #  - winemenubuilder-loader: menu entries/associations use
    #    $WINEMENUBUILDER_LOADER (b64wine) instead of the system "wine".
    local p
    for p in "$SCRIPT_DIR"/patches/wine-*.patch; do
        [ -e "$p" ] || continue
        if patch -d "$WINE_SRC" -p1 -R --dry-run -s -f < "$p" >/dev/null 2>&1; then
            skip "$(basename "$p")"
        else
            patch -d "$WINE_SRC" -p1 -N < "$p"
        fi
    done
}

step_wine_tools() {
    log "wine native tools"
    if [ -x "$WINE_TOOLS/tools/sfnt2fon/sfnt2fon" ] &&
       "$WINE_TOOLS/tools/sfnt2fon/sfnt2fon" 2>&1 | grep -q '\[options\]'; then
        skip "$WINE_TOOLS"
    else
        mkdir -p "$WINE_TOOLS"
        # FreeType is required: sfnt2fon builds the bitmap fonts.
        (cd "$WINE_TOOLS" && PATH="$LLVM_MINGW/bin:$PATH" "$WINE_SRC/configure" \
            --enable-win64 --without-x --without-gnutls --without-vulkan \
            --without-pulse --without-alsa --without-dbus --without-gstreamer \
            --without-cups --without-sane --without-pcap --without-usb \
            --without-krb5 --without-wayland --disable-tests &&
            make -j"$JOBS" __tooldeps__)
    fi
    # wrc of an out-of-tree tools build looks for nls/ next to the tools dir.
    mkdir -p "$WINE_TOOLS/nls"
    ln -sf "$WINE_SRC/nls/locale.nls" "$WINE_TOOLS/nls/locale.nls"
}

step_wine() {
    log "wine x86_64 + WoW64 build -> $WINE_ROOT"
    export PATH="$LLVM_MINGW/bin:$PATH"
    mkdir -p "$WINE_BUILD"
    if [ ! -f "$WINE_BUILD/Makefile" ]; then
        (cd "$WINE_BUILD" && PKG_CONFIG=x86_64-linux-gnu-pkg-config "$WINE_SRC/configure" \
            --host=x86_64-linux-gnu --build=aarch64-linux-gnu \
            --with-wine-tools="$WINE_TOOLS" --enable-archs=i386,x86_64 \
            --prefix="$WINE_ROOT" \
            --with-x --with-opengl --with-vulkan --with-pulse --with-alsa \
            --with-gnutls --with-freetype --with-fontconfig --with-dbus \
            --with-krb5 --with-usb --without-wayland --without-gstreamer \
            --without-cups --without-sane --without-pcap --without-oss \
            --disable-tests \
            LDFLAGS="-L$GLVND_SYSROOT/usr/lib/x86_64-linux-gnu -Wl,-rpath-link,$GLVND_SYSROOT/usr/lib/x86_64-linux-gnu")
    else
        skip "configure ($WINE_BUILD/Makefile exists)"
    fi
    for s in SONAME_LIBEGL SONAME_LIBVULKAN SONAME_LIBGNUTLS SONAME_LIBFREETYPE; do
        grep -q "define $s " "$WINE_BUILD/include/config.h" ||
            { echo "missing $s in config.h, check $WINE_BUILD/config.log" >&2; exit 1; }
    done
    make -C "$WINE_BUILD" -j"$JOBS"
    make -C "$WINE_BUILD" -j"$JOBS" install
}

step_addons() {
    log "wine-mono $WINE_MONO_VERSION / wine-gecko $WINE_GECKO_VERSION (official x86 builds)"
    # The system /usr/share/wine/mono comes from the arm64 wine package and holds
    # ARM64EC hybrid binaries, which crash under box64. This Wine looks in its
    # own share/wine first.
    local share="$WINE_ROOT/share/wine"
    mkdir -p "$share/mono" "$share/gecko"
    if [ -d "$share/mono/wine-mono-$WINE_MONO_VERSION" ]; then
        skip "wine-mono"
    else
        curl -fL "https://dl.winehq.org/wine/wine-mono/$WINE_MONO_VERSION/wine-mono-$WINE_MONO_VERSION-x86.tar.xz" |
            tar xJ -C "$share/mono"
    fi
    for arch in x86 x86_64; do
        if [ -d "$share/gecko/wine-gecko-$WINE_GECKO_VERSION-$arch" ]; then
            skip "wine-gecko $arch"
        else
            curl -fL "https://dl.winehq.org/wine/wine-gecko/$WINE_GECKO_VERSION/wine-gecko-$WINE_GECKO_VERSION-$arch.tar.xz" |
                tar xJ -C "$share/gecko"
        fi
    done
}

step_box64() {
    log "box64 $BOX64_COMMIT (M1) -> $BOX64_BIN"
    [ -d "$BOX64_SRC/.git" ] || git clone "$BOX64_REPO" "$BOX64_SRC"
    if [ "$(git -C "$BOX64_SRC" rev-parse --short=7 HEAD)" != "$BOX64_COMMIT" ]; then
        git -C "$BOX64_SRC" fetch origin
        git -C "$BOX64_SRC" checkout "$BOX64_COMMIT"
    fi
    if [ -x "$BOX64_BIN" ] && "$BOX64_BIN" --version 2>&1 | grep -q "$BOX64_COMMIT"; then
        skip "$BOX64_BIN"; return
    fi
    cmake -S "$BOX64_SRC" -B "$BOX64_SRC/build-m1" -DM1=ON -DARM_DYNAREC=ON \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo
    make -C "$BOX64_SRC/build-m1" -j"$JOBS"
    install -D -m755 "$BOX64_SRC/build-m1/box64" "$BOX64_BIN"
}

step_launcher() {
    log "launcher: ~/.local/bin/b64wine, alias, ~/.box64rc"
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/b64wine" <<'EOF'
#!/bin/sh
# b64wine - run the x86_64 (WoW64) Wine build under box64.
#
#   b64wine program.exe [args]     run a Windows program
#   b64wine winecfg | regedit ...  run a builtin Wine program
#   b64wine wineserver -k          talk to this Wine's wineserver
#
# Environment overrides:
#   WINEPREFIX        prefix to use (default: ~/.wine-b64, kept apart from
#                     the native arm64 Wine's ~/.wine)
#   B64WINE_BOX64     box64 binary (default: ~/.local/opt/box64/bin/box64)
#   B64WINE_ROOT      Wine install root (default: ~/.local/opt/wine-box64)
#   BOX64_LOG etc.    passed through to box64 unchanged

BOX64="${B64WINE_BOX64:-$HOME/.local/opt/box64/bin/box64}"
WINE_ROOT="${B64WINE_ROOT:-$HOME/.local/opt/wine-box64}"

export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-b64}"
export BOX64_LOG="${BOX64_LOG:-0}"
export BOX64_NOBANNER="${BOX64_NOBANNER:-1}"
# Menu entries and file/protocol associations that winemenubuilder writes
# (e.g. when an installer adds a Start Menu shortcut) must start this Wine
# through box64, not the system "wine" (needs the winemenubuilder patch in
# scripts/patches of this repository).
export WINEMENUBUILDER_LOADER="${WINEMENUBUILDER_LOADER:-$HOME/.local/bin/b64wine}"
# Only the Asahi Vulkan driver applies here; probing the virtio/gfxstream
# ICDs just prints DRM_VIRTGPU errors.
if [ -z "$VK_DRIVER_FILES" ] && [ -z "$VK_ICD_FILENAMES" ] &&
   [ -f /usr/share/vulkan/icd.d/asahi_icd.json ]; then
    export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/asahi_icd.json
fi

for f in "$BOX64" "$WINE_ROOT/bin/wine"; do
    if [ ! -x "$f" ]; then
        echo "b64wine: $f not found" >&2
        exit 127
    fi
done

case "$1" in
wineserver)
    shift
    exec "$BOX64" "$WINE_ROOT/bin/wineserver" "$@"
    ;;
esac

exec "$BOX64" "$WINE_ROOT/bin/wine" "$@"
EOF
    chmod +x "$HOME/.local/bin/b64wine"

    if grep -q '^alias b64wine=' "$HOME/.bashrc" 2>/dev/null; then
        skip "alias in ~/.bashrc"
    else
        printf '\n# x86_64 Wine (WoW64) under box64, prefix ~/.wine-b64\nalias b64wine="$HOME/.local/bin/b64wine"\n' >> "$HOME/.bashrc"
    fi

    if grep -q '^\[KakaoTalk.exe\]' "$HOME/.box64rc" 2>/dev/null; then
        skip "[KakaoTalk.exe] in ~/.box64rc"
    else
        cat >> "$HOME/.box64rc" <<'EOF'

# KakaoTalk PC 26.8.1.5315 (Themida-protected, 32-bit, run through b64wine).
# The ARM64 dynarec computes a wrong value for `pop dword [ebp+0x4ec8]`
# (8f 85 c8 4e 00 00) at 0x11291abe in Vox3.dll's .themida section
# (Vox3 loads at its fixed base 0x10000000; BOX64_DYNAREC_TEST shows the
# store differing from the interpreter), after which "Vox3.dll failed to
# initialize" with c0000005. Keeping that one 4K page in the interpreter is
# enough; the rest stays on the dynarec (~30 s to the login window).
# Re-check the page after a KakaoTalk update changes Vox3.dll.
[KakaoTalk.exe]
BOX64_NODYNAREC=0x11291000-0x11292000
EOF
    fi
}

step_kakaotalk() {
    log "KakaoTalk into $WINEPREFIX"
    local exe="$WINEPREFIX/drive_c/Program Files (x86)/Kakao/KakaoTalk/KakaoTalk.exe"
    if [ -f "$exe" ]; then
        skip "$exe"; return
    fi
    mkdir -p "$DOWNLOADS"
    curl -fL -o "$DOWNLOADS/KakaoTalk_Setup.exe" "$KAKAO_URL"
    [ -d "$WINEPREFIX" ] || "$HOME/.local/bin/b64wine" wineboot -i
    "$HOME/.local/bin/b64wine" "$DOWNLOADS/KakaoTalk_Setup.exe" /S
    [ -f "$exe" ] || { echo "KakaoTalk.exe not found after install" >&2; exit 1; }
}

step_menus() {
    log "menus: KDE entries and associations of $WINEPREFIX through b64wine"
    local b64="$HOME/.local/bin/b64wine" apps="$HOME/.local/share/applications" f k
    [ -d "$WINEPREFIX" ] || { skip "no prefix yet"; return; }
    # Entries written before the winemenubuilder patch start the system wine.
    for f in "$apps"/wine-*.desktop "$apps"/wine/Programs/*.desktop; do
        [ -f "$f" ] || continue
        grep -q "WINEPREFIX=$WINEPREFIX\"" "$f" || continue
        grep -q "^Exec=.* $b64 " "$f" && continue
        echo "    regenerating $(basename "$f")"
        rm -f "$f"
    done
    # winemenubuilder only rewrites associations it has not recorded yet.
    for k in $("$b64" reg query 'HKCU\Software\Wine\FileOpenAssociations' 2>/dev/null |
               tr -d '\r' | sed -n 's/^HKEY_CURRENT_USER\\Software\\Wine\\FileOpenAssociations\\//p'); do
        grep -qs "$b64" "$apps/wine-extension-${k#.}.desktop" "$apps/wine-protocol-$k.desktop" && continue
        "$b64" reg delete "HKCU\\Software\\Wine\\FileOpenAssociations\\$k" /f >/dev/null 2>&1 || true
    done
    "$b64" winemenubuilder -a
    find "$WINEPREFIX/drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs" \
         "$WINEPREFIX/drive_c/users/$USER/AppData/Roaming/Microsoft/Windows/Start Menu/Programs" \
         -name '*.lnk' 2>/dev/null | while read -r f; do
        "$b64" winemenubuilder -w "$("$b64" winepath -w "$f" 2>/dev/null | tr -d '\r')"
    done
    command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 >/dev/null 2>&1 || true
}

ALL_STEPS=(deps glvnd llvm-mingw wine-src wine-tools wine addons box64 launcher kakaotalk menus)
steps=("$@")
[ ${#steps[@]} -eq 0 ] && steps=("${ALL_STEPS[@]}")

for s in "${steps[@]}"; do
    case "$s" in
    deps|glvnd|llvm-mingw|wine-src|wine-tools|wine|addons|box64|launcher|kakaotalk|menus)
        "step_${s//-/_}" ;;
    *)
        echo "unknown step: $s (steps: ${ALL_STEPS[*]})" >&2; exit 2 ;;
    esac
done

log "done"
