module

public import Html
public import CommonMark
public import Json
public import RealWorld.Db
public import RealWorld.Errors
public import RealWorld.Web.Routes

public section

/-!
The Conduit pages, following the RealWorld frontend templates and the class names its end-to-end
selector contract lists. Markup is typed (`Html.Node`), so nesting is checked by the compiler and
text is escaped. The one exception is an article body, which is Markdown rendered by lean-markdown's
`renderHtmlSafe`, proved to produce well-formed HTML in which no text from the document becomes
markup.

Interactive parts are Datastar attributes: `data-bind` ties an input to a signal, and `data-on`
sends the signals to the server, which answers with the elements that changed. Signals are named
after the API's request bodies (`user.email`, `article.title`), so what the browser sends is what
the API would accept.
-/

namespace RealWorld.Web.Views

open Html

def datastarJs : String :=
  "https://cdn.jsdelivr.net/gh/starfederation/datastar@v1.0.4/bundles/datastar.js"
def ioniconsCss : String := "https://cdnjs.cloudflare.com/ajax/libs/ionicons/2.0.1/css/ionicons.min.css"
def fontsCss : String :=
  "https://fonts.googleapis.com/css?family=Source+Sans+Pro:300,400,600,700|Lora:400,700"

def nbsp : String := " "

/-- A Datastar action. The URL is written as a JSON string, which is also a JavaScript string, so
nothing a username can hold ends the expression early. -/
def action (method url : String) : String := s!"@{method}({Json.renderString url})"

def avatar (image : Option String) : String :=
  match image with
  | some url => if url.trimAscii.isEmpty then "/default-avatar.svg" else url
  | none => "/default-avatar.svg"

def months : Array String :=
  #["January", "February", "March", "April", "May", "June", "July", "August", "September",
    "October", "November", "December"]

/-- `2026-10-05T08:51:25.123Z` as `October 5, 2026`. -/
def date (iso : String) : String :=
  match ((iso.take 10).toString.splitOn "-").map String.toNat? with
  | [some y, some m, some d] => s!"{months.getD (m - 1) ""} {d}, {y}"
  | _ => iso

/-- A JSON value for a `data-signals` attribute. lean-html escapes it as an attribute value. -/
def signals (j : Json) : String × String := ("data-signals", Json.compress j)

def onClick (expr : String) : String × String := ("data-on:click", expr)

def onSubmit (expr : String) : String × String := ("data-on:submit__prevent", expr)

/-! ## Layout -/

inductive Page where
  | home | login | register | editor | settings | profile (username : String) | other
deriving DecidableEq

def navItem (active : Bool) (href : String) (content : List (Node .phrasing)) : Node .listItem :=
  li [ a (cat := .phrasing) { href, class_ := if active then "nav-link active" else "nav-link" } content ]
    { class_ := "nav-item" }

def navbar (viewer : Option Db.UserRow) (page : Page) : Node .flow :=
  let items := match viewer with
    | none =>
      [ navItem (page == .home) Site.links.home [ "Home" ],
        navItem (page == .login) Site.links.login [ "Sign in" ],
        navItem (page == .register) Site.links.register [ "Sign up" ] ]
    | some me =>
      [ navItem (page == .home) Site.links.home [ "Home" ],
        navItem (page == .editor) Site.links.editor [ i [] { class_ := "ion-compose" }, s!"{nbsp}New Article" ],
        navItem (page == .settings) Site.links.settings [ i [] { class_ := "ion-gear-a" }, s!"{nbsp}Settings" ],
        navItem (page == .profile me.username) (Site.links.profile me.username)
          [ img { src := avatar me.image, alt := "", class_ := "user-pic" }, me.username ] ]
  nav [
    div [
      a { href := Site.links.home, class_ := "navbar-brand" } [ "conduit" ],
      ul items { class_ := "nav navbar-nav pull-xs-right" }
    ] { class_ := "container" }
  ] { class_ := "navbar navbar-light" }

def footer_ : Node .flow :=
  footer [
    div [
      a { href := Site.links.home, class_ := "logo-font" } [ "conduit" ],
      span [ "Served by Lean: ",
             a { href := "https://github.com/saviorand/lean-realworld-example-app" } [ "source" ],
             ". Code & design licensed under MIT." ] { class_ := "attribution" }
    ] { class_ := "container" }
  ]

