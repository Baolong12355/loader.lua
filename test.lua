local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local PlayerScripts = player:WaitForChild("PlayerScripts")

local replStorage = game:GetService("ReplicatedStorage")
local remotes = replStorage:WaitForChild("Remotes")
local TowerUseAbilityRequest = remotes:WaitForChild("TowerUseAbilityRequest")
local localPlayer = game:GetService("Players").LocalPlayer

-- Biến lưu hàm gốc
local originalInvokeServer

-- Cache để lưu moving skills thay vì ghi file
local movingSkillsCache = {}

-- Lấy TowerClass để ánh xạ hash tới tower type
local TowerClass
pcall(function()
    local client = PlayerScripts:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    TowerClass = require(towerModule)
end)

-- Lấy thông tin wave và thời gian hiện tại
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

-- Chuyển đổi chuỗi thời gian thành số
local function convertTimeToNumber(timeStr)
    if not timeStr then return nil end
    local mins, secs = timeStr:match("(%d+):(%d+)")
    if mins and secs then
        return tonumber(mins) * 100 + tonumber(secs)
    end
    return nil
end

-- Lấy tower type từ hash
local function getTowerTypeFromHash(hash)
    if not TowerClass then return nil end
    local towers = TowerClass.GetTowers()
    local tower = towers[hash]
    return tower and tower.Type or nil
end

-- Lấy vị trí X của tower từ hash
local function getTowerXFromHash(hash)
    if not TowerClass then return nil end
    local towers = TowerClass.GetTowers()
    local tower = towers[hash]
    if tower and tower.SpawnCFrame then
        return tower.SpawnCFrame.Position.X
    end
    return nil
end

-- Cache moving skill thay vì ghi file
local function cacheMovingSkill(entry)
    table.insert(movingSkillsCache, entry)
    print(string.format("📋 Cached moving skill: %s (X=%.1f) skill %d -> (%.1f, %.1f, %.1f) at wave %s", 
        entry.towerType or "Unknown", entry.towermoving, entry.skillindex, 
        entry.location.x, entry.location.y, entry.location.z, entry.wave or "?"))
end

-- Xử lý khi phát hiện moving skill
local function handleMovingSkill(hash, skillIndex, targetPos)
    -- ==== ĐIỀU KIỆN NGĂN LOG HÀNH ĐỘNG KHI REBUILD ====
    if _G and _G.TDX_REBUILD_RUNNING then
        return
    end
    -- ==================================================
    
    local towerType = getTowerTypeFromHash(hash)
    if not towerType then return end
    
    -- Kiểm tra xem có phải tower moving skill không
    local isMovingSkill = false
    
    if towerType == "Helicopter" and (skillIndex == 1 or skillIndex == 3) then
        isMovingSkill = true
    elseif towerType == "Cryo Helicopter" and (skillIndex == 1 or skillIndex == 3) then
        isMovingSkill = true
    elseif towerType == "Jet Trooper" and skillIndex == 1 then
        isMovingSkill = true
    end
    
    if not isMovingSkill then return end
    
    local towerX = getTowerXFromHash(hash)
    if not towerX then return end
    
    local currentWave, currentTime = getCurrentWaveAndTime()
    local timeNumber = convertTimeToNumber(currentTime)
    
    -- Tạo entry theo format yêu cầu
    local entry = {
        towermoving = towerX,
        skillindex = skillIndex,
        location = {
            x = targetPos.X,
            y = targetPos.Y,
            z = targetPos.Z
        },
        wave = currentWave,
        time = timeNumber,
        towerType = towerType -- Thêm để debug
    }
    
    -- Cache thay vì ghi file
    cacheMovingSkill(entry)
end

