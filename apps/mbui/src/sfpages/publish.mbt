// A chat shared as a picture (2026-10-26 用户：「静态分享功能改成分享图片吧，把内容直接渲染成一张长图」; still.fail
// web/src/Publish.tsx PublishDialog, PublishPicture, FileToggle; Publish.css.ts, FilePreview.css.ts fp; the phone's
// PublishSheet in mobile/Chat.tsx, the same), one on every screen: from its info's 分享图片, over the whole window as a
// file is previewed, the picture as it would be (`chat.publishPreview`, asked as it opens: what the chat holds now,
// what looks like a secret in it hidden): the chat's name, its messages as the chat's list draws them (the preview's
// `list`, drawn by its rows), each attachment where its message has it, pressed anywhere to tick it or not (all at
// first: FileToggle's label), and still.fail's mark at its foot. What it is for is the library's viewer_frame_act (2026-10-26 用户, of a button filled
// in a pill of its own over it: 「太不对劲了」「应该放下面，俩按钮，一个取消一个保存到相册，pc 的话直接跟附件预览一样，有顶栏」「pc
// 也用文字按钮，不要用图标」): on a wide screen the bar a file opened has across the top (back to the chat by its name, 分享图片
// and how much was hidden), the button 复制图片 at its end; on a small screen 取消 and 保存到相册 side by side at the foot
// (picture_out). Pressed, the picture is drawn whole off the screen as one long picture (@ui.take_picture), the attachments
// left out not in it, nor the ticks and the notes of what was hidden that are for the one sharing it, its times as
// dates; then handed out. A page of HTML an agent's words place is drawn live on the page, as the chat draws it, and in
// the picture as it looks then (2026-11-02 用户：「分享会话内容时，好像不会把inline html也渲染进去」): a page is the system's
// view, which no picture holds, so before the picture is taken each is brought into sight and grabbed (publish_walk_on),
// its grab drawn in its place; one that cannot be (a browser's frame grabs nothing, a page that did not draw) is its
// card, as are those left out on the page. Which files an agent's words place, and those words as Markdown, are the
// core's (the list's `placed`, `md`). All of it nodes of the window's tree, its messages the chat's page's
// (MessageNodeHere's `picture` drawing their files its way); the picture made as nodes apart (@ui.take_picture). The
// shells lay it over their pages (publish_layer_node).

///|
/// The sharing as it stands: the chat it is of and its thread (None: closed), how many times it was opened (what the
/// shells' layer is made again by), the preview as read (0 being read, 1 read, 2 not: `error` says why), the attachments
/// and messages left out (by their `k`, message_k), its picture being taken, how many times it was copied (its button
/// 已复制 a moment after).
priv struct Publishing {
  of : @signals.Signal[(ChatRef, Double)?]
  opened : @signals.Signal[Int]
  read : @signals.Signal[Int]
  preview : @signals.Signal[Json?]
  error : @signals.Signal[String]
  off : @sf.LiveMap[String, Bool]
  busy : @signals.Signal[Bool]
  copied : @signals.Signal[Int]
  /// the pages of HTML drawn live on the page, by their `k`, while each is: the box it is drawn in and its frame
  /// (publish_viz_live); `viz_made` told as one comes or goes
  viz_at : Map[String, (@view.View, @sfbase.VizFrame)]
  viz_made : @signals.Signal[Int]
  /// told each time the page's list says what it has in sight (a layout done: where a page of HTML is laid out read then)
  sighted : @signals.Signal[Int]
  /// those of them whose file could not be read: their cards
  viz_failed : Map[String, Bool]
  /// what each was grabbed as for the picture, by its `k`: its image and the size it was drawn at
  stills : Map[String, (String, Double, Double)]
  /// the going through them as its picture is asked for (publish_walk_on), how many times it was asked
  walk : @signals.Signal[PublishWalk?]
  mut todo : Array[(String, String)]
  mut walks : Int
  /// the page that shares it as it is made: its layer, its list, where its list is asked to show a block
  mut page : PublishPage?
  /// the picture asked for copied, not kept in the photo album (a phone's 复制图片 beside its 保存到相册)
  mut copying : Bool
  /// opened by a message's 多选: its seq, the one message ticked once the preview is read, and brought into sight
  /// once it is laid out (None: all ticked, the page from its top)
  mut picked : Double?
}

///|
/// The page that shares it, as it is made: its layer (what its moments and the picture's walk are of), its list's
/// scroll and what asks it to show a block.
priv struct PublishPage {
  layer : @view.View
  scroll : @view.Scroll
  place : @view.ListPlace[String]
}

///|
/// Where the going through the pages of HTML is (publish_walk_on): which time the picture was asked, which of them it is
/// at (`todo`'s), how far with it (0 to bring it into sight, 1 waiting till it has drawn itself, 2 waiting for its
/// grab), and how far the page was scrolled as it began (where it is put back once the picture is taken).
#derive(Eq)
priv struct PublishWalk {
  walks : Int
  at : Int
  step : Int
  back : Double
}

///|
let publishing : Publishing = {
  of: @signals.signal(None),
  opened: @signals.signal(0),
  read: @signals.signal(0, same=fn(a, b) { a == b }),
  preview: @signals.signal(None),
  error: @signals.signal("", same=fn(a, b) { a == b }),
  off: @sf.LiveMap::new(),
  busy: @signals.signal(false, same=fn(a, b) { a == b }),
  copied: @signals.signal(0, same=fn(a, b) { a == b }),
  viz_at: {},
  viz_made: @signals.signal(0),
  sighted: @signals.signal(0),
  viz_failed: {},
  stills: {},
  walk: @signals.signal(None),
  todo: [],
  walks: 0,
  page: None,
  copying: false,
  picked: None,
}

///|
pub fn publish_reset() -> Unit {
  publishing.of.set(None)
  publishing.read.set(0)
  publishing.preview.set(None)
  publishing.error.set("")
  publishing.off.clear()
  publishing.busy.set(false)
  publishing.copied.set(0)
  publishing.viz_failed.clear()
  publishing.stills.clear()
  publishing.walk.set(None)
  publishing.todo = []
  publishing.picked = None
}

///|
/// Opened for chat `r`'s `thread`: what the picture would hold asked now (usePublishPreview). With `picked` (a
/// message's seq: its menu's 多选, 2026-11-06 用户「分享这一轮改成多选，默认选中右键的那一行，可以勾选其它行，然后复制成图片」)
/// the whole chat still, that message alone ticked and brought into sight, the others to tick.
pub fn open_publish(src : Source, r : ChatRef, thread : Double, picked? : Double? = None) -> Unit {
  publish_reset()
  publishing.of.set(Some((r, thread)))
  publishing.opened.set(publishing.opened.untracked() + 1)
  publishing.picked = picked
  let asked : Map[String, Json] = { "station": Json::string(r.station), "thread": Json::number(thread) }
  (src.call)("chat.publishPreview", Json::object(asked), fn(res) {
    match publishing.of.untracked() {
      Some((o, th)) if o.station == r.station && th == thread =>
        match res {
          Ok(v) => {
            publish_pick_only(Some(v))
            publishing.preview.set(Some(v))
            publishing.read.set(1)
          }
          Err(e) => {
            publishing.error.set(error_words(e))
            publishing.read.set(2)
          }
        }
      _ => ()
    }
  })
}

