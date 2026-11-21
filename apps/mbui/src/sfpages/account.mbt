// 账号, one page in every frame, the same
// on every width (the user, 2026-10-26: 「设置感觉很乱」; it was four sections and two cards wide, one card narrow): the
// accounts on this device on one card, the one in view first with who it is (its picture, name, email and how it
// signs in) and signing out of it, the others each signed out of by itself, another added, each one's picture changed
// by pressing it (one of its own from the system's photos, or its sign-in's again); where it is signed in (each device,
// signed out from here but this one); deleting the account, in red at the foot. Signing out and deleting asked first
// (@sf.confirm).

///|
/// 账号 (AccountSettings, MeScreen) made once as nodes in node `v`, laid out by the `width` its frame gives it, as who
/// is signed in says now (`here`): the accounts on this device on one card, the one in view with who it is, then the
/// others, each signed out of by itself, another added; where it is signed in; deleting it, in red at the foot. Pictures
/// asked for on `stint`, the page's time on top.
pub fn me_node(
  v : @view.View,
  core : Core,
  here : () -> Here,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  stint~ : () -> Int,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
) -> Unit {
  let name = fn() {
    let h = here()
    if h.person != "" { h.person } else { h.email }
  }
  let how = fn() {
    let sub = here().sub
    if sub.has_prefix("em-") || sub.has_prefix("pw-") {
      @sf.t("web-pages.settings.account.email")
    } else {
      @sf.t("web-pages.settings.account.google")
    }
  }
  let accounts = fn() {
    match (core.topic)("accounts", Map([])).get().value {
      Some(Array(a)) => a
      _ => []
    }
  }
  let others = fn() {
    let sub = here().sub
    accounts().filter(fn(a) { text(Some(a), "sub") != sub })
  }
  // a picture picked as theirs, once read: made their face and put up (own_picture's reading, as it is picked)
  v.pick(fn() { own_picture.reading.get() }, fn(r, src) {
    guard src != "" else { return }
    let read = @ui.tree_image_pixels(r, src, @sf.face_picture_read)
    r.reacts(read, fn(got) {
      match got {
        None => ()
        Some(PixelsRead(w, h, px)) => {
          let sub = own_picture.sub.untracked()
          own_picture.reading.set("")
          @settings.act(
            core,
            @sf.t("android-settings.me.pictureWhat"),
            "account.setPicture",
            obj([("account", str(sub)), ("picture", str(@sf.face_picture(w, h, px)))]),
            done=@sf.t("android-settings.me.pictureSet"),
          )
        }
        Some(_) => {
          own_picture.reading.set("")
          (core.say)(@sf.t("android-settings.me.pictureUnread"))
        }
      }
    })
  })
  // signing out of one: asked first, then the chats (the account in view goes with it)
  let sign_out = fn(sub : String, email : String) {
    @sf.confirm(
      @sf.t("web-pages.settings.account.signOutConfirm", args=[("email", email)]),
      @sf.t("web-pages.settings.account.signOutConfirmBody"),
      @sf.t("web-pages.settings.account.signOutAction"),
      fn() {
        if sub == @signals.untracked(here).sub {
          (core.home)()
        }
        @settings.act(
          core,
          @sf.t("web-pages.settings.account.signOut"),
          "auth.signOut",
          obj([("account", str(sub))]),
          done=@sf.t("web-pages.settings.account.signedOut", args=[("email", email)]),
        )
      },
    )
  }
  let delete = fn() {
    let h = @signals.untracked(here)
    @sf.confirm(
      @sf.t("web-pages.settings.account.delete"),
      @sf.t("web-pages.settings.account.deleteConfirmBody", args=[("email", h.email)]),
      @sf.t("web-pages.settings.account.deleteAction"),
      danger=true,
      fn() {
        (core.home)()
        @settings.act(
          core,
          @sf.t("web-pages.settings.account.deleteAction"),
          "auth.deleteAccount",
          obj([("account", str(h.sub))]),
          done=@sf.t("web-pages.settings.account.deleted", args=[("email", h.email)]),
        )
      },
    )
  }
  @sf.page_node(v, fn() { @sf.t("android-settings.me.title") }, on_back~, frame~, said?, width?, fn() { ["accounts", "sessions", "delete"] }, fn(
    b,
    key,
  ) {
    match key {
      // the accounts on this device on one card: the one in view with who it is, then the others, each signed out
      // of by itself, another added
      "accounts" =>
        @sf.group_node(b, fn(g) {
          @sf.link_row_node(
            g,
            name,
            fn() {  },
            note=fn() { here().email + " · " + how() },
            strong=true,
            goes=false,
            lead=LeadMade(fn(l) {
              own_face_node(l, core, fn() { here().sub }, fn() { here().email }, name, fn() { here().picture }, stint)
            }),
            control=fn(e) {
              // (in the card's top end corner, concentric with it: its lines under it the row's whole width)
              @sf.row_corner_button_node(
                e,
                fn() { @sf.t(if others().length() > 0 { "android-settings.me.signOut" } else { "android-settings.me.signOutOnly" }) },
                fn() {
                  let h = @signals.untracked(here)
                  sign_out(h.sub, h.email)
                },
              )
              |> ignore
            },
          )
          // (the others kept by who they are: a row reads its own, told only as that one changes: View::keyed_by)
          let others_by = g.keyed_by(others, fn(a) { text(Some(a), "sub") })
          g.each(fn() { others_by.keys() }, fn(k) { k }, fn(row, sub) {
            let sub = sub.untracked()
            let a = fn() { others_by.get(sub) }
            let email = fn() { text(a(), "email") }
            let shown = fn() { if text(a(), "name") != "" { text(a(), "name") } else { email() } }
            // each with their face, changed by pressing it as the one in view's
            @sf.link_row_node(
              row,
              email,
              fn() {  },
              goes=false,
              face=true,
              lead=LeadMade(fn(l) { own_face_node(l, core, fn() { sub }, email, shown, fn() { text(a(), "picture") }, stint) }),
              control=fn(e) {
                @sf.row_end_button_node(e, fn() { @sf.t("android-settings.me.signOut") }, fn() { sign_out(sub, @signals.untracked(email)) })
                |> ignore
              },
            )
          })
          // (its ＋ as large as a chevron at either width, in the title's ink: row_lead_mark's)
          @sf.link_row_node(g, fn() { @sf.t("android-settings.me.addAccount") }, fn() { (core.sign_in)() }, chevron=false, lead=LeadLine(fn(
            l,
          ) {
            @sf.row_lead_mark_node(l, "plus")
          }))
        })
      "sessions" =>
        @sf.section_node(
          b,
          fn() { @sf.t("web-pages.settings.account.sessions") },
          note=fn() { @sf.t("web-pages.settings.account.sessionsLead", args=[("name", @sf.product())]) },
          fn(sec) { acc_devices_node(sec, core, here) },
        )
      // deleting the account in view, at the foot, in red
      _ =>
        @sf.group_node(b, fn(g) {
          @sf.link_row_node(g, fn() { @sf.t("android-settings.me.delete") }, delete, danger=true, chevron=false)
        })
    }
  })
}