-- Hook nguyên mẫu cho Ability Request
local function setupAbilityHook()
    if TowerUseAbilityRequest:IsA("RemoteFunction") then
        originalInvokeServer = hookfunction(TowerUseAbilityRequest.InvokeServer, function(self, ...)
            local args = {...}

            -- Xử lý moving skill nếu có đủ args
            if #args >= 3 and typeof(args[1]) == "number" and typeof(args[2]) == "number" and typeof(args[3]) == "Vector3" then
                handleMovingSkill(args[1], args[2], args[3])
            end

            return originalInvokeServer(self, ...)
        end)
    end

    -- Hook namecall để bắt mọi trường hợp
    local originalNamecall
    originalNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if getnamecallmethod() == "InvokeServer" and self == TowerUseAbilityRequest then
            local args = {...}

            -- Xử lý moving skill nếu có đủ args
            if #args >= 3 and typeof(args[1]) == "number" and typeof(args[2]) == "number" and typeof(args[3]) == "Vector3" then
                handleMovingSkill(args[1], args[2], args[3])
            end
        end
        return originalNamecall(self, ...)
    end)
end

-- API để truy cập cache
_G.TDX_MovingSkills = {
    getCache = function()
        return movingSkillsCache
    end,
    
    clearCache = function()
        movingSkillsCache = {}
        print("🗑️ Moving skills cache cleared")
    end,
    
    getCacheCount = function()
        return #movingSkillsCache
    end,
    
    getLastSkill = function()
        return movingSkillsCache[#movingSkillsCache]
    end,
    
    -- Chuyển đổi cache thành format recorder
    convertToRecorderFormat = function()
        local converted = {}
        for _, entry in ipairs(movingSkillsCache) do
            table.insert(converted, {
                towermoving = entry.towermoving,
                skillindex = entry.skillindex,
                location = string.format("%.1f, %.1f, %.1f", entry.location.x, entry.location.y, entry.location.z),
                wave = entry.wave,
                time = entry.time
            })
        end
        return converted
    end,
    
    -- Xuất cache ra file JSON
    exportToFile = function(filename)
        filename = filename or "tdx/macros/moving_skills_export.json"
        pcall(function() makefolder("tdx") end)
        pcall(function() makefolder("tdx/macros") end)
        
        local converted = _G.TDX_MovingSkills.convertToRecorderFormat()
        local ok, jsonStr = pcall(HttpService.JSONEncode, HttpService, converted)
        if ok and writefile then
            pcall(writefile, filename, jsonStr)
            print("💾 Exported " .. #converted .. " moving skills to: " .. filename)
            return true
        end
        return false
    end,
    
    -- Tích hợp vào recorder output
    integrateToRecorder = function()
        local outJson = "tdx/macros/recorder_output.json"
        if not (readfile and isfile and isfile(outJson)) then
            print("❌ Recorder output file not found")
            return false
        end
        
        local content = ""
        pcall(function() content = readfile(outJson) end)
        
        local existingActions = {}
        if content ~= "" then
            local ok, decoded = pcall(HttpService.JSONDecode, HttpService, content)
            if ok and type(decoded) == "table" then
                existingActions = decoded
            end
        end
        
        -- Thêm moving skills vào
        for _, entry in ipairs(_G.TDX_MovingSkills.convertToRecorderFormat()) do
            table.insert(existingActions, entry)
        end
        
        local ok, jsonStr = pcall(HttpService.JSONEncode, HttpService, existingActions)
        if ok and writefile then
            pcall(writefile, outJson, jsonStr)
            print("🔄 Integrated " .. #movingSkillsCache .. " moving skills into recorder output")
            return true
        end
        return false
    end
}

-- Khởi tạo hook
setupAbilityHook()

print("✅ TDX Moving Skills Recorder Hook đã hoạt động!")
print("🎯 Tracking: Helicopter (skill 1,3), Cryo Helicopter (skill 1,3), Jet Trooper (skill 1)")
print("📋 Dữ liệu được cache trong memory - Sử dụng _G.TDX_MovingSkills để truy cập")
print("🔧 Commands available:")
print("   _G.TDX_MovingSkills.getCache() - Xem cache")
print("   _G.TDX_MovingSkills.exportToFile() - Xuất ra file") 
print("   _G.TDX_MovingSkills.integrateToRecorder() - Tích hợp vào recorder")