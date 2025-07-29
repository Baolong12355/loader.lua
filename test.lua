local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

-- Remote setup
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local TowerUseAbilityRequest = remotes:WaitForChild("TowerUseAbilityRequest")

-- Tower configuration
local MOVING_SKILL_CONFIG = {
    ["Helicopter"] = {1, 3},        -- Skill 1 (with vector), skill 3 (no vector)
    ["Cryo Helicopter"] = {1, 3},   -- Skill 1 (with vector), skill 3 (no vector)
    ["Jet Trooper"] = {1}           -- Skill 1 (with vector)
}

-- Cache and file setup
local outJson = "tdx/macros/recorder_output.json"
local actionCache = {}
local cacheLock = false
local lastProcessTime = 0

-- Create directories if needed
if makefolder then
    pcall(makefolder, "tdx")
    pcall(makefolder, "tdx/macros")
end

-- ========================
-- CORE FUNCTIONALITY
-- ========================

local function safeWriteFile(path, content)
    if writefile then
        local success, err = pcall(writefile, path, content)
        if not success then
            warn("File write error: "..tostring(err))
        end
    end
end

local function safeReadFile(path)
    if isfile and isfile(path) and readfile then
        local success, content = pcall(readfile, path)
        if success then return content end
    end
    return nil
end

local function getCurrentWaveAndTime()
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return nil, nil end
    
    local interface = playerGui:FindFirstChild("Interface")
    if not interface then return nil, nil end
    
    local gameInfoBar = interface:FindFirstChild("GameInfoBar")
    if not gameInfoBar then return nil, nil end
    
    return gameInfoBar.Wave.WaveText.Text, gameInfoBar.TimeLeft.TimeLeftText.Text
end

local function processCache()
    if cacheLock or #actionCache == 0 then return end
    cacheLock = true
    
    -- Load existing data
    local existingData = {}
    local fileContent = safeReadFile(outJson)
    if fileContent then
        local success, decoded = pcall(HttpService.JSONDecode, HttpService, fileContent)
        if success and type(decoded) == "table" then
            existingData = decoded
        end
    end
    
    -- Merge new actions
    for _, action in ipairs(actionCache) do
        table.insert(existingData, action)
    end
    
    -- Save back to file
    local success, json = pcall(HttpService.JSONEncode, HttpService, existingData)
    if success then
        safeWriteFile(outJson, json)
        actionCache = {}
        print(string.format("💾 Saved %d actions to file", #actionCache))
    end
    
    cacheLock = false
    lastProcessTime = os.time()
end

-- ========================
-- HOOK IMPLEMENTATION
-- ========================

local originalInvoke
local originalNamecall

local function shouldRecordSkill(towerType, skillIndex)
    local config = MOVING_SKILL_CONFIG[towerType]
    if not config then return false end
    
    for _, allowedSkill in ipairs(config) do
        if skillIndex == allowedSkill then
            return true
        end
    end
    return false
end

local function createSkillRecord(hash, skillIndex, targetPos)
    -- Get tower info
    local towerType, towerX
    if TowerClass and TowerClass.GetTowers then
        local tower = TowerClass.GetTowers()[hash]
        if tower then
            towerType = tower.Type
            if tower.SpawnCFrame then
                towerX = tower.SpawnCFrame.Position.X
            end
        end
    end
    
    if not towerType or not towerX then return nil end
    
    -- Get current game state
    local wave, timeStr = getCurrentWaveAndTime()
    local timeNum = nil
    if timeStr then
        local mins, secs = timeStr:match("(%d+):(%d+)")
        if mins and secs then
            timeNum = tonumber(mins) * 100 + tonumber(secs)
        end
    end
    
    -- Format position
    local locationStr
    if targetPos then
        locationStr = string.format("%.2f, %.2f, %.2f", targetPos.X, targetPos.Y, targetPos.Z)
    else
        locationStr = "0, 0, 0"
    end
    
    return {
        TowerMoving = towerX,
        SkillIndex = skillIndex,
        Location = locationStr,
        Wave = wave or "?",
        Time = timeNum or 0,
        Timestamp = os.time()
    }
end

local function handleSkillInvocation(method, self, ...)
    -- Skip if rebuild is running
    if _G and _G.TDX_REBUILD_RUNNING then return end
    
    -- Only process TowerUseAbilityRequest
    if self ~= TowerUseAbilityRequest then return end
    
    local args = {...}
    if #args < 2 then return end
    
    local hash, skillIndex = args[1], args[2]
    local targetPos = #args >= 3 and args[3] or nil
    
    -- Create record
    local record = createSkillRecord(hash, skillIndex, targetPos)
    if not record then return end
    
    -- Add to cache
    table.insert(actionCache, record)
    print(string.format("📝 [Skill Recorded] %s (X:%.1f) skill %d at %s", 
        record.TowerType or "?", record.TowerMoving or 0, 
        skillIndex, record.Location))
    
    -- Process cache periodically
    if os.time() - lastProcessTime > 5 or #actionCache > 20 then
        task.spawn(processCache)
    end
end

local function setupHooks()
    -- Hook InvokeServer
    if TowerUseAbilityRequest:IsA("RemoteFunction") then
        originalInvoke = hookfunction(TowerUseAbilityRequest.InvokeServer, function(self, ...)
            handleSkillInvocation("InvokeServer", self, ...)
            return originalInvoke(self, ...)
        end)
    end
    
    -- Hook namecall
    originalNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if getnamecallmethod() == "InvokeServer" and self == TowerUseAbilityRequest then
            handleSkillInvocation("Namecall", self, ...)
        end
        return originalNamecall(self, ...)
    end)
end

-- ========================
-- INITIALIZATION
-- ========================

-- Load TowerClass
local TowerClass
local success, err = pcall(function()
    local PlayerScripts = player:WaitForChild("PlayerScripts")
    local client = PlayerScripts:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    TowerClass = require(towerModule)
end)

if not TowerClass then
    warn("Could not load TowerClass - limited functionality")
end

-- Set up periodic cache processing
task.spawn(function()
    while true do
        processCache()
        task.wait(10) -- Process cache every 10 seconds
    end
end)

-- Initialize hooks
setupHooks()

print("🚀 Moving Skill Recorder Initialized")
print("📌 Tracking:", table.concat(table.keys(MOVING_SKILL_CONFIG), ", "))
print("💾 Output:", outJson)