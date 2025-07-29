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
    ["Helicopter"] = {1, 3},        -- Skill 1 và 3
    ["Cryo Helicopter"] = {1, 3},   -- Skill 1 và 3  
    ["Jet Trooper"] = {1}           -- Chỉ skill 1
}

-- File output và dữ liệu
local outJson = "tdx/macros/recorder_output.json"
local recordedActions = {}

-- Tạo thư mục
if makefolder then
    pcall(makefolder, "tdx")
    pcall(makefolder, "tdx/macros")
end

-- Hàm tiện ích
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

-- Ghi lại moving skill
local function recordMovingSkill(hash, skillIndex, targetPos)
    -- Skip nếu đang rebuild
    if _G and _G.TDX_REBUILD_RUNNING then return end
    
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
    
    -- Tạo entry
    local entry = {
        TowerMoving = towerX,
        SkillIndex = skillIndex,
        Location = string.format("%s, %s, %s", 
            tostring(targetPos.X), 
            tostring(targetPos.Y), 
            tostring(targetPos.Z)),
        Wave = currentWave,
        Time = convertTimeToNumber(currentTime)
    }
    
    table.insert(recordedActions, entry)
    updateJsonFile()
    
    print(string.format("✅ [Moving Skill] %s (X: %s) | Skill: %d | Wave: %s",
        towerType, tostring(towerX), skillIndex, currentWave or "N/A"))
end

-- Biến lưu hàm gốc
local originalInvokeServer

-- Hook function - Sử dụng cấu trúc giống script hoạt động của bạn
local function setupAbilityHook()
    if TowerUseAbilityRequest:IsA("RemoteFunction") then
        originalInvokeServer = hookfunction(TowerUseAbilityRequest.InvokeServer, function(self, ...)
            local args = {...}
            
            -- Ghi lại moving skill nếu có Vector3 position
            if #args >= 3 and typeof(args[1]) == "number" and typeof(args[2]) == "number" and typeof(args[3]) == "Vector3" then
                recordMovingSkill(args[1], args[2], args[3])
            end
            
            return originalInvokeServer(self, ...)
        end)
    end
    
    -- Hook namecall
    local originalNamecall
    originalNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if getnamecallmethod() == "InvokeServer" and self == TowerUseAbilityRequest then
            local args = {...}
            
            -- Ghi lại moving skill nếu có Vector3 position  
            if #args >= 3 and typeof(args[1]) == "number" and typeof(args[2]) == "number" and typeof(args[3]) == "Vector3" then
                recordMovingSkill(args[1], args[2], args[3])
            end
        end
        return originalNamecall(self, ...)
    end)
end

-- Khởi tạo
preserveExistingData()
setupAbilityHook()

print("✅ TDX Moving Skill Recorder Hook đã hoạt động!")
print("🎯 Đang theo dõi: Helicopter (skill 1,3), Cryo Helicopter (skill 1,3), Jet Trooper (skill 1)")
print("📁 Dữ liệu sẽ được ghi vào: " .. outJson)