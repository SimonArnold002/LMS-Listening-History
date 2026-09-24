# Listening History — LMS Plugin

A plugin for **Lyrion Music Server (LMS)** that keeps a full history of what you've played, on **every player**, from your **local library** and from **streaming services** (Qobuz, Tidal, Deezer, Spotify and others), plus Radio Paradise song by song. Play a whole album and it's logged as **one album**, not a dozen separate tracks. Play one track and it's logged as that track. Every entry plays again with one tap, streaming ones included.

Tested on LMS 9.x with the **Material Skin**.

---

## Features at a glance

| Feature | What it gives you | Needs |
|---|---|---|
| **Albums stay albums** | Two or more tracks of the same release played back to back become one entry, whether it's an album, an EP or a single | Nothing |
| **Every player** | Every player on the server is recorded; browse by player to see what played where | Nothing |
| **Library and streaming** | Local files and any streaming service, in one history | The service's own plugin |
| **Looks like LMS** | An album reads album over artist, a single track reads track and album over artist, and streaming entries carry the service's badge on the artwork | Badge: a Material Skin newer than 6.4.9 |
| **Plays again** | Tap an entry to play it: a whole album or the single track | The service's own plugin |
| **Material home shelf** | A *Listening History* row of your latest 50 entries on the home screen | Material Skin |
| **Look further back** | Browse by date, artist, release, service or player, or search by text, a date, a year or a range of either | Nothing |
| **Sort any list** | Newest first, artist A–Z or album A–Z | Nothing |
| **Keeps up with your library** | After a rescan, retag or move, library entries find their album again and take its current names | Nothing |
| **Radio Paradise too** | Each song is logged as a track, with its title and artist | The Radio Paradise plugin |
| **Its own database** | Nothing is lost when the server restarts, and you choose how long to keep it | Nothing |

---

## Requirements

- **Lyrion Music Server 9.0.0+**. The home shelf needs the **Material Skin**.
- To replay **streaming** entries, the matching service plugin installed and signed in.

---

## Installation

Add this repository URL under **Settings → Plugins → Additional repositories**:

```
https://simonarnold002.github.io/LMS-Listening-History/repo.xml
```

Then install **Listening History** from the plugin list and restart the server.

---

## Using it

### What gets recorded

- **A track counts once 90% of it has played.** A track that reports no length counts after 60 seconds. Skip a track before then and it isn't recorded; pause it and the count simply waits. Podcast episodes and other web tracks follow the same rule, even when their length only becomes known after they start.
- **Back-to-back tracks from one album become one album entry.** The first track appears as a track; as soon as a second track from the same album plays, the entry turns into an album and its count goes up with every further track.
- **A new album, a stop, or a cleared queue starts a new entry.** So does a gap longer than 30 minutes between two tracks. Time spent paused doesn't count towards that gap, so a long pause doesn't split an album.
- **A server restart doesn't split anything.** If an album carries on after the server restarts, it stays one entry, and a track already counted isn't counted again.
- **Internet radio stations aren't recorded.** Radio Paradise is the exception: it names every song, so each song is recorded as a track once 90% of it has played. Station entries recorded by an earlier version stay in your history and still play.

### When your library changes

A rescan, a retag or moving files can give an album a new place in LMS's library. Library entries follow it:

- **Each entry finds its album again** the way LMS finds a favourite: by the album's MusicBrainz id where your files have one, otherwise by the files you played, otherwise by the album and artist name. Tapping it plays the whole album again, and it stays under the right type in *By release*.
- **Names follow the library.** An album entry takes the album's current title, artist and year; a track entry also takes its track's current title and artist. The tracks recorded inside an entry keep the names you heard them under.
- **Every library entry is checked shortly after each rescan finishes**, and two minutes after the server starts. An entry you open is checked straight away. Until then, an entry whose album moved may show its old name and a blank cover.

### Browsing

Open **My Apps → Listening History**:

| Menu | What it shows |
|---|---|
| **Recently played** | Your latest 50 entries, the same as the home shelf |
| **Search history** | Anything whose artist, album, track title or player name matches, including tracks played inside an album. Type a **date**, a **year** or a range of either to see what was played then (see below) |
| **By date** | Today, Yesterday, then each year → *All of* the year, or a month → day |
| **By artist** | Every artist you've played, with a count |
| **By release** | Your releases split by type, the way LMS does: *Albums*, *EPs*, *Singles*, *Compilations*. Each opens its releases, with the service badge of the latest play. Library releases use the type from your tags; Qobuz states its own. Releases from other services are listed as albums |
| **By service** | Library, Qobuz, Spotify, Radio Paradise and so on, each with its own history |
| **By player** | Each player, with its history |

Rows read the way LMS shows any release:

- **Album**: the album, with the artist underneath. The Default and Classic web skins show it on one line, *Album by Artist*.
- **Track**: the track and its album, with the artist underneath, e.g. *Live By You from Radical Frame* over *Actress*. The Default and Classic web skins show it on one line, the way LMS names a favourite track: *Live By You by Actress from Radical Frame*.
- **A station** recorded by an earlier version: the station's name.

On the Material Skin, an entry from a streaming service carries that service's badge on its artwork; library entries have none, as in Material's own library lists. The badge needs a Material Skin newer than 6.4.9. Which player an entry played on and when aren't shown on the row: use **By player**, **By date** or a date or year search.

Every list starts with a **Sorted by** row: tap it to switch between *date* (newest first), *artist A–Z* and *album A–Z*. The choice is remembered. The home shelf always shows the newest first.

### Searching by date or year

Dates are **day first**. Any of these find everything played on 18 September 2026:

`18/09/2026` · `18-09-2026` · `18.09.2026` · `18/9/26` · `2026-09-18` · `18 Sep 2026` · `18 September 2026`

For a **range**, put two dates either side of ` - ` or ` to `. For example, `01/09/2026 - 15/09/2026` lists everything from the 1st to the 15th, both days included. A date that doesn't exist, like `31/02/2026`, is searched as ordinary text.

Type a **year**, like `2025`, or a range of years, like `2024 - 2025`, and the first result is **Played in 2025**, which opens everything played that year. Below it are the ordinary text matches, so an album or artist with a year in its name, like *1989* or *The 1975*, still turns up.

### Playing an entry

- **Album**: plays the whole album. If the library or service can't provide the full album (Deezer and some others don't identify albums during playback), it plays the tracks you actually heard, in the order you heard them.
- **Track**: plays that track.
- **A station** recorded by an earlier version: plays the station.

Use the row's **… → More → Remove from history** to delete an entry.

---

## Settings reference

| Setting | Default | What it does |
|---|---|---|
| Track counts as played at | 90 % | How much of a track must play before it's recorded |
| Album session gap | 30 minutes | The longest pause between two tracks that still groups them into one album |
| Keep history for | 0 days (forever) | Entries older than this are removed once a day |

---

## Notes & limitations

- **History starts when the plugin is installed.** Nothing is imported from before then.
- **Bandcamp albums replay as the tracks you heard**, because a playing Bandcamp track doesn't tell us which album page it came from.
- **Search is case-insensitive for plain letters only** (A–Z). Accented letters and other scripts match with exact case.
