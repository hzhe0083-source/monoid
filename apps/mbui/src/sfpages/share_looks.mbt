// The looks the card to share can be drawn in (2026-10-27 用户：「再搞几版骚气的分享图片模板，让用户可以选择」「结构不用都
// 一致，信息甚至都不用一样」「为视觉服务」), chosen under it on its stage (share_looks_pick), the choice kept on the device
// (the prefs' `shareLook`). Each is its own picture, saying of the `fleet` view what serves it, as it serves it: the
// night (stations_now.mbt night_look, all of it), 大字报 (one number as large as the picture holds, still.fail's orange
// to its edges, a line under it), 小票 (a till's receipt: each day a line of the chats archived, the week's spend its
// total, a barcode) and 终端 (a fetch run in a terminal: still.fail's mark beside who it is, a line a figure, the
// palette). Each 360 wide as it is (@sf.share_w_most), nothing cut short, the same in either theme, as a poster is. The
// code face only for what a till or a terminal prints in it (figures, dates, keys, the command): words of Chinese in
// it stand a cell apart (「9  个对话」), so what is said is in the face of words. More are to come (2026-11-02 用户：「我们
// 后面会有很多分享模板」): a look is one entry of share_looks, offered as itself drawn small in a strip that scrolls.

///|
/// A look the card to share can be drawn in: `key` what the prefs keep of it (`shareLook`), its name the app's words'
/// `web-main.stations.shareLook.<key>`; `draw` the picture of the `fleet` view in the box it is given (share_pen.mbt), the
/// card's box, round as a card on the stage or `flat` (handed out: its ground to its edges). A new look is a `draw` and a line in share_looks: the picker,
/// the fixtures (share-card-<key>) and the corners' check take it from there; the core keeps any key it is given.
/// `group` the set it is offered in (share_groups), its looks alone in the strip while that set is shown.
/// `art`: its picture, its tile in the strip (senren_tile; "" none: its card drawn small there).
priv struct ShareLook {
  key : String
  group : String
  draw : (Pen, () -> Json?, Bool) -> Pen
  art : String
}

///|
/// The sets the looks are offered in, in their order, each named by the app's words'
/// `web-main.stations.shareGroup.<group>`: still.fail's own, and 千恋＊万花's thirty (share_senren.mbt), which in one strip
/// put the others out of sight (2026-11-03 用户：「想办法分组吧，不然这一批分享卡放进去后其它的卡都看不到了」).
// kept across runs: a table, never written
let share_groups : Array[String] = ["own", "senren"]

///|
/// The looks, in the order they are offered; the first the one drawn while none is chosen.
// kept across runs: a table, never written
let share_looks : Array[ShareLook] = [
  { key: "night", group: "own", draw: night_look, art: "" },
  { key: "poster", group: "own", draw: poster_look, art: "" },
  { key: "receipt", group: "own", draw: receipt_look, art: "" },
  { key: "terminal", group: "own", draw: terminal_look, art: "" },
  // 千恋＊万花's (share_senren.mbt): the heroines' own, 丛雨's ADV box, 芳乃's fortune slip, 茉子's mission report, 蕾娜's inn
  // bill, 小春's menu, 芦花's ledger
  senren("senren-adv", "a1-murasame-adv", sr_adv),
  senren("senren-omikuji", "a2-yoshino-omikuji", sr_omikuji),
  senren("senren-ninja", "a3-mako-roof", sr_ninja),
  senren("senren-ryokan", "a4-lena-ryokan", sr_ryokan),
  senren("senren-menu", "a5-koharu-sweets", sr_menu),
  senren("senren-ledger", "a6-roka-ledger", sr_ledger),
  // chibi: Ciallo's salute, 芳乃's dog ears, 丛雨's parfait, 小春's capsule toys, all six
  senren("senren-ciallo", "b1-chibi-ciallo", sr_ciallo),
  senren("senren-inumimi", "b2-chibi-yoshino-ears", sr_inumimi),
  senren("senren-parfait", "b3-chibi-murasame-spoon", sr_parfait),
  senren("senren-gacha", "b4-chibi-koharu-gacha", sr_gacha),
  senren("senren-chibi", "b5-chibi-group", sr_chibi),
  // the game's own screens: the title, the CG gallery, the routes' affection, the girls' group chat, the staff roll
  senren("senren-title", "c1-title-kv", sr_title),
  senren("senren-cg", "e1-murasame-beauty", sr_cg),
  senren("senren-affection", "a2-yoshino-omikuji", sr_affection),
  senren("senren-chat", "b2-chibi-yoshino-ears", sr_chat),
  senren("senren-staff", "c5-staffroll-bg", sr_staff),
  // 穗织's things: the sword's appraisal, the spring festival's kagura, the town's map, the votive plaques
  senren("senren-sword", "b6-chibi-murasame-pout", sr_sword),
  senren("senren-kagura", "d2-yoshino-kagura", sr_kagura),
  senren("senren-map", "d3-hoori-map", sr_map),
  senren("senren-ema", "d4-ema", sr_ema),
  // 穗织画报, a magazine's covers, each heroine whole
  senren("senren-gahou-murasame", "e1-murasame-beauty", sr_gahou_of("senren-gahou-murasame")),
  senren("senren-gahou-mako", "e4-mako-beauty", sr_gahou_of("senren-gahou-mako")),
  senren("senren-gahou-lena", "e3-lena-beauty", sr_gahou_of("senren-gahou-lena")),
  senren("senren-gahou-roka", "e2-roka-beauty", sr_gahou_of("senren-gahou-roka")),
  senren("senren-gahou-koharu", "e5-koharu-beauty", sr_gahou_of("senren-gahou-koharu")),
  senren("senren-gahou-roka2", "f2-roka-cover", sr_gahou_of("senren-gahou-roka2")),
  // together: the summer festival's photo, the sweets party, after school; 芦花's shop at night
  senren("senren-photo", "h1-group-festival", sr_photo),
  senren("senren-party", "h2-group-sweets", sr_party),
  senren("senren-class", "h3-group-classroom", sr_class),
  senren("senren-night", "f1-roka-night", sr_night),
]

