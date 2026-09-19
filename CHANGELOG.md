# Changelog

User-facing release notes, written at each merge to `main`. Per-build engineering notes live in
`docs/VERSION-HISTORY.md`.

## 1.0.7 — 2026-09-19

Browse your history by release, split into albums, EPs and singles the way LMS does.

### Improvements
- **By album is now By release.** It opens *Albums*, *EPs*, *Singles* and *Compilations*, each with a count, and each opens its releases. The names and order are the ones LMS and the Material Skin use for your library.
- **Release types come from the source.** Library releases use the type from your tags, read live, so a retag and rescan moves a release. Qobuz releases use the type Qobuz states, looked up once when you play them. Releases from Tidal, Deezer, Spotify and Bandcamp don't state a type, so they're listed as albums, as Material does.
- **Singles and EPs group like albums.** Play two or more tracks of a single or an EP back to back and they're one entry for that release.

## 1.0.5 — 2026-09-19

Search your history by year, and browse it year by year.

### Improvements
- **Search by year.** Type a year, like `2025`, or a range of years, like `2024 - 2025`. The first result is *Played in 2025*, which opens everything played that year. Your ordinary text matches follow below it, so an album or artist with a year in its name, like *1989* or *The 1975*, still turns up.
- **By date now starts with years.** Under Today and Yesterday there's one row per year, with its count. A year opens *All of 2025*, then its months, and a month opens its days as before.

## 1.0.4 — 2026-09-19

First release. A history of everything you play, on every player, from your library, streaming services and internet radio. A played album is one entry, and every entry plays again.

### Features
- **Albums stay albums.** Two or more tracks from the same album played back to back become one album entry. A single track stays a track entry.
- **Every player, every source.** Every player on the server is recorded. Local files, Qobuz, Tidal, Deezer, Spotify (via Spotty), Bandcamp and internet radio all go into one history.
- **A track counts once 90% of it has played**, or after 60 seconds if it reports no length. Skipped tracks aren't recorded; pausing just delays the count. Both figures can be changed in Settings.
- **Radio is recorded once per listening session**, not once per song title change.
- **Entries look like LMS.** An album shows the album over the artist. A single track reads the way LMS names a favourite track, e.g. *Live By You by Actress from Radical Frame*. On the Default and Classic web skins, an album reads *Album by Artist*.
- **Service badges.** On the Material Skin, an entry from a streaming service carries the service's badge on its artwork. This needs a Material Skin newer than 6.4.9.
- **Plays again.** Tap an entry to play it: the whole album, the track, or the station. If a service can't provide the full album, the tracks you actually heard play in the order you heard them.
- **Material home shelf.** A *Listening History* row shows your latest 50 entries.
- **Look further back.** Browse by date, artist, album, service or player. Search by text, a date, or a date range (day first, e.g. `01/09/2026 - 15/09/2026`).
- **Sort any list** by date, artist A–Z or album A–Z. Your choice is remembered.
- **Remove an entry** from its … menu.
- **Its own database.** History survives restarts, and you choose how long it's kept (forever by default).
