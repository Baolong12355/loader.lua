local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local PlayerScripts = player:WaitForChild("PlayerScripts")

-- File output path
local outJson = "tdx/macros/moving_skills_only.json"

-- Xóa file cũ nếu đã tồn tại
if isfile and isfile(outJson) and delfile then
    local ok, err = pcall(delfile, outJson)
    if not ok then
        warn("Không thể xóa file cũ: " .. tostring(err))
    end
end

local recordedSkills = {} -- Bảng lưu trữ moving skills

-- Lấy TowerClass một cách an toàn
local TowerClass
pcall(function()
    local client = PlayerScripts:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    TowerClass = require(towerModule)
end)

-- Tạo thư mục nếu chưa tồn tại
if makefolder then
    pcall(makefolder, "tdx")
    pcall(makefolder, "tdx/macros")
end

--==============================================================================
--=                           HÀM TIỆN ÍCH                                     =
--==============================================================================

-- Hàm ghi file an toàn
local function safeWriteFile(path, content)
    if writefile then
        local success, err = pcall(writefile, path, content)
        if not success then
            warn("Lỗi khi ghi file: " .. tostring(err))
        end
    end
end

-- Lấy thông tin wave và time hiện tại
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

-- Lấy vị trí spawn của tower
local function GetTowerSpawnPosition(tower)
    if not tower then return nil end
    
    -- Thử lấy SpawnCFrame trước
    if tower.SpawnCFrame and typeof(tower.SpawnCFrame) == "CFrame" then
        return tower.SpawnCFrame.Position
    end
    
    -- Fallback: thử các phương thức khác
    local success, cframe = pcall(function() return tower.CFrame end)
    if success and typeof(cframe) == "CFrame" then 
        return cframe.Position 
    end

    if tower.GetPosition then
        local posSuccess, position = pcall(tower.GetPosition, tower)
        if posSuccess and typeof(position) == "Vector3" then 
            return position 
        end
    end

    if tower.Character and tower.Character:GetCharacterModel() and tower.Character:GetCharacterModel().PrimaryPart then
        return tower.Character:GetCharacterModel().PrimaryPart.Position
    end

    return nil
end

-- Cập nhật file JSON
local function updateJsonFile()
    if not HttpService then return end
    local jsonLines = {}
    for i, entry in ipairs(recordedSkills) do
        local ok, jsonStr = pcall(HttpService.JSONEncode, HttpService, entry)
        if ok then
            if i < #recordedSkills then
                jsonStr = jsonStr .. ","
            end
            table.insert(jsonLines, jsonStr)
        end
    end
    local finalJson = "[\n" .. table.concat(jsonLines, "\n") .. "\n]"
    safeWriteFile(outJson, finalJson)
end

-- Kiểm tra xem có phải moving skill không
local function isMovingSkill(towerType, skillIndex)
    -- Helicopter: skill 1, 3
    if towerType == "Helicopter" then
        return skillIndex == 1 or skillIndex == 3
    end
    
    -- Cryo Helicopter: skill 1, 3  
    if towerType == "Cryo Helicopter" then
        return skillIndex == 1 or skillIndex == 3
    end
    
    -- Jet Trooper: skill 1
    if towerType == "Jet Trooper" then
        return skillIndex == 1
    end
    
    return false
end

--==============================================================================
--=                         HOOK SYSTEM GIỐNG RECORDER                         =
--==============================================================================

-- Hàng đợi chờ xác nhận cho moving skills
local pendingMovingSkills = {}
local movingSkillTimeout = 2

-- Thêm moving skill vào hàng đợi chờ
local function setPendingMovingSkill(hash, skillIndex, targetPos)
    table.insert(pendingMovingSkills, {
        hash = hash,
        skillIndex = skillIndex,
        targetPos = targetPos,
        created = tick()
    })
end

