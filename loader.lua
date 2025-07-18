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

-- 🔁 Chạy từng module trong thread riêng
spawn(function() tryRun("Return Lobby",    getgenv().TDX_Config["Return Lobby"],    links["Return Lobby"]) end)
spawn(function() tryRun("x1.5 Speed",       getgenv().TDX_Config["x1.5 Speed"],     links["x1.5 Speed"]) end)
spawn(function() tryRun("Join Map",         getgenv().TDX_Config["Map"] ~= nil,     links["Join Map"]) end)
spawn(function() tryRun("Auto Difficulty",  getgenv().TDX_Config["Auto Difficulty"] ~= nil, links["Auto Difficulty"]) end)

-- 🧠 Macro chạy theo loại
if getgenv().TDX_Config["Macros"] == "run" then
    spawn(function() tryRun("Run Macro", true, links["Run Macro"]) end)
elseif getgenv().TDX_Config["Macros"] == "record" then
    spawn(function() tryRun("Record Macro", true, links["Record Macro"]) end)
end

spawn(function() tryRun("Auto Skill", getgenv().TDX_Config["Auto Skill"], links["Auto Skill"]) end)
