#!/bin/sh
#~ Rust Project
SCRIPT_DIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
SCRIPT_NAME=`basename $0`

if [ -t 1 ]; then
    ANSI_RESET="$(tput sgr0)"
    ANSI_RED="`[ $(tput colors) -ge 16 ] && tput setaf 9 || tput setaf 1 bold`"
    ANSI_YELLOW="`[ $(tput colors) -ge 16 ] && tput setaf 11 || tput setaf 3 bold`"
    ANSI_MAGENTA="`[ $(tput colors) -ge 16 ] && tput setaf 13 || tput setaf 5 bold`"
    ANSI_PURPLE="$(tput setaf 5)"
    ANSI_CYAN="`[ $(tput colors) -ge 16 ] && tput setaf 14 || tput setaf 6 bold`"
fi

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $SCRIPT_NAME [target]..."
    echo
    echo "Targets:"
    echo "  clean      Clean all build artifacts"
    echo "  run        Run the project"
    echo "  debug      Compile in debug mode"
    echo "  release    Compile in release mode"
    echo
    echo "Actions with '~' prefix are negated"
    echo
    echo "Examples:"
    echo "  make release         - Compile in release mode"
    echo "  make ~clean release  - Compile in release mode without cleaning"
    echo
    exit 0
fi


if ! [ -e "$SCRIPT_DIR/.meta" ]; then
    echo "${ANSI_RED}Meta file not found${ANSI_RESET}" >&2
    exit 113
fi

if ! command -v git >/dev/null; then
    echo "${ANSI_YELLOW}Missing git command${ANSI_RESET}"
fi


HAS_CHANGES=$( git status -s 2>&1 | wc -l )
if [ "$HAS_CHANGES" -gt 0 ]; then
    echo "${ANSI_YELLOW}Uncommitted changes present${ANSI_RESET}"
fi


PROJECT_NAME=$( cat "$SCRIPT_DIR/.meta" | grep -E "^PROJECT_NAME:" | sed  -n 1p | cut -d: -sf2- | xargs )
if [ "$PROJECT_NAME" = "" ]; then
    echo "${ANSI_PURPLE}Project name ........: ${ANSI_RED}not found${ANSI_RESET}"
    exit 113
fi
echo "${ANSI_PURPLE}Project name ........: ${ANSI_MAGENTA}$PROJECT_NAME${ANSI_RESET}"

GIT_INDEX=$( git rev-list --count HEAD 2>/dev/null )
if [ "$GIT_INDEX" = "" ]; then GIT_INDEX=0; fi

GIT_HASH=$( git log -n 1 --format=%h 2>/dev/null )
if [ "$GIT_HASH" = "" ]; then GIT_HASH=alpha; fi

GIT_VERSION=$( git tag --points-at HEAD 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sed -n 1p | sed 's/^v//g' | xargs )
if [ "$GIT_VERSION" != "" ]; then
    if [ "$HAS_CHANGES" -eq 0 ]; then
        ASSEMBLY_VERSION_TEXT="$GIT_VERSION"
    else
        ASSEMBLY_VERSION_TEXT="$GIT_VERSION+$GIT_HASH"
    fi
else
    ASSEMBLY_VERSION_TEXT="0.0.0+$GIT_HASH"
fi

if [ "$GIT_VERSION" != "" ]; then
    echo "${ANSI_PURPLE}Git tag version .....: ${ANSI_MAGENTA}$GIT_VERSION${ANSI_RESET}"
else
    echo "${ANSI_PURPLE}Git tag version .....: ${ANSI_MAGENTA}-${ANSI_RESET}"
fi

if [ "$GIT_VERSION" != "" ]; then
    ASSEMBLY_VERSION="$GIT_VERSION.$GIT_INDEX"
else
    ASSEMBLY_VERSION="0.0.0.$GIT_INDEX"
fi
echo "${ANSI_PURPLE}Assembly version ....: ${ANSI_MAGENTA}$ASSEMBLY_VERSION${ANSI_RESET}"
echo "${ANSI_PURPLE}Assembly version text: ${ANSI_MAGENTA}$ASSEMBLY_VERSION_TEXT${ANSI_RESET}"


prereq_compile() {
    if ! command -v cargo >/dev/null; then
        echo "${ANSI_RED}Missing cargo command${ANSI_RESET}" >&2
        exit 113
    fi
}

make_clean() {
    echo
    echo "${ANSI_MAGENTA}┏━━━━━━━┓${ANSI_RESET}"
    echo "${ANSI_MAGENTA}┃ CLEAN ┃${ANSI_RESET}"
    echo "${ANSI_MAGENTA}┗━━━━━━━┛${ANSI_RESET}"
    echo

    find "$SCRIPT_DIR/bin" -mindepth 1 -delete 2>/dev/null || true
    find "$SCRIPT_DIR/target" -mindepth 1 -delete 2>/dev/null || true
    rmdir "$SCRIPT_DIR/bin" 2>/dev/null || true
    rmdir "$SCRIPT_DIR/target" 2>/dev/null || true
}

