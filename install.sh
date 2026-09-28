#!/usr/bin/env bash
# ph4ge:managed-file v1
# Install PH4GE only into an explicit workspace root. This script never edits
# source code, Git history, existing root documents, settings, or child CLAUDE files.

set -euo pipefail

BEGIN_MARKER='<!-- ph4ge:begin v1 -->'
END_MARKER='<!-- ph4ge:end -->'
SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
KIT_DIR="$SCRIPT_DIR/kit"
WORKSPACE=''
DRY_RUN=0

usage() {
    cat <<'EOF'
Usage: bash install.sh --workspace <path> [--dry-run]

Install PH4GE into an explicit workspace root with one or more immediate
child Git repositories. --dry-run prints the intended changes only.
EOF
}

die() {
    printf 'PH4GE: %s\n' "$*" >&2
    exit 2
}

plan() {
    printf 'Plan: %s\n' "$*"
}

run_copy() {
    local source="$1"
    local destination="$2"
    local description="$3"
    plan "$description: $destination"
    if [ "$DRY_RUN" -eq 1 ]; then
        return
    fi
    mkdir -p -- "$(dirname -- "$destination")"
    cp -- "$source" "$destination"
}

canonical_directory() {
    [ -d "$1" ] || return 1
    (cd -P -- "$1" && pwd -P)
}

first_bytes_hex() {
    LC_ALL=C head -c 3 -- "$1" | od -An -tx1 | tr -d '[:space:]'
}

require_utf8_without_bom() {
    local path="$1"
    local prefix
    prefix="$(first_bytes_hex "$path")"
    case "$prefix" in
        efbbbf*|fffe*|feff*)
            die "Bash installer supports UTF-8 without BOM only: $path"
            ;;
    esac
    command -v iconv >/dev/null 2>&1 || \
        die 'Bash installer requires iconv to validate UTF-8 input safely.'
    iconv -f UTF-8 -t UTF-8 -- "$path" >/dev/null 2>&1 || \
        die "Bash installer cannot safely read non-UTF-8 file: $path"
}

newline_for() {
    if LC_ALL=C grep -q $'\r$' -- "$1"; then
        printf '\r\n'
    else
        printf '\n'
    fi
}

child_marker_state() {
    local path="$1"
    if [ ! -e "$path" ]; then
        printf 'create'
        return
    fi

    require_utf8_without_bom "$path"
    awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
        {
            value = $0
            sub(/\r$/, "", value)
            if (value == begin) {
                beginCount++
                if (beginLine == 0) beginLine = NR
            }
            if (value == end) {
                endCount++
                if (endLine == 0) endLine = NR
            }
        }
        END {
            if (beginCount == 0 && endCount == 0) print "append"
            else if (beginCount == 1 && endCount == 1 && beginLine < endLine) print "replace"
            else print "malformed"
        }
    ' "$path"
}

write_template_with_newline() {
    local template="$1"
    local destination="$2"
    local newline="$3"
    local line
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        printf '%s%b' "$line" "$newline" >> "$destination"
    done < "$template"
}

append_child_block() {
    local destination="$1"
    local template="$2"
    local newline
    newline="$(newline_for "$destination")"

    if [ -s "$destination" ]; then
        local last_byte
        last_byte="$(tail -c 1 -- "$destination" | od -An -tx1 | tr -d '[:space:]')"
        if [ "$last_byte" != '0a' ] && [ "$last_byte" != '0d' ]; then
            printf '%b' "$newline" >> "$destination"
        fi
    fi
    write_template_with_newline "$template" "$destination" "$newline"
}

replace_child_block() {
    local destination="$1"
    local template="$2"
    local carriage_return=''
    local temporary

    if LC_ALL=C grep -q $'\r$' -- "$destination"; then
        carriage_return=$'\r'
    fi
    temporary="$(mktemp "${destination}.ph4ge.XXXXXX")"
    awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" \
        -v template="$template" -v cr="$carriage_return" '
        function emit_template( line) {
            while ((getline line < template) > 0) {
                sub(/\r$/, "", line)
                printf "%s%s\n", line, cr
            }
            close(template)
        }
        {
            value = $0
            sub(/\r$/, "", value)
            if (value == begin) {
                emit_template()
                inside = 1
                next
            }
            if (inside) {
                if (value == end) inside = 0
                next
            }
            print $0
        }
    ' "$destination" > "$temporary"
    mv -- "$temporary" "$destination"
}

