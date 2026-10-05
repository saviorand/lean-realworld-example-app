module

public import Routing
public import RealWorld.Api
public import RealWorld.Web.Pages

public section

namespace RealWorld

open Std Http Server
open Routing
open Middleware

route_table Api
  [ login := "/api/users/login",
    users := "/api/users",
    user := "/api/user",
    profile := "/api/profiles/:username:String",
    follow := "/api/profiles/:username:String/follow",
    articles := "/api/articles",
    feed := "/api/articles/feed",
    article := "/api/articles/:slug:String",
    favorite := "/api/articles/:slug:String/favorite",
    comments := "/api/articles/:slug:String/comments",
    comment := "/api/articles/:slug:String/comments/:id:Nat",
    tags := "/api/tags" ]

open Api in
/-- Routes are tried in order, so the feed comes before the article pattern it would also match. -/
def routes (env : Env) : List (Route Result) :=
  open RealWorld.Api in
  [ .post patterns.login (login env),
    .post patterns.users (register env),
    .get patterns.user (currentUser env),
    .put patterns.user (updateUser env),
    .get patterns.profile (getProfile env),
    .post patterns.follow (follow env),
    .delete patterns.follow (unfollow env),
    .get patterns.feed (feed env),
    .get patterns.articles (listArticles env),
    .post patterns.articles (createArticle env),
    .get patterns.article (getArticle env),
    .put patterns.article (updateArticle env),
    .delete patterns.article (deleteArticle env),
    .post patterns.favorite (favorite env),
    .delete patterns.favorite (unfavorite env),
    .get patterns.comments (listComments env),
    .post patterns.comments (addComment env),
    .delete patterns.comment (deleteComment env),
    .get patterns.tags (tags env) ]

/-- JSON under `/api`, the site's own page everywhere else. -/
def notFound (env : Env) : Result := fun req =>
  match req.line.uri.path.toDecodedSegments.toList with
  | "api" :: _ => jsonResponse .notFound (ApiError.notFound "route").toJson
  | _ => Web.notFound env req

/-- Any origin may call the API, which authenticates with a header rather than a cookie, so no
credentials are allowed and a page elsewhere cannot act as a signed-in user. The allowed request
headers are the API's own, which leaves out the header Datastar sends with the site's actions.

`file` serves the stylesheet and the default avatar from `public`, and passes everything else
through to the routes. -/
def app (env : Env) : StatelessHandler :=
  Middleware.apply
    [cors { allowHeaders := some ["content-type", "authorization"] },
     catchAll, cookies, params, contentType, file "public"]
    (toHandler (routes env ++ Web.routes env) (notFound env))

end RealWorld
