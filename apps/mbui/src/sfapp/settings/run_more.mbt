// The machine's own sessions to go on with (openMachineSessions, lookAtMachineSession),
// and adding people to the workspace with the workspace's mark.

// ---------------------------------------------------------------------------
// The machine's own sessions

///|
/// The sessions a station's machine kept (by station), as `machineSessions.list` answered; asked once a page. What
/// shows them follows the answer (it comes from outside, as the core answers).
let machine_sessions : @sf.LiveMap[String, Array[Json]] = @sf.LiveMap::new()

///|
/// The stations whose machine's sessions were asked (machine_sessions): asked once.
let machine_sessions_asked : Map[String, Bool] = Map([])

///|
/// The offer, where the station's machine kept sessions of its own Claude Code or Codex:
/// quiet as the words around it until pointed at, then its ground and its words the text's; its list and a look at one
/// before going on with it are sheets. Drawn by a new chat's page (sfpages), which says where it hangs.
pub fn machine_sessions_offer(c : @ui.Ctx, core : Core, station : String, name : String) -> Unit {
  let t = @sf.theme()
  if !machine_sessions_asked.contains(station) {
    machine_sessions_asked[station] = true
    // (asked once the frame's builds are over: the build that first comes to it alone)
    c.tell("machineSessions.list/" + station, fn() {
      (core.call)("machineSessions.list", obj([("station", str(station))]), fn(r) {
        match r {
          Ok(v) => machine_sessions.set(station, items(Some(v), "sessions"))
          Err(_) => ()
        }
      })
    })
  }
  let sessions = machine_sessions.get(station).unwrap_or([])
  if sessions.length() == 0 {
    return
  }
  let id = c.id("machine-offer/" + station)
  c.on_press(id, fn() {
    open_machine_sessions(core, station, name)
  })
  let lit = c.lit(id)
  let words = fill("android-chat.new.machine.offer", [
    ("station", if name == "" { tr("android-chat.new.machine.here") } else { name }),
  ])
  let b = c.box(style=machine_offer_box, id~, fn() {
    @sf.icon(c, "monitor", size=machine_offer_mark, color=if lit { t.p.text } else { t.p.muted }) |> ignore
    c.text(words, style=if lit { machine_offer_words_lit } else { machine_offer_words }) |> ignore
    @sf.press_ripple(c, id, @sf.small_corner)
  })
  c.semantics(b, Button, id~, label=words)
}

///|
/// The offer (machine_sessions_offer's) as nodes in `parent`, of the station `station()` names (`name()` its name, ""
/// this machine): the sessions its machine kept asked once a station, as it is first made for it; shown once it has
/// any, its mark and words quiet till the hand is on it; pressed, their list (open_machine_sessions).
#callsite(autofill(loc))
pub fn machine_sessions_offer_node(
  parent : @view.View,
  core : Core,
  station : () -> String,
  name : () -> String,
  loc~ : SourceLoc,
) -> Unit {
  // (asked once a station, as the page is first made on it: as the answer comes, it shows)
  parent.reacts(station, fn(st) {
    guard st != "" && !machine_sessions_asked.contains(st) else { return }
    machine_sessions_asked[st] = true
    (core.call)("machineSessions.list", obj([("station", str(st))]), fn(r) {
      match r {
        Ok(v) => machine_sessions.set(st, items(Some(v), "sessions"))
        Err(_) => ()
      }
    })
  })
  let words = fn() {
    fill("android-chat.new.machine.offer", [("station", if name() == "" { tr("android-chat.new.machine.here") } else { name() })])
  }
  parent.show(fn() { machine_sessions.get(station()).unwrap_or([]).length() > 0 }, fn(o) {
    @sf.ripple_button_node(loc~, o, words, fn() { open_machine_sessions(core, station(), name()) }, fn(b, state) {
      let lit = fn() { state.hovered() || state.pressed() || state.focus_shown() }
      @sf.style_node(b, fn() { machine_offer_box })
      @sf.hover_ground_node(b, lit=Some(lit))
      @sf.icon_node(b, "monitor", machine_offer_mark, By(fn() { if lit() { @sf.theme().p.text } else { @sf.theme().p.muted } }))
      |> ignore
      @sf.words_node(b, words, fn() { if lit() { machine_offer_words_lit } else { machine_offer_words } }) |> ignore
      Is(@sf.small_corner)
    })
    |> ignore
  })
}

///|
/// The offer (offer: 4 by 10 in, its parts 6 apart, the hover's ground; 13 on 20, muted) and its mark (Monitor 14).
// kept across runs: a value (no field of it changes)
let machine_offer_box : @ui.Style = @ui.css("row px=S2_5 py=S1 gap=S1_5 align=ACenter hovered{bg=Hover}").then(
  @ui.style(radius=@sf.small_radius),
)

///|
// kept across runs: a value (no field of it changes)
let machine_offer_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let machine_offer_words_lit : @ui.TextStyle = machine_offer_words.then(@ui.text_style(color=Fg))

///|
let machine_offer_mark : Double = 14.0

