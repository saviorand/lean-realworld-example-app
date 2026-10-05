module

@[expose] public section

namespace RealWorld.Slug

/-- Characters a slug is made of, besides the hyphens between its words. -/
def isSlugChar (c : Char) : Bool :=
  ('a' ≤ c && c ≤ 'z') || ('0' ≤ c && c ≤ '9')

/-- A slug: words of `isSlugChar` characters joined by single hyphens. So it is not empty, and it
neither starts nor ends with a hyphen nor has two in a row. -/
inductive Valid : List Char → Prop where
  | single {c} : isSlugChar c → Valid [c]
  | cons {c rest} : isSlugChar c → Valid rest → Valid (c :: rest)
  | hyphen {c rest} : isSlugChar c → Valid rest → Valid (c :: '-' :: rest)

/-- The slug characters of `cs`, lowercased, with one hyphen wherever anything else separated two
of them. `started` once a character has been kept; `pending` when something has been skipped since
the last one kept. -/
def chars : List Char → (started pending : Bool) → List Char
  | [], _, _ => []
  | c :: cs, started, pending =>
    if isSlugChar c.toLower then
      (if started && pending then ['-', c.toLower] else [c.toLower]) ++ chars cs true false
    else chars cs started true

/-- A title's slug: its ASCII letters and digits, lowercased, with every run of anything else
between them turned into one hyphen. A title with none becomes `article`. -/
def ofTitle (title : String) : String :=
  match chars title.toList false false with
  | [] => "article"
  | cs => String.ofList cs

/-- Six characters to tell apart two articles whose titles slug alike. Lowercase base 32, so the
result is still a slug. -/
def suffix (bytes : ByteArray) : String :=
  let alphabet := "abcdefghijklmnopqrstuvwxyz234567".toList
  String.ofList ((bytes.toList.take 6).map fun b => alphabet.getD (b.toNat % 32) 'a')

/-! ## Every slug is valid -/

/-- What `chars` produces once it has started: nothing, a slug, or a hyphen before a slug. -/
private def Tail (l : List Char) : Prop :=
  l = [] ∨ Valid l ∨ ∃ r, l = '-' :: r ∧ Valid r

private theorem valid_cons {c : Char} {l : List Char} (hc : isSlugChar c) (hl : Tail l) :
    Valid (c :: l) := by
  rcases hl with rfl | hl | ⟨r, rfl, hr⟩
  · exact .single hc
  · exact .cons hc hl
  · exact .hyphen hc hr

private theorem tail_chars (cs : List Char) (pending : Bool) : Tail (chars cs true pending) := by
  induction cs generalizing pending with
  | nil => exact Or.inl rfl
  | cons c cs ih =>
    unfold chars
    by_cases hc : isSlugChar c.toLower
    · cases pending
      · simp only [hc, Bool.and_false, ite_true, Bool.false_eq_true, ite_false, List.cons_append,
          List.nil_append]
        exact Or.inr (Or.inl (valid_cons hc (ih false)))
      · simp only [hc, Bool.and_self, ite_true, List.cons_append, List.nil_append]
        exact Or.inr (Or.inr ⟨_, rfl, valid_cons hc (ih false)⟩)
    · simp only [hc, Bool.false_eq_true, ite_false]
      exact ih true

private theorem chars_valid (cs : List Char) (pending : Bool) :
    chars cs false pending = [] ∨ Valid (chars cs false pending) := by
  induction cs generalizing pending with
  | nil => exact Or.inl rfl
  | cons c cs ih =>
    unfold chars
    by_cases hc : isSlugChar c.toLower
    · simp only [hc, Bool.false_and, Bool.false_eq_true, ite_false, ite_true, List.cons_append,
        List.nil_append]
      exact Or.inr (valid_cons hc (tail_chars cs false))
    · simp only [hc, Bool.false_eq_true, ite_false]
      exact ih true

theorem ofTitle_valid (title : String) : Valid (ofTitle title).toList := by
  unfold ofTitle
  split
  · exact .cons (by decide) (.cons (by decide) (.cons (by decide) (.cons (by decide)
      (.cons (by decide) (.cons (by decide) (.single (by decide)))))))
  · next cs hne =>
    rw [String.toList_ofList]
    rcases chars_valid title.toList false with h | h
    · exact absurd h (by simpa using hne)
    · simp_all

end RealWorld.Slug