///|
/// The message 多选 was opened from (publishing.picked) the only one of preview `p`'s ticked; all of them when it is
/// not among them.
fn publish_pick_only(p : Json?) -> Unit {
  guard publishing.picked is Some(seq) else { return }
  let seqs = items(p, "list").map(fn(j) { number(Some(j), "seq") })
  if !seqs.contains(seq) {
    return
  }
  for n in seqs {
    if n != seq {
      publishing.off[message_k(n)] = true
    }
  }
}

///|
/// Its page closed: it goes (publish_layer_node), what it showed kept till it has gone, the rest put back as the next
/// opens.
pub fn publish_close() -> Unit {
  publishing.of.set(None)
  publishing.busy.set(false)
  publishing.walk.set(None)
}

///|
/// Whether its page is open (not closed, whether or not it has gone yet).
pub fn publish_open() -> Bool {
  publishing.of.untracked() is Some(_)
}

///|
/// Chat `r`'s `thread` being shared, `preview` read (a screen's fixture).
pub fn publish_set(r : ChatRef, thread : Double, preview : Json) -> Unit {
  publish_reset()
  publishing.of.set(Some((r, thread)))
  publishing.opened.set(publishing.opened.untracked() + 1)
  publishing.preview.set(Some(preview))
  publishing.read.set(1)
}

///|
/// Whether page of HTML `k` was grabbed for the picture (tests).
pub fn publish_has_still(k : String) -> Bool {
  publishing.stills.contains(k)
}

///|
/// Whether attachment `k` is left out of the picture (tests).
pub fn publish_left_out(k : String) -> Bool {
  publishing.off.contains(k)
}

///|
/// What leaves message `seq` out of the picture in `off` (its attachments are there by their `k`).
fn message_k(seq : Double) -> String {
  "m:" + seq_s(seq)
}

///|
/// Whether message `seq` is left out of the picture (tests).
pub fn publish_message_left_out(seq : Double) -> Bool {
  publishing.off.contains(message_k(seq))
}

///|
/// How many of the preview's messages go in the picture (none ticked: nothing to take).
fn publish_kept(p : Json?) -> Int {
  items(p, "list").filter(fn(j) { !publishing.off.contains(message_k(number(Some(j), "seq"))) }).length()
}

///|
/// The picture's key (@ui.take_picture).
let publish_shot : String = "publish/picture"

///|
/// Its picture asked for (`copy`: copied, a phone's 复制图片; else as @sf.picture_out_way says), at that cause: the pages
/// of HTML in it grabbed first (publish_walk_on), then taken.
fn publish_go(copy? : Bool = false) -> Unit {
  if publishing.busy.untracked() {
    return
  }
  let p = publishing.preview.untracked()
  if p is None || publish_kept(p) == 0 {
    return
  }
  publishing.copying = copy || !@sf.picture_to_album()
  publishing.busy.set(true)
  publishing.stills.clear()
  let todo = publish_viz_todo()
  match publishing.page {
    Some(page) if !todo.is_empty() => {
      publishing.walks = publishing.walks + 1
      publishing.todo = todo
      let back = page.scroll.at(page.layer.tree)
      publishing.walk.set(Some({ walks: publishing.walks, at: 0, step: 0, back }))
    }
    _ => publish_take()
  }
}

///|
/// The `(k, row_key)` pairs of the pages of HTML the picture holds, drawn live on the page (not left out, not in a
/// browser), in the order they come in it.
fn publish_viz_todo() -> Array[(String, String)] {
  let todo = []
  if @ui.platform() == 4 {
    return todo
  }
  for i, j in items(publishing.preview.untracked(), "list") {
    let m = picture_message(@sfbase.message_of(j), true)
    if publishing.off.contains(message_k(m.seq)) {
      continue
    }
    let rk = publish_row_key(i, m.seq)
    for a in m.attachments {
      let k = file_k(m.seq, a)
      if k != "" && !publishing.viz_failed.contains(k) && m.placed.contains(a.name) && is_viz(a.name) && !@sfbase.is_mbui_viz(a.name) {
        todo.push((k, rk))
      }
    }
  }
  todo
}

///|
/// How long a page of HTML that has drawn itself is left before it is grabbed (what it draws on coming in: a chart's
/// first animation), and how long it is waited for at most at each step: one not there by then is its card.
pub let publish_viz_settle_ms : Double = 600.0

///|
let publish_viz_wait_ms : Double = 8000.0

///|
/// The tallest page of HTML grabbed: a picture of one taller (a catalogue of twenty screens) is past what a host holds
/// at once. Its card.
let publish_viz_most_h : Double = 8000.0

///|
/// What the walk through the pages of HTML in the picture said (`w`), at each cause that moves it on (a change of it, a
/// page come to be drawn on the page, one drawn by its host, a grab answered: publish_walk_said), in the page's layer
/// `n`: the page brought into sight (step 0 brings its virtualized message row into sight if unmounted, step 1 waits
/// for it to mount, then adjusts scroll so its box sits under the header and above the foot), left till it has drawn
/// itself (step 2), publish_viz_settle_ms more, grabbed (step 3), and that kept for the picture; after the last, the
/// page scrolled back and the picture taken. publish_viz_wait_ms at most at each step: one not there by then is its
/// card.
fn publish_walk_on(n : @view.View, w : PublishWalk) -> Unit {
  guard publishing.page is Some(page) else { return }
  if w.at >= publishing.todo.length() {
    publishing.walk.set(None)
    page.scroll.put(w.back)
    publish_take()
    return
  }
  let (k, rk) = publishing.todo[w.at]
  let next = fn() { publishing.walk.set(Some({ ..w, at: w.at + 1, step: 0 })) }
  let step = fn(s : Int) { publishing.walk.set(Some({ ..w, step: s })) }
  match (w.step, publishing.viz_at.get(k)) {
    // (not mounted on the page yet: bring its message row into sight, or skip if loading failed)
    (0, None) =>
      if publishing.viz_failed.contains(k) {
        next()
      } else {
        page.place.bring(rk, offset=0.0, glide=false)
        step(1)
      }
    (1, None) =>
      if publishing.viz_failed.contains(k) {
        next()
      }
    (0 | 1, Some((box, f))) => {
      let (_, y, _, h) = box.rect()
      // (not laid out yet: as the list says what it has in sight once it is)
      if h <= 0.0 {
        return
      }
      if h > publish_viz_most_h {
        return next()
      }
      let (ww, wh) = n.window()
      let top = publish_head_w(ww)
      if y < top || y + h > wh - publish_foot_w(ww) {
        page.scroll.put(page.scroll.at(n.tree) + (y - top))
      }
      ignore(f)
      step(2)
    }
    (2, Some((_, f))) =>
      if f.drawn() {
        // (left to draw what it draws as it comes in, then grabbed: at that moment, where it is still this step)
        let at = n.cause_at() + publish_viz_settle_ms
        n.at_moment(at, fn() {
          if publishing.walk.untracked() == Some(w) && !f.view.grabbing() {
            f.view.grab_frame(0.0)
            step(3)
          }
        })
        |> ignore
      }
    (3, Some((box, f))) =>
      match f.view.grabbed() {
        Some(png) => {
          let (_, _, bw, bh) = box.rect()
          match publish_viz_grab_size(png) {
            // (a grab of all of it: one of a part of it is not stretched to all of it)
            Some((pw, ph)) if (ph * bw / pw - bh).abs() <= 2.0 => {
              let image = "mem:publish/\{publishing.walks}/\{k}"
              @ui.add_image(image, png)
              publishing.stills[k] = (image, bw, bh)
            }
            _ => ()
          }
          next()
        }
        None => ()
      }
    // (gone from the page meanwhile: its card)
    _ => next()
  }
}

