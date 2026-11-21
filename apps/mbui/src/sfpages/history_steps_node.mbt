// An agent's execution history's steps, in any pane (still.fail web/src/History.tsx, History.css.ts; ToolStep.tsx,
// ToolStep.css.ts): what the core put together (its `history` view) drawn turn by turn, each prompt that woke the agent
// beginning one (its time shown once 5 min or a day has passed); each event a mark in the gutter on the turn's rail and what it
// is beside it. What people were sent leads, on a card; the agent's own words are a grey line; the calls and thoughts
// between fold into a group, a call opening to what it asked for and what came back (the core's reading of them:
// `history.tool`). Long words fold to a few lines. A call or thought in brief is read whole as it is opened
// (`history.detail`), the pages before as the reader nears the top (`history.older`). 只看收发 leaves out what the
// core calls `work`.
//
// They are nodes of the window's tree, laid out from the styles below (style_node), in a page's list that holds each
// row only while it shows (View::scrolls_window). It follows its newest end; the page before is asked for as the reader
// comes within a height of its top, and comes in above what is read, which stays where it is (the list's top, where
// the history begins, holding nothing: what comes in comes under it); an entry gone to is brought to the middle and
// marked a moment.

///|
/// A row of the list as it was picked: the same as another where it is (steps_row_same), so its nodes are made again
/// only as what it shows changes.
priv struct StepsPicked {
  row : StepsRow?
}

///|
impl Eq for StepsPicked with equal(a, b) {
  steps_row_same(a.row, b.row)
}

///|
/// The room kept under the last row (historyBody: 40, steps_foot's).
let steps_foot_room : Double = 40.0

///|
/// How the history stands, for what its node shows: being read the first time (0), with nothing in it (1), its rows (2).
fn steps_state(h : StepsHead) -> Int {
  if h.waiting {
    0
  } else if h.empty {
    1
  } else {
    2
  }
}

///|
/// Agent `key`'s history on `station`, its steps made once in node `v`, which they fill; tips in `tips`.
pub fn history_steps_node(v : @view.View, src : Source, station : String, key : String, tips : @sf.TipLayer) -> Unit {
  let params : Map[String, Json] = { "station": Json::string(station), "key": Json::string(key) }
  let lkey = "history-steps/" + station + "/" + key
  let head = fn() { steps_head_of(src, params, lkey) }
  steps_fills(v)
  v.pick(at_once=true, fn() { steps_state(head()) }, fn(p, state) {
    steps_fills(p)
    match state {
      0 =>
        steps_box_node(p, steps_waiting, fn(b) {
          @sf.waiting_node(b, fn(s) { steps_sample_node(s, station, key, tips) }, note=fn() {
            {
              reading: true,
              text: match head().edge {
                "" => @sf.t("web-main.history.reading")
                e => e
              },
              failing: match head().failed {
                "" => []
                f => [f]
              },
            }
          })
        })
      1 =>
        steps_box_node(p, steps_box, fn(b) {
          // (in the middle across, as steps_edge says: center)
          b.lines_up(Is(Some(Middle))) |> ignore
          steps_words(b, fn() { head().edge }, steps_edge)
        })
      _ => steps_list_node(p, src, station, key, params, lkey, tips)
    }
  })
}

///|
/// The list of agent `key`'s history (its `params`, its list's key `lkey`) in `v`: see the file's head.
fn steps_list_node(
  v : @view.View,
  src : Source,
  station : String,
  key : String,
  params : Map[String, Json],
  lkey : String,
  tips : @sf.TipLayer,
) -> Unit {
  let fk = station + "\u{1}" + key
  // its rows by their keys, in order: its top, each item's by the item's, what is in flight, the phase
  let rows_epoch = Ref(0)
  let only_io_was = Ref(steps_own.only_io.untracked())
  let io_toggled = Ref(false)
  let rows : @signals.Computed[(Array[String], Map[String, StepsRow], Int)] = @signals.computed(fn(was) {
    let io_now = steps_own.only_io.get()
    let (_, all) = steps_rows_of_topic(src, params, lkey)
    let keys : Array[String] = []
    let by : Map[String, StepsRow] = Map([])
    let mut live = 0
    for r in all {
      let k = match r {
        Edge => "edge"
        Item(i, _) => "i/" + text(Some(i), "key")
        Live(_, _) => {
          live = live + 1
          "live/" + live.to_string()
        }
        Phase(_) => "phase"
      }
      keys.push(k)
      by[k] = r
    }
    match was {
      // (the same rows: the same, its epoch as it was, so nothing that reads it is told)
      Some(w) if w.0 == keys && w.1 == by => w
      _ => {
        io_toggled.val = io_now != only_io_was.val
        only_io_was.val = io_now
        rows_epoch.val = rows_epoch.val + 1
        (keys, by, rows_epoch.val)
      }
    }
  })
  let rows_rev : @signals.Signal[Int] = @signals.signal(0)
  v.reacts(fn() { rows.get().2 }, at_start=false, fn(rev) {
    rows_rev.set(rev)
  })
  let row_of = fn(k : String) -> StepsRow? {
    rows_rev.get() |> ignore
    @signals.untracked(fn() { rows.get().1.get(k) })
  }
  let scroll = @view.Scroll::list()
  // (the item gone to: brought to the middle, its ground the accent's faint one till steps_marked_ms on)
  let place : @view.ListPlace[String] = @view.ListPlace::new()
  let away : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })
  let gliding : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })
  // (the floating jump-to-bottom button fades in/out on its own leave=float_ms way when the reader scrolls away from
  // or back to the foot, scoped strictly within its overlay container)
  let float_box : Ref[@view.View?] = Ref(None)
  let set_float = fn(f : () -> Unit) {
    match float_box.val {
      Some(fl) => @view.transition(within=fl, f)
      None => f()
    }
  }
  place.on_sight(fn(s) {
    let at_foot = s.at_foot || s.from_foot <= 0.5
    if at_foot {
      set_float(fn() {
        away.set(false)
        gliding.set(false)
      })
      steps_own.kept_place.remove(lkey)
      // Once the reader scrolls back to the bottom after jumping to an entry, resume auto-following new steps.
      if !place.asking() && @signals.untracked(fn() { steps_own.focus.get(fk) }) is None && @signals.untracked(fn() { steps_own.went.contains(lkey) }) {
        steps_own.went.remove(lkey)
      }
    } else {
      if !place.asking() && s.from_foot > 24.0 {
        steps_own.kept_place[lkey] = (s.first, s.into)
      }
      set_float(fn() {
        if gliding.untracked() && !place.asking() && scroll.glides_till() is None {
          gliding.set(false)
        }
        away.set(!gliding.untracked() && s.from_foot > dmax(160.0, s.shows * 0.45))
      })
    }
  })
  // Preserve where the reader was scrolled when switching side tabs or remounting the history list.
  v.owns(fn() {
    match place.sight_live() {
      Some(s) if !(s.at_foot || s.from_foot <= 0.5) && s.from_foot > 24.0 =>
        steps_own.kept_place[lkey] = (s.first, s.into)
      Some(_) => steps_own.kept_place.remove(lkey)
      None => ()
    }
  })
  |> ignore
  if @signals.untracked(fn() { steps_own.focus.get(fk) }) is None {
    match steps_own.kept_place.get(lkey) {
      Some((saved_key, saved_into)) => place.bring(saved_key, offset=saved_into, glide=false)
      None => ()
    }
  }
  let lit : @signals.Signal[String] = @signals.signal("", same=fn(a, b) { a == b })
  let unlit = Ref(fn() {  })
  // opened at an entry: the item that draws it brought to the middle, marked a moment; one before what is loaded, the
  // pages before first (below); one 只看收发 leaves out, all of it shown again first
  v.reacts(fn() { (steps_own.focus.get(fk), rows.get().0.length()) }, fn(now) {
    guard now.0 is Some(e) else { return }
    let loaded = items(@signals.untracked(fn() { src.topic("history", params).get().value }), "items")
    match loaded.search_by(fn(i) { entries_of(Some(i)).map(fn(x) { x.0 <= e && e <= x.1 }).unwrap_or(false) }) {
      Some(at) => {
        if steps_own.only_io.untracked() && flag(loaded.get(at), "work") {
          steps_own.only_io.set(false)
        }
        let ik = text(loaded.get(at), "key")
        steps_own.focus.remove(fk)
        steps_own.went[lkey] = true
        steps_own.marked.set((lkey, ik))
        lit.set(ik)
        (unlit.val)()
        unlit.val = v.at_moment(v.cause_at() + steps_marked_ms, fn() { lit.set("") })
        place.centre("i/" + ik)
      }
      None =>
        match loaded.get(0) {
          // (the pages before asked below, as near its top)
          Some(i) if flag(@signals.untracked(fn() { src.topic("history", params).get().value }), "more") &&
            e < entries_of(Some(i)).map(fn(x) { x.0 }).unwrap_or(0) => ()
          // not there: where it opens
          _ => steps_own.focus.remove(fk)
        }
    }
  })
  // The page before, asked of the core while there is one and the core neither reads it nor waits after a read that
  // failed (it says when to ask again): as the list comes within a height of its top (the list's own to say, by where
  // it is held: View::scrolls_window's near_top; kept here as the first row shown and the first item it was told
  // with, a page come in that left that row first was never asked past, its top waiting for ever), and for an entry
  // before what is loaded, once for each first item the pages come above, till the entry is among what is loaded (by
  // the entries themselves: the entry asked for is taken off only as the rows are worked out, after the first item
  // is told, and a page more was asked for with the entry's own page just come).
  let wants_older = fn() {
    let h = steps_head_of(src, params, lkey)
    h.more && h.older == ""
  }
  // (asked once for each first item, whichever asks: near its top and an entry before what is loaded both ask as a
  // page comes, before the core says it reads; again once the core has said it reads or that a read failed)
  let asked_over : Ref[String?] = Ref(None)
  v.reacts(fn() { steps_head_of(src, params, lkey).older }, fn(older) {
    if older != "" {
      asked_over.val = None
    }
  })
  let ask_older = fn() {
    let first = @signals.untracked(fn() { steps_head_of(src, params, lkey).first })
    guard asked_over.val != Some(first) else { return }
    asked_over.val = Some(first)
    (src.call)("history.older", Json::object(params), fn(res) {
      // (an entry asked for before what could be had: where it opens; not asked: asked again as it nears its top)
      if res is Err(_) {
        steps_own.focus.remove(fk)
        asked_over.val = None
      }
    })
  }
  let entry_before = fn() {
    guard steps_own.focus.get(fk) is Some(e) else { return false }
    match items(src.topic("history", params).get().value, "items").get(0) {
      Some(i) => e < entries_of(Some(i)).map(fn(x) { x.0 }).unwrap_or(0)
      None => true
    }
  }
  v.reacts(fn() { (wants_older() && entry_before(), steps_head_of(src, params, lkey).first) }, fn(now) {
    if now.0 {
      ask_older()
    }
  })
  steps_box_node(v, steps_box, fn(b) {
    steps_fills(b)
    b.box(fn(l) {
      steps_fills(l)
      let make_row = fn(p : @view.View, row : StepsRow) {
        let row_style = match row {
          Edge => steps_row_first
          Item(item, _) if field(Some(item), "turn") is Some(Object(_)) && turn_time_of(Some(item)) == "" =>
            steps_row_turn
          _ => steps_row
        }
        steps_box_node(p, row_style, fn(r) {
          match row {
            Edge =>
              r.pick(at_once=true, fn() { steps_head_of(src, params, lkey).more }, fn(e, more) {
                if more {
                  steps_box_node(e, steps_edge_wait, fn(w) {
                    @sf.wait_line_node(w, fn() { steps_head_of(src, params, lkey).edge }) |> ignore
                  })
                } else {
                  // (in the middle across, as steps_edge says: center)
                  e.lines_up(Is(Some(Middle))) |> ignore
                  steps_words(e, fn() { steps_head_of(src, params, lkey).edge }, steps_edge)
                }
              })
            Item(item, rail) =>
              history_row_node(r, src, station, key, Some(item), rail, tips, marked=fn() {
                lit.get() == text(Some(item), "key")
              })
            Live(l, rail) =>
              steps_main_node(r, fn(m) {
                ev_node(m, "think", "", "", rail_last=rail, fn(b) {
                  steps_box_node(b, h_one, fn(o) { steps_words(o, fn() { text(Some(l), "text") }, live_words) })
                })
              })
            Phase(ph) => phase_line_node(r, src, Some(ph))
          }
        })
      }
      l.scrolls_window(
        scroll,
        fn() { rows.get().0 },
        est=steps_est,
        bar=@ui.tree_scroll_bar(),
        // (the room under its last entry: its foot, drawing nothing)
        foot=fn(f) { f.height(Is(Some(steps_foot_room))) |> ignore },
        // (its top, where it begins or the pages before come, stands over what comes in under it)
        holds=fn(k) { k != "edge" },
        // (followed at its newest; paused while viewing a jumped-to entry, resumed on returning to bottom)
        follows=fn() { !steps_own.went.contains(lkey) },
        place~,
        // (new steps and phase rows glide in; filter switches and the top edge row settle at once)
        comes=fn(k) { !io_toggled.val && k != "edge" },
        goes=fn(k) { !io_toggled.val && k != "edge" },
        near_top=(0.5, wants_older, ask_older),
        reused=fn(k) { steps_row_shape(rows.untracked().1.get(k), station, key) },
        make_reused=fn(slot, row_key) {
          steps_reused_row_node(slot, src, station, key, row_of, row_key, lit, tips, make_row)
        },
        fn(slot, k) {
          slot.pick(at_once=true, fn() { StepsPicked::{ row: row_of(k) } }, fn(p, picked) {
            guard picked.row is Some(row) else { return }
            make_row(p, row)
          })
        },
      )
      |> ignore
    })
    |> ignore
    // Floating jump-to-bottom button when scrolled up away from the latest step.
    b.box(fn(fl) {
      float_box.val = Some(fl)
      fl
      .over(Is(true))
      .points(Is(false))
      .lies_along(Is(End))
      .lines_up(Is(Some(End)))
      .padding(Is((0.0, 0.0, 12.0, 12.0)))
      |> ignore
      fl.show(fn() { away.get() && !gliding.get() }, at_once=true, leave=float_ms, fn(stand) {
        stand
        .points(Is(false))
        .alpha(By(@motion.presence_in(stand, @motion.tween(float_ms, ease=Out), from=0.0)))
        |> ignore
        @sf.float_button_node(
          stand,
          "arrow-down",
          fn() { @sf.t("web-main.chat.toLatest") },
          fn() {
            steps_own.went.remove(lkey)
            steps_own.kept_place.remove(lkey)
            set_float(fn() {
              gliding.set(true)
              away.set(false)
            })
            place.to_end()
          },
          tips~,
        )
        |> ignore
      })
    })
    |> ignore
  })
}

///|
/// `v` taking the room it is given down its column, no more: as tall as that whatever what it holds asks (its list
/// scrolling in it), never as tall as all of it.
fn steps_fills(v : @view.View) -> Unit {
  v.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
}

///|
/// A box of `look` (laid on it as an old view's box of that style is laid out, style_node) in `parent`, what `make`
/// makes in it; `in_row`: in a row (w=Full and a grow along it).
fn steps_box_node(parent : @view.View, look : @ui.Style, make : (@view.View) -> Unit, in_row? : Bool = false) -> Unit {
  parent.box(fn(b) {
    @sf.style_node(b, fn() { look }, in_row~)
    make(b)
  })
  |> ignore
}

///|
/// Words of `style` in `parent` as they are said: giving way in a row where they cut or wrap (min_width 0).
fn steps_words(parent : @view.View, words : () -> String, style : @ui.TextStyle) -> Unit {
  @sf.words_node(parent, words, fn() { style }).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
}

///|
/// Words of `style` in one run in `parent`: in the code face where `mono`, struck through where `strike`, underlined
/// while `underline` says (Ctx::rich's of one span).
fn steps_run(
  parent : @view.View,
  words : () -> String,
  style : @ui.TextStyle,
  mono? : Bool = false,
  strike? : Bool = false,
  underline? : () -> Bool = fn() { false },
  ink? : () -> Int64 = fn() { 0L },
) -> Unit {
  parent.box(fn(w) {
    w
    .words_runs(By(fn() { [@ui.span(words(), mono~, strike~, underline=underline(), color=ink())] }))
    .words_look(By(fn() { @ui.style_words(style) }))
    .ink(By(fn() { @ui.style_ink(style) }))
    .shrink(Is(1.0))
    .min_width(Is(Some(0.0)))
    |> ignore
    if @ui.style_cut(style) {
      w.cuts(Is(true)).allow_ellipsis(Is(true)) |> ignore
    }
  })
  |> ignore
}

///|
/// A row pressed as a whole made in `parent` and laid out by `look`: `press` done as it is, read out a button named
/// `label` (one that `folds` open as `open` says, or shut, a disclosure). The node.
fn steps_press_box(
  parent : @view.View,
  press : () -> Unit,
  look : (@view.View) -> Unit,
  label? : () -> String = fn() { "" },
  folds? : Bool = false,
  open? : () -> Bool = fn() { false },
) -> @view.View {
  if folds {
    @sf.action_box_node(parent, label, fn(_) { press() }, look, expanded=open)
  } else {
    @sf.action_box_node(parent, label, fn(_) { press() }, look)
  }
}

///|
/// One of what the reader opens (a fold, a line, a group, a call), by its key, opened or shut (what was pressed
/// staying where it was: mbui's press_stays.mbt). Closing a failed detail clears its error so reopening retries.
fn steps_flip(key : String) -> Unit {
  @view.transition(fn() {
    if steps_own.opened.contains(key) {
      steps_own.opened.remove(key)
      match @signals.untracked(fn() { steps_own.detail.get(key) }) {
        Some((-2.0, _)) => steps_own.detail.remove(key)
        _ => ()
      }
    } else {
      steps_own.opened[key] = true
    }
  })
}

///|
/// A clock running in `v` from `since` (the core's time: `src.now`), read again each whole second from then as it is
/// shown, no longer than `till` (ms after it, none: on), the test's idle not waiting on it (Ctx::every's): what reads
/// the time of it reads what this returns.
pub fn steps_seconds(v : @view.View, src : Source, since : Double, till? : Double) -> () -> Int {
  let tick : @signals.Signal[Int] = @signals.signal(0)
  fn plan() -> Unit {
    let gone = (src.now)() - since
    if till is Some(t) && gone >= t {
      return
    }
    let into = if gone > 0.0 { gone - (gone / second_ms).floor() * second_ms } else { gone }
    v.at_moment(v.logic_at() + second_ms - into, later=true, fn() {
      tick.set(tick.untracked() + 1)
      plan()
    })
    |> ignore
  }

  plan()
  fn() { tick.get() }
}

///|
/// The history's rows to come while it is read the first time in `v`, as its list draws them.
pub fn steps_sample_node(v : @view.View, station : String, key : String, tips : @sf.TipLayer) -> Unit {
  let lines = [("group", 16), ("text", 24), ("group", 12), ("group", 20), ("text", 9), ("group", 18)]
  for i, line in lines {
    let (kind, n) = line
    let words = Json::string(@sf.sample_words(n))
    let content : Json = if kind == "group" { { "summary": words } } else { { "text": words, "line": words } }
    let item : Map[String, Json] = {
      "key": Json::string("sample" + i.to_string()),
      "body": { "kind": Json::string(kind), "content": content },
    }
    if i == 0 {
      item["turn"] = { "time": Json::string(@sf.sample_words(4)) }
    }
    let item = Json::object(item)
    steps_box_node(v, if i == 0 { steps_row_first } else { steps_row }, fn(r) {
      history_row_node(r, @sfbase.sample_source, station, key, Some(item), i + 1 < lines.length(), tips)
    })
  }
}

///|
fn turn_time_of(item : Json?) -> String {
  match field(item, "turn") {
    Some(Object(_)) as turn => text(turn, "time")
    _ => ""
  }
}

///|
/// An item in `v`: the time of the turn it begins (when shown), then its events; on the accent's faint ground while
/// `marked` says (an entry gone to).
fn history_row_node(
  v : @view.View,
  src : Source,
  station : String,
  key : String,
  item : Json?,
  rail : Bool,
  tips : @sf.TipLayer,
  marked? : () -> Bool = fn() { false },
) -> Unit {
  let ik = steps_item_key(station, key, text(item, "key"))
  v.box(fn(b) {
    @sf.style_node(b, fn() { h_item })
    // (gone to: on the accent's faint ground a moment, hItem[data-focus])
    b.ground(By(fn() { if marked() { @ui.tree_theme().color(A(Accent, O10)) } else { 0L } })) |> ignore
    let time = turn_time_of(item)
    if time != "" {
      steps_box_node(b, h_turn, fn(t) {
        t.box(fn(w) {
          w
          .words(Is(time))
          .words_look(By(fn() { @ui.style_words(h_turn_words) }))
          .ink(By(fn() { @ui.style_ink(h_turn_words) }))
          .cuts(Is(true))
          .min_width(Is(Some(0.0)))
          .allow_ellipsis(Is(true))
          |> ignore
        })
        |> ignore
      })
    }
    steps_main_node(b, fn(m) { item_node(m, src, station, key, ik, item, rail, tips) })
  })
  |> ignore
}

///|
/// An item's events, one under another (hMain).
fn steps_main_node(v : @view.View, body : (@view.View) -> Unit) -> Unit {
  steps_box_node(v, h_main, body)
}

///|
/// The side rail's points for an event whose header row is `head_h` tall (its `20×20` icon pulled `6px` left, centred
/// at `x = 4.0`) and whose subordinate body below it (`pl = S5`, clear of the rail) is `body_h` tall. The rail is one
/// straight line at `x = 4.0` from the icon's bottom `(4.0, 20.0)`:
/// - on to the next event's icon (`head_h + body_h + 10.0`) when `rail_next` is true;
/// - otherwise down beside the body to `2px` above its end, or nothing when there is no body.
fn rail_pts(head_h : Double, body_h : Double, rail_next : Bool) -> Array[Double] {
  if rail_next {
    [4.0, 20.0, 4.0, head_h + body_h + 10.0]
  } else if body_h <= 2.0 {
    []
  } else {
    [4.0, 20.0, 4.0, dmax(21.0, head_h + body_h - 2.0)]
  }
}

///|
fn rail_shapes(head_h : Double, body_h : Double, rail_next : Bool, color : Int64) -> Array[@ui.Shape] {
  let pts = rail_pts(head_h, body_h, rail_next)
  if pts.is_empty() {
    []
  } else {
    [@ui.shape_of([(pts, false)], stroke=color, width=1.25)]
  }
}

///|
/// The side rail as a `GroundShape` for a `1.25 × 1.0` overlay box anchored at `(0, 0)`, matching `rail_pts` so
/// `View::shown_by` tracks an expanding or folding body frame-accurately without per-frame layout reads.
fn rail_ground(head_h : Double, body_h : Double, rail_next : Bool) -> @view.GroundShape {
  match rail_pts(head_h, body_h, rail_next) {
    [_, y0, _, y1] if y1 > y0 => { dx: 3.375, dy: y0, dw: 0.0, dh: y1 - y0 - 1.0, corners: None }
    _ => { dx: 3.375, dy: 20.0, dw: 0.0, dh: -1.0, corners: None }
  }
}

///|
/// Overlay side-rail box at `x = 4.0` in `v`; callers with animated bodies bind it via `View::shown_by`.
fn steps_rail_box_node(
  v : @view.View,
  color : () -> Int64,
  head_h : () -> Double,
  rail_next : () -> Bool,
) -> @view.View {
  v.box(fn(rail) {
    rail
    .over(Is(true))
    .points(Is(false))
    .width(Is(Some(1.25)))
    .height(Is(Some(1.0)))
    .ground(By(color))
    .ground_drawn(By(fn() { rail_ground(head_h(), 0.0, rail_next()) }))
    |> ignore
  })
}

