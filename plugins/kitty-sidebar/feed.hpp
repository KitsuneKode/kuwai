#pragma once
#include <nlohmann/json.hpp>
#include <string>
#include <vector>
#include <stdexcept>

namespace Sidebar {
using Json = nlohmann::json;
struct Row {
    int pid;
    std::string title, state, agent;
    Json action;
};
inline std::vector<Row> parseFeed(const std::string& bytes) {
    if (bytes.size() > 1024 * 1024) throw std::runtime_error("feed too large");
    auto j = Json::parse(bytes);
    if (!j.is_object() || j.value("version", 0) != 1 || !j.contains("agents") || !j["agents"].is_array())
        throw std::runtime_error("unsupported agents feed");
    std::vector<Row> rows;
    for (const auto& a : j["agents"]) {
        if (rows.size() == 128) break;
        if (!a.is_object() || !a.contains("kitty_pid") || !a["kitty_pid"].is_number_integer()) continue;
        const auto pid = a["kitty_pid"].get<long long>();
        if (pid <= 0 || pid > 2147483647) continue;
        const auto text = [&](const char* key, const char* fallback) {
            auto it = a.find(key);
            if (it == a.end() || !it->is_string()) return std::string(fallback);
            // Bound layout work; Pango receives plain text, never markup.
            auto value = it->get<std::string>();
            if (value.size() > 256) {
                size_t end = 256;
                while (end && (static_cast<unsigned char>(value[end]) & 0xC0) == 0x80) --end;
                value.resize(end);
            }
            for (auto& c : value) if (static_cast<unsigned char>(c) < 32) c = ' ';
            return value;
        };
        Json action;
        if (a.contains("action") && a["action"].is_object()) {
            const auto& x = a["action"];
            if (x.value("op", std::string{}) == "jump" && x.contains("pid") && x["pid"].is_number_integer() &&
                x["pid"].get<long long>() == pid && x.contains("w") && x["w"].is_string()) {
                auto w = x["w"].get<std::string>();
                if (!w.empty() && w.size() <= 16 && w.find_first_not_of("0123456789") == std::string::npos)
                    action = {{"op", "jump"}, {"pid", pid}, {"w", w}};
            }
        }
        rows.push_back({static_cast<int>(pid), text("title", "Agent"), text("state", "idle"), text("agent", "agent"), action});
    }
    return rows;
}
}