def layout (pageTitle : String) (viewer : Option Db.UserRow) (page : Page)
    (content : List (Node .flow)) : String :=
  document (lang := "en") [
    head [
      meta_ [("charset", "utf-8")],
      meta_ [("name", "viewport"), ("content", "width=device-width, initial-scale=1")],
      title (if pageTitle.isEmpty then "Conduit" else s!"{pageTitle} — Conduit"),
      link { rel := "stylesheet", href := ioniconsCss },
      link { rel := "stylesheet", href := fontsCss },
      link { rel := "stylesheet", href := "/styles.css" },
      link { rel := "icon", href := "/default-avatar.svg" },
      script { src := datastarJs } [("type", "module")]
    ],
    body ([navbar viewer page] ++ content ++ [footer_])
  ]

/-- The list a form's failures are patched into. Always rendered, so there is always something
with this id to patch. -/
def errors (id : String) (e : Option ApiError := none) : Node .flow :=
  let messages := match e with
    | some e => e.errors.toList.flatMap fun (field, msgs) =>
        msgs.toList.map fun msg => li [ (s!"{field} {msg}" : Node .flow) ]
    | none => []
  ul messages { class_ := "error-messages", id }

/-! ## Articles -/

/-- Where a favorite or follow button sits, which decides how it looks and which copy of it a
response patches. -/
inductive Place where
  | preview | top | bottom | profile
deriving DecidableEq

def Place.name : Place → String
  | .preview => "preview" | .top => "top" | .bottom => "bottom" | .profile => "profile"

def favoriteId (slug : String) : Place → String
  | .preview => s!"favorite-{slug}"
  | place => s!"favorite-{place.name}"

def favoriteButton (art : Db.ArticleRow) (place : Place) : Node .phrasing :=
  let method := if art.favorited then "delete" else "post"
  let click := onClick (action method s!"{Site.links.favorite art.slug}?place={place.name}")
  let style := if art.favorited then "btn-primary" else "btn-outline-primary"
  match place with
  | .preview =>
    button [ i [] { class_ := "ion-heart" }, s!" {art.favoritesCount}" ]
      { type := "button", id := favoriteId art.slug place, class_ := s!"btn {style} btn-sm pull-xs-right" }
      [click]
  | _ =>
    button [ i [] { class_ := "ion-heart" },
             s!"{nbsp}{if art.favorited then "Unfavorite" else "Favorite"} Article ",
             span [ s!"({art.favoritesCount})" ] { class_ := "counter" } ]
      { type := "button", id := favoriteId art.slug place, class_ := s!"btn btn-sm {style}" }
      [click]

def followId : Place → String
  | place => s!"follow-{place.name}"

def followButton (username : String) (following : Bool) (place : Place) : Node .phrasing :=
  let method := if following then "delete" else "post"
  button [ i [] { class_ := if following then "ion-minus-round" else "ion-plus-round" },
           s!"{nbsp}{if following then "Unfollow" else "Follow"} {username}" ]
    { type := "button", id := followId place,
      class_ := "btn btn-sm btn-outline-secondary action-btn" }
    [onClick (action method s!"{Site.links.follow username}?place={place.name}")]

def tagList (tags : Array String) : Node .flow :=
  ul (tags.toList.map fun t => li [ Node.text t ] { class_ := "tag-default tag-pill tag-outline" })
    { class_ := "tag-list" }

def authorInfo (username : String) (image : Option String) (created : String) : List (Node .flow) :=
  [ a { href := Site.links.profile username } [ img { src := avatar image, alt := username } ],
    div [ a { href := Site.links.profile username, class_ := "author" } [ username ],
          span [ date created ] { class_ := "date" } ] { class_ := "info" } ]

def preview (art : Db.ArticleRow) : Node .flow :=
  div [
    div (authorInfo art.authorUsername art.authorImage art.createdAt ++ [(favoriteButton art .preview).toFlow])
      { class_ := "article-meta" },
    a { href := Site.links.article art.slug, class_ := "preview-link" }
      [ h1 [ art.title ], p [ art.description ], span [ "Read more..." ], tagList art.tagList ]
  ] { class_ := "article-preview" }

def pageSize : Nat := 10

/-- Page links, each keeping whatever else the query said (`base` ends in `?` or `&`). -/
def pagination (count : Nat) (current : Nat) (base : String) : Node .flow :=
  let pages := (count + pageSize - 1) / pageSize
  if pages ≤ 1 then ul [] { class_ := "pagination" }
  else
    ul ((List.range pages).map fun n =>
        li [ a { href := s!"{base}page={n + 1}", class_ := "page-link" } [ s!"{n + 1}" ] ]
          { class_ := if n + 1 == current then "page-item active" else "page-item" })
      { class_ := "pagination" }

