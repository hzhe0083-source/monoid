// A new connect on the desktop, in a dialog (still.fail web/src/pages/Connect.tsx NewConnectDialog, CoreNewConnectDialog,
// SlackTeamIcon, TokenOwner, MadeAppSteps; FeishuConnect.tsx useFeishuStep; Connect.css.ts, FeishuConnect.css.ts): the
// core's wizard (`connectFlow {station, form}`: its step, title, count, what can be done, what is wrong) drawn a step
// at a time — the platform; Slack's (the workspace to make its app in, a configuration token to add, the app's look
// and permissions, making and installing it then its app-level token, or both tokens pasted by hand) or Feishu's (the
// model, how its conversations become sessions, a bot made by scanning or an app of one's own); last the model it
// runs. What is typed goes to the core's draft (`connect.flow.edit`), the way on (`connect.flow.go`), what is done
// (`connect.flow.<config|make|verify|register|create>`); added, its page.

///|
/// A wizard open on a station (its form), and what the dialog keeps of its own: the Feishu app's fields, the Comma
/// line, whether it was let go of.
priv struct NcFlow {
  station : String
  form : String
  app_id : @ui.Field
  app_secret : @ui.Field
  /// the line Comma's still.fail plugin shows, as typed
  comma_line : @ui.Field
  /// the group server's fields as typed (its endpoint id, relays, join code, the member's name), and whether the
  /// core's draft was put in them once
  group_server : @ui.Field
  group_relays : @ui.Field
  group_code : @ui.Field
  group_name : @ui.Field
  mut group_filled : Bool
  mut gone : Bool
  /// the steps the dialog shows, as the wizard has gone through them (the dialog's steps follow the core's: nc_follow)
  pages : Array[String]
  /// what each step said as it was last on top (its title, count and what it is about): nc_words_at
  words : Map[Int, (String, String, String)]
  /// the page the dialog was opened over, as it stood then: what its pictures are asked for by
  stint : Int
}

///|
// kept across runs: counted by new_connect_dialog; new_connect_reset puts it back
let nc_made : Ref[Int] = Ref(0)

///|
fn new_connect_reset() -> Unit {
  nc_made.val = 0
}

///|
/// The calls that are the wizard's doing (useConnectFlow's actions).
// kept across runs: a table, never written
let nc_actions : Array[String] = [
  "connect.flow.config", "connect.flow.make", "connect.flow.verify", "connect.flow.register", "connect.flow.create",
]

///|
/// A new connect on `station`, in a dialog of nodes that goes in steps (NewConnectDialog): from the start, or
/// (`made_app`) from a Slack app made before. Its wizard is opened as it is, and let go of as the dialog closes; the
/// dialog's steps follow the wizard's (nc_follow), each its title, count and what it is about as the core says them.
pub fn new_connect_dialog(src : Source, core : Core, here : Here, station : String, made_app? : String = "") -> Unit {
  ignore(here)
  nc_made.val += 1
  let f : NcFlow = {
    station,
    form: "desk-connect-" + nc_made.val.to_string(),
    app_id: @ui.Field::new(),
    app_secret: @ui.Field::new(),
    comma_line: @ui.Field::new(),
    group_server: @ui.Field::new(),
    group_relays: @ui.Field::new(),
    group_code: @ui.Field::new(),
    group_name: @ui.Field::new(),
    group_filled: false,
    gone: false,
    pages: [],
    words: {},
    stint: app.nav.top_stay().1,
  }
  let view = fn() { (core.topic)("connectFlow", { "station": str(station), "form": str(f.form) }).get().value }
  // (back on any step the wizard's: told to the core, which goes back or says it is closed; the dialog's steps follow)
  let shut = fn() { @sf.close_presented() }
  let close = fn() { nc_close(core, f, shut) }
  let back = fn() { nc_go(core, f, "back", close) }
  // (the step the dialog opens on: the wizard's first, as the core first says it)
  let first : @signals.Signal[String] = @signals.signal("")
  (core.call)(
    "connect.flow.open",
    obj([
      ("station", str(station)),
      ("form", str(f.form)),
      // (no `mobile`: one page draws the one flow, the web desktop's, on every screen; told it, the core's phone flow
      // asked for a step of its own (token) this page has not)
      ("input", obj([("resume", if made_app == "" { Json::null() } else { str(made_app) })])),
    ]),
    fn(r) {
      match r {
        Ok(_) => ()
        Err(e) => (core.say)(error_text(e))
      }
    },
  )
  open_dialog_nodes(
    @sf.t("web-pages.connects.add"),
    wide=true,
    steps=true,
    back~,
    live=fn() { nc_words_at(f, view, 0) },
    fn(v, _) {
      // (the dialog's steps brought to the wizard's as the core says its step)
      v.reacts(fn() { nc_step_of(view()) }, fn(step) { nc_follow(src, core, f, view, step, first, v, close, back) })
      v.pick(fn() { first.get() }, fn(p, step) {
        if step == "" {
          @sf.wait_line_node(p, fn() { @sf.t("common.reading") }) |> ignore
        } else {
          nc_body_node(p, src, core, f, view, close, step)
        }
      })
    },
    fn(v, _) {
      v.pick(fn() { first.get() }, fn(p, step) {
        @sf.foot_part_node(p)
        nc_foot_node(p, core, f, view, close, step)
      })
    },
    on_gone=fn() { nc_drop(core, f) },
  )
}

///|
/// The wizard's step as the core says it ("" before it has said it).
fn nc_step_of(v : Json?) -> String {
  match v {
    Some(Object(_)) => text(v, "step")
    _ => ""
  }
}

///|
/// The wizard's title, which of its steps it is on and what that is about, as the core says now (CoreNewConnectDialog's
/// head), or the dialog's before it has said.
fn nc_words(v : Json?) -> (String, String, String) {
  match v {
    Some(_) =>
      (
        text(v, "title"),
        text_number(v, "number").to_string() + " / " + text_number(v, "total").to_string(),
        if text(v, "step") == "team" && !flag(v, "gettingToken") {
          @sf.t("web-pages.connect.teamLead")
        } else {
          ""
        },
      )
    None => (@sf.t("web-pages.connects.add"), "", "")
  }
}

