// Which account a session runs on (station/src/sessions/accounts.ts): the pool's choice among the station's profiles,
// kept while usable, moved off one whose allowance ran out (another runtime's too, left to the station), and changed
// by hand (profile, model, effort, fast). How profiles are doing comes from outside (the accounts' checks and
// allowances: `set_health`); which ran into their allowance lately is kept here. The store, the hub's load and what a
// workspace may run on are the station's parts (backend.mbt); config.json is read once a call, as it cannot change
// within one.

///|
let spent_for_ms : Double = 3_600_000.0

///|
let compactions_over_ms : Double = 7.0 * 24.0 * 3_600_000.0

///|
let compactions_every_ms : Double = 3_600_000.0

///|
let calls_looked_at : Int = 200

///|
/// A model's own limit a turn ran into on an account: the model as the runtime named it, as the session ran it, when.
struct ModelSpent {
  named : String
  ran : String?
  at : Double
}

///|
/// What `limitAfter` found: the model whose own week is used up, a window of the account's, or nothing known.
pub(all) enum LimitAfter {
  OwnLimit(String)
  AccountLimit
  NotKnown
} derive(Eq, Show)

///|
pub struct SessionAccounts {
  b : Backend
  words : Words
  station_lang : String
  /// config.json as the hub reads it, now.
  config : async () -> HubConfig
  /// Its time.
  now : () -> Double
  /// Whether `allows` asks the station (a hub's `allows`); none: any.
  asks_allows : Bool
  /// Whether `moved` tells the station.
  tells_moved : Bool
  /// Whether `billedFallback` tells the station.
  tells_billed_fallback : Bool
  mut health : (String) -> Health
  mut check_again : async (String) -> Unit
  mut quota_again : async (String) -> Unit
  rechecking : Map[String, @effect.Deferred[Unit]]
  picked : Map[String, Double]
  spent : Map[String, Double]
  model_spent : Map[String, Array[ModelSpent]]
  scope_spent : Map[String, Double]
  mut compactions : (Double, Map[String, Double])?
  rt : @effect.Runtime
}

///|
pub fn SessionAccounts::new(
  b : Backend,
  words : Words,
  station_lang : String,
  config : async () -> HubConfig,
  now : () -> Double,
  rt : @effect.Runtime,
  asks_allows? : Bool = true,
  tells_moved? : Bool = true,
  tells_billed_fallback? : Bool = false,
) -> SessionAccounts {
  {
    b,
    words,
    station_lang,
    config,
    now,
    asks_allows,
    tells_moved,
    tells_billed_fallback,
    health: _ => Health::empty(),
    check_again: async fn(_) { () },
    quota_again: async fn(_) { () },
    rechecking: Map::new(),
    picked: Map::new(),
    spent: Map::new(),
    model_spent: Map::new(),
    scope_spent: Map::new(),
    compactions: None,
    rt,
  }
}

///|
/// `setHealth`.
pub fn SessionAccounts::set_health(
  self : SessionAccounts,
  health : (String) -> Health,
) -> Unit {
  self.health = health
}

///|
/// `setRecheck`.
pub fn SessionAccounts::set_recheck(
  self : SessionAccounts,
  recheck : async (String) -> Unit,
) -> Unit {
  self.check_again = recheck
}

///|
/// `setQuotaAgain`.
pub fn SessionAccounts::set_quota_again(
  self : SessionAccounts,
  read : async (String) -> Unit,
) -> Unit {
  self.quota_again = read
}

///|
fn profile_in(cfg : HubConfig, id : String) -> Profile? {
  cfg.profiles.iter().find_first(p => p.id == id)
}

///|
fn profile_model_of(cfg : HubConfig, id : String) -> String? {
  match profile_in(cfg, id) {
    Some(p) => p.model
    None => None
  }
}

///|
/// A model's name in words (`modelWords`).
fn model_words(m : String) -> Array[String] {
  let out = []
  let cur = StringBuilder::new()
  for c in lower(m) {
    if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') {
      cur.write_char(c)
    } else {
      let w = cur.to_string()
      if w != "" {
        out.push(w)
      }
      cur.reset()
    }
  }
  let w = cur.to_string()
  if w != "" {
    out.push(w)
  }
  out
}

///|
fn same_words(a : String, b : String) -> Bool {
  model_words(a).join(" ") == model_words(b).join(" ")
}

///|
/// `ownedBy`: a model's own window that `model` runs under.
fn owned_by(w : JV, model : String) -> Bool {
  match w.get("scope") {
    Some(Str(scope)) => {
      let mine = model_words(model_key(model))
      model_words(scope).iter().all(x => mine.contains(x))
    }
    _ => false
  }
}

///|
fn is_full(w : JV, now : Double) -> Bool {
  to_number(w.get("usedPercent")) >= 100.0 &&
  !(match w.get("resetsAt") {
    Some(Num(r)) => r <= now
    _ => false
  })
}

///|
/// `limitAfter`: what a turn on profile `id` running `model` ran into, its failure's words naming no limit.
pub async fn SessionAccounts::limit_after(
  self : SessionAccounts,
  id : String,
  model : String?,
) -> LimitAfter {
  (self.quota_again)(id) catch {
    _ => return NotKnown
  }
  let cfg = (self.config)()
  let now = (self.now)()
  let quota = self.health_of(cfg, id).quota
  if windows_of(self.quota_for_model(cfg, id, quota, model)).iter().any(w => is_full(w, now)) {
    return AccountLimit
  }
  let runs = match model {
    Some(m) => Some(m)
    None => profile_model_of(cfg, id)
  }
  guard runs is Some(runs) else { return NotKnown }
  if jget(quota, "state") != Some(Str("ok")) {
    return NotKnown
  }
  guard jget(quota, "scoped") is Some(Arr(scoped)) else { return NotKnown }
  match scoped.iter().find_first(w => is_full(w, now) && owned_by(w, runs)) {
    Some(w) => OwnLimit(js_string(w.get("scope")))
    None => NotKnown
  }
}

///|
/// `recheck`: profile `id` checked again, a runtime on it having failed to sign in (once at a time).
pub async fn SessionAccounts::recheck(self : SessionAccounts, id : String) -> Unit {
  match self.rechecking.get(id) {
    Some(busy) => {
      busy.wait()
      return
    }
    None => ()
  }
  let done : @effect.Deferred[Unit] = @effect.Deferred::new()
  self.rechecking[id] = done
  (self.check_again)(id) catch {
    _ => ()
  }
  self.rechecking.remove(id)
  ignore(done.succeed(()))
}

