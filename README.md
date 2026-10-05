# Lean RealWorld example app

[RealWorld](https://github.com/realworld-apps/realworld) in Lean 4, on both ends: the Medium-style blogging app (users, profiles, articles, comments, tags, favourites, follows) that has been implemented in over a hundred stacks.

- **The API** (`/api/...`) passes the official Hurl suite, 154 requests in 13 files.
- **The site** (everything else) is the Conduit frontend, rendered on the server with typed HTML and made interactive with [Datastar](https://data-star.dev): forms, favourites, follows and comments update in place over server-sent events, with no frontend build step. It calls the same service layer as the API, so every rule is written once.

## Stack

Lean 4.34.1, `Std.Http.Server`, PostgreSQL, and:

| | |
|---|---|
| [lean-routing](https://github.com/paulbutcher/lean-routing) | typed route tables, and the links the site's pages use |
| [lean-middleware](https://github.com/paulbutcher/lean-middleware) | CORS, cookies, exception handling, query parameters, static files |
| [leanpostgres](https://github.com/paulbutcher/leanpostgres) · [leanmigrate](https://github.com/paulbutcher/leanmigrate) | `libpq` bindings with a connection pool; SQL migrations |
| [lean-json](https://github.com/paulbutcher/lean-json) | JSON |
| [lean-jose](https://github.com/paulbutcher/lean-jose) | HS256 JWTs |
| [lean-libcrypto](https://github.com/paulbutcher/lean-libcrypto) | OpenSSL's scrypt, for password hashing |
| [leancrypto](https://github.com/paulbutcher/leancrypto) | base64url, constant-time comparison |
| [lean-html](https://github.com/paulbutcher/lean-html) | typed, escaped HTML for the site |
| [lean-markdown](https://github.com/paulbutcher/lean-markdown) | article bodies, through its proved-safe `renderHtmlSafe` |
| [datastar-lean](https://github.com/carlohamalainen/datastar-lean) | Datastar's server-sent events; [Datastar](https://data-star.dev) 1.0.4 in the browser |

### Library changes not yet released

This application needed changes to most of those libraries, and none is released yet, so `lakefile.toml` requires each at the `lean-realworld` branch of a fork, which holds them on Lean 4.34.1:

| Library | Change | Status |
|---|---|---|
| leancrypto, lean-html, lean-libcrypto, lean-routing, lean-middleware, lean-markdown | move to Lean 4.34.1 | [leancrypto#1](https://github.com/paulbutcher/leancrypto/pull/1), [lean-html#1](https://github.com/paulbutcher/lean-html/pull/1), [lean-libcrypto#1](https://github.com/paulbutcher/lean-libcrypto/pull/1), [lean-routing#1](https://github.com/paulbutcher/lean-routing/pull/1), [lean-middleware#1](https://github.com/paulbutcher/lean-middleware/pull/1), [lean-markdown#2](https://github.com/paulbutcher/lean-markdown/pull/2) |
| lean-json | move to Lean 4.34 | [lean-json#1](https://github.com/paulbutcher/lean-json/pull/1) |
| leanpostgres, leanmigrate, lean-jose | move to Lean 4.34.1 | waiting for a lean-json release |
| lean-routing | `String` captures in links are percent-encoded, so a link round-trips through `dispatch` | [lean-routing#2](https://github.com/paulbutcher/lean-routing/pull/2) |
| lean-middleware | a `cors` middleware | [lean-middleware#2](https://github.com/paulbutcher/lean-middleware/pull/2) |
| leanpostgres | `Error.constraint`, the constraint a violation names | [leanpostgres#1](https://github.com/paulbutcher/leanpostgres/pull/1) |
| lean-html | `a` takes its parent's content model, as HTML5 does | [lean-html#2](https://github.com/paulbutcher/lean-html/pull/2) |
| datastar-lean | built on the module system, with `Lean.Data.Json` optional (`Datastar.Core`) | [saviorand/datastar-lean-modules](https://github.com/saviorand/datastar-lean-modules/tree/lean-realworld) |

Lake resolves the requirements from the last up and keeps the first version it finds of each package, so the libraries others depend on are listed last; that is what makes the fork versions replace the older ones the libraries pin of each other.

## Running

Needs [elan](https://github.com/leanprover/elan), PostgreSQL, and the `libpq` and OpenSSL 3 headers with `pkg-config` (`brew install libpq openssl@3 pkg-config`, or `apt-get install libpq-dev libssl-dev pkg-config`).

```
createdb realworld
DATABASE_URL="dbname=realworld" JWT_SECRET="at-least-32-bytes-of-secret......" lake exe realworld
```

Open <http://127.0.0.1:8000>. The server applies migrations at startup and serves `public/` (the shared Conduit stylesheet and the default avatar) from the working directory.

The binary, `.lake/build/bin/realworld`, loads one library of its own at runtime: lean-libcrypto's OpenSSL shim, `libcrypto_shim.so` (`.dylib` on macOS), in `.lake/packages/libcrypto/.lake/build/lib`. `lake exe` finds it; to run the binary anywhere else, put the shim on the loader's path, with `LD_LIBRARY_PATH` or in `/usr/lib`, along with `public/` and `migrations/` in the working directory.

| Variable | Default | |
|---|---|---|
| `DATABASE_URL` | empty, so libpq reads the `PG*` variables | a libpq connection string |
| `JWT_SECRET` | random per process | at least 32 bytes; without it, tokens stop working on restart |
| `PORT` | `8000` | |
| `HOST` | `127.0.0.1` | an IPv4 address; `0.0.0.0` to listen on every interface |
| `POOL_SIZE` | `16` | database connections |

## Testing

```
lake test                      # unit tests
scripts/run-api-tests.sh       # the RealWorld API suite, against a fresh build
cd e2e && node flow.js         # the site in Chromium, against a running server
```

CI runs the unit tests and the API suite on every push, and checks that no proof rests on an axiom beyond Lean's standard three. The API suite needs Hurl 5 or newer and a checkout of [realworld-apps/realworld](https://github.com/realworld-apps/realworld) beside this repository (or `REALWORLD=/path/to/it`). The browser walk-through needs Node and Playwright (`npm install && npx playwright install chromium` in `e2e/`).

## Layout

| | |
|---|---|
| `RealWorld/Requests.lean` | request bodies parsed and validated, including the absent/`null`/value distinction `PUT` needs |
| `RealWorld/Service.lean` | what the app does, shared by the API and the site |
| `RealWorld/Db.lean` | every SQL statement |
| `RealWorld/Api.lean` | one handler per API endpoint |
| `RealWorld/Http.lean` | the handler monad, reading requests, JSON response bodies |
| `RealWorld/App.lean` | the API's route table and the middleware stack |
| `RealWorld/Web/Views.lean` · `RealWorld/Web/Pages.lean` | the site's pages and its Datastar actions |
| `RealWorld/Web/Routes.lean` | the site's route table |
| `RealWorld/Password.lean` · `RealWorld/Token.lean` | scrypt hashes and JWTs |
| `migrations/` | the schema |

## Proved

| Theorem | Says |
|---|---|
| `Slug.ofTitle_valid` | every slug is words of `[a-z0-9]` joined by single hyphens: never empty, no leading, trailing or doubled hyphen |
| `Service.loginOutcome_unknown_email` | a failed login answers the same whether or not the email has an account |
| `Service.authorize_ok_iff` | an article or comment can be changed exactly when the requester wrote it |

The libraries carry their own: lean-html's output is well-formed HTML, lean-markdown's sanitised rendering never lets text from a document become markup, lean-json reads back what it writes, and leancrypto's encodings round-trip.

## License

MIT; see [LICENSE](LICENSE). `public/styles.css` and `public/default-avatar.svg` are RealWorld's shared Conduit theme, from [realworld-apps/realworld](https://github.com/realworld-apps/realworld), under its MIT license, in [LICENSE-realworld](LICENSE-realworld).
