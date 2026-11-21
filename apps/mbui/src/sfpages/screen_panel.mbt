// What the screen's bar has beside 只看/控制, as the web's: how the view goes (a signal
// mark and how long it has been seen, under the title on a phone, a chip of the viewer's bar with keyboard and mouse;
// pressed, its figures under the round trip, 复制诊断), 控制中心 (a round button, or one of the bar's tools), what can be
// done with the view and how its picture is asked (screen_center_node.mbt: 全屏, pasting, sending files, the sound, the
// trackpad; 画质, 帧率, 缩放, 分辨率; 连接, 断开), and 按键 by the keyboard: 组合键 (the keys a phone has none of, or its own
// system would keep: ⌘Tab, Alt+Tab, the Windows key…), F1–F12 and the keys the keys row has not. Each opens through the
// library's presenters: a sheet from a phone's foot, a small panel beside its button with keyboard and mouse; what this
// page opened is one at a time, its own (screen_panel_toggle).

///|
/// A key sent with modifiers (mod_alt, mod_ctrl, mod_meta, mod_shift), as the screen's system names it: its name, its
/// keys as they are written (each apart), what it sends.
#derive(Eq)
priv struct Combo {
  name : String
  keys : String
  key : String
  code : String
  mods : Int
  icon : String
}

///|
/// The combos worth sending to a station's system (its host's `os`, in words: macOS 26.6.2, Windows 11 Pro…; the web's
/// combosFor): a Mac's for a Mac, else Windows'.
fn combos_for(os : String) -> Array[Combo] {
  let c = fn(name : String, keys : String, key : String, code : String, mods : Int, icon : String) -> Combo {
    { name: @sf.t(name), keys, key, code, mods, icon }
  }
  let low = os.to_lower()
  if low.has_prefix("mac") || low.has_prefix("darwin") {
    [
      c("web-pages.screen.combo.switchApp", "⌘ Tab", "Tab", "Tab", mod_meta, "view-columns"),
      c("web-pages.screen.combo.spotlight", "⌘ Space", " ", "Space", mod_meta, "search"),
      c("web-pages.screen.combo.missionControl", "⌃ ↑", "ArrowUp", "ArrowUp", mod_ctrl, "boxes"),
      c("web-pages.screen.combo.forceQuit", "⌘ ⌥ Esc", "Escape", "Escape", mod_meta | mod_alt, "stop"),
      c("web-pages.screen.combo.quit", "⌘ Q", "q", "KeyQ", mod_meta, "close"),
      c("web-pages.screen.combo.screenshot", "⌘ ⇧ 4", "4", "Digit4", mod_meta | mod_shift, "camera"),
    ]
  } else {
    [
      c("web-pages.screen.combo.start", "Win", "Meta", "MetaLeft", 0, "boxes"),
      c("web-pages.screen.combo.switchWindow", "Alt Tab", "Tab", "Tab", mod_alt, "view-columns"),
      c("web-pages.screen.combo.desktop", "Win D", "d", "KeyD", mod_meta, "monitor"),
      c("web-pages.screen.combo.taskManager", "Ctrl Shift Esc", "Escape", "Escape", mod_ctrl | mod_shift, "chart"),
      c("web-pages.screen.combo.close", "Alt F4", "F4", "F4", mod_alt, "close"),
      c("web-pages.screen.combo.snip", "Win Shift S", "s", "KeyS", mod_meta | mod_shift, "camera"),
    ]
  }
}

///|
/// The system the screen's station runs on, in words (its host's `os`, the workspace's stations' view); "" until known.
fn screen_os(src : Source, station : String) -> String {
  let scope = match station.find("/") {
    Some(i) => station.exact_view(end=i).to_owned()
    None => station
  }
  match @sfbase.station_rows(src, scope).value {
    Some(Array(list)) =>
      for s in list {
        if text(Some(s), "station") == station {
          break text(field(Some(s), "host"), "os")
        }
      } nobreak {
        ""
      }
    _ => ""
  }
}

