// The agents' side of the station (P5-2; station/src/sessions/agents.ts `AgentsLive`): the hub (session_hub) with its
// actors in the sessions' program, the nine runtimes' drivers over `stillfail-runner`, the agents' tools and their door
// (`/mcp`), what other stations ask of this one's chats, and what the station's process does with them (its status, a
// handover, a drain). Made by `run` (run.mbt) on the bus (live_bus.mbt); nothing registers itself.

///|
/// agents.ts's start, in MoonBit: made at once; the sessions taken up once the agents' door is open (`take_handover`).
pub async fn start_live_p5_2(bus : LiveBus) -> Unit {
  let host = bus.host
  // (the launcher's sockets and channel kept from the runners and programs it starts: one that kept them would hold
  // the station's door and channel open after it is gone)
  ignore(keep_descriptors())
  let pump = Pump::new(host)
  let program = SessionsProgram::new(host, bus.argv0, bus.data)
  let agents = AgentsHost::new(pump, program)
  let (zh, en) = catalogs_json()
  let maps = (j : Json) => {
    match j {
      Object(m) => m
      _ => Map([])
    }
  }
  let threads = @store_threads.Store::new(bus.db, wall_ms().to_double()) catch {
    e => {
      slice_log("error", "agents", "the threads' store does not open", {
        "error": jstr(said_of(e)),
      })
      return
    }
  }
  let ctx : P52 = {
    bus,
    host,
    data: bus.data,
    pump,
    program,
    agents,
    threads,
    words: @session_hub.Words::new(
      zh=maps(zh),
      en=maps(en),
      lang=(bus.lang.val)(),
    ),
    cwords: @session_chats.Words::new(to_jv(zh), to_jv(en)),
    rwords: @api_routes.Words::new(to_jv(zh), to_jv(en)),
    files: p52_cold_files(bus),
    config: Json::object({
      "dataDir": jstr(bus.data),
      "profiles": Json::array([]),
      "connects": Json::array([]),
    }),
    hub: None,
    actors_program: None,
    drivers: Map([]),
    door_url: "",
    taken: false,
    site_instructions: "",
    agents_side: None,
    runner: runner_binary(bus.app, bus.argv0, bus.data),
    closed: false,
    computer: None,
    ids_seq: Ref(0),
    repo_index: @session_chats.RepoIndex::new(),
    repo_walking: false,
    everies: {},
    live_locator: None,
    feedback: None,
    card_outcomes: None,
    outcomes_following: false,
    read_lately: Map([]),
    runner_all: None,
    runner_unnamed: Set::new(),
    billed_notified: Map([]),
  }
  p52_lang_fn.val = () => ctx.lang()
  // The cards' queued outcomes, written by the parts that decide a card (the rigs, the phones, the vault) and their
  // cards closed and restated by one worker here (agents.ts `cardOutcomes`).
  ctx.outcomes_start()
  ctx.site_instructions = @agent_runtimes.read_site_instructions(
    host,
    env_get("STILLFAIL_SITE_INSTRUCTIONS"),
  ) catch {
    _ => ""
  }
  ctx.computer = Some(@mcp_tools.Computer::new(ctx.tool_ctx())) catch {
    _ => None
  }
  ignore(
    (bus.config_listen.val)(_ => {
      ignore(
        host.rt.fork_daemon("hub config", on_error=e => @host.note("hub config failed: \{e}"), async fn() { ctx.refresh_config() }),
      )
    }),
  )
  // The drivers, over the processes the program reads.
  let pre : Ref[(HostedProcess) -> Unit] = Ref(p => {
    hosted_by_runner[p.info.id()] = p
  })
  let procs = agents.procs(() => ctx.runner, bus.data, pre)
  let words = driver_words(bus.argv0, bus.app)
  ctx.drivers["claude"] = claude_driver(ctx, procs, words)
  ctx.drivers["codex"] = codex_driver(ctx, procs, words)
  ctx.drivers["agy"] = agy_driver(ctx, procs, words)
  for kind in ["dsh", "grok", "cursor", "devin", "hermes", "pi"] {
    ctx.drivers[kind] = own_runtime_driver(ctx, procs, words, kind)
  }
  bus.runtimes_available.val = () => {
    @session_hub.runtime_kinds.filter(k => ctx.drivers.contains(k))
  }
  // The hub and its actors.
  let hub = @session_hub.Hub::new(
    ctx.hub_world(),
    bus.store,
    threads,
    words=ctx.words,
  )
  ctx.hub = Some(hub)
  ctx.refresh_config()
  ctx.actors_program = Some(ActorsProgram::new(ctx))
  ctx.mount_live(hub)
  // No turn until the agents' door is open (a runtime started before has no MCP endpoint).
  hub.hold("starting")
  ctx.wire_bus()
  // The station's own memory (resources/module.ts): the programs this side runs counted, and what of them answers
  // nothing let go short of memory (agents.ts `readers.onTrim`: the live locator; usage/module.ts: the usage counter).
  bus.register_pids(() => {
    let out : Array[Int] = []
    match program.proc {
      Some(p) if !program.ended => out.push(p.pid)
      _ => ()
    }
    if usage_counter_program.val.bind(c => c.pid()) is Some(pid) { out.push(pid) }
    if ctx.live_locator.bind(l => l.pid()) is Some(pid) { out.push(pid) }
    out
  })
  // (the hub's own reads of the threads' store, what they found not prepared asked of the builders as the store
  // changes next)
  ignore(bus.subscribe_store(_ => bus.drain_thread_requests(threads)))
  bus.on_trim(() => {
    let mut n = 0
    if ctx.live_locator is Some(l) { n += l.trim_idle() }
    if usage_counter_program.val is Some(c) { n += c.trim_idle() }
    n
  })
  // The agents' home (agenthome/module.ts).
  ctx.agent_home_live()
  // Workspaces as the control plane says them (agents.ts `follow`).
  ignore(
    (bus.cloud_listen.val)(_ => {
      fork_bg(host, "agents follow", async fn() {
        if ctx.agents_side is Some(side) { side.follow(ctx.place()) }
      })
    }),
  )
  // The auto-archive's timer, the archived sessions' expiry and the runners' sweep (lifecycle.ts).
  fork_bg(host, "lifecycle", async fn() { ctx.lifecycle() })
}

///|
/// The hub's config worked out again (config.ts `hubConfig`) from config.json.
async fn P52::refresh_config(self : P52) -> Unit {
  let raw = (self.bus.config_raw.val)()
  let worked = @session_chats.hub_config(
    self.chats_world(),
    to_jv(raw),
    self.data,
    _ => None,
  ) catch {
    e => {
      slice_log("warn", "agents", "config.json's hub config not worked out", {
        "error": jstr(said_of(e)),
      })
      return
    }
  }
  self.config = of_jv(worked)
}

