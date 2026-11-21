// What still.fail uses of a station's machine (resources.mbt's, as nodes of a page made once, from its styles): a
// station's page's 进程 and the line its overview says it in. What is chosen in it (whose, how, the column sorted by,
// the groups open) is rs_shown's, by station, followed as it changes. On its page each row of its table is a block of
// its own (a page's list makes a block only while it shows: a table of every process made one block was made whole as
// it came to show, 22 rows where 8 show): its head (what is counted, the choice of whose and how, the columns' heads)
// a block, each row a block (rs_block_node), how it is read a block under them; what they read worked out once for
// all of them, by its page (RsTable).

///|
/// Its 进程 (station_processes', online): what is counted over the page, then the body; nothing read yet, its bones.
/// `table`: its page's, whose blocks its rows and its foot are (rs_block_node); none, all of it here.
fn resources_node(p : @view.View, core : Core, here : () -> Here, address : String, table? : RsTable) -> Unit {
  let v = fn() { station_part_read(core, address, resources_ask(here(), address)).value }
  p.box(fn(k) {
    @sf.style_node(k, fn() { rs_processes })
    @sf.words_node(k, fn() { @sf.t("web-pages.stations.processesLead") }, fn() { st_memory }) |> ignore
    k.pick(fn() { v() is Some(Object(_)) }, fn(b, read) {
      if read {
        resources_body_node(b, core, address, v, table?)
      } else {
        @sf.waiting_node(b, fn(w) {
          @sf.style_node(w, fn() { rs_page })
          rs_figures_node(w, core.quiet(), "sample", fn() { Some(rs_sample_view()) })
        })
      }
    })
  })
  |> ignore
}

///|
/// What a body (resources_body's) shows by what is read `v`: 0, seen; 1, nothing yet, read; 2, nothing to see.
fn rs_state(v : Json?) -> Int {
  if !flag(v, "empty") {
    0
  } else {
    let wait = field(v, "wait")
    if flag(wait, "reading") || items(wait, "failing").length() > 0 { 1 } else { 2 }
  }
}

///|
/// The body (resources_body's): empty, a wait (or that there is nothing to see); else its totals, the choice of whose
/// and of how, the table; how it is read under either (where its page has its rows and foot its blocks, `table`, that
/// is one of them).
fn resources_body_node(b : @view.View, core : Core, address : String, v : () -> Json?, table? : RsTable) -> Unit {
  b.pick(fn() { rs_state(v()) }, fn(r, k) {
    @sf.style_node(r, fn() { rs_page })
    match k {
      0 => rs_figures_node(r, core, address, v, table?)
      1 => @sf.waiting_node(r, fn(w) { rs_figures_node(w, core.quiet(), "sample", fn() { Some(rs_sample_view()) }) })
      _ => @sf.words_node(r, fn() { @sf.t("web-main.resources.none") }, fn() { rs_empty }) |> ignore
    }
    if table is None {
      rs_foot_node(r, v, k == 0)
    }
  })
}

///|
/// What is seen of the machine (rs_figures_of's): its totals in pairs, the choice of whose and of how on a line apart
/// at its ends, the table (where its page has its rows blocks of their own, `table`, its heads alone).
fn rs_figures_node(r : @view.View, core : Core, address : String, v : () -> Json?, table? : RsTable) -> Unit {
  // (what is counted, and each tile, worked out once as the value changes: a sample that leaves a tile as it was tells
  // none of what that tile draws)
  let tiles_now = @signals.computed(fn(_) { items(v(), "tiles") }, same=fn(a, b) { a == b })
  let tiles = fn() { tiles_now.get() }
  r.box(fn(ts) {
    @sf.style_node(ts, fn() { rs_tiles })
    ts.wraps(Is(Some(rs_flow_lines))) |> ignore
    ts.each(fn() { Array::makei((tiles().length() + 1) / 2, fn(k) { k }) }, fn(k) { k }, fn(pair, k) {
      let k = k.untracked()
      @sf.style_node(pair, fn() { rs_tile_pair }, in_row=true)
      // (never narrower than its tiles at their least, so a pair without the room on its line goes under the other)
      pair
      .shrink(Is(0.0))
      .min_width(By(fn() {
        let n = @cmp.minimum(2, tiles().length() - k * 2).to_double()
        Some(n * rs_tile_least + dmax(n - 1.0, 0.0) * rs_tile_gap)
      }))
      |> ignore
      for i in (k * 2)..<(k * 2 + 2) {
        pair.show(fn() { i < tiles().length() }, fn(t) {
          // (as wide as a tile is at least, so a pair that has not the room on its line goes under the other: rs_tile_box's)
          t.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(rs_tile_least))) |> ignore
          let tile = @signals.computed(fn(_) { tiles().get(i) }, same=fn(a, b) { a == b })
          rs_tile_node(t, fn() { tile.get() })
        })
      }
    })
  })
  |> ignore
  let shown = fn() { rs_shown_of(address) }
  r.box(fn(bar) {
    @sf.style_node(bar, fn() { rs_bar })
    bar.wraps(Is(Some(rs_flow_lines))) |> ignore
    let keys = fn() { ["all"] + items(v(), "kinds").map(fn(k) { text(Some(k), "key") }) }
    bar.box(fn(slot) {
      @sf.segmented_node(
        slot,
        fn() { [@sf.t("web-main.resources.all")] + items(v(), "kinds").map(fn(k) { text(Some(k), "label") }) },
        fn() { keys().search(shown().kind).unwrap_or(0) },
        fn(i) {
          match keys().get(i) {
            Some(kind) => rs_shown[address] = { ..rs_shown_of(address), kind: kind }
            None => ()
          }
        },
      )
    })
    |> ignore
    bar.box(fn(slot) {
      @sf.segmented_node(
        slot,
        fn() { [@sf.t("web-main.resources.grouped"), @sf.t("web-main.resources.flat")] },
        fn() { if shown().flat { 1 } else { 0 } },
        fn(i) { rs_shown[address] = { ..rs_shown_of(address), flat: i == 1 } },
      )
    })
    |> ignore
  })
  |> ignore
  match table {
    // (its rows blocks of their own: its heads alone here, laid out as its rows are, rs_block_node)
    Some(t) =>
      r.pick(fn() { shown().flat }, fn(tt, flat) {
        tt.by_room(fn(heads, room) {
          @sf.style_node(heads, fn() { rs_table })
          let lay = rs_lay_in(heads, room, t.lay_at)
          rs_heads_node(heads, address, flat, t.columns, lay)
        })
        |> ignore
      })
    None => {
      let groups = rs_groups_of(address, v)
      let columns_now = @signals.computed(fn(_) { rs_columns_of(v()) }, same=fn(a, b) { a == b })
      let columns = fn() { columns_now.get() }
      r.pick(fn() { shown().flat }, fn(t, flat) { rs_table_node(t, core, address, groups, columns, flat) })
    }
  }
}

