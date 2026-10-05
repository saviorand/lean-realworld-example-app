module

public import RealWorld.Http
public import RealWorld.Password
public import RealWorld.Slug

public section

/-!
What the application does, independent of how it is asked: the JSON API and the web pages both
call these, so a rule such as "only an article's author may edit it" is written once.

Bodies arrive as `ApiM Json` rather than `Json` where the spec puts other failures first: an update
to an article that does not exist is a 404 even when its body is malformed.
-/

namespace RealWorld.Service

open Std Async

/-- Runs blocking work, such as a key derivation, on a thread of its own, so the threads serving
other requests are not held up by it. -/
def offload (act : IO α) : ApiM α := do
  let task ← (IO.asTask act (prio := .dedicated) : IO _)
  match ← (Async.ofTask task : Async _) with
  | .ok a => pure a
  | .error e => throwThe IO.Error e

private def conflicts (usernameTaken emailTaken : Bool) : ApiM Unit :=
  ofExcept <| collect .conflict
    [("username", if usernameTaken then some "has already been taken" else none),
     ("email", if emailTaken then some "has already been taken" else none)]

/-- Turns a unique violation that slipped past the check, because another request took the name
in between, into the same answer the check would have given. -/
private def unlessTaken (act : IO α) : IO (Except ApiError α) :=
  tryCatch (.ok <$> act) fun e =>
    match Db.uniqueViolation? e with
    | some "users_email_key" => pure (.error (ApiError.taken "email"))
    | some "users_username_key" => pure (.error (ApiError.taken "username"))
    | _ => throw e

/-- The user a token was issued to, if it verifies and they still exist. -/
def userOfToken (env : Env) (token : String) : ApiM (Option Db.UserRow) := do
  let some id ← (env.tokens.verify token : IO _) | pure none
  withDb env (Db.userById · id)

def token (env : Env) (user : Db.UserRow) : ApiM String := (env.tokens.issue user.id : IO _)

/-! ## Users -/

private def reload (env : Env) (id : Int64) : ApiM Db.UserRow := do
  let some user ← withDb env (Db.userById · id) | fail ApiError.tokenInvalid
  pure user

def register (env : Env) (body : Json) : ApiM Db.UserRow := do
  let r ← ofExcept (Registration.parse body)
  let (usernameTaken, emailTaken) ← withDb env (Db.taken · (some r.username) (some r.email))
  conflicts usernameTaken emailTaken
  let hash ← offload (Password.hash r.password)
  let id ← ofExcept (← withDb env fun db => unlessTaken (Db.insertUser db r.username r.email hash))
  reload env id

/-- What a login attempt answers, given the account its email names, if any, and whether the
password matched it. -/
def loginOutcome : Option Db.UserRow → Bool → Except ApiError Db.UserRow
  | some user, true => .ok user
  | _, _ => .error ApiError.credentials

/-- A failed login says nothing about whether the email has an account: the answer for an unknown
email is the answer for a wrong password. The work is the same too, since an unknown email is
checked against a stored hash all the same. -/
theorem loginOutcome_unknown_email (user : Db.UserRow) (matched : Bool) :
    loginOutcome none matched = loginOutcome (some user) false := by
  cases matched <;> rfl

def login (env : Env) (body : Json) : ApiM Db.UserRow := do
  let l ← ofExcept (Login.parse body)
  let account ← withDb env (Db.userByEmail · l.email)
  let stored := (account.map (·.passwordHash)).getD env.decoy
  ofExcept (loginOutcome account (← offload (Password.verify l.password stored)))

def updateUser (env : Env) (me : Db.UserRow) (body : Json) : ApiM Db.UserRow := do
  let u ← ofExcept (UserUpdate.parse body)
  let (usernameTaken, emailTaken) ← withDb env (Db.taken · u.username u.email (some me.id))
  conflicts usernameTaken emailTaken
  let hash ← match u.password with
    | some password => some <$> offload (Password.hash password)
    | none => pure none
  ofExcept (← withDb env fun db => unlessTaken (Db.updateUser db me.id u hash))
  reload env me.id

/-! ## Profiles -/

def profile (env : Env) (username : String) (viewer : Option Int64) : ApiM Db.ProfileRow := do
  let some p ← withDb env (Db.profile · username viewer) | fail (ApiError.notFound "profile")
  pure p

def setFollowing (env : Env) (me : Db.UserRow) (username : String) (following : Bool) :
    ApiM Db.ProfileRow := do
  let p ← profile env username (some me.id)
  withDb env fun db => if following then Db.follow db me.id p.id else Db.unfollow db me.id p.id
  pure { p with following }

/-! ## Articles -/

