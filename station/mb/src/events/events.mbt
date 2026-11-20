// GET /events (station/src/api/events.ts `Events`): what changed, as it changes, pushed to each stream whose viewer
// sees it. What is told to everyone is of the log (log.mbt), told again to a stream that comes back `since` an id it
// heard; a viewer's overview is told against what their streams were told of it last; the shared chat list's rows
// as they change; the sessions at work as they run (`heldTold`, a stream opening told each as it is now first);
// a job's log, a login's terminal and host samples to the streams that asked. What it asks of the station (its
// readers, the live view, the overview, the clock) is its `Deps`, each answer given back when it comes: nothing
// here waits.

///|
let ping_ms : Double = 25_000.0

///|
let host_ms : Double = 10_000.0

///|
let usage_every_ms : Double = 60_000.0

///|
/// events.ts RESUMED, HEAD, FOLLOWS: the answer's headers.
pub let resumed_header : String = "stillfail-resumed"

///|
pub let head_header : String = "stillfail-head"

///|
pub let follows_header : String = "stillfail-follows"

///|
/// events.ts LIVE_RATES: a running-session snapshot includes each current output rate, and a quiet rate is cleared.
pub let live_rates_header : String = "stillfail-live-rates"

///|
/// A login's terminal as it is now (events.ts `loginScreen`'s screen).
pub(all) struct Screen {
  rows : Array[String]
  cursor : J
  echo : Bool
  live : Bool
}

///|
/// What the events need of the rest of the station (events.ts `EventsDeps`); each answer is given to the function
/// passed, when it comes.
pub(all) struct Deps {
  /// readers.read(op, args, "zh", TOLD): its text, or why it failed.
  read : (String, J, (Result[String, String]) -> Unit) -> Unit
  /// What was just said in a thread, as the pages show it (made at once; a failure says why).
  said : (J, Array[J], String) -> Result[Array[J], String]
  /// A host sample (GET /host's answer); none: it failed.
  host : ((J?) -> Unit) -> Unit
  job_log : (String) -> String?
  log_now : (String, Int32, (J?) -> Unit) -> Unit
  mut live : ((String, Double, Double?, (J) -> Unit, Bool) -> (() -> Unit)?)?
  mut held : (() -> Array[String])?
  mut held_now : ((Array[String], (Result[J, String]) -> Unit) -> Unit)?
  session_exists : (String) -> Bool
  live_seen : ((Viewer, String) -> Bool)?
  mut overview : ((Viewer, String, (Result[J, String]) -> Unit) -> Unit)?
  mut process_state : ((String) -> String?)?
  mut followed : (() -> Unit)?
  seen : ((Viewer, Of) -> Bool)?
  mut login_screen : ((String, (Screen) -> Unit) -> (() -> Unit)?)?
  mut in_vault : ((Viewer, String) -> Bool)?
  /// The clock: its time, a function after so long, one every so long (each gives how to stop it), and one after
  /// what is being done now (setImmediate).
  now : () -> Double
  after : (Double, () -> Unit) -> () -> Unit
  every : (Double, () -> Unit) -> () -> Unit
  immediate : (() -> Unit) -> Unit
  /// A file's watch (fs.watch): what to call as it changes; none where it cannot be watched (not there yet).
  watch : (String, () -> Unit) -> (() -> Unit)?
  /// A line for the log.
  warn : (String, J) -> Unit
}

///|
/// The stream an `open` answers with: what it tells, piece by piece, given to what carries it (`relay`), what came
/// before that kept.
pub struct Stream {
  queue : Array[String]
  mut closed : Bool
  mut carried : ((String) -> Unit, () -> Unit)?
  mut remove : () -> Unit
}

///|
/// events.ts `relay`: each piece given `send` as it is told, what waited first; `ended` once it ends from this side.
pub fn Stream::relay(
  self : Stream,
  send : (String) -> Unit,
  ended : () -> Unit,
) -> Unit {
  let waiting = self.queue.copy()
  self.queue.clear()
  for t in waiting {
    send(t)
  }
  self.carried = Some((send, ended))
  if self.closed {
    ended()
  }
}

///|
/// Its reader went (the mesh stream closed): the client does, at once.
pub fn Stream::close(self : Stream) -> Unit {
  (self.remove)()
}

///|
fn Stream::push(self : Stream, text : String) -> Unit {
  if self.closed {
    return
  }
  match self.carried {
    Some((send, _)) => send(text)
    None => self.queue.push(text)
  }
}

///|
/// An answer to GET /events: its headers (in order) and its stream.
pub struct Answer {
  headers : Array[(String, String)]
  stream : Stream
}

///|
struct Client {
  id : Int32
  viewer : Viewer
  lang : String
  host : Bool
  running : Bool
  /// What is told of the sessions at work it is told as they are now meanwhile (`heldNow`), by its making.
  mut held_waits : (Int32, Map[String, Array[J]])?
  stream : Stream
  stops : Array[() -> Unit]
}

///|
fn Client::send(self : Client, event : String, data : J) -> Unit {
  self.stream.push("event: \{event}\ndata: \{stringify(data)}\n\n")
}

///|
fn Client::raw(self : Client, text : String) -> Unit {
  self.stream.push(text)
}

///|
struct Dirty {
  sessions : Map[String, Unit]
  mut overview : Bool
  mut whole : Bool
  item_sessions : Map[String, Unit]
  /// Threads by their JSON (a number), with the number as it came.
  item_threads : Map[String, J]
}

///|
fn Dirty::clean() -> Dirty {
  {
    sessions: Map([]),
    overview: false,
    whole: false,
    item_sessions: Map([]),
    item_threads: Map([]),
  }
}

///|
fn Dirty::any(self : Dirty) -> Bool {
  self.sessions.length() > 0 ||
  self.whole ||
  self.overview ||
  self.item_sessions.length() > 0 ||
  self.item_threads.length() > 0
}

