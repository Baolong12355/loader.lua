-- Script: moving_skill_recorder.lua
-- Purpose: Records moving skills (Helio 1/3, Cryo Helio, Jet Trooper 1) with wave/time info

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- Configuration
local TOWERS_TO_RECORD = {
    ["Helicopter"] = {1, 3},    -- Helio skills 1 and 3
    ["Cryo Helicopter"] = true,  -- All skills
    ["Jet Trooper"] = {1}        -- Only skill 1
}

-- Output file (same format as your recorder)
local outJson = "tdx/macros/recorder_output.json"

-- Get current wave and time (from your existing recorder)
local function getCurrentWaveAndTime()
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return nil, nil end

    local interface = playerGui:FindFirstChild("Interface")
    if not interface then return nil, nil end
    local gameInfoBar = interface:FindFirstChild("GameInfoBar")
    if not gameInfoBar then return nil, nil end

    local wave = gameInfoBar.Wave.WaveText.Text
    local time = gameInfoBar.TimeLeft.TimeLeftText.Text
    return wave, time
end

-- Convert time string to number (from your existing recorder)
local function convertTimeToNumber(timeStr)
    if not timeStr then return nil end
    local mins, secs = timeStr:match("(%d+):(%d+)")
    if mins and secs then
        return tonumber(mins) * 100 + tonumber(secs)
    end
    return nil
end

-- Update JSON file (from your existing recorder)
local function updateJsonFile(recordedActions)
    if not HttpService then return end
    local jsonLines = {}
    for i, entry in ipairs(recordedActions) do
        local ok, jsonStr = pcall(HttpService.JSONEncode, HttpService, entry)
        if ok then
            if i < #recordedActions then
                jsonStr = jsonStr .. ","
            end
            table.insert(jsonLines, jsonStr)
        end
    end
    local finalJson = "[\n" .. table.concat(jsonLines, "\n") .. "\n]"
    
    if writefile then
        pcall(writefile, outJson, finalJson)
    end
end

-- Read existing recorded actions
local function readRecordedActions()
    if not isfile or not isfile(outJson) or not readfile then return {} end
    
    local content = readfile(outJson)
    if content == "" then return {} end

    content = content:gsub("^%[%s*", ""):gsub("%s*%]$", "")
    local actions = {}
    for line in content:gmatch("[^\r\n]+") do
        line = line:gsub(",$", "")
        if line:match("%S") then
            local ok, decoded = pcall(HttpService.JSONDecode, HttpService, line)
            if ok and decoded then
                table.insert(actions, decoded)
            end
        end
    end
    return actions
end

-- Record a moving skill action
local function recordMovingSkill(hash, index, position)
    -- Skip if rebuild is running (from your existing recorder)
    if _G and _G.TDX_REBUILD_RUNNING then return end

    -- Get tower type from hash
    local tower
    for h, t in pairs(TowerClass.GetTowers()) do
        if tostring(h) == tostring(hash) then
            tower = t
            break
        end
    end
    
    if not tower or not TOWERS_TO_RECORD[tower.Type] then return end
    
    -- Check if this specific skill should be recorded
    local shouldRecord = false
    if TOWERS_TO_RECORD[tower.Type] == true then
        shouldRecord = true
    else
        for _, skillIndex in ipairs(TOWERS_TO_RECORD[tower.Type]) do
            if skillIndex == index then
                shouldRecord = true
                break
            end
        end
    end
    
    if not shouldRecord then return end
    
    -- Get current wave and time
    local wave, time = getCurrentWaveAndTime()
    
    -- Create the action record with X position only
    local action = {
        TowerMoving = position.X,  -- Using X position as requested
        SkillIndex = index,
        Location = string.format("%s, %s, %s", position.X, position.Y, position.Z),  -- Still keep full position for reference
        Wave = wave,
        Time = convertTimeToNumber(time)
    }
    
    -- Update the JSON file
    local recordedActions = readRecordedActions()
    table.insert(recordedActions, action)
    updateJsonFile(recordedActions)
    
    print(string.format("📢 [Moving Skill Recorded] %s (Hash: %d) | Skill %d | X Position: %.2f", 
        tower.Type, hash, index, position.X))
end

-- Hook setup
local function setupHooks()
    local originalInvokeServer
    local originalNamecall
    
    -- Hook InvokeServer directly
    if typeof(TowerUseAbilityRequest) == "Instance" then
        originalInvokeServer = hookfunction(TowerUseAbilityRequest.InvokeServer, function(self, ...)
            local args = {...}
            if self == TowerUseAbilityRequest and #args >= 3 and typeof(args[3]) == "Vector3" then
                recordMovingSkill(args[1], args[2], args[3])
            end
            return originalInvokeServer(self, ...)
        end)
    end
    
    -- Hook namecall for all cases
    originalNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if getnamecallmethod() == "InvokeServer" and typeof(self) == "Instance" and self.Name == "TowerUseAbilityRequest" then
            local args = {...}
            if #args >= 3 and typeof(args[3]) == "Vector3" then
                recordMovingSkill(args[1], args[2], args[3])
            end
        end
        return originalNamecall(self, ...)
    end)
end

-- Initialize
local TowerClass
local TowerUseAbilityRequest

local function initialize()
    -- Load TowerClass
    pcall(function()
        local PlayerScripts = player:WaitForChild("PlayerScripts")
        local client = PlayerScripts:WaitForChild("Client")
        local gameClass = client:WaitForChild("GameClass")
        local towerModule = gameClass:WaitForChild("TowerClass")
        TowerClass = require(towerModule)
    end)

    if not TowerClass then
        warn("❌ Failed to load TowerClass - moving skills won't be recorded")
        return false
    end

    -- Get TowerUseAbilityRequest remote
    TowerUseAbilityRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUseAbilityRequest")
    if not TowerUseAbilityRequest then
        warn("❌ Failed to find TowerUseAbilityRequest remote")
        return false
    end

    return true
end

if initialize() then
    setupHooks()
    print("✅ Moving Skill Recorder activated for Helio/Cryo Helio/Jet Trooper")
end