///|
/// Where the station is (cloud/state.ts as agents.ts reads it).
fn P52::place(self : P52) -> @session_hub.Place {
  let state = (self.bus.cloud_state.val)()
  let home = match state {
    Some(s) => jtext(s, "workspace")
    None => None
  }
  let joined = match state {
    Some(s) =>
      jitems(jfield(s, "joined")).filter_map(j => {
        match j {
          String(w) => Some(w)
          Object(_) => jtext(j, "workspace")
          _ => None
        }
      })
    None => []
  }
  {
    bound: self.bound(),
    joined,
    home,
    first: home,
    removed: match state {
      Some(s) => jfield(s, "removed_at") != Json::null()
      None => false
    },
    // (cloud/state.ts `rig_due`: listed as a rig now, as its owner's device asked of this station; `rig_pending` what
    // it asked)
    rig_due: match state {
      Some(s) => jfield(s, "rig_due") is True
      None => false
    },
    rig_pending: match state {
      Some(s) =>
        match jfield(s, "rig_pending") {
          Object(_) as due => Some(due)
          _ => None
        }
      None => None
    },
  }
}

///|
/// The workspaces the station is in: its home one first, those it joined after.
fn P52::memberships(self : P52) -> Array[String] {
  let p = self.place()
  if !p.bound {
    return []
  }
  let out = match p.home {
    Some(h) => [h]
    None => []
  }
  for j in p.joined {
    if !out.contains(j) {
      out.push(j)
    }
  }
  out
}

///|
/// A session's page in still.fail (sessions/page.ts `sessionPage`), where the station is in a workspace of still.fail
/// cloud.
fn P52::page_of(self : P52, key : String) -> String? {
  guard (self.bus.cloud_state.val)() is Some(s) else { return None }
  guard jtext(s, "origin") is Some(origin) &&
    jtext(s, "station") is Some(station) &&
    self.bound() else {
    return None
  }
  let ws = match self.ws_of(key) {
    Some(w) => w
    None => jtext(s, "workspace").unwrap_or("")
  }
  if ws != jtext(s, "workspace").unwrap_or("") &&
    !self.memberships().contains(ws) {
    return None
  }
  let o = if origin.has_suffix("/") {
    origin[:origin.length() - 1].to_owned()
  } else {
    origin
  }
  Some("\{o}/o/\{ws}/\{station}/\{@session_hub.encode_uri_component(key)}")
}

///|
/// The hub's world (session_hub `World`): what the hub asks of what is outside it, answered by the station's parts.
fn P52::hub_world(self : P52) -> @session_hub.World {
  {
    tell: (what, args) => self.hub_told(what, args),
    ask: async fn(what, args) { self.hub_asked(what, args) },
    now: () => wall_ms().to_double(),
    config: () => self.config,
    workspaces: () => self.memberships(),
    station: () => {
      match (self.bus.cloud_state.val)() {
        Some(s) => jtext(s, "station")
        None => None
      }
    },
    link: key => self.page_of(key),
    chat: connect => {
      if connect == @session_hub.internal_connect {
        Some({
          "botUserId": jstr("UEMBER"),
          "workspace": Json::null(),
          "has": Json::array([]),
        })
      } else {
        connect_surfaces.get(connect)
      }
    },
    process_state: key => {
      match self.actors_program {
        Some(p) =>
          match p.actors.get(key) {
            Some(a) => a.process_state()
            None => "cold"
          }
        None => "cold"
      }
    },
    idle_ms: (key, now) => {
      match self.actors_program {
        Some(p) =>
          match p.actors.get(key) {
            Some(a) => a.idle_ms(now)
            None => None
          }
        None => None
      }
    },
    random_hex: n => @drive.hex(@drive.random_bytes(n)),
    move_on: () => {
      Some(
        station_feature(
          "stationMove",
          (self.bus.config_raw.val)(),
          self.bus.app,
        ),
      )
    },
  }
}

///|
/// What the hub tells (and waits for nothing of).
fn P52::hub_told(self : P52, what : String, args : Json) -> Unit {
  match what {
    "log" =>
      match args {
        Object(m) =>
          for kv in m {
            slice_log(
              kv.0,
              "hub",
              match kv.1 {
                String(t) => t
                o => o.stringify()
              },
              Json::object({}),
            )
          }
        _ => ()
      }
    "actor.made" =>
      match self.actors_program {
        Some(p) =>
          ignore(
            p.actor(
              jtext(args, "key").unwrap_or(""),
              jtext(args, "runtime").unwrap_or("claude"),
            ),
          )
        None => ()
      }
    "actor" =>
      ignore(
        self.host.rt.fork_quiet(name="actor told", async fn() {
          ignore(self.hub_asked("actor", args)) catch {
            e =>
              slice_log("warn", "hub", "an actor's call failed", {
                "error": jstr(said_of(e)),
              })
          }
        }),
      )
    "chat.post" =>
      ignore(
        self.host.rt.fork_quiet(name="chat post", async fn() {
          ignore(self.hub_asked("chat.post", args)) catch {
            e =>
              slice_log("warn", "hub", "a post failed", {
                "error": jstr(said_of(e)),
              })
          }
        }),
      )
    "drivers" => {
      let call = jtext(args, "call").unwrap_or("")
      let again = jitems(jfield(args, "args")).get(0) ==
        Some(Json::boolean(true))
      for d in self.drivers.values() {
        match call {
          "detach" => (d.detach)()
          "thaw" => (d.thaw)()
          "shutdown" =>
            fork_bg(self.host, "driver shutdown", async fn() {
              (d.shutdown)(again)
            })
          _ => ()
        }
      }
    }
    "actors.close" =>
      if self.actors_program is Some(p) { p.close() }
    "live.call" =>
      match self.actors_program {
        Some(p) =>
          ignore(
            p.post({
              "call": ji(0),
              "actor": jstr("#live"),
              "method": jfield(args, "method"),
              "args": jfield(args, "args"),
            }),
          )
        None => ()
      }
    "closed" =>
      self.on_closed(
        match args {
          String(k) => k
          _ => jtext(args, "key").unwrap_or("")
        },
      )
    "usage.close" =>
      if usage_counter_program.val is Some(p) { p.close() }
    // (what the hub tells its live view, hub.ts's `live`: the shell of the program's `#live`)
    "live.running" =>
      if ctx_live.val is Some(l) { l.running(jtext(args, "key").unwrap_or(""), jfield(args, "running") is True) }
    "live.forget" => {
      let key = match args {
        String(k) => k
        _ => jtext(args, "key").unwrap_or("")
      }
      if ctx_live.val is Some(l) { l.forget(key) }
      self.disarm(key)
    }
    "live.usageCounted" =>
      if ctx_live.val is Some(l) { l.usage_counted() }
    "live.disarmAll" =>
      for key in transcript_watches.keys().collect() {
        self.disarm(key)
      }
    // (a lookup under way is not called off here: its answer is kept as any)
    "live.abortLookups" => ()
    "live.listener" =>
      match jfield(args, "id") {
        Number(n, ..) =>
          if live_listeners.get(n.to_int()) is Some(send) { send(to_jv(jfield(args, "message"))) }
        _ => ()
      }
    "live.heldTold" =>
      if live_events.val is Some(e) { e.held_told(jtext(args, "key").unwrap_or(""), to_jv(jfield(args, "message"))) }
    "live.arm" => self.arm(jtext(args, "key").unwrap_or(""), jtext(args, "path").unwrap_or(""))
    "live.disarm" =>
      self.disarm(
        match args {
          String(k) => k
          _ => jtext(args, "key").unwrap_or("")
        },
      )
    // (a lookup of where a session went on is not called off here: the next read asks again)
    "live.unfollow" => ()
    // (agents.ts `follow`: due to be a rig with nothing asked of it, `rig_due` dropped)
    "agents.rigDueDropped" =>
      ignore(
        self.host.rt.fork_quiet(name="rig due dropped", async fn() {
          ignore((self.bus.cloud_call.val)("dropRigDue", Json::null())) catch {
            _ => ()
          }
        }),
      )
    "taking" => (self.bus.control_say)({ "taking": jb(true) })
    _ =>
      if what.has_prefix("usageCheck.") || what.has_prefix("live.") {
        (self.bus.events_tell.val)(what, args, "", Json::null())
      } else {
        slice_log(
          "warn",
          "hub",
          "the hub told the station what it does not know",
          { "tell": jstr(what) },
        )
      }
  }
}