///|
enum UsageFrom {
  Unset
  Unknown
  From(Double)
}

///|
/// What a handover writes (events.ts `handOver`): nothing (not this one's turn), the file removed (nobody follows),
/// or the file's text.
pub(all) enum Handed {
  Nothing
  Removed
  Written(String)
}

///|
pub struct Events {
  deps : Deps
  mut clients : Array[Client]
  mut next : Int32
  mut log : EventLog
  mut lingering : (() -> Unit)?
  mut last : (Viewer, String)?
  mut shared_told : Map[String, String]?
  /// A read of the shared chat list under way: who waits for it.
  mut shared_reading : Array[(Bool) -> Unit]?
  mut opening_shared : Int32
  overview_told : Map[String, String]
  mut dirty : Dirty
  states : Map[String, String]
  taken : Map[String, Int32]
  mut flushing : Bool
  mut timers : Array[() -> Unit]
  mut last_host : String
  mut usage_told : Double
  mut usage_later : (() -> Unit)?
  mut usage_from : UsageFrom
  /// Reads to be told once read under way (events.ts `reading`), and who waits for none (a handover).
  mut reading : Int32
  idle_waiters : Array[() -> Unit]
  /// Until what the process before handed over is taken up: what is to be told (in order), the opens waiting.
  mut taking : Bool
  mut early : Array[() -> Unit]
  taking_waiters : Array[() -> Unit]
  mut handed : Bool
  /// The clock's work under way, stopped all at once as it is handed over (Fibers `close`).
  timer_stops : Map[Int32, () -> Unit]
  mut timer_next : Int32
  mut time_closed : Bool
  mut held_making : Int32
}

///|
/// events.ts `new Events`: `run`, its log's (a run of its own); `taking`, whether what the process before handed over
/// is yet to be taken up (`took_up`).
pub fn Events::new(deps : Deps, run : String, taking~ : Bool = false) -> Events {
  {
    deps,
    clients: [],
    next: 1,
    log: EventLog::new(run),
    lingering: None,
    last: None,
    shared_told: None,
    shared_reading: None,
    opening_shared: 0,
    overview_told: Map([]),
    dirty: Dirty::clean(),
    states: Map([]),
    taken: Map([]),
    flushing: false,
    timers: [],
    last_host: "",
    usage_told: -@double.infinity,
    usage_later: None,
    usage_from: Unset,
    reading: 0,
    idle_waiters: [],
    taking,
    early: [],
    taking_waiters: [],
    handed: false,
    timer_stops: Map([]),
    timer_next: 0,
    time_closed: false,
    held_making: 0,
  }
}

///|
/// The log (its run and where it is), for a test.
pub fn Events::log(self : Events) -> EventLog {
  self.log
}

///|
/// Fibers `after`: nothing once the clock's work is closed.
fn Events::after(self : Events, ms : Double, f : () -> Unit) -> () -> Unit {
  if self.time_closed {
    return () => ()
  }
  self.timer_next += 1
  let id = self.timer_next
  let stop = (self.deps.after)(@cmp.maximum(0.0, ms), () => {
    self.timer_stops.remove(id)
    f()
  })
  self.timer_stops[id] = stop
  () => {
    self.timer_stops.remove(id)
    stop()
  }
}

///|
fn Events::every(self : Events, ms : Double, f : () -> Unit) -> () -> Unit {
  if self.time_closed {
    return () => ()
  }
  self.timer_next += 1
  let id = self.timer_next
  let stop = (self.deps.every)(ms, f)
  self.timer_stops[id] = stop
  () => {
    self.timer_stops.remove(id)
    stop()
  }
}

///|
fn Events::close_time(self : Events) -> Unit {
  self.time_closed = true
  let stops = self.timer_stops.values().to_array()
  self.timer_stops.clear()
  for stop in stops {
    stop()
  }
}

///|
/// The taking up is over: streams are answered from now, what was to be told meanwhile given back (in order).
fn Events::took_up_now(self : Events) -> Array[() -> Unit] {
  self.taking = false
  let early = self.early
  self.early = []
  early
}