def articleList (rows : Array Db.ArticleRow) (count : Nat) (current : Nat) (base : String) :
    List (Node .flow) :=
  if rows.isEmpty then [ div [ "No articles are here... yet." ] { class_ := "article-preview empty-feed-message" } ]
  else rows.toList.map preview ++ [pagination count current base]

/-! ## Pages -/

inductive Feed where
  | global | following | tag (name : String)
deriving DecidableEq

def homePage (viewer : Option Db.UserRow) (feed : Feed) (rows : Array Db.ArticleRow) (count : Nat)
    (current : Nat) (tags : Array String) : String :=
  let tab (active : Bool) (href : String) (content : List (Node .phrasing)) :=
    li [ a (cat := .phrasing) { href, class_ := if active then "nav-link active" else "nav-link" } content ]
      { class_ := "nav-item" }
  let tabs := (if viewer.isSome then [tab (feed == .following) s!"{Site.links.home}?feed=following" [ "Your Feed" ]] else [])
    ++ [tab (feed == .global) Site.links.home [ "Global Feed" ]]
    ++ (match feed with
        | .tag name => [tab true (Site.links.tag name) [ i [] { class_ := "ion-pound" }, s!" {name}" ]]
        | _ => [])
  let base := match feed with
    | .global => s!"{Site.links.home}?"
    | .following => s!"{Site.links.home}?feed=following&"
    | .tag name => s!"{Site.links.tag name}?"
  layout "" viewer .home [
    div [
      div [ div [ h1 [ "conduit" ] { class_ := "logo-font" }, p [ "A place to share your knowledge." ] ]
              { class_ := "container" } ] { class_ := "banner" },
      div [
        div [
          div ([div [ ul tabs { class_ := "nav nav-pills outline-active" } ] { class_ := "feed-toggle" }]
                ++ articleList rows count current base) { class_ := "col-md-9" },
          div [
            div [
              p [ "Popular Tags" ],
              div (tags.toList.map fun t => a { href := Site.links.tag t, class_ := "tag-pill tag-default" } [ t ])
                { class_ := "tag-list" }
            ] { class_ := "sidebar" }
          ] { class_ := "col-md-3" }
        ] { class_ := "row" }
      ] { class_ := "container page" }
    ] { class_ := "home-page" }
  ]

def field (input : Node .phrasing) : Node .flow := fieldset [ input ] { class_ := "form-group" }

def textInput (signal placeholder : String) (name : String) (large := true) (type := "text") :
    Node .phrasing :=
  Html.input { type, name, placeholder,
               class_ := if large then "form-control form-control-lg" else "form-control" }
    [("data-bind", signal)]

def authPage (registering : Bool) : String :=
  let submit := action "post" (if registering then Site.links.register else Site.links.login)
  let initial : Json := .obj #[("user", .obj (
    (if registering then #[("username", .str "")] else #[]) ++ #[("email", .str ""), ("password", .str "")]))]
  layout (if registering then "Sign up" else "Sign in") none (if registering then .register else .login) [
    div [
      div [
        div [
          div [
            h1 [ if registering then "Sign up" else "Sign in" ] { class_ := "text-xs-center" },
            p [ if registering then a { href := Site.links.login } [ "Have an account?" ]
                else a { href := Site.links.register } [ "Need an account?" ] ] { class_ := "text-xs-center" },
            errors "errors",
            form ((if registering then [field (textInput "user.username" "Username" "username")] else [])
              ++ [ field (textInput "user.email" "Email" "email"),
                   field (textInput "user.password" "Password" "password" (type := "password")),
                   button [ if registering then "Sign up" else "Sign in" ]
                     { class_ := "btn btn-lg btn-primary pull-xs-right" } ])
              {} [signals initial, onSubmit submit]
          ] { class_ := "col-md-6 offset-md-3 col-xs-12" }
        ] { class_ := "row" }
      ] { class_ := "container page" }
    ] { class_ := "auth-page" }
  ]

def settingsPage (me : Db.UserRow) : String :=
  let opt := fun (o : Option String) => Json.str (o.getD "")
  let initial : Json := .obj #[("user", .obj #[
    ("image", opt me.image), ("username", .str me.username), ("bio", opt me.bio),
    ("email", .str me.email), ("password", .str "")])]
  layout "Settings" (some me) .settings [
    div [
      div [
        div [
          div [
            h1 [ "Your Settings" ] { class_ := "text-xs-center" },
            errors "errors",
            form [
              fieldset [
                field (textInput "user.image" "URL of profile picture" "image" (large := false)),
                field (textInput "user.username" "Your Name" "username"),
                field (textarea "" { name := "bio", placeholder := "Short bio about you", rows := "8",
                                     class_ := "form-control form-control-lg" } [("data-bind", "user.bio")]),
                field (textInput "user.email" "Email" "email"),
                field (textInput "user.password" "New Password" "password" (type := "password")),
                button [ "Update Settings" ] { class_ := "btn btn-lg btn-primary pull-xs-right" }
              ]
            ] {} [signals initial, onSubmit (action "post" Site.links.settings)],
            hr,
            button [ "Or click here to logout." ] { type := "button", class_ := "btn btn-outline-danger" }
              [onClick (action "post" Site.links.logout)]
          ] { class_ := "col-md-6 offset-md-3 col-xs-12" }
        ] { class_ := "row" }
      ] { class_ := "container page" }
    ] { class_ := "settings-page" }
  ]