///|
/// The machine's sessions (openMachineSessions), each a look at it before going on with it: a dialog of its own in the
/// window's middle (a sheet on a small screen), as the web's is, not a panel hanging off the offer's line of words.
/// Found by what they are (pengxiao, 2026-10-30: 「没有时间、没有 Provider 之类的过滤」): over the list, kept in view
/// as it scrolls, a search of their titles and folders, which runtime (where more than one ran: each with how many),
/// and which folder (the projects they ran in, most used first; still.fail's own sessions, under its directory, one of
/// them, not in the rest). The list under its days' headings (the core's `day`), each row the runtime's mark, its
/// title, when at its line's end (the core's `when`), where it ran under them.
pub fn open_machine_sessions(core : Core, station : String, name : String) -> Unit {
  let shown = if name == "" { tr("android-chat.new.machine.here") } else { name }
  let runtime : @signals.Signal[String] = @signals.signal("", same=fn(a, b) { a == b })
  // (the folder chosen: "" all of them but still.fail's own, machine_own those alone)
  let folder : @signals.Signal[String] = @signals.signal("", same=fn(a, b) { a == b })
  let search = field_of("machine-search/" + station)
  let all = fn() { machine_sessions.get(station).unwrap_or([]) }
  // whether one is in the folder chosen
  let in_folder = fn(sv : Json?) {
    match folder.get() {
      "" => !flag(sv, "own")
      f if f == machine_own => flag(sv, "own")
      f => !flag(sv, "own") && text(sv, "folder") == f
    }
  }
  // what is chosen among: the runtimes of those in the folder (each with how many, and how many in all), the folders
  // of all of them (still.fail's own apart, most used first), how many are still.fail's own
  let among = @signals.computed(fn(_) {
    let runtimes : Array[(String, Int)] = []
    let folders : Array[(String, Int)] = []
    let mut own = 0
    let mut shown_n = 0
    for s in all() {
      let sv = Some(s)
      if in_folder(sv) {
        shown_n += 1
        let rt = text(sv, "runtime")
        match runtimes.search_by(fn(r) { r.0 == rt }) {
          Some(i) => runtimes[i] = (rt, runtimes[i].1 + 1)
          None => runtimes.push((rt, 1))
        }
      }
      if flag(sv, "own") {
        own += 1
      } else {
        let f = text(sv, "folder")
        match folders.search_by(fn(r) { r.0 == f }) {
          Some(i) => folders[i] = (f, folders[i].1 + 1)
          None => folders.push((f, 1))
        }
      }
    }
    folders.sort_by(fn(a, b) { if a.1 != b.1 { b.1 - a.1 } else { a.0.compare(b.0) } })
    (runtimes, folders, own, shown_n)
  })
  // the runtime chosen, while the folder has more than one and that among them (else all of them: nothing hidden by
  // a choice no longer shown)
  let rt_now = fn() {
    let runtimes = among.get().0
    if runtimes.length() > 1 && runtimes.iter().any(fn(r) { r.0 == runtime.get() }) {
      runtime.get()
    } else {
      ""
    }
  }
  // those the filters leave, under their days' headings: a day by "d" and its words, one of them by "s" and its id
  let rows = @signals.computed(fn(_) {
    let lower = search.text().trim().to_owned().to_lower()
    let rt = rt_now()
    let out : Array[String] = []
    let mut day = ""
    for s in all() {
      let sv = Some(s)
      if rt != "" && text(sv, "runtime") != rt {
        continue
      }
      if !in_folder(sv) {
        continue
      }
      if lower != "" &&
        !first_text(sv, ["title", "first"], "").to_lower().contains(lower) &&
        !text(sv, "where").to_lower().contains(lower) {
        continue
      }
      if text(sv, "day") != day {
        day = text(sv, "day")
        out.push("d" + day)
      }
      out.push("s" + text(sv, "id"))
    }
    out
  })
  let session_of = fn(id : String) -> Json? {
    let list = all()
    match list.search_by(fn(s) { text(Some(s), "id") == id }) {
      Some(i) => Some(list[i])
      None => None
    }
  }
  @sf.panel_nodes(
    fill("android-chat.new.machine.title", [("station", shown)]),
    description=tr("android-chat.new.machine.text"),
    from=Unanchored,
    wide=true,
    tall=0.75,
    // (one looked at a step of the same panel: panel_go_nodes)
    steps=true,
    fn(v, _) {
      // the filters, in view over the list
      v.box(fn(f) {
        @sf.style_node(f, fn() { @sf.panel_words_in_node(f).then(machine_filters) })
        f.box(fn(line) {
          @sf.style_node(line, fn() { machine_filters_line })
          line.box(fn(s) {
            @sf.style_node(s, fn() { machine_search }, in_row=true)
            s.min_width(Is(Some(0.0))) |> ignore
            @sf.input_node(s, search, placeholder=tr("android-chat.new.machine.search"), small=true) |> ignore
          })
          |> ignore
          let chip : Ref[@view.View?] = Ref(None)
          chip.val = Some(
            @sf.chip_node(
              line,
              fn() {
                match folder.get() {
                  "" => tr("android-chat.new.machine.allFolders")
                  f if f == machine_own => tr("android-chat.new.machine.own")
                  f => f
                }
              },
              fn() {
                let (_, folders, own, _) = among.untracked()
                let choices = [@sf.choice("", tr("android-chat.new.machine.allFolders"), value=(all().length() - own).to_string())]
                for f in folders {
                  choices.push(@sf.choice(f.0, f.0, value=f.1.to_string()))
                }
                if own > 0 {
                  choices.push(@sf.choice(machine_own, tr("android-chat.new.machine.own"), value=own.to_string()))
                }
                match chip.val {
                  Some(at) =>
                    @sf.pick(tr("android-chat.new.machine.folder"), choices, folder.untracked(), fn(k) { folder.set(k) }, from=Node(at))
                  None => ()
                }
              },
              icon="folder",
            ),
          )
        })
        |> ignore
        f.show(at_once=true, fn() { among.get().0.length() > 1 }, fn(seg) {
          @sf.segmented_node(
            seg,
            fn() {
              let (runtimes, _, _, shown_n) = among.get()
              let labels = [tr("android-chat.new.machine.all") + " " + shown_n.to_string()]
              for r in runtimes {
                labels.push(runtime_label(r.0) + " " + r.1.to_string())
              }
              labels
            },
            fn() {
              let rt = rt_now()
              match among.get().0.search_by(fn(r) { r.0 == rt }) {
                Some(i) => i + 1
                None => 0
              }
            },
            fn(picked) {
              let runtimes = among.untracked().0
              runtime.set(if picked == 0 || picked > runtimes.length() { "" } else { runtimes[picked - 1].0 })
            },
          )
        })
      })
      |> ignore
      // where none is left by the filters: said in the middle
      v.show(at_once=true, fn() { rows.get().is_empty() }, fn(n) {
        n.box(fn(b) {
          @sf.style_node(b, fn() { @sf.panel_words_in_node(b).then(machine_none) })
          @sf.words_node(b, fn() { tr("android-chat.new.machine.none") }, fn() { machine_none_words }) |> ignore
        })
        |> ignore
      })
      let tips = @sf.panel_tips_of(v)
      v.show(at_once=true, fn() { !rows.get().is_empty() }, fn(l) {
        @sf.panel_list_node(
          l,
          fn() { rows.get() },
          fn(b, k) {
            let key = k.exact_view(start=1).to_owned()
            if k.has_prefix("d") {
              b.box(fn(d) {
                @sf.style_node(d, fn() {
                  @sf.panel_words_in_node(d).then(if rows.get().get(0) == Some(k) { machine_day_first } else { machine_day })
                })
                @sf.words_node(d, fn() { key }, fn() { machine_day_words }) |> ignore
              })
              |> ignore
            } else {
              let sv = fn() { session_of(key) }
              let r = b.box(fn(r) {
                @sf.choice_row_node(
                  r,
                  fn() { first_text(sv(), ["title", "first"], "") },
                  fn() { false },
                  note=fn() { first_text(sv(), ["where", "meta"], "") },
                  lead=fn(m) { @sf.maker_mark_node(m, "", @signals.untracked(fn() { text(sv(), "runtime") }), machine_mark) |> ignore },
                  tag=fn(g) {
                    g.show(at_once=true, fn() { has(sv(), "session") }, fn(p) {
                      @sf.pill_node(p, fn() { fill("android-chat.new.machine.inApp", [("app", @sf.product())]) }) |> ignore
                    })
                  },
                  trail=fn(t) { @sf.words_node(t, fn() { text(sv(), "when") }, fn() { machine_when }) |> ignore },
                  // (the look a step further in, in the same dialog)
                  press=fn() {
                    match @signals.untracked(sv) {
                      Some(s) => look_at_machine_session(core, station, s)
                      None => ()
                    }
                  },
                )
              })
              // its first words whole while it is pointed at
              match tips {
                Some(layer) =>
                  @sf.tip_node(
                    layer,
                    r,
                    fn() { text(sv(), "first") },
                    within=true,
                    repeats=@signals.untracked(fn() { text(sv(), "title") == "" }),
                  )
                  |> ignore
                None => ()
              }
            }
          },
          est=machine_row_est,
          fills=true,
        )
        |> ignore
      })
    },
  )
}