///|
/// events.ts `takeUp`, once the process before is gone: `text`, what it handed over (none: nothing there; `unread`,
/// there but not read), `from` its pid (none: none held the station).
pub fn Events::take_up(
  self : Events,
  text : String?,
  unread~ : Bool = false,
  from? : Int32,
) -> Unit {
  if !self.taking {
    return
  }
  if self.handed {
    let _ = self.took_up_now()
    self.resume_taking()
    return
  }
  let early = self.took_up_now()
  if text is Some(_) || unread {
    let taken : Result[Unit, String] = if unread {
      Err("unread")
    } else {
      match parse(text.unwrap()) {
        None => Err("not JSON")
        Some(handed) => {
          let now = (self.deps.now)()
          let pid = num_prop(handed, "pid")
          let written_at = num_prop(handed, "at")
          if from is Some(f) && pid != Some(f.to_double()) {
            (self.deps.warn)(
              "what another process than the one before told is not gone on from",
              jo([]),
            )
            Ok(())
          } else if !(written_at is Some(a) && now - a <= kept_ms) {
            (self.deps.warn)(
              "what the process before told is too old to go on from",
              jo([]),
            )
            Ok(())
          } else {
            match handed.get("log") {
              None => Err("not a log")
              Some(kept) =>
                match (Ok(EventLog::from(kept, now)) catch { e => Err(e) }) {
                  Err(_) => Err("not a log")
                  Ok(log) => {
                    let overviews = []
                    // (`new Map(overviews)`: none is none; each entry a pair)
                    let well = match handed.get("overviews") {
                      None | Some(Null) => true
                      Some(Arr(pairs)) =>
                        pairs
                        .iter()
                        .all(p => {
                          p is Arr(_) &&
                          ({
                            overviews.push(
                              (string_of(at(p, 0)), string_of(at(p, 1))),
                            )
                            true
                          })
                        })
                      _ => false
                    }
                    if !well {
                      Err("not overviews")
                    } else {
                      self.log = log
                      self.overview_told.clear()
                      for p in overviews {
                        self.overview_told[p.0] = p.1
                      }
                      self.last = match handed.get("last") {
                        Some(Obj(_) as last) =>
                          match
                            (last.get("viewer"), text_of(last.get("lang"))) {
                            (Some(v), Some(lang)) => Some((Viewer::of(v), lang))
                            _ => None
                          }
                        _ => None
                      }
                      if handed.get("shared") is Some(Obj(_) as shared) {
                        let fresh = match shared.get("until") {
                          Some(Num(until)) => now <= until
                          None | Some(Null) => true
                          _ => false
                        }
                        if fresh {
                          let rows : Map[String, String] = Map([])
                          if shared.get("rows") is Some(Arr(pairs)) {
                            for p in pairs {
                              rows[string_of(at(p, 0))] = string_of(at(p, 1))
                            }
                          }
                          self.shared_told = Some(rows)
                        }
                      }
                      self.linger()
                      Ok(())
                    }
                  }
                }
            }
          }
        }
      }
    }
    if taken is Err(why) {
      (self.deps.warn)(
        "what the process before told does not read; its streams are not resumed",
        jo([("error", js(why))]),
      )
    }
  }
  for tell in early {
    tell()
  }
  self.resume_taking()
}

///|
fn Events::resume_taking(self : Events) -> Unit {
  let waiting = self.taking_waiters.copy()
  self.taking_waiters.clear()
  for w in waiting {
    w()
  }
}

///|
/// events.ts `follow`: the agents' side, once it is made.
pub fn Events::follow(
  self : Events,
  live? : (String, Double, Double?, (J) -> Unit, Bool) -> (() -> Unit)?,
  held? : () -> Array[String],
  held_now? : (Array[String], (Result[J, String]) -> Unit) -> Unit,
  overview? : (Viewer, String, (Result[J, String]) -> Unit) -> Unit,
  process_state? : (String) -> String?,
  followed? : () -> Unit,
  login_screen? : (String, (Screen) -> Unit) -> (() -> Unit)?,
  in_vault? : (Viewer, String) -> Bool,
) -> Unit {
  if live is Some(_) {
    self.deps.live = live
  }
  if held is Some(_) {
    self.deps.held = held
  }
  if held_now is Some(_) {
    self.deps.held_now = held_now
  }
  if overview is Some(_) {
    self.deps.overview = overview
  }
  if process_state is Some(_) {
    self.deps.process_state = process_state
  }
  if followed is Some(_) {
    self.deps.followed = followed
  }
  if login_screen is Some(_) {
    self.deps.login_screen = login_screen
  }
  if in_vault is Some(_) {
    self.deps.in_vault = in_vault
  }
}

///|
/// events.ts `screens`: `listed` in each stream's language, the latest alone kept.
pub fn Events::screens(self : Events, listed : (String) -> J) -> Unit {
  let langs : Map[String, Unit] = Map([])
  for c in self.clients {
    langs[c.lang] = ()
  }
  for lang, _ in langs {
    self.emit(
      "screens",
      listed(lang),
      jo([("lang", js(lang))]),
      of="screens\u{0}\{lang}",
    )
  }
}

///|
pub fn Events::tell(
  self : Events,
  event : String,
  data : J,
  of : String,
  to : J,
) -> Unit {
  self.emit(event, data, to, of~)
}

///|
/// Sends an ephemeral event to currently connected matching streams without appending to the resume log.
pub fn Events::send_live(
  self : Events,
  event : String,
  data : J,
  to : J,
) -> Unit {
  if self.handed {
    return
  }
  for c in self.clients {
    if self.reaches(c, to) {
      c.send(event, data)
    }
  }
}

///|
pub fn Events::machine_logins(
  self : Events,
  data : J,
  limited : J,
  of : String,
) -> Unit {
  self.emit(
    "machine-logins",
    data,
    jo([("readOnly", Bool(false))]),
    of="machine-logins\u{0}\{of}",
  )
  self.emit(
    "machine-logins",
    limited,
    jo([("readOnly", Bool(true))]),
    of="machine-logins-limited\u{0}\{of}",
  )
}

///|
pub fn Events::presets_changed(self : Events) -> Unit {
  self.emit("presets", jo([]), jo([]), of="presets")
}

///|
pub fn Events::overview_changed(self : Events) -> Unit {
  self.dirty.overview = true
  self.wake()
}

///|
pub fn Events::in_use(self : Events) -> Bool {
  self.clients.length() > 0
}

///|
/// `{ ...message, key }`.
fn keyed(message : J, key : String) -> J {
  with_prop(spread(message), "key", js(key))
}

///|
/// events.ts `heldTold`: what a session at work did, to every stream that follows them and sees it.
pub fn Events::held_told(self : Events, key : String, message : J) -> Unit {
  for c in self.clients {
    if !c.running || !self.seen_by(c, Session(key)) {
      continue
    }
    match c.held_waits {
      Some((_, waits)) if waits.get(key) is Some(w) => w.push(message)
      _ => c.send("live", keyed(message, key))
    }
  }
}

///|
fn Events::listening(self : Events) -> Bool {
  !self.handed &&
  (
    self.clients.length() > 0 ||
    self.lingering is Some(_) ||
    self.opening_shared > 0
  )
}

///|
fn rows_told(rows : Array[J]) -> Map[String, String] {
  let told : Map[String, String] = Map([])
  for r in rows {
    told[string_of(r.get("id"))] = stringify(r)
  }
  told
}