def articles (env : Env) (viewer : Option Int64) (filter : Db.Filter) (limit offset : Nat) :
    ApiM (Array Db.ArticleRow × Int64) :=
  withDb env (Db.articles · viewer filter limit offset)

def article (env : Env) (slug : String) (viewer : Option Int64) : ApiM Db.ArticleRow := do
  let some a ← withDb env (Db.articleBySlug · slug viewer) | fail (ApiError.notFound "article")
  pure a

/-- Writes with `base` as the slug, or, if another article already has it, with a short random
suffix after it. The unique index decides, so two articles created at once with the same title
cannot end up with the same slug. -/
private def withUniqueSlug (env : Env) (base : String) (write : Postgres.Conn → String → IO Unit) :
    ApiM String := do
  let attempt (db : Postgres.Conn) (slug : String) : IO Bool :=
    tryCatch (write db slug *> pure true) fun e =>
      if (Db.uniqueViolation? e).isSome then pure false else throw e
  let mut candidate := base
  for _ in [0:8] do
    if ← withDb env (attempt · candidate) then return candidate
    candidate := base ++ "-" ++ Slug.suffix (← (IO.getRandomBytes 6 : IO _))
  throwThe IO.Error (IO.userError s!"no free slug found for {base}")

def createArticle (env : Env) (me : Db.UserRow) (body : Json) : ApiM Db.ArticleRow := do
  let a ← ofExcept (NewArticle.parse body)
  let slug ← withUniqueSlug env (Slug.ofTitle a.title) fun db slug => Db.insertArticle db slug me.id a
  article env slug (some me.id)

/-- Whether `me` may change something `author` wrote, `what` naming it in the refusal. -/
def authorize (me author : Int64) (what : String) : Except ApiError Unit :=
  if me = author then .ok () else .error (ApiError.forbidden what)

/-- Only an article's or a comment's author may change it. -/
theorem authorize_ok_iff (me author : Int64) (what : String) :
    authorize me author what = .ok () ↔ me = author := by
  unfold authorize; split <;> simp_all

/-- The article's id and title, once it is established that `me` wrote it. -/
private def owned (env : Env) (slug : String) (me : Db.UserRow) : ApiM (Int64 × String) := do
  let some (id, author, title) ← withDb env (Db.articleOwner · slug) | fail (ApiError.notFound "article")
  ofExcept (authorize me.id author "article")
  pure (id, title)

def updateArticle (env : Env) (me : Db.UserRow) (slug : String) (body : ApiM Json) :
    ApiM Db.ArticleRow := do
  let (id, title) ← owned env slug me
  let u ← ofExcept (ArticleUpdate.parse (← body))
  let slug ← match u.title with
    | some newTitle =>
      if newTitle == title then
        withDb env (Db.updateArticle · id none u); pure slug
      else
        withUniqueSlug env (Slug.ofTitle newTitle) fun db newSlug => Db.updateArticle db id (some newSlug) u
    | none => withDb env (Db.updateArticle · id none u); pure slug
  article env slug (some me.id)

def deleteArticle (env : Env) (me : Db.UserRow) (slug : String) : ApiM Unit := do
  let (id, _) ← owned env slug me
  withDb env (Db.deleteArticle · id)

private def articleId (env : Env) (slug : String) : ApiM Int64 := do
  let some (id, _, _) ← withDb env (Db.articleOwner · slug) | fail (ApiError.notFound "article")
  pure id

def setFavorite (env : Env) (me : Db.UserRow) (slug : String) (favorite : Bool) :
    ApiM Db.ArticleRow := do
  let id ← articleId env slug
  withDb env fun db => if favorite then Db.favorite db me.id id else Db.unfavorite db me.id id
  article env slug (some me.id)

/-! ## Comments -/

def comments (env : Env) (slug : String) (viewer : Option Int64) : ApiM (Array Db.CommentRow) := do
  let id ← articleId env slug
  withDb env (Db.comments · id viewer)

def addComment (env : Env) (me : Db.UserRow) (slug : String) (body : ApiM Json) :
    ApiM Db.CommentRow := do
  let id ← articleId env slug
  let text ← ofExcept (NewComment.parse (← body))
  let some row ← withDb env (Db.insertComment · id me.id text) | fail (ApiError.notFound "article")
  pure row

def deleteComment (env : Env) (me : Db.UserRow) (slug : String) (commentId : Nat) : ApiM Unit := do
  let id ← articleId env slug
  let commentId := Int64.ofNat commentId
  let some author ← withDb env (Db.commentAuthor · id commentId) | fail (ApiError.notFound "comment")
  ofExcept (authorize me.id author "comment")
  withDb env (Db.deleteComment · commentId)

def tags (env : Env) : ApiM (Array String) := withDb env Db.tags

end RealWorld.Service