///|
/// The handover the process before carried (run/handover.json as it was read before it was removed).
let carried_handover : Ref[Json?] = Ref(None)

///|
/// Runtime sessions taken up by a driver for an actor's `adopt`, by the number the hub is given.
let adopting : Map[Int32, Agent] = Map([])

///|
/// What takes the events of a process being taken up for its actor, by its runner's id (hub.ts `takeUp`'s `router`,
/// mb-agents.ts `HostedProcess.adopt`): its actor in the program has them from its first line, held by the actor
/// until it is taken up (`MbActor::begin_adopt`). A Codex app-server's thread's are by its session's key.
let adopt_routers : Map[String, (Int, Int) -> Bool] = Map([])

///|
/// What the hub asks and waits for.
async fn P52::hub_asked(self : P52, what : String, args : Json) -> Json {
  if trace_on() {
    err_write("p52 hub ask \{what} \{clip(args.stringify(), 200)}\n")
  }
  let s = (k : String) => jtext(args, k).unwrap_or("")
  match what {
    "actor" => {
      guard self.actors_program is Some(p) else { return Json::null() }
      let key = s("key")
      let call = s("call")
      let given = jitems(jfield(args, "args"))
      guard p.actors.get(key) is Some(actor) else { return Json::null() }
      if call == "adopt" {
        let agent = match
          jnum_of(given.get(1).unwrap_or(Json::null()), "agent") {
          Some(n) => {
            let a = adopting.get(n.to_int())
            adopting.remove(n.to_int())
            a
          }
          None => None
        }
        actor.adopt(
          given.get(0).unwrap_or(Json::null()),
          agent,
          jtext(
            Json::object({ "p": given.get(2).unwrap_or(Json::null()) }),
            "p",
          ).unwrap_or(""),
        )
        return Json::null()
      }
      actor.hub_asked(call, given)
    }
    "chat.post" => {
      let thread = jfield(args, "thread")
      jstr(
        self.chat_post(
          s("connect"),
          jtext(thread, "channel").unwrap_or(""),
          jtext(thread, "threadTs").unwrap_or(""),
          s("text"),
          jitems(jfield(args, "files")),
        ),
      )
    }
    // (hub.ts `fetched`: a shared file fetched by its chat's surface, written to the session's uploads, measured)
    "chat.downloadTo" => {
      let connect = s("connect")
      let path_to = s("path")
      let got = (self.bus.coord_ask.val)("chat.download", Json::array([Json::string(connect), jfield(args, "file")]))
      let bytes = match got {
        String(hex) => @cloud_lock.hex_bytes(hex)
        _ => raise LiveError("this platform does not give files")
      }
      @drive.mkdir(s("dir"), true)
      ignore(self.host.shell("fs.put", { "path": Json::string(path_to), "truncate": true }, bytes~))
      { "size": Json::number(bytes.length().to_double()), "facts": shown_facts(self.host, path_to) }
    }
    "chat.history"
    | "chat.userEmail"
    | "chat.userName"
    | "chat.sessionLink"
    | "chat.quoted" =>
      if s("connect") == @session_hub.internal_connect {
        match what {
          "chat.userName" =>
            jopt(
              self.user_name(s("connect"), jtext(args, "user").unwrap_or("")),
            )
          "chat.sessionLink" => jfield(args, "link")
          _ => Json::null()
        }
      } else {
        (self.bus.coord_ask.val)(what, args)
      }
    "drivers.evictIdle" => {
      let mut n = 0
      for d in self.drivers.values() {
        n += (d.evict_idle)()
      }
      ji(n)
    }
    "drivers.freeze" => {
      let limit = jnum_of(args, "limitMs").unwrap_or(30_000.0).to_int()
      let done = @effect.timeout(limit, async fn() {
        for d in self.drivers.values() {
          (d.freeze)()
        }
      })
      match done {
        Some(_) => Json::object({})
        None => { "error": jstr("the drivers did not freeze in \{limit} ms") }
      }
    }
    "drivers.owns" => {
      let id = as_text(args).unwrap_or("")
      let kind = match id.find("-") {
        Some(i) => id[:i].to_owned()
        None => id
      }
      match self.drivers.get(kind) {
        Some(d) => jb((d.owned_runners)().contains(id))
        None => jb(false)
      }
    }
    "drivers.adopt" => {
      let row = jfield(args, "row")
      let snap = jfield(args, "snap")
      let key = jtext(row, "key").unwrap_or("")
      guard self.actors_program is Some(p) else { return Json::null() }
      guard p.actors.get(key) is Some(actor) else { return Json::null() }
      let runtime = @session_hub.runtime_named(
        jtext(row, "runtime").unwrap_or(""),
      ).unwrap_or("claude")
      guard self.drivers.get(runtime) is Some(driver) else {
        return Json::null()
      }
      // (the account its runtime session ran on, else the one it runs on now: hub.ts `takeUp`,
      // `accounts.profile(ranOn) ?? accounts.runOn(row.key)`)
      let ran_on = match jtext(args, "ranOn") {
        Some(id) if id != "" =>
          match (try { Ok(self.bus.jobs_accounts_profile(id)) } catch { e => Err(e) }) {
            Ok(Object(_) as p) => Some(p)
            _ => None
          }
        _ => None
      }
      let profile = match ran_on {
        Some(p) => p
        None => self.run_on(key, true, false)
      }
      // Its runtime session as the row keeps it, for what a crash's output read again does not name (an ACP process
      // whose `session/new` or `session/load` came before the acknowledged offset: agy's turns went to session "" and
      // each failed "Session not found", 0.1.9984). A Codex thread with no snapshot (a crash) is taken up by it too:
      // its driver resumes only a thread named so (codex.mbt `adopt`); one with a snapshot goes by the snapshot's.
      let options = match (self.open_options(row, profile, self.link_skills(row)), jtext(row, "runtimeSessionId")) {
        (Object(m), Some(id)) if id != "" && !m.contains("resume") => {
          let c = m.copy()
          c["resume"] = jstr(id)
          Json::object(c)
        }
        (o, _) => o
      }
      // (its events held by its actor while it is taken up, routed from the first: hub.ts `takeUp`, #7096)
      let generation = actor.generation
      let took = actor.begin_adopt(generation)
      let routed_by = if runtime == "codex" { key } else { @agent_drivers.runner_id(runtime, key) }
      adopt_routers[routed_by] = took
      let agent = (driver.adopt)(
        options,
        match jfield(snap, "agent") {
          Null => None
          a => Some(a)
        },
        actor.listener(generation),
      ) catch {
        e => {
          adopt_routers.remove(routed_by)
          actor.cancel_adopt(generation)
          slice_log("warn", "hub", "a session's process was not taken up", {
            "session": jstr(key),
            "error": jstr(said_of(e)),
          })
          return Json::null()
        }
      }
      adopt_routers.remove(routed_by)
      self.ids_seq.val += 1
      adopting[self.ids_seq.val] = agent
      { "agent": ji(self.ids_seq.val) }
    }
    "accounts.pick" =>
      match (self.bus.jobs_ask.val)(what, args) {
        Null => {
          let ids = jitems(jfield(args, "candidates"))
          match
            self
            .profiles()
            .iter()
            .find_first(p => ids.contains(jfield(p, "id"))) {
            Some(p) => p
            None => { "error": jstr("no account can run it") }
          }
        }
        picked => picked
      }
    "accounts.runOn"
    | "accounts.goesOnWith"
    | "accounts.resetAllowance"
    | "accounts.change"
    | "accounts.repick"
    | "accounts.modelEfforts" =>
      match (self.bus.jobs_ask.val)(what, args) {
        Null =>
          match what {
            "accounts.goesOnWith" => jb(true)
            "accounts.modelEfforts" => Json::array([])
            "accounts.change" => Json::object({})
            _ => Json::null()
          }
        v => v
      }
    "fs.mkdirs" => {
      for d in jitems(args) {
        match d {
          String(p) => host_mkdir_quiet(self.host, p)
          _ => ()
        }
      }
      Json::null()
    }
    "fs.write" => {
      let p = s("path")
      host_mkdir_quiet(self.host, @nodepath.dirname(sep(), p))
      ignore(write_text_mode(p, s("text"), 0))
      Json::null()
    }
    "fs.read" => {
      let p = s("path")
      if p == path([self.data, "run", "handover.json"]) {
        match carried_handover.val {
          Some(h) => {
            carried_handover.val = None
            return jstr(h.stringify())
          }
          None => ()
        }
      }
      match (self.host.read_text(p) catch { _ => None }) {
        Some(t) => jstr(t)
        None => Json::null()
      }
    }
    "fs.rm" => {
      host_remove_tree(self.host, s("path"))
      Json::null()
    }
    "fs.rmRoom" => {
      host_remove_tree(self.host, s("home"))
      Json::null()
    }
    "actors.settled" => {
      guard self.actors_program is Some(p) else { return Json::object({}) }
      let limit = jnum_of(args, "limitMs").unwrap_or(30_000.0).to_int()
      let skip : Map[String, Bool] = Map([])
      for k in jitems(jfield(args, "skip")) {
        if k is String(s) {
          skip[s] = true
        }
      }
      let pending : Map[String, Bool] = Map([])
      let done = @effect.timeout(limit, async fn() {
        // Each session's actor alone, its queue run out and again while more came (hub.ts `settled`): the
        // program's own count of asks under way is the shells' too (`#remote`, `#jobs`), which a mirror's sync keeps
        // busy for minutes. (What a runtime said goes to an actor in the program itself, not counted here: the
        // actor's `flushed` waits for it.)
        while true {
          let entries : Array[(String, MbActor)] = []
          pending.clear()
          for kv in p.actors {
            if !skip.contains(kv.0) {
              entries.push((kv.0, kv.1))
              pending[kv.0] = true
            }
          }
          ignore(
            @effect.all(
              entries.map(e => async fn() {
                ignore(e.1.call("flushed", []))
                pending.remove(e.0)
              }),
            ),
          )
          let mut all_ok = true
          for e in entries {
            if !e.1.settled() {
              all_ok = false
              break
            }
          }
          if all_ok {
            for kv in p.actors {
              if !skip.contains(kv.0) && !kv.1.settled() {
                all_ok = false
                break
              }
            }
          }
          if all_ok {
            break
          }
        }
      })
      match done {
        Some(_) => Json::object({})
        None => {
          let unsettled : Array[Json] = []
          let seen : Map[String, Bool] = Map([])
          for kv in p.actors {
            if !skip.contains(kv.0) && (pending.contains(kv.0) || !kv.1.settled()) && !seen.contains(kv.0) {
              seen[kv.0] = true
              unsettled.push(jstr(kv.0))
            }
          }
          for kv in pending {
            if !skip.contains(kv.0) && !seen.contains(kv.0) {
              seen[kv.0] = true
              unsettled.push(jstr(kv.0))
            }
          }
          {
            "error": jstr("the sessions did not settle in \{limit} ms"),
            "unsettled": Json::array(unsettled),
          }
        }
      }
    }
    "runners.allLeft" => {
      all_left(10_000)
      Json::object({})
    }
    "runners" => {
      let infos = self.pump.wait(
        @agent_drivers.live_runners(self.pump.machine(), self.data),
      ) catch {
        _ => []
      }
      Json::array(infos.map(i => jstr(i.id())))
    }
    "runnerId" => jstr(@agent_drivers.runner_id(s("runtime"), s("key")))
    "runners.end" => {
      ignore(
        self.pump.wait(
          @agent_drivers.end_runner(
            self.pump.machine(),
            self.data,
            s("id"),
            s("id"),
          ),
        ),
      ) catch {
        _ => ()
      }
      Json::null()
    }
    // (hub.ts `takeUp`'s lookup of the sessions its runners are of by their ids' parts, its index no longer prepared:
    // "fallback", the sessions listed whole, as SandboxNameBuilder says where it is not ready)
    "sandboxNames.takeUp" => Json::null()
    "machine.transcriptOf" | "transcripts.of" | "marks.forget" | "machine.copyTranscript" => self.machine_ask(what, args)
    "live.call" =>
      match self.actors_program {
        Some(p) => p.call("#live", s("method"), jitems(jfield(args, "args")))
        None => Json::null()
      }
    "live.locate" | "live.tailRead" | "live.page" | "live.state" | "live.counted" => self.live_ask(what, args)
    // (live.ts `handover`: the process before's readings taken up before the program runs here, `take_handover`: none
    // left to wait for once it asks)
    "live.handedOver" => Json::null()
    "cold.expires" => jb(true)
    "cold.holdsMore" =>
      jb(
        self
        .storage()
        .cold_holds_more(
          match args {
            String(k) => k
            _ => s("key")
          },
        ),
      )
    "cold.expire" => {
      self
      .storage()
      .cold_expire(s("key"), jnum_of(args, "before").unwrap_or(0.0))
      Json::null()
    }
    "cold.restore" => {
      self
      .storage()
      .cold_restore(
        match args {
          String(k) => k
          _ => s("key")
        },
      )
      Json::null()
    }
    // (agents.ts `relieving`'s mark, `diskLow`, the one upkeep asks relieveArchived under; a lower one here left the hub
    // finding the disk not low and emptying no archived workspace until 2 GiB were left)
    "disk.low" =>
      match disk_of(self.data) {
        Some((free, total)) => jb(free < @ops_platform.disk_low(total))
        None => jb(false)
      }
    "places.directory" => {
      let p = s("path")
      match attempt(() => @drive.stat(p)) {
        Ok(st) if st.dir => Json::null()
        Ok(_) =>
          { "refused": jstr("notDir"), "message": jstr("\{p} is not a folder") }
        Err(_) =>
          { "refused": jstr("missing"), "message": jstr("\{p} is not there") }
      }
    }
    "agents.along" => (self.bus.coord_ask.val)("agents.along", args)
    "agents.jobsRelaunch" => self.bus.jobs_relaunch(args)
    "agents.jobsStopAll" => self.bus.jobs_stop_all(args)
    "agents.becomeRig" => (self.bus.cloud_call.val)("becomeRig", { "due": args })
    "agents.openDoor" => {
      let url = (self.bus.open_door.val)()
      self.door_url = url
      jstr(url)
    }
    "store.archiveDir" => jstr(path([self.data, "archive"]))
    "waitForWorkspaceActivity" | "prepareLegacyEdits" => Json::null()
    "waitForWorkspaceActivity.has" | "prepareLegacyEdits.has" => jb(false)
    // (the logins are P5-4's: none answers on a station without them)
    "logins.has" =>
      match (try { Ok((self.bus.ui_ask.val)(what, args)) } catch { e => Err(e) }) {
        Ok(True) => jb(true)
        _ => jb(false)
      }
    "logins.answer" => (self.bus.ui_ask.val)(what, args)
    "presets.refusal" | "presets.keep" => self.presets_answer(what[8:].to_owned(), [args])
    "usage.read" | "usage.drainStep" | "usage.stopIndexes" | "usage.inMemory" | "usage.retireStep" =>
      self.usage_ask(what, args)
    "usage.close" => {
      if usage_counter_program.val is Some(p) { p.close() }
      Json::null()
    }
    // (agents.ts `hub.onClose`: a session archived or deleted: its other stations' tasks closed, a deleted one's
    // workspace limits let go, its hands on the screens, its forwards, what the parts keep of it)
    "closed" => {
      let key = match args {
        String(k) => k
        _ => jtext(args, "key").unwrap_or("")
      }
      self.on_closed(key)
      Json::null()
    }
    "turnEnded" | "now" | "carried" | "taking" => {
      if what == "taking" {
        (self.bus.control_say)({ "taking": jb(true) })
      }
      Json::null()
    }
    _ =>
      raise LiveError(
        "the hub asked the station for \{what}, which it does not know",
      )
  }
}