def editorPage (me : Db.UserRow) (existing : Option Db.ArticleRow) : String :=
  let initial : Json := .obj #[
    ("article", .obj #[
      ("title", .str ((existing.map (·.title)).getD "")),
      ("description", .str ((existing.map (·.description)).getD "")),
      ("body", .str ((existing.map (·.body)).getD ""))]),
    ("tags", .str ((existing.map fun art => " ".intercalate art.tagList.toList).getD ""))]
  let submit := action "post" (match existing with
    | some art => Site.links.editArticle art.slug
    | none => Site.links.editor)
  layout (if existing.isSome then "Edit article" else "New article") (some me) .editor [
    div [
      div [
        div [
          div [
            errors "errors",
            form [
              fieldset [
                field (textInput "article.title" "Article Title" "title"),
                field (textInput "article.description" "What's this article about?" "description" (large := false)),
                field (textarea "" { name := "body", placeholder := "Write your article (in markdown)", rows := "8",
                                     class_ := "form-control" } [("data-bind", "article.body")]),
                field (textInput "tags" "Enter tags" "tags" (large := false)),
                button [ "Publish Article" ] { class_ := "btn btn-lg pull-xs-right btn-primary" }
              ]
            ] {} [signals initial, onSubmit submit]
          ] { class_ := "col-md-10 offset-md-1 col-xs-12" }
        ] { class_ := "row" }
      ] { class_ := "container page" }
    ] { class_ := "editor-page" }
  ]

def articleMeta (viewer : Option Db.UserRow) (art : Db.ArticleRow) (place : Place) : Node .flow :=
  let mine := viewer.any (·.id == art.authorId)
  let actions : List (Node .flow) :=
    if mine then
      [ a { href := Site.links.editArticle art.slug, class_ := "btn btn-sm btn-outline-secondary" }
          [ i [] { class_ := "ion-edit" }, " Edit Article" ],
        (s!"{nbsp}" : Node .flow),
        button [ i [] { class_ := "ion-trash-a" }, " Delete Article" ]
          { type := "button", class_ := "btn btn-sm btn-outline-danger" }
          [onClick s!"confirm('Delete this article?') && {action "delete" (Site.links.article art.slug)}"] ]
    else
      [ (followButton art.authorUsername art.following place).toFlow, (s!"{nbsp}{nbsp}" : Node .flow),
        (favoriteButton art place).toFlow ]
  div (authorInfo art.authorUsername art.authorImage art.createdAt ++ actions) { class_ := "article-meta" }

def commentCard (viewer : Option Db.UserRow) (slug : String) (c : Db.CommentRow) : Node .flow :=
  let delete : List (Node .phrasing) :=
    if viewer.any (·.id == c.authorId) then
      [ span [ i [] { class_ := "ion-trash-a" } ] { class_ := "mod-options" }
          [onClick (action "delete" (Site.links.comment slug c.id.toInt.toNat))] ]
    else []
  div [
    div [ p [ c.body ] { class_ := "card-text" } ] { class_ := "card-block" },
    div (([ a { href := Site.links.profile c.authorUsername, class_ := "comment-author" }
             [ img { src := avatar c.authorImage, alt := c.authorUsername, class_ := "comment-author-img" } ],
           (s!"{nbsp}" : Node .phrasing),
           a { href := Site.links.profile c.authorUsername, class_ := "comment-author" } [ c.authorUsername ],
           span [ date c.createdAt ] { class_ := "date-posted" } ] ++ delete).map Node.toFlow) { class_ := "card-footer" }
  ] { class_ := "card", id := s!"comment-{c.id}" }

