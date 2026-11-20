// P5-1's machine and its event streams (services.ts AdminHost and Events; api/host.ts, api/events.ts): the machine as
// GET /host, the events' `host` samples and other stations are told of it (its CPUs noted every 15 s for their recent
// average, its memory and OS read by the platform's commands, its disk the data directory's, its GPUs Apple's and
// NVIDIA's), and the event streams (`GET /events`): the store's changes pushed as they happen, what was told taken up
// from the process before (`run/events.json`) and handed to the next as this one stops.

///|
priv struct AdminHostLive {
  host : @events.Host
}

///|
/// The CPUs' ticks as the machine says them now: all of them, and those not idle.
fn cpu_ticks() -> @events.Ticks? {
  machine_cpu_ticks().map(t => { busy: t.0, total: t.1 })
}

///|
/// platform's `host.sample`: the memory as the machine counts it, the CPU's model, the uptime, the OS, this process's
/// own memory.
async fn host_sample(host : @host.Host) -> Json {
  let m = machine()
  let num = (k : String) => match m {
    Object(o) =>
      match o.get(k) {
        Some(Number(n, ..)) => n
        _ => 0.0
      }
    _ => 0.0
  }
  let own = if num("footprint") > 0.0 { num("footprint") } else { num("rss") }
  if platform() == "darwin" {
    let total = run_said(host, "/usr/sbin/sysctl", ["-n", "hw.memsize"], 3000)
    let vm = run_said(host, "/usr/bin/vm_stat", [], 3000)
    let swap = run_said(host, "/usr/sbin/sysctl", ["-n", "vm.swapusage"], 3000)
    let model = run_said(host, "/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"], 3000)
    let version = run_said(host, "/usr/bin/sw_vers", ["-productVersion"], 3000)
    // (the system's own commands by their paths: a station's PATH may name none of them)
    let memory = @ops_platform.mac_memory_of(total, vm, () => swap)
    let memory = if memory.total_bytes > 0.0 {
      memory.to_json()
    } else {
      { "totalBytes": Json::number(num("totalmem")), "usedBytes": Json::number(num("totalmem") - num("freemem")), "swapUsedBytes": Json::null() }
    }
    {
      "memory": memory,
      "cpuModel": Json::string(model.unwrap_or("")),
      "uptimeSec": Json::number(num("uptime").round()),
      "osName": Json::string(
        match version {
          Some(v) => "macOS \{v}"
          None => "macOS"
        },
      ),
      "ownRss": Json::number(own),
    }
  } else if is_windows() {
    let total = num("totalmem")
    {
      "memory": { "totalBytes": Json::number(total), "usedBytes": Json::number(total - num("freemem")), "swapUsedBytes": Json::null() },
      "cpuModel": match m {
        { "cpus": Array([{ "model": String(s), .. }, ..]), .. } => Json::string(s)
        _ => Json::string("")
      },
      "uptimeSec": Json::number(num("uptime").round()),
      "osName": Json::string("Windows_NT"),
      "ownRss": Json::number(own),
    }
  } else {
    let (memory, model, uptime) = @ops_platform.linux_sample(
      shell_read_text(host, "/proc/meminfo").unwrap_or(""),
      shell_read_text(host, "/proc/cpuinfo").unwrap_or(""),
      shell_read_text(host, "/proc/uptime").unwrap_or(""),
    )
    let release = run_said(host, "/bin/uname", ["-r"], 3000).unwrap_or("")
    {
      "memory": memory.to_json(),
      "cpuModel": Json::string(model),
      "uptimeSec": Json::number(uptime.round()),
      "osName": Json::string("Linux \{release}"),
      "ownRss": Json::number(own),
    }
  }
}

///|
/// services.ts AdminHost: the machine's state (api/host.ts `Host`), its CPUs followed while the station runs; the bus's
/// `host_sample` from now on.
fn P51::admin_host_live(self : P51) -> AdminHostLive {
  let host = self.host
  let gpus = make_gpus(host)
  let deps : @events.HostDeps = {
    test_host: () => env_get("STILLFAIL_TEST_HOST") == Some("1"),
    now: () => wall_ms().to_double(),
    after: (ms, f) => bus_after(host, ms, f),
    cpu_ticks: k => k(cpu_ticks()),
    sample: k => fork_bg(host, "host sample", async fn() { k(to_jv(host_sample(host))) }),
    statfs: (p, k) => match disk_of(p) {
      // (statfs's fields: blocks of one byte each, as the disk's sizes say them)
      Some((free, total)) => k(Some(to_jv({ "blocks": Json::number(total), "bavail": Json::number(free), "bsize": Json::number(1.0) })))
      None => k(None)
    },
    hostname: () => hostname(),
    parallelism: () => match machine() {
      { "cpus": Array(c), .. } => c.length()
      _ => 1
    },
    loadavg: () => match machine() {
      { "loadavg": Array(l), .. } => l.map(x => match x { Number(n, ..) => n; _ => 0.0 })
      _ => [0.0, 0.0, 0.0]
    },
    arch: if arch() == "x86_64" { "x64" } else { arch() },
    os: () => platform(),
    gpus_read: k => fork_bg(host, "gpus", async fn() {
      k(gpus.read().map(g => to_jv(gpus_to_json(g))))
    }),
    gpus_cached: Some(() => gpus.cached().map(g => to_jv(gpus_to_json(g)))),
  }
  let h = @events.Host::new(deps, self.bus.data)
  let l : AdminHostLive = { host: h }
  // timer: a sample of this machine (its CPUs every 15 s: api/host.ts CPU_EVERY_MS)
  let stop = h.follow((ms, f) => {
    let fiber = host.rt.fork(name="cpu follow", async fn() {
      while true {
        @effect.sleep(ms.to_int())
        f()
      }
    })
    () => fiber.interrupt()
  })
  self.stops.push(stop)
  self.bus.host_sample.val = async fn() { l.sample() }
  l
}

