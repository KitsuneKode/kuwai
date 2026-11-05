// Research spike only. Intentionally refuses ordinary desktop sessions.
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowMetadata.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/render/decorations/IHyprWindowDecoration.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/WindowRenderPresentation.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopTimer.hpp>
#include <hyprland/src/devices/IPointer.hpp>
#include <linux/input-event-codes.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <chrono>
#include <cstdlib>
#include <fstream>
#include <array>
#include "feed.hpp"

namespace {
HANDLE handle;
std::vector<Sidebar::Row> rows;
std::string lastBytes, feedPath;
std::chrono::steady_clock::time_point nextRead;
std::vector<WP<IHyprWindowDecoration>> decorations;
CHyprSignalListener openListener;
SP<CEventLoopTimer> pollTimer;
constexpr int WIDTH = 260, TOP = 90, ROW = 66;

std::string readFeed() {
    const int fd = open(feedPath.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
    if (fd < 0) throw std::runtime_error("feed unavailable");
    struct Close { int fd; ~Close() { close(fd); } } closeFD{fd};
    struct stat st{};
    if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_size > 1024 * 1024)
        throw std::runtime_error("feed must be a bounded regular file");
    std::string bytes;
    std::array<char, 4096> buffer;
    for (;;) {
        auto n = read(fd, buffer.data(), buffer.size());
        if (!n) return bytes;
        if (n < 0) throw std::runtime_error("feed read failed");
        bytes.append(buffer.data(), n);
        if (bytes.size() > 1024 * 1024) throw std::runtime_error("feed grew too large");
    }
}

class SidebarDecoration final : public IHyprWindowDecoration {
    CBox assigned;
    std::string cacheKey, status = "Click stages an action (stub)";
    float cacheScale = 0;
    std::vector<SP<Render::ITexture>> labels;
    std::vector<Sidebar::Json> actions;
    CBox globalBox(const Render::SWindowRenderPresentation& p) {
        auto box = assigned;
        box.translate(g_pDecorationPositioner->getEdgeDefinedPoint(DECORATION_EDGE_LEFT, owningWindow()));
        return box.translate(p.workspaceOffset + p.floatingOffset);
    }
  public:
    explicit SidebarDecoration(PHLWINDOW w) : IHyprWindowDecoration(w) {}
    SDecorationPositioningInfo getPositioningInfo() override {
        SDecorationPositioningInfo i;
        i.policy = DECORATION_POSITION_STICKY;
        i.edges = DECORATION_EDGE_LEFT;
        i.priority = 5000;
        i.reserved = true;
        i.desiredExtents = {{WIDTH, 0}, {0, 0}};
        return i;
    }
    void onPositioningReply(const SDecorationPositioningReply& r) override { assigned = r.assignedGeometry; }
    eDecorationType getDecorationType() override { return DECORATION_CUSTOM; }
    eDecorationLayer getDecorationLayer() override { return DECORATION_LAYER_UNDER; }
    uint64_t getDecorationFlags() override { return DECORATION_ALLOWS_MOUSE_INPUT | DECORATION_PART_OF_MAIN_WINDOW; }
    std::string getDisplayName() override { return "Kitty sidebar spike"; }
    void updateWindow(PHLWINDOW) override { damageEntire(); }
    void damageEntire() override {
        if (auto w = owningWindow(); validMapped(w))
            g_pHyprRenderer->damageBox(globalBox(w->presentation().renderPresentation()));
    }
    void draw(Render::CRenderContext& ctx, PHLMONITOR mon, const float& alpha,
              const Render::SWindowRenderPresentation& presentation) override {
        auto w = owningWindow();
        if (!w || !mon || assigned.w < 1 || assigned.h < 1) return;
        const auto global = globalBox(presentation);
        auto panel = global;
        panel.translate(-mon->m_position).scale(mon->m_scale).round();
        // The core rect/texture elements handle blur and compositor presentation.
        CRectPassElement::SRectData bg;
        bg.box = panel;
        bg.color = CHyprColor{0.065, 0.075, 0.10, 0.76F * alpha};
        bg.round = std::round(18 * mon->m_scale);
        bg.blur = true;
        bg.blurA = alpha;
        bg.blurOwner = w;
        bg.workspacePresentation = presentation;
        Render::IHyprRenderer::addPassElement(ctx, makeUnique<CRectPassElement>(bg));
        // Fixed spike colours only; production would share rice theme tokens.
        std::string key = lastBytes + status;
        const auto scale = mon->m_scale;
        if (cacheKey != key || cacheScale != scale || labels.empty()) {
            labels.clear(); actions.clear(); cacheKey = key; cacheScale = scale;
            const auto label = [&](const std::string& text, int size, CHyprColor color) {
                labels.push_back(g_pHyprRenderer->renderText(text, color, std::round(size * scale), false, "Sans", 222 * scale));
            };
            label("Tabs & agents", 18, CHyprColor{0.94,0.95,0.99,1.0});
            label("KITTYMUX / COMPOSITOR SPIKE", 9, CHyprColor{0.56,0.64,0.75,1.0});
            for (const auto& r : rows) {
                if (r.pid != w->backend().pid() || actions.size() >= 12) continue;
                label(r.title, 12, CHyprColor{0.90,0.93,0.98,1.0});
                label(r.agent + "  /  " + r.state, 10, CHyprColor{0.50,0.75,0.85,1.0});
                actions.push_back(r.action);
            }
            if (actions.empty()) label("No agents in this kitty", 11, CHyprColor{0.60,0.65,0.73,1.0});
            label(status, 9, CHyprColor{0.60,0.65,0.73,1.0});
        }
        const auto texture = [&](size_t n, double y) {
            if (n >= labels.size() || !labels[n]) return;
            auto tex = labels[n];
            if (y + tex->m_size.y / scale > global.h - 8) return;
            CTexPassElement::SRenderData data;
            data.tex = tex;
            data.box = CBox{panel.x + 18 * scale, panel.y + y * scale, tex->m_size.x, tex->m_size.y};
            data.a = alpha;
            data.workspacePresentation = presentation;
            Render::IHyprRenderer::addPassElement(ctx, makeUnique<CTexPassElement>(data));
        };
        texture(0, 22); texture(1, 55);
        for (size_t i = 0; i < actions.size(); ++i) {
            if (TOP + (i + 1) * ROW > global.h - 36) break;
            texture(2+i*2, TOP+i*ROW); texture(3+i*2, TOP+i*ROW+25);
        }
        if (actions.empty()) texture(2, TOP);
        texture(labels.size()-1, std::max(0.0, global.h-27));
    }
    bool onInputOnDeco(eInputType type, const Vector2D& pos, std::any data) override {
        if (type != INPUT_TYPE_BUTTON || data.type() != typeid(IPointer::SButtonEvent)) return false;
        const auto e = std::any_cast<IPointer::SButtonEvent>(data);
        if (e.button != BTN_LEFT) return false;
        auto w = owningWindow();
        if (!w) return false;
        const auto box = globalBox(w->presentation().renderPresentation());
        if (!box.containsPoint(pos)) return false;
        if (e.state == WL_POINTER_BUTTON_STATE_PRESSED) {
            const auto relativeY = pos.y - box.y;
            const int index = static_cast<int>((relativeY-TOP)/ROW);
            if (relativeY >= TOP && index >= 0 && static_cast<size_t>(index) < actions.size() &&
                TOP + (index+1)*ROW <= box.h-36 && !actions[index].is_null()) {
                // Deliberate no-exec stub. Future helper: posix_spawnp("kittymux", {"kittymux", "act", action.dump()}).
                // Never pass JSON through a shell. Never run this against live kitty from a test.
                status = "Action staged: jump (no execution)";
                damageEntire();
            }
        }
        return true;
    }
};
void attach(PHLWINDOW w) {
    if (!w || w->metadata().appID() != "kitty") return;
    for (const auto& d : w->presentation().decorations())
        if (d->getDisplayName() == "Kitty sidebar spike") return;
    auto d = makeShared<SidebarDecoration>(w);
    decorations.emplace_back(d);
    HyprlandAPI::addWindowDecoration(handle, w, std::move(d));
}
void refresh() {
    auto now = std::chrono::steady_clock::now();
    if (now < nextRead) return;
    nextRead = now + std::chrono::milliseconds(500);
    try {
        auto bytes = readFeed();
        if (bytes == lastBytes) return;
        auto parsed = Sidebar::parseFeed(bytes);
        rows = std::move(parsed); lastBytes = std::move(bytes);
    } catch (...) {
        // Fail closed: malformed/removed feeds must not leave actionable stale rows.
        if (lastBytes.empty() && rows.empty()) return;
        rows.clear(); lastBytes.clear();
    }
    std::erase_if(decorations, [](const auto& d) { return !d; });
    for (const auto& d : decorations) if (d) d->damageEntire();
}
}
APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }
APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE h) {
    const char* isolated = std::getenv("KITTY_SIDEBAR_SPIKE");
    const char* runtime = std::getenv("XDG_RUNTIME_DIR");
    if (!isolated || std::string(isolated) != "isolated" || !runtime)
        throw std::runtime_error("kitty-sidebar: isolated rig only");
    std::ifstream marker(std::string(runtime) + "/kitty-sidebar-isolated");
    std::string value; std::getline(marker, value);
    if (value != "isolated") throw std::runtime_error("kitty-sidebar: missing isolated-runtime marker");
    if (__hyprland_api_get_hash() != __hyprland_api_get_client_hash())
        throw std::runtime_error("kitty-sidebar: compositor/header ABI mismatch");
    handle = h;
    const char* state = std::getenv("KITTYMUX_STATE");
    if (!state || !*state) throw std::runtime_error("kitty-sidebar: explicit isolated KITTYMUX_STATE required");
    feedPath = std::string(state) + "/agents.json";
    refresh();
    openListener = Event::bus()->m_events.window.open.listen([](PHLWINDOW w) { attach(w); });
    // Animation ticks stop when idle: use an event-loop timer so feed changes wake the panel.
    pollTimer = makeShared<CEventLoopTimer>(std::chrono::milliseconds(500), [](SP<CEventLoopTimer> self, void*) {
        refresh();
        self->updateTimeout(std::chrono::milliseconds(500));
    }, nullptr);
    g_pEventLoopManager->addTimer(pollTimer);
    for (const auto& w : Desktop::windowState()->windows()) if (validMapped(w) && !w->isHidden()) attach(w);
    return {"kitty-sidebar-spike", "Isolated kitty left decoration; no-exec click stub", "rice research", "0.1"};
}
APICALL EXPORT void PLUGIN_EXIT() {
    openListener.reset();
    if (pollTimer) { pollTimer->cancel(); g_pEventLoopManager->removeTimer(pollTimer); pollTimer.reset(); }
    for (const auto& d : decorations) if (d) HyprlandAPI::removeWindowDecoration(handle, d.get());
    decorations.clear(); rows.clear();
}