///|
/// Full-width event stack in `parent`: `head` renders the top event row (with its `20×20` `h_icon` centered at
/// `x = 4.0`), `body` renders the subordinate block below it (indented by `pl = S5`, the column of the head's words), and an overlay rail runs
/// straight down at `x = 4.0` from `(4.0, 20.0)` beside `body` and on to the next event (`+10.0`) when `rail_next` is
/// true.
fn event_stack_node(
  parent : @view.View,
  failed? : () -> Bool = fn() { false },
  rail_next? : () -> Bool = fn() { false },
  head : (@view.View) -> Unit,
  body : (@view.View) -> Unit,
) -> Unit {
  parent.by_room(fn(v, room) {
    @sf.style_node(v, fn() { h_group })
    let head_ref : Ref[@view.View?] = Ref(None)
    let body_ref : Ref[@view.View?] = Ref(None)
    let head_h = fn() {
      match head_ref.val {
        Some(h) => dmax(20.0, room.tall(h))
        None => 20.0
      }
    }
    let body_h = fn() {
      match body_ref.val {
        Some(b) => dmax(0.0, room.tall(b))
        None => 0.0
      }
    }
    v.box(fn(h) {
      h.fills_across(Is(true)) |> ignore
      head_ref.val = Some(h)
      head(h)
    })
    |> ignore
    v.box(fn(b) {
      b.fills_across(Is(true)) |> ignore
      body_ref.val = Some(b)
      body(b)
    })
    |> ignore
    v.shapes(By(fn() {
      let color = @ui.tree_theme().color(if failed() { Danger } else { Line })
      rail_shapes(head_h(), body_h(), rail_next(), color)
    }))
    |> ignore
  })
  .fills_across(Is(true))
  |> ignore
}

///|
/// Full-width event stack whose subordinate body reveals and hides smoothly via `steps_reveal_node`, keeping the side
/// rail synchronized with the reveal node's animated height on every frame (`View::shown_by`).
fn event_reveal_stack_node(
  parent : @view.View,
  open : () -> Bool,
  failed? : () -> Bool = fn() { false },
  rail_next? : () -> Bool = fn() { false },
  head : (@view.View) -> Unit,
  body : (@view.View) -> Unit,
) -> Unit {
  parent.by_room(fn(v, room) {
    @sf.style_node(v, fn() { h_group })
    let head_ref : Ref[@view.View?] = Ref(None)
    let head_h = fn() {
      match head_ref.val {
        Some(h) => dmax(20.0, room.tall(h))
        None => 20.0
      }
    }
    v.box(fn(h) {
      h.fills_across(Is(true)) |> ignore
      head_ref.val = Some(h)
      head(h)
    })
    |> ignore
    let rail = steps_rail_box_node(
      v,
      fn() { @ui.tree_theme().color(if failed() { Danger } else { Line }) },
      head_h,
      rail_next,
    )
    steps_reveal_node(v, open, fn(s) {
      rail.shown_by(s, fn(s_tall) {
        rail_ground(@signals.untracked(head_h), s_tall, @signals.untracked(rail_next))
      })
      |> ignore
      body(s)
    })
  })
  .fills_across(Is(true))
  |> ignore
}

///|
/// One event in `v`: its mark in the gutter and what `body` makes beside it.
fn ev_node(
  v : @view.View,
  icon : String,
  state : String,
  tone : String,
  rail? : Bool = false,
  rail_last? : Bool = false,
  row? : Bool = false,
  body : (@view.View) -> Unit,
) -> Unit {
  let ink = fn() {
    let t = @sf.theme()
    match (state, tone) {
      ("done", _) => t.p.green
      ("waiting", _) => t.p.blue
      ("human", _) => t.p.accent_text
      (_, "accent") => t.p.accent
      (_, "red") => t.p.red
      _ => t.p.muted
    }
  }
  ignore(row)
  let make_ev = fn(e : @view.View) {
    e.box(fn(i) {
      @sf.style_node(i, fn() { h_icon })
      if icon == "pulse" {
        steps_box_node(i, h_pulse, fn(_) {  })
      } else {
        @sf.icon_node(i, icon, 14.0, By(ink)) |> ignore
      }
    })
    |> ignore
    steps_box_node(e, h_ev_body, body, in_row=true)
  }
  if rail || rail_last {
    v.by_room(fn(p, room) {
      p.fills_across(Is(true)) |> ignore
      let row_ref : Ref[@view.View?] = Ref(None)
      let tall = fn() {
        match row_ref.val {
          Some(r) => dmax(20.0, room.tall(r))
          None => 20.0
        }
      }
      steps_box_node(p, h_ev, fn(e) {
        row_ref.val = Some(e)
        make_ev(e)
      })
      p.shapes(By(fn() {
        let color = @ui.tree_theme().color(if tone == "red" { Danger } else { Line })
        rail_shapes(tall(), 0.0, rail || rail_last, color)
      }))
      |> ignore
    })
    .fills_across(Is(true))
    |> ignore
  } else {
    steps_box_node(v, h_ev, make_ev)
  }
}

///|
/// What an item is in `v`.
fn item_node(
  v : @view.View,
  src : Source,
  station : String,
  key : String,
  ik : String,
  item : Json?,
  rail : Bool,
  tips : @sf.TipLayer,
) -> Unit {
  let body = field(item, "body")
  let content = field(body, "content")
  match text(body, "kind") {
    "received" => {
      let note = text(content, "note")
      let tasks = items(content, "tasks")
      let messages = items(content, "messages")
      let n = (if note != "" { 1 } else { 0 }) + tasks.length() + messages.length()
      let mut at = 0
      let next = fn() {
        at = at + 1
        at < n
      }
      if note != "" {
        let more = next()
        let first = first_line(note)
        let single = note == first && !note.contains("\n")
        let rem_label = @sf.t("web-main.history.reminder", args=[("name", @sf.product())])
        one_line_ev_node(
          v,
          "bell",
          "",
          ik + "/note",
          more || rail,
          single~,
          lead_text=rem_label,
          lead_pt=12.0,
          lead_pad=6.0,
          fn(l) {
            @sf.words_node(l, fn() { rem_label }, fn() { h_reminder })
            .shrink(Is(0.0))
            |> ignore
          },
          first,
          "",
          fn(w) {
            card_plain_or_clip_node(w, rem_label, note, h_note_plain)
          },
        )
      }
      for k, task in tasks {
        let more = next()
        task_node(v, ik + "/task/" + k.to_string(), Some(task), more, !more && rail)
      }
      for k, m in messages {
        let more = next()
        received_node(v, src, station, ik + "/message/" + k.to_string(), Some(m), more, !more && rail, tips)
      }
    }
    // the agent's own words reach no one (only what it posts does): a grey line, opened in a faint card below
    "text" => {
      let words = text(content, "text")
      let line = text(content, "line")
      let sub = flag(content, "subagent")
      let single = words == line && !words.contains("\n")
      let text_label = if sub { @sf.t("web-main.history.subagent") } else { first_line(line) }
      if sub {
        let sub_label = @sf.t("web-main.history.subagent")
        one_line_ev_node(
          v,
          "said",
          "",
          ik + "/text",
          rail,
          single~,
          lead_text=sub_label,
          lead_pt=11.0,
          lead_pad=16.0,
          fn(l) {
            // (a chip: in bones one piece)
            l.box(fn(tag) {
              @sf.style_node(tag, fn() { h_tag })
              tag.bone_whole(Is(true)) |> ignore
              steps_words(tag, fn() { sub_label }, h_tag_words)
            })
            |> ignore
          },
          line,
          "",
          fn(w) { card_md_or_clip_node(w, text_label, words, field(content, "md"), small=true) },
        )
      } else if single && single_line_px(words) <= 220.0 {
        ev_node(v, "said", "", "", rail_last=rail, row=true, fn(b) {
          steps_box_node(b, h_one, fn(o) { steps_words(o, fn() { line }, h_one_words) })
        })
      } else {
        one_line_ev_node(
          v,
          "said",
          "",
          ik + "/text",
          rail,
          single~,
          fn(_) {  },
          line,
          "",
          fn(w) { card_md_or_clip_node(w, text_label, words, field(content, "md"), small=true) },
        )
      }
    }
      "post" => {
      let ends = text(content, "ends")
      let failed = flag(content, "failed")
      let words = text(content, "text")
      let md = field(content, "md")
      let pkey = ik + "/post"
      let gaps = md_preview_gaps(md, post_lines)
      message_fold_stack_node(
        v,
        fn() { pkey },
        "send",
        fn() { if failed { "red" } else { "accent" } },
        failed=fn() { failed },
        rail_next=fn() { ends != "" || rail },
        extra_gap=fn() { gaps },
        body_pad=24.0,
        wrap_label=true,
        post_lines,
        md_line,
        fn(l) {
          steps_label_words(l, fn() { @sf.t("web-main.history.sentTo") }, h_label_words)
          match field(content, "place") {
            Some(Object(_)) as p => place_node(l, station, p)
            _ =>
              steps_box_node(l, h_place, fn(pl) {
                steps_box_node(pl, h_place_mark, fn(d) {
                  @sf.drawable_node(d, "slack", 12.0) |> ignore
                })
                steps_words(pl, fn() { "Slack" }, h_place_words)
              })
          }
          if flag(content, "block") && ends == "" {
            @sf.badge_node(l, fn() { "Block" }, tone=Blue) |> ignore
          }
          if failed {
            @sf.badge_node(l, fn() { @sf.t("web-main.history.sendFailed") }, tone=Red) |> ignore
          }
        },
        fn(ev, body_ref, inside) {
          ev.box(fn(pb) {
            @sf.style_node(pb, fn() { h_post_body })
            body_ref.val = Some(pb)
            steps_box_node(pb, if failed { h_card_failed } else { h_card }, fn(card) {
              card.edge(By(fn() { (1.0, @ui.tree_theme().color(if failed { Danger } else { Line })) })) |> ignore
              inside(card)
            })
          })
          |> ignore
        },
        fn(f) { md_node(f, words, md) },
      )
      if ends != "" {
        ended_node(
          v,
          ik + "/ended",
          ends,
          @sf.t(if ends == "human" { "web-main.history.ends.human" } else { "web-main.history.ends.done" }),
          rail,
        )
      }
    }
    "mark" => mark_node(v, src, ik + "/mark", content, rail)
    "group" => group_node(v, src, station, key, ik, content, rail, tips)
    _ => ()
  }
}

///|
/// Words as Markdown in `v`: the panel's size, or small and grey.
fn md_node(v : @view.View, words : String, md : Json?, small? : Bool = false) -> Unit {
  md_live_node(v, fn() { words }, fn() { md }, small~)
}

///|
fn md_live_node(v : @view.View, words : () -> String, md : () -> Json?, small? : Bool = false) -> Unit {
  @sf.markdown_node(v, words, tree=md, size=fn() { if small { 12.0 } else { 13.0 } }, ink=fn() {
    if small {
      @sf.theme().p.muted
    } else {
      0L
    }
  })
  |> ignore
}

///|
/// A block under its line in `parent` that opens and closes smoothly across the full row width (`cuts_softly`),
/// without `@motion.reveal_node`'s horizontal center-scaling.
fn steps_reveal_node(parent : @view.View, open : () -> Bool, make : (@view.View) -> Unit) -> Unit {
  parent.show(open, fn(s) {
    s.fills_across(Is(true)).cuts_softly(Is(true)) |> ignore
    make(s)
  })
}

///|
fn steps_opened_contains_fn(key_fn : () -> String) -> Bool {
  !steps_own.opened.is_empty() && steps_own.opened.contains(key_fn())
}

///|
/// A chevron icon in `parent` that rotates smoothly on `@motion.moved()` when `open` changes (`"chevron-right"`
/// turns +pi/2 to down; `"chevron-down"` turns -pi to up).
fn steps_chevron_node(
  parent : @view.View,
  name : String,
  size : Double,
  color : @view.Live[Int64],
  open : () -> Bool,
) -> Unit {
  let turn_rad = if name == "chevron-right" { 1.5707963267948966 } else { -3.141592653589793 }
  let way = @motion.Way::new(if @signals.untracked(open) { 1.0 } else { 0.0 })
  let icon = @sf.icon_node(parent, name, size, color)
  icon.reacts(open, at_start=false, fn(o) {
    let target = if o { 1.0 } else { 0.0 }
    if @view.answering_now() {
      way.put(target)
    } else {
      way.go(target, @motion.moved(), at=icon.cause_at())
    }
  })
  icon
  .turn(
    By(fn() {
      way.said()
      way.value_at(icon.drawn_while(fn(t) { way.goes_at(t) })) * turn_rad
    }),
    drawn=true,
  )
  |> ignore
}

///|
/// The mark at the end of a row `r` pressed to open and shut what it holds: a 12 chevron turning as it opens, in a box
/// as high as the row's first line, so on a row of several lines it stays by the first.
fn steps_fold_mark_node(r : @view.View, open : () -> Bool) -> Unit {
  r.box(fn(c) {
    @sf.style_node(c, fn() { h_one_mark })
    c.shrink(Is(0.0)) |> ignore
    steps_chevron_node(
      c,
      "chevron-down",
      12.0,
      By(fn() { if @sf.lit_node(r) { @sf.theme().p.blue } else { @sf.theme().p.muted } }),
      open,
    )
  })
  |> ignore
}

///|
/// An event in one line in `v`: `lead`, then `line` cut at its end; pressed (where `single` does not fit on one line
/// or `whole` has multiple lines), what `whole` makes under it in a faint rounded card beside the side rail, its header
/// row staying in place and its chevron turning.
fn one_line_ev_node(
  v : @view.View,
  icon : String,
  ev_tone : String,
  key : String,
  rail_next : Bool,
  single? : Bool = false,
  lead_text? : String = "",
  lead_pt? : Double = 0.0,
  lead_pad? : Double = 0.0,
  lead : (@view.View) -> Unit,
  line : String,
  tone : String,
  whole : (@view.View) -> Unit,
) -> Unit {
  let make_flat = fn(host : @view.View) {
    ev_node(host, icon, "", ev_tone, rail_last=rail_next, row=true, fn(b) {
      steps_box_node(b, h_one, fn(r) {
        lead(r)
        if line != "" {
          steps_words(r, fn() { line }, if tone == "red" { h_one_red } else { h_one_words })
        }
      })
    })
  }
  let make_expandable = fn(host : @view.View) {
    let open = fn() { steps_own.opened.contains(key) }
    event_reveal_stack_node(
      host,
      open,
      rail_next=fn() { rail_next },
      fn(ev) {
        ev_node(ev, icon, "", ev_tone, row=true, fn(b) {
          steps_press_box(b, fn() { steps_flip(key) }, label=fn() { line }, folds=true, open~, fn(r) {
            @sf.style_node(r, fn() { h_one_press })
            lead(r)
            if line != "" {
              r.box(fn(l) {
                l.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
                @sf.words_node(l, fn() { line }, fn() {
                  if tone == "red" {
                    h_one_red
                  } else if @sf.lit_node(r) {
                    h_one_hot
                  } else {
                    h_one_words
                  }
                })
                |> ignore
              })
              |> ignore
            } else {
              steps_box_node(r, h_grow, fn(_) {  }, in_row=true)
            }
            steps_fold_mark_node(r, open)
          })
          |> ignore
        })
      },
      fn(b) {
        steps_box_node(b, h_post_body, fn(pb) { steps_box_node(pb, h_one_card, whole) })
      },
    )
  }
  if !single {
    make_expandable(v)
    return
  }
  if lead_text == "" && single_line_px(line) <= 160.0 {
    make_flat(v)
    return
  }
  v.by_room(fn(vp, room) {
    vp.fills_across(Is(true)) |> ignore
    let fits = room_fits_one_line(
      vp,
      room,
      lead_text,
      lead_pt,
      lead_pad,
      line,
      @ui.style_words(h_one_words).size,
      22.0,
    )
    vp.pick(at_once=true, fits, fn(p, is_short) {
      p.fills_across(Is(true)) |> ignore
      if is_short {
        make_flat(p)
      } else {
        make_expandable(p)
      }
    })
  })
  .fills_across(Is(true))
  |> ignore
}

///|
/// Clips a long block inside an already-expanded tool card or task card to `lines` lines (with `cuts_softly`),
/// showing a bottom `查看完整内容` strip whenever the measured content actually overflows `lines` lines.
fn clip_lines_node(
  v : @view.View,
  lines : Int,
  line : Double,
  body : (@view.View) -> Unit,
  on_full? : (() -> Unit)? = None,
) -> Unit {
  v.by_room(fn(v, given) {
    v.fills_across(Is(true)) |> ignore
    let line_h = fn() { @sf.node_sp(v, line) }
    let most = fn() { lines.to_double() * line_h() + 2.0 }
    let inner : Ref[@view.View?] = Ref(None)
    let tall = fn() {
      match inner.val {
        Some(i) => given.tall(i)
        None => 0.0
      }
    }
    let clipped_sig = @signals.computed(fn(_) { tall() > most() + 1.5 * line_h() }, same=fn(a, b) { a == b })
    let clipped = fn() { clipped_sig.get() }
    steps_box_node(v, h_fold_room, fn(room) {
      steps_box_node(room, h_fold_inner, fn(i) {
        i.shrink(Is(0.0)).offset(By(fn() { (0.0, 0.0) })) |> ignore
        inner.val = Some(i)
        body(i)
      })
      room
      .holds_whole()
      .cuts_softly(By(clipped))
      .max_height(By(fn() { if clipped() { Some(most()) } else { None } }))
      |> ignore
    })
    match on_full {
      Some(open_full) =>
        v.show(at_once=true, clipped, fn(foot) {
          foot.fills_across(Is(true)) |> ignore
          steps_press_box(foot, open_full, label=fn() { "查看完整内容" }, fn(btn) {
            @sf.style_node(btn, fn() { tool_clip_more })
            let ink = fn() { if @sf.lit_node(btn) { @sf.theme().p.accent } else { @sf.theme().p.blue } }
            @sf.icon_node(btn, "expand", 11.0, By(ink)) |> ignore
            @sf.words_node(btn, fn() { "查看完整内容" }, fn() {
              if @sf.lit_node(btn) {
                tool_expand_words_hot
              } else {
                tool_expand_words
              }
            })
            |> ignore
          })
          |> ignore
        })
      None => ()
    }
  })
  .fills_across(Is(true))
  |> ignore
}

///|
/// Whether a block might wrap past 14 lines on a narrow side panel and should measure height with `clip_lines_node`.
fn may_clip_block(words : String) -> Bool {
  if is_long_block(words) || words.length() > 180 {
    return true
  }
  let mut nl = 0
  for ch in words {
    if ch == '\n' {
      nl = nl + 1
      if nl >= 6 {
        return true
      }
    }
  }
  false
}

///|
/// Renders Markdown (with plain-words test fallback) inside an expanded card, clipping blocks longer than 14 lines and
/// offering `复制` / `全屏查看` in the card's top bar and a bottom `查看完整内容` strip whenever actually clipped.
fn card_md_or_clip_node(v : @view.View, title : String, words : String, md : Json?, small? : Bool = true) -> Unit {
  let open_full = fn() {
    open_tool_reader(title, words, fn(rb) { render_md_or_words(rb, words, md, small=false) })
  }
  if is_long_block(words) {
    steps_box_node(v, tool_field_stack, fn(stack) {
      steps_box_node(stack, tool_block_bar, fn(bar) {
        steps_words(bar, fn() { title }, tool_key_words)
        steps_box_node(bar, h_grow, fn(_) {  }, in_row=true)
        tool_copy_btn_node(bar, words)
        tool_expand_btn_node(bar, title, words, fn(rb) {
          render_md_or_words(rb, words, md, small=false)
        })
      })
      clip_lines_node(stack, 14, md_line, fn(f) { render_md_or_words(f, words, md, small~) }, on_full=Some(open_full))
    })
  } else if may_clip_block(words) {
    clip_lines_node(v, 14, md_line, fn(f) { render_md_or_words(f, words, md, small~) }, on_full=Some(open_full))
  } else {
    render_md_or_words(v, words, md, small~)
  }
}

///|
/// Renders plain or monospace text inside an expanded card, clipping blocks longer than 14 lines with `复制` / `全屏查看`.
fn card_plain_or_clip_node(
  v : @view.View,
  title : String,
  words : String,
  style : @ui.TextStyle,
  mono? : Bool = false,
) -> Unit {
  let draw = fn(host : @view.View) {
    if mono {
      steps_run(host, fn() { words }, style, mono=true)
    } else {
      steps_words(host, fn() { words }, style)
    }
  }
  let open_full = fn() { open_tool_reader(title, words, draw) }
  if is_long_block(words) {
    steps_box_node(v, tool_field_stack, fn(stack) {
      steps_box_node(stack, tool_block_bar, fn(bar) {
        steps_words(bar, fn() { title }, tool_key_words)
        steps_box_node(bar, h_grow, fn(_) {  }, in_row=true)
        tool_copy_btn_node(bar, words)
        tool_expand_btn_node(bar, title, words, draw)
      })
      clip_lines_node(stack, 14, words_line, draw, on_full=Some(open_full))
    })
  } else if may_clip_block(words) {
    clip_lines_node(v, 14, words_line, draw, on_full=Some(open_full))
  } else {
    draw(v)
  }
}

///|
fn steps_label_words(parent : @view.View, words : () -> String, style : @ui.TextStyle) -> Unit {
  steps_words(parent, words, style)
}

///|
/// Inter-block vertical gaps (`markdown.mbt`'s `paragraph_after = 8.0`) within the first `lines` blocks of a Markdown
/// tree, so a 3-line preview of multi-paragraph messages keeps all 3 lines whole without slicing the 3rd line.
fn md_preview_gaps(md : Json?, lines : Int) -> Double {
  match md {
    Some(Array(blocks)) if blocks.length() > 1 => {
      let max_gaps = if lines > 1 { lines - 1 } else { 0 }
      let gaps = if blocks.length() - 1 < max_gaps { blocks.length() - 1 } else { max_gaps }
      gaps.to_double() * 8.0
    }
    _ => 0.0
  }
}

///|
/// Whether plain-text `words` fits within `words_lines` (3 lines) on every window width and font scale (`<= 64` display
/// columns, single paragraph), so short received messages skip fold measurement and button subtrees entirely.
fn short_plain_words(words : String) -> Bool {
  if words.contains("\n") || words.length() > 64 {
    return false
  }
  let mut w = 0
  for c in words {
    w = w + (if c <= '\u{7f}' { 1 } else { 2 })
    if w > 64 {
      return false
    }
  }
  true
}

