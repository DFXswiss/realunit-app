# Referral programme and promo code

Implementation spec for this repository and `realunit.app`. The DFX API is
the decision authority. This app is a rendering layer.

## API contract (`api.dfx.swiss` / `dev.api.dfx.swiss`)

Authenticated routes use the existing Bearer session.

Live contract until `DFXswiss/backend` is writable (private):
[JonnyLuca/dfx-referral-api](https://github.com/JonnyLuca/dfx-referral-api)
(`GET`/`POST /v1/realunit/referral/*`, 70 REALU gate re-checked at credit,
quarterly cap 100, 3-month expiry, promo `redemptionCap` required, min-buy N
default 200, KYC + late bind, CORS for `realunit.app`, NestJS drop-in
`RealUnitReferralController`). Credit is evaluated on Aktionariat
**settlement** (whole REALU shares) and again when KYC Level 30 is
reached — not on `PUT /v1/realunit/buy/{id}/confirm` (payment
instructions only). On mount, `ReferralAuthHydrateInterceptor` rewrites `req.user.id` to the
JWT wallet address so a numeric RealUnitLegal user id cannot miss
holdings or prize send.

Authenticated calls hydrate mail, firstName, live
`kyc.level` and Aktionariat `confirmedDate` from `GET /v2/user`,
`GET /v2/kyc` (`x-kyc-code` from `kyc.hash`, same as this app),
`GET /v2/user/profile` and `GET /v1/realunit/registration` with the same
Bearer this app already sends. First purchase (if the settlement hook
is not yet wired) is the earliest inbound mint from `0x0` on
`GET /v1/realunit/account/{address}/history`, paginated with `first=200`
and `after=pageInfo.endCursor`. A successful authenticated GET may
credit from that mint, and also when KYC Level 30 arrives on a wallet
that already has a recorded first purchase. The server persists before
the 200 so a retry cannot double-pay. A failed live holding lookup
does not credit from a stale snapshot (TB Ziff. 2). GET summary and
POST invites then return `503 { "code": "UNAVAILABLE" }` so this app
retries instead of showing «not eligible». Live `GET /v1/realunit/account`
404 `Account not found` is a known-zero holding (tile stays hidden), not
unknown. Live swagger still
has no `/v1/realunit/referral` paths; public lookup currently returns
NestJS `Cannot GET`. The app maps that body (and `503 UNAVAILABLE`)
to the unavailable retry copy, not Nest internals. `onAccountMerge` /
`mergeWallets` is idempotent so a DFX `register/wallet` retry after
the dropped key is gone does not 404.

### `GET /v1/realunit/referral/summary`

```json
{
  "eligible": true,
  "termsAccepted": true,
  "minHolding": 70,
  "openCount": 1,
  "creditedCount": 2,
  "realuSum": 40,
  "chfSum": 55.2,
  "sharePriceLabel": "Aktienkurs",
  "sharePrice": 1.38
}
```

`eligible` is the dashboard/settings gate (KYC-verified, holding ≥ 70
REALU, not an employee). The app must not recompute
shareholder status or the 70 REALU holding locally.
A failed first load hides the tile; returning to the foreground or to
this route (pop back from Settings) retries the summary without a
loading flash so a later mount can open it, and a blip does not hide a
tile that is already shown. While that GET failed (unmounted Nest
`Cannot GET`, 503, timeout) the gate is also polled so the tile can
open without backgrounding the app. Polling runs only while this
route is current and the app is in the foreground. A 200 with
`eligible: false` is not polled.
`sharePrice` is the live Aktienkurs (`GET /v1/realunit/price` `chf`);
the total tile uses `realuSum * sharePrice` (running value). `chfSum`
is the sum of frozen payout CHF for history. `sharePriceLabel` is the
API token `Aktienkurs` (never «aktueller NAV»). The tile localizes it
(DE «Aktienkurs», EN «Share price»).

### `GET /v1/realunit/referral/terms`

```json
{
  "version": "2026-08-14",
  "markdown": "…",
  "markdownEn": "…"
}
```

The app renders this 1:1. Bundled `assets/legal/referral_terms_*.md` is only
a fallback when the call fails.

### `POST /v1/realunit/referral/terms/accept`

Body: `{ "accepted": true }`.

### `POST /v1/realunit/referral/invites`

Body: `{ "guestName": "Alice" }`. Empty, whitespace-only, or
format-character-only names are **400** (`guestName required`). The
server applies the same folds as the app (ZWSP/bidi stripped, Unicode
spaces collapsed, cap 80).

Response:

```json
{
  "code": "AB12CD",
  "url": "https://realunit.app/invite/AB12CD",
  "guestName": "Alice",
  "copyText": "Hey Alice, Björn lädt dich ein zu RealUnit: https://realunit.app/invite/AB12CD",
  "copyTextEn": "Hey Alice, Björn invites you to RealUnit: https://realunit.app/invite/AB12CD",
  "inviterName": "Björn"
}
```

The server generates code, URL, and share text. `inviterName` is the
Empfehler display name so a missing `copyText` still shares
«Hey Alice, Björn …» instead of «Hey Alice, RealUnit …». A later
`GET /v2/user/profile` firstName (or Kontozusammenführung) rewrites
open-invite `copyText` / `inviterName` so a first invite created
while the name was still the wallet address is not stuck as
«Hey Alice, tritt RealUnit bei». Wallet and numeric ids stay out of
the prize-mail greeting too; unsent mail waits for a real `mail`
address instead of sending to `0x…`. The prize confirmation is HTML at
send (`html` / `htmlEn` from the plaintext Anzahl / Datum / frozen CHF);
Überwachung `GET /admin/emails` stays the compact plaintext body. The app renders
`copyText` / `copyTextEn` 1:1 except `http://`, protocol-relative
`//realunit.app`, `www.realunit.app`, and scheme-less
`realunit.app/…` are folded onto
`https://realunit.app` (`dev.realunit.app` is left unchanged). A scheme-less or `//` invite/promo URL keeps
its path (`/promo/…` is not rewritten to `/invite/`). Empty EN falls
back to DE. Guest names are a single line (newlines/tabs become spaces)
and capped at 80 characters in the app. Submit writes the sanitized
name back into the field before POST. The name field autofocuses and
accepts given-name autofill.

### `GET /v1/realunit/referral/invites`

List of the current user's invites (bare array or `{ "invites": [...] }`).
Each row includes `copyText` / `copyTextEn` / `inviterName` so copy/share
on overview can name the Empfehler when the server omits share text.
The Empfehler list is **Open** or **Credited** only. Bound and Review
are folded to Open server-side so the Empfehler cannot see the invitee’s
registration or purchase progress (TB Ziff. 7). Admin relationships keep
the true status. `Deleted`, `Expired` and `Rejected` rows are omitted.
Counts of `Open` and `Credited` come from the summary. Open invites can be
copied and shared again (including a missing/blank
guestName as a nameless invite, and including a missing created
timestamp, and including a missing/blank status treated as Open).
If a backend still returns `Bound` or `Review`, the app treats them as
open so copy/share stay until Credited. An unknown non-terminal status
is treated as open so a new API spelling cannot hide copy/share;
credited/paid and deleted/expired/rejected are not open. Pending
Open/Bound/Review rows are **Deleted** after 90 days.
credited
names stay hidden — never registration, verification, or purchases of
the invited person. If this list call fails, the app still shows the
summary tiles (open/credited/total) and omits the copy/share rows on
first load; a later reload keeps previous rows. Retry is shown for a
list error even when those rows stay on screen, and when the summary
open count has no matching rows. List Retry is keyboard-focused when
no open-invite rows are on screen. Retry reloads only the list so a
summary outage cannot hide the counts. List Retry stays on the
list-error copy in the loading state so a second tap is ignored
(the rows are not replaced with only the loading spinner). List Retry is ignored while an
overview refresh is in flight; a slower list GET is discarded so it
cannot roll back counts after create.

### `POST /v1/realunit/referral/bind`

Body: `{ "code": "AB12CD" }`. Binds an invite or promo code.

```json
{
  "kind": "Promo",
  "campaignText": "…",
  "campaignTextEn": "…",
  "minBuyRealu": 200,
  "validUntil": "2026-09-07T00:00:00Z",
  "redemptionCap": 100
}
```

Invite binds return `inviterName` / `inviteeName` (same fields as lookup)
so a late Universal-Link bind can show the registration recognition
copy. Promo `campaignText` is shown 1:1 in a dialog.

`kind` is `Invite` or `Promo`. If `kind` is omitted, campaign/action text
without an inviter name is treated as promo so the confirmation dialog
still appears. The API rejects self-referral, double-bind, and promo+invite
stacking. Promo credit is only the first successful purchase of at least
`minBuyRealu` (default 200). A first buy below N creates no later claim.
`redemptionCap` is required — no unlimited option.

### `GET /v1/realunit/referral/code/:code` (public)

Landing payload for `realunit.app/invite/…` and `/promo/…`.
The server strips ZWSP/bidi, unwraps `/invite|promo/{code}` (including a
pasted `https://realunit.app/invite/…`), and upper-cases before lookup.
Empty after that fold is **400**. Bound, credited, rejected and
cap-spent codes are **410** `{ code: SPENT }` so the landing does not
greet with names after the invite is used. 90-day delete and disabled
promo are **410** `{ code: EXPIRED }`. Unknown is **404**. HTTP 400/404/409/410/422 mean the code is invalid or spent. 5xx, 401, 408
and 429 are transport failures — the registration field must not show
«invalid», and the landing shows «unavailable». Persist failure is
`503 { "code": "UNAVAILABLE" }` (retry, not expired). A NestJS 404 whose
message starts with `Cannot GET` / `Cannot POST` means the route is not
mounted yet: treat it as unavailable and keep a stashed code for retry.

### `GET /v1/realunit/referral/payouts`

Bare array or `{ "payouts": [...] }`. Each row carries `amount` (whole REALU;
a fractional API value is truncated, never rounded up),
`created`, and `chfValue` frozen at credit. The app never recomputes that
CHF amount from the live share
price. The API returns **Settled** rows only (Offerte Punkt 4) with public
fields (`id`, `amount`, `chfValue`, `created`, `kind`, `status`,
`txHash`). `userId` and `inviteId` stay off this list. Pending
and failed payouts stay out of history until the transfer
is confirmed. The server persists the broadcast `txHash` while the
row is still Pending and confirms that receipt on retry, so a
restart does not send a second 20 REALU. Non-settled rows are dropped if a payload includes them. Missing
status is treated as Settled (this list is Settled-only). Duplicate payout rows (same id or tx hash) are shown once, including
when history sync writes a payload that repeats an id or hash casing.
A settled row with neither id nor tx hash is dropped so it cannot
collide as `referral-payout-0`.
Frozen CHF
is stored as two decimals (`246.50`) when history
sync writes the row (amount is truncated, never rounded up). A locale-formatted
`chfValue` (`246,5`, `1'246.50`, `CHF 246.50`) still parses as a payout
row.

## App surfaces

- Dashboard card and settings entry only when `summary.eligible`.
  A second eligibility load while the summary GET is in flight is
  ignored, so a slower retry cannot hide the card after a later success.
  A timed-out eligibility GET is not retried, so a hung summary cannot
  occupy the dashboard for two 15s budgets.
  Gate and create-invite not-eligible screens offer Close
  (keyboard-focused). Gate, overview, and create-invite summary
  failures put keyboard focus on Retry, as does a terms-markdown
  load failure. A timed-out summary, create, or list GET shows the
  unavailable copy, not the TimeoutException string. Retry on a summary
  failure stays on the error copy in the loading state so a second tap
  is ignored (the screen is not replaced with a blank spinner). Create-invite
  Retry from needs-terms stays on that copy the same way.
- Terms page (markdown selectable, only http(s) links open in the in-app
  browser; root-relative `/…` paths open as `https://realunit.ch/…`;
  protocol-relative `//host/…` opens as https; mailto and other schemes stay in the markdown); the accepted-terms checkbox is shown only after the
  markdown has loaded; a later load (language change or Retry)
  discards an earlier in-flight result. A hung bundled TB asset is timed
  out after 5s so Retry is shown. Retry stays on the load-failed copy in
  the loading state so a second tap is ignored (the screen is not
  replaced with a blank spinner). create-invite button after checkbox
  «Ich habe die Teilnahmebedingungen gelesen und akzeptiert».
  Accepting terms opens the name-entry screen. A second accept while
  the POST is in flight is ignored. A failed accept
  focuses Create so it can be retried. A second accept stays on that
  error copy in the loading state so the page is not replaced with only
  the accepting spinner. After create, the
  personalised share text is shown under «Persönlicher Einladungslink»
  for copy and share. Share is keyboard-focused. A failed create
  POST focuses Create (the name field autofocus is cleared). A second
  create stays on that error copy in the loading state so the form is
  not replaced with only «Einladung wird erstellt…». Guest-name
  paste collapses Unicode spaces (nbsp, em/thin/ideographic) to ASCII
  spaces as they are typed and on submit so a messenger name stays one line. A second
  submit while create is in flight is ignored. Copy confirms with «Kopiert» for two seconds
  only after a successful clipboard write (announced only then,
  including the share text). A failed clipboard write keeps «Einladungslink
  kopieren» in the error state for two seconds and stays tappable. A
  second tap while the clipboard write is in flight is ignored — Copy
  is in the loading state and not tappable. A hung
  write is treated as a failure after two seconds so copy is not stuck.
  A second tap copies again and restarts the
  two-second timer. A new share text clears the Kopiert state and does
  not confirm or error a write that started on a previous invite. Share uses that label as the share-sheet
  title and email subject, and anchors the iOS/Mac popover on the share
  button (screen origin if the button has no size). A failed share
  (throw or unavailable) keeps «Einladungslink versenden» in the error
  state for two seconds and stays tappable. A second tap while the
  sheet is open is ignored. If the share sheet never returns, resuming
  the app clears loading so Versenden is tappable again. A new share text while the sheet is open
  does not show that error on the new invite. Dismissing the sheet does not. Open invite rows are
  keyed by invite id and code so two nameless rows with a missing id
  cannot share a key, and copy/share state cannot jump to another guest.
- Overview: open / credited counts, total REALU (truncated to a whole
  token, never rounded up), CHF, label «Aktienkurs»
  (empty or «NAV» API labels fall back to the localized Aktienkurs copy).
  Count tiles are announced as «3 Offen» / «2 Gutgeschrieben»; the total
  tile is one name (REALU, frozen CHF, Aktienkurs).
  Open invites show the personalised share text (API copyText 1:1,
  otherwise the localised template) and can be copied and shared again,
  including when the guest name is blank («Deine Einladung», share text
  without «Hey ,»);
  credited names stay hidden. Copy and share behave as after create.
  With no open-invite rows and no list error, Create is keyboard-focused.
  A second overview refresh while the summary GET is in flight is ignored,
  so a slower failure after create cannot hide the tiles.
  A second tap while create is already open is ignored. The create-route
  lock is released when that screen pops, and overview refresh after
  create is not awaited, so a hung summary GET cannot block Create.
  The overview title and Settings → Legal documents (last tile) open
  the Teilnahmebedingungen read-only (GET /terms 1:1, then bundled
  14.08) so Ziff. 2–11 stay reachable after the checkbox.
- Registration: dedicated optional step (skip allowed) with the same
  field for invite and promo. A pasted `realunit.app/invite|promo/…`
  URL (or the landing copy button) is reduced to the code before lookup
  and bind, including a query-only origin URL (`https://realunit.app?invite=`),
  a hash-only path (`/invite#CODE`, `invite#CODE`, `realunit-wallet://invite#CODE`,
  `https://realunit.app/invite#CODE`, `https://realunit.app#CODE`,
  `realunit.app#CODE`), including App Links that carry the code only in
  the fragment,
  a nested landing URL in the path (`/invite/https://realunit.app/invite/{code}`,
  `intent://`, or `realunit-wallet://`),
  `?code=` / `?invite=` wrapping a landing URL (including an App Link
  `https://realunit.app/invite?code=https://realunit.app/invite/{code}`),
  Facebook `l.php?u=` / Google `url?q=` wrappers around a landing URL,
  WhatsApp/Telegram/SMS/mailto/Messenger/Threema/Signal/Viber/LINE
  share-sheet schemes (`whatsapp://`, `tg://`, `sms:`, `smsto:`,
  `mailto:`, `fb-messenger://`, `threema://`, `sgnl://`, `viber://`,
  `line://`, `wa.me`, `t.me/share`) with a percent-encoded landing URL in
  `text` / `body` / `url` / `link` / the LINE path, including share copy
  around the URL,
  Chrome Android `intent://send?text=…#Intent;scheme=whatsapp;end` and
  `#Intent;S.text=` / `S.browser_fallback_url=` extras,
  Outlook Safe Links `url=`, Proofpoint URL Defense v2 (`-3A` / `_`)
  and v3 (`__/https://realunit.app/…__`),
  key-less wrappers (`href.li/?https://realunit.app/invite/{code}`),
  path-nested landing URLs (`https://example.com/r/https://realunit.app/invite/{code}`,
  Yahoo `RU=https://realunit.app/invite/{code}`),
  and AMP/CDN paths (`https://www.google.com/amp/s/realunit.app/invite/{code}`),
  `app-argument` and ads/Play `utm_content` /
  `referrer` wrapping `invite=` or a landing URL, also when that URL
  is embedded in a share message without a path code, including Chrome
  `intent://…/invite?code=` and android-app / ios-app
  `…/invite?code=` alternate links. Format characters that messengers inject around a copied
  code or URL (zero-width, LRM/RLM, bidi) are stripped so lookup is not
  sent a tainted token. Extracted codes are uppercased, stripped of
  messenger zero-width/fullwidth characters and trailing sentence punct
  (`!`, `?`, `/`, …), and capped at 32 like the API `sanitizeReferralCode`
  fold, including a nested `invite|promo/{code}` inside a pasted token,
  as are typographic quotes wrapping a copied URL
  (`“…”`, `«…»`), wrapping parentheses, and a trailing `)` from a
  markdown link, a trailing `"` / `'` from an HTML `href`, or HTML
  entities (`&quot;…&quot;`, `https&#58;//`, `&#x2f;`, `&colon;`, `&sol;`),
  JSON-escaped slashes (`https:\\/\\/…`) and `\u003a` / `\u002f`,
  fullwidth `：` / `／` and fullwidth digits/letters from a mobile keyboard,
  Word/Pages fraction slash `⁄`, division slash `∕`, and ratio colon `∶`,
  CJK ideographic full stop `。` as the domain dot (`realunit。app`),
  Word/PDF typesetting spaces (nbsp, thin space, narrow nbsp) in a URL
  or code,
  and line breaks that email clients insert
  in a wrapped URL (`/invite/\nCODE`) or spaces inserted after `/` or
  `://` (`https://realunit.app/ invite/CODE`), or `>` quote prefixes on
  wrapped reply lines, or a backslash before the line break
  (`/invite/\\\nCODE`), a hyphen before the line break from PDF wrapping
  (`/in-\\nvite/CODE`) or a Unicode hyphen (`/in‐\\nvite/CODE`),
  a quoted-printable soft break (`/inv=\\nite/CODE`)
  or quoted-printable URL hex (`https=3A=2F=2Frealunit.app=2Finvite=2FCODE`),
  or an RFC 2047 encoded-word from an email subject
  (`=?UTF-8?Q?https=3A=2F=2F…?=`, `=?UTF-8?B?…?=`),
  markdown/WhatsApp emphasis (`*url*`, `_url_`),
  or inline-code backticks (`` `url` ``) and fenced triple-backtick
  blocks, or table pipes (`| url |`). A trailing slash or sentence
  punctuation on a pasted code (`AB12CD/`, `AB12CD.`) is dropped.
  A fullwidth path segment (`/invite/ＡＢ１２ＣＤ`) or App Link query
  code is folded onto ASCII before lookup. The landing Pages Function
  applies the same fold to the HTML bytes Safari snapshots for the
  Smart App Banner, including ads/Play `utm_content` / `referrer`
  wrapping `invite=` or a landing URL (including `realunit.app/invite/…`
  without a scheme) on a bare `/invite` path, and Facebook `u=` / Google
  `q=` / Outlook `url=` / email `link=` wrapping a landing URL (`u=hello` is not a code;
  a campaign name in `utm_content` does not hide a later wrapper key;
  a tracking URL that only mentions `realunit.app` does not hide them either;
  paste and App Links use the same try-each keys;
  a foreign `https://` URL is not a code; Proofpoint URL Defense and
  Outlook Safe Links wrapping a RealUnit landing are unwrapped; short
  `ios-app://` alternate links too). The registration field strips those characters as
  they are entered, including ASCII/Unicode spaces and the paste control (a clipboard of only
  format characters is ignored, as is a RealUnit invite/promo URL with
  no code, or a clipboard read failure). An empty field auto-pastes a
  landing clipboard code after the deeplink stash (iOS has no Play
  referrer); a typed or stashed code is not overwritten. A second paste while the
  clipboard read is in flight is ignored — the paste control is not
  tappable until that read finishes. A hung clipboard read is
  ignored after two seconds so paste and Next are not stuck. Paste of the same code joins
  the in-flight lookup. Paste after Skip (field locked, or an in-flight
  clipboard read that finishes after Überspringen) is discarded. Next
  awaits that in-flight paste before commitLookup. The same strip runs on the Play install referrer
  before `invite=` / `promo=` / `code=` keys are read (an empty or foreign
  `invite=` does not hide a later key), including fullwidth / CJK
  / HTML folds so `realunit。app` still matches; a double-encoded
  referrer (`invite%253D…`) is decoded again, and `utm_content`
  or a nested `referrer=` / Facebook `u=` / Google `q=` / Outlook `url=` /
  email `link=` wrapping `invite=` or a landing URL is unwrapped
  (a campaign name in `utm_content` does not hide a later wrapper key;
  a tracking URL that only mentions `realunit.app` does not hide them either),
  as is a Facebook `l.php?u=` / Google `url?q=` wrapper as the whole
  referrer, an Outlook Safe Links `url=`, a Proofpoint URL Defense
  v2/v3 encoded landing URL, or a path-nested landing URL (Yahoo `RU=https://…`). A hung
  Play Install Referrer read is timed out after 4s so app setup cannot
  stall; the consumed flag is left unset. While lookup is in flight the field shows «Code wird»
  geprüft…» and hides the previous result. A later lookup of the same
  code (Done, paste, Retry) discards an earlier in-flight result so a
  slower 4xx cannot overwrite a later 200. Next/Skip lock the field
  until they finish and cancel a pending lookup debounce (Next still
  awaits commitLookup and joins an in-flight lookup of the same code,
  or skips a second GET when that code already has a terminal result;
  Skip does not put Next into loading). Skip stays tappable while Next
  is awaiting lookup so a hung GET cannot trap the user; Skip then
  discards that in-flight lookup and does not let Next also advance.
  A 5xx /
  401 / 408 / 429 lookup or an unmounted NestJS route is not «invalid»:
  the field keeps the code, shows the unavailable copy, and offers
  Retry (secondary, so Next stays the primary action). A hung lookup
  GET is unavailable after 15s so Next is not stuck. Retry stays on the
  unavailable copy in the loading state so a second tap is ignored
  (the field is not replaced with only the checking spinner). Done still looks up a newly typed
  code while a previous lookup is in flight. Skip drops a typed code immediately and leaves a
  deeplink stash in place. Skip also discards an in-flight paste or
  lookup so a late clipboard write or GET cannot stash after
  Überspringen. After lookup the invite recognition copy or
  the promo campaign dialog is shown. The campaign dialog stays until
  Close — a barrier tap does not dismiss it; Close is keyboard-focused.
  A 4xx bind (stacking, self-referral,
  spent) shows the matching copy once (spent: «Code bereits eingelöst»;
  self-referral / already-bound / already-registered have their own
  sentence; unknown/expired stay «Link ungültig oder abgelaufen»). Close
  is focused, not barrier-dismissible.
  If the navigator is not attached yet (dashboard boot bind), the promo,
  invalid, or unavailable dialog is shown on the next frame instead of
  dropped.
  A second bind while the POST is in flight only stashes. A retryable
  bind failure does not overwrite a newer stashed code. A retryable bind
  (Dart timeout, transport error, 5xx, 401, 408, 429, 504, or an unmounted
  NestJS route) restashes the code and shows the unavailable copy once
  (Retry focused, Close beside it, not barrier-dismissible). Retry stays
  on that dialog in the loading state and binds the stash again without
  waiting for the next dashboard landing; Close is not tappable while
  that POST is in flight. After the POST
  finishes, a leftover stash is bound next.
- History: referral payouts with amount, date, frozen CHF, announced as
  one name (title, date, frozen CHF, +20 REALU). Dashboard prize rows
  use the same name. A frozen CHF string with a decimal comma
  (`246,5`), Swiss thousands apostrophes (`1'246.50`), or a `CHF`
  prefix formats as two decimals (`246.50`).
- Deeplinks: `realunit-wallet://invite|promo/{code}` and
  `https://realunit.app/invite|promo/{code}`. Release Universal Links
  associate `realunit.app` and `www.realunit.app` only; Debug entitlements
  add `applinks:dev.realunit.app?mode=developer` (and the same query on
  apex/www) so Universal Links can be tested while production AASA is
  still 404. iOS Profile/Release use App Store signing without
  `?mode=developer`.
  Invite bind is silent on
  success; promo bind shows the campaign dialog (Close only,
  keyboard-focused), including when bind returns before the navigator
  has a context. Registration auto-pastes a copied landing code when the
  field is empty; a deeplink stash wins over the clipboard.

## Website

`realunit.app/invite/{code}` and `/promo/{code}` look up the public code
route, greet by name or show the promo action text, open the app via the
custom scheme, and show App Store / Play Store badges (the matching store leads on iOS/Android).
A nested invite
URL in the path or query is unwrapped to the code, including a
path-nested landing URL on a messenger redirect and an AMP/CDN path
with `realunit.app` as a segment. `/invite#CODE` is
the hash fallback when the path has no segment and the query has no
code. Path and query codes
drop ASCII/Unicode spaces the same way as the registration field. Ads/Play
`utm_content` or `referrer` wrapping `invite=` / a landing URL is
unwrapped when the path has no code, as is Facebook `u=` / Google `q=` /
Outlook `url=` / email `link=`; a bare campaign name is not, a campaign
name in `utm_content` does not hide a later wrapper key, an empty or
foreign `code=` does not hide a later `invite=` / `promo=`, and a
foreign `https://` URL is not a code. Proofpoint URL Defense, Outlook
Safe Links, and short `ios-app://` alternate links wrapping a RealUnit
landing are unwrapped. The landing shows the
code with copy (tap / long-press) during lookup so iOS users can enter
it during registration after a fresh install. `format-detection` is
`telephone=no, date=no` so Safari does not turn that code or the
Aktionstext date into a phone or calendar link. `#ok-code` and `#ok-body`
also set `x-apple-data-detectors="false"` because lookup JS writes those
strings after load. Desktop can copy the
canonical link while lookup runs; the in-app CTA is mobile-only and
stays hidden until lookup finishes. iOS Smart App Banner `app-argument`,
`og:url`, `rel=canonical`, `twitter:url`, `og:title`, `twitter:title`, `og:description`,
`twitter:description`, `og:image:alt`, `twitter:image:alt`, `og:locale`, `og:site_name`, Play install
referrer, android-app / ios-app
alternate links, Facebook App Links (`al:ios:url` / `al:android:url`
are `realunit-wallet://…`; `al:android:class` is
`swiss.realunit.app.MainActivity`; `al:web:url` is the HTTPS landing), and Twitter
App Card `twitter:app:url:iphone` / `twitter:app:url:ipad` /
`twitter:app:url:googleplay` (same custom scheme; `twitter:app:country` is CH)
are injected into the HTML bytes from the request URL so
Safari, Play, WhatsApp, X, and share crawlers can snapshot them before JS. `?lang=en`
sets English title/description/alt and `og:locale=en_GB`.
(`/js/invite-banner.js` in `<head>` is the CSP-safe fallback because
Cloudflare Pages CSP blocks inline `<script>`). Invalid lookup strips those
handoff attributes. `www.realunit.app/invite|promo` is HTTP 200 (not a 301 to the apex) so
Universal Links and the Smart App Banner keep the associated host.
An App Store / Play / CTA tap copies the code (user gesture) so an iOS
badge install can still be pasted at registration. Copy confirmation
is announced only after a successful copy (a failed clipboard write
keeps «Code kopieren» / «Link kopieren» in the error style for two
seconds, and the code control is status red). A second tap while
writeText is in flight is ignored — Code and Link kopieren are each
disabled (`aria-busy`) with their own in-flight guard, and the code
control is `aria-disabled` so a tap on the code does not stack another
write. A hung writeText falls back to execCommand
after two seconds so copy is not stuck. Confirmation is via the existing status hint
(not aria-live on the button); the code control's name
becomes «Kopiert {code}». The document title, Open Graph, Twitter
tags, and the standard description meta follow loading, invite/promo,
invalid, and unavailable — including a path with no code, which is
invalid and offers «Zur Startseite» to the apex
(`https://realunit.app/`; `/` on local preview), with keyboard focus
on that link (with a visible focus ring). `og:locale` is `de_CH` or `en_GB`; `og:locale:alternate` is
the other. Invalid heading and body use status red; `theme-color`
matches (`#E02523` invalid, `#1988C6` otherwise). Unavailable puts
keyboard focus on Retry (visible ring) and offers «Zur Startseite» beside it
(same apex homepage URL). Invalid and unavailable copy is a live
region; Retry and Zur Startseite sit outside it. Retry looks up again without a full page
reload; Retry stays on the unavailable copy, disabled (`aria-busy`), so
a second tap is ignored and the section is not replaced with only the
checking hint. A hung
lookup is marked unavailable when the 15s budget elapses even if fetch
abort is a no-op, so Retry is not stuck. If the previous control is hidden, focus moves to the
checking hint. Retry is described by the unavailable body. When the
retry succeeds, focus moves to the result heading; if lookup is still
unavailable, focus returns to Retry. Retry and Zur Startseite keep
focus if they already have it when the same state is shown again.
On first Android launch the
app reads the Play referrer once and stashes the code for post-unlock
bind. The landing also tells iOS users to tap the link again (Play
Install Referrer covers Android).

## Out of this repository

The HTTP contract and Nest drop-in live in
[JonnyLuca/dfx-referral-api](https://github.com/JonnyLuca/dfx-referral-api)
(`nest/*`, `openapi/referral.json`). Copy that module into private
`DFXswiss/backend` next to `RealUnitLegalController`. Live
`api.dfx.swiss` has no `/v1/realunit/referral/*` until that mount
(NestJS `Cannot GET`). Prize-wallet keys (`PRIZE_WALLET_KEY`,
`ETH_RPC_URL`) and the Play app-signing SHA256 are mount/release
config, not app code.
