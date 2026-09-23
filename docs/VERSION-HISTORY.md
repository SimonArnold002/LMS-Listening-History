# Version History

Per-build engineering notes, oldest first. Append new entries at the end. User-facing notes go in
`CHANGELOG.md` at the merge to `main`.

## 0.1.0 — 2026-09-18 (dev, not built)

First version. Built from the plan agreed 2026-09-18.

- `Tracker.pm`:
  - Subscribes to `playlist newsong/stop/clear` on every player.
  - A track is recorded at `played_threshold`% (default 90), or after 60s with no duration. The
    mark is re-checked against `songElapsedSeconds`, and the next `newsong` cancels it.
  - Tracks are grouped per player into a session keyed by `album_key`: the second track of the
    same album promotes the entry to kind `album`.
  - A session ends on stop, on clear, on a different album, on a repeated url, or after
    `session_gap_min`.
  - Radio: one `station` entry per session. Title-change `newsong`s on the same url are ignored
    and do not reset the pending mark.
- `DB.pm`:
  - `entries` + `plays` tables, `SCHEMA_VERSION` 1.
  - Every list is ordered `played_at DESC, id DESC`.
  - Search escapes `%`, `_` and `\`.
  - Remove and purge delete an entry's plays in the same transaction.
- `Sources.pm`:
  - `describe` handles the library (album id, contributor, artwork, live track count) and remote
    tracks (`getMetadataFor`, service album id: Qobuz `albumId`, Tidal `album_id`, Spotify via
    Spotty's `trackCached`).
  - A service track with no duration is refused (the Spotty error-text guard).
  - `resolveTracks`: the whole album where the library or service can rebuild it, otherwise the
    recorded plays.
- `Browse.pm`: Recently played, Search, By date / artist / album / player, and Settings. Album
  rows are `playlist`; track and station rows are `audio`.
- `HomeExtras.pm`: `LHHome`, the latest 50 entries, flat.
- Tests: `t_db`, `t_tracker`, `t_browse`, `t_load`, 149 assertions, all passing.
  - Anti-tested: 12 of 13 deliberate mutations turn a suite red.
  - The one that stays green is removing the `id DESC` tie-break. The `entries_played` index
    already returns that order, so no test can tell the difference; the tie-break stays so the
    order is guaranteed rather than incidental.

## 0.1.1 — 2026-09-18 (dev, installed locally)

- The Material home shelf is titled **Listening History** (`PLUGIN_LH`), not "Recently played" —
  Simon, 2026-09-18: Material has its own Recently Played section and the two would be confused.
  The in-app "Recently played" menu tile keeps its name.
- 0.1.0 installed and working on plex:9000 (Simon).

## 0.1.2 — 2026-09-18 (dev, installed locally)

Three findings from a whole-plugin `/code-review`. Each had a failing test first; 6 assertions
were red before the fixes.

- **`DB::addToEntry` / `remove` / `purge` reported success on a failed COMMIT.** The result was
  set inside the transaction body, before commit, and returned regardless of `_txn`. A locked or
  busy database therefore rolled back the write while `Tracker::_record` believed it. The
  session then marked the track as heard, and the play was lost. All three now return
  `_txn(...) or return 0`. Pinned in `t_db.pl` by overriding `DBD::SQLite::db::commit` to die.
- **The tracker and `describe` disagreed about what a station is.** `_onChange` decided from
  `$song->duration` alone, while `describe` also read the handler's duration. A remote http track
  whose length was unknown at `newsong` (a podcast episode) was timed like radio, a flat 60s, and
  then recorded as a track, so a skip at 61s counted. Fixed two ways:
  - `Tracker::_duration` reads both sources in `describe`'s order.
  - `_markTick` re-checks a "station" whose length has since become known, and hands it to the
    90% rule.
  - Pinned in `t_tracker.pl`: the handler knows the length at the start; and the song learns it
    later, with a skip at 61s of 300.
- **"Yesterday" was now-minus-86400**, which is two days back just after midnight on the day
  after the clocks go forward. It is now counted from midday today (`Browse::_middayToday`).
  Pinned in `t_browse.pl` at 2026-03-30 00:30 Europe/London.
- Test harness: `TestClock::now()`. A test file is compiled before `t_stubs.pl` installs the
  `CORE::GLOBAL::time` override, so `time()` INSIDE a test reads the real clock while the plugin
  reads the offset one. That made the first podcast assertion pass against the bug; the
  assertion now uses `TestClock::now()`.

## 0.1.3 — 2026-09-18 (dev, installed locally)

Simon's requests: search by exact date, a date and time on every row, and filtering by service
and sorting by album, artist or date. The shape of each was asked first (see CLAUDE.md A2
`DATES, SERVICE MENU, SORT`).

- `Browse::_when`: always `18 Sep 2026, 14:32`. Before this, today showed only `14:32` and
  this year omitted the year. No day of the week.
- **By service** menu: `DB::services` / `forSource`, labelled with `Sources::sourceLabel`.
- **Sorted by** row on every entry list: date / artist A–Z / album A–Z, pref `sort`.
  `sortEntries` does the ordering in Perl on lists already capped at `LIST_CAP`. The home shelf
  is unchanged.
- **Date search**: `parseDateSearch` takes a single day or a range, day-first, and queries
  `DB::forRange`. Any other term is a text search, as before.
- Tests 162 → 205. (Reported at the time as 206, a miscount: `t_browse` was 74, not 77. Nothing
  was skipped. Corrected 2026-09-18 by the second review round.)
  - Mutation-checked: weekday re-added, sort pref ignored, range end exclusive, impossible
    dates accepted, blank names not last, a captured (stale) sort value, and the By service tile
    removed. Each turns `t_browse` red.
  - The tile check was added after the first run of that mutation stayed green.

## 1.0.0 — 2026-09-18 (dev; Simon: "this is locked")

The feature set is locked at 1.0.0. The only code changes since 0.1.3 are the second review
round's two fixes (CLAUDE.md §C):
- **By service labels.** `deezerpodcast` is now "Deezer podcasts", not a second "Deezer" row.
  `http` and `https` are both "Web stream". `Browse::_services` makes one row per LABEL, with
  `sources => [...]` in its passthrough, and `DB::forSource` accepts a list.
- **Sorted by row on the Default / Classic web skins.** Those skins have no `nextWindow`, so the
  empty answer opened a blank page. `_webSkin($args)` now answers with `_webBounce` (Pitchfork's
  rule, copied), which returns the browser to the re-sorted list. New string `PLUGIN_LH_WEB_BACK`.
- Tests 205 → 214, each fix mutation-checked.
- Ledger: back-fill from LMS's play data DECLINED; the logo stays `music_history`.
- `repo.xml` is left untouched (still 0.1.0, empty sha) until Simon publishes, as agreed.

## 1.0.1 — 2026-09-18 (dev) — service badge

- `Sources::extid` and the row's `extid`: Material's service badge (upstream `d3f1d9227`). See
  CLAUDE.md `THE SERVICE IS A BADGE`.
- `entryRow` line2 drops the service name, "Library" included.
- Tests 214 → 230. Mutation-checked: the row's extid removed, the service name put back in line2,
  no `sounds`→`bbc`, no url-scheme fallback, no real album extid, and no `deezerpodcast` map. Each
  turns `t_browse` red.

## 1.0.2 — 2026-09-19 (dev) — rows read like a release

- `entryRow`: the album (a track: its title; a station: its name) over the artist, nothing else.
  The `Artist – ` prefix, glyphs, "N of M tracks", "from <album>", player and date/time are gone
  from the row; the data is still stored and the sort row still orders by it. See CLAUDE.md
  `A ROW READS LIKE A RELEASE`.
- By album tiles (`_albums`): album over artist, no count, and the service badge of the group's most
  recent play (`DB::albums` returns `last_id`). Found from Simon's screenshot: those tiles had no badge.
- Removed: `_join`, `_when`, `SEP`, `DASH`, `GLYPH_*` and six unused strings.
- Tests 230 → 235 (t_browse 98 → 103; the old date/count assertions replaced). Mutation-checked:
  a tail on line2, an "Artist – Album" name, the oldest play badged, and the tile badge dropped each
  turn `t_browse` red.
- Zip sha `321c3ecb2481b1b0f2f4bcee9ffc68f5893f5126`. `repo.xml` still untouched.

## 1.0.3 — 2026-09-19 (dev) — web skins keep the artist

- Review of `e70f803` (1.0.2): on the Default / Classic web skins, which draw `name` only, rows
  and By album tiles had lost the artist. `Browse::_titled` now gives a release row `name` =
  "Album by Artist" (core string `BY`) plus `line1` / `line2` for Material, which LMS sends as
  line1 over line2 — Material is unchanged. See CLAUDE.md `THE WEB SKINS KEEP THE ARTIST IN THE NAME`.
- Tests 235 → 240 (t_browse 103 → 108). Anti-tested: web name without the artist 3 red; `line1`
  dropped 17 red.
- BUILT as 1.0.3, zip sha `66d5db43259538a9b70b63a7b20999d9388a7144`. `repo.xml` still untouched.

## 1.0.4 — 2026-09-19 (dev) — a single track is named like LMS names one

- `Browse::_trackName`: a `track` row is ONE line, "Title by Artist from Album" (core strings `BY` /
  `FROM`), exactly as LMS names a favourite track (Simon's Qobuz favourite: `Live By You by Actress
  from Radical Frame`). No line1/line2, so Material and the web skins show the same text. A missing
  artist or album drops its clause. Album rows and stations unchanged. See CLAUDE.md
  `A SINGLE TRACK IS NAMED LIKE LMS NAMES ONE`.
- A misplaced comment moved back above `_entryTracks`.
- Tests 240 → 242 (t_browse 108 → 110). Anti-tested: no FROM clause 4 red; track rows on `_titled` 5 red.
- Zip sha `202b50fc7ae556c6a96b4967c0cee6435e3333eb`. `repo.xml` still untouched.

## 1.0.5 — 2026-09-19 (dev) — search and browse by year

- `Browse::parseYearSearch`: `2025` or `2024 - 2025`. `_searchResults` puts a "Played in 2025 (n)" row
  (`_rangeLink` → `_range`) above the text matches, so a name like *1989* is still found. See CLAUDE.md
  `A YEAR IS ALSO A NAME`.
- By date: Today, Yesterday, then years (`_dates`, `DB::years`); a year opens "All of 2025 (n)" then its
  months (`_months`, `DB::months($year)`).
- `DB::countRange`. Strings `PLUGIN_LH_PLAYED_IN`, `PLUGIN_LH_ALL_OF`.
- Tests 242 → 276 (t_browse 110 → 135, t_db 44 → 51, t_load 37 → 39). Six mutations, each red.
- Zip sha `2d57ecf390544455753069b71c51820c33daf451`. README text for this waits for the merge to `main`.

## 1.0.6 — 2026-09-19 (dev) — By release, broken down like LMS

- **By album is now By release**: one row per release type (Albums / EPs / Singles / Compilations …,
  LMS's names, Material's order) with its count, each opening its release tiles. See CLAUDE.md
  `BY RELEASE, BROKEN DOWN LIKE LMS`. Grouping of plays is unchanged: a two-track single or an EP played
  through is one entry.
- `Sources::releaseType` (library live from `albums.release_type` + the compilation rule; Qobuz stored;
  else ALBUM), `releaseTypeLabel` (LMS's `releaseTypeName` first), `sortReleaseTypes`,
  `fetchReleaseType` (Qobuz `getAlbum`, once per album per run). `DB::setReleaseType`. `Tracker` asks
  after recording a Qobuz play. String `PLUGIN_LH_BY_ALBUM` → `PLUGIN_LH_BY_RELEASE`.
- Tests 276 → 317 (t_browse 135 → 149, t_db 51 → 57, t_load 39 → 44, t_tracker 51 → 67). 11 mutations,
  each red.
- Zip sha `41b4d1a9e03bce2ca984d88870efb713c0f61e67`. README / CHANGELOG wait for the merge to `main`.

## 1.0.7 — 2026-09-19 (dev) — Qobuz EPs

- Live on 1.0.6, a Qobuz EP showed as its own "Epmini (1)" type: Qobuz's album object says `epmini` for an
  EP. `Sources::_normType` maps EPMINI → EP on every read (`%TYPE_ALIAS`), which also fixes the entry
  already stored. Tests 317 → 318; the tracker's fake Qobuz now answers with Qobuz's real spellings.
- Zip sha `775fcef641e9940638d1f1313b9cd70e4ccebf67`.

## 1.0.8 – 1.0.9 — 2026-09-21 (dev, `5bc5376`) — a server restart is not a new listen

- Reported by Simon: after a server restart, resuming from Now Playing logged the play twice. `%session` /
  `%pending` were memory only, so the resumed album became a second entry and a track counted before the
  restart could be counted again.
- `Tracker::_restore`: the FIRST `newsong` per player after `init` (`%restored`) rebuilds that player's
  session from its last entry (`DB::forPlayer($cid, 1)`, which now takes a limit) when it ended within
  `session_gap_min`, with `resumed_url` = the last play's url. `_record` drops the first counted play if it is
  that url. A stop or clear seen before that first `newsong` does not cancel the restore (what LMS sends around a
  restart is unmeasured; the gap decides).
- 1.0.9 (first review): dropping the resumed track also sets `last_at` to now, or a long track heard again after
  the restart split the album on the gap.
- Tests: `t_tracker` 70 → 86 (the restart block; 10 red on the old Tracker, controls green).
- Zip sha (1.0.9) `28345d2eba5cc73f12606783f517072a6f0a6d03`. 1.0.8 was built and superseded before install.

## 1.0.10 — 2026-09-21 (dev, `fa43460`) — superseded

- Second review: a track resumed part way through ended before a full-length mark and was never recorded.
  1.0.10 armed the mark for `target - $client->songElapsedSeconds`. This was a NO-OP: LMS counts
  `songElapsedSeconds` from the start of the STREAM, and the test passed only because the stub counted from the
  start of the track. Replaced in 1.0.11.
- Zip sha `7fd1d4544b10810eb9cae410f9ac153af65bb9b4`.

## 1.0.11 — 2026-09-21 (dev, `b720356`) — a local track resumed after a restart is recorded

- On the first `newsong` per player after startup only, the song's `startOffset` (the resume point) comes off
  the 90% target. `_markTick` stays stream-relative, so everywhere else a seek must still be listened through
  (a seek also fires `newsong`).
- The tracker stub now models LMS: `songElapsedSeconds` per stream, `startOffset` on the song.
- LMS 9.1 source facts behind it are in CLAUDE.md `A RESTART IS NOT A NEW LISTEN`.
- VERIFIED LIVE on HQPlayer (ManCave), local FLAC: the album carried on across a restart as one entry. The
  `startOffset` path was not exercised live (the track restarted from the top on that player).
- Tests: `t_tracker` 86 → 92 (local resume at 80%, red on 1.0.10; seek-to-95% control; streaming restart
  from the top).
- Zip sha `7460a39f45b4f4e892d7b0ac71016ad8115e6674`.

## 1.0.12 — 2026-09-21 (dev, `af195e6`) — service titles; a track row shows its artist

- Live: three Qobuz rows read "Pylon by beabadoobee from Pylon by beabadoobee from Pylon". LMS stores the name
  of the row a track was started from as its title, and our own track rows (and LMS favourites) are named
  "Title by Artist from Album". `Sources::describe` now takes the handler's title first for a remote track.
  The three bad rows were removed by hand; a repair migration was offered and declined.
- Simon: a single-track row on Material is now "Title from Album" over the artist (`Browse::_trackName` gives
  `line1` / `line2`); the web skins keep "Title by Artist from Album" in `name`.
- Tests: `t_tracker` 92 → 95, `t_browse` 150 → 154 (8 red on the one-line row).
- Zip sha `c63ea6b2e4382c9f4c31b4da9653c959f64efc2d`.

## 1.0.13 – 1.0.14 — 2026-09-21 (dev, `0053471`) — a plain web track keeps its own title and artist

- 1.0.13 (review of 1.0.12): a plain `http(s)` track keeps `$track->title` first again. LMS's own HTTP handler
  builds its title from the row name and splits exactly one " - " into artist and title, so "Episode 12 - The
  Big One" was being recorded as "The Big One". Every plugin handler still comes first.
- 1.0.14: the same split also stored the front half as the ARTIST (older than 1.0.12). `Sources::_isSplit` drops
  the handler's artist when its artist and title rejoin to the track's own title; a real stream artist is kept.
- Tests: `t_tracker` 95 → 98. Totals 323 (start of 2026-09-21) → 355 (t_browse 154, t_db 57, t_load 46, t_tracker 98).
- Zip sha `29fd895040cdcb5c83264fef54dcc9fa4a7cf5d5`. CHANGELOG / README wait for the merge to `main`.

## 1.0.15 — 2026-09-23 (dev, uncommitted) — pauses, song lengths learnt late, radio

Four reports from Simon, one build. Ledger: `A PAUSE IS NOT A GAP`, `THE LENGTH IS READ AT EVERY CHECK`,
`RADIO IS NOT RECORDED`, `A RESTART IS NOT A NEW LISTEN`.
- Pause: `Tracker` subscribes to `playlist pause`. The time paused no longer counts towards the session gap
  (`_unpause`), and a paused streaming track that LMS re-streams from the pause point (a `newsong` on the same
  url) keeps its mark, owing only what is left (`from` = `startOffset`, `_owed`). Was: Gia Margaret *Singing*
  logged twice, the paused track in neither entry.
- Length: `Sources::trackDuration` reads a remote track's length from its handler first; `_markTick` re-reads it
  at every check and recomputes the target. A service track with no length yet waits rather than counting at
  60s. Was: Radio Paradise songs shorter than 90% of the song before were never recorded (every song on one
  url, LMS holding the previous length), and a queued streaming track with no length at its start was counted
  at 60s.
- Restart: the resumed-play drop also compares the title (`resumed_title`), for Radio Paradise's shared url.
- Radio: stations are no longer recorded; `record_radio`, its settings row and three strings removed. Radio
  Paradise is recorded song by song as before.
- Tests: `t_tracker` 98 → 123 (shuffle, pause ×10, length ×2, RP ×6, radio rewritten); `t_browse` 154 (the
  checkbox test replaced by a pref-gone check). 18 red on 1.0.14; mutations each red (clock shift 8, length
  order 7, title check, mark kept 2). Totals 380.
- Zip sha `de3bf3ec9504a50f0a9095f1a3f210103de5fb0f`. CHANGELOG / README wait for the merge to `main`.
