#!/bin/bash
# setup-hoffice.sh - install Hancom Office for Linux (amd64 .deb) and run it
# under box64 on Asahi Linux, with Korean input through fcitx5.
#
# Usage: setup-hoffice.sh [step ...]      (no argument: all steps in order)
#
# Steps (each one skips work that is already done, so re-running is safe):
#   download   fetch the hoffice .deb from Hancom's CDN
#   deps       amd64 libharfbuzz-icu, and the ibus package (sudo)
#   compat     OpenSSL 1.1 and ICU 63 (amd64) from older Debian releases,
#              extracted into a private library directory
#   install    extract /opt/hnc from the .deb (sudo); the package itself is not
#              installed because libglu1:amd64 would pull amd64 Mesa
#   launcher   ~/.local/bin/hoffice wrapper
#   desktop    KDE menu entries, icons, MIME types, default apps for Hancom
#              formats (user level, ~/.local/share)
#
# Environment: DOWNLOADS (default: <repo>/downloads).
#
# box64 comes from setup-b64wine.sh (~/.local/opt/box64/bin/box64); the
# wrapper falls back to /usr/bin/box64.
#
# Why Korean input needs this setup (compared against a real amd64 Debian 13
# machine with the same hoffice build, where it works):
#   - The bundled Qt 5.11.3 only ships compose/ibus/virtualkeyboard input
#     plugins. The session's QT_IM_MODULE=fcitx names a plugin it does not have
#     and silently falls back to "compose" -> no Korean. The launcher therefore
#     forces QT_IM_MODULE=ibus (the amd64 machine does the same by editing the
#     .desktop files to "env QT_IM_MODULE=ibus ...").
#   - fcitx5 answers as org.freedesktop.IBus and writes ~/.config/ibus/bus/*,
#     so the ibus plugin talks to fcitx5 directly.
#   - Qt's ibus plugin only enables itself when an ibus-daemon executable exists
#     in PATH (it never starts it). The amd64 machine has the ibus package
#     installed; here it is installed for that reason only (fcitx5 stays the IM).

set -euo pipefail

HOFFICE_VERSION=11.20.0.1496
DEB_NAME="hoffice_${HOFFICE_VERSION}_amd64.deb"
DEB_URL="https://cdn.hancom.com/pds/hnc/DOWN/gooroom/$DEB_NAME"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOWNLOADS="${DOWNLOADS:-$SCRIPT_DIR/../downloads}"  # installers (not in git)
DEB="$DOWNLOADS/$DEB_NAME"
ROOT=/opt/hnc/hoffice11
LIBS="$HOME/.local/opt/hoffice-libs"

ICU63_URL=https://archive.debian.org/debian/pool/main/i/icu/libicu63_63.1-6+deb10u3_amd64.deb
SSL11_URL=https://deb.debian.org/debian/pool/main/o/openssl/libssl1.1_1.1.1w-0+deb11u1_amd64.deb

log() { printf '\n=== %s\n' "$*"; }
skip() { printf '    (already done: %s)\n' "$*"; }

step_download() {
    log "download $DEB_NAME"
    if [ -f "$DEB" ] && dpkg-deb -f "$DEB" Version 2>/dev/null | grep -qx "$HOFFICE_VERSION"; then
        skip "$DEB"; return
    fi
    mkdir -p "$DOWNLOADS"
    # The CDN only serves the file with Hancom's Host/Referer headers.
    curl -fL -H "Host: cdn.hancom.com" -H "Referer: https://www.hancom.com/cs_center" \
        -o "$DEB.part" "$DEB_URL"
    mv "$DEB.part" "$DEB"
}

step_deps() {
    log "deps: libharfbuzz-icu0:amd64 (Bidi engine, Hancell, Hanshow), ibus (see header)"
    if ! dpkg --print-foreign-architectures | grep -qx amd64; then
        sudo dpkg --add-architecture amd64
        sudo apt-get update
    fi
    sudo apt-get install -y --no-install-recommends libharfbuzz-icu0:amd64 ibus libglu1-mesa
}