///|
async fn AdminHostLive::sample(self : AdminHostLive) -> Json {
  let d : @effect.Deferred[Json] = @effect.Deferred::new()
  self.host.sample(v => ignore(d.succeed(of_jv(v))))
  d.wait()
}

// ── the event streams ──

///|
priv struct EventsLive {
  events : @events.Events
  /// The streams open, by id, each what it tells next (None: it ended).
  streams : Map[Int, (@effect.Queue[String?], @events.Stream)]
  mut next_stream : Int
}

///|
/// What a thread's change says of its entries as the pages show them (views.ts `entryViews`): each as written, its
/// author's name the credential's where it is a person's, an agent's runtime and model its session's.
fn P51::entry_views(self : P51, entries : Array[@jsjson.JValue]) -> Array[@jsjson.JValue] {
  let names = match self.readers {
    Some(r) => r.names
    None => {}
  }
  entries.map(e => {
    let j = of_jv(e)
    guard j is Object(m) else { return e }
    let v = m.copy()
    let kind = opt_str(v.get("authorKind")).unwrap_or("")
    let author = opt_str(v.get("author")).unwrap_or("")
    if v.get("authorName") is None {
      match kind {
        "person" | "human" =>
          if names.get(author) is Some(n) { v["authorName"] = Json::string(n) }
        "agent" =>
          match (try { Ok(self.bus.store.get_session(author)) } catch { e => Err(e) }) {
            Ok(Object(s)) => {
              if s.get("runtime") is Some(r) { v["authorRuntime"] = r }
              match s.get("model") {
                Some(String(_) as md) => v["authorModel"] = md
                _ => ()
              }
              match s.get("title") {
                Some(String(t)) if t != "" => v["authorName"] = Json::string(t)
                _ => ()
              }
            }
            _ => ()
          }
        _ => ()
      }
    }
    match (v.get("card"), v.get("options")) {
      (None, Some(o)) => v["card"] = { "type": "options", "options": o }
      _ => ()
    }
    to_jv(Json::object(v))
  })
}

///|
/// What a store's session, thread and job are of, as the events and the admin API look at what a viewer sees.
fn P51::seen_store(self : P51) -> @events.SeenStore {
  let store = self.bus.store
  let db = self.bus.db
  {
    session_ws: key => match (try { Ok(store.session_ws(key)) } catch { e => Err(e) }) {
      Ok(Null) | Err(_) => None
      Ok(ws) => Some(to_jv(ws))
    },
    thread_sessions: thread => match (try { Ok(db.all("SELECT session FROM thread_sessions WHERE thread = ? ORDER BY joined_at, rowid", [Json::number(thread)])) } catch { e => Err(e) }) {
      Ok(rows) => rows.filter_map(r => match r.get("session") { Some(String(s)) => Some(s); _ => None })
      Err(_) => []
    },
    job_session: id => match (try { Ok(store.get_job(Json::string(id))) } catch { e => Err(e) }) {
      Ok({ "sessionKey": String(s), .. }) => Some(s)
      _ => None
    },
    session_there: key => match (try { Ok(store.get_session(key)) } catch { e => Err(e) }) {
      Ok(Null) | Err(_) => false
      Ok(_) => true
    },
    thread_there: thread => match (try { Ok(db.all("SELECT id FROM threads WHERE id = ?", [Json::number(thread)])) } catch { e => Err(e) }) {
      Ok(rows) => rows.length() > 0
      Err(_) => false
    },
    handed_to: key => match (try { Ok(store.handed_to(key)) } catch { e => Err(e) }) {
      Ok(Null) | Err(_) => None
      Ok(h) => Some(to_jv(h))
    },
  }
}