///|
/// The keys of the looks, in their order (the fixtures' share-card-<key>).
pub fn share_look_keys() -> Array[String] {
  share_looks.map(fn(l) { l.key })
}

///|
/// The look chosen (the prefs' `shareLook`; none kept, or one this build does not know: the first).
fn share_look(src : Source) -> ShareLook {
  share_look_of(text(src.topic("prefs", Map([])).get().value, "shareLook"))
}

///|
/// The look kept as `kept` (one this build does not know: the first).
fn share_look_of(kept : String) -> ShareLook {
  for l in share_looks {
    if l.key == kept {
      return l
    }
  }
  share_looks[0]
}

///|
/// Under the picture, over its buttons, in `v`: the sets of looks by name (share_groups, a tab list), the one shown in
/// the white; under them that set's looks, each the picture itself drawn small (its top, as wide as its tile), its name
/// under it, the chosen one ringed; a strip that scrolls sideways once there are more than the picture is wide for, the
/// chosen one brought into view as the set shows. The set shown is the chosen look's until another is pressed
/// (share_group_shown). A press on a look draws the card in it at once and keeps it the device's (`prefs.set`).
fn share_looks_pick_node(v : @view.View, src : Source, w : Workspace) -> Unit {
  let shown = fn() {
    match share_group_shown.get() {
      "" => share_look(src).group
      g => g
    }
  }
  v.box(fn(all) {
    @sf.style_node(all, fn() { groups_and_looks })
    @sf.share_tabs_node(
      all,
      fn() { @sf.t("web-main.stations.shareLook") },
      share_groups,
      fn(group) { @sf.t("web-main.stations.shareGroup." + group) },
      shown,
      fn(g) { share_group_shown.set(g) },
    )
    |> ignore
    // (as wide as the picture is laid out: more looks than that has the room for scrolled in it, not the stage made as
    // wide as all of them; no bar under it (one strip): the stage as tall as with four)
    all.pick(at_once=true, shown, fn(strip, group) { share_looks_strip(strip, src, w, group) })
  })
  |> ignore
}

///|
/// The looks of set `group` side by side in `v`, scrolled sideways where there are more than the picture is wide for,
/// the chosen one brought into view as it is made.
fn share_looks_strip(v : @view.View, src : Source, w : Workspace, group : String) -> Unit {
  let looks = share_looks.filter(fn(l) { l.group == group })
  // (their pictures asked all at once, before any is made: what comes of each asked as it is made would lay the strip
  // out again for each)
  senren_asked(src, looks.filter(fn(l) { l.art != "" }).map(fn(l) { look_tile_file(l) }))
  let s = @view.Scroll::across()
  v.box(fn(room) {
    room.width(Is(Some(@sf.share_w_most))).max_width(Is(Some(@sf.share_w_most))) |> ignore
    room.scrolls(s, slop=@ui.touch_slop(), fn(row) {
      @sf.style_node(row, fn() { looks_row })
      for look in looks {
        share_look_item(row, src, w, look)
      }
    })
    |> ignore
  })
  |> ignore
  // (the chosen one in view: as far along as it is, less what the strip shows past it)
  let now = share_look(src).key
  match looks.search_by(fn(l) { l.key == now }) {
    Some(i) => {
      let each = share_look_ring_w + @ui.Space::px(S2)
      s.put(dmax(0.0, i.to_double() * each + share_look_ring_w - @sf.share_w_most))
    }
    None => ()
  }
}

///|
/// How wide a look's ring is in the strip: its tile and the room round it to its ring.
let share_look_ring_w : Double = @sf.share_look_tile_w + 2.0 * (@ui.Space::px(@sf.share_look_in) + 1.5)