///|
/// The words of the dialog's step `at`: the core's as it says them now while the wizard is on that step, those it had
/// then once it has gone on or back (the core says the wizard's step now, not the one the dialog's step was for).
fn nc_words_at(f : NcFlow, view : () -> Json?, at : Int) -> (String, String, String) {
  let v = view()
  // (the core on this step still: gone on, the words are the next step's before the dialog has it on top)
  if f.pages.is_empty() || f.pages.get(at) == Some(text(v, "step")) {
    let w = nc_words(v)
    f.words[at] = w
    w
  } else {
    f.words.get(at).unwrap_or(nc_words(view()))
  }
}

///|
/// The dialog's step `at` (0 its first): what it holds for the wizard's step `own` it was for ("" the wizard's now,
/// before it has said its first); on the step on top, the dialog's steps brought to the wizard's (nc_follow) first.
///|
/// The dialog's steps brought to the wizard's step `step` as the core has it now: its first as it is first said (the
/// dialog's own, `first`); gone on to another, that one slides in (its words as the core says them while it shows, back
/// on it the wizard's); gone back to the one under the top, the top slides away.
fn nc_follow(
  src : Source,
  core : Core,
  f : NcFlow,
  view : () -> Json?,
  step : String,
  first : @signals.Signal[String],
  within : @view.View,
  close : () -> Unit,
  back : () -> Unit,
) -> Unit {
  guard step != "" && !f.gone else { return }
  let n = f.pages.length()
  // (done is no step of its own: the step it was done on shows it as the dialog closes onto what was made (each step's
  // body and foot say `| "done"`), so it is never pushed over that step, whose fields a second page of the same step
  // would give to two editors at once; a dialog let go follows nothing)
  if step == "done" && n > 0 {
    ()
  } else if n == 0 {
    f.pages.push(step)
    @view.transition(within=within.transitions_root(), fn() { first.set(step) })
  } else if f.pages[n - 1] == step {
    ()
  } else if n >= 2 && f.pages[n - 2] == step {
    f.pages.pop() |> ignore
    @sf.panel_back() |> ignore
  } else {
    f.pages.push(step)
    let at = n
    @sf.panel_go_nodes(
      text(@signals.untracked(view), "title"),
      fn(v, _) { nc_body_node(v, src, core, f, view, close, step) },
      foot=fn(v, _) { nc_foot_node(v, core, f, view, close, step) },
      back~,
      live=fn() { nc_words_at(f, view, at) },
    )
  }
}

///|
/// The dialog closed: its wizard and its tokens' draft let go of.
fn nc_close(core : Core, f : NcFlow, shut : () -> Unit) -> Unit {
  shut()
  nc_drop(core, f)
}

///|
/// Its wizard and tokens' draft let go of, once.
fn nc_drop(core : Core, f : NcFlow) -> Unit {
  if !f.gone {
    f.gone = true
    (core.call)("connect.flow.drop", obj([("station", str(f.station)), ("form", str(f.form))]), @sfbase.answer_unread)
    for k in slack_token_forms.keys().to_array() {
      if k.has_prefix("flow/" + f.form) {
        slack_token_forms.remove(k)
      }
    }
  }
}

///|
/// What is typed sent to the wizard's draft (`connect.flow.edit`).
fn nc_edit(core : Core, f : NcFlow, input : Json) -> Unit {
  (core.call)("connect.flow.edit", obj([("station", str(f.station)), ("form", str(f.form)), ("input", input)]), fn(r) {
    match r {
      Ok(_) => ()
      Err(e) => (core.say)(error_text(e))
    }
  })
}

///|
/// The way on (`connect.flow.go`): the core moves the wizard; where it says to close, it closes.
fn nc_go(core : Core, f : NcFlow, to : String, close : () -> Unit) -> Unit {
  (core.call)("connect.flow.go", obj([("station", str(f.station)), ("form", str(f.form)), ("input", obj([("to", str(to))]))]), fn(
    r,
  ) {
    match r {
      Ok(v) => if flag(Some(v), "close") { close() }
      Err(e) => (core.say)(error_text(e))
    }
  })
}

///|
/// What the wizard does (`connect.flow.<action>`), not while it is doing another; `done` its answer.
fn nc_act(core : Core, f : NcFlow, action : String, done? : (Json) -> Unit = fn(_) {  }) -> Unit {
  if nc_busy(core, f) {
    return
  }
  (core.call)("connect.flow." + action, obj([("station", str(f.station)), ("form", str(f.form))]), fn(r) {
    match r {
      Ok(v) => done(v)
      Err(e) => (core.say)(error_text(e))
    }
  })
}

///|
/// Whether the wizard is doing something, and why what it did last failed ("" none).
fn nc_busy(core : Core, f : NcFlow) -> Bool {
  is_doing(core, nc_actions, [("station", f.station), ("form", f.form)])
}

///|
fn nc_error(core : Core, f : NcFlow) -> String {
  failed_of(core, nc_actions, [("station", f.station), ("form", f.form)]).unwrap_or("")
}

///|
/// The connect added: said (as its kind says it: `platform`), the dialog closed onto its page.
fn nc_added(core : Core, f : NcFlow, id : String, close : () -> Unit, platform : String) -> Unit {
  (core.say)(
    @sf.t(
      match platform {
        "feishu" => "web-pages.connect.feishu.added"
        "comma" => "web-pages.connect.added.comma"
        "group" => "web-pages.connect.added.group"
        _ => "web-pages.connect.added"
      },
    ),
  )
  close()
  (core.push)(Connect(f.station, id))
}

///|
/// The wizard's tokens' draft (useSlackTokens with its form), opened for an app installed through Slack (`install`).
///|
/// The wizard's tokens' draft (useSlackTokens with its form), opened for an app installed through Slack (`install`).
fn nc_tokens(core : Core, f : NcFlow, install : String) -> SlackTokens {
  slack_tokens_draft(core, f.station, "flow/" + f.form + "/" + install, "", install, f.form, fn(_, open) { open() })
}

///|
/// What the dialog's step `step` shows (CoreNewConnectDialog's body; useFeishuStep's) as the core says the wizard now
/// (`v`): "" while it has said nothing.
fn nc_kind(step : String, v : Json?) -> String {
  guard v is Some(Object(_)) else { return "" }
  let fe = field(v, "feishu")
  match step {
    "platform" => "platform"
    "commaLine" | "done" if text(v, "platform") == "comma" => "commaLine"
    "commaBind" => "commaBind"
    "groupForm" | "done" if text(v, "platform") == "group" => "groupForm"
    "groupBind" => "groupBind"
    "feishuBind" | "bind" => step
    "feishuWay" => "feishuWay"
    "feishuScan" => "scan"
    "done" if field(fe, "registration") is Some(Object(_)) => "scan"
    "feishuApp" | "done" => "feishuApp"
    "team" => "team"
    "app" => "app"
    "install" if field(v, "made") is Some(Object(_)) => "install"
    "manual" => "manual"
    _ => "other"
  }
}