///|
/// services.ts Events: the event streams, made on the store's changes, the readers, the machine's samples, what of a
/// job's log is read, what a viewer sees; taken up from the process before (`run/events.json`, events.ts
/// `eventsHandoverFile`: the same file whichever program wrote it) once it is gone,
/// handed over as this one stops; the bus's `events_tell` and `overview_changed` from now on.
fn P51::events_live(self : P51) -> EventsLive {
  let bus = self.bus
  let host = self.host
  let readers = self.readers.unwrap()
  let admin_host = self.admin_host.unwrap()
  let handover_file = path([bus.data, "run", "events.json"])
  let fork_after = (ms : Double, f : () -> Unit) => {
    let fiber = host.rt.fork(name="events after", async fn() {
      @effect.sleep(ms.to_int())
      f()
    })
    () => fiber.interrupt()
  }
  let seen = self.seen_store()
  let deps : @events.Deps = {
    read: (op, args, k) => ignore(
      host.rt.fork_quiet(name="events read", async fn() {
        match (try { Ok(readers.read_bytes(op, of_jv(args), "zh")) } catch { e => Err(e) }) {
          Ok(b) => k(Ok(@utf8.decode_lossy(b)))
          Err(e) => k(Err("\{e}"))
        }
      }),
    ),
    said: (_thread, entries, _lang) => Ok(self.entry_views(entries)),
    host: k => admin_host.host.sample(v => k(Some(v))),
    job_log: id => match (try { Ok(bus.store.get_job(Json::string(id))) } catch { e => Err(e) }) {
      Ok({ "log": String(l), .. }) => Some(l)
      _ => None
    },
    log_now: (id, lines, k) => ignore(
      host.rt.fork_quiet(name="events log", async fn() {
        match (try { Ok(readers.read("jobLog", { "id": Json::string(id), "lines": Json::string(lines.to_string()) }, "zh")) } catch { e => Err(e) }) {
          Ok({ "text": text, .. } as r) =>
            k(Some(to_jv({ "text": text, "outputAt": match r { Object(m) => m.get("outputAt").unwrap_or(Json::null()); _ => Json::null() } })))
          _ => k(None)
        }
      }),
    ),
    live: None,
    held: None,
    held_now: None,
    session_exists: key => match (try { Ok(bus.store.get_session(key)) } catch { e => Err(e) }) {
      Ok(Null) | Err(_) => false
      Ok(_) => true
    },
    live_seen: Some((viewer, key) => @events.session_seen(seen, viewer, key)),
    overview: None,
    process_state: None,
    followed: None,
    seen: Some((viewer, of) => @events.seen_of(seen, viewer, of)),
    login_screen: None,
    in_vault: None,
    now: () => wall_ms().to_double(),
    after: fork_after,
    every: (ms, f) => {
      let fiber = host.rt.fork(name="events every", async fn() {
        while true {
          @effect.sleep(ms.to_int()) // timer: what the events' own clock asks (a heartbeat of a stream, a debounce)
          f()
        }
      })
      () => fiber.interrupt()
    },
    immediate: f => fork_bg(host, "events now", async fn() { f() }),
    // (fs.watch of a file, as a job's log is followed: the shell keeps no watch, so its size and time are looked at
    // every EVENTS_WATCH_MS while it is followed; none where it is not there yet)
    watch: (file, changed) => {
      guard attempt(() => @drive.stat(file)) is Ok(first) else { return None }
      let going = Ref(true)
      fork_bg(host, "a file followed", async fn() {
        let mut before = "\{first.size}:\{first.mtime_ms}"
        while going.val && !bus.stopped.is_done() {
          @effect.sleep(events_watch_ms) // timer: an outside system that offers no push (a file another process writes)
          match attempt(() => @drive.stat(file)) {
            Ok(st) => {
              let now = "\{st.size}:\{st.mtime_ms}"
              if now != before {
                before = now
                changed()
              }
            }
            Err(_) => going.val = false
          }
        }
      })
      Some(() => going.val = false)
    },
    warn: (m, fields) => p51_log("WARN", "events", m, fields=of_jv(fields)),
  }
  let run = @drive.hex(@drive.random_bytes(4))
  let events = @events.Events::new(deps, run, taking=true)
  let e : EventsLive = { events, streams: {}, next_stream: 0 }
  live_events.val = Some(events)
  // The overview as the agents' side and the parts make it (`agents.overview`), for the streams that follow it.
  events.follow(overview=(viewer, lang, k) => ignore(
    host.rt.fork_quiet(name="events overview", async fn() {
      match (try { Ok(self.overview(of_jv(viewer.raw), lang)) } catch { e => Err(e) }) {
        Ok(v) => k(Ok(to_jv(v)))
        Err(err) => k(Err("\{err}"))
      }
    }),
  ))
  // The store's changes, told.
  self.stops.push(bus.subscribe_store(change => events.store_changed(to_jv(change))))
  bus.events_tell.val = (event, data, key, to) => events.tell(event, to_jv(data), key, to_jv(to))
  bus.events_send_live.val = (event, data, to) => events.send_live(event, to_jv(data), to_jv(to))
  bus.overview_changed.val = () => events.overview_changed()
  // config.json changed: the overview and every chat row told again; cloud.json changed: the overview (agents.ts
  // `config.listen(() => (events.overviewChanged(), events.rowsChanged(null)))`, `cloud.listen(() => events.overviewChanged())`).
  self.stops.push(
    (bus.config_listen.val)(_ => {
      events.overview_changed()
      events.rows_changed(None)
    }),
  )
  self.stops.push((bus.cloud_listen.val)(_ => events.overview_changed()))
  // What the process before told, taken up once it is gone.
  self.fork("events take up", async fn() {
    (bus.previous_gone)()
    // events.ts `takeUp`: there but not read (not ENOENT) is `unread`; either way what is there is removed, and the
    // one before's pid (run/hub.json's) is what it must have been written by.
    let text = read_text(handover_file)
    let unread = text is None &&
      (try { Some(@drive.stat(handover_file)) } catch { _ => None }) is Some(_)
    if text is Some(_) || unread {
      @drive.rm_force(handover_file)
    }
    match bus.previous_pid {
      Some(pid) => events.take_up(text, unread~, from=pid)
      None => events.take_up(text, unread~)
    }
  })
  // Handed over as the station stops: what the next process takes up. A read under way is waited for first (the
  // events' `idle_waiters`), so the process waits for it before it ends (`live_p5_1_handed`).
  let handed_now : @effect.Deferred[Unit] = @effect.Deferred::new()
  p51_events_handed.val = Some(handed_now)
  self.stops.push(() => {
    events.hand_over(@drive.pid(), handed => {
      match handed {
        Written(t) => write_whole(handover_file, t)
        Removed => @drive.rm_force(handover_file)
        Nothing => ()
      }
      // (the streams ended once what was handed over is written: a stream that ended before would be no listener)
      for _, s in e.streams {
        ignore(s.0.try_offer(None))
      }
      ignore(handed_now.succeed(()))
    })
  })
  e
}

