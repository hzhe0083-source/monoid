import { ultrafastModel, type ModelSpeed } from "../../../client/core-ts/src/model-speed.ts";
// Which account a session runs on (spend, pick, health_of, model_efforts, configure): the
// pool's choice among the station's profiles, kept while usable, moved off one whose allowance ran out, and changed by
// hand (profile, model, effort, fast). How profiles are doing comes from outside (the accounts module's checks and
// allowances: `setHealth`); which ran into their allowance lately is kept here.
import type { Clock } from "effect";
import { log } from "../ops/log.ts";
import { tr, type Lang, stationLang } from "../ops/i18n.ts";
import { CONTEXT_RUNTIMES, checkContext } from "./context-cap.ts";
import type { Store } from "../store/store.ts";
import type { SessionRow } from "../store/rows.ts";
import { type HubConfig, type Profile, runs, runtimeNamed, runtimeTitle, sameModel, spelling } from "./config.ts";
import { modelKey } from "../read/usage.ts";
import { availableEfforts, cheapToLeave, commonEfforts, type ProfileHealth, pickProfile, reportedEfforts, serves, signsIn, urgency, usable, windowsOf } from "./pool.ts";
import { agyScopeForModel } from "../accounts/agy-quota.ts";
import type { RuntimeKind } from "../agents/runtime.ts";
import { accessKind, billedPerUse, FAST_RUNTIMES } from "../agents/profiles.ts";

/// How long a profile a turn ran into the allowance of is passed over when its allowance is not read again.
const SPENT_FOR_MS = 60 * 60 * 1000;
/// Where models are compacted is learnt from the calls of this long, and learnt again this often.
const COMPACTIONS_OVER_MS = 7 * 24 * 60 * 60 * 1000;
const COMPACTIONS_EVERY_MS = 60 * 60 * 1000;
/// How many of a session's last calls say whether it compacted lately.
const CALLS_LOOKED_AT = 200;

/// How a session runs from its next turn on. A field left out: unchanged; null: back to the default. `profiles`: the set
/// of profiles it may run on (one keeps it to that one; null: all of them). `repick`: its account picked again now, as a
/// new session's would be (`Accounts.repick`).
export type SessionChange = { runtime?: string; profile?: string | null; profiles?: string[] | null; model?: string | null; effort?: string | null; fast?: boolean | null; speed?: ModelSpeed | null; tui?: boolean; context?: number | null; repick?: boolean; afresh?: boolean | null };

/// A profile as a session's runtime starts on it, with its spelling of the session's model.
export type RunOn = Profile & { spelling(model: string): string | null };

const withSpelling = (p: Profile): RunOn => ({ ...p, spelling: (model: string) => spelling(p, model) });

export type AccountsDeps = {
  config(): HubConfig;
  store: Store;
  /// The profiles of sessions with a process now (their load), `except`'s left out.
  running(except?: string): string[];
  /// Its time.
  clock: Clock.Clock;
  /// Whether session `key` may run on a profile: one allowed in its workspace; absent: any.
  allows?(key: string, profile: Profile): boolean;
  /// Session `key`, left to the station, was moved to another profile by it (`runOn`, `spend`): `was` how it ran before.
  moved?(key: string, was: SessionRow): void;
  /// Session `key` automatically fell back from a subscription profile to a billed-per-use profile.
  billedFallback?(info: { session: string; workspace: string | null; runtime: RuntimeKind; profile: Profile }): void;
};

export class Accounts {
  private deps: AccountsDeps;
  private health: (id: string) => ProfileHealth = () => ({});
  private checkAgain: (id: string) => Promise<unknown> = async () => {};
  private quotaAgain: (id: string) => Promise<unknown> = async () => {};
  private rechecking = new Map<string, Promise<void>>();
  private picked = new Map<string, number>();
  /// Accounts a turn ran into the allowance of, and when: passed over until their allowance is read again, or for
  /// SPENT_FOR_MS when it is not.
  private spent = new Map<string, number>();
  /// Models that ran into their own limit on an account (Claude Code's "You've reached your Fable limit."), by account:
  /// the model as the runtime named it, as the session ran it (null: its profile's default) and when. That model alone
  /// is passed over there, for SPENT_FOR_MS (the runtime says no refill time); the account's others run on (#4643).
  private modelSpent = new Map<string, { named: string; ran: string | null; at: number }[]>();
  /// Model groups of an account whose windows are split by them (Antigravity's Gemini vs Claude / GPT) that a turn ran
  /// into the allowance of, by `${account}\0${group}`, and when: its runtime's words name no model ("Individual quota
  /// reached"), so the group the turn's model is of is passed over, as `spent` the whole account would be; the other
  /// group runs on there (2026-11-16: a Claude limit marked the account spent, and its Gemini sessions, its Gemini week
  /// at 16%, moved off it again and again).
  private scopeSpent = new Map<string, number>();
  /// Where each model's context is compacted on this station, and when that was learnt.
  private compactions: [number, Map<string, number>] | null = null;

  constructor(deps: AccountsDeps) {
    this.deps = deps;
  }

  /// Lets the pool see profiles' checks and allowances.
  setHealth(health: (id: string) => ProfileHealth) {
    this.health = health;
  }

  /// Lets the pool have a profile checked again (accounts/index.ts `check`).
  setRecheck(recheck: (id: string) => Promise<unknown>) {
    this.checkAgain = recheck;
  }

