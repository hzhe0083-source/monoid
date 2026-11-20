import { ulid } from "ulid";
import { STATIONS_PER_WORKSPACE } from "../../../client/limits.ts";
import { digest, nowSeconds, pastedSecret } from "../auth";
import { publicOrigins } from "../compat";
import { langOf, type Lang } from "../i18n.ts";
import { showsOf, type Shows } from "../noticeText";
import type { Role, WorkspaceView } from "../types";
import type { DirectoryDb, DirectoryHost } from "./db";
import { ENROLLMENT_TTL_SEC, LIMITS, MANAGERS, REVOCATION_DAYS, cleanEmoji, cleanIcon, cleanName, fail, type PushDevice, type PushRegistration } from "./types";

// ── stations, revocations, and push registrations ───────────────────────

export class DirectoryStations {
  #db: DirectoryDb;
  #host: DirectoryHost;

  constructor(db: DirectoryDb, host: DirectoryHost) {
    this.#db = db;
    this.#host = host;
  }

  /** A person no longer in a workspace: their rigs and unused rig enrollment tokens leave it with them. */
  rigsGone(workspace: string, sub: string): void {
    this.#db.run("DELETE FROM enrollments WHERE workspace = ? AND created_by = ? AND rig = 1", workspace, sub);
    for (const r of this.#db.rows("SELECT station FROM station_members WHERE workspace = ? AND rig = 1 AND enrolled_by = ?", workspace, sub)) {
      const station = r.station as string;
      const home = this.#db.memberships(station)[0]!;
      this.#db.run("DELETE FROM station_members WHERE station = ? AND workspace = ?", station, workspace);
      this.left(station, home);
    }
  }

  async createEnrollment(sub: string, workspace: string, name: string): Promise<{ token: string; expires_at: number }> {
    this.#db.role(sub, workspace, MANAGERS);
    return this.enrollment(sub, workspace, name);
  }

  /**
   * A rig's enrollment: any member adds one, which is theirs (a rig holds nothing of the workspace and asks nothing
   * of its stations; what runs on it is its person's to grant). A station is its managers' to add.
   */
  async createRigEnrollment(sub: string, workspace: string, name: string): Promise<{ token: string; expires_at: number }> {
    this.#db.role(sub, workspace);
    return this.enrollment(sub, workspace, name, true);
  }

  async enrollment(sub: string, workspace: string, name: unknown, rig = false): Promise<{ token: string; expires_at: number }> {
    const clean = cleanName(name) ?? fail(400, "invalid_name");
    if (this.#stationsFull(workspace)) fail(429, "too_many_stations");
    // (pasted after a command: never beginning with `-`, auth.ts pastedSecret)
    const token = pastedSecret();
    const expires = nowSeconds() + ENROLLMENT_TTL_SEC;
    const hash = await digest(token);
    // They may have left while the token's hash was made: leave no new rig token after #rigsGone took theirs.
    if (rig) this.#db.role(sub, workspace);
    this.#db.run("DELETE FROM enrollments WHERE expires_at <= ?", nowSeconds());
    this.#db.run("INSERT INTO enrollments (token_hash, workspace, name, created_by, expires_at, rig) VALUES (?, ?, ?, ?, ?, ?)", hash, workspace, clean, sub, expires, rig ? 1 : null);
    return { token, expires_at: expires };
  }

  #stationsFull(workspace: string): boolean {
    const stations = this.#db.one("SELECT COUNT(*) AS n FROM station_members WHERE workspace = ?", workspace)!.n as number;
    return stations >= STATIONS_PER_WORKSPACE;
  }

