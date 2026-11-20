// Who belongs where: users, workspaces, memberships, invitations and
// stations, in one SQLite-backed object so every change is a single
// transaction. Callers have already verified the account's access token;
// methods here check what that account may do in a workspace.
//
// The sockets that make this live are not here: each device's `/v1/events` socket is on its account's object
// (account.ts), each station's presence socket on the station's own (station.ts). What a change affects is told to
// those objects after its transaction (directory/sockets.ts: each account the events it gets, each station that its
// state changed, which it then reads here), at least once (the outbox). What scales with devices, stations and requests
// stays off this object; what scales with changes to who belongs where is here. Whether a station is up is not decided
// here: each device finds it out, reaching the station over the mesh.
//
// Sockets held here are those of before (`sub:<account>`, `station:<id>`), and, with DIRECTORY_SOCKETS "primary",
// those opened while the cloud is rolled back to them (`sockets`): told as they were, beside the objects.
import { DurableObject } from "cloudflare:workers";
import { nowSeconds, type Identity } from "./auth";
import type { Part } from "./changelog";
import type { Env } from "./env";
import type { FeedbackInput } from "./feedback";
import { setCloud, type Lang } from "./i18n.ts";
import { MeshRelayEvents } from "./mesh-relay-events";
import type { MeshRelay } from "./mesh-relay-registry";
import type { Shows } from "./noticeText";
import type { RelayListed, RelayTokenInput } from "./relay-registry";
import type { Listed, Relays, relays } from "./relays";
import type { AccountEvent, AdminAuditEntry, AdminFeedback, AdminPending, AdminUser, AdminWorkspace, DeviceView, FeedbackStatus, InviteCodeView, LockHead, LockRequestView, MeView, PendingInvitation, Role, StationEvent, WorkspaceFeedback, WorkspaceSummary, WorkspaceView } from "./types";
import { DirectoryAdmin } from "./directory/admin";
import { DirectoryDb, type DirectoryHost } from "./directory/db";
import { DirectoryFeedback } from "./directory/feedback";
import { DirectoryLocks } from "./directory/locks";
import { DirectoryMembers } from "./directory/members";
import { DirectoryRelays } from "./directory/relays";
import { initSchema, migrateFreePlan, migrateStationMembers } from "./directory/schema";
import { DirectorySockets } from "./directory/sockets";
import { DirectoryStations } from "./directory/stations";
import { FAMILIES, UNCOUNTED, sockets, type AddedMail, type Delivery, type DirectoryLoad, type PushDevice, type PushRegistration, type Row } from "./directory/types";
import { DirectoryWorkspaces } from "./directory/workspaces";

export {
  ADDED_MAIL_EVERY_SEC, CLOSE, DirectoryError, ENROLLMENT_TTL_SEC, EVENTS_PROTOCOLS, INVITATION_TTL_SEC,
  LIMITS_MAX, LOCK_REQUEST_TTL_SEC, PING_SEC, PLANS, ROLES, SILENT_MS, sockets,
  type AddedMail, type Delivery, type DirectoryLoad, type Plan, type PushDevice, type PushRegistration, type Role,
} from "./directory/types";

export class Directory extends DurableObject<Env> {
  /** Workspaces whose kept chain was checked while this object lives (directory/locks.ts). */
  protected readonly lockSeen = new Set<string>();

