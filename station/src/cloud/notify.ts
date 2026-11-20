// What the chats' people hear about while no client of theirs runs (admin/notify.rs and the station process's
// notify.rs): noticed from the store's changes as they come, worked out by the readers
// (src/read/notices.ts), gathered over a second and posted to the control plane (still.fail cloud's
// `/v1/stations/notify`, Comma's `/v1/comma/stations/notify`: ControlPlane.notify), signed with the station's key, which
// pushes them to people's devices. Only what happens from now on is noticed. A batch that cannot be
// sent is dropped; an older cloud (404) has no pushes.
import { Clock, Effect, Exit, FiberSet, Scope } from "effect";
import { stationLang, tr } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import type { Readers } from "../read/pool.ts";
import type { Notice } from "../read/notices.ts";
import type { Store } from "../store/store.ts";
import type { Cloud } from "./state.ts";
import { liveClock } from "../ops/fibers.ts";
import { STATION_AUTHOR } from "../store/rows.ts";

/// Notices wait this long to go out together; at most this many in one post (the cloud takes no more).
const GATHER_MS = 1_000;
const MAX_BATCH = 50;
/// Minimum interval between pay-as-you-go fallback alerts for the same workspace and runtime.
export const BILLED_NOTIFY_COOLDOWN_MS = 4 * 60 * 60 * 1000;

/// Per-(workspace, runtime) cooldown gate so billed-per-use fallback alerts never spam workspace managers.
export class BilledCooldown {
  private last = new Map<string, number>();

  take(workspace: string, runtime: string, at: number): boolean {
    const key = `${workspace}\0${runtime}`;
    const prev = this.last.get(key);
    if (prev !== undefined && at - prev < BILLED_NOTIFY_COOLDOWN_MS) return false;
    this.last.set(key, at);
    return true;
  }
}

export class Notifier {
  private since: number;
  /// Each session's last turn noticed (when it ended), so one turn is noticed once.
  private ended = new Map<string, number>();
  private billedCooldown: BilledCooldown;
  private waiting: Notice[] = [];
  /// A batch is being gathered (its wait is running).
  private gathering = false;
  /// Runs an effect as a fiber of the notifier's (the wait while a batch gathers): they end at `close`.
  private run: (effect: Effect.Effect<void>) => Promise<void>;
  private scope: Scope.Closeable;
  private stop: () => void;
  private readers: Readers;
  private store: Store;
  private cloud: Cloud;
  /// Where a batch goes (tests give their own); the control plane's by default (`send`). `workspace`: a joined
  /// workspace's batch (its sessions' notices); absent, the home one's.
  post: (notices: Notice[], workspace?: string) => Promise<void>;

  /// When a login under way runs out of time (logins/module.ts, through the hub): what a notice of its card says.
  private deadline: (login: string) => number | null;
  private now: () => number;

  /// `send`: a batch to the control plane; `clock`: the clock a batch gathers on (a TestClock in tests); `deadline`:
  /// when a login of this station's under way runs out of time; `now`, the time it is told by (the hub's clock).
  constructor(store: Store, readers: Readers, cloud: Cloud, send: (notices: Notice[], workspace?: string) => Promise<void>, options: { clock?: Clock.Clock; now?: () => number; deadline?: (login: string) => number | null; billedCooldown?: BilledCooldown } = {}) {
    this.scope = Effect.runSync(Scope.make());
    const runtime = Scope.provide(FiberSet.makeRuntimePromise<never, void, never>(), this.scope);
    this.run = Effect.runSync(options.clock ? runtime.pipe(Effect.provideService(Clock.Clock, options.clock)) : runtime);
    this.since = (options.clock ?? liveClock).currentTimeMillisUnsafe();
    this.billedCooldown = options.billedCooldown ?? new BilledCooldown();
    this.store = store;
    this.readers = readers;
    this.cloud = cloud;
    this.post = send;
    this.deadline = options.deadline ?? (() => null);
    const clock = options.clock ?? liveClock;
    this.now = options.now ?? (() => clock.currentTimeMillisUnsafe());
    this.stop = store.subscribe((change) => {
      if (change.type === "session") this.sessionChanged(change.key);
      else if (change.type === "thread") this.said(change.id, change.entries);
    });
  }

  close() {
    this.stop();
    Effect.runFork(Scope.close(this.scope, Exit.void));
  }

