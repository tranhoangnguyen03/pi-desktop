# About this fork

This is [DLYZZT/pi-desktop](https://github.com/DLYZZT/pi-desktop) plus one feature:
**Desktop extension panels** (interactive extension text panels and slash-argument
completions, proposed upstream as [DLYZZT/pi-desktop#52](https://github.com/DLYZZT/pi-desktop/pull/52)).
Everything else comes from upstream. Builds are provided for Windows x64 and
macOS (Apple Silicon arm64 & Intel x64).

Installed Windows copies update from **this repository's releases**, not upstream's.
macOS packages are unsigned beta builds downloaded directly from Releases.

## How it stays current

1. **Daily sync** (`.github/workflows/fork-upstream-sync.yml`) checks for a new upstream
   release. If there is one, it merges that release into a `sync/upstream-<tag>` branch
   and opens an "Upgrade to upstream <tag>" PR set to merge itself.
2. **CI** is upstream's own `build-desktop.yml`, unchanged. Once the required checks pass,
   the PR merges.
3. **Release** (`.github/workflows/fork-release.yml`) runs on every push to `main`
   (or manual `workflow_dispatch`). If `package.json` has a version with no release
   here yet, it builds the Windows and macOS packages and publishes `v<version>`.
   Installed Windows apps then offer the update.

You step in only when:

- **The merge conflicts.** The sync opens an issue, "Upstream <tag> needs a manual merge",
  with the conflicted files and the commands to finish the merge. Once you push the
  branch, its PR merges itself after CI passes.
- **CI fails on a sync PR.** The PR stays open. Fix it on the sync branch.
- **The release job fails.** Nothing is published, so installed apps stay on the previous
  version. This usually means upstream changed how packages are built (the sync PR
  says so); update `fork-release.yml` to match upstream's release jobs.

## Keeping merges easy

- Fork-only files live in `FORK.md`, `.github/fork/` and `.github/workflows/fork-*.yml`.
  Upstream files are not edited for fork plumbing; the update feed is overridden on the
  `electron-builder` command line.
- The feature patch puts its logic in new files and touches upstream files at small hook
  points. Keep it that way: frequently edited upstream files such as `useAgentSession.ts`,
  `ChatInput.tsx` and `rpc-manager.ts` cause most conflicts.
- Upstream caps the length of large files (`scripts/architecture-policy.mjs`) and re-fits
  the caps to its own code. When the fork patch pushes one of its files over a cap, the
  sync raises that cap in a separate `chore(fork)` commit (`.github/fork/fit-line-budgets.mjs`).

## Versions

Fork releases use upstream's version numbers. The updater installs only a higher version,
so a fork-only change ships with the next upstream release. An urgent fork-only fix needs
a version bump, after which the fork is ahead of upstream until upstream passes that number.

## One-time repository setup

- Settings → General: allow auto-merge; automatically delete head branches.
- Branch protection for `main`: require PRs and the status checks **Quality gate**,
  **Tests (Windows x64)**, **Windows managed framework acceptance** and **Windows x64**.
  Require the jobs themselves, because a skipped job reports success.
- Actions secret `FORK_SYNC_TOKEN`: a fine-grained token for this repository with
  Contents, Pull requests, Issues and Workflows set to read and write.
- Actions → enable workflows (forks start with scheduled workflows disabled).

## Switching an installed app to this fork

Run this fork's installer once over the existing install. It uses the same app ID and
name, so it upgrades in place and keeps settings and sessions. To go back to upstream,
run an upstream installer.

## macOS Installation & Updates (Unsigned Beta)

Because releases from this fork are unsigned, macOS Gatekeeper blocks opening on first launch.

- **To run:** On macOS 15 Sequoia and later, Apple prevents opening unsigned apps via
  right-click. Go to **System Settings → Privacy & Security** and click **Open Anyway**,
  or open Terminal and run:
  ```sh
  xattr -cr "/Applications/Pi Agent Desktop.app"
  ```
- **Updates:** macOS's built-in updater (Squirrel.Mac) requires Apple code signatures and
  refuses to install unsigned updates. To prevent installation errors, macOS releases do
  not publish an update feed (`latest-mac.yml`). Checking for updates inside the app will
  report that the update is not available yet (`UPDATE_NOT_PUBLISHED`). When a new release
  is published, download the updated DMG or ZIP directly from this repository's Releases page.
