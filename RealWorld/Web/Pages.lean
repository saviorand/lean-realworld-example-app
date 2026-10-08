module

public import Routing
public import Datastar.Core
public import RealWorld.Service
public import RealWorld.Web.Routes
public import RealWorld.Web.Views

public section

/-!
The browser-facing site. Pages are rendered on the server; anything that changes data is a
Datastar request, answered with the elements that changed or with a redirect. Signing in sets an
`HttpOnly` cookie holding the same JWT the API issues.
-/

namespace RealWorld.Web

open Std Async
open Std Http Server
open Routing

abbrev Handler := Request Body.Stream → ContextAsync (Response Body.Any)

def cookieName : String := "jwt"

/-- Who is signed in. A cookie that no longer verifies reads as nobody, so an expired session
shows the signed-out site rather than an error. -/
def viewer (env : Env) (req : Request Body.Stream) : ContextAsync (Option Db.UserRow) := do
  let some token := (req.extensions.get Middleware.Cookies).bind (·.get cookieName) | pure none
  match ← (Service.userOfToken env token).run with
  | .ok user => pure user
  | .error _ => pure none

/-! ## Pages -/

def html (page : String) : ContextAsync (Response Body.Any) := Response.ok.html page

def redirectTo (location : String) : ContextAsync (Response Body.Any) :=
  Response.withStatus .seeOther
    |>.header (Header.Name.mk "location") (Middleware.Header.Value.ofStringSanitized location)
    |>.text ""

def notFound (env : Env) : Handler := fun req => do
  Response.notFound.html (Views.notFoundPage (← viewer env req))

def pageNumber (req : Request Body.Stream) : Nat :=
  max 1 (((param req "page").bind String.toNat?).getD 1)

private def offset (page : Nat) : Nat := (page - 1) * Views.pageSize

private def showFeed (env : Env) (req : Request Body.Stream) (me : Option Db.UserRow)
    (feed : Views.Feed) : ContextAsync (Response Body.Any) := do
  let page := pageNumber req
  let filter : Db.Filter := match feed with
    | .global => {}
    | .following => { feed := true }
    | .tag name => { tag := some name }
  let result ← (do
    let (rows, count) ← Service.articles env (me.map Db.UserRow.id) filter Views.pageSize (offset page)
    pure (rows, count, ← Service.tags env)).run
  match result with
  | .ok (rows, count, tags) =>
    html (Views.homePage me feed rows count.toInt.toNat page (tags.extract 0 20))
  | .error _ => notFound env req

def home (env : Env) : Handler := fun req => do
  let me ← viewer env req
  match param req "feed", me with
  | some "following", none => redirectTo Site.links.login
  | some "following", some _ => showFeed env req me .following
  | _, _ => showFeed env req me .global

def tag (env : Env) (name : String) : Handler := fun req => do
  showFeed env req (← viewer env req) (.tag name)

def loginPage (env : Env) (registering : Bool) : Handler := fun req => do
  match ← viewer env req with
  | some _ => redirectTo Site.links.home
  | none => html (Views.authPage registering)

def settingsPage (env : Env) : Handler := fun req => do
  match ← viewer env req with
  | some me => html (Views.settingsPage me)
  | none => redirectTo Site.links.login

def editorPage (env : Env) : Handler := fun req => do
  match ← viewer env req with
  | some me => html (Views.editorPage me none)
  | none => redirectTo Site.links.login

def editArticlePage (env : Env) (slug : String) : Handler := fun req => do
  let some me ← viewer env req | redirectTo Site.links.login
  match ← (Service.article env slug (some me.id)).run with
  | .ok a => if a.authorId == me.id then html (Views.editorPage me (some a)) else redirectTo (Site.links.article slug)
  | .error _ => notFound env req

def articlePage (env : Env) (slug : String) : Handler := fun req => do
  let me ← viewer env req
  let viewerId := me.map Db.UserRow.id
  match ← (return (← Service.article env slug viewerId, ← Service.comments env slug viewerId)).run with
  | .ok (a, comments) => html (Views.articlePage me a comments)
  | .error _ => notFound env req