///|
/// The dialog's step `step` in `p` (CoreNewConnectDialog's body; useFeishuStep's), as the core says the wizard now
/// (`view`): one sliding away as another comes still shows what it was for.
fn nc_body_node(
  p : @view.View,
  src : Source,
  core : Core,
  f : NcFlow,
  view : () -> Json?,
  close : () -> Unit,
  step : String,
) -> Unit {
  let fe = fn() { field(view(), "feishu") }
  let error = fn() { nc_error(core, f) }
  p.box(fn(b) {
    @sf.style_node(b, fn() { nc_body_box })
    // added on its own (a bot made by scanning): its page, once
    // (the wizard's done shown on the step it was done on: nc_follow)
    b.reacts(fn() { if text(view(), "step") == "done" { opt_text(fe(), "connect") } else { None } }, fn(id) {
      if id is Some(_) && !f.gone {
        nc_watch_added(core, f, @signals.untracked(view), close)
      }
    })
    b.pick(fn() { nc_kind(step, view()) }, fn(k, kind) {
      // (its parts as far apart as the step's: nc_body_box's)
      @sf.style_node(k, fn() { nc_body_box })
      match kind {
        "" => @sf.wait_line_node(k, fn() { @sf.t("common.reading") }) |> ignore
        "platform" => nc_platform_node(k, core, f, view)
        "commaLine" => nc_comma_line_node(k, core, f, fn() { field(view(), "comma") }, error)
        // (a Comma connect has one way, a session a Task: the station makes it so, and Comma has no threads to choose by)
        "commaBind" => nc_models_node(k, src, core, f, view)
        "groupForm" => nc_group_form_node(k, core, f, fn() { field(view(), "group") }, error)
        // (a group connect's way: a session a conversation, or one for all; a private chat and a group are each one)
        "groupBind" => {
          nc_models_node(k, src, core, f, view)
          @sf.field_node(k, fn() { @sf.t("web-pages.connect.mode") }, fn(m) {
            mode_choices_node(m, fn() { field(view(), "modeWords") }, fn() {
              let v = view()
              (text(v, "mode"), flag(v, "requireMention"), false)
            }, fn(n) {
              let (mode, mention, _) = n
              nc_edit(core, f, obj([("mode", str(mode)), ("requireMention", Json::boolean(mention))]))
            })
          })
        }
        "feishuBind" | "bind" => {
          nc_models_node(k, src, core, f, view)
          @sf.field_node(k, fn() { @sf.t("web-pages.connect.mode") }, fn(m) {
            mode_choices_node(
              m,
              fn() { field(view(), "modeWords") },
              fn() {
                let v = view()
                (text(v, "mode"), flag(v, "requireMention"), flag(v, "threads"))
              },
              fn(n) {
                let (mode, mention, threads) = n
                nc_edit(core, f, obj([("mode", str(mode)), ("requireMention", Json::boolean(mention)), ("threads", Json::boolean(threads))]))
              },
            )
          })
          if kind == "bind" {
            nc_bad_node(k, error)
          }
        }
        "feishuWay" => {
          @sf.choices_node(
            k,
            fn() { text(fe(), "way") },
            fn() {
              [
                ("scan", @sf.t("web-pages.connect.feishu.scan"), @sf.t("web-pages.connect.feishu.scanNote")),
                ("app", @sf.t("web-pages.connect.feishu.app"), @sf.t("web-pages.connect.feishu.appNote")),
              ]
            },
            fn(way) { nc_edit(core, f, obj([("feishu", obj([("way", str(way))]))])) },
            label=fn() { @sf.t("web-pages.connect.feishu.way") },
          )
          nc_bad_node(k, error)
        }
        "scan" => nc_scan_node(k, core, fe)
        "feishuApp" => nc_feishu_app_node(k, core, f, fe, error)
        "team" => nc_team_node(k, core, f, view, close)
        "app" => nc_app_node(k, core, f, view, error)
        "install" => {
          let made = fn() { field(view(), "made") }
          nc_made_steps_node(k, core, made)
          k.show(fn() { opt_text(view(), "iconError").unwrap_or("") != "" }, fn(e) {
            @sf.words_node(e, fn() { @sf.t("web-pages.connect.iconFailed", args=[("error", text(view(), "iconError"))]) }, fn() {
              desk_note_bad
            })
            |> ignore
          })
          let tk = nc_tokens(core, f, text(@signals.untracked(made), "state"))
          token_fields_node(k, core, tk, install=opt_text(@signals.untracked(made), "install") is Some(_))
        }
        "manual" => {
          create_app_steps_node(k, core, f.station, fn() { @sf.product() })
          token_fields_node(k, core, nc_tokens(core, f, ""))
        }
        _ => ()
      }
    })
  })
  |> ignore
}

///|
/// What went wrong (`error`, as it is now), in red, while it says something.
fn nc_bad_node(k : @view.View, error : () -> String) -> Unit {
  k.show(fn() { error() != "" }, fn(e) { @sf.words_node(e, error, fn() { desk_note_bad }) |> ignore })
}

///|
/// Where the connect goes (the platform step): Slack, Feishu (its note why not where the station is too old for it),
/// Comma where the station offers it, each its mark on its title's line.
fn nc_platform_node(k : @view.View, core : Core, f : NcFlow, view : () -> Json?) -> Unit {
  let offered = fn() { strings(view(), "platforms").contains("feishu") }
  @sf.choices_node(
    k,
    fn() { opt_text(view(), "platform").unwrap_or("slack") },
    fn() {
      let out = [
        ("slack", "Slack", @sf.t("web-pages.connect.feishu.slackNote")),
        (
          "feishu",
          @sf.t("web-pages.connect.feishu.name"),
          @sf.t(if offered() { "web-pages.connect.feishu.feishuNote" } else { "web-pages.connect.feishu.update" }),
        ),
      ]
      // (offered only by a station with the Comma connect)
      if strings(view(), "platforms").contains("comma") {
        out.push(("comma", "Comma", @sf.t("web-pages.connect.comma.note")))
      }
      // (offered only by a station with the group connect)
      if strings(view(), "platforms").contains("group") {
        out.push(("group", @sf.t("web-pages.connect.group.name"), @sf.t("web-pages.connect.group.note")))
      }
      out
    },
    fn(picked) { nc_edit(core, f, obj([("platform", str(picked))])) },
    label=fn() { @sf.t("web-pages.connect.feishu.platform") },
    disabled=fn(p) { p == "feishu" && !offered() },
    icon=fn(m, p) {
      m.box(fn(at) {
        @sf.style_node(at, fn() { nc_platform_mark })
        // (Comma's mark is one colour: in the page's ink)
        if p == "comma" {
          @sf.drawable_node(at, @sf.origin_mark_name(p), nc_platform_size, tint=fn() { Some(@sf.theme().p.text) }) |> ignore
        } else {
          @sf.drawable_node(at, @sf.origin_mark_name(p), nc_platform_size) |> ignore
        }
      })
      |> ignore
    },
  )
}

