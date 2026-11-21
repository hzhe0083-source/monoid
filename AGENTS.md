# Working on monoid (for agents)

These rules apply to the whole repository. Each part has its own `AGENTS.md` beside its code, loaded when tools touch that directory.

## The parts

monoid (also built as still.fail, the same code under its other name: `client/i18n/brand.ts`) runs coding-agent sessions in team chats (Slack, Feishu, Comma, and its own chats) on user-owned **stations** driven by Claude Code, Codex, and other runtimes.

- `station/`: TypeScript station on bundled Node + Effect (`scripts/station-bundle.sh`), prebuilt native parts (`station/native`), and MoonBit program (`station/mb`) for readers, builders, and the whole station (not shipped alone until it matches TypeScript). Holds chats, sessions, agents, jobs, and accounts over the mesh.
- `cloud/`: Cloudflare Workers for accounts, workspaces, member credentials, and relays. People only.
- `client/core-ts/`: TypeScript + Effect client core for every app (accounts, station links, SQLite cache, views). UIs only render it. `client/shell` (Rust) is native IO, `client/iroh-wasm` is browser iroh, `client/i18n/catalog` holds shared zh/en strings with matching keys.
- `apps/mbui/`: single app for Android, iOS, macOS, Windows, Linux, and web in MoonBit on `libs/mbui`. `libs/comma-ui` is Comma's component library. `libs/sf-ui` is still.fail's component library.
- `libs/base/`: program-agnostic MoonBit base (Rust shell binding, `sql`, `scheduler`, mesh wire/device side, `hash`, `net`). `station/mb` uses shell-free packages.
- `libs/client-core/`: first MoonBit client-core slice on `libs/base` (zero-write chat open, `MdStore`, `FrameOutbox`). Unused in production yet.
- `web/`: web host for the mbui app, Preact pages, and `web/ui`. `apps/extension` sends browser pages to a chat.
- `website/`: official site. `rules/`: shared MoonBit lock/vault rules built to JS. `scripts/`: checks, releases, CI plan. `vendor/`: patched upstream code (see its README).
- `docs/`: build, run, and operate guides (`docs/development.md`, `docs/operations.md`, station setup notes) and release notes. Design lives in code comments and `AGENTS.md`. A comment naming another `docs/` file refers to a design doc deleted in #4614 (`git show ec9da461f6^:docs/<name>.md`), which stays its format or protocol spec.

## These files are kept true

- Update any `AGENTS.md` made untrue by a change in the same change. `scripts/check.sh` rejects missing paths.
- Put unchecked owner rules and non-obvious pitfalls in the narrowest directory's `AGENTS.md`, once, concisely. Do not repeat code or comments. State the rule and its reason without attribution or date annotations.
- Pair every new directory `AGENTS.md` with a one-line `CLAUDE.md` containing `@AGENTS.md`.

## Changes, checks and CI

### Pull requests and evidence

- Open one PR per request from `origin/main`. Split only when a maintainer asks. External contributors open one PR per issue.
- Squash each task into one commit before its first PR. Append commits after that without squashing.
- For requests from still.fail, use the requester's GitHub account when local `gh` has it. Otherwise use CommaBot and add `Co-authored-by: Name <requester-email>` to commits. For other sources, use the existing `gh` identity without CommaBot.
- End the PR description with the model(s) used and test frameworks run.
- Attach before-and-after images for UI changes, plus a short video for animation or timing changes. Upload evidence to GitHub and link it in the PR. Never commit PR-only assets.
- Merging to `main` deploys beta (`.github/workflows/pipeline.yml`, `scripts/plan.sh`), so keep `main` releasable. Bug fixes merge once latest checks pass. Product or visible changes need owner approval.

### Commit and pull request messages

- Follow `.agents/skills/ste-writing/SKILL.md` for commits and PR text. Write PR titles and descriptions in English. Use `{type}({scope}): {description}` for commit subjects (for example `feat(server): add mesh routes`).
- Add trailers only for user-visible changes (`scripts/changelog.ts`): `Changelog:` in Chinese (`修复：…`, `新增：…`, `改进：…`), `Changelog-parts:` (`station`, `web`, `android`, `desktop`, `cloud`), and `Fixes: FB-<n>`.
- For gated features (`client/core-ts/src/features.ts`), add `Changelog-channel: beta` for `beta` or `betaOnly` experimental features. For experimental features, name where to enable them (`新增：实验性功能「对话列表看板视图」中，…`). Write a stable line when opening to stable. Override prior lines in `docs/changelog-notes.json`.