///|
/// The face of an account on this device (`sub`, `email`, `name`, its `picture`, each as it says now) in `parent`,
/// pressed to change it: a camera in its corner says so, spinning while a change of it goes (each change once at a
/// time, of any account). Pressed, the system's photos at once; once it has a picture of its own, a menu beside it to
/// pick another or to take its sign-in's again. Its picture asked for on `stint`.
fn own_face_node(
  parent : @view.View,
  core : Core,
  sub : () -> String,
  email : () -> String,
  name : () -> String,
  picture : () -> String,
  stint : () -> Int,
) -> Unit {
  let picking = fn() { own_picture.asking.get() || own_picture.reading.get() != "" }
  let busy = fn() {
    (picking() && own_picture.sub.get() == sub()) ||
    is_doing(core, ["account.setPicture", "account.removePicture"], [("account", sub())])
  }
  @sf.action_box_node(parent, fn() { @sf.t("android-settings.me.picture") }, disabled=fn() { busy() || picking() }, fn(f) {
      let sub = @signals.untracked(sub)
      if !@signals.untracked(fn() { own_picture_of(core, sub) }) {
        pick_own_picture(core, sub)
      } else {
        @sf.menu(
          [
            Some(@sf.menu_item_of(@sf.t("android-settings.me.picture"), icon="photo", fn() { pick_own_picture(core, sub) })),
            Some(
              @sf.menu_item_of(@sf.t("android-settings.me.pictureDefault"), icon="user", fn() {
                @settings.act(
                  core,
                  @sf.t("android-settings.me.pictureDefaultWhat"),
                  "account.removePicture",
                  obj([("account", str(sub))]),
                  done=@sf.t("android-settings.me.pictureDefaultSet"),
                )
              }),
            ),
          ],
          from=Node(f),
        )
      }
    }, fn(f) {
    @sf.style_node(f, fn() { own_face_room })
    @sf.avatar_node(f, email, name, fn() {
      let p = picture()
      if p == "" { "" } else { (core.picture)(p, stint()) }
    }, acc_picture)
    // the camera in its corner (or what turns while a change of it goes), standing off the face
    f.box(fn(badge) {
      @sf.style_node(badge, fn() { own_face_badge })
      badge.over(Is(true)) |> ignore
      badge.offset(By(fn() { (acc_picture - own_face_badge_side - own_face_badge_out, acc_picture - own_face_badge_side - own_face_badge_out) })) |> ignore
      badge.pick(busy, fn(m, turning) {
        if turning {
          @sf.spinner_node(m, size=own_face_mark) |> ignore
        } else {
          @sf.icon_node(m, "camera", own_face_mark, By(fn() { @sf.theme().p.text })) |> ignore
        }
      })
    })
    |> ignore
  })
  |> ignore
}

