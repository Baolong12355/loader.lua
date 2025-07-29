local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local PlayerScripts = player:WaitForChild("PlayerScripts")

-- Load required classes
local TowerClass, EnemyClass
pcall(function()
    local client = PlayerScripts:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    TowerClass = require(gameClass:WaitForChild("TowerClass"))
    EnemyClass = require(gameClass:WaitForChild("EnemyClass"))
end)

-- Configuration for moving skill towers
local MOVING_SKILL_TOWERS = {
    ["Helio"] = {skills = {1, 3}},
    ["Cryo Helicopter"] = {skills = {1}},
    ["Jet Trooper"] = {skills = {1}}
}

-- Get current wave and time (reusing existing function from recorder)
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

-- Convert time string to number (reusing existing function)
local function convertTimeToNumber(timeStr)
    if not timeStr then return nil end
    local mins, secs = timeStr:match("(%d+):(%d+)")
    if mins and secs then
        return tonumber(mins) * 100 + tonumber(secs)
    end
    return nil
end

-- Safe write to file (reusing existing function)
local function safeWriteFile(path, content)
    if writefile then
        local success, err = pcall(writefile, path, content)
        if not success then
            warn("Lỗi khi ghi file: " .. tostring(err))
        end
    end
end

-- Main recording function for moving skills
local function recordMovingSkill(hash, index, pos)
    -- Skip if rebuild is running
    if _G and _G.TDX_REBUILD_RUNNING then return end
    
    -- Get tower info
    local tower = TowerClass.GetTowers()[hash]
    if not tower then return end
    
    -- Check if this is a moving skill tower and skill
    local config = MOVING_SKILL_TOWERS[tower.Type]
    if not config or not table.find(config.skills, index) then return end
    
    -- Get current wave and time
    local currentWave, currentTime = getCurrentWaveAndTime()
    local timeNumber = convertTimeToNumber(currentTime)
    
    -- Create record entry
    local entry = {
        TowerMoving = tostring(hash),
        SkillIndex = index,
        Location = string.format("%.2f, %.2f, %.2f", pos.X, pos.Y, pos.Z),
        Wave = currentWave,
        Time = timeNumber
    }
    
    -- Read existing file
    local outJson = "tdx/macros/recorder_output.json"
    local existingContent = ""
    if isfile and isfile(outJson) and readfile then
        existingContent = readfile(outJson)
        -- Remove closing bracket if exists
        existingContent = existingContent:gsub("%s*%]$", "")
    end
    
    -- Prepare new content
    local newEntry = HttpService:JSONEncode(entry)
    local newContent = existingContent
    if #existingContent > 0 and not existingContent:match(",%s*$") then
        newContent = newContent .. ","
    end
    newContent = newContent .. "\n" .. newEntry .. "\n]"
    
    -- Write to file
    safeWriteFile(outJson, newContent)
    
    print(string.format("Recorded moving skill: %s skill %d at %s (Wave %s, Time %s)",
        tower.Type, index, tostring(pos), currentWave or "?", currentTime or "?"))
end

-- Hook setup
local function setupMovingSkillHooks()
    if not hookfunction or not hookmetamethod then
        warn("Executor doesn't support required hook functions")
        return
    end

    -- Store original functions
    local originalInvokeServer
    
    -- Hook InvokeServer for TowerUseAbilityRequest
    local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUseAbilityRequest")
    if remote:IsA("RemoteFunction") then
        originalInvokeServer = hookfunction(remote.InvokeServer, function(self, ...)
            if self.Name == "TowerUseAbilityRequest" and not checkcaller() then
                local args = {...}
                if #args >= 3 and typeof(args[3]) == "Vector3" then
                    recordMovingSkill(args[1], args[2], args[3])
                end
            end
            return originalInvokeServer(self, ...)
        end)
    end

    -- Hook __namecall for broader catching
    local originalNamecall
    originalNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if getnamecallmethod() == "InvokeServer" and self.Name == "TowerUseAbilityRequest" and not checkcaller() then
            local args = {...}
            if #args >= 3 and typeof(args[3]) == "Vector3" then
                recordMovingSkill(args[1], args[2], args[3])
            end
        end
        return originalNamecall(self, ...)
    end)

    print("Moving Skill Recorder hooks installed successfully!")
end

-- Initialize
if TowerClass then
    setupMovingSkillHooks()
else
    warn("Could not load TowerClass - moving skills won't be recorded")
end

return {
    Setup = setupMovingSkillHooks,
    Config = MOVING_SKILL_TOWERS
}