// An invitation's link (/invite#<token>) opened in the app (still.fail apps/android settings/screens/Workspaces.kt
// openInvite, InviteLinkSheet, invitationToken): what it leads to, read as the account it would be accepted by
// (`invitation.preview`), shown in a sheet of half the screen before it is accepted (`invitation.accept`), that
// account chosen when more than one is signed in. Signed out, the sheet says to sign in first. Without a link (pasted
// instead), a field to paste one in.

///|
/// The invitation sheet's state: the link's token (None: one to paste), the account chosen, what each account was
/// told of it, and its acceptance.
priv struct Invite {
  token : @signals.Signal[String?]
  /// the link it was opened with (None: pasted)
  given : @signals.Signal[String?]
  chosen : @signals.Signal[String]
  /// what `invitation.preview` answered, by token and account: Ok(the preview) or Err(why not)
  read : @sf.LiveMap[String, Result[Json, String]]
  /// asked already, by token and account
  asked : @sf.LiveMap[String, Bool]
  accepting : @signals.Signal[Bool]
  error : @signals.Signal[String]
  /// the link written in, the sheet's field's
  field : @ui.Field
}

///|
let invite : Invite = {
  token: @signals.signal(None),
  given: @signals.signal(None),
  chosen: @signals.signal("", same=fn(a, b) { a == b }),
  read: @sf.LiveMap::new(),
  asked: @sf.LiveMap::new(),
  accepting: @signals.signal(false, same=fn(a, b) { a == b }),
  error: @signals.signal("", same=fn(a, b) { a == b }),
  field: @ui.Field::new(),
}

///|
fn invite_reset() -> Unit {
  invite.token.set(None)
  invite.given.set(None)
  invite.chosen.set("")
  invite.read.clear()
  invite.asked.clear()
  invite.accepting.set(false)
  invite.error.set("")
  invite.field.set("")
}

///|
/// An invitation's link opened in the app: what it leads to, before it is accepted.
fn open_invite(token : String) -> Unit {
  invite_reset()
  invite.token.set(Some(token))
  invite.given.set(Some(token))
  raise_sheet(InviteLink)
}

///|
/// The token of an invitation's link (`<cloud>/invite#<token>`), or what was pasted when it is a token by itself
/// .
fn invitation_token(words : String) -> String? {
  let t = words.trim(chars=" \n\t").to_owned()
  if t == "" {
    return None
  }
  let hash = match t.find("/invite#") {
    Some(i) => t.exact_view(start=i + 8).to_owned()
    None => ""
  }
  let token = if hash != "" {
    hash
  } else if t.contains("/") || t.contains(" ") {
    ""
  } else {
    t
  }
  match token.trim(chars=" \n\t").to_owned() {
    "" => None
    s => Some(s)
  }
}

///|
/// Its buttons at the end of a row, 8 apart, 6 over them and 24 under (InviteLinkSheet's Row).
// kept across runs: a value (no field of it changes)
let invite_buttons : @ui.Style = @ui.css("row w=Full pt=S1_5 pb=S6 gap=S2 justify=JEnd")

///|
/// The same in a dialog in the middle of the window, nothing under them: the dialog's foot is 24 from them as its sides.
// kept across runs: a value (no field of it changes)
let invite_buttons_in_dialog : @ui.Style = @ui.css("row w=Full pt=S1_5 gap=S2 justify=JEnd")

///|
/// The field the link is pasted in: a rectangle's corners (12), as the sheet's field was, not a capsule.
let invite_corner : Double = 12.0

///|
/// What it says (14, muted), the account's label (13, semibold), why it failed (13, red).
// kept across runs: a value (no field of it changes)
let invite_lead : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let invite_label : @ui.TextStyle = @ui.text_style(size=Meta, weight=Semibold, color=Fg)

///|
// kept across runs: a value (no field of it changes)
let invite_error : @ui.TextStyle = @ui.text_style(size=Meta, color=Danger)

///|
/// The invitation's sheet with no link yet: one to paste: the landing's 用邀请链接加入.
fn open_invite_link() -> Unit {
  invite_reset()
  raise_sheet(InviteLink)
}