  #db: DirectoryDb;
  #meshEvents = new MeshRelayEvents();
  #locks: DirectoryLocks;
  #relays: DirectoryRelays;
  #stations: DirectoryStations;
  #sockets: DirectorySockets;
  #workspaces: DirectoryWorkspaces;
  #members: DirectoryMembers;
  #admin: DirectoryAdmin;
  #feedback: DirectoryFeedback;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    // (its pushes' words name its product)
    setCloud(env.PUBLIC_ORIGIN);
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
    this.#db = new DirectoryDb(ctx, env);
    const host: DirectoryHost = {
      tell: (subs, ...events) => this.#sockets.tell(subs, ...events),
      tellAll: (event, station) => this.tellAll(event, station),
      tellStations: (event) => this.tellStations(event),
      deliver: (kind, key, body, how) => this.#sockets.deliver(kind, key, body, how),
      delivered: () => this.#sockets.delivered(),
      send: (kind, key, body) => this.send(kind, key, body),
      opened: (kind, key) => this.#sockets.opened(kind, key),
      presence: (station) => this.#sockets.presence(station),
      sendState: (station, urgent) => this.#sockets.sendState(station, urgent),
      disconnect: (station) => this.#sockets.disconnect(station),
      frame: (station) => this.#sockets.frame(station),
      said: (station, message, send) => this.#sockets.said(station, message, send),
      adminChanged: (...lists) => this.#admin.adminChanged(...lists),
      adminSubs: () => this.#admin.adminSubs(),
      betaTold: (sub) => this.#admin.betaTold(sub),
      setBeta: (sub, on) => this.setBeta(sub, on),
      setMayCreate: (sub, on) => this.setMayCreate(sub, on),
      inviteCodes: () => this.inviteCodes(),
      keepCounts: () => this.#admin.keepCounts(),
      changed: (workspace, list, also, only) => this.#workspaces.changed(workspace, list, also, only),
      view: (sub, id) => this.#workspaces.view(sub, id),
      removeWorkspace: (id) => this.#workspaces.remove(id),
      standard: (sub) => this.#workspaces.standard(sub),
      memberCap: (workspace) => this.#workspaces.memberCap(workspace),
      seats: (workspace, invited) => this.#workspaces.seats(workspace, invited),
      addEmails: (by, workspace, role, wanted) => this.#members.addEmails(by, workspace, role, wanted),
      toMail: (by, workspace, joined, added, already, reportsSent) => this.#members.toMail(by, workspace, joined, added, already, reportsSent),
      forgetMailRetry: (workspace, email) => this.#members.forgetMailRetry(workspace, email),
      enrollment: (sub, workspace, name, rig) => this.#stations.enrollment(sub, workspace, name, rig),
      left: (station, home) => this.#stations.left(station, home),
      rigsGone: (workspace, sub) => this.#stations.rigsGone(workspace, sub),
      isStation: (station) => this.isStation(station),
      revoke: (workspace, kind, id) => this.#stations.revoke(workspace, kind, id),
      meshRelays: () => this.meshRelays(),
      lockHead: (workspace) => this.#locks.lockHead(workspace),
      locked: (workspace) => this.#locks.locked(workspace),
      moved: (workspace) => this.#locks.moved(workspace),
      lockRequestCount: (workspace, sub, role) => this.#locks.lockRequestCount(workspace, sub, role),
      lockTurnedOff: (workspace, genesis, after) => this.#locks.lockTurnedOff(workspace, genesis, after),
      lockAfter: (workspace, after) => this.#locks.lockAfter(workspace, after),
      appendLockInternal: (workspace, raw, fork) => this.#locks.appendLockInternal(workspace, raw, fork),
      resetFixesMarked: () => this.#feedback.resetFixesMarked(),
    };
    this.#locks = new DirectoryLocks(this.#db, host, this.lockSeen);
    this.#relays = new DirectoryRelays(this.#db, host, this.#meshEvents);
    this.#stations = new DirectoryStations(this.#db, host);
    this.#sockets = new DirectorySockets(this.#db, host, this.#meshEvents);
    this.#workspaces = new DirectoryWorkspaces(this.#db, host);
    this.#members = new DirectoryMembers(this.#db, host);
    this.#admin = new DirectoryAdmin(this.#db, host, () => counted.get(this));
    this.#feedback = new DirectoryFeedback(this.#db, host);

