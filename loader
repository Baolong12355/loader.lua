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

-- ⚠️ Sử dụng link RAW đúng chuẩn GitHub (đã chuyển sang /main/)
local links = {
    ["x1.5 Speed"]      = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/speed",
    ["Auto Skill"]      = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/Auto%20Skill",
    ["Run Macro"]       = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/Run%20Macro",
    ["Return Lobby"]    = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/Return%20Lobby",
    ["Join Map"]        = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/Join%20Map",
    ["Auto Difficulty"] = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/Auto%20Difficulty"
}

tryRun("x1.5 Speed", config["x1.5 Speed"], links["x1.5 Speed"])
tryRun("Auto Skill", config["Auto Skill"], links["Auto Skill"])
tryRun("Run Macro", config["Macros"] == "run" or config["Macros"] == "record", links["Run Macro"])
tryRun("Return Lobby", true, links["Return Lobby"])
tryRun("Join Map", config["Map"] ~= nil, links["Join Map"])
tryRun("Auto Difficulty", config["Auto Difficulty"] ~= nil, links["Auto Difficulty"])
