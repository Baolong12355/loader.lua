-- ✅ TDX Loader - Tải chức năng từ repo GitHub của bạn
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

-- 📦 Link RAW cho từng module từ repo của bạn
local base = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/"
local links = {
    ["x1.5 Speed"]      = base .. "speed.lua",
    ["Auto Skill"]      = base .. "auto_skill.lua",
    ["Run Macro"]       = base .. "run_macro.lua",
    ["Join Map"]        = base .. "auto_join.lua",
    ["Auto Difficulty"] = base .. "difficulty.lua",
    ["Return Lobby"]    = base .. "return_lobby.lua", -- ✅ thêm vào đây
}

-- 🚪 Chạy Return Lobby ngay lập tức, không chờ
spawn(function()
    tryRun("Return Lobby", config["Return Lobby"], links["Return Lobby"])
end)

-- 🔁 Các module còn lại (vẫn có delay để tránh lỗi tải)
tryRun("x1.5 Speed",      config["x1.5 Speed"], links["x1.5 Speed"])
task.wait(1)

tryRun("Join Map",        config["Map"] ~= nil, links["Join Map"])
task.wait(0.5)

tryRun("Auto Difficulty", config["Auto Difficulty"] ~= nil, links["Auto Difficulty"])
task.wait(1)

tryRun("Run Macro",       config["Macros"] == "run" or config["Macros"] == "record", links["Run Macro"])
task.wait(2)

tryRun("Auto Skill",      config["Auto Skill"], links["Auto Skill"])
task.wait(2)