///|
/// `accountKey`: several profiles can spend the same account's allowance.
fn SessionAccounts::account_key(
  self : SessionAccounts,
  id : String,
  health? : Health,
) -> String {
  let h = match health {
    Some(h) => h
    None => (self.health)(id)
  }
  match h.account {
    Some(a) if a != "" => "account:\{a}"
    _ => "profile:\{id}"
  }
}

///|
/// `sameAccount`.
pub fn SessionAccounts::same_account(
  self : SessionAccounts,
  a : String,
  b : String,
) -> Bool {
  self.account_key(a) == self.account_key(b)
}

///|
/// `resetAllowance`: an explicit reset supersedes the failure which made this account unavailable to the pool.
pub fn SessionAccounts::reset_allowance(self : SessionAccounts, id : String) -> Unit {
  let key = self.account_key(id)
  self.spent.remove(key)
  self.model_spent.remove(key)
  for scope in ["gemini", "3p"] {
    self.scope_spent.remove("\{key}\u0000\{scope}")
  }
}

///|
fn SessionAccounts::has_agy_scopes(
  _self : SessionAccounts,
  cfg : HubConfig,
  id : String,
  quota : JV?,
) -> Bool {
  (match profile_in(cfg, id) {
    Some(p) => p.runtimes.contains("agy")
    None => false
  }) ||
  windows_of(quota).iter().any(w => w.get("scope") == Some(Str("gemini")) || w.get("scope") == Some(Str("3p")))
}

///|
/// `healthOf`.
pub fn SessionAccounts::health_of(
  self : SessionAccounts,
  cfg : HubConfig,
  id : String,
) -> Health {
  let base = (self.health)(id)
  let mut quota = base.quota
  let key = self.account_key(id, health=base)
  if key.has_prefix("account:") {
    for other in cfg.profiles {
      if other.id == id {
        continue
      }
      let candidate = (self.health)(other.id)
      if self.account_key(other.id, health=candidate) != key ||
        jget(candidate.quota, "state") != Some(Str("ok")) {
        continue
      }
      let checked = (q : JV?) => to_number(
        match jget(q, "checkedAt") {
          None | Some(Null) => Some(Num(0.0))
          x => x
        },
      )
      if jget(quota, "state") != Some(Str("ok")) ||
        checked(candidate.quota) > checked(quota) {
        quota = candidate.quota
      }
    }
  }
  let mut spent = base.spent
  match self.spent.get(key) {
    Some(at) => {
      let read_since = match jget(quota, "checkedAt") {
        Some(Num(c)) => c > at
        _ => false
      }
      if read_since || (self.now)() - at > spent_for_ms {
        self.spent.remove(key)
      } else {
        spent = true
      }
    }
    None => ()
  }
  { check: base.check, quota, account: base.account, spent }
}

///|
/// `healthFor`: how profile `id` is doing for running `model`.
fn SessionAccounts::health_for(
  self : SessionAccounts,
  cfg : HubConfig,
  id : String,
  model : String?,
) -> Health {
  let health = self.health_of(cfg, id)
  let quota = self.model_quota(cfg, id, health.quota, model)
  let scoped = { ..health, quota, }
  if self.scope_spent_at(cfg, id, model, None) is Some(_) ||
    self.model_spent_at(cfg, id, model, None) is Some(_) {
    { ..scoped, spent: true }
  } else {
    scoped
  }
}

///|
fn scope_of(w : JV) -> JV? {
  w.get("scope")
}

///|
/// `quotaForModel`: where windows are split by model group, only that group's weigh on `model`.
fn SessionAccounts::quota_for_model(
  _self : SessionAccounts,
  cfg : HubConfig,
  id : String,
  quota : JV?,
  model : String?,
) -> JV? {
  let wins = windows_of(quota)
  if wins.length() == 0 ||
    !wins.iter().any(w => scope_of(w) == Some(Str("gemini")) || scope_of(w) == Some(Str("3p"))) {
    return quota
  }
  let chosen = match model {
    Some(m) => Some(m)
    None => profile_model_of(cfg, id)
  }
  let want = agy_scope_for_model(chosen)
  let filtered = wins.filter(w => scope_of(w) is None || scope_of(w) == Some(Str(want)))
  if filtered.length() > 0 && filtered.length() != wins.length() {
    Some(jset(quota.unwrap(), "windows", jarr(filtered)))
  } else {
    quota
  }
}

///|
/// `modelQuota`: what weighs on `model` running on profile `id`, its own week under the account's among them.
fn SessionAccounts::model_quota(
  self : SessionAccounts,
  cfg : HubConfig,
  id : String,
  quota : JV?,
  model : String?,
) -> JV? {
  let q = self.quota_for_model(cfg, id, quota, model)
  let runs = match model {
    Some(m) => Some(m)
    None => profile_model_of(cfg, id)
  }
  guard runs is Some(runs) else { return q }
  if jget(quota, "state") != Some(Str("ok")) {
    return q
  }
  guard jget(quota, "scoped") is Some(Arr(scoped)) else { return q }
  let own = scoped.filter(w => owned_by(w, runs))
  if own.length() > 0 {
    let all = windows_of(q).copy()
    all.push_iter(own.iter())
    Some(jset(q.unwrap_or(Obj([])), "windows", jarr(all)))
  } else {
    q
  }
}

///|
/// `can`: whether profile `id` can run `model` now.
fn SessionAccounts::can(
  self : SessionAccounts,
  cfg : HubConfig,
  id : String,
  model : String?,
) -> Bool {
  usable(self.health_for(cfg, id, model), now=(self.now)())
}

///|
/// A session as the store has it (`SessionRow`), what is read of it here.
pub(all) struct Row {
  raw : JV
  key : String
  runtime : String
  profile : String
  profiles : Array[String]?
  pinned : Bool
  model : String?
  effort : String?
  runtime_session : String?
}

///|
pub fn Row::of_jv(v : JV) -> Row {
  {
    raw: v,
    key: js_string(v.get("key")),
    runtime: js_string(v.get("runtime")),
    profile: js_string(v.get("profile")),
    profiles: match v.get("profiles") {
      Some(Arr(a)) => Some(a.map(x => js_string(Some(x))))
      _ => None
    },
    pinned: is_truthy(v.get("profilePinned")),
    model: match v.get("model") {
      Some(Str(m)) => Some(m)
      _ => None
    },
    effort: match v.get("effort") {
      Some(Str(e)) => Some(e)
      _ => None
    },
    runtime_session: match v.get("runtimeSessionId") {
      Some(Str(s)) if s != "" => Some(s)
      _ => None
    },
  }
}

///|
async fn SessionAccounts::row(self : SessionAccounts, key : String) -> Row? {
  match json_to_jv(self.b.with_store(s => s.get_session(key))) {
    Obj(_) as r => Some(Row::of_jv(r))
    _ => None
  }
}