///|
/// The groups of what is read `v` of station `address` of the kind of whose shown, worked out once as either changes.
fn rs_groups_of(address : String, v : () -> Json?) -> () -> Array[Json] {
  let groups_now = @signals.computed(
    fn(_) {
      let kind = rs_shown_of(address).kind
      items(v(), "groups").filter(fn(g) { kind == "all" || text(Some(g), "kind") == kind })
    },
    same=fn(a, b) { a == b },
  )
  fn() { groups_now.get() }
}

///|
/// A total, said, with the last minutes' line under it (rs_tile's), the line as wide as the tile is laid out.
fn rs_tile_node(t : @view.View, tv : () -> Json?) -> Unit {
  t.box(fn(b) {
    @sf.style_node(b, fn() { rs_tile_box })
    b.box(fn(h) {
      @sf.style_node(h, fn() { rs_tile_head })
      @sf.words_node(h, fn() { text(tv(), "label") }, fn() { rs_tile_label }) |> ignore
      @sf.words_node(h, fn() { text(tv(), "sub") }, fn() { rs_tile_sub }) |> ignore
    })
    |> ignore
    @sf.words_node(b, fn() { text(tv(), "value") }, fn() { rs_tile_value }) |> ignore
    b.box(fn(s) {
      @sf.style_node(s, fn() { rs_spark })
      // (drawn across the room it is given)
      s.by_room(fn(line, room) {
        line
        .height(Is(Some(rs_spark_h)))
        .shapes(By(fn() {
          let w = room.width()
          if w > 0.0 {
            rs_spark_shapes(number_list(tv(), "points"), w, rs_spark_ink(text(tv(), "key")))
          } else {
            []
          }
        }))
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A row of the table (rs_grouped's, rs_flat's), by what it is: a group (its key), a process under its group (the
/// group's key and its), a process flat (its group's key and its).
#derive(Eq, Hash)
priv enum RsRow {
  RsGroup(String)
  RsUnder(String, String)
  RsFlat(String, String)
}

///|
/// What a table of station `address`'s 进程 reads of its `groups`, laid out `flat` or not, worked out once (rs_table_node's,
/// and its page's for its rows' blocks, RsTable): the column sorted by, a group and a process by key, the most of the
/// sorted column, its rows in order.
priv struct RsRead {
  by : () -> String
  group_of : (String) -> Json?
  process_of : (String, String) -> Json?
  most : () -> Double
  rows : () -> Array[RsRow]
}

///|
/// RsRead's of `groups` of station `address`, laid out as `flat` says (rs_table_node's: as it was made; its page's: as
/// it is shown now).
fn rs_read(address : String, groups : () -> Array[Json], flat : () -> Bool) -> RsRead {
  let by = fn() { rs_shown_of(address).by }
  let group_of = fn(key : String) { groups().iter().find_first(fn(g) { text(Some(g), "key") == key }) }
  let process_of = fn(gkey : String, key : String) {
    items(group_of(gkey), "processes").iter().find_first(fn(p) { text(Some(p), "key") == key })
  }
  let use_of = fn(j : Json?) { rs_use(field(j, "use"), by()) }
  let most_now = @signals.computed(fn(_) {
    if flat() {
      groups().fold(init=0.0, fn(m, g) { items(Some(g), "processes").fold(init=m, fn(m, p) { @cmp.maximum(m, use_of(Some(p))) }) })
    } else {
      groups().fold(init=0.0, fn(m, g) { @cmp.maximum(m, use_of(Some(g))) })
    }
  }, same=fn(a, b) { a == b })
  // (which rows there are and in what order, worked out once as the groups or what is chosen change: a sample that
  // sorts them as they were tells the list nothing)
  let rows_now = @signals.computed(fn(_) {
    let out : Array[RsRow] = []
    if flat() {
      let all : Array[(Json, String)] = []
      for g in groups() {
        for p in items(Some(g), "processes") {
          all.push((p, text(Some(g), "key")))
        }
      }
      all.sort_by(fn(a, b) { use_of(Some(b.0)).compare(use_of(Some(a.0))) })
      for r in all {
        out.push(RsFlat(r.1, text(Some(r.0), "key")))
      }
    } else {
      let shown = rs_shown_of(address)
      let gs = groups()
      let sorted = gs.copy()
      sorted.sort_by(fn(a, b) { use_of(Some(b)).compare(use_of(Some(a))) })
      for g in sorted {
        let key = text(Some(g), "key")
        out.push(RsGroup(key))
        if rs_open(shown, gs, key) {
          let ps = items(Some(g), "processes").copy()
          ps.sort_by(fn(a, b) { use_of(Some(b)).compare(use_of(Some(a))) })
          for p in ps {
            out.push(RsUnder(key, text(Some(p), "key")))
          }
        }
      }
    }
    out
  }, same=fn(a, b) { a == b })
  { by, group_of, process_of, most: fn() { most_now.get() }, rows: fn() { rows_now.get() } }
}

///|
/// How a table of `groups` with `columns` is laid out (rs_layout_of's) by the room it is given and the sizes of its heads'
/// and figures' words, as `by` and `flat` say: worked out once for all that ask it of the same (each row of its page's
/// blocks laid out by its own room, of one width), again as any of it changes.
fn rs_lay_memo(
  groups : () -> Array[Json],
  columns : () -> Array[(String, String)],
  by : () -> String,
  flat : () -> Bool,
) -> (Double, Double, Double) -> RsLayout {
  let kept : Ref[(Double, Double, Double, Array[Json], Array[(String, String)], String, Bool, RsLayout)?] = Ref(None)
  fn(w, head, figure) {
    let gs = groups()
    let cols = columns()
    let b = by()
    let f = flat()
    match kept.val {
      Some(k) if k.0 == w && k.1 == head && k.2 == figure && physical_equal(k.3, gs) && physical_equal(k.4, cols) && k.5 == b && k.6 == f =>
        k.7
      _ => {
        // (every figure it says, a group's processes' too, open or not: none moves as a group opens)
        let figures : Array[(Json?, Bool)] = []
        for g in gs {
          if !f {
            figures.push((field(Some(g), "use"), true))
          }
          for p in items(Some(g), "processes") {
            figures.push((field(Some(p), "use"), f))
          }
        }
        let lay = rs_layout_of(w, head, figure, figures, cols, b, if f { 2 } else { 1 })
        kept.val = Some((w, head, figure, gs, cols, b, f, lay))
        lay
      }
    }
  }
}

///|
/// The layout a table's part laid out in node `t` by `room` reads (rs_lay_memo's `lay_at`), its words as `t` draws them.
fn rs_lay_in(t : @view.View, room : @view.Room, lay_at : (Double, Double, Double) -> RsLayout) -> () -> RsLayout {
  let lay = @signals.computed(fn(_) {
    let th = @ui.tree_theme()
    lay_at(room.width(), @sf.node_sp(t, th.text_size(Xs).0), @sf.node_sp(t, th.text_size(Sm).0))
  }, same=fn(a, b) { a == b })
  fn() { lay.get() }
}

///|
/// The table (rs_grouped's, `flat` rs_flat's): its heads, then its rows, the most of the column sorted by first; laid
/// out by how wide it is given to be (rs_layout_of, by its room: View::by_room).
fn rs_table_node(
  t : @view.View,
  core : Core,
  address : String,
  groups : () -> Array[Json],
  columns : () -> Array[(String, String)],
  flat : Bool,
) -> Unit {
  let read = rs_read(address, groups, fn() { flat })
  let lay_at = rs_lay_memo(groups, columns, read.by, fn() { flat })
  // (its heads and rows by how wide it is given to be, laid out in that same layout)
  t.by_room(fn(table, room) {
    // (read out as a table (@sf.grid_table_node): its heads' row and its rows, the node each is drawn by)
    @sf.grid_table_node(table, in_node=true, fn(table, tb) {
      @sf.style_node(table, fn() { rs_table })
      let lay = rs_lay_in(table, room, lay_at)
      rs_heads_node(table, address, flat, columns, lay, tb~)
      table.each(read.rows, fn(r) { r }, fn(row, r) {
        rs_row_of(row, core, address, read, groups, columns, lay, r.untracked(), tb~)
      })
    })
    |> ignore
  })
  |> ignore
}

///|
/// Row `r` of a table of station `address`'s 进程 (rs_table_node's, or a block of its page's: rs_block_node) in `row`,
/// as `read` reads its `groups` and `columns`, laid out as `lay` says; read out a row of `tb` where it is one of its
/// rows (a group's row a button that opens it, as ever).
fn rs_row_of(
  row : @view.View,
  core : Core,
  address : String,
  read : RsRead,
  groups : () -> Array[Json],
  columns : () -> Array[(String, String)],
  lay : () -> RsLayout,
  r : RsRow,
  tb? : @sf.GridTable,
) -> Unit {
  match (tb, r) {
    (Some(_), RsGroup(_)) | (None, _) => ()
    (Some(tb), _) => tb.row(row, in_node=true, fn(_, _) {  }) |> ignore
  }
  let by = read.by
  let most = read.most
  let group_of = read.group_of
  let process_of = read.process_of
  match r {
    RsGroup(key) => {
      // (its group as the groups say it now, told only as it changes: a sample that leaves it as it was tells this
      // row nothing)
      let g_now = @signals.computed(fn(_) { group_of(key) }, same=fn(a, b) { a == b })
      let g = fn() { g_now.get() }
      let on = fn() { rs_open(rs_shown_of(address), groups(), key) }
      rs_row_node(
        row,
        lay,
        opens=(fn() { text(g(), "title") }, on, fn() { rs_open_or_shut(address, groups(), key) }),
        fn(n) {
          n.box(fn(cell) {
            @sf.style_node(cell, fn() { rs_name_cell }, in_row=true)
            cell.box(fn(name) {
              @sf.style_node(name, fn() { rs_name })
              @sf.icon_node(
                name,
                if @signals.untracked(on) { "chevron-down" } else { "chevron-right" },
                rs_toggle,
                By(fn() { @sf.theme().p.subtle }),
                name_now=fn() { if on() { "chevron-down" } else { "chevron-right" } },
              )
              |> ignore
              rs_title_node(name, core, g, rs_name_text)
              @sf.words_node(
                name,
                fn() { join([text(g(), "kindText"), items(g(), "processes").length().to_string()], " · ") },
                fn() { rs_meta },
              )
              |> ignore
            })
            |> ignore
          })
          |> ignore
        },
        fn(f) { rs_figures_node_of(f, fn() { field(g(), "use") }, columns, by, most, lay, false) },
        fn(_) {  },
      )
    }
    RsUnder(gkey, key) => {
      let p_now = @signals.computed(fn(_) { process_of(gkey, key) }, same=fn(a, b) { a == b })
      let p = fn() { p_now.get() }
      rs_row_node(
        row,
        lay,
        fn(n) {
          n.box(fn(cell) {
            @sf.style_node(cell, fn() { rs_process_cell }, in_row=true)
            @sf.words_node(cell, fn() { text(p(), "name") }, fn() { rs_process_name }) |> ignore
            @sf.words_node(cell, fn() { number(p(), "pid").to_int().to_string() }, fn() { rs_meta }) |> ignore
          })
          |> ignore
        },
        fn(f) { rs_figures_node_of(f, fn() { field(p(), "use") }, columns, by, most, lay, true) },
        fn(e) { rs_end_node(e, core, p, fn() { group_of(gkey) }, row) },
      )
    }
    RsFlat(gkey, key) => {
      let p_now = @signals.computed(fn(_) { process_of(gkey, key) }, same=fn(a, b) { a == b })
      let p = fn() { p_now.get() }
      let g_now = @signals.computed(fn(_) { group_of(gkey) }, same=fn(a, b) { a == b })
      let g = fn() { g_now.get() }
      rs_row_node(
        row,
        lay,
        fn(n) {
          n.box(fn(cell) {
            @sf.style_node(cell, fn() { rs_name_cell }, in_row=true)
            cell.box(fn(name) {
              @sf.style_node(name, fn() { rs_name })
              @sf.words_node(name, fn() { text(p(), "name") }, fn() { rs_cell_words }) |> ignore
              @sf.words_node(name, fn() { number(p(), "pid").to_int().to_string() }, fn() { rs_meta }) |> ignore
            })
            |> ignore
          })
          |> ignore
          n.box(fn(cell) {
            @sf.style_node(cell, fn() { rs_whose_cell }, in_row=true)
            rs_title_node(cell, core, g, rs_whose)
          })
          |> ignore
        },
        fn(f) { rs_figures_node_of(f, fn() { field(p(), "use") }, columns, by, most, lay, false) },
        fn(e) { rs_end_node(e, core, p, g, row) },
      )
    }
  }
}

///|
/// A station's 进程 as its page reads it, worked out once for its blocks (its head's heads, each row a block, its foot:
/// rs_block_keys, rs_block_node), held by its page as long as it is: what is read, what the body shows (rs_state's; -1
/// none read yet), the groups of the kind shown, the columns, whether flat, its rows, how it is laid out by width.
priv struct RsTable {
  v : () -> Json?
  state : () -> Int
  groups : () -> Array[Json]
  columns : () -> Array[(String, String)]
  read : RsRead
  lay_at : (Double, Double, Double) -> RsLayout
}

///|
/// Station `address`'s 进程 as its page reads it (RsTable), made as the page is: nothing read till a block reads it.
fn rs_table_of(core : Core, here : () -> Here, address : String) -> RsTable {
  let v = fn() { station_part_read(core, address, resources_ask(here(), address)).value }
  let groups = rs_groups_of(address, v)
  let columns_now = @signals.computed(fn(_) { rs_columns_of(v()) }, same=fn(a, b) { a == b })
  let columns = fn() { columns_now.get() }
  let flat = fn() { rs_shown_of(address).flat }
  let read = rs_read(address, groups, flat)
  {
    v,
    state: fn() { if v() is Some(Object(_)) { rs_state(v()) } else { -1 } },
    groups,
    columns,
    read,
    lay_at: rs_lay_memo(groups, columns, read.by, flat),
  }
}

///|
/// Its 进程's blocks under its head (`table`, the station `online`): each row of its table while it is seen, how it is
/// read once something is ("processes/foot").
fn rs_block_keys(table : RsTable, online : Bool) -> Array[String] {
  guard online else { return [] }
  let state = (table.state)()
  let out : Array[String] = []
  if state == 0 {
    for r in (table.read.rows)() {
      out.push(rs_row_key(r))
    }
  }
  if state >= 0 {
    out.push(rs_foot_key)
  }
  out
}

///|
/// Its 进程's foot's block's key (rs_block_keys').
let rs_foot_key : String = "processes/foot"

///|
/// The block's key of row `r` of its 进程's table: what it is and its keys, apart by a character no key holds.
fn rs_row_key(r : RsRow) -> String {
  match r {
    RsGroup(k) => "processes/g\u{0}" + k
    RsUnder(g, k) => "processes/u\u{0}" + g + "\u{0}" + k
    RsFlat(g, k) => "processes/f\u{0}" + g + "\u{0}" + k
  }
}

///|
/// The row a block's key (rs_row_key's) is of, none where it is no row's.
fn rs_row_of_key(key : String) -> RsRow? {
  let parts : Array[String] = key.split("\u{0}").map(fn(p) { p.to_owned() }).collect()
  match parts {
    ["processes/g", k] => Some(RsGroup(k))
    ["processes/u", g, k] => Some(RsUnder(g, k))
    ["processes/f", g, k] => Some(RsFlat(g, k))
    _ => None
  }
}

///|
/// Block `key` of its 进程 (rs_block_keys') in `b`, as `table` reads it now: a row of its table, laid out as its heads
/// are, by its own room (of their width); how it is read, as far under what is over it as its body's parts are apart.
fn rs_block_node(b : @view.View, core : Core, address : String, table : RsTable, key : String) -> Unit {
  if key == rs_foot_key {
    b.pick(table.state, fn(f, k) {
      if k >= 0 {
        f.box(fn(x) {
          x.padding(Is((0.0, rs_page_gap, 0.0, 0.0))) |> ignore
          rs_foot_node(x, table.v, k == 0)
        })
        |> ignore
      }
    })
    return
  }
  guard rs_row_of_key(key) is Some(r) else { return }
  b.by_room(fn(t, room) {
    @sf.style_node(t, fn() { rs_table })
    let lay = rs_lay_in(t, room, table.lay_at)
    t.box(fn(row) { rs_row_of(row, core, address, table.read, table.groups, table.columns, lay, r) }) |> ignore
  })
  |> ignore
}

///|
/// The body's parts apart (rs_page's gap=S3_5): its foot under its table's last row so.
let rs_page_gap : Double = @ui.Space::S3_5.px()


///|
/// A row's end (rs_end_node's, or nothing for a group's) in its cell, in `parent`.
fn rs_end_cell_node(parent : @view.View, end : (@view.View) -> Unit) -> Unit {
  parent.box(fn(e) {
    @sf.style_node(e, fn() { rs_end_cell }, in_row=true)
    end(e)
  })
  |> ignore
}

///|
/// A row of the table (rs_table_row's, rs_line's) in `row`: its names, its figures and its end on one line; stacked,
/// its names on a line of their own with its end, and its figures under them; a row's least height at least.
/// `opens`: a group's, what it is called, whether it is open, and what pressing it does: the row a button that opens
/// and shuts it (read out expanded while it is open), lit under the pointer.
fn rs_row_node(
  row : @view.View,
  lay : () -> RsLayout,
  opens? : (() -> String, () -> Bool, () -> Unit),
  names : (@view.View) -> Unit,
  figures : (@view.View) -> Unit,
  end : (@view.View) -> Unit,
) -> Unit {
  match opens {
    Some((label, open, press)) => {
      @sf.style_node(row, fn() { rs_table })
      @sf.action_box_node(row, label, expanded=open, fn(_) { press() }, fn(b) {
        rs_row_body(b, lay, names, figures, end)
        // (round, a list's row's: never a square patch standing in from the pane's sides, the corner rule's lit square)
        b.radius(Is(@sf.row_corner)) |> ignore
        @sf.hover_ground_node(b)
      })
      |> ignore
    }
    None => rs_row_body(row, lay, names, figures, end)
  }
}

///|
/// What a row of the table (rs_row_node's) is in `row`: its names, figures and end as the layout has them.
fn rs_row_body(
  row : @view.View,
  lay : () -> RsLayout,
  names : (@view.View) -> Unit,
  figures : (@view.View) -> Unit,
  end : (@view.View) -> Unit,
) -> Unit {
  @sf.style_node(row, fn() { rs_row.then(@sf.row_least_h()) })
  row.pick(fn() { lay().stacked }, fn(r, stacked) {
    r.row(Is(true)).grow(Is(1.0)).basis(Is(Some(0.0))).lines_up(Is(Some(Middle))) |> ignore
    if stacked {
      r.box(fn(s) {
        @sf.style_node(s, fn() { rs_stack }, in_row=true)
        // (its end on its names' line, centred on that line and not on both: what stands beside a block of lines
        // sits on its first, apps/mbui/AGENTS.md)
        s.box(fn(n) {
          @sf.style_node(n, fn() { rs_row })
          names(n)
          rs_end_cell_node(n, end)
        })
        |> ignore
        s.box(fn(f) {
          @sf.style_node(f, fn() { rs_figures_line })
          figures(f)
        })
        |> ignore
      })
      |> ignore
    } else {
      names(r)
      figures(r)
      rs_end_cell_node(r, end)
    }
  })
}

///|
/// The columns' heads (rs_heads'): the names' first (none stacked: the names have a line of their own), then each
/// column's, sorting by itself as it is pressed, lit under the pointer; the end's room. Read out the head's row of `tb`
/// where it is its table's, the names' heads naming their columns (the columns' each a button that sorts by it).
fn rs_heads_node(
  table : @view.View,
  address : String,
  flat : Bool,
  columns : () -> Array[(String, String)],
  lay : () -> RsLayout,
  tb? : @sf.GridTable,
) -> Unit {
  let row = fn(make : (@view.View, @sf.GridRow?) -> Unit) {
    match tb {
      Some(tb) => tb.row(table, fn(h, tr) { make(h, Some(tr)) })
      None => table.box(fn(h) { make(h, None) })
    }
  }
  row(fn(h, tr) {
    @sf.style_node(h, fn() { (if lay().stacked { rs_head_row_stacked } else { rs_head_row }).then(@sf.row_least_h()) })
    h.show(fn() { !lay().stacked }, fn(first) {
      first.row(Is(true)).grow(Is(1.0)).basis(Is(Some(0.0))) |> ignore
      let heads = if flat {
        ["web-main.resources.column.process", "web-main.resources.column.whose"]
      } else {
        ["web-main.resources.column.name"]
      }
      for i, key in heads {
        let look = fn(cell : @view.View) {
          @sf.style_node(cell, fn() { if i == 0 { rs_name_cell } else { rs_whose_cell } }, in_row=true)
          @sf.words_node(cell, fn() { @sf.t(key) }, fn() { rs_head }) |> ignore
        }
        match tr {
          Some(tr) => tr.head(first, look) |> ignore
          None => first.box(look) |> ignore
        }
      }
    })
    h.each(fn() { columns().mapi(fn(k, col) { (k, col.0) }) }, fn(c) { c.1 }, fn(cell, c) {
      let col = c.untracked().1
      let k = fn() { c.get().0 }
      let on = fn() { rs_shown_of(address).by == col }
      let name = fn() { @sf.t("web-main.resources.column." + col) }
      // (its cell as wide as its column, the head pressed in it as wide)
      @sf.style_node(cell, fn() { rs_column_room(lay(), k()) }, in_row=true)
      @sf.action_box_node(
        cell,
        fn() { @sf.t("web-main.resources.by", args=[("column", name())]) },
        fn(_) { rs_shown[address] = { ..rs_shown_of(address), by: col } },
        fn(b) {
          @sf.style_node(b, fn() { rs_column(lay(), k()).then(rs_head_pressed) })
          @sf.words_node(b, fn() { if on() { name() + " ↓" } else { name() } }, fn() {
            if on() || @sf.lit_node(b) {
              rs_head_on
            } else {
              rs_head
            }
          })
          |> ignore
        },
      )
      |> ignore
    })
    h.box(fn(e) { @sf.style_node(e, fn() { rs_end_cell }, in_row=true) }) |> ignore
  })
  |> ignore
}

///|
/// A row's figures (rs_figures'), each in its column: the sorted column's bold, with how much of the most it is
/// before it where the layout has room for it; `plain`, none so.
fn rs_figures_node_of(
  f : @view.View,
  u : () -> Json?,
  columns : () -> Array[(String, String)],
  by : () -> String,
  most : () -> Double,
  lay : () -> RsLayout,
  plain : Bool,
) -> Unit {
  f.each(fn() { columns().mapi(fn(k, col) { (k, col) }) }, fn(c) { c.1.0 }, fn(cell, c) {
    let key = c.untracked().1.0
    let strong = fn() { !plain && key == by() }
    let shared = fn() { strong() && lay().share }
    @sf.style_node(cell, fn() { rs_column(lay(), c.get().0, under=lay().stacked, shared=shared()) }, in_row=true)
    cell.show(shared, fn(s) {
      // (the room the figure leaves, the share at its start: rs_number_shared's JBetween, the share at the cell's start
      // and the figure at its end)
      s.grow(Is(1.0)) |> ignore
      let part = fn() {
        let m = most()
        if m > 0.0 { @cmp.minimum(1.0, rs_use(u(), by()) / m) } else { 0.0 }
      }
      s.box(fn(bar) {
        @sf.style_node(bar, fn() { rs_share }, in_row=true)
        bar.box(fn(x) {
          @sf.style_node(x, fn() { rs_share_fill }, in_row=true)
          x.grow(By(part)).basis(Is(Some(0.0))) |> ignore
        })
        |> ignore
        bar.box(fn(x) { x.grow(By(fn() { 1.0 - part() })).basis(Is(Some(0.0))) |> ignore }) |> ignore
      })
      |> ignore
    })
    @sf.words_node(cell, fn() { text(u(), c.get().1.1) }, fn() { if strong() { rs_figure_strong } else { rs_figure } })
    |> ignore
  })
}

///|
/// Whose a row is (rs_title's): a chat's, its chat opened from its title, underlined under the pointer, cut short where
/// its row has less room; a station's own group has the station mark after its title.
fn rs_title_node(p : @view.View, core : Core, g : () -> Json?, style : @ui.TextStyle) -> Unit {
  let chat = fn() { field(g(), "chat") }
  let session = fn() { text(chat(), "session") }
  p.box(fn(title) {
    title.row(Is(true)).gap(Is(@ui.Space::S1.px())).lines_up(Is(Some(Middle))).cuts(Is(true)).min_width(Is(Some(0.0))) |> ignore
    title.pick(fn() { chat() is Some(Object(_)) && session() != "" }, fn(x, link) {
      x.cuts(Is(true)).min_width(Is(Some(0.0))) |> ignore
      if link {
        @sf.presses_node(x, fn() { (core.open_chat)(text(chat(), "station"), session(), text(g(), "title")) })
        x.says(By(fn() { Some(@view.said(Link, label=text(g(), "title"))) })) |> ignore
        x.box(fn(w) {
          w
          .words_runs(By(fn() { [@ui.span(text(g(), "title"), underline=@sf.lit_node(x))] }))
          .words_look(Is(@ui.style_words(style)))
          .ink(By(fn() { @ui.style_ink(style) }))
          .cuts(Is(true))
          .min_width(Is(Some(0.0)))
          .allow_ellipsis(Is(true))
          |> ignore
        })
        |> ignore
      } else {
        @sf.words_node(x, fn() { text(g(), "title") }, fn() { style }) |> ignore
      }
    })
    title.show(fn() { text(g(), "kind") == "station" }, fn(mark) {
      @sf.icon_node(mark, "server", 14.0, By(fn() { @sf.theme().p.muted })) |> ignore
    })
  })
  |> ignore
}

///|
/// Its row's end (rs_end's): a way to end the process where it may be ended, asked first: a stop of its own for the
/// keyboard (Tab reaches it, no row taking the focus), said by what it ends (结束 …); seen as its row is pointed at or
/// it has the focus (clear till then), always where the hand is a finger (more_held: no pointer hovers).
fn rs_end_node(e : @view.View, core : Core, p : () -> Json?, g : () -> Json?, row : @view.View) -> Unit {
  e.show(fn() { flag(p(), "endable") }, fn(x) {
    let name = fn() { text(p(), "name") }
    let b = @sf.icon_button_node(x, "stop", fn() { @sf.t("web-main.resources.endLabel", args=[("name", name())]) }, fn() {
      let name = name()
      let pid = number(p(), "pid")
      let gv = g()
      @sf.confirm(
        @sf.t("web-main.resources.endTitle", args=[("name", name), ("pid", pid.to_int().to_string())]),
        @sf.t("web-main.resources.endBody", args=[("chat", text(gv, "title"))]),
        @sf.t("web-main.resources.end"),
        danger=true,
        fn() { rs_end_now(core, gv, pid, name) },
      )
    }, size=rs_end_size)
    x.alpha(By(fn() { if @sf.more_held() || @sf.lit_in_node(row) || @sf.lit_node(b) { 1.0 } else { 0.0 } })) |> ignore
  })
}

///|
/// How it is read, what is missing, how it is counted (rs_foot's).
fn rs_foot_node(r : @view.View, v : () -> Json?, basis : Bool) -> Unit {
  r.box(fn(f) {
    @sf.style_node(f, fn() { rs_foot_box })
    f.show(fn() { number(v(), "everyMs") > 0.0 }, fn(x) {
      @sf.words_node(
        x,
        fn() { @sf.t("web-main.resources.every", args=[("n", (number(v(), "everyMs") / 1000.0).round().to_int().to_string())]) },
        fn() { rs_foot_words },
      )
      |> ignore
    })
    let notes = fn() {
      items(v(), "notes").filter_map(fn(n) {
        match n {
          String(w) => Some(w)
          _ => None
        }
      })
    }
    f.each(fn() { notes().mapi(fn(i, _) { i }) }, fn(i) { i }, fn(x, i) {
      let i = i.untracked()
      @sf.words_node(x, fn() { notes().get(i).unwrap_or("") }, fn() { rs_foot_words }) |> ignore
    })
    if basis {
      @sf.words_node(f, fn() { text(v(), "basis") }, fn() { rs_foot_words }) |> ignore
    }
  })
  |> ignore
}

///|
/// What still.fail uses of the machine (station_uses'): a quiet line, the whole of it opening its 进程; its name beside
/// its figures where the line has the room for all of them, else over them; the network's figure where the station
/// reads it. Pressed, `processes` (its page's choice's press of 进程).
fn station_uses_node(p : @view.View, uv : () -> Json?, processes : () -> Unit) -> Unit {
  let name = fn() { @sf.t("web-pages.stations.uses", args=[("name", @sf.product())]) }
  p.box(fn(b) {
    @sf.style_node(b, fn() { rs_uses })
    @sf.presses_node(b, processes)
    b.says(By(fn() { Some(@view.said(Link, label=name())) })) |> ignore
    let lit = fn() { @sf.lit_node(b) }
    // (its figures worked out once a sample, both ways of the line reading them: as they were where the sample
    // changed none of them)
    let shown = @signals.computed(fn(_) {
      let u = field(uv(), "use")
      (text(u, "cpuText"), text(u, "memoryText"), text(u, "netText"), flag(uv(), "net"))
    }, same=fn(a, b) { a == b })
    let figures = fn(f : @view.View) {
      let figure = fn(label : () -> String, value : () -> String) {
        f.box(fn(w) {
          w
          .words_runs(By(fn() { [@ui.span(label() + " "), @ui.span(value(), weight=500, color=@sf.theme().p.text)] }))
          .words_look(Is(@ui.style_words(rs_uses_words)))
          .ink(By(fn() { @ui.style_ink(rs_uses_words) }))
          |> ignore
        })
        |> ignore
      }
      figure(fn() { "CPU" }, fn() { shown.get().0 })
      figure(fn() { @sf.t("web-main.resources.column.memory") }, fn() { shown.get().1 })
      f.show(fn() { shown.get().3 }, fn(x) {
        x.box(fn(w) {
          w
          .words_runs(By(fn() { [@ui.span(@sf.t("web-main.resources.column.net") + " "), @ui.span(shown.get().2, weight=500, color=@sf.theme().p.text)] }))
          .words_look(Is(@ui.style_words(rs_uses_words)))
          .ink(By(fn() { @ui.style_ink(rs_uses_words) }))
          |> ignore
        })
        |> ignore
      })
    }
    // (the line beside its name left out of its row where it has not the room, the one under it there only then:
    // View::drops)
    b.box(fn(ways) {
      @sf.style_node(ways, fn() { rs_uses_ways }, in_row=true)
      ways.fits(Is(true)) |> ignore
      ways.box(fn(beside) {
        @sf.style_node(beside, fn() { rs_uses_beside }, in_row=true)
        beside.drops(Is(1)) |> ignore
        @sf.words_node(beside, name, fn() { if lit() { rs_uses_lit } else { rs_uses_words } }) |> ignore
        beside.box(fn(f) {
          @sf.style_node(f, fn() { rs_uses_one_line }, in_row=true)
          figures(f)
        })
        |> ignore
      })
      |> ignore
      ways.box(fn(over) {
        @sf.style_node(over, fn() { rs_uses_over }, in_row=true)
        over.drops(Is(-1)) |> ignore
        @sf.words_node(over, name, fn() { if lit() { rs_uses_lit } else { rs_uses_words } }) |> ignore
        over.box(fn(f) {
          @sf.style_node(f, fn() { rs_uses_figures })
          f.wraps(Is(Some(rs_uses_gap))) |> ignore
          figures(f)
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
    @sf.icon_node(b, "chevron-right", rs_uses_chevron, By(fn() { if lit() { @sf.theme().p.text } else { @sf.theme().p.muted } }))
    |> ignore
  })
  |> ignore
}

///|
/// A total's tile at its narrowest (rs_tile_box's min_w=S36).
let rs_tile_least : Double = @ui.Space::S36.px()

///|
/// A pair's tiles apart (rs_tile_pair's gap=S2).
let rs_tile_gap : Double = @ui.Space::S2.px()

///|
/// A column's head's cell in the heads' row: as wide as its column (rs_column's least), the head pressed in it.
fn rs_column_room(lay : RsLayout, k : Int) -> @ui.Style {
  @ui.style(min_w=Fixed(lay.widths[k]))
}

///|
/// A column's head pressed (to sort by it): as wide as its cell.
// kept across runs: a value (no field of it changes)
let rs_head_pressed : @ui.Style = @ui.css("w=Full")