  /// A turn that ended since the last look: its chats hear how. Looked at here first, so most changes ask nothing.
  private sessionChanged(key: string) {
    const ended = this.store.lastTurn(key)?.endedAt;
    if (typeof ended !== "number" || ended < this.since || this.ended.get(key) === ended) return;
    this.ended.set(key, ended);
    // A chat an agent leads (chat_create `for: "me"`) tells its leader how its turns end, not its people's phones: the
    // leader takes up what it says and asks (sessions/opened.ts).
    if (this.store.openerOf(key)?.led === true) return;
    this.ask("turnNotices", { key, since: this.since, ended: null, lang: stationLang() });
  }

  /// People's messages and the station's ⚠️ in its own chats.
  private said(thread: number, entries: { n: number; kind: string; authorKind: string; text: string | null; at: number }[]) {
    const worth = entries.some((e) => e.kind === "message" && e.at >= this.since && (e.authorKind === "person" || (e.authorKind === STATION_AUTHOR && (e.text ?? "").startsWith("⚠️"))));
    if (worth) this.ask("saidNotices", { thread, entries, since: this.since, lang: stationLang() });
  }

  private ask(op: string, args: unknown) {
    void this.readers.read(op, args, stationLang(), { told: true }).then(
      (text) => {
        const answer = JSON.parse(text);
        this.queue((Array.isArray(answer) ? answer : answer.notices).map((n: Notice) => this.timed(n)));
      },
      (error) => log.warn("notify", "a notice could not be made", { error: (error as Error).message }),
    );
  }

  /// What a chat asks of its person by a login's card, said with how long is left to log in (需要你登录 gh（14 分钟内）):
  /// it ends by itself, after which it has to be started again.
  private timed(n: Notice): Notice {
    if (n.kind !== "block") return n;
    let card: unknown = null;
    try {
      card = this.store.pendingCardHeader(n.thread)?.[1] ?? null;
    } catch {
      return n;
    }
    const c = card as { type?: unknown; login?: unknown; station?: unknown } | null;
    if (c?.type !== "login" || typeof c.login !== "string" || c.station !== undefined) return n;
    const ends = this.deadline(c.login);
    if (ends === null) return n;
    const minutes = Math.ceil((ends - this.now()) / 60_000);
    if (minutes <= 0) return n;
    return { ...n, text: tr(stationLang(), "station.notice.loginWithin", { text: n.text, minutes: String(minutes) }) };
  }

  /// Enqueues a manager-only push notice when sessions automatically fall back to a pay-as-you-go profile.
  /// Returns true when the notice is accepted (not suppressed by membership or the 4-hour cooldown).
  notifyBilledFallback(info: { workspace: string | null; runtime: string; runtimeTitle: string; profile: string; at: number }, options: { cooled?: boolean } = {}): boolean {
    const ws = info.workspace ?? this.cloud.home();
    if (ws === null || this.cloud.membership(ws) === null) return false;
    if (!options.cooled && !this.billedCooldown.take(ws, info.runtime, info.at)) return false;
    const title = this.cloud.membership(ws)?.name ?? this.cloud.state?.name ?? "still.fail";
    this.queue([{
      to: [],
      audience: "managers",
      kind: "billed",
      session: `billed:${info.runtime}`,
      thread: 0,
      seq: null,
      title,
      by: info.runtimeTitle,
      text: info.profile,
      at: info.at,
      ws,
    }]);
    return true;
  }

  private queue(notices: Notice[]) {
    if (notices.length === 0) return;
    this.waiting.push(...notices);
    if (this.gathering) return;
    this.gathering = true;
    void this.run(Effect.sleep(GATHER_MS).pipe(Effect.andThen(Effect.sync(() => this.gathered())))).catch(() => {});
  }

  private gathered() {
    this.gathering = false;
    const batch = this.waiting.splice(0, MAX_BATCH);
    if (this.waiting.length > 0) this.queue(this.waiting.splice(0));
    if (this.cloud.removed() || this.cloud.state === null) return;
    // Each workspace's people hear of its own chats: one post a workspace, those of a
    // workspace the station is no longer in dropped.
    const home = this.cloud.home();
    const by = new Map<string | undefined, Notice[]>();
    for (const notice of batch) {
      const ws = notice.ws ?? this.store.sessionWs(notice.session) ?? home;
      if (ws === null || this.cloud.membership(ws) === null) continue;
      const of = ws === home ? undefined : ws;
      const { ws: _ws, ...wire } = notice;
      by.set(of, [...(by.get(of) ?? []), wire]);
    }
    for (const [ws, notices] of by) {
      this.post(notices, ws).then(
        () => log.info("notify", "notices sent", { n: notices.length, ...(ws ? { workspace: ws } : {}) }),
        (error) => log.warn("notify", "notices dropped", { n: notices.length, error: (error as Error).message }),
      );
    }
  }
}
