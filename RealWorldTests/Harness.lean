module

public section

namespace RealWorldTests

structure Outcome where
  passed : Nat := 0
  failed : Array String := #[]

abbrev TestM := StateT Outcome IO

def check (name : String) (ok : Bool) (detail : String := "") : TestM Unit :=
  modify fun o =>
    if ok then { o with passed := o.passed + 1 }
    else { o with failed := o.failed.push (if detail.isEmpty then name else s!"{name}: {detail}") }

def checkEq [BEq α] [Repr α] (name : String) (actual expected : α) : TestM Unit :=
  check name (actual == expected) s!"expected {repr expected}, got {repr actual}"

def run (suites : List (String × TestM Unit)) : IO UInt32 := do
  let mut total : Outcome := {}
  for (name, suite) in suites do
    let ((), o) ← suite.run {}
    IO.println s!"{name}: {o.passed} passed, {o.failed.size} failed"
    for f in o.failed do IO.println s!"  FAIL {f}"
    total := { passed := total.passed + o.passed, failed := total.failed ++ o.failed }
  IO.println s!"total: {total.passed} passed, {total.failed.size} failed"
  pure (if total.failed.isEmpty then 0 else 1)

end RealWorldTests