///|
/// events.ts `prepareShared`: the shared chat list read whole, once however many wait for it; `done(true)` once read.
fn Events::prepare_shared(self : Events, done : (Bool) -> Unit) -> Unit {
  if self.shared_told is Some(_) {
    return done(true)
  }
  if self.shared_reading is Some(waiters) {
    waiters.push(done)
    return
  }
  let waiters = [done]
  self.shared_reading = Some(waiters)
  self.reading += 1
  (self.deps.read)("sharedOf", jo([("sessions", Null), ("threads", Null)]), got => {
    let ok = match got {
      Ok(text) =>
        match parse(text) {
          Some(read) => {
            let rows = match read.get("rows") {
              Some(Arr(rows)) => rows
              _ => []
            }
            self.shared_told = Some(rows_told(rows))
            true
          }
          None => false
        }
      Err(_) => false
    }
    self.shared_reading = None
    for w in waiters {
      w(ok)
    }
    self.read_done()
  })
}

///|
fn Events::read_done(self : Events) -> Unit {
  self.reading -= 1
  self.idle_check()
}

///|
fn Events::idle_check(self : Events) -> Unit {
  if self.reading == 0 && !self.flushing && self.idle_waiters.length() > 0 {
    let waiting = self.idle_waiters.copy()
    self.idle_waiters.clear()
    for w in waiting {
      w()
    }
  }
}

///|
fn Events::linger(self : Events) -> Unit {
  self.lingering = Some(
    self.after(kept_ms, () => {
      if self.opening_shared > 0 {
        return self.linger()
      }
      self.lingering = None
      self.log.clear()
      self.shared_told = None
      self.overview_told.clear()
    }),
  )
}

///|
/// events.ts `rowsChanged`: `viewer`'s rows (none: the shared list's, read whole); `made`, what is told puts them in
/// place itself.
pub fn Events::rows_changed(
  self : Events,
  viewer : String?,
  made~ : Bool = false,
) -> Unit {
  if !made {
    self.emit(
      "chat-changed",
      jo([]),
      match viewer {
        None => jo([])
        Some(v) => jo([("email", js(v))])
      },
    )
  }
  if viewer is Some(_) {
    return
  }
  self.dirty.whole = true
  self.wake()
}

///|
fn Events::items_changed(
  self : Events,
  sessions : Array[String],
  threads : Array[J],
) -> Unit {
  for key in sessions {
    self.dirty.item_sessions[key] = ()
  }
  for id in threads {
    self.dirty.item_threads[stringify(id)] = id
  }
  self.wake()
}

///|
/// What a stream is opened with (events.ts `open`'s parameters).
pub(all) struct Asked {
  host : Bool
  live : Array[(String, Double, Double?)]
  logs : Array[(String, Int32)]
  since : String?
  brief : Bool
  logins : Array[String]
  running : Bool
}

///|
/// events.ts `open`: a stream for `viewer` in `lang`, given `done` once it is answered (an error: the shared chat list
/// did not read).
pub fn Events::open(
  self : Events,
  viewer : Viewer,
  lang : String,
  asked : Asked,
  done : (Result[Answer, String]) -> Unit,
) -> Unit {
  let follows = asked.running && self.deps.held is Some(_)
  let live = if follows { [] } else { asked.live }
  let go = () => {
    let shared_history = self.shared_told is Some(_)
    self.opening_shared += 1
    fn again() {
      if self.shared_told is Some(_) {
        self.opened(viewer, lang, asked, follows, live, shared_history, done)
      } else {
        self.prepare_shared(ok => {
          if ok {
            again()
          } else {
            self.opening_shared -= 1
            done(Err("the chat list is not read"))
          }
        })
      }
    }

    again()
  }
  if self.taking {
    self.taking_waiters.push(go)
  } else {
    go()
  }
}

