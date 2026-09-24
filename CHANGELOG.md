# Changelog

User-facing release notes, written at each merge to `main`. Per-build engineering notes live in
`docs/VERSION-HISTORY.md`.

## 1.0.19 — 2026-09-24

Radio Paradise's station breaks no longer appear in your history.

### Fixes
- **Radio Paradise breaks aren't recorded.** The station break (*Listener-supported* by *Commercial-free*) and DJ announcements on an interactive stream were being recorded as songs. They're now skipped, using the Radio Paradise plugin's own rule for spotting them. The songs either side are recorded as usual. Breaks already in your history stay until you remove them (… → Remove from history).
- **The Album session gap setting now says that time spent paused doesn't count**, which has been true since 1.0.18.

## 1.0.18 — 2026-09-24

Your history now keeps up with your library, a pause no longer splits an album, and Radio Paradise records every song.

### Improvements
- **Library entries find their album again after a rescan.** After *Clear library and rescan*, a retag or moving your files, an album gets a new place in LMS's library. Before, its entry could then only replay the tracks you'd heard, and an EP or single moved under *Albums*. Now the entry finds its album the way LMS finds a favourite: by the album's MusicBrainz id where your files have one, otherwise by the files you played, otherwise by album and artist name. Your existing history is kept and nothing is merged or deleted.
- **Names follow your library.** Retag an album and its entries take the new title, artist and year. A track entry also takes its track's new title and artist. The tracks recorded inside an entry keep the names you heard them under.
- **Checked after every rescan.** Every library entry is checked shortly after each rescan finishes, and two minutes after the server starts, so the changes appear without you opening anything. An entry you open is checked straight away.
- **Radio Paradise is recorded song by song**, each song a track with its own title and artist. This needs one of the plugin's interactive streams: the regular streams have no song lengths, so they're treated as an ordinary station and not recorded.

### Fixes
- **A pause no longer splits an album.** Time spent paused doesn't count towards the 30-minute gap. A streaming track paused part way through still counts once the rest has played, instead of being lost.
- **Radio Paradise no longer misses songs.** A song shorter than the one before it was never recorded, because its length wasn't known yet when it started.
- **Streaming tracks that report their length late are counted at 90%**, instead of after 60 seconds.

### Changes
- **Internet radio stations are no longer recorded**, and the *Record internet radio* setting has gone. Radio Paradise's interactive streams are the exception. Station entries already in your history stay there and still play.

## 1.0.14 — 2026-09-21

A server restart no longer splits your history, and track entries show the right title and artist.

### Improvements
- **Track entries show their artist on the Material Skin.** A single track now reads *Title from Album*, with the artist underneath, the same way an album entry shows its artist. Before, the one long line was cut off before the artist. The Default and Classic web skins still show one line, *Title by Artist from Album*.

### Fixes
- **A server restart isn't a new listen.** If an album carries on after the server restarts, it stays one entry, and a track already counted before the restart isn't counted again.
- **A track resumed part way through is still recorded.** A local track that picks up where it left off after a restart counts once the rest of it has played.
- **Replayed streaming tracks keep their own title.** Playing a streaming track again from a favourite or from your history no longer records the whole row name, like *Title by Artist from Album*, as its title.
- **Web tracks with " - " in their name keep their title.** A podcast episode or other web track called, say, *Episode 12 - The Big One* is recorded under that full name, and *Episode 12* is no longer stored as its artist.

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