///|
/// This device's connection to the screen's station (the `stationNet` view: its way, round trip and packets lost), while
/// the view is live; None before it is, or before the core has one open.
fn screen_net(s : ScreenSess) -> Json? {
  if s.phase() != "live" {
    return None
  }
  match s.src.topic("stationNet", { "station": Json::string(s.station) }).get().value {
    Some(Object(_)) as v => v
    _ => None
  }
}

///|
/// The share a station's link line says was lost (`stationNet`'s `loss.text`: 丢包 12.5%, 12.5% loss): its number alone,
/// None where it says none.
fn loss_pct_of_words(w : String) -> Double? {
  let mut whole = 0.0
  let mut frac = 0.0
  let mut scale = 1.0
  let mut in_frac = false
  let mut any = false
  for ch in w {
    if ch >= '0' && ch <= '9' {
      let d = (ch.to_int() - '0'.to_int()).to_double()
      if in_frac {
        scale = scale / 10.0
        frac = frac + d * scale
      } else {
        whole = whole * 10.0 + d
      }
      any = true
    } else if ch == '.' && any && !in_frac {
      in_frac = true
    } else if any {
      break
    }
  }
  if any { Some(whole + frac) } else { None }
}

///|
/// A share lost, as 丢包率 says it (to a tenth: 28.6%, 0%) and its level: red from 10%, amber from 1%, plain below.
fn loss_words(pct : Double) -> (String, String) {
  let clamped = if pct < 0.0 { 0.0 } else if pct > 100.0 { 100.0 } else { pct }
  let tenths = (clamped * 10.0).round().to_int()
  if tenths <= 0 {
    return ("0%", "")
  }
  ("\{tenths / 10}.\{tenths % 10}%", if tenths >= 100 { "red" } else if tenths >= 10 { "amber" } else { "" })
}

///|
/// What the view's link lost (丢包率) and its level: the most of what the station counts of the view's link (the view's
/// state's `loss`: the pictures all go its way) and of what this device counts of its own connection (`stationNet`'s,
/// a station before the view's count); 0% where neither says one, — before either is known.
fn screen_loss(st : Json?, net : Json?) -> (String, String) {
  let down = match field(st, "loss") {
    Some(Number(n, ..)) => Some(n)
    _ => None
  }
  let up = match field(net, "loss") {
    Some(Object(_)) as f => loss_pct_of_words(text(f, "text"))
    _ => None
  }
  match (down, up) {
    (Some(d), Some(u)) => loss_words(if d > u { d } else { u })
    (Some(d), None) => loss_words(d)
    (None, Some(u)) => loss_words(u)
    (None, None) => if net is Some(_) { ("0%", "") } else { ("—", "") }
  }
}

///|
/// How bad a level is: red, then amber, then ok, then none.
fn level_rank(level : String) -> Int {
  match level {
    "red" => 3
    "amber" => 2
    "ok" => 1
    _ => 0
  }
}

///|
/// How the view's link goes, as the signal mark and the viewer's bar say it: the worst of its round trip's level and
/// what it lost (a link of 57 ms that loses a quarter of what goes is not good: pengxiao, 2026-11-17). What it lost
/// only makes it worse; before the round trip is known, none.
fn screen_link_level(st : Json?, net : Json?) -> String {
  let mut worst = text(field(net, "rtt"), "level")
  let down = match field(st, "loss") {
    Some(Number(n, ..)) => loss_words(n).1
    _ => ""
  }
  for l in [down, text(field(net, "loss"), "level")] {
    if level_rank(l) > level_rank(worst) {
      worst = l
    }
  }
  worst
}

///|
/// 画质's choices, the default first: its key in the prefs ("" none), its words' key.
// kept across runs: a table, never written
let screen_qualities : Array[(String, String)] = [("", "auto"), ("smooth", "smooth"), ("hd", "hd"), ("qhd", "qhd"), ("original", "original")]

// ── what the view's figures are now ──────────────────────────────────────

///|
/// How long it has been seen, in the seconds counted: 00:20:50 (read as it changes where a node reads it).
fn seen_for(u : ScreenUi) -> String {
  let secs = u.seen.get()
  let two = fn(n : Int) { if n < 10 { "0\{n}" } else { "\{n}" } }
  "\{two(secs / 3600)}:\{two(secs / 60 % 60)}:\{two(secs % 60)}"
}

