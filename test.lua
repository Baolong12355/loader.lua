local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer

-- Lấy remote
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local TowerUseAbilityRequest = remotes:WaitForChild("TowerUseAbilityRequest")

-- Lấy TowerClass
local TowerClass
local PlayerScripts = player:WaitForChild("PlayerScripts")
pcall(function()
    local client = PlayerScripts:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    TowerClass = require(towerModule)
end)

-- Cấu hình các tower và skill cần ghi lại
local MOVING_SKILL_CONFIG = {
    ["Helicopter"] = {1, 3},        -- Skill 1 (có vector), skill 3 (không có vector)
    ["Cryo Helicopter"] = {1, 3},   -- Skill 1 (có vector), skill 3 (không có vector)
    ["Jet Trooper"] = {1}           -- Skill 1 (có vector)
}

-- File output và dữ liệu
local outJson = "tdx/macros/recorder_output.json"
local recordedActions = {}

-- Tạo thư mục
if makefolder then
    pcall(makefolder, "tdx")
    pcall(makefolder, "tdx/macros")
end

-- Hàm tiện ích (sử dụng từ main.lua)
local function serialize(value)
    if type(value) == "table" then
        local result = "{"
        for k, v in pairs(value) do
            result = result .. "[" .. serialize(k) .. "]=" .. serialize(v) .. ", "
        end
        if result ~= "{" then
            result = result:sub(1, -3)
        end
        return result .. "}"
    else
        return tostring(value)
    end
end

local function serializeArgs(...)
    local args = {...}
    local strArgs = {}
    for i, v in ipairs(args) do
        strArgs[i] = serialize(v)
    end
    return table.concat(strArgs, ", ")
end

local function safeWriteFile(path, content)
    if writefile then
        pcall(writefile, path, content)
    end
end

local function safeReadFile(path)
    if isfile and isfile(path) and readfile then
        local success, content = pcall(readfile, path)
        if success then return content end
    end
    return ""
end

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

local function convertTimeToNumber(timeStr)
    if not timeStr then return nil end
    local mins, secs = timeStr:match("(%d+):(%d+)")
    if mins and secs then
        return tonumber(mins) * 100 + tonumber(secs)
    end
    return nil
end

local function updateJsonFile()
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
    safeWriteFile(outJson, finalJson)
end

-- Đọc dữ liệu hiện có
local function preserveExistingData()
    local content = safeReadFile(outJson)
    if content == "" then return end
    content = content:gsub("^%[%s*", ""):gsub("%s*%]$", "")
    for line in content:gmatch("[^\r\n]+") do
        line = line:gsub(",$", "")
        if line:match("%S") then
            local ok, decoded = pcall(HttpService.JSONDecode, HttpService, line)
            if ok and decoded then
                table.insert(recordedActions, decoded)
            end
        end
    end
    if #recordedActions > 0 then
        updateJsonFile()
    end
end

-- Lấy tower info
local function getTowerInfo(hash)
    if not TowerClass then return nil, nil end
    local towers = TowerClass.GetTowers()
    local tower = towers[hash]
    if not tower then return nil, nil end
    
    local towerType = tower.Type
    local towerX = nil
    
    if tower.SpawnCFrame and typeof(tower.SpawnCFrame) == "CFrame" then
        towerX = tower.SpawnCFrame.Position.X
    else
        local success, pos = pcall(function() return tower:GetPosition() end)
        if success and typeof(pos) == "Vector3" then
            towerX = pos.X
        end
    end
    
    return towerType, towerX
end

-- Lấy vị trí hiện tại của tower
local function getTowerCurrentPosition(hash)
    if not TowerClass then return nil end
    local towers = TowerClass.GetTowers()
    local tower = towers[hash]
    if not tower then return nil end
    
    local success, pos = pcall(function() return tower:GetPosition() end)
    if success and typeof(pos) == "Vector3" then
        return pos
    end
    return nil
end

