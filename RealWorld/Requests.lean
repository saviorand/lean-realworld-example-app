module

public import Json
public import RealWorld.Errors

@[expose] public section

namespace RealWorld

open Json

/-- A member of a request object as the client sent it. `PUT` treats the three differently: an
absent member leaves a value alone, `null` clears it, and a value replaces it. -/
inductive Field (α : Type) where
  | absent
  | null
  | value (a : α)
deriving Repr, DecidableEq

def member (obj : Array (String × Json)) (name : String) : Field Json :=
  match obj.findRev? (·.1 == name) with
  | none => .absent
  | some (_, .null) => .null
  | some (_, v) => .value v

/-- The object under `key` at the top of a request body, such as `user` in `{"user": {...}}`. -/
def envelope (body : Json) (key : String) : Except ApiError (Array (String × Json)) :=
  match body with
  | .obj fields =>
    match member fields key with
    | .value (.obj inner) => .ok inner
    | .absent | .null => .error (ApiError.blank key)
    | .value _ => .error (ApiError.invalid key)
  | _ => .error (ApiError.invalid "body")

def isBlank (s : String) : Bool := s.trimAscii.isEmpty

/-- What is wrong with a member that must be a non-blank string, if anything. -/
def requiredProblem : Field Json → Option String
  | .absent | .null => some "can't be blank"
  | .value (.str s) => if isBlank s then some "can't be blank" else none
  | .value _ => some "must be a string"

/-- Names and titles are trimmed; prose is kept exactly as written. -/
def requiredString (obj : Array (String × Json)) (name : String) (trim := true) : String :=
  match member obj name with
  | .value (.str s) => if trim then s.trimAscii.toString else s
  | _ => ""

/-- NIST SP 800-63B §5.1.1.2: at least eight characters, at least 64 accepted, no composition
rules. The upper bound only keeps a request from making the key derivation hash megabytes. -/
def minPassword : Nat := 8
def maxPassword : Nat := 1024

def passwordProblem (password : String) : Option String :=
  if password.isEmpty then some "can't be blank"
  else if password.length < minPassword then some s!"is too short (minimum is {minPassword} characters)"
  else if password.length > maxPassword then some s!"is too long (maximum is {maxPassword} characters)"
  else none

def passwordField (obj : Array (String × Json)) : Option String :=
  match member obj "password" with
  | .absent | .null => some "can't be blank"
  | .value (.str s) => passwordProblem s
  | .value _ => some "must be a string"

structure Registration where
  username : String
  email : String
  password : String
deriving Repr

def Registration.parse (body : Json) : Except ApiError Registration := do
  let user ← envelope body "user"
  collect .unprocessable
    [("username", requiredProblem (member user "username")),
     ("email", requiredProblem (member user "email")),
     ("password", passwordField user)]
  let password := match member user "password" with | .value (.str s) => s | _ => ""
  pure { username := requiredString user "username", email := requiredString user "email", password }

structure Login where
  email : String
  password : String
deriving Repr

/-- A login only checks presence: the length rule is for choosing a password, and telling someone
their attempt was too short would say something about what the real one is not. -/
def Login.parse (body : Json) : Except ApiError Login := do
  let user ← envelope body "user"
  let password := member user "password"
  collect .unprocessable
    [("email", requiredProblem (member user "email")),
     ("password", match password with
       | .value (.str s) => if s.isEmpty then some "can't be blank" else none
       | other => requiredProblem other)]
  let password := match password with | .value (.str s) => s | _ => ""
  pure { email := requiredString user "email", password }

/-- `bio` and `image` are nullable, and an empty string means the same as `null`. -/
def nullableText : Field Json → Except String (Field String)
  | .absent => .ok .absent
  | .null => .ok .null
  | .value (.str s) => .ok (if isBlank s then .null else .value s)
  | .value _ => .error "must be a string or null"

