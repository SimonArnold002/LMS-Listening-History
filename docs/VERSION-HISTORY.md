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