///|
/// The model it runs (a field): the core's pick of `connect-new:<form>` in the model control, both runtimes said where
/// its model runs on more than one; none on the station, to its profiles.
fn nc_models_node(k : @view.View, src : Source, core : Core, f : NcFlow, view : () -> Json?) -> Unit {
  let pick = fn() { field(view(), "pick") }
  @sf.field_node(
    k,
    fn() { @sf.t("web-pages.profiles.models") },
    hint=fn() { if strings(field(pick(), "valueOption"), "runtimes").length() > 1 { @sf.t("web-pages.connect.bothRuntimes") } else { "" } },
    fn(m) {
      m.pick(fn() { items(pick(), "options").length() == 0 }, fn(p, none) {
        if none {
          @sf.link_node(p, fn() { @sf.t("web-pages.connect.noModels") }, fn() { (core.push)(Profiles(f.station)) }) |> ignore
        } else {
          model_triple_node(p, src, f.station, "connect-new:" + f.form)
        }
      })
    },
  )
}

///|
/// The Slack workspace to make its app in (the team step): getting a configuration token, as a view of its own while
/// there is none or another is added (why, the form, the way by hand where there is none); else the workspaces, each
/// its icon and whose token it is, 添加配置 token and 手动创建 under them.
fn nc_team_node(k : @view.View, core : Core, f : NcFlow, view : () -> Json?, close : () -> Unit) -> Unit {
  let teams = fn() { items(view(), "teams") }
  let team = fn(id : String) { teams().iter().find_first(fn(t) { text(Some(t), "teamId") == id }) }
  k.pick(fn() { flag(view(), "gettingToken") }, fn(p, getting) {
    if getting {
      p.box(fn(s) {
        @sf.style_node(s, fn() { nc_token_start })
        @sf.words_node(s, fn() { @sf.t("web-pages.connect.tokenWhy", args=[("name", @sf.product())]) }, fn() { desk_muted }) |> ignore
        config_token_form_node(s, core, f.station, "nc-config/" + f.form, fn() {  }, flow=(
          view,
          fn() { nc_act(core, f, "config") },
          fn(token) { nc_edit(core, f, obj([("config", str(token))])) },
        ))
        s.show(fn() { teams().length() == 0 }, fn(m) {
          m.box(fn(l) {
            @sf.style_node(l, fn() { nc_manual_line })
            @sf.words_node(l, fn() { @sf.t("web-pages.connect.noToken") }, fn() { nc_meta }) |> ignore
            @sf.quiet_action_node(l, fn() { @sf.t("web-pages.connect.manualApp") }, fn() { nc_go(core, f, "manual", close) }) |> ignore
          })
          |> ignore
        })
      })
      |> ignore
      return
    }
    @sf.choices_node(
      p,
      fn() { text(field(view(), "chosen"), "teamId") },
      fn() { teams().map(fn(t) { (text(Some(t), "teamId"), text(Some(t), "name"), "") }) },
      fn(picked) { nc_edit(core, f, obj([("team", str(picked))])) },
      label=fn() { @sf.t("web-pages.connect.slackWorkspace") },
      icon=fn(m, id) { nc_team_icon_node(m, core, f, fn() { field(team(id), "owner") }) },
      note_made=fn(m, id) { nc_token_owner_node(m, core, f, fn() { field(team(id), "owner") }) },
    )
    // (the two at its ends while they fit, else one over the other, the button's mark out on the words' line and what
    // goes under it starting there)
    p.box(fn(r) {
      @sf.style_node(r, fn() { nc_team_more })
      r.wraps(Is(Some(nc_team_more_lines))) |> ignore
      r.box(fn(b) {
        @sf.style_node(b, fn() { @sf.button_start_reach() }, in_row=true)
        @sf.button_node(
          b,
          fn() { @sf.t("web-pages.connect.addTeamToken") },
          fn() { nc_edit(core, f, obj([("adding", Json::boolean(true))])) },
          tone=Ghost,
          icon="plus",
        )
        |> ignore
      })
      |> ignore
      @sf.quiet_action_node(r, fn() { @sf.t("web-pages.connect.manualShort") }, fn() { nc_go(core, f, "manual", close) }) |> ignore
    })
    |> ignore
  })
}

///|
/// A Slack workspace's icon (SlackTeamIcon: its picture 28, round; Slack's mark 18 before it is known), `owner` as it
/// is now.
fn nc_team_icon_node(m : @view.View, core : Core, f : NcFlow, owner : () -> Json?) -> Unit {
  let url = fn() { opt_text(owner(), "teamIcon").unwrap_or("") }
  m.box(fn(b) {
    @sf.style_node(b, fn() { nc_team_icon_box })
    b.pick(fn() { url() != "" }, fn(p, has) {
      if has {
        @sf.avatar_node(p, url, fn() { "" }, fn() { (core.picture)(url(), f.stint) }, nc_team_icon_size)
      } else {
        @sf.drawable_node(p, "slack", nc_slack_size) |> ignore
      }
    })
  })
  |> ignore
}