///|
/// `poolFor`: which of `candidates` session `row` may use.
fn SessionAccounts::supports_ultrafast(self : SessionAccounts, profile : Profile, model : String?) -> Bool {
  guard access_kind(profile.raw) == "subscription" else { return false }
  guard (match model { Some(_) => model; None => jstr(profile.get("model")) }) is Some(id) else { return false }
  match jget((self.health)(profile.id).check, "codexUltrafastModels") {
    Some(Arr(models)) => models.iter().any(m => match jstr(Some(m)) {
      Some(m) => same_model(m, id)
      None => false
    })
    _ => same_model(id, "gpt-6-astra") || same_model(id, "gpt-6.1-sol")
  }
}

///|
fn Row::ultrafast(self : Row) -> Bool {
  self.raw.get("speed") == Some(js("ultrafast"))
}

///|
fn SessionAccounts::pool_for(
  self : SessionAccounts,
  row : Row,
  candidates : Array[Profile],
  use_subset? : Bool = true,
) -> (Array[Profile], Array[String]?) {
  let requested = if use_subset { row.profiles } else { None }
  let subset = match requested {
    Some(list) => candidates.filter(p => list.contains(p.id))
    None => []
  }
  let kept = if subset.is_empty() { None } else { requested }
  let allowed = if kept is Some(_) { subset } else { candidates }
  let pool = if row.ultrafast() { allowed.filter(p => self.supports_ultrafast(p, row.model)) } else { allowed }
  (pool, kept)
}

///|
/// What workspace `key` may run on, asked once of each profile (`allows`).
async fn SessionAccounts::allowed(
  self : SessionAccounts,
  key : String,
  cfg : HubConfig,
) -> (Profile) -> Bool {
  let answers : Map[String, Bool] = Map::new()
  for p in cfg.profiles {
    let ok = p.enabled &&
      (
        !self.asks_allows ||
        self.b.ask("sessions.allows", [js(key), p.raw]) != Bool(false)
      )
    answers[p.id] = ok
  }
  p => answers.get(p.id).unwrap_or(false)
}

///|
/// `allows`: whether session `key` may run on `profile`.
pub async fn SessionAccounts::allows(
  self : SessionAccounts,
  key : String,
  profile : Profile,
) -> Bool {
  profile.enabled &&
  (
    !self.asks_allows ||
    self.b.ask("sessions.allows", [js(key), profile.raw]) != Bool(false)
  )
}

///|
/// `others`: the profiles session `row` could go on on other than its own, left to the station.
fn SessionAccounts::others(
  self : SessionAccounts,
  cfg : HubConfig,
  row : Row,
  allows : (Profile) -> Bool,
) -> Array[Profile] {
  guard runtime_kind(Some(Str(row.runtime))) is Some(runtime) else { return [] }
  if row.pinned {
    return []
  }
  let workspace_all = cfg.profiles.filter(p => p.runtimes.contains(runtime) && allows(p))
  let (all, _) = self.pool_for(row, workspace_all)
  let strict = all.iter().any(p => serves(p, row.model))
  all.filter(p => p.id != row.profile && (!strict || serves(p, row.model)))
}

///|
/// `scopeSpentAt`.
fn SessionAccounts::scope_spent_at(
  self : SessionAccounts,
  cfg : HubConfig,
  id : String,
  model : String?,
  health : Health?,
) -> Double? {
  let h = match health {
    Some(h) => h
    None => self.health_of(cfg, id)
  }
  if !self.has_agy_scopes(cfg, id, h.quota) {
    return None
  }
  let chosen = match model {
    Some(m) => Some(m)
    None => profile_model_of(cfg, id)
  }
  let k = "\{self.account_key(id, health=h)}\u0000\{agy_scope_for_model(chosen)}"
  guard self.scope_spent.get(k) is Some(at) else { return None }
  let read_since = match jget(h.quota, "checkedAt") {
    Some(Num(c)) => c > at
    _ => false
  }
  if read_since || (self.now)() - at > spent_for_ms {
    self.scope_spent.remove(k)
    return None
  }
  Some(at)
}

///|
/// `modelSpentAt`.
fn SessionAccounts::model_spent_at(
  self : SessionAccounts,
  cfg : HubConfig,
  id : String,
  model : String?,
  health : Health?,
) -> Double? {
  let h = match health {
    Some(h) => h
    None => self.health_of(cfg, id)
  }
  let key = self.account_key(id, health=h)
  let now = (self.now)()
  let quota = h.quota
  let read_since = (s : ModelSpent) => jget(quota, "state") == Some(Str("ok")) &&
    (match jget(quota, "checkedAt") {
      Some(Num(c)) => c > s.at
      _ => false
    }) &&
    (match jget(quota, "scoped") {
      Some(Arr(scoped)) =>
        scoped
        .iter()
        .any(w => match w.get("scope") {
          Some(Str(sc)) => same_words(sc, s.named)
          _ => false
        })
      _ => false
    })
  let kept = self.model_spent
    .get(key)
    .unwrap_or([])
    .filter(s => now - s.at <= spent_for_ms && !read_since(s))
  if kept.length() > 0 {
    self.model_spent[key] = kept
  } else {
    self.model_spent.remove(key)
  }
  let runs = match model {
    Some(m) => Some(m)
    None => profile_model_of(cfg, id)
  }
  let named = (s : ModelSpent) => match runs {
    None => s.ran is None
    Some(r) =>
      (match s.ran {
        Some(ran) => same_model(r, ran)
        None => false
      }) ||
      {
        let mine = model_words(model_key(r))
        model_words(s.named).iter().all(w => mine.contains(w))
      }
  }
  let matching = kept.filter(named)
  if matching.length() > 0 {
    Some(matching[matching.length() - 1].at)
  } else {
    None
  }
}

///|
/// `pick`: chooses the profile a session runs on (pool.mbt); `except`: the session it is chosen for, whose own process
/// is not counted.
pub async fn SessionAccounts::pick(
  self : SessionAccounts,
  cfg : HubConfig,
  candidates : Array[Profile],
  model : String?,
  strict : Bool,
  except? : String,
) -> Profile {
  let running = jitems(
    Some(
      self.b.ask("sessions.running", [
        match except {
          Some(e) => js(e)
          None => jundef
        },
      ]),
    ),
  ).map(x => js_string(Some(x)))
  let load : Map[String, Int] = Map::new()
  for id in running {
    let k = self.account_key(id)
    load[k] = load.get(k).unwrap_or(0) + 1
  }
  let profile = pick_profile(
    candidates,
    model,
    {
      health: id => self.health_for(cfg, id, model),
      load: id => load.get(self.account_key(id)).unwrap_or(0),
      last_picked: id => self.picked.get(self.account_key(id)).unwrap_or(0.0),
      now: self.now,
    },
    strict,
  )
  self.picked[self.account_key(profile.id)] = (self.now)()
  profile
}