///|
/// What the station's process asks of its agents' side, on the bus.
fn P52::wire_bus(self : P52) -> Unit {
  let bus = self.bus
  bus.mcp_handle.val = Some(async fn(r) { self.mcp(r) })
  bus.hub_ask.val = async fn(op, arg) { self.hub_op(op, arg) }
  bus.hub_models_for.val = connect_id => {
    match self.hub {
      Some(h) => h.models_for(connect_id) catch { _ => [] }
      None => []
    }
  }
  bus.status_agents.val = () => Some(self.status_agents())
  bus.handover_sessions.val = async fn() { self.hand_over() }
  bus.take_handover.val = async fn(handed) { self.take_handover(handed) }
  bus.drain_wait.val = async fn() { self.drain() }
  // What other stations ask of this one's chats (agents.ts `local`).
  for
    meth in [
      "session.read", "session.file", "session.put", "session.create", "session.create.preset",
      "session.create.speed", "session.create.preset.speed", "session.create.preset.tui", "session.archive",
      "session.configure", "session.list", "session.notice",
      "session.message",
    ] {
    bus.on_peer(meth, async fn(peer, ws, params, _bytes) {
      (self.peer_local(peer, ws, meth, params), None)
    })
  }
}

///|
/// What another station's session asks of this one's chats (agents.ts `local`, by session_hub `peer_route`).
async fn P52::peer_local(
  self : P52,
  peer : String,
  ws : String?,
  meth : String,
  params : Json,
) -> Json {
  let storage = self.storage()
  let w = self.chats_world()
  let request = match params {
    Object(m) => {
      let c = m.copy()
      if !c.contains("method") {
        c["method"] = jstr(meth)
      }
      Json::object(c)
    }
    other => other
  }
  match @session_hub.peer_route(meth) {
    "read" => storage.for_peer(peer, request, ws)
    "file" => storage.file_for_peer(request, ws)
    "put" => storage.put_for_peer(peer, request, ws)
    "archive" => storage.archive_for_peer(request, ws)
    "configure" => storage.configure_for_peer(request, ws)
    "list" => storage.list_for_peer(request, ws)
    "create" =>
      of_jv(
        @session_chats.create_for_peer(
          w,
          peer,
          to_jv(request),
          match ws {
            Some(x) => @jsjson.JValue::of_string(x)
            None => J::Null
          },
        ),
      )
    // (a turn of a chat a session here opened there ended: opened.ts `noticeForPeer`)
    "notice" =>
      of_jv(
        @session_chats.notice_for_peer(
          w,
          peer,
          to_jv(request),
          match ws {
            Some(x) => @jsjson.JValue::of_string(x)
            None => J::Null
          },
        ),
      ) catch {
        @session_chats.Thrown(_, m) => raise @gate.PeerRefused(m)
        e => raise e
      }
    // (a message to a session here: messages.ts `fromPeer`)
    _ =>
      of_jv(@session_chats.from_peer(w, peer, to_jv(request), ws)) catch {
        @session_chats.Thrown(_, m) => raise @gate.PeerRefused(m)
        e => raise e
      }
  }
}