///|
/// A received or sent message event in `v` whose body folds to `lines` lines when taller than `lines` lines, with its
/// expand/collapse button (`展开 · 还有 N 行 ⌄` / `收起 ⌃`) anchored at the right end of the first header line so opening
/// or shutting never moves the pressed control.
fn message_fold_stack_node(
  v : @view.View,
  key_fn : () -> String,
  icon : String,
  tone : () -> String,
  failed? : () -> Bool = fn() { false },
  rail_next? : () -> Bool = fn() { false },
  extra_gap? : () -> Double = fn() { 0.0 },
  body_pad? : Double = 6.0,
  wrap_label? : Bool = true,
  lines : Int,
  line : Double,
  label : (@view.View) -> Unit,
  wrap_body : (@view.View, Ref[@view.View?], (@view.View) -> Unit) -> Unit,
  body : (@view.View) -> Unit,
) -> Unit {
  let open_sig = @signals.computed(fn(_) { steps_opened_contains_fn(key_fn) }, same=fn(a, b) { a == b })
  let open = fn() { open_sig.get() }
  v.by_room(fn(vp, given) {
    @sf.style_node(vp, fn() { h_group })
    vp.fills_across(Is(true)) |> ignore
    let line_h = fn() { @sf.node_sp(vp, line) }
    let most = fn() { lines.to_double() * line_h() + extra_gap() + 2.0 }
    let stride = fn() { if extra_gap() > 0.0 { line_h() + 8.0 } else { line_h() } }
    let head_ref : Ref[@view.View?] = Ref(None)
    let body_ref : Ref[@view.View?] = Ref(None)
    let room_ref : Ref[@view.View?] = Ref(None)
    let inner : Ref[@view.View?] = Ref(None)
    let head_h = fn() {
      match head_ref.val {
        Some(h) => dmax(20.0, given.tall(h))
        None => 20.0
      }
    }
    let tall = fn() {
      match inner.val {
        Some(i) => given.tall(i)
        None => 0.0
      }
    }
    let long_sig = @signals.computed(fn(_) { tall() > most() + 0.65 * line_h() }, same=fn(a, b) { a == b })
    let long = fn() { long_sig.get() }
    let head_slot : Ref[@view.View?] = Ref(None)
    vp.box(fn(hw) {
      hw.fills_across(Is(true)) |> ignore
      head_ref.val = Some(hw)
      ev_live_node(hw, icon, tone, direct_body=true, fn(e) {
        steps_box_node(e, h_msg_head_grow, fn(head) {
          steps_box_node(head, h_msg_label_grow, fn(l) {
            if wrap_label {
              label_wraps(l)
            }
            label(l)
          }, in_row=true)
          head_slot.val = Some(head)
        }, in_row=true)
      })
    })
    |> ignore
    let rail_used = @signals.signal(@signals.untracked(open), same=fn(a, b) { a == b })
    wrap_body(vp, body_ref, fn(host) {
      steps_box_node(host, h_fold_room, fn(room) {
        room_ref.val = Some(room)
        steps_box_node(room, h_fold_inner, fn(i) {
          i.shrink(Is(0.0)).offset(By(fn() { (0.0, 0.0) })) |> ignore
          inner.val = Some(i)
          body(i)
        })
        room
        .holds_whole()
        .cuts_softly(By(long))
        .max_height(By(fn() {
          if open() || !long() {
            None
          } else {
            Some(most())
          }
        }))
        |> ignore
      })
    })
    vp.show(at_once=true, fn() { rail_used.get() }, fn(host) {
      host.over(Is(true)).points(Is(false)) |> ignore
      let rail = steps_rail_box_node(
        host,
        fn() { @ui.tree_theme().color(if failed() { Danger } else { Line }) },
        head_h,
        rail_next,
      )
      match room_ref.val {
        Some(room) =>
          rail.shown_by(room, fn(rt) {
            rail_ground(@signals.untracked(head_h), dmax(0.0, rt) + body_pad, @signals.untracked(rail_next))
          })
          |> ignore
        None => ()
      }
    })
    vp.shapes(By(fn() {
      if rail_used.get() {
        return []
      }
      let bh = match body_ref.val {
        Some(b) => dmax(0.0, given.tall(b))
        None => 0.0
      }
      let color = @ui.tree_theme().color(if failed() { Danger } else { Line })
      rail_shapes(head_h(), bh, rail_next(), color)
    }))
    |> ignore
    match head_slot.val {
      Some(head) =>
        head.show(at_once=true, long, fn(t) {
          @sf.style_node(t, fn() { h_msg_fold_btn })
          t.shrink(Is(0.0)) |> ignore
          let words_sig = @signals.computed(
            fn(_) {
              if open() {
                @sf.t("web-main.fold")
              } else {
                let more = dmax(1.0, ((tall() - most()) / stride()).round()).to_int()
                @sf.t("web-main.history.more", args=[("n", more.to_string())])
              }
            },
            same=fn(a, b) { a == b },
          )
          let words = fn() { words_sig.get() }
          // (the show's own node the button, by hand: a node of its own would be one more in every long message's head,
          // over the chat's page's bar)
          @sf.presses_node(t, fn() {
            rail_used.set(true)
            match room_ref.val {
              Some(rm) => rm.resizes() |> ignore
              None => ()
            }
            steps_flip(@signals.untracked(key_fn))
          })
          t.says(By(fn() { Some(@view.said(Button, label=words(), expanded=open())) })) |> ignore
          @sf.words_node(t, words, fn() {
            if @sf.lit_node(t) { h_msg_toggle_hot } else { h_msg_toggle_words }
          })
          |> ignore
          steps_chevron_node(
            t,
            "chevron-down",
            12.0,
            By(fn() { if @sf.lit_node(t) { @sf.theme().p.text } else { @sf.theme().p.muted } }),
            open,
          )
        })
      None => ()
    }
  })
  .fills_across(Is(true))
  |> ignore
}

///|
/// Conservative upper-bound pixel width at `12pt` without calling the host shaper, so `steps_row_shape` and short
/// single-line fast paths never incur host text measurements (`measured`).
fn single_line_px(words : String) -> Double {
  let mut w = 0.0
  for c in words {
    w = w + (if c <= '\u{7f}' { 6.2 } else { 12.0 })
  }
  w
}

///|
fn char_width_factors(words : String) -> (Double, Double) {
  let mut min_f = 0.0
  let mut max_f = 0.0
  for c in words {
    if c <= '\u{7f}' {
      min_f = min_f + 0.28
      max_f = max_f + 0.82
    } else if c >= '\u{2e80}' {
      min_f = min_f + 0.94
      max_f = max_f + 1.05
    } else {
      min_f = min_f + 0.35
      max_f = max_f + 1.05
    }
  }
  (min_f, max_f)
}

///|
/// Decides whether `lead_text` + `text` fits in `room.width() - margin` on one line, settling clearly short or clearly
/// overflowing strings by character-class bounds (`0` host measurements) and caching `@sf.node_words_w` per font scale
/// for borderline cases.
fn room_fits_one_line(
  vp : @view.View,
  room : @view.Room,
  lead_text : String,
  lead_pt : Double,
  lead_pad : Double,
  text : String,
  text_pt : Double,
  margin : Double,
) -> () -> Bool {
  let (lead_min, lead_max) = char_width_factors(lead_text)
  let (text_min, text_max) = char_width_factors(text)
  let cached_sp : Ref[Double] = Ref(-1.0)
  let cached_px : Ref[Double] = Ref(0.0)
  fn() {
    let sp_text = @sf.node_sp(vp, text_pt)
    let sp_lead = if lead_pt > 0.0 { @sf.node_sp(vp, lead_pt) } else { 0.0 }
    let avail = dmax(160.0, room.width() - margin)
    let max_px = lead_max * sp_lead + lead_pad + text_max * sp_text
    if max_px <= avail {
      return true
    }
    let min_px = lead_min * sp_lead + lead_pad + text_min * sp_text
    if min_px > avail {
      return false
    }
    if cached_sp.val != sp_text {
      cached_sp.val = sp_text
      let lpx = if lead_pt > 0.0 && lead_text != "" {
        @sf.node_words_w(lead_text, sp_lead) + lead_pad
      } else {
        0.0
      }
      cached_px.val = lpx + @sf.node_words_w(text, sp_text)
    }
    cached_px.val <= avail
  }
}

///|
/// A step's label in `l` going on in the next line where its line has not the room: each part as wide as its words
/// while its line has the room, giving way only alone in a line (a row of parts each giving way squeezed every one of
/// them, 收到来… with its name in two lines, desktop 0.1.7973).
fn label_wraps(l : @view.View) -> Unit {
  l.wraps(Is(Some(0.0))) |> ignore
}

///|
/// A message to the agent in `v`.
fn received_node(
  v : @view.View,
  src : Source,
  station : String,
  key : String,
  m : Json?,
  rail : Bool,
  rail_last : Bool,
  tips : @sf.TipLayer,
) -> Unit {
  let notice = text(m, "notice")
  let job = notice == "job"
  let words = text(m, "text")
  let md = field(m, "md")
  let has_md = md is Some(Array(_))
  let make_label = fn(l : @view.View) {
    steps_label_words(l, fn() {
      @sf.t(if job { "web-main.history.jobMessage.before" } else { "web-main.history.message.before" })
    }, h_label_words)
    let from = field(m, "from")
    let user = text(from, "slackUser")
    if user != "" {
      slack_name_node(l, src, station, user, text(from, "name"), flag(from, "bound"), tips)
    } else {
      steps_label_words(l, fn() { if notice == "stillfail" { @sf.product() } else { text(from, "name") } }, h_strong)
    }
    steps_label_words(l, fn() {
      @sf.t(if job { "web-main.history.jobMessage.after" } else { "web-main.history.message.after" })
    }, h_label_words)
    match field(m, "place") {
      Some(Object(_)) as p =>
        // (the dot going on with its place, never left at a line's end)
        label_place_node(l, fn(dp) { place_node(dp, station, p) })
      _ => ()
    }
  }
  if !has_md && !job && short_plain_words(words) {
    event_stack_node(
      v,
      rail_next=fn() { rail || rail_last },
      fn(ev) {
        ev_live_node(ev, "received", fn() { "" }, direct_body=true, fn(e) {
          steps_box_node(e, h_msg_label_grow, fn(l) {
            label_wraps(l)
            make_label(l)
          }, in_row=true)
        })
      },
      fn(ev) {
        steps_box_node(ev, h_received_body, fn(bb) {
          steps_words(bb, fn() { words }, h_words)
        })
      },
    )
    return
  }
  let gaps = if has_md { md_preview_gaps(md, words_lines) } else { 0.0 }
  message_fold_stack_node(
    v,
    fn() { key },
    "received",
    fn() { "" },
    rail_next=fn() { rail || rail_last },
    extra_gap=fn() { gaps },
    words_lines,
    if has_md { md_line } else { words_line },
    make_label,
    fn(ev, body_ref, inside) {
      ev.box(fn(bb) {
        @sf.style_node(bb, fn() { h_received_body })
        body_ref.val = Some(bb)
        inside(bb)
      })
      |> ignore
    },
    fn(f) {
      if has_md {
        md_node(f, words, md)
      } else if job {
        steps_run(f, fn() { words }, h_output, mono=true)
      } else {
        steps_words(f, fn() { words }, h_words)
      }
    },
  )
}

///|
/// A place as its platform's mark and its name in `v` (the library's place_node): a Slack thread opens in Slack, a
/// still.fail chat its page.
fn place_node(v : @view.View, station : String, place : Json?) -> Unit {
  let link = text(place, "url") != "" || text(place, "session") != ""
  place_live_node(v, station, fn() { place }, link)
}

///|
fn place_mark_name(surface : String, dark : Bool) -> String {
  match surface {
    "chat" | "ember" | "stillfail" => if dark { "stillfail_mark_dark" } else { "stillfail_mark" }
    "feishu" => "feishu"
    _ => "slack"
  }
}

///|
fn place_live_node(v : @view.View, station : String, place : () -> Json?, link : Bool) -> Unit {
  let surface_sig = @signals.computed(fn(_) { text(place(), "surface") }, same=fn(a, b) { a == b })
  let name_sig = @signals.computed(fn(_) { text(place(), "name") }, same=fn(a, b) { a == b })
  let words = if link { h_place_link_words } else { h_place_words }
  v.box(fn(p) {
    @sf.style_node(p, fn() { if link && @sf.lit_node(p) { h_place_hot } else { h_place } })
    p.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
    if link {
      @sf.presses_node(p, fn() {
        let pl = @signals.untracked(place)
        let url = text(pl, "url")
        let session = text(pl, "session")
        if url != "" {
          @sfbase.open_slack(text(pl, "app"), url) |> ignore
        } else if session != "" {
          @sfbase.history_push()
          app.nav.push(Chat({ station, session, title: text(pl, "name"), station_name: "" }))
        }
      })
    }
    p.pick(
      fn() { place_mark_name(surface_sig.get(), @sf.theme().dark) },
      fn(d, name) {
        @sf.style_node(d, fn() { h_place_mark })
        @sf.drawable_node(d, name, 12.0) |> ignore
      },
    )
    @sf.words_node(p, fn() { name_sig.get() }, fn() { words }).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
  })
  |> ignore
}

///|
/// A Slack user's name in `v`: pressed, 这是我 or 不是我 in its menu beside it; turning while the station
/// is told, a red mark a few seconds if that failed (its tip in `tips`).
fn slack_name_node(
  v : @view.View,
  src : Source,
  station : String,
  user : String,
  name : String,
  bound : Bool,
  tips : @sf.TipLayer,
) -> Unit {
  let on = [("station", station), ("user", user)]
  let saying = fn() { core_doing(src, ["slack.identity"], on) }
  steps_box_node(v, h_person, fn(p) {
    @sf.presses_node(
      p,
      fn() {
        let words = if bound { @sf.t("web-main.history.notMe") } else { @sf.t("web-main.history.isMe") }
        let (x, y, w, h) = p.placed_window_now()
        @sf.menu(
          [
            Some(
              @sf.menu_item_of(words, fn() {
                act(src, words, "", "slack.identity", {
                  "station": Json::string(station),
                  "user": Json::string(user),
                  // (the core's `bound`: bound to the viewer, or let go)
                  "bound": Json::boolean(!bound),
                })
              }),
            ),
          ],
          from=At(x, y, w, h),
        )
      },
      on=fn() { !saying() },
    )
    steps_run(p, fn() { name }, h_strong_link, underline=fn() { @sf.lit_node(p) && !saying() })
    p.show(fn() { !saying() }, fn(i) {
      @sf.icon_node(i, "chevron-down", 10.0, By(fn() { @sf.theme().p.blue })) |> ignore
    })
    p.show(saying, fn(s) { @sf.spinner_node(s, size=12.0) |> ignore })
    p.show(fn() { !saying() && core_failed(src, ["slack.identity"], on) is Some(_) }, fn(f) {
      @sf.icon_node(f, "info", 12.0, By(fn() { @sf.theme().p.red })) |> ignore
      @sf.tip_node(tips, f, fn() {
        match core_failed(src, ["slack.identity"], on) {
          Some("") | None => @sf.t("web-main.doing.failed")
          Some(why) => why
        }
      })
      |> ignore
    })
  })
}

///|
/// Work the agent started in the background, ended in `v`.
fn task_node(v : @view.View, key : String, task : Json?, rail : Bool, rail_last : Bool) -> Unit {
  let failed = flag(task, "failed")
  let answer = text(task, "result")
  let title = text(task, "text")
  let first_title = first_line(title)
  let has = answer != ""
  let agent = flag(task, "agent")
  let icon = if agent { "agent" } else { "command" }
  let tone = if failed { "red" } else { "" }
  if !has {
    one_line_ev_node(
      v,
      icon,
      tone,
      key,
      rail || rail_last,
      single=title == first_title && !title.contains("\n"),
      fn(_) {  },
      first_title,
      tone,
      fn(w) {
        card_plain_or_clip_node(w, first_title, title, if failed { h_one_red_wrap } else { h_note_plain })
      },
    )
    return
  }
  let open = fn() { steps_own.opened.contains(key) }
  event_reveal_stack_node(
    v,
    open,
    failed=fn() { failed },
    rail_next=fn() { rail || rail_last },
    fn(ev) {
      ev_node(ev, icon, "", tone, row=true, fn(b) {
        steps_press_box(b, fn() { steps_flip(key) }, label=fn() { first_title }, folds=true, open~, fn(r) {
          @sf.style_node(r, fn() { h_one_press })
          r.box(fn(l) {
            l.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
            @sf.words_node(l, fn() { first_title }, fn() {
              if failed {
                h_one_red
              } else if @sf.lit_node(r) {
                h_one_hot
              } else {
                h_one_words
              }
            })
            |> ignore
          })
          |> ignore
          steps_fold_mark_node(r, open)
        })
        |> ignore
      })
    },
    fn(b) {
      steps_box_node(b, h_post_body, fn(pb) {
        if agent {
          steps_box_node(pb, h_one_card, fn(w) {
            card_md_or_clip_node(w, first_title, answer, field(task, "md"), small=true)
          })
        } else {
          steps_box_node(pb, if failed { tool_box_red } else { tool_box }, fn(bx) {
            card_plain_or_clip_node(bx, "输出", answer, h_output, mono=true)
          })
        }
      })
    },
  )
}

///|
/// A turn's state in `v`: waiting on work it started (counting on each second while it does, a bar
/// filling toward the most it waits), done, or waiting on a person.
fn mark_node(v : @view.View, src : Source, key : String, mark : Json?, rail : Bool) -> Unit {
  let wait = field(mark, "wait")
  guard wait is Some(Object(_)) else {
    ended_node(v, key, text(mark, "ends"), text(mark, "text"), rail)
    return
  }
  let still = !(field(wait, "until") is Some(Number(_)))
  if !still {
    ended_node(v, key, "waiting", text(mark, "text"), rail)
    return
  }
  let since = number(wait, "since")
  let most = match opt_number(wait, "seconds") {
    Some(sec) if sec > 0.0 => Some(sec * second_ms)
    _ => None
  }
  let what_raw = text(wait, "what")
  let what_first = first_line(what_raw)
  let long_what = what_raw != what_first || what_raw.contains("\n") || single_line_px(what_raw) > 180.0
  let make_wait_line = fn(b : @view.View, tick : () -> Int, expandable : Bool, open : () -> Bool) {
    let words_fn = fn() {
      tick() |> ignore
      let ran = (src.now)() - since
      let what = match what_first {
        "" => ""
        w => w + " · "
      }
      let waited = match most {
        Some(m) => elapsed(if ran < m { ran } else { m }) + " / " + elapsed(m)
        None => elapsed(ran)
      }
      what + @sf.t("web-main.activity.waiting") + " " + waited
    }
    if expandable {
      steps_press_box(b, fn() { steps_flip(key) }, label=fn() { what_first }, folds=true, open~, fn(r) {
        @sf.style_node(r, fn() { h_one_press })
        r.box(fn(l) {
          l.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
          @sf.words_node(l, words_fn, fn() { if @sf.lit_node(r) { h_one_hot } else { h_state_words_line } })
          |> ignore
        })
        |> ignore
        steps_fold_mark_node(r, open)
      })
      |> ignore
    } else {
      steps_box_node(b, h_state_line, fn(l) {
        steps_words(l, words_fn, h_state_words_line)
      })
    }
    match most {
      Some(m) =>
        // how much of the most it waits has gone (WaitBar: a clock, not a motion)
        steps_box_node(b, h_wait_bar, fn(bar) {
          bar.box(fn(fill) {
            @sf.style_node(fill, fn() { h_wait_fill }, in_row=true)
            fill.width_share(By(fn() {
              tick() |> ignore
              dmin(1.0, dmax(0.0, ((src.now)() - since) / m))
            }))
            |> ignore
          })
          |> ignore
        })
      None => ()
    }
  }
  if long_what {
    let open = fn() { steps_own.opened.contains(key) }
    event_reveal_stack_node(
      v,
      open,
      rail_next=fn() { rail },
      fn(ev) {
        ev_node(ev, "wait", "waiting", "", fn(b) {
          let tick = steps_seconds(b, src, since, till?=most)
          make_wait_line(b, tick, true, open)
        })
      },
      fn(b) {
        steps_box_node(b, h_post_body, fn(pb) {
          steps_box_node(pb, h_one_card, fn(w) {
            card_plain_or_clip_node(w, @sf.t("web-main.activity.waiting"), what_raw, h_note_plain)
          })
        })
      },
    )
  } else {
    ev_node(v, "wait", "waiting", "", rail_last=rail, fn(b) {
      let tick = steps_seconds(b, src, since, till?=most)
      make_wait_line(b, tick, false, fn() { false })
    })
  }
}

///|
fn ended_words_node(parent : @view.View, state : String, words_fn : () -> String, cut~ : Bool, hot : () -> Bool) -> Unit {
  let look_style = if cut { h_state_words_line } else { h_state_words }
  parent.box(fn(w) {
    w
    .words_runs(By(fn() {
      let words = words_fn()
      let t = @sf.theme()
      let lead_color = match state {
        "done" => t.p.green_ink
        "human" => t.p.accent_text
        _ => t.p.text
      }
      let tail_color = if hot() { t.p.text } else { t.p.muted }
      match words.find("：") {
        Some(at) => {
          let head = words.unsafe_substring(start=0, end=at + 1)
          let tail = words.unsafe_substring(start=at + 1, end=words.length())
          [
            @ui.span(head, weight=600, color=lead_color),
            @ui.span(tail, color=tail_color),
          ]
        }
        None =>
          match words.find(": ") {
            Some(at) => {
              let head = words.unsafe_substring(start=0, end=at + 2)
              let tail = words.unsafe_substring(start=at + 2, end=words.length())
              [
                @ui.span(head, weight=600, color=lead_color),
                @ui.span(tail, color=tail_color),
              ]
            }
            None => [@ui.span(words, weight=600, color=lead_color)]
          }
      }
    }))
    .words_look(By(fn() { @ui.style_words(look_style) }))
    .ink(By(fn() { @ui.style_ink(look_style) }))
    .shrink(Is(1.0))
    .min_width(Is(Some(0.0)))
    |> ignore
    if cut {
      w.cuts(Is(true)).allow_ellipsis(Is(true)) |> ignore
    }
  })
  |> ignore
}

///|
/// How a turn ended in `v`: one line when short, or folded to one line with a chevron opening the full reason in a
/// faint rounded card below.
fn ended_node(v : @view.View, key : String, ends : String, words : String, rail : Bool) -> Unit {
  let effective_ends = if ends != "" {
    ends
  } else if words.has_prefix("标记为做完了") || words.has_prefix("标记为已完成") || words.has_prefix("Marked as done") {
    "done"
  } else if words.has_prefix("已暂停") || words.has_prefix("暂停") || words.has_prefix("等待人工") || words.has_prefix("标记为等") || words.has_prefix("Paused") || words.has_prefix("Stopped for human") {
    "human"
  } else {
    ""
  }
  let (icon, state) = match effective_ends {
    "human" => ("user", "human")
    "done" => ("check-circle", "done")
    "waiting" => ("wait", "waited")
    _ => ("info", "other")
  }
  let first = first_line(words)
  let single = words == first && !words.contains("\n")
  let make_flat = fn(host : @view.View) {
    ev_node(host, icon, state, "", rail_last=rail, row=true, fn(b) {
      steps_box_node(b, h_state_line, fn(l) {
        ended_words_node(l, state, fn() { first }, cut=true, fn() { false })
      })
    })
  }
  let make_expandable = fn(host : @view.View) {
    let open = fn() { steps_own.opened.contains(key) }
    event_reveal_stack_node(
      host,
      open,
      rail_next=fn() { rail },
      fn(ev) {
        ev_node(ev, icon, state, "", row=true, fn(b) {
          steps_press_box(b, fn() { steps_flip(key) }, label=fn() { first }, folds=true, open~, fn(r) {
            @sf.style_node(r, fn() { h_one_press })
            r.box(fn(l) {
              l.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
              ended_words_node(l, state, fn() { first }, cut=true, fn() { @sf.lit_node(r) })
            })
            |> ignore
            steps_fold_mark_node(r, open)
          })
          |> ignore
        })
      },
      fn(b) {
        steps_box_node(b, h_post_body, fn(pb) {
          steps_box_node(pb, h_one_card, fn(w) {
            if is_long_block(words) {
              card_plain_or_clip_node(w, first, words, h_note_plain)
            } else {
              ended_words_node(w, state, fn() { words }, cut=false, fn() { false })
            }
          })
        })
      },
    )
  }
  if !single {
    make_expandable(v)
    return
  }
  if single_line_px(first) <= 160.0 {
    make_flat(v)
    return
  }
  v.by_room(fn(vp, room) {
    vp.fills_across(Is(true)) |> ignore
    let fits = room_fits_one_line(
      vp,
      room,
      "",
      0.0,
      0.0,
      first,
      @ui.style_words(h_state_words_line).size,
      22.0,
    )
    vp.pick(at_once=true, fits, fn(p, is_short) {
      p.fills_across(Is(true)) |> ignore
      if is_short {
        make_flat(p)
      } else {
        make_expandable(p)
      }
    })
  })
  .fills_across(Is(true))
  |> ignore
}