-- Xác nhận và ghi moving skill
local function confirmMovingSkill(hash, skillIndex, targetPos)
    -- ==== ĐIỀU KIỆN NGĂN LOG HÀNH ĐỘNG KHI REBUILD ====
    if _G and _G.TDX_REBUILD_RUNNING then
        return
    end
    -- ==================================================
    
    if not TowerClass then return end
    
    local towers = TowerClass.GetTowers()
    if not towers or not towers[hash] then return end
    
    local tower = towers[hash]
    local towerType = tower.Type
    
    -- Kiểm tra xem có phải moving skill không
    if not isMovingSkill(towerType, skillIndex) then return end
    
    local spawnPos = GetTowerSpawnPosition(tower)
    if not spawnPos then return end
    
    local currentWave, currentTime = getCurrentWaveAndTime()
    
    local skillRecord = {
        x = spawnPos.X, -- vị trí tower (tower moving position)
        skill_index = skillIndex,
        pos = string.format("%.6f, %.6f, %.6f", targetPos.X, targetPos.Y, targetPos.Z), -- vị trí đích (target location)
        wave = currentWave,
        time = currentTime
    }
    
    table.insert(recordedSkills, skillRecord)
    updateJsonFile()
    
    print(string.format("[Moving Skill] %s (tower x=%.1f) skill %d -> target pos(%.1f, %.1f, %.1f) | Wave: %s Time: %s", 
        towerType, spawnPos.X, skillIndex, targetPos.X, targetPos.Y, targetPos.Z, currentWave or "?", currentTime or "?"))
end

-- Xử lý remote calls (giống như trong recorder chính)
local function handleRemote(name, args)
    -- ==== ĐIỀU KIỆN NGĂN LOG HÀNH ĐỘNG KHI REBUILD ====
    if _G and _G.TDX_REBUILD_RUNNING then
        return
    end
    -- ==================================================

    if name == "TowerUseAbilityRequest" then
        local hash, skillIndex, targetPos = args[1], args[2], args[3]
        if typeof(hash) == "number" and typeof(skillIndex) == "number" and typeof(targetPos) == "Vector3" then
            -- Thêm vào pending queue
            setPendingMovingSkill(hash, skillIndex, targetPos)
            -- Confirm ngay lập tức (không cần chờ event như upgrade)
            confirmMovingSkill(hash, skillIndex, targetPos)
        end
    end
end

-- Hook các hàm remote (giống như recorder chính)
local function setupHooks()
    if not hookfunction or not hookmetamethod or not checkcaller then
        warn("Executor không hỗ trợ đầy đủ các hàm hook cần thiết.")
        return
    end

    -- Hook FireServer
    local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
        handleRemote(self.Name, {...})
        return oldFireServer(self, ...)
    end)

    -- Hook InvokeServer (TowerUseAbilityRequest sử dụng InvokeServer)
    local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
        handleRemote(self.Name, {...})
        return oldInvokeServer(self, ...)
    end)

    -- Hook namecall
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if checkcaller() then return oldNamecall(self, ...) end
        local method = getnamecallmethod()
        if method == "FireServer" or method == "InvokeServer" then
            handleRemote(self.Name, {...})
        end
        return oldNamecall(self, ...)
    end)
end

--==============================================================================
--=                         VÒNG LẶP DỌN DẸP                                   =
--==============================================================================

-- Vòng lặp dọn dẹp hàng đợi chờ (giống như recorder chính)
task.spawn(function()
    while task.wait(0.5) do
        local now = tick()
        for i = #pendingMovingSkills, 1, -1 do
            if now - pendingMovingSkills[i].created > movingSkillTimeout then
                warn("❌ Moving skill timeout: " .. tostring(pendingMovingSkills[i].hash) .. " skill " .. tostring(pendingMovingSkills[i].skillIndex))
                table.remove(pendingMovingSkills, i)
            end
        end
    end
end)

--==============================================================================
--=                         KHỞI TẠO                                           =
--==============================================================================

setupHooks()

print("✅ TDX Moving Skills Hook Only đã hoạt động!")
print("🎯 Chỉ hook: Helicopter (skill 1,3), Cryo Helicopter (skill 1,3), Jet Trooper (skill 1)")
print("📍 Format: x=tower position, pos=target location")
print("🔧 Hook TowerUseAbilityRequest với InvokeServer")
print("📁 Dữ liệu sẽ được ghi vào: " .. outJson)