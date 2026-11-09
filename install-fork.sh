#!/bin/sh
# Install herdr from the tuananh131001/herdr fork by building it from source.
#
#   curl -fsSL https://raw.githubusercontent.com/tuananh131001/herdr/master/install-fork.sh | sh
#
# The fork publishes no release binaries, so this builds with cargo. The Rust
# and Zig toolchains come from mise, which is installed when it is missing.
#
# Environment:
#   HERDR_INSTALL_DIR  install directory (default: ~/.local/bin)
#   HERDR_FORK_REPO    git repository (default: https://github.com/tuananh131001/herdr)
#   HERDR_FORK_REF     branch to build (default: master)
#   HERDR_FORK_REV     commit to build; overrides HERDR_FORK_REF
#   HERDR_SKIP_HANDOFF set to 1 to leave a running server on its old binary
set -eu

BIN="herdr"
REPO="${HERDR_FORK_REPO:-https://github.com/tuananh131001/herdr}"
REF="${HERDR_FORK_REF:-master}"
REV="${HERDR_FORK_REV:-}"
INSTALL_DIR="${HERDR_INSTALL_DIR:-$HOME/.local/bin}"
# Keep in step with rust-toolchain.toml and the Zig version the vendored
# libghostty-vt requires.
RUST_VERSION="1.96.1"
ZIG_VERSION="0.17.0"

main() {
    echo ""
    echo "  herdr fork installer (build from source)"
    echo "  ${REPO}"
    echo ""

    case "$(uname -s)" in
        Linux|Darwin) ;;
        *) err "unsupported OS: $(uname -s)" ;;
    esac

    need curl
    need cc

    find_mise

    if [ -n "$REV" ]; then
        source_args="--rev ${REV}"
        log "building ${BIN} at commit ${REV}..."
    else
        source_args="--branch ${REF}"
        log "building ${BIN} from branch ${REF}..."
    fi
    log "this compiles Rust and Zig code and can take several minutes"

    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT

    # Install into a scratch root so cargo's own install tracking is not
    # touched, then move the binary into place ourselves.
    # shellcheck disable=SC2086 # source_args is two intentional words
    "$MISE" exec "rust@${RUST_VERSION}" "zig@${ZIG_VERSION}" -- \
        cargo install --locked --git "$REPO" $source_args --root "${TMP}/root" "$BIN" \
        || err "build failed"

    built="${TMP}/root/bin/${BIN}"
    [ -x "$built" ] || err "build did not produce ${built}"

    # Stage beside the target and rename so a running binary is replaced
    # atomically.
    mkdir -p "$INSTALL_DIR"
    staged="${INSTALL_DIR}/.${BIN}-install.$$"
    cp "$built" "$staged"
    chmod 755 "$staged"
    mv -f "$staged" "${INSTALL_DIR}/${BIN}"

    log "installed $("${INSTALL_DIR}/${BIN}" --version) to ${INSTALL_DIR}/${BIN}"

    check_path
    handoff_server

    echo ""
}

find_mise() {
    if command -v mise >/dev/null 2>&1; then
        MISE="$(command -v mise)"
    elif [ -x "$HOME/.local/bin/mise" ]; then
        MISE="$HOME/.local/bin/mise"
    else
        log "installing mise to provide Rust ${RUST_VERSION} and Zig ${ZIG_VERSION}..."
        curl -fsSL https://mise.run | sh || err "mise install failed"
        MISE="$HOME/.local/bin/mise"
        [ -x "$MISE" ] || err "mise was not installed at ${MISE}"
    fi
}

check_path() {
    case ":${PATH}:" in
        *":${INSTALL_DIR}:"*)
            found="$(command -v "$BIN" 2>/dev/null || true)"
            if [ -n "$found" ] && [ "$found" != "${INSTALL_DIR}/${BIN}" ]; then
                echo ""
                warn "${found} comes first on your PATH and shadows this install"
                echo "  remove it (for example: brew uninstall herdr) or put ${INSTALL_DIR} earlier in PATH"
            fi
            ;;
        *)
            echo ""
            warn "${INSTALL_DIR} is not in your PATH"
            echo "  add it to your shell config:"
            echo ""
            echo "    export PATH=\"${INSTALL_DIR}:\$PATH\""
            ;;
    esac
}

# Move a running herdr server onto the new binary without dropping sessions.
# Only when the new binary is the herdr on PATH, so an install elsewhere never
# repoints the live server.
handoff_server() {
    new="${INSTALL_DIR}/${BIN}"
    [ "${HERDR_SKIP_HANDOFF:-}" = "1" ] && return 0
    [ "$(command -v "$BIN" 2>/dev/null || true)" = "$new" ] || return 0
    if "$new" status server 2>/dev/null | grep -q '^status: running'; then
        log "handing off the running server to the new binary..."
        "$new" server live-handoff --import-exe "$new" \
            || warn "live handoff failed; restart herdr to use the new binary"
    fi
}

log()  { printf '  \033[32m>\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
err()  { printf '  \033[31mx\033[0m %s\n' "$1" >&2; exit 1; }

need() {
    if ! command -v "$1" >/dev/null 2>&1; then
        err "requires '$1'; install it first (on macOS: xcode-select --install)"
    fi
}

main "$@"
