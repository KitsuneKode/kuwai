from conftest import started
from test_tools import answer, call, completion

CAPS = {"hermes3:8b": ["completion", "tools"]}
USER = {"messages": [{"role": "user", "content": "look it up"}]}

DDG = """<html><body>
<div class="result"><h2><a rel="nofollow" class="result__a" href="https://hypr.land/news/update57/">Hyprland 0.57 &amp; Lua</a></h2>
<a class="result__snippet" href="https://hypr.land/news/update57/">The <b>Lua</b> config is here.</a></div>
<div class="result"><h2><a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fgithub.com%2Fhyprwm%2FHyprland%2Freleases&amp;rut=x">Releases · hyprwm/Hyprland</a></h2>
<a class="result__snippet" href="#">All releases.</a></div>
</body></html>"""

PAGE = """<html><head><title>Notes</title><style>body{color:red}</style><script>var x=1;</script></head>
<body><nav>Menu Home About</nav><main><h1>Update 57</h1><p>Lua config&nbsp;is the default.</p>
<p>Second   paragraph.</p></main><footer>Copyright</footer></body></html>"""


def test_web_search_parses_duckduckgo_html(run_agent):
    events, _ = run_agent(USER, [[call("web_search", {"query": "hyprland 0.57"}), {"done": True}], answer()],
                          caps=CAPS, pages={"/ddg": ("text/html", DDG)})
    item = started(events, "web_search")[0]
    out = completion(events, item["id"])["output"]
    assert completion(events, item["id"])["status"] == "completed"
    assert "1. Hyprland 0.57 & Lua — https://hypr.land/news/update57/" in out
    assert "The Lua config is here." in out
    assert "2. Releases · hyprwm/Hyprland — https://github.com/hyprwm/Hyprland/releases" in out


def test_web_search_no_results_fails_item(run_agent):
    events, _ = run_agent(USER, [[call("web_search", {"query": "zzz"}), {"done": True}], answer()],
                          caps=CAPS, pages={"/ddg": ("text/html", "<html><body>No results.</body></html>")})
    item = started(events, "web_search")[0]
    assert completion(events, item["id"])["status"] == "failed"


def test_web_fetch_returns_clean_text(run_agent):
    # __FAKE__ becomes the fake server's URL, which also serves the page.
    events, _ = run_agent(USER, [[call("web_fetch", {"url": "__FAKE__/page"}), {"done": True}], answer()],
                          caps=CAPS, pages={"/page": ("text/html; charset=utf-8", PAGE)})
    item = [e for e in events if e["type"] == "item.started" and e["itemType"] == "dynamic_tool_call"][0]
    done = completion(events, item["id"])
    assert done["status"] == "completed", done["output"]
    out = done["output"]
    assert out.startswith("Notes\n")
    assert "Update 57" in out and "Lua config is the default." in out and "Second paragraph." in out
    assert "var x" not in out and "color:red" not in out and "Menu Home" not in out and "Copyright" not in out


def test_web_fetch_rejects_non_http(run_agent):
    events, _ = run_agent(USER, [[call("web_fetch", {"url": "file:///etc/passwd"}), {"done": True}], answer()],
                          caps=CAPS)
    item = [e for e in events if e["type"] == "item.started" and e["itemType"] == "dynamic_tool_call"][0]
    assert completion(events, item["id"])["status"] == "failed"


def test_web_fetch_sniffs_html_without_content_type(run_agent):
    events, _ = run_agent(USER, [[call("web_fetch", {"url": "__FAKE__/page"}), {"done": True}], answer()],
                          caps=CAPS, pages={"/page": ("application/octet-stream", "<!doctype html>\n" + PAGE)})
    item = [e for e in events if e["type"] == "item.started" and e["itemType"] == "dynamic_tool_call"][0]
    out = completion(events, item["id"])["output"]
    assert "<" not in out and "Update 57" in out


BING = """<html><body><ol id="b_results">
<li class="b_algo"><div class="b_tpcn"></div><h2><a target="_blank" href="https://www.bing.com/ck/a?!&amp;&amp;p=x&amp;u=a1aHR0cHM6Ly9naXRodWIuY29tL2h5cHJ3bS9IeXBybGFuZA&amp;ntb=1"><strong>GitHub</strong> - hyprwm/Hyprland</a></h2>
<div class="b_caption"><p class="b_lineclamp2">Hyprland is a dynamic tiling Wayland compositor.</p></div></li>
<li class="b_algo"><h2><a href="https://hypr.land/news/update57/">Hyprland 0.57</a></h2><p class="b_lineclamp3">Lua configs.</p></li>
</ol></body></html>"""
ANOMALY = "<html><body><div class='anomaly-modal'>Unfortunately, bots use DuckDuckGo too.</div></body></html>"
WIKI = '{"pages":[{"key":"Hyprland","title":"Hyprland","excerpt":"<span class=\\"searchmatch\\">Hyprland</span> is a tiling compositor"}]}'