///|
/// A row of the machine's sessions as long as it is thought before it is measured, and its runtime's mark.
let machine_row_est : Double = 60.0

///|
let machine_mark : Double = 18.0

///|
/// The filters over the machine's sessions (their search and folder's line, the runtimes under it), 10 apart.
// kept across runs: a value (no field of it changes)
let machine_filters : @ui.Style = @ui.css("w=Full gap=S2_5 pt=S1 pb=S2_5")

///|
// kept across runs: a value (no field of it changes)
let machine_filters_line : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let machine_search : @ui.Style = @ui.css("w=Full")

///|
/// Where none is left by the filters: its words in the middle, room over and under them.
// kept across runs: a value (no field of it changes)
let machine_none : @ui.Style = @ui.css("w=Full pt=S8 pb=S10 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let machine_none_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, center=true, w=Full)

///|
/// A day's heading among them (the first close under the filters, the rest a gap over them).
// kept across runs: a value (no field of it changes)
let machine_day : @ui.Style = @ui.css("w=Full pt=S3_5 pb=S1")

///|
// kept across runs: a value (no field of it changes)
let machine_day_first : @ui.Style = @ui.css("w=Full pt=S1 pb=S1")

///|
// kept across runs: a value (no field of it changes)
let machine_day_words : @ui.TextStyle = @ui.text_style(size=Caption, weight=Semibold, color=Muted, wrap=false)

///|
/// When at a row's end (the core's `when`).
// kept across runs: a value (no field of it changes)
let machine_when : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, wrap=false)

