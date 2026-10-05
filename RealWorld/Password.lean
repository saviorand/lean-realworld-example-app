module

public import Libcrypto
public import Leancrypto

public section

namespace RealWorld.Password

open Libcrypto.Evp
open Leancrypto

/-- scrypt's cost parameters. OWASP's password storage cheat sheet lists `N = 2^15, r = 8, p = 3`
as one of its equivalent minimums, at 32 MiB per derivation. -/
structure Cost where
  logN : Nat := 15
  r : Nat := 8
  p : Nat := 3
deriving Repr, DecidableEq

def saltLength : Nat := 16
def hashLength : Nat := 32

/-- Far above what the default cost needs (`128 * r * N` bytes), so that a stored hash with a
higher cost still verifies. OpenSSL refuses a derivation that would exceed it. -/
private def maxMem : Nat := 1024 * 1024 * 1024

def derive (cost : Cost) (password salt : ByteArray) : IO ByteArray := do
  let kdf ← Kdf.fetch "SCRYPT"
  kdf.derive hashLength
    #[{ key := "pass", value := .octets password },
      { key := "salt", value := .octets salt },
      { key := "n", value := .uint (2 ^ cost.logN) },
      { key := "r", value := .uint cost.r },
      { key := "p", value := .uint cost.p },
      { key := "maxmem_bytes", value := .uint maxMem }]

/-- `scrypt$logN$r$p$salt$hash`, salt and hash in unpadded base64url, so the cost travels with the
hash and can be raised later without invalidating anything already stored. -/
def encode (cost : Cost) (salt hash : ByteArray) : String :=
  s!"scrypt${cost.logN}${cost.r}${cost.p}${Codec.Base64Url.encodeString salt}${Codec.Base64Url.encodeString hash}"

def decode (stored : String) : Option (Cost × ByteArray × ByteArray) :=
  match stored.splitOn "$" with
  | ["scrypt", logN, r, p, salt, hash] => do
    let cost : Cost := { logN := ← logN.toNat?, r := ← r.toNat?, p := ← p.toNat? }
    pure (cost, ← Codec.Base64Url.decodeString salt, ← Codec.Base64Url.decodeString hash)
  | _ => none

def hash (password : String) (cost : Cost := {}) : IO String := do
  let salt ← IO.getRandomBytes saltLength.toUSize
  pure (encode cost salt (← derive cost password.toUTF8 salt))

def verify (password stored : String) : IO Bool := do
  match decode stored with
  | none => pure false
  | some (cost, salt, expected) => pure (bytesEqual (← derive cost password.toUTF8 salt) expected)

/-- A stored hash for an account that does not exist, verified against when a login names an
unknown email, so that the answer takes as long as a wrong password would. -/
def decoy : IO String := hash "no account has this password"

end RealWorld.Password