///|
/// The face pressed: round, as it is.
// kept across runs: a value (no field of it changes)
let own_face_room : @ui.Style = @ui.css("radius=Full")

///|
/// The camera in its corner: a small disc of the card's ground, standing off the face.
// kept across runs: a value (no field of it changes)
let own_face_badge : @ui.Style = @ui.css("w=S6 h=S6 radius=Full bg=Card align=ACenter justify=JCenter")

///|
/// How far the camera's disc stands past the face's edge (its corner's).
let own_face_badge_out : Double = -4.0

///|
/// The camera's (or the spinner's) size in its disc.
let own_face_mark : Double = 14.0

///|
/// The camera's disc's side (own_face_badge's S6).
let own_face_badge_side : Double = 24.0

///|
/// Where the account is signed in (the `loginSessions` topic) in node `parent`, as who is signed in says now (`here`):
/// each device's name (this one marked 当前), when it signed in and until when; 退出 on the others
/// (`loginSession.revoke`). On a card. Read the first time, rows' shapes where their card's rows will be (3); what
/// failed, said in red.
fn acc_devices_node(parent : @view.View, core : Core, here : () -> Here) -> Unit {
  let topic = fn() { (core.topic)("loginSessions", { "account": str(here().sub) }).get() }
  let shows = fn() {
    let t = topic()
    match (t.value, t.error) {
      (Some(Array(_)), _) => 0
      (_, Some(_)) => 1
      _ => 2
    }
  }
  parent.pick(shows, fn(p, k) {
    match k {
      0 =>
        devices_list_node(p, core, here, fn() {
          match topic().value {
            Some(Array(a)) => a
            _ => []
          }
        })
      1 =>
        @sf.page_note_node(
          p,
          fn() {
            @sf.t("web-pages.settings.account.sessionsFailed", args=[("error", topic().error.map(error_text).unwrap_or(""))])
          },
          bad=fn() { true },
        )
      _ =>
        @sf.waiting_node(p, fn(s) { devices_list_node(s, core.quiet(), here, devices_sample) }, note=fn() {
          { reading: true, text: @sf.t("common.reading"), failing: [] }
        })
    }
  })
}