///|
/// The folder chosen for still.fail's own sessions alone (no folder's name: a path's part never has a NUL).
let machine_own : String = "\u{0}own"

///|
/// One of them looked at before going on with it (lookAtMachineSession), a step of their list's panel (panel_go_nodes:
/// sliding in over the list in the same dialog or sheet, back sliding it off, the list as it was left): what was said in it, the latest at the bottom, the list
/// standing at its end as it comes (`machineSessions.read`); 继续 makes the chat that goes on with it
/// (`machineSessions.continue`) and opens it. Where it ran and how long ago under its title.
fn look_at_machine_session(core : Core, station : String, s : Json) -> Unit {
  let sv = Some(s)
  let said : @signals.Signal[(Array[Json], Int)?] = @signals.signal(None)
  let error : @signals.Signal[String] = @signals.signal("", same=fn(a, b) { a == b })
  (core.call)("machineSessions.read", obj([("station", str(station)), ("runtime", str(text(sv, "runtime"))), ("id", str(text(sv, "id"))), ("limit", Json::number(200.0))]), fn(r) {
    match r {
      Ok(v) => {
        let list = items(Some(v), "said")
        said.set(Some((list, if has(Some(v), "total") { count(Some(v), "total") } else { list.length() })))
      }
      Err(e) => error.set(error_text(e))
    }
  })
  let runtime = text(sv, "runtime")
  let model = match text(sv, "model") {
    "" => runtime_label(runtime)
    m => m
  }
  @sf.panel_go_nodes(
    first_text(sv, ["title", "first"], ""),
    description=text(sv, "meta"),
    fn(v, close) {
      v.box(fn(main) {
        @sf.style_node(main, fn() { @sf.panel_words_in_node(main).then(machine_said_box) })
        main.pick(fn() { said.get() is Some(_) }, fn(p, read) {
          if !read {
            p.show(at_once=true, fn() { error.get() == "" }, fn(w) {
              w.box(fn(b) {
                @sf.style_node(b, fn() { machine_said_wait })
                @sf.wait_line_node(b, fn() { tr("common.reading") }) |> ignore
              })
              |> ignore
            })
          } else {
            @sf.style_node(p, fn() { machine_said_box })
            // (what was said, the one not given said over them, then each: the person's on its right, the agent's
            // under its mark and model; -1 the one over them)
            let blocks = fn() -> Array[Int] {
              match said.get() {
                Some((list, total)) => {
                  let out : Array[Int] = if total > list.length() { [-1] } else { [] }
                  for i in 0..<list.length() {
                    out.push(i)
                  }
                  out
                }
                None => []
              }
            }
            // (standing at its end, the latest, as it comes and as its words are measured: stick_end)
            @sf.panel_list_node(p, blocks, fn(b, i) { machine_said_node(b, said, i, runtime, model) }, est=machine_said_est, fills=true, stick_end=true)
            |> ignore
          }
        })
      })
      |> ignore
      v.show(at_once=true, fn() { error.get() != "" }, fn(e) {
        e.box(fn(b) {
          @sf.style_node(b, fn() { @sf.panel_words_in_node(b).then(machine_error_box) })
          @sf.words_node(b, fn() { error.get() }, machine_error_words) |> ignore
        })
        |> ignore
      })
      v.box(fn(row) {
        @sf.style_node(row, fn() { @sf.panel_words_in_node(row).then(machine_go_row) })
        @sf.button_node(
          row,
          fn() { tr(if has(sv, "session") { "android-chat.new.machine.open" } else { "android-chat.new.machine.continue" }) },
          fn() {
            error.set("")
            (core.call)("machineSessions.continue", obj([("station", str(station)), ("runtime", str(text(sv, "runtime"))), ("id", str(text(sv, "id")))]), fn(r) {
              match r {
                Ok(v) => {
                  close()
                  (core.pop)()
                  (core.open_chat)(station, text(Some(v), "key"), first_text(sv, ["title", "first"], ""))
                }
                Err(e) => error.set(error_text(e))
              }
            })
          },
          tone=Primary,
          busy=fn() { is_doing(core, ["machineSessions.continue"], [("station", station), ("id", text(sv, "id"))]) },
        )
        |> ignore
      })
      |> ignore
    },
  )
}

