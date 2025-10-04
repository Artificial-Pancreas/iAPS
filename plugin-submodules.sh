#!/usr/bin/env bash
set -euo pipefail

# submodule-sync.sh
#
# Usage:
#   # Compare current repo vs reference (path or URL)
#   REF_REPO=/path/to/reference ./submodule-sync.sh compare
#   REF_REPO=https://github.com/org/reference.git ./submodule-sync.sh compare
#
#   # Update interactively (prompts on DIFF entries)
#   REF_REPO=/path/or/url ./submodule-sync.sh update
#
#   # If REF_REPO is NOT set, a default will be used:
#   #   DEFAULT_REF_URL (optionally REF_BRANCH to override branch)
#
# Env vars:
#   REF_REPO       : (optional) local path to reference repo OR https URL
#   REF_BRANCH     : (optional) branch to use when REF_REPO is a URL or default is used
#
# Configurable defaults (used ONLY when REF_REPO is not set):
DEFAULT_REF_URL="https://github.com/LoopKit/LoopWorkspace.git"
DEFAULT_REF_BRANCH="dev"

die() { echo "Error: $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

need_cmd git
need_cmd awk
need_cmd mktemp
need_cmd sed

THIS_REPO="$(pwd)"
REF_REPO="${REF_REPO:-}"
REF_BRANCH="${REF_BRANCH:-}"

TMP_CLONE_DIR=""
cleanup() {
  if [[ -n "${TMP_CLONE_DIR}" && -d "${TMP_CLONE_DIR}" ]]; then
    rm -rf "${TMP_CLONE_DIR}" || true
  fi
}
trap cleanup EXIT

# If REF_REPO is empty -> clone DEFAULT_REF_URL at DEFAULT_REF_BRANCH (or REF_BRANCH if set)
# If REF_REPO is a path -> use it
# If REF_REPO is an https URL -> shallow clone (optionally at REF_BRANCH)
resolve_reference_repo() {
  local ref_repo="$1"
  local ref_branch="$2"

  if [[ -z "$ref_repo" ]]; then
    local branch="${ref_branch:-$DEFAULT_REF_BRANCH}"
    # send message to stderr
    echo "REF_REPO not set, using default: $DEFAULT_REF_URL (branch $branch)" >&2
    TMP_CLONE_DIR="$(mktemp -d -t submodule-ref-XXXXXX)"
    git clone --depth=1 --branch "$branch" "$DEFAULT_REF_URL" "$TMP_CLONE_DIR" >/dev/null
    # only echo the path to stdout
    echo "$TMP_CLONE_DIR"
    return
  fi

  if [[ -d "$ref_repo" ]]; then
    (cd "$ref_repo" >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null) \
      || die "REF_REPO directory is not a git repo: $ref_repo"
    # only echo the absolute path to stdout
    (cd "$ref_repo" && pwd)
    return
  fi

  if [[ "$ref_repo" =~ ^https?:// ]]; then
    TMP_CLONE_DIR="$(mktemp -d -t submodule-ref-XXXXXX)"
    if [[ -n "$ref_branch" ]]; then
      git clone --depth=1 --branch "$ref_branch" "$ref_repo" "$TMP_CLONE_DIR" >/dev/null
    else
      git clone --depth=1 "$ref_repo" "$TMP_CLONE_DIR" >/dev/null
    fi
    echo "$TMP_CLONE_DIR"
    return
  fi

  die "REF_REPO must be an existing directory or an https URL"
}

# Enumerate submodules recorded at HEAD in a repo
# Output: PATH<TAB>COMMIT  (COMMIT empty if the path isn't present at this HEAD)
map_submodules() {
  local repo="$1"
  local gm="$repo/.gitmodules"

  if [[ -f "$gm" ]]; then
    # Paths from .gitmodules (authoritative list)
    git -C "$repo" config -f "$gm" --get-regexp '^submodule\..*\.path$' 2>/dev/null \
      | awk '{print $2}' \
      | while IFS= read -r path; do
          # Ask the tree for exactly this path; grab gitlink (mode 160000, type commit)
          local line
          line="$(git -C "$repo" ls-tree -z HEAD -- "$path" | tr -d '\0')"
          if [[ "$line" =~ ^160000[[:space:]]+commit[[:space:]]+([0-9a-f]{40})[[:space:]] ]]; then
            printf "%s\t%s\n" "$path" "${BASH_REMATCH[1]}"
          else
            # path not present at this HEAD (or not a submodule)
            printf "%s\t\n" "$path"
          fi
        done
    return
  fi

  # Fallback: scan entire tree for gitlinks
  git -C "$repo" ls-tree -z HEAD \
    | awk -v RS='\0' '$0 ~ /^160000 commit/ {print $4 "\t" $3}'
}

short() {
    git rev-parse --short=12 "$1" 2>/dev/null || echo "$1"
}

print_header() {
  printf "%-40s  %-14s  %-14s  %-11s  %-18s\n" "PATH" "THIS_REPO" "LOOP" "STATUS" "HEAD"
  printf "%-40s  %-14s  %-14s  %-11s  %-18s\n" "----------------------------------------" "--------------" "--------------" "----------" "------------------"
}

# ---- colors ----
RESET="\033[0m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
GREY="\033[90m"

colorize_status() {
  local status="$1"
  case "$status" in
    SAME)      echo -e "${GREEN}${status}${RESET}" ;;
    ONLY_LOOP|ONLY_IAPS) echo -e "${GREY}${status}${RESET}" ;;
    DIFF)      echo -e "${YELLOW}${status}${RESET}" ;;
    ???)       echo -e "${RED}${status}${RESET}" ;;
    *)         echo "$status" ;;
  esac
}