  /// Lets the pool have a profile's allowance asked again (accounts/index.ts `readQuota`).
  setQuotaAgain(read: (id: string) => Promise<unknown>) {
    this.quotaAgain = read;
  }

  /// What a turn on profile `id` running `model` ran into, its failure's words naming no limit: its allowance asked
  /// again says it (the runtime's words for a limit change, as Claude Code's for Fable's did on 2026-11-14: "You've hit
  /// your Fable limit", read as the model failing, so the session stayed on the account and failed again and again).
  /// The name of the model whose own week is used up there, null when a window of the account's is, else undefined.
  async limitAfter(id: string, model: string | null): Promise<string | null | undefined> {
    try {
      await this.quotaAgain(id);
    } catch {
      return undefined;
    }
    const now = this.deps.clock.currentTimeMillisUnsafe();
    const quota = this.healthOf(id).quota;
    const full = (w: any) => Number(w?.usedPercent) >= 100 && !(typeof w?.resetsAt === "number" && w.resetsAt <= now);
    if (windowsOf(this.quotaForModel(id, quota, model)).some(full)) return null;
    const runs = model ?? this.deps.config().profiles.find((p) => p.id === id)?.model ?? null;
    if (runs === null || quota?.state !== "ok" || !Array.isArray(quota.scoped)) return undefined;
    const own = quota.scoped.find((w: any) => full(w) && ownedBy(w, runs));
    return own ? (own.scope as string) : undefined;
  }

  /// Profile `id` checked again, a runtime on it having failed to sign in (once at a time): one whose login is over is
  /// passed over from then on, and a session left to the station goes on on another (`runOn`).
  recheck(id: string): Promise<void> {
    const busy = this.rechecking.get(id);
    if (busy) return busy;
    const run = this.checkAgain(id)
      .then(
        () => {},
        () => {},
      )
      .finally(() => this.rechecking.delete(id));
    this.rechecking.set(id, run);
    return run;
  }

  /// Several profiles can spend the same account's allowance. An unknown account keeps its own profile's identity.
  private accountKey(id: string, health = this.health(id)): string {
    return typeof health.account === "string" && health.account !== "" ? `account:${health.account}` : `profile:${id}`;
  }

  /// Profiles can be different logins to the same account, whose allowance they share.
  sameAccount(a: string, b: string): boolean {
    return this.accountKey(a) === this.accountKey(b);
  }

  /// An explicit reset supersedes the failure which made this account unavailable to the pool.
  resetAllowance(id: string): void {
    const key = this.accountKey(id);
    this.spent.delete(key);
    this.modelSpent.delete(key);
    for (const scope of ["gemini", "3p"]) this.scopeSpent.delete(`${key}\0${scope}`);
  }

  /// Whether profile `id`'s windows are split by model group (Antigravity's), so a limit its runtime names no model of
  /// is its turn's model's group's alone.
  private hasAgyScopes(id: string, quota: any): boolean {
    return this.deps.config().profiles.find((p) => p.id === id)?.runtimes.includes("agy") === true || windowsOf(quota).some((w) => w?.scope === "gemini" || w?.scope === "3p");
  }

  healthOf(id: string): ProfileHealth {
    const health: ProfileHealth = { ...this.health(id) };
    const key = this.accountKey(id, health);
    // Another profile of the same account may have read its allowance more recently. A failed read does not replace a
    // successful one; sign-in checks remain specific to each profile.
    if (key.startsWith("account:")) {
      for (const other of this.deps.config().profiles) {
        if (other.id === id) continue;
        const candidate = this.health(other.id);
        if (this.accountKey(other.id, candidate) !== key || candidate.quota?.state !== "ok") continue;
        if (health.quota?.state !== "ok" || Number(candidate.quota.checkedAt ?? 0) > Number(health.quota.checkedAt ?? 0)) health.quota = candidate.quota;
      }
    }
    const at = this.spent.get(key);
    if (at !== undefined) {
      // Read again since: what it says now counts.
      const checked = health.quota?.checkedAt;
      if ((typeof checked === "number" && checked > at) || this.deps.clock.currentTimeMillisUnsafe() - at > SPENT_FOR_MS) this.spent.delete(key);
      else health.spent = true;
    }
    return health;
  }

  /// How profile `id` is doing for running `model` (null: its own default): spent as well while that model is passed
  /// over on its account, having run into its own limit there; where windows are split by model group (Antigravity's
  /// Gemini vs Claude / GPT), only that group's windows weigh on `model`.
  private healthFor(id: string, model: string | null | undefined): ProfileHealth {
    const health = this.healthOf(id);
    const quota = this.modelQuota(id, health.quota, model);
    const scoped = quota !== health.quota ? { ...health, quota } : health;
    return this.scopeSpentAt(id, model, health) !== undefined || this.modelSpentAt(id, model, health) !== undefined ? { ...scoped, spent: true } : scoped;
  }

  private quotaForModel(id: string, quota: any, model: string | null | undefined): any {
    const wins = windowsOf(quota);
    if (wins.length === 0 || !wins.some((w) => w?.scope === "gemini" || w?.scope === "3p")) return quota;
    const chosen = model ?? this.deps.config().profiles.find((p) => p.id === id)?.model ?? null;
    const want = agyScopeForModel(chosen);
    const filtered = wins.filter((w) => w?.scope === undefined || w.scope === want);
    return filtered.length > 0 && filtered.length !== wins.length ? { ...quota, windows: filtered } : quota;
  }