///|
/// One of what was said in a machine's session in node `b` (look_at_machine_session's list, `i` of what `said` holds; -1
/// how many over them it does not give): the person's in a bubble on its right, 300 wide at most; the agent's under
/// its runtime's mark and `model`, its words as Markdown.
fn machine_said_node(b : @view.View, said : @signals.Signal[(Array[Json], Int)?], i : Int, runtime : String, model : String) -> Unit {
  let m = fn() -> Json? {
    match said.get() {
      Some((list, _)) => list.get(i)
      None => None
    }
  }
  if i < 0 {
    b.box(fn(w) {
      @sf.style_node(w, fn() { machine_said_more })
      @sf.words_node(w, fn() {
        match said.get() {
          Some((list, total)) => fill("android-chat.new.machine.more", [("n", (total - list.length()).to_string())])
          None => ""
        }
      }, fn() { machine_said_more_words })
      |> ignore
    })
    |> ignore
    return
  }
  b.box(fn(one) {
    @sf.style_node(one, fn() { machine_said_one })
    one.pick(fn() { flag(m(), "person") }, fn(p, person) {
      if person {
        @sf.style_node(p, fn() { machine_said_person_row })
        p.box(fn(bubble) {
          @sf.style_node(bubble, machine_said_bubble)
          @sf.words_node(bubble, fn() { text(m(), "text") }, fn() { machine_said_person_words }) |> ignore
        })
        |> ignore
      } else {
        @sf.style_node(p, fn() { machine_said_agent })
        p.box(fn(h) {
          @sf.style_node(h, fn() { machine_said_head })
          @sf.maker_mark_node(h, "", runtime, machine_said_mark) |> ignore
          @sf.words_node(h, fn() { model }, fn() { machine_said_model }) |> ignore
        })
        |> ignore
        @sf.markdown_node(p, fn() { text(m(), "text") }) |> ignore
      }
    })
  })
  |> ignore
}

///|
/// What was said in one looked at: as tall as the dialog leaves it, a block 120 high till it is measured.
// kept across runs: a value (no field of it changes)
let machine_said_box : @ui.Style = @ui.css("w=Full h=Full")

///|
let machine_said_est : Double = 120.0

///|
/// Its wait, 40 under its top in the middle.
// kept across runs: a value (no field of it changes)
let machine_said_wait : @ui.Style = @ui.css("w=Full pt=S10 align=ACenter")

///|
/// How many over them it does not give: in the middle, caption on 16.
// kept across runs: a value (no field of it changes)
let machine_said_more : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let machine_said_more_words : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, center=true, w=Full, leading=L4)

///|
/// Each 18 over the next.
// kept across runs: a value (no field of it changes)
let machine_said_one : @ui.Style = @ui.css("w=Full pb=S4_5")

///|
/// The person's, on its right, a bubble of the chip's ground 300 wide at most, 14 by 8 in, 16 round, the body's words on 20.
// kept across runs: a value (no field of it changes)
let machine_said_person_row : @ui.Style = @ui.css("row w=Full justify=JEnd")

///|
let machine_said_most : Double = 300.0

///|
fn machine_said_bubble() -> @ui.Style {
  @ui.style(max_w=Fixed(machine_said_most), px=S3_5, py=S2, radius=Xl2, bg=Data(@sf.theme().p.chip))
}

///|
// kept across runs: a value (no field of it changes)
let machine_said_person_words : @ui.TextStyle = @ui.text_style(size=Body, color=Fg, leading=L5)