///|
/// Whose configuration token it is there (TokenOwner: their picture 16, their name and email, the workspace's address
/// muted, 6 apart), `owner` as it is now, in the words' box `m` of its choice.
fn nc_token_owner_node(m : @view.View, core : Core, f : NcFlow, owner : () -> Json?) -> Unit {
  m.show(fn() { owner() is Some(Object(_)) }, fn(s) {
    s.box(fn(l) {
      @sf.style_node(l, fn() { nc_owner_line })
      // (the workspace's address on a line of its own where the name and email leave it no room: the old row's flow)
      l.wraps(Is(Some(0.0))) |> ignore
      l.show(fn() { opt_text(owner(), "image").unwrap_or("") != "" }, fn(a) {
        @sf.avatar_node(a, fn() { text(owner(), "image") }, fn() { text(owner(), "user") }, fn() {
          (core.picture)(text(owner(), "image"), f.stint)
        }, nc_owner_size)
      })
      @sf.words_node(l, fn() {
        let o = owner()
        let email = text(o, "email")
        text(o, "user") + (if email != "" { "（" + email + "）" } else { "" })
      }, fn() { nc_meta_ink })
      |> ignore
      l.show(fn() { opt_text(owner(), "teamDomain").unwrap_or("") != "" }, fn(d) {
        @sf.words_node(d, fn() { text(owner(), "teamDomain") + ".slack.com" }, fn() { nc_meta }) |> ignore
      })
    })
    |> ignore
  })
}

///|
/// Its app's look and permissions (the app step: app_fields_node), what is picked and typed told to the wizard's draft,
/// the icon made too; why the icon could not be made, and what went wrong, under them.
fn nc_app_node(k : @view.View, core : Core, f : NcFlow, view : () -> Json?, error : () -> String) -> Unit {
  let d = sa_draft(field(@signals.untracked(view), "settings"))
  let now = fn() { sa_settings(d, field(view(), "settings")) }
  let sent = Ref(@signals.untracked(now).stringify())
  let tips = @sf.panel_tips_of(k).unwrap_or(@sf.window_tips())
  app_fields_node(k, core, d, fn() { items(view(), "sections") }, fn() { nc_inner_w }, tips, fresh=true)
  k.reacts(now, fn(s) {
    if s.stringify() != sent.val {
      sent.val = s.stringify()
      nc_edit(core, f, obj([("settings", s)]))
    }
  })
  k.reacts(at_start=false, fn() { (d.icon.get(), d.icon_error.get()) }, fn(icon) {
    let (made, wrong) = icon
    nc_edit(core, f, obj([("icon", if made == "" { Json::null() } else { str(made) }), ("iconError", if wrong == "" { Json::null() } else { str(wrong) })]))
  })
  nc_bad_node(k, fn() { opt_text(view(), "iconError").unwrap_or("") })
  nc_bad_node(k, error)
}

///|
/// What is left in Slack once the app is made (MadeAppSteps), `made` as the core says it now: installing it (through
/// Slack's OAuth, which sends the bot token to the station itself; else by hand, its OAuth page to copy it from), its
/// app-level token, the token or tokens filled in below.
fn nc_made_steps_node(k : @view.View, core : Core, made : () -> Json?) -> Unit {
  let links = fn() { field(made(), "links") }
  let oauth = fn() { opt_text(made(), "install") }
  let words = fn(s : @view.View, w : () -> String) { @sf.words_node(s, w, fn() { @sf.step_words }) |> ignore }
  @sf.steps_node(k, [
    fn(s) {
      s.pick(
        fn() {
          match oauth() {
            Some(_) => if flag(made(), "installed") { 2 } else { 1 }
            None => 0
          }
        },
        fn(p, how) {
          match how {
            2 =>
              @sf.verify_ok_node(p, fn() {
                @sf.t("web-pages.cloud.slackInstalled.done", args=[
                  ("team", first_text(made(), ["installedTeam", "team"], @sf.t("web-pages.cloud.slackInstalled.workspace"))),
                ])
              })
            1 => {
              words(p, fn() { @sf.t("web-pages.connect.made.oauth") })
              @sf.button_node(p, fn() { @sf.t("web-pages.connect.made.install") }, fn() {
                (core.open_link)(oauth().unwrap_or(""))
              }, tone=Primary, icon="external")
              |> ignore
            }
            _ => {
              words(p, fn() { @sf.t("web-pages.connect.made.manual") })
              @sf.button_node(p, fn() { @sf.t("web-pages.connect.made.install") }, fn() { (core.open_link)(text(links(), "install")) }, tone=Primary, icon="external")
              |> ignore
              @sf.button_node(p, fn() { @sf.t("web-pages.connect.made.openOauth") }, fn() { (core.open_link)(text(links(), "oauth")) }) |> ignore
            }
          }
        },
      )
    },
    fn(s) {
      words(s, fn() { @sf.t("web-pages.connect.made.appToken") })
      @sf.button_node(s, fn() { @sf.t("web-pages.connect.made.openSocket") }, fn() { (core.open_link)(text(links(), "appToken")) }, icon="external")
      |> ignore
    },
    fn(s) { words(s, fn() { @sf.t(if oauth() is Some(_) { "web-pages.connect.made.fillOne" } else { "web-pages.connect.made.fillBoth" }) }) },
  ])
}

///|
/// A Feishu bot being made by scanning (`fe` as the core says it now): its QR code 196 (or, before it, a ring or
/// Feishu's mark in its place), beside it (narrow: under it) where it stands (a ring while the connect is added, red
/// where it failed), what went wrong, and while it waits how to scan it and the way to open it on this device.
fn nc_scan_node(k : @view.View, core : Core, fe : () -> Json?) -> Unit {
  let r = fn() { field(fe(), "registration") }
  let waiting = fn() { text(r(), "state") == "waiting" }
  let failing = fn() { flag(fe(), "failed") || opt_text(fe(), "error") is Some(_) }
  let erred = fn() { opt_text(fe(), "error") is Some(_) }
  // (narrow, its words under the code: beside it they had a phone's leftover hundred points, three lines a sentence
  // and the button cut off)
  @sf.figure_words_node(
    k,
    fn(g) {
      g.pick(fn() { field(fe(), "qr") is Some(Object(_)) }, fn(p, code) {
        if code {
          @sf.qr_code_node(p, fn() { field(fe(), "qr") }, nc_qr_size, fn() { @sf.t("web-pages.connect.feishu.qr") })
          return
        }
        p.box(fn(place) {
          @sf.style_node(place, fn() { nc_qr_place })
          place.pick(fn() { (flag(fe(), "creating") || text(r(), "state") == "done") && !erred() }, fn(m, turning) {
            if turning {
              @sf.spinner_node(m) |> ignore
            } else {
              @sf.drawable_node(m, "feishu", nc_feishu_size) |> ignore
            }
          })
        })
        |> ignore
      })
    },
    fn(w) {
      w.box(fn(l) {
        @sf.style_node(l, fn() { desk_said_line })
        l.show(fn() { flag(fe(), "creating") || (text(r(), "state") == "done" && !erred() && opt_text(fe(), "connect") is None) }, fn(
          s,
        ) {
          @sf.spinner_node(s, size=cd_icon) |> ignore
        })
        @sf.words_node(l, fn() { text(fe(), "stateText") }, fn() { if failing() { nc_scan_bad } else { desk_words } }) |> ignore
      })
      |> ignore
      nc_bad_node(w, fn() { opt_text(fe(), "error").unwrap_or("") })
      w.show(waiting, fn(s) {
        @sf.style_node(s, fn() { nc_scan_waits })
        @sf.words_node(s, fn() { @sf.t("web-pages.connect.feishu.scanHint") }, fn() { desk_muted }) |> ignore
        @sf.button_node(s, fn() { @sf.t("web-pages.connect.feishu.openInFeishu") }, fn() { (core.open_link)(text(r(), "url")) }, icon="external")
        |> ignore
      })
    },
  )
}

