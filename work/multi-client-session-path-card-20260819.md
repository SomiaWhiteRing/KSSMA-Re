# Multi-client session path card (2026-08-19)

## Frontier

Two clients can authenticate different local accounts, but `createServer()` currently stores the
last login in process-global `activeAccount` / `playerSavePath`. The second login therefore redirects
the first client's later gameplay requests to the second account save.

## Accepted target path

The stock Java transport already provides the complete per-client state carrier needed here:

```text
native gameplay connect
-> AsyncTaskRunner.connectPost(url, param, sender)
-> com/test/b.run()
-> HttpUtil.connectPost(url, param)
-> one static DefaultHttpClient
-> its per-process CookieStore
-> HTTP Cookie header on later /connect/app/* requests
```

Static DEX evidence from the source APK:

- `AsyncTaskRunner.connectPost` constructs `com/test/b` and starts it in a `Thread`.
- `com/test/b.run` calls `HttpUtil.connectPost(String,String)`.
- `HttpUtil.connectPost` constructs the static `DefaultHttpClient b` only while it is null, so one
  client process keeps one cookie jar across login and gameplay routes.
- `HttpUtil.a(String,String)` sends the actual `HttpPost` through
  `DefaultHttpClient.execute(...)`.
- After a request, `HttpUtil.connectPost` explicitly calls
  `DefaultHttpClient.getCookieStore().getCookies()` and iterates the cookies. It never clears that
  store between routes.

This is a stronger complete path than adding a new encrypted parameter in dozens of native route
builders: an ordinary `Set-Cookie` on `/connect/app/login` is accepted by the existing common
transport and is automatically replayed on every later request.

## Wrong path connection point

`server/bootstrap-server.js:createServer()` mutates closure-wide `activeAccount` and
`playerSavePath` in the login handler. All later route handlers read those two globals. MuMu NAT also
presents clients through the same host address, so source IP cannot repair this ambiguity.

## Product mapping

```text
POST /connect/app/login (valid credentials)
-> Set-Cookie: kssma_session=<signed account token>; Path=/; HttpOnly
-> stock DefaultHttpClient CookieStore
-> Cookie: kssma_session=<same token> on later routes
-> server verifies signature/expiry/account enabled state
-> resolves that request's account save path
```

The token is signed from the account's server-only password hash plus the existing local protocol
key. It contains a random nonce and issue time, survives a server restart, supports multiple
simultaneous sessions, and is invalidated by disabling the account or changing its password. The
token itself must never be logged.

For compatibility with existing direct protocol fixtures, a request with no session cookie retains
the last-login single-client fallback. A request which supplies a malformed/invalid
`kssma_session` cookie must fail closed rather than falling through to another account.

## Minimal observable

The HTTP/decrypt self-check must:

1. log in account 1 and account 2 and receive two different cookies;
2. send concurrent `/connect/app/mainmenu` requests with those cookies and decrypt different player
   names from the two independent saves;
3. send concurrent `/connect/app/exploration/explore` requests and prove AP/move mutations land in
   the matching save only;
4. reject a modified cookie without mutating either save.

Client acceptance remains a separate observable: two real client processes log in as different
accounts, both continue issuing gameplay routes, and server logs show different `accountUserId`
values without an intervening account switch.

## One variable / non-goals / stop

- One variable: restore per-client identity by issuing and consuming the transport's existing
  CookieStore session path.
- Non-goals: no fairy/reward rule changes, no IP-based identity, no APK/lib patch, no registration UI.
- Stop: if a real client does not replay `Set-Cookie`, collect the exact login/next-route headers and
  stop at a Java transport classifier. Do not begin per-route native parameter patches without a new
  path card and closed calling convention.

## Implemented result

- `server/bootstrap-server.js` now signs and verifies the account session, sets it only on a valid
  login, resolves gameplay account/save state per request, and rejects a supplied invalid Cookie with
  HTTP 401. Session values are absent from request/response logs.
- `node .\server\test-bootstrap-server.js` passes two different login cookies, concurrent mainmenu
  identity (`局域网亚瑟` / `协力亚瑟`), concurrent independent exploration writes (AP `9 -> 8` and
  `14 -> 13`, one move each), and a bad-signature replay with no save mutation.
- After the final live server restart, the fingerprint-clean process was healthy on `50005` and `10001`. A real encrypted login for
  account 1 returned `Set-Cookie`, and a following `/connect/app/mainmenu` using that Cookie returned
  HTTP 200 with player name `Yukie`. The server logged only `source=cookie`, `accountUserId=1`, and the
  save path; it did not log the token.
- The live registry currently contains only account 1, so two physical clients cannot yet complete the
  final visible co-op acceptance. Create account 2 in `/admin/`, then log two client processes into
  different accounts and require interleaved `connect_app_session` entries for user 1 and user 2.