-- Function log moving skill - sử dụng logic từ main.lua
local function logMovingSkill(method, self, serializedArgs)
    -- Skip nếu đang rebuild
    if _G and _G.TDX_REBUILD_RUNNING then return end
    
    -- Chỉ xử lý TowerUseAbilityRequest
    if self.Name ~= "TowerUseAbilityRequest" then return end
    
    -- Parse args từ serializedArgs string
    local args = {}
    local argString = serializedArgs
    
    -- Extract hash (first number)
    local hash = tonumber(argString:match("^([^,]+)"))
    if not hash then return end
    args[1] = hash
    
    -- Extract skill index (second number)  
    local remaining = argString:match("^[^,]+,%s*(.+)")
    if not remaining then return end
    local skillIndex = tonumber(remaining:match("^([^,]+)"))
    if not skillIndex then return end
    args[2] = skillIndex
    
    -- Extract Vector3 if exists (third argument)
    local remaining2 = remaining:match("^[^,]+,%s*(.+)")
    local targetPos = nil
    if remaining2 and remaining2:match("Vector3") then
        -- Parse Vector3 from string format
        local x, y, z = remaining2:match("Vector3%.new%(([^,]+),%s*([^,]+),%s*([^%)]+)%)")
        if x and y and z then
            targetPos = Vector3.new(tonumber(x), tonumber(y), tonumber(z))
        end
    end
    
    -- Debug output
    print(string.format("🔍 [Raw Hook] %s | Hash: %s | Skill: %s | Has Vector: %s", 
        method, tostring(hash), tostring(skillIndex), tostring(targetPos ~= nil)))
    
    -- Xử lý ghi lại skill
    local towerType, towerX = getTowerInfo(hash)
    if not towerType or not towerX then return end
    
    -- Kiểm tra tower có cần ghi lại không
    local skillsToRecord = MOVING_SKILL_CONFIG[towerType]
    if not skillsToRecord then return end
    
    -- Kiểm tra skill index
    local shouldRecord = false
    for _, allowedSkill in ipairs(skillsToRecord) do
        if skillIndex == allowedSkill then
            shouldRecord = true
            break
        end
    end
    if not shouldRecord then return end
    
    -- Lấy wave và time
    local currentWave, currentTime = getCurrentWaveAndTime()
    
    -- Xử lý position
    local locationStr
    if targetPos then
        locationStr = string.format("%s, %s, %s", 
            tostring(targetPos.X), 
            tostring(targetPos.Y), 
            tostring(targetPos.Z))
    else
        -- Skill không có vector - dùng vị trí hiện tại
        local currentPos = getTowerCurrentPosition(hash)
        if currentPos then
            locationStr = string.format("%s, %s, %s", 
                tostring(currentPos.X), 
                tostring(currentPos.Y), 
                tostring(currentPos.Z))
        else
            locationStr = "0, 0, 0"
        end
    end
    
    -- Tạo entry
    local entry = {
        TowerMoving = towerX,
        SkillIndex = skillIndex,
        Location = locationStr,
        Wave = currentWave,
        Time = convertTimeToNumber(currentTime)
    }
    
    table.insert(recordedActions, entry)
    updateJsonFile()
    
    print(string.format("✅ [Moving Skill] %s (X: %s) | Skill: %d | Location: %s | Wave: %s",
        towerType, tostring(towerX), skillIndex, locationStr, currentWave or "N/A"))
end

-- Hook system từ main.lua
local function setupMovingSkillLogger()
    -- Hook FireServer
    local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
        local serializedArgs = serializeArgs(...)
        logMovingSkill("FireServer", self, serializedArgs)
        return oldFireServer(self, ...)
    end)
   
    -- Hook InvokeServer
    local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
        local serializedArgs = serializeArgs(...)
        logMovingSkill("InvokeServer", self, serializedArgs)
        return oldInvokeServer(self, ...)
    end)
    
    -- Hook namecall
    local oldNameCall
    oldNameCall = hookmetamethod(game, "__namecall", function(self, ...)    
        local namecallmethod = getnamecallmethod()
        
        if namecallmethod == "FireServer" or namecallmethod == "InvokeServer" then
            local serializedArgs = serializeArgs(...)
            logMovingSkill(namecallmethod, self, serializedArgs)
        end
 
        return oldNameCall(self, ...)
    end)
end

-- Khởi tạo
preserveExistingData()
setupMovingSkillLogger()

print("✅ TDX Moving Skill Recorder Hook đã hoạt động!")
print("🎯 Đang theo dõi:")
print("   - Helicopter: skill 1 (có vector), skill 3 (không vector)")
print("   - Cryo Helicopter: skill 1 (có vector), skill 3 (không vector)")  
print("   - Jet Trooper: skill 1 (có vector)")
print("📁 Dữ liệu sẽ được ghi vào: " .. outJson)
print("🔧 Sử dụng hook system từ main.lua")