step_compat() {
    log "compat libs: OpenSSL 1.1 (Hword) and ICU 63 (equation editor) -> $LIBS"
    if [ -e "$LIBS/libssl.so.1.1" ] && [ -e "$LIBS/libicuuc.so.63" ]; then
        skip "$LIBS"; return
    fi
    local tmp; tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' RETURN
    (cd "$tmp" && curl -fLO "$ICU63_URL" && curl -fLO "$SSL11_URL" &&
        for f in *.deb; do dpkg-deb -x "$f" x; done)
    mkdir -p "$LIBS"
    cp -a "$tmp"/x/usr/lib/x86_64-linux-gnu/libicu*.so.63* \
          "$tmp"/x/usr/lib/x86_64-linux-gnu/libssl.so.1.1 \
          "$tmp"/x/usr/lib/x86_64-linux-gnu/libcrypto.so.1.1 "$LIBS/"
}

step_install() {
    log "install $ROOT from $DEB_NAME"
    local marker="$ROOT/.installed-from"
    if [ -f "$marker" ] && [ "$(cat "$marker")" = "$DEB_NAME" ]; then
        skip "$ROOT"; return
    fi
    dpkg-deb --fsys-tarfile "$DEB" | sudo tar -x -C / ./opt/hnc
    echo "$DEB_NAME" | sudo tee "$marker" >/dev/null
}

step_launcher() {
    log "launcher: ~/.local/bin/hoffice"
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/hoffice" <<'EOF'
#!/bin/sh
# hoffice - run Hancom Office for Linux (amd64 build) under box64.
#
#   hoffice hwp [file]      Hangul (hwp)
#   hoffice hword [file]    Hancom Word (docx)
#   hoffice hcl [file]      Hancell (xlsx)
#   hoffice hsl [file]      Hanshow (pptx)
#
# Korean input: the bundled Qt 5.11 has no fcitx/XIM plugin, only ibus. fcitx5
# answers as org.freedesktop.IBus (its ibusfrontend addon), so the bundled ibus
# plugin talks to fcitx5 directly. That plugin only enables itself when an
# ibus-daemon executable exists in PATH (it never runs it), so the ibus package
# must be installed even though fcitx5 stays the input method.
#
# Environment overrides: HOFFICE_ROOT, HOFFICE_LIBS, HOFFICE_BOX64,
# HOFFICE_IM_MODULE (Qt input module to use, default "ibus").

ROOT="${HOFFICE_ROOT:-/opt/hnc/hoffice11}"
LIBS="${HOFFICE_LIBS:-$HOME/.local/opt/hoffice-libs}"
BOX64="${HOFFICE_BOX64:-$HOME/.local/opt/box64/bin/box64}"
[ -x "$BOX64" ] || BOX64=/usr/bin/box64

app="${1:-hwp}"
case "$app" in
hwp|hword|hcl|hsl) shift ;;
*) app=hwp ;;
esac

if [ ! -x "$ROOT/Bin/$app" ]; then
    echo "hoffice: $ROOT/Bin/$app not found" >&2
    exit 127
fi

# The session's QT_IM_MODULE (usually "fcitx") names a plugin the bundled Qt
# does not have, which silently falls back to "compose" (no Korean input).
export QT_IM_MODULE="${HOFFICE_IM_MODULE:-ibus}"
export XMODIFIERS="${XMODIFIERS:-@im=fcitx}"
# The bundled Qt only has X11 (xcb) usable under box64; run through XWayland.
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"
# OpenSSL 1.1 (Hword) and ICU 63 (equation editor) are no longer in Debian.
export BOX64_LD_LIBRARY_PATH="$LIBS${BOX64_LD_LIBRARY_PATH:+:$BOX64_LD_LIBRARY_PATH}"
export BOX64_LOG="${BOX64_LOG:-0}"
export BOX64_NOBANNER="${BOX64_NOBANNER:-1}"

cd "$ROOT/Bin" || exit 1
exec "$BOX64" "./$app" "$@"
EOF
    chmod +x "$HOME/.local/bin/hoffice"
}

