# ph4ge:managed-file v1
# Read-only PH4GE workspace probe (Bash).
# Verifies the expected root support material and discovers immediate
# child Git repositories. Writes nothing.

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

# Filesystem root check
case "$WORKSPACE" in
    /)
        echo "Refusing to operate on a filesystem root: $WORKSPACE" >&2
        exit 2
        ;;
esac

# Home directory check
HOME_DIR="${HOME:-}"
if [ -n "$HOME_DIR" ] && [ "$WORKSPACE" = "$HOME_DIR" ]; then
    echo "Refusing to operate on a home directory: $WORKSPACE" >&2
    exit 2
fi

# Absolute path resolution
ROOT_FULL="$(cd "$WORKSPACE" && pwd)"
case "$ROOT_FULL" in
    /)
        echo "Refusing to operate on a filesystem root: $ROOT_FULL" >&2
        exit 2
        ;;
esac

REPO_COUNT=0
for entry in "$ROOT_FULL"/*/; do
    [ -d "$entry" ] || continue
    if [ -d "$entry.git" ] || [ -f "$entry.git" ]; then
        REPO_COUNT=$((REPO_COUNT + 1))
    fi
done

MISSING=()
for rel in AGENTS.md CLAUDE.md PH4GE.md .claude/commands/ph4ge.md \
           .ph4ge/scripts/ph4ge-probe.ps1 .ph4ge/scripts/ph4ge-map.ps1 \
           .ph4ge/scripts/ph4ge-probe.sh .ph4ge/scripts/ph4ge-map.sh \
           .ph4ge/templates/child-AGENTS.md; do
    if [ ! -e "$ROOT_FULL/$rel" ]; then
        MISSING+=("$rel")
    fi
done

echo "Workspace: $ROOT_FULL"
if [ ${#MISSING[@]} -eq 0 ]; then
    echo "Root support files missing: none"
else
    echo "Root support files missing: $(IFS=', '; echo "${MISSING[*]}")"
fi
echo "Immediate child Git repos: $REPO_COUNT"

if [ -e "$ROOT_FULL/.claude/settings.json" ]; then
    echo "Settings note: .claude/settings.json exists and was left untouched"
fi

if [ ${#MISSING[@]} -gt 0 ] || [ "$REPO_COUNT" -eq 0 ]; then
    exit 1
fi
exit 0