///|
/// The icon a group of calls and thoughts in the history leads with: what its calls do, by its title or its first
/// call's kind (`step_label`); `think` for a group of thoughts alone.
fn group_icon(g : Json?) -> String {
  let rows = items(g, "rows")
  guard rows.iter().find_first(fn(r) { text(Some(r), "kind") == "step" }) is Some(first) else { return "think" }
  let title = text(g, "title")
  let label = step_label(text(field(Some(first), "content"), "name"))
  let says = fn(prefixes : Array[String], labels : Array[String]) {
    prefixes.iter().any(fn(p) { title.has_prefix(p) }) || labels.contains(label)
  }
  if says(["修改", "编辑", "新建"], ["编辑", "新建"]) {
    "edit"
  } else if says(["读取"], ["读取"]) {
    "file-text"
  } else if says(["搜索"], ["搜索"]) {
    "search"
  } else if says(["运行", "命令"], ["命令"]) {
    "command"
  } else if says(["网页"], ["网页"]) {
    "web"
  } else if says(["子代理", "代理"], ["代理"]) {
    "agent"
  } else if says(["对话"], ["对话"]) {
    "thread"
  } else {
    "other"
  }
}

///|
/// A group of calls and thoughts in `v`: its line, all of it opening the group (its title its tip, in
/// `tips`); opened, a line each beside the group's side line.
fn group_node(
  v : @view.View,
  src : Source,
  station : String,
  key : String,
  ik : String,
  g : Json?,
  rail : Bool,
  tips : @sf.TipLayer,
) -> Unit {
  let gk = ik + "/group"
  let open = fn() { steps_own.opened.contains(gk) }
  let failures = number(g, "failures").to_int()
  let pending = number(g, "pending").to_int()
  let rows = items(g, "rows")
  let calls = rows.iter().any(fn(r) { text(Some(r), "kind") == "step" })
  event_reveal_stack_node(
    v,
    open,
    rail_next=fn() { rail },
    fn(gv) {
      steps_press_box(gv, fn() { steps_flip(gk) }, label=fn() { text(g, "summary") }, folds=true, open~, fn(h) {
        @sf.style_node(h, fn() { h_group_head })
        let hot = fn() { @sf.lit_node(h) }
        @sf.hover_ground_node(h, lit=Some(fn() { @sf.lit_in_node(h) }))
        let g_icon = group_icon(g)
        h.box(fn(i) {
          @sf.style_node(i, fn() { h_icon })
          @sf.icon_node(i, g_icon, 14.0, By(fn() { if hot() { @sf.theme().p.text } else { @sf.theme().p.muted } }))
          |> ignore
        })
        |> ignore
        steps_box_node(h, h_grow_clip, fn(w) {
          w.box(fn(r) {
            r
            .words_runs(By(fn() { [@ui.span(text(g, "summary"), mono=false)] }))
            .words_look(By(fn() { @ui.style_words(h_group_words) }))
            .ink(By(fn() { @ui.style_ink(if hot() { h_group_hot } else { h_group_words }) }))
            .cuts(Is(true))
            .min_width(Is(Some(0.0)))
            .allow_ellipsis(Is(true))
            |> ignore
          })
          |> ignore
        }, in_row=true)
        if failures > 0 {
          @sf.badge_node(h, fn() { @sf.t("web-main.history.failures", args=[("n", failures.to_string())]) }, tone=Red)
          |> ignore
        }
        if pending > 0 {
          @sf.badge_node(h, fn() { @sf.t("web-main.history.pending", args=[("n", pending.to_string())]) }, tone=Accented)
          |> ignore
        }
        steps_fold_mark_node(h, open)
        ignore(tips)
      })
      |> ignore
    },
    fn(s) {
      group_rows_node(s, src, station, key, gk, rows, calls)
    },
  )
}

///|
fn group_rows_node(
  s : @view.View,
  src : Source,
  station : String,
  key : String,
  gk : String,
  rows : Array[Json],
  calls : Bool,
) -> Unit {
  let single_thought = !calls && rows.length() == 1
  steps_box_node(s, h_steps, fn(list) {
    for i, row in rows {
      group_row_node(list, src, station, key, group_row_key(gk, row, i), row, single_thought)
    }
  })
}

///|
/// What a reused group's row shows of its group's rows (`gk`, `rows` as they are now), a row each by its place in the
/// group: a step added makes its own row, a step changed makes its own again (the core's deltas keep the rest as they
/// were), none of the others.
fn group_rows_each_node(
  s : @view.View,
  src : Source,
  station : String,
  key : String,
  gk : () -> String,
  rows : () -> Array[Json],
) -> Unit {
  let calls_sig = @signals.computed(
    fn(_) { rows().iter().any(fn(r) { text(Some(r), "kind") == "step" }) },
    same=fn(a, b) { a == b },
  )
  let count_sig = @signals.computed(fn(_) { rows().length() }, same=fn(a, b) { a == b })
  let single_thought_sig = @signals.computed(
    fn(_) { !calls_sig.get() && count_sig.get() == 1 },
    same=fn(a, b) { a == b },
  )
  steps_box_node(s, h_steps, fn(list) {
    list.each(fn() { Array::makei(count_sig.get(), fn(i) { i }) }, fn(i) { i }, at_once=true, fn(x, at) {
      let i = at.untracked()
      x.pick(
        at_once=true,
        fn() { GroupRowPicked::{ gk: gk(), row: rows().get(i), single_thought: single_thought_sig.get() } },
        fn(p, cur) {
          guard cur.row is Some(row) else { return }
          group_row_node(p, src, station, key, group_row_key(cur.gk, row, i), row, cur.single_thought)
        },
      )
    })
  })
}

///|
/// A row of a group as group_rows_each_node shows it: its group's key, its JSON (the same as the core's delta left it),
/// whether the group is a single thought alone.
priv struct GroupRowPicked {
  gk : String
  row : Json?
  single_thought : Bool
}

///|
impl Eq for GroupRowPicked with equal(a, b) {
  a.gk == b.gk &&
  a.single_thought == b.single_thought &&
  (match (a.row, b.row) {
    (Some(x), Some(y)) => physical_equal(x, y)
    (None, None) => true
    _ => false
  })
}

///|
/// A row `row` of a group (`rk` its key) in `list`: a thought (opened in a faint card below its line where there is more
/// of it, or right in a faint card when the group holds one thought alone), else a step.
fn group_row_node(
  list : @view.View,
  src : Source,
  station : String,
  key : String,
  rk : String,
  row : Json,
  single_thought : Bool,
) -> Unit {
  let rv = Some(row)
  let content = field(rv, "content")
  if text(rv, "kind") == "thought" {
    let thought_words = text(content, "text")
    if single_thought {
      whole_node(list, src, station, key, rk, content, fn(body) {
        steps_box_node(body, h_step_card, fn(t) {
          card_md_or_clip_node(t, @sf.t("web-main.history.thinking"), thought_words, field(content, "md"), small=true)
        })
      })
    } else {
      let first = text(content, "first")
      let multi = flag(content, "brief") || thought_words != first || thought_words.contains("\n")
      let make_flat_thought = fn(host : @view.View) {
        steps_box_node(host, h_step, fn(s) {
          steps_box_node(s, h_step_summary, fn(sum) {
            steps_words(sum, fn() { @sf.t("web-main.history.thinking") }, h_step_name)
            steps_box_node(sum, h_grow_clip, fn(c) {
              steps_words(c, fn() { first }, h_step_hint_line)
            }, in_row=true)
          })
        })
      }
      let make_open_thought = fn(host : @view.View) {
        opened_node(host, src, station, key, rk, content, fn(sum) {
          steps_words(sum, fn() { @sf.t("web-main.history.thinking") }, h_step_name)
          steps_box_node(sum, h_grow_clip, fn(c) {
            steps_words(c, fn() { first }, h_step_hint_line)
          }, in_row=true)
        }, fn(body) {
          steps_box_node(body, h_step_card, fn(t) {
            card_md_or_clip_node(t, @sf.t("web-main.history.thinking"), thought_words, field(content, "md"), small=true)
          })
        })
      }
      if multi {
        make_open_thought(list)
      } else if single_line_px(first) <= 130.0 {
        make_flat_thought(list)
      } else {
        let thinking_label = @sf.t("web-main.history.thinking")
        list.by_room(fn(lp, room) {
          lp.fills_across(Is(true)) |> ignore
          let fits = room_fits_one_line(lp, room, thinking_label, 12.0, 8.0, first, 12.0, 4.0)
          lp.pick(at_once=true, fits, fn(p, is_short) {
            p.fills_across(Is(true)) |> ignore
            if is_short {
              make_flat_thought(p)
            } else {
              make_open_thought(p)
            }
          })
        })
        .fills_across(Is(true))
        |> ignore
      }
    }
  } else {
    step_node(list, src, station, key, rk, content)
  }
}

///|
/// Transcript entry numbers belong to one session on one station.
fn steps_item_key(station : String, key : String, item : String) -> String {
  station + "\u{1}" + key + "\u{1}" + item
}

///|
/// A group's rows can move when calls are combined or a preceding thought is removed.
/// Keep the disclosure on its transcript entry through those changes.
fn group_row_key(group : String, row : Json, index : Int) -> String {
  match items(field(Some(row), "content"), "entries").get(0) {
    Some(Number(n, ..)) => group + "/e" + n.to_int64().to_string()
    _ => group + "/" + index.to_string()
  }
}

///|
fn steps_opened_under(ik : String) -> Bool {
  if steps_own.opened.is_empty() {
    return false
  }
  let prefix = ik + "/"
  for k, _ in steps_own.opened {
    if k.has_prefix(prefix) {
      return true
    }
  }
  false
}

///|
/// Pool key for common closed `Item` row shapes so scrolling reuses existing row subtrees in place (`View::scrolls_window`'s
/// `reused`) instead of tearing down and rebuilding every row that enters or leaves the viewport.
fn steps_row_shape(row : StepsRow?, station : String, key : String, ignore_opened? : Bool = false) -> Int? {
  match row {
    Some(Live(_, _)) => return Some(66)
    Some(Item(item, _)) => {
      let ik = text(Some(item), "key")
      if ik == "" || (!ignore_opened && steps_opened_under(steps_item_key(station, key, ik))) {
        return None
      }
      let turn_kind = match field(Some(item), "turn") {
        Some(Object(_)) as t => if text(t, "time") != "" { 2 } else { 1 }
        _ => 0
      }
      let body = field(Some(item), "body")
      let content = field(body, "content")
      let base = match text(body, "kind") {
        // (one shape whatever its failures and pending: its badges show and go in it as they change)
        "group" => 0
        "text" => {
          let words = text(content, "text")
          let line = text(content, "line")
          let sub = flag(content, "subagent")
          if !sub && words == line && !words.contains("\n") && single_line_px(words) <= 220.0 {
            4
          } else {
            return None
          }
        }
        "received" => {
          let note = text(content, "note")
          let tasks = items(content, "tasks")
          let messages = items(content, "messages")
          if note == "" && tasks.length() == 1 && messages.is_empty() {
            let task = Some(tasks[0])
            let answer = text(task, "result")
            let title = text(task, "text")
            if answer == "" && !title.contains("\n") && single_line_px(title) <= 290.0 {
              if flag(task, "agent") { 5 } else { 6 }
            } else {
              return None
            }
          } else if note == "" && tasks.is_empty() && messages.length() == 1 {
            let m = Some(messages[0])
            let from = field(m, "from")
            let words = text(m, "text")
            if text(from, "slackUser") == "" && text(m, "notice") != "job" {
              let place = field(m, "place")
              let place_kind = match place {
                Some(Object(_)) => if text(place, "url") != "" || text(place, "session") != "" { 2 } else { 1 }
                _ => 0
              }
              let msg_kind = if field(m, "md") is Some(Array(_)) {
                2
              } else if short_plain_words(words) {
                0
              } else {
                1
              }
              7 + place_kind * 3 + msg_kind
            } else {
              return None
            }
          } else {
            return None
          }
        }
        "post" => {
          let ends = text(content, "ends")
          let failed = flag(content, "failed")
          let block = flag(content, "block")
          let place = field(content, "place")
          if ends == "" && !failed && !block && place is Some(Object(_)) {
            if text(place, "url") != "" || text(place, "session") != "" { 19 } else { 20 }
          } else {
            return None
          }
        }
        "mark" => {
          let wait = field(content, "wait")
          let words = text(content, "text")
          if wait is Some(Object(_)) &&
            field(wait, "until") is Some(Number(_)) &&
            !words.contains("\n") &&
            single_line_px(words) <= 220.0 {
            21
          } else {
            return None
          }
        }
        _ => return None
      }
      Some(base * 3 + turn_kind)
    }
    _ => None
  }
}

///|
fn ev_live_node(
  v : @view.View,
  icon : String,
  tone : () -> String,
  rail_last? : () -> Bool,
  fixed_h? : Double,
  direct_body? : Bool = false,
  body : (@view.View) -> Unit,
) -> Unit {
  let ink = fn() {
    let t = @sf.theme()
    match tone() {
      "accent" => t.p.accent
      "red" => t.p.red
      _ => t.p.muted
    }
  }
  let make_ev = fn(e : @view.View) {
    e.box(fn(i) {
      @sf.style_node(i, fn() { h_icon })
      @sf.icon_node(i, icon, 14.0, By(ink)) |> ignore
    })
    |> ignore
    if direct_body {
      body(e)
    } else {
      steps_box_node(e, h_ev_body, body, in_row=true)
    }
  }
  match (rail_last, fixed_h) {
    (Some(has_rail), Some(h)) =>
      steps_box_node(v, h_ev, fn(e) {
        make_ev(e)
        e.shapes(By(fn() {
          let color = @ui.tree_theme().color(if tone() == "red" { Danger } else { Line })
          rail_shapes(h, 0.0, has_rail(), color)
        }))
        |> ignore
      })
    (Some(has_rail), None) =>
      v.by_room(fn(p, room) {
        p.fills_across(Is(true)) |> ignore
        let row_ref : Ref[@view.View?] = Ref(None)
        let tall = fn() {
          match row_ref.val {
            Some(r) => dmax(20.0, room.tall(r))
            None => 20.0
          }
        }
        steps_box_node(p, h_ev, fn(e) {
          row_ref.val = Some(e)
          make_ev(e)
        })
        p.shapes(By(fn() {
          let color = @ui.tree_theme().color(if tone() == "red" { Danger } else { Line })
          rail_shapes(tall(), 0.0, has_rail(), color)
        }))
        |> ignore
      })
      .fills_across(Is(true))
      |> ignore
    (None, _) => steps_box_node(v, h_ev, make_ev)
  }
}

///|
fn steps_reused_row_node(
  slot : @view.View,
  src : Source,
  station : String,
  key : String,
  row_of : (String) -> StepsRow?,
  row_key : () -> String,
  lit : @signals.Signal[String],
  tips : @sf.TipLayer,
  make_row : (@view.View, StepsRow) -> Unit,
) -> Unit {
  let picked = @signals.computed(fn(_) { StepsPicked::{ row: row_of(row_key()) } }, same=fn(a, b) { a == b })
  let init_shape = @signals.untracked(fn() { steps_row_shape(picked.get().row, station, key) })
  let same_shape_sig = @signals.computed(
    fn(_) { steps_row_shape(picked.get().row, station, key, ignore_opened=true) == init_shape },
    same=fn(a, b) { a == b },
  )
  slot.pick(
    at_once=true,
    fn() { if same_shape_sig.get() { None } else { Some(picked.get()) } },
    fn(p, fallback) {
      match fallback {
        Some(pk) => {
          guard pk.row is Some(row) else { return }
          make_row(p, row)
        }
        None => {
          guard init_shape is Some(shape) else { return }
          let base = shape / 3
          if base == 22 {
            let live_words_sig = @signals.computed(
              fn(_) {
                match picked.get().row {
                  Some(Live(l, _)) => text(Some(l), "text")
                  _ => ""
                }
              },
              same=fn(a, b) { a == b },
            )
            let has_live_rail_sig = @signals.computed(
              fn(_) {
                match picked.get().row {
                  Some(Live(_, rail)) => rail
                  _ => false
                }
              },
              same=fn(a, b) { a == b },
            )
            let has_live_rail = fn() { has_live_rail_sig.get() }
            @sf.style_node(p, fn() { steps_row })
            ev_live_node(p, "think", fn() { "" }, rail_last=has_live_rail, fixed_h=20.0, direct_body=true, fn(e) {
              steps_box_node(e, h_one_grow, fn(o) {
                steps_words(o, fn() { live_words_sig.get() }, live_words) |> ignore
              }, in_row=true)
            })
            return
          }
          let turn_kind = shape % 3
          let item_fn = fn() {
            match picked.get().row {
              Some(Item(item, _)) => Some(item)
              _ => None
            }
          }
          let has_rail_sig = @signals.computed(
            fn(_) {
              match picked.get().row {
                Some(Item(_, rail)) => rail
                _ => false
              }
            },
            same=fn(a, b) { a == b },
          )
          let has_rail = fn() { has_rail_sig.get() }
          let item_key = fn() {
            let k = row_key()
            if k.has_prefix("i/") {
              k.unsafe_substring(start=2, end=k.length())
            } else {
              k
            }
          }
          let disclosure_key = fn() { steps_item_key(station, key, item_key()) }
          let marked = fn() {
            let l = lit.get()
            l != "" && l == item_key()
          }
          @sf.style_node(p, fn() { if turn_kind == 1 { steps_row_turn } else { steps_row } })
          p.box(fn(b) {
            @sf.style_node(b, fn() { h_item })
            b.ground(By(fn() { if marked() { @ui.tree_theme().color(A(Accent, O10)) } else { 0L } })) |> ignore
            if turn_kind == 2 {
              let said_sig = @signals.computed(
                fn(_) { turn_time_of(item_fn()) },
                same=fn(a, b) { a == b },
              )
              b.box(fn(t) {
                t
                .fills_across(Is(true))
                .padding(Is((0.0, 4.0, 0.0, 0.0)))
                .words(By(fn() { said_sig.get() }))
                .words_centered(Is(true))
                .cuts(Is(true))
                .min_width(Is(Some(0.0)))
                .allow_ellipsis(Is(true))
                .words_look(By(fn() { @ui.style_words(h_turn_words) }))
                .ink(By(fn() { @ui.style_ink(h_turn_words) }))
                |> ignore
              })
              |> ignore
            }
            let content = fn() { field(field(item_fn(), "body"), "content") }
              match base {
                0 => {
                  let gk = fn() { disclosure_key() + "/group" }
                  let open_sig = @signals.computed(fn(_) { steps_opened_contains_fn(gk) }, same=fn(a, b) { a == b })
                  let open = fn() { open_sig.get() }
                  let summary_sig = @signals.computed(fn(_) { text(content(), "summary") }, same=fn(a, b) { a == b })
                  let summary = fn() { summary_sig.get() }
                  b.box(fn(gv) {
                    @sf.style_node(gv, fn() { h_group })
                    let rail_used = @signals.signal(@signals.untracked(open), same=fn(a, b) { a == b })
                    let rail_ref : Ref[@view.View?] = Ref(None)
                    steps_press_box(gv, fn() {
                      rail_used.set(true)
                      steps_flip(@signals.untracked(gk))
                    }, label=summary, folds=true, open~, fn(h) {
                      @sf.style_node(h, fn() { h_group_head })
                      let hot = fn() { @sf.lit_node(h) }
                      @sf.hover_ground_node(h, lit=Some(fn() { @sf.lit_in_node(h) }))
                      let icon_sig = @signals.computed(fn(_) { group_icon(content()) }, same=fn(a, b) { a == b })
                      let icon_fn = fn() { icon_sig.get() }
                      h.box(fn(i) {
                        @sf.style_node(i, fn() { h_icon })
                        @sf.icon_node(
                          i,
                          @signals.untracked(icon_fn),
                          14.0,
                          By(fn() { if hot() { @sf.theme().p.text } else { @sf.theme().p.muted } }),
                          name_now=icon_fn,
                        )
                        |> ignore
                      })
                      |> ignore
                      @sf.words_node(h, summary, fn() { if hot() { h_group_hot } else { h_group_words } })
                      .grow(Is(1.0))
                      .shrink(Is(1.0))
                      .basis(Is(Some(0.0)))
                      |> ignore
                      // (its badges shown and gone as its failures and pending come and go, the row kept)
                      h.show(at_once=true, fn() { number(content(), "failures").to_int() > 0 }, fn(x) {
                        @sf.badge_node(x, fn() {
                          @sf.t("web-main.history.failures", args=[("n", number(content(), "failures").to_int().to_string())])
                        }, tone=Red)
                        |> ignore
                      })
                      h.show(at_once=true, fn() { number(content(), "pending").to_int() > 0 }, fn(x) {
                        @sf.badge_node(x, fn() {
                          @sf.t("web-main.history.pending", args=[("n", number(content(), "pending").to_int().to_string())])
                        }, tone=Accented)
                        |> ignore
                      })
                      steps_fold_mark_node(h, open)
                      ignore(tips)
                    })
                    |> ignore
                    gv.show(at_once=true, fn() { rail_used.get() }, fn(host) {
                      host.over(Is(true)).points(Is(false)) |> ignore
                      rail_ref.val = Some(
                        steps_rail_box_node(
                          host,
                          fn() { @ui.tree_theme().color(Line) },
                          fn() { 20.0 },
                          has_rail,
                        ),
                      )
                    })
                    gv.shapes(By(fn() {
                      if rail_used.get() {
                        []
                      } else {
                        rail_shapes(20.0, 0.0, has_rail(), @ui.tree_theme().color(Line))
                      }
                    }))
                    |> ignore
                    gv.show(open, fn(s) {
                      s.fills_across(Is(true)).cuts_softly(Is(true)) |> ignore
                      match rail_ref.val {
                        Some(rail) =>
                          rail.shown_by(s, fn(s_tall) {
                            rail_ground(20.0, s_tall, @signals.untracked(has_rail))
                          })
                          |> ignore
                        None => ()
                      }
                      group_rows_each_node(s, src, station, key, gk, fn() { items(content(), "rows") })
                    })
                  })
                  .fills_across(Is(true))
                  |> ignore
                }
                4 => {
                  let line_sig = @signals.computed(fn(_) { text(content(), "line") }, same=fn(a, b) { a == b })
                  ev_live_node(b, "said", fn() { "" }, rail_last=has_rail, fixed_h=20.0, direct_body=true, fn(e) {
                    steps_box_node(e, h_one_grow, fn(o) { steps_words(o, fn() { line_sig.get() }, h_one_words) }, in_row=true)
                  })
                }
                5 | 6 => {
                  let agent = base == 5
                  let task = fn() { items(content(), "tasks").get(0) }
                  let failed_sig = @signals.computed(fn(_) { flag(task(), "failed") }, same=fn(a, b) { a == b })
                  let failed = fn() { failed_sig.get() }
                  let task_words_sig = @signals.computed(fn(_) { text(task(), "text") }, same=fn(a, b) { a == b })
                  ev_live_node(
                    b,
                    if agent { "agent" } else { "command" },
                    fn() { if failed() { "red" } else { "" } },
                    rail_last=has_rail,
                    fixed_h=20.0,
                    direct_body=true,
                    fn(e) {
                      steps_box_node(e, h_one_grow, fn(o) {
                        @sf.words_node(o, fn() { task_words_sig.get() }, fn() {
                          if failed() {
                            h_one_red
                          } else {
                            h_one_words
                          }
                        })
                        .shrink(Is(1.0))
                        .min_width(Is(Some(0.0)))
                        |> ignore
                      }, in_row=true)
                    },
                  )
                }
                7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 => {
                  let place_kind = (base - 7) / 3
                  let msg_kind = (base - 7) % 3
                  let msg = fn() { items(content(), "messages").get(0) }
                  let from_name_sig = @signals.computed(
                    fn(_) {
                      let m0 = msg()
                      if text(m0, "notice") == "stillfail" {
                        @sf.product()
                      } else {
                        text(field(m0, "from"), "name")
                      }
                    },
                    same=fn(a, b) { a == b },
                  )
                  let words_sig = @signals.computed(fn(_) { text(msg(), "text") }, same=fn(a, b) { a == b })
                  let words = fn() { words_sig.get() }
                  let make_label = fn(l : @view.View) {
                    steps_label_words(l, fn() { @sf.t("web-main.history.message.before") }, h_label_words)
                    steps_label_words(l, fn() { from_name_sig.get() }, h_strong)
                    steps_label_words(l, fn() { @sf.t("web-main.history.message.after") }, h_label_words)
                    if place_kind > 0 {
                      label_place_node(l, fn(dp) {
                        place_live_node(dp, station, fn() { field(msg(), "place") }, place_kind == 2)
                      })
                    }
                  }
                  if msg_kind == 0 {
                    event_stack_node(
                      b,
                      rail_next=has_rail,
                      fn(ev) {
                        ev_live_node(ev, "received", fn() { "" }, direct_body=true, fn(e) {
                          steps_box_node(e, h_msg_label_grow, fn(l) {
                            label_wraps(l)
                            make_label(l)
                          }, in_row=true)
                        })
                      },
                      fn(ev) {
                        steps_box_node(ev, h_received_body, fn(bb) {
                          steps_words(bb, words, h_words)
                        })
                      },
                    )
                  } else {
                    let fk = fn() { disclosure_key() + "/message/0" }
                    let md_sig = if msg_kind == 2 {
                      Some(@signals.computed(fn(_) { field(msg(), "md") }, same=json_opt_same))
                    } else {
                      None
                    }
                    let md_fn = fn() {
                      match md_sig {
                        Some(s) => s.get()
                        None => None
                      }
                    }
                    message_fold_stack_node(
                      b,
                      fk,
                      "received",
                      fn() { "" },
                      rail_next=has_rail,
                      extra_gap=fn() { if msg_kind == 2 { md_preview_gaps(md_fn(), words_lines) } else { 0.0 } },
                      words_lines,
                      if msg_kind == 2 { md_line } else { words_line },
                      make_label,
                      fn(ev, body_ref, inside) {
                        ev.box(fn(bb) {
                          @sf.style_node(bb, fn() { h_received_body })
                          body_ref.val = Some(bb)
                          inside(bb)
                        })
                        |> ignore
                      },
                      fn(f) {
                        if msg_kind == 2 {
                          md_live_node(f, words, md_fn)
                        } else {
                          steps_words(f, words, h_words)
                        }
                      },
                    )
                  }
                }
                19 | 20 => {
                  let link = base == 19
                  let post_words_sig = @signals.computed(fn(_) { text(content(), "text") }, same=fn(a, b) { a == b })
                  let post_md_sig = @signals.computed(fn(_) { field(content(), "md") }, same=json_opt_same)
                  let fk = fn() { disclosure_key() + "/post" }
                  message_fold_stack_node(
                    b,
                    fk,
                    "send",
                    fn() { "accent" },
                    rail_next=has_rail,
                    extra_gap=fn() { md_preview_gaps(post_md_sig.get(), post_lines) },
                    body_pad=24.0,
                    wrap_label=true,
                    post_lines,
                    md_line,
                    fn(l) {
                      steps_label_words(l, fn() { @sf.t("web-main.history.sentTo") }, h_label_words)
                      place_live_node(l, station, fn() { field(content(), "place") }, link)
                    },
                    fn(ev, body_ref, inside) {
                      ev.box(fn(pb) {
                        @sf.style_node(pb, fn() { h_post_body })
                        body_ref.val = Some(pb)
                        steps_box_node(pb, h_card, fn(card) {
                          card.edge(By(fn() { (1.0, @ui.tree_theme().color(Line)) })) |> ignore
                          inside(card)
                        })
                      })
                      |> ignore
                    },
                    fn(f) {
                      md_live_node(f, fn() { post_words_sig.get() }, fn() { post_md_sig.get() })
                    },
                  )
                }
                21 => {
                  let mark_words_sig = @signals.computed(fn(_) { text(content(), "text") }, same=fn(a, b) { a == b })
                  ev_live_node(b, "wait", fn() { "" }, rail_last=has_rail, fixed_h=20.0, direct_body=true, fn(e) {
                    steps_box_node(e, h_state_line_grow, fn(l) {
                      ended_words_node(l, "waited", fn() { mark_words_sig.get() }, cut=true, fn() { false })
                    }, in_row=true)
                  })
                }
                _ => ()
              }
          })
          |> ignore
        }
      }
    },
  )
}