///|
fn SessionAccounts::tr(
  self : SessionAccounts,
  lang : String,
  key : String,
  args? : Array[(String, String)] = [],
) -> String {
  self.words.tr(lang, key, args~)
}

///|
async fn SessionAccounts::log(
  self : SessionAccounts,
  message : String,
  fields : JV,
) -> Unit {
  ignore(self.b.ask("log.info", [js("hub"), js(message), fields]))
}

///|
async fn SessionAccounts::set_profile(
  self : SessionAccounts,
  key : String,
  id : String,
  kept : Array[String]?,
) -> Unit {
  let profiles : Json? = Some(
    match kept {
      Some(k) => Json::array(k.map(Json::string))
      None => Json::null()
    },
  )
  self.b.with_store(s => s.set_session_profile(key, Json::string(id), false, profiles))
}

///|
async fn SessionAccounts::moved(self : SessionAccounts, key : String, row : Row) -> Unit {
  if self.tells_moved {
    ignore(self.b.ask("sessions.moved", [js(key), row.raw]))
  }
}

///|
async fn SessionAccounts::billed_fallback(
  self : SessionAccounts,
  key : String,
  row : Row,
  runtime : String,
  next : Profile,
) -> Unit {
  if self.tells_billed_fallback {
    ignore(self.b.ask("sessions.billedFallback", [js(key), row.raw, js(runtime), next.raw]))
  }
}

///|
/// `runOn`: the profile a session's runtime starts on, asked again before each turn.
pub async fn SessionAccounts::run_on(
  self : SessionAccounts,
  key : String,
  holding? : Bool = false,
  quiet? : Bool = false,
  across? : Bool = false,
) -> Profile {
  guard self.row(key) is Some(row) else { raise plain_error("unknown session \{key}") }
  guard runtime_kind(Some(Str(row.runtime))) is Some(runtime) else {
    raise plain_error("session \{key} runs an unknown runtime \{row.runtime}")
  }
  let cfg = (self.config)()
  let allows = self.allowed(key, cfg)
  let all = cfg.profiles.filter(p => p.runtimes.contains(runtime))
  let workspace_candidates = all.filter(allows)
  let elsewhere = async fn(kept : Array[String]?) -> Profile? {
    if !across || row.pinned || kept is Some(_) || row.model is None {
      return None
    }
    self.take_across(
      cfg,
      key,
      row,
      None,
      "session taken on by another runtime's profile",
      quiet,
      allows,
    )
  }
  if workspace_candidates.length() == 0 {
    match elsewhere(None) {
      Some(p) => return p
      None => ()
    }
  }
  if workspace_candidates.length() == 0 && all.length() > 0 {
    raise plain_error(
      self.tr(self.station_lang, "station.session.noProfileHere", args=[
        ("runtime", runtime_label(runtime)),
      ]),
    )
  }
  let (candidates, kept_profiles) = self.pool_for(row, workspace_candidates)
  if row.ultrafast() && (candidates.is_empty() || (row.pinned && !candidates.iter().any(p => p.id == row.profile))) {
    raise plain_error(self.tr(self.station_lang, "station.speed.ultrafast_unavailable"))
  }
  let now = (self.now)()
  let next = match
    choose_run_on_profile(
      key,
      row,
      candidates,
      holding,
      crowded=p => urgency(self.health_for(cfg, p.id, row.model).quota, now).crowded,
      can=id => self.can(cfg, id, row.model),
      health_of=id => self.health_of(cfg, id),
      cheap_to_leave=async fn() { self.cheap_to_leave(key) },
      elsewhere=async fn() { elsewhere(kept_profiles) },
      pick=async fn(among) { self.pick(cfg, among, row.model, false) },
    ) {
    Stay(p) => return p
    Move(p) => p
  }
  if next.id != row.profile || kept_profiles != row.profiles {
    self.set_profile(key, next.id, kept_profiles)
    if next.id != row.profile {
      self.log(
        "session taken on by another profile",
        jobj([("session", js(key)), ("from", js(row.profile)), ("to", js(next.id))]),
      )
      if !quiet {
        self.moved(key, row)
        let prev = match candidates.iter().find_first(p => p.id == row.profile) {
          Some(c) => Some(c)
          None => profile_in(cfg, row.profile)
        }
        let prev_billed = match prev {
          Some(p) => billed_per_use(p.raw)
          None => false
        }
        if billed_per_use(next.raw) &&
          !prev_billed &&
          candidates.iter().any(p => !billed_per_use(p.raw)) {
          self.billed_fallback(key, row, runtime, next)
        }
      }
    }
  }
  next
}

///|
/// What `run_on` settles on: `Stay` keeps the session as it is, `Move` is a profile picked again (it may be the one it
/// was on).
priv enum RunOnChoice {
  Stay(Profile)
  Move(Profile)
}

///|
/// The choice `SessionAccounts::run_on` makes among `candidates`, apart from the store and the host: `crowded`, `can`
/// and `health_of` tell how each profile is doing for the session's model, `cheap_to_leave` whether the session loses
/// little by going on afresh, `elsewhere` a profile of another runtime it may be taken on by, `pick` the pool's pick.
async fn choose_run_on_profile(
  key : String,
  row : Row,
  candidates : Array[Profile],
  holding : Bool,
  crowded~ : (Profile) -> Bool,
  can~ : (String) -> Bool,
  health_of~ : (String) -> Health,
  cheap_to_leave~ : async () -> Bool,
  elsewhere~ : async () -> Profile?,
  pick~ : async (Array[Profile]) -> Profile,
) -> RunOnChoice {
  let current = candidates.iter().find_first(p => p.id == row.profile)
  let strict = candidates.iter().any(p => serves(p, row.model))
  let fits = (p : Profile) => !strict || serves(p, row.model)
  let keeps = match current {
    Some(c) => row.pinned || (can(c.id) && fits(c))
    None => false
  }
  let mut among = candidates
  match current {
    Some(c) if keeps => {
      if row.pinned {
        return Stay(c)
      }
      let paid = (p : Profile) => !billed_per_use(p.raw)
      let better = (p : Profile) => p.id != c.id &&
        fits(p) &&
        can(p.id) &&
        (if paid(p) == paid(c) { crowded(c) && !crowded(p) } else { paid(p) })
      among = candidates.filter(better)
      // Leaving a billed-per-use profile for a paid subscription happens on the next turn without waiting for
      // `cheap_to_leave`; moving off a crowded profile to an uncrowded one of the same tier still waits for
      // `cheap_to_leave`.
      let upgrading = !paid(c) && among.iter().any(paid)
      if among.length() == 0 || holding || (!upgrading && !cheap_to_leave()) {
        return Stay(c)
      }
    }
    _ => {
      let standing = (p : Profile) => if can(p.id) {
        2
      } else if signs_in(health_of(p.id)) {
        1
      } else {
        0
      }
      let fit = candidates.filter(fits)
      let best = js_max_of(fit.map(p => standing(p).to_double()))
      if best < 2.0 {
        match elsewhere() {
          Some(p) => return Stay(p)
          None => ()
        }
      }
      match current {
        Some(c) if fits(c) && standing(c).to_double() >= best => return Stay(c)
        _ => ()
      }
      if fit.length() > 0 {
        among = fit.filter(p => standing(p).to_double() == best)
      }
    }
  }
  if candidates.length() == 0 {
    raise plain_error("session \{key}: no profile runs \{row.runtime}")
  }
  Move(pick(among))
}