make_run() {
    echo
    echo "${ANSI_MAGENTA}┏━━━━━┓${ANSI_RESET}"
    echo "${ANSI_MAGENTA}┃ RUN ┃${ANSI_RESET}"
    echo "${ANSI_MAGENTA}┗━━━━━┛${ANSI_RESET}"
    echo

    cargo run
}

make_debug() {
    echo
    echo "${ANSI_MAGENTA}┏━━━━━━━┓${ANSI_RESET}"
    echo "${ANSI_MAGENTA}┃ DEBUG ┃${ANSI_RESET}"
    echo "${ANSI_MAGENTA}┗━━━━━━━┛${ANSI_RESET}"
    echo

    echo "${ANSI_MAGENTA}$(basename $PROJECT_ENTRYPOINT)${ANSI_RESET}"

    PROJECT_EXECUTABLE=$( echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' )
    mkdir -p "$SCRIPT_DIR/bin"
    cargo build --bins                                                                || exit 113
    cp "$SCRIPT_DIR/target/debug/$PROJECT_NAME" "$SCRIPT_DIR/bin/$PROJECT_EXECUTABLE" || exit 113
    echo "${ANSI_CYAN}$SCRIPT_DIR/bin/$PROJECT_NAME${ANSI_RESET}"                     || exit 113
}

make_release() {
    echo
    echo "${ANSI_MAGENTA}┏━━━━━━━━━┓${ANSI_RESET}"
    echo "${ANSI_MAGENTA}┃ RELEASE ┃${ANSI_RESET}"
    echo "${ANSI_MAGENTA}┗━━━━━━━━━┛${ANSI_RESET}"
    echo

    PROJECT_EXECUTABLE=$( echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' )
    mkdir -p "$SCRIPT_DIR/bin"
    cargo build --release --bins                                                        || exit 113
    cp "$SCRIPT_DIR/target/release/$PROJECT_NAME" "$SCRIPT_DIR/bin/$PROJECT_EXECUTABLE" || exit 113
    echo "${ANSI_CYAN}$SCRIPT_DIR/bin/$PROJECT_NAME${ANSI_RESET}"                       || exit 113
    echo
}


if [ "$1" = "" ]; then ACTIONS="all"; else ACTIONS="$@"; fi

TOKENS=" "
NEGTOKENS=
PREREQ_COMPILE=0
for ACTION in $ACTIONS; do
    case $ACTION in
        all)        TOKENS="$TOKENS clean release"   ; PREREQ_COMPILE=1 ;;
        clean)      TOKENS="$TOKENS clean"                              ;;
        run)        TOKENS="$TOKENS run"             ; PREREQ_COMPILE=1 ;;
        debug)      TOKENS="$TOKENS clean debug"     ; PREREQ_COMPILE=1 ;;
        release)    TOKENS="$TOKENS clean release"   ; PREREQ_COMPILE=1 ;;
        ~clean)     NEGTOKENS="$NEGTOKENS clean"     ;;
        ~run)       NEGTOKENS="$NEGTOKENS run"       ;;
        ~debug)     NEGTOKENS="$NEGTOKENS debug"     ;;
        ~release)   NEGTOKENS="$NEGTOKENS release"   ;;
        *)         echo "Unknown action $ACTION" >&2 ; exit 113 ;;
    esac
done

if [ $PREREQ_COMPILE -ne 0 ]; then prereq_compile; fi

NEGTOKENS=$( echo $NEGTOKENS | xargs | tr ' ' '\n' | awk '!seen[$0]++' | xargs )  # remove duplicates
TOKENS=$( echo $TOKENS | xargs | tr ' ' '\n' | awk '!seen[$0]++' | xargs )  # remove duplicates

for NEGTOKEN in $NEGTOKENS; do  # remove tokens we specifically asked not to have
    TOKENS=$( echo $TOKENS | tr ' ' '\n' | grep -v $NEGTOKEN | xargs )
done

if [ "$TOKENS" != "" ]; then
    echo "${ANSI_PURPLE}Make targets ........: ${ANSI_MAGENTA}$TOKENS${ANSI_RESET}"
else
    echo "${ANSI_PURPLE}Make targets ........: ${ANSI_RED}not found${ANSI_RESET}"
    exit 113
fi
echo

for TOKEN in $TOKENS; do
    case $TOKEN in
        clean)     make_clean     || exit 113 ;;
        run)       make_run       || exit 113 ;;
        debug)     make_debug     || exit 113 ;;
        release)   make_release   || exit 113 ;;
        *)         echo "Unknown token $TOKEN" >&2 ; exit 113 ;;
    esac
done

exit 0
