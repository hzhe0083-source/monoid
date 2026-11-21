// A connect's Slack app on the desktop (still.fail web/src/pages/SlackApp.tsx SlackAppSection, ConfigTokenForm, AppFields,
// AppForm; SlackApp.css.ts): folded on its page (it is changed now and then), its look and permissions edited here and
// written into the app's manifest with the viewer's configuration token (`connect.putSlackApp`, given what the form
// started from: the core writes only what differs); without one, a way to add it. The permissions' sections are the
// core's (the slackApp topic's and the connect wizard's `sections`); the icon is drawn by the library (app_icon.mbt).

///|
/// A Slack app's look and permissions being edited (AppFields' settings, and what its look keeps): what is typed (its
/// fields' words: its name, what it is for, its colour) and picked, the icon made (a data URL, "" none) and why it could
/// not be, and how the icon is coming along; each as it is now, followed.
priv struct SaDraft {
  /// the colour as it was last set (typed, or what was picked's)
  color : @signals.Signal[String]
  groups : @sf.LiveMap[String, Bool]
  icon : @signals.Signal[String]
  icon_error : @signals.Signal[String]
  /// the icon as shown (its picture's key), "" none
  shown : @signals.Signal[String]
  /// what was picked: an avatar's id, or a picture of the person's own (its key), "" neither
  picked : @signals.Signal[String]
  upload : @signals.Signal[String]
  upload_bg : @signals.Signal[String]
  /// the colour set by hand, not by what was picked
  colour_set : @signals.Signal[Bool]
  /// the picture being read to draw from: its source, how large, on what colour ("" none)
  reading : @signals.Signal[(String, Int, String)]
  mut asking : Bool
  /// the permissions unfolded
  perms : @signals.Signal[Bool]
  name_field : @ui.Field
  desc_field : @ui.Field
  hex_field : @ui.Field
}

///|
/// The groups `settings` (a Slack app's, as the core has them) turns on.
fn sa_groups(settings : Json?) -> Map[String, Bool] {
  let groups : Map[String, Bool] = Map([])
  match field(settings, "groups") {
    Some(Object(m)) =>
      for g, v in m {
        groups[g] = v == Json::boolean(true)
      }
    _ => ()
  }
  groups
}

///|
/// A draft of `settings` (a Slack app's, as the core has them), its fields filled with them.
fn sa_draft(settings : Json?) -> SaDraft {
  {
    color: @signals.signal(text(settings, "backgroundColor")),
    groups: @sf.LiveMap::from(sa_groups(settings)),
    icon: @signals.signal(""),
    icon_error: @signals.signal(""),
    shown: @signals.signal(""),
    picked: @signals.signal(""),
    upload: @signals.signal(""),
    upload_bg: @signals.signal(""),
    colour_set: @signals.signal(false),
    reading: @signals.signal(("", 0, "")),
    asking: false,
    perms: @signals.signal(false),
    name_field: @ui.Field::new(text=text(settings, "name")),
    desc_field: @ui.Field::new(text=text(settings, "description")),
    hex_field: @ui.Field::new(text=text(settings, "backgroundColor")),
  }
}

///|
/// The draft `d` started again from `settings`, as it was first made of them (还原; Slack's settings changed).
fn sa_draft_reset(d : SaDraft, settings : Json?) -> Unit {
  let prev_shown = d.shown.untracked()
  let prev_upload = d.upload.untracked()
  @signals.start_batch()
  d.color.set(text(settings, "backgroundColor"))
  d.groups.clear()
  for g, v in sa_groups(settings) {
    d.groups[g] = v
  }
  d.icon.set("")
  d.icon_error.set("")
  d.shown.set("")
  d.picked.set("")
  d.upload.set("")
  d.upload_bg.set("")
  d.colour_set.set(false)
  d.reading.set(("", 0, ""))
  d.asking = false
  d.perms.set(false)
  d.name_field.set(text(settings, "name"))
  d.desc_field.set(text(settings, "description"))
  d.hex_field.set(text(settings, "backgroundColor"))
  @signals.end_batch()
  if prev_shown != "" {
    @ui.forget_image(prev_shown)
  }
  if prev_upload != "" {
    @ui.forget_image(prev_upload)
  }
}