///|
/// `repick`: session `key` has its account picked again now, as a new session's would be.
pub async fn SessionAccounts::repick(self : SessionAccounts, key : String) -> Unit {
  guard self.row(key) is Some(row) else { raise plain_error("unknown session \{key}") }
  guard runtime_kind(Some(Str(row.runtime))) is Some(runtime) else {
    raise plain_error("session \{key} runs an unknown runtime \{row.runtime}")
  }
  let cfg = (self.config)()
  let allows = self.allowed(key, cfg)
  let workspace_candidates = cfg.profiles.filter(p => p.runtimes.contains(runtime) && allows(p))
  if workspace_candidates.length() == 0 {
    raise plain_error(
      self.tr(self.station_lang, "station.session.noProfileHere", args=[
        ("runtime", runtime_label(runtime)),
      ]),
    )
  }
  let (candidates, kept_profiles) = self.pool_for(row, workspace_candidates, use_subset=!row.pinned)
  if row.ultrafast() && candidates.is_empty() {
    raise plain_error(self.tr(self.station_lang, "station.speed.ultrafast_unavailable"))
  }
  let next = self.pick(cfg, candidates, row.model, false, except=key)
  self.set_profile(key, next.id, kept_profiles)
  if next.id != row.profile {
    self.log(
      "session's account picked again",
      jobj([("session", js(key)), ("from", js(row.profile)), ("to", js(next.id))]),
    )
  }
}

///|
/// `cheapToLeave`: whether session `key` loses little by going on afresh on another account.
async fn SessionAccounts::cheap_to_leave(self : SessionAccounts, key : String) -> Bool {
  let now = (self.now)()
  if self.b.with_store(s => s.recently_compacted(key)) {
    return true
  }
  let contexts = () => jitems(
      Some(json_to_jv(Json::array(self.b.with_store(s => s.last_contexts(key, calls_looked_at))))),
    ).map(c => {
      turn: c.get("turn").unwrap_or(Null),
      profile: match c.get("profile") {
        Some(Str(p)) => Some(p)
        _ => None
      },
      model: match c.get("model") {
        Some(Str(m)) => Some(m)
        _ => None
      },
      context: match c.get("context") {
        Some(Num(n)) => Some(n)
        _ => None
      },
    })
  if !self.b.with_store(s => s.compactions_ready()) {
    return cheap_to_leave(contexts(), Map::new())
  }
  let stale = match self.compactions {
    None => true
    Some((at, _)) => now - at > compactions_every_ms
  }
  if stale {
    let points : Map[String, Double] = Map::new()
    let got = json_to_jv(self.b.with_store(s => s.compaction_points(Json::number(now - compactions_over_ms))))
    match got {
      Arr(pairs) =>
        for p in pairs {
          let items = jitems(Some(p))
          points[js_string(items.get(0))] = to_number(items.get(1))
        }
      Obj(fields) => for f in fields { points[f.0] = to_number(Some(f.1)) }
      _ => ()
    }
    self.compactions = Some((now, points))
  }
  cheap_to_leave(contexts(), self.compactions.unwrap().1)
}

///|
/// `profile`: profile `id` as a session's runtime runs on it; None when the station no longer has it.
pub async fn SessionAccounts::profile(self : SessionAccounts, id : String) -> Profile? {
  profile_in((self.config)(), id)
}

///|
/// `spend`: a turn of the session ran into the allowance of `ran_on` (None: the session's own). The names of the one
/// left and the one taken when it moved; None when it is kept to its profile or none other can.
pub async fn SessionAccounts::spend(
  self : SessionAccounts,
  key : String,
  ran_on : String?,
  model? : String,
) -> (String, String)? {
  guard self.row(key) is Some(row) else { raise plain_error("unknown session \{key}") }
  let left = ran_on.unwrap_or(row.profile)
  let cfg = (self.config)()
  let now = (self.now)()
  let ran = match row.model {
    Some(m) => Some(m)
    None => profile_model_of(cfg, left)
  }
  let spend_model = (named : String) => {
    let k = self.account_key(left)
    let list = self.model_spent.get(k).unwrap_or([]).copy()
    list.push({ named, ran, at: now })
    self.model_spent[k] = list
  }
  match model {
    Some(m) => spend_model(m)
    None => {
      let q = self.health_of(cfg, left).quota
      let fresh = (w : JV) => match w.get("resetsAt") {
        Some(Num(r)) if r <= now => 0.0
        _ => {
          let n = to_number(w.get("usedPercent"))
          if n == 0.0 || n.is_nan() {
            0.0
          } else {
            n
          }
        }
      }
      let own = match ran {
        Some(r) if jget(q, "state") == Some(Str("ok")) =>
          match jget(q, "scoped") {
            Some(Arr(scoped)) => scoped.iter().find_first(w => owned_by(w, r))
            _ => None
          }
        _ => None
      }
      let used = [0.0]
      for w in windows_of(self.quota_for_model(cfg, left, q, ran)) {
        used.push(fresh(w))
      }
      let base_used = js_max_of(used)
      match own {
        Some(o) if fresh(o) >= 100.0 || (fresh(o) > base_used && base_used < 90.0) =>
          spend_model(js_string(o.get("scope")))
        _ =>
          if self.has_agy_scopes(cfg, left, q) {
            self.scope_spent["\{self.account_key(left)}\u0000\{agy_scope_for_model(ran)}"] = now
          } else {
            self.spent[self.account_key(left)] = now
          }
      }
    }
  }
  let name = (id : String) => match profile_in(cfg, id) {
    Some(p) => p.name
    None => id
  }
  if row.profile != left {
    return Some((name(left), name(row.profile)))
  }
  if row.pinned {
    return None
  }
  guard runtime_kind(Some(Str(row.runtime))) is Some(runtime) else { return None }
  let allows = self.allowed(key, cfg)
  let workspace_all = cfg.profiles.filter(p => p.runtimes.contains(runtime) && allows(p))
  let (all, kept_profiles) = self.pool_for(row, workspace_all)
  let strict = all.iter().any(p => serves(p, row.model))
  let candidates = all.filter(p => p.id != left &&
    (!strict || serves(p, row.model)) &&
    self.can(cfg, p.id, row.model))
  if candidates.length() == 0 {
    if kept_profiles is Some(_) {
      return None
    }
    let next = self.take_across(
      cfg,
      key,
      row,
      Some(left),
      "allowance ran out; session taken on by another runtime's profile",
      false,
      allows,
    )
    return match next {
      Some(n) => Some((name(left), n.name))
      None => None
    }
  }
  let next = self.pick(cfg, candidates, row.model, false)
  self.set_profile(key, next.id, kept_profiles)
  self.log(
    "allowance ran out; session taken on by another profile",
    jobj([("session", js(key)), ("from", js(left)), ("to", js(next.id))]),
  )
  self.moved(key, row)
  let prev_billed = match profile_in(cfg, left) {
    Some(p) => billed_per_use(p.raw)
    None => false
  }
  if billed_per_use(next.raw) &&
    !prev_billed &&
    all.iter().any(p => !billed_per_use(p.raw)) {
    self.billed_fallback(key, row, runtime, next)
  }
  Some((name(left), next.name))
}

