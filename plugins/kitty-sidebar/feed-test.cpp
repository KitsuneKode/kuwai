#include "feed.hpp"
#include <iostream>
#include <cstdlib>
static void require(bool x) { if (!x) { std::cerr << "contract assertion failed\n"; std::exit(1); } }
int main() {
    auto j = Sidebar::Json{{"version", 1}, {"agents", Sidebar::Json::array({
        {{"kitty_pid", 42}, {"title", "Review parser"}, {"state", "working"},
         {"action", {{"op", "jump"}, {"pid", 42}, {"w", "20"}}}},
        {{"kitty_pid", 43}, {"action", {{"op", "jump"}, {"pid", 42}, {"w", "21"}}}}
    })}};
    auto rows = Sidebar::parseFeed(j.dump());
    require(rows.size() == 2 && rows[0].pid == 42 && rows[0].action["w"] == "20" && rows[1].action.is_null());
    j["agents"][0]["action"]["w"] = "20; echo nope";
    require(Sidebar::parseFeed(j.dump())[0].action.is_null());
    require(Sidebar::parseFeed(R"({"version":1,"agents":[]})").empty());
    j["agents"][0]["title"] = std::string(255, 'a') + "界";
    require(Sidebar::parseFeed(j.dump())[0].title.size() == 255);
    j["agents"][0]["title"] = "one\ntwo";
    require(Sidebar::parseFeed(j.dump())[0].title == "one two");
    for (auto s : {std::string("{broken"), std::string(R"({"version":2,"agents":[]})"), std::string(1024*1024+1, 'x')}) {
        bool rejected = false; try { Sidebar::parseFeed(s); } catch (...) { rejected = true; }
        require(rejected);
    }
    std::cout << "feed contract: PASS (schema, empty, bounds, malformed, action/PID validation)\n";
}