///|
/// Look `look` in the strip (`v`): its tile in its ring (the chosen one's the white), its name under it; pressed, chosen
/// and kept the device's.
fn share_look_item(v : @view.View, src : Source, w : Workspace, look : ShareLook) -> Unit {
  let name = fn() { @sf.t("web-main.stations.shareLook." + look.key) }
  let on = fn() { share_look(src).key == look.key }
  @sf.action_box_node(v, name, selected=on, fn(_) {
    if !on() {
      (src.call)("prefs.set", { "shareLook": Json::string(look.key) }, @sfbase.answer_unread)
    }
  }, fn(item) {
    @sf.style_node(item, fn() { looks_item })
    item.box(fn(ring) {
      @sf.style_node(ring, fn() { if on() { looks_ring_on } else { looks_ring } })
      look_tile_node(ring, src, look, w)
    })
    |> ignore
    item.box(fn(n) {
      let st = fn() { if on() || item.pointed() || item.focus_shown() { looks_name_on } else { looks_name } }
      n.words(By(name)).words_look(By(fn() { @ui.style_words(st()) })).ink(By(fn() { @ui.style_ink(st()) })) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A look's small picture in `v`: the picture it draws (千恋＊万花's, its picture alone: senren_tile), laid out as wide as
/// it is handed out (@sf.share_w_most) and drawn as wide as the tile, from its top (what is under the tile's foot cut);
/// said by its name, not its words; made as the strip shows its set, its figures as they were then (too small to be
/// read: the picture over it follows them). Its own files of the looks (its small picture:
/// look_tile_file) had on their own, how far in a spinner in its middle until they are here (2026-11-03 用户「每张独立
/// 下载并提供进度」).
fn look_tile_node(v : @view.View, src : Source, look : ShareLook, w : Workspace) -> Unit {
  let k = @sf.share_look_tile_w / @sf.share_w_most
  v.box(fn(tile) {
    @sf.style_node(tile, fn() { @sf.share_look_tile })
    tile.hides(Is(true)) |> ignore
    tile.box(fn(whole) {
      whole
      .over(Is(true), edges=(Some(0.0), Some(0.0), None, None))
      .width(Is(Some(@sf.share_w_most)))
      .scale(Is(k), about=At(0.0, 0.0))
      |> ignore
      if look.art != "" {
        senren_tile(Pen::of(whole), look.art) |> ignore
      } else {
        // (what the view says as the strip shows the set: too small to be read, it follows none of its changes)
        let said = @signals.untracked(share_fleet(src, w))
        (look.draw)(Pen::of(whole), fn() { said }, true) |> ignore
      }
    })
    |> ignore
    let needs = if look.art != "" { [look_tile_file(look)] } else { [] }
    let coming = fn() {
      match @sfbase.looks_stand(src, needs) {
        LooksGoing(part) => Some(part)
        _ => None
      }
    }
    // (seen only while they come: made once, how far they are and whether it shows its look alone, so what comes of each
    // file lays out nothing; whole once they are here, turning no more)
    tile.box(fn(wait) {
      wait.over(Is(true)).alpha(By(fn() { if coming() is Some(_) { 1.0 } else { 0.0 } })) |> ignore
      @sf.style_node(wait, fn() { tile_waiting })
      @sf.progress_spinner_node(wait, fn() { coming().unwrap_or(Some(1.0)) }, size=@sf.theme().round.glyph) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The file of a look's small picture (senren_tile's), as it is had (senren_art_file).
fn look_tile_file(look : ShareLook) -> String {
  senren_art_file(look.art, small=true)
}

///|
/// Over a look's tile while its files come: as large as the tile, its spinner in the middle.
// kept across runs: a value (no field of it changes)
let tile_waiting : @ui.Style = @sf.centred.then(@ui.style(w=Fixed(@sf.share_look_tile_w), h=Fixed(@sf.share_look_tile_h)))

///|
/// The card in `ground`: round as a card on the stage, or `flat` (handed out: its ground to its edges).
fn look_box(c : Pen, flat : Bool, ground : Int64, inner : (Pen) -> Unit) -> Pen {
  c.box(style=(if flat { pic_box_flat } else { pic_box }).then(@ui.style(bg=Data(ground))), inner)
}

///|
/// Words in the code face, as `words` works them out (and as `style_by` chooses their style, laid out as `style`).
fn code_words(c : Pen, words : () -> String, style : @ui.TextStyle, style_by? : () -> @ui.TextStyle) -> Unit {
  c.rich_by(fn() { [@ui.span(words(), mono=true)] }, style~, style_by?)
}

///|
/// A span's figures, each its value and what it is (today's, the last 7 days').
fn span_stats(span : Json?) -> Array[(String, String)] {
  items(span, "stats").map(fn(x) { (text(Some(x), "label"), text(Some(x), "value")) })
}

///|
/// `all` each with its place in it: a line kept by its place where nothing else names it.
fn[T] placed(all : Array[T]) -> Array[(Int, T)] {
  all.mapi(fn(i, x) { (i, x) })
}

// ── 大字报 ─────────────────────────────────────────────────────────────────

///|
/// 大字报: one number, as large as the picture holds, on still.fail's orange to its edges, in the night's black: what
/// leads the first kind's share over it, what it is of under it; then the chats at work now, large, and where; still.fail
/// large at its foot (what is passed on says whose it is), its line beside the time. Nothing used: the chats at work
/// are its number, the tasks across devices its line.
fn poster_look(c : Pen, fleet : () -> Json?, flat : Bool) -> Pen {
  let spent = fn() { items(fleet(), "spent") }
  let used = fn() { spent().length() > 0 }
  let first = fn() { spent().get(0) }
  let models = fn() { items(first(), "models") }
  let top = fn() { models().get(0) }
  let tasks = fn() { text(fleet(), "tasksText") }
  look_box(c, flat, @sf.share_poster_ground, fn(c) {
    c.box(style=poster_inner, fn(c) {
      c.box(style=poster_hero, fn(c) {
        c.show_rich(used, fn() { [@ui.span(text(first(), "lead"))] }, style=poster_words)
        // (the first model's tokens, or with nothing used the chats at work)
        c.rich_by(
          fn() {
            if used() {
              let words = text(top(), "tokensText")
              let scale = if words.length() > 4 {
                @sf.share_poster_number_less
              } else {
                @sf.share_poster_number_scale
              }
              [@ui.span(words, scale~)]
            } else {
              [@ui.span(count(fleet(), "chats").to_string(), scale=@sf.share_poster_number_scale)]
            }
          },
          style=poster_number,
        )
        c.text_by(
          fn() {
            if used() {
              text(top(), "name") + " " + text(top(), "of")
            } else {
              text(fleet(), "chatsText")
            }
          },
          style=poster_words,
        )
        // its other models, each its own tokens and cost (no kind adds its models' up), each kept by its place
        c.each_rich(
          fn() { if used() { placed(models()[1:].to_owned()) } else { [] } },
          fn(m) { m.0 },
          fn(m) { [@ui.span(text(Some(m().1), "name") + "  " + text(Some(m().1), "lineText"))] },
          style=poster_small,
        )
      })
      |> ignore
      c.box(style=poster_more, fn(c) {
        let more = fn() { used() || tasks() != "" }
        c.show_rich(more, fn() { [@ui.span(if used() { text(fleet(), "chatsText") } else { tasks() })] }, style=poster_big)
        c.show_rich(
          more,
          fn() { [@ui.span(text(fleet(), if used() { "where" } else { "tasksPer" }))] },
          style=poster_small,
        )
      })
      |> ignore
      // (the foot at the picture's foot, however tall what is over it)
      c.box(style=poster_rest, fn(_) {  }) |> ignore
      c.box(style=poster_foot, fn(c) {
        c.text(@sf.product(), style=poster_brand) |> ignore
        c.box(style=pic_head, fn(c) {
          c.box(style=pic_grow, fn(c) { c.text_by(fn() { @sf.t("web-main.stations.shareTagline") }, style=poster_small) })
          |> ignore
          c.text_by(fn() { text(fleet(), "at") }, style=poster_small)
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
}

// ── 小票 ───────────────────────────────────────────────────────────────────

///|
/// A line of the receipt's kinds: kind `kind` (in the core's order) as `model` -1, else its model `model`.
#derive(Eq)
priv struct ReceiptLine {
  kind : Int
  model : Int
  of : Json
}

///|
/// 小票: a till's receipt of the agents' week, on its paper. Read down: still.fail and when, in its middle; each day a
/// line, its chats archived at its end (today's date in the orange); the chats archived and the tokens read as its
/// subtotals; each kind of account a line (its accounts), its models under it (each its tokens and cost); between
/// double dashes the week's spend, large, its total; a barcode made of what it says, still.fail's line under it.
fn receipt_look(c : Pen, fleet : () -> Json?, flat : Bool) -> Pen {
  let spent = fn() { items(fleet(), "spent") }
  let week = fn() { field(fleet(), "week") }
  let stats = fn() { span_stats(week()) }
  let days = fn() { items(week(), "days") }
  let has_days = fn() { days().length() > 0 }
  let total = fn() { stats().last() }
  look_box(c, flat, @sf.share_receipt_ground, fn(c) {
    c.box(style=receipt_head, fn(c) {
      c.rich(
        [@ui.span("still", mono=true), @ui.span(".", mono=true, color=@sf.share_receipt_orange), @ui.span("fail", mono=true)],
        style=receipt_brand,
      )
      |> ignore
      code_words(c, fn() { text(fleet(), "at") }, receipt_dim)
    })
    |> ignore
    c.box(style=receipt_dashes, dashes) |> ignore
    c.show(has_days, style=receipt_items, fn(c) {
      c.each(fn() { placed(days()) }, fn(d) { d.0 }, style_of=fn(_) { pic_other }, fn(c, d) {
        let d = fn() { Some(d().1) }
        let today = fn() { flag(d(), "today") }
        code_words(c, fn() { text(d(), "label") }, receipt_code_line, style_by=fn() {
          if today() {
            receipt_today
          } else {
            receipt_code_line
          }
        })
        c.box(style=pic_grow, fn(_) {  }) |> ignore
        code_words(c, fn() { text(d(), "value") }, receipt_value)
      })
    })
    c.show(has_days, style=receipt_dashes, dashes)
    // the subtotals: the week's figures but its spend (its total)
    c.show(fn() { stats().length() > 1 }, style=receipt_items, fn(c) {
      c.each(
        fn() {
          let s = stats()
          placed(s[:s.length() - 1].to_owned())
        },
        fn(x) { x.0 },
        style_of=fn(_) { pic_other },
        fn(c, x) { receipt_item(c, fn() { x().1.0 }, fn() { x().1.1 }, true) },
      )
    })
    c.show(fn() { spent().length() > 0 }, style=receipt_items, fn(c) {
      // each kind a line, its models under it, each its own tokens and cost
      let lines = fn() {
        let out : Array[ReceiptLine] = []
        for k, q in spent() {
          out.push({ kind: k, model: -1, of: q })
          for i, m in items(Some(q), "models") {
            out.push({ kind: k, model: i, of: m })
          }
        }
        out
      }
      c.each(
        lines,
        fn(l) { (l.kind, l.model) },
        style_of=fn(l) {
          if l.model >= 0 {
            receipt_model
          } else if l.kind == 0 {
            receipt_kind_first
          } else {
            receipt_kind
          }
        },
        fn(c, l) {
          let of = fn() { Some(l().of) }
          if @signals.untracked(l).model < 0 {
            c.text_by(fn() { text(of(), "name") + " ×" + count(of(), "accounts").to_string() }, style=receipt_line)
          } else {
            c.box(style=pic_other, fn(c) {
              receipt_item(c, fn() { text(of(), "name") }, fn() { text(of(), "lineText") }, false)
            })
            |> ignore
          }
        },
      )
    })
    let has_total = fn() { total() is Some(_) }
    let double = fn(c : Pen) {
      c.box(style=receipt_dashes, dashes) |> ignore
      c.box(style=receipt_dashes, dashes) |> ignore
    }
    c.show(has_total, style=receipt_double, double)
    c.show(has_total, style=pic_other, fn(c) {
      c.text_by(fn() { total().map(fn(t) { t.0 }).unwrap_or("") }, style=receipt_title)
      c.box(style=pic_grow, fn(_) {  }) |> ignore
      code_words(c, fn() { total().map(fn(t) { t.1 }).unwrap_or("") }, receipt_total)
    })
    c.show(has_total, style=receipt_double, double)
    c.box(style=receipt_foot, fn(c) {
      c.box(style=receipt_code, fn(c) {
        barcode(c, fn() { text(fleet(), "at") + text(fleet(), "chatsText") + text(fleet(), "tasksText") })
      })
      |> ignore
      c.text_by(fn() { @sf.t("web-main.stations.shareTagline") }, style=receipt_tagline)
    })
    |> ignore
  })
}

///|
/// What an item of the receipt holds (`c`, its line: pic_other): what it is (`strong`: in the ink, else dimmer), its
/// figure at the line's end.
fn receipt_item(c : Pen, what : () -> String, value : () -> String, strong : Bool) -> Unit {
  c.text_by(what, style=if strong { receipt_name } else { receipt_line })
  c.box(style=pic_grow, fn(_) {  }) |> ignore
  code_words(c, value, receipt_value)
}

///|
/// What a torn line of dashes across the receipt holds (`c`, its line: receipt_dashes).
fn dashes(c : Pen) -> Unit {
  for _ in 0..<receipt_dash_count {
    c.box(style=receipt_dash, fn(_) {  }) |> ignore
  }
}

///|
/// A barcode of `words` (`c`, its row: receipt_code): a bar for each of its characters (receipt_code_most at most), as
/// wide as its code says (1 to 3), as far from the next; each kept by its place, as wide as its character there now.
fn barcode(c : Pen, words : () -> String) -> Unit {
  let codes = fn() {
    let out : Array[(Int, Int)] = []
    for ch in words() {
      if out.length() >= receipt_code_most {
        break
      }
      out.push((out.length(), ch.to_int()))
    }
    out
  }
  c.each(codes, fn(x) { x.0 }, style_of=fn(x) {
    let k = x.1
    let w = (k % 3 + 1).to_double()
    // (as far from the next as its code says: a point or two)
    let gap : @ui.Space = if k / 3 % 2 == 0 { SPx } else { S0_5 }
    receipt_bar.then(@ui.style(w=Fixed(w), mr=gap))
  }, fn(_, _) {  })
}

// ── 终端 ───────────────────────────────────────────────────────────────────

///|
/// A line of the fetch: `id` what it is (a kind, a model, a figure), its key (`key`: "" none, the line going on the one
/// before) and what it says.
#derive(Eq)
priv struct TermLine {
  id : String
  key : String
  words : String
}

///|
/// 终端: still.fail fetched in a terminal, as a system's fetch says what it runs on. Its window's dots and title; the
/// command; still.fail's mark large (its white face, the terminal being dark) beside who and when; a line a figure, its key in the code
/// face in the orange: each kind's tokens, the chats at work, the devices, the tasks across devices, the week's chats
/// archived, tokens and spend; the palette; the prompt again, its cursor.
fn terminal_look(c : Pen, fleet : () -> Json?, flat : Bool) -> Pen {
  // (its lines, each kept by what it is: a figure changed changes its words alone)
  let lines = fn() {
    let f = fleet()
    let out : Array[TermLine] = []
    for k, q in items(f, "spent") {
      let q = Some(q)
      // (its tokens and cost under it, as the tasks' average under them: on its line a long name was cut short)
      out.push({
        id: "kind \{k}",
        key: if k == 0 { "accounts" } else { "" },
        words: text(q, "name") + " ×" + count(q, "accounts").to_string(),
      })
      // its models under it, each its own tokens and cost
      for i, m in items(q, "models") {
        out.push({ id: "model \{k} \{i}", key: "", words: "  " + text(Some(m), "name") + " · " + text(Some(m), "lineText") })
      }
    }
    out.push({ id: "chats", key: "chats", words: text(f, "chatsText") })
    out.push({ id: "devices", key: "devices", words: text(f, "where") })
    if text(f, "tasksText") != "" {
      out.push({ id: "tasks", key: "tasks", words: text(f, "tasksText") })
      out.push({ id: "tasksPer", key: "", words: text(f, "tasksPer") })
    }
    for i, x in span_stats(field(f, "week")) {
      if i < term_week_keys.length() {
        out.push({ id: "week \{i}", key: term_week_keys[i], words: x.1 })
      }
    }
    out
  }
  look_box(c, flat, @sf.share_terminal_ground, fn(c) {
    c.box(style=term_bar, fn(c) {
      for _ in 0..<3 {
        c.box(style=term_dot, fn(_) {  }) |> ignore
      }
      c.box(style=pic_grow, fn(c) { code_words(c, fn() { "still.fail — zsh" }, term_title) }) |> ignore
    })
    |> ignore
    prompt(c, @sf.product() + " fetch")
    c.box(style=term_who, fn(c) {
      @sf.drawable_node(c.v, "stillfail_mark_dark", term_mark) |> ignore
      c.box(style=term_who_words, fn(c) {
        c.rich(
          [@ui.span("agents", mono=true, color=@sf.share_orange), @ui.span("@", mono=true), @ui.span(@sf.product(), mono=true, color=@sf.share_orange)],
          style=term_line_bold,
        )
        |> ignore
        c.box(style=term_rule, fn(_) {  }) |> ignore
        code_words(c, fn() { text(fleet(), "at") }, term_dim)
      })
      |> ignore
    })
    |> ignore
    c.box(style=term_block, fn(c) {
      c.each(lines, fn(l) { l.id }, style_of=fn(_) { term_key_row }, fn(c, l) {
        c.box(style=term_key_box, fn(c) { code_words(c, fn() { l().key }, term_key) }) |> ignore
        c.box(style=term_value_box, fn(c) { c.text_by(fn() { l().words }, style=term_value) }) |> ignore
      })
    })
    |> ignore
    // (a drawing of the terminal's colours, its swatches edge to edge as a terminal's palette shows them: read out as
    // one picture, its blocks what it draws, not the app's to stand apart)
    let palette = c.box(style=term_palette, fn(c) {
      for ink in @sf.share_terminal_palette {
        c.box(style=term_swatch.then(@ui.style(bg=Data(ink))), fn(_) {  }) |> ignore
      }
    })
    palette.says(Image, fn() { @sf.t("web-main.stations.sharePalette") })
    c.box(style=term_prompt_row, fn(c) {
      code_words(c, fn() { "~ $" }, term_prompt)
      c.box(style=term_cursor, fn(_) {  }) |> ignore
    })
    |> ignore
  })
}

///|
/// The keys of the week's figures, in their order (the chats archived, the tokens read, what was spent).
// kept across runs: a table, never written
let term_week_keys : Array[String] = ["archived", "tokens", "spent"]

///|
/// The prompt and what is typed after it.
fn prompt(c : Pen, command : String) -> Unit {
  c.rich(
    [@ui.span("~ ", mono=true, color=@sf.share_terminal_dim), @ui.span("$ ", mono=true, color=@sf.share_orange), @ui.span(command, mono=true)],
    style=term_line_bold,
  )
  |> ignore
}

///|
/// The set of looks shown in the strip, pressed while the card is open; "" none pressed: the chosen look's.
// kept across runs: put back as a run begins (share_looks_reset)
let share_group_shown : @signals.Signal[String] = @signals.signal("")

///|
fn share_looks_reset() -> Unit {
  share_group_shown.set("")
}

// ── the picker's styles ──────────────────────────────────────────────────

///|
/// The sets' names over the strip, 8 apart.
// kept across runs: a value (no field of it changes)
let groups_and_looks : @ui.Style = @ui.css("gap=S2 w=Full align=ACenter")






///|
/// The looks side by side, 8 apart (four in a 360 phone's stage), from the strip's start: what is past its end
/// scrolled to (34 of them since 千恋＊万花's), the chosen one brought into view.
// kept across runs: a value (no field of it changes)
let looks_row : @ui.Style = @ui.css("row gap=S2")

///|
/// A look: its small picture over its name, 6 apart, as wide as its name or its ring.
// kept across runs: a value (no field of it changes)
let looks_item : @ui.Style = @ui.css("gap=S1_5 align=ACenter")

///|
/// The ring round a small picture: none but the chosen one's (the white), as far out either way.
// kept across runs: a value (no field of it changes)
let looks_ring : @ui.Style = @ui.style(p=@sf.share_look_in, radius=@sf.share_look_ring, border=B1_5, border_color=Clear)

///|
// kept across runs: a value (no field of it changes)
let looks_ring_on : @ui.Style = looks_ring.then(@ui.style(border_color=Data(@sf.share_ink)))

///|
/// Its name: the white thinned, the white chosen or under the hand.
// kept across runs: a value (no field of it changes)
let looks_name : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(@sf.share_dim), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let looks_name_on : @ui.TextStyle = looks_name.then(@ui.text_style(color=Data(@sf.share_ink)))


// ── 大字报's ────────────────────────────────────────────────────────────────

///|
/// Its parts far apart (40), the number's group, the line's, the foot's; as tall as a portrait's three to four.
// kept across runs: a value (no field of it changes)
let poster_inner : @ui.Style = @ui.css("w=Full gap=S10 py=S3").then(@ui.style(min_h=@sf.share_poster_least_h))

///|
/// What is left of its height, between the line and the foot.
// kept across runs: a value (no field of it changes)
let poster_rest : @ui.Style = @ui.style(h=@sf.grow)

///|
/// What leads its number, the number, what it is of: one under another, tight.
// kept across runs: a value (no field of it changes)
let poster_hero : @ui.Style = @ui.css("w=Full gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let poster_words : @ui.TextStyle = @ui.text_style(size=Xl2, weight=Bold, color=Data(@sf.share_poster_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let poster_number : @ui.TextStyle = @ui.text_style(size=Xl7, weight=Bold, tracking=Tighter, color=Data(@sf.share_poster_ink), wrap=false)

///|
/// The line under the number: what it says large, where under it.
// kept across runs: a value (no field of it changes)
let poster_more : @ui.Style = @ui.css("w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let poster_big : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Bold, tracking=Tight, color=Data(@sf.share_poster_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let poster_small : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Data(@sf.share_poster_dim), w=Full)

///|
/// Its foot: still.fail large over its line and the time.
// kept across runs: a value (no field of it changes)
let poster_foot : @ui.Style = @ui.css("w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let poster_brand : @ui.TextStyle = @ui.text_style(size=Xl5, weight=Bold, tracking=Tighter, color=Data(@sf.share_poster_ink), wrap=false)

// ── 小票's ──────────────────────────────────────────────────────────────────

///|
/// Its head: still.fail over when, in its middle.
// kept across runs: a value (no field of it changes)
let receipt_head : @ui.Style = @ui.css("w=Full gap=S1 align=ACenter pt=S2")

///|
// kept across runs: a value (no field of it changes)
let receipt_brand : @ui.TextStyle = @ui.text_style(size=Xl2, weight=Bold, color=Data(@sf.share_receipt_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let receipt_dim : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(@sf.share_receipt_dim), wrap=false)

///|
/// A group of its items, 4 apart.
// kept across runs: a value (no field of it changes)
let receipt_items : @ui.Style = @ui.css("w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let receipt_title : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_receipt_ink), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let receipt_name : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(@sf.share_receipt_ink), w=Cut, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let receipt_line : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(@sf.share_receipt_dim), w=Cut, wrap=false)

///|
/// A kind's line: as far from the model over it as its models' lines are from each other (receipt_item's top), and
/// that again.
// kept across runs: a value (no field of it changes)
let receipt_kind : @ui.Style = @ui.css("w=Full pt=S2")

///|
/// The first kind's line: as far from the subtotals as a line is.
// kept across runs: a value (no field of it changes)
let receipt_kind_first : @ui.Style = @ui.css("w=Full")

///|
/// A kind's model, set in under its kind's line.
// kept across runs: a value (no field of it changes)
let receipt_model : @ui.Style = @ui.css("w=Full pl=S3")

///|
/// A day's date (today's in the orange).
// kept across runs: a value (no field of it changes)
let receipt_code_line : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(@sf.share_receipt_dim), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let receipt_today : @ui.TextStyle = receipt_code_line.then(@ui.text_style(weight=Bold, color=Data(@sf.share_receipt_orange)))

///|
// kept across runs: a value (no field of it changes)
let receipt_value : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_receipt_ink), wrap=false)

///|
/// Its total: large, in the ink.
// kept across runs: a value (no field of it changes)
let receipt_total : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Bold, color=Data(@sf.share_receipt_ink), wrap=false)

///|
/// A line of dashes: as many, as wide as the receipt shares them, 4 apart.
// kept across runs: a value (no field of it changes)
let receipt_dashes : @ui.Style = @ui.css("row w=Full gap=S1")

///|
let receipt_dash_count : Int = 30

///|
// kept across runs: a value (no field of it changes)
let receipt_dash : @ui.Style = @ui.style(w=@sf.grow, h=@sf.share_receipt_dash_h, bg=Data(@sf.share_receipt_rule))

///|
/// Two lines of dashes, 2 apart.
// kept across runs: a value (no field of it changes)
let receipt_double : @ui.Style = @ui.css("w=Full gap=S0_5")

///|
/// Its foot: the barcode over still.fail's line, in its middle.
// kept across runs: a value (no field of it changes)
let receipt_foot : @ui.Style = @ui.css("w=Full gap=S2 align=ACenter pt=S1")

///|
// kept across runs: a value (no field of it changes)
let receipt_code : @ui.Style = @ui.css("row h=S12 justify=JCenter")

///|
/// At most this many bars (the receipt's width holds them).
let receipt_code_most : Int = 64

///|
// kept across runs: a value (no field of it changes)
let receipt_bar : @ui.Style = @ui.style(h=Full, bg=Data(@sf.share_receipt_ink))

///|
// kept across runs: a value (no field of it changes)
let receipt_tagline : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(@sf.share_receipt_dim), wrap=false)

// ── 终端's ──────────────────────────────────────────────────────────────────

///|
/// Its window's bar: three dots 6 apart, its title after them.
// kept across runs: a value (no field of it changes)
let term_bar : @ui.Style = @ui.css("row w=Full gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let term_dot : @ui.Style = @ui.css("w=S2_5 h=S2_5 radius=Full").then(@ui.style(bg=Data(@sf.share_terminal_dot)))

///|
// kept across runs: a value (no field of it changes)
let term_title : @ui.TextStyle = @ui.text_style(size=Xs, color=Data(@sf.share_terminal_dim), wrap=false)

///|
/// still.fail's mark beside who and when, 16 apart, in the middle of each other's height.
// kept across runs: a value (no field of it changes)
let term_who : @ui.Style = @ui.css("row w=Full gap=S4 align=ACenter py=S2")

///|
/// The mark: still.fail's own face (design/brand), as tall as the who and when beside it with room to spare.
let term_mark : Double = 56.0

///|
// kept across runs: a value (no field of it changes)
let term_who_words : @ui.Style = @ui.css("gap=S1_5").then(@ui.style(w=@sf.grow))

///|
/// The rule under who it is, as a fetch draws it: the grey thinned.
// kept across runs: a value (no field of it changes)
let term_rule : @ui.Style = @ui.style(w=Full, h=@sf.share_receipt_dash_h, bg=Data(@sf.share_terminal_cell))

///|
/// Its lines, 6 apart.
// kept across runs: a value (no field of it changes)
let term_block : @ui.Style = @ui.css("w=Full gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let term_line_bold : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_terminal_ink), w=Full)

///|
// kept across runs: a value (no field of it changes)
let term_dim : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(@sf.share_terminal_dim), w=Full)

///|
/// A line: its key's column, what it is beside it, by their first lines.
// kept across runs: a value (no field of it changes)
let term_key_row : @ui.Style = @ui.css("row w=Full gap=S3 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let term_key_box : @ui.Style = @ui.style(w=@sf.share_terminal_key_w)

///|
// kept across runs: a value (no field of it changes)
let term_key : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_orange), wrap=false)

///|
/// What it is, taking the rest of the line.
// kept across runs: a value (no field of it changes)
let term_value_box : @ui.Style = @ui.css("row gap=S2 align=ACenter").then(@ui.style(w=@sf.grow))

///|
// kept across runs: a value (no field of it changes)
let term_value : @ui.TextStyle = @ui.text_style(size=Sm, color=Data(@sf.share_terminal_ink), w=Cut, wrap=false)

///|
/// The palette: its colours side by side, as wide as the line shares them, 16 high.
// kept across runs: a value (no field of it changes)
let term_palette : @ui.Style = @ui.css("row w=Full pt=S2")

///|
// kept across runs: a value (no field of it changes)
let term_swatch : @ui.Style = @ui.style(w=@sf.grow, h=@sf.share_terminal_cursor_h)

///|
// kept across runs: a value (no field of it changes)
let term_prompt : @ui.TextStyle = @ui.text_style(size=Sm, weight=Bold, color=Data(@sf.share_orange), wrap=false)

///|
/// The prompt at its end: its cursor after it, 6 apart.
// kept across runs: a value (no field of it changes)
let term_prompt_row : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
/// Its cursor: a block of the orange, as a terminal's.
// kept across runs: a value (no field of it changes)
let term_cursor : @ui.Style = @ui.style(w=@sf.share_terminal_cursor_w, h=@sf.share_terminal_cursor_h, bg=Data(@sf.share_orange))
