# Listening History — LMS Plugin

## Project Overview
A plugin for Lyrion Music Server (LMS) that records a play history across EVERY player, for
local library files, streaming services (Qobuz, Tidal, Deezer, Spotify via Spotty, anything
else with a protocol handler) and internet radio. A played album is ONE entry, not one per
track; a lone track is a track entry; a station is a station entry. Every entry plays again,
streaming included. Material home shelf of the latest 50 entries; app menu to look back by date,
artist, album, service, player, or search by text, date or date range; every list sortable. Stores its own SQLite DB. Targets LMS 9.x, Material
Skin preferred. Built 2026-09-18 from Simon's brief, in the shape of Listen Later / LBF / PFR.

## Branches and releasing
- **1.0.4 is the first release**: merged to `main` and tagged `v1.0.4` on 2026-09-19. **1.0.5** (year search,
  By date years) released and tagged `v1.0.5` the same day. **1.0.7** (By release by type, Qobuz `epmini`)
  released and tagged `v1.0.7` the same day.
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
| radio recorded as a station row | **DECIDED by Simon 2026-09-18** | `RADIO IS A STATION ROW` |
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
| restart carry-on `Tracker::_restore`, `resumed_url`: first newsong per player after startup rebuilds the session from its last entry (within `session_gap_min`); the first counted play is dropped if it is the last play's url | **ASKED FOR by Simon 2026-09-21**; carry-on VERIFIED LIVE 1.0.11, offset path unexercised | `A RESTART IS NOT A NEW LISTEN` |
| service track title `Sources::describe`: handler `$meta->{title}` BEFORE `$track->title` (radio still names from `$track->title`) | **FIXED 2026-09-21**, asked for by Simon | `THE SERVICE NAMES ITS TRACK` |
| back-fill from LMS's own play data (`tracks_persistent` lastplayed/playcount) | **DECLINED by Simon 2026-09-18** | `NO BACK-FILL FROM LMS` |
| app/shelf logo `ListeningHistoryIcon` = Google `music_history`, not Material's `history` glyph | **KEPT by Simon 2026-09-18** | `THE LOGO STAYS` |
| "More by this artist" context entry | DROPPED at build; By artist covers it | `MORE BY THIS ARTIST` |
| radio detection, Tidal/Deezer/Spotify album nodes, live Material rendering | **UNVERIFIED LIVE** — §B | `UNVERIFIED LIVE` |

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
  percentage of the album. (The row used to say "N of M tracks"; since 2026-09-19 it shows only
  Album over Artist — see `A ROW READS LIKE A RELEASE`. The counts are still stored.) Offered alternatives (a % threshold; "queue matches the album")
  were declined.
- **THE 90% RULE — Simon, 2026-09-18.** A track counts at `played_threshold`% (default 90) of its
  duration, or `FALLBACK_SECS` (60) with no duration, re-checked against `songElapsedSeconds`, and
  cancelled by the next `newsong`. Copied from LL `Played.pm`. The scrobble "50% or 4 min" rule
  was offered and declined.
- **RADIO IS A STATION ROW — Simon, 2026-09-18.** One `station` entry per session, 60s after it
  starts, named after the station (`$track->title`), playing the station url. Title-change
  `newsong`s on the same url neither add a row nor reset the pending mark (pinned:
  "title changes do not push the mark back"). Pref `record_radio`.
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
  LMS's auto-resume on reconnect only). A stop/clear seen before
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

### B. KNOWN-OPEN AND ACCEPTED

- **UNVERIFIED LIVE (2026-09-18).** Installed on plex:9000 since 0.1.0 and Simon
  reports it working in general use; the service badge is verified live (§A2). 1.0.4 (single-track naming)
  built 2026-09-19 and RELEASED to `main` (`v1.0.4`). 1.0.5 (year search + By date years) released to
  `main` (`v1.0.5`) 2026-09-19. 1.0.6 (By release) built on dev and installed 2026-09-19 (Qobuz lookup verified live); 1.0.7
  (Qobuz `epmini` → EP) built and INSTALLED the same day; VERIFIED LIVE: By release = Albums / EPs / Singles,
  the stored EPMINI entry reads as an EP. These specific paths have not been checked individually and are covered by
  the suites only:
  - `Sources::isStation` — any remote non-service url with no duration is a station. Not checked
    against TuneIn, Radio Paradise, BBC Sounds.
  - Station naming from `$track->title`.
  - `_albumNode` for Tidal, Deezer and Spotty (Qobuz is exercised with a stub only).
  - That `newsong` fires on radio title changes with the same url (assumed, and guarded either way).
  - Material rendering of the tiles (`_MTL_icon_` names checked against MaterialIcons.ttf: all
    present), the home shelf, and the search row.

### C. CLOSED FINDINGS

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
├── Plugin.pm      # prefs, CLI (contextmenu/remove), tracker start, home shelf, daily purge
├── Tracker.pm     # newsong/stop/clear subscription, 90% mark, album sessions, stations
├── DB.pm          # SQLite: entries + plays, migration ladder, queries, browse indexes
├── Sources.pm     # describe() a playing track; resolveTracks() an album entry
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
`plugin.listeninghistory`: `played_threshold` (90), `session_gap_min` (30), `record_radio` (1),
`retention_days` (0 = forever). No pref name may start with `_`.

## Regression tests — RUN BEFORE ANY BUILD
```
sh tools/t_all.sh          # one line per suite
V=1 perl tools/t_tracker.pl
```
| suite | protects |
|---|---|
| `t_tracker.pl` | the grouping rules end to end through the real callback + timers: one track, album promotion, A/B/A, stop, same url, gap, two players, skip, pause, Qobuz id grouping, first-credit grouping, Spotty error text, radio once per session (+ the deadline), a web track with no length at start is not timed as radio (skip at 61s of 300 not recorded), removed-mid-album |
| `t_db.pl` | schema stamp + re-open, promote in one transaction, no orphan play on a missing entry, literal `%`/`_` search, indexes, forDay injection, remove/purge cascade, a failed COMMIT reported as failure by addToEntry/remove/purge |
| `t_browse.pl` | shelf exactly 50 and flat and stable, row types, library album = whole album, no-id album = recorded tracks, Qobuz info rows dropped and empty-answer fallback, search dispatch + item_id gate, Yesterday across the spring clock change, album rows read Album over Artist and nothing else, a track row is one line "Title by Artist from Album" (each clause dropped alone; no second line), a station has no second line, By release (type rows in LMS order and names with counts, each opening its releases; library type read LIVE incl. Material's compilation rule, Qobuz type stored; LMS's releaseTypeName preferred) and its tiles (album over artist, the latest play's badge, library control), the service badge (extid) per source, the sort row (cycle, live-pref step, blank last, shelf unaffected, bogus pref), By service (+ the tile, one row per label, Deezer vs Deezer podcasts, http+https merged), the sort row's web-skin bounce, date search (every accepted form, ranges both ways, rejects, inclusive bounds), year search (the Played in row above the text matches, ranges, a numeric name) and By date years (All of + months), context menu + remove, unticked checkbox stores 0 |
| `t_load.pl` | every module loads; every `Plugins::ListeningHistory::X::y` call is defined |

Version history: `docs/VERSION-HISTORY.md`.