/-- `username` and `email` may be left out of an update but not cleared. -/
def requiredUpdate (field : Field Json) (trim := true) : Except String (Option String) :=
  match field with
  | .absent => .ok none
  | .value (.str s) =>
    if isBlank s then .error "can't be blank" else .ok (some (if trim then s.trimAscii.toString else s))
  | .null => .error "can't be blank"
  | .value _ => .error "must be a string"

def passwordUpdate : Field Json → Except String (Option String)
  | .absent => .ok none
  | .null => .error "can't be blank"
  | .value (.str s) => match passwordProblem s with
    | some problem => .error problem
    | none => .ok (some s)
  | .value _ => .error "must be a string"

structure UserUpdate where
  username : Option String
  email : Option String
  password : Option String
  bio : Field String
  image : Field String
deriving Repr

def problemOf : Except String α → Option String
  | .error e => some e
  | .ok _ => none

def valueOf [Inhabited α] : Except String α → α
  | .ok a => a
  | .error _ => default

instance : Inhabited (Field α) := ⟨.absent⟩

def UserUpdate.parse (body : Json) : Except ApiError UserUpdate := do
  let user ← envelope body "user"
  let username := requiredUpdate (member user "username")
  let email := requiredUpdate (member user "email")
  let password := passwordUpdate (member user "password")
  let bio := nullableText (member user "bio")
  let image := nullableText (member user "image")
  collect .unprocessable
    [("username", problemOf username), ("email", problemOf email),
     ("password", problemOf password), ("bio", problemOf bio), ("image", problemOf image)]
  pure { username := valueOf username, email := valueOf email, password := valueOf password,
         bio := valueOf bio, image := valueOf image }

/-- Tags in the order given, blank ones dropped and repeats kept only the first time. -/
def normaliseTags (tags : Array String) : Array String :=
  tags.foldl (init := #[]) fun acc t =>
    let t := t.trimAscii.toString
    if t.isEmpty || acc.contains t then acc else acc.push t

def tagList : Field Json → Except String (Option (Array String))
  | .absent => .ok none
  | .null => .error "must be an array of strings"
  | .value (.arr items) =>
    match items.mapM (fun | .str s => some s | _ => none) with
    | some tags => .ok (some (normaliseTags tags))
    | none => .error "must be an array of strings"
  | .value _ => .error "must be an array of strings"

structure NewArticle where
  title : String
  description : String
  body : String
  tags : Array String
deriving Repr

def NewArticle.parse (json : Json) : Except ApiError NewArticle := do
  let article ← envelope json "article"
  let tags := tagList (member article "tagList")
  collect .unprocessable
    [("title", requiredProblem (member article "title")),
     ("description", requiredProblem (member article "description")),
     ("body", requiredProblem (member article "body")),
     ("tagList", problemOf tags)]
  pure { title := requiredString article "title", description := requiredString article "description" (trim := false),
         body := requiredString article "body" (trim := false), tags := (valueOf tags).getD #[] }

structure ArticleUpdate where
  title : Option String
  description : Option String
  body : Option String
  tags : Option (Array String)
deriving Repr

def ArticleUpdate.parse (json : Json) : Except ApiError ArticleUpdate := do
  let article ← envelope json "article"
  let title := requiredUpdate (member article "title")
  let description := requiredUpdate (member article "description") (trim := false)
  let body := requiredUpdate (member article "body") (trim := false)
  let tags := tagList (member article "tagList")
  collect .unprocessable
    [("title", problemOf title), ("description", problemOf description),
     ("body", problemOf body), ("tagList", problemOf tags)]
  pure { title := valueOf title, description := valueOf description, body := valueOf body,
         tags := valueOf tags }

def NewComment.parse (json : Json) : Except ApiError String := do
  let comment ← envelope json "comment"
  collect .unprocessable [("body", requiredProblem (member comment "body"))]
  pure (requiredString comment "body" (trim := false))

end RealWorld
