#!/usr/bin/env bash
# Fork-only. Merges the latest upstream release into a sync branch and opens a PR that
# merges itself once CI passes. If the merge conflicts, opens an issue instead.
#
# Usage: .github/fork/sync-upstream.sh [upstream-tag]
# Env:   UPSTREAM_REPO (default DLYZZT/pi-desktop), UPSTREAM_URL (default its GitHub URL),
#        BASE_BRANCH (default main), DRY_RUN=1 to stop before pushing or calling GitHub.
set -euo pipefail

upstream_repo="${UPSTREAM_REPO:-DLYZZT/pi-desktop}"
upstream_url="${UPSTREAM_URL:-https://github.com/$upstream_repo.git}"
base="${BASE_BRANCH:-main}"
policy="scripts/architecture-policy.mjs"
tag="${1:-$(gh release view --repo "$upstream_repo" --json tagName --jq .tagName)}"
branch="sync/upstream-$tag"

git fetch --quiet --no-tags origin "$base"
# Upstream tags live outside refs/tags so they never collide with the fork's own release tags.
git fetch --quiet --no-tags "$upstream_url" "+refs/tags/$tag:refs/upstream-tags/$tag"
upstream_sha="$(git rev-parse "refs/upstream-tags/$tag^{commit}")"

if git merge-base --is-ancestor "$upstream_sha" "origin/$base"; then
  echo "$base already contains upstream $tag."
  exit 0
fi
if [ -z "${DRY_RUN:-}" ] && git ls-remote --exit-code --heads origin "$branch" >/dev/null; then
  echo "$branch already exists; its PR is in progress."
  exit 0
fi

git switch --quiet --force-create "$branch" "origin/$base"
if ! git merge --quiet --no-ff --no-edit -m "Merge upstream $tag" "$upstream_sha"; then
  conflicts="$(git diff --name-only --diff-filter=U)"
  if [ "$conflicts" = "$policy" ]; then
    # Budgets are re-fitted below, so upstream's policy always wins.
    git checkout --theirs -- "$policy"
    git add "$policy"
    git commit --quiet --no-edit
  else
    git merge --abort
    title="Upstream $tag needs a manual merge"
    echo "$title. Conflicted files:"
    echo "$conflicts"
    [ -n "${DRY_RUN:-}" ] && exit 2
    if [ -z "$(gh issue list --state open --search "\"$title\" in:title" --json number --jq '.[0].number')" ]; then
      gh issue create --title "$title" --body "Merging upstream \`$tag\` into \`$base\` conflicts in:

\`\`\`
$conflicts
\`\`\`

Resolve locally, then push the branch. Its PR merges itself once CI passes:

\`\`\`sh
git fetch --no-tags $upstream_url +refs/tags/$tag:refs/upstream-tags/$tag
git switch -c $branch origin/$base
git merge refs/upstream-tags/$tag   # resolve, then commit
node .github/fork/fit-line-budgets.mjs refs/upstream-tags/$tag && git commit -am 'chore(fork): fit line budgets' || true
git push -u origin $branch
gh pr create --base $base --title 'Upgrade to upstream $tag' --fill && gh pr merge --auto --merge
\`\`\`

See FORK.md."
    fi
    exit 0
  fi
fi

node .github/fork/fit-line-budgets.mjs "$upstream_sha"
if ! git diff --quiet -- "$policy"; then
  git commit --quiet -m "chore(fork): fit line budgets for the fork patch" -- "$policy"
fi

previous_base="$(git merge-base "origin/$base" "$upstream_sha")"
packaging_changes="$(git diff --name-only "$previous_base" "$upstream_sha" -- .github/workflows electron-builder.yml)"

if [ -n "${DRY_RUN:-}" ]; then
  echo "Dry run: $branch is ready locally ($(git rev-parse --short HEAD))."
  [ -n "$packaging_changes" ] && printf 'Upstream packaging changes:\n%s\n' "$packaging_changes"
  exit 0
fi

note="No upstream packaging files changed."
if [ -n "$packaging_changes" ]; then
  note="Upstream changed packaging files. If the fork release fails after merge, compare \`.github/workflows/fork-release.yml\` with upstream's \`release-windows\` job:

\`\`\`
$packaging_changes
\`\`\`"
fi

git push --quiet origin "$branch"
gh pr create --base "$base" --head "$branch" --title "Upgrade to upstream $tag" --body "Merges upstream [\`$tag\`](https://github.com/$upstream_repo/releases/tag/$tag) into \`$base\`.

This PR merges itself when the required checks pass. Merging releases the new version to installed apps.

$note"
gh pr merge "$branch" --auto --merge
