# Listening History — LMS Plugin

## Project Overview
A plugin for Lyrion Music Server (LMS) that records a play history across EVERY player, for
local library files, streaming services (Qobuz, Tidal, Deezer, Spotify via Spotty, anything
else with a protocol handler). A played album is ONE entry, not one per track; a lone track is
a track entry. Radio stations are NOT recorded (since 1.0.15); Radio Paradise, which names each
song, is recorded song by song. Every entry plays again,
streaming included. Material home shelf of the latest 50 entries; app menu to look back by date,
artist, album, service, player, or search by text, date or date range; every list sortable. Library entries
follow the library: after a rescan, retag or move they find their album again and take its current names
(since 1.0.16 / 1.0.17). Stores its own SQLite DB. Targets LMS 9.x, Material
Skin preferred. Built 2026-09-18 from Simon's brief, in the shape of Listen Later / LBF / PFR.

## Branches and releasing
- **1.0.4 is the first release**: merged to `main` and tagged `v1.0.4` on 2026-09-19. **1.0.5** (year search,
  By date years) released and tagged `v1.0.5` the same day. **1.0.7** (By release by type, Qobuz `epmini`)
  released and tagged `v1.0.7` the same day. **1.0.14** (restart carry-on, service titles, track rows) released
  2026-09-21: merge `765f0d0`, tag `v1.0.14`.
  **1.0.18** (1.0.15–1.0.18: pause, Radio Paradise per song, stations dropped, library entries found again
  and following the library, the post-rescan check) released 2026-09-24, tag `v1.0.18`.
- Work happens on `dev`. `dev` mirrors `main` except for ONE line, the `repo.xml` `<url>`:
  - main: `https://simonarnold002.github.io/LMS-Listening-History/ListeningHistory.zip` (Pages)
  - dev: `https://raw.githubusercontent.com/SimonArnold002/LMS-Listening-History/dev/ListeningHistory.zip`
  - Reconcile that line on every merge; never blind-merge it. `<sha>`, `<icon>` and `<link>` are the same on both.
- At a merge to `main`: ONE `CHANGELOG.md` entry for the version released, covering everything since the
  last `main` commit; regenerate `README.html` / `index.html`; tag `v<version>` on the main merge commit.

## Review Ledger — READ THIS BEFORE REPORTING ANY FINDING

The workspace `CLAUDE.md` one level up holds the three fleet-wide gates. This ledger holds what
is settled for THIS plugin. Review and fix happen in separate sessions, so a decision that is not
written here will be re-reported as a finding.

### DECLINED / SETTLED INDEX — GREP THIS FIRST, BY SYMBOL

```
grep -n "_record\|album_key" CLAUDE.md
```

