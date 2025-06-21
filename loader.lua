repeat wait() until game:IsLoaded() and game.Players.LocalPlayer

-- giả sử getgenv().TDX_Config đã được khai báo ở ngoài

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

-- 📦 Link các module
local base = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/"
local links = {
    ["x1.5 Speed"]      = base .. "speed.lua",
    ["Auto Skill"]      = base .. "auto_skill.lua",
    ["Run Macro"]       = base .. "run_macro.lua",
    ["Record Macro"]    = base .. "record.lua",
    ["Join Map"]        = base .. "auto_join.lua",
    ["Auto Difficulty"] = base .. "difficulty.lua",
    ["Return Lobby"]    = base .. "return_lobby.lua"
}

-- 🚪 Return Lobby chạy riêng, không chờ
spawn(function()
    tryRun("Return Lobby", getgenv().TDX_Config["Return Lobby"], links["Return Lobby"])
end)

-- 🔁 Chạy các module còn lại theo cấu hình
tryRun("x1.5 Speed",      getgenv().TDX_Config["x1.5 Speed"], links["x1.5 Speed"])
task.wait(1)

tryRun("Join Map",        getgenv().TDX_Config["Map"] ~= nil, links["Join Map"])
task.wait(0.5)

tryRun("Auto Difficulty", getgenv().TDX_Config["Auto Difficulty"] ~= nil, links["Auto Difficulty"])
task.wait(1)

if getgenv().TDX_Config["Macros"] == "run" then
    tryRun("Run Macro", true, links["Run Macro"])
elseif getgenv().TDX_Config["Macros"] == "record" then
    tryRun("Record Macro", true, links["Record Macro"])
end
task.wait(2)

tryRun("Auto Skill",      getgenv().TDX_Config["Auto Skill"], links["Auto Skill"])
task.wait(2)
