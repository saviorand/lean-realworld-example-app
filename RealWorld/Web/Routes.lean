module

public import Routing.RouteTable

@[expose] public section

/-! The site's routes, apart from its handlers so that views can link with `Site.links` and a link
cannot drift from the route that serves it. -/

route_table Site
  [ home := "/",
    tag := "/tag/:tag:String",
    login := "/login",
    register := "/register",
    settings := "/settings",
    logout := "/logout",
    editor := "/editor",
    editArticle := "/editor/:slug:String",
    article := "/article/:slug:String",
    favorite := "/article/:slug:String/favorite",
    comments := "/article/:slug:String/comments",
    comment := "/article/:slug:String/comments/:id:Nat",
    profile := "/profile/:username:String",
    favorites := "/profile/:username:String/favorites",
    follow := "/profile/:username:String/follow" ]