///|
/// What a part asks of the hub on the bus (`hub_ask`): a method of it by name (session_hub `hub_call`).
async fn P52::hub_op(self : P52, op : String, arg : Json) -> Json {
  let hub = self.the_hub()
  match op {
    "settled" => {
      // (a turn ended as its opener is told: opened.ts `settled`, an agent that opened the chat woken by it)
      let words = as_text(jfield(arg, "words"))
      @session_chats.settled(self.chats_world(), jtext(arg, "key").unwrap_or(""), jtext(arg, "state").unwrap_or(""), words)
      Json::null()
    }
    "processes" =>
      Json::array(hub.processes().map(p => Json::array([jstr(p.0), jstr(p.1)])))
    "shutdown" => {
      // (the station stops, not handing over: every session's process ended, the program let go)
      if self.closed {
        return Json::null()
      }
      self.closed = true
      hub.hold("drain")
      match self.actors_program {
        Some(p) =>
          for kv in p.actors {
            ignore(kv.1.hub_asked("dispose", [])) catch {
              _ => ()
            }
          }
        None => ()
      }
      for d in self.drivers.values() {
        (d.shutdown)(false) catch {
          _ => ()
        }
      }
      if self.actors_program is Some(p) { p.close() }
      self.program.kill_now()
      Json::null()
    }
    // (the other pseudo-actors of the one sessions' program, `#jobs` and `#remote` (P5-3): mounted on it, asked by it)
    "program.has" => Json::boolean(self.actors_program is Some(_))
    "program.shell" => {
      guard self.actors_program is Some(p) else { return Json::boolean(false) }
      guard jtext(arg, "key") is Some(key) else { return Json::boolean(false) }
      let bus = self.bus
      p.shells[key] = (
        async fn(f, args) {
          bus.program_asked(key, f, args)
        },
        fn(t, args) {
          fork_bg(self.host, "shell's tell", async fn() {
            bus.program_told(key, t, args)
          })
        },
      )
      Json::boolean(true)
    }
    "program.call" => {
      guard self.actors_program is Some(p) else {
        raise LiveError("no sessions' program")
      }
      p.call(
        jtext(arg, "actor").unwrap_or(""),
        jtext(arg, "method").unwrap_or(""),
        jitems(jfield(arg, "args")),
      )
    }
    // (what the platform's own overview is made of where the agents' side makes none: P5-1's `platform_overview`)
    "overview" => Json::null()
    // (P5-5's connects' surfaces, told as one starts, changes or stops: what `world.chat` reads at once)
    "surfaces" => {
      connect_surfaces.clear()
      match arg {
        Object(m) =>
          for k, v in m {
            connect_surfaces[k] = v
          }
        _ => ()
      }
      Json::null()
    }
    // ── what the other slices ask by an object of its fields ──
    // (hub.ts `notify`: the session's actor made where it is cold, an unknown session refused to the one telling)
    "notify" => hub.command(jtext(arg, "session").unwrap_or(""), "notify", [jfield(arg, "text")])
    "link" => jopt(self.page_of(jtext(arg, "session").unwrap_or("")))
    "runners" => self.runners_with_sessions()
    "sweepRunners" =>
      Json::array(
        self.pump.wait(
          @agent_drivers.sweep_runners(self.pump.machine(), self.data, jnum_of(arg, "now").unwrap_or(wall_ms().to_double()), orphan=info => self.pump.later(
            "an orphan runner ended",
            async fn() { hub.end_orphan(of_jv(info.json), wall_ms().to_double()) },
          )),
        ).map(Json::string),
      )
    "relieveArchived" => {
      hub.relieve_archived()
      Json::null()
    }
    "profileGone" => {
      hub.profile_gone(jtext(arg, "profile").unwrap_or(""))
      Json::null()
    }
    // (a message another workspace's station sent a chat shared with it: xshare's inbox, messages.ts `fromPeer`)
    "inbox" => {
      let req = jfield(arg, "request")
      let meth = jtext_or_empty(req, "method")
      self.peer_local(jtext(arg, "station").unwrap_or(""), None, meth, req)
    }
    "codex.renewRunning" | "codex.rateLimits" =>
      match self.drivers.get("codex") {
        Some(d) =>
          (d.ask)(
            op[6:].to_owned(),
            match arg {
              Array([p, ..]) => p
              other => other
            },
          )
        None => if op == "codex.renewRunning" { Json::boolean(false) } else { raise LiveError("no Codex driver here") }
      }
    "agy.renew" | "agy.takeBack" | "agy.noteEmail" =>
      match self.drivers.get("agy") {
        Some(d) =>
          (d.ask)(
            op[4:].to_owned(),
            match arg {
              Array([String(h), ..]) => { "profile": Json::string(h), "home": Json::string(h) }
              other => other
            },
          )
        None => if op == "agy.takeBack" { Json::boolean(false) } else { Json::null() }
      }
    "sessions.allows" => {
      let a = jitems(arg)
      let key = opt_str(a.get(0))
      Json::boolean(
        @session_hub.allowed_in(a.get(1).unwrap_or(Json::null()), hub.ws_of(key), self.workspaces().get(0)),
      )
    }
    "sessions.running" => {
      let except = opt_str(jitems(arg).get(0))
      let out = []
      for key, _ in hub.actors {
        if Some(key) == except || hub.process_state(key) == "cold" {
          continue
        }
        match hub.get_session(key) {
          Some(row) =>
            match jfield(row, "profile") {
              String(p) => out.push(Json::string(p))
              _ => ()
            }
          None => ()
        }
      }
      Json::array(out)
    }
    "sessions.moved" => {
      let a = jitems(arg)
      let key = opt_str(a.get(0)).unwrap_or("")
      let was = a.get(1).unwrap_or(Json::null())
      match hub.get_session(key) {
        Some(now) if !hub.handed_over(key) => {
          let named = (id : String) => {
            let found = self.profiles().iter().find_first(p => jtext(p, "id") == Some(id))
            match found {
              Some(p) => jtext(p, "name")
              None => None
            }
          }
          let ran : Json = { "was": @session_hub.run_shown(was, named), "now": @session_hub.run_shown(now, named) }
          ignore(
            self.host.rt.fork_quiet(name="a session moved", async fn() {
              ignore(hub.ask_actor(hub.actor(now), "runChanged", args=[ran])) catch {
                _ => ()
              }
            }),
          )
        }
        _ => ()
      }
      Json::null()
    }
    "sessions.billedFallback" => {
      let a = jitems(arg)
      let key = opt_str(a.get(0)).unwrap_or("")
      let was = a.get(1).unwrap_or(Json::null())
      let runtime = opt_str(a.get(2)).unwrap_or("")
      let next = a.get(3).unwrap_or(Json::null())
      if !hub.handed_over(key) && runtime != "" {
        let ws = match jtext(was, "ws") {
          Some(w) if w != "" => Some(w)
          _ => self.workspaces().get(0)
        }
        match ws {
          Some(ws) => {
            let at = wall_ms()
            let ck = "\{ws}\u{0}\{runtime}"
            let cooled = match self.billed_notified.get(ck) {
              Some(prev) if at - prev < @cloud_net.billed_notify_cooldown_ms => false
              _ => true
            }
            if cooled {
              self.billed_notified[ck] = at
              let runtime_title = @session_hub.runtime_label(runtime)
              let profile = jtext(next, "name").unwrap_or(jtext(next, "id").unwrap_or(""))
              let cloud = (self.bus.cloud_state.val)()
              let station_name = match cloud {
                Some(c) => {
                  let mut joined_name : String? = None
                  for j in jitems(jfield(c, "joined")) {
                    if jtext(j, "workspace") == Some(ws) {
                      joined_name = jtext(j, "name")
                      break
                    }
                  }
                  match joined_name {
                    Some(n) => n
                    None => jtext(c, "name").unwrap_or("still.fail")
                  }
                }
                None => "still.fail"
              }
              (self.bus.events_send_live.val)(
                "billed-fallback",
                {
                  "runtime": Json::string(runtime),
                  "runtimeTitle": Json::string(runtime_title),
                  "profile": Json::string(profile),
                  "stationName": Json::string(station_name),
                  "at": Json::number(at.to_double()),
                },
                {
                  "managers": Json::boolean(true),
                  "workspace": Json::string(ws),
                },
              )
              let is_stillfail = match cloud {
                Some(c) => @cloud_net.provider_of(Some(jfield(c, "provider"))) is Stillfail
                None => false
              }
              if is_stillfail {
                let notice : Json = {
                  "to": Json::array([]),
                  "audience": Json::string("managers"),
                  "kind": Json::string("billed"),
                  "session": Json::string("billed:\{runtime}"),
                  "thread": Json::number(0.0),
                  "seq": Json::null(),
                  "title": Json::string(station_name),
                  "by": Json::string(runtime_title),
                  "text": Json::string(profile),
                  "at": Json::number(at.to_double()),
                }
                let home = self.workspaces().get(0)
                let body : Json = if Some(ws) == home {
                  { "notices": Json::array([notice]) }
                } else {
                  { "notices": Json::array([notice]), "workspace": Json::string(ws) }
                }
                ignore(
                  self.host.rt.fork_quiet(name="billed fallback notify", async fn() {
                    ignore((self.bus.cloud_call.val)("notify", body)) catch {
                      _ => ()
                    }
                  }),
                )
              }
            }
          }
          None => ()
        }
      }
      Json::null()
    }
    // ── what the accounts (P5-3's) ask of the drivers and the decisions here (agents.ts `makeAccounts`) ──
    "codex.models" | "codex.resetQuota" | "codex.loginChanged" =>
      match self.drivers.get("codex") {
        Some(d) => (d.ask)(op[6:].to_owned(), Json::array(jitems(arg)))
        None => raise LiveError("no Codex driver here")
      }
    "agy.catalog" =>
      match self.drivers.get("agy") {
        Some(d) => (d.ask)("catalog", Json::array(jitems(arg)))
        None => raise LiveError("no Antigravity CLI driver here")
      }
    "hermes.models" =>
      match self.drivers.get("hermes") {
        Some(d) => (d.ask)("models", Json::array(jitems(arg)))
        None => raise LiveError("no Hermes Agent driver here")
      }
    "usage.reprice" => {
      hub.reprice_usage()
      Json::null()
    }
    "decision.fingerprint" =>
      Json::string(@session_chats.fingerprint(self.chats_world(), to_jv(jitems(arg).get(0).unwrap_or(Json::null()))))
    "decision.resolvedModel" => {
      let a = jitems(arg)
      let at = (i : Int) => to_jv(a.get(i).unwrap_or(Json::null()))
      Json::boolean(@session_chats.resolved_model(self.chats_world(), at(0), at(1), at(2)) is Some(_))
    }
    "decision.discover" => {
      let a = jitems(arg)
      let at = (i : Int) => to_jv(a.get(i).unwrap_or(Json::null()))
      of_jv(@session_chats.discover(self.chats_world(), at(0), at(1)))
    }
    // (sessions/archive-policy.ts `savePolicy` on the hub's store: what it changed, null where nothing)
    "policy.savePolicy" => {
      let a = jitems(arg)
      jopt(
        self
        .storage()
        .save_policy(
          match a.get(0) {
            Some(x) if !is_undef_json(x) => Some(x)
            _ => None
          },
          a.get(1).unwrap_or(Json::null()),
          None,
        ),
      )
    }
    // (sessions/review.ts `startReview`: how many chats are reviewed, null where none can be)
    "reviewUndecided" =>
      (@session_chats.start_review(self.chats_world())).map(jn).unwrap_or(Json::null())
    // (agents.ts: the accounts follow the allowances while a stream is open or a session runs)
    "following" =>
      Json::boolean(
        (match live_events.val {
          Some(e) => e.in_use()
          None => false
        }) || hub.any_running(),
      )
    // (agents.ts `updates.onRuntimeChanged`: a runtime installed or updated from the pages)
    "runtimeChanged" => {
      let kind = jtext(arg, "kind").unwrap_or("")
      let replaced = jfield(arg, "replaced") is True
      // Installed: the sessions whose start found it missing take what waits.
      if jfield(arg, "installed") is True {
        hub.installed(kind) catch {
          _ => ()
        }
      }
      // Codex updated: its app-servers of the old version are replaced (their files are gone).
      if self.drivers.get("codex") is Some(d) {
        ignore(
          self.host.rt.fork_quiet(name="codex runtime changed", async fn() {
            ignore((d.ask)("runtimeChanged", { "replaced": jb(kind == "codex" && replaced), "drainBusy": jb(false) })) catch {
              e => slice_log("warn", "agents::codex", "codex app-servers not checked after an update", { "error": jstr(said_of(e)) })
            }
          }),
        )
      }
      // Another runtime: each session's process of it is started again on the new one.
      if kind != "codex" {
        hub.runtime_updated(kind)
      }
      Json::null()
    }
    _ => self.hub_bridge(op, jitems(arg))
  }
}