///|
/// What moves the walk through the pages of HTML on (publish_walk_on), as it changes: the walk itself, the page it is
/// at come to be drawn on the page or gone from it, drawn by its host, its grab answered.
fn publish_walk_said() -> (PublishWalk, Int, Bool, Int)? {
  match publishing.walk.get() {
    Some(w) => {
      publishing.viz_made.get() |> ignore
      publishing.sighted.get() |> ignore
      let k = match publishing.todo.get(w.at) {
        Some((k, _)) => k
        None => ""
      }
      match publishing.viz_at.get(k) {
        Some((_, f)) => {
          Some((w, 1, f.drawn(), f.view.grabs_told()))
        }
        None => Some((w, 0, false, 0))
      }
    }
    None => None
  }
}

///|
/// How many pixels across and down a page's grab `png` is; None when it is empty or not a PNG.
fn publish_viz_grab_size(png : Bytes) -> (Double, Double)? {
  match @sfbase.png_size(png) {
    Some((w, h)) if w > 0 && h > 0 => Some((w.to_double(), h.to_double()))
    _ => None
  }
}

///|
/// The picture taken (the attachments ticked in it, nothing else of the page's: publish_picture_node, made apart), then
/// handed out as its button says: copied, its button 已复制 a moment, else what came of it said.
fn publish_take() -> Unit {
  guard publishing.of.untracked() is Some((r, _)) else {
    publishing.busy.set(false)
    return
  }
  let p = publishing.preview.untracked()
  let here = publish_here(r, fn() { publish_page_w }, true, None)
  @ui.take_picture(publish_shot, publish_page_w, fn(paper) { publish_picture_node(paper, here, p) }, fn(png) {
    publishing.busy.set(false)
    let copy = publishing.copying
    // (copied said where its button does not say it: the system's bars, their buttons icons)
    if picture_out_now(png, copy_said=copy && !@sf.native_on(), copy~) && copy {
      publishing.copied.set(publishing.copied.untracked() + 1)
    }
  })
}

///|
/// Where the chat `r`'s messages are drawn for its picture (MessageNodeHere): its view as it is as it opens, `width`,
/// in the picture taken (`taking`) or on the page, its tips in `tips`; their files drawn its way (publish_files,
/// publish_viz_node).
fn publish_here(r : ChatRef, width : () -> Double, taking : Bool, tips : @sf.TipLayer?) -> MessageNodeHere {
  let view = publish_view(r)
  {
    station: r.station,
    session: r.session,
    view: fn() { view },
    width,
    tips: tips.unwrap_or(@sf.TipLayer::new(fn() { None })),
    stint: fn() { 0 },
    jump: None,
    picture: Some({
      taking,
      file: fn(parent, ts, a, draw) { publish_file_node(parent, ts, a, draw, taking) },
      viz: fn(parent, ts, a, card) { publish_viz_node(parent, r, ts, a, card, taking) },
    }),
  }
}

///|
/// The source the page that shares a chat reads its chat's view and its pages of HTML with, as it is made.
// kept across runs: put as each page is made (publish_node), what the next one's reads
let publishing_src : Ref[Source?] = Ref(None)

///|
/// Chat `r`'s view as the page that shares it reads it, as it is asked (what its messages' agents and its title are).
fn publish_view(r : ChatRef) -> ChatView {
  @signals.untracked(fn() {
    match publishing_src.val.bind(fn(src) { @sfbase.view_of_chat(src, r).0 }) {
      Some(v) => v
      None => @sfbase.chat_view_made(Json::null())
    }
  })
}

///|
/// The page that shares it, while it is open, over the shells' pages (narrow_shell, tape_shell), in node `v`: made as it
/// is opened, let go as it has gone. It comes in faded in as a file opened over the window does, and goes as a dialog
/// does (@motion.overlay_presence, @motion.dialog_out), drawn as it was while it goes, the pages under it theirs again from then.
pub fn publish_layer_node(v : @view.View, src : Source) -> Unit {
  // (over the pages, the whole of the room it is given: publish_node's; kept for dialog_out_ms while leaving)
  v.show(
    at_once=true,
    leave=@motion.dialog_out_ms,
    fn() { publishing.of.get() is Some(_) },
    fn(n) {
      let (look, live) = @motion.overlay_presence(
        n,
        enter=@motion.trans(fade=0.0, spec=@motion.tween(publish_in_ms, ease=Out), ground_first=true),
        exit=@motion.dialog_out,
      )
      n
      .over(Is(true))
      // (the pages under it theirs again as it begins to go)
      .modal(By(live))
      .presses(By(live))
      .ground(By(fn() { @sf.theme().p.bg }))
      .alpha(By(fn() { look().alpha }))
      .scale(By(fn() { look().sx }))
      .offset(By(fn() { (look().dx, look().dy) }))
      |> ignore
      // (keyed on publishing.opened alone so closing leaves the preview intact during dialog_out)
      n.pick(
        at_once=true,
        fn() { publishing.opened.get() },
        fn(body, opened) {
          if opened > 0 {
            publish_node(body, src, look)
          }
        },
      )
    },
  )
}