///|
fn Events::opened(
  self : Events,
  viewer : Viewer,
  lang : String,
  asked : Asked,
  follows : Bool,
  live : Array[(String, Double, Double?)],
  shared_history : Bool,
  done : (Result[Answer, String]) -> Unit,
) -> Unit {
  let stream = { queue: [], closed: false, carried: None, remove: () => (), }
  let client = {
    id: self.next,
    viewer,
    lang,
    host: asked.host,
    running: follows,
    held_waits: None,
    stream,
    stops: [],
  }
  self.next += 1
  client.raw("retry: 3000\n\n")
  client.send(
    "made",
    jo([("rows", Bool(true)), ("marks", Bool(true)), ("shared", Bool(true))]),
  )
  let k = viewer_key(viewer, lang)
  let resumes = asked.since is Some(since) &&
    shared_history &&
    self.log.has(since)
  if asked.since is Some(since) && !resumes {
    (self.deps.warn)("a stream is not resumed", jo([("since", js(since))]))
    client.send("missed", jo([]))
  }
  if !resumes {
    self.overview_told.remove(k)
  }
  if follows && self.deps.held_now is Some(held_now) {
    let keys = self.deps.held.unwrap()().filter(key => {
      self.seen_by(client, Session(key))
    })
    if keys.length() > 0 {
      self.held_making += 1
      let making = self.held_making
      let waits : Map[String, Array[J]] = Map([])
      for key in keys {
        waits[key] = []
      }
      client.held_waits = Some((making, waits))
      held_now(keys, got => {
        let now = match got {
          Ok(now) => now
          Err(_) => jo([])
        }
        guard client.held_waits is Some((m, _)) && m == making else { return }
        client.held_waits = None
        for key in keys {
          let before = match now.get(key) {
            Some(Arr(items)) => items
            _ => []
          }
          for message in before {
            client.send("live", keyed(message, key))
          }
          for message in waits.get(key).unwrap() {
            client.send("live", keyed(message, key))
          }
        }
      })
    }
  }
  for one in live {
    let (key, from, last) = one
    if self.deps.live is Some(follow) {
      let stop = follow(
        key,
        from,
        last,
        message => {
          let seen = match self.deps.live_seen {
            Some(f) => f(viewer, key)
            None =>
              (self.deps.session_exists)(key) &&
              self.seen_by(client, Session(key))
          }
          if seen {
            client.send("live", keyed(message, key))
          }
        },
        asked.brief,
      )
      if stop is Some(stop) {
        client.stops.push(stop)
      }
    }
  }
  for one in asked.logs {
    client.stops.push(self.follow_log(client, one.0, one.1))
  }
  for id in asked.logins {
    if self.deps.login_screen is Some(screen_of) {
      let told : Ref[Array[String]?] = { val: None, }
      let stop = screen_of(id, screen => {
        let rows = []
        for i, row in screen.rows {
          let same = match told.val {
            Some(t) => i < t.length() && t[i] == row
            None => false
          }
          if !same {
            rows.push((i.to_string(), js(row)))
          }
        }
        client.send(
          "login-screen",
          jopt([
            ("id", Some(js(id))),
            ("rows", Some(jo(rows))),
            ("cursor", Some(screen.cursor)),
            ("echo", Some(Bool(screen.echo))),
            ("live", Some(Bool(screen.live))),
            ("full", if told.val is None { Some(Bool(true)) } else { None }),
          ]),
        )
        told.val = Some(screen.rows)
      })
      if stop is Some(stop) {
        client.stops.push(stop)
      }
    }
  }
  if asked.host {
    (self.deps.host)(info => if info is Some(info) { client.send("host", info) })
  }
  if !resumes {
    client.raw("id: \{self.log.at()}\n\n")
  }
  self.clients.push(client)
  self.opening_shared -= 1
  self.last = Some((viewer, lang))
  if self.lingering is Some(stop) {
    stop()
  }
  self.lingering = None
  if resumes {
    for told in self.log.after(asked.since.unwrap()) {
      if self.reaches(client, told.to) {
        client.raw(told.text)
      }
    }
  }
  let head = if resumes { Some(self.log.at()) } else { None }
  if resumes {
    self.overview_changed()
  }
  if self.clients.length() == 1 {
    self.start_timers()
    if self.deps.followed is Some(f) {
      f()
    }
  }
  stream.remove = () => {
    if stream.closed {
      return
    }
    stream.closed = true
    if stream.carried is Some((_, ended)) {
      ended()
    }
    self.clients = self.clients.filter(c => c.id != client.id)
    for stop in client.stops {
      stop()
    }
    if self.clients.length() > 0 {
      return
    }
    self.stop_timers()
    self.linger()
  }
  let headers = [
    ("content-type", "text/event-stream"),
    ("cache-control", "no-store"),
    ("connection", "keep-alive"),
    ("x-accel-buffering", "no"),
  ]
  if head is Some(h) {
    headers.push((resumed_header, "1"))
    headers.push((head_header, h))
  }
  if follows {
    headers.push((follows_header, "running"))
    if self.deps.held_now is Some(_) {
      headers.push((live_rates_header, "1"))
    }
  }
  done(Ok({ headers, stream, }))
}

///|
/// events.ts `followLog`: a job's last `lines` (`job-log`), at once, then whenever its log changes.
fn Events::follow_log(
  self : Events,
  client : Client,
  id : String,
  lines : Int32,
) -> () -> Unit {
  guard (self.deps.job_log)(id) is Some(path) else { return () => () }
  let seen = Ref("")
  let stopped = Ref(false)
  let reading = Ref(false)
  let again = Ref(false)
  fn tell() {
    if reading.val {
      again.val = true
      return
    }
    reading.val = true
    fn round() {
      again.val = false
      (self.deps.log_now)(id, lines, got => {
        if stopped.val {
          reading.val = false
          return
        }
        let now = match got {
          None => "none"
          Some(g) => stringify(g)
        }
        if now != seen.val {
          seen.val = now
          client.send(
            "job-log",
            jo([
              ("id", js(id)),
              ("lines", jn(lines.to_double())),
              (
                "text",
                match got {
                  Some(g) => either(g.get("text"), None).unwrap_or(js(""))
                  None => js("")
                },
              ),
              (
                "outputAt",
                match got {
                  Some(g) =>
                    match g.get("outputAt") {
                      Some(Null) | None => (Null : J)
                      Some(v) => v
                    }
                  None => (Null : J)
                },
              ),
            ]),
          )
        }
        if again.val {
          round()
        } else {
          reading.val = false
        }
      })
    }

    round()
  }

  tell()
  let watcher : Ref[(() -> Unit)?] = { val: None, }
  let pending : Ref[(() -> Unit)?] = { val: None, }
  let soon = () => {
    if pending.val is Some(_) {
      return
    }
    pending.val = Some(
      self.after(200.0, () => {
        pending.val = None
        tell()
      }),
    )
  }
  let follow = () => {
    if watcher.val is None {
      watcher.val = (self.deps.watch)(path, soon)
    }
  }
  follow()
  let check = self.every(5000.0, () => {
    follow()
    tell()
  })
  () => {
    stopped.val = true
    if watcher.val is Some(w) {
      w()
    }
    check()
    if pending.val is Some(p) {
      p()
    }
  }
}

///|
fn Events::start_timers(self : Events) -> Unit {
  self.timers.push(
    self.every(ping_ms, () => {
      for c in self.clients {
        c.raw(": ping\n\n")
      }
    }),
  )
  self.timers.push(
    self.every(host_ms, () => {
      if !self.clients.iter().any(c => c.host) {
        return
      }
      (self.deps.host)(info => {
        guard info is Some(info) else { return }
        let shown = without(without(spread(info), "checkedAt"), "uptimeSec")
        let key = stringify(shown)
        if key == self.last_host {
          return
        }
        self.last_host = key
        for c in self.clients {
          if c.host {
            c.send("host", info)
          }
        }
      })
    }),
  )
}