///|
/// A Feishu app of one's own (useFeishuStep's app step), `fe` as the core says it now: where to find it (its console
/// opened), its App ID and App Secret (what verifying found wrong under the secret; each told to the wizard's draft as
/// it is typed), whether it is Lark's; who it was verified as.
fn nc_feishu_app_node(k : @view.View, core : Core, f : NcFlow, fe : () -> Json?, error : () -> String) -> Unit {
  let lark = fn() { flag(fe(), "lark") }
  k.box(fn(l) {
    @sf.style_node(l, fn() { nc_hint_line })
    @sf.words_node(l, fn() { @sf.t("web-pages.connect.feishu.appHint") }, fn() { desk_muted }).shrink(Is(1.0)) |> ignore
    @sf.link_node(l, fn() { @sf.t("web-pages.connect.feishu.openConsole") }, fn() {
      (core.open_link)(if @signals.untracked(lark) { "https://open.larksuite.com/app" } else { "https://open.feishu.cn/app" })
    })
    |> ignore
  })
  |> ignore
  // (what the wizard has of it, as the dialog's step is made: the field echoes what is typed, the core has it after)
  let kept = text(@signals.untracked(fe), "appId")
  if f.app_id.text() == "" && kept != "" {
    f.app_id.set(kept)
  }
  @sf.field_node(k, fn() { "App ID" }, fn(m) { @sf.input_node(m, f.app_id, placeholder="cli_…", label="App ID") |> ignore })
  k.reacts(at_start=false, fn() { f.app_id.text() }, fn(typed) { nc_edit(core, f, obj([("feishu", obj([("appId", str(typed))]))])) })
  @sf.field_node(
    k,
    fn() { "App Secret" },
    error=fn() { strings(fe(), "errors").iter().fold(init="", fn(a, e) { if a == "" { e } else { a + "；" + e } }) },
    fn(m) { @sf.input_node(m, f.app_secret, secret=true, label="App Secret") |> ignore },
  )
  k.reacts(at_start=false, fn() { f.app_secret.text() }, fn(typed) { nc_edit(core, f, obj([("feishu", obj([("appSecret", str(typed))]))])) })
  @sf.switch_row_node(
    k,
    fn() { @sf.t("web-pages.connect.feishu.lark") },
    lark,
    fn(now) { nc_edit(core, f, obj([("feishu", obj([("lark", Json::boolean(now))]))])) },
    note=fn() { @sf.t("web-pages.connect.feishu.larkNote") },
    in_words=true,
  )
  let verified = fn() {
    let identity = field(fe(), "identity")
    guard flag(fe(), "verified") && identity is Some(Object(_)) else { return "" }
    let tenant = text(field(identity, "tenant"), "name")
    if tenant != "" {
      @sf.t("web-pages.connect.feishu.verified", args=[("bot", text(identity, "botName")), ("tenant", tenant)])
    } else {
      @sf.t("web-pages.connect.feishu.verifiedBot", args=[("bot", text(identity, "botName"))])
    }
  }
  k.show(fn() { verified() != "" }, fn(o) { @sf.verify_ok_node(o, verified) })
  nc_bad_node(k, fn() {
    match opt_text(fe(), "error") {
      Some(e) => e
      None => error()
    }
  })
}

///|
/// The Comma path's last step (`cm` as the core says it now): where the line comes from (Comma's still.fail plugin),
/// the line pasted (told to the wizard's draft as it is typed), why adding it failed.
fn nc_comma_line_node(k : @view.View, core : Core, f : NcFlow, cm : () -> Json?, error : () -> String) -> Unit {
  let kept = text(@signals.untracked(cm), "line")
  if f.comma_line.text() == "" && kept != "" {
    f.comma_line.set(kept)
  }
  @sf.field_node(
    k,
    fn() { @sf.t("web-pages.connect.comma.line") },
    hint=fn() { @sf.t("web-pages.connect.comma.lineHint") },
    error=fn() {
      match opt_text(cm(), "error") {
        Some(e) => e
        None => error()
      }
    },
    fn(m) { @sf.input_node(m, f.comma_line, placeholder="comma https://… …", label=@sf.t("web-pages.connect.comma.line")) |> ignore },
  )
  k.reacts(at_start=false, fn() { f.comma_line.text() }, fn(typed) { nc_edit(core, f, obj([("comma", obj([("line", str(typed))]))])) })
}