///|
/// The devices the account is signed in on (`list()`) in node `parent`, on a card: each a row of its own by its id,
/// its name (当前 after it on this one), 退出 at its end on the others (turning while that goes), when it signed in and
/// until when under them.
fn devices_list_node(parent : @view.View, core : Core, here : () -> Here, list : () -> Array[Json]) -> Unit {
  @sf.group_node(parent, fn(g) {
    // (kept by their ids: a row reads its own device, told only as that one changes: View::keyed_by)
    let by_id = g.keyed_by(list, fn(d) { text(Some(d), "id") })
    g.each(fn() { by_id.keys() }, fn(k) { k }, fn(row, id) {
      let id = id.untracked()
      let dv = fn() { by_id.get(id) }
      let current = fn() { flag(dv(), "current") }
      let name = fn() {
        match text(dv(), "name") {
          "" => @sf.t("web-pages.settings.account.unnamedDevice")
          n => n
        }
      }
      let times = fn() {
        let d = dv()
        @sf.t("web-pages.settings.account.sessionTimes", args=[("time", stamp(d, "created_at", "ago")), ("until", stamp(d, "expires_at", "until"))])
      }
      row.pick(current, fn(r, here_now) {
        @sf.link_row_node(
          r,
          name,
          fn() {  },
          note=times,
          goes=false,
          title_after?=if here_now { Some(fn(a) { ws_you_node(a, fn() { @sf.t("web-pages.settings.account.here") }) }) } else { None },
          control?=if here_now {
            None
          } else {
            Some(fn(e) {
              @sf.row_end_button_node(
                e,
                fn() { @sf.t("web-pages.settings.account.revoke") },
                fn() {
                  @settings.act(
                    core,
                    @sf.t("web-pages.settings.account.revoke"),
                    "loginSession.revoke",
                    obj([("id", str(id)), ("account", str(@signals.untracked(here).sub))]),
                    done=@sf.t("web-pages.settings.account.revoked"),
                  )
                },
                busy=fn() { is_doing(core, ["loginSession.revoke"], [("id", id)]) },
              )
              |> ignore
            })
          },
        )
      })
    })
  })
}

///|
/// A picture of an account's own being had: asked of the system's photo picker, then read to be made its face
/// (me_node), for the account it was asked for (it may be another by then); each as it changes, what shows it
/// following.
priv struct OwnPicture {
  /// the account it is for
  sub : @signals.Signal[String]
  /// asked of the system's photo picker
  asking : @signals.Signal[Bool]
  /// the picture picked, being read (its key), "" none
  reading : @signals.Signal[String]
}

///|
// kept across runs: put back as a run begins (own_picture_reset)
let own_picture : OwnPicture = {
  sub: @signals.signal(""),
  asking: @signals.signal(false),
  reading: @signals.signal(""),
}

///|
/// Pictures picked as an account's own, each its own key.
let own_pictures : Ref[Int] = Ref(0)

///|
fn own_picture_reset() -> Unit {
  own_picture.sub.set("")
  own_picture.asking.set(false)
  own_picture.reading.set("")
  own_pictures.val = 0
}

///|
/// The system's photo picker asked for a picture to be the account `sub`'s own; the one picked read by me_node.
fn pick_own_picture(core : Core, sub : String) -> Unit {
  own_picture.sub.set(sub)
  let asked = (core.pick_picture)(fn(bytes) {
    own_picture.asking.set(false)
    match bytes {
      Some(b) => {
        own_pictures.val += 1
        let key = "mem:own-picture/\{own_pictures.val}"
        @ui.add_image(key, b)
        own_picture.reading.set(key)
      }
      None => ()
    }
  })
  own_picture.asking.set(asked)
  if !asked {
    (core.say)(@sf.t("android-settings.me.pictureUnread"))
  }
}

///|
/// Whether the account `sub` shows a picture of its own (the `workspaces` topic's `ownPicture`), rather than its
/// sign-in's.
fn own_picture_of(core : Core, sub : String) -> Bool {
  match (core.topic)("workspaces", Map([])).get().value {
    Some(Array(entries)) =>
      entries.iter().any(fn(e) { text(field(Some(e), "account"), "sub") == sub && flag(Some(e), "ownPicture") })
    _ => false
  }
}

///|
let acc_picture : Double = @sf.identity_mark

///|
/// (a narrow page's foot: what takes something away, 16 over it)
// kept across runs: a value (no field of it changes)
pub let acc_narrow_foot : @ui.Style = @ui.css("w=Full pt=S4")

///|
/// Devices made up, for what is shown while they are read (devices_list_node in its bones): this one and two others.
fn devices_sample() -> Array[Json] {
  [(6, true), (9, false), (7, false)].mapi(fn(i, d) {
    Json::object({
      "id": Json::string("sample" + i.to_string()),
      "name": Json::string(@sf.sample_words(d.0)),
      "current": Json::boolean(d.1),
      "created_at": { "ago": Json::string(@sf.sample_words(4)) },
      "expires_at": { "until": Json::string(@sf.sample_words(4)) },
    })
  })
}