///|
fn Events::stop_timers(self : Events) -> Unit {
  for stop in self.timers {
    stop()
  }
  self.timers = []
  self.last_host = ""
}

///|
/// events.ts `emit`: one text for every stream `to` says, of the log.
fn Events::emit(
  self : Events,
  event : String,
  data : J,
  to : J,
  of? : String,
) -> Unit {
  if self.taking {
    self.early.push(() => self.emit(event, data, to, of?))
    return
  }
  if !self.listening() {
    return
  }
  let logged = self.log.append(
    event,
    stringify(data),
    to,
    (self.deps.now)(),
    of?,
  )
  for c in self.clients {
    if self.reaches(c, to) {
      c.raw(logged.text)
    }
  }
}

///|
fn Events::reaches(self : Events, c : Client, to : J) -> Bool {
  is_for(to, c.viewer, c.lang, self.deps.seen, self.deps.in_vault)
}

///|
fn Events::seen_by(self : Events, c : Client, of : Of) -> Bool {
  match self.deps.seen {
    Some(f) => f(c.viewer, of)
    None => true
  }
}

///|
fn sees_to(of : (String, J)) -> J {
  jo([("sees", jo([of]))])
}

///|
/// events.ts `storeChanged`: one of the store's changes (store/rows.ts `StoreChange`, as data).
pub fn Events::store_changed(self : Events, change : J) -> Unit {
  if self.taking {
    self.early.push(() => self.store_changed(change))
    return
  }
  let kind = str_prop(change, "type").unwrap_or("")
  let key = string_of(change.get("key"))
  match kind {
    "session" => {
      if change.get("pending") is Some(pending) {
        self.taken[key] = self.taken.get(key).unwrap_or(0) + 1
        self.emit(
          "session-pending",
          jopt([("key", change.get("key")), ("pending", Some(pending))]),
          sees_to(("session", js(key))),
        )
      }
      self.dirty.sessions[key] = ()
      self.items_changed([key], [])
    }
    "sessionRemoved" => {
      self.dirty.sessions.remove(key)
      self.states.remove(key)
      self.taken.remove(key)
      self.overview_changed()
      self.emit(
        "session-removed",
        jopt([("key", change.get("key"))]),
        sees_to(("ws", ws_of(change))),
        of="session\u{0}\{key}",
      )
      self.items_changed([key], [])
    }
    "thread" => {
      let id = change.get("id").unwrap_or(Null)
      let entries = match change.get("entries") {
        Some(Arr(e)) => e
        _ => []
      }
      if self.listening() && entries.length() > 0 && self.who() is Some(lang) {
        self.tell_said("thread", id, entries, lang)
      }
      if entries.length() == 0 {
        self.emit("chat-changed", jo([("thread", id)]), sees_to(("thread", id)))
      }
      self.items_changed([], [id])
    }
    "letters" => {
      let id = change.get("id").unwrap_or(Null)
      let letters = match change.get("letters") {
        Some(Arr(e)) => e
        _ => []
      }
      if self.listening() && letters.length() > 0 && self.who() is Some(lang) {
        self.tell_said("letters", id, letters, lang)
      }
    }
    "moved" => {
      self.emit(
        "chat-moved",
        jopt([
          ("session", change.get("key")),
          ("station", change.get("station")),
          ("thread", change.get("thread")),
          ("there", change.get("there")),
        ]),
        jo([("sees", jopt([("ws", change.get("ws"))]))]),
      )
      self.rows_changed(None, made=true)
    }
    "threadRemoved" => {
      self.emit(
        "thread-removed",
        jopt([("id", change.get("id"))]),
        sees_to(("ws", ws_of(change))),
      )
      self.rows_changed(None, made=true)
    }
    "read" =>
      self.emit(
        "read",
        jopt([
          ("viewer", change.get("viewer")),
          ("thread", change.get("thread")),
          ("n", change.get("n")),
        ]),
        viewer_thread(change),
      )
    "hidden" =>
      self.emit(
        "hidden",
        jopt([
          ("thread", change.get("thread")),
          ("hidden", change.get("hidden")),
        ]),
        viewer_thread(change),
      )
    "muted" =>
      self.emit(
        "muted",
        jopt([("thread", change.get("thread")), ("muted", change.get("muted"))]),
        viewer_thread(change),
      )
    "identities" => {
      self.overview_changed()
      self.rows_changed(text_of(change.get("viewer")))
    }
    "pins" | "dismissed" => {
      let viewer = change.get("viewer")
      let email = jopt([("email", viewer)])
      if kind == "pins" && change.get("session") is Some(session) {
        let at = match change.get("at") {
          None | Some(Null) => (Null : J)
          Some(at) => at
        }
        self.emit("pin", jo([("session", session), ("at", at)]), email)
      }
      if kind == "dismissed" && change.get("card") is Some(card) {
        self.emit(
          "dismiss",
          card,
          jopt([
            ("email", viewer),
            ("sees", Some(jopt([("thread", card.get("thread"))]))),
          ]),
        )
      }
      if kind == "dismissed" && change.get("kept") is Some(kept) {
        self.emit(
          "kept",
          kept,
          jopt([
            ("email", viewer),
            ("sees", Some(jopt([("thread", kept.get("thread"))]))),
          ]),
        )
      }
      let made = (kind == "pins" && change.get("session") is Some(_)) ||
        (
          kind == "dismissed" &&
          (change.get("card") is Some(_) || change.get("kept") is Some(_))
        )
      self.rows_changed(text_of(viewer), made~)
    }
    "job" => {
      let id = string_of(change.get("id"))
      self.reading += 1
      (self.deps.read)("job", jo([("id", change.get("id").unwrap_or(Null))]), got => {
        if got is Ok(text) && parse(text) is Some(job) {
          self.emit("job", job, sees_to(("job", js(id))), of="job\u{0}\{id}")
        }
        self.read_done()
      })
    }
    "jobRemoved" => {
      let id = string_of(change.get("id"))
      self.emit(
        "job-removed",
        jopt([("id", change.get("id")), ("session", change.get("session"))]),
        sees_to(("session", js(string_of(change.get("session"))))),
        of="job\u{0}\{id}",
      )
    }
    "usage" => {
      self.usage_from = match (self.usage_from, change.get("from")) {
        (Unknown, _) | (_, None) => Unknown
        (Unset, Some(f)) => From(js_min(@double.infinity, to_number(f)))
        (From(was), Some(f)) => From(js_min(was, to_number(f)))
      }
      self.usage_changed()
    }
    "chatMark" => {
      let mark = without(change, "type")
      let to = match change.get("thread") {
        Some(Null) => sees_to(("session", js(string_of(change.get("session")))))
        thread => sees_to(("thread", thread.unwrap_or(Null)))
      }
      self.emit("chat-mark", mark, to)
    }
    "processes" | "decisionChecks" => self.overview_changed()
    _ => ()
  }
}

