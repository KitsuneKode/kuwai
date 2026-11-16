// Track titles and sources for people (shell/services/mediaText.js).
//   bun test tests/shell/media-text.test.mjs
import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";

const lib = readFileSync(new URL("../../shell/services/mediaText.js", import.meta.url), "utf8").replace(/^\.pragma library\s*$/m, "");
const { cleanTitle, siteName, subtitle } = new Function(lib + "\nreturn { cleanTitle, siteName, subtitle };")();

const hot = "https://www.hotstar.com/in/movies/pirates-of-the-caribbean-the-curse-of-the-black-pearl/1660010115/watch";

describe("siteName", () => {
    test("known hosts get their brand", () => {
        expect(siteName(hot)).toBe("JioHotstar");
        expect(siteName("https://www.youtube.com/watch?v=x")).toBe("YouTube");
        expect(siteName("https://music.youtube.com/watch?v=x")).toBe("YouTube Music");
        expect(siteName("https://www.netflix.com/watch/1")).toBe("Netflix");
    });
    test("unknown hosts keep their domain; local ones say nothing", () => {
        expect(siteName("https://cdn.example.org/a.mp4")).toBe("example.org");
        expect(siteName("http://localhost:3000/")).toBe("");
        expect(siteName("file:///home/x/a.mkv")).toBe("");
        expect(siteName("")).toBe("");
    });
});

describe("cleanTitle", () => {
    test("streaming page titles lose 'Watch' and the site", () => {
        expect(cleanTitle("Watch Pirates Of The Caribbean: The Curse Of The Black Pearl - JioHotstar", hot))
            .toBe("Pirates Of The Caribbean: The Curse Of The Black Pearl");
    });
    test("YouTube noise goes, the colon in a real title stays", () => {
        expect(cleanTitle("(3) Daft Punk - Something About Us (Official Video) - YouTube", "https://youtube.com/watch?v=1"))
            .toBe("Daft Punk - Something About Us");
    });
    test("music player titles are untouched", () => {
        expect(cleanTitle("Rock It", "")).toBe("Rock It");
        expect(cleanTitle("Watchmen", "")).toBe("Watchmen");
    });
    test("never empty when there was a title", () => {
        expect(cleanTitle("YouTube", "https://youtube.com")).toBe("YouTube");
        expect(cleanTitle("", "")).toBe("");
    });
});

describe("subtitle", () => {
    test("artist, else the site, else the player", () => {
        expect(subtitle("Daft Punk", hot, "Mozilla zen")).toBe("Daft Punk");
        expect(subtitle("", hot, "Mozilla zen")).toBe("JioHotstar");
        expect(subtitle("", "", "Mozilla zen")).toBe("Mozilla zen");
    });
});