///|
/// What an app's look and permissions say of it, as the core takes its settings (the name in messages its name too).
fn sa_settings_of(name : String, description : String, color : String, groups : Map[String, Bool], settings : Json?) -> Json {
  let out : Map[String, Json] = Map([])
  for g, v in groups {
    out[g] = Json::boolean(v)
  }
  obj([
    ("name", str(name)),
    ("displayName", str(name)),
    ("description", str(description)),
    ("longDescription", str(text(settings, "longDescription"))),
    ("backgroundColor", str(color)),
    ("groups", Json::object(out)),
  ])
}

///|
/// What the draft says of the app, as the core takes its settings.
fn sa_settings(d : SaDraft, settings : Json?) -> Json {
  sa_settings_of(d.name_field.text(), d.desc_field.text(), d.color.get(), d.groups.copy(), settings)
}

///|
/// The drafts, by their form; the folds open, by station/connect; icons made, each its own picture's key.
// kept across runs: made as each form is first made; slack_app_reset empties it
let sa_drafts : Map[String, SaDraft] = Map([])

///|
// kept across runs: said by the fold's press; slack_app_reset empties it
let sa_open : Map[String, Bool] = Map([])

///|
/// What a form started from (its settings as text), by its key: a change there starts it again.
// kept across runs: said as each form starts; slack_app_reset empties it
let sa_started : Map[String, String] = Map([])

///|
/// The forms whose permissions Slack wants approved (their install links), by station/connect.
// kept across runs: said by 应用's answer; slack_app_reset empties it
let sa_approve : @sf.LiveMap[String, String] = @sf.LiveMap::new()

///|
// kept across runs: counted by sa_icon_made; slack_app_reset puts it back
let sa_icons_made : Ref[Int] = Ref(0)

///|
fn slack_app_reset() -> Unit {
  sa_drafts.clear()
  sa_open.clear()
  sa_started.clear()
  sa_approve.clear()
  sa_token_errors.clear()
  sa_icons_made.val = 0
  @sf.app_icons_reset()
}

///|
/// The connect's Slack app, folded (SlackAppSection), as nodes in `b`: a row of its own on a card, its title and what it
/// is for, that opens it (open as it was left, kept with its connect); open, the app as Slack has it under it (read
/// through the station: being read, none, no configuration token to write it with, or why it could not be read), its
/// form, and Slack's page of it. Apart from what follows, as a section is. `page_w`: how wide its page is; its tips in
/// `tips`.
fn slack_app_node(b : @view.View, core : Core, station : String, id : String, page_w : () -> Double, tips : @sf.TipLayer) -> Unit {
  let me = station + "/" + id
  let open : @signals.Signal[Bool] = @signals.signal(sa_open.get(me).unwrap_or(false), same=fn(a, b) { a == b })
  @sf.apart_node(b, fn(a) {
    @sf.group_node(a, fn(g) {
      g.pick(fn() { open.get() }, fn(r, now) {
        @sf.link_row_node(
          r,
          fn() { "Slack app" },
          fn() {
            sa_open[me] = !now
            open.set(!now)
          },
          note=fn() { @sf.t("web-pages.slackApp.foldNote") },
          value=fn() { if now { @sf.t("web-pages.profiles.collapse") } else { "" } },
          chevron=!now,
        )
      })
    })
    a.show(fn() { open.get() }, fn(i) { slack_app_open_node(i, core, station, id, page_w, tips) })
  })
  |> ignore
}

