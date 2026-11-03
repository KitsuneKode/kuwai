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
