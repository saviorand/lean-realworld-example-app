module

public import Json

@[expose] public section

namespace RealWorld

open Json

/-- Messages keyed by the field they are about, in the order they were found. The spec's error
body is exactly this shape: `{"errors": {"field": ["message", ...]}}`. -/
abbrev FieldErrors := Array (String × Array String)

/-- How a request failed, which is what decides its status. -/
inductive Failure where
  | unprocessable
  | unauthorized
  | forbidden
  | notFound
  | conflict
  | tooLarge
deriving Repr, DecidableEq

def Failure.code : Failure → Nat
  | .unprocessable => 422
  | .unauthorized => 401
  | .forbidden => 403
  | .notFound => 404
  | .conflict => 409
  | .tooLarge => 413

structure ApiError where
  failure : Failure
  errors : FieldErrors
deriving Repr

namespace ApiError

def one (failure : Failure) (field message : String) : ApiError :=
  { failure, errors := #[(field, #[message])] }

def blank (field : String) : ApiError := one .unprocessable field "can't be blank"
def invalid (field : String) : ApiError := one .unprocessable field "is invalid"
def notFound (what : String) : ApiError := one .notFound what "not found"
def forbidden (what : String) : ApiError := one .forbidden what "forbidden"
def taken (field : String) : ApiError := one .conflict field "has already been taken"
def tokenMissing : ApiError := one .unauthorized "token" "is missing"
def tokenInvalid : ApiError := one .unauthorized "token" "is invalid"
def credentials : ApiError := one .unauthorized "credentials" "invalid"

def toJson (e : ApiError) : Json :=
  .obj #[("errors", .obj (e.errors.map fun (field, msgs) => (field, .arr (msgs.map .str))))]

end ApiError

/-- Collects every field's complaints before failing, so a client that sent three bad fields hears
about all three at once. -/
def collect (failure : Failure) (checks : List (String × Option String)) : Except ApiError Unit :=
  let errors := checks.filterMap fun (field, problem) => problem.map fun msg => (field, #[msg])
  if errors.isEmpty then .ok () else .error { failure, errors := errors.toArray }

end RealWorld
