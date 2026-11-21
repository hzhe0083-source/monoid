// What a station's own page (station_node.mbt, one in every frame: web/src/cloud/StationPage.tsx) works out of what the
// core says, and what it does, apart from its nodes: the facts under its name, a made-up one in its bones, its ⋯'s
// items, renaming and removing it, its profiles' panel, its agents' variables as they are written, a cold machine's
// amount. Its old view is gone: every frame and a chat's side panel make the page once (2026-11-17).

///|
fn station_page_reset() -> Unit {
  env_forms.clear()
  env_forms_made.val = 0
  env_drafts.clear()
  station_env_open.clear()
  rs_shown.clear()
}

///|
let station_env_open : @sf.LiveMap[String, Bool] = @sf.LiveMap::new()

///|
/// The page's parts (Body's PARTS), in order.
// kept across runs: a table, never written
let station_part_names : Array[String] = ["overview", "processes", "settings"]

///|
fn station_head_facts(s : Json?) -> String {
  let host = field(s, "host")
  let details = items(host, "details")
  let uptime = match details.iter().find_first(fn(d) { text(Some(d), "label") == "已运行" }) {
    Some(d) if text(Some(d), "value") != "" => "已运行 " + text(Some(d), "value")
    _ => ""
  }
  let facts = [text(host, "identity")]
  if uptime != "" {
    facts.push(uptime)
  } else if text(s, "version") != "" {
    facts.push("Station " + text(s, "version"))
  }
  facts.push(joined_text(s))
  join(facts, " · ")
}

///|
fn station_env_summary(env : Array[Json]) -> String {
  if env.length() == 0 {
    return "未设置"
  }
  let keys = env.map(fn(e) { text(Some(e), "key") }).filter(fn(k) { k != "" })
  join(keys, ", ") + " · " + env.length().to_string() + " 个变量"
}

///|
/// The viewer's role in the workspace in view.
fn role_of(core : Core, here : Here) -> String {
  text(workspace_view(core, here).value, "role")
}

///|
/// A station made up, for what its page shows while the stations are read (station_view_node in its bones): its head, the
/// machine's figures, a few profiles.
fn station_sample() -> Json {
  let w = fn(n : Int) { Json::string(@sf.sample_words(n)) }
  let meter = fn(left : Int) -> Json { { "big": w(2), "unit": "%", "left": Json::number(left.to_double()), "level": "ok", "title": w(4), "total": w(5) } }
  let profile = fn(i : Int, n : Int) -> Json { { "id": Json::string("sample" + i.to_string()), "name": w(n), "modelsText": w(12) } }
  {
    "station": "sample",
    "name": w(5),
    "online": true,
    "version": w(4),
    "host": { "identity": w(10), "meters": [meter(70), meter(40), meter(60)] },
    "overview": { "profiles": [profile(0, 7), profile(1, 9), profile(2, 6)] },
    "profileGroups": [{ "group": "claude", "title": w(6), "profiles": ["sample0", "sample1", "sample2"], "attention": 0 }],
  }
}

///|
/// Where a station another workspace lent is from: its home workspace's name, else that
/// it is another's; "" for one whose home is here.
fn joined_text(s : Json?) -> String {
  if !flag(s, "joined") {
    return ""
  }
  match opt_text(s, "home") {
    Some(h) => @sf.t("web-pages.stations.joinedFrom", args=[("name", h)])
    None => @sf.t("web-pages.stations.joinedElsewhere")
  }
}

///|
/// Its name asked anew (RenameStationDialog), kept when it changed (`workspace.renameStation`).
fn station_rename(core : Core, here : Here, s : Json?) -> Unit {
  let name = text(s, "name")
  guard flag(s, "online") else { @settings.mark_offline(core, name) }
  ask(@sf.t("web-pages.settings.stations.rename"), name, @sf.t("web-pages.settings.stations.namePrompt"), @sf.t("common.save"), fn(
    line,
  ) {
    let to = line.trim(chars=" \t\n").to_owned()
    if to != "" && to != name {
      @settings.act(
        core,
        @sf.t("android-settings.station.renameWhat"),
        "workspace.renameStation",
        obj([("workspace", str(here.workspace)), ("station", str(text(s, "id"))), ("name", str(to)), ("account", str(here.sub))]),
        done=@sf.t("android-settings.renamed"),
      )
    }
  })
}

