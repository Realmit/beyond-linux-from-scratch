#!/bin/bash
# squash-commits.sh – Interactive Git commit squasher
# Usage: ./squash-commits.sh -n N -m "message" [-b branch]

set -e

show_help() {
    cat << 'EOF'
Usage: $0 -n <number> -m "message" [-b <branch>]

  -n <number>   Number of last commits to squash (must be >= 2)
  -m "message"  Final commit message
  -b <branch>   (Optional) Branch to work on (default: current branch)
  -h            Show this help

Examples:
  $0 -n 3 -m "Fix: corrections and refactoring of module X"
  $0 -n 2 -m "Merge modifications" -b develop
EOF
}

# Default values
N_COMMITS=""
COMMIT_MSG=""
BRANCH=""

# Argument parsing
while getopts "n:m:b:h" opt; do
    case "$opt" in
        n) N_COMMITS="$OPTARG" ;;
        m) COMMIT_MSG="$OPTARG" ;;
        b) BRANCH="$OPTARG" ;;
        h) show_help; exit 0 ;;
        *) show_help; exit 1 ;;
    esac
done

if [ -z "$N_COMMITS" ] || [ -z "$COMMIT_MSG" ]; then
    echo "Please specify both -n and -m"
    show_help
    exit 1
fi

if ! [[ "$N_COMMITS" =~ ^[0-9]+$ ]] || [ "$N_COMMITS" -lt 2 ]; then
    echo "-n must be an integer >= 2"
    exit 1
fi

if [ -n "$BRANCH" ]; then
    if ! git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
        echo "Branch '$BRANCH' does not exist"
        exit 1
    fi
    git checkout "$BRANCH" >/dev/null 2>&1
fi

# Check that the requested number of commits is available
COMMIT_COUNT=$(git rev-list --count HEAD)
if [ "$COMMIT_COUNT" -lt "$N_COMMITS" ]; then
    echo "Only $COMMIT_COUNT commits in history, cannot squash $N_COMMITS"
    exit 1
fi

echo "🔧 Squashing the last $N_COMMITS commits on branch $(git branch --show-current)"

# Use GIT_SEQUENCE_EDITOR to modify the rebase interactive todo file
export GIT_SEQUENCE_EDITOR="sed -i '1!s/^pick/squash/'"
# Keep the first commit as 'pick', change the rest to 'squash'

# Launch interactive rebase
git rebase -i HEAD~$N_COMMITS

# After rebase, git will open an editor for the combined commit message.
# We let the user edit it manually.

echo "Interactive rebase launched."
echo "An editor will open for you to modify the resulting commit message."
echo "You can keep it as is or customize it."
echo "Once closed, the squash will be performed."