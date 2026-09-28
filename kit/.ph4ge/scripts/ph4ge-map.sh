# ph4ge:managed-file v1
# Read-only PH4GE workspace map (Bash).
# Prints a short human-readable workspace/repository map. Writes nothing.

set -u

usage() {
    echo "Usage: $0 --workspace <path>" >&2
    exit 64
}

WORKSPACE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --workspace)
            shift
            [ $# -gt 0 ] || usage
            WORKSPACE="$1"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            ;;
    esac
done

[ -n "$WORKSPACE" ] || usage

if [ ! -e "$WORKSPACE" ]; then
    echo "Workspace path does not exist: $WORKSPACE" >&2
    exit 2
fi

case "$WORKSPACE" in
    /)
        echo "Refusing to operate on a filesystem root: $WORKSPACE" >&2
        exit 2
        ;;
esac

HOME_DIR="${HOME:-}"
if [ -n "$HOME_DIR" ] && [ "$WORKSPACE" = "$HOME_DIR" ]; then
    echo "Refusing to operate on a home directory: $WORKSPACE" >&2
    exit 2
fi

ROOT_FULL="$(cd "$WORKSPACE" && pwd)"
case "$ROOT_FULL" in
    /)
        echo "Refusing to operate on a filesystem root: $ROOT_FULL" >&2
        exit 2
        ;;
esac

echo "Workspace: $ROOT_FULL"

REPO_COUNT=0
for entry in "$ROOT_FULL"/*/; do
    [ -d "$entry" ] || continue
    if [ -d "$entry.git" ] || [ -f "$entry.git" ]; then
        REPO_COUNT=$((REPO_COUNT + 1))
        name="$(basename "$entry")"
        if [ -e "$entry/AGENTS.md" ]; then
            agents="yes"
        else
            agents="no"
        fi
        if [ -e "$entry/CLAUDE.md" ]; then
            claude="yes"
        else
            claude="no"
        fi
        echo " - $name (AGENTS=$agents CLAUDE=$claude)"
    fi
done

if [ "$REPO_COUNT" -eq 0 ]; then
    echo " (no immediate child Git repositories)"
fi

if [ -e "$ROOT_FULL/.claude/settings.json" ]; then
    echo "Settings: present (untouched)"
else
    echo "Settings: absent"
fi
