# actions

Reusable GitHub Actions that every [tinwright](https://github.com/tinwright) workshop calls, so the
rules live in one place.

| Action | What it does |
|---|---|
| [`private-data-guard`](#private-data-guard) | Fails a change when it contains private data, without saying what the private data is. |

Planned, as the workshops need them: per-tool release builds, the catalog-site deploy, and
`claude plugin validate`.

## private-data-guard

Fails when any of a list of secret patterns matches a repository's files, file paths, or any
commit's message, author, committer or changes. Patterns describe what must never be published:
company hosts, internal ID formats, work email addresses.

The patterns live only in a secret, never in a repository, and the guard never prints them or the
text they matched. It names the file and line, or the commit, and nothing else, so a failed check on
a public pull request gives nothing away. The one exception is a file whose path matches, which is
named so it can be found; that path is already in the change.

### Use it

```yaml
name: Private-data guard

on:
  # pull_request_target runs this file from the base branch with the repository's secrets, so pull
  # requests from forks are checked too. It only reads the pull request's files and never runs them.
  pull_request_target:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  guard:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          ref: ${{ github.event.pull_request.head.sha || github.sha }}
          fetch-depth: 0
          persist-credentials: false
      - uses: tinwright/actions/private-data-guard@main
        with:
          patterns: ${{ secrets.PRIVATE_DATA_PATTERNS }}
```

Then add the secret `PRIVATE_DATA_PATTERNS`: extended regular expressions (`grep -E`), one per
line, matched case-insensitively. Blank lines and lines starting with `#` are skipped. Add it as a
Dependabot secret too, since Dependabot's pull requests can't read Actions secrets. While a
repository is private on GitHub Free it can't read organization secrets, so set it on each
repository.

| Input | Default | |
|---|---|---|
| `patterns` | (required) | The patterns. Pass a secret, never a literal. |
| `path` | `.` | The repository folder. |
| `range` | `HEAD` | The commits to check. The default is the whole history, so check out with `fetch-depth: 0`. |

The step exits 1 when something matches and 2 when there are no patterns, so a missing secret fails
loudly rather than passing.

### Run it locally

```sh
PRIVATE_DATA_PATTERNS_FILE=~/.config/tinwright/private-data-patterns private-data-guard/guard.sh path/to/repo
```

Run it before the first push of anything that came from an internal repository. Something in the
history has to be rewritten before it's pushed; once pushed, assume it's public.

## Develop

```sh
test/guard.test.sh
```

## Licence

[MIT](LICENSE)
