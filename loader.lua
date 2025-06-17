local config = getgenv().TDX_Config or {}

local function tryRun(name, enabled, url)
    if enabled and typeof(url) == "string" and url:match("^https?://") then
        print("⏳ Loading:", name)
        local ok, result = pcall(function()
            return loadstring(game:HttpGet(url))()
        end)
        if ok then
            print("✅ Loaded:", name)
        else
            warn("❌ Failed:", name, result)
        end
    else
        print("⏭️ Skipped:", name)
    end
end

local base = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/"
local links = {
    ["x1.5 Speed"]      = base .. "speed",
    ["Auto Skill"]      = base .. "Auto%20Skill",
    ["Run Macro"]       = base .. "Run%20Macro",
    ["Return Lobby"]    = base .. "Return%20Lobby",
    ["Join Map"]        = base .. "Join%20Map",
    ["Auto Difficulty"] = base .. "Auto%20Difficulty"
}

tryRun("x1.5 Speed", config["x1.5 Speed"], links["x1.5 Speed"])
task.wait(1)

tryRun("Join Map", config["Map"] ~= nil, links["Join Map"])
task.wait(0.5)

tryRun("Auto Difficulty", config["Auto Difficulty"] ~= nil, links["Auto Difficulty"])
task.wait(1)

tryRun("Run Macro", config["Macros"] == "run" or config["Macros"] == "record", links["Run Macro"])
task.wait(2)

tryRun("Auto Skill", config["Auto Skill"], links["Auto Skill"])
task.wait(2)

tryRun("Return Lobby", true, links["Return Lobby"])
task.wait(10)
