module

public import RealWorld
public import RealWorldTests.Harness

public section

namespace RealWorldTests

open RealWorld

def slugs : TestM Unit := do
  checkEq "punctuation becomes one hyphen" (Slug.ofTitle "How to train your dragon!") "how-to-train-your-dragon"
  checkEq "edges trimmed" (Slug.ofTitle "--a--b--") "a-b"
  checkEq "nothing left is still a slug" (Slug.ofTitle "日本語") "article"

def parse! (s : String) : Json := (Json.parse s).toOption.getD .null

def requests : TestM Unit := do
  let reg := Registration.parse (parse! "{\"user\":{\"username\":\"\",\"email\":\"a@b.c\",\"password\":\"short\"}}")
  check "registration reports every bad field" (match reg with
    | .error e => e.errors.map (·.1) == #["username", "password"] | .ok _ => false)
  let upd := UserUpdate.parse (parse! "{\"user\":{\"bio\":\"\",\"image\":null}}")
  check "empty bio and null image both clear" (match upd with
    | .ok u => u.bio == .null && u.image == .null && u.username.isNone | .error _ => false)
  check "null email is refused" (UserUpdate.parse (parse! "{\"user\":{\"email\":null}}") matches .error _)
  check "null tagList is refused" (ArticleUpdate.parse (parse! "{\"article\":{\"tagList\":null}}") matches .error _)
  check "absent tagList leaves tags alone" (match ArticleUpdate.parse (parse! "{\"article\":{\"body\":\"x\"}}") with
    | .ok u => u.tags.isNone | .error _ => false)

def passwords : TestM Unit := do
  let stored ← Password.hash "password123"
  check "right password verifies" (← Password.verify "password123" stored)
  check "wrong password does not" !(← Password.verify "password124" stored)
  check "garbage hash does not" !(← Password.verify "password123" "scrypt$garbage")

def tokens : TestM Unit := do
  let some t := Tokens.ofSecret? "0123456789abcdef0123456789abcdef".toUTF8 | check "secret accepted" false
  let token ← t.issue 42
  checkEq "token names its user" (← t.verify token) (some 42)
  checkEq "tampered token refused" (← t.verify ((token.dropEnd 2).toString ++ "xx")) none
  let some other := Tokens.ofSecret? "ffffffffffffffffffffffffffffffff".toUTF8 | check "secret accepted" false
  checkEq "token from another key refused" (← other.verify token) none
  check "short secret refused" (Tokens.ofSecret? "short".toUTF8).isNone

def unitSuites : List (String × TestM Unit) :=
  [("slugs", slugs), ("requests", requests), ("passwords", passwords), ("tokens", tokens)]

end RealWorldTests
