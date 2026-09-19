# Changelog

User-facing release notes, written at each merge to `main`. Per-build engineering notes live in
`docs/VERSION-HISTORY.md`.

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