///|
/// `change.ws ?? null`.
fn ws_of(change : J) -> J {
  match change.get("ws") {
    None => Null
    Some(ws) => ws
  }
}

///|
fn viewer_thread(change : J) -> J {
  jopt([
    ("email", change.get("viewer")),
    ("sees", Some(jopt([("thread", change.get("thread"))]))),
  ])
}

///|
/// Whose language a thread's entries are told in: the first stream's, or the last to follow's.
fn Events::who(self : Events) -> String? {
  if self.clients.length() > 0 {
    Some(self.clients[0].lang)
  } else {
    self.last.map(l => l.1)
  }
}

///|
fn Events::tell_said(
  self : Events,
  event : String,
  id : J,
  entries : Array[J],
  lang : String,
) -> Unit {
  match (self.deps.said)(id, entries, lang) {
    Err(why) =>
      (self.deps.warn)("\{event} event not sent", jo([("error", js(why))]))
    Ok(views) =>
      self.emit(
        event,
        jo([
          ("id", id),
          (if event == "thread" { "entries" } else { "letters" }, ja(views)),
        ]),
        sees_to(("thread", id)),
      )
  }
}

///|
fn Events::usage_changed(self : Events) -> Unit {
  if self.usage_later is Some(_) {
    return
  }
  let tell = () => {
    self.usage_later = None
    self.tell_usage()
  }
  let wait = self.usage_told + usage_every_ms - (self.deps.now)()
  if wait <= 0 {
    tell()
  } else {
    self.usage_later = Some(self.after(wait, tell))
  }
}

///|
fn Events::tell_usage(self : Events) -> Unit {
  let from = self.usage_from
  self.usage_from = Unset
  self.usage_told = (self.deps.now)()
  self.emit(
    "usage",
    match from {
      From(f) => jo([("from", jn(f))])
      _ => jo([])
    },
    jo([]),
  )
}

///|
/// events.ts `wake`: changes gathered into one round, after what happens now.
fn Events::wake(self : Events) -> Unit {
  if self.flushing {
    return
  }
  self.flushing = true
  (self.deps.immediate)(() => {
    self.flush(() => {
      self.flushing = false
      if self.dirty.any() {
        self.wake()
      }
      self.idle_check()
    })
  })
}

///|
/// events.ts `flush`: an event per changed session, the overview to each viewer, the shared list's changed rows.
fn Events::flush(self : Events, done : () -> Unit) -> Unit {
  let dirty = self.dirty
  self.dirty = Dirty::clean()
  let overview = Ref(dirty.overview)
  for key, _ in dirty.sessions {
    if !(self.deps.session_exists)(key) {
      continue
    }
    if self.deps.process_state is Some(f) &&
      f(key) is Some(state) &&
      self.states.get(key) != Some(state) {
      self.states[key] = state
      overview.val = true
    }
  }
  if !self.listening() {
    return done()
  }
  let keys = dirty.sessions.keys().to_array()
  fn summaries(i : Int32) {
    if i >= keys.length() {
      return self.flush_overviews(overview.val, () => {
        self.tell_shared(dirty, done)
      })
    }
    let key = keys[i]
    if !(self.deps.session_exists)(key) {
      return summaries(i + 1)
    }
    let taken = self.taken.get(key)
    (self.deps.read)("summary", jo([("key", js(key))]), got => {
      match got {
        Ok(text) =>
          if self.taken.get(key) == taken {
            match parse(text) {
              Some(summary) =>
                self.emit(
                  "session",
                  summary,
                  sees_to(("session", js(key))),
                  of="session\u{0}\{key}",
                )
              None =>
                (self.deps.warn)(
                  "session event not sent",
                  jo([("session", js(key))]),
                )
            }
          }
        Err(why) =>
          (self.deps.warn)(
            "session event not sent",
            jo([("session", js(key)), ("error", js(why))]),
          )
      }
      summaries(i + 1)
    })
  }

  summaries(0)
}