///|
/// The Slack app's fold open (slack_app_node's) in `i`: the app as Slack has it, as the station reads it now; its page
/// in Slack under it where Slack gives one.
fn slack_app_open_node(i : @view.View, core : Core, station : String, id : String, page_w : () -> Double, tips : @sf.TipLayer) -> Unit {
  let topic = fn() { (core.topic)("slackApp", { "station": str(station), "connect": str(id) }).get() }
  let view = fn() { topic().value }
  let links = fn() { field(view(), "links") }
  let error = fn() {
    match topic().error {
      Some(e) => error_text(e)
      None => ""
    }
  }
  i.pick(
    fn() {
      if topic().error is Some(_) {
        "failed"
      } else if view() is None {
        "reading"
      } else {
        match text(view(), "state") {
          "no_app" => "no_app"
          "no_config_token" => "no_config_token"
          "error" => "error"
          _ => "form"
        }
      }
    },
    fn(p, k) {
      match k {
        "failed" => @sf.page_note_node(p, error, bad=fn() { true })
        "reading" => @sf.page_note_node(p, fn() { @sf.t("web-pages.slackApp.loading") })
        "no_app" =>
          @sf.page_note_node(p, fn() {
            match opt_text(view(), "error") {
              Some(e) => @sf.t("web-pages.slackApp.noApp", args=[("error", e)])
              None => @sf.t("web-pages.slackApp.notConnected")
            }
          })
        "no_config_token" =>
          sa_token_card_node(
            p,
            core,
            station,
            fn() { @sf.t("web-pages.slackApp.needsToken") },
            fn() { @sf.t("web-pages.slackApp.needsTokenNote") },
            fn() { @sf.t("web-pages.slackApp.addToken") },
            false,
          )
        "error" =>
          sa_token_card_node(
            p,
            core,
            station,
            fn() { @sf.t("web-pages.slackApp.readFailed", args=[("error", text(view(), "error"))]) },
            fn() { "" },
            fn() { @sf.t("web-pages.slackApp.replaceToken") },
            true,
          )
        _ => sa_form_node(p, core, station, id, fn() { field(view(), "settings") }, links, fn() { items(view(), "sections") }, page_w, tips)
      }
    },
  )
  let settings_url = fn() { opt_text(links(), "settings").unwrap_or("") }
  i.show(fn() { settings_url() != "" }, fn(o) {
    @sf.group_node(o, fn(g) {
      @sf.link_row_node(g, fn() { @sf.t("web-pages.slackApp.openInSlack") }, fn() { (core.open_link)(@signals.untracked(settings_url)) }, out=true)
    })
  })
}

///|
/// A card saying the app wants a configuration token (none, or one Slack refused: `bad`), and the button that adds one
/// (in a dialog: ConfigTokenForm), as nodes in `p`.
fn sa_token_card_node(
  p : @view.View,
  core : Core,
  station : String,
  words : () -> String,
  note : () -> String,
  action : () -> String,
  bad : Bool,
) -> Unit {
  @sf.page_card_node(p, footed=true, fn(k) {
    @sf.card_lines_node(k, fn() { "" }, words=fn() { if bad { "" } else { words() } }, note~, bad=fn() { if bad { words() } else { "" } })
    @sf.card_foot_node(k, fn(f) { @sf.button_node(f, action, fn() { config_token_dialog(core, station) }, card_words=true) |> ignore })
  })
}

///|
/// A Slack workspace's app configuration token added, in a dialog (SlackAppSection's Dialog: ConfigTokenForm).
fn config_token_dialog(core : Core, station : String) -> Unit {
  let key = "config-token/" + (desk_dialogs.val + 1).to_string()
  // (no foot: its button is beside the token, in its third step)
  open_dialog_bare_nodes(
    @sf.t("web-pages.slackApp.addTokenTitle"),
    wide=true,
    fn(v, shut) { config_token_form_node(v, core, station, key, shut) },
    on_gone=fn() { sa_token_errors.remove(key) },
  )
}

///|
/// What a configuration token form went through: why the station refused it ("" none), by the form's own key.
// kept across runs: said by its call's answer; let go as its dialog goes (config_token_dialog)
let sa_token_errors : @sf.LiveMap[String, String] = @sf.LiveMap::new()