///|
/// What its ⋯ holds (station_menu's): renaming it, restarting it while it is online, its things moved to another station
/// (station_move_item's), its chats moved away and it taken out (station_retire_item's), removing it (asked first).
fn station_menu_items(core : Core, here : Here, s : Json?) -> Array[@sf.MenuItem?] {
  let address = text(s, "station")
  let remove = fn() { station_remove_ask(core, here, s) }
  // (what is done with it, those it offers now; a line; then what takes it away)
  let items : Array[@sf.MenuItem?] = [
    Some(@sf.menu_item_of(@sf.t("web-pages.settings.stations.rename"), icon="edit", fn() { station_rename(core, here, s) })),
  ]
  if flag(s, "online") {
    items.push(
      Some(@sf.menu_item_of(@sf.t("web-pages.settings.stations.restart"), icon="power", fn() {
        @settings.act(core, @sf.t("web-pages.settings.stations.restartWhat"), "station.restart",
          obj([("station", str(address))]), done=@sf.t("web-pages.settings.stations.restarting"))
      })),
    )
  }
  // made one that only runs tasks by who added it or a workspace owner or admin, whose rig it then is (`mine`: the
  // core says, false for a plain member's view of a station another added; asked first, with how many chats it holds
  // go out of sight): its own station asked, so only while it is up; one of another workspace's stays whole
  if flag(s, "mine") && flag(s, "online") && !flag(s, "joined") {
    items.push(
      // (not again while it is under way: the station and the cloud asked once)
      Some(@sf.menu_item_of(@sf.t("web-pages.rigs.toTasks"), icon="boxes", disabled=is_doing(core, ["rig.setMode"], [("station", text(s, "id"))]), fn() {
        let chats = number(field(field(s, "overview"), "counts"), "sessions").to_int()
        confirm(
          @sf.t("web-pages.rigs.toTasksAsk", args=[("name", text(s, "name"))]),
          if chats > 0 { @sf.t("web-pages.rigs.toTasksNote", args=[("n", chats.to_string())]) } else { @sf.t("web-pages.rigs.toTasksNoteNone") },
          @sf.t("web-pages.rigs.toTasks"),
          fn() {
            @settings.act(
              core,
              @sf.t("web-pages.rigs.toTasks"),
              "rig.setMode",
              obj([("workspace", str(here.workspace)), ("station", str(text(s, "id"))), ("mode", str("tasks"))]),
              done=@sf.t("web-pages.rigs.toTasksDone"),
            )
          },
        )
      })),
    )
  }
  match station_move_item(core, s) {
    Some(item) => items.push(Some(item))
    None => ()
  }
  items.push(None)
  match station_retire_item(core, here, s) {
    Some(item) => items.push(Some(item))
    None => ()
  }
  items.push(Some(@sf.menu_item_of(@sf.t("web-pages.settings.stations.remove"), icon="trash", danger=true, remove)))
  items
}

///|
let st_row_glyph : Double = 16.0

///|
/// One account kind, with its live profiles and their allowances, in a panel opened `from` what was pressed (a sheet
/// from the foot on 小屏, beside it on 中屏 and 大屏), made once as nodes (@sf.panel_nodes, station_kind_node). A long
/// kind (`many`: its list scrolls, a share of the window tall) can be searched without leaving it.
fn station_profiles_panel(
  core : Core,
  here : Here,
  address : String,
  kind : String,
  title : String,
  from : @sf.Anchor,
  many : Bool,
) -> Unit {
  @sf.panel_nodes(
    title,
    fn(v, close) { station_kind_node(v, core, here, address, kind, many, close) },
    from~,
    tall=if many { 0.85 } else { 0.0 },
    grows=many,
  )
}

