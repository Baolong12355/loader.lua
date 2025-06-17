local config = getgenv().TDX_Config or {}

local function tryRun(name, enabled, url)
    if enabled and typeof(url) == "string" and url:match("^https?://") then
        local ok, result = pcall(function()
            return loadstring(game:HttpGet(url))()
        end)
        if ok then
            print("✅ Loaded:", name)
        else
            warn("⚠️ Failed to load:", name, result)
        end
    else
        print("⏭️ Bỏ qua:", name)
    end
end

-- ✅ Link raw chuẩn sau khi đã rename file trên GitHub
local links = {
    ["x1.5 Speed"]      = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/speed.lua",
    ["Auto Skill"]      = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/auto_skill.lua",
    ["Run Macro"]       = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/run_macro.lua",
    ["Return Lobby"]    = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/return_lobby.lua",
    ["Join Map"]        = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/auto_join.lua",
    ["Auto Difficulty"] = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/difficulty.lua"
}

tryRun("x1.5 Speed", config["x1.5 Speed"], links["x1.5 Speed"])
tryRun("Auto Skill", config["Auto Skill"], links["Auto Skill"])
tryRun("Run Macro", config["Macros"] == "run" or config["Macros"] == "record", links["Run Macro"])
tryRun("Return Lobby", true, links["Return Lobby"])
tryRun("Join Map", config["Map"] ~= nil, links["Join Map"])
tryRun("Auto Difficulty", config["Auto Difficulty"] ~= nil, links["Auto Difficulty"])
