-- âœ… TDX Loader - Táº£i chá»©c nÄƒng tá»« repo GitHub cá»§a báº¡n
local config = getgenv().TDX_Config or {}

local function tryRun(name, enabled, url)
    if enabled and typeof(url) == "string" and url:match("^https?://") then
        print("â³ Loading:", name)
        local ok, result = pcall(function()
            local script = game:HttpGet(url)
            return loadstring(script)()
        end)
        if ok then
            print("âœ… Loaded:", name)
            return true
        else
            warn("âŒ Failed:", name, result)
            return false
        end
    else
        print("â­ï¸ Skipped:", name)
        return false
    end
end

-- đŸ§© Link RAW cho tá»«ng module tá»« repo cá»§a báº¡n
local base = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/"
local links = {
    ["x1.5 Speed"]      = base .. "speed.lua",
    ["Auto Skill"]      = base .. "auto_skill.lua",
    ["Run Macro"]       = base .. "run_macro.lua",
    ["Join Map"]        = base .. "auto_join.lua",
    ["Auto Difficulty"] = base .. "difficulty.lua",
    ["Return Lobby"]    = base .. "return_lobby.lua"
}

-- Special case for Return Lobby
if config["Return Lobby"] then
    local success = tryRun("Return Lobby", true, links["Return Lobby"])
    if not success then
        warn("âŒ Critical error in Return Lobby - attempting fallback...")
        -- Add simple fallback return to lobby function
        game:GetService("ReplicatedStorage").Remotes.To_Server.Handle_Initiate_S:FireServer("leave_game")
    end
    return -- Stop execution here if we're just returning to lobby
end

-- Normal module loading sequence
tryRun("x1.5 Speed",      config["x1.5 Speed"], links["x1.5 Speed"])
task.wait(1)
tryRun("Join Map",        config["Map"] ~= nil, links["Join Map"])
task.wait(0.5)
tryRun("Auto Difficulty", config["Auto Difficulty"] ~= nil, links["Auto Difficulty"])
task.wait(1)
tryRun("Run Macro",       config["Macros"] == "run" or config["Macros"] == "record", links["Run Macro"])
task.wait(2)
tryRun("Auto Skill",      config["Auto Skill"], links["Auto Skill"])