///|
/// The account the invitation is read and accepted as, of `src`'s accounts as they are now: the one chosen, else the
/// first; "" none.
fn invite_sub(src : Source) -> String {
  let list = invite_accounts(src)
  match list.iter().find_first(fn(a) { text(Some(a), "sub") == invite.chosen.get() }) {
    Some(a) => text(Some(a), "sub")
    None =>
      match list.get(0) {
        Some(a) => text(Some(a), "sub")
        None => ""
      }
  }
}

///|
/// The accounts signed in, as the core says them now.
fn invite_accounts(src : Source) -> Array[Json] {
  match src.topic("accounts", {}).get().value {
    Some(Array(a)) => a
    _ => []
  }
}

///|
/// What the invitation's link was read to lead to as the account it would be accepted by: Ok(its preview), Err(why
/// not), None while it is read (or with no link yet).
fn invite_read(src : Source) -> Result[Json, String]? {
  match invite.token.get() {
    Some(tok) => invite.read.get(tok + "\u{1}" + invite_sub(src))
    None => None
  }
}

///|
/// Whether it is signed out (the core says no account signed in): nothing reads the invitation yet.
fn invite_signed_out(src : Source) -> Bool {
  src.topic("accounts", {}).get().value is Some(_) && invite_accounts(src).length() == 0
}

///|
/// The invitation sheet's title as it is now: to sign in first, to paste a link, the workspace it leads to, that it
/// cannot be used, that it is read.
fn invite_title(src : Source) -> String {
  if invite_signed_out(src) {
    return fill("android-misc.signIn.title", [("app", @sf.product())])
  }
  match (invite.token.get(), invite_read(src)) {
    (None, _) => tr("android-misc.invite.byLink")
    (Some(_), Some(Ok(p))) => fill("android-misc.invite.joinNamed", [("name", text(Some(p), "name"))])
    (Some(_), Some(Err(_))) => tr("android-misc.invite.unusable")
    (Some(_), None) => tr("android-misc.invite.loading")
  }
}

///|
/// Where the invitation sheet stands: signed out, a link to paste, why it cannot be used, read meanwhile, what it leads
/// to (invite_node's).
#derive(Eq)
priv enum InviteStands {
  InviteSignIn
  InvitePaste
  InviteUnusable(String)
  InviteReading
  InviteShown(String)
}