  /// What weighs on `model` running on profile `id`: `quotaForModel`, and the model's own week under a Claude
  /// subscription's (`scoped`, Fable's) as one of its windows. Left out, an account whose Fable week was used up looked
  /// free to a Fable session, which moved there, failed at once and moved again (2026-11-14).
  private modelQuota(id: string, quota: any, model: string | null | undefined): any {
    const q = this.quotaForModel(id, quota, model);
    const runs = model ?? this.deps.config().profiles.find((p) => p.id === id)?.model ?? null;
    if (runs === null || quota?.state !== "ok" || !Array.isArray(quota.scoped)) return q;
    const own = quota.scoped.filter((w: any) => ownedBy(w, runs));
    return own.length > 0 ? { ...q, windows: [...windowsOf(q), ...own] } : q;
  }

  /// Whether profile `id` can run `model` now (pool.ts `usable`).
  private can(id: string, model: string | null | undefined): boolean {
    return usable(this.healthFor(id, model), this.deps.clock.currentTimeMillisUnsafe());
  }

  supportsUltrafast(profile: Profile, model?: string | null): boolean {
    return accessKind(profile) === "subscription" && ultrafastModel(model ?? profile.model, this.health(profile.id).check?.codexUltrafastModels);
  }

  /// Which of `candidates` session `row` may use: its chosen subset while at least one of them is still configured and
  /// allowed here, else all of `candidates`.
  private poolFor(row: SessionRow, candidates: Profile[]): [Profile[], string[] | null] {
    const kept = new Set(row.profiles ?? []);
    const subset = candidates.filter((p) => kept.has(p.id));
    const allowed = subset.length > 0 ? subset : candidates;
    const pool = row.speed === "ultrafast" ? allowed.filter((p) => this.supportsUltrafast(p, row.model)) : allowed;
    return [pool, subset.length > 0 ? row.profiles ?? null : null];
  }

  /// The profiles session `row` could go on on other than its own, left to the station: those of its runtime allowed in
  /// its workspace (and in its chosen set, when kept to several) that run its model, or, when none does, all of them (as
  /// `runOn` and `spend`). Kept to one: none.
  private others(row: SessionRow): Profile[] {
    const runtime = runtimeNamed(row.runtime);
    if (!runtime || row.profilePinned) return [];
    const workspaceAll = this.deps.config().profiles.filter((p) => p.runtimes.includes(runtime) && this.allows(row.key, p));
    const [all] = this.poolFor(row, workspaceAll);
    const strict = all.some((p) => serves(p, row.model));
    return all.filter((p) => p.id !== row.profile && (!strict || serves(p, row.model)));
  }

  /// When the model group of `model` (null: profile `id`'s default) ran into its allowance on `id`'s account, while it
  /// is passed over (as `spent`: until its allowance is read again, or for SPENT_FOR_MS); undefined on an account whose
  /// windows are not split by group.
  private scopeSpentAt(id: string, model: string | null | undefined, health = this.healthOf(id)): number | undefined {
    if (!this.hasAgyScopes(id, health.quota)) return undefined;
    const chosen = model ?? this.deps.config().profiles.find((p) => p.id === id)?.model ?? null;
    const k = `${this.accountKey(id, health)}\0${agyScopeForModel(chosen)}`;
    const at = this.scopeSpent.get(k);
    if (at === undefined) return undefined;
    const checked = health.quota?.checkedAt;
    if ((typeof checked === "number" && checked > at) || this.deps.clock.currentTimeMillisUnsafe() - at > SPENT_FOR_MS) {
      this.scopeSpent.delete(k);
      return undefined;
    }
    return at;
  }

  /// When `model` (null: profile `id`'s default) ran into its own limit on `id`'s account, while it is passed over: for
  /// SPENT_FOR_MS, or until its allowance read again says that model's own window (`scoped`), which then weighs on it
  /// itself (`modelQuota`).
  private modelSpentAt(id: string, model: string | null | undefined, health = this.healthOf(id)): number | undefined {
    const key = this.accountKey(id, health);
    const now = this.deps.clock.currentTimeMillisUnsafe();
    const quota = health.quota;
    const readSince = (s: { named: string; at: number }) =>
      quota?.state === "ok" && typeof quota.checkedAt === "number" && quota.checkedAt > s.at && Array.isArray(quota.scoped) && quota.scoped.some((w: any) => typeof w?.scope === "string" && sameWords(w.scope, s.named));
    const kept = (this.modelSpent.get(key) ?? []).filter((s) => now - s.at <= SPENT_FOR_MS && !readSince(s));
    if (kept.length > 0) this.modelSpent.set(key, kept);
    else this.modelSpent.delete(key);
    const runs = model ?? this.deps.config().profiles.find((p) => p.id === id)?.model ?? null;
    // The runtime names it in words ("Fable" for claude-fable-5-1); one run by its default, unknown, is the same default.
    const named = (s: { named: string; ran: string | null }) =>
      runs === null ? s.ran === null : (s.ran !== null && sameModel(runs, s.ran)) || modelWords(s.named).every((w) => modelWords(modelKey(runs)).includes(w));
    return kept.filter(named).at(-1)?.at;
  }