def test_search_falls_back_to_bing_when_duckduckgo_blocks(run_agent):
    events, _ = run_agent(USER, [[call("web_search", {"query": "hyprland"}), {"done": True}], answer()],
                          caps=CAPS, pages={"/ddg": ("text/html", ANOMALY), "/bing": ("text/html", BING)})
    out = completion(events, started(events, "web_search")[0]["id"])["output"]
    assert "1. GitHub - hyprwm/Hyprland — https://github.com/hyprwm/Hyprland" in out
    assert "Hyprland is a dynamic tiling Wayland compositor." in out
    assert "2. Hyprland 0.57 — https://hypr.land/news/update57/" in out


def test_search_falls_back_to_wikipedia_last(run_agent):
    events, _ = run_agent(USER, [[call("web_search", {"query": "hyprland"}), {"done": True}], answer()],
                          caps=CAPS, pages={"/ddg": ("text/html", ANOMALY), "/bing": ("text/html", "<html></html>"),
                                            "/wiki": ("application/json", WIKI)})
    out = completion(events, started(events, "web_search")[0]["id"])["output"]
    assert "1. Hyprland — https://en.wikipedia.org/wiki/Hyprland" in out
    assert "Hyprland is a tiling compositor" in out


def test_web_fetch_keeps_machine_dates(run_agent):
    page = ('<html><body><main><h2>Hyprland 0.57.1</h2><relative-time datetime="2026-11-03T09:47:12Z">03 Nov 09:47'
            '</relative-time><p>Posted <time datetime="2026-10-28">last week</time>.</p></main></body></html>')
    events, _ = run_agent(USER, [[call("web_fetch", {"url": "__FAKE__/page"}), {"done": True}], answer()],
                          caps=CAPS, pages={"/page": ("text/html", page)})
    item = [e for e in events if e["type"] == "item.started" and e["itemType"] == "dynamic_tool_call"][0]
    out = completion(events, item["id"])["output"]
    assert "03 Nov 09:47 (2026-11-03)" in out
    assert "last week (2026-10-28)" in out


AMAZON = """<html><body>
<div data-component-type="s-search-result" data-asin="B0AAA"><h2 aria-label="Sponsored Ad - Acer Aspire 3, 16GB RAM"><span>x</span></h2>
<a class="a-link-normal" href="/Acer-Aspire/dp/B0AAA?ref=sr_1"></a><span class="a-price"><span class="a-offscreen">₹49,300</span></span>
<span class="a-text-price"><span class="a-offscreen">M.R.P: ₹65,900</span></span><span class="a-icon-alt">4.1 out of 5 stars</span></div>
<div data-component-type="s-search-result" data-asin="B0BBB"><h2><span>No price here</span></h2><a href="/x/dp/B0BBB"></a></div>
</body></html>"""


def test_shop_search_reads_amazon(run_agent, tmp_path):
    events, fake = run_agent(USER, [[call("shop_search", {"query": "laptop 16gb", "store": "amazon"}), {"done": True}],
                                    answer()], caps=CAPS, pages={"/amz/s": ("text/html", AMAZON)})
    item = started(events, "web_search")[0]
    assert item["title"] == "Shopping “laptop 16gb”"
    out = completion(events, item["id"])["output"]
    assert "1. Acer Aspire 3, 16GB RAM — " in out and out.split(" — ")[1].startswith(fake.url + "/amz/dp/B0AAA")
    assert "Amazon ₹49,300 · MRP ₹65,900 · 4.1★" in out
    assert "No price here" not in out


def test_duckduckgo_ads_are_skipped(run_agent):
    ad = ('<div class="result result--ad"><h2><a class="result__a" href="https://duckduckgo.com/y.js?ad_domain=x">'
          'Buy now</a></h2></div>')
    events, _ = run_agent(USER, [[call("web_search", {"query": "q"}), {"done": True}], answer()],
                          caps=CAPS, pages={"/ddg": ("text/html", DDG.replace("<body>", "<body>" + ad))})
    out = completion(events, started(events, "web_search")[0]["id"])["output"]
    assert "Buy now" not in out and out.startswith("1. Hyprland 0.57")