classify() {
  local a="$1" b="$2"
  if [[ -z "$a" && -z "$b" ]]; then echo "???"; return; fi
  if [[ -z "$a" ]]; then echo "ONLY_LOOP"; return; fi
  if [[ -z "$b" ]]; then echo "ONLY_IAPS"; return; fi
  if [[ "$a" == "$b" ]]; then echo "SAME"; return; fi
  echo "DIFF"
}

ensure_submodule_ready() {
  local path="$1"
  if [[ ! -d "$path" ]]; then
    git submodule update --init "$path"
  fi
}

# Returns "DETACHED", "BRANCH:<name>", or "N/A"
submodule_head_mode() {
  local path="$1"
  if [[ ! -d "$path" ]]; then echo "N/A"; return; fi
  local ref
  if ! ref=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null); then
    echo "N/A"; return
  fi
  [[ "$ref" = "HEAD" ]] && echo "DETACHED" || echo "BRANCH:$ref"
}

# Returns "DIRTY" if working tree has changes, else empty
submodule_dirty_flag() {
  local path="$1"
  [[ -d "$path" ]] || { echo ""; return; }
  if [[ -n "$(git -C "$path" status --porcelain)" ]]; then
    echo " +DIRTY"
  else
    echo ""
  fi
}

# Update one submodule to a specific commit (DETACHED), but:
# - if local changes present -> print and skip (no stash/apply)
update_one_submodule() {
  local path="$1" target_commit="$2"

  ensure_submodule_ready "$path"

  local dirty
  dirty="$(submodule_dirty_flag "$path")"
  if [[ -n "$dirty" ]]; then
    echo "  ! Skipping $path: local changes present."
    return 1
  fi

  local mode
  mode="$(submodule_head_mode "$path")"
  if [[ "$mode" != "DETACHED" && "$mode" != "N/A" ]]; then
    echo "  ! Note: $path is currently $mode; syncing will detach HEAD."
  fi

  # Make sure the target commit exists locally
  git -C "$path" fetch --all --tags >/dev/null 2>&1 || true
  if ! git -C "$path" rev-parse --verify -q "$target_commit" >/dev/null; then
    echo "  ! Cannot find commit $target_commit in $path (even after fetch). Skipping."
    return 1
  fi

  git -C "$path" checkout --detach "$target_commit" >/dev/null
  git add "$path"

  echo "  ✓ Staged $path to $(short "$target_commit")"
}

# ----- main -----

[[ -d ".git" ]] || die "Run from the root of your repo."

REF_DIR="$(resolve_reference_repo "$REF_REPO" "$REF_BRANCH")"

