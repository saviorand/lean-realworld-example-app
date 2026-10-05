module

public import Jose
public import Json

public section

namespace RealWorld

open Jose

/-- Signs and checks the JWTs the API hands out. HS256 under one shared secret, since the server
that issues a token is the only one that ever reads it. -/
structure Tokens where
  key : Jwk
  lifetime : Int := 60 * 60 * 24 * 7

namespace Tokens

def issuer : String := "realworld"

/-- RFC 7518 §3.2: an HMAC key at least as long as its digest. -/
def minSecret : Nat := 32

def ofSecret? (secret : ByteArray) : Option Tokens :=
  if secret.size < minSecret then none
  else some { key := { material := .oct secret, kid := none, alg := some .hs256 } }

def policy : Policy := { algs := #[.hs256], issuer, audience := #[issuer] }

private def header : String := "{\"alg\":\"HS256\",\"typ\":\"JWT\"}"

def issue (tokens : Tokens) (userId : Int64) : IO String := do
  let now := (← Std.Time.Timestamp.now).toSecondsSinceUnixEpoch.val
  let claims : Json := .obj #[
    ("iss", .str issuer), ("aud", .str issuer), ("sub", .str (toString userId)),
    ("iat", Json.ofInt now), ("exp", Json.ofInt (now + tokens.lifetime))]
  match Pure.token .hs256 (Pure.prepare tokens.key) header (Json.compress claims) with
  | .ok token => pure token
  | .error reason => throw (IO.userError s!"could not sign a token: {repr reason}")

/-- The user a token was issued to, if it verifies and has not expired. -/
def verify (tokens : Tokens) (token : String) : IO (Option Int64) := do
  match ← Jwt.verifyNow Backend.pure policy (Pure.keySet (Jwks.ofKeys #[tokens.key])) token with
  | .ok claims => pure ((claims.subject.bind String.toInt?).map Int64.ofInt)
  | .error _ => pure none

end Tokens

end RealWorld