///|
/// Adding a Slack workspace's app configuration token by its refresh token (ConfigTokenForm), as nodes in `v`: three
/// steps, each a number in a circle on its title's line, its title and what to do (Slack's apps page opened from the
/// first; the token pasted in the third, added from the button beside it). `flow`: the connect wizard's (its view as
/// it is now, how it is told to add it, how each change is told), which keeps the token and says whether it is ready
/// and what is wrong with it; else the station checks it as it is added, `saved` once it took it.
fn config_token_form_node(
  v : @view.View,
  core : Core,
  station : String,
  key : String,
  saved : () -> Unit,
  flow? : (() -> Json?, () -> Unit, (String) -> Unit),
) -> Unit {
  let tf = @ui.Field::new()
  let token = fn() { tf.text().trim(chars=" \t\n").to_owned() }
  let ready = fn() {
    match flow {
      Some((view, _, _)) => flag(view(), "configReady")
      None => token() != ""
    }
  }
  let wrong = fn() {
    match flow {
      Some((view, _, _)) => opt_text(view(), "configError").unwrap_or("")
      None => sa_token_errors.get(key).unwrap_or("")
    }
  }
  let busy = fn() {
    match flow {
      Some(_) => is_doing(core, ["connect.flow.config"], [("station", station)])
      None => is_doing(core, ["slack.addConfigToken"], [("station", station)])
    }
  }
  let add = fn() {
    match flow {
      Some((_, act, _)) => act()
      None => {
        let typed = token()
        sa_token_errors.remove(key)
        (core.call)("slack.addConfigToken", obj([("station", str(station)), ("refreshToken", str(typed))]), fn(r) {
          match r {
            Ok(_) => {
              tf.set("")
              (core.say)(@sf.t("web-pages.slackApp.tokenAdded"))
              saved()
            }
            Err(e) => sa_token_errors.set(key, error_text(e))
          }
        })
      }
    }
  }
  // (with the wizard: each change of the token told to it as it is typed)
  match flow {
    Some((_, _, edit)) => v.reacts(at_start=false, token, fn(t) { edit(t) })
    None => ()
  }
  v.box(fn(g) {
    @sf.style_node(g, fn() { sa_guide })
    sa_guide_step_node(g, 1, "web-pages.slackApp.step1", fn() { @sf.t("web-pages.slackApp.step1Note") }, fn(b) {
      @sf.button_node(b, fn() { @sf.t("web-pages.slackApp.openApps") }, fn() { (core.open_link)("https://api.slack.com/apps") }, tone=Primary, icon="external")
      |> ignore
    })
    sa_guide_step_node(g, 2, "web-pages.slackApp.step2", fn() { @sf.t("web-pages.slackApp.step2Note") }, fn(_) {  })
    sa_guide_step_node(g, 3, "web-pages.slackApp.step3", fn() { @sf.t("web-pages.slackApp.step3Note", args=[("name", @sf.product())]) }, fn(
      b,
    ) {
      b.box(fn(r) {
        @sf.style_node(r, fn() { sa_input_row })
        r.box(fn(i) {
          @sf.style_node(i, fn() { sa_input_grow }, in_row=true)
          @sf.input_node(i, tf, placeholder="xoxe-1-…", secret=true, label=@sf.t("web-pages.slackApp.step3")) |> ignore
        })
        |> ignore
        @sf.button_node(r, fn() { @sf.t("web-pages.slackApp.add") }, add, tone=Primary, busy~, disabled=fn() { !ready() }) |> ignore
      })
      |> ignore
      b.show(fn() { wrong() != "" }, fn(w) { @sf.words_node(w, wrong, fn() { desk_note_bad }) |> ignore })
    })
  })
  |> ignore
}

///|
/// One of the guide's steps (tokenGuide li, sa_guide_step's as nodes) in `g`: its number `n` in a 24 circle on the
/// neutral ground on its title's line, its title (`title`: its words' key) in 600, what to do muted, what `body` makes
/// under them.
fn sa_guide_step_node(g : @view.View, n : Int, title : String, note : () -> String, body : (@view.View) -> Unit) -> Unit {
  g.box(fn(r) {
    @sf.style_node(r, fn() { sa_step })
    // (its circle across its title's line's middle, as tall as that line at the system's size of words)
    @sf.step_circle_node(r, fn() { n.to_string() }, first_line=Ui, leading=L6) |> ignore
    r.box(fn(b) {
      @sf.style_node(b, fn() { sa_step_body }, in_row=true)
      @sf.words_node(b, fn() { @sf.t(title) }, fn() { desk_strong }) |> ignore
      @sf.words_node(b, note, fn() { desk_muted }) |> ignore
      body(b)
    })
    |> ignore
  })
  |> ignore
}