///|
let context_runtimes : Array[String] = ["claude", "codex"]

///|
/// `takeAcross`: session `row`, left to the station, with no profile of its runtime able to run its model now, goes
/// on on a profile of another runtime that runs the same model and can now.
async fn SessionAccounts::take_across(
  self : SessionAccounts,
  cfg : HubConfig,
  key : String,
  row : Row,
  left : String?,
  said : String,
  quiet : Bool,
  allows : (Profile) -> Bool,
) -> Profile? {
  guard runtime_kind(Some(Str(row.runtime))) is Some(runtime) else { return None }
  if row.ultrafast() { return None }
  guard row.model is Some(model) else { return None }
  let candidates = cfg.profiles.filter(p => !p.runtimes.contains(runtime) &&
    allows(p) &&
    runs(p, model) &&
    self.can(cfg, p.id, Some(model)))
  if candidates.length() == 0 {
    return None
  }
  let next = self.pick(cfg, candidates, Some(model), true, except=key)
  guard next.runtimes.iter().find_first(r => r != runtime && runs(next, model))
    is Some(target) else {
    return None
  }
  let effort = match row.effort {
    Some(e) if self.model_efforts_in(cfg, target, Some(model), Pinned::None_, allows).contains(e) =>
      Some(e)
    _ => None
  }
  let fast = if fast_runtimes.contains(target) {
    match row.raw.get("fast") {
      None | Some(Null) => JV::Null
      Some(f) => f
    }
  } else {
    Null
  }
  let context = if context_runtimes.contains(target) {
    match row.raw.get("context") {
      None | Some(Null) => JV::Null
      Some(c) => c
    }
  } else {
    Null
  }
  match row.runtime_session {
    Some(rs) => self.b.with_store(s => s.ran_in(key, Json::string(rs), Json::string(row.profile)))
    None => ()
  }
  self.b.with_store(s => {
    s.set_session_runtime(
      key,
      Json::string(target),
      Json::string(next.id),
      false,
      Json::string(model),
      match effort {
        Some(e) => Json::string(e)
        None => Json::null()
      },
      Some(jv_to_json(fast)),
      jv_to_json(context),
      Some(Json::null()),
    )
  })
  self.b.with_store(s => s.set_session_context_before(key, Json::null()))
  self.log(
    said,
    jobj([
      ("session", js(key)),
      ("from", js(left.unwrap_or(row.profile))),
      ("to", js(next.id)),
      ("runtime", js(target)),
    ]),
  )
  if !quiet {
    self.moved(key, row)
    let prev = profile_in(cfg, left.unwrap_or(row.profile))
    if billed_per_use(next.raw) &&
      (match prev {
        Some(p) => !billed_per_use(p.raw)
        None => false
      }) {
      self.billed_fallback(key, row, runtime, next)
    }
  }
  Some(next)
}

///|
/// `acrossOthers`: the profiles of other runtimes session `row` could go on on.
fn SessionAccounts::across_others(
  self : SessionAccounts,
  cfg : HubConfig,
  row : Row,
  allows : (Profile) -> Bool,
) -> Array[Profile] {
  guard runtime_kind(Some(Str(row.runtime))) is Some(runtime) else { return [] }
  if row.pinned || row.ultrafast() {
    return []
  }
  guard row.model is Some(model) else { return [] }
  let workspace_all = cfg.profiles.filter(p => p.runtimes.contains(runtime) && allows(p))
  if self.pool_for(row, workspace_all).1 is Some(_) {
    return []
  }
  cfg.profiles.filter(p => !p.runtimes.contains(runtime) && allows(p) && runs(p, model))
}

///|
/// `refillsAt`: when session `key`, which ran into its allowance, is expected to run again.
pub async fn SessionAccounts::refills_at(self : SessionAccounts, key : String) -> Double {
  let now = (self.now)()
  guard self.row(key) is Some(row) else { return now + spent_for_ms }
  let cfg = (self.config)()
  let last = json_to_jv(self.b.with_store(s => s.last_turn(Json::string(key))))
  let ended = match jget(Some(last), "endedAt") {
    None | Some(Null) => now
    x => to_number(x)
  }
  let own = self.refill_of(cfg, row.profile, row.model, ended)
  let allows = self.allowed(key, cfg)
  let others = self.others(cfg, row, allows)
  others.push_iter(self.across_others(cfg, row, allows).iter())
  let candidates = others.filter(p => signs_in(self.health_of(cfg, p.id)))
  let times = [own]
  for p in candidates {
    times.push(
      if self.can(cfg, p.id, row.model) {
        now
      } else {
        self.refill_of(cfg, p.id, row.model, now)
      },
    )
  }
  js_min_of(times)
}

///|
/// `refillOf`: when profile `id`, unable to run `model` now, is expected to.
fn SessionAccounts::refill_of(
  self : SessionAccounts,
  cfg : HubConfig,
  id : String,
  model : String?,
  since : Double,
) -> Double {
  let now = (self.now)()
  let quota = self.model_quota(cfg, id, self.health_of(cfg, id).quota, model)
  let full = windows_of(quota).filter(w => to_number(w.get("usedPercent")) >= 100.0 &&
    (match w.get("resetsAt") {
      Some(Num(r)) => r > now
      _ => false
    }))
  if full.length() > 0 {
    return js_max_of(full.map(w => to_number(w.get("resetsAt"))))
  }
  let base = match self.spent.get(self.account_key(id)) {
    Some(at) => at
    None =>
      match self.scope_spent_at(cfg, id, model, None) {
        Some(at) => at
        None =>
          match self.model_spent_at(cfg, id, model, None) {
            Some(at) => at
            None => since
          }
      }
  }
  base + spent_for_ms
}