///|
/// Short localized action badge for a tool step row.
fn step_label(name : String) -> String {
  match name {
    "Read" | "NotebookRead" | "view_image" | "read_image" | "read" | "read_file" | "view_file_outline" | "view_code_item" | "skill_read" | "skill" => "读取"
    "Edit" | "MultiEdit" | "NotebookEdit" | "apply_patch" | "edit" | "edit_file" | "replace_file_content" | "multi_replace_file_content" | "search_replace" | "delete_file" => "编辑"
    "Write" | "write" | "write_file" | "write_to_file" => "新建"
    "Glob" | "Grep" | "LS" | "ToolSearch" | "search_tool" | "mcp_list_tools" | "glob" | "grep" | "grep_search" | "find_by_name" | "find_file_by_name" | "list_dir" | "search" => "搜索"
    "Bash" | "bash" | "BashOutput" | "KillShell" | "exec_command" | "exec" | "shell" | "local_shell" | "write_stdin" | "wait" | "job_output" | "unified_exec" | "run_command" | "run_terminal_command" | "command_status" | "send_command_input" | "manage_task" => "命令"
    "WebFetch" | "WebSearch" | "web_search" | "web_fetch" | "search_web" | "read_url_content" | "web__run" => @sf.t("web-main.history.tool.web")
    "Task" | "Agent" | "spawn_agent" | "subagent" | "invoke_subagent" | "define_subagent" | "manage_subagents" | "swarm" | "send_message" | "SendMessage" | "followup_task" | "list_agents" | "wait_agent" => "代理"
    "chat_history" | "chat_list" | "chat_read" | "session_history" | "chat_archive" | "chat_leave" => "对话"
    "chat_post" | "chat_state" | "session_send" | "chat_create" | "feishu_api" | "slack_api" => "消息"
    "station_task" | "station_file" | "station_list" | "station_tool" | "relays" | "workspace_limit" => "远程"
    "job_start" | "job_list" | "job_log" | "job_stop" | "sleep" | "get_output" | "clock__curr_time" | "TaskOutput" | "TaskStop" | "schedule" => "任务"
    "TodoWrite" | "EnterPlanMode" | "ExitPlanMode" => "计划"
    "AskUserQuestion" | "ask_question" => "提问"
    "screen" | "browser" | "computer" => "屏幕"
    "secret_list" | "secret_describe" | "secret_delete" | "secret_cancel" | "secret_reask" | "secret_use" | "secret_save" | "secret_run" => "密钥"
    "phone_use" | "phone_send" | "adb_devices" | "device_list" | "device_use" | "permissions" => "设备"
    "" => "工具"
    other => {
      let clean = if other.has_prefix("mcp__") {
        let rest = other.unsafe_substring(start=5, end=other.length())
        match rest.find("__") {
          Some(i) => rest.unsafe_substring(start=i + 2, end=rest.length())
          None => rest
        }
      } else {
        other
      }
      if clean.length() > 18 {
        clean.unsafe_substring(start=0, end=18) + "…"
      } else {
        clean
      }
    }
  }
}