///|
/// jobs/memory.ts `runnersWithSessions`: the runners alive, each with its session (runnerSessions: a live session's
/// runner first, then any session's).
async fn P52::runners_with_sessions(self : P52) -> Json {
  let infos = self.pump.wait(@agent_drivers.live_runners(self.pump.machine(), self.data))
  let whose : Map[String, String] = {}
  let of = (into : Map[String, String], rows : Array[Json]) => for s in rows {
    match jtext(s, "key") {
      Some(k) =>
        for kind in @events.runtime_kinds {
          let id = @agent_drivers.runner_id(kind, k)
          if !into.contains(id) {
            into[id] = k
          }
        }
      None => ()
    }
  }
  if infos.length() > 0 {
    of(whose, self.bus.store.live_sessions()) catch {
      _ => ()
    }
    // (every session asked again only for a runner neither named nor known to have none: a runner shared by no
    // session's key, a Codex app-server's, asked it at every look, thousands of rows and their runners' ids hashed)
    let rest = infos.filter(i => !whose.contains(i.id()))
    let known = (id : String) => self.runner_unnamed.contains(id) ||
      (match self.runner_all {
        Some(all) => all.contains(id)
        None => false
      })
    if rest.iter().any(i => !known(i.id())) {
      let all : Map[String, String] = {}
      let read = try {
        of(all, self.bus.store.list_sessions())
        true
      } catch {
        _ => false
      }
      if read {
        self.runner_all = Some(all)
        for i in rest {
          if !all.contains(i.id()) {
            self.runner_unnamed.add(i.id())
          }
        }
      }
    }
    if self.runner_all is Some(all) {
      for i in rest {
        if all.get(i.id()) is Some(k) {
          whose[i.id()] = k
        }
      }
    }
  }
  Json::array(
    infos.map(i => {
      let m = match of_jv(i.json) {
        Object(m) => m.copy()
        _ => {}
      }
      m["session"] = jopt(whose.get(i.id()))
      Json::object(m)
    }),
  )
}