///|
/// The page that shares it (PublishDialog) in `n` (publish_layer_node's): over the whole window on the canvas, a preview
/// at the page's width, what it is for over it (viewer_frame_act_node: the bar a file opened has, or 取消 and 保存到相册
/// at the foot; beside the system's bars, theirs: publish_native); back and Escape close it, but while its picture is
/// being taken. The picture is taken whole off the screen at the chat's maximum column width (publish_take).
fn publish_node(n : @view.View, src : Source, look : () -> @ui.Look) -> Unit {
  guard @signals.untracked(fn() { publishing.of.get() }) is Some((r, _)) else { return }
  publishing_src.val = Some(src)
  let busy = fn() { publishing.busy.untracked() }
  n
  .over(Is(true))
  .on_key(fn(k) {
    if k.code == @ui.key_escape {
      if !busy() {
        publish_close()
      }
      true
    } else {
      false
    }
  })
  .takes_back(fn() {
    if !busy() {
      publish_close()
    }
  })
  |> ignore
  // (what was drawn live on it let go as it has gone, where no other has opened since)
  n.owns(fn() {
    if publishing.of.untracked() is None {
      @sfbase.viz_close("publish/")
    }
  })
  |> ignore
  // beside the system's bars (an iPhone Duo's): its tabs put away while it is open, its way back and its doing in
  // their bars in place of its own bar or band
  n.reacts(fn() { publish_native_said() }, fn(said) { publish_native(said) })
  // (已复制 a moment after it was copied)
  let copied_now = publish_copied_shown
  copied_now.set(false)
  let copied_due : Ref[() -> Unit] = Ref(fn() {  })
  n.reacts(fn() { publishing.copied.get() }, fn(times) {
    if times > 0 {
      (copied_due.val)()
      copied_now.set(true)
      copied_due.val = n.at_moment(n.cause_at() + @sf.copied_ms, fn() { copied_now.set(false) })
    }
  })
  // the walk through its pages of HTML as its picture is asked for, at each cause that moves it on
  // (publish_viz_wait_ms at most at each step of it, from the moment it came to it: one not there by then is its card)
  let armed : Ref[PublishWalk?] = Ref(None)
  let timeout : Ref[() -> Unit] = Ref(fn() {  })
  n.reacts(publish_walk_said, fn(said) {
    match said {
      Some((w, _, _, _)) => {
        if armed.val != Some(w) {
          armed.val = Some(w)
          (timeout.val)()
          timeout.val = n.at_moment(n.cause_at() + publish_viz_wait_ms, fn() {
            if publishing.walk.untracked() == Some(w) {
              publishing.walk.set(Some({ ..w, at: w.at + 1, step: 0 }))
            }
          })
        }
        publish_walk_on(n, w)
      }
      None => {
        armed.val = None
        (timeout.val)()
        timeout.val = fn() {  }
      }
    }
  })
  let width = fn() { n.window_w() }
  let tips_at : Ref[@view.View?] = Ref(None)
  let tips = @sf.TipLayer::new(fn() { tips_at.val })
  n.box(fn(page) {
    page.fills_across(Is(true)).grow(Is(1.0)).alpha(By(fn() { look().words })) |> ignore
    // (one in the other's place at once: what comes is there whole as it is answered, as a page shows what it opens on)
    page.pick(
      at_once=true,
      fn() {
        match publishing.read.get() {
          0 => 0
          2 => 2
          _ => if items(publishing.preview.get(), "list").length() == 0 { 3 } else { 1 }
        }
      },
      fn(o, state) {
        match state {
          1 => publish_list_node(o, src, r, width, tips)
          _ => {
            o.over(Is(true)) |> ignore
            @sf.style_node(o, fn() { publish_note })
            match state {
              0 => @sf.wait_line_node(o, fn() { @sf.t("web-pages.chat.publish.reading") }) |> ignore
              2 => @sf.words_node(o, fn() { publishing.error.get() }, fn() { publish_problem }) |> ignore
              _ => @sf.words_node(o, fn() { @sf.t("web-pages.chat.publish.empty") }, fn() { publish_note_words }) |> ignore
            }
          }
        }
      },
    )
  })
  |> ignore
  // what it is for: on a wide screen the bar a file opened has (back to the chat), 复制图片 at its end; on a small one
  // 取消, 复制 and 保存到相册 at the foot; beside the system's bars, theirs (publish_native)
  n.show(fn() { !@sf.native_on() }, fn(o) {
    o.over(Is(true)).alpha(By(fn() { look().words })) |> ignore
    let p = fn() { publishing.preview.get() }
    @sf.viewer_frame_act_node(
      o,
      fn() { if r.title != "" { r.title } else { @sf.t("common.close") } },
      fn() { @sf.t("web-pages.chat.shareImage") },
      fn() { text(p(), "hiddenText") },
      fn() { @sf.page_viewer_ink() },
      fn() {
        let (label, _) = @sf.picture_out_way()
        if copied_now.get() && !@sf.picture_to_album() { @sf.t("common.copied") } else { label }
      },
      width,
      tips,
      // (copied: 已复制 a moment after; on a phone 复制 beside 保存到相册, the user 2026-11-06「手机上都加复制」; 复制 there:
      // 复制图片 cut the row short in English)
      copy?=if @sf.picture_to_album() {
        Some(fn() { if copied_now.get() { @sf.t("common.copied") } else { @sf.t("common.copy") } })
      } else {
        None
      },
      busy=fn() { publishing.busy.get() },
      busy_copy=fn() {
        publishing.busy.get() |> ignore
        publishing.copying && @sf.picture_to_album()
      },
      disabled=fn() { p() is None || publish_kept(p()) == 0 },
      on_close=fn() {
        if !busy() {
          publish_close()
        }
      },
      on_act=fn() { publish_go(copy=false) },
      on_copy=fn() { publish_go(copy=true) },
    )
  })
  tips_at.val = Some(n.box(fn(l) { l.over(Is(true)) |> ignore }))
}

///|
/// How it comes in (window_page_in's fade).
pub let publish_in_ms : Double = 140.0

///|
/// What it says to the system's bars (an iPhone Duo's), as it changes (publish_native's).
#derive(Eq)
priv struct PublishNative {
  title : String
  busy : Bool
  can : Bool
  copied : Bool
  album : Bool
  words : Array[String]
}

///|
/// What it says to the system's bars, where they are (publish_native's): 分享图片 their title upright (with how much was
/// hidden), none on its side (the system floats it over the page's top, on the chat's name and its first message: seen
/// on the Duo's simulator, 2026-11-06; the page says what it is and what was hidden itself); its doing once there is
/// something in the picture, not while it is being taken; 已复制 a moment after it was copied.
fn publish_native_said() -> PublishNative? {
  if !@sf.native_on() {
    return None
  }
  let p = publishing.preview.get()
  let hidden = text(p, "hiddenText")
  let copied = publish_copied_shown.get()
  Some({
    title: if @sf.native_side() {
      ""
    } else {
      @sf.t("web-pages.chat.shareImage") + (if hidden != "" { " · " + hidden } else { "" })
    },
    busy: publishing.busy.get(),
    can: p is Some(_) && publish_kept(p) > 0,
    copied,
    album: @sf.picture_to_album(),
    words: ["common.close", "common.copied", "desktop.contextMenu.copyImage"].map(fn(k) { @sf.t(k) }) +
      [@sf.picture_out_way().0, @sf.picture_out_way().1],
  })
}