  /// Chooses the profile a session runs on (pool.ts); `except`: the session it is chosen for, whose own process is not
  /// counted.
  pick(candidates: Profile[], model: string | null | undefined, strict: boolean, except?: string): Profile {
    const running = this.deps.running(except);
    const load = new Map<string, number>();
    for (const id of running) {
      const key = this.accountKey(id);
      load.set(key, (load.get(key) ?? 0) + 1);
    }
    const profile = pickProfile(candidates, model, { health: (id) => this.healthFor(id, model), load: (id) => load.get(this.accountKey(id)) ?? 0, lastPicked: (id) => this.picked.get(this.accountKey(id)) ?? 0, now: () => this.deps.clock.currentTimeMillisUnsafe() }, strict);
    this.picked.set(this.accountKey(profile.id), this.deps.clock.currentTimeMillisUnsafe());
    return profile;
  }

  /// Whether session `key` may run on `profile` (its workspace's).
  allows(key: string, profile: Profile): boolean {
    return profile.enabled !== false && (this.deps.allows?.(key, profile) ?? true);
  }

  /// The profile a session's runtime starts on, asked again before each turn: its own while usable (on another it goes
  /// on afresh, afresh.ts), else the one the pool picks among those of its runtime allowed in its workspace. One billed
  /// per use it leaves before the next turn for one paid for already that can run it (without waiting for
  /// `cheapToLeave`); one whose short window is nearly full it leaves for one paid for alike that is not only when that
  /// loses little (pool.ts `cheapToLeave`: its context was just compacted, or is about to be). Neither moves while its
  /// process has work going in the background (`holding`: commands and subagents, which end with it). Its own unable to
  /// run it and no other able either (every allowance used up), it stays where it is and waits there (`refillsAt`); its
  /// own unable even to sign in, it moves once to one that signs in. A move is told (`moved`, said in its chat) unless
  /// `quiet`: a change by hand says its own. `across` (before a turn): none of its runtime's able to run it now, it
  /// goes on on another runtime's that runs its model and can, as `spend` moves it when a turn ran into the allowance
  /// (`takeAcross`), rather than first running a turn into a limit it knows of.
  runOn(key: string, holding = false, quiet = false, across = false): RunOn {
    const { store } = this.deps;
    const row = store.getSession(key);
    if (!row) throw new Error(`unknown session ${key}`);
    const runtime = runtimeNamed(row.runtime);
    if (!runtime) throw new Error(`session ${key} runs an unknown runtime ${row.runtime}`);
    const all = this.deps.config().profiles.filter((p) => p.runtimes.includes(runtime));
    const workspaceCandidates = all.filter((p) => this.allows(key, p));
    // Left to the station, none of its runtime's able to run its model now: one of another runtime's that can.
    const elsewhere = (kept: string[] | null): RunOn | null => {
      if (!across || row.profilePinned || kept !== null || row.model === null) return null;
      const next = this.takeAcross(key, row, null, "session taken on by another runtime's profile", quiet);
      return next ? withSpelling(next) : null;
    };
    if (workspaceCandidates.length === 0) {
      const moved = elsewhere(null);
      if (moved) return moved;
    }
    // Profiles there are, none of them for its workspace: said so, for people to allow one.
    if (workspaceCandidates.length === 0 && all.length > 0) throw new Error(tr(stationLang(), "station.session.noProfileHere", { runtime: runtimeTitle(runtime) }));
    const [candidates, keptProfiles] = this.poolFor(row, workspaceCandidates);
    if (row.speed === "ultrafast" && (candidates.length === 0 || (row.profilePinned && !candidates.some((p) => p.id === row.profile)))) {
      throw new Error(tr(stationLang(), "station.speed.ultrafast_unavailable"));
    }
    // Kept to it by hand: that one, whatever it says. Otherwise its own while it can run it: usable, and with its model
    // enabled.
    const current = candidates.find((p) => p.id === row.profile);
    const now = this.deps.clock.currentTimeMillisUnsafe();
    // Of the windows that weigh on its model alone (an Antigravity account's Claude / GPT ones do not on Gemini).
    const crowded = (p: Profile) => urgency(this.healthFor(p.id, row.model).quota, now).crowded;
    // (Its model counts only where one of them has it enabled, as in `spend` and the pool: else each call would move it
    // to the least loaded, its own process counted where it is, back and forth.)
    const strict = candidates.some((p) => serves(p, row.model));
    const fits = (p: Profile) => !strict || serves(p, row.model);
    const keeps = current && (row.profilePinned || (this.can(current.id, row.model) && fits(current)));
    let among = candidates;
    if (current && keeps) {
      if (row.profilePinned) return withSpelling(current);
      // It moves from one billed per use to one paid for already on the next turn without waiting for `cheapToLeave`,
      // and from a crowded paid-for account to an uncrowded one (the pool puts those last) only when that loses little
      // (`cheapToLeave`); never from one paid for already to one billed per use.
      const paid = (p: Profile) => !billedPerUse(p);
      const better = (p: Profile) =>
        p.id !== current.id && fits(p) && this.can(p.id, row.model) && (paid(p) === paid(current) ? crowded(current) && !crowded(p) : paid(p));
      among = candidates.filter(better);
      const upgrading = !paid(current) && among.some(paid);
      if (among.length === 0 || holding || (!upgrading && !this.cheapToLeave(key))) return withSpelling(current);
    } else {
      // It goes to those that can run it now; none can: to those that at least sign in (it waits for their refill).
      // When its own is as good as any, it stays. The pool, given none that can run, picks the one picked least
      // recently, so each asking moved it on to the next spent account (2026-11-10: asked three times before a turn,
      // a session was moved three times in a second, each a notice in its chat, and waited for the refill of the
      // account it ended on, days away, while another's five hours refilled).
      const standing = (p: Profile) => (this.can(p.id, row.model) ? 2 : signsIn(this.healthOf(p.id)) ? 1 : 0);
      const fit = candidates.filter(fits);
      const best = Math.max(...fit.map(standing));
      if (best < 2) {
        const moved = elsewhere(keptProfiles);
        if (moved) return moved;
      }
      if (current && fits(current) && standing(current) >= best) return withSpelling(current);
      if (fit.length > 0) among = fit.filter((p) => standing(p) === best);
    }
    if (candidates.length === 0) throw new Error(`session ${key}: no profile runs ${row.runtime}`);
    const next = this.pick(among, row.model, false);
    if (next.id !== row.profile || keptProfiles !== (row.profiles ?? null)) {
      store.setSessionProfile(key, next.id, false, keptProfiles);
      if (next.id !== row.profile) {
        log.info("hub", "session taken on by another profile", { session: key, from: row.profile, to: next.id });
        if (!quiet) {
          this.deps.moved?.(key, row);
          const prev = current ?? this.deps.config().profiles.find((p) => p.id === row.profile);
          if (billedPerUse(next) && (!prev || !billedPerUse(prev)) && candidates.some((p) => !billedPerUse(p))) {
            this.deps.billedFallback?.({ session: key, workspace: row.ws ?? null, runtime, profile: next });
          }
        }
      }
    }
    return withSpelling(next);
  }

