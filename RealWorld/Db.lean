module

public import Postgres
public import Leanmigrate
public import LeanmigratePostgres
public import RealWorld.Requests

public section

namespace RealWorld.Db

open Postgres
open Postgres.Interpolation

def migrationsDir : System.FilePath := "migrations"

/-- Any value will do, as long as every instance uses the same one. -/
private def migrationLockKey : Int := 7467215

/-- Brings the schema up to date, one instance at a time. -/
def migrate (db : Conn) : IO Unit := do
  execScript db s!"SELECT pg_advisory_lock({migrationLockKey})"
  try
    migrateUp db (← discoverMigrations migrationsDir)
  finally
    execScript db s!"SELECT pg_advisory_unlock({migrationLockKey})"

/-- If `e` is a unique violation, the constraint it violated. -/
def uniqueViolation? (e : IO.Error) : Option String :=
  match Postgres.Error.ofIOError? e with
  | some err => if err.sqlstate == "23505" then some (err.constraint.getD "") else none
  | none => none

private def first [Row α] (stmt : Stmt) : IO (Option α) := do
  let rows : Array α ← stmt.results.toArray
  pure rows[0]?

/-! ## Users and profiles -/

structure UserRow where
  id : Int64
  username : String
  email : String
  passwordHash : String
  bio : Option String
  image : Option String
deriving Row, Repr

def userById (db : Conn) (id : Int64) : IO (Option UserRow) := do
  first (← db sql!"SELECT id, username, email, password_hash, bio, image FROM users WHERE id = {id}")

def userByEmail (db : Conn) (email : String) : IO (Option UserRow) := do
  first (← db sql!"SELECT id, username, email, password_hash, bio, image FROM users
                     WHERE email = {email}")

/-- Which of a username and an email already belong to someone other than `except`. -/
def taken (db : Conn) (username email : Option String) (except : Option Int64 := none) :
    IO (Bool × Bool) := do
  let stmt ← db sql!"SELECT
      EXISTS (SELECT 1 FROM users WHERE username = {username} AND id IS DISTINCT FROM {except}),
      EXISTS (SELECT 1 FROM users WHERE email = {email} AND id IS DISTINCT FROM {except})"
  pure ((← first stmt).getD (false, false))

def insertUser (db : Conn) (username email passwordHash : String) : IO Int64 := do
  let stmt ← db sql!"INSERT INTO users (username, email, password_hash)
                       VALUES ({username}, {email}, {passwordHash}) RETURNING id"
  match ← first stmt with
  | some id => pure id
  | none => throw (IO.userError "INSERT ... RETURNING returned no row")

/-- An absent field leaves its column alone, `null` clears it, and a value replaces it. -/
private def assignment : Field String → Bool × Option String
  | .absent => (false, none)
  | .null => (true, none)
  | .value v => (true, some v)

def updateUser (db : Conn) (id : Int64) (update : UserUpdate) (passwordHash : Option String) :
    IO Unit := do
  let (setBio, bio) := assignment update.bio
  let (setImage, image) := assignment update.image
  db exec!"UPDATE users SET
      username = COALESCE({update.username}, username),
      email = COALESCE({update.email}, email),
      password_hash = COALESCE({passwordHash}, password_hash),
      bio = CASE WHEN {setBio} THEN {bio} ELSE bio END,
      image = CASE WHEN {setImage} THEN {image} ELSE image END
    WHERE id = {id}"

structure ProfileRow where
  id : Int64
  username : String
  bio : Option String
  image : Option String
  following : Bool
deriving Row, Repr

def profile (db : Conn) (username : String) (viewer : Option Int64) : IO (Option ProfileRow) := do
  first (← db sql!"SELECT u.id, u.username, u.bio, u.image,
      EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = {viewer} AND f.followee_id = u.id)
    FROM users u WHERE u.username = {username}")

def follow (db : Conn) (follower followee : Int64) : IO Unit :=
  db exec!"INSERT INTO follows (follower_id, followee_id) VALUES ({follower}, {followee})
             ON CONFLICT DO NOTHING"

def unfollow (db : Conn) (follower followee : Int64) : IO Unit :=
  db exec!"DELETE FROM follows WHERE follower_id = {follower} AND followee_id = {followee}"

/-! ## Articles -/

structure ArticleRow where
  id : Int64
  slug : String
  title : String
  description : String
  body : String
  tagList : Array String
  createdAt : String
  updatedAt : String
  favorited : Bool
  favoritesCount : Int64
  authorId : Int64
  authorUsername : String
  authorBio : Option String
  authorImage : Option String
  following : Bool
deriving Row, Repr

def articleBySlug (db : Conn) (slug : String) (viewer : Option Int64) : IO (Option ArticleRow) := do
  first (← db sql!"SELECT d.id, d.slug, d.title, d.description, d.body, d.tag_list,
      iso_time(d.created_at), iso_time(d.updated_at),
      EXISTS (SELECT 1 FROM favorites f WHERE f.article_id = d.id AND f.user_id = {viewer}),
      d.favorites_count, d.author_id, d.author_username, d.author_bio, d.author_image,
      EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = {viewer} AND f.followee_id = d.author_id)
    FROM article_details d WHERE d.slug = {slug}")

/-- What a list of articles is narrowed to. `feed` keeps only authors the viewer follows. -/
structure Filter where
  tag : Option String := none
  author : Option String := none
  favoritedBy : Option String := none
  feed : Bool := false
deriving Repr

/-- One page of articles, newest first, without bodies, and how many match in all. -/
def articles (db : Conn) (viewer : Option Int64) (filter : Filter) (limit offset : Nat) :
    IO (Array ArticleRow × Int64) := do
  let { tag, author, favoritedBy, feed } := filter
  let limit : Int64 := .ofNat limit
  let offset : Int64 := .ofNat offset
  let page ← db sql!"SELECT d.id, d.slug, d.title, d.description, '', d.tag_list,
      iso_time(d.created_at), iso_time(d.updated_at),
      EXISTS (SELECT 1 FROM favorites f WHERE f.article_id = d.id AND f.user_id = {viewer}),
      d.favorites_count, d.author_id, d.author_username, d.author_bio, d.author_image,
      EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = {viewer} AND f.followee_id = d.author_id)
    FROM article_details d
    WHERE ({tag}::text IS NULL OR {tag} = ANY (d.tag_list))
      AND ({author}::text IS NULL OR d.author_username = {author})
      AND ({favoritedBy}::text IS NULL OR EXISTS (
            SELECT 1 FROM favorites f JOIN users u ON u.id = f.user_id
             WHERE f.article_id = d.id AND u.username = {favoritedBy}))
      AND (NOT {feed} OR EXISTS (
            SELECT 1 FROM follows f WHERE f.follower_id = {viewer} AND f.followee_id = d.author_id))
    ORDER BY d.created_at DESC, d.id DESC
    LIMIT {limit} OFFSET {offset}"
  let rows : Array ArticleRow ← page.results.toArray
  let count ← db sql!"SELECT count(*) FROM articles a JOIN users u ON u.id = a.author_id
    WHERE ({tag}::text IS NULL OR {tag} = ANY (a.tag_list))
      AND ({author}::text IS NULL OR u.username = {author})
      AND ({favoritedBy}::text IS NULL OR EXISTS (
            SELECT 1 FROM favorites f JOIN users fu ON fu.id = f.user_id
             WHERE f.article_id = a.id AND fu.username = {favoritedBy}))
      AND (NOT {feed} OR EXISTS (
            SELECT 1 FROM follows f WHERE f.follower_id = {viewer} AND f.followee_id = a.author_id))"
  pure (rows, (← first count).getD 0)

