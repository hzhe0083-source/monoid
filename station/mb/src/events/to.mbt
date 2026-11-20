// Who sees what of a station (station/src/api/events.ts `To`, `isFor`, `viewerKey`; store/rows.ts `sees`;
// mesh/credential.ts `readOnly`, `managesStation`): only workspaces are kept apart.

///|
/// A member as their credential says them (mesh/credential.ts `Viewer`): the object as it came, and what is read of it.
pub struct Viewer {
  raw : J
  sub : String
  email : String
  role : String
  workspace : String
  /// `home`: false for one of a workspace the station joined; absent (none) or true, its home one.
  home : Bool?
}

///|
pub fn Viewer::of(raw : J) -> Viewer {
  {
    raw,
    sub: str_prop(raw, "sub").unwrap_or(""),
    email: str_prop(raw, "email").unwrap_or(""),
    role: str_prop(raw, "role").unwrap_or(""),
    workspace: str_prop(raw, "workspace").unwrap_or(""),
    home: match raw.get("home") {
      Some(Bool(b)) => Some(b)
      _ => None
    },
  }
}

///|
/// credential.ts READ_ONLY_ROLES.
pub fn read_only(role : String) -> Bool {
  role == "viewer"
}

///|
pub fn manages_station(role : String) -> Bool {
  role == "owner" || role == "admin"
}

///|
/// store/rows.ts `sees`: a chat of workspace `ws` (null: the home one) is the viewer's.
pub fn sees(viewer : Viewer, ws : J) -> Bool {
  match ws {
    Str(s) => s == viewer.workspace
    Null => viewer.home != Some(false)
    _ => false
  }
}

///|
/// A workspace by its id or none (the home one), as `sees` takes it.
pub fn sees_ws(viewer : Viewer, ws : String?) -> Bool {
  match ws {
    Some(w) => w == viewer.workspace
    None => viewer.home != Some(false)
  }
}

///|
/// events.ts `viewerKey`: a viewer's streams in one language.
pub fn viewer_key(viewer : Viewer, lang : String) -> String {
  "\{viewer.email}\u{0}\{viewer.workspace}\u{0}\{lang}"
}

///|
/// What a viewer may see one of: a session, a thread, a job, or the chats of a workspace.
pub(all) enum Of {
  Session(String)
  Thread(J)
  Job(String)
  Ws(J)
}

///|
/// A `sees` of `To` as data: `{session}`, `{thread}`, `{job}` or `{ws}`, by which key it has (`"ws" in to.sees`).
fn of_sees(v : J) -> Of {
  if has(v, "ws") {
    Ws(v.get("ws").unwrap())
  } else if has(v, "session") {
    Session(string_of(v.get("session")))
  } else if has(v, "thread") {
    Thread(v.get("thread").unwrap())
  } else {
    Job(string_of(v.get("job")))
  }
}

///|
/// events.ts `isFor`: whether `to` is for a stream of `viewer`'s in `lang`. `seen`, whether its viewer sees a
/// session, a thread or a job (none: every one); `in_vault`, whether they are a member of a vault (none: of none).
pub fn is_for(
  to : J,
  viewer : Viewer,
  lang : String,
  seen : ((Viewer, Of) -> Bool)?,
  in_vault : ((Viewer, String) -> Bool)?,
) -> Bool {
  if to.get("lang") is Some(l) && text_of(Some(l)) != Some(lang) {
    return false
  }
  if to.get("viewer") is Some(k) &&
    text_of(Some(k)) != Some(viewer_key(viewer, lang)) {
    return false
  }
  if to.get("email") is Some(e) &&
    @jscase.lower(string_of(Some(e))) != @jscase.lower(viewer.email) {
    return false
  }
  if to.get("workspace") is Some(w) &&
    text_of(Some(w)) != Some(viewer.workspace) {
    return false
  }
  if to.get("subs") is Some(subs) {
    guard subs is Arr(subs) &&
      subs.iter().any(s => text_of(Some(s)) == Some(viewer.sub)) else {
      return false
    }
  }
  if to.get("readOnly") is Some(r) &&
    !(r is Bool(b) && b == read_only(viewer.role)) {
    return false
  }
  if to.get("managers") is Some(m) &&
    !(m is Bool(b) && b == manages_station(viewer.role)) {
    return false
  }
  if to.get("vault") is Some(v) {
    guard in_vault is Some(f) && f(viewer, string_of(Some(v))) else {
      return false
    }
  }
  if to.get("sees") is Some(s) {
    match of_sees(s) {
      Ws(ws) => if !sees(viewer, ws) { return false }
      of => if seen is Some(f) && !f(viewer, of) { return false }
    }
  }
  true
}