  /**
   * A station redeems an enrollment token. The caller has checked that the station holds the key for `station`.
   * Re-enrolling moves the station: it leaves every other workspace it is in. Joining (`join`, POST /v1/stations/join)
   * it stays in them and joins this one too; a station whose home is locked joins locked
   * workspaces only (an unlocked one's members are this cloud's word, which the home's lock took away). It pins each
   * locked workspace's lock there. `home` is the workspace it joined first, whose say goes for the machine.
   * `rig`: the machine enrolls as a rig, which a rig's token alone makes (a station's program from before rigs would
   * serve the workspace as a station under a rig's name) and no other does; a rig is in one workspace, so it never
   * joins. Its answer names its person (`rig`).
   */
  async enroll(token: string, station: string, version: string | null, join = false, locks = false, rig = false): Promise<{ workspace: string; workspace_name: string; name: string; home: string; rig?: { owner: string; owner_email: string; owner_name: string } }> {
    const hash = await digest(token);
    const row = this.#db.one("SELECT workspace, name, created_by, rig FROM enrollments WHERE token_hash = ? AND expires_at > ?", hash, nowSeconds());
    if (!row) fail(404, "enrollment_not_found");
    if ((row!.rig === 1) !== rig) fail(409, row!.rig === 1 ? "rig_enrollment" : "station_enrollment");
    if (rig && join) fail(409, "rig_enrollment");
    const workspace = row!.workspace as string;
    // A token kept by a Directory from before #rigsGone took unused tokens must not bring a departed person's rig back.
    if (rig && !this.#db.one("SELECT 1 AS x FROM members WHERE workspace = ? AND sub = ?", workspace, row!.created_by)) fail(404, "enrollment_not_found");
    const was = this.#db.memberships(station);
    // A rig stays one, a station a station, where it is: its kind changes only by removing it first.
    if (join && this.#db.one("SELECT 1 AS x FROM station_members WHERE station = ? AND rig = 1", station)) fail(409, "rig_enrollment");
    const member = was.includes(workspace);
    // Across a lock: a locked home into an unlocked workspace; or into a locked one, by a station that would not pin it.
    // A chain moved is on or off by its root's log, which this cloud never reads: into one as into a locked one; out
    // of one as the home, no refusal on a guess (the asker's own check comes first, the station's own after: it takes
    // no members of a workspace that is off while its home is on, station/src/cloud/state.ts `leftOut`).
    const homeOn = was.length > 0 && this.#host.locked(was[0]!) && !this.#host.moved(was[0]!);
    if (join && !member && was.length > 0 && (homeOn ? !this.#host.locked(workspace) : this.#host.locked(workspace) && !locks)) fail(409, "locked_workspace");
    // Several tokens may be out at once: the last free place goes to the first redeemed.
    if (!member && this.#stationsFull(workspace)) fail(429, "too_many_stations");
    const left = join ? [] : was.filter((w) => w !== workspace);
    this.#db.ctx.storage.transactionSync(() => {
      this.#db.run("DELETE FROM enrollments WHERE token_hash = ?", hash);
      this.#db.run("INSERT INTO stations (id, last_seen, version) VALUES (?, ?, ?) ON CONFLICT (id) DO UPDATE SET last_seen = excluded.last_seen, version = excluded.version", station, nowSeconds(), version);
      for (const other of left) this.#db.run("DELETE FROM station_members WHERE workspace = ? AND station = ?", other, station);
      if (join && member) this.#db.run("UPDATE station_members SET name = ? WHERE workspace = ? AND station = ?", row!.name, workspace, station);
      else {
        // Enrolled again where it is (moving), it keeps its emoji and icon there.
        this.#db.run(`INSERT INTO station_members (workspace, station, name, enrolled_at, enrolled_by, rig) VALUES (?, ?, ?, ?, ?, ?)
          ON CONFLICT (workspace, station) DO UPDATE SET name = excluded.name, enrolled_at = excluded.enrolled_at, enrolled_by = excluded.enrolled_by, rig = excluded.rig`,
          workspace, station, row!.name, nowSeconds(), row!.created_by, rig ? 1 : null);
      }
    });
    const w = this.#db.one("SELECT name FROM workspaces WHERE id = ?", workspace)!;
    this.#host.changed(workspace, true);
    for (const other of left) this.#host.changed(other, true);
    // Already connected (re-enrolled while running): it learns where it is now, before the answer when it left some.
    this.#host.sendState(station, left.length > 0);
    const home = this.#db.memberships(station)[0]!;
    const owner = rig ? this.#db.one("SELECT email, name FROM users WHERE sub = ?", row!.created_by) : undefined;
    await this.#host.delivered();
    return {
      workspace, workspace_name: w.name as string, name: row!.name as string, home,
      ...(rig ? { rig: { owner: row!.created_by as string, owner_email: (owner?.email as string | undefined) ?? "", owner_name: (owner?.name as string | undefined) ?? "" } } : {}),
    };
  }

  /** A new name, a new emoji, a new icon (null or "" takes either away), or several; what is not given stays. */
  updateStation(sub: string, workspace: string, station: string, input: { name?: unknown; emoji?: unknown; icon?: unknown }): WorkspaceView {
    if (!MANAGERS.includes(this.#db.role(sub, workspace)) && !this.#db.one("SELECT 1 AS x FROM station_members WHERE station = ? AND workspace = ? AND rig = 1 AND enrolled_by = ?", station, workspace, sub)) fail(403, "forbidden");
    const name = input.name === undefined ? undefined : cleanName(input.name) ?? fail(400, "invalid_name");
    const emoji = input.emoji === undefined ? undefined : input.emoji === null || input.emoji === "" ? null : cleanEmoji(input.emoji) ?? fail(400, "invalid_emoji");
    const icon = input.icon === undefined ? undefined : input.icon === null || input.icon === "" ? null : cleanIcon(input.icon, publicOrigins(this.#db.env)) ?? fail(400, "invalid_icon");
    if (name === undefined && emoji === undefined && icon === undefined) fail(400, "invalid_name");
    if (name !== undefined) this.#db.run("UPDATE station_members SET name = ? WHERE station = ? AND workspace = ?", name, station, workspace);
    if (emoji !== undefined) this.#db.run("UPDATE station_members SET emoji = ? WHERE station = ? AND workspace = ?", emoji, station, workspace);
    if (icon !== undefined) this.#db.run("UPDATE station_members SET icon = ? WHERE station = ? AND workspace = ?", icon, station, workspace);
    this.#host.changed(workspace, false);
    if (name !== undefined) this.#host.sendState(station);
    return this.#host.view(sub, workspace);
  }

  /**
   * What a station is here: a whole one (`full`), or one that only runs tasks (`tasks`: a rig). It stays whose it is,
   * the member who added it (`enrolled_by`), and only they change its mode, either way (the user, 2026-11-10); whole
   * again only where they manage the workspace, as a member adds no whole station. One no member added (its adder
   * left, or the operator enrolled it) a workspace owner may make one that runs tasks, and it is theirs then. The
   * machine itself becomes it only by what that person's device asked of it (tasks) or they signed (full), which the
   * app brings it first: this lists it so. A station in several workspaces stays whole (a rig is in one), and a
   * workspace keeps one whole station at least.
   */
  async setStationMode(sub: string, workspace: string, station: string, mode: unknown): Promise<WorkspaceView> {
    const role = this.#db.role(sub, workspace);
    if (mode !== "full" && mode !== "tasks") fail(400, "invalid_name");
    const row = this.#db.one("SELECT rig, enrolled_by FROM station_members WHERE station = ? AND workspace = ?", station, workspace) ?? fail(404, "station_not_found");
    if ((row.rig === 1) !== (mode === "tasks")) {
      const mine = row.enrolled_by === sub;
      if (mode === "tasks") {
        const nobodys = !mine && !this.#db.one("SELECT 1 AS x FROM members WHERE workspace = ? AND sub = ?", workspace, row.enrolled_by ?? "");
        if (!mine && !(nobodys && role === "owner")) fail(403, "forbidden");
        if (this.#db.memberships(station).length !== 1) fail(409, "station_in_others");
        if (!this.#db.one("SELECT 1 AS x FROM station_members WHERE workspace = ? AND rig IS NULL AND station != ?", workspace, station)) fail(409, "last_station");
        // Theirs already, or (no member's) theirs now.
        this.#db.run("UPDATE station_members SET rig = 1, enrolled_by = ? WHERE station = ? AND workspace = ?", sub, station, workspace);
      } else {
        if (!mine || !MANAGERS.includes(role)) fail(403, "forbidden");
        this.#db.run("UPDATE station_members SET rig = NULL WHERE station = ? AND workspace = ?", station, workspace);
      }
      this.#host.changed(workspace, true);
      this.#host.sendState(station, true);
      await this.#host.delivered();
    }
    return this.#host.view(sub, workspace);
  }

  /** Takes a station out of this workspace only; it stays in the others it is in. A rig: its person may too. */
  async removeStation(sub: string, workspace: string, station: string): Promise<void> {
    const mine = this.#db.role(sub, workspace);
    const row = this.#db.one("SELECT rig, enrolled_by FROM station_members WHERE station = ? AND workspace = ?", station, workspace);
    if (!MANAGERS.includes(mine) && !(row?.rig === 1 && row.enrolled_by === sub)) fail(403, "forbidden");
    const home = this.#db.memberships(station)[0];
    if (!row) return;
    this.#db.run("DELETE FROM station_members WHERE station = ? AND workspace = ?", station, workspace);
    this.#host.changed(workspace, true);
    this.left(station, home!);
    await this.#host.delivered();
  }

  /**
   * A station has left a workspace (its row gone already; `home` its home before): in none now, it is let go (4004, as
   * when a station was in one); else it hears where it is now, and, its home gone, the workspace taking over (whose
   * views now name it home) is changed too.
   */
  left(station: string, home: string): void {
    const now = this.#db.memberships(station);
    if (now.length === 0) {
      this.#db.run("DELETE FROM stations WHERE id = ?", station);
      this.#host.disconnect(station);
      return;
    }
    if (now[0] !== home) this.#host.changed(now[0]!, true);
    // Until it hears it, it takes that workspace's members still.
    this.#host.sendState(station, true);
  }

  /** Whether a station is enrolled (in some workspace). */
  isStation(station: string): boolean {
    return this.#db.one("SELECT 1 AS found FROM station_members WHERE station = ?", station) !== undefined;
  }

  // ── what a station's own object asks (station.ts) ──────────────────────

  /**
   * A station's presence socket opens on its object: when it was here noted, it is live, and what to tell it (`frame`,
   * null for one in no workspace, which is turned away).
   */
  stationConnected(station: string, version: string | null): { frame: string | null; gen: number } {
    if (this.#db.memberships(station).length === 0) return { frame: null, gen: 0 };
    this.#db.run("UPDATE stations SET last_seen = ?, version = COALESCE(?, version) WHERE id = ?", nowSeconds(), version, station);
    return { frame: this.#host.frame(station), gen: this.#host.opened("station", station) };
  }

  /** What a station is told as it changed: its state frame, null in no workspace now (it is let go). */
  stationState(station: string): string | null {
    return this.#host.frame(station);
  }

  /** A station's presence socket, opened as `gen`, closed or went silent on its object: when it was here. */
  stationLeft(station: string, gen: number): void {
    this.#db.run("UPDATE stations SET last_seen = ? WHERE id = ?", nowSeconds(), station);
    this.#db.run("DELETE FROM live WHERE kind = 'station' AND key = ? AND gen = ?", station, gen);
  }

  /** What a station said on its socket (on its object), and the frames that answer it. */
  async stationSaid(station: string, message: string): Promise<string[]> {
    const out: string[] = [];
    await this.#host.said(station, message, (frame) => out.push(frame));
    return out;
  }

  /** A mstill.fail's role, which its credential names (grants.ts). */
  memberRole(sub: string, workspace: string): Role {
    return this.#db.role(sub, workspace);
  }

  // ── revocations ─────────────────────────────────────────────────────────
  // A mstill.fail's credential lasts 30 days and stations check it offline, so what takes one back is told to them: every
  // credential of an account (`sub`) or of a sign-in session (`sid`) issued up to `at` is refused from then on. Each
  // station hears it at once if connected, and all of its workspaces' (of the last 31 days) when it connects.

  /** Takes back an account's credentials in a workspace, or one session's. */
  revoke(workspace: string, kind: "sub" | "sid", id: string): void {
    const at = nowSeconds();
    this.#db.run("INSERT INTO revocations (workspace, kind, id, at) VALUES (?, ?, ?, ?) ON CONFLICT (workspace, kind, id) DO UPDATE SET at = excluded.at", workspace, kind, id, at);
    this.#db.run("DELETE FROM revocations WHERE at < ?", at - REVOCATION_DAYS * 86400);
    // Which workspace's: a station in several takes it back there alone (one from before them reads no such field).
    const frame = JSON.stringify({ type: "revoke", kind, id, at, workspace });
    for (const station of this.#db.stationsIn(workspace)) {
      this.#host.deliver("station", station, { frames: [frame] }, { urgent: true });
      for (const ws of this.#host.presence(station)) {
        try {
          ws.send(frame);
        } catch {
          // Closing already: it hears all of them when it connects again.
        }
      }
    }
  }

  /** Sessions signed out (all of an account's with none named): their credentials go, in every workspace of the account. */
  async revokeSessions(sub: string, sids: string[] | null): Promise<void> {
    for (const ws of this.#db.ctx.getWebSockets(`sub:${sub}`)) {
      const { sid } = ws.deserializeAttachment() as { sid?: string };
      if (ws.readyState === WebSocket.OPEN && (sids === null || sid === undefined || sids.includes(sid))) ws.close(1008, "session ended");
    }
    if (sids === null) this.#db.run("DELETE FROM push WHERE sub = ?", sub);
    else for (const sid of sids) this.#db.run("DELETE FROM push WHERE sub = ? AND sid = ?", sub, sid);
    for (const row of this.#db.rows("SELECT workspace FROM members WHERE sub = ?", sub)) {
      const workspace = row.workspace as string;
      if (sids === null) this.revoke(workspace, "sub", sub);
      else for (const sid of sids) this.revoke(workspace, "sid", sid);
    }
    await this.#host.delivered();
  }

  // ── push registrations ──────────────────────────
  // A device's push subscription (Web Push) or token (FCM, APNs) is registered with each account signed in on it, one row
  // each, which belongs to the sign-in session that registered it last; signing that session out takes it
  // (revokeSessions).

  /** Registers a device's push subscription or token to an account's session (moving it there from the account's other). */
  registerPush(sub: string, sid: string, device: PushDevice, lang: Lang = "zh", shows: Shows | null = null): void {
    const [column, value] = device.kind === "web" ? ["endpoint", device.endpoint] : ["token", device.token];
    this.#db.run(`DELETE FROM push WHERE sub = ? AND ${column} = ?`, sub, value);
    const said = shows ? JSON.stringify(shows) : null;
    if (device.kind === "web") {
      this.#db.run("INSERT INTO push (id, sub, sid, kind, endpoint, p256dh, auth, created, lang, shows) VALUES (?, ?, ?, 'web', ?, ?, ?, ?, ?, ?)", ulid(), sub, sid, device.endpoint, device.p256dh, device.auth, nowSeconds(), lang, said);
    } else if (device.kind === "apns") {
      this.#db.run("INSERT INTO push (id, sub, sid, kind, token, sandbox, created, lang, shows) VALUES (?, ?, ?, 'apns', ?, ?, ?, ?, ?)", ulid(), sub, sid, device.token, device.sandbox ? 1 : 0, nowSeconds(), lang, said);
    } else {
      this.#db.run("INSERT INTO push (id, sub, sid, kind, token, created, lang, shows) VALUES (?, ?, ?, 'fcm', ?, ?, ?, ?)", ulid(), sub, sid, device.token, nowSeconds(), lang, said);
    }
    // An account's oldest go past a few dozen devices.
    this.#db.run("DELETE FROM push WHERE sub = ? AND id NOT IN (SELECT id FROM push WHERE sub = ? ORDER BY id DESC LIMIT ?)", sub, sub, LIMITS.pushPerUser);
  }

  /** Takes a device's registration off an account (another account's is left alone). */
  unregisterPush(sub: string, device: { endpoint: string } | { token: string }): void {
    if ("endpoint" in device) this.#db.run("DELETE FROM push WHERE sub = ? AND endpoint = ?", sub, device.endpoint);
    else this.#db.run("DELETE FROM push WHERE sub = ? AND token = ?", sub, device.token);
  }

  /** The credential that took each of these tokens (push.ts), kept with their registrations. */
  pushApps(took: { token: string; app: string }[]): void {
    for (const { token, app } of took) this.#db.run("UPDATE push SET app = ? WHERE token = ?", app, token);
  }

  /** Devices whose push service said they are gone: their registrations with every account. */
  dropPush(devices: PushDevice[]): void {
    for (const device of devices) {
      if (device.kind === "web") this.#db.run("DELETE FROM push WHERE endpoint = ?", device.endpoint);
      else this.#db.run("DELETE FROM push WHERE token = ?", device.token);
    }
  }

  /**
   * Where a station's notices go: the workspace they are of (`wanted`, else the station's home), and for each email
   * (lowercased) the registrations of the workspace's members signed in with it. When `includeManagers` is true, also
   * returns push registrations of workspace owners and admins. Null for a station not in it.
   */
  pushTargets(station: string, emails: string[], wanted: string | null = null, includeManagers = false): { workspace: string; devices: Record<string, PushRegistration[]>; managers?: PushRegistration[] } | null {
    const memberships = this.#db.memberships(station);
    const workspace = wanted ?? memberships[0];
    if (!workspace || !memberships.includes(workspace)) return null;
    const registration = (r: Record<string, unknown>): PushRegistration => {
      const lang = langOf(r.lang as string | null);
      const shows = typeof r.shows === "string" ? showsOf(JSON.parse(r.shows) as Record<string, unknown>) : null;
      const id = r.id as string;
      if (r.kind === "web") return { id, lang, shows, kind: "web", endpoint: r.endpoint as string, p256dh: r.p256dh as string, auth: r.auth as string };
      const app = typeof r.app === "string" ? { app: r.app } : {};
      if (r.kind === "apns") return { id, lang, shows, kind: "apns", token: r.token as string, sandbox: r.sandbox === 1, ...app };
      return { id, lang, shows, kind: "fcm", token: r.token as string, ...app };
    };
    const devices: Record<string, PushRegistration[]> = {};
    for (const email of new Set(emails.map((e) => e.toLowerCase()))) {
      devices[email] = this.#db.rows(
        `SELECT p.id, p.kind, p.endpoint, p.p256dh, p.auth, p.token, p.sandbox, p.lang, p.shows, p.app FROM push p JOIN users u ON u.sub = p.sub JOIN members m ON m.sub = p.sub AND m.workspace = ?
         WHERE lower(u.email) = ? ORDER BY p.id LIMIT ?`,
        workspace, email, LIMITS.pushPerUser,
      ).map(registration);
    }
    const managers = includeManagers
      ? this.#db.rows(
          `SELECT p.id, p.kind, p.endpoint, p.p256dh, p.auth, p.token, p.sandbox, p.lang, p.shows, p.app FROM push p JOIN members m ON m.sub = p.sub AND m.workspace = ?
           WHERE m.role IN ('owner', 'admin') ORDER BY p.id LIMIT ?`,
          workspace, 200,
        ).map(registration)
      : undefined;
    return { workspace, devices, ...(includeManagers ? { managers } : {}) };
  }
}