///|
/// What `status.sock` says of the agents (api/status.ts): those at work, those warm, all, those waiting for a person,
/// and the tasks at work.
fn P52::status_agents(self : P52) -> Json {
  let states = match self.hub {
    Some(h) => h.processes()
    None => []
  }
  let busy = states.filter(p => p.1 == "running").length()
  let warm = states.filter(p => p.1 == "warm").length()
  let running = self.bus.store.running_sessions() catch { _ => [] }
  let tasks = running.map(r => {
    (
      {
        "session": jfield(r, "key"),
        "title": jfield(r, "title"),
        "state": jstr("working"),
        "since": jfield(r, "lastActiveAt"),
        "need": Json::null(),
      } : Json)
  })
  let waiting = 0.0
  {
    "agents": {
      "busy": ji(if busy > running.length() { busy } else { running.length() }),
      "warm": ji(warm),
      "total": ji(
        if states.length() > running.length() {
          states.length()
        } else {
          running.length()
        },
      ),
    },
    "waiting": jn(waiting),
    "tasks": Json::array(
      tasks[:if tasks.length() > 50 { 50 } else { tasks.length() }].to_owned(),
    ),
  }
}

///|
/// A handover (hub.ts `handOver`): turns held, every actor's snapshot, the drivers let go of their processes; the
/// sessions handed over.
async fn P52::hand_over(self : P52) -> Array[Json] {
  guard self.hub is Some(hub) else { return [] }
  // Within the launcher's 30 s (`Times::exit`): partial handover keeps every settled session's snapshot while
  // skipping any that did not settle in time; its runner is detached and taken up by crash-recovery on the next
  // station.
  let handed = hub.hand_over(limit_ms=15_000.0, partial=true) catch {
    e => {
      slice_log("warn", "agents", "the sessions were not handed over", {
        "error": jstr(said_of(e)),
      })
      // Never leave `self.closed = false` on handover failure: `hub_shutdown()` on stop would otherwise dispose
      // every actor and kill running agent processes. Detach drivers and close the actors' program instead.
      if self.actors_program is Some(p) { p.close() }
      for d in self.drivers.values() {
        (d.detach)()
      }
      all_left(5_000)
      self.closed = true
      self.program.release(false)
      return []
    }
  }
  self.closed = true
  self.program.release(false)
  jitems(jfield(handed, "sessions"))
}