  /// Session `key`, left to the station (or kept to several accounts), has its account picked again now, as a new
  /// session's would be: among those of its runtime allowed in its workspace (and in its chosen set), its own process not
  /// counted on the one it is on (pool.ts). The one it is on stays when it is still the pool's choice; on another it goes
  /// on afresh (afresh.ts).
  repick(key: string): void {
    const { store } = this.deps;
    const row = store.getSession(key);
    if (!row) throw new Error(`unknown session ${key}`);
    const runtime = runtimeNamed(row.runtime);
    if (!runtime) throw new Error(`session ${key} runs an unknown runtime ${row.runtime}`);
    const workspaceCandidates = this.deps.config().profiles.filter((p) => p.runtimes.includes(runtime) && this.allows(key, p));
    if (workspaceCandidates.length === 0) throw new Error(tr(stationLang(), "station.session.noProfileHere", { runtime: runtimeTitle(runtime) }));
    const [candidates, keptProfiles] = this.poolFor(row.profilePinned ? { ...row, profiles: null } : row, workspaceCandidates);
    if (row.speed === "ultrafast" && candidates.length === 0) throw new Error(tr(stationLang(), "station.speed.ultrafast_unavailable"));
    const next = this.pick(candidates, row.model, false, key);
    store.setSessionProfile(key, next.id, false, keptProfiles);
    if (next.id !== row.profile) log.info("hub", "session's account picked again", { session: key, from: row.profile, to: next.id });
  }

  /// Whether session `key` loses little by going on afresh on another account (pool.ts `cheapToLeave`).
  private cheapToLeave(key: string): boolean {
    const now = this.deps.clock.currentTimeMillisUnsafe();
    const { store } = this.deps;
    if (store.recentlyCompacted(key)) return true;
    if (!store.compactionsReady()) return cheapToLeave(store.lastContexts(key, CALLS_LOOKED_AT), new Map());
    if (this.compactions === null || now - this.compactions[0] > COMPACTIONS_EVERY_MS) this.compactions = [now, store.compactionPoints(now - COMPACTIONS_OVER_MS)];
    return cheapToLeave(store.lastContexts(key, CALLS_LOOKED_AT), this.compactions[1]);
  }

  /// Profile `id` as a session's runtime runs on it; null when the station no longer has it.
  profile(id: string): RunOn | null {
    const profile = this.deps.config().profiles.find((p) => p.id === id);
    return profile ? withSpelling(profile) : null;
  }