/-- An article's id, author and title, for deciding whether a request may change it and whether a
new title needs a new slug. -/
def articleOwner (db : Conn) (slug : String) : IO (Option (Int64 × Int64 × String)) := do
  first (← db sql!"SELECT id, author_id, title FROM articles WHERE slug = {slug}")

def insertArticle (db : Conn) (slug : String) (author : Int64) (a : NewArticle) : IO Unit :=
  db exec!"INSERT INTO articles (slug, title, description, body, tag_list, author_id)
             VALUES ({slug}, {a.title}, {a.description}, {a.body}, {a.tags}, {author})"

/-- `updated_at` moves forward by at least a millisecond, the precision the API reports, so an
update is always visible as one even when it lands within the same millisecond as the last. -/
def updateArticle (db : Conn) (id : Int64) (slug : Option String) (u : ArticleUpdate) : IO Unit :=
  let setTags := u.tags.isSome
  let tags := u.tags.getD #[]
  db exec!"UPDATE articles SET
      slug = COALESCE({slug}, slug),
      title = COALESCE({u.title}, title),
      description = COALESCE({u.description}, description),
      body = COALESCE({u.body}, body),
      tag_list = CASE WHEN {setTags} THEN {tags} ELSE tag_list END,
      updated_at = GREATEST(clock_timestamp(), updated_at + interval '1 millisecond')
    WHERE id = {id}"

def deleteArticle (db : Conn) (id : Int64) : IO Unit :=
  db exec!"DELETE FROM articles WHERE id = {id}"

def favorite (db : Conn) (user article : Int64) : IO Unit :=
  db exec!"INSERT INTO favorites (user_id, article_id) VALUES ({user}, {article})
             ON CONFLICT DO NOTHING"

def unfavorite (db : Conn) (user article : Int64) : IO Unit :=
  db exec!"DELETE FROM favorites WHERE user_id = {user} AND article_id = {article}"

/-- Every tag in use, most used first. -/
def tags (db : Conn) : IO (Array String) := do
  (← db sql!"SELECT tag FROM articles, unnest(tag_list) AS tag
               GROUP BY tag ORDER BY count(*) DESC, tag").results.toArray

/-! ## Comments -/

structure CommentRow where
  id : Int64
  body : String
  createdAt : String
  updatedAt : String
  authorId : Int64
  authorUsername : String
  authorBio : Option String
  authorImage : Option String
  following : Bool
deriving Row, Repr

def comments (db : Conn) (article : Int64) (viewer : Option Int64) : IO (Array CommentRow) := do
  (← db sql!"SELECT c.id, c.body, iso_time(c.created_at), iso_time(c.updated_at),
      u.id, u.username, u.bio, u.image,
      EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = {viewer} AND f.followee_id = u.id)
    FROM comments c JOIN users u ON u.id = c.author_id
    WHERE c.article_id = {article}
    ORDER BY c.created_at DESC, c.id DESC").results.toArray

def insertComment (db : Conn) (article author : Int64) (body : String) : IO (Option CommentRow) := do
  first (← db sql!"WITH c AS (
      INSERT INTO comments (article_id, author_id, body) VALUES ({article}, {author}, {body})
      RETURNING id, body, created_at, updated_at, author_id)
    SELECT c.id, c.body, iso_time(c.created_at), iso_time(c.updated_at),
      u.id, u.username, u.bio, u.image, false
    FROM c JOIN users u ON u.id = c.author_id")

/-- A comment's author, if the comment exists and belongs to `article`. -/
def commentAuthor (db : Conn) (article id : Int64) : IO (Option Int64) := do
  first (← db sql!"SELECT author_id FROM comments WHERE id = {id} AND article_id = {article}")

def deleteComment (db : Conn) (id : Int64) : IO Unit :=
  db exec!"DELETE FROM comments WHERE id = {id}"

end RealWorld.Db
