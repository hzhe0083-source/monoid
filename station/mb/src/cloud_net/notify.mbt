// What the chats' people hear about while no client of theirs runs (station/src/cloud/notify.ts): noticed from the
// store's changes as they come, worked out by the readers, gathered over a second and posted to the control plane
// (ControlPlane::notify) a workspace at a time, signed with the station's key. Only what happens from now on is noticed.
// A batch that cannot be sent is dropped; an older cloud (404) has no pushes.

///|
/// Notices wait this long to go out together; at most this many in one post (the cloud takes no more).
pub let gather_ms : Int = 1_000

///|
pub let max_batch : Int = 50

///|
/// Minimum interval between pay-as-you-go fallback alerts for the same workspace and runtime (4 hours).
pub let billed_notify_cooldown_ms : Int64 = 14_400_000L

///|
/// Who wrote a message the station said itself (rows.ts `STATION_AUTHOR`).
pub let station_author : String = "station"

///|
/// A thread's entry as the store tells it changed.
pub(all) struct SaidEntry {
  n : Int64
  kind : String
  author_kind : String
  text : String?
  at : Int64
}

///|
pub fn SaidEntry::to_json(self : SaidEntry) -> Json {
  {
    "n": int_json(self.n),
    "kind": Json::string(self.kind),
    "authorKind": Json::string(self.author_kind),
    "text": match self.text {
      Some(t) => Json::string(t)
      None => Json::null()
    },
    "at": int_json(self.at),
  }
}

///|
/// What the store tells: a session's row changed, or a thread's entries came.
pub(all) enum StoreChange {
  SessionChanged(String)
  ThreadSaid(Int64, Array[SaidEntry])
}

///|
/// What the notifier asks of the station.
pub(all) struct NotifyParts {
  /// When a session's last turn ended (None: none ended).
  last_turn_ended : (String) -> Int64?
  /// Whether an agent leads the chat (its turns tell its leader, not people's phones).
  led : (String) -> Bool
  /// The workspace a session is of.
  session_ws : (String) -> String?
  subscribe : ((StoreChange) -> Unit) -> () -> Unit
  /// A read of the readers (`turnNotices`, `saidNotices`): its answer, or why it failed.
  read : (String, Json, (Result[Json, String]) -> Unit) -> Unit
  lang : () -> String
  /// Whether the station is in a workspace now (not removed, enrolled), its home one, and one it is in.
  enrolled : () -> Bool
  home : () -> String?
  member_of : (String) -> Bool
  /// Where a batch goes: the workspace's (None: the home one's), its outcome told.
  post : (Array[Json], String?, (Result[Unit, String]) -> Unit) -> Unit
  timers : After
  log : (String) -> Unit
}

///|
pub struct Notifier {
  priv parts : NotifyParts
  priv since : Int64
  /// Each session's last turn noticed (when it ended), so one turn is noticed once.
  priv ended : Map[String, Int64]
  /// Last time a billed-per-use fallback alert was accepted, by `<workspace>\0<runtime>`.
  priv billed_notified : Map[String, Int64]
  priv waiting : Array[Json]
  priv mut gathering : Bool
  priv mut stop : () -> Unit
  priv mut cancel : () -> Unit
}

///|
/// Noticing from now on (`now`, ms).
pub fn Notifier::new(parts : NotifyParts, now : Int64) -> Notifier {
  let n = {
    parts,
    since: now,
    ended: Map([]),
    billed_notified: Map([]),
    waiting: [],
    gathering: false,
    stop: fn() {  },
    cancel: fn() {  },
  }
  n.stop = (parts.subscribe)(change => match change {
    SessionChanged(key) => n.session_changed(key)
    ThreadSaid(thread, entries) => n.said(thread, entries)
  })
  n
}

///|
pub fn Notifier::close(self : Notifier) -> Unit {
  (self.stop)()
  (self.cancel)()
}

///|
/// A turn that ended since the last look: its chats hear how.
fn Notifier::session_changed(self : Notifier, key : String) -> Unit {
  guard (self.parts.last_turn_ended)(key) is Some(ended) else { return }
  if ended < self.since || self.ended.get(key) == Some(ended) {
    return
  }
  self.ended[key] = ended
  // A chat an agent leads tells its leader how its turns end, not its people's phones.
  if (self.parts.led)(key) {
    return
  }
  self.ask("turnNotices", {
    "key": Json::string(key),
    "since": int_json(self.since),
    "ended": Json::null(),
    "lang": Json::string((self.parts.lang)()),
  })
}

