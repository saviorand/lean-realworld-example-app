# Lean RealWorld example app

This is a [RealWorld](https://github.com/realworld-apps/realworld) implementation written in Lean 4 on both ends, the backend and the frontend. RealWorld is the Medium-style blogging app (users, profiles, articles, comments, tags, favorites, follows) that has been implemented in over a hundred stacks.

The JSON API under `/api` passes the official Hurl suite, 154 requests in 13 files. Everything else is the site, the Conduit frontend rendered on the server with typed HTML. Forms, favorites, follows and comments update in place over server-sent events through [Datastar](https://data-star.dev), and there is no frontend build step. The site calls the same service layer as the API, so every rule is written once, and it passes all 74 tests that the official Playwright suite runs against an app that owns both ends.

## Stack

The app runs on Lean 4.34.1 with `Std.Http.Server` and PostgreSQL, and uses these libraries:

| | |
|---|---|
| [lean-routing](https://github.com/paulbutcher/lean-routing) | typed route tables, and the links the site's pages use |
| [lean-middleware](https://github.com/paulbutcher/lean-middleware) | CORS, cookies, exception handling, query parameters, static files |
| [leanpostgres](https://github.com/paulbutcher/leanpostgres) · [leanmigrate](https://github.com/paulbutcher/leanmigrate) | `libpq` bindings with a connection pool, and SQL migrations |
| [lean-json](https://github.com/paulbutcher/lean-json) | JSON |
| [lean-jose](https://github.com/paulbutcher/lean-jose) | HS256 JWTs |
| [lean-libcrypto](https://github.com/paulbutcher/lean-libcrypto) | OpenSSL's scrypt, for password hashing |
| [leancrypto](https://github.com/paulbutcher/leancrypto) | base64url, constant-time comparison |
| [lean-html](https://github.com/paulbutcher/lean-html) | typed, escaped HTML for the site |
| [lean-markdown](https://github.com/paulbutcher/lean-markdown) | article bodies, through its proved-safe `renderHtmlSafe` |
| [datastar-lean](https://github.com/carlohamalainen/datastar-lean) | Datastar's server-sent events, with [Datastar](https://data-star.dev) 1.0.4 in the browser |

### Unreleased library changes

The app needed changes to most of these libraries. lean-html v0.10.0, lean-routing v0.8.0 and lean-markdown v0.8.0 include what it needed from those three, so `lakefile.toml` requires them at those releases. The other changes are not released yet, and `lakefile.toml` requires each remaining library at the `lean-realworld` branch of a fork, which holds its changes on Lean 4.34.1:

| Library | Change | Pull request |
|---|---|---|
| leancrypto, lean-libcrypto, lean-middleware | move to Lean 4.34.1 | [leancrypto#1](https://github.com/paulbutcher/leancrypto/pull/1), [lean-libcrypto#1](https://github.com/paulbutcher/lean-libcrypto/pull/1), [lean-middleware#1](https://github.com/paulbutcher/lean-middleware/pull/1) |
| lean-middleware | a `cors` middleware | [lean-middleware#2](https://github.com/paulbutcher/lean-middleware/pull/2) |
| leanpostgres | `Error.constraint`, the constraint a violation names | [leanpostgres#1](https://github.com/paulbutcher/leanpostgres/pull/1) |
| lean-json | move to Lean 4.34 | [lean-json#1](https://github.com/paulbutcher/lean-json/pull/1) |
| leanpostgres, leanmigrate, lean-jose | move to Lean 4.34.1 | waiting for a lean-json release |
| datastar-lean | built on the module system, with `Lean.Data.Json` optional (`Datastar.Core`) | [datastar-lean#4](https://github.com/carlohamalainen/datastar-lean/pull/4) |

Lake resolves the requirements from the last up and keeps the first version it finds of each package. The libraries others depend on are therefore listed last, which lets the versions in `lakefile.toml` replace the older ones the libraries pin of each other.

## Running

You need [elan](https://github.com/leanprover/elan) and a PostgreSQL server. Building also needs the `libpq` and OpenSSL 3 headers and `pkg-config` (`brew install libpq openssl@3 pkg-config`, or `apt-get install libpq-dev libssl-dev pkg-config`).

```
createdb realworld
DATABASE_URL="dbname=realworld" JWT_SECRET="at-least-32-bytes-of-secret......" lake exe realworld
```

Open <http://127.0.0.1:8000>. The server applies migrations at startup and serves `public/` (the shared Conduit stylesheet and the default avatar) from the working directory.

The binary, `.lake/build/bin/realworld`, loads one library of its own at runtime: lean-libcrypto's OpenSSL shim, `libcrypto_shim.so` (`.dylib` on macOS), in `.lake/packages/libcrypto/.lake/build/lib`. `lake exe` finds it. To run the binary anywhere else, put the shim on the loader's path (with `LD_LIBRARY_PATH`, or in `/usr/lib`) and `public/` and `migrations/` in the working directory.

| Variable | Default | |
|---|---|---|
| `DATABASE_URL` | empty, so libpq reads the `PG*` variables | a libpq connection string |
| `JWT_SECRET` | random per process | at least 32 bytes. Without it, tokens stop working on restart |
| `PORT` | `8000` | |
| `HOST` | `127.0.0.1` | an IPv4 address, or `0.0.0.0` to listen on every interface |
| `POOL_SIZE` | `16` | database connections |

## Testing

```
lake test                      # unit tests
scripts/run-api-tests.sh       # the RealWorld API suite, against a fresh build
scripts/run-frontend-tests.sh  # the RealWorld frontend suite, likewise, on an empty database
cd e2e && node flow.js         # a walk through the site, against a running server
```

CI runs all but the walk-through on every push, and checks that no proof rests on an axiom beyond Lean's standard three. Both suites need a checkout of [realworld-apps/realworld](https://github.com/realworld-apps/realworld) beside this repository (or `REALWORLD=/path/to/it`). The API suite needs Hurl 5 or newer, and the frontend suite and the walk-through need Node and Playwright (`npm ci && npx playwright install chromium` in `e2e/`). The frontend suite wants a database with no articles, because its tests look for the tags they create among the popular ones, so run it as `DATABASE_URL=dbname=fresh scripts/run-frontend-tests.sh` after `createdb fresh`.

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

## Proofs

| Theorem | Says |
|---|---|
| `Slug.ofTitle_valid` | every slug is words of `[a-z0-9]` joined by single hyphens, so it is never empty and has no hyphen at either end or two in a row |
| `Service.loginOutcome_unknown_email` | a failed login answers the same whether or not the email has an account |
| `Service.authorize_ok_iff` | an article or comment can be changed exactly when the requester wrote it |

The libraries carry proofs of their own. lean-html's output is well-formed HTML, lean-markdown's sanitized rendering never lets text from a document become markup, lean-json reads back what it writes, and leancrypto's encodings round-trip.

## License

The code is under the MIT license, in [LICENSE](LICENSE). `public/styles.css` and `public/default-avatar.svg` are RealWorld's shared Conduit theme from [realworld-apps/realworld](https://github.com/realworld-apps/realworld), under its own MIT license, in [LICENSE-realworld](LICENSE-realworld).