| symbol / subject | verdict | find it with |
|---|---|---|
| album vs track rule, `Tracker::_record`, promote on 2nd track | **DECIDED by Simon 2026-09-18**: 2+ back-to-back tracks = album | `2+ TRACKS = AN ALBUM` |
| `played_threshold` 90%, 60s fallback | **DECIDED by Simon 2026-09-18**: Listen Later's rule | `THE 90% RULE` |
| Radio Paradise station breaks / DJ talk (`_rpAnnouncement`) | **DECIDED by Simon 2026-09-24**: not recorded, by RP's own rule | `RP BREAKS ARE NOT MUSIC` |
| radio: stations NOT recorded, `record_radio` pref REMOVED; Radio Paradise recorded per song as tracks | **CHANGED by Simon 2026-09-23** (was a station row, 2026-09-18) | `RADIO IS NOT RECORDED` |
| pause: `Tracker::_unpause` stops the session clock; a paused stream's re-stream (`newsong`, same url, `startOffset`) keeps its mark only if it starts where it paused (`RESUME_SLACK`), crediting `startOffset - base`; a station title change is ignored only while it has no length | **FIXED 2026-09-23** (1.0.15), reported by Simon | `A PAUSE IS NOT A GAP` |
| track length re-read at every `_markTick`, `Sources::trackDuration` handler-first for a remote track; a service track with no length waits, is not counted at 60s | **FIXED 2026-09-23** (1.0.15), reported by Simon | `THE LENGTH IS READ AT EVERY CHECK` |
| shuffle / random order within one album | works the same as track order: `album_key` + distinct url, order never read (pinned 2026-09-23) | `2+ TRACKS = AN ALBUM` |
| By service menu, sort row `_sortRow`/`sortEntries`, date search `parseDateSearch` | **DECIDED by Simon 2026-09-18** (0.1.3) | `DATES, SERVICE MENU, SORT` |
| By release `_releases`/`_releaseList`; type = `Sources::releaseType` (library live, Qobuz stored via `fetchReleaseType`, else ALBUM) | **DECIDED by Simon 2026-09-19** | `BY RELEASE, BROKEN DOWN LIKE LMS` |
| year search `parseYearSearch` = a "Played in" row ABOVE the text matches; By date years `_dates`/`_months` + "All of" | **DECIDED by Simon 2026-09-19** | `A YEAR IS ALSO A NAME` |
| home shelf title `PLUGIN_LH`, not "Recently played" | **DECIDED by Simon 2026-09-18**: avoids confusion with Material's own Recently Played | `SHELF TITLE` |
| `Sources::albumKey` name fallback, `primaryArtist` | deliberate: first credit only | `THE NAME KEY USES THE FIRST CREDIT` |
| Bandcamp album replay = recorded tracks | deliberate, no album page url at play time | `BANDCAMP REPLAYS WHAT WAS HEARD` |
| replay code copied from LL, not shared | deliberate | `COPIED, NOT SHARED` |
| `ORDER BY … id DESC` tie-break untestable | known; index gives the same order | `THE TIE-BREAK CANNOT BE PINNED` |
| `LIST_CAP` 1000 per browse list | deliberate, and says so on the list | `LIST_CAP` |
| service badge `Sources::extid` / row `extid`; NO service name in `entryRow` line2 | **DECIDED by Simon 2026-09-18** (1.0.1) | `THE SERVICE IS A BADGE` |
| `entryRow` text: Album over Artist (a track: one line "Title by Artist from Album", 1.0.4), no count / player / time on the row; `_when`, `PLUGIN_LH_TRACKS_OF`, `PLUGIN_LH_FROM` removed | **DECIDED by Simon 2026-09-19** | `A ROW READS LIKE A RELEASE` |
| `_titled`: web-skin `name` = "Album by Artist", Material gets `line1` over `line2` | **DECIDED by Simon 2026-09-19** (1.0.2 review) | `THE WEB SKINS KEEP THE ARTIST IN THE NAME` |
| `_trackName`: a single-track row: web skins "Title by Artist from Album" (as LMS names a favourite track); Material "Title from Album" over the artist | **DECIDED by Simon 2026-09-19, CHANGED by Simon 2026-09-21** (artist to line 2) | `A SINGLE TRACK IS NAMED LIKE LMS NAMES ONE` |
| restart carry-on `Tracker::_restore`, `resumed_url` + `resumed_title` (1.0.15): first newsong per player after startup rebuilds the session from its last entry (within `session_gap_min`); the first counted play is dropped if it is the last play's url (and title, only where `Sources::sharesUrl`: Radio Paradise) | **ASKED FOR by Simon 2026-09-21**; carry-on VERIFIED LIVE 1.0.11, offset path unexercised live (Simon 2026-09-23: local files DO resume in place in some circumstances) | `A RESTART IS NOT A NEW LISTEN` |
| service track title `Sources::describe`: handler `$meta->{title}` BEFORE `$track->title`, except a plain web track (`http`/`https`: LMS's HTTP handler splits the row name); radio names from `$track->title` | **FIXED 2026-09-21**, asked for by Simon | `THE SERVICE NAMES ITS TRACK` |
| `Sources::_isSplit` lexical `$a` (shadows `sort`'s) | **DECLINED by Simon 2026-09-21**: harmless, rename only in passing | `§C` round 2026-09-21 #6 |
| back-fill from LMS's own play data (`tracks_persistent` lastplayed/playcount) | **DECLINED by Simon 2026-09-18** | `NO BACK-FILL FROM LMS` |
| app/shelf logo `ListeningHistoryIcon` = Google `music_history`, not Material's `history` glyph | **KEPT by Simon 2026-09-18** | `THE LOGO STAYS` |
| "More by this artist" context entry | DROPPED at build; By artist covers it | `MORE BY THIS ARTIST` |
| stale library `ref.album_id` replays the WRONG album (`resolveTracks`, `_libraryTracks`, `_libraryReleaseType`) | **DISPROVEN 2026-09-23** — §A3: `albums.id` is AUTOINCREMENT, never reused | `AN ALBUM ID IS NEVER REUSED` |
| a stale library album found again: `Sources::libraryAlbum`, `DB::relinkLibrary`, ref `album_mbid` / `track_mbid` / `album_url` | **DECIDED by Simon 2026-09-24**: "follow what LMS does" — row id, album MBID, files, track MBID, LMS's album url; VERIFIED LIVE on 1.0.16 (retag + full clear and rescan) | `FOUND AGAIN THE WAY LMS FINDS IT` |
| history follows the library: `Sources::_nameChanges` (album / artist / title / year), the rescan sweep `startSweep` / `sweepTick` / `DB::libraryAfter`, `Plugin::_onRescanDone` | **DECIDED by Simon 2026-09-24** (after the live retag test): names follow the library, swept after every rescan; VERIFIED LIVE on 1.0.17 | `HISTORY FOLLOWS THE LIBRARY` |
| `releaseType` searching for a stale album on a By release render | **FIXED 2026-09-24** (review): a list render reads the row id only; the sweep / an open finds it again | `A LIST RENDER DOES NOT SEARCH` |
| a track MBID names one album (`_byTrackMbid`) | **DISPROVEN 2026-09-24** — §A3: it is the RECORDING id, it repeats on compilations | `A TRACK MBID IS A RECORDING` |
| Tidal/Deezer/Spotify album nodes, live Material rendering, the 1.0.15 pause / length / RP paths | **UNVERIFIED LIVE** — §B | `UNVERIFIED LIVE` |

**Two standing rules** (fleet): name the WRITER, not just the branch; a comment is not the
contract.

### HOW TO LOG A VERDICT
Every new decision goes in §A2 (declined / by design), §B (open / accepted) or §C (closed) as a
bullet whose FIRST LINE names the symbols a future review would grep for, then the verdict, the
date and who decided. Add a row to the index in the same edit. State the reason as a fact that
can be DISPROVEN. Closing a round is not a suppression.

### A. NOT FINDINGS — deliberate, fleet-wide
- Stale zip / `repo.xml <sha>` on `dev`: recomputed at build time with the version bump.
- `CHANGELOG.md` / `README` are written at the MERGE TO MAIN.
- Uncommitted = under review; unpushed = review not passed. Never prompt to commit or push.

### A2. NOT FINDINGS — Listening History specific

- **2+ TRACKS = AN ALBUM — Simon, 2026-09-18.** `Tracker::_record` promotes a track entry to kind
  `album` on the SECOND track from the same `album_key`, heard back to back on one player. Not a
  percentage of the album. ORDER IS NEVER READ: an album played in shuffle joins exactly as in track
  order (same `album_key`, a url not yet heard). Checked 2026-09-23 at Simon's request; guard
  `t_tracker.pl` "shuffle". (The row used to say "N of M tracks"; since 2026-09-19 it shows only
  Album over Artist — see `A ROW READS LIKE A RELEASE`. The counts are still stored.) Offered alternatives (a % threshold; "queue matches the album")
  were declined.
- **THE 90% RULE — Simon, 2026-09-18.** A track counts at `played_threshold`% (default 90) of its
  duration, or `FALLBACK_SECS` (60) with no duration, re-checked against `songElapsedSeconds`, and
  cancelled by the next `newsong`. Copied from LL `Played.pm`. The scrobble "50% or 4 min" rule
  was offered and declined. 1.0.15: the 60s fallback is for a track that has NO length (a local
  file with none, a stream timed as a station). A SERVICE track (never a station) with no length yet
  keeps waiting for one instead — see `THE LENGTH IS READ AT EVERY CHECK`.
- **RADIO IS NOT RECORDED — CHANGED by Simon, 2026-09-23** (was RADIO IS A STATION ROW, 2026-09-18).
  *"I thought we included radio streams they dont show up, but I am happy for them not to at all. Radio
  Paradise being the exception as that plays individual tracks not a continuous stream and provides
  metadata for finding them again later."* 1.0.15: `_record` writes nothing for `is_station`; it still sets
  a `station` session (ends the album session; later title changes on the url are ignored). The
  `record_radio` pref, its settings row and `PLUGIN_LH_RADIO*` / `PLUGIN_LH_ENABLED` strings are REMOVED.
  A stream with no length is still TIMED as a station for 60s, because it may learn a length (a podcast,
  RP's first song). Why stations never showed was not established (never checked live) and is moot.
  Old `station` rows in a db still render and replay (Browse unchanged). Radio Paradise is not a station:
  every song has a length, so it is recorded song by song as TRACK entries, source `radioparadise`.
  ONLY its INTERACTIVE streams (the RP plugin's `radioparadise://` urls: a service scheme, per-song length,
  `isRepeatingStream`). RP's REGULAR streams are plain http with no length or timeline, so `isStation` makes
  them stations and they are NOT recorded, by design (Simon 2026-09-24; README + CHANGELOG say so).
- **RP BREAKS ARE NOT MUSIC — `Sources::_rpAnnouncement`, `describe` — Simon, 2026-09-24.** Seen live: an
  entry "Listener-supported" by "Commercial-free" (RP's station break, cover 105.jpg, `radioparadise://4.flac`).
  Station breaks and DJ talk are blocks WITH a length, so they passed as songs. `describe` now returns
  `(undef, 'a Radio Paradise announcement')` for source `radioparadise` when RP's OWN announcement rule
  (RadioParadise `API.pm`, the HEAD check before play) matches: the block url contains `/dj/` (RP sets it as
  the song's `streamUrl`, ProtocolHandler L122), or title `/listener-?supported/i`, or artist
  `/commercial-?free/i`. The regexes are RP's, verbatim: "Listener supported" with a SPACE does not match,
  as in RP. `_record` returns before touching the session, so the songs either side are recorded as usual.
  Only RP: a service track carrying the same words is recorded. UNVERIFIED LIVE: the `/dj/` path (no DJ block
  seen yet). The one entry already recorded is left for Simon to remove (… → Remove from history).
  Guard: `t_tracker.pl` "RP breaks" + its CONTROL; 3 mutations (check off, `/dj/` off, RP scope off) each red.
  Guard: `t_tracker.pl` radio block (not recorded, timed once, ends the album session), `t_browse.pl`
  settings (pref gone).
- **SHELF TITLE — Simon, 2026-09-18.** The Material home shelf (`HomeExtras`, `LHHome`) is titled
  `PLUGIN_LH` ("Listening History"). Material has its own Recently Played section, so a shelf
  called that would be confused with it. The app menu's "Recently played" tile is inside the
  plugin and keeps its name.
- **DATES, SERVICE MENU, SORT — Simon, 2026-09-18 (0.1.3).**
  - ~~Every row's line2 ends with the full date and time~~ — SUPERSEDED 2026-09-19: the row shows no
    time at all (`A ROW READS LIKE A RELEASE`); `_when` is gone. The sort row still orders by date.
  - Filter by service is a separate **By service** menu (`_services`/`_service`,
    `DB::services`/`forSource`), NOT a filter row. Simon chose it over an options row and over a
    sort-only design.
  - A **Sorted by** row tops every entry list (`_sortRow`), cycling date → artist A–Z → album
    A–Z. It is stored in pref `sort` and stepped from the LIVE pref (Pitchfork's
    `_yearSortToggle` mechanics). `sortEntries` always tie-breaks newest-first then id, and a
    blank name sorts last.
  - The home shelf is never re-sorted and has no sort row (it must stay flat).
  - Service is not a sort mode: the By service menu covers it.
  - Date search (`parseDateSearch`) is a single date OR a range, **day-first** (UK). There is no
    month-first guessing: `09/18/2026` is text, not a date.
- **BY RELEASE, BROKEN DOWN LIKE LMS (`_releases`, `_releaseList`, `Sources::releaseType`) — Simon, 2026-09-19.**
  *"This is purely how to group the tracks played together as we see them in a view, so a single with two
  tracks shows as how the single would as one entry, same for EP's, we just need By release instead of By
  album and then break them down like LMS."* So:
  - GROUPING IS UNCHANGED. Tracks group by their RELEASE (`albumKey`: library album id, service album id,
    else name + first credit), whatever its type: a two-track single or an EP played through is ONE entry,
    shown like any release. No type label on any row (`A ROW READS LIKE A RELEASE` stands).
  - **By album → By release** (`PLUGIN_LH_BY_RELEASE`). It opens one row per TYPE with its count —
    Albums / EPs / Singles / Compilations … — each opening its release tiles (the old By album tiles).
    Simon chose type rows over in-list headers (headers need Material's feature flags passed down; rows
    work on every skin).
  - Names: LMS's own `Slim::Schema::Album::releaseTypeName` (8.4+), else the same string lookup copied.
    Order: Material's `RELEASE_TYPES` (ALBUM EP BOXSET BESTOF COMPILATION SINGLE APPEARANCE), others after A–Z.
  - A release's type is its MOST RECENT play's (`DB::albums` `last_id`), the same entry that gives the badge.
  - **Library**: read LIVE from `albums.release_type` by `ref.album_id` — every past entry has one, and a
    retag + rescan moves it. Material's rule: a compilation whose type is ALBUM (or none) is COMPILATION.
  - **Qobuz**: its album object states `release_type` (album / ep / single); the cached track meta does
    NOT (checked upstream `precacheTrack`). `Tracker` calls `Sources::fetchReleaseType` once per album per
    server run after recording, and `DB::setReleaseType` MERGES it into the entry's ref. `describe` carries
    a type already known this run, because an album promotion rewrites the ref from the second track.
    Qobuz entries recorded before 1.0.6 have no type and sit under Albums until played again.
  - **Qobuz spells an EP `epmini`** (its `album` / `single` match LMS). 1.0.6 stored it raw and By release
    showed an "Epmini (1)" row on the rig (Simon, 2026-09-19 — VERIFIED LIVE that the Qobuz lookup runs).
    `Sources::%TYPE_ALIAS` maps EPMINI → EP on EVERY read, so an entry already stored as EPMINI reads as an
    EP with no data change. Anti-tested: alias removed, 1 + 2 red. (LL's `_normRelType` has the same gap:
    `/\bep\b/` does not match `epmini` — reported to Simon, not changed.)
  - **Tidal / Deezer / Spotify / Bandcamp**: no type → ALBUM, as Material assumes. Reaching into the
    plugins' internals for one was DECLINED fleet-wide (2026-07-25, re-confirmed 2026-09-02); do not
    re-propose it here.
  Guard: `t_browse.pl` (type rows, names, counts, order; each type's tiles; library live + retag; the
  compilation rule; LMS's releaseTypeName vs the fallback), `t_tracker.pl` (asked once, an answer after the
  promotion lands and keeps the album ref, an answer before it survives it, Deezer asks nobody,
  `fetchReleaseType` direct), `t_db.pl` (`setReleaseType` merge / refusals). Anti-tested, 11 mutations,
  each red (library not live 3, compilation rule 1, stored type ignored 3, order 2, empty-name skip 1,
  per-run cache 1, describe not carrying the type 1, tracker never asks 6, ref overwritten 1+1, type rows
  not filtered 5).
- **A YEAR IS ALSO A NAME (`parseYearSearch`, `_searchResults`) — Simon, 2026-09-19.** *"search by year as
  well as exact date … and can we have year option when browsing"*. A search that is a year (`2025`) or two
  years joined like a date range (`2024 - 2025`, either order) answers with a **"Played in 2025 (n)"** row
  (`_rangeLink` → `_range` → `DB::forRange`, count from `DB::countRange`) FIRST, then the ordinary text
  matches under their sort row. Simon chose this over "a year is only a year": *1989* and *The 1975* are
  names, and a bare number must still find them. No year row when that year has no entries; nothing at
  all → `PLUGIN_LH_NO_RESULTS`. A year is 1970–2999 (any other 4 digits is text only).
  - Opening the row from Material: search results carry `item_id` `_<term>.N`, which XMLBrowser resolves
    by re-running the search through `_legacySearch` and taking row N. Checked live 2026-09-19 on a date
    search (row `_18%2F09%2F2026.1` opened that album's 12 tracks). The row order is deterministic, so
    position 0 is the year row every time.
  - **By date**: Today, Yesterday, then one row per year (`DB::years`, newest first). A year
    (`_months`, `DB::months($year)`) opens **"All of 2025 (n)"** then its months; a month opens its days
    as before. Simon chose the "All of" row over year → months only.
  Guard: `t_browse.pl` (every accepted/rejected form, the row + text matches, the whole year inclusive of
  1 Jan 00:00 and 31 Dec 23:59:59, a range, no-entries, a numeric name, the By date years/All of/months)
  and `t_db.pl` (`years`, `months($year)`, `countRange`). Anti-tested: year row dropped 3 red, text matches
  dropped 2, range end +1 year 8, no year level 1, no All-of row 3, the 1970 floor dropped 1.
  - A range is split on ` - `, ` to ` or a spaced en/em dash, in either order, with both days
    inclusive. The bounds are local midnights from `POSIX::mktime`, so a clock-change day is
    exact.
  - An impossible date (31/02) is not a date and falls back to a text search.
  - Date plus text in one search was offered and NOT chosen. Nor were month-only terms.
- **THE NAME KEY USES THE FIRST CREDIT.** With no album id, `albumKey` is
  `<source>:name:<lc album>|<primaryArtist>`. Spotty joins every credit at play time
  ("Kygo, Khalid, Gryffin"), so the full string differs track to track within one album; the first
  credit does not. The key only ever compares CONSECUTIVE tracks on one player, so two different
  albums sharing a title and a first credit, played back to back, is the only collision.
- **BANDCAMP REPLAYS WHAT WAS HEARD.** `Bandcamp::get_album` needs the album PAGE url; a playing
  Bandcamp track does not expose it. Such an album falls to `Sources::playedTracks` — the recorded
  urls, in play order. So does Deezer (no album id in `getMetadataFor`) and any service not in
  `serviceCan`.
- **COPIED, NOT SHARED.** `playingMeta`, `isPlayableTrack`, `_albumNode`'s per-service
  passthrough keys, and `_spotifyAlbumId` are copies of LL `Sources.pm` / `Played.pm`, each
  commented with its origin. A sibling plugin cannot be `use`d (installed-layout package names),
  and a runtime dependency on LL would make these rows unplayable without it. None of it is the
  shared matcher, so the fleet matcher-sync rule does not apply.
- **THE TIE-BREAK CANNOT BE PINNED.** Every list orders `played_at DESC, id DESC`. Removing
  `id DESC` leaves `t_db` green because the `entries_played` index already yields that order.
  It stays so the order is guaranteed by the query, not by the planner.
- **`LIST_CAP`** (1000) bounds every browse list. A capped list ends with a text row saying so and
  pointing at By date. The home shelf and Recently played are 50, fixed (Simon's spec).
- **THE SERVICE IS A BADGE — Simon, 2026-09-18 (1.0.1). VERIFIED LIVE 2026-09-18 on a Material 6.4.9.1 build made from upstream `master` at `d3f1d9227`.** `Browse::entryRow`
  no longer writes the service name (`sourceLabel`) into line2, and that includes "Library". Every
  row with a service carries `extid` (`Sources::extid`), and Material draws its service badge on the
  artwork from the part before the first `:`, looked up in `emblems.json`.
  - Material: upstream `d3f1d9227` (2026-09-18) maps a SlimBrowse row's extid to an emblem.
  - LMS: 9.1 `Slim/Control/XMLBrowser.pm:1176` passes the feed item's extid through.
  - Where the prefix comes from: the stored source first (qobuz, tidal, deezer, deezerpodcast→deezer,
    spotify, bandcamp), else the url scheme (radioparadise, sounds→bbc, youtube, ytm, pandora).
  - What the row carries: an album row with `svc_album_id` gets the real `<svc>:album:<id>`, any
    other badged row gets the bare `<svc>:`. On a SlimBrowse row Material reads only the prefix. Its
    favourite-url use of extid is gated on library `album_id:` ids, which these rows never have.
  - What gets no badge: library rows, plain radio and plain web streams, the same as Material's own
    library lists.
  - Accepted consequence: on a Material without `d3f1d9227`, and on the web skins, a row no longer
    shows its service at all. By service still groups by it.
- **A ROW READS LIKE A RELEASE — Simon, 2026-09-19.** `Browse::entryRow` gives Material the same two
  lines as any release elsewhere in LMS: the album (a station: its name) on top, the artist underneath,
  and nothing of our own. A track row is one line since 1.0.4 — see `A SINGLE TRACK IS NAMED LIKE LMS
  NAMES ONE` below. *"we dont need to have our own variant here"* — asked for the
  grid thumbnails, and the extra line was dropped entirely rather than kept as a tail.
  - Gone from the row: `Artist – ` in the name, the ♫/♪ glyphs, "N of M tracks" / "from <album>", the
    player and the date/time (`_join`, `_when`, `SEP`, `GLYPH_*`, and six unused strings removed). The
    data is still stored and the sort row still orders by date, artist or album.
  - A station has no second line; a row with no artist likewise.
  - **A SINGLE TRACK IS NAMED LIKE LMS NAMES ONE (`_trackName`) — Simon, 2026-09-19.** *"if a user plays just
    a single track from an album we should be showing it like LMS does for one track"*, pointing at his
    Favourites: a Qobuz track saved there reads `Live By You by Actress from Radical Frame` (checked over
    `favorites items`: one `text` line, no second line, and Material does not split it). So a `track` row is
    `name` = "Title by Artist from Album" (core strings `BY` / `FROM`, translated), with NO `line1`/`line2`,
    identical on Material and the web skins. A missing artist or album drops its clause. Album rows stay
    album over artist (`_titled`); stations stay their name.
    Guard: `t_browse.pl` (the full form, no line1/line2, each clause dropped alone, album-row control);
    anti-tested (no FROM clause: 4 red; track put back on `_titled`: 5 red).
    **CHANGED by Simon 2026-09-21:** *"for single played tracks is it possible that the artist can show where it
    does for albums?"* then *"keep the track from album on top row, artist on 2nd"*. The one long line was cut off
    before the artist on Material. Now `name` stays "Title by Artist from Album" (web skins), plus `line1` =
    "Title from Album" and `line2` = the artist. With no artist there's no line1/line2, just the name. Offered and
    NOT chosen: the album on line 2 as well ("Artist · Album", the kind of tail removed on 2026-09-19).
    Guard: `t_browse.pl` track-row block (8 red on the one-line version).
  - **THE WEB SKINS KEEP THE ARTIST IN THE NAME (`_titled`) — Simon, 2026-09-19, from the 1.0.2 review.**
    Default / Classic draw `name` only (never line2), so a bare title there lost the artist. A release row
    now carries `name` = "Album by Artist" (core string `BY`, as LMS's own web lists word it) plus `line1`
    = album and `line2` = artist. `Slim::Control::XMLBrowser` sends Material `(line1 || name) . "\n" .
    line2`, so Material is unchanged. *"If I switch to webskin LMS doesnt loose the artist for its standard
    views."* Do not drop `line1`: without it Material shows "Album by Artist" as the title (17 red).
  - **The By album tiles too** (`_albums`, now `_releaseList` under By release — see `BY RELEASE, BROKEN DOWN LIKE LMS`; found from Simon's screenshot the same day): the album over the
    artist, no `– Artist (n)` label, and `extid` from the group's MOST RECENT entry (`DB::albums` now returns
    `last_id`; a group can mix sources, and the latest play is the one badged). A library album stays
    unbadged. `DASH` removed. By artist / By player / By service tiles are not releases and keep their
    `Name (n)` labels.
  - `extid` (the badge), `image`, the play fields and the "…" menu are unchanged.
  Guard: `tools/t_browse.pl` (album line2 is EXACTLY the artist; a track and a station have none; a service track's
  name carries no service, player or time; By album: album/artist, latest play's badge, library control), anti-tested
  (a tail on line2: 3 red; "Artist – Album" name: red; oldest play badged: 1 red; tile badge dropped: 1 red).
- **A RESTART IS NOT A NEW LISTEN — asked for by Simon, 2026-09-21.** Reported: after a server restart,
  resuming from Now Playing logged the play twice. Cause: `%session` / `%pending` are memory only, so
  the resumed album became a second entry and a track counted before the restart was counted again.
  Fix: `Tracker::_restore` runs on the FIRST newsong per player after `init` (`%restored`), reads
  `DB::forPlayer($cid, 1)` and, if it ended within `session_gap_min`, rebuilds the session (urls from
  its plays) with `resumed_url` = the last play's url. `_record` drops the first counted play if it is
  that url, then forgets it, so a deliberate replay afterwards still counts. Dropping it also sets
  `last_at` to now (review 2026-09-21: without it a long track resumed after a restart split the album
  again, the gap measured from the count BEFORE the restart; guard: "restart in a long track", 2 red without it).
  1.0.10 (second review) armed the mark for `target - $client->songElapsedSeconds`: a NO-OP, and its test
  passed only because the stub counted elapsed from the start of the TRACK. 1.0.11 (third review, 2026-09-21)
  replaces it: on the FIRST newsong per player after startup only, `$song->startOffset` (the resume point)
  comes off the target; `_markTick` stays stream-relative, so a seek must still be listened through.
  Simon, 2026-09-21: streaming titles restart FROM THE TOP after a restart (the `resumed_url` drop covers
  those); LOCAL files resume where they stopped (the startOffset path). Guards: "resumed at 80%" (2 red on
  1.0.10 with the corrected stub), "CONTROL seek to 95%", "streaming restart from the top".
  VERIFIED FROM LMS 9.1 SOURCE (read, not measured live), do not re-derive:
  - `Squeezebox2::songElapsedSeconds` counts from the start of the current STREAM. The track position is
    `StreamingController::playingSongElapsed` (= `Slim::Player::Source::songTime`), which adds `startOffset`.
  - A seek fires `newsong`: `_JumpToTime` stops and re-streams, the player's track-started event runs
    `_Playing`, which notifies `playlist newsong`.
  - LMS's own auto-resume on reconnect (`Player::resumeOnPower`, powerOnResume …PlayOn + playingAtPowerOff)
    is `playlist jump <index> … {timeOffset => positionAtDisconnect}`, i.e. a resume at an offset.
  - A local file started at an offset DOES set `$song->startOffset`, on both paths: a transcoder seek
    (`Song::open`, `$transcoder->{start} = $self->startOffset(timeOffset)`) and a direct byte seek
    (`Protocols::File`, `$song->startOffset($seekdata->{timeOffset})`). A cue-sheet track's position in its
    file is `$song->offset`, a separate field, so a cue track started normally reads startOffset 0.
    (Fourth review, 2026-09-21: checked and cleared.)
  VERIFIED LIVE 2026-09-21 on 1.0.11, HQPlayer (ManCave), local FLAC, *It Goes On*: track 1 recorded as a
  track entry; paused 9s into track 2, server restarted, resumed from Now Playing: the queue survived (2 of
  11), track 2 restarted FROM THE TOP, counted at 2:36 and JOINED the entry (now one album entry, no
  separate track 2 entry). NOT exercised live: the startOffset path. On this player a local track restarted
  from the top too, so "local resumes where it stopped" is unconfirmed here (maybe real players or
  LMS's auto-resume on reconnect only). **Simon, 2026-09-23: local files DO resume in place after a
  restart in some circumstances.** No code change: that is the startOffset path, built for it.
  1.0.15: `resumed_title` too. Radio Paradise plays every song on ONE url, so the url alone dropped the
  first NEW song after a restart; the drop now needs the title to match as well (a play with no title
  still matches on the url). Review of 1.0.15: the title decides ONLY where `Sources::sharesUrl` (the
  handler's `isRepeatingStream`) says the url is shared; everywhere else the url alone decides, as in
  1.0.14, because a service track's title can fall back to LMS's row name just after a restart. Guard: "RP restart" (red on 1.0.14) + "CONTROL RP restart" (same song).
  1.0.15 also moves the startOffset into `$info->{from}` (see `A PAUSE IS NOT A GAP`); the target is
  recomputed at every check and `from` comes off it. A stop/clear seen before
  the first newsong does NOT cancel the restore: what LMS sends around a restart is unmeasured, and
  the gap decides. Known limit, accepted: restart, then within 30 min deliberately play the track
  that was last recorded = not counted. Guard: `tools/t_tracker.pl` "restart" block (10 red on the
  old Tracker; the gap and other-player controls stay green). UNVERIFIED LIVE: whether a resume fires
  `newsong` and at what offset. The suite covers both an offset and a restart from the top.
- **THE SERVICE NAMES ITS TRACK — fixed 2026-09-21, asked for by Simon.** Live: three Qobuz rows read
  "Pylon by beabadoobee from Pylon by beabadoobee from Pylon". Writer: LMS stores the name of the row a
  track was started from as its title (`Commands.pm` playlist play: `Slim::Music::Info::setTitle($url,
  $title)`, LMS 9.1 source), and `describe` preferred `$track->title` for a service track. A favourite
  track or one of OUR OWN track rows (`_trackName`, since 1.0.4) is named "Title by Artist from Album", so a
  replay from the history recorded that whole name as the title. Fix: the handler's title first, `$track->title`
  as the fallback. Stations are unchanged: they are deliberately named from `$track->title`. Existing bad rows:
  Simon removes his three by hand; a repair migration was offered and DECLINED. Guard: `t_tracker.pl`
  "service title" (2 red on the old order) + a no-handler-title control.
  1.0.13 (review of 1.0.12): the handler-first order is NOT for a plain web track (source `http`/`https`,
  i.e. LMS's own HTTP handler); every plugin handler keeps it. A plain http(s) track keeps `$track->title` first: LMS's HTTP handler (`Protocols/HTTP.pm`
  `getMetadataFor`, 9.1 source) builds its title from `getCurrentTitle`, which `playlist play` set to the row name,
  and splits exactly one " - " into artist and title. So "Episode 12 - The Big One" was recorded as "The Big One".
  Guard: "web track: keeps its own title" (red on 1.0.12).
  Same review: the split's front half was also stored as the ARTIST (older than 1.0.12). `_isSplit`: for a plain web
  track, drop the handler's artist when its artist and title rejoined with " - " (case and whitespace folded) equal
  the track's own title; a real stream artist is kept. Guard: "web track: and not the split's front half" (red
  before) + "CONTROL web track: an artist the handler really has is kept".
- **A PAUSE IS NOT A GAP (`Tracker::_unpause`, `%paused`, `_owed`, `from`) — fixed 2026-09-23 (1.0.15),
  reported by Simon.** Live: Gia Margaret *Singing* (Qobuz, MacBook Pro / LyrPlay) paused and resumed was
  logged as TWO album entries (Simon removed one); two back-to-back *Radical Frame* (Qobuz, HQPlayer
  ManCave) entries may be the same. VERIFIED FROM LMS 9.1 SOURCE (read, not measured live), do not re-derive:
  - `StreamingController::_CheckPaused`: a paused REMOTE track whose player buffer is >98% full stops
    fetching (`_pauseStreaming`) if it `canSeek`. The resume is then `_JumpOrResume` -> `_JumpToTime
    {newtime => resumeTime}`: a NEW stream from the pause point, i.e. `newsong` on the SAME url with
    `startOffset` = the pause point, and NO `['playlist','pause',0]` (only `_Resume` sends that).
  - A local file (not remote) is always `_Resume`d in place: `pause 1` then `pause 0`, no newsong.
  - The notification is `['playlist','pause','_newvalue']` (Request.pm dispatch table).
  Two defects came from it, reproduced in the harness: (1) the re-stream re-armed the FULL 90% against
  per-stream elapsed, so the paused track was never counted; (2) the gap ran through the pause, so the next
  track after a pause of ~30 min started a new entry. (2) also hit LOCAL albums when the pause fell after a
  track's 90% count.
  Fix: subscribe to `pause`. `pause 1` stores `{at, url}`; `pause 0` OR the next newsong ends it
  (`_unpause`), moving the session's `last_at` and the pending track's `started_at` on by the time paused
  (each only if it was before the pause), so the pause is out of the gap. A newsong on the paused url with a
  NON-station mark pending is the re-stream: the mark is kept, `from` = `startOffset`, re-armed for
  `_owed` = target - from. Paused after the count: the re-stream is ignored (still that one play).
  Review of 1.0.15: ONLY when the new stream starts where it paused (`abs(startOffset - pos) <=
  RESUME_SLACK` (3s), `pos` = `_position` at the pause: `controller->playingSongElapsed`, LMS's own resume
  time). A seek made while paused starts elsewhere and takes the normal path (so would a shared-url stream's
  next song, from 0; Radio Paradise itself refuses pause, `canDoAction`).
  A seek (no pause before it) is unchanged: the whole 90% is owed (pinned by two CONTROLs).
  Accepted: time paused never counts towards the gap, so pause at night, press play next day = one listen.
  Guard: `t_tracker.pl` "a pause stops the session clock" (streaming resume, resume after the count, local
  pause after the count, mid-track, skip while paused, CONTROLs: gap without pause, pause+stop, streaming
  seek, another track after a pause). 12 red on 1.0.14; mutations: no clock shift 8 red, no mark kept 2 red.
- **THE LENGTH IS READ AT EVERY CHECK (`Sources::trackDuration`, `Tracker::_markTick`) — fixed 2026-09-23
  (1.0.15), reported by Simon.** Two live reports, one cause: a length learnt AFTER newsong.
  - Radio Paradise *"logs first track then nothing after that"*. RP 3.6.6 (`herger.net` zip, read) is
    `isRepeatingStream`: every song is a `clonePlaylistSong` on ONE url (`radioparadise://4.flac`), and LMS
    `_Playing` sends a newsong per song. The clone has no `_duration`, so `Song::duration` falls back to the
    SHARED track's secs, which RP's `getMetadataFor` updates (`setDuration`) only when asked: at newsong it
    is the PREVIOUS song's. So the mark waited 90% of the previous song; a shorter song was cancelled by
    the next newsong, never recorded. WATCHED LIVE 2026-09-23 (MacBook Pro): The The 212s recorded at 199s,
    the song before it missed; Jerry Garcia 257s after it recorded.
  - A streaming album QUEUED after a local album was logged before its first track had finished. A service
    track with no length at newsong (target 0) was armed for the 60s fallback and `_markTick` re-read the
    length ONLY for a station, so it was counted at 60s. NOT confirmed live that Qobuz has no length at
    that moment; it is the one path found that counts a streaming track before its 90%. Turn on
    `plugin.listeninghistory` INFO to catch the next one with times.
  Fix: `Sources::trackDuration` = the handler's `duration` FIRST for a remote track (it describes the song
  playing now), then `$song->duration`; `describe` and `Tracker::_duration` both use it, so they still
  agree on what is a station. `_markTick` re-reads it at EVERY check and recomputes the target; a remote
  non-station track still with no length re-arms for 60s rather than counting (describe refuses a service
  track with no length anyway). Guard: `t_tracker.pl` "late length", "no length yet", RP block (timed from
  its own length, each song its own entry with its own duration). Mutation: song length first again, 7 red.
- **NO BACK-FILL FROM LMS — declined by Simon, 2026-09-18.** An import from LMS's persistent DB
  was offered: `tracks_persistent` holds only ONE `lastplayed` + a `playcount` per LIBRARY track
  (no player, no earlier plays, almost certainly no streaming or radio), so it could only rebuild a
  lossy "last time each track played" history. Simon: leave it. Do not re-propose without a new
  data source that holds real per-play history.
- **THE LOGO STAYS — Simon, 2026-09-18.** Swapping `ListeningHistoryIcon.{svg,_svg.png,.png}` for
  Material's own Recently Played glyph (`history`, font glyph `uniE889`, `browse-resp.js`
  `icon:"history"`) was started and stopped: keep Google's `music_history`.
- **MORE BY THIS ARTIST** was in the plan's context menu and was dropped at build time to keep
  the menu to one CLI action; By artist already lists the same rows. It would need a `go` into a
  query that returns rows (LL's `buy` shape). Re-add only if Simon asks. The menu holds Remove
  only.

- **FOUND AGAIN THE WAY LMS FINDS IT — `Sources::libraryAlbum`, `_byAlbumMbid`, `_byUrls`,
  `_byTrackMbid`, `_byAlbumUrl`, `_albumKeys`, `DB::relinkLibrary`, ref `album_mbid` / `track_mbid` /
  `album_url` — decided by Simon 2026-09-24 ("follow what LMS does … persist works for all users").**
  A library entry's album after a rescan, retag or move. The steps run most exact first:
  1. the row id;
  2. the album MBID (a release split into discs: the one holding a played url);
  3. the played files, which must all agree;
  4. the track MBID, only if ONE album carries it (see `A TRACK MBID IS A RECORDING`);
  5. LMS's own `Album::url`. For an entry recorded before the keys, it is rebuilt from an ALBUM
     entry's album + artist; an old TRACK entry stores the track's artist, so it skips this step.

  A find by 2–5 is written back (compare-and-set on `ref.album_id`, `album_key` only where it was
  `lib:<old>`, artwork refreshed, `plays` never touched). There is no write during
  `Import->stillScanning`. No schema change: the keys live in `ref_json`. The keys are recorded at
  play time (`describe`). An entry recorded before them gets them when it is OPENED
  (`resolveTracks`, capture on) or SWEPT. A list render never searches at all: `releaseType` (By
  release asks it of every release) reads the row id alone, and a stale release reads as its stored
  type or ALBUM until the sweep or an open finds it again (`A LIST RENDER DOES NOT SEARCH`, §C
  2026-09-24). Accepted residual: step 5 is LMS's guess by
  name (first match, as a favourite), used only after every exact key has failed. (The residual
  once stated here, that an old single-TRACK entry never captured the keys, is CLOSED by the
  sweep in `HISTORY FOLLOWS THE LIBRARY`.) Guard:
  `t_browse.pl` relink block, `t_db.pl` relink block, `t_tracker.pl` "keys". 12 mutations, each red.

- **HISTORY FOLLOWS THE LIBRARY — `Sources::_nameChanges`, `libraryAlbum` modes, `startSweep` /
  `stopSweep` / `sweepTick`, `DB::libraryAfter`, `DB::relinkLibrary` names, `Plugin::_onRescanDone`
  — decided by Simon 2026-09-24.** The retag test on the rig (1.0.16: "At Sea (Single)" renamed
  "bollocks", LMS rebuilt it as album 46646, and the entry relinked by its played files) showed the
  row keeping the old name. Simon chose to have the names follow the library, updated by a sweep
  after every rescan.
  - What follows: an ALBUM entry takes the album's title, album artist and year. A TRACK entry
    takes the album and year, plus its own track's title and artist when its file is on that album.
    Values are trimmed as `describe` trims. The play log (`plays`) is never touched: it keeps what
    was heard.
  - When: on an entry being OPENED (`resolveTracks`, mode `open`) or SWEPT (mode `sweep`), whether
    its album was found again or is still there. A list render never renames anything: it does not
    call `libraryAlbum` (`A LIST RENDER DOES NOT SEARCH`).
  - The sweep: `['rescan','done']` (sent by `Slim::Music::Import` when a scan ends or is aborted)
    and once 120s after startup. It walks every library entry by id cursor, 25 per tick, 1s apart.
    While a scan runs it waits 30s and carries on from the same place. It also captures the lasting
    keys, which closes the old single-track gap. It logs one line at the end: WARN when it changed
    something, INFO otherwise. A new rescan restarts it; shutdown stops it.
  - Accepted costs: every restart re-walks the library entries (a `find` each, plus one track
    lookup per track entry). An entry whose album cannot be found repeats steps 2–5 on every sweep.
    Neither writes.
  - The summary line counts an entry once: a relink that also renamed it is counted under "found
    their album again", so "0 renamed" beside "1 found" can still mean a row changed its name.
  - Until the sweep reaches it, an unopened stale entry shows its old name, and its cover is LMS's
    placeholder (its stored coverid is gone). Opening the entry fixes it at once. VERIFIED LIVE on
    1.0.17, §B.
  - Guard: `t_browse.pl` "names:", "sweep:" and "plugin:"; 12 mutations, each red.

### A3. DISPROVEN — beliefs the code suggests and a measurement killed

Not defects and not decisions. Re-raise one only by disproving the evidence it cites.

- **AN ALBUM ID IS NEVER REUSED — `Sources::resolveTracks`, `_libraryTracks`,
  `_libraryReleaseType`, library `ref.album_id` — disproven 2026-09-23 (checked while comparing
  with Material's Recently Played).** Belief: after a rescan LMS renumbers `albums.id`, so a stored
  `album_id` could point at a DIFFERENT album and an entry would replay, or be typed as, the wrong
  release. Evidence (LMS 9.1 source): `SQL/SQLite/schema_1_up.sql` creates `albums.id INTEGER
  PRIMARY KEY AUTOINCREMENT`, and "Clear library and rescan" (`Slim::Schema::wipeDB` →
  `schema_clear.sql`) empties the table with `DELETE FROM albums`, which leaves `sqlite_sequence`
  alone, so new ids always sit above old ones. Deleting the cache folder cannot mix them up either:
  our db is `cachedir/listeninghistory.db`, next to `library.db`, so the two go together.
  - What a stale id DOES do (a wipe-and-rescan, or a retag that makes LMS rebuild an album): it
    points at NOTHING. `resolveTracks` falls back to the tracks that were played, and
    `releaseType` falls back to the stored type or ALBUM, so an EP / single / compilation moves under
    Album in By release. **BUILT 2026-09-24** (`FOUND AGAIN THE WAY LMS FINDS IT`, §A2): the entry
    is found again by its lasting keys and relinked, and only when nothing answers does it fall
    back, as it did before.

- **A TRACK MBID IS A RECORDING — `Sources::_byTrackMbid` — disproven 2026-09-24.** Belief: persist.db
  finds a track by its MusicBrainz id first (`Track::retrievePersistent`), so that id can find the
  track's ALBUM. Evidence (LMS 9.1 `Slim/Formats/FLAC.pm` L56 `MUSICBRAINZ_TRACKID => MUSICBRAINZ_ID`,
  MP3 `UFID`, Movie `MusicBrainz Track Id`): it is the RECORDING id, which is the same on the original
  album and on every compilation the song is on. persist.db only counts plays, so that does not
  matter to it. Here it would. So `_byTrackMbid` accepts only when every track carrying the id is on
  ONE album, and it runs AFTER the file urls, which are exact. Pinned: `t_browse.pl` "CONTROL relink
  track MBID".
- **LMS HAS NO PERMANENT ALBUM ROW ID — checked 2026-09-24.** persist.db has no album key at all.
  LMS's own lasting reference to an album, `Album::url` (what a favourite stores), is `extid`, else
  `db:album.title=…&contributor.name=…`, found again BY NAME (`Schema::_objForDbUrl` → `->first`). The
  scanner tells tagged albums apart by `albums.musicbrainz_id` (`_createOrUpdateAlbum`). Those are
  the keys `libraryAlbum` uses.

### B. KNOWN-OPEN AND ACCEPTED

- **UNVERIFIED LIVE (2026-09-18).** Installed on plex:9000 since 0.1.0 and Simon
  reports it working in general use; the service badge is verified live (§A2). 1.0.4 (single-track naming)
  built 2026-09-19 and RELEASED to `main` (`v1.0.4`). 1.0.5 (year search + By date years) released to
  `main` (`v1.0.5`) 2026-09-19. 1.0.6 (By release) built on dev and installed 2026-09-19 (Qobuz lookup verified live); 1.0.7
  (Qobuz `epmini` → EP) built and INSTALLED the same day; VERIFIED LIVE: By release = Albums / EPs / Singles,
  the stored EPMINI entry reads as an EP. 2026-09-21: 1.0.8–1.0.14 built and committed on `dev` (`0053471`), unpushed;
  1.0.11 was INSTALLED and the restart carry-on VERIFIED LIVE; 1.0.12–1.0.14 (service titles, the track row's
  artist on line 2, plain web titles/artists) are built and 1.0.14 is INSTALLED. VERIFIED LIVE by Simon: a
  streaming single-track row on Material shows the artist underneath, and it became an album entry after the
  second track. Still OPEN: a Qobuz track replayed from a favourite or history row records its plain title.
  The `startOffset` resume path is unexercised live. These specific paths have not been checked individually and are covered by
  the suites only:
  - 1.0.15 (built 2026-09-23, zip `54b0ccb4…`; three review rounds + a full check, ALL CLOSED; PUSHED to
    `dev` 2026-09-23; running on the rig since 1.0.16 was installed 2026-09-24, RELEASED in 1.0.18; the
    specific checks below still not done): the pause re-stream (only from the pause position), the pause clock, the per-check
    length (RP songs, a queued streaming track), the RP-only restart title check. Checks for Simon: pause a Qobuz album
    mid-track for 40+ min and resume (one entry, the paused track in it); a Radio Paradise hour (every song
    heard to 90% appears); a local album with a Qobuz album queued after it (no streaming row before its
    first track reaches 90%).
  - `Sources::isStation` — any remote non-service url with no duration is a station (timed, not recorded
    since 1.0.15). Not checked against TuneIn or BBC Sounds.
  - `Sources::_rpAnnouncement` (unreleased, after 1.0.18): the `/dj/` signal on `$song->streamUrl`. The
    station break ("Listener-supported" by "Commercial-free") was SEEN recorded live on 1.0.17, which is
    what the title/artist test matches; no DJ block has been seen yet.
  - `_albumNode` for Tidal, Deezer and Spotty (Qobuz is exercised with a stub only).
  - That `newsong` fires on radio title changes with the same url (assumed, and guarded either way).
  - Material rendering of the tiles (`_MTL_icon_` names checked against MaterialIcons.ttf: all
    present), the home shelf, and the search row.

- **README / CHANGELOG for 1.0.15–1.0.18: DONE at the 1.0.18 release (2026-09-24).** Every item below was
  written then, except the "Album session gap" setting row, fixed on `dev` afterwards (goes to `main` at
  the next merge). Kept for the record. At the merge,
  README.md (then README.html / index.html) must change: the intro "plus internet radio" (line ~3); the
  "Plays again" row "or the radio station" (~17); the "Radio too" row (~21); "pause it and the count simply
  waits" should add that a pause of any length keeps an album together (~49); the Radio bullet (~53) becomes
  "radio stations are not recorded; Radio Paradise is recorded song by song"; "Radio: the station's name"
  (~73) and "Radio: plays the station" (~93) apply only to rows recorded before 1.0.15; the "Album session gap"
  setting (~104) is the time between tracks NOT counting a pause; the "Record internet radio" setting row
  (~105) is removed; "Radio detection is by stream type" (~114). CHANGELOG: one entry for the release.

- **THE RELINK — RETAG VERIFIED LIVE on 1.0.16 (2026-09-24).** "At Sea (Single)" by All India Radio,
  retitled "bollocks": LMS rebuilt it as album 46646, and the entry opened the new album's three
  tracks straight from the library (no per-track image, so not the played-tracks fallback). Caveat
  seen: a tag editor that PRESERVES the file mtime makes LMS's standard rescan skip the file.
  **FULL CLEAR + RESCAN VERIFIED LIVE on 1.0.16 (2026-09-24, finished 11:48):** every album got a
  new id above all the old ones (Bubblegum 46639 → 47198, as AUTOINCREMENT predicts), and all 11
  library album entries in the baseline still opened their WHOLE album, with the same track counts.
  So each one was found again through its lasting keys. No Listening History errors in the log. One
  expected difference: the older "At Sea (Single)" entry's cover moved from the stale pre-retag
  coverid to the current one (refreshed by the relink).
  **1.0.17 SWEEP + NAMES VERIFIED LIVE (2026-09-24, server up 11:54:10).** Opening the first "At Sea
  (Single)" row renamed it to "Bollocks" (album 49586) with the new cover at once, before the sweep
  ran. At 11:56:11 (+120s) the log said `library check done — 12 entries, 1 found their album again,
  0 renamed`, and the second row then read "Bollocks" too, with the real cover in place of the
  placeholder PNG its stale coverid had served. Until the sweep runs, an unopened stale row shows its
  old name and a placeholder cover; that is the ~2 minute wait Simon saw, not a fault. The count
  reports a rename that rides on a relink under "found their album again", not under "renamed".
  The failed plays at the same time were HQPlayer (MacMini) being offline (`PlaylistAdd refused`),
  not this plugin.

### C. CLOSED FINDINGS

**Review round 2026-09-24 (`063e1d8..c0f875c`, 1.0.18, /code-review) — CLOSED, NO findings.** Checked
and CLEARED: `releaseType` on a live album reads exactly what the no-mode `libraryAlbum` read (find,
no write); a renumbered album reads ALBUM until the sweep or an open (library entries store no type);
`libraryAlbum`'s only plugin callers are `sweepTick` and `resolveTracks`, so its comment is true; the
new test's lookup counter catches the old path (it searches by album MBID through `Slim::Schema->search`).

**Review round 2026-09-24 (`74013de~1..063e1d8` + the uncommitted doc edits, /code-review) — CLOSED,
two findings, both FIXED and BUILT as 1.0.18 (not installed; UNVERIFIED LIVE, nothing to see beyond
By release staying quick during a rescan).**
1. **A LIST RENDER DOES NOT SEARCH — `Sources::releaseType`, `Browse::_releaseGroups`.** Since 1.0.16
   `releaseType` called `libraryAlbum($e)`, so every By release view (the top list AND each type's
   list: `_releaseGroups` runs for both, over every release in the history) ran steps 2–5 for every
   stale library release: a `plays` read, one `objectForUrl` per played file, two MBID searches and the
   album-url lookup, blocking the server. Through a whole rescan nothing is stored
   (`stillScanning`), so each view repeated it for every entry; an album gone from the library paid
   it on every view for good. Before 1.0.16 it was one `find`. FIX: `releaseType` reads the row id
   alone (`find`), exactly the pre-1.0.16 cost; finding again is left to the sweep and to an open.
   Knock-on checked: (a) the sweep is the repair path, and `['rescan','done']` is sent on EVERY scan
   end, measured in the LMS 9.1 source: `SQLiteHelper::_notifyFromScanner` on the scanner's `exit`
   (normal end, and an exit without `end`), `Import::abortScan`, and `Import::stillScanning` when the
   scanner process died; plus the startup sweep. (b) Library entries store no `release_type`
   (`describe` stores it for Qobuz only), so a stale library EP / single reads as ALBUM from the
   rescan's end until the sweep reaches it (10s + 1s per 25 entries), as it did permanently before
   1.0.16. (c) `libraryAlbum` with no mode now has no plugin caller; kept for the suites, doc says so.
   (d) Names, artwork, `album_key` and the play log are written only by `open` / `sweep`, unchanged.
   (e) `resolveTracks` (one entry, on a tap) still searches, by design. Guard: `t_browse.pl` "CONTROL
   relink: a list render does not search" (counts `search` + `objectForUrl` calls: 0) and "and writes
   nothing"; both RED with the 1.0.16 line put back. 485 assertions green.
2. `DB::libraryAfter` had been inserted between `plays`' comment and `plays`, and named
   `Sources::_sweepTick` (it is `sweepTick`). FIXED: comment moved back, name corrected.

**Third review round 2026-09-23 (`874e991~1..963a417`, /code-review) — CLOSED, NO findings.** Checked and
CLEARED (do not re-derive): the station early-return moved below the resume branch still ignores a no-length
title change, and a same-url song WITH a length re-arms as a track; an old `station` row rebuilt by `_restore`
still suppresses its resumed station (which records nothing anyway). The resume credit `from += startOffset -
base` is right for a restart mark (`from = base = S`), a mark with target 0 (falls to 60s) and two resumes in a
row; `killTimers` then `_arm` leaves ONE timer. A podcast paused inside its first 60s, before it knows its length,
is timed from the resume point (as before 1.0.15; rare). `_unpause`: a pause inside the pending track moves
`started_at` and `last_at` together (gap unchanged), a pause between tracks moves only `last_at`, a lone `pause 0`
is a no-op. A `deezerpodcast` / service track that never learns a length re-arms every 60s and is never recorded
(describe refused it before 1.0.15 too). A station always ends the album session (deliberate, `_record`
comment; 1.0.14 with `record_radio` off did not). In the restart check `$d->{title}` cannot be undef
(describe refuses no title), and `sharesUrl` is asked only after url and title are compared. Nothing still
reads `record_radio`, `PLUGIN_LH_RADIO*` or `PLUGIN_LH_ENABLED`.

**Full check of 1.0.15 2026-09-23 (whole Tracker state machine walked by hand, after two review rounds) —
one finding, FIXED, committed.** A same-url newsong was dropped as a station title change whenever the
pending mark or the session was a STATION, even when the new song HAS a length. So if Radio Paradise's first
song was still undescribed (length 0) at its 60s check, it became a station session and every later RP song
was ignored until a stop (older than 1.0.15; RP symptom). Fix: the station early-returns apply only while the
newsong itself is a station (`$station`, no length). Guard: "RP after a station guess" (2 red on `23bace0`);
the radio title-change tests stay green. Checked in the same pass and CLEARED, with the source read: only
`_Pause` / `_Resume` notify `playlist pause` (a rebuffer's `_Resume` sends a `pause 0` with no `pause 1`,
which `_unpause` ignores); LMS turns a pause a handler refuses into a STOP (`StreamingController::pause`), and
RP refuses pause (`canDoAction`), so RP never enters the pause paths; `_JumpToTime` with `restartIfNoSeek` on an
unseekable track restarts at 0, which misses the position match and is timed from the top (correct); `pos` is
`playingSongElapsed` = `resumeTime` while paused, the same absolute figure a re-stream's `startOffset` is; a
restart's `from`/`base` start equal, so a later resume credits only what played after it; a seek with no pause
still owes the whole 90%; `trackDuration`'s handler-first order reads a numeric `duration` (Qobuz, Spotty,
TIDAL, RP); a non-numeric one falls back to the song's.

**Second review round 2026-09-23 (`874e991~1..23bace0`, 1.0.15 span, /code-review) — CLOSED, one finding,
FIXED, committed.** A seek, THEN a pause and resume, credited the whole resume point: `from` was set to
the re-stream's startOffset, but the mark was timing a stream that began at the seek point (`from` 0). 10-min
track, seek to 8:00, pause at 8:30, resume: 510s credited, recorded at 9:00 after a minute heard. Fix:
`$pending{…}{base}` = where the mark's current stream began; a resume adds `startOffset - base` to `from`
and moves `base`. Guard: "seek then pause" (2 red on `23bace0`) + "CONTROL two resumes" (green both). Writer:
LMS `time` (a seek) then pause on a remote track, reachable from any skin's seek bar. Cleared by the same
review (checked, not defects): the pause clock shift incl. a pause between tracks, skip while paused, a second
pause after a resume; the per-check length incl. a service track waiting with no length; the RP-only title
check; the station path writing nothing; no leftover `record_radio` reference.

**Review round 2026-09-23 (`874e991`, 1.0.15, /code-review) — CLOSED, three findings, all FIXED (`d46604c`).**

| # | finding | disposition |
|---|---|---|
| 1 | a seek made WHILE PAUSED was taken for the resume: its startOffset came off the target, so 10s + the last 30s counted | FIXED: resume only if the re-stream starts within `RESUME_SLACK` of the pause position (`_position`) |
| 2 | the restart drop needed a title match for EVERY service: a Qobuz/Spotty title falling back to the row name after a restart counted the resumed track twice | FIXED: title compared only where `Sources::sharesUrl` (isRepeatingStream) |
| 3 | Radio Paradise: Next pressed while paused, after song A counted, was ignored as "the rest of A" (same url) | PROBABLY UNREACHABLE: RP 3.6.6 `canDoAction` refuses `pause` (and `rew`). Covered anyway by #1's position check (a new song starts at 0); the test pins the branch, not a live path |

Guards: `t_tracker.pl` "review of 1.0.15" block, 5 red on `874e991`. Writers: #1 LMS `time` while paused
(`_JumpToTime`); #2 needs the handler to have no title just after startup, NOT seen live; #3 none found (RP
refuses pause).

**Review rounds 2026-09-21 (1.0.8 → 1.0.14, five inline rounds, committed on dev through `0053471`, unpushed) —
ALL CLOSED.** Six findings, five FIXED, one DECLINED. Details in `docs/VERSION-HISTORY.md` 1.0.8–1.0.14.

| # | round | finding | disposition |
|---|---|---|---|
| 1 | review of 1.0.8 | resumed track dropped without refreshing `last_at`: a long track resumed after a restart split the album on the gap | FIXED 1.0.9 |
| 2 | review of 1.0.9 | the mark armed for the full target: a track resumed part way through ended before it and was never recorded | FIXED 1.0.10, but that fix was a NO-OP, see #3 |
| 3 | review of 1.0.10 | 1.0.10 read `$client->songElapsedSeconds`, which counts per STREAM; its test passed on a stub that counted per track | FIXED 1.0.11 (`startOffset`, first newsong only; stub corrected) |
| 4 | review of 1.0.12 | handler-first titles also hit plain web tracks, where LMS's HTTP handler splits the row name at " - " | FIXED 1.0.13 |
| 5 | review of 1.0.13 | the same split stored the front half as the ARTIST (older than 1.0.12) | FIXED 1.0.14 (`_isSplit`) |
| 6 | review of 1.0.14 | `_isSplit` names a lexical `$a` (shadows `sort`'s) | DECLINED by Simon 2026-09-21: *"ill live with that for now"*; harmless, no `sort` in it. Rename only if a build touches it anyway |

Cleared in the rounds (checked, not defects): review of 1.0.11: `startOffset` is set for a local resume on both
paths (logged under `A RESTART IS NOT A NEW LISTEN`). Review of 1.0.12: every track row path (Recently played,
home shelf, search, By date) uses `_trackName`, and album and By release rows keep `_titled`. Review of 1.0.14:
a plugin metadata provider on an `http` url loses its artist only if it is exactly the title's front half.
Test-harness lesson (#3): a stub built from the code's guess of an LMS value makes a no-op fix pass. Model the
stub on LMS's source, then anti-test.

**Review round 2026-09-19 (unpushed `e70f803`, 1.0.2) — CLOSED, one defect reported twice, FIXED.**
`entryRow` (history rows) and `_albums` (By album tiles) moved the artist onto line2 only, which the
Default / Classic web skins never draw — two plays of "Intro" by different artists, or two "Greatest Hits"
tiles, became indistinguishable there. Fixed with `_titled` (§A2 `THE WEB SKINS KEEP THE ARTIST IN THE
NAME`). t_browse 103 → 108; anti-tested (web name without the artist: 3 red; `line1` dropped: 17 red).
Cleared in the same round: nothing still uses the removed helpers/strings, `POSIX` is still needed, the
`last_id` subquery matches rows as the grouping and `forAlbum` do, and the badge path gets a decoded `ref`.

**Review round 2026-09-18 (whole plugin at 0.1.1, not a git repo yet so no diff) — CLOSED,
three findings, all FIXED in 0.1.2.** Details and tests in `docs/VERSION-HISTORY.md` 0.1.2.

| # | finding | disposition |
|---|---|---|
| 1 | `DB::addToEntry` / `remove` / `purge` return success on a failed commit | FIXED — `_txn(...) or return 0` |
| 2 | `Tracker::_onChange` vs `Sources::describe` disagree on station-ness; a podcast skip at 61s counted | FIXED — `Tracker::_duration`, `_markTick` re-check |
| 3 | `Browse::_months` "Yesterday" = now-86400, wrong after a spring-forward midnight | FIXED — `_middayToday` |

Dropped by the review itself: a list of exactly `LIST_CAP` rows shows the "latest N" note
(`LIST_CAP` is settled in A2).

**Test-harness trap found in the round:** `time()` in a TEST FILE is the real clock (compiled
before the override); compare against `TestClock::now()`. It made a new assertion pass vacuously.

**Review round 2026-09-18 (0.1.3, second round) — CLOSED, two findings, both FIXED, built
in 1.0.0.**

| # | finding | disposition |
|---|---|---|
| 1 | `Browse::_services` showed two identical "Deezer" rows (`deezer` + `deezerpodcast` shared a `sourceLabel`); `http` / `https` showed as "Http" / "Https" | FIXED: `deezerpodcast` → "Deezer podcasts", `http`/`https` → "Web stream"; `_services` makes ONE row per LABEL carrying `sources => [...]`, and `DB::forSource` takes a list |
| 2 | `Browse::_sortRow` opened a blank page on the Default / Classic web skins (no `nextWindow`) | FIXED: `_webSkin($args)` → `_webBounce` back to the list (Pitchfork's rule, copied); Material still gets the EMPTY answer |

Each is mutation-checked in `t_browse` (old label, no bounce, no merge, feedMode ignored: all go red).
Dropped by the review: a search-result row opening the wrong item (disproved live: ids are
`_a.N`); the global `sort` pref moving a list under another client (Pitchfork's adopted mechanism);
pre-1970 / full-width-digit / `%e`-on-Windows date edges (no writer).

### D. ADDING TO THIS LEDGER
When a finding is declined, or accepted-but-deferred, add it here in the same session, one line,
with the reason.

## Server Details
- **LMS Server**: `http://plex:9000` (test over HTTP; never ssh)
- **Plugin DB**: `<server cachedir>/listeninghistory.db`
- **Log category**: `plugin.listeninghistory` (default WARN; INFO shows each recorded play)

## Testing the live server WITHOUT SSH
- Log: `curl -s http://plex:9000/log.txt`
- Feed: `POST http://plex:9000/jsonrpc.js` with
  `{"id":1,"method":"slim.request","params":["<mac>",["listeninghistory","items","0","50"]]}`
- Shelf: `["<mac>",["LHHome","items","0","50","menu:1"]]`
- Search: `["<mac>",["listeninghistory","items","0","50","search:<term>"]]`

## Install Commands
```bash
sudo rm -rf /var/lib/squeezeboxserver/Plugins/ListeningHistory
sudo unzip -o ListeningHistory.zip -d /var/lib/squeezeboxserver/Plugins/
sudo chown -R squeezeboxserver:nogroup /var/lib/squeezeboxserver/Plugins/ListeningHistory
sudo systemctl restart lyrionmusicserver
```

## File Structure
```
ListeningHistory/
├── Plugin.pm      # prefs, CLI (contextmenu/remove), tracker start, home shelf, daily purge, library check after a rescan
├── Tracker.pm     # newsong/stop/clear/pause subscription, 90% mark, album sessions, pause clock
├── DB.pm          # SQLite: entries + plays, migration ladder, queries, browse indexes, relinkLibrary
├── Sources.pm     # describe() a playing track; resolveTracks() an album entry; libraryAlbum() finds a
│                  #   library album again after a rescan (row id, album MBID, files, track MBID, LMS url),
│                  #   names following the library; startSweep/sweepTick run it over every library entry
├── Browse.pm      # app menu, history rows, homeShelf
├── HomeExtras.pm  # Material home shelf LHHome
├── Settings.pm    # settings page handler
├── install.xml  strings.txt
└── HTML/EN/plugins/ListeningHistory/{settings.html, html/images/*}
```
Icons: `ListeningHistoryIcon.{svg,_svg.png,.png}` is Google's `music_history`, copied from LL's
`PlayedIcon`. Tiles use `<name>_MTL_icon_<name>.png` font icons (history, search,
calendar_month, person, album, speaker, settings) — every name verified present in Material's
MaterialIcons.ttf 2026-09-18; the PNG is only a non-Material fallback.

## Prefs Namespace
`plugin.listeninghistory`: `played_threshold` (90), `session_gap_min` (30), `retention_days`
(0 = forever), `sort`. `record_radio` REMOVED in 1.0.15 (a stored value is ignored). No pref name may start with `_`.

## Regression tests — RUN BEFORE ANY BUILD
```
sh tools/t_all.sh          # one line per suite
V=1 perl tools/t_tracker.pl
```
| suite | protects |
|---|---|
| `t_tracker.pl` | Radio Paradise station breaks and DJ talk not recorded, the songs either side are (+ the non-RP control); the lasting keys (`album_mbid`, `track_mbid`, `album_url`) recorded and kept by a promotion, untagged / malformed MBID not stored; the grouping rules end to end through the real callback + timers: one track, album promotion, A/B/A, stop, same url, gap, two players, skip, pause, Qobuz id grouping, first-credit grouping, Spotty error text, radio timed once and NOT recorded (+ the deadline; ends the album session), a web track with no length at start is not timed as radio (skip at 61s of 300 not recorded), removed-mid-album, a server restart (album carries on, resumed track once, long track, before-count, single track, deliberate replay, other album, stop, gap control, other player, radio), a local resume at an offset vs a seek control, a streaming restart from the top, a service track titled by its handler (+ no-title control), a plain web track keeping its own title and not the split's artist (+ real-artist control), 1.0.15: a pause (streaming re-stream keeps its mark, after-count, local pause clock, mid-track, skip while paused, 4 controls; seek while paused; seek then pause credits only what played + two-resume control), the length re-read at every check (late length, no length yet, Radio Paradise per song + restart title check, RP-only title check vs a service title fallback, RP after a station guess) |
| `t_db.pl` | `relinkLibrary` (compare-and-set, keys merged, unknown key dropped, `album_key` only from `lib:<old>`, artwork kept when none given, plays untouched, non-library / missing / non-numeric refused), schema stamp + re-open, promote in one transaction, no orphan play on a missing entry, literal `%`/`_` search, indexes, forDay injection, remove/purge cascade, a failed COMMIT reported as failure by addToEntry/remove/purge |
| `t_browse.pl` | names follow the library (album / track entry, play log kept, By artist, never on a list render for a live album, not rewritten when unchanged), the rescan sweep (waits during a scan, batches, relinks + renames + captures, streaming untouched, log line, stopSweep), plugin wiring (rescan done subscribed, startup check armed, shutdown), a library album found again (`libraryAlbum`: album MBID incl. a split release, files, track MBID + the compilation control, LMS album url incl. non-ASCII and the old-track-entry control, files on two albums, nothing resolves, scan = no write, compare-and-set, valid id captured on open but not on a list render, a list render never searches for a stale album: 0 lookups, no write), shelf exactly 50 and flat and stable, row types, library album = whole album, no-id album = recorded tracks, Qobuz info rows dropped and empty-answer fallback, search dispatch + item_id gate, Yesterday across the spring clock change, album rows read Album over Artist and nothing else, a track row is "Title by Artist from Album" on the web skins and "Title from Album" over the artist on Material (each clause dropped alone; no artist = no second line), a station has no second line, By release (type rows in LMS order and names with counts, each opening its releases; library type read LIVE incl. Material's compilation rule, Qobuz type stored; LMS's releaseTypeName preferred) and its tiles (album over artist, the latest play's badge, library control), the service badge (extid) per source, the sort row (cycle, live-pref step, blank last, shelf unaffected, bogus pref), By service (+ the tile, one row per label, Deezer vs Deezer podcasts, http+https merged), the sort row's web-skin bounce, date search (every accepted form, ranges both ways, rejects, inclusive bounds), year search (the Played in row above the text matches, ranges, a numeric name) and By date years (All of + months), context menu + remove, settings clamps (no `record_radio`) |
| `t_load.pl` | every module loads; every `Plugins::ListeningHistory::X::y` call is defined |

Version history: `docs/VERSION-HISTORY.md`.