///|
/// What one account kind's panel holds (station_profiles_panel), in node `v` (its body), as station `address` says now
/// (its own ask, held while the panel is up): a search over its accounts while it has as many as a pick searches
/// (pick_search_from) or words are in it, then its accounts it finds, a row each by its id (View::each; a long
/// list's rows made as they show, panel_list_node, where `many`), coming and going as the station lists them; none
/// found, a line saying so. A row pressed closes the panel (`close`) for its account's page. Once the station said
/// the kind and says it no more, the panel closes (`close`, as that is said), showing what it showed last till it is
/// gone; while the station is not said yet, or never said the kind, it stays.
fn station_kind_node(
  v : @view.View,
  core : Core,
  here : Here,
  address : String,
  kind : String,
  many : Bool,
  close : () -> Unit,
) -> Unit {
  let query = @ui.Field::new()
  let group_in = fn(s : Json?) { items(s, "profileGroups").iter().find_first(fn(g) { text(Some(g), "group") == kind }) }
  let said = fn() { @settings.station_of(core, here, address) }
  // (the kind gone: the panel closes, what it showed last kept as it goes, not emptied under it)
  let last : Ref[Json?] = Ref(None)
  let now = fn() {
    let s = said()
    match s {
      Some(_) if group_in(s) is None && last.val is Some(_) => last.val
      _ => {
        if group_in(s) is Some(_) {
          last.val = s
        }
        s
      }
    }
  }
  // (closed as a kind the station said comes to be gone: said once, as it does; while the station is not said, or
  // the kind never was, nothing)
  let had = Ref(false)
  v.reacts(
    fn() {
      let s = said()
      match s {
        None => 0
        Some(_) => if group_in(s) is Some(_) { 1 } else { 2 }
      }
    },
    fn(says) {
      if says == 1 {
        had.val = true
      } else if says == 2 && had.val {
        close()
      }
    },
  )
  let ids = fn() { strings(group_in(now()), "profiles") }
  let searched = fn() { ids().length() >= @sf.pick_search_from || query.text() != "" }
  // (its accounts it lists that the station has, in its order, those the search's words are in)
  let found = fn() {
    let words = if searched() { query.text().trim().to_owned().to_lower() } else { "" }
    // (its accounts by id once, the first of an id as the station lists them, not looked for again for each)
    let profiles : Map[String, Json] = Map([])
    for p in items(field(now(), "overview"), "profiles") {
      let id = text(Some(p), "id")
      if !profiles.contains(id) {
        profiles[id] = p
      }
    }
    let out : Array[String] = []
    for id in ids() {
      match profiles.get(id) {
        Some(p) => {
          let hay = (text(Some(p), "name") + "\n" + text(Some(p), "email")).to_lower()
          if words == "" || hay.contains(words) {
            out.push(id)
          }
        }
        None => ()
      }
    }
    out
  }
  // (each account and how its check stands kept by its id once, so a row is told only as its own changes: View::keyed_by)
  let profiles_by = v.keyed_by(fn() { items(field(now(), "overview"), "profiles") }, fn(p) { text(Some(p), "id") })
  let states_by = v.keyed_by(
    fn() {
      match field(now(), "profileStates") {
        Some(Object(m)) => m.to_array()
        _ => []
      }
    },
    fn(e) { e.0 },
  )
  let profile = fn(id : String) { profiles_by.get(id) }
  let state = fn(id : String) { states_by.get(id).map(fn(e) { e.1 }) }
  let row = fn(b : @view.View, id : String) {
    station_profile_row_node(b, core, address, id, fn() { profile(id) }, fn() { state(id) }, close)
  }
  v.show(searched, fn(s) {
    @sf.style_node(s, fn() { @sf.panel_words_in_node(s).then(st_profiles_search) })
    let f = @sf.input_node(s, query, placeholder=@sf.t("common.search"), small=true)
    // (a long kind's: the keys there as it opens beside what opened it, not on a sheet)
    if many {
      @sf.panel_search_at_hand_node(f)
    }
  })
  v.show(fn() { found().is_empty() }, fn(n) { @sf.panel_note_node(n, fn() { @sf.t("common.noMatch") }) })
  if many {
    @sf.panel_list_node(v, found, row, est=st_profile_row_est) |> ignore
  } else {
    v.box(fn(rows) {
      @sf.style_node(rows, fn() { st_profiles_rows })
      rows.each(found, fn(id) { id }, fn(r, id) { row(r, id.untracked()) })
    })
    |> ignore
  }
}

