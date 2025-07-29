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

-- Lấy vị trí hiện tại của tower (để ghi lại cho skill không có vector)
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
    
    -- Xử lý position - nếu không có targetPos thì dùng vị trí hiện tại của tower
    local locationStr
    if targetPos and typeof(targetPos) == "Vector3" then
        locationStr = string.format("%s, %s, %s", 
            tostring(targetPos.X), 
            tostring(targetPos.Y), 
            tostring(targetPos.Z))
    else
        -- Skill không có vector (như Helicopter skill 3) - dùng vị trí hiện tại
        local currentPos = getTowerCurrentPosition(hash)
        if currentPos then
            locationStr = string.format("%s, %s, %s", 
                tostring(currentPos.X), 
                tostring(currentPos.Y), 
                tostring(currentPos.Z))
        else
            locationStr = "0, 0, 0" -- Fallback
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

-- Biến lưu hàm gốc
local originalInvokeServer

-- Hook function - Hook thô trước, xử lý sau
local function setupAbilityHook()
    if TowerUseAbilityRequest:IsA("RemoteFunction") then
        originalInvokeServer = hookfunction(TowerUseAbilityRequest.InvokeServer, function(self, ...)
            local args = {...}
            
            -- Hook thô - in ra console để debug
            print(string.format("🔍 [Raw Hook] Hash: %s | Skill: %s | Args count: %d", 
                tostring(args[1]), tostring(args[2]), #args))
            if args[3] then
                print(string.format("   Arg3 type: %s | Value: %s", typeof(args[3]), tostring(args[3])))
            end
            
            -- Xử lý ghi lại skill
            if #args >= 2 and typeof(args[1]) == "number" and typeof(args[2]) == "number" then
                -- args[3] có thể là Vector3 hoặc nil/khác
                local targetPos = (typeof(args[3]) == "Vector3") and args[3] or nil
                recordMovingSkill(args[1], args[2], targetPos)
            end
            
            -- Trả về kết quả gốc
            return originalInvokeServer(self, ...)
        end)
    end
    
    -- Hook namecall
    local originalNamecall
    originalNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if getnamecallmethod() == "InvokeServer" and self == TowerUseAbilityRequest then
            local args = {...}
            
            -- Hook thô - in ra console để debug
            print(string.format("🔸 [Namecall Hook] Hash: %s | Skill: %s | Args count: %d", 
                tostring(args[1]), tostring(args[2]), #args))
            if args[3] then
                print(string.format("   Arg3 type: %s | Value: %s", typeof(args[3]), tostring(args[3])))
            end
            
            -- Xử lý ghi lại skill
            if #args >= 2 and typeof(args[1]) == "number" and typeof(args[2]) == "number" then
                local targetPos = (typeof(args[3]) == "Vector3") and args[3] or nil
                recordMovingSkill(args[1], args[2], targetPos)
            end
        end
        return originalNamecall(self, ...)
    end)
end

-- Khởi tạo
preserveExistingData()
setupAbilityHook()

print("✅ TDX Moving Skill Recorder Hook đã hoạt động!")
print("🎯 Đang theo dõi:")
print("   - Helicopter: skill 1 (có vector), skill 3 (không vector)")
print("   - Cryo Helicopter: skill 1 (có vector), skill 3 (không vector)")  
print("   - Jet Trooper: skill 1 (có vector)")
print("📁 Dữ liệu sẽ được ghi vào: " .. outJson)