  /// A turn of the session ran into the allowance of `ranOn`, the profile its process was started on (null: the
  /// session's own): that profile is passed over for now, and a session left to the station moves to another of its
  /// runtime's that can run it now; one moved off it while the turn ran (changed by hand, its profile deleted) goes on
  /// where it was moved. `model`: the model whose own limit it was, as the runtime named it (runtime.ts `modelLimitOf`),
  /// which alone is passed over on that account, its other models still run there (#4643). The names of the one left and
  /// the one taken when it moved; null when it is kept to its profile or none other can.
  spend(key: string, ranOn: string | null, model: string | null = null): [string, string] | null {
    const { store } = this.deps;
    const row = store.getSession(key);
    if (!row) throw new Error(`unknown session ${key}`);
    const left = ranOn ?? row.profile;
    const config = this.deps.config();
    const now = this.deps.clock.currentTimeMillisUnsafe();
    const ran = row.model ?? config.profiles.find((p) => p.id === left)?.model ?? null;
    const spendModel = (named: string) => this.modelSpent.set(this.accountKey(left), [...(this.modelSpent.get(this.accountKey(left)) ?? []), { named, ran, at: now }]);
    if (model !== null) spendModel(model);
    else {
      // Its words name no model (Antigravity's "Individual quota reached"): the model's own week (`scoped`, a Pro
      // account's Argon) when that is what is used up, else the model's group on an account whose windows are split by
      // group, else the account.
      const q = this.healthOf(left).quota;
      const fresh = (w: any) => (typeof w?.resetsAt === "number" && w.resetsAt <= now ? 0 : Number(w?.usedPercent) || 0);
      const own = ran !== null && q?.state === "ok" && Array.isArray(q.scoped) ? q.scoped.find((w: any) => ownedBy(w, ran)) : undefined;
      const baseUsed = Math.max(0, ...windowsOf(this.quotaForModel(left, q, ran)).map(fresh));
      if (own && (fresh(own) >= 100 || (fresh(own) > baseUsed && baseUsed < 90))) spendModel(own.scope as string);
      else if (this.hasAgyScopes(left, q)) this.scopeSpent.set(`${this.accountKey(left)}\0${agyScopeForModel(ran)}`, now);
      else this.spent.set(this.accountKey(left), now);
    }
    const name = (id: string) => config.profiles.find((p) => p.id === id)?.name ?? id;
    if (row.profile !== left) return [name(left), name(row.profile)];
    if (row.profilePinned) return null;
    const runtime = runtimeNamed(row.runtime);
    if (!runtime) return null;
    // As the pool: those that run its model, or, when none does (a connect's binding from before models were
    // enabled), all of its runtime's.
    const workspaceAll = config.profiles.filter((p) => p.runtimes.includes(runtime) && this.allows(key, p));
    const [all, keptProfiles] = this.poolFor(row, workspaceAll);
    const strict = all.some((p) => serves(p, row.model));
    const candidates = all.filter((p) => p.id !== left && (!strict || serves(p, row.model)) && this.can(p.id, row.model));
    if (candidates.length === 0) {
      if (keptProfiles !== null) return null;
      const next = this.takeAcross(key, row, left, "allowance ran out; session taken on by another runtime's profile", false);
      return next ? [name(left), next.name] : null;
    }
    const next = this.pick(candidates, row.model, false);
    store.setSessionProfile(key, next.id, false, keptProfiles);
    log.info("hub", "allowance ran out; session taken on by another profile", { session: key, from: left, to: next.id });
    this.deps.moved?.(key, row);
    const prev = config.profiles.find((p) => p.id === left);
    if (billedPerUse(next) && (!prev || !billedPerUse(prev)) && all.some((p) => !billedPerUse(p))) {
      this.deps.billedFallback?.({ session: key, workspace: row.ws ?? null, runtime, profile: next });
    }
    return [name(left), next.name];
  }

  /// Session `row`, left to the station, with no profile of its runtime able to run its model now (`left` the one whose
  /// allowance a turn ran into, null: before a turn, `runOn`): it goes on on a profile of another runtime that runs the
  /// same model and can now (the user, 2026-11-15: 「跨 runtime 自动切」), as a change of runtime by hand does
  /// (lifecycle.ts `configure`): its runtime session kept as one it ran in, the new one started afresh (afresh.ts). Its
  /// effort, speed and most context go along only where the new runtime takes them. Told (`moved`) unless `quiet`. The
  /// profile taken; null when none can.
  private takeAcross(key: string, row: SessionRow, left: string | null, said: string, quiet: boolean): Profile | null {
    const runtime = runtimeNamed(row.runtime);
    const model = row.model;
    if (!runtime || model === null || row.speed === "ultrafast") return null;
    const config = this.deps.config();
    const candidates = config.profiles.filter((p) => !p.runtimes.includes(runtime) && this.allows(key, p) && runs(p, model) && this.can(p.id, model));
    if (candidates.length === 0) return null;
    const next = this.pick(candidates, model, true, key);
    const target = next.runtimes.find((r) => r !== runtime && runs(next, model));
    if (!target) return null;
    const effort = row.effort !== null && this.modelEfforts(target, model, null, (p) => this.allows(key, p)).includes(row.effort) ? row.effort : null;
    const fast = FAST_RUNTIMES.includes(target) ? (row.fast ?? null) : null;
    const context = CONTEXT_RUNTIMES.includes(target) ? (row.context ?? null) : null;
    const { store } = this.deps;
    if (row.runtimeSessionId) store.ranIn(key, row.runtimeSessionId, row.profile);
    store.setSessionRuntime(key, target, next.id, false, model, effort, fast, context, null);
    store.setSessionContextBefore(key, null);
    log.info("hub", said, { session: key, from: left ?? row.profile, to: next.id, runtime: target });
    if (!quiet) {
      this.deps.moved?.(key, row);
      const prev = config.profiles.find((p) => p.id === (left ?? row.profile));
      if (billedPerUse(next) && prev !== undefined && !billedPerUse(prev)) {
        this.deps.billedFallback?.({ session: key, workspace: row.ws ?? null, runtime, profile: next });
      }
    }
    return next;
  }

  /// The profiles of other runtimes session `row` could go on on, left to the station and not kept to a set of its
  /// own: those allowed in its workspace that run its model (`takeAcross`).
  private acrossOthers(row: SessionRow): Profile[] {
    const runtime = runtimeNamed(row.runtime);
    if (!runtime || row.profilePinned || row.model === null || row.speed === "ultrafast") return [];
    const config = this.deps.config();
    const workspaceAll = config.profiles.filter((p) => p.runtimes.includes(runtime) && this.allows(row.key, p));
    if (this.poolFor(row, workspaceAll)[1] !== null) return [];
    return config.profiles.filter((p) => !p.runtimes.includes(runtime) && this.allows(row.key, p) && runs(p, row.model!));
  }