step_desktop() {
    log "desktop: KDE menu entries, icons, MIME types and default apps (user level)"
    local share="$HOME/.local/share" tmp app
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' RETURN
    dpkg-deb --fsys-tarfile "$DEB" | tar -x -C "$tmp" ./usr/share

    mkdir -p "$share/icons" "$share/mime/packages" "$share/applications"
    cp -a "$tmp/usr/share/icons/hicolor" "$share/icons/"

    # The vendor entries also list docx/xlsx/pptx/pdf/... Remember the current
    # default app of every non-Hancom type they claim, to restore it afterwards
    # (a user-level mimeinfo.cache listing these entries would otherwise make
    # them the default). Entries from an earlier run are removed first so the
    # snapshot reflects the defaults without them.
    rm -f "$share/applications"/hoffice11-{hwp,hword,hcl,hsl}.desktop
    update-desktop-database "$share/applications" 2>/dev/null || true
    command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
    local others=() t
    mapfile -t others < <(sed -n 's/^MimeType=//p' "$tmp"/usr/share/applications/hoffice11-*.desktop |
                          tr ';' '\n' | grep -vE '^$|^application/(vnd\.hancom\.|x-hw)' | sort -u)
    declare -A before=()
    for t in "${others[@]}"; do
        before[$t]=$(xdg-mime query default "$t" 2>/dev/null || true)
    done

    # Only Hancom's own types are installed:
    #  - Re-declarations of standard types (xlsx, pptx, csv, *.bak, ...) are
    #    dropped: the system database already has them, and the vendor copies
    #    only attach Hancom icons to files that keep opening elsewhere.
    #  - Hancom types for extensions that already belong to a standard type
    #    (*.pdf -> vnd.hancom.pdf, *.docx -> vnd.hancom.docx, *.potx, *.thmx)
    #    are dropped too: they would retype every such file on the system
    #    (PDFs would stop opening in the PDF viewer).
    python3 - "$tmp/usr/share/mime/packages" "$share/mime/packages" <<'PY'
import glob, os, re, sys
src, dst = sys.argv[1:3]
system = {}
with open('/usr/share/mime/globs2') as f:
    for line in f:
        if line.startswith('#'):
            continue
        _, mtype, pattern = line.rstrip('\n').split(':', 2)[:3]
        system.setdefault(pattern.split(':')[0], mtype)
for path in glob.glob(os.path.join(src, '*.xml')):
    text = open(path, encoding='utf-8').read()
    def keep(m):
        mtype = m.group(1)
        if not re.match(r'application/(vnd\.hancom\.|x-hw)', mtype):
            return 
        for pattern in re.findall(r'<glob pattern="([^"]+)"', m.group(0)):
            if system.get(pattern, mtype) != mtype:
                print(f'    skipping {mtype} ({pattern} is {system[pattern]})')
                return ''
        return m.group(0)
    text = re.sub(r'\s*<mime-type type="([^"]+)".*?</mime-type>', keep, text, flags=re.S)
    open(os.path.join(dst, os.path.basename(path)), 'w', encoding='utf-8').write(text)
PY
    update-mime-database "$share/mime"

    for app in hwp hword hcl hsl; do
        # Same file name as the vendor entry, so this user-level one wins.
        sed -e "s|^Exec=.*|Exec=$HOME/.local/bin/hoffice $app %f|" \
            -e '/^StartupWMClass=/d' -e '/^InitialPreference=/d' \
            "$tmp/usr/share/applications/hoffice11-$app.desktop" |
            sed -e "/^\[Desktop Entry\]/a StartupWMClass=$app" \
            > "$share/applications/hoffice11-$app.desktop"

        # Default app only for Hancom's own formats; docx/xlsx/pptx/pdf keep
        # whatever default the user already has.
        local types
        types=$(sed -n 's/^MimeType=//p' "$share/applications/hoffice11-$app.desktop" | tr ';' '\n' |
                grep -E '^application/(vnd\.hancom\.|x-hw)' |
                while read -r t; do
                    [ -n "$(grep -l "type=\"$t\"" "$share/mime/packages/"*.xml /usr/share/mime/packages/*.xml 2>/dev/null)" ] && echo "$t"
                done)
        [ -n "$types" ] && xdg-mime default "hoffice11-$app.desktop" $types 2>/dev/null
    done
    update-desktop-database "$share/applications" 2>/dev/null || true
    command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 --noincremental >/dev/null 2>&1 || true

    for t in "${others[@]}"; do
        local now; now=$(xdg-mime query default "$t" 2>/dev/null || true)
        if [ -n "${before[$t]}" ] && [ "$now" != "${before[$t]}" ]; then
            echo "    keeping default for $t: ${before[$t]}"
            xdg-mime default "${before[$t]}" "$t" 2>/dev/null
        fi
    done
}

ALL_STEPS=(download deps compat install launcher desktop)
steps=("$@")
[ ${#steps[@]} -eq 0 ] && steps=("${ALL_STEPS[@]}")

for s in "${steps[@]}"; do
    case "$s" in
    download|deps|compat|install|launcher|desktop) "step_$s" ;;
    *) echo "unknown step: $s (steps: ${ALL_STEPS[*]})" >&2; exit 2 ;;
    esac
done

log "done - run: ~/.local/bin/hoffice hwp"
