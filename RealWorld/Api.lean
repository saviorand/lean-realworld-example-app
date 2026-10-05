module

public import RealWorld.Service

public section

/-! The JSON API, as the RealWorld spec defines it. Each handler reads the request, calls the
service, and writes the spec's response shape. -/

namespace RealWorld.Api

open Std Async
open Std Http Server

abbrev Handler := Request Body.Stream → ContextAsync (Response Body.Any)

/-- Who is asking, if anyone. A request with no `Authorization` header is anonymous; one with a
header that does not hold a valid token for an existing user is refused rather than treated as
anonymous, so a client with an expired token finds out. -/
def viewer (env : Env) (req : Request Body.Stream) : ApiM (Option Db.UserRow) := do
  match req.line.headers.get? (Header.Name.mk "authorization") with
  | none => pure none
  | some header =>
    let some token := tokenOf header.value | fail ApiError.tokenInvalid
    let some user ← Service.userOfToken env token | fail ApiError.tokenInvalid
    pure (some user)

def requireUser (env : Env) (req : Request Body.Stream) : ApiM Db.UserRow := do
  match ← viewer env req with
  | some user => pure user
  | none => fail ApiError.tokenMissing

private def viewerId (env : Env) (req : Request Body.Stream) : ApiM (Option Int64) :=
  return (← viewer env req).map (·.id)

private def userResponse (env : Env) (user : Db.UserRow) : ApiM Json :=
  return userJson user (← Service.token env user)

def register (env : Env) : Handler := fun req => respond do
  created (← userResponse env (← Service.register env (← readJson req)))

def login (env : Env) : Handler := fun req => respond do
  ok (← userResponse env (← Service.login env (← readJson req)))

def currentUser (env : Env) : Handler := fun req => respond do
  ok (← userResponse env (← requireUser env req))

def updateUser (env : Env) : Handler := fun req => respond do
  let me ← requireUser env req
  ok (← userResponse env (← Service.updateUser env me (← readJson req)))

def getProfile (env : Env) (username : String) : Handler := fun req => respond do
  ok (profileJson (← Service.profile env username (← viewerId env req)))

def follow (env : Env) (username : String) : Handler := fun req => respond do
  ok (profileJson (← Service.setFollowing env (← requireUser env req) username true))

def unfollow (env : Env) (username : String) : Handler := fun req => respond do
  ok (profileJson (← Service.setFollowing env (← requireUser env req) username false))

private def page (req : Request Body.Stream) : ApiM (Nat × Nat) :=
  return (← natParam req "limit" 20, ← natParam req "offset" 0)

def listArticles (env : Env) : Handler := fun req => respond do
  let viewer ← viewerId env req
  let (limit, offset) ← page req
  let filter : Db.Filter :=
    { tag := param req "tag", author := param req "author", favoritedBy := param req "favorited" }
  let (rows, count) ← Service.articles env viewer filter limit offset
  ok (articlesJson rows count)

def feed (env : Env) : Handler := fun req => respond do
  let me ← requireUser env req
  let (limit, offset) ← page req
  let (rows, count) ← Service.articles env (some me.id) { feed := true } limit offset
  ok (articlesJson rows count)

def getArticle (env : Env) (slug : String) : Handler := fun req => respond do
  ok (articleJson (← Service.article env slug (← viewerId env req)))

def createArticle (env : Env) : Handler := fun req => respond do
  let me ← requireUser env req
  created (articleJson (← Service.createArticle env me (← readJson req)))

def updateArticle (env : Env) (slug : String) : Handler := fun req => respond do
  let me ← requireUser env req
  ok (articleJson (← Service.updateArticle env me slug (readJson req)))

def deleteArticle (env : Env) (slug : String) : Handler := fun req => respond do
  Service.deleteArticle env (← requireUser env req) slug
  noContent

def favorite (env : Env) (slug : String) : Handler := fun req => respond do
  ok (articleJson (← Service.setFavorite env (← requireUser env req) slug true))

def unfavorite (env : Env) (slug : String) : Handler := fun req => respond do
  ok (articleJson (← Service.setFavorite env (← requireUser env req) slug false))

def listComments (env : Env) (slug : String) : Handler := fun req => respond do
  let rows ← Service.comments env slug (← viewerId env req)
  ok (.obj #[("comments", .arr (rows.map commentFields))])

def addComment (env : Env) (slug : String) : Handler := fun req => respond do
  let me ← requireUser env req
  created (.obj #[("comment", commentFields (← Service.addComment env me slug (readJson req)))])

def deleteComment (env : Env) (slug : String) (id : Nat) : Handler := fun req => respond do
  Service.deleteComment env (← requireUser env req) slug id
  noContent

def tags (env : Env) : Handler := fun _ => respond do
  ok (.obj #[("tags", .arr ((← Service.tags env).map .str))])

end RealWorld.Api