### Checks and compatibility

- Run `sh scripts/check.sh full origin/main..HEAD` (narrow with `STILLFAIL_CHECK_PART`) for the part you changed before a PR. Git hooks run quick checks, and CI runs full checks.
- Add `Stable: yes` only for urgent fixes that cannot wait a day for stable (crash, data loss, lockout, broken updater). `.github/stable-plan.py` cherry-picks only those onto yesterday's `main`.
- Older stations and newer cores coexist. Drop compat shims 7 days after replacement ships, raising `OLDEST_CORE` (`station/src/api/oldest.ts`) and `OLDEST_STATION` (`client/core-ts/src/station/oldest.ts`). Migrate DBs forward only. Keep existing commands and shared links working.
- Update both `web/public/privacy.html` and `web/public/en/privacy.html` in the same PR for new data, third parties, or retention changes.
- Keep tests deterministic with test clocks and simulated networks (`docs/development.md`). Never add sleeps, retries, or longer deadlines. Put non-deterministic checks in `scripts/side.sh`. Never rerun a flaky check green: find and remove the uncontrolled input.

## To people there is one safe mode

- A person's own lock is the root of trust for their devices. A workspace lock keeps the roster (members, stations) and follows each person's lock for their devices.
- Never ask people to tell the two locks apart. Keep 安全模式, 受信任设备, and 批准 as one flow. Never send people to 个人锁 to enter a workspace or name it where the workspace lock appeared.
- Only a person changes their own devices. Owners and admins remove a member, never someone else's single device.
- Safe-mode members get a personal lock automatically (`client/core-ts/src/views/lock.ts` `ownLockFor`, `vouchersIn`) with no re-approval. Do not widen that rule (never by device id, never the approver of a device already on the lock), and do not narrow it without owner approval.
- Every error, refusal, and wait tells the person what to do next. Leave no dead ends.

## No polling between still.fail's own parts

`client/core-ts/`, `station/`, and `cloud/` never poll each other on a timer. The owning part pushes changes over existing sockets (`cloud/src/types.ts` `/v1/events`, station presence socket) or event streams. Readers read on notification, on first show, and on reconnect. Never long-poll: serve a stream.

Allow a timer only for: heartbeats or pings, local machine sampling (CPU, memory, network), failure retries with backoff or timeouts/deadlines, burst debouncing, or external systems without push (registries, provider quotas, third-party feeds).

`scripts/check.sh` rejects new timers in those three parts unless marked `timer:` with the reason. Drop old-part support rather than poll it.

## No way into a station from outside

still.fail has no public entrance. A station is reached only over the mesh (`station/src/mesh/`), admitting workspace stations by key and members by cloud-signed credentials. All other station listeners stay local (`127.0.0.1`, Unix socket, or launcher fd). Never add bind-address settings, tunnels (Tailcat, ngrok, cloudflared, Tailscale funnel), port forwards, or inbound webhooks. Stations connect outbound to cloud, Slack Socket Mode, Feishu, and Comma.

`cloud/` stores no chats and proxies no station requests. Stations serve workspace-wide operations over the mesh. `scripts/check.sh` rejects non-local station listeners and tunnel names in `station/` or `cloud/`.

## The cloud is the account system and nothing else

Only accounts, sign-in, workspaces, members, roles, invitations, station lists, and member credentials depend on `cloud/`. Everything else flows over the mesh and works with the cloud down, slow, or withholding data. Relays carry only end-to-end encrypted packets. Push notifications (`cloud/src/push.ts`) are the sole exception.

Cloud-signed data is not enough because the cloud can still delay or withhold it. Put no new feature state in `cloud/`.

Locks live on stations (`station/src/cloud/AGENTS.md`, `client/core-ts/src/views/AGENTS.md`, `rules/AGENTS.md`). Devices read and submit locks to stations, stations sync via fork choice, and unaccepted entries stay pending on the signing device (`client/core-ts/src/lock-pending.ts`) unless the lock names no stations. Cloud fallback and mirroring exist only for older parts and go 7 days after new stations ship.

Lock threat model (`rules/protocol/lock.spthy`):

- The adversary is the cloud and every station except the one queried. Only signatures of devices on a lock decide. Neither cloud nor station arbitrates order.
- Settle forks by fork choice and re-signing. Hand unresolvable conflicts (mutual removal, full takeover, all signers lost) to the person with a way out.