///|
/// The sessions taken up before opening the agents' door (agents.ts `start`): what the process before handed over, the
/// runners it left, then the door opens and turns are released.
async fn P52::take_handover(self : P52, handed : Json?) -> Unit {
  carried_handover.val = handed
  guard self.hub is Some(hub) else {
    codex_left_taken_up()
    return
  }
  let side = @session_hub.AgentsSide::new(hub, self.place())
  self.agents_side = Some(side)
  side.start(self.place()) catch {
    e =>
      slice_log("error", "agents", "the sessions were not taken up", {
        "error": jstr(said_of(e)),
      })
  }
  codex_left_taken_up()
  self.taken = true
  self.start_usage()
  self.start_feedback()
  if trace_on() {
    err_write("p52 taken up\n")
  }
}

///|
/// The station drained (ops/launcher.ts `drain`): once no turn runs, "idle".
async fn P52::drain(self : P52) -> String {
  guard self.hub is Some(hub) else { return "idle" }
  while hub.any_running() {
    @effect.sleep(200) // timer: a deadline's wait for what runs to end (a turn tells nothing of its end to this)
  }
  "idle"
}

///|
/// The sessions' lifecycle (lifecycle.ts): auto archive and the archived sessions' expiry, each when it is next due.
async fn P52::lifecycle(self : P52) -> Unit {
  while !self.taken && !self.bus.stopped.is_done() && !self.closed {
    @effect.sleep(200) // timer: a deadline (waiting for take_handover before the first lifecycle pass)
  }
  while !self.bus.stopped.is_done() && !self.closed {
    let next = match self.hub {
      Some(hub) if self.taken => {
        let a = hub.auto_archive(wall_ms().to_double()) catch {
          e => {
            slice_log("warn", "hub", "auto-archiving failed", { "error": jstr(said_of(e)) })
            None
          }
        }
        let b = hub.expire_archived(wall_ms().to_double()) catch {
          e => {
            slice_log("warn", "hub", "expiring archived workspaces failed", { "error": jstr(said_of(e)) })
            None
          }
        }
        match (a, b) {
          (Some(x), Some(y)) => Some(if x < y { x } else { y })
          (Some(x), None) | (None, Some(x)) => Some(x)
          _ => None
        }
      }
      _ => None
    }
    let wait = match next {
      Some(at) => at - wall_ms().to_double()
      None => 600_000.0
    }
    // timer: a deadline (the next session due to be archived or expired, as the store says)
    @effect.sleep(
      if wait < 1000.0 {
        1000
      } else if wait > 600_000.0 {
        600_000
      } else {
        wait.to_int()
      },
    )
  }
}

///|
/// Whether what the agents' side asks and is asked is written to stderr (STILLFAIL_P52_TRACE=1: looking at what a
/// session did).
fn trace_on() -> Bool {
  env_get("STILLFAIL_P52_TRACE") == Some("1")
}

///|
/// The connects' chat surfaces as the connects' part told them (`surfaces`), by connect.
let connect_surfaces : Map[String, Json] = Map([])

///|
/// The hub's live view (hub.ts `live`, sessions/live.ts `LiveHub`): the shell of the program's `#live`, once made.
let ctx_live : Ref[@session_hub.LiveShell?] = Ref(None)

///|
/// The live view's listeners (a stream following a session), by their subscription: what each is given.
let live_listeners : Map[Int, (@jsjson.JValue) -> Unit] = Map([])

///|
/// agents.ts: the live view mounted on the sessions' program as `#live`, and the event streams given it (`follow`:
/// a session's live steps, the sessions at work, what each now does, a process's state; accounts read again as someone
/// follows again).
fn P52::mount_live(self : P52, hub : @session_hub.Hub) -> Unit {
  let live = @session_hub.LiveShell::new(hub)
  ctx_live.val = Some(live)
  match self.actors_program {
    Some(p) =>
      p.shells["#live"] = (
        async fn(f, args) { live.asked_by_program(f, args) },
        fn(t, args) { live.told_by_program(t, args) },
      )
    None => ()
  }
  // Where each checklist was read to, for the next process to read on from (not back, at each update), and where each
  // transcript's reading stood, for it to read on from there (agents.ts `parts.carry("live.plans" | "live.tails")`).
  self.bus.parts.carry("live.plans", async fn() { jfield(live.carried(), "plans") }, what => live.take_plans(what)) catch {
    _ => ()
  }
  self.bus.parts.carry("live.tails", async fn() { jfield(live.carried(), "tails") }, what => live.take_tails(what)) catch {
    _ => ()
  }
  guard live_events.val is Some(events) else { return }
  let host = self.host
  let bus = self.bus
  events.follow(
    live=(key, from, last, send, brief) => {
      let id = live.subscribe(key, from, last, brief~)
      live_listeners[id] = send
      Some(() => {
        live_listeners.remove(id)
        live.unsubscribe(key, id)
      })
    },
    held=() => live.held_now(),
    held_now=(keys, k) => ignore(
      host.rt.fork_quiet(name="the sessions at work now", async fn() {
        match (try { Ok(live.now_of(keys)) } catch { e => Err(e) }) {
          Ok(v) => k(Ok(to_jv(v)))
          Err(e) => k(Err(said_of(e)))
        }
      }),
    ),
    process_state=key => Some(hub.process_state(key)),
    followed=() => ignore(
      host.rt.fork_quiet(name="followed again", async fn() {
        bus.jobs_accounts_followed() catch {
          _ => ()
        }
      }),
    ),
  )
}