///|
/// The agent's: its mark 16 and model (meta, 600) 6 apart, its words 4 under them.
// kept across runs: a value (no field of it changes)
let machine_said_agent : @ui.Style = @ui.css("w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let machine_said_head : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
let machine_said_mark : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
let machine_said_model : @ui.TextStyle = @ui.text_style(size=Meta, weight=Semibold, color=Fg, wrap=false)

///|
/// What went wrong (red, meta on 19), 6 over and under.
// kept across runs: a value (no field of it changes)
let machine_error_box : @ui.Style = @ui.css("w=Full py=S1_5")

///|
fn machine_error_words() -> @ui.TextStyle {
  @ui.text_style(size=Meta, color=Data(@sf.theme().p.red), w=Full, leading=L4_75)
}

///|
/// 继续 at its end, 10 over it and 24 under it, 8 apart.
// kept across runs: a value (no field of it changes)
let machine_go_row : @ui.Style = @ui.css("row w=Full pt=S2_5 pb=S6 gap=S2 justify=JEnd")

// ---------------------------------------------------------------------------
// Adding people and the workspace's mark

///|
/// The emails in what was typed or pasted (parseEmails): each once, lowercased.
fn parse_emails(words : String) -> Array[String] {
  let out : Array[String] = []
  let stop = fn(ch : Char) { ch == ' ' || ch == '\n' || ch == '\t' || ch == ',' || ch == ';' || ch == '<' || ch == '>' || ch == '"' || ch == '\'' || ch == '(' || ch == ')' || ch == '，' || ch == '；' }
  let b = StringBuilder()
  let flush = fn() {
    let w = b.to_string()
    b.reset()
    match w.find("@") {
      Some(at) if at > 0 && w.unsafe_substring(start=at + 1, end=w.length()).contains(".") => {
        let e = w.to_lower()
        if !out.contains(e) && !e.has_suffix(".") {
          out.push(e)
        }
      }
      _ => ()
    }
  }
  for ch in words {
    if stop(ch) {
      flush()
    } else {
      b.write_char(ch)
    }
  }
  flush()
  out
}

///|
/// A role's line in the adding sheet (ROLE_HINT: "android-misc.role.member.hint" "android-misc.role.admin.hint"
/// "android-misc.role.owner.hint").
fn role_hint(role : String) -> String {
  tr("android-misc.role." + role + ".hint")
}

///|
/// Adding people by email (AddSheet): no invitation to accept, members at once when they have signed in to still.fail
/// before, from their first sign-in otherwise (`workspace.addMembers`). Typed or pasted, or picked from the people of
/// the Slack workspaces the online stations are in (`slack.people`); their role; what came of it said.
pub fn open_add_people(core : Core, here : Here, view : Json?, from? : @sf.Anchor = Unanchored) -> Unit {
  vault_serial.val += 1
  let key = "add-people/" + vault_serial.val.to_string()
  let inside : Array[String] = []
  for m in items(view, "members") {
    inside.push(text(Some(m), "email").to_lower())
  }
  for a in items(view, "added") {
    inside.push(text(Some(a), "email").to_lower())
  }
  let st : AddPeople = {
    key,
    view,
    inside,
    roles: if text(view, "role") == "owner" { ["member", "admin", "owner"] } else { ["member", "admin"] },
    typed: @signals.signal(field_of(key).text(), same=fn(a, b) { a == b }),
    role: @signals.signal("member", same=fn(a, b) { a == b }),
    error: @signals.signal("", same=fn(a, b) { a == b }),
    done: @signals.signal("", same=fn(a, b) { a == b }),
    people: @signals.signal(None),
    problems: @signals.signal([]),
    reading: @signals.signal(0, same=fn(a, b) { a == b }),
    picked: @signals.signal([]),
  }
  // the library's panel opened `from` what was pressed, most of the window tall, made once as nodes of the window's
  // tree (@sf.panel_nodes): the form, then what came of it in its place
  @sf.panel_nodes(
    tr("android-settings.add.title"),
    fn(v, _) { add_people_body(v, core, here, st) },
    from~,
    tall=0.8,
    form=true,
    foot=fn(v, close) { add_people_foot(v, core, here, st, close) },
  )
}

///|
/// What adding people holds while it is open: its field's key, the workspace's view as it opened and who is in it
/// already (members and those added who have not signed in yet, by email), the roles to give, what is typed, the role
/// chosen, why adding failed, what came of it ("" before), the Slack people read (None before), what reading them
/// said went wrong, how many stations are still being read, and those picked of them.
priv struct AddPeople {
  key : String
  view : Json?
  inside : Array[String]
  roles : Array[String]
  typed : @signals.Signal[String]
  role : @signals.Signal[String]
  error : @signals.Signal[String]
  done : @signals.Signal[String]
  people : @signals.Signal[Array[Json]?]
  problems : @signals.Signal[Array[String]]
  reading : @signals.Signal[Int]
  picked : @signals.Signal[Array[String]]
}

///|
/// The emails to add now: those typed, then those picked, each once, none already in.
fn add_people_emails(st : AddPeople) -> Array[String] {
  let emails : Array[String] = []
  for e in parse_emails(st.typed.get()) + st.picked.get() {
    if !st.inside.contains(e) && !emails.contains(e) {
      emails.push(e)
    }
  }
  emails
}

///|
/// Adding people's body in node `v`: the form (what it does, the emails, the Slack people of the online stations, the
/// role, why it failed) or, once added, what came of it.
fn add_people_body(v : @view.View, core : Core, here : Here, st : AddPeople) -> Unit {
  v.pick(fn() { st.done.get() != "" }, fn(b, done) {
    if done {
      b.box(fn(n) {
        @sf.style_node(n, fn() { @sf.panel_words_in_node(n).then(full_room) })
        @sf.words_node(n, fn() { st.done.get() }, fn() { add_people_said }) |> ignore
      })
      |> ignore
      return
    }
    b.box(fn(n) {
      @sf.style_node(n, fn() { @sf.panel_words_in_node(n).then(full_room) })
      @sf.words_node(
        n,
        fn() { fill("android-settings.add.note", [("name", text(st.view, "name")), ("app", @sf.product())]) },
        fn() { add_note_words },
      )
      |> ignore
    })
    |> ignore
    b.box(fn(n) {
      @sf.style_node(n, fn() { @sf.panel_words_in_node(n).then(add_people_block) })
      @sf.words_node(n, fn() { tr("android-settings.add.emails") }, fn() { add_people_label }) |> ignore
      @sf.textarea_node(
        n,
        field_of(st.key),
        rows=1,
        most=3,
        placeholder=tr("android-settings.add.emailsPlaceholder"),
        edited=fn(t) { st.typed.set(t) },
      )
      |> ignore
    })
    |> ignore
    b.show(fn() { online_stations(core, here).length() > 0 }, fn(s) {
      s.pick(fn() { st.people.get() is Some(_) }, fn(p, read) {
        if read {
          add_people_slack_node(p, core, st)
        } else {
          p.box(fn(n) {
            @sf.style_node(n, fn() { @sf.panel_words_in_node(n).then(add_people_button_line) })
            @sf.button_node(
              n,
              fn() { tr("android-settings.add.fromSlack") },
              fn() { add_people_read_slack(core, here, st) },
              busy=fn() { st.reading.get() > 0 },
            )
            |> ignore
          })
          |> ignore
        }
      })
    })
    b.box(fn(n) {
      @sf.style_node(n, fn() { @sf.panel_words_in_node(n).then(add_people_block) })
      @sf.words_node(n, fn() { tr("android-settings.add.role") }, fn() { add_people_label }) |> ignore
    })
    |> ignore
    @sf.sheet_column_node(b, fn(col) {
      for r in st.roles {
        @sf.choice_row_node(
          col,
          fn() { role_label(r) },
          fn() { st.role.get() == r },
          press=fn() { st.role.set(r) },
          note=fn() { role_hint(r) },
        )
      }
    })
    b.show(fn() { st.error.get() != "" }, fn(e) {
      e.box(fn(n) {
        @sf.style_node(n, fn() { @sf.panel_words_in_node(n).then(add_people_block) })
        @sf.words_node(n, fn() { st.error.get() }, fn() { add_error_words }) |> ignore
      })
      |> ignore
    })
  })
}

///|
/// The Slack people read, in node `p`: how many and how many picked, 全部 and 不选; a row each (in already, a guest),
/// picked or not as it is pressed; what went wrong reading them under.
fn add_people_slack_node(p : @view.View, core : Core, st : AddPeople) -> Unit {
  let list = fn() { st.people.get().unwrap_or([]) }
  p.box(fn(n) {
    @sf.style_node(n, fn() { @sf.panel_words_in_node(n).then(add_people_picked_line) }, in_row=true)
    n.box(fn(w) {
      @sf.style_node(w, fn() { add_people_grow }, in_row=true)
      @sf.words_node(
        w,
        fn() {
          fill("android-settings.add.picked", [
            ("n", list().length().to_string()),
            ("picked", st.picked.get().filter(fn(e) { !st.inside.contains(e) }).length().to_string()),
          ])
        },
        fn() { add_note_words },
      )
      |> ignore
    })
    |> ignore
    @sf.button_node(
      n,
      fn() { tr("android-settings.all") },
      fn() {
        st.picked.set(
          @signals.untracked(list).map(fn(x) { text(Some(x), "email") }).filter(fn(e) { !st.inside.contains(e) }),
        )
      },
      tone=Ghost,
    )
    |> ignore
    @sf.button_node(n, fn() { tr("android-settings.none") }, fn() { st.picked.set([]) }, tone=Ghost) |> ignore
  })
  |> ignore
  @sf.sheet_column_node(p, fn(col) {
    col.each(list, fn(x) { text(Some(x), "email") }, fn(r, x) {
      r.box(fn(row) {
        let pv = Some(x.untracked())
        let e = text(pv, "email")
        let there = st.inside.contains(e)
        let name = match text(pv, "name") {
          "" => e
          n => n
        }
        let image = text(pv, "image")
        @sf.choice_row_node(
          row,
          fn() { name },
          fn() { there || st.picked.get().contains(e) },
          press=fn() {
            let now = st.picked.untracked()
            st.picked.set(if now.contains(e) { now.filter(fn(y) { y != e }) } else { [..now, e] })
          },
          note=fn() {
            join([e, if there { tr("android-settings.add.in") } else if flag(pv, "guest") { tr("android-settings.add.guest") } else { "" }], " · ")
          },
          lead=fn(l) {
            @sf.avatar_node(l, fn() { e }, fn() { name }, fn() { if image == "" { "" } else { (core.picture)(image, 0) } }, 28.0)
          },
          disabled=fn() { there },
        )
      })
      |> ignore
    })
  })
  p.show(fn() { st.problems.get().length() > 0 }, fn(s) {
    s.box(fn(n) {
      @sf.style_node(n, fn() { @sf.panel_words_in_node(n).then(add_people_block) })
      @sf.words_node(n, fn() { join(st.problems.get(), tr("android-settings.add.problemSep")) }, fn() { add_error_words }) |> ignore
    })
    |> ignore
  })
}

///|
/// The people of the Slack workspaces the online stations are in (`slack.people`), each once, the workspace's own first
/// then its guests, each by name; once all are read, the workspace's own are picked, guests left to choose.
fn add_people_read_slack(core : Core, here : Here, st : AddPeople) -> Unit {
  let online = online_stations(core, here)
  guard online.length() > 0 else { return }
  st.reading.set(online.length())
  let seen : Map[String, Json] = Map([])
  let problems : Array[String] = []
  for s in online {
    (core.call)("slack.people", obj([("station", str(text(Some(s), "station")))]), fn(r) {
      match r {
        Ok(v) => {
          for p in items(Some(v), "people") {
            let e = text(Some(p), "email")
            if !seen.contains(e) {
              seen[e] = p
            }
          }
          for e in strings(Some(v), "errors") {
            problems.push(e)
          }
        }
        Err(e) => problems.push(error_text(e))
      }
      st.reading.set(st.reading.untracked() - 1)
      if st.reading.untracked() == 0 {
        let all = seen.values().collect()
        all.sort_by(fn(a, b) {
          let ga = flag(Some(a), "guest")
          let gb = flag(Some(b), "guest")
          if ga != gb {
            if ga { 1 } else { -1 }
          } else {
            text(Some(a), "name").compare(text(Some(b), "name"))
          }
        })
        let picked = st.picked.untracked().copy()
        for p in all {
          let e = text(Some(p), "email")
          if !flag(Some(p), "guest") && !st.inside.contains(e) && !picked.contains(e) {
            picked.push(e)
          }
        }
        @signals.start_batch()
        st.problems.set(problems.copy())
        st.picked.set(picked)
        st.people.set(Some(all))
        @signals.end_batch()
      }
    })
  }
}

///|
/// Adding people's foot in node `v`: 取消 and 添加 (添加 N 人 for several, lit once there is one to add, turning while it
/// goes) while the form shows; 完成 once it is added, which closes it (`close`).
fn add_people_foot(v : @view.View, core : Core, here : Here, st : AddPeople, close : () -> Unit) -> Unit {
  let form = fn() { st.done.get() == "" }
  @sf.foot_place_node(v, form, fn(p) {
    @sf.button_node(p, fn() { tr("common.cancel") }, fn() {
      p.focus_let_go()
      close()
    })
    |> ignore
  })
  @sf.foot_place_node(v, form, fn(p) {
    @sf.button_node(
      p,
      fn() {
        let n = add_people_emails(st).length()
        if n > 1 {
          fill("android-settings.add.many", [("n", n.to_string())])
        } else {
          tr("android-settings.add.one")
        }
      },
      fn() {
        p.focus_let_go()
        add_people_go(core, here, st)
      },
      tone=Primary,
      busy=fn() { is_doing(core, ["workspace.addMembers"], [("account", here.sub), ("workspace", here.workspace)]) },
      disabled=fn() { add_people_emails(st).length() == 0 },
    )
    |> ignore
  })
  @sf.foot_place_node(v, fn() { !form() }, fn(p) {
    @sf.button_node(p, fn() { tr("common.done") }, fn() { close() }, tone=Primary) |> ignore
  })
}

///|
/// Those to add added (`workspace.addMembers`) with the role chosen: what came of it said in the form's place (joined,
/// added to join at their first sign-in, in already, whose mail could not be sent; where the lock's change no station took yet, that sentence), or
/// why not under it.
fn add_people_go(core : Core, here : Here, st : AddPeople) -> Unit {
  let emails = @signals.untracked(fn() { add_people_emails(st) })
  guard emails.length() > 0 else { return }
  st.error.set("")
  (core.call)(
    "workspace.addMembers",
    obj([
      ("workspace", str(here.workspace)),
      ("role", str(st.role.untracked())),
      ("emails", Json::array(emails.map(str))),
      ("account", str(here.sub)),
    ]),
    fn(r) {
      match r {
        // (a change of the lock no station took yet: its sentence in the done words' place)
        Ok(v) if pending_said(v) != "" => st.done.set(pending_said(v))
        Ok(v) => {
          let n = fn(k : String) { items(Some(v), k).length() }
          st.done.set(fill("android-settings.add.done", [
            (
              "list",
              join(
                [
                  if n("joined") > 0 { fill("android-settings.add.joined", [("n", n("joined").to_string())]) } else { "" },
                  if n("added") > 0 { fill("android-settings.add.added", [("n", n("added").to_string()), ("app", @sf.product())]) } else { "" },
                  if n("already") > 0 { fill("android-settings.add.already", [("n", n("already").to_string())]) } else { "" },
                  // (the cloud mails each one added; one it could not is sent again as they are added again)
                  if n("unmailed") > 0 { fill("android-settings.add.unmailed", [("n", n("unmailed").to_string())]) } else { "" },
                ],
                tr("android-settings.add.sep"),
              ),
            ),
          ]))
        }
        Err(e) => st.error.set(error_text(e))
      }
    },
  )
}

///|
/// A part of adding people's form under the one before: across the panel's words, 10 over it.
// kept across runs: a value (no field of it changes)
let add_people_block : @ui.Style = @ui.css("w=Full pt=S2_5 gap=S1_5")

///|
/// 从 Slack 选择成员 under the field, as wide as its words: a row across the panel's words, 10 over it.
// kept across runs: a value (no field of it changes)
let add_people_button_line : @ui.Style = @ui.css("row w=Full pt=S2_5")

///|
/// How many Slack people and how many picked, 全部 and 不选 at its end: a row across the panel's words, 10 over it.
// kept across runs: a value (no field of it changes)
let add_people_picked_line : @ui.Style = @ui.css("row w=Full pt=S2_5 gap=S3 align=ACenter")

///|
/// What takes the rest of a row.
// kept across runs: a value (no field of it changes)
let add_people_grow : @ui.Style = @ui.css("w=Grow(1.0)")

///|
/// A heading of adding people's form (邮箱, 角色): the meta's size, semibold, 18 a line.
// kept across runs: a value (no field of it changes)
let add_people_label : @ui.TextStyle = @ui.text_style(size=Meta, weight=Semibold, color=Fg, w=Full, leading=L5)

///|
/// What came of adding: the UI's size, 20 a line.
// kept across runs: a value (no field of it changes)
let add_people_said : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, w=Full, leading=L6)