///|
/// The invitation's sheet (invite_sheet's, as nodes of the window's tree made once in `v`), over the pages or the
/// sign-in page, as the core and `invite` say it now: what the link leads to, read once per account (what it leads to
/// depends on who looks), that account chosen when more than one is signed in, joined from here; signed out, to sign in
/// first; with no link, a field to paste one in.
fn invite_node(v : @view.View, src : Source) -> Unit {
  // (read once per account and link: as either comes to be)
  v.reacts(fn() { (invite.token.get(), invite_sub(src)) }, fn(k) {
    match k {
      (Some(tok), sub) if sub != "" && !invite.asked.contains(tok + "\u{1}" + sub) => {
        let key = tok + "\u{1}" + sub
        invite.asked[key] = true
        (src.call)("invitation.preview", { "token": Json::string(tok), "account": Json::string(sub) }, fn(r) {
          invite.read[key] = match r {
            Ok(p) => Ok(p)
            Err(e) => Err(error_words(e))
          }
        })
      }
      _ => ()
    }
  })
  let stands = fn() {
    if invite_signed_out(src) {
      return InviteSignIn
    }
    match (invite.token.get(), invite_read(src)) {
      (None, _) => InvitePaste
      (Some(_), Some(Err(why))) => InviteUnusable(why)
      (Some(_), None) => InviteReading
      (Some(tok), Some(Ok(_))) => InviteShown(tok)
    }
  }
  v.pick(stands, fn(p, at) {
    @sf.style_node(p, fn() { @sf.panel_words_in_node(p).then(invite_column) })
    let lead = fn(words : () -> String) { @sf.words_node(p, words, fn() { invite_lead }) |> ignore }
    let buttons = fn(make : (@view.View) -> Unit) {
      p.box(fn(b) {
        // (24 under them on a sheet; in a dialog its own room under what it holds is that already)
        @sf.style_node(b, fn() { if @sf.in_dialog_node(b) { invite_buttons_in_dialog } else { invite_buttons } })
        make(b)
      })
      |> ignore
    }
    match at {
      InviteSignIn => {
        lead(fn() { fill("android-misc.signIn.invited", [("app", @sf.product())]) })
        buttons(fn(b) {
          @sf.button_node(b, fn() { tr("common.cancel") }, lower_sheet) |> ignore
          @sf.button_node(b, fn() { tr("android-misc.signIn.google") }, fn() { (src.sign_in)() }, tone=Primary, busy=fn() {
            (src.signing_in)()
          })
          |> ignore
        })
      }
      InvitePaste => {
        lead(fn() { fill("android-misc.invite.pasteLink", [("app", @sf.product())]) })
        let words = @signals.signal(invite.field.text())
        // (the link pasted in a rectangle with rounded corners (invite_corner), two lines of it at most, not a capsule)
        @sf.textarea_node(p, invite.field, rows=1, most=2, corner=invite_corner, placeholder="https://app.still.fail/invite#…", edited=fn(w) {
          words.set(w)
        })
        |> ignore
        buttons(fn(b) {
          @sf.button_node(b, fn() { tr("common.cancel") }, fn() {
            invite.field.take() |> ignore
            lower_sheet()
          })
          |> ignore
          @sf.button_node(
            b,
            fn() { tr("android-misc.invite.view") },
            fn() {
              let token = invitation_token(words.untracked())
              invite.field.take() |> ignore
              invite.token.set(token)
            },
            tone=Primary,
            disabled=fn() { invitation_token(words.get()) is None },
          )
          |> ignore
        })
      }
      InviteUnusable(why) => {
        lead(fn() { why })
        buttons(fn(b) {
          if @signals.untracked(fn() { invite.given.get() }) is None {
            @sf.button_node(b, fn() { tr("android-misc.invite.otherLink") }, fn() { invite.token.set(None) }) |> ignore
          }
          @sf.button_node(b, fn() { tr("common.close") }, lower_sheet, tone=Primary) |> ignore
        })
      }
      InviteReading => @sf.wait_line_node(p, fn() { tr("common.reading") }) |> ignore
      InviteShown(tok) => {
        let preview = fn() {
          match invite_read(src) {
            Some(Ok(pv)) => Some(pv)
            _ => None
          }
        }
        lead(fn() {
          let pv = preview()
          let inviter = match text(pv, "inviter") {
            "" => tr("android-misc.invite.someone")
            s => s
          }
          let email = text(pv, "email")
          fill(if email != "" { "android-misc.invite.invitedYouAsOnly" } else { "android-misc.invite.invitedYouAs" }, [
            ("inviter", inviter),
            ("role", @sfpages.role_words(text(pv, "role"))),
            ("email", email),
          ])
        })
        // (which account, where more than one is signed in)
        p.pick(fn() { invite_accounts(src).map(fn(a) { (text(Some(a), "sub"), text(Some(a), "email")) }) }, fn(w, list) {
          guard list.length() > 1 else { return }
          @sf.words_node(w, fn() { tr("android-misc.invite.whichAccount") }, fn() { invite_label }) |> ignore
          w.box(fn(rows) {
            @sf.style_node(rows, fn() { @sf.full_width })
            rows.each_of(fn() { list }, at_once=true, fn(row, a) {
              let (sub, email) = a
              @sf.choice_row_node(row, fn() { email }, fn() { invite_sub(src) == sub }, press=fn() { invite.chosen.set(sub) })
            })
          })
          |> ignore
        })
        p.show(at_once=true, fn() { invite.error.get() != "" }, fn(e) {
          @sf.words_node(e, fn() { invite.error.get() }, fn() { invite_error }) |> ignore
        })
        buttons(fn(b) {
          @sf.button_node(b, fn() { tr("common.cancel") }, lower_sheet) |> ignore
          @sf.button_node(
            b,
            fn() {
              let sub = invite_sub(src)
              let email = match invite_accounts(src).iter().find_first(fn(a) { text(Some(a), "sub") == sub }) {
                Some(a) => text(Some(a), "email")
                None => ""
              }
              fill("android-misc.invite.joinAs", [("email", email)])
            },
            fn() {
              let sub = invite_sub(src)
              accept_invite(src, tok, sub, text(@signals.untracked(preview), "name"))
            },
            tone=Primary,
            busy=fn() { invite.accepting.get() },
            disabled=fn() { invite_sub(src) == "" },
          )
          |> ignore
        })
      }
    }
  })
}