///|
/// The app's form (AppForm, a card) as nodes in `p`: Slack asking for changed permissions to be approved (its page
/// opened from it); its look and permissions; why its icon could not be made; 还原 while changed, 应用 writing what
/// changed (the core compares it with what the form started from). Started again when Slack's settings change.
fn sa_form_node(
  p : @view.View,
  core : Core,
  station : String,
  id : String,
  settings : () -> Json?,
  links : () -> Json?,
  sections : () -> Array[Json],
  page_w : () -> Double,
  tips : @sf.TipLayer,
) -> Unit {
  let me = station + "/" + id
  let key = "slack-app/" + me
  let start = fn() {
    match settings() {
      Some(s) => s.stringify()
      None => ""
    }
  }
  let started = @signals.untracked(start)
  let d = match sa_drafts.get(key) {
    Some(d) if sa_started.get(key) == Some(started) => d
    _ => {
      let d = sa_draft(@signals.untracked(settings))
      sa_drafts[key] = d
      sa_started[key] = started
      d
    }
  }
  // (Slack's settings changed: the form started again from them)
  p.reacts(start, fn(now) {
    if sa_started.get(key) != Some(now) {
      sa_started[key] = now
      sa_draft_reset(d, @signals.untracked(settings))
    }
  })
  let busy = fn() { is_doing(core, ["connect.putSlackApp"], [("station", station), ("connect", id)]) }
  let now = fn() { sa_settings(d, settings()) }
  let dirty = fn() {
    let s = settings()
    now() != sa_settings_of(text(s, "name"), text(s, "description"), text(s, "backgroundColor"), sa_groups(s), s) ||
    d.icon.get() != ""
  }
  @sf.page_card_node(p, footed=true, fn(k) {
    k.show(fn() { sa_approve.get(me) is Some(_) }, fn(a) {
      a.box(fn(b) {
        @sf.style_node(b, fn() { sa_blue })
        b.ground(By(fn() { @sf.theme().p.blue_bg })) |> ignore
        @sf.icon_node(b, "shield-check", cd_icon, By(fn() { @sf.theme().p.blue })) |> ignore
        b.box(fn(w) {
          @sf.style_node(w, fn() { cd_effect_words }, in_row=true)
          @sf.words_node(w, fn() { @sf.t("web-pages.slackApp.approveNote") }, fn() { sa_blue_words }) |> ignore
        })
        |> ignore
        @sf.button_node(
          b,
          fn() { @sf.t("web-pages.slackApp.approve") },
          fn() {
            let install = sa_approve.get(me).unwrap_or("")
            sa_approve.remove(me)
            (core.open_link)(install)
          },
          tone=Primary,
        )
        |> ignore
      })
      |> ignore
    })
    app_fields_node(k, core, d, sections, fn() { sa_column(page_w()) - 2.0 * sa_card_in }, tips)
    k.show(fn() { d.icon_error.get() != "" }, fn(e) { @sf.card_lines_node(e, fn() { "" }, bad=fn() { d.icon_error.get() }) })
    @sf.card_foot_node(k, at_end=true, fn(f) {
      f.show(dirty, fn(r) {
        @sf.button_node(r, fn() { @sf.t("web-pages.slackApp.revert") }, fn() { sa_draft_reset(d, @signals.untracked(settings)) }, tone=Ghost)
        |> ignore
      })
      @sf.button_node(
        f,
        fn() { @sf.t("web-pages.slackApp.apply") },
        fn() {
          let (input0, from, links_now) = @signals.untracked(fn() { (now(), settings(), links()) })
          let input = match input0 {
            Object(m) => {
              let m2 = Map::from_iter(m.iter())
              let icon = d.icon.untracked()
              if icon != "" {
                m2["icon"] = str(icon)
              }
              Json::object(m2)
            }
            other => other
          }
          (core.call)(
            "connect.putSlackApp",
            obj([("station", str(station)), ("connect", str(id)), ("input", input), ("from", from.unwrap_or(Json::null()))]),
            fn(r) {
              match r {
                Ok(v) => {
                  let rv = Some(v)
                  let approve = flag(rv, "permissionsUpdated")
                  d.icon.set("")
                  d.icon_error.set(opt_text(rv, "iconError").unwrap_or(""))
                  let install = text(field(rv, "links"), "install")
                  if approve {
                    sa_approve[me] = if install != "" { install } else { text(links_now, "install") }
                    // (the desktop opens Slack's page in the system's browser, at any time)
                    (core.open_link)(sa_approve.get(me).unwrap_or(""))
                  }
                  (core.say)(@sf.t(if approve { "web-pages.slackApp.updatedApprove" } else { "web-pages.slackApp.updated" }))
                }
                Err(e) => (core.say)(error_text(e))
              }
            },
          )
        },
        tone=Primary,
        busy~,
        disabled=fn() { !dirty() },
      )
      |> ignore
    })
  })
}