///|
/// An account's row (`id`, `p` as the station says it now, `state` how its check stands) in `b`: its name, its models
/// and how many use it, its maker's mark before them; its allowance's chips under them while the core can say it; a
/// pill at its end where its check (or the station's word on it) is not well. Pressed, the panel closes (`close`) for
/// its page.
fn station_profile_row_node(
  b : @view.View,
  core : Core,
  address : String,
  id : String,
  p : () -> Json?,
  state : () -> Json?,
  close : () -> Unit,
) -> Unit {
  let facts = fn() {
    let used = items(p(), "usedBy").length()
    let facts = [text(p(), "modelsText")]
    if used > 0 {
      facts.push(@sf.t("web-pages.settings.profiles.usedBy", args=[("n", used.to_string())]))
    }
    join(facts, " · ")
  }
  // (its check's words and tone, the station's own where it says any)
  let check = fn() {
    let st = state()
    if text(st, "text") != "" {
      (text(st, "text"), text(st, "tone"))
    } else {
      (text(p(), "checkText"), text(p(), "checkTone"))
    }
  }
  @sf.link_row_node(
    b,
    fn() { text(p(), "name") },
    fn() {
      close()
      (core.push)(Profile(address, id))
    },
    note=facts,
    lead=LeadLine(fn(l) {
      l.box(fn(m) {
        @sf.style_node(m, fn() { st_profile_mark.then(@sf.row_lead_out_node(m)) })
        m.pick(fn() { (text(p(), "runtime"), text(field(p(), "access"), "kind"), text(p(), "providerMark")) }, fn(k, mk) {
          @sf.provider_logo_node(k, mk.0, mk.1, st_profile_glyph, mk.2) |> ignore
        })
      })
      |> ignore
    }),
    below=fn(q) { @sf.quota_lines_node(q, fn() { field(p(), "quota") }, small=true, in_row=true) },
    below_open=fn() { if text(field(p(), "quota"), "state") == "ok" { 1.0 } else { 0.0 } },
    tail=fn(e) {
      e.pick(check, fn(k, c) {
        @sf.pill_node(k, fn() { c.0 }, tone=match c.1 {
          "red" => Red
          "amber" => Amber
          "blue" => Blue
          _ => Neutral
        })
        |> ignore
      })
    },
    tail_shown=fn() {
      let (status, tone) = check()
      tone != "green" && status != ""
    },
  )
}

///|
// kept across runs: a value (no field of it changes)
let st_profiles_rows : @ui.Style = @ui.css("w=Full gap=SPx")

///|
// kept across runs: a value (no field of it changes)
let st_profiles_search : @ui.Style = @ui.css("w=Full pt=S1 pb=S2_5")

///|
/// A long list's first estimate; its rows say their actual heights as they are laid out.
let st_profile_row_est : Double = 84.0

// ── Settings ────────────────────────────────────────────────────────────

///|
/// A grant's mark: the screen's two by what they do, the folders by what they
/// hold, the LAN by the devices on it.
fn grant_icon(id : String) -> String {
  match id {
    "capture" => "monitor"
    "control" => "cursor"
    "documents" => "file-text"
    "downloads" => "download"
    "removable" => "disk"
    "network" => "server"
    "localNetwork" => "devices"
    _ => "folder"
  }
}

///|
/// How many of a person's own pages a station's browser has, as its row says it: none, nothing.
fn browser_tabs_note(n : Int) -> String {
  if n == 0 {
    ""
  } else {
    @sf.t("web-pages.screen.tabsCount", args=[("count", "\{n}")])
  }
}