///|
/// Bits a second, as a link's speed is said: 850 kbps, 4.2 Mbps.
fn bitrate_words(bps : Double) -> String {
  if bps >= 1.0e7 {
    "\{(bps / 1.0e6).round().to_int()} Mbps"
  } else if bps >= 1.0e6 {
    let tenths = (bps / 1.0e5).round().to_int()
    "\{tenths / 10}.\{tenths % 10} Mbps"
  } else {
    "\{(bps / 1.0e3).round().to_int()} kbps"
  }
}

///|
/// A codec as it is written: H.264, H.265, JPEG.
fn codec_words(codec : String) -> String {
  match codec {
    "h264" => "H.264"
    "h265" => "H.265"
    "" => "—"
    other => other.to_upper()
  }
}

// ── the signal mark ──────────────────────────────────────────────────────

///|
/// How many of the mark's three bars are lit: all as the round trip is good, two as it is slow, one as it is very
/// slow, none before it is known.
fn bars_lit(level : String) -> Int {
  match level {
    "ok" => 3
    "amber" => 2
    "red" => 1
    _ => 0
  }
}

///|
/// The colour of a figure, or of the mark, as its level is (the muted ink before it is known).
fn level_color(level : String, plain : @ui.Color) -> @ui.Color {
  match level {
    "ok" => Positive
    "amber" => Warn
    "red" => Danger
    _ => plain
  }
}

///|
/// The colour of a figure's words as its level is: the mark's, but amber's ink that reads on the panel (Warn itself is
/// too light for words).
fn figure_ink(level : String) -> @ui.Color {
  match level {
    "amber" => WarnInk
    l => level_color(l, Fg)
  }
}

///|
/// Native events arrive before this frame rebuilds native_over; use the page and system bars, not that transient flag.
fn screen_panel_side() -> @ui.Side {
  if @sf.native_side() && app.nav.top() is Screen(_) { Left } else { Bottom }
}