///|
/// The group path's last step (`g` as the core says it now): the server it joins (its endpoint id, its relays one a line,
/// the code it joins by, the name it joins as), each field's fault under it as the core finds it, why adding it failed.
fn nc_group_form_node(k : @view.View, core : Core, f : NcFlow, g : () -> Json?, error : () -> String) -> Unit {
  // (the fields echo what is typed; the core has it a moment later: what it kept is put in them once, as they open)
  if !f.group_filled {
    f.group_filled = true
    let kept = @signals.untracked(g)
    f.group_server.set(text(kept, "server"))
    f.group_relays.set(text(kept, "relays"))
    f.group_code.set(text(kept, "code"))
    f.group_name.set(text(kept, "botName"))
  }
  let edit = fn(name : String, typed : String) { nc_edit(core, f, obj([("group", obj([(name, str(typed))]))])) }
  let fault = fn(key : String) { fn() { opt_text(g(), key).unwrap_or("") } }
  @sf.field_node(k, fn() { @sf.t("web-pages.connect.group.server") }, hint=fn() { @sf.t("web-pages.connect.group.serverHint") }, error=fault(
    "serverError",
  ), fn(m) { @sf.input_node(m, f.group_server, placeholder="0123abcd…", label=@sf.t("web-pages.connect.group.server")) |> ignore })
  @sf.field_node(k, fn() { @sf.t("web-pages.connect.group.relays") }, hint=fn() { @sf.t("web-pages.connect.group.relaysHint") }, error=fault(
    "relaysError",
  ), fn(m) {
    @sf.textarea_node(m, f.group_relays, placeholder="https://relay.example.com", label=@sf.t("web-pages.connect.group.relays")) |> ignore
  })
  @sf.field_node(k, fn() { @sf.t("web-pages.connect.group.code") }, hint=fn() { @sf.t("web-pages.connect.group.codeHint") }, error=fault(
    "codeError",
  ), fn(m) { @sf.input_node(m, f.group_code, placeholder="XXXX-XXXX-XXXX-XXXX", label=@sf.t("web-pages.connect.group.code")) |> ignore })
  @sf.field_node(k, fn() { @sf.t("web-pages.connect.group.botName") }, hint=fn() { @sf.t("web-pages.connect.group.botNameHint") }, fn(m) {
    @sf.input_node(m, f.group_name, placeholder="Claude", label=@sf.t("web-pages.connect.group.botName")) |> ignore
  })
  // (what is typed told to the wizard's draft as it is typed)
  k.reacts(at_start=false, fn() { f.group_server.text() }, fn(typed) { edit("server", typed) })
  k.reacts(at_start=false, fn() { f.group_relays.text() }, fn(typed) { edit("relays", typed) })
  k.reacts(at_start=false, fn() { f.group_code.text() }, fn(typed) { edit("code", typed) })
  k.reacts(at_start=false, fn() { f.group_name.text() }, fn(typed) { edit("botName", typed) })
  nc_bad_node(k, fn() {
    match opt_text(g(), "error") {
      Some(e) => e
      None => error()
    }
  })
}
///|
/// The dialog's buttons for its step `step` in its foot `p` (CoreNewConnectDialog's footer; useFeishuStep's), as the
/// core says the wizard now (`view`): 取消 where the wizard's back closes it (back a step is the step's head's, the
/// dialog's steps following the wizard's), and the way on, each as the core says the step stands.
fn nc_foot_node(p : @view.View, core : Core, f : NcFlow, view : () -> Json?, close : () -> Unit, step : String) -> Unit {
  let busy = fn() { nc_busy(core, f) }
  let fe = fn() { field(view(), "feishu") }
  p.pick(fn() { nc_kind(step, view()) }, fn(row, kind) {
    // (its buttons in a row of their own, at a sheet's foot across it each its share: foot_part_node's)
    @sf.style_node(row, fn() { nc_foot_row })
    @sf.foot_part_node(row)
    let cancel = fn(only : Bool) {
      @sf.foot_place_node(row, fn() { only || text(view(), "back") == "close" }, fn(s) {
        @sf.button_node(s, fn() { @sf.t("common.cancel") }, close, tone=Ghost) |> ignore
      })
    }
    let next = fn(label : () -> String, disabled : () -> Bool, busy : () -> Bool, run : () -> Unit) {
      @sf.button_node(row, label, run, tone=Primary, disabled~, busy~) |> ignore
    }
    let words = fn(key : String) { fn() { @sf.t(key) } }
    let never = fn() { false }
    match kind {
      "" => cancel(true)
      "platform" => {
        cancel(false)
        next(words("web-pages.connect.next"), never, never, fn() {
          let v = view()
          let feishu = opt_text(v, "platform") == Some("feishu") && strings(v, "platforms").contains("feishu")
          let comma = opt_text(v, "platform") == Some("comma") && strings(v, "platforms").contains("comma")
          let group = opt_text(v, "platform") == Some("group") && strings(v, "platforms").contains("group")
          nc_go(core, f, if feishu { "feishuBind" } else if comma { "commaBind" } else if group { "groupBind" } else { "team" }, close)
        })
      }
      "groupBind" => {
        cancel(false)
        next(words("web-pages.connect.next"), fn() { !flag(view(), "canCreate") }, never, fn() { nc_go(core, f, "groupForm", close) })
      }
      "groupForm" => {
        cancel(false)
        next(words("web-pages.connect.addConnect"), fn() { !flag(field(view(), "group"), "ready") }, busy, fn() {
          nc_act(core, f, "create", done=fn(a) { nc_added(core, f, text(Some(a), "id"), close, "group") })
        })
      }
      "commaBind" => {
        cancel(false)
        next(words("web-pages.connect.next"), fn() { !flag(view(), "canCreate") }, never, fn() { nc_go(core, f, "commaLine", close) })
      }
      "commaLine" => {
        cancel(false)
        next(words("web-pages.connect.addConnect"), fn() { !flag(field(view(), "comma"), "ready") }, busy, fn() {
          nc_act(core, f, "create", done=fn(a) { nc_added(core, f, text(Some(a), "id"), close, "comma") })
        })
      }
      "feishuBind" => {
        cancel(false)
        next(words("web-pages.connect.next"), fn() { !flag(view(), "canCreate") }, never, fn() { nc_go(core, f, "feishuWay", close) })
      }
      "feishuWay" => {
        cancel(false)
        next(words("web-pages.connect.next"), never, busy, fn() {
          if text(fe(), "way") == "app" {
            nc_go(core, f, "feishuApp", close)
          } else {
            nc_act(core, f, "register")
          }
        })
      }
      "scan" => {
        // (a new QR code where it ended without an app, or trying again where adding the connect failed)
        cancel(false)
        let what = fn() {
          if flag(fe(), "failed") {
            1
          } else if opt_text(fe(), "error") is Some(_) {
            2
          } else {
            0
          }
        }
        @sf.foot_place_node(row, fn() { what() == 1 }, fn(b) {
          @sf.button_node(b, words("web-pages.connect.feishu.newQr"), fn() { nc_act(core, f, "register") }, tone=Primary, icon="refresh", busy~)
          |> ignore
        })
        @sf.foot_place_node(row, fn() { what() == 2 }, fn(b) {
          @sf.button_node(b, words("web-pages.connect.feishu.retry"), fn() { nc_act(core, f, "create") }, tone=Primary, busy=fn() {
            busy() || flag(fe(), "creating")
          })
          |> ignore
        })
      }
      "feishuApp" => {
        cancel(false)
        row.pick(fn() { flag(fe(), "verified") }, fn(b, verified) {
          @sf.foot_part_node(b)
          if verified {
            @sf.button_node(b, words("web-pages.connect.addConnect"), fn() {
              nc_act(core, f, "create", done=fn(a) { nc_added(core, f, text(Some(a), "id"), close, "feishu") })
            }, tone=Primary, busy=fn() { busy() || flag(fe(), "creating") })
            |> ignore
          } else {
            @sf.button_node(b, words("web-pages.connect.feishu.verify"), fn() { nc_act(core, f, "verify") }, tone=Primary, busy~, disabled=fn() {
              !flag(fe(), "canVerify")
            })
            |> ignore
          }
        })
      }
      "team" => {
        // (adding another token where there are workspaces already: back to them, not closed)
        let adding = fn() { flag(view(), "adding") && items(view(), "teams").length() > 0 }
        @sf.foot_place_node(row, adding, fn(b) {
          @sf.button_node(b, words("common.back"), fn() { nc_edit(core, f, obj([("adding", Json::boolean(false))])) }, tone=Ghost) |> ignore
        })
        @sf.foot_place_node(row, fn() { !adding() && text(view(), "back") == "close" }, fn(s) {
          @sf.button_node(s, words("common.cancel"), close, tone=Ghost) |> ignore
        })
        @sf.foot_place_node(row, fn() { !flag(view(), "gettingToken") }, fn(s) {
          @sf.button_node(s, words("web-pages.connect.next"), fn() { nc_go(core, f, "app", close) }, tone=Primary, disabled=fn() {
            !(field(view(), "chosen") is Some(Object(_)))
          })
          |> ignore
        })
      }
      "app" => next(words("web-pages.connect.createApp"), fn() { !flag(view(), "canMake") }, busy, fn() { nc_act(core, f, "make") })
      "install" | "manual" => {
        cancel(false)
        let install = if kind == "install" { text(field(@signals.untracked(view), "made"), "state") } else { "" }
        let tk = nc_tokens(core, f, install)
        next(words("web-pages.connect.next"), fn() { !tokens_ready(core, tk) }, fn() { busy() || tokens_busy(core, tk) }, fn() {
          nc_act(core, f, "verify")
        })
      }
      _ =>
        next(words("web-pages.connect.addConnect"), fn() { items(field(view(), "pick"), "options").length() == 0 }, busy, fn() {
          nc_act(core, f, "create", done=fn(a) { nc_added(core, f, text(Some(a), "id"), close, "slack") })
        })
    }
  })
}