///|
/// A screen the core links to, opened as the core reads its link (`link.parse`).
fn open_screen_link(core : Core, link : String) -> Unit {
  (core.call)("link.parse", obj([("url", str(link))]), fn(r) {
    match r {
      Ok(Object(_) as v) if text(Some(v), "opens") == "screen" =>
        @sfbase.open_page(Screen({ station: text(Some(v), "station"), screen: text(Some(v), "screen"), title: "", until_gone: false }))
      _ => ()
    }
  })
}

///|
/// The draft of a station's variables open while the page shows it, by station (its form's key).
// kept across runs: said as the page opens one; station_page_reset empties it
let env_forms : Map[String, String] = Map([])

///|
// kept across runs: counted as forms are opened; station_page_reset puts it back
let env_forms_made : Ref[Int] = Ref(0)

///|
/// The shared draft, independent of the editor and its page's layout and selection.
priv struct EnvDraft {
  pending : @signals.Signal[String?]
  reset : @signals.Signal[Int]
  mut source : String?
  mut sent : String?
}

///|
// kept across runs: made as a station's page opens its draft; station_page_reset empties it
let env_drafts : Map[String, EnvDraft] = Map([])

///|
/// Sends one value of the shared variables draft to the core.
fn station_env_edit(core : Core, address : String, form : String, typed : String) -> Unit {
  @settings.act(
    core,
    @sf.t("web-pages.stations.agentEnvEdit"),
    "agentEnv.form.edit",
    obj([("station", str(address)), ("form", str(form)), ("input", obj([("text", str(typed))]))]),
  )
}

///|
let env_placeholder : String = "HTTPS_PROXY=http://127.0.0.1:7890\nNO_PROXY=localhost,.internal"

///|
/// The threshold can be any non-negative, finite amount, including zero.
fn station_cold_amount(words : String) -> Double? {
  match (try Some(@json.parse(words.trim(chars=" \t\n").to_owned())) catch { _ => None }) {
    Some(Number(v, ..)) if v >= 0.0 && !v.is_inf() && !v.is_nan() => Some(v)
    _ => None
  }
}

///|
/// A custom threshold is entered in its own editor, keeping the words being typed there.
fn station_cold_custom(core : Core, address : String, cost : Double) -> Unit {
  let field_ = @ui.Field::new(text=cost.to_string())
  let title = @sf.t("web-pages.stations.context.threshold")
  let amount = fn() { station_cold_amount(field_.text()) }
  open_dialog_nodes(
    @sf.t("web-pages.stations.context.customAmount"),
    fn(v, _) {
      @sf.field_node(v, fn() { title }, hint=fn() { @sf.t("web-pages.stations.context.amountHint") }, fn(f) {
        @sf.input_node(f, field_, placeholder=title, label=title) |> ignore
      })
    },
    fn(v, shut) {
      @sf.button_node(v, fn() { @sf.t("common.cancel") }, shut, tone=Ghost) |> ignore
      @sf.button_node(
        v,
        fn() { @sf.t("common.save") },
        fn() {
          match amount() {
            Some(a) => {
              @settings.act(core, @sf.t("web-pages.stations.context.what"), "context.setAfresh", obj([("station", str(address)), ("afreshAbove", Json::number(a))]))
              shut()
            }
            None => ()
          }
        },
        tone=Primary,
        busy=fn() { is_doing(core, ["context.setAfresh"], [("station", address)]) },
        disabled=fn() {
          match amount() {
            Some(a) => a == cost
            None => true
          }
        },
      )
      |> ignore
    },
  )
}

///|
/// A workspace's mark before its name.
let st_ws_mark : Double = 16.0

// ── Machine ─────────────────────────────────────────────────────────────

// ── styles ──────────

///|
let st_mark_glyph : Double = 28.0

///|
let st_mark_wide_glyph : Double = 18.0

///|
let st_profile_glyph : Double = 18.0

