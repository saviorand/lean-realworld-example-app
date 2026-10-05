module

public import Std.Http.Server
public import Middleware
public import Json
public import Postgres
public import RealWorld.Errors
public import RealWorld.Token
public import RealWorld.Db

public section

namespace RealWorld

open Std Async
open Std Http Server

/-- What every handler needs: the database, the key tokens are signed with, and a stored hash to
check logins for unknown emails against. -/
structure Env where
  pool : Postgres.Pool
  tokens : Tokens
  decoy : String

/-- A handler's monad. A failure carries what the spec says to answer with, and `respond` turns it
into that answer, so no handler builds an error response itself. -/
abbrev ApiM := ExceptT ApiError ContextAsync

def fail (e : ApiError) : ApiM α := throwThe ApiError e

def ofExcept : Except ApiError α → ApiM α
  | .ok a => pure a
  | .error e => fail e

def statusOf (failure : Failure) : Status :=
  (Status.ofCode none failure.code.toUInt16).getD .badRequest

def jsonResponse (status : Status) (body : Json) : ContextAsync (Response Body.Any) :=
  Response.withStatus status
    |>.header Header.Name.contentType (Header.Value.ofString! "application/json; charset=utf-8")
    |>.fromBytes (Json.compress body).toUTF8

def ok (body : Json) : ApiM (Response Body.Any) := jsonResponse .ok body
def created (body : Json) : ApiM (Response Body.Any) := jsonResponse .created body
def noContent : ApiM (Response Body.Any) := Response.withStatus .noContent |>.fromBytes .empty

def respond (act : ApiM (Response Body.Any)) : ContextAsync (Response Body.Any) := do
  match ← act.run with
  | .ok response => pure response
  | .error e => jsonResponse (statusOf e.failure) e.toJson

/-- Runs `act` on a pooled connection. Waiting for one is cooperative, so a request queued behind a
busy pool does not hold up the thread it would have run on. -/
def withDb (env : Env) (act : Postgres.Conn → IO α) : ApiM α :=
  (env.pool.withConnAsync act : Async α)

/-- Enough for any article a person would write, and small enough that a request cannot ask the
server to buffer an arbitrary amount. -/
def maxBody : UInt64 := 1024 * 1024

def readJson (req : Request Body.Stream) : ApiM Json := do
  let read : ContextAsync (Except IO.Error ByteArray) :=
    tryCatch (Except.ok <$> req.body.readAll (maximumSize := some maxBody)) (pure ∘ .error)
  match ← read with
  | .error _ => fail (ApiError.one .tooLarge "body" s!"is larger than {maxBody} bytes")
  | .ok bytes =>
    match Json.parseBytes bytes with
    | .ok json => pure json
    | .error _ => fail (ApiError.invalid "body")

def param (req : Request Body.Stream) (key : String) : Option String :=
  (req.extensions.get Middleware.Params).bind (·.get key)

def natParam (req : Request Body.Stream) (key : String) (default : Nat) : ApiM Nat :=
  match param req key with
  | none => pure default
  | some raw => match raw.toNat? with
    | some n => pure n
    | none => fail (ApiError.invalid key)

/-! ## Authentication -/

/-- The token in `Authorization: Token <jwt>`. `Bearer` is accepted too, since that is what most
HTTP clients send by default. -/
def tokenOf (header : String) : Option String :=
  match (header.trimAscii.toString.splitOn " ").filter (· ≠ "") with
  | [scheme, token] => if scheme == "Token" || scheme == "Bearer" then some token else none
  | _ => none

/-! ## Response bodies -/

def optional : Option String → Json
  | some s => .str s
  | none => .null

def userJson (user : Db.UserRow) (token : String) : Json :=
  .obj #[("user", .obj #[
    ("email", .str user.email), ("token", .str token), ("username", .str user.username),
    ("bio", optional user.bio), ("image", optional user.image)])]

def profileFields (username : String) (bio image : Option String) (following : Bool) : Json :=
  .obj #[("username", .str username), ("bio", optional bio), ("image", optional image),
         ("following", .bool following)]

def profileJson (p : Db.ProfileRow) : Json :=
  .obj #[("profile", profileFields p.username p.bio p.image p.following)]

/-- Lists leave the body out, as the spec has required since August 2024. -/
def articleFields (a : Db.ArticleRow) (withBody : Bool) : Json :=
  .obj (#[("slug", .str a.slug), ("title", .str a.title), ("description", .str a.description)]
    ++ (if withBody then #[("body", .str a.body)] else #[])
    ++ #[("tagList", .arr (a.tagList.map .str)),
         ("createdAt", .str a.createdAt), ("updatedAt", .str a.updatedAt),
         ("favorited", .bool a.favorited), ("favoritesCount", Json.ofInt a.favoritesCount.toInt),
         ("author", profileFields a.authorUsername a.authorBio a.authorImage a.following)])

def articleJson (a : Db.ArticleRow) : Json := .obj #[("article", articleFields a true)]

def articlesJson (rows : Array Db.ArticleRow) (count : Int64) : Json :=
  .obj #[("articles", .arr (rows.map (articleFields · false))),
         ("articlesCount", Json.ofInt count.toInt)]

def commentFields (c : Db.CommentRow) : Json :=
  .obj #[("id", Json.ofInt c.id.toInt), ("createdAt", .str c.createdAt),
         ("updatedAt", .str c.updatedAt), ("body", .str c.body),
         ("author", profileFields c.authorUsername c.authorBio c.authorImage c.following)]

end RealWorld
