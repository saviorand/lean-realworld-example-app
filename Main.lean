module

public import Std.Http.Server
public import Postgres
public import RealWorld

public section

open Std Async
open Std Http Server
open RealWorld

private def envNat (name : String) (default : Nat) : IO Nat := do
  match ← IO.getEnv name with
  | none => pure default
  | some raw => match raw.toNat? with
    | some n => pure n
    | none => throw (IO.userError s!"{name} is {raw}, which is not a number")

/-- `HOST` as four octets, defaulting to loopback so a development server is not reachable from
the network by accident. -/
private def host : IO Net.IPv4Addr := do
  match ← IO.getEnv "HOST" with
  | none => pure (.ofParts 127 0 0 1)
  | some raw =>
    match (raw.splitOn ".").mapM String.toNat? with
    | some [a, b, c, d] =>
      if [a, b, c, d].all (· < 256) then pure (.ofParts a.toUInt8 b.toUInt8 c.toUInt8 d.toUInt8)
      else throw (IO.userError s!"HOST is {raw}, which is not an IPv4 address")
    | _ => throw (IO.userError s!"HOST is {raw}, which is not an IPv4 address")

/-- From `JWT_SECRET` when set. Otherwise a fresh random key, which means tokens stop working when
the server restarts; fine for development, and said out loud. -/
private def tokens : IO Tokens := do
  match ← IO.getEnv "JWT_SECRET" with
  | some secret =>
    match Tokens.ofSecret? secret.toUTF8 with
    | some tokens => pure tokens
    | none => throw (IO.userError s!"JWT_SECRET must be at least {Tokens.minSecret} bytes")
  | none =>
    IO.eprintln "JWT_SECRET is not set; using a random key, so tokens will not survive a restart"
    match Tokens.ofSecret? (← IO.getRandomBytes 32) with
    | some tokens => pure tokens
    | none => throw (IO.userError "could not make a signing key")

def main : IO Unit := Async.block do
  let conninfo := (← IO.getEnv "DATABASE_URL").getD ""
  let port ← envNat "PORT" 8000
  let pool ← Postgres.Pool.create conninfo (← envNat "POOL_SIZE" 16)
  pool.withConnAsync Db.migrate
  let env : Env := { pool, tokens := ← tokens, decoy := ← Password.decoy }
  let server ← serve (.v4 ⟨← host, port.toUInt16⟩) (app env)
  IO.println s!"Listening on port {port}"
  server.waitShutdown