///|
/// Whether 已复制 shows where it was copied (publish_native_said), told by the page's layer a moment after each copy.
// kept across runs: a signal set by the page's layer, put back as each page opens
let publish_copied_shown : @signals.Signal[Bool] = @signals.signal(false)

///|
/// Its way back and its doing in the system's bars (an iPhone Duo's), as `said` says (publish_native_said), as a picture
/// opened has its (sfbase's vf_native): close at their lead, 复制图片 and 保存到相册 once there is something in the
/// picture; neither while it is being taken. Kept as said while it is open (@sf.native_over_up).
fn publish_native(said : PublishNative?) -> Unit {
  guard said is Some(s) else { return }
  if !@sf.native_over_up(s.title, alive=publish_open, owner="publish", over=1) {
    return
  }
  @sf.native_over_act("close", s.words[0], "close", fn() {
    if !publishing.busy.untracked() {
      publish_close()
    }
  }, lead=true)
  if s.busy || !s.can {
    return
  }
  let label = s.words[3]
  let icon = s.words[4]
  // (a phone's 复制图片 before its 保存到相册, as a picture opened has copy before download)
  if s.album {
    @sf.native_over_act("copy", if s.copied { s.words[1] } else { s.words[2] }, "copy", fn() { publish_go(copy=true) })
  }
  @sf.native_over_act("act", if s.copied && !s.album { s.words[1] } else { label }, icon, fn() { publish_go(copy=false) })
}

///|
/// How far down the page under what is over it starts, the window `w` wide: beside the system's bars their room (its
/// own bar none), else @sf.viewer_act_head's (the bar on a wide screen, the status bar on a small one).
fn publish_head_w(w : Double) -> Double {
  if @sf.native_on() {
    (@sf.viewer_host().room)().0
  } else {
    @sf.viewer_act_head(w)
  }
}

///|
/// How much of the window's foot what is over the page takes, the window `w` wide: beside the system's bars their room
/// (no band of its own), else @sf.viewer_act_foot's (the band of a small screen; none on a wide one).
fn publish_foot_w(w : Double) -> Double {
  if @sf.native_on() {
    (@sf.viewer_host().room)().1
  } else {
    @sf.viewer_act_foot(w)
  }
}

///|
/// The page's list in `parent` (publish_node's), the window `width` wide: the chat's name in its `head`, each message
/// virtualized as its own `scrolls_window` row key (`publish_row_key`) with still.fail's mark as a trailing row
/// (`publish_foot_key`), at the chat's width (760 at most) in the middle, a column before it where each message's box
/// to tick stands, under what is over it at the top and over the band at the foot. Opened from a message's 多选, that
/// message's row is brought into sight via `place.bring`.
fn publish_list_node(parent : @view.View, src : Source, r : ChatRef, width : () -> Double, tips : @sf.TipLayer) -> Unit {
  parent.over(Is(true)) |> ignore
  let scroll = @view.Scroll::list()
  let place : @view.ListPlace[String] = @view.ListPlace::new()
  publishing.page = Some({ layer: parent, scroll, place })
  parent.owns(fn() {
    match publishing.page {
      Some(page) if physical_equal(page.place, place) => publishing.page = None
      _ => ()
    }
  })
  |> ignore
  // (the picture's width: the window's on a phone, less the column its boxes to tick stand in before it on the page)
  let column = fn() { dmin(width() - @sf.native_clear() - publish_tick_room(), publish_page_w) }
  let here = publish_here(r, column, false, Some(tips))
  let p = @signals.untracked(fn() { publishing.preview.get() })
  let hidden = publish_hidden(p)
  let row_keys : Array[String] = []
  let by_key : Map[String, (Int, Message)] = Map([])
  let mut picked_at : (Int, String)? = None
  for i, j in items(p, "list") {
    let m = @sfbase.message_of(j)
    let rk = publish_row_key(i, m.seq)
    row_keys.push(rk)
    by_key[rk] = (i, m)
    if picked_at is None && publishing.picked == Some(m.seq) {
      picked_at = Some((i, rk))
    }
  }
  row_keys.push(publish_foot_key)
  place.on_sight(fn(_) { publishing.sighted.set(publishing.sighted.untracked() + 1) })
  parent.box(fn(l) {
    l.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
    // (each message its own virtualized row key, title in head, brand in trailing row so long chats only mount what
    // is in sight)
    l.scrolls_window(
      scroll,
      fn() { row_keys },
      fn(slot, rk) {
        slot.fills_across(Is(true)) |> ignore
        if rk == publish_foot_key {
          publish_block(slot, column, false, fn(b) {
            b.padding(By(fn() { (0.0, publish_paper_gap + publish_foot_down, 0.0, publish_paper_in + publish_page_under + publish_foot_w(width())) })) |> ignore
            publish_brand_node(b, column, false)
          })
        } else {
          match by_key.get(rk) {
            Some((i, m)) =>
              publish_block(slot, column, false, fn(b) {
                publish_message_block(b, src, here, column, m, hidden, i == 0)
              })
            None => ()
          }
        }
      },
      head=fn(h) {
        h.fills_across(Is(true)) |> ignore
        publish_block(h, column, false, fn(b) {
          b.padding(By(fn() { (0.0, publish_head_w(width()) + publish_paper_in, 0.0, publish_paper_gap) })) |> ignore
          publish_title_node(b, column, false, text(p, "title"))
        })
      },
      top_covered=fn() { publish_head_w(width()) },
      comes=fn(_) { false },
      goes=fn(_) { false },
      place~,
    )
    |> ignore
    if picked_at is Some((picked_i, rk)) && picked_i > 0 {
      let gap_now = if column() <= chat_narrow_w { list_gap_narrow } else { list_gap }
      place.bring(rk, offset=gap_now - publish_paper_in, glide=false)
    }
  })
  |> ignore
}

///|
/// The page list's trailing brand row key, and each message's unique row key.
let publish_foot_key : String = "foot"

///|
fn publish_row_key(i : Int, seq : Double) -> String {
  "m:\{i}:\{seq_s(seq)}"
}

///|
/// How much was hidden in each of preview `p`'s messages, by its seq (the preview's `messages`, by their n).
fn publish_hidden(p : Json?) -> Map[Double, String] {
  let hidden : Map[Double, String] = Map([])
  for m in items(p, "messages") {
    match text(Some(m), "hiddenText") {
      "" => ()
      h => hidden[number(Some(m), "n")] = h
    }
  }
  hidden
}