///|
// kept across runs: a value (no field of it changes)
let st_mark_letter : @ui.TextStyle = @ui.text_style(size=Heading, weight=Semibold, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let st_fact : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let st_fact_busy : @ui.TextStyle = st_fact.then(@ui.text_style(color=AccentText))

///|
/// A section's count beside its title (titleCount: 8 after it, 500, subtle).
// kept across runs: a value (no field of it changes)
let st_count : @ui.TextStyle = @ui.text_style(size=Meta, leading=L7, weight=Medium, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let st_memory : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let st_offline_note : @ui.Style = @ui.css("w=Full pb=S4")

///|
/// A profile's maker's mark, concentric with its row's corner.
// kept across runs: a value (no field of it changes)
let st_profile_mark : @ui.Style = @ui.css("w=S9 h=S9 bg=Neutral align=ACenter justify=JCenter").then(
  @ui.style(radius=@sf.small_radius),
)

///|
// kept across runs: a value (no field of it changes)
let st_env_problems : @ui.Style = @ui.css("w=Full gap=S1")

///|
/// The variables' editor on its card: the field, what is wrong under it, its buttons, 12 apart.
// kept across runs: a value (no field of it changes)
let st_editor : @ui.Style = @ui.css("w=Full gap=S3")

///|
/// A line of the variables the core cannot take (the meta's 12, muted; red where it is an error).
// kept across runs: a value (no field of it changes)
let st_problem : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let st_problem_bad : @ui.TextStyle = st_problem.then(@ui.text_style(color=Danger))

///|
// kept across runs: a value (no field of it changes)
let st_diag_head : @ui.Style = @ui.css("w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let st_diag_summary : @ui.TextStyle = @ui.text_style(size=Body, leading=L6, weight=Medium, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let st_diag_meta : @ui.Style = @ui.css("w=Full gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let st_diag_meta_row : @ui.Style = @ui.css("row w=Full gap=S2_5 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let st_diag_meta_val_box : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let st_diag_meta_val : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, w=Full)

///|
/// Aligned label column minimum width in diagnostic key-value and route rows (keeps values aligned while leaving
/// >=168px on 320px 1.3x screens for IPv4:port tokens).
let st_diag_label_w : Double = 74.0

///|
// kept across runs: a value (no field of it changes)
let st_diag_ways : @ui.Style = @ui.css("w=Full gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let st_diag_way_row : @ui.Style = @ui.css("row w=Full gap=S2 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let st_diag_way_dot : @ui.Style = @ui.css("h=S4 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let st_diag_way_name : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, color=Fg, wrap=false)

///|
/// Taking a station out of the workspace, asked first (its ⋯'s 移出, and 移出 workspace once its chats were moved
/// away, station_retire_node.mbt): back to the list at once (the page of a station going has nothing to show), its answer said there.
fn station_remove_ask(core : Core, here : Here, s : Json?) -> Unit {
  let address = text(s, "station")
  confirm(
    @sf.t("web-pages.settings.stations.removeConfirm", args=[("name", text(s, "name"))]),
    @sf.t("web-pages.settings.stations.removeConfirmBody", args=[("name", @sf.product())]),
    @sf.t("web-pages.settings.stations.removeAction"),
    danger=true,
    // closed where its page (or its move page) was pushed on the stack; in the stations' place it stays on the place,
    // which moves on to the first left once the list drops it (places.mbt place_route)
    fn() {
      if !@sfbase.close_page(Setting(@settings.Route::Station(address))) {
        @sfbase.close_page(Setting(@settings.Route::StationMove(address))) |> ignore
      }
      @settings.act(
        core,
        @sf.t("web-pages.settings.stations.remove"),
        "workspace.removeStation",
        obj([("workspace", str(here.workspace)), ("station", str(text(s, "id"))), ("account", str(here.sub))]),
        done=@sf.t("android-settings.station.removed"),
        then=fn(_) {
          let key = place_key(here.workspace, "stations")
          if place_pick.get(key) == Some(@settings.Route::Station(address)) {
            place_pick.remove(key)
          }
        },
      )
    },
  )
}
