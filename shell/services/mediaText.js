.pragma library
// What a player's track is called, for people. Browsers pass the page title
// through MPRIS untouched ("Watch Pirates Of The Caribbean: … - JioHotstar",
// "Song (Official Video) - YouTube"), and their name ("Mozilla zen") is not
// where the thing is playing: the site is.
//   cleanTitle(title, url)  → "Pirates Of The Caribbean: The Curse Of The Black Pearl"
//   siteName(url)           → "JioHotstar" (known hosts) / "hotstar.com" / ""

const SITES = {
    "hotstar.com": "JioHotstar", "youtube.com": "YouTube", "youtu.be": "YouTube", "music.youtube.com": "YouTube Music",
    "netflix.com": "Netflix", "primevideo.com": "Prime Video", "amazon.com": "Prime Video", "disneyplus.com": "Disney+",
    "twitch.tv": "Twitch", "spotify.com": "Spotify", "soundcloud.com": "SoundCloud", "vimeo.com": "Vimeo",
    "crunchyroll.com": "Crunchyroll", "max.com": "Max", "hulu.com": "Hulu", "apple.com": "Apple TV",
    "jiocinema.com": "JioCinema", "sonyliv.com": "SonyLIV", "zee5.com": "ZEE5", "bandcamp.com": "Bandcamp",
};

function host(url) {
    const m = String(url || "").match(/^[a-z][a-z0-9+.-]*:\/\/([^/?#:]+)/i);
    return m ? m[1].toLowerCase().replace(/^www\./, "") : "";
}

function siteName(url) {
    const h = host(url);
    if (!h || h === "localhost" || /^[\d.]+$/.test(h)) return "";
    if (SITES[h]) return SITES[h];
    const parts = h.split(".");
    for (let i = 1; i < parts.length - 1; i++) {
        const tail = parts.slice(i).join(".");
        if (SITES[tail]) return SITES[tail];
    }
    return parts.slice(-2).join(".");
}

function cleanTitle(title, url) {
    let t = String(title || "").replace(/\s+/g, " ").trim();
    if (!t) return "";
    const site = siteName(url);
    // " - JioHotstar", " | Netflix", " – YouTube", "· Twitch": the site's own name at the end.
    const names = [site, "YouTube", "YouTube Music", "Netflix", "JioHotstar", "Hotstar", "Disney+ Hotstar", "Prime Video", "Twitch", "Spotify", "SoundCloud", "Vimeo", "Crunchyroll"]
        .filter(x => x).map(x => x.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
    if (names.length) t = t.replace(new RegExp("\\s*[-|–—·:]\\s*(" + names.join("|") + ")\\s*$", "i"), "");
    // "Watch …" / "Watch … Online" (streaming sites' page titles).
    t = t.replace(/^watch\s+(?=\S)/i, "").replace(/\s+(online|full movie|full episode|full hd)(\s+(free|in hd))?\s*$/i, "");
    // Unread counts browsers prepend: "(3) Song".
    t = t.replace(/^\(\d+\)\s+/, "");
    // Video noise in music titles.
    t = t.replace(/\s*[([](official\s+(music\s+)?video|official\s+audio|official\s+lyric\s+video|lyric\s+video|lyrics|audio|visualizer|hd|4k)[)\]]/ig, "");
    return t.trim() || String(title || "").trim();
}

// The second line under a title: who made it, else where it plays, else the player.
function subtitle(artist, url, identity) {
    return String(artist || "").trim() || siteName(url) || String(identity || "").trim();
}