is_ph4ge_managed_support_file() {
    local path="$1"
    local first_line
    IFS= read -r first_line < "$path" || true
    first_line="${first_line%$'\r'}"
    [ "$first_line" = '# ph4ge:managed-file v1' ] || \
        [ "$first_line" = '<!-- ph4ge:begin v1 -->' ]
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --workspace)
            [ "$#" -ge 2 ] || die '--workspace requires a path'
            WORKSPACE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown argument: $1"
            ;;
    esac
done

[ -n "$WORKSPACE" ] || die 'Provide --workspace <path>.'
[ -d "$WORKSPACE" ] || die "Workspace root must be an existing directory: $WORKSPACE"
[ ! -L "$WORKSPACE" ] || die "Workspace root must not be a symbolic link: $WORKSPACE"
ROOT="$(canonical_directory "$WORKSPACE")" || die "Cannot resolve workspace root: $WORKSPACE"
[ "$ROOT" != '/' ] || die "Refusing to operate on a filesystem root: $ROOT"

if [ -n "${HOME:-}" ] && [ -d "$HOME" ]; then
    HOME_ROOT="$(canonical_directory "$HOME")"
    [ "$ROOT" != "$HOME_ROOT" ] || die "Refusing to operate on a home directory: $ROOT"
fi

[ -d "$KIT_DIR" ] || die "PH4GE kit is missing: $KIT_DIR"

shopt -s nullglob
REPOSITORIES=()
for child in "$ROOT"/*/; do
    [ -L "$child" ] && { plan "skip symbolic-link child $child"; continue; }
    if [ -d "${child}.git" ] || [ -f "${child}.git" ]; then
        REPOSITORIES+=("${child%/}")
    fi
done
[ "${#REPOSITORIES[@]}" -gt 0 ] || die "Workspace root has no immediate child Git repositories: $ROOT"

declare -a CHILD_STATES=()
for repository in "${REPOSITORIES[@]}"; do
    agent_file="$repository/AGENTS.md"
    state="$(child_marker_state "$agent_file")"
    [ "$state" != 'malformed' ] || die "Malformed PH4GE markers in $agent_file"
    CHILD_STATES+=("$state")
done

copy_root_if_absent() {
    local source="$1"
    local destination="$2"
    if [ -e "$destination" ]; then
        plan "preserve existing root file $destination"
    else
        run_copy "$source" "$destination" 'create missing root PH4GE file'
    fi
}

copy_root_if_absent "$KIT_DIR/.ph4ge/templates/root-AGENTS.md" "$ROOT/AGENTS.md"
copy_root_if_absent "$KIT_DIR/.ph4ge/templates/root-CLAUDE.md" "$ROOT/CLAUDE.md"
copy_root_if_absent "$KIT_DIR/.ph4ge/templates/root-PH4GE.md" "$ROOT/PH4GE.md"
copy_root_if_absent "$KIT_DIR/.claude/commands/ph4ge.md" "$ROOT/.claude/commands/ph4ge.md"

while IFS= read -r -d '' source; do
    relative="${source#"$KIT_DIR/.ph4ge/"}"
    destination="$ROOT/.ph4ge/$relative"
    if [ ! -e "$destination" ]; then
        run_copy "$source" "$destination" 'create PH4GE support file'
    elif is_ph4ge_managed_support_file "$destination"; then
        run_copy "$source" "$destination" 'refresh PH4GE-owned support file'
    else
        plan "preserve non-PH4GE support file $destination"
    fi
done < <(find "$KIT_DIR/.ph4ge" -type f -print0)

child_template="$KIT_DIR/.ph4ge/templates/child-AGENTS.md"
for index in "${!REPOSITORIES[@]}"; do
    destination="${REPOSITORIES[$index]}/AGENTS.md"
    case "${CHILD_STATES[$index]}" in
        create)
            run_copy "$child_template" "$destination" 'create child AGENTS.md from PH4GE template'
            ;;
        append)
            plan "append PH4GE managed block to child AGENTS.md: $destination"
            [ "$DRY_RUN" -eq 1 ] || append_child_block "$destination" "$child_template"
            ;;
        replace)
            plan "refresh PH4GE managed block in child AGENTS.md: $destination"
            [ "$DRY_RUN" -eq 1 ] || replace_child_block "$destination" "$child_template"
            ;;
    esac
done

printf 'PH4GE processed %s immediate child Git repository/repositories.\n' "${#REPOSITORIES[@]}"