///|
/// What it holds: its parts 10 apart.
// kept across runs: a value (no field of it changes)
let invite_column : @ui.Style = @ui.css("w=Full gap=S2_5")

///|
/// The login sheet's body (login_sheet's, as nodes of the window's tree made once in `v`), over the pages in view, as
/// the core says the login of `login_link`'s target now, workspace `w`'s core reading it: its card; why it cannot be
/// read, or read meanwhile; ended. Seen under way while it is up, it closes by itself once finished or cancelled.
fn login_node(v : @view.View, src : Source, w : Workspace) -> Unit {
  let core = settings_core(src, w)
  v.pick(fn() { login_link.target.get() }, fn(p, target) {
    guard target is Some((station, id)) else { return }
    let topic = fn() { src.topic("machineLogin", { "station": Json::string(station), "id": Json::string(id) }).get() }
    p.reacts(fn() { (flag(topic().value, "active"), text(topic().value, "state")) }, fn(k) {
      let (active, state) = k
      if active {
        login_link.seen_active = true
      } else if login_link.seen_active && (state == "done" || state == "cancelled") {
        lower_sheet()
      }
    })
    // (0: read meanwhile; 1: why not; 2: its card; 3: ended)
    p.pick(
      fn() {
        let t = topic()
        match t.value {
          None => if t.error is Some(_) { 1 } else { 0 }
          Some(Object(_)) => 2
          Some(_) => 3
        }
      },
      fn(b, what) {
        match what {
          0 => @sf.wait_line_node(b, fn() { tr("common.reading") }) |> ignore
          1 => @sf.words_node(b, fn() { topic().error.map_or("", error_words) }, fn() { invite_error }) |> ignore
          2 => @sfpages.login_card_node(b, core, station, id, place="sheet")
          _ => @sf.words_node(b, fn() { tr("web-main.logins.ended") }, fn() { invite_lead }) |> ignore
        }
      },
    )
  })
}

///|
/// Accepted as `sub` (Cloud.acceptInvitationToken): the workspace joined is the one in view, Home at its top, and said
/// so; failed, why under it.
fn accept_invite(src : Source, token : String, sub : String, name : String) -> Unit {
  if src.read_only {
    toast_later(read_only_words)
    return
  }
  invite.accepting.set(true)
  invite.error.set("")
  (src.call)("invitation.accept", { "token": Json::string(token), "account": Json::string(sub) }, fn(r) {
    invite.accepting.set(false)
    match r {
      Ok(v) => {
        pick_workspace(src, text(Some(v), "id"))
        home()
        toast_later(fill("android-misc.invite.joined", [("name", name)]))
      }
      Err(e) => invite.error.set(error_words(e))
    }
  })
}

///|
/// A station login's link (/w/<ws>/s/<station>/login/<id>) opened in the app: its station and login id, and whether it
/// was seen active while this sheet was up (so it closes by itself once finished or cancelled).
priv struct LoginLinkState {
  target : @signals.Signal[(String, String)?]
  mut seen_active : Bool
}

///|
let login_link : LoginLinkState = {
  target: @signals.signal(None),
  seen_active: false,
}

///|
fn login_link_reset() -> Unit {
  login_link.target.set(None)
  login_link.seen_active = false
}

///|
/// A station login's link opened in the app: its dialog or sheet over the page in view.
fn open_login(station : String, id : String) -> Unit {
  login_link.target.set(Some((station, id)))
  login_link.seen_active = false
  raise_sheet(LoginLink, title=tr("web-main.logins.title"))
}

///|
/// What is over the pages put down, as a page opens from a link or a notification (AppState: sheet, menu null): the
/// sheets and the menus, a file open over the window (viewer.mbt) and a chat being shared as a picture (publish.mbt),
/// which would otherwise stay over the page that opened under them.
fn close_overlays() -> Unit {
  lower_sheet()
  app.menu = false
  @sf.close_all_presented()
  @sfbase.close_now()
  @sfpages.publish_close()
}
