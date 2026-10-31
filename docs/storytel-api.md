## Storytel API (the four calls)

The source of truth is Bookwave's `server/storytel/client.ts` and
`server/storytel/fetch.ts` (https://github.com/sz3ry/bookwave). Port the
behaviour, not the code. Copy this section into the new repo as
`docs/storytel-api.md`.

Common to every request:
- Headers `x-storytel-terminal: ios` and
  `user-agent: Storytel/25.38.0 (iOS 26.0; iPhone16,2) Release/924.1`;
  query parameter `version=25.38.0`.
- Default `Accept: application/json, text/plain, */*` unless stated.
- **Redirects are never followed** (needed for the stream call).
- Bodies may be JSON even with a wrong content-type: parse JSON-looking bodies.
- 401 = session expired (or, on login, credentials rejected).

1. **Login** — `GET https://www.storytel.com/api/login.action?m=1&uid=<email>&pwd=<encrypted>`.
   `pwd` is the trimmed password encrypted with AES-128-CBC, key
   `VQZBJ6TD8M9WBUWT`, IV `joiwef08u23j341a` (UTF-8 bytes, PKCS7 padding),
   hex, upper-case (`server/storytel/passwordCrypt.ts`). The reply carries
   `accountInfo.jwt`; a 2xx without a jwt is a failure.
2. **Bookshelf** — `POST https://api.storytel.net/libraries/bookshelf`,
   `Authorization: Bearer <jwt>`, `Accept: */*`, **empty form body**
   (`application/x-www-form-urlencoded`, body `""`). A JSON body such as
   `{"items": []}` is rejected with 400. Reply:
   `{ items: { "<id>": { action, model } } }`; `model` has `id` (the
   consumableId), `title`, `state`, `stateUpdateTime`, `authors[].name`,
   `formats[]` with `type: 'abook' | 'ebook'`, `durationInMilliseconds`,
   `cover.url`, `position { position (ms), updatedTime }`. Keep models that
   have an `abook` format.
3. **Stream** — `GET https://api.storytel.net/assets/v2/consumables/<consumableId>/abook`,
   bearer, `Accept: */*`. Answers 302; the `Location` header is a signed MP3
   URL on the CDN with no Storytel token in it. Its lifetime is unknown:
   resolve a fresh URL on every book open and on playback errors (e.g. resuming
   after a long pause).
4. **Position** —
   - read: `GET https://api.storytel.net/bookmarks/positional?kidsMode=false&orderBy=updated&orderDirection=desc&consumableIds=<id>`,
     bearer; reply `{ bookmarks: [{ type, position (ms), updatedTime, ... }] }`,
     use the `type: 'abook'` entry.
   - write: `POST https://api.storytel.net/bookmarks/positional`, bearer, JSON
     `{ deviceId, action: 'player_paused', secondsSinceCreated: 0, position (ms), type: 'abook', kidsMode: false, consumableId }`.
     `deviceId` = a random upper-case UUID generated once and stored.

Token refresh: the jwt has an `exp` claim. Re-login with the stored
email + encrypted password when it is within 60 s of expiry, and once on a 401
(then retry the request once). Concurrent requests share one in-flight login.
A rejected re-login sends the app back to the login screen.