declare -A THIS_MAP REF_MAP
while IFS=$'\t' read -r p c; do
  [[ -n "$p" ]] && THIS_MAP["$p"]="$c"
done < <(map_submodules "$THIS_REPO")

while IFS=$'\t' read -r p c; do
  [[ -n "$p" ]] && REF_MAP["$p"]="$c"
done < <(map_submodules "$REF_DIR")

# Union of paths
declare -A UNION
for k in "${!THIS_MAP[@]}"; do UNION["$k"]=1; done
for k in "${!REF_MAP[@]}";  do UNION["$k"]=1; done

cmd="${1:-}"
filter_path=""
if [[ "$cmd" == "update" ]]; then
  filter_path="${2:-}"   # optional: path/to/submodule
fi

if [[ "$cmd" != "compare" && "$cmd" != "update" ]]; then
  cat >&2 <<EOF
Usage:
  REF_REPO=<path-or-https-url> [REF_BRANCH=<branch>] $0 compare
  REF_REPO=<path-or-https-url> [REF_BRANCH=<branch>] $0 update [path/to/submodule]

If REF_REPO is not set, defaults will be used:
  URL   : $DEFAULT_REF_URL
  BRANCH: ${REF_BRANCH:-$DEFAULT_REF_BRANCH}
EOF
  exit 2
fi

print_header

# Collect DIFFs for update phase
declare -a DIFF_PATHS DIFF_THIS DIFF_REF

declare -a DIFF_PATHS=()
declare -a DIFF_THIS=()
declare -a DIFF_REF=()

for path in "${!UNION[@]}"; do
  # If update was called with a specific path, skip others
  if [[ "$cmd" == "update" && -n "$filter_path" && "$path" != "$filter_path" ]]; then
    continue
  fi

  this="${THIS_MAP[$path]:-}"
  ref="${REF_MAP[$path]:-}"
  status="$(classify "$this" "$ref")"
  status_col="$(colorize_status "$status")"

  headmode="$(submodule_head_mode "$path")"
  dirty="$(submodule_dirty_flag "$path")"
  headdisp="${headmode}${dirty}"

  case "$status" in
    ONLY_IAPS)
      printf "%-40s  %-14s  %-14s  %-20s  %-18s\n" "$path" "$(short "${this:-}")" "-" "$status_col" "$headdisp"
      ;;
    ONLY_LOOP)
      printf "%-40s  %-14s  %-14s  %-20s  %-18s\n" "$path" "-" "$(short "${ref:-}")" "$status_col" "N/A"
      ;;
    SAME)
      printf "%-40s  %-14s  %-14s  %-20s  %-18s\n" "$path" "$(short "${this:-}")" "$(short "${ref:-}")" "$status_col" "$headdisp"
      ;;
    DIFF)
      printf "%-40s  %-14s  %-14s  %-20s  %-18s\n" "$path" "$(short "${this:-}")" "$(short "${ref:-}")" "$status_col" "$headdisp"
      DIFF_PATHS+=("$path"); DIFF_THIS+=("$this"); DIFF_REF+=("$ref")
      ;;
  esac
done

if [[ "$cmd" == "update" ]]; then
  for i in "${!DIFF_PATHS[@]}"; do
    path="${DIFF_PATHS[$i]}"
    this="${DIFF_THIS[$i]}"
    ref="${DIFF_REF[$i]}"

    echo "----"
    echo "Path: $path"
    echo "This repo : $(short "$this")  (HEAD=$(submodule_head_mode "$path")$(submodule_dirty_flag "$path"))"
    echo "Loop repo : $(short "$ref")"
    read -r -p "Update this submodule to match the commit in LoopWorkspace? [y/N] " ans
    case "$ans" in
      y|Y|yes|YES)
        if update_one_submodule "$path" "$ref"; then
          :
        else
          echo "  ! Skipped $path due to errors or local changes."
        fi
        ;;
      *)
        echo "  · Skipped."
        ;;
    esac
  done

fi

echo
if [[ ${#DIFF_PATHS[@]} -eq 0 ]]; then
  echo "No differences to update."
  exit 0
else
  echo
  echo "Done. If you accepted updates, they're staged. Next:"
  echo "  git commit -m \"Sync submodules to WorkspaceLoop\""
fi