///|
/// An app's look and permissions (app_fields', as nodes) in `k`: its heading; its avatar (pressed, a picture of the
/// person's own), its name, what it is for and its colour (following what was picked until set by hand, and back to it);
/// the avatars to start from (still.fail's buddies, the model makers); the permissions folded. `width`: how wide it is
/// drawn now; its tips in `tips`. `fresh`: a new app's (the new connect's), which starts as the general helper (else
/// the first avatar), on its colour, once the avatars are read; its own picture's choice then says 上传, not 保留.
fn app_fields_node(
  k : @view.View,
  core : Core,
  d : SaDraft,
  sections : () -> Array[Json],
  width : () -> Double,
  tips : @sf.TipLayer,
  fresh? : Bool = false,
) -> Unit {
  @sf.app_buddies_ask(fn(done) { (core.call)("buddies", obj([]), done) })
  let all = fn() { @sf.app_buddies_now() + @sf.app_makers }
  let find = fn(id : String) { @signals.untracked(all).iter().find_first(fn(a) { a.id == id }) }
  let colour = fn(bg : String) {
    d.color.set(bg)
    d.hex_field.set(bg)
  }
  // an avatar drawn on `bg`: a mark at once, a buddy once its picture is read
  let draw = fn(a : @sf.AppAvatar, bg : String) {
    if a.mark != "" {
      d.reading.set(("", 0, ""))
      match @sf.app_avatar_icon(a, bg, 0, 0, FixedArray::make(0, b'\x00')) {
        Some(icon) => sa_icon_made(d, icon)
        None => sa_icon_failed(d, @sf.t("web-pages.slackApp.drawFailed"))
      }
    } else {
      d.reading.set((@sf.avatars_base() + "/avatars/" + a.id + ".webp", @sf.app_icon_px, bg))
    }
  }
  let pick = fn(a : @sf.AppAvatar) {
    d.picked.set(a.id)
    d.upload.set("")
    let bg = if d.colour_set.untracked() { d.color.untracked() } else { a.bg }
    colour(bg)
    draw(a, bg)
  }
  // a new app starts as the general helper (else the first avatar), on its colour, once the avatars are read
  if fresh {
    let started = Ref(false)
    k.reacts(fn() { all().length() > @sf.app_makers.length() }, fn(read) {
      if read && !started.val {
        started.val = true
        let avatars = @signals.untracked(all)
        pick(find("general-helper").unwrap_or(avatars[0]))
      }
    })
  }
  // the picture being read, its pixels drawn into the icon once they are here (or why they could not be)
  k.pick(fn() { d.reading.get() }, fn(r, rd) {
    let (src, px, bg) = rd
    guard src != "" else { return }
    let read = @ui.tree_image_pixels(r, src, px)
    let state = fn() {
      match read() {
        None => 0
        Some(PixelsRead(_, _, _)) => 1
        Some(_) => 2
      }
    }
    r.reacts(state, fn(s) {
      match (s, @signals.untracked(read)) {
        (1, Some(PixelsRead(w, h, pixels))) => {
          let own = d.upload.untracked() != ""
          d.reading.set(("", 0, ""))
          if own {
            let icon = @sf.app_own_icon(w, h, pixels)
            let edge = @pixels.edge_colour(@sf.app_icon_px, @sf.app_icon_px, icon.pixels())
            d.upload_bg.set(edge)
            sa_icon_made(d, icon)
            if !d.colour_set.untracked() {
              colour(edge)
            }
          } else {
            match find(d.picked.untracked()) {
              Some(a) =>
                match @sf.app_avatar_icon(a, bg, w, h, pixels) {
                  Some(icon) => sa_icon_made(d, icon)
                  None => sa_icon_failed(d, @sf.t("web-pages.slackApp.drawFailed"))
                }
              None => ()
            }
          }
        }
        (2, _) => {
          let own = d.upload.untracked() != ""
          sa_icon_failed(d, @sf.t(if own { "web-pages.slackApp.readImageFailed" } else { "web-pages.slackApp.drawFailed" }))
        }
        _ => ()
      }
    })
  })
  // a picture of their own, from the system's picker
  let upload = fn() {
    if d.asking {
      return
    }
    let asked = (core.pick_picture)(fn(bytes) {
      d.asking = false
      match bytes {
        Some(b) => {
          let prev_upload = d.upload.untracked()
          sa_icons_made.val += 1
          let own = "mem:desk-slack-icon/own/\{sa_icons_made.val}"
          @ui.add_image(own, b)
          d.upload.set(own)
          d.picked.set("")
          d.reading.set((own, @sf.app_own_px, ""))
          if prev_upload != "" && prev_upload != own {
            @ui.forget_image(prev_upload)
          }
        }
        None => ()
      }
    })
    d.asking = asked
    if !asked {
      sa_icon_failed(d, @sf.t("web-pages.slackApp.readImageFailed"))
    }
  }
  // (typed in its colour's field: set by hand, what was picked drawn on it)
  k.reacts(fn() { d.hex_field.text().trim(chars=" ").to_owned() }, fn(typed) {
    if typed != d.color.untracked() {
      d.color.set(typed)
      d.colour_set.set(true)
      if @sf.hex_color(typed) is Some(_) {
        match find(d.picked.untracked()) {
          Some(a) => draw(a, typed)
          None => ()
        }
      }
    }
  })
  let ground = fn() { @sf.hex_color(d.color.get()).unwrap_or(@sf.theme().p.neutral_bg) }
  // (what it says on the colour chosen: a near black or white, whichever reads on it; the muted grey on none)
  let ink = fn() {
    match @sf.hex_color(d.color.get()) {
      Some(v) => @ui.ink_on(v, [0x24272BFFL, 0xFFFFFFFFL])
      None => @sf.theme().p.muted
    }
  }
  // its heading (as the phone's look: 头像), over what has a ground: so a card's corner it begins in holds words
  @sf.card_lines_node(k, fn() { @sf.t("android-settings.slack.icon") })
  k.box(fn(l) {
    @sf.style_node(l, fn() { sa_look })
    // its avatar (appAvatar: 136, the settings' corner, on the neutral ground behind its colour): pressed, a picture
    let ab = @sf.icon_well_node(l, fn() { @sf.t("web-pages.slackApp.upload") }, upload, ground, ink, fn() { d.shown.get() }, fn() {
      @sf.t(if fresh { "web-pages.slackApp.uploadShort" } else { "web-pages.slackApp.keep" })
    }, @sf.app_icon_px)
    @sf.tip_node(tips, ab, fn() { @sf.t("web-pages.slackApp.upload") }) |> ignore
    l.box(fn(m) {
      @sf.style_node(m, fn() { sa_look_main }, in_row=true)
      @sf.input_node(m, d.name_field, placeholder=@sf.t("web-pages.settings.workspace.name")) |> ignore
      @sf.input_node(m, d.desc_field, placeholder=@sf.t("web-pages.slackApp.descriptionPlaceholder")) |> ignore
      // what was picked's own colour, after one set by hand
      let recommended = fn() {
        match d.picked.get() {
          "" => d.upload_bg.get()
          id =>
            match all().iter().find_first(fn(a) { a.id == id }) {
              Some(a) => a.bg
              None => d.upload_bg.get()
            }
        }
      }
      @sf.swatch_field_node(m, d.hex_field, ground, @sf.t("web-pages.slackApp.color"), after=fn(c) {
        c.show(fn() { d.colour_set.get() && recommended() != "" && recommended().to_lower() != d.color.get().to_lower() }, fn(r) {
          @sf.quiet_action_node(r, fn() { @sf.t("web-pages.slackApp.recommended") }, fn() {
            let bg = @signals.untracked(recommended)
            d.colour_set.set(false)
            colour(bg)
            match find(d.picked.untracked()) {
              Some(a) => draw(a, bg)
              None => ()
            }
          })
          |> ignore
        })
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
  @sf.avatar_tiles_node(k, all, fn() { d.picked.get() }, width, pick, tips) |> ignore
  sa_permissions_node(k, d, sections, tips)
}

///|
/// The permissions, folded (sa_permissions', as nodes: @sf.check_groups_node) in `k`: the core's sections (`sections`, as
/// they are now) as the library's, each group on as the draft says it, ticked into it; open as the draft keeps it.
fn sa_permissions_node(k : @view.View, d : SaDraft, sections : () -> Array[Json], tips : @sf.TipLayer) -> Unit {
  @sf.check_groups_node(
    k,
    fn() {
      sections().map(fn(s) {
        let sv = Some(s)
        {
          title: text(sv, "title"),
          groups: items(sv, "groups").map(fn(g) {
            let gv = Some(g)
            { id: text(gv, "id"), label: text(gv, "label"), tip: text(gv, "tip"), fixed: flag(gv, "fixed"), admin: opt_text(gv, "admin") is Some(_) }
          }),
        }
      })
    },
    fn(id) { d.groups.get(id).unwrap_or(false) },
    fn(id, on) { d.groups[id] = on },
    fn() { d.perms.get() },
    fn() { d.perms.set(!d.perms.untracked()) },
    {
      summary: fn(on, all) { @sf.t("web-pages.slackApp.permissions", args=[("on", on.to_string()), ("all", all.to_string())]) },
      all_on: fn() { @sf.t("web-pages.slackApp.allOn") },
      select_all: fn() { @sf.t("web-pages.settings.members.all") },
      select_none: fn() { @sf.t("web-pages.settings.members.none") },
      admin: fn() { @sf.t("web-pages.slackApp.admin") },
    },
    tips,
  )
}

///|
/// How wide a page `w` wide leaves its column (settings_page's desk_column, a page's width given).
fn sa_column(w : Double) -> Double {
  dmin(desk_column_most, dmin(w - 2.0 * desk_lane_in, desk_lane_most) - 2.0 * desk_column_in)
}

///|
/// An icon made: shown in the look, and kept as it goes to Slack.
fn sa_icon_made(d : SaDraft, icon : @pixels.Canvas) -> Unit {
  let prev = d.shown.untracked()
  let (jpeg, url) = @sf.app_icon_jpeg(icon)
  sa_icons_made.val += 1
  let shown = "mem:desk-slack-icon/\{sa_icons_made.val}"
  @ui.add_image(shown, jpeg)
  d.shown.set(shown)
  d.icon.set(url)
  d.icon_error.set("")
  if prev != "" && prev != shown {
    @ui.forget_image(prev)
  }
}

///|
/// An icon that could not be made: why.
fn sa_icon_failed(d : SaDraft, words : String) -> Unit {
  d.reading.set(("", 0, ""))
  d.icon.set("")
  d.icon_error.set(words)
}

///|
/// The card's padding (20).
let sa_card_in : Double = 20.0

///|
/// The guide (tokenGuide: its steps 18 apart).
// kept across runs: a value (no field of it changes)
let sa_guide : @ui.Style = @ui.css("w=Full gap=S4_5")

///|
// kept across runs: a value (no field of it changes)
let sa_step : @ui.Style = @ui.css("row w=Full gap=S3 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let sa_step_body : @ui.Style = @ui.style(w=@sf.grow, gap=S1, align=AStart)

///|
/// The token's line (inputRow: the field as wide as is left, its button after it, 8 apart, 6 under the words).
// kept across runs: a value (no field of it changes)
let sa_input_row : @ui.Style = @ui.css("row w=Full pt=S1_5 gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sa_input_grow : @ui.Style = @ui.style(w=@sf.grow)

///|
/// Slack asking for approval (callout blue: 12 by 14 in, 10 apart, a corner of 14, in the blue's ink).
// kept across runs: a value (no field of it changes)
let sa_blue : @ui.Style = @ui.css("row w=Full px=S3_5 py=S3 gap=S2_5 radius=Xl1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sa_blue_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, w=Full)

///|
/// Its look (appLook: the avatar's well and the rest, 16 apart; appLookMain: 8 apart).
// kept across runs: a value (no field of it changes)
let sa_look : @ui.Style = @ui.css("row w=Full gap=S4 align=AStretch")

///|
// kept across runs: a value (no field of it changes)
let sa_look_main : @ui.Style = @ui.style(w=@sf.grow, gap=S2)

