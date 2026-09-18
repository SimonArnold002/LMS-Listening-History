# Listening History — LMS Plugin

## Project Overview
A plugin for Lyrion Music Server (LMS) that records a play history across EVERY player, for
local library files, streaming services (Qobuz, Tidal, Deezer, Spotify via Spotty, anything
else with a protocol handler) and internet radio. A played album is ONE entry, not one per
track; a lone track is a track entry; a station is a station entry. Every entry plays again,
streaming included. Material home shelf of the latest 50 entries; app menu to look back by date,
artist, album, service, player, or search by text, date or date range; every list sortable. Stores its own SQLite DB. Targets LMS 9.x, Material
Skin preferred. Built 2026-09-18 from Simon's brief, in the shape of Listen Later / LBF / PFR.

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
| row date `Browse::_when`, By service menu, sort row `_sortRow`/`sortEntries`, date search `parseDateSearch` | **DECIDED by Simon 2026-09-18** (0.1.3) | `DATES, SERVICE MENU, SORT` |
| home shelf title `PLUGIN_LH`, not "Recently played" | **DECIDED by Simon 2026-09-18**: avoids confusion with Material's own Recently Played | `SHELF TITLE` |
| `Sources::albumKey` name fallback, `primaryArtist` | deliberate: first credit only | `THE NAME KEY USES THE FIRST CREDIT` |
| Bandcamp album replay = recorded tracks | deliberate, no album page url at play time | `BANDCAMP REPLAYS WHAT WAS HEARD` |
| replay code copied from LL, not shared | deliberate | `COPIED, NOT SHARED` |
| `ORDER BY … id DESC` tie-break untestable | known; index gives the same order | `THE TIE-BREAK CANNOT BE PINNED` |
| `LIST_CAP` 1000 per browse list | deliberate, and says so on the list | `LIST_CAP` |
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
- Stale zip / `repo.xml <sha>` on `dev`: recomputed at build time with the version bump. The sha
  is EMPTY until the first build.
- `CHANGELOG.md` / `README` are written at the MERGE TO MAIN.
- Uncommitted = under review; unpushed = review not passed. Never prompt to commit or push.

### A2. NOT FINDINGS — Listening History specific

- **2+ TRACKS = AN ALBUM — Simon, 2026-09-18.** `Tracker::_record` promotes a track entry to kind
  `album` on the SECOND track from the same `album_key`, heard back to back on one player. Not a
  percentage of the album. The row says "N of M tracks" when the total is known (library: live
  count), "N tracks" otherwise. Offered alternatives (a % threshold; "queue matches the album")
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
  - Every row's line2 ends with the full date and time, `18 Sep 2026, 14:32`, today included.
    There is NO day of the week (asked for). `Browse::_when`.
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
- **MORE BY THIS ARTIST** was in the plan's context menu and was dropped at build time to keep
  the menu to one CLI action; By artist already lists the same rows. It would need a `go` into a
  query that returns rows (LL's `buy` shape). Re-add only if Simon asks. The menu holds Remove
  only.

### B. KNOWN-OPEN AND ACCEPTED

- **UNVERIFIED LIVE (2026-09-18).** 0.1.0 is installed on plex:9000 and Simon reports it working
  in general use. These specific paths have not been checked individually and are covered by
  the suites only:
  - `Sources::isStation` — any remote non-service url with no duration is a station. Not checked
    against TuneIn, Radio Paradise, BBC Sounds.
  - Station naming from `$track->title`.
  - `_albumNode` for Tidal, Deezer and Spotty (Qobuz is exercised with a stub only).
  - That `newsong` fires on radio title changes with the same url (assumed, and guarded either way).
  - Material rendering of the tiles (`_MTL_icon_` names checked against MaterialIcons.ttf: all
    present), the home shelf, and the search row.

### C. CLOSED FINDINGS

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

**Review round 2026-09-18 (0.1.3, second round) — CLOSED, two findings, both FIXED (unbuilt,
next build).**

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
| `t_browse.pl` | shelf exactly 50 and flat and stable, row types, library album = whole album, no-id album = recorded tracks, Qobuz info rows dropped and empty-answer fallback, search dispatch + item_id gate, Yesterday across the spring clock change, full date+time on every row (today too), the sort row (cycle, live-pref step, blank last, shelf unaffected, bogus pref), By service (+ the tile, one row per label, Deezer vs Deezer podcasts, http+https merged), the sort row's web-skin bounce, date search (every accepted form, ranges both ways, rejects, inclusive bounds), context menu + remove, unticked checkbox stores 0 |
| `t_load.pl` | every module loads; every `Plugins::ListeningHistory::X::y` call is defined |

Version history: `docs/VERSION-HISTORY.md`.