///|
/// Whether `s` is an opaque hex/UUID identifier that should not be shown as a human-readable hint.
fn is_opaque_id(s : String) -> Bool {
  let v = s.trim().to_owned()
  if v.length() < 8 {
    return false
  }
  let mut has_digit = false
  for ch in v {
    let is_hex = (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F') || ch == '-'
    if !is_hex {
      return false
    }
    if ch >= '0' && ch <= '9' {
      has_digit = true
    }
  }
  has_digit
}

///|
/// Fallback summary extracted from a step's raw JSON call when `said` was not populated on the step item.
fn step_call_summary(call : String) -> (String, String) {
  let trimmed = call.trim().to_owned()
  guard trimmed.has_prefix("{") else { return ("", "") }
  let parsed = @json.parse(trimmed) catch { _ => Json::null() }
  guard parsed is Object(m) else { return ("", "") }
  let mut said = ""
  for k in ["summary", "description", "toolSummary", "Role", "title"] {
    match m.get(k) {
      Some(String(s)) if s.trim().to_owned() != "" => {
        said = first_line(s.trim().to_owned())
        break
      }
      _ => ()
    }
  }
  let mut hint = ""
  for k in ["_target", "recipient_name", "to", "recipient", "Recipient", "subagent_type", "TypeName", "path", "file_path", "Path", "pattern", "query", "message", "prompt"] {
    match m.get(k) {
      Some(String(s)) => {
        let v = s.trim().to_owned()
        if v != "" && !is_opaque_id(v) {
          hint = first_line(v)
          break
        }
      }
      _ => ()
    }
  }
  (said, hint)
}

///|
/// Whether expanding `step` reveals details beyond what its summary row (`said`, `hint`, `meta`) already displays.
fn step_has_detail(step : Json?) -> Bool {
  if flag(step, "brief") || flag(step, "failed") {
    return true
  }
  let res = text(step, "result").trim().to_owned()
  let name = text(step, "name")
  let call = text(step, "call").trim().to_owned()
  match name {
    "Read" | "NotebookRead" | "read_file" | "read" | "view_image" | "read_image" =>
      return res != ""
    "ToolSearch" | "search_tool" =>
      if text(step, "said") != "" && call.contains("\"select:") && (res == "" || res.contains("\"tool_reference\"")) {
        return false
      }
    _ =>
      if name.has_prefix("File ") &&
        res == "" &&
        !call.contains("\"old_string\"") &&
        !call.contains("\"new_string\"") &&
        !call.contains("\"Target\"") &&
        !call.contains("\"Replacement\"") &&
        !call.contains("\"content\"") &&
        !call.contains("\"Content\"") &&
        !call.contains("\"edits\"") &&
        !call.contains("\"patch\"") {
        return false
      }
  }
  if res != "" {
    return true
  }
  if call == "" || call == "{}" {
    return false
  }
  if call.has_prefix("{") {
    let parsed = @json.parse(call) catch { _ => Json::null() }
    if parsed is Object(m) {
      let mut extra_keys = false
      for k, _ in m {
        match k {
          "toolSummary" | "description" | "explanation" | "summary" => ()
          _ => {
            extra_keys = true
            break
          }
        }
      }
      if !extra_keys {
        return false
      }
    }
  }
  true
}

///|
/// A call in `v`: its line; opened (where it holds more than its summary line), what it asked for and what came back.
fn step_node(v : @view.View, src : Source, station : String, key : String, rk : String, step : Json?) -> Unit {
  let failed = flag(step, "failed")
  let raw_said = text(step, "said")
  let raw_hint = text(step, "hint")
  let (fallback_said, fallback_hint) = if raw_said == "" || raw_hint == "" {
    step_call_summary(text(step, "call"))
  } else {
    ("", "")
  }
  let step_said = if raw_said != "" { raw_said } else { fallback_said }
  let step_hint = if raw_hint != "" { raw_hint } else { fallback_hint }
  let render_summary = fn(sum : @view.View) {
    let label = fn() { step_label(text(step, "name")) }
    let show_secondary_hint = match @signals.untracked(label) {
      "读取" | "编辑" | "新建" | "搜索" => true
      _ => false
    }
    steps_words(sum, label, if failed { h_step_name_red } else { h_step_name })
    steps_box_node(sum, h_grow_clip, fn(c) {
      match (step_said, step_hint) {
        ("", hint) => steps_run(c, fn() { hint }, h_step_hint_line, mono=true)
        (said, "") => steps_words(c, fn() { said }, h_step_said)
        (said, hint) =>
          if !show_secondary_hint || said == hint || said.contains(hint) {
            steps_words(c, fn() { said }, h_step_said)
          } else {
            c.box(fn(r) {
              r
              .words_runs(By(fn() {
                [
                  @ui.span(said, color=@sf.theme().p.text),
                  @ui.span("  " + hint, mono=true, color=@sf.theme().p.muted),
                ]
              }))
              .words_look(By(fn() { @ui.style_words(h_step_said) }))
              .ink(By(fn() { @ui.style_ink(h_step_said) }))
              .cuts(Is(true))
              .min_width(Is(Some(0.0)))
              .allow_ellipsis(Is(true))
              |> ignore
            })
            |> ignore
          }
      }
    }, in_row=true)
    let meta = text(step, "meta")
    if meta != "" {
      @sf.words_node(sum, fn() { meta }, fn() { if failed { h_step_meta_red } else { h_step_meta } }).shrink(Is(0.0)) |> ignore
    }
  }
  if !step_has_detail(step) {
    steps_box_node(v, h_step, fn(s) { steps_box_node(s, h_step_summary, render_summary) })
    return
  }
  let (ask, tk) = tool_ask_of(rk, step)
  let before_open = Some(fn(open_now : () -> Unit) {
    if flag(step, "brief") ||
      @signals.untracked(fn() { steps_own.tools.contains(tk) }) ||
      src.read_only ||
      !(src.switches_ahead)() {
      open_now()
      return
    }
    tool_fetch(src, ask, tk)
    @sfbase.press_wait(
      fn() { steps_own.tools.contains(tk) || steps_own.tool_err.contains(tk) },
      open_now,
      most=@sf.open_hold_ms,
    )
    |> ignore
  })
  opened_node(
    v,
    src,
    station,
    key,
    rk,
    step,
    render_summary,
    fn(body) { tool_body_node(body, src, station, key, rk, step) },
    before_open~,
    on_close=fn() { steps_own.tool_err.remove(tk) },
  )
}

///|
/// A line of a group that opens to what is behind it in `v`; in brief, read whole as it is opened.
fn opened_node(
  v : @view.View,
  src : Source,
  station : String,
  key : String,
  rk : String,
  content : Json?,
  summary : (@view.View) -> Unit,
  body : (@view.View) -> Unit,
  before_open? : ((() -> Unit) -> Unit)? = None,
  on_close? : () -> Unit = fn() {  },
) -> Unit {
  let open = fn() { steps_own.opened.contains(rk) }
  let toggle = fn() {
    if @signals.untracked(open) {
      steps_flip(rk)
      on_close()
    } else {
      match before_open {
        Some(prepare) => prepare(fn() { steps_flip(rk) })
        None => steps_flip(rk)
      }
    }
  }
  steps_box_node(v, h_step, fn(s) {
    steps_press_box(s, toggle, folds=true, open~, fn(line) {
      @sf.style_node(line, fn() { h_step_summary })
      @sf.hover_ground_node(line, lit=Some(fn() { @sf.lit_in_node(line) }))
      summary(line)
      steps_chevron_node(
        line,
        "chevron-down",
        12.0,
        By(fn() { if @sf.lit_in_node(line) { @sf.theme().p.blue } else { @sf.theme().p.muted } }),
        open,
      )
    })
    |> ignore
    steps_reveal_node(s, open, fn(o) { whole_node(o, src, station, key, rk, content, body) })
  })
}

///|
/// What a step or thought holds as it shows in `v`: in brief, read whole now (`history.detail`), a line saying
/// so till it comes (or why it did not, with a retry action).
fn whole_node(
  v : @view.View,
  src : Source,
  station : String,
  key : String,
  rk : String,
  content : Json?,
  body : (@view.View) -> Unit,
) -> Unit {
  if !flag(content, "brief") {
    body(v)
    return
  }
  let entries = items(content, "entries").map(fn(e) {
    match e {
      Number(n, ..) => n
      _ => 0.0
    }
  })
  // (asked once as it first shows, and again when cleared by retry or close+reopen)
  v.reacts(fn() { steps_own.detail.contains(rk) }, fn(has) {
    guard !has else { return }
    if entries.is_empty() {
      steps_own.detail[rk] = (-2.0, @sf.t("web-main.doing.failed"))
      return
    }
    steps_own.detail[rk] = (-1.0, "")
    let mut lo = entries[0]
    let mut hi = entries[0]
    for e in entries {
      lo = dmin(lo, e)
      hi = dmax(hi, e)
    }
    (src.call)(
      "history.detail",
      { "station": Json::string(station), "key": Json::string(key), "from": Json::number(lo), "to": Json::number(hi) },
      fn(res) {
        match res {
          Ok(_) => steps_own.detail[rk] = (0.0, "")
          Err(e) => steps_own.detail[rk] = (-2.0, error_words(e))
        }
      },
    )
  })
  v.pick(fn() {
    match steps_own.detail.get(rk) {
      Some((-2.0, why)) => why
      _ => "\u{0}"
    }
  }, fn(p, why) {
    p.fills_across(Is(true)).cuts_softly(Is(true)) |> ignore
    steps_box_node(p, h_step_body, fn(b) {
      if why == "\u{0}" {
        @sf.wait_line_node(b, fn() { "" }) |> ignore
      } else {
        steps_box_node(b, tool_err_row, fn(er) {
          er.box(fn(w) {
            w.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
            steps_words(w, fn() { @sf.t("web-main.history.stepUnread", args=[("error", why)]) }, h_thinking_muted)
          })
          |> ignore
          if !entries.is_empty() {
            steps_retry_btn_node(er, fn() { steps_own.detail.remove(rk) })
          }
        })
      }
    })
  })
}

///|
/// Compact inline retry action shown beside a failed `history.detail` or `history.tool` read.
fn steps_retry_btn_node(parent : @view.View, on_retry : () -> Unit) -> Unit {
  steps_press_box(parent, on_retry, label=fn() { "重试" }, fn(btn) {
    @sf.style_node(btn, fn() { tool_expand_btn })
    btn.shrink(Is(0.0)) |> ignore
    @sf.words_node(btn, fn() { "重试" }, fn() {
      if @sf.lit_node(btn) { tool_expand_words_hot } else { tool_expand_words }
    })
    |> ignore
  })
  |> ignore
}

///|
/// Builds the `history.tool` request object and cache key for `step`.
fn tool_ask_of(rk : String, step : Json?) -> (Map[String, Json], String) {
  let ask : Map[String, Json] = {
    "name": Json::string(text(step, "name")),
    "call": Json::string(text(step, "call")),
    "failed": Json::boolean(flag(step, "failed")),
    "said": Json::boolean(text(step, "said") != ""),
  }
  match field(step, "result") {
    Some(String(r)) => ask["result"] = Json::string(r)
    _ => ()
  }
  let tk = rk + "\u{1}" + Json::object(ask).stringify()
  (ask, tk)
}

///|
/// Requests `history.tool` once for `tk`, recording either the parsed parts or the error message so callers never spin
/// forever on failure.
fn tool_fetch(src : Source, ask : Map[String, Json], tk : String) -> Unit {
  if @signals.untracked(fn() { steps_own.tools.contains(tk) }) || steps_own.tool_asking.contains(tk) {
    return
  }
  steps_own.tool_asking[tk] = true
  steps_own.tool_err.remove(tk)
  (src.call)("history.tool", Json::object(ask), fn(res) {
    steps_own.tool_asking.remove(tk)
    match res {
      Ok(got) => {
        steps_own.tool_err.remove(tk)
        steps_own.tools[tk] = got
      }
      Err(e) => steps_own.tool_err[tk] = error_words(e)
    }
  })
}

///|
/// Plain copyable text concatenated from a tool step's result parts (for the `返回` header copy button).
fn tool_parts_copy_text(parts : Array[Json]) -> String {
  let chunks : Array[String] = []
  for part in parts {
    let pv = Some(part)
    match text(pv, "kind") {
      "output" | "code" | "json" | "markdown" | "lead" => {
        let t = text(pv, "text")
        if t != "" {
          chunks.push(t)
        }
      }
      "diff" => {
        let diff_rows = items(pv, "rows")
        if !diff_rows.is_empty() {
          chunks.push(
            diff_rows
            .map(fn(r) {
              match r {
                Array([String(m), String(l)]) => m + l
                _ => ""
              }
            })
            .join("\n"),
          )
        }
      }
      _ => ()
    }
  }
  chunks.join("\n")
}

///|
/// A call opened in `v`: what it asked for, then what came back, as the core reads them (`history.tool`),
/// asked once as it is first shown (or pre-fetched before opening by `step_node`).
fn tool_body_node(v : @view.View, src : Source, station : String, key : String, rk : String, step : Json?) -> Unit {
  let (ask, tk) = tool_ask_of(rk, step)
  v.reacts(fn() { steps_own.tools.contains(tk) || steps_own.tool_err.contains(tk) }, fn(settled) {
    guard !settled else { return }
    tool_fetch(src, ask, tk)
  })
  v.pick(fn() {
    if steps_own.tools.contains(tk) {
      2
    } else if steps_own.tool_err.contains(tk) {
      1
    } else {
      0
    }
  }, fn(p, state) {
    p.fills_across(Is(true)).cuts_softly(Is(true)) |> ignore
    if state == 0 {
      steps_box_node(p, h_step_body, fn(b) { @sf.wait_line_node(b, fn() { "" }) |> ignore })
      return
    }
    if state == 1 {
      let why = @signals.untracked(fn() { steps_own.tool_err.get(tk).unwrap_or(@sf.t("web-main.doing.failed")) })
      steps_box_node(p, h_step_body, fn(b) {
        steps_box_node(b, tool_err_row, fn(er) {
          er.box(fn(w) {
            w.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
            steps_words(w, fn() { @sf.t("web-main.history.stepUnread", args=[("error", why)]) }, h_thinking_muted)
          })
          |> ignore
          steps_retry_btn_node(er, fn() {
            steps_own.tool_err.remove(tk)
            tool_fetch(src, ask, tk)
          })
        })
      })
      return
    }
    let parts = @signals.untracked(fn() { steps_own.tools.get(tk) })
    let raw_calls = items(parts, "call")
    let raw_results = items(parts, "result")
    let raw_said = text(step, "said")
    let raw_hint = text(step, "hint")
    let (fb_said, fb_hint) = if raw_said == "" || raw_hint == "" {
      step_call_summary(text(step, "call"))
    } else {
      ("", "")
    }
    let step_said = if raw_said != "" { raw_said } else { fb_said }
    let step_hint = if raw_hint != "" { raw_hint } else { fb_hint }
    let step_meta = text(step, "meta")
    let failed = flag(step, "failed")
    let has_real_call = raw_calls.iter().any(fn(p) { text(Some(p), "kind") != "none" })
    let result_parts : Array[Json] = []
    for part in raw_results {
      let k = text(Some(part), "kind")
      if !failed && k == "none" && has_real_call {
        continue
      }
      if !failed && k == "output" {
        let out = text(Some(part), "text").trim().to_owned()
        if out == "The file has been updated." ||
          out == "File updated successfully." ||
          out == "File created successfully." ||
          (out.has_prefix("File created successfully at:") && !out.contains("\n")) ||
          (out.has_prefix("Made ") && out.contains(" replacement")) {
          continue
        }
      }
      if k == "facts" {
        let kept = items(Some(part), "items").filter(fn(it) {
          let fk = text(Some(it), "key")
          if fk == "退出码 0" || fk == "Exit code 0" {
            false
          } else if step_meta != "" && (fk == step_meta || (fk.has_prefix("第 ") && fk.contains(" 行 · +"))) {
            false
          } else {
            true
          }
        })
        if kept.length() > 0 {
          result_parts.push({ "kind": "facts", "items": Json::array(kept) })
        }
        continue
      }
      result_parts.push(part)
    }
    let call_parts : Array[Json] = []
    for part in raw_calls {
      let k = text(Some(part), "kind")
      if k == "none" && result_parts.length() > 0 {
        continue
      }
      if (raw_calls.length() > 1 || result_parts.length() > 0) && k == "path" && text(Some(part), "extra") == "" {
        let p = text(Some(part), "path")
        let matches_hint = step_hint != "" && (p == step_hint || p.has_suffix("/" + step_hint))
        let matches_said = step_said != "" && (p == step_said || p.has_suffix("/" + step_said))
        let matches_both = step_hint != "" &&
          step_said != "" &&
          (p == step_hint + "/" + step_said || p.has_suffix("/" + step_hint + "/" + step_said))
        if matches_hint || matches_said || matches_both {
          continue
        }
      }
      call_parts.push(part)
    }
    if call_parts.is_empty() && result_parts.is_empty() {
      for part in raw_results {
        if text(Some(part), "kind") != "none" {
          result_parts.push(part)
        }
      }
    }
    if call_parts.is_empty() && result_parts.is_empty() {
      return
    }
    // Every expanded tool step renders inside ONE faint rounded card (`tool_body_card`) so its start and end are
    // unmistakable; the only exception is a standalone short `diff` (`<= 14` rows, no result parts), where `tool_diff`
    // is already that single faint rounded container with full-bleed +/- lines.
    let standalone_short_diff = call_parts.length() == 1 &&
      result_parts.is_empty() &&
      text(Some(call_parts[0]), "kind") == "diff" &&
      items(Some(call_parts[0]), "rows").length() <= 14
    let in_card = !standalone_short_diff
    let body_style = if in_card { tool_body_card } else { tool_body_box }
    let has_result_head = in_card && (call_parts.length() > 0 || failed)
    let result_copy = if has_result_head { tool_parts_copy_text(result_parts) } else { "" }
    steps_box_node(p, body_style, fn(b) {
      if call_parts.length() > 0 {
        steps_box_node(b, if in_card { tool_section_card } else { tool_section }, fn(s) {
          for idx, part in call_parts {
            tool_part_node(s, Some(part), rk=rk + "/c" + idx.to_string(), src~, station~, key~, in_card~)
          }
        })
      }
      if result_parts.length() > 0 {
        let res_style = if in_card && call_parts.length() > 0 {
          tool_result_card
        } else {
          tool_section
        }
        steps_box_node(b, res_style, fn(s) {
          if has_result_head {
            steps_box_node(s, tool_result_head, fn(h) {
              steps_words(
                h,
                fn() { if failed { "返回 · 失败" } else { "返回" } },
                if failed { tool_result_head_red } else { tool_result_head_words },
              )
              steps_box_node(h, h_grow, fn(_) {  }, in_row=true)
              tool_copy_btn_node(h, result_copy)
            })
          }
          for idx, part in result_parts {
            tool_part_node(
              s,
              Some(part),
              rk=rk + "/r" + idx.to_string(),
              src~,
              station~,
              key~,
              in_card~,
              has_bar=has_result_head,
            )
          }
        })
      }
    })
  })
}

///|
/// A list of things to do in `v`, each `{text, status}`, as `list` says it now: done ✓ struck and muted, under way › in
/// 600, the rest ·. A plan call's in the history, and an agent's checklist in the panel of its work (agent_work_node):
/// a row each by its place in the list, its mark and words as its item says them now, one more or less coming and
/// going as the list changes (View::each).
fn plan_node(v : @view.View, list : () -> Array[Json]) -> Unit {
  steps_box_node(v, tool_plan, fn(p) {
    p.each(fn() { list().mapi(fn(i, it) { (i, it) }) }, fn(x) { x.0 }, fn(row, item) {
      let status = fn() { text(Some(item.get().1), "status") }
      let words = fn() {
        match status() {
          "completed" => tool_plan_done
          "in_progress" => tool_plan_now
          _ => tool_plan_words
        }
      }
      let mark_ink = fn() {
        match status() {
          "completed" => @sf.theme().p.green
          "in_progress" => @sf.theme().p.accent
          _ => @sf.theme().p.subtle
        }
      }
      steps_box_node(row, tool_plan_row, fn(r) {
        steps_box_node(r, tool_plan_mark, fn(m) {
          m.box(fn(w) {
            w
            .words(By(fn() {
              match status() {
                "completed" => "✓"
                "in_progress" => "›"
                _ => "·"
              }
            }))
            .words_look(By(fn() { @ui.style_words(tool_plan_words) }))
            .ink(By(mark_ink))
            |> ignore
          })
          |> ignore
        })
        // (the room its mark leaves, from none: its words wrapped at that width, not at the row's)
        r.box(fn(w) {
          w.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
          w.box(fn(x) {
            x
            .words_runs(By(fn() { [@ui.span(text(Some(item.get().1), "text"), strike=status() == "completed")] }))
            .words_look(By(fn() { @ui.style_words(words()) }))
            .ink(By(fn() { @ui.style_ink(words()) }))
            .shrink(Is(1.0))
            .min_width(Is(Some(0.0)))
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
    })
  })
}

///|
/// Whether a block of text is long enough to offer folding and a full-screen reader drawer.
fn is_long_block(words : String) -> Bool {
  if words.length() > 420 {
    return true
  }
  let mut nl = 0
  for ch in words {
    if ch == '\n' {
      nl = nl + 1
      if nl >= 10 {
        return true
      }
    }
  }
  false
}

///|
/// Whether a short field key holds natural-language prose rather than an identifier/code value.
fn is_prose_key(key : String) -> Bool {
  match key {
    "summary" | "description" | "title" | "reason" | "about" | "role" | "Role" | "explanation" | "note" | "question" => true
    _ => false
  }
}

///|
/// Renders `words` as Markdown when a parsed tree (`md`) or live Markdown reader is available, falling back to plain
/// prose text in unit tests that pass raw strings without `md`.
fn render_md_or_words(v : @view.View, words : String, md : Json?, small? : Bool = false) -> Unit {
  if md is Some(Array(_)) || @sf.markdown_read.val is Some(_) {
    md_node(v, words, md, small~)
  } else {
    steps_words(v, fn() { words }, if small { tool_long_words } else { h_words })
  }
}

///|
/// Renders a short prose value inline, turning `code` spans into monospace runs instead of showing raw backticks.
fn steps_prose_inline(parent : @view.View, words : String, style : @ui.TextStyle) -> Unit {
  if !words.contains("`") {
    steps_words(parent, fn() { words }, style)
    return
  }
  parent.box(fn(w) {
    w
    .words_runs(By(fn() {
      let runs = []
      let parts = words.split("`").to_array()
      for i, part in parts {
        let s = part.to_owned()
        if s != "" {
          if i % 2 == 1 && i + 1 < parts.length() {
            runs.push(@ui.span(s, mono=true, color=@sf.theme().p.text))
          } else {
            runs.push(@ui.span(s))
          }
        }
      }
      if runs.is_empty() { [@ui.span(words)] } else { runs }
    }))
    .words_look(By(fn() { @ui.style_words(style) }))
    .ink(By(fn() { @ui.style_ink(style) }))
    .shrink(Is(1.0))
    .min_width(Is(Some(0.0)))
    |> ignore
  })
  |> ignore
}

///|
/// Opens a full-width reader sheet (on phone) or wide dialog (on desktop) for reading and copying a tool step's content.
fn open_tool_reader(title : String, raw_copy : String, body : (@view.View) -> Unit) -> Unit {
  let copied = @signals.signal(false)
  @sf.panel_nodes(
    if title != "" { title } else { "查看内容" },
    fn(p, _) {
      // (what it holds scrolling in itself past the panel's share of the window, its title and foot where they are: a
      // tall panel's body scrolls itself, panel_nodes' `tall`)
      p.box(fn(room) {
        let side = @sf.panel_sides_at_node(room)
        @sf.style_node(room, fn() { @sf.panel_bleed_node(room) })
        @ui.words_picked(room)
        room.scrolls(@view.Scroll::new(), slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(s) {
          if side > 0.0 {
            s.padding(Is((side, 0.0, side, 0.0))) |> ignore
          }
          s.box(fn(b) {
            @sf.style_node(b, fn() { @sf.panel_words_in_node(b).then(tool_reader_body) })
            body(b)
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    from=Unanchored,
    wide=true,
    tall=0.82,
    grows=true,
    hugs=true,
    foot=fn(fv, close) {
      if raw_copy != "" {
        @sf.button_node(
          fv,
          fn() { if copied.get() { "已复制" } else { "复制" } },
          fn() {
            @ui.clipboard_set(raw_copy)
            copied.set(true)
          },
          icon="copy",
        )
        |> ignore
      }
      @sf.button_node(fv, fn() { @sf.t("common.done") }, close, tone=Primary) |> ignore
    },
  )
}

///|
fn tool_copy_trigger(
  my_id : Int,
  raw_copy : String,
) -> Unit {
  @ui.clipboard_set(raw_copy)
  steps_own.copied_id.set(my_id)
  @sfbase.toast_later(@sf.t("common.copied"))
}

///|
/// Compact inline copy button (`复制` -> `已复制`) for tool block bars and result headers.
fn tool_copy_btn_node(parent : @view.View, raw_copy : String) -> Unit {
  guard raw_copy != "" else { return }
  steps_own.copied_seq = steps_own.copied_seq + 1
  let my_id = steps_own.copied_seq
  let copied = fn() { steps_own.copied_id.get() == my_id }
  steps_press_box(
    parent,
    fn() { tool_copy_trigger(my_id, raw_copy) },
    label=fn() { if copied() { "已复制" } else { "复制" } },
    fn(b) {
      @sf.style_node(b, fn() { tool_copy_btn })
      b.shrink(Is(0.0)) |> ignore
      let ink = fn() {
        if copied() {
          @sf.theme().p.green_ink
        } else if @sf.lit_node(b) {
          @sf.theme().p.text
        } else {
          @sf.theme().p.muted
        }
      }
      @sf.icon_node(
        b,
        "copy",
        11.0,
        By(ink),
        name_now=fn() { if copied() { "check" } else { "copy" } },
      )
      |> ignore
      @sf.words_node(b, fn() { if copied() { "已复制" } else { "复制" } }, fn() {
        if copied() {
          tool_copy_words_done
        } else if @sf.lit_node(b) {
          tool_copy_words_hot
        } else {
          tool_copy_words
        }
      })
      |> ignore
    },
  )
  |> ignore
}

///|
/// Compact icon-only copy button aligned to the first line of a short command/code/output block.
fn tool_copy_icon_node(parent : @view.View, raw_copy : String) -> Unit {
  guard raw_copy != "" else { return }
  steps_own.copied_seq = steps_own.copied_seq + 1
  let my_id = steps_own.copied_seq
  let copied = fn() { steps_own.copied_id.get() == my_id }
  steps_press_box(
    parent,
    fn() { tool_copy_trigger(my_id, raw_copy) },
    label=fn() { if copied() { "已复制" } else { "复制" } },
    fn(b) {
      @sf.style_node(b, fn() { tool_copy_icon })
      b.shrink(Is(0.0)) |> ignore
      let ink = fn() {
        if copied() {
          @sf.theme().p.green_ink
        } else if @sf.lit_node(b) {
          @sf.theme().p.text
        } else {
          @sf.theme().p.subtle
        }
      }
      @sf.icon_node(
        b,
        "copy",
        12.0,
        By(ink),
        name_now=fn() { if copied() { "check" } else { "copy" } },
      )
      |> ignore
    },
  )
  |> ignore
}

///|
/// Monospace block that preserves original lines and scrolls horizontally when wider than the card.
fn steps_across_run(parent : @view.View, words : () -> String, style : @ui.TextStyle) -> Unit {
  parent.box(fn(q) {
    q.fills_across(Is(true)).min_width(Is(Some(0.0))) |> ignore
    q.scrolls(@view.Scroll::across(), slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(held) {
      held.grow(Is(1.0)).lines_up(Is(Some(Start))) |> ignore
      held.box(fn(w) {
        w
        .words_runs(By(fn() { [@ui.span(words(), mono=true)] }))
        .words_look(By(fn() { @ui.style_words(style) }))
        .ink(By(fn() { @ui.style_ink(style) }))
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// Horizontally scrollable monospace block with a compact first-line-aligned copy icon on the right.
fn steps_across_copy_row(parent : @view.View, raw : String, style : @ui.TextStyle) -> Unit {
  parent.box(fn(r) {
    r.row(Is(true)).fills_across(Is(true)).lines_up(Is(Some(Start))).gap(Is(4.0)) |> ignore
    r.box(fn(q) {
      q.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
      steps_across_run(q, fn() { raw }, style)
    })
    |> ignore
    tool_copy_icon_node(r, raw)
  })
  |> ignore
}

///|
/// Wrapping monospace block with a compact first-line-aligned copy icon on the right.
fn steps_wrap_copy_row(parent : @view.View, raw : String, style : @ui.TextStyle) -> Unit {
  parent.box(fn(r) {
    r.row(Is(true)).fills_across(Is(true)).lines_up(Is(Some(Start))).gap(Is(4.0)) |> ignore
    r.box(fn(q) {
      q.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
      steps_run(q, fn() { raw }, style, mono=true)
    })
    |> ignore
    tool_copy_icon_node(r, raw)
  })
  |> ignore
}

///|
/// Compact action chip that opens `open_tool_reader` for a long field, dispatch card, or code/output block.
fn tool_expand_btn_node(parent : @view.View, title : String, raw_copy : String, body : (@view.View) -> Unit) -> Unit {
  steps_press_box(parent, fn() { open_tool_reader(title, raw_copy, body) }, label=fn() { "全屏查看" }, fn(btn) {
    @sf.style_node(btn, fn() { tool_expand_btn })
    btn.shrink(Is(0.0)) |> ignore
    let ink = fn() { if @sf.lit_node(btn) { @sf.theme().p.accent } else { @sf.theme().p.blue } }
    @sf.icon_node(btn, "expand", 11.0, By(ink)) |> ignore
    @sf.words_node(btn, fn() { "全屏查看" }, fn() {
      if @sf.lit_node(btn) {
        tool_expand_words_hot
      } else {
        tool_expand_words
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// Navigates to the sub-agent step or target chat referenced by a dispatch card's target badge.
fn jump_to_dispatch_target(src : Source, station : String, key : String, current_rk : String, target : String) -> Unit {
  let t = target.trim().to_owned()
  guard t != "" else { return }
  if t.has_prefix("c-") || t.contains("/chats/") {
    let session = match t.find("/chats/") {
      Some(i) => t.unsafe_substring(start=i + 7, end=t.length())
      None => t
    }
    if session != "" && station != "" {
      @sfbase.history_push()
      app.nav.push(Chat({ station, session, title: t, station_name: "" }))
      return
    }
  }
  guard station != "" && key != "" else { return }
  let h = @signals.untracked(fn() {
    src.topic("history", { "station": Json::string(station), "key": Json::string(key) }).get().value
  })
  let loaded = items(h, "items")
  for it in loaded {
    let ik = steps_item_key(station, key, text(Some(it), "key"))
    let body = field(Some(it), "body")
    let kind = text(body, "kind")
    let content = field(body, "content")
    if kind == "group" {
      let gk = ik + "/group"
      for j, r in items(content, "rows") {
        let rk = group_row_key(gk, r, j)
        if rk != current_rk && !current_rk.has_prefix(rk + "/") && r.stringify().contains(t) {
          steps_own.opened[gk] = true
          steps_own.opened[rk] = true
          match entries_of(Some(it)) {
            Some((e0, _)) => history_focus(station, key, e0)
            None => ()
          }
          return
        }
      }
    } else if kind == "received" {
      for k, task in items(content, "tasks") {
        if task.stringify().contains(t) {
          steps_own.opened[ik + "/task/" + k.to_string()] = true
          match entries_of(Some(it)) {
            Some((e0, _)) => history_focus(station, key, e0)
            None => ()
          }
          return
        }
      }
    }
  }
}

///|
/// Renders the diff lines of a `"diff"` tool part in `v`, preserving original line lengths with horizontal scrolling.
fn tool_diff_node(v : @view.View, diff_rows : Array[Json]) -> Unit {
  let n = diff_rows.length()
  steps_box_node(v, tool_diff, fn(d) {
    d.scrolls(@view.Scroll::across(), slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(held) {
      held.grow(Is(1.0)).lines_up(Is(None)) |> ignore
      for i, r in diff_rows {
        match r {
          Array([String(mark), String(line)]) =>
            held.box(fn(l) {
              let is_first = i == 0
              let is_last = i + 1 == n
              @sf.style_node(l, fn() {
                let base = match mark {
                  "-" => tool_diff_out
                  "+" => tool_diff_line.then(@ui.style(bg=Data(@sf.theme().p.green_bg)))
                  "@" => tool_diff_head
                  _ => tool_diff_line
                }
                let with_top = if is_first { base.then(tool_diff_row_top) } else { base }
                if is_last { with_top.then(tool_diff_row_bot) } else { with_top }
              })
              // (in the theme's inks as it is now: the dark one's where it is told to be dark)
              let ink = fn() {
                match mark {
                  "-" => @sf.theme().p.red
                  "+" => @sf.theme().p.green_ink
                  _ => @sf.theme().p.subtle
                }
              }
              // (its mark in the gutter before its words, the line's ends as far in either side)
              steps_box_node(l, tool_diff_mark, fn(m) {
                m.shrink(Is(0.0)) |> ignore
                if mark == "-" || mark == "+" {
                  steps_run(m, fn() { mark }, tool_mono_nowrap, mono=true, ink~)
                }
              })
              l.box(fn(w) {
                w
                .words_runs(By(fn() { [@ui.span(if line == "" { " " } else { line }, mono=true)] }))
                .words_look(By(fn() {
                  @ui.style_words(match mark {
                    "@" => tool_mono_head_nowrap
                    " " => tool_mono_muted_nowrap
                    _ => tool_mono_nowrap
                  })
                }))
                .ink(By(fn() {
                  @ui.style_ink(match mark {
                    "@" => tool_mono_head_nowrap
                    " " => tool_mono_muted_nowrap
                    _ => tool_mono_nowrap
                  })
                }))
                |> ignore
              })
              |> ignore
            })
            |> ignore
          _ => ()
        }
      }
    })
    |> ignore
  })
}

///|
/// Renders a code block in `parent` using the history panel's unified `@sf.faint_ground` container background.
fn tool_code_block_node(parent : @view.View, code_text : String, lang : String) -> Unit {
  parent.box(fn(b) {
    @sf.code_block_node(b, fn() { code_text }, fn() { lang }, fn() { None })
    b.ground(By(fn() { @ui.tree_theme().color(@sf.faint_ground) })) |> ignore
  })
  |> ignore
}

///|
/// One part of a call or of what came back in `v`.
fn tool_part_node(
  v : @view.View,
  part : Json?,
  rk? : String = "",
  src? : Source = @sfbase.sample_source,
  station? : String = "",
  key? : String = "",
  in_card? : Bool = false,
  has_bar? : Bool = false,
) -> Unit {
  match text(part, "kind") {
    "code" => {
      let code_text = text(part, "text")
      let lang = text(part, "lang")
      let reader_title = if lang != "" { "代码 · " + lang } else { "代码" }
      let open_full = fn() {
        open_tool_reader(reader_title, code_text, fn(rb) { tool_code_block_node(rb, code_text, lang) })
      }
      let render_inline_code = fn(host : @view.View, show_copy : Bool) {
        if in_card {
          if code_text.contains("\n") {
            if show_copy {
              steps_across_copy_row(host, code_text, tool_mono_nowrap)
            } else {
              steps_across_run(host, fn() { code_text }, tool_mono_nowrap)
            }
          } else if show_copy {
            steps_wrap_copy_row(host, code_text, tool_mono)
          } else {
            steps_run(host, fn() { code_text }, tool_mono, mono=true)
          }
        } else {
          tool_code_block_node(host, code_text, lang)
        }
      }
      if is_long_block(code_text) {
        steps_box_node(v, tool_field_stack, fn(stack) {
          steps_box_node(stack, tool_block_bar, fn(bar) {
            steps_words(bar, fn() { if lang != "" { lang } else { "代码" } }, tool_key_words)
            steps_box_node(bar, h_grow, fn(_) {  }, in_row=true)
            tool_copy_btn_node(bar, code_text)
            tool_expand_btn_node(bar, reader_title, code_text, fn(rb) {
              tool_code_block_node(rb, code_text, lang)
            })
          })
          clip_lines_node(stack, 14, words_line, fn(f) { render_inline_code(f, false) }, on_full=Some(open_full))
        })
      } else if in_card && may_clip_block(code_text) {
        clip_lines_node(v, 14, words_line, fn(f) { render_inline_code(f, !has_bar) }, on_full=Some(open_full))
      } else {
        render_inline_code(v, !has_bar)
      }
    }
    "facts" =>
      steps_box_node(v, tool_facts, fn(f) {
        f.wraps(Is(Some(4.0))) |> ignore
        for fact in items(part, "items") {
          let fv = Some(fact)
          match field(fv, "value") {
            Some(String(value)) if !flag(fv, "plain") =>
              f.box(fn(w) {
                w
                .words_runs(By(fn() {
                  [
                    @ui.span(text(fv, "key") + " "),
                    @ui.span(value, mono=true, color=@sf.theme().p.muted, weight=500),
                  ]
                }))
                .words_look(By(fn() { @ui.style_words(tool_fact) }))
                .ink(By(fn() { @ui.style_ink(tool_fact) }))
                .shrink(Is(1.0))
                .min_width(Is(Some(0.0)))
                |> ignore
              })
              |> ignore
            _ => steps_words(f, fn() { text(fv, "key") }, tool_fact)
          }
        }
      })
    "path" =>
      steps_box_node(v, tool_path, fn(p) {
        p.box(fn(w) {
          w.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
          steps_run(w, fn() { text(part, "path") }, tool_path_words, mono=true)
        })
        |> ignore
        match text(part, "extra") {
          "" => ()
          e => @sf.words_node(p, fn() { e }, fn() { tool_path_extra }).shrink(Is(0.0)) |> ignore
        }
      })
    "diff" => {
      let diff_rows = items(part, "rows")
      if diff_rows.length() > 14 {
        let raw_diff = diff_rows
          .map(fn(r) {
            match r {
              Array([String(m), String(l)]) => m + l
              _ => ""
            }
          })
          .join("\n")
        let open_full = fn() {
          open_tool_reader("变更对比", raw_diff, fn(rb) { tool_diff_node(rb, diff_rows) })
        }
        steps_box_node(v, tool_field_stack, fn(stack) {
          steps_box_node(stack, tool_block_bar, fn(bar) {
            steps_words(bar, fn() { "变更对比" }, tool_key_words)
            steps_box_node(bar, h_grow, fn(_) {  }, in_row=true)
            tool_copy_btn_node(bar, raw_diff)
            tool_expand_btn_node(bar, "变更对比", raw_diff, fn(rb) { tool_diff_node(rb, diff_rows) })
          })
          clip_lines_node(stack, 14, words_line, fn(f) { tool_diff_node(f, diff_rows) }, on_full=Some(open_full))
        })
      } else {
        tool_diff_node(v, diff_rows)
      }
    }
    "markdown" => {
      let words = text(part, "text")
      let md = field(part, "md")
      let target = text(part, "target")
      let target_id = text(part, "targetId")
      let nav_target = if target_id != "" { target_id } else { target }
      let summary = text(part, "summary")
      let long = is_long_block(words)
      let reader_title = if summary != "" { summary } else if target != "" { "→ " + target } else { "查看内容" }
      let open_full = fn() {
        open_tool_reader(reader_title, words, fn(rb) { render_md_or_words(rb, words, md, small=false) })
      }
      let render_md_body = fn(host : @view.View) {
        if long || may_clip_block(words) {
          clip_lines_node(host, 14, md_line, fn(f) { render_md_or_words(f, words, md, small=true) }, on_full=Some(open_full))
        } else {
          render_md_or_words(host, words, md, small=true)
        }
      }
      if target != "" || long {
        steps_box_node(v, tool_field_stack, fn(stack) {
          steps_box_node(stack, tool_block_bar, fn(bar) {
            if target != "" {
              steps_press_box(bar, fn() { jump_to_dispatch_target(src, station, key, rk, nav_target) }, label=fn() { "→ " + target }, fn(badge) {
                @sf.style_node(badge, fn() { tool_dispatch_badge })
                let ink = fn() { if @sf.lit_node(badge) { @sf.theme().p.blue } else { @sf.theme().p.accent_text } }
                @sf.icon_node(badge, "agent", 12.0, By(ink)) |> ignore
                @sf.words_node(badge, fn() { "→ " + target }, fn() {
                  if @sf.lit_node(badge) {
                    tool_dispatch_target_words_hot
                  } else {
                    tool_dispatch_target_words
                  }
                })
                |> ignore
              })
              |> ignore
            }
            steps_box_node(bar, h_grow, fn(_) {  }, in_row=true)
            tool_copy_btn_node(bar, words)
            if long {
              tool_expand_btn_node(
                bar,
                reader_title,
                words,
                fn(rb) { render_md_or_words(rb, words, md, small=false) },
              )
            }
          })
          render_md_body(stack)
        })
      } else {
        render_md_body(v)
      }
    }
    "plan" => {
      let plan_items = items(part, "items")
      if plan_items.length() > 10 {
        let copy_buf = StringBuilder()
        for it in plan_items {
          let iv = Some(it)
          let mark = match text(iv, "status") {
            "completed" => "[x] "
            "in_progress" => "[>] "
            _ => "[ ] "
          }
          copy_buf.write_string(mark + text(iv, "text") + "\n")
        }
        let copy_text = copy_buf.to_string()
        let open_full = fn() {
          open_tool_reader("计划", copy_text, fn(rb) { plan_node(rb, fn() { plan_items }) })
        }
        steps_box_node(v, tool_field_stack, fn(stack) {
          steps_box_node(stack, tool_block_bar, fn(bar) {
            steps_words(bar, fn() { "计划" }, tool_key_words)
            steps_box_node(bar, h_grow, fn(_) {  }, in_row=true)
            tool_copy_btn_node(bar, copy_text)
            tool_expand_btn_node(bar, "计划", copy_text, fn(rb) { plan_node(rb, fn() { plan_items }) })
          })
          clip_lines_node(stack, 12, words_line, fn(f) { plan_node(f, fn() { plan_items }) }, on_full=Some(open_full))
        })
      } else {
        plan_node(v, fn() { plan_items })
      }
    }
    "fields" =>
      steps_box_node(v, tool_fields, fn(fs) {
        for r in items(part, "rows") {
          let rv = Some(r)
          let k = text(rv, "key")
          let val = text(rv, "value")
          let form = text(rv, "form")
          let prose = flag(rv, "prose") || is_prose_key(k)
          match form {
            "long" => {
              let long = is_long_block(val)
              let open_full = fn() {
                open_tool_reader(k, val, fn(rb) { render_md_or_words(rb, val, field(rv, "md"), small=false) })
              }
              let render_long_val = fn(host : @view.View) {
                if long || may_clip_block(val) {
                  clip_lines_node(
                    host,
                    14,
                    md_line,
                    fn(inner) { render_md_or_words(inner, val, field(rv, "md"), small=true) },
                    on_full=Some(open_full),
                  )
                } else {
                  render_md_or_words(host, val, field(rv, "md"), small=true)
                }
              }
              steps_box_node(fs, tool_field_stack, fn(f) {
                steps_box_node(f, tool_field_head, fn(head) {
                  steps_words(head, fn() { k }, tool_key_words)
                  steps_box_node(head, h_grow, fn(_) {  }, in_row=true)
                  tool_copy_btn_node(head, val)
                  if long {
                    tool_expand_btn_node(head, k, val, fn(rb) {
                      render_md_or_words(rb, val, field(rv, "md"), small=false)
                    })
                  }
                })
                render_long_val(f)
              })
            }
            "json" => {
              let long = is_long_block(val)
              let open_full = fn() {
                open_tool_reader(k, val, fn(rb) { steps_across_run(rb, fn() { val }, tool_mono_nowrap) })
              }
              let render_json_val = fn(host : @view.View) {
                if long || may_clip_block(val) {
                  clip_lines_node(
                    host,
                    14,
                    words_line,
                    fn(inner) { steps_across_run(inner, fn() { val }, tool_mono_nowrap) },
                    on_full=Some(open_full),
                  )
                } else {
                  steps_across_run(host, fn() { val }, tool_mono_nowrap)
                }
              }
              steps_box_node(fs, tool_field_stack, fn(f) {
                steps_box_node(f, tool_field_head, fn(head) {
                  steps_words(head, fn() { k }, tool_key_words)
                  steps_box_node(head, h_grow, fn(_) {  }, in_row=true)
                  tool_copy_btn_node(head, val)
                  if long {
                    tool_expand_btn_node(head, k, val, fn(rb) {
                      steps_across_run(rb, fn() { val }, tool_mono_nowrap)
                    })
                  }
                })
                if in_card {
                  render_json_val(f)
                } else {
                  steps_box_node(f, tool_box, render_json_val)
                }
              })
            }
            _ =>
              steps_box_node(fs, tool_field, fn(f) {
                steps_box_node(f, tool_field_key, fn(kb) { steps_words(kb, fn() { k }, tool_key_words) })
                steps_box_node(f, h_grow, fn(g) {
                  if prose {
                    steps_prose_inline(g, val, tool_value)
                  } else {
                    steps_run(g, fn() { val }, tool_value, mono=true)
                  }
                }, in_row=true)
              })
          }
        }
      })
    "lead" => steps_box_node(v, tool_lead, fn(b) { card_plain_or_clip_node(b, "参数", text(part, "text"), tool_lead_words, mono=true) })
    "none" => steps_box_node(v, tool_lead, fn(b) { steps_words(b, fn() { text(part, "text") }, tool_none) })
    "output" => {
      let out_text = text(part, "text")
      let is_failed = flag(part, "failed")
      let box_look = if is_failed { tool_box_red } else { tool_box }
      let text_look = if is_failed { tool_mono } else { tool_mono_muted }
      let open_full = fn() {
        open_tool_reader("输出", out_text, fn(rb) { steps_run(rb, fn() { out_text }, text_look, mono=true) })
      }
      let render_out = fn(host : @view.View, show_copy : Bool) {
        let draw_line = fn(h : @view.View) {
          if show_copy {
            steps_wrap_copy_row(h, out_text, text_look)
          } else {
            steps_run(h, fn() { out_text }, text_look, mono=true)
          }
        }
        if is_long_block(out_text) || may_clip_block(out_text) {
          clip_lines_node(host, 14, words_line, draw_line, on_full=Some(open_full))
        } else {
          draw_line(host)
        }
      }
      if is_long_block(out_text) {
        steps_box_node(v, tool_field_stack, fn(stack) {
          steps_box_node(stack, tool_block_bar, fn(bar) {
            steps_words(bar, fn() { "输出" }, tool_key_words)
            steps_box_node(bar, h_grow, fn(_) {  }, in_row=true)
            tool_copy_btn_node(bar, out_text)
            tool_expand_btn_node(bar, "输出", out_text, fn(rb) {
              steps_run(rb, fn() { out_text }, text_look, mono=true)
            })
          })
          if in_card && !is_failed {
            render_out(stack, false)
          } else {
            steps_box_node(stack, box_look, fn(bx) { render_out(bx, false) })
          }
        })
      } else if in_card && !is_failed {
        render_out(v, !has_bar)
      } else {
        steps_box_node(v, box_look, fn(bx) { render_out(bx, !has_bar) })
      }
    }
    "json" => {
      let json_text = text(part, "text")
      let open_full = fn() {
        open_tool_reader("JSON", json_text, fn(rb) { steps_across_run(rb, fn() { json_text }, tool_mono_nowrap) })
      }
      let render_json = fn(host : @view.View, show_copy : Bool) {
        let draw_line = fn(h : @view.View) {
          if show_copy {
            steps_across_copy_row(h, json_text, tool_mono_nowrap)
          } else {
            steps_across_run(h, fn() { json_text }, tool_mono_nowrap)
          }
        }
        if is_long_block(json_text) || may_clip_block(json_text) {
          clip_lines_node(host, 14, words_line, draw_line, on_full=Some(open_full))
        } else {
          draw_line(host)
        }
      }
      if is_long_block(json_text) {
        steps_box_node(v, tool_field_stack, fn(stack) {
          steps_box_node(stack, tool_block_bar, fn(bar) {
            steps_words(bar, fn() { "JSON" }, tool_key_words)
            steps_box_node(bar, h_grow, fn(_) {  }, in_row=true)
            tool_copy_btn_node(bar, json_text)
            tool_expand_btn_node(bar, "JSON", json_text, fn(rb) {
              steps_across_run(rb, fn() { json_text }, tool_mono_nowrap)
            })
          })
          if in_card {
            render_json(stack, false)
          } else {
            steps_box_node(stack, tool_box, fn(bx) { render_json(bx, false) })
          }
        })
      } else if in_card {
        render_json(v, !has_bar)
      } else {
        steps_box_node(v, tool_box, fn(bx) { render_json(bx, !has_bar) })
      }
    }
    _ => ()
  }
}

///|
/// Where the turn stands with the model in `v`: its pulse in the gutter, the core's words, a clock
/// running each second.
fn phase_line_node(v : @view.View, src : Source, p : Json?) -> Unit {
  let since = number(p, "since")
  steps_main_node(v, fn(m) {
    let tick = steps_seconds(m, src, since)
    ev_node(m, "pulse", "", "", fn(b) {
      steps_box_node(b, h_state_line, fn(l) {
        steps_words(l, fn() { text(p, "text") }, if text(p, "phase") == "responding" { h_phase_now } else { h_phase_words })
        steps_words(l, fn() {
          tick() |> ignore
          let secs = dmax(((src.now)() - since) / second_ms, 0.0).to_int()
          "\{secs}s"
        }, h_phase_time)
      })
    })
  })
}

///|
/// A call's hint and a thought's first words on their line, cut at its end (h_step_hint's, one line).
// kept across runs: a value (no field of it changes)
let h_step_hint_line : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false, w=Cut)

///|
/// What the steps keep of their own (the rest is the core's): what the reader opened (folds, lines, groups, calls), by
/// their keys; the entries read whole (by the step's key: when they came, -1 asked, -2 failed and why); what the core
/// said each opened call is (`history.tool`, by its key). What
/// a row shows of them it reads, followed (a row is kept while nothing it read changed: history_steps_node).
priv struct StepsOwn {
  opened : @sf.LiveMap[String, Bool]
  detail : @sf.LiveMap[String, (Double, String)]
  tools : @sf.LiveMap[String, Json]
  tool_err : @sf.LiveMap[String, String]
  tool_asking : Map[String, Bool]
  /// an entry asked to be brought into view, by history (`<station>\u{1}<key>`); the item gone to, marked a moment
  /// (its history's list, its key), and the histories gone to an entry, not following their newest till back at foot
  focus : @sf.LiveMap[String, Int]
  marked : @signals.Signal[(String, String)]
  went : @sf.LiveMap[String, Bool]
  /// last non-bottom scroll place `(first_key, into)` by list key, restored when switching side tabs back
  kept_place : Map[String, (String, Double)]
  /// each history's first item as its list was last built, by the list's key
  tops : Map[String, String]
  /// 只看收发, for every history (as the web keeps it): a signal, what each history's rows are worked out by
  only_io : @signals.Signal[Bool]
  /// last copied tool block button id so copying another block resets the previous check mark
  copied_id : @signals.Signal[Int]
  mut copied_seq : Int
}

///|
let steps_own : StepsOwn = {
  opened: @sf.LiveMap::new(),
  detail: @sf.LiveMap::new(),
  tools: @sf.LiveMap::new(),
  tool_err: @sf.LiveMap::new(),
  tool_asking: {},
  focus: @sf.LiveMap::new(),
  marked: @signals.signal(("", ""), same=fn(a, b) { a == b }),
  went: @sf.LiveMap::new(),
  kept_place: {},
  tops: {},
  only_io: @signals.signal(false, same=fn(a, b) { a == b }),
  copied_id: @signals.signal(0, same=fn(a, b) { a == b }),
  copied_seq: 0,
}

///|
fn steps_reset() -> Unit {
  steps_own.opened.clear()
  steps_own.detail.clear()
  steps_own.tools.clear()
  steps_own.tool_err.clear()
  steps_own.tool_asking.clear()
  steps_own.focus.clear()
  steps_own.marked.set(("", ""))
  steps_own.went.clear()
  steps_own.kept_place.clear()
  steps_own.tops.clear()
  steps_own.only_io.set(false)
  steps_own.copied_id.set(0)
  steps_own.copied_seq = 0
}

///|
/// Whether a history shows only what came in and went out.
pub fn history_only_io() -> Bool {
  steps_own.only_io.get()
}

///|
/// 只看收发 turned on or off.
pub fn history_only_io_flip() -> Unit {
  steps_own.only_io.set(!steps_own.only_io.get())
}

///|
/// Agent `key`'s history on `station` to bring transcript entry `entry` into view as it next shows (a link's
/// `?history=…&entry=…`, History.tsx focusEntry): the item that draws it in the pane's middle, marked a moment.
pub fn history_focus(station : String, key : String, entry : Int) -> Unit {
  steps_own.focus[station + "\u{1}" + key] = entry
}

///|
/// The transcript entries an item spans (HistoryItem.entries: its first and last), if it says.
fn entries_of(item : Json?) -> (Int, Int)? {
  match field(item, "entries") {
    Some(Array([Number(a, ..), Number(b, ..)])) => Some((a.to_int(), b.to_int()))
    _ => None
  }
}

///|
/// One of the history's rows: its top (where it begins, or the pages before on their way), an item (the rail running on
/// past it), the thinking and reply streaming in, the turn's state with the model.
priv enum StepsRow {
  Edge
  Item(Json, Bool)
  Live(Json, Bool)
  Phase(Json)
}

///|
/// The same row: its kind and what it was made of, the one JSON or equal (a row the core's delta kept is the one it was).
impl Eq for StepsRow with equal(a, b) {
  match (a, b) {
    (Edge, Edge) => true
    (Item(j, x), Item(k, y)) | (Live(j, x), Live(k, y)) => x == y && @signals.same_value(j, k)
    (Phase(j), Phase(k)) => @signals.same_value(j, k)
    _ => false
  }
}

///|
/// How an agent's history's steps stand (what builds them reads of it): read yet, why its read failed (read again),
/// none, what its top says, whether there are pages before and how the page before stands (reading, failed, or ""),
/// how many rows and its first item's key.
#derive(Eq)
priv struct StepsHead {
  waiting : Bool
  failed : String
  empty : Bool
  edge : String
  more : Bool
  older : String
  rows : Int
  first : String
}

///|
/// Each history's StepsHead, by its list's key: told only as it comes out otherwise.
// kept across runs: what it keeps is let go of by a run anew and by reset (sfbase derived.mbt)
let steps_head : @sfbase.Kept[StepsHead] = @sfbase.Kept::new()

///|
fn steps_head_of(src : Source, params : Map[String, Json], lkey : String) -> StepsHead {
  steps_head.read(
    src,
    lkey,
    fn(was) {
      let st = src.topic("history", params).get()
      // (none read yet, no error: asked again as a page taken back from the stack's kept left reads it, what it read
      // last till the core's first answer, never its bones in between)
      match was {
        Some(prev) if st.value is None && st.error is None => return prev
        _ => ()
      }
      let h = st.value
      let empty = flag(h, "empty")
      let waiting = !(h is Some(Object(_))) || (empty && !flag(h, "loaded"))
      let (all, rows) = if waiting || empty { ([], []) } else { steps_rows_of_topic(src, params, lkey) }
      {
        waiting,
        failed: text(h, "failed"),
        empty,
        edge: text(h, "edge"),
        more: flag(h, "more"),
        older: text(h, "older"),
        rows: rows.length(),
        first: match all.get(0) {
          Some(i) => text(Some(i), "key")
          None => ""
        },
      }
    },
    same=fn(a, b) { a == b },
  )
}

///|
/// Agent `key`'s history's rows (steps_rows).
fn steps_rows_of_topic(src : Source, params : Map[String, Json], lkey : String) -> (Array[Json], Array[StepsRow]) {
  steps_rows.read(
    src,
    lkey,
    fn(was) {
      let st = src.topic("history", params).get()
      // (as steps_head_of's: what it read last till the core's first answer to it asked again)
      match was {
        Some(prev) if st.value is None && st.error is None => return prev
        _ => ()
      }
      let h = st.value
      steps_rows_of(h, items(h, "items"), steps_own.only_io.get())
    },
    // (by its rows: each item of the items shown is one of them)
    same=fn(a, b) { a.1 == b.1 },
  )
}

///|
/// A row the same as before: the same of it, its item the same JSON (the core's deltas keep what they do not touch),
/// its rail running on as it did.
fn steps_row_same(a : StepsRow?, b : StepsRow?) -> Bool {
  match (a, b) {
    (None, None) | (Some(Edge), Some(Edge)) => true
    (Some(Item(x, r)), Some(Item(y, s))) => physical_equal(x, y) && r == s
    (Some(Live(x, r)), Some(Live(y, s))) => physical_equal(x, y) && r == s
    (Some(Phase(x)), Some(Phase(y))) => physical_equal(x, y)
    _ => false
  }
}

///|
/// An agent's history's rows (`h`, its items `loaded`), 只看收发 (`io`) or not: the items shown, and the rows (the edge's,
/// each item's, what is in flight, the phase it is in).
fn steps_rows_of(h : Json?, loaded : Array[Json], io : Bool) -> (Array[Json], Array[StepsRow]) {
  let all = loaded.filter(fn(i) { !io || !flag(Some(i), "work") })
  let live = if io { [] } else { items(h, "live") }
  let phase = field(h, "phase")
  let going = live.length() > 0 || phase is Some(Object(_))
  let rows : Array[StepsRow] = [Edge]
  for i, item in all {
    // the turn's rail runs on from an item to the next unless the next begins a turn of its own; from the last, to what
    // is in flight
    let rail = match all.get(i + 1) {
      Some(next) => !(field(Some(next), "turn") is Some(Object(_)))
      None => going
    }
    rows.push(Item(item, rail))
  }
  for i, l in live {
    rows.push(Live(l, i < live.length() - 1 || phase is Some(Object(_))))
  }
  match phase {
    Some(Object(_)) as p => rows.push(Phase(p.unwrap()))
    _ => ()
  }
  (all, rows)
}

///|
/// Each history's rows, by its list's key: worked out again as its topic changes or 只看收发 is turned (steps_rows_of,
/// a computed: sfbase derived.mbt).
// kept across runs: what it keeps is let go of by a run anew and by reset (sfbase derived.mbt)
let steps_rows : @sfbase.Kept[(Array[Json], Array[StepsRow])] = @sfbase.Kept::new()

///|
/// About how tall a row stands before it is laid out.
let steps_est : Double = 48.0

///|
/// The lines a sent message and a person's words show folded, and how tall a line of each is.
let post_lines : Int = 3

///|
let words_lines : Int = 3

///|
let md_line : Double = 21.5

///|
let words_line : Double = 20.0

///|
/// The steps (historyBody): 12 over, 16 at the sides; a row 14 under the one before; 40 under the last.
// kept across runs: a value (no field of it changes)
let steps_box : @ui.Style = @ui.css("w=Full h=Full")

///|
// kept across runs: a value (no field of it changes)
let steps_waiting : @ui.Style = @ui.css("w=Full h=Full px=S4 pt=S3")

///|
// kept across runs: a value (no field of it changes)
let steps_row_first : @ui.Style = @ui.css("w=Full px=S4 pt=S3")

///|
// kept across runs: a value (no field of it changes)
let steps_row_turn : @ui.Style = @ui.css("w=Full px=S4 pt=S4")

///|
// kept across runs: a value (no field of it changes)
let steps_row : @ui.Style = @ui.css("w=Full px=S4 pt=S2_5")

///|
/// Its top (historyEdge): 4 over and under, 12 muted, in the middle; on their way, a spinner before the words.
// kept across runs: a value (no field of it changes)
let steps_edge : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full, center=true)

///|
// kept across runs: a value (no field of it changes)
let steps_edge_wait : @ui.Style = @ui.css("row w=Full py=S1 justify=JCenter")

///|
/// An item (hItem): its turn's rule and its events, 8 apart.
// kept across runs: a value (no field of it changes)
let h_item : @ui.Style = @ui.css("w=Full gap=S2")

///|
/// Groups and calls opened as a screen opens (a fixture's), by their disclosure keys within that history.
pub fn history_open(station : String, key : String, keys : Array[String]) -> Unit {
  for k in keys {
    steps_own.opened[steps_item_key(station, key, k)] = true
  }
}

///|
/// The item last gone to (a link's entry), its history's list and its key.
pub fn history_marked() -> (String, String) {
  steps_own.marked.untracked()
}

///|
/// How long an item gone to stays marked.
pub let steps_marked_ms : Double = 1600.0

///|
/// A turn's time (hTurn): 4 over it, centered 11 muted when shown.
// kept across runs: a value (no field of it changes)
let h_turn : @ui.Style = @ui.css("row w=Full pt=S1 justify=JCenter align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let h_turn_words : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, wrap=false)

///|
/// An item's events (hMain), 10 apart.
// kept across runs: a value (no field of it changes)
let h_main : @ui.Style = @ui.css("w=Full gap=S2_5")

///|
/// An event (hEv): its 20 gutter and what it is, 6 apart, pulled 6 left so its icon centres on the rail at `x = 4.0` and its words start at `x = 20`, the column of what it holds below.
// kept across runs: a value (no field of it changes)
let h_ev : @ui.Style = @ui.css("row w=Full gap=S1_5 align=AStart").then(@sf.outset_start(6.0))

///|
/// A received message's body beside the event's side rail (`20px` left offset: the column of the event's words, clear of the rail at `x = 4.0`).
// kept across runs: a value (no field of it changes)
let h_received_body : @ui.Style = @ui.css("w=Full pl=S5 pt=S1 pb=S0_5")

///|
/// A sent card or expanded note/task body beside the event's side rail (`20px` left offset: the column of the event's words, clear of the rail at `x = 4.0`).
// kept across runs: a value (no field of it changes)
let h_post_body : @ui.Style = @ui.css("w=Full pl=S5 pt=S1 pb=S0_5")

///|
/// An event's mark (hIcon): 20 square, on whatever it stands on: the turn's rail runs from under it, so nothing of it
/// covers the rail. As high as its event's first line (ev's `row`), its mark in its middle.
// kept across runs: a value (no field of it changes)
let h_icon : @ui.Style = @ui.css("w=S5 h=S5 align=ACenter justify=JCenter")

///|
/// The model's pulse (activityPulse): a 7 dot in the accent.
// kept across runs: a value (no field of it changes)
let h_pulse : @ui.Style = @ui.style(w=@sf.dot_size, h=@sf.dot_size, radius=Full, bg=Accent)

///|
// kept across runs: a value (no field of it changes)
let h_ev_body : @ui.Style = @ui.style(w=@sf.grow, gap=SPx)

///|
/// Who and where in a line: 20 high, 12 muted, 6 apart; who in the words' ink, 600.
// kept across runs: a value (no field of it changes)
let h_msg_head_grow : @ui.Style = @ui.style(row=true, w=@sf.grow, min_h=S5, gap=S2, align=AStart, justify=JBetween)

///|
// kept across runs: a value (no field of it changes)
let h_one_grow : @ui.Style = @ui.style(row=true, w=@sf.grow, min_h=S5, gap=S1_5, align=ACenter, clip=true)

///|
// kept across runs: a value (no field of it changes)
let h_state_line_grow : @ui.Style = @ui.style(row=true, w=@sf.grow, min_h=S5, gap=S1_5, align=ACenter, clip=true)

///|
// kept across runs: a value (no field of it changes)
let h_msg_label_grow : @ui.Style = @ui.style(row=true, w=@sf.grow, min_h=S5, gap=S1_5, align=ACenter, clip=true)

///|
// kept across runs: a value (no field of it changes)
let h_msg_fold_btn : @ui.Style = @ui.css("row h=S5 px=S1_5 gap=S1 align=ACenter radius=Md hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let h_msg_toggle_words : @ui.TextStyle = @ui.text_style(size=Caption, leading=L6, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let h_msg_toggle_hot : @ui.TextStyle = @ui.text_style(size=Caption, leading=L6, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let h_label_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let h_strong : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, weight=Semibold, color=Fg)

///|
// kept across runs: a value (no field of it changes)
let h_strong_link : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, weight=Semibold, color=Link)

///|
/// A reminder's label stays on one line; its preview gives way when the row is narrow.
// kept across runs: a value (no field of it changes)
let h_reminder : @ui.TextStyle = h_strong.then(@ui.text_style(wrap=false))

///|
// kept across runs: a value (no field of it changes)
let h_label_place : @ui.Style = @ui.css("row min_h=S5 pl=S3 align=AStart clip")

///|
fn label_place_dot_shapes(cx : Double, cy : Double, r : Double, fill : Int64) -> Array[@ui.Shape] {
  let a = r * 0.8660254
  let b = r * 0.5
  let pts : Array[Double] = [
    cx + r, cy,
    cx + a, cy + b,
    cx + b, cy + a,
    cx, cy + r,
    cx - b, cy + a,
    cx - a, cy + b,
    cx - r, cy,
    cx - a, cy - b,
    cx - b, cy - a,
    cx, cy - r,
    cx + b, cy - a,
    cx + a, cy - b,
  ]
  [@ui.shape_of([(pts, true)], fill~)]
}

///|
/// Wraps a message label's place chip with a leading middle dot drawn in its `pl=S3` gutter so the dot always wraps
/// with the place without adding a sibling text measurement or extra flex shrink pass.
fn label_place_node(l : @view.View, body : (@view.View) -> Unit) -> Unit {
  steps_box_node(l, h_label_place, fn(dp) {
    dp
    .shrink(Is(1.0))
    .min_width(Is(Some(0.0)))
    .shapes(By(fn() {
      label_place_dot_shapes(3.2, @sf.node_sp(dp, 10.0), 1.25, @ui.tree_theme().color(Muted))
    }))
    |> ignore
    body(dp)
  })
}

///|
// kept across runs: a value (no field of it changes)
let h_person : @ui.Style = @ui.css("row min_h=S5 gap=S1 align=ACenter")

///|
/// A place (hPlace): its mark and name 4 apart; where it goes, the pointer's ground on it.
// kept across runs: a value (no field of it changes)
let h_place : @ui.Style = @ui.css("row min_h=S5 gap=S1 align=AStart radius=Base clip")

///|
// kept across runs: a value (no field of it changes)
let h_place_mark : @ui.Style = @ui.css("row min_h=S5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let h_place_hot : @ui.Style = h_place.then(@ui.css("bg=Hover"))

///|
// kept across runs: a value (no field of it changes)
let h_place_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, weight=Semibold, color=Fg)

///|
// kept across runs: a value (no field of it changes)
let h_place_link_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, weight=Semibold, color=Link)

///|
/// A person's words (hWords: 13, the ink); a job's (hOutput: 11 mono on 1.55).
// kept across runs: a value (no field of it changes)
let h_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let h_output : @ui.TextStyle = @ui.text_style(size=Caption, color=Fg, w=Full)

///|
/// A message it sent (hCard): 4 under its line, 8 by 12 in, a line round it, round as a field, on the paper; red when it
/// failed.
// kept across runs: a value (no field of it changes)
let h_card : @ui.Style = @ui.css("w=Full py=S2 px=S3 radius=Xl border=B1 border_color=Line bg=Card")

///|
// kept across runs: a value (no field of it changes)
let h_card_failed : @ui.Style = h_card.then(@ui.css("border_color=Danger"))

///|
// kept across runs: a value (no field of it changes)
let h_fold_room : @ui.Style = @ui.css("w=Full clip")

///|
// kept across runs: a value (no field of it changes)
let h_fold_inner : @ui.Style = @ui.css("w=Full")

///|
/// An event in one line (hOne): 20 high, 12 muted (the ink pointed at, red when it failed), 6 apart; a chevron at its end that turns as it opens;
/// what it says in whole under it, 2 over and 4 under (hOneBody).
// kept across runs: a value (no field of it changes)
let h_one : @ui.Style = @ui.css("row w=Full min_h=S5 gap=S1_5 align=ACenter clip")

///|
// kept across runs: a value (no field of it changes)
let h_one_press : @ui.Style = h_one.then(@ui.css("radius=Lg hovered{bg=Hover}"))

///|
// kept across runs: a value (no field of it changes)
let h_one_mark : @ui.Style = @ui.css("row h=S5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let h_one_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let h_one_hot : @ui.TextStyle = h_one_words.then(@ui.text_style(color=Fg))

///|
// kept across runs: a value (no field of it changes)
let h_one_red : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Danger, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let h_one_red_wrap : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Danger, w=Full)

///|
// kept across runs: a value (no field of it changes)
let h_one_card : @ui.Style = @ui.style(w=Full, py=S2, px=S3, radius=@sf.custom_field_r, bg=@sf.faint_ground)

///|
// kept across runs: a value (no field of it changes)
let h_note_plain : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, w=Full)

///|
/// What kind of words a one-line event's are (hTag): 5 in, round 4, on the neutral ground, 11.
// kept across runs: a value (no field of it changes)
let h_tag : @ui.Style = @ui.css("row px=S1_25 radius=Base bg=Neutral")

///|
// kept across runs: a value (no field of it changes)
let h_tag_words : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let h_grow : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let h_grow_clip : @ui.Style = @ui.style(row=true, w=@sf.grow, clip=true)

///|
/// A state's words in a line (hStateLine): 20 high, 12, 6 apart.
// kept across runs: a value (no field of it changes)
let h_state_line : @ui.Style = @ui.css("row w=Full min_h=S5 gap=S1_5 align=ACenter clip")

///|
// kept across runs: a value (no field of it changes)
let h_state_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let h_state_words_line : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false, w=Cut)

///|
/// How much of the most it waits has gone (hWaitBar): a 3 bar under the words, its fill in the blue.
// kept across runs: a value (no field of it changes)
let h_wait_bar : @ui.Style = @ui.style(row=true, w=Full, h=@sf.wait_bar_h, mt=SPx, radius=Full, clip=true, bg=A(Link, O20))

///|
// kept across runs: a value (no field of it changes)
let h_wait_fill : @ui.Style = @ui.css("h=Full bg=Link")

///|
/// A group (hGroup), its line (hGroupHead: the chevron's 20 column, its words, its pills 8 apart; 6 past the column on
/// either side, round as an option, the pointer's ground and the ink on it).
// kept across runs: a value (no field of it changes)
let h_group : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let h_group_head : @ui.Style = @ui.css("row w=Full pr=S1_5 gap=S1_5 align=ACenter radius=Lg hovered{bg=Hover}").then(@sf.outset(6.0))

///|
// kept across runs: a value (no field of it changes)
let h_group_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let h_group_hot : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Fg, wrap=false, w=Cut)

///|
/// Its calls, opened (hSteps): 20px left offset (the group head's words' column) beside the group's straight side rail at `x = 4.0`, 4 apart.
// kept across runs: a value (no field of it changes)
let h_steps : @ui.Style = @ui.css("w=Full pl=S5 pt=S1 pb=S1 gap=S1")

///|
/// A call's line (hStep summary): aligned with the card below it, 8 apart, 12.
// kept across runs: a value (no field of it changes)
let h_step : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let h_step_summary : @ui.Style = @ui.css("row w=Full py=S0_5 gap=S2 align=ACenter radius=Md")

///|
// kept across runs: a value (no field of it changes)
let h_step_name : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Semibold, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let h_step_name_red : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Semibold, color=Danger, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let h_step_said : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let h_step_meta : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let h_step_meta_red : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Danger, wrap=false)

///|
/// A step's or thought's words (hStepBody: 4 over, 12; hStepCard: rounded faint surface card); a thought alone (hThinking: muted).
// kept across runs: a value (no field of it changes)
let h_step_body : @ui.Style = @ui.css("w=Full pt=S1")

///|
// kept across runs: a value (no field of it changes)
let h_step_card : @ui.Style = @ui.style(w=Full, mt=S1, py=S2, px=S3, radius=@sf.custom_field_r, bg=@sf.faint_ground)

///|
// kept across runs: a value (no field of it changes)
let h_thinking_muted : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full)

///|
/// The thinking streaming in (hLiveThinking): 12 on 20, muted, a line.
// kept across runs: a value (no field of it changes)
let live_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false, w=Cut)

///|
/// Where the turn stands (hPhase: 12, muted; responding in the ink), its clock subtle.
// kept across runs: a value (no field of it changes)
let h_phase_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let h_phase_now : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let h_phase_time : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Subtle, wrap=false)

///|
/// A call opened: 4 over, the call and what came back 6 apart; multi-part or structured steps sit in a faint
/// rounded container (`tool_body_card`) so each expanded step's start and end are clear without a second vertical line.
// kept across runs: a value (no field of it changes)
let tool_body_box : @ui.Style = @ui.css("w=Full mt=S1 gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let tool_body_card : @ui.Style = @ui.style(w=Full, mt=S1, py=S2, px=S3, gap=S1_5, radius=@sf.custom_field_r, bg=@sf.faint_ground)

///|
// kept across runs: a value (no field of it changes)
let tool_section : @ui.Style = @ui.css("w=Full gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let tool_section_card : @ui.Style = @ui.css("w=Full gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let tool_result_card : @ui.Style = @ui.css("w=Full pt=S1 gap=S1")

///|
// kept across runs: a value (no field of it changes)
let tool_result_head : @ui.Style = @ui.css("row w=Full px=S0_5 gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let tool_result_head_words : @ui.TextStyle = @ui.text_style(size=Caption, weight=Semibold, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let tool_result_head_red : @ui.TextStyle = @ui.text_style(size=Caption, weight=Semibold, color=Danger, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let tool_reader_body : @ui.Style = @ui.css("w=Full py=S2 gap=S2")

///|
// kept across runs: a value (no field of it changes)
let tool_expand_btn : @ui.Style = @ui.css("row py=S0_5 px=S1 gap=S1 align=ACenter radius=Md hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let tool_expand_words : @ui.TextStyle = @ui.text_style(size=Caption, color=Link, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let tool_expand_words_hot : @ui.TextStyle = @ui.text_style(size=Caption, color=Accent, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let tool_copy_btn : @ui.Style = @ui.css("row py=S0_5 px=S1 gap=S1 align=ACenter radius=Md hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let tool_copy_icon : @ui.Style = @ui.css("row w=S5 h=S5 align=ACenter justify=JCenter radius=Md hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let tool_copy_words : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let tool_copy_words_hot : @ui.TextStyle = @ui.text_style(size=Caption, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let tool_copy_words_done : @ui.TextStyle = @ui.text_style(size=Caption, color=Positive, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let tool_clip_more : @ui.Style = @ui.css("row w=Full pt=S1 pb=S0_5 px=S1 gap=S1 align=ACenter justify=JCenter radius=Md hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let tool_err_row : @ui.Style = @ui.css("row w=Full gap=S2 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let tool_block_bar : @ui.Style = @ui.css("row w=Full px=S0_5 gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let tool_dispatch_badge : @ui.Style = @ui.css("row py=S0_5 gap=S1 align=ACenter clip")

///|
// kept across runs: a value (no field of it changes)
let tool_dispatch_target_words : @ui.TextStyle = @ui.text_style(size=Caption, weight=Semibold, color=Link, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let tool_dispatch_target_words_hot : @ui.TextStyle = @ui.text_style(size=Caption, weight=Semibold, color=Fg, wrap=false, w=Cut)

///|
/// A box of words (box): 8 by 12 in, round 10, the ink at 4% over the canvas, 12 mono on 1.55; red's ground when it
/// failed.
// kept across runs: a value (no field of it changes)
let tool_box : @ui.Style = @ui.style(w=Full, py=S2, px=S3, radius=@sf.custom_field_r, bg=@sf.faint_ground)

///|
// kept across runs: a value (no field of it changes)
let tool_box_red : @ui.Style = tool_box.then(@ui.css("bg=DangerBg"))

///|
// kept across runs: a value (no field of it changes)
let tool_mono : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let tool_mono_muted : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let tool_mono_head : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=Link, w=Full)

///|
// kept across runs: a value (no field of it changes)
let tool_mono_nowrap : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let tool_mono_muted_nowrap : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let tool_mono_head_nowrap : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=Link, wrap=false)

///|
/// The facts (facts): 4 by 10 apart, 11 subtle, a fact's value in mono, muted.
// kept across runs: a value (no field of it changes)
let tool_facts : @ui.Style = @ui.css("row w=Full px=S0_5 gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let tool_fact : @ui.TextStyle = @ui.text_style(size=Caption, color=Subtle)

///|
/// A path (path): 2 in, 12 mono on 1.5, the ink; what of it after, 11 subtle.
// kept across runs: a value (no field of it changes)
let tool_path : @ui.Style = @ui.css("row w=Full px=S0_5 gap=S2 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let tool_path_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let tool_path_extra : @ui.TextStyle = @ui.text_style(size=Caption, color=Subtle, wrap=false)

///|
/// A diff (diff: the box, 6 over and under, no sides; a line's mark 9 in at its start, its words 22, its end 9 in as
/// its start is (what a line on its ground holds as far in from both sides: the web's 12 at its end, beside its mark
/// laid over the line, held it 22 and 12); taken out on the red's ground, put in on the green's, a header in the blue,
/// 4 over it).
// kept across runs: a value (no field of it changes)
let tool_diff : @ui.Style = @ui.style(w=Full, radius=@sf.custom_field_r, bg=@sf.faint_ground, clip=true)

///|
// kept across runs: a value (no field of it changes)
let tool_diff_line : @ui.Style = @ui.style(row=true, w=Full, pl=@sf.diff_mark_in, pr=@sf.diff_mark_in)

///|
// kept across runs: a value (no field of it changes)
let tool_diff_out : @ui.Style = tool_diff_line.then(@ui.css("bg=DangerBg"))


///|
// kept across runs: a value (no field of it changes)
let tool_diff_head : @ui.Style = tool_diff_line.then(@ui.css("pt=S1"))

///|
// kept across runs: a value (no field of it changes)
let tool_diff_row_top : @ui.Style = @ui.css("pt=S1_5")

///|
// kept across runs: a value (no field of it changes)
let tool_diff_row_bot : @ui.Style = @ui.css("pb=S1_5")

///|
/// The gutter a line's mark stands in (taken out or put in), 9 in: as far as its words are 22 in.
// kept across runs: a value (no field of it changes)
let tool_diff_mark : @ui.Style = @ui.style(w=Fixed(@sf.diff_line_in.px() - @sf.diff_mark_in.px()))

///|
/// A line's words: what the gutter leaves.
// kept across runs: a value (no field of it changes)
let tool_diff_words : @ui.Style = @ui.style(w=@sf.grow, min_w=S0)

///|
/// A plan (plan): 2 apart, 2 in, 12; its marks in a 16 column; done struck and muted, under way in 600.
// kept across runs: a value (no field of it changes)
let tool_plan : @ui.Style = @ui.css("w=Full px=S0_5 gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let tool_plan_row : @ui.Style = @ui.css("row w=Full")

///|
// kept across runs: a value (no field of it changes)
let tool_plan_mark : @ui.Style = @ui.css("w=S4")

///|
// kept across runs: a value (no field of it changes)
let tool_plan_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let tool_plan_done : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let tool_plan_now : @ui.TextStyle = @ui.text_style(size=Meta, weight=Semibold, color=Fg, w=@sf.grow)

///|
/// Fields (fields): 4 apart, 2 in; a key in a column 64 wide at least (11 subtle), its value 12 apart (12 mono), long
/// words and data in a box.
// kept across runs: a value (no field of it changes)
let tool_fields : @ui.Style = @ui.css("w=Full px=S0_5 gap=S1")

///|
// kept across runs: a value (no field of it changes)
let tool_field : @ui.Style = @ui.css("row w=Full gap=S3 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let tool_field_stack : @ui.Style = @ui.css("w=Full pt=S0_5 gap=S1")

///|
// kept across runs: a value (no field of it changes)
let tool_field_head : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let tool_field_key : @ui.Style = @ui.css("min_w=S16")

///|
// kept across runs: a value (no field of it changes)
let tool_key_words : @ui.TextStyle = @ui.text_style(size=Caption, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let tool_value : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let tool_long_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, w=Full)

///|
/// The one thing it asked about (lead): 2 in, 12 mono on 1.5; nothing (none): 11 subtle.
// kept across runs: a value (no field of it changes)
let tool_lead : @ui.Style = @ui.css("w=Full px=S0_5")

///|
// kept across runs: a value (no field of it changes)
let tool_lead_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let tool_none : @ui.TextStyle = @ui.text_style(size=Caption, color=Subtle, w=Full)

///|
/// What agent `key`'s history on `station` is asked of the core by (a topic and its params): what its figures are read
/// by (history_usage, history_usage_line).
pub fn history_ask(station : String, key : String) -> (String, Map[String, Json]) {
  ("history", { "station": Json::string(station), "key": Json::string(key) })
}

///|
/// What an agent's history's details hold of the machine its station is (`host`), asked of the core by.
pub fn history_host_ask(station : String) -> (String, Map[String, Json]) {
  ("host", { "station": Json::string(station) })
}

///|
/// What agent `key`'s history on `station` hands 详情's asks to (sfbase's hand_over_shown): its details say so as they
/// read (shown_read).
pub fn history_details_at(station : String, key : String) -> String {
  "history-details\u{1}" + station + "\u{1}" + key
}

///|
/// 详情 pressed in an agent's history's head, its details folded (sfdesk's chip, the narrow page's tab): `asks` (all the
/// details read as they are first drawn, each said by the code it reads by) asked of `src` now, the head as it is
/// meanwhile, the control showing itself pressed by a state of its own; once each is answered (at once where they are
/// already), `open` unfolds them as it did at the press before, by their way where they have one: a person's act told
/// late, never as an answer (sfbase's switch_answered would set nothing out). What was asked is handed to the details
/// by `at` (history_details_at; hand_over_shown), let go at the end of the frame they first read it in. Given up
/// (press_wait: the page left, the workspace switched, something else put up; by its caller as the control is pressed
/// again), what was asked is let go and `let_go` run (the control put back). Made in the press's handler.
pub fn history_details_open(
  src : Source,
  asks : Array[(String, Map[String, Json])],
  at : String,
  open : () -> Unit,
  let_go? : () -> Unit = fn() {  },
) -> @sfbase.PressWait {
  // (asking nothing ahead where the source's run did not: a replay of a run from before, unfolded at the press)
  if asks.is_empty() || src.read_only || !(src.switches_ahead)() {
    return @sfbase.press_wait(fn() { true }, open)
  }
  let (answered, leases) = @sfbase.asked_now(src, asks)
  @sfbase.press_wait(answered, fn() { @sfbase.hand_over_shown(at, leases, open) }, let_go=fn() {
    leases.each(fn(l) { l.cancel() })
    let_go()
  })
}

///|
/// What agent `key`'s history on `station` says it used, in a line (its `usageLine`): what reads it is told only as the
/// line changes, not as the rest of the history does (what streams in as the agent works: history_steps_node).
pub fn history_usage_line(src : Source, station : String, key : String) -> String {
  let (name, params) = history_ask(station, key)
  steps_usage_line.read(
    src,
    station + "\u{1}" + key,
    fn(_) { text(src.topic(name, params).get().value, "usageLine") },
    same=fn(a, b) { a == b },
  )
}

///|
/// What agent `key`'s history on `station` says it used, each figure (its `usage`): told only as they change.
pub fn history_usage(src : Source, station : String, key : String) -> Array[Json] {
  let (name, params) = history_ask(station, key)
  let usage = steps_usage.read(
    src,
    station + "\u{1}" + key,
    fn(_) { field(src.topic(name, params).get().value, "usage") },
    same=fn(a, b) {
      match (a, b) {
        (Some(x), Some(y)) => physical_equal(x, y)
        (None, None) => true
        _ => false
      }
    },
  )
  match usage {
    Some(Array(a)) => a
    _ => []
  }
}

///|
// kept across runs: what it keeps is let go of by a run anew and by reset (sfbase derived.mbt)
let steps_usage_line : @sfbase.Kept[String] = @sfbase.Kept::new()

///|
// kept across runs: what it keeps is let go of by a run anew and by reset (sfbase derived.mbt)
let steps_usage : @sfbase.Kept[Json?] = @sfbase.Kept::new()

///|
/// What needs seeing to in an agent's history now (HistorySummary), as `a` (the chat's agent) says it, in `parent`'s
/// row: a quota running out (its chip, what it says and more over it while it is pointed at, in `tips`), the disk
/// filling up (in `amber`), an account that cannot run (in `red`).
pub fn history_attention_node(
  parent : @view.View,
  a : () -> Json?,
  tips : @sf.TipLayer,
  amber : @ui.TextStyle,
  red : @ui.TextStyle,
) -> Unit {
  let notes = fn() { items(a(), "attention") }
  parent.each(fn() { Array::makei(notes().length(), fn(i) { i }) }, fn(i) { i }, fn(c, i) {
    c.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
    let k = i.untracked()
    let n = fn() { notes().get(k) }
    let q = fn() { field(n(), "quota") }
    c.pick(fn() { q() is Some(Object(_)) }, fn(x, quota) {
      if quota {
        @sf.fill_chip_node(
          x,
          fn() { number(q(), "left").to_int() },
          fn() { text(q(), "level") },
          fn() { @sf.quota_mark(q()) },
          fn() { @sf.quota_figure(q()) },
          small=true,
          label_muted=true,
          refill=fn() { @sf.quota_is_refill(q()) },
          said=fn() {
            let more = text(n(), "more")
            text(n(), "text") + (if more != "" { "\n" + more } else { "" })
          },
          tips~,
        )
        |> ignore
      } else {
        x.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
        @sf.words_node(x, fn() { text(n(), "text") }, fn() { if text(n(), "kind") == "disk" { amber } else { red } })
        .shrink(Is(1.0))
        .min_width(Is(Some(0.0)))
        |> ignore
      }
    })
  })
}

