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
    echo "  package    Package the project"
    echo "  publish    Publish the project"
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

if [ $HAS_CHANGES -eq 0 ] ; then  # only if there are no changes, check for tag
    GIT_VERSION=$( git tag --points-at HEAD 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sed -n 1p | sed 's/^v//g' | xargs )
fi
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


PROJECT_RUNTIMES=$( cat "$SCRIPT_DIR/.meta" | grep -E "^PROJECT_RUNTIMES:" | sed  -n 1p | cut -d: -sf2- | xargs )
if [ "$PROJECT_RUNTIMES" = "" ]; then
    PROJECT_RUNTIMES=current
fi
echo "${ANSI_PURPLE}Project runtimes ....: ${ANSI_MAGENTA}$PROJECT_RUNTIMES${ANSI_RESET}"


PACKAGE_LINUX_DEB=$( cat "$SCRIPT_DIR/.meta" | grep -E "^PACKAGE_LINUX_DEB:" | sed  -n 1p | cut -d: -sf2- | xargs )
if [ "$PACKAGE_LINUX_DEB" = "" ]; then  # auto-detect
    if [ -d "$SCRIPT_DIR/packaging/linux-deb" ]; then
        PACKAGE_LINUX_DEB=$PROJECT_NAME
    fi
fi
if [ "$PACKAGE_LINUX_DEB" != "" ]; then
    echo "${ANSI_PURPLE}Debian package ......: ${ANSI_MAGENTA}$PACKAGE_LINUX_DEB${ANSI_RESET}"

    PUBLISH_LINUX_DEB=$( cat "$SCRIPT_DIR/.meta.private" 2>/dev/null | grep -E "^PUBLISH_LINUX_DEB:" | sed  -n 1p | cut -d: -sf2- | xargs )
    if [ "$PUBLISH_LINUX_DEB" = "" ]; then
        echo "${ANSI_PURPLE}Debian package remote: ${ANSI_YELLOW}(not configured)${ANSI_RESET}" >&2
    else
        echo "${ANSI_PURPLE}Debian package remote: ${ANSI_MAGENTA}$PUBLISH_LINUX_APPIMAGE${ANSI_RESET}"
    fi
fi


prereq_compile() {
    if ! command -v cargo >/dev/null; then
        echo "${ANSI_RED}Missing cargo command${ANSI_RESET}" >&2
        exit 113
    fi
}

prereq_package() {
    if [ "$PACKAGE_LINUX_DEB" != "" ]; then
        if ! [ -d "$SCRIPT_DIR/packaging/linux-deb" ]; then
            echo "${ANSI_RED}Missing linux-deb directory${ANSI_RESET}" >&2
            exit 113
        fi
        # if ! [ -e "$SCRIPT_DIR/packaging/linux-deb/usr/share/applications"/*.desktop ]; then
        #     echo "${ANSI_RED}Missing desktip file${ANSI_RESET}" >&2
        #     exit 113
        # fi
        # if ! [ -e "$SCRIPT_DIR/packaging/linux-deb/usr/share/icons/hicolor/128x128/apps"/*.png ]; then
        #     echo "${ANSI_RED}Missing icon files${ANSI_RESET}" >&2
        #     exit 113
        # fi
        if ! command -v dpkg-deb >/dev/null; then
            echo "${ANSI_RED}Missing dpkg-deb command (dpkg-deb package)${ANSI_RESET}" >&2
            exit 113
        fi
        if ! command -v fakeroot >/dev/null; then
            echo "${ANSI_RED}Missing fakeroot command${ANSI_RESET}" >&2
            exit 113
        fi
        if ! command -v gzip >/dev/null; then
            echo "${ANSI_RED}Missing gzip command${ANSI_RESET}" >&2
            exit 113
        fi
        if ! command -v lintian >/dev/null; then
            echo "${ANSI_RED}Missing lintian command (lintian package)${ANSI_RESET}" >&2
            exit 113
        fi
        if ! command -v strip >/dev/null; then
            echo "${ANSI_RED}Missing strip command${ANSI_RESET}" >&2
            exit 113
        fi
    fi
}