def profilePage (env : Env) (favorites : Bool) (username : String) : Handler := fun req => do
  let me ← viewer env req
  let page := pageNumber req
  let filter : Db.Filter := if favorites then { favoritedBy := some username } else { author := some username }
  let result ← (do
    let p ← Service.profile env username (me.map Db.UserRow.id)
    let (rows, count) ← Service.articles env (me.map Db.UserRow.id) filter Views.pageSize (offset page)
    pure (p, rows, count)).run
  match result with
  | .ok (p, rows, count) => html (Views.profilePage me p favorites rows count.toInt.toNat page)
  | .error _ => notFound env req

/-! ## Actions -/

/-- The cookie that holds a signed-in user's token. `SameSite=Lax` keeps it off requests another
site starts, and `HttpOnly` out of reach of scripts. -/
private def sessionCookie (value : String) (maxAge : Int) : Middleware.SetCookie :=
  { name := cookieName, value
    attrs := { path := some "/", httpOnly := true, sameSite := some .lax, maxAge := some maxAge } }

private def respond (events : List Datastar.DatastarEvent) : ContextAsync (Response Body.Any) :=
  Datastar.sseResponse fun sse => for event in events do sse.send event

private def redirect (url : String) : Datastar.DatastarEvent :=
  Datastar.toEvent (Datastar.executeScript s!"window.location.href = {Json.renderString url}")

private def patch (node : Html.Node .flow) : Datastar.DatastarEvent :=
  Datastar.toEvent (Datastar.patchElements node.render)

private def signIn (env : Env) (user : Db.UserRow) (to : String) : ContextAsync (Response Body.Any) := do
  let token ← (env.tokens.issue user.id : IO _)
  return Middleware.appendSetCookie (← respond [redirect to]) (sessionCookie token (60 * 60 * 24 * 7))

private def showErrors (id : String) (e : ApiError) : ContextAsync (Response Body.Any) :=
  respond [patch (Views.errors id (some e))]

/-- Whether Datastar sent the request. Its `fetch` sets this header, which another origin cannot
send here: the CORS preflight it needs does not allow it. -/
private def isDatastar (req : Request Body.Stream) : Bool :=
  (req.line.headers.get? (Header.Name.mk "datastar-request")).isSome