  /// When session `key`, which ran into its allowance (or its model into its own limit), is expected to run again: when
  /// its own profile is (`refillOf`), or, left to the station, the first of those it could go on on, another runtime's
  /// too (`runOn` moves it there as it wakes): one that can run it now at once, one that cannot sign in never.
  refillsAt(key: string): number {
    const row = this.deps.store.getSession(key);
    const now = this.deps.clock.currentTimeMillisUnsafe();
    if (!row) return now + SPENT_FOR_MS;
    const own = this.refillOf(row.profile, row.model, this.deps.store.lastTurn(key)?.endedAt ?? now);
    const others = [...this.others(row), ...this.acrossOthers(row)].filter((p) => signsIn(this.healthOf(p.id)));
    return Math.min(own, ...others.map((p) => (this.can(p.id, row.model) ? now : this.refillOf(p.id, row.model, now))));
  }

  /// When profile `id`, unable to run `model` now, is expected to: the last refill of its used-up windows, or, none
  /// known, when it stops being passed over (`since`: when it ran into its allowance, where that is not kept).
  private refillOf(id: string, model: string | null, since: number): number {
    const now = this.deps.clock.currentTimeMillisUnsafe();
    const quota = this.modelQuota(id, this.healthOf(id).quota, model);
    const full = windowsOf(quota).filter((w) => Number(w.usedPercent) >= 100 && typeof w.resetsAt === "number" && w.resetsAt > now);
    if (full.length > 0) return Math.max(...full.map((w) => w.resetsAt as number));
    return (this.spent.get(this.accountKey(id)) ?? this.scopeSpentAt(id, model) ?? this.modelSpentAt(id, model) ?? since) + SPENT_FOR_MS;
  }

  /// Whether session `row`, waiting for an allowance, could go on once profile `id`'s is reset: on its own account, or,
  /// left to the station, on one it could move to, another runtime's too.
  goesOnWith(row: SessionRow, id: string): boolean {
    return this.sameAccount(id, row.profile) || [...this.others(row), ...this.acrossOthers(row)].some((p) => this.sameAccount(id, p.id));
  }

  /// The reasoning levels every eligible account that has said offers for a model (a pinned account or chosen subset may
  /// offer more): automatic selection must work on every one, quota failover included. `allowed`: the profiles of the
  /// workspace asked for.
  modelEfforts(runtime: RuntimeKind, model: string | null, pinned: string | readonly string[] | null, allowed: (p: Profile) => boolean = () => true): string[] {
    const kept = typeof pinned === "string" ? new Set([pinned]) : Array.isArray(pinned) && pinned.length > 0 ? new Set(pinned) : null;
    const profiles = this.deps
      .config()
      .profiles.filter((p) => p.enabled !== false && p.runtimes.includes(runtime) && allowed(p))
      .filter((p) => kept === null || kept.has(p.id))
      .filter((p) => model === null || runs(p, model));
    // One that has reported no levels (its check not done, or failed) is not known to lack any: it does not hold back
    // those that have.
    const catalog = (p: Profile) => this.healthOf(p.id).check?.modelEfforts ?? null;
    const said = profiles.map((p) => reportedEfforts(runtime, model ?? p.model ?? null, catalog(p))).filter((levels) => levels !== null);
    return commonEfforts(said.length > 0 ? said : profiles.map((p) => availableEfforts(runtime, model ?? p.model ?? null, catalog(p))), runtime);
  }