make_clean() {
    echo
    echo "${ANSI_MAGENTA}┏━━━━━━━┓${ANSI_RESET}"
    echo "${ANSI_MAGENTA}┃ CLEAN ┃${ANSI_RESET}"
    echo "${ANSI_MAGENTA}┗━━━━━━━┛${ANSI_RESET}"
    echo

    find "$SCRIPT_DIR/bin" -mindepth 1 -delete 2>/dev/null || true
    find "$SCRIPT_DIR/build" -mindepth 1 -delete 2>/dev/null || true
    find "$SCRIPT_DIR/target" -mindepth 1 -delete 2>/dev/null || true
    rmdir "$SCRIPT_DIR/bin" 2>/dev/null || true
    rmdir "$SCRIPT_DIR/build" 2>/dev/null || true
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
    echo "${ANSI_CYAN}$SCRIPT_DIR/bin/$PROJECT_EXECUTABLE${ANSI_RESET}"                     || exit 113
}

make_release() {
    echo
    echo "${ANSI_MAGENTA}┏━━━━━━━━━┓${ANSI_RESET}"
    echo "${ANSI_MAGENTA}┃ RELEASE ┃${ANSI_RESET}"
    echo "${ANSI_MAGENTA}┗━━━━━━━━━┛${ANSI_RESET}"
    echo

    PROJECT_EXECUTABLE=$( echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' )

    mkdir -p "$SCRIPT_DIR/bin"
    for RUNTIME in $PROJECT_RUNTIMES; do
        echo "${ANSI_MAGENTA}$RUNTIME${ANSI_RESET}"

        if [ "$RUNTIME" = "current" ]; then
            cargo build --release --bins                                                        || exit 113
            cp "$SCRIPT_DIR/target/release/$PROJECT_NAME" "$SCRIPT_DIR/bin/$PROJECT_EXECUTABLE" || exit 113
            echo "${ANSI_CYAN}$SCRIPT_DIR/bin/$PROJECT_EXECUTABLE${ANSI_RESET}"
            echo
        else
            mkdir -p "$SCRIPT_DIR/bin/$RUNTIME"
            cargo build --release --bins --target $RUNTIME                                                        || exit 113
            cp "$SCRIPT_DIR/target/$RUNTIME/release/$PROJECT_NAME" "$SCRIPT_DIR/bin/$RUNTIME/$PROJECT_EXECUTABLE" || exit 113
            echo "${ANSI_CYAN}$SCRIPT_DIR/bin/$RUNTIME/$PROJECT_EXECUTABLE${ANSI_RESET}"
            echo
        fi
    done
}

make_package() {
    echo
    echo "${ANSI_MAGENTA}┏━━━━━━━━━┓${ANSI_RESET}"
    echo "${ANSI_MAGENTA}┃ PACKAGE ┃${ANSI_RESET}"
    echo "${ANSI_MAGENTA}┗━━━━━━━━━┛${ANSI_RESET}"
    echo

    ANYTHING_DONE=0
    PROJECT_NAME_LOWER="$(echo $PROJECT_NAME | tr [:upper:] [:lower:])"

    ANYTHING_DONE=1
    echo "${ANSI_MAGENTA}archive${ANSI_RESET}"

    mkdir -p "$SCRIPT_DIR/build/archive"
    find "$SCRIPT_DIR/build/archive" -mindepth 1 -delete

    rsync -a "$SCRIPT_DIR/bin/" "$SCRIPT_DIR/build/archive/" || exit 113

    mkdir -p "dist"

    ARCHIVE_NAME_CURR="$PROJECT_NAME_LOWER-$ASSEMBLY_VERSION_TEXT.tgz"
    rm "dist/$ARCHIVE_NAME_CURR" 2>/dev/null

    tar czvf "dist/$ARCHIVE_NAME_CURR" -C "$SCRIPT_DIR/build/archive" . || exit 113

    echo "${ANSI_CYAN}dist/$ARCHIVE_NAME_CURR${ANSI_RESET}"
    echo

    if [ "$PACKAGE_LINUX_DEB" != "" ]; then
        DEB_ARCHITECTURE=amd64

        ANYTHING_DONE=1
        echo "${ANSI_MAGENTA}deb ($DEB_ARCHITECTURE)${ANSI_RESET}"

        if [ "$GIT_VERSION" != "" ]; then
            DEB_VERSION=$GIT_VERSION
            DEB_PACKAGE_NAME="${PROJECT_NAME_LOWER}_${ASSEMBLY_VERSION_TEXT}_${DEB_ARCHITECTURE}"
        else
            DEB_VERSION=0.0.0
            DEB_PACKAGE_NAME="${PROJECT_NAME_LOWER}_${ASSEMBLY_VERSION_TEXT}_${DEB_ARCHITECTURE}"
        fi

        mkdir -p "$SCRIPT_DIR/build/$DEB_PACKAGE_NAME"
        find "$SCRIPT_DIR/build/$DEB_PACKAGE_NAME/" -mindepth 1 -delete

        rsync -a "$SCRIPT_DIR/packaging/linux-deb/DEBIAN/" "$SCRIPT_DIR/build/$DEB_PACKAGE_NAME/DEBIAN/" || exit 113
        sed -i "s/<DEB_VERSION>/$DEB_VERSION/" "$SCRIPT_DIR/build/$DEB_PACKAGE_NAME/DEBIAN/control" || exit 113
        sed -i "s/<DEB_ARCHITECTURE>/amd64/" "$SCRIPT_DIR/build/$DEB_PACKAGE_NAME/DEBIAN/control" || exit 113

        if [ -e "$SCRIPT_DIR/packaging/linux-deb/usr" ]; then
            rsync -a "$SCRIPT_DIR/packaging/linux-deb/usr/" "$SCRIPT_DIR/build/$DEB_PACKAGE_NAME/usr/" || exit 113
        fi

        mkdir -p  "$SCRIPT_DIR/build/$DEB_PACKAGE_NAME/opt/$PROJECT_NAME_LOWER/"
        rsync -a "$SCRIPT_DIR/bin/" "$SCRIPT_DIR/build/$DEB_PACKAGE_NAME/opt/$PROJECT_NAME_LOWER/" || exit 113

        if [ -e "$SCRIPT_DIR/packaging/linux-deb/copyright" ]; then
            mkdir -p "$SCRIPT_DIR/build/$DEB_PACKAGE_NAME/usr/share/doc/$PROJECT_NAME_LOWER/"
            cp "$SCRIPT_DIR/packaging/linux-deb/copyright" "$SCRIPT_DIR/build/$DEB_PACKAGE_NAME/usr/share/doc/$PROJECT_NAME_LOWER/copyright" || exit 113
        fi

        find "$SCRIPT_DIR/build/$DEB_PACKAGE_NAME/" -type d -exec chmod 755 {} + || exit 113
        find "$SCRIPT_DIR/build/$DEB_PACKAGE_NAME/" -type f -exec chmod 644 {} + || exit 113
        find "$SCRIPT_DIR/build/$DEB_PACKAGE_NAME/opt/" -type f -name "$PROJECT_NAME_LOWER" -exec chmod 755 {} + || exit 113
        chmod 755 "$SCRIPT_DIR/build/$DEB_PACKAGE_NAME/DEBIAN"/config || exit 113
        chmod 755 "$SCRIPT_DIR/build/$DEB_PACKAGE_NAME/DEBIAN"/p*inst || exit 113
        chmod 755 "$SCRIPT_DIR/build/$DEB_PACKAGE_NAME/DEBIAN"/p*rm || exit 113

        fakeroot dpkg-deb -Z gzip --build "$SCRIPT_DIR/build/$DEB_PACKAGE_NAME/" > /dev/null || exit 113
        mv "$SCRIPT_DIR/build/$DEB_PACKAGE_NAME.deb" "dist/$DEB_PACKAGE_NAME.deb" || exit 113
        lintian --suppress-tags dir-or-file-in-opt,embedded-library "dist/$DEB_PACKAGE_NAME.deb"

        DEB_PACKAGE_AMD64=$DEB_PACKAGE_NAME.deb

        echo "${ANSI_CYAN}dist/$DEB_PACKAGE_NAME.deb${ANSI_RESET}"
        echo
    fi

    if [ "$ANYTHING_DONE" -eq 0 ]; then
        echo "${ANSI_RED}Nothing to package${ANSI_RESET}" >&2
        exit 113
    fi
}

make_publish() {
    echo
    echo "${ANSI_MAGENTA}┏━━━━━━━━━┓${ANSI_RESET}"
    echo "${ANSI_MAGENTA}┃ PUBLISH ┃${ANSI_RESET}"
    echo "${ANSI_MAGENTA}┗━━━━━━━━━┛${ANSI_RESET}"
    echo

    ANYTHING_DONE=0

    if [ "$PUBLISH_LINUX_DEB" != "" ]; then
        DEB_ARCHITECTURE=amd64
        DEB_PACKAGE_CURR=$DEB_PACKAGE_AMD64

        ANYTHING_DONE=1
        echo "${ANSI_MAGENTA}deb ($DEB_ARCHITECTURE)${ANSI_RESET}"

        PUBLISH_LINUX_DEB_CURR="$( echo "$PUBLISH_LINUX_DEB" | sed "s/<DEB_ARCHITECTURE>/$DEB_ARCHITECTURE/g" )"

        rsync --no-g --no-o --progress "dist/$DEB_PACKAGE_CURR" $PUBLISH_LINUX_DEB_CURR || exit 113
        echo "${ANSI_CYAN}$PUBLISH_LINUX_DEB_CURR${ANSI_RESET}"
        echo
    fi

    if [ "$ANYTHING_DONE" -eq 0 ]; then
        echo "${ANSI_RED}Nothing to publish${ANSI_RESET}" >&2
        exit 113
    fi
}


if [ "$1" = "" ]; then ACTIONS="all"; else ACTIONS="$@"; fi

TOKENS=" "
NEGTOKENS=
PREREQ_COMPILE=0
PREREQ_PACKAGE=0
for ACTION in $ACTIONS; do
    case $ACTION in
        all)        TOKENS="$TOKENS clean release"                 ; PREREQ_COMPILE=1 ;;
        clean)      TOKENS="$TOKENS clean"                                            ;;
        run)        TOKENS="$TOKENS run"                           ; PREREQ_COMPILE=1 ;;
        debug)      TOKENS="$TOKENS clean debug"                   ; PREREQ_COMPILE=1 ;;
        release)    TOKENS="$TOKENS clean release"                 ; PREREQ_COMPILE=1 ;;
        package)    TOKENS="$TOKENS clean release package"         ; PREREQ_COMPILE=1 ; PREREQ_PACKAGE=1 ;;
        publish)    TOKENS="$TOKENS clean release package publish" ; PREREQ_COMPILE=1 ; PREREQ_PACKAGE=1 ;;
        ~clean)     NEGTOKENS="$NEGTOKENS clean"     ;;
        ~run)       NEGTOKENS="$NEGTOKENS run"       ;;
        ~debug)     NEGTOKENS="$NEGTOKENS debug"     ;;
        ~release)   NEGTOKENS="$NEGTOKENS release"   ;;
        ~package)   NEGTOKENS="$NEGTOKENS package"   ;;
        ~publish)   NEGTOKENS="$NEGTOKENS publish"   ;;
        *)         echo "Unknown action $ACTION" >&2 ; exit 113 ;;
    esac
done

if [ $PREREQ_COMPILE -ne 0 ]; then prereq_compile; fi
if [ $PREREQ_PACKAGE -ne 0 ]; then prereq_package; fi

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
        package)   make_package   || exit 113 ;;
        publish)   make_publish   || exit 113 ;;
        *)         echo "Unknown token $TOKEN" >&2 ; exit 113 ;;
    esac
done

exit 0