/-- The signals a Datastar request carries; an absent or unreadable set reads as none. -/
private def signals (req : Request Body.Stream) : ContextAsync Json := do
  match ← Datastar.signalsText req with
  | .ok text => pure ((Json.parse text).toOption.getD (.obj #[]))
  | .error _ => pure (.obj #[])

/-- An action: refuses anything Datastar did not send, then runs `act` with the signed-in user,
sending anyone else to the sign-in page. -/
private def action (env : Env) (act : Db.UserRow → Json → ContextAsync (Response Body.Any)) : Handler :=
  fun req => do
    unless isDatastar req do return ← Response.forbidden.text "Datastar requests only"
    match ← viewer env req with
    | some me => act me (← signals req)
    | none => respond [redirect Site.links.login]

private def guestAction (act : Json → ContextAsync (Response Body.Any)) : Handler := fun req => do
  unless isDatastar req do return ← Response.forbidden.text "Datastar requests only"
  act (← signals req)

def loginAction (env : Env) : Handler := guestAction fun signals => do
  match ← (Service.login env signals).run with
  | .ok user => signIn env user Site.links.home
  | .error e => showErrors "errors" e

def registerAction (env : Env) : Handler := guestAction fun signals => do
  match ← (Service.register env signals).run with
  | .ok user => signIn env user Site.links.home
  | .error e => showErrors "errors" e

def logoutAction : Handler := guestAction fun _ => do
  return Middleware.appendSetCookie (← respond [redirect Site.links.home]) (sessionCookie "" 0)

/-- The settings form always sends a password; left empty, it means "keep the current one". -/
def withoutEmptyPassword : Json → Json
  | .obj fields => .obj (fields.map fun (key, value) =>
      match key, value with
      | "user", .obj user => (key, .obj (user.filter fun (name, v) => !(name == "password" && v == .str "")))
      | _, _ => (key, value))
  | json => json

def settingsAction (env : Env) : Handler := action env fun me signals => do
  match ← (Service.updateUser env me (withoutEmptyPassword signals)).run with
  | .ok user => respond [redirect (Site.links.profile user.username)]
  | .error e => showErrors "errors" e

/-- The editor's signals as the API's article body, whose `article` the `article` signal is. -/
def articleBody (signals : Json) : Json :=
  .obj #[("article", (signals.get? [.field "article"]).getD (.obj #[]))]

/-- The editor's tag pills, for the `article.tagList` the browser holds, normalized as the API
will normalize them. -/
def tagPillsAction : Handler := guestAction fun signals => do
  let tags := match signals.get? [.field "article", .field "tagList"] with
    | some (.arr items) => normalizeTags (items.filterMap fun | .str s => some s | _ => none)
    | _ => #[]
  respond [patch (Views.tagPills tags)]

def createAction (env : Env) : Handler := action env fun me signals => do
  match ← (Service.createArticle env me (articleBody signals)).run with
  | .ok art => respond [redirect (Site.links.article art.slug)]
  | .error e => showErrors "errors" e

def updateAction (env : Env) (slug : String) : Handler := action env fun me signals => do
  match ← (Service.updateArticle env me slug (pure (articleBody signals))).run with
  | .ok art => respond [redirect (Site.links.article art.slug)]
  | .error e => showErrors "errors" e

def deleteArticleAction (env : Env) (slug : String) : Handler := action env fun me _ => do
  match ← (Service.deleteArticle env me slug).run with
  | .ok () => respond [redirect Site.links.home]
  | .error _ => respond [redirect (Site.links.article slug)]

private def place (req : Request Body.Stream) : Views.Place :=
  match param req "place" with
  | some "top" | some "bottom" => .top
  | some "profile" => .profile
  | _ => .preview

def favoriteAction (env : Env) (favorite : Bool) (slug : String) : Handler := fun req =>
  action env (fun me _ => do
    match ← (Service.setFavorite env me slug favorite).run with
    | .ok a =>
      let buttons := match place req with
        | .preview => [Views.favoriteButton a .preview]
        | _ => [Views.favoriteButton a .top, Views.favoriteButton a .bottom]
      respond (buttons.map fun b => patch b.toFlow)
    | .error _ => respond [redirect (Site.links.article slug)]) req

def followAction (env : Env) (following : Bool) (username : String) : Handler := fun req =>
  action env (fun me _ => do
    match ← (Service.setFollowing env me username following).run with
    | .ok p =>
      let places := if place req == .profile then [Views.Place.profile] else [.top, .bottom]
      respond (places.map fun at_ => patch (Views.followButton p.username p.following at_).toFlow)
    | .error _ => respond [redirect (Site.links.profile username)]) req

def commentAction (env : Env) (slug : String) : Handler := action env fun me signals => do
  match ← (Service.addComment env me slug (pure signals)).run with
  | .ok c =>
    respond [
      Datastar.toEvent (Datastar.patchElements (Views.commentCard (some me) slug c).render
        (selector := some "#comments") (mode := .prepend)),
      patch (Views.errors "comment-errors"),
      Datastar.toEvent (Datastar.patchSignals (Json.compress (.obj #[("comment", .obj #[("body", .str "")])])))]
  | .error e => showErrors "comment-errors" e

def deleteCommentAction (env : Env) (slug : String) (id : Nat) : Handler := action env fun me _ => do
  match ← (Service.deleteComment env me slug id).run with
  | .ok () => respond [Datastar.toEvent (Datastar.removeElements s!"#comment-{id}")]
  | .error e => showErrors "comment-errors" e

open Site in
def routes (env : Env) : List (Route Result) :=
  [ .get patterns.home (home env),
    .get patterns.tag (tag env),
    .get patterns.login (loginPage env false),
    .post patterns.login (loginAction env),
    .get patterns.register (loginPage env true),
    .post patterns.register (registerAction env),
    .get patterns.settings (settingsPage env),
    .post patterns.settings (settingsAction env),
    .post patterns.logout logoutAction,
    .get patterns.editor (editorPage env),
    .post patterns.editor (createAction env),
    .get patterns.editArticle (editArticlePage env),
    .post patterns.editArticle (updateAction env),
    .get patterns.tagPills tagPillsAction,
    .get patterns.article (articlePage env),
    .delete patterns.article (deleteArticleAction env),
    .post patterns.favorite (favoriteAction env true),
    .delete patterns.favorite (favoriteAction env false),
    .post patterns.comments (commentAction env),
    .delete patterns.comment (deleteCommentAction env),
    .get patterns.profile (profilePage env false),
    .get patterns.favorites (profilePage env true),
    .post patterns.follow (followAction env true),
    .delete patterns.follow (followAction env false) ]

end RealWorld.Web