///|
/// Whether this process's events were handed over as it stopped (None where it serves none).
let p51_events_handed : Ref[@effect.Deferred[Unit]?] = Ref(None)

///|
/// Waits, as the process ends, for its events to be handed over: a read under way when it stopped ends first.
pub async fn live_p5_1_handed() -> Unit {
  if p51_events_handed.val is Some(d) {
    ignore(@effect.timeout(5_000, async fn() { d.wait() })) // timer: a deadline to the process's end
    match p51_live.val {
      Some({ readers: Some(r), .. }) => r.close()
      _ => ()
    }
  }
}

///|
/// `GET /events` (api/events.ts `open`): a stream for `viewer`, as its query asks; what it tells taken a piece at a time
/// (`next`), None once it ends.
async fn EventsLive::open(
  self : EventsLive,
  viewer : Json,
  lang : String,
  asked : @events.Asked,
) -> (Array[(String, String)], Int) {
  let d : @effect.Deferred[Result[@events.Answer, String]] = @effect.Deferred::new()
  self.events.open(@events.Viewer::of(to_jv(viewer)), lang, asked, r => ignore(d.succeed(r)))
  match d.wait() {
    Ok(answer) => {
      self.next_stream += 1
      let id = self.next_stream
      let q : @effect.Queue[String?] = @effect.Queue::unbounded()
      self.streams[id] = (q, answer.stream)
      answer.stream.relay(text => ignore(q.try_offer(Some(text))), () => ignore(q.try_offer(None)))
      (answer.headers, id)
    }
    Err(why) => raise BusError(why)
  }
}

///|
/// A stream's next piece; None once it ended (closed then).
async fn EventsLive::next(self : EventsLive, id : Int) -> String? {
  guard self.streams.get(id) is Some((q, stream)) else { return None }
  match (try { Ok(q.take()) } catch { e => Err(e) }) {
    Ok(Some(t)) => Some(t)
    _ => {
      self.streams.remove(id)
      stream.close()
      None
    }
  }
}

///|
/// A stream's reader went: the stream closed at once.
fn EventsLive::close(self : EventsLive, id : Int) -> Unit {
  match self.streams.get(id) {
    Some((q, stream)) => {
      ignore(q.try_offer(None))
      self.streams.remove(id)
      stream.close()
    }
    None => ()
  }
}

///|
/// The event streams' part, once made: the agents' side gives it the live view (`follow`) and tells it what the
/// sessions at work did (`held_told`).
let live_events : Ref[@events.Events?] = Ref(None)

///|
let events_watch_ms : Int = 250