    initSchema(this.#db, { freePlan: () => this.migrateFreePlan(), stationMembers: () => this.migrateStationMembers() });
    if (sockets.where(env) === "objects") this.handOff();
    // What deliveries a restart cut short still owe.
    if (this.#db.one("SELECT 1 AS x FROM outbox LIMIT 1")) void ctx.blockConcurrencyWhile(() => this.#sockets.arm());
  }

  // ── protected hooks (used by migrations & tests) ────────────────────────

  protected handOff(): void {
    this.#sockets.handOff();
  }

  protected migrateStationMembers(): void {
    migrateStationMembers(this.#db);
  }

  protected migrateFreePlan(): void {
    migrateFreePlan(this.#db);
  }

  /** One delivery to an object (a test makes it fail). */
  protected send(kind: "account" | "station", key: string, body: Delivery): Promise<{ live: boolean }> {
    return kind === "account" ? this.env.ACCOUNTS.getByName(key).deliver(key, body) : this.env.STATIONS.getByName(key).deliver(key, body);
  }

  /** Every delivery under way has got there or failed (the tests' barrier, instead of waiting a while). */
  protected settled(): Promise<void> {
    return this.#sockets.settled();
  }

  /** Drops station sockets silent at `now`; says whether any station is still connected. */
  protected sweep(now: number): boolean {
    return this.#sockets.sweep(now);
  }

  // ── notifications, sockets, and presence ────────────────────────────────

  seen(sub: string): number {
    return this.#sockets.seen(sub);
  }

  closed(sub: string, gen: number): void {
    this.#sockets.closed(sub, gen);
  }

  tellAll(event: AccountEvent, station: StationEvent | null): void {
    this.#sockets.tellAll(event, station);
  }

  tellStations(event: StationEvent): void {
    this.#sockets.tellStations(event);
  }

  modelsMade(etag: string): Promise<void> {
    return this.#sockets.modelsMade(etag);
  }

  tellAdmins(event: AccountEvent): void {
    this.#admin.tellAdmins(event);
  }

  fetch(request: Request): Promise<Response> {
    return this.#sockets.fetch(request);
  }

  webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    return this.#sockets.webSocketMessage(ws, message);
  }

  webSocketClose(ws: WebSocket, code: number): Promise<void> {
    return this.#sockets.webSocketClose(ws, code);
  }

  webSocketError(ws: WebSocket): Promise<void> {
    return this.#sockets.webSocketError(ws);
  }

  alarm(): Promise<void> {
    return this.#sockets.alarm((now) => this.sweep(now));
  }

  // ── accounts and workspaces ─────────────────────────────────────────────

  accountFor(sub: string, email: string): { sub: string; name: string; picture: string } | null {
    return this.#workspaces.accountFor(sub, email);
  }

  upsertUser(identity: Identity): void {
    this.#workspaces.upsertUser(identity);
  }

  setOwnPicture(sub: string, picture: unknown): { picture: string } {
    return this.#workspaces.setOwnPicture(sub, picture);
  }

  openToSignIn(workspace: string, open: boolean): void {
    this.#workspaces.openToSignIn(workspace, open);
  }

  joinBySignIn(email: string, role: Role | null = null): Promise<void> {
    return this.#workspaces.joinBySignIn(email, role);
  }

  me(sub: string): { user: MeView | null; workspaces: WorkspaceSummary[] } & ReturnType<typeof relays> {
    return this.#workspaces.me(sub);
  }

  createWorkspace(sub: string, name: string, admin: boolean, code: unknown): WorkspaceView {
    return this.#workspaces.createWorkspace(sub, name, admin, code);
  }

  workspace(sub: string, id: string): WorkspaceView {
    return this.#workspaces.workspace(sub, id);
  }

  setRelays(sub: string, id: string, input: unknown): WorkspaceView {
    return this.#workspaces.setRelays(sub, id, input);
  }

  setWay(sub: string, id: string, way: unknown, on: unknown): WorkspaceView {
    return this.#workspaces.setWay(sub, id, way, on);
  }

  manages(sub: string, id: string): void {
    this.#workspaces.manages(sub, id);
  }

  updateWorkspace(sub: string, id: string, input: { name?: unknown; emoji?: unknown; icon?: unknown }): WorkspaceView {
    return this.#workspaces.updateWorkspace(sub, id, input);
  }

  deleteWorkspace(sub: string, id: string): Promise<void> {
    return this.#workspaces.deleteWorkspace(sub, id);
  }

  // ── members, invitations, and roles ─────────────────────────────────────

  addMembers(sub: string, workspace: string, role: Role, emails: unknown, reportsSent = false): { joined: string[]; added: string[]; already: string[]; view: WorkspaceView; mail: AddedMail } {
    return this.#members.addMembers(sub, workspace, role, emails, reportsSent);
  }

  mailFailed(workspace: string, emails: string[], sent: string[] = []): void {
    this.#members.mailFailed(workspace, emails, sent);
  }

  removeAdded(sub: string, workspace: string, email: string): WorkspaceView {
    return this.#members.removeAdded(sub, workspace, email);
  }

  invite(sub: string, workspace: string, role: Role, email: string | null): Promise<{ token: string; id: string; expires_at: number }> {
    return this.#members.invite(sub, workspace, role, email);
  }

  previewInvitation(token: string): Promise<{ workspace: string; name: string; role: Role; inviter: string; email: string | null }> {
    return this.#members.previewInvitation(token);
  }

  acceptInvitation(sub: string, email: string, token: string): Promise<WorkspaceView> {
    return this.#members.acceptInvitation(sub, email, token);
  }

  invitationsFor(email: string): PendingInvitation[] {
    return this.#members.invitationsFor(email);
  }

  acceptById(sub: string, email: string, id: string): WorkspaceView {
    return this.#members.acceptById(sub, email, id);
  }

  declineById(email: string, id: string): void {
    this.#members.declineById(email, id);
  }

  revokeInvitation(sub: string, workspace: string, id: string): void {
    this.#members.revokeInvitation(sub, workspace, id);
  }

  setRole(sub: string, workspace: string, target: string, role: Role): Promise<WorkspaceView> {
    return this.#members.setRole(sub, workspace, target, role);
  }

  removeMember(sub: string, workspace: string, target: string): Promise<void> {
    return this.#members.removeMember(sub, workspace, target);
  }

  deleteAccount(sub: string): Promise<void> {
    return this.#members.deleteAccount(sub);
  }

  // ── workspace locks ─────────────────────────────────────────────────────

  lock(sub: string, workspace: string, after: number): { head: LockHead | null; entries: unknown[] } {
    return this.#locks.lock(sub, workspace, after);
  }

  appendLock(sub: string, workspace: string, entries: unknown, keep = false): Promise<{ head: LockHead | null }> {
    return this.#locks.appendLock(sub, workspace, entries, keep);
  }

  clearLock(sub: string, workspace: string): void {
    this.#locks.clearLock(sub, workspace);
  }

  recordDevice(sub: string, workspace: string, device: string, said: { base?: string; kind?: string; label?: string }): ReturnType<typeof relays> {
    return this.#locks.recordDevice(sub, workspace, device, said);
  }

  devices(sub: string, workspace: string): { devices: DeviceView[] } {
    return this.#locks.devices(sub, workspace);
  }

  requestLock(sub: string, workspace: string, input: Record<string, unknown>): Promise<LockRequestView> {
    return this.#locks.requestLock(sub, workspace, input);
  }

  lockRequests(sub: string, workspace: string): Promise<{ requests: LockRequestView[] }> {
    return this.#locks.lockRequests(sub, workspace);
  }

  dropLockRequest(sub: string, workspace: string, base: string): void {
    this.#locks.dropLockRequest(sub, workspace, base);
  }

  // ── stations, revocations, and push ─────────────────────────────────────

  createEnrollment(sub: string, workspace: string, name: string): Promise<{ token: string; expires_at: number }> {
    return this.#stations.createEnrollment(sub, workspace, name);
  }

  createRigEnrollment(sub: string, workspace: string, name: string): Promise<{ token: string; expires_at: number }> {
    return this.#stations.createRigEnrollment(sub, workspace, name);
  }

  enroll(token: string, station: string, version: string | null, join = false, locks = false, rig = false): Promise<{ workspace: string; workspace_name: string; name: string; home: string; rig?: { owner: string; owner_email: string; owner_name: string } }> {
    return this.#stations.enroll(token, station, version, join, locks, rig);
  }

  updateStation(sub: string, workspace: string, station: string, input: { name?: unknown; emoji?: unknown; icon?: unknown }): WorkspaceView {
    return this.#stations.updateStation(sub, workspace, station, input);
  }

  setStationMode(sub: string, workspace: string, station: string, mode: unknown): Promise<WorkspaceView> {
    return this.#stations.setStationMode(sub, workspace, station, mode);
  }

  removeStation(sub: string, workspace: string, station: string): Promise<void> {
    return this.#stations.removeStation(sub, workspace, station);
  }

  isStation(station: string): boolean {
    return this.#stations.isStation(station);
  }

  stationConnected(station: string, version: string | null): { frame: string | null; gen: number } {
    return this.#stations.stationConnected(station, version);
  }

  stationState(station: string): string | null {
    return this.#stations.stationState(station);
  }

  stationLeft(station: string, gen: number): void {
    this.#stations.stationLeft(station, gen);
  }

  stationSaid(station: string, message: string): Promise<string[]> {
    return this.#stations.stationSaid(station, message);
  }

  memberRole(sub: string, workspace: string): Role {
    return this.#stations.memberRole(sub, workspace);
  }

  revokeSessions(sub: string, sids: string[] | null): Promise<void> {
    return this.#stations.revokeSessions(sub, sids);
  }

  registerPush(sub: string, sid: string, device: PushDevice, lang: Lang = "zh", shows: Shows | null = null): void {
    this.#stations.registerPush(sub, sid, device, lang, shows);
  }

  unregisterPush(sub: string, device: { endpoint: string } | { token: string }): void {
    this.#stations.unregisterPush(sub, device);
  }

  pushApps(took: { token: string; app: string }[]): void {
    this.#stations.pushApps(took);
  }

  dropPush(devices: PushDevice[]): void {
    this.#stations.dropPush(devices);
  }

  pushTargets(station: string, emails: string[], wanted: string | null = null, includeManagers = false): { workspace: string; devices: Record<string, PushRegistration[]>; managers?: PushRegistration[] } | null {
    return this.#stations.pushTargets(station, emails, wanted, includeManagers);
  }

  // ── relays ──────────────────────────────────────────────────────────────

  meshRelays(): MeshRelay[] {
    return this.#relays.meshRelays();
  }

  meshRelayRegister(body: unknown, signature: unknown, enroll: boolean): Promise<MeshRelay> {
    return this.#relays.meshRelayRegister(body, signature, enroll);
  }

  meshRelayRemove(node: unknown): void {
    this.#relays.meshRelayRemove(node);
  }

  relaysNow(): Relays {
    return this.#relays.relaysNow();
  }

  relayList(): { own: string; relays: RelayListed[]; tokens: { name: string; url: string | null; target: string | null; expires_at: number }[] } {
    return this.#relays.relayList();
  }

  relayTokenRevoke(id: unknown): { revoked: true } {
    return this.#relays.relayTokenRevoke(id);
  }

  relayPut(by: string, input: RelayTokenInput): Listed {
    return this.#relays.relayPut(by, input);
  }

  relayRemove(url: unknown): void {
    this.#relays.relayRemove(url);
  }

  relayToken(by: string, input: RelayTokenInput): Promise<{ token: string; name: string; url: string | null; expires_at: number }> {
    return this.#relays.relayToken(by, input);
  }

  relayEnrolled(token: unknown, said: unknown): Promise<{ url: string; name: string; secret: string }> {
    return this.#relays.relayEnrolled(token, said);
  }

  relayHeard(secretHash: string | null, named: string, from: string | null): string {
    return this.#relays.relayHeard(secretHash, named, from);
  }

  // ── admin, operators, audit, and move ───────────────────────────────────

  noteOperator(sub: string, email: string): void {
    this.#admin.noteOperator(sub, email);
  }

  isAdminAccount(sub: string): boolean {
    return this.#admin.isAdminAccount(sub);
  }

  moveExport(): Record<string, Row[]> {
    return this.#admin.moveExport();
  }

  moveImport(tables: Record<string, Row[]>): Record<string, number> {
    return this.#admin.moveImport(tables);
  }

  moveAccounts(): string[] {
    return this.#admin.moveAccounts();
  }

  recordAudit(actor: string, action: string, target = "", detail = ""): void {
    this.#admin.recordAudit(actor, action, target, detail);
  }

  auditName(ref: string): string {
    return this.#admin.auditName(ref);
  }

  adminAudit(): AdminAuditEntry[] {
    return this.#admin.adminAudit();
  }

  adminUsers(): AdminUser[] {
    return this.#admin.adminUsers();
  }

  setMayCreate(sub: string, on: boolean): { sub: string; may_create: boolean } {
    return this.#admin.setMayCreate(sub, on);
  }

  adminPending(): AdminPending[] {
    return this.#admin.adminPending();
  }

  setPending(by: string, email: unknown, beta: boolean | null | undefined, mayCreate: boolean | null | undefined): { email: string; sub: string | null } {
    return this.#admin.setPending(by, email, beta, mayCreate);
  }

  removePending(email: unknown): { ok: true } {
    return this.#admin.removePending(email);
  }

  setBlocked(sub: string, on: boolean): void {
    this.#admin.setBlocked(sub, on);
  }

  setBeta(sub: string, on: boolean): { sub: string; beta: boolean } {
    return this.#admin.setBeta(sub, on);
  }

  isBeta(sub: string): boolean {
    return this.#admin.isBeta(sub);
  }

  adminDeleteWorkspace(id: string): Promise<void> {
    return this.#admin.adminDeleteWorkspace(id);
  }

  adminCreateWorkspace(by: string, input: { name?: unknown; owners?: unknown; members?: unknown; stations?: unknown }): { id: string; joined: string[]; added: string[] } {
    return this.#admin.adminCreateWorkspace(by, input);
  }

  adminSetLimits(workspace: string, input: { members?: unknown; stations?: unknown; reset?: unknown }): { members: number; stations: number; reset?: true } {
    return this.#admin.adminSetLimits(workspace, input);
  }

  adminEnrollment(by: string, workspace: string, name: unknown): Promise<{ token: string; expires_at: number }> {
    return this.#admin.adminEnrollment(by, workspace, name);
  }

  adminAddOwners(by: string, workspace: string, emails: unknown): { joined: string[]; added: string[]; already: string[]; mail: AddedMail } {
    return this.#admin.adminAddOwners(by, workspace, emails);
  }

  adminRemoveAdded(workspace: string, email: unknown): { ok: true } {
    return this.#admin.adminRemoveAdded(workspace, email);
  }

  adminWorkspaces(): AdminWorkspace[] {
    return this.#admin.adminWorkspaces();
  }

  adminLoad(): DirectoryLoad {
    return this.#admin.adminLoad();
  }

  inviteCodes(): InviteCodeView[] {
    return this.#admin.inviteCodes();
  }

  createInviteCode(sub: string, note: unknown, days: unknown, beta = false): InviteCodeView {
    return this.#admin.createInviteCode(sub, note, days, beta);
  }

  revokeInviteCode(value: string): void {
    this.#admin.revokeInviteCode(value);
  }

  // ── bug reports (feedback) ──────────────────────────────────────────────

  addFeedback(input: FeedbackInput): { id: string; number: number; duplicate: boolean } | null {
    return this.#feedback.addFeedback(input);
  }

  adminFeedback(slim = false): AdminFeedback[] {
    return this.#feedback.adminFeedback(slim);
  }

  adminFeedbackItem(idOrRef: string): AdminFeedback {
    return this.#feedback.adminFeedbackItem(idOrRef);
  }

  setFeedbackStatus(id: string, status: FeedbackStatus): void {
    this.#feedback.setFeedbackStatus(id, status);
  }

  markFixed(fixes: { number: number; version: number; parts: string[] }[]): void {
    this.#feedback.markFixed(fixes);
  }

  fixedUntold(station: string): { desktopPlatform: string | null; id: string; number: number; title: string; channel: "stable" | "beta"; version: number; parts: Part[]; session: string | null; thread: string | null }[] {
    return this.#feedback.fixedUntold(station);
  }

  replyToFeedback(id: string, by: string, text: string): { id: string; delivery: "pending" } | { undeliverable: "no_station" | "no_chat" } {
    return this.#feedback.replyToFeedback(id, by, text);
  }

  reporterReply(station: string, number: number, text: string, session: string | null): { id: string } | null {
    return this.#feedback.reporterReply(station, number, text, session);
  }

  feedbackOf(sub: string, workspace: string): { feedback: WorkspaceFeedback[] } {
    return this.#feedback.feedbackOf(sub, workspace);
  }

  memberFeedbackReply(sub: string, workspace: string, id: string, text: string): { id: string } {
    return this.#feedback.memberFeedbackReply(sub, workspace, id, text);
  }

  toldFixed(station: string, ids: string[]): void {
    this.#feedback.toldFixed(station, ids);
  }
}

/** Each directory's calls since they were last kept, by `hour family`: counted in memory, so a call that only reads writes nothing. */
const counted = new WeakMap<Directory, Map<string, number>>();
for (const name of Object.getOwnPropertyNames(Directory.prototype)) {
  const prototype = Directory.prototype as unknown as Record<string, unknown>;
  const method = prototype[name];
  if (UNCOUNTED.has(name) || typeof method !== "function") continue;
  const family = FAMILIES[name] ?? "other";
  prototype[name] = function (this: Directory, ...args: unknown[]) {
    const counts = counted.get(this) ?? counted.set(this, new Map()).get(this)!;
    const k = `${Math.floor(nowSeconds() / 3600)} ${family}`;
    counts.set(k, (counts.get(k) ?? 0) + 1);
    return (method as (...a: unknown[]) => unknown).apply(this, args);
  };
}