///|
fn Events::flush_overviews(
  self : Events,
  overview : Bool,
  done : () -> Unit,
) -> Unit {
  guard overview && self.deps.overview is Some(overview_of) else {
    return done()
  }
  let seen : Map[String, Unit] = Map([])
  let viewers = []
  for c in self.clients {
    let k = viewer_key(c.viewer, c.lang)
    if !seen.contains(k) {
      seen[k] = ()
      viewers.push((c.viewer, c.lang))
    }
  }
  if viewers.length() == 0 {
    return done()
  }
  let left = Ref(viewers.length())
  for one in viewers {
    let (viewer, lang) = one
    overview_of(viewer, lang, got => {
      match got {
        Ok(value) => {
          let k = viewer_key(viewer, lang)
          let text = stringify(value)
          if self.overview_told.get(k) != Some(text) {
            self.overview_told[k] = text
            self.emit(
              "overview",
              value,
              jo([("viewer", js(k))]),
              of="overview\u{0}\{k}",
            )
          }
        }
        Err(why) =>
          (self.deps.warn)("overview not told", jo([("error", js(why))]))
      }
      left.val -= 1
      if left.val == 0 {
        done()
      }
    })
  }
}

///|
/// `place`: the workspace a row was told in (`ws ?? null`).
fn place(text : String) -> J {
  match parse(text) {
    Some(v) =>
      match v.get("ws") {
        None => Null
        Some(ws) => ws
      }
    None => Null
  }
}

///|
fn shared_key(id : String, ws : J) -> String {
  "chat-shared\u{0}\{id}\u{0}\{stringify(ws)}"
}

///|
/// events.ts `tellShared`.
fn Events::tell_shared(self : Events, dirty : Dirty, done : () -> Unit) -> Unit {
  let sessions = dirty.item_sessions.keys().to_array()
  let threads = dirty.item_threads.values().to_array()
  let whole = dirty.whole
  if !whole && sessions.length() == 0 && threads.length() == 0 {
    return done()
  }
  let go = () => {
    if self.shared_told is None || !self.listening() {
      return done()
    }
    let args = if whole {
      jo([("sessions", Null), ("threads", Null)])
    } else {
      jo([("sessions", ja(sessions.map(js))), ("threads", ja(threads))])
    }
    (self.deps.read)("sharedOf", args, got => {
      let read = match got {
        Ok(text) => parse(text)
        Err(_) => None
      }
      let rows = match read {
        Some(r) =>
          match r.get("rows") {
            Some(Arr(rows)) => Some(rows)
            _ => None
          }
        None => None
      }
      guard read is Some(read) && rows is Some(rows) else {
        (self.deps.warn)(
          "the chat list not read; its streams will read again",
          jo([]),
        )
        self.shared_told = None
        self.log.clear()
        for c in self.clients.copy() {
          c.stream.close()
        }
        return done()
      }
      let now = rows_told(rows)
      guard self.shared_told is Some(told) else { return done() }
      for row in rows {
        let id = string_of(row.get("id"))
        if told.get(id) == now.get(id) {
          continue
        }
        let before = told.get(id)
        let ws : J = match row.get("ws") {
          None => Null
          Some(ws) => ws
        }
        if before is Some(b) && stringify(place(b)) != stringify(ws) {
          let old = place(b)
          self.emit(
            "chat-shared-removed",
            jo([("id", js(id))]),
            sees_to(("ws", old)),
            of=shared_key(id, old),
          )
        }
        told[id] = now.get(id).unwrap()
        self.emit(
          "chat-shared",
          row,
          sees_to(("ws", ws)),
          of=shared_key(id, ws),
        )
      }
      let gone = match read.get("scope") {
        Some(Arr(scope)) =>
          scope.filter_map(id => {
            match id {
              Str(s) => {
                let id = s
                if !now.contains(id) && told.contains(id) {
                  Some(id)
                } else {
                  None
                }
              }
              _ => None
            }
          })
        _ => told.keys().to_array().filter(id => !now.contains(id))
      }
      for id in gone {
        let ws = place(told.get(id).unwrap())
        told.remove(id)
        self.emit(
          "chat-shared-removed",
          jo([("id", js(id))]),
          sees_to(("ws", ws)),
          of=shared_key(id, ws),
        )
      }
      done()
    })
  }
  match self.shared_reading {
    Some(waiters) => waiters.push(ok => if ok { go() } else { done() })
    None => go()
  }
}

///|
/// events.ts `handOver`, as this process stops: all being told told first, then nothing more; `done` given what is
/// written for the next (`pid`: this process's).
pub fn Events::hand_over(
  self : Events,
  pid : Int32,
  done : (Handed) -> Unit,
) -> Unit {
  if self.handed {
    return done(Nothing)
  }
  if self.usage_later is Some(stop) {
    stop()
    self.usage_later = None
    self.tell_usage()
  }
  let finish = () => {
    let listening = self.listening()
    let turn = !self.taking
    let at = (self.deps.now)()
    self.handed = true
    self.stop_timers()
    self.close_time()
    if !turn {
      return done(Nothing)
    }
    if !listening {
      return done(Removed)
    }
    let last : J = match self.last {
      None => Null
      Some((viewer, lang)) =>
        jo([("viewer", without(viewer.raw, "lockDevice")), ("lang", js(lang))])
    }
    let shared = if self.shared_told is Some(told) {
      Some(
        jo([
          ("rows", ja(told.iter().map(p => ja([js(p.0), js(p.1)])).to_array())),
          ("until", jn(at + kept_ms)),
        ]),
      )
    } else {
      None
    }
    let handed = jopt([
      ("pid", Some(jn(pid.to_double()))),
      ("at", Some(jn(at))),
      ("log", Some(self.log.kept())),
      (
        "overviews",
        Some(
          ja(
            self.overview_told
            .iter()
            .map(p => ja([js(p.0), js(p.1)]))
            .to_array(),
          ),
        ),
      ),
      ("last", Some(last)),
      ("shared", shared),
    ])
    done(Written(stringify(handed)))
  }
  if self.reading == 0 && !self.flushing {
    finish()
  } else {
    self.idle_waiters.push(finish)
  }
}
