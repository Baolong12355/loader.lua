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
local function cacheToMemory(entry)
    -- ==== ĐIỀU KIỆN NGĂN LOG HÀNH ĐỘNG KHI REBUILD ====
    if _G and _G.TDX_REBUILD_RUNNING then
        return
    end
    -- ==================================================
    
    table.insert(movingSkillsCache, entry)
    print(string.format("📋 Cached: %s", entry))
end

-- Hook nguyên mẫu cho Ability Request
local function setupAbilityHook()
    if TowerUseAbilityRequest:IsA("RemoteFunction") then
        originalInvokeServer = hookfunction(TowerUseAbilityRequest.InvokeServer, function(self, ...)
            local args = {...}

            -- Kiểm tra moving skill
            if #args >= 3 and typeof(args[1]) == "number" and typeof(args[2]) == "number" and typeof(args[3]) == "Vector3" then
                local hash = args[1]
                local skillIndex = args[2]
                local targetPos = args[3]
                
                local towerType = getTowerTypeFromHash(hash)
                local isMovingSkill = false
                
                if towerType == "Helicopter" and (skillIndex == 1 or skillIndex == 3) then
                    isMovingSkill = true
                elseif towerType == "Cryo Helicopter" and (skillIndex == 1 or skillIndex == 3) then
                    isMovingSkill = true
                elseif towerType == "Jet Trooper" and skillIndex == 1 then
                    isMovingSkill = true
                end
                
                if isMovingSkill then
                    local towerX = getTowerXFromHash(hash)
                    local currentWave, currentTime = getCurrentWaveAndTime()
                    local timeNumber = convertTimeToNumber(currentTime)
                    
                    local logText = string.format("towermoving=%s|skillindex=%s|location=%s,%s,%s|wave=%s|time=%s",
                        tostring(towerX),
                        tostring(skillIndex),
                        tostring(targetPos.X),
                        tostring(targetPos.Y), 
                        tostring(targetPos.Z),
                        tostring(currentWave),
                        tostring(timeNumber))
                    cacheToMemory(logText)
                end
            end

            return originalInvokeServer(self, ...)
        end)
    end

    -- Hook namecall để bắt mọi trường hợp
    local originalNamecall
    originalNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if getnamecallmethod() == "InvokeServer" and self == TowerUseAbilityRequest then
            local args = {...}

            -- Kiểm tra moving skill
            if #args >= 3 and typeof(args[1]) == "number" and typeof(args[2]) == "number" and typeof(args[3]) == "Vector3" then
                local hash = args[1]
                local skillIndex = args[2]
                local targetPos = args[3]
                
                local towerType = getTowerTypeFromHash(hash)
                local isMovingSkill = false
                
                if towerType == "Helicopter" and (skillIndex == 1 or skillIndex == 3) then
                    isMovingSkill = true
                elseif towerType == "Cryo Helicopter" and (skillIndex == 1 or skillIndex == 3) then
                    isMovingSkill = true
                elseif towerType == "Jet Trooper" and skillIndex == 1 then
                    isMovingSkill = true
                end
                
                if isMovingSkill then
                    local towerX = getTowerXFromHash(hash)
                    local currentWave, currentTime = getCurrentWaveAndTime()
                    local timeNumber = convertTimeToNumber(currentTime)
                    
                    local logText = string.format("towermoving=%s|skillindex=%s|location=%s,%s,%s|wave=%s|time=%s",
                        tostring(towerX),
                        tostring(skillIndex),
                        tostring(targetPos.X),
                        tostring(targetPos.Y),
                        tostring(targetPos.Z),
                        tostring(currentWave),
                        tostring(timeNumber))
                    cacheToMemory(logText)
                end
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
    
    exportToFile = function(filename)
        filename = filename or "tdx/moving_skills_export.txt"
        pcall(function() makefolder("tdx") end)
        
        local content = table.concat(movingSkillsCache, "\n")
        if writefile then
            pcall(writefile, filename, content)
            print("💾 Exported " .. #movingSkillsCache .. " moving skills to: " .. filename)
        end
    end
}

-- Khởi tạo hook
setupAbilityHook()

print("✅ TDX Moving Skills Hook activated - Ready to track moving skills")