///|
/// A block of the picture in `parent`: the page's column in the middle of the room (the chat's width and, on the page,
/// the column its boxes to tick stand in before it; clear of the system's column at its end), its paper's sides as the
/// picture is `column()` wide (narrow: as far in as the chat's list has its words there), what `make` makes in it.
fn publish_block(parent : @view.View, column : () -> Double, taking : Bool, make : (@view.View) -> Unit) -> Unit {
  parent.box(fn(room) {
    room
    .fills_across(Is(true))
    .lines_up(Is(Some(Middle)))
    .padding(By(fn() { (0.0, 0.0, if taking { 0.0 } else { @sf.native_clear() }, 0.0) }))
    |> ignore
    room.box(fn(paper) {
      paper
      .width_share(Is(1.0))
      .max_width(By(fn() { Some(publish_page_w + (if taking { 0.0 } else { publish_tick_room() })) }))
      |> ignore
      paper.box(fn(b) {
        b
        .fills_across(Is(true))
        .margin(By(fn() {
          let edge = publish_edge(column())
          (edge, 0.0, edge, 0.0)
        }))
        |> ignore
        make(b)
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// How far in from the paper's sides what it holds is, the picture `w` wide: 32, narrow as far in as the chat's list has
/// its words there (16: chat_list.mbt row_side_narrow).
fn publish_edge(w : Double) -> Double {
  if w <= chat_narrow_w {
    row_side_narrow
  } else {
    publish_paper_in
  }
}

///|
/// How far the words are in past the paper's edge, the picture `w` wide, on the page or in the picture taken (`taking`):
/// past the column of its boxes to tick (on the page) and the pictures out in the margin (wide; narrow, inline).
fn publish_words_in(w : Double, taking : Bool) -> Double {
  (if taking { 0.0 } else { publish_tick_room() }) + (if w <= chat_narrow_w { 0.0 } else { @sf.message_avatar_reach })
}

///|
/// The chat's name over its messages (the chat's bar's title, its size), where its words start.
fn publish_title_node(parent : @view.View, column : () -> Double, taking : Bool, title : String) -> Unit {
  if title == "" {
    return
  }
  @sf.words_node(parent, fn() { title }, fn() { publish_title }).margin(By(fn() { (publish_words_in(column(), taking), 0.0, 0.0, 0.0) }))
  |> ignore
}

///|
/// still.fail's mark and name, where the words start: 16 and 6 apart, muted.
fn publish_brand_node(parent : @view.View, column : () -> Double, taking : Bool) -> Unit {
  parent.box(fn(b) {
    b
    .row(Is(true))
    .lines_up(Is(Some(Middle)))
    .gap(Is(@ui.Space::px(S1_5)))
    .margin(By(fn() { (publish_words_in(column(), taking), 0.0, 0.0, 0.0) }))
    |> ignore
    @sf.drawable_node(b, "stillfail_mark", publish_mark) |> ignore
    @sf.words_node(b, fn() { @sf.product() }, fn() { publish_brand }) |> ignore
  })
  |> ignore
}

///|
/// Message `m` on the page in `parent` (publish_list_node's block), `hidden` how much was hidden in each: as far under
/// the one before as the chat's list has them (none over the `first`); its box to tick in the column before its words,
/// on the middle of its first line (its head's, or the first of the viewer's own bubble), its edge the muted ink so that
/// every one shows (2026-11-06 用户 of the boxes of those not ticked,「看不清」), never faded; the message as the chat's
/// list draws it (publish_said_node) and, under it, how much was hidden in it, faded once out of the picture; pointed at
/// (or pressed), its box to tick lights all of it, a band across the paper from edge to edge (square: it runs out of its
/// sides as a list's row does), half the room between messages over and under it, so that lit one after another they
/// meet.
fn publish_message_block(
  parent : @view.View,
  src : Source,
  here : MessageNodeHere,
  column : () -> Double,
  m : Message,
  hidden : Map[Double, String],
  first : Bool,
) -> Unit {
  let k = message_k(m.seq)
  let gap = fn() { if column() <= chat_narrow_w { list_gap_narrow } else { list_gap } }
  if !first {
    parent.padding(By(fn() { (0.0, gap(), 0.0, 0.0) })) |> ignore
  }
  let on = fn() { !publishing.off.contains(k) }
  let out = @motion.eased_on(parent, fn() { !on() }, @motion.tween(@sf.dur_ms, ease=Out))
  parent.box(fn(band) {
    band.row(Is(true)).fills_across(Is(true)) |> ignore
    // (the band across the paper, from edge to edge, half the room between messages over and under it)
    band.ground_drawn(
      By(fn() {
        let edge = publish_edge(column())
        let half = gap() / 2.0
        { dx: -edge, dy: -half, dw: edge * 2.0, dh: half * 2.0, corners: None }
      }),
    )
    |> ignore
    let side = @sf.theme().rows.check
    band.box(fn(col) {
      col.width(Is(Some(publish_tick_room()))).shrink(Is(0.0)).padding(Is((0.0, centred_in(first_line_h(m), side), 0.0, 0.0))) |> ignore
      let tick = @sf.check_node_of(
        col,
        on,
        fn(now) {
          if now {
            publishing.off.remove(k)
          } else {
            publishing.off[k] = true
          }
        },
        fn() { @sf.t("web-pages.chat.publish.message") },
        side~,
        corner=@sf.theme().rows.check_corner,
        edge=fn() { @sf.theme().p.muted },
      )
      @sf.hover_ground_node(band, by=tick)
    })
    |> ignore
    band.box(fn(content) {
      content
      .grow(Is(1.0))
      .shrink(Is(1.0))
      .min_width(Is(Some(0.0)))
      .padding(By(fn() { (publish_words_in(column(), true), 0.0, 0.0, 0.0) }))
      .alpha(By(fn() { publish_faded(out.shown(content)) }))
      // (a message and, under it, how much was hidden in it, 6 under)
      .gap(Is(@ui.Space::px(S1_5)))
      |> ignore
      publish_said_node(content, src, here, m)
      match hidden.get(m.seq) {
        Some(h) =>
          content.box(fn(note) {
            @sf.style_node(note, fn() { if m.mine { publish_note_mine } else { publish_note_said } })
            @sf.icon_node(note, "shield-check", publish_note_icon_small, By(fn() { @sf.theme().p.muted })) |> ignore
            @sf.words_node(note, fn() { h }, fn() { publish_meta }) |> ignore
          })
          |> ignore
        None => ()
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// Message `m` as the chat's list draws it (chat_body_row's, by its kind: the viewer's own, still.fail's notice, a
/// person's, an agent's), in `parent`, none of the list's own round it (no room over it, none at its sides), its files
/// drawn as `here` says (its `picture`), nothing it offers of itself.
fn publish_said_node(parent : @view.View, src : Source, here : MessageNodeHere, m : Message) -> Unit {
  let key = "p:" + m.ts
  let none = fn() { 0.0 }
  let now = fn() { m }
  if m.mine {
    mine_said_node(parent, src, here, fn() { key }, none, none, now) |> ignore
  } else if m.system {
    notice_said_node(parent, src, here, fn() { key }, none, none, now, @sf.LiveMap::new(), @sf.LiveMap::new()) |> ignore
  } else if m.author_kind == "person" {
    person_said_node(parent, src, here, fn() { key }, none, none, now) |> ignore
  } else {
    agent_said_node(parent, src, here, fn() { key }, none, none, now, code=fn(lang) {
      if lang == "mermaid" {
        Some(fn(b, code) { @sfbase.viz_mermaid_node(b, src, here.station, code, fn() { @sf.theme().p.subtle }, here.tips) })
      } else {
        None
      }
    })
    |> ignore
  }
}

///|
/// The picture taken in `paper` (publish_take's, made apart), as wide as it is said: on the page's ground, the chat's
/// name over its messages as the chat's list draws them (2026-10-26 用户, of a picture that drew them apart:「渲染跟消息列表
/// 完全不一样」), only those ticked, only their attachments ticked (picture_message), their times dates (how long ago it was
/// is not so for long), still.fail's mark and name at its foot; no box to tick, no note of what was hidden.
fn publish_picture_node(paper : @view.View, here : MessageNodeHere, p : Json?) -> Unit {
  guard publishing_src.val is Some(src) else { return }
  let column = fn() { publish_page_w }
  paper.ground(By(fn() { @sf.theme().p.bg })) |> ignore
  publish_block(paper, column, true, fn(b) {
    b.padding(Is((0.0, publish_paper_in, 0.0, publish_paper_in))) |> ignore
    publish_title_node(b, column, true, text(p, "title"))
    b.box(fn(list) {
      list.fills_across(Is(true)).padding(Is((0.0, publish_paper_gap, 0.0, 0.0))).gap(Is(list_gap)) |> ignore
      for j in items(p, "list") {
        let m = picture_message(@sfbase.message_of(j), true)
        if publishing.off.contains(message_k(m.seq)) {
          continue
        }
        list.box(fn(row) {
          row.fills_across(Is(true)).padding(Is((publish_words_in(publish_page_w, true), 0.0, 0.0, 0.0))) |> ignore
          publish_said_node(row, src, here, m)
        })
        |> ignore
      }
    })
    |> ignore
    b.box(fn(f) {
      f.padding(Is((0.0, publish_paper_gap + publish_foot_down, 0.0, 0.0))) |> ignore
      publish_brand_node(f, column, true)
    })
    |> ignore
  })
}

///|
/// Message `m` as the picture holds it: taken (`taking`), without the attachments left out, its time a date.
fn picture_message(m : Message, taking : Bool) -> Message {
  if !taking {
    return m
  }
  let kept = m.attachments.filter(fn(a) { !publishing.off.contains(file_k(m.seq, a)) })
  {
    ..m,
    attachments: kept,
    placed: m.placed.filter(fn(n) { kept.iter().any(fn(a) { a.name == n }) }),
    time: m.time.map(fn(s) { { ..s, ago: s.full } }),
  }
}

///|
/// Attachment `a` of message `seq`'s number in the preview (its `files`' `k`, by the message's n and where it is); ""
/// when it has none.
fn file_k(seq : Double, a : Attachment) -> String {
  for f in items(publishing.preview.untracked(), "files") {
    if number(Some(f), "n") == seq && text(field(Some(f), "file"), "path") == a.path {
      return text(Some(f), "k")
    }
  }
  ""
}

///|
/// The seq of the preview's message `ts` (its files' `n`), -1 where it holds none.
fn publish_seq_of(ts : String) -> Double {
  for j in items(publishing.preview.untracked(), "list") {
    if text(Some(j), "ts") == ts {
      return number(Some(j), "seq")
    }
  }
  -1.0
}

///|
/// A file of message `ts` in the picture (MessagePicture's `file`), as the chat draws it (`draw`), in `parent`: in the
/// picture taken (`taking`), as it is, the room its ✕ hangs in kept, so that it is laid out as the page has it; on the
/// page, as what waits to go in the composer has it, a ✕ hung on its top right corner (publish_ticked) takes it out of
/// the picture.
fn publish_file_node(parent : @view.View, ts : String, a : () -> Attachment, draw : (@view.View) -> Unit, taking : Bool) -> Unit {
  let k = file_k(publish_seq_of(ts), @signals.untracked(a))
  if taking || k == "" {
    parent.box(fn(b) {
      b.padding(Is((0.0, 0.0, @sf.corner_remove_reach(@sf.message_file_corner), 0.0))) |> ignore
      draw(b)
    })
    |> ignore
  } else {
    publish_ticked(parent, k, true, draw)
  }
}

///|
/// Attachment `k` on the page in `parent`, drawn by `draw`, with its ✕ (@sf.with_corner_remove_node; `hung`: the room it
/// hangs in past the right edge kept): taken out, faded as its ✕ turns into a ＋ (that puts it back), as long as a
/// control's change takes; pressed anywhere on it too (what the chat would open it by does not here).
fn publish_ticked(parent : @view.View, k : String, hung : Bool, draw : (@view.View) -> Unit) -> Unit {
  let on = fn() { !publishing.off.contains(k) }
  let flip = fn() {
    if @signals.untracked(on) {
      publishing.off[k] = true
    } else {
      publishing.off.remove(k)
    }
  }
  let out = @motion.eased_on(parent, fn() { !on() }, @motion.tween(@sf.dur_ms, ease=Out))
  @sf.with_corner_remove_node(
    parent,
    fn() { @sf.t(if on() { "web-pages.chat.publish.leaveOut" } else { "web-pages.chat.publish.putBack" }) },
    @sf.message_file_corner,
    fn(i) {
      i.box(fn(card) {
        card.fills_across(Is(true)).alpha(By(fn() { publish_faded(out.shown(card)) })) |> ignore
        draw(card)
      })
      |> ignore
    },
    flip,
    hung~,
    // (pressed anywhere, as its mark is)
    whole=true,
    turn=fn(mark) { out.shown(mark) * publish_plus_turn },
  )
  |> ignore
}

///|
/// A page of HTML `a` placed in message `ts`'s words in the picture (MessagePicture's `viz`), in `parent`, `card` its card:
/// in the picture taken (`taking`), what it was grabbed as (its own kind's widget as itself), else its card; on the page,
/// as the chat draws it, keeping nothing and sending nothing, while it can be grabbed and is in the picture (a view fades
/// with nothing round it: one left out, or in a browser, is its card, to put back), its ✕ on it (publish_ticked).
fn publish_viz_node(parent : @view.View, r : ChatRef, ts : String, a : Attachment, card : (@view.View) -> Unit, taking : Bool) -> Unit {
  let seq = publish_seq_of(ts)
  let k = file_k(seq, a)
  if k == "" {
    return card(parent)
  }
  let mbui = @sfbase.is_mbui_viz(a.name)
  if taking {
    match publishing.stills.get(k) {
      _ if mbui => publish_viz_live(parent, r, k, a, card, true)
      Some((image, w, h)) =>
        parent.box(fn(b) {
          @sf.style_node(b, fn() { @sfbase.viz_file_box })
          // (its grab as it appeared on the page: that size keeps its words and its proportions in a wider picture)
          b.box(fn(i) {
            i
            .width(Is(Some(w)))
            .height(Is(Some(h)))
            .image(Is(Some((image, "", (dmax(w, h) * i.pixel_scale()).to_int()))))
            .image_covers(Is(true))
            .image_fades(Is(false))
            |> ignore
          })
          |> ignore
        })
        |> ignore
      None => card(parent)
    }
    return
  }
  let live = fn() {
    !publishing.off.contains(k) && !publishing.off.contains(message_k(seq)) && (mbui || @ui.platform() != 4)
  }
  parent.pick(live, fn(p, on) { if on { publish_viz_live(p, r, k, a, card, false) } else { card(p) } })
}

///|
/// Page of HTML `k` (`a`) drawn as itself in `parent` (publish_viz_node's), its file read first (its place breathing
/// meanwhile), its card (`card`) where it cannot be read; on the page with its ✕, in the picture taken (`taking`: its own
/// kind's widget alone) as it is. One drawn as a page is kept, while it is drawn on the page, for the picture's walk to
/// grab (publishing.viz_at).
fn publish_viz_live(parent : @view.View, r : ChatRef, k : String, a : Attachment, card : (@view.View) -> Unit, taking : Bool) -> Unit {
  guard publishing_src.val is Some(src) else { return card(parent) }
  let owner = owner_of(
    { station: r.station, session: r.session, view: publish_view(r), go: None, inline: false, gutter: 0.0, list: None, core: None },
    a,
  )
  let load = @sfbase.viz_load_node(parent, src, r.station, owner, a.path, size=a.size)
  let ticked = fn(p : @view.View, draw : (@view.View) -> Unit) {
    if taking {
      p.box(fn(b) { draw(b) }) |> ignore
    } else {
      publish_ticked(p, k, false, draw)
    }
  }
  parent.pick(
    fn() {
      match load() {
        None => 0
        Some(Err(_)) => 1
        Some(Ok(_)) => 2
      }
    },
    fn(p, state) {
      match (state, @signals.untracked(load)) {
        (2, Some(Ok((html, state)))) => {
          let place = "publish/" + r.station + ":" + r.session + "/" + k
          let hears : @sfbase.VizHears = { keep: None, failed: None, follow_up: None }
          match @sfbase.viz_mbui_parse(a.name, html) {
            Some(widget) =>
              ticked(p, fn(b) {
                @sf.style_node(b, fn() { @sfbase.viz_file_box })
                @sfbase.viz_mbui_node(b, place, widget, fn() { state.unwrap_or(Json::null()) }, hears)
              })
            None if @sfbase.is_mbui_viz(a.name) || taking => {
              publishing.viz_failed[k] = true
              publishing.viz_made.set(publishing.viz_made.untracked() + 1)
              card(p)
            }
            None =>
              ticked(p, fn(b) {
                @sf.style_node(b, fn() { @sfbase.viz_file_box })
                b.box(fn(box) {
                  let f = viz_page_node(box, place, html, state, hears)
                  publishing.viz_at[k] = (box, f)
                  publishing.viz_made.set(publishing.viz_made.untracked() + 1)
                  box.owns(fn() {
                    match publishing.viz_at.get(k) {
                      Some((at, _)) if physical_equal(at, box) => {
                        publishing.viz_at.remove(k)
                        publishing.viz_made.set(publishing.viz_made.untracked() + 1)
                      }
                      _ => ()
                    }
                  })
                  |> ignore
                })
                |> ignore
              })
          }
        }
        (1, _) => {
          publishing.viz_failed[k] = true
          publishing.viz_made.set(publishing.viz_made.untracked() + 1)
          card(p)
        }
        _ =>
          // its place, breathing as every wait's shapes, till the page comes
          ticked(p, fn(b) {
            @sf.style_node(b, fn() { @sfbase.viz_wait_under })
            b.box(fn(i) {
              @sf.style_node(i, fn() { @sfbase.viz_wait })
              @sf.breathe_node(i)
            })
            |> ignore
          })
      }
    },
  )
}

///|
/// An attachment left out (file[data-off]: .45); the shield before how much was hidden, under a message (13).
let publish_off_alpha : Double = 0.45

///|
/// How opaque it is, `out` of the picture.
fn publish_faded(out : Double) -> Double {
  1.0 - out * (1.0 - publish_off_alpha)
}

///|
/// The ✕ turned an eighth of a turn: a ＋.
let publish_plus_turn : Double = 0.7853981633974483

///|
let publish_note_icon_small : Double = 13.0

///|
/// Being read, not read, nothing to hold (fpNote: in the middle, muted, the ui's size).
// kept across runs: a value (no field of it changes)
let publish_note : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JCenter gap=S3_5")

///|
// kept across runs: a value (no field of it changes)
let publish_note_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let publish_problem : @ui.TextStyle = @ui.text_style(size=Ui, color=Danger)

///|
/// How far in from its sides what the picture holds is, and down from its top and up from its foot (S8's 32).
let publish_paper_in : Double = 32.0

///|
/// The picture's parts (its name, its messages, its foot) 16 apart; its foot 8 further under its last message.
let publish_paper_gap : Double = 16.0

///|
let publish_foot_down : Double = 8.0

///|
/// The chat's name over its messages (the chat's bar's title, its size).
// kept across runs: a value (no field of it changes)
let publish_title : @ui.TextStyle = @ui.text_style(size=Title, weight=Semibold, color=Fg, w=Full)

///|
let publish_mark : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
let publish_brand : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=Muted, wrap=false)

///|
/// How far under the picture the page ends: 64, over the band of 取消 and 保存到相册 on a small screen.
let publish_page_under : Double = 64.0

///|
let publish_page_w : Double = 760.0

///|
/// How much was hidden in a message (note: its shield 6 before it, the meta's size, muted); under the viewer's own, at
/// its end as the message is.
// kept across runs: a value (no field of it changes)
let publish_note_said : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let publish_note_mine : @ui.Style = @ui.css("row w=Full gap=S1_5 align=ACenter justify=JEnd")

///|
// kept across runs: a value (no field of it changes)
let publish_meta : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// The column the boxes to tick stand in on the page: a box (the theme's rows' check) and 12 after it.
fn publish_tick_room() -> Double {
  @sf.theme().rows.check + publish_tick_gap
}

///|
let publish_tick_gap : Double = 12.0

///|
/// How far down something `h` high is to be in the middle of a line `line` high.
fn centred_in(line : Double, h : Double) -> Double {
  (line - h) / 2.0
}

///|
/// How high message `m`'s first line is, from its top: its head's line (its name, its time; S6), or for the viewer's
/// own that begins with its words, its bubble's first line (the bubble's 8 over a line of the theme's words); one that
/// begins with what it quotes or a file, the head's line as well.
fn first_line_h(m : @sfbase.Message) -> Double {
  if m.mine && m.text != "" && m.quotes.length() == 0 && beside_quotes(m.quotes, m.attachments).length() == 0 {
    bubble_in_y * 2.0 + @ui.style_words(@sf.theme().t.words).line
  } else {
    head_line_h
  }
}