def commentForm (me : Db.UserRow) (slug : String) : Node .flow :=
  form [
    div [ textarea "" { name := "body", placeholder := "Write a comment...", rows := "3", class_ := "form-control" }
            [("data-bind", "comment.body")] ] { class_ := "card-block" },
    div [ img { src := avatar me.image, alt := me.username, class_ := "comment-author-img" },
          button [ "Post Comment" ] { class_ := "btn btn-sm btn-primary" } ] { class_ := "card-footer" }
  ] { class_ := "card comment-form" }
    [signals (.obj #[("comment", .obj #[("body", .str "")])]),
     onSubmit (action "post" (Site.links.comments slug))]

def articlePage (viewer : Option Db.UserRow) (art : Db.ArticleRow) (comments : Array Db.CommentRow) : String :=
  let body := CommonMark.renderHtmlSafe (CommonMark.parseDocument art.body)
  layout art.title viewer .other [
    div [
      div [ div [ h1 [ art.title ], articleMeta viewer art .top ] { class_ := "container" } ] { class_ := "banner" },
      div [
        div [ div [ Node.unsafeRaw body, tagList art.tagList ] { class_ := "col-md-12" } ]
          { class_ := "row article-content" },
        hr,
        div [ articleMeta viewer art .bottom ] { class_ := "article-actions" },
        div [
          div ((match viewer with
                | some me => [errors "comment-errors", commentForm me art.slug]
                | none => [p [ a { href := Site.links.login } [ "Sign in" ], " or ",
                               a { href := Site.links.register } [ "sign up" ], " to add comments on this article." ]])
              ++ [div (comments.toList.map (commentCard viewer art.slug)) { id := "comments" }])
            { class_ := "col-xs-12 col-md-8 offset-md-2" }
        ] { class_ := "row" }
      ] { class_ := "container page" }
    ] { class_ := "article-page" }
  ]

def profilePage (viewer : Option Db.UserRow) (prof : Db.ProfileRow) (favorites : Bool)
    (rows : Array Db.ArticleRow) (count : Nat) (current : Nat) : String :=
  let mine := viewer.any (·.id == prof.id)
  let tab (active : Bool) (href : String) (label : String) :=
    li [ a { href, class_ := if active then "nav-link active" else "nav-link" } [ label ] ] { class_ := "nav-item" }
  let base := s!"{if favorites then Site.links.favorites prof.username else Site.links.profile prof.username}?"
  layout prof.username viewer (.profile prof.username) [
    div [
      div [ div [ div [ div [
        img { src := avatar prof.image, alt := prof.username, class_ := "user-img" },
        h4 [ prof.username ],
        Html.p [ prof.bio.getD "" ],
        if mine then
          a { href := Site.links.settings, class_ := "btn btn-sm btn-outline-secondary action-btn" }
            [ i [] { class_ := "ion-gear-a" }, s!"{nbsp}Edit Profile Settings" ]
        else (followButton prof.username prof.following .profile).toFlow
      ] { class_ := "col-xs-12 col-md-10 offset-md-1" } ] { class_ := "row" } ] { class_ := "container" } ]
        { class_ := "user-info" },
      div [ div [ div ([
        div [ ul [ tab (!favorites) (Site.links.profile prof.username) "My Articles",
                   tab favorites (Site.links.favorites prof.username) "Favorited Articles" ]
                { class_ := "nav nav-pills outline-active" } ] { class_ := "articles-toggle" }
      ] ++ articleList rows count current base) { class_ := "col-xs-12 col-md-10 offset-md-1" } ] { class_ := "row" } ]
        { class_ := "container" }
    ] { class_ := "profile-page" }
  ]

def notFoundPage (viewer : Option Db.UserRow) : String :=
  layout "Not found" viewer .other [
    div [ div [ h1 [ "Not found" ], p [ a { href := Site.links.home } [ "Back to the home page" ] ] ]
            { class_ := "container" } ] { class_ := "container page" }
  ]

end RealWorld.Web.Views