  /// Checks a change (configure) and works out what it makes of the session: its profile(s) (and whether kept to one),
  /// its model and effort. Throws what is wrong with it, in `lang`.
  change(key: string, change: SessionChange, lang: Lang = stationLang()) {
    const { store } = this.deps;
    const t = (k: string, args?: Record<string, unknown>) => tr(lang, k, args);
    const row = store.getSession(key);
    if (!row) throw new Error(`unknown session ${key}`);
    const runtime = runtimeNamed(row.runtime);
    if (!runtime) throw new Error(`session ${key} runs an unknown runtime ${row.runtime}`);
    const name = runtimeTitle(runtime);
    const config = this.deps.config();
    const nonEmpty = (v: string | null | undefined) => (v === undefined ? undefined : v === null || v === "" ? null : v);
    const normList = change.profiles === undefined
      ? undefined
      : change.profiles === null
        ? null
        : (() => {
            const list = [...new Set(change.profiles.map((x) => x.trim()).filter((x) => x !== ""))];
            return list.length > 0 ? list : null;
          })();
    // Profiles given keep the session to them (one: pinned); null gives the choice back to the station.
    const wantedSingle = change.repick === true && (change.profile === undefined || change.profile === null) && normList === undefined
      ? (row.profilePinned || change.profile === null ? null : undefined)
      : nonEmpty(change.profile);
    const wantedProfiles: string[] | null | undefined =
      normList !== undefined ? normList : wantedSingle !== undefined ? (wantedSingle === null ? null : [wantedSingle]) : undefined;
    const newModel = nonEmpty(change.model);
    const newEffort = nonEmpty(change.effort);
    const allowed = (p: Profile) => this.allows(key, p);
    if (change.runtime !== undefined && change.runtime !== row.runtime) {
      const target = runtimeNamed(change.runtime);
      if (!target) throw new Error(`unknown runtime ${change.runtime}`);
      const model = newModel ?? null;
      const candidates = config.profiles.filter((p) => p.runtimes.includes(target) && this.allows(key, p));
      if (candidates.length === 0) throw new Error(t("station.session.noProfileHere", { runtime: runtimeTitle(target) }));
      if (model !== null && !candidates.some((p) => runs(p, model))) throw new Error(t("station.session.noProfileForModel", { model, runtime: runtimeTitle(target) }));
      const pick = (pool: Profile[]) => {
        if (target !== "codex" || change.speed !== "ultrafast") return this.pick(pool, model, true, key);
        const eligible = pool.filter((p) => this.supportsUltrafast(p, model));
        if (eligible.length === 0) throw new Error(t("station.speed.ultrafast_unavailable"));
        return this.pick(eligible, model, true, key);
      };
      let picked: Profile | undefined;
      const nextProfiles = Array.isArray(wantedProfiles) ? wantedProfiles : null;
      if (nextProfiles !== null) {
        const subset: Profile[] = [];
        for (const id of nextProfiles) {
          const found = candidates.find((p) => p.id === id);
          if (!found) throw new Error(`unknown profile ${id}`);
          if (model !== null && !runs(found, model)) throw new Error(t("station.session.modelOff", { profile: found.name, model }));
          subset.push(found);
        }
        picked = subset.length === 1 ? subset[0] : pick(subset);
      } else {
        picked = pick(candidates);
      }
      if (!picked) throw new Error(`unknown profile ${nextProfiles?.[0] ?? ""}`);
      const effort = newEffort ?? null;
      if (effort !== null) {
        const efforts = this.modelEfforts(target, model, nextProfiles, allowed);
        if (!efforts.includes(effort)) throw new Error(t("station.profile.efforts", { runtime: runtimeTitle(target), efforts: efforts.join(t("station.list.separator")) }));
      }
      if (change.fast != null && !FAST_RUNTIMES.includes(target)) throw new Error(t("station.session.fastOpenAiOnly"));
      checkContext(target, change.context, lang);
      return { row, runtime: target, model, effort, profile: picked.id, profiles: nextProfiles, pinned: nextProfiles?.length === 1, repick: false };
    }
    if (change.fast !== undefined && change.fast !== null && !FAST_RUNTIMES.includes(runtime)) throw new Error(t("station.session.fastOpenAiOnly"));
    checkContext(runtime, change.context, lang);
    if (Array.isArray(wantedProfiles)) {
      const model = newModel !== undefined ? newModel : row.model;
      for (const id of wantedProfiles) {
        const next = config.profiles.find((p) => p.id === id);
        if (!next) throw new Error(`unknown profile ${id}`);
        if (next.enabled === false) throw new Error(t("station.profile.disabled", { profile: next.name }));
        if (!next.runtimes.includes(runtime)) throw new Error(t("station.profile.cannotRun", { profile: next.name, runtime: name }));
        if (!allowed(next)) throw new Error(t("station.profile.notHere", { profile: next.name }));
        if (model !== null && !runs(next, model)) throw new Error(t("station.session.modelOff", { profile: next.name, model }));
      }
    }
    let model = newModel !== undefined ? newModel : row.model;
    // Another spelling of its model is its model.
    const remodel = model !== null && row.model !== null ? !sameModel(model, row.model) : model !== row.model;
    if (!remodel) model = row.model;
    const effort = newEffort !== undefined ? newEffort : remodel ? null : row.effort;
    // What changes is checked; what stays is as it was.
    if (typeof newModel === "string" && model !== null && !config.profiles.some((p) => p.runtimes.includes(runtime) && allowed(p) && runs(p, model!))) {
      throw new Error(t("station.session.noProfileForModel", { model, runtime: name }));
    }
    const remodelProfiles = () => {
      if (row.profilePinned || !row.profiles || row.profiles.length === 0) return null;
      const kept = row.profiles.filter((id) => {
        const p = config.profiles.find((x) => x.id === id);
        return p !== undefined && p.runtimes.includes(runtime) && allowed(p) && (model === null || runs(p, model));
      });
      return kept.length > 0 ? kept : null;
    };
    const nextProfiles: string[] | null | undefined = wantedProfiles !== undefined ? wantedProfiles : remodel ? remodelProfiles() : undefined;
    if (effort !== null && (newEffort !== undefined || wantedProfiles !== undefined || remodel)) {
      const effectiveProfiles = nextProfiles !== undefined ? nextProfiles : (row.profiles ?? (row.profilePinned ? [row.profile] : null));
      const efforts = this.modelEfforts(runtime, model, effectiveProfiles, allowed);
      if (!efforts.includes(effort)) throw new Error(t("station.profile.efforts", { runtime: name, efforts: efforts.join(t("station.list.separator")) }));
    }
    const profile = nextProfiles === undefined ? undefined : nextProfiles !== null && nextProfiles.length === 1 ? nextProfiles[0]! : null;
    const canRepick = change.repick === true && (nextProfiles === undefined ? !row.profilePinned : nextProfiles === null || nextProfiles.length > 1);
    return { row, runtime, model, effort, profile, profiles: nextProfiles, pinned: undefined, repick: canRepick };
  }
}

/// A model's name in words, as a runtime names it ("Fable") and as its id spells it (claude-fable-5-1).
const modelWords = (m: string) => m.toLowerCase().split(/[^a-z0-9]+/).filter((w) => w !== "");
const sameWords = (a: string, b: string) => modelWords(a).join(" ") === modelWords(b).join(" ");
/// A model's own window (`scoped`) that `model` runs under: its words all in the model's ("Argon" for gemini-4-argon).
const ownedBy = (w: any, model: string) => typeof w?.scope === "string" && modelWords(w.scope).every((x) => modelWords(modelKey(model)).includes(x));