///|
/// People's messages and the station's ⚠️ in its own chats.
fn Notifier::said(self : Notifier, thread : Int64, entries : Array[SaidEntry]) -> Unit {
  let worth = entries
    .iter()
    .any(e => e.kind == "message" &&
      e.at >= self.since &&
      (e.author_kind == "person" ||
      (e.author_kind == station_author && e.text.unwrap_or("").has_prefix("⚠️"))))
  if worth {
    self.ask("saidNotices", {
      "thread": int_json(thread),
      "entries": Json::array(entries.map(e => e.to_json())),
      "since": int_json(self.since),
      "lang": Json::string((self.parts.lang)()),
    })
  }
}

///|
fn Notifier::ask(self : Notifier, op : String, args : Json) -> Unit {
  (self.parts.read)(op, args, r => match r {
    Ok(Array(a)) => self.queue(a)
    Ok(answer) => self.queue(array_of(field(answer, "notices")).unwrap_or([]))
    Err(e) => (self.parts.log)("a notice could not be made: \{e}")
  })
}

///|
/// Enqueues a manager-only push notice when sessions automatically fall back to a pay-as-you-go profile.
/// Returns true when accepted (member of workspace and outside the 4-hour cooldown).
pub fn Notifier::notify_billed_fallback(
  self : Notifier,
  workspace : String?,
  runtime : String,
  runtime_title : String,
  profile : String,
  title : String,
  at : Int64,
) -> Bool {
  let ws = match workspace {
    Some(w) => Some(w)
    None => (self.parts.home)()
  }
  guard ws is Some(ws) && (self.parts.member_of)(ws) else { return false }
  let k = "\{ws}\u{0}\{runtime}"
  match self.billed_notified.get(k) {
    Some(prev) if at - prev < billed_notify_cooldown_ms => return false
    _ => ()
  }
  self.billed_notified[k] = at
  self.queue([
    {
      "to": Json::array([]),
      "audience": Json::string("managers"),
      "kind": Json::string("billed"),
      "session": Json::string("billed:\{runtime}"),
      "thread": Json::number(0.0),
      "seq": Json::null(),
      "title": Json::string(title),
      "by": Json::string(runtime_title),
      "text": Json::string(profile),
      "at": int_json(at),
      "ws": Json::string(ws),
    },
  ])
  true
}

///|
/// Notices to go out with the next batch (tests and what the readers made).
pub fn Notifier::queue(self : Notifier, notices : Array[Json]) -> Unit {
  if notices.length() == 0 {
    return
  }
  self.waiting.append(notices)
  if self.gathering {
    return
  }
  self.gathering = true
  self.cancel = (self.parts.timers.after)(gather_ms, () => self.gathered())
}

///|
fn Notifier::gathered(self : Notifier) -> Unit {
  self.gathering = false
  let n = if self.waiting.length() < max_batch {
    self.waiting.length()
  } else {
    max_batch
  }
  let batch = self.waiting[:n].to_owned()
  let rest = self.waiting[n:].to_owned()
  self.waiting.clear()
  if rest.length() > 0 {
    self.queue(rest)
  }
  if !(self.parts.enrolled)() {
    return
  }
  // Each workspace's people hear of its own chats: one post a workspace, those of one the station is no longer in
  // dropped.
  let home = (self.parts.home)()
  let order : Array[String?] = []
  let by : Map[String, Array[Json]] = Map([])
  for notice in batch {
    let session = text_of(field(notice, "session")).unwrap_or("")
    let ws = match text_of(field(notice, "ws")) {
      Some(w) => Some(w)
      None =>
        match (self.parts.session_ws)(session) {
          Some(w) => Some(w)
          None => home
        }
    }
    guard ws is Some(ws) && (self.parts.member_of)(ws) else { continue }
    let of = if Some(ws) == home { None } else { Some(ws) }
    let key = of.unwrap_or("\u{0}home")
    if !by.contains(key) {
      order.push(of)
      by[key] = []
    }
    let wire = match notice {
      Object(m) if m.contains("ws") => {
        let copy = m.copy()
        copy.remove("ws")
        Json::object(copy)
      }
      other => other
    }
    by[key].push(wire)
  }
  for of in order {
    let notices = by[of.unwrap_or("\u{0}home")]
    (self.parts.post)(notices, of, r => match r {
      Ok(_) => (self.parts.log)("notices sent: \{notices.length()}")
      Err(e) => (self.parts.log)("notices dropped: \{notices.length()}: \{e}")
    })
  }
}