///|
/// Three bars (signal_bars') as nodes in `parent`, as the round trip's `level` is now.
fn signal_bars_node(parent : @view.View, level : () -> String) -> Unit {
  parent.box(fn(row) {
    @sf.style_node(row, fn() { bars_row }, in_row=true)
    for i, bar in [bar_low, bar_mid, bar_high] {
      row.box(fn(b) {
        @sf.style_node(b, fn() {
          let ink = level_color(level(), Muted)
          bar.then(@ui.style(bg=if i < bars_lit(level()) { ink } else { A(ink, O25) }))
        }, in_row=true)
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// The view's figures beside what opened them (`from`): from 控制中心's 连接 (`stepped`), a step further in from it, its
/// panel's; else this page's panel of its own (screen_panel_toggle).
fn net_panel_open(s : ScreenSess, u : ScreenUi, from : @sf.Anchor, stepped? : Bool = false) -> Unit {
  let open = fn() { @sf.panel_nodes("", fn(v, _) { net_node(v, s, u) }, from~, side=screen_panel_side(), w=net_panel_w, focus=false) }
  if stepped {
    open()
  } else {
    screen_panel_toggle(u, "stats", open)
  }
}

///|
/// The view's figures in `v` (the web's netPanel), as nodes: the round trip over them, then the frames', the link's and
/// the picture's, and 复制诊断; each as it is now (the state, the link, and the seconds counted: screen_count).
fn net_node(v : @view.View, s : ScreenSess, u : ScreenUi) -> Unit {
  let st = fn() {
    s.said.get() |> ignore
    s.state
  }
  let net = fn() { screen_net(s) }
  // (its figures counted each second as the view's seconds seen are, screen_count)
  let counted = fn() { u.seen.get() |> ignore }
  let or_dash = fn(w : String) { if w == "" { "—" } else { w } }
  let copied = @signals.signal(false, same=fn(a, b) { a == b })
  let due : Ref[() -> Unit] = Ref(fn() {  })
  v.box(fn(b) {
    @sf.style_node(b, fn() { net_panel_box })
    b.box(fn(head) {
      @sf.style_node(head, fn() { net_head_box })
      signal_bars_node(head, fn() { screen_link_level(st(), net()) })
      @sf.words_node(head, fn() {
        @sf.t("web-pages.screen.stat.rttHead").replace_all(old="{rtt}", new=or_dash(text(field(net(), "rtt"), "text")))
      }, fn() { net_head_words })
      |> ignore
    })
    |> ignore
    let group = fn(rows : Array[(String, () -> String, () -> String)]) {
      b.box(fn(g) {
        @sf.style_node(g, fn() { net_group_box })
        g.box(fn(col) {
          @sf.style_node(col, fn() { net_rows })
          for r in rows {
            let (name, value, level) = r
            col.box(fn(row) {
              @sf.style_node(row, fn() { net_row_box })
              row.box(fn(n) {
                @sf.style_node(n, fn() { net_row_name }, in_row=true)
                @sf.words_node(n, fn() { @sf.t(name) }, fn() { net_name_words }) |> ignore
              })
              |> ignore
              @sf.words_node(row, value, fn() { net_value_words.then(@ui.text_style(color=figure_ink(level()))) })
              |> ignore
            })
            |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    }
    let ms = fn(key : String) {
      fn() {
        match field(field(st(), "latency"), key) {
          Some(Number(n, ..)) => "\{n.to_int()} ms"
          _ => "—"
        }
      }
    }
    let plain = fn() { "" }
    let loss = fn() { screen_loss(st(), net()) }
    group([
      ("web-pages.screen.stat.frameLatency", ms("frame"), plain),
      ("web-pages.screen.stat.beforeSent", ms("before"), plain),
      (
        "web-pages.screen.stat.fps",
        fn() {
          counted()
          match u.fps {
            Some(f) => "\{f.round().to_int()}"
            None => "—"
          }
        },
        plain,
      ),
      (
        "web-pages.screen.stat.bitrate",
        fn() {
          counted()
          match u.bps {
            Some(b) => bitrate_words(b)
            None => "—"
          }
        },
        plain,
      ),
      ("web-pages.screen.stat.loss", fn() { loss().0 }, fn() { loss().1 }),
    ])
    group([
      ("web-pages.screen.stat.path", fn() { or_dash(text(net(), "path")) }, plain),
      ("web-pages.screen.stat.system", fn() { or_dash(screen_os(s.src, s.station)) }, plain),
    ])
    group([
      (
        "web-pages.screen.stat.picture",
        fn() {
          let w = number(st(), "width").to_int()
          let h = number(st(), "height").to_int()
          if w > 0 && h > 0 { "\{w}×\{h}" } else { "—" }
        },
        plain,
      ),
      ("web-pages.screen.stat.codec", fn() { codec_words(text(st(), "codec")) }, plain),
      ("web-pages.screen.stat.capture", fn() { or_dash(text(field(st(), "video"), "capture")) }, plain),
      (
        "web-pages.screen.stat.encoder",
        fn() {
          match field(field(st(), "video"), "hardware") {
            Some(True) => @sf.t("web-pages.screen.stat.hardware")
            Some(False) => @sf.t("web-pages.screen.stat.software")
            _ => "—"
          }
        },
        plain,
      ),
    ])
    // everything above as figures (no screen, no names), for a report; 已复制 for a moment after
    b.box(fn(at) {
      @sf.style_node(at, fn() { net_diag_place })
      @sf.panel_button_node(
        at,
        fn() { @sf.t(if copied.get() { "web-pages.screen.stat.copied" } else { "web-pages.screen.stat.copy" }) },
        fn() {
          let n = @signals.untracked(net)
          @ui.clipboard_set(diagnosis(s, u, n, screen_os(s.src, s.station)).stringify(), label=@sf.product())
          copied.set(true)
          (due.val)()
          due.val = at.at_moment(at.cause_at() + diag_said_ms, fn() { copied.set(false) })
        },
        tone=Quiet,
      )
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// What 复制诊断 copies (the web's: the figures, no screen and no names), with this app's own name in place of the
/// browser's.
fn diagnosis(s : ScreenSess, u : ScreenUi, net : Json?, os : String) -> Json {
  let st = s.state
  let w = number(st, "width").to_int()
  let num_or_null = fn(v : Double?) {
    match v {
      Some(x) => Json::number(x.round())
      None => Json::null()
    }
  }
  let said : Map[String, Json] = {
    "rtt": match opt_text(field(net, "rtt"), "text") {
      Some(t) => Json::string(t)
      None => Json::null()
    },
    "loss": match screen_loss(st, net).0 {
      "—" => Json::null()
      t => Json::string(t)
    },
    "path": match opt_text(net, "path") {
      Some(t) => Json::string(t)
      None => Json::null()
    },
    "system": if os == "" { Json::null() } else { Json::string(os) },
    "fps": num_or_null(u.fps),
    "bps": num_or_null(u.bps),
    "picture": if w > 0 {
      Json::string("\{w}x\{number(st, "height").to_int()}")
    } else {
      Json::null()
    },
    "codec": match opt_text(st, "codec") {
      Some(t) => Json::string(t)
      None => Json::null()
    },
    "latency": field(st, "latency").unwrap_or(Json::null()),
    "video": field(st, "video").unwrap_or(Json::null()),
    "agent": Json::string("still.fail"),
  }
  Json::object(said)
}

///|
/// How long 已复制 is said in place of 复制诊断 (the web's 1500).
let diag_said_ms : Double = 1500.0

// ── 控制中心 ──────────────────────────────────────────────────────────────

// ── 按键 ─────────────────────────────────────────────────────────────────

///|
/// 按键 (the combos, then F1–F12 and the keys the keys row has not) beside what opened it (`from`), or with keyboard and
/// mouse (`combos_only`: its keyboard has the rest) 组合键 alone; this page's panel of its own (screen_panel_toggle).
fn keys_open(s : ScreenSess, u : ScreenUi, from : @sf.Anchor, combos_only? : Bool = false) -> Unit {
  let title = @sf.t(if combos_only { "web-pages.screen.combos" } else { "web-pages.screen.keysPanel" })
  screen_panel_toggle(u, "keys", fn() {
    @sf.panel_nodes(title, fn(v, _) { keys_node(v, s, u, combos_only) }, from~, side=screen_panel_side(), focus=false)
  })
}

///|
/// Whether 全屏 is on: the screen alone on a phone (ScreenUi's), the window filling the screen with keyboard and mouse.
fn full_now(u : ScreenUi) -> Bool {
  u.full.get() || @ui.full_screen()
}

///|
/// Out of 全屏 (touch's): where it was asked beside its chat, the page of it put on top for it taken off, back to the
/// panel.
fn screen_unfull(u : ScreenUi) -> Unit {
  let pop = u.full_from_tab
  u.full_from_tab = false
  u.full.set(false)
  if pop && u.at is Some(at) && @sfbase.app.nav.top() == Screen(at) {
    @sfbase.close_page(Screen(at)) |> ignore
  }
}

///|
/// 全屏 asked for, or let go of: on a phone the screen alone, turned sideways, its tools folded into one button; with
/// keyboard and mouse the window made to fill the screen, the bar kept (as the web's page in its browser's full screen).
fn full_asked(u : ScreenUi) -> Unit {
  screen_panels_close(u)
  if @sf.soft_keyboard() {
    if u.full.untracked() {
      screen_unfull(u)
    } else if u.in_tab && u.at is Some(at) {
      // beside its chat: the page of it on top over all of it, the whole window (the system's bars put away:
      // screen_native_acts), not the panel's room alone
      u.full_from_tab = true
      u.full.set(true)
      @sfbase.app.nav.push(Screen(at))
    } else {
      u.full.set(true)
    }
  } else {
    let on = !@ui.full_screen()
    @hostapi.set_full_screen(on)
    u.fulled = on
  }
}

///|
/// The keys a phone's keyboard and the keys row have not (F1–F12, Delete, Home, End, Page Up and Down), as on a
/// keyboard: its name, what it sends.
// kept across runs: a value (nothing of it changes)
let screen_panel_keys : Array[(String, String)] = [
  ("F1", "F1"),
  ("F2", "F2"),
  ("F3", "F3"),
  ("F4", "F4"),
  ("F5", "F5"),
  ("F6", "F6"),
  ("F7", "F7"),
  ("F8", "F8"),
  ("F9", "F9"),
  ("F10", "F10"),
  ("F11", "F11"),
  ("F12", "F12"),
  ("Del", "Delete"),
  ("Home", "Home"),
  ("End", "End"),
  ("PgUp", "PageUp"),
  ("PgDn", "PageDown"),
]

///|
/// A choice of 控制中心 kept on this device for every screen (`prefs.set`, null for the default): the view takes it
/// once the prefs say so (screen_life_node's asked_again: 画质 asked of the open view).
fn prefs_chosen(s : ScreenSess, name : String, value : String) -> Unit {
  prefs_set(s, name, value, if value == "" { Json::null() } else { Json::string(value) })
}

///|
/// What 帧率's note says of the one chosen: 自动 goes by the link; 90 and 120 only where the display draws that many.
fn fps_note(fps : Int) -> String {
  if fps == 0 {
    @sf.t("web-pages.screen.fpsHint.auto")
  } else {
    @sf.t(if fps > 60 { "web-pages.screen.fpsHint.high" } else { "web-pages.screen.fpsHint.cap" }, args=[("fps", "\{fps}")])
  }
}

///|
/// A choice kept on this device (`prefs.set` `name`: `v`, null for the default), `value` naming it.
fn prefs_set(s : ScreenSess, name : String, value : String, v : Json) -> Unit {
  ignore(value)
  let p : Map[String, Json] = Map([])
  p[name] = v
  (s.src.call)("prefs.set", Json::object(p), screen_act(@sf.t("web-pages.screen.panel")))
}

// ── 页面切换与网址导航 ───────────────────────────────────────────────────

///|
/// Switches the viewer from `s` to another screen `next` on the same station: in place on the stack, in its standalone
/// window if popped out, or beside the chat when shown in a side-panel tab.
fn switch_screen_to(s : ScreenSess, u : ScreenUi, next : String, title : String, until_gone : Bool) -> Unit {
  screen_panels_close(u)
  if next == "" || next == s.screen {
    return
  }
  let next_at : ScreenAt = { station: s.station, screen: next, title, until_gone }
  match @sfbase.lone_page.val {
    Some(Screen(prev)) => {
      // (the window shows the next first, so the screen it leaves is no window's when it is let go of)
      @sfbase.lone_page_replace(Screen({ ..next_at, until_gone: false }))
      screen_left(s.src, prev.station, prev.screen)
    }
    _ =>
      if !u.in_tab && @sfbase.app.nav.top() is Screen(_) {
        @sfbase.open_in_place(Screen(next_at))
      } else {
        @sfbase.open_page(Screen(next_at))
      }
  }
}

///|
/// Asks for a URL, bare domain, or pasted text containing an `https://` link and navigates the current browser tab to it
/// (`screen.openUrl`).
fn go_url_asked(s : ScreenSess, from : @sf.Anchor) -> Unit {
  let site = text(s.state, "site")
  @sf.ask(
    @sf.t("web-pages.screen.goUrl"),
    @sf.t("web-pages.screen.goUrlAction"),
    fn(url) {
      let p : Map[String, Json] = {
        "station": Json::string(s.station),
        "screen": Json::string(s.screen),
        "url": Json::string(url),
      }
      (s.src.call)("screen.openUrl", Json::object(p), screen_act(@sf.t("web-pages.screen.goUrlWhat")))
    },
    placeholder=if site != "" { site } else { "mail.proton.me" },
    hint=@sf.t("web-pages.screen.urlHint"),
    from~,
  )
}

///|
/// Reloads the current browser tab (`screen.reload`).
fn reload_asked(s : ScreenSess) -> Unit {
  let p : Map[String, Json] = {
    "station": Json::string(s.station),
    "screen": Json::string(s.screen),
  }
  (s.src.call)("screen.reload", Json::object(p), screen_act(@sf.t("web-pages.screen.reloadWhat")))
}
