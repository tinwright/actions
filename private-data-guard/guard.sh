#!/usr/bin/env bash
# Fails when a private-data pattern matches anywhere in a repository: its files, their paths, or
# any commit's message, author, committer or changes. It reports only where (a file and line, or a
# commit), never the pattern or the matching text, so a failed run's log reveals nothing the change
# itself doesn't. The one exception is a file whose path matches: it has to be named to be found.
#
# Patterns are extended regular expressions (grep -E), one per line, matched case-insensitively.
# Blank lines and lines starting with # are skipped. They come from $PRIVATE_DATA_PATTERNS, else
# from the file $PRIVATE_DATA_PATTERNS_FILE names.
#
# Usage: guard.sh [repo folder] [revision range]
#   The range defaults to HEAD, the whole history behind the checked-out commit.
#
# Exit codes: 0 nothing matched, 1 something matched, 2 no patterns to match.
set -euo pipefail

repo=${1:-.}
range=${2:-HEAD}

patterns=${PRIVATE_DATA_PATTERNS:-}
if [[ -z $patterns && -n ${PRIVATE_DATA_PATTERNS_FILE:-} ]]; then
  patterns=$(<"$PRIVATE_DATA_PATTERNS_FILE")
fi
list=$(mktemp)
trap 'rm -f "$list"' EXIT
printf '%s\n' "$patterns" | grep -v -E '^[[:space:]]*(#|$)' >"$list" || true
if [[ ! -s $list ]]; then
  echo "::error::No private-data patterns to check against. Set the PRIVATE_DATA_PATTERNS secret; see https://github.com/tinwright/actions#private-data-guard"
  exit 2
fi

cd "$repo"
found=0

# Files in the working tree, tracked or not, except ignored ones. Only the path and line number are
# kept; the matching text is dropped before anything is printed.
while IFS=: read -r file line _; do
  echo "::error file=$file,line=$line::This line matches a private-data pattern."
  found=1
done < <(git grep -I -n -i -E --untracked -f "$list" 2>/dev/null || true)

while IFS= read -r file; do
  echo "::error file=$file::This file's path matches a private-data pattern."
  found=1
done < <(git ls-files -co --exclude-standard | grep -i -E -f "$list" || true)

# Every commit in the range: its author and committer names and emails, its message and its diff,
# so text removed in a later commit is still caught in the commit that added it.
if git rev-parse --verify -q HEAD >/dev/null; then
  while IFS= read -r commit; do
    if git show --no-color --format='%an%n%ae%n%cn%n%ce%n%B' --unified=0 "$commit" | grep -q -i -E -f "$list"; then
      echo "::error::Commit $commit matches a private-data pattern in its message, author, committer or changes."
      found=1
    fi
  done < <(git rev-list "$range")
fi

if [[ $found == 1 ]]; then
  echo "Private data found. Remove it from the files, and rewrite any commit named above before it is pushed or merged."
  exit 1
fi
echo "No private data found."