///|
/// Watching for a Feishu connect added on its own (its bot made by scanning): its page, once.
fn nc_watch_added(core : Core, f : NcFlow, v : Json?, close : () -> Unit) -> Unit {
  if text(v, "step") == "done" && text(v, "platform") == "feishu" {
    match opt_text(field(v, "feishu"), "connect") {
      Some(id) if !f.gone => nc_added(core, f, id, close, "feishu")
      _ => ()
    }
  }
}

///|
/// The sizes: a platform's mark 22 in its 28 square, a team's icon 28 (Slack's mark 18), its owner's picture 16, the QR
/// code 196 (Feishu's mark 40 in its place), the dialog's inside (a wide dialog's 640 less its 24 each side).
let nc_platform_size : Double = 22.0

///|
let nc_team_icon_size : Double = 28.0

///|
let nc_slack_size : Double = 18.0

///|
let nc_owner_size : Double = 16.0

///|
let nc_qr_size : Double = 196.0

///|
let nc_feishu_size : Double = 40.0

///|
let nc_inner_w : Double = 592.0

///|
// kept across runs: a value (no field of it changes)
let nc_body_box : @ui.Style = @ui.css("w=Full gap=S4")

///|
/// How to scan and the way to open it here, 10 apart as the code's words are (figure_words' gap=S2_5).
// kept across runs: a value (no field of it changes)
let nc_scan_waits : @ui.Style = @ui.css("w=Full gap=S2_5 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let nc_platform_mark : @ui.Style = @ui.css("w=S7 h=S7 align=ACenter justify=JCenter")

///|
/// Getting a token (tokenStart: 8 apart; tokenManual: the meta's 12, 8 over it).
// kept across runs: a value (no field of it changes)
let nc_token_start : @ui.Style = @ui.css("w=Full gap=S2")

///|
// kept across runs: a value (no field of it changes)
let nc_manual_line : @ui.Style = @ui.css("row w=Full pt=S2 gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let nc_meta : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let nc_meta_ink : @ui.TextStyle = nc_meta.then(@ui.text_style(color=Fg))

///|
/// The workspaces' foot (teamMore: 添加 and 手动 at its ends, 8 under them).
// kept across runs: a value (no field of it changes)
let nc_team_more : @ui.Style = @ui.css("row w=Full pt=S2 align=ACenter justify=JBetween")

///|
/// The room between its two lines where they go one over the other (teamMore's flow line gap, S1).
let nc_team_more_lines : Double = 4.0

///|
// kept across runs: a value (no field of it changes)
let nc_team_icon_box : @ui.Style = @ui.css("row w=S7 h=S7 align=ACenter justify=JCenter")

///|
/// The dialog's foot (its buttons at its end, 8 apart, as a dialog's foot row has them).
// kept across runs: a value (no field of it changes)
let nc_foot_row : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter justify=JEnd")

///|
// kept across runs: a value (no field of it changes)
let nc_owner_line : @ui.Style = @ui.css("row w=Full gap=S1_5 align=ACenter")

///|
/// Scanning (scan: the code and its words, @sf.figure_words; qrPlace: 196, the dialog's inner corner, on the neutral
/// ground; scanBad: red).
// kept across runs: a value (no field of it changes)
let nc_qr_place : @ui.Style = @ui.style(w=Fixed(nc_qr_size), h=Fixed(nc_qr_size)).then(@ui.css("radius=Xl bg=Neutral align=ACenter justify=JCenter"))


///|
// kept across runs: a value (no field of it changes)
let nc_scan_bad : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Danger, w=Full)

///|
// kept across runs: a value (no field of it changes)
let nc_hint_line : @ui.Style = @ui.css("row w=Full gap=S1 align=ACenter")
