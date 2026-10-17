#!/usr/bin/env bash
# Tests private-data-guard/guard.sh against throwaway repositories: what it catches, that it
# passes clean ones, and that its output never contains a pattern or the text that matched.
set -uo pipefail

guard="$(cd "$(dirname "$0")/.." && pwd)/private-data-guard/guard.sh"
failures=0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export PRIVATE_DATA_PATTERNS=$'# a comment\n\nsecret-host\\.example\nACME-[0-9]+'

# A fresh repository with one commit holding `content` in notes.txt.
fresh() {
  local dir="$work/$1"
  git init -q "$dir"
  git -C "$dir" config user.name Tester
  git -C "$dir" config user.email tester@example.com
  git -C "$dir" config commit.gpgsign false
  printf '%s\n' "$2" >"$dir/notes.txt"
  git -C "$dir" add notes.txt
  git -C "$dir" commit -q -m "${3:-Add notes}"
  echo "$dir"
}

# expect <name> <exit code> <repo> [extra guard args]: runs the guard and checks its exit code,
# and that nothing it printed contains a pattern or matched text.
expect() {
  local name=$1 want=$2 dir=$3
  shift 3
  local out code
  out=$("$guard" "$dir" "$@" 2>&1)
  code=$?
  if [[ $code != "$want" ]]; then
    echo "FAIL $name: exit $code, expected $want"
    echo "$out" | sed 's/^/  /'
    failures=$((failures + 1))
  elif [[ -z ${LEAK_OK:-} ]] && grep -q -i -E 'secret-host|ACME-[0-9]' <<<"$out"; then
    echo "FAIL $name: the output reveals a pattern or the matching text"
    failures=$((failures + 1))
  else
    echo "ok   $name"
  fi
}

expect 'a clean repository passes' 0 "$(fresh clean 'Nothing to see here.')"
expect 'a matching line fails' 1 "$(fresh line 'Deployed to api.SECRET-HOST.example today.')"
expect 'a matching commit message fails' 1 "$(fresh message 'Fine text.' 'Fix ACME-1234')"

dir=$(fresh removed 'Ticket ACME-42 notes.')
printf 'Clean now.\n' >"$dir/notes.txt"
git -C "$dir" commit -q -am 'Tidy notes'
expect 'text removed by a later commit still fails' 1 "$dir"
printf 'More.\n' >"$dir/more.txt"
git -C "$dir" add more.txt
git -C "$dir" commit -q -m 'Add more'
expect 'a range after the text was removed passes' 0 "$dir" HEAD~1..HEAD

# A matching path has to be named so it can be found, so this one case skips the leak check; the
# path is in the change itself anyway.
dir=$(fresh path 'Fine text.')
printf 'x\n' >"$dir/acme-77.txt"
LEAK_OK=1 expect 'a matching untracked file path fails' 1 "$dir"

dir=$(fresh ignored 'Fine text.')
printf '*.local\n' >"$dir/.gitignore"
printf 'ACME-77\n' >"$dir/notes.local"
git -C "$dir" add .gitignore
git -C "$dir" commit -q -m 'Ignore local notes'
expect 'an ignored file is skipped' 0 "$dir"

dir=$(fresh author 'Fine text.')
git -C "$dir" -c user.email=me@secret-host.example commit -q --allow-empty -m 'Empty'
expect 'a matching author email fails' 1 "$dir"

expect 'an empty repository passes' 0 "$(mkdir "$work/empty" && git -C "$work/empty" init -q && echo "$work/empty")"

PRIVATE_DATA_PATTERNS=$'# only comments\n' expect 'no patterns exits 2' 2 "$(fresh nopatterns 'Fine text.')"

file="$work/patterns.txt"
printf 'acme-[0-9]+\n' >"$file"
PRIVATE_DATA_PATTERNS='' PRIVATE_DATA_PATTERNS_FILE=$file expect 'patterns from a file' 1 "$(fresh fromfile 'See ACME-9.')"

if [[ $failures != 0 ]]; then
  echo "$failures test(s) failed."
  exit 1
fi
echo 'All guard tests passed.'