///|
/// `goesOnWith`: whether session `row`, waiting for an allowance, could go on once profile `id`'s is reset.
pub async fn SessionAccounts::goes_on_with(
  self : SessionAccounts,
  row : Row,
  id : String,
) -> Bool {
  if self.same_account(id, row.profile) {
    return true
  }
  let cfg = (self.config)()
  let allows = self.allowed(row.key, cfg)
  let others = self.others(cfg, row, allows)
  others.push_iter(self.across_others(cfg, row, allows).iter())
  others.iter().any(p => self.same_account(id, p.id))
}

///|
/// The profiles a session is kept to, as `modelEfforts` is given them.
pub(all) enum Pinned {
  None_
  One(String)
  Some_(Array[String])
}

///|
/// `modelEfforts`: the reasoning levels every eligible account that has said offers for a model.
pub async fn SessionAccounts::model_efforts(
  self : SessionAccounts,
  runtime : String,
  model : String?,
  pinned : Pinned,
  allowed? : (Profile) -> Bool = _ => true,
) -> Array[String] {
  self.model_efforts_in((self.config)(), runtime, model, pinned, allowed)
}

///|
fn SessionAccounts::model_efforts_in(
  self : SessionAccounts,
  cfg : HubConfig,
  runtime : String,
  model : String?,
  pinned : Pinned,
  allowed : (Profile) -> Bool,
) -> Array[String] {
  let kept : Array[String]? = match pinned {
    One(p) => Some([p])
    Some_(list) if list.length() > 0 => Some(list)
    _ => None
  }
  let profiles = cfg.profiles
    .filter(p => p.enabled && p.runtimes.contains(runtime) && allowed(p))
    .filter(p => match kept {
      None => true
      Some(k) => k.contains(p.id)
    })
    .filter(p => match model {
      None => true
      Some(m) => runs(p, m)
    })
  let catalog = (p : Profile) => match jget(self.health_of(cfg, p.id).check, "modelEfforts") {
    None | Some(Null) => None
    x => x
  }
  let model_of = (p : Profile) => match model {
    Some(m) => Some(m)
    None => p.model
  }
  let said = profiles.filter_map(p => reported_efforts(runtime, model_of(p), catalog(p)))
  common_efforts(
    if said.length() > 0 {
      said
    } else {
      profiles.map(p => available_efforts(runtime, model_of(p), catalog(p)))
    },
    runtime,
  )
}

///|
/// A field of a change: left out (undefined), null, or a value.
fn change_field(change : JV, k : String) -> JV? {
  match change.get(k) {
    Some(x) if is_undef(x) => None
    x => x
  }
}

///|
/// `nonEmpty`: undefined stays, null and "" are null.
fn non_empty_change(v : JV?) -> JV? {
  match v {
    None => None
    Some(Null) | Some(Str("")) => Some(Null)
    Some(x) => Some(x)
  }
}

///|
/// `change`: checks a change (configure) and works out what it makes of the session. Throws what is wrong with it,
/// in `lang`. What it comes to as JSON: `{row, runtime, model, effort, profile, profiles, pinned, repick}` (undefined
/// fields left out).
pub async fn SessionAccounts::change(
  self : SessionAccounts,
  key : String,
  change : JV,
  lang : String,
) -> JV {
  guard self.row(key) is Some(row) else { raise plain_error("unknown session \{key}") }
  guard runtime_kind(Some(Str(row.runtime))) is Some(runtime) else {
    raise plain_error("session \{key} runs an unknown runtime \{row.runtime}")
  }
  let name = runtime_label(runtime)
  let cfg = (self.config)()
  let t = (k : String, args : Array[(String, String)]) => self.tr(lang, k, args~)
  let profiles_given = change_field(change, "profiles")
  let norm_list : Array[String]?? = match profiles_given {
    None => None
    Some(Null) => Some(None)
    Some(list) => {
      let seen : Array[String] = []
      for x in jitems(Some(list)) {
        let s = trim_js(js_string(Some(x)))
        if s != "" && !seen.contains(s) {
          seen.push(s)
        }
      }
      Some(if seen.length() > 0 { Some(seen) } else { None })
    }
  }
  let profile_given = change_field(change, "profile")
  let repick_asked = change_field(change, "repick") == Some(Bool(true))
  // undefined: unchanged; Some(None): back to the station; Some(Some(id)): that one
  let wanted_single : String?? = if repick_asked &&
    (profile_given is None || profile_given == Some(Null)) &&
    norm_list is None {
    if row.pinned || profile_given == Some(Null) {
      Some(None)
    } else {
      None
    }
  } else {
    match non_empty_change(profile_given) {
      None => None
      Some(Null) => Some(None)
      Some(v) => Some(Some(js_string(Some(v))))
    }
  }
  let wanted_profiles : Array[String]?? = match norm_list {
    Some(l) => Some(l)
    None =>
      match wanted_single {
        Some(None) => Some(None)
        Some(Some(id)) => Some(Some([id]))
        None => None
      }
  }
  let new_model : String?? = match non_empty_change(change_field(change, "model")) {
    None => None
    Some(Null) => Some(None)
    Some(v) => Some(Some(js_string(Some(v))))
  }
  let new_effort : String?? = match non_empty_change(change_field(change, "effort")) {
    None => None
    Some(Null) => Some(None)
    Some(v) => Some(Some(js_string(Some(v))))
  }
  let allows = self.allowed(key, cfg)
  let fast = change_field(change, "fast")
  let context = change_field(change, "context")
  let context_given = match context {
    None | Some(Null) => false
    _ => true
  }
  let runtime_given = change_field(change, "runtime")
  match runtime_given {
    Some(rv) if js_string(Some(rv)) != row.runtime => {
      let asked = js_string(Some(rv))
      guard runtime_kind(Some(rv)) is Some(target) else {
        raise plain_error("unknown runtime \{asked}")
      }
      let model = match new_model {
        Some(m) => m
        None => None
      }
      let candidates = cfg.profiles.filter(p => p.runtimes.contains(target) && allows(p))
      if candidates.length() == 0 {
        raise plain_error(
          t("station.session.noProfileHere", [("runtime", runtime_label(target))]),
        )
      }
      match model {
        Some(m) if !candidates.iter().any(p => runs(p, m)) =>
          raise plain_error(
            t("station.session.noProfileForModel", [
              ("model", m),
              ("runtime", runtime_label(target)),
            ]),
          )
        _ => ()
      }
      let next_profiles : Array[String]? = match wanted_profiles {
        Some(Some(l)) => Some(l)
        _ => None
      }
      let pick = async fn(pool : Array[Profile]) {
        let eligible = if target == "codex" && change.get("speed") == Some(js("ultrafast")) {
          let eligible = pool.filter(p => self.supports_ultrafast(p, model))
          if eligible.is_empty() {
            raise plain_error(t("station.speed.ultrafast_unavailable", []))
          }
          eligible
        } else {
          pool
        }
        self.pick(cfg, eligible, model, true, except=key)
      }
      let picked = match next_profiles {
        Some(list) => {
          let subset = []
          for id in list {
            guard candidates.iter().find_first(p => p.id == id) is Some(found) else {
              raise plain_error("unknown profile \{id}")
            }
            match model {
              Some(m) if !runs(found, m) =>
                raise plain_error(
                  t("station.session.modelOff", [("profile", found.name), ("model", m)]),
                )
              _ => ()
            }
            subset.push(found)
          }
          if subset.length() == 1 {
            subset[0]
          } else {
            pick(subset)
          }
        }
        None => pick(candidates)
      }
      let effort = match new_effort {
        Some(e) => e
        None => None
      }
      match effort {
        Some(e) => {
          let efforts = self.model_efforts_in(
            cfg,
            target,
            model,
            match next_profiles {
              Some(l) => Some_(l)
              None => None_
            },
            allows,
          )
          if !efforts.contains(e) {
            raise plain_error(
              t("station.profile.efforts", [
                ("runtime", runtime_label(target)),
                ("efforts", efforts.join(t("station.list.separator", []))),
              ]),
            )
          }
        }
        None => ()
      }
      match fast {
        None | Some(Null) => ()
        Some(_) =>
          if !fast_runtimes.contains(target) {
            raise plain_error(t("station.session.fastOpenAiOnly", []))
          }
      }
      if context_given && !context_runtimes.contains(target) {
        raise plain_error(t("station.session.contextRuntimes", []))
      }
      return jobj([
        ("row", row.raw),
        ("runtime", js(target)),
        ("model", jopt(model)),
        ("effort", jopt(effort)),
        ("profile", js(picked.id)),
        (
          "profiles",
          match next_profiles {
            Some(l) => jstrs(l)
            None => Null
          },
        ),
        (
          "pinned",
          jbool(
            match next_profiles {
              Some(l) => l.length() == 1
              None => false
            },
          ),
        ),
        ("repick", jbool(false)),
      ])
    }
    _ => ()
  }
  match fast {
    None | Some(Null) => ()
    Some(_) =>
      if !fast_runtimes.contains(runtime) {
        raise plain_error(t("station.session.fastOpenAiOnly", []))
      }
  }
  if context_given && !context_runtimes.contains(runtime) {
    raise plain_error(t("station.session.contextRuntimes", []))
  }
  match wanted_profiles {
    Some(Some(list)) => {
      let model = match new_model {
        Some(m) => m
        None => row.model
      }
      for id in list {
        guard profile_in(cfg, id) is Some(next) else {
          raise plain_error("unknown profile \{id}")
        }
        if !next.enabled {
          raise plain_error(t("station.profile.disabled", [("profile", next.name)]))
        }
        if !next.runtimes.contains(runtime) {
          raise plain_error(
            t("station.profile.cannotRun", [("profile", next.name), ("runtime", name)]),
          )
        }
        if !allows(next) {
          raise plain_error(t("station.profile.notHere", [("profile", next.name)]))
        }
        match model {
          Some(m) if !runs(next, m) =>
            raise plain_error(
              t("station.session.modelOff", [("profile", next.name), ("model", m)]),
            )
          _ => ()
        }
      }
    }
    _ => ()
  }
  let mut model = match new_model {
    Some(m) => m
    None => row.model
  }
  let remodel = match (model, row.model) {
    (Some(a), Some(b)) => !same_model(a, b)
    (a, b) => a != b
  }
  if !remodel {
    model = row.model
  }
  let effort = match new_effort {
    Some(e) => e
    None => if remodel { None } else { row.effort }
  }
  match (new_model, model) {
    (Some(Some(_)), Some(m)) =>
      if !cfg.profiles.iter().any(p => p.runtimes.contains(runtime) && allows(p) && runs(p, m)) {
        raise plain_error(
          t("station.session.noProfileForModel", [("model", m), ("runtime", name)]),
        )
      }
    _ => ()
  }
  let remodel_profiles = () => {
    if row.pinned {
      return None
    }
    match row.profiles {
      None => None
      Some(list) if list.length() == 0 => None
      Some(list) => {
        let kept = list.filter(id => match profile_in(cfg, id) {
          Some(p) =>
            p.runtimes.contains(runtime) &&
            allows(p) &&
            (match model {
              None => true
              Some(m) => runs(p, m)
            })
          None => false
        })
        if kept.length() > 0 {
          Some(kept)
        } else {
          None
        }
      }
    }
  }
  let next_profiles : Array[String]?? = match wanted_profiles {
    Some(w) => Some(w)
    None => if remodel { Some(remodel_profiles()) } else { None }
  }
  match effort {
    Some(e) if new_effort is Some(_) || wanted_profiles is Some(_) || remodel => {
      let effective : Pinned = match next_profiles {
        Some(Some(l)) => Some_(l)
        Some(None) => None_
        None =>
          match row.profiles {
            Some(l) => Some_(l)
            None => if row.pinned { One(row.profile) } else { None_ }
          }
      }
      let efforts = self.model_efforts_in(cfg, runtime, model, effective, allows)
      if !efforts.contains(e) {
        raise plain_error(
          t("station.profile.efforts", [
            ("runtime", name),
            ("efforts", efforts.join(t("station.list.separator", []))),
          ]),
        )
      }
    }
    _ => ()
  }
  let profile : JV? = match next_profiles {
    None => None
    Some(Some(l)) if l.length() == 1 => Some(js(l[0]))
    Some(_) => Some(Null)
  }
  let can_repick = repick_asked &&
    (match next_profiles {
      None => !row.pinned
      Some(None) => true
      Some(Some(l)) => l.length() > 1
    })
  let fields = [
    ("row", row.raw),
    ("runtime", js(runtime)),
    ("model", jopt(model)),
    ("effort", jopt(effort)),
  ]
  match profile {
    Some(p) => fields.push(("profile", p))
    None => ()
  }
  match next_profiles {
    Some(Some(l)) => fields.push(("profiles", jstrs(l)))
    Some(None) => fields.push(("profiles", Null))
    None => ()
  }
  fields.push(("repick", jbool(can_repick)))
  jobj(fields)
}
