local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local PlayerScripts = player:WaitForChild("PlayerScripts")

-- Tận dụng logic từ recorder.lua
local outJson = "tdx/macros/moving_skills.json"

-- Xóa file cũ nếu tồn tại
if isfile and isfile(outJson) and delfile then
    local ok, err = pcall(delfile, outJson)
    if not ok then
        warn("Không thể xóa file cũ: " .. tostring(err))
    end
end

local recordedMovingSkills = {}
local hash2pos = {} -- Tái sử dụng từ recorder.lua

-- Lấy TowerClass (tái sử dụng logic)
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

-- Hàm ghi file an toàn (tái sử dụng)
local function safeWriteFile(path, content)
    if writefile then
        local success, err = pcall(writefile, path, content)
        if not success then
            warn("Lỗi khi ghi file: " .. tostring(err))
        end
    end
end

-- Lấy vị trí tower (tái sử dụng từ recorder.lua)
local function GetTowerPosition(tower)
    if not TowerClass or not tower then return nil end

    local success, cframe = pcall(function() return tower.CFrame end)
    if success and typeof(cframe) == "CFrame" then return cframe.Position end

    if tower.GetPosition then
        local posSuccess, position = pcall(tower.GetPosition, tower)
        if posSuccess and typeof(position) == "Vector3" then return position end
    end

    if tower.Character and tower.Character:GetCharacterModel() and tower.Character:GetCharacterModel().PrimaryPart then
        return tower.Character:GetCharacterModel().PrimaryPart.Position
    end

    return nil
end

-- Lấy thông tin wave và time (tái sử dụng từ recorder.lua)
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

-- Chuyển đổi time thành số (tái sử dụng)
local function convertTimeToNumber(timeStr)
    if not timeStr then return nil end
    local mins, secs = timeStr:match("(%d+):(%d+)")
    if mins and secs then
        return tonumber(mins) * 100 + tonumber(secs)
    end
    return nil
end

-- Cập nhật file JSON
local function updateJsonFile()
    if not HttpService then return end
    local jsonLines = {}
    for i, entry in ipairs(recordedMovingSkills) do
        local ok, jsonStr = pcall(HttpService.JSONEncode, HttpService, entry)
        if ok then
            if i < #recordedMovingSkills then
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
    -- Cryo Helicopter: skill 1
    if towerType == "Cryo Helicopter" then
        return skillIndex == 1
    end
    -- Jet Trooper: skill 1
    if towerType == "Jet Trooper" then
        return skillIndex == 1
    end
    return false
end

-- Lấy tower type từ hash
local function getTowerTypeFromHash(hash)
    if not TowerClass or not TowerClass.GetTowers then return nil end
    local towers = TowerClass.GetTowers()
    local tower = towers[hash]
    return tower and tower.Type or nil
end

-- Hook TowerUseAbilityRequest
local function setupMovingSkillHook()
    if not hookfunction or not hookmetamethod or not checkcaller then
        warn("Executor không hỗ trợ đầy đủ các hàm hook cần thiết.")
        return
    end

    local TowerUseAbilityRequest = ReplicatedStorage.Remotes:WaitForChild("TowerUseAbilityRequest")
    
    -- Hàm xử lý moving skill (giống handleRemote trong recorder.lua)
    local function handleMovingSkill(hash, skillIndex, targetPos)
        -- ==== ĐIỀU KIỆN NGĂN LOG HÀNH ĐỘNG KHI REBUILD ====
        if _G and _G.TDX_REBUILD_RUNNING then
            return
        end
        -- ==================================================
        
        if not targetPos then return end
        
        local towerType = getTowerTypeFromHash(hash)
        if not towerType or not isMovingSkill(towerType, skillIndex) then return end
        
        local currentWave, currentTime = getCurrentWaveAndTime()
        
        -- Lấy vị trí tower
        local towerPos = nil
        if TowerClass and TowerClass.GetTowers then
            local towers = TowerClass.GetTowers()
            local tower = towers[hash]
            if tower then
                towerPos = GetTowerPosition(tower)
            end
        end
        
        local entry = {
            TowerMoving = towerPos and towerPos.X or 0,
            SkillIndex = skillIndex,
            Location = string.format("%s, %s, %s", tostring(targetPos.X), tostring(targetPos.Y), tostring(targetPos.Z)),
            Wave = currentWave,
            Time = convertTimeToNumber(currentTime)
        }
        
        table.insert(recordedMovingSkills, entry)
        updateJsonFile()
        
        print("🎯 Đã ghi moving skill: " .. towerType .. " skill " .. skillIndex)
    end

    -- Hook namecall method (chỉ dùng namecall cho RemoteFunction)
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if checkcaller() then return oldNamecall(self, ...) end
        
        local method = getnamecallmethod()
        if method == "InvokeServer" and self == TowerUseAbilityRequest then
            local args = {...}
            -- CHỈ QUAN SÁT, KHÔNG SỬA ĐỔI
            handleMovingSkill(args[1], args[2], args[3])
        end
        
        -- GỌI GỐC VÀ RETURN
        return oldNamecall(self, ...)
    end)
    
    print("🪝 Hook setup completed!")
end

-- Vòng lặp cập nhật vị trí tower (tái sử dụng từ recorder.lua)
task.spawn(function() 
    while task.wait() do
        if TowerClass and TowerClass.GetTowers then
            for hash, tower in pairs(TowerClass.GetTowers()) do
                local pos = GetTowerPosition(tower)
                if pos then
                    hash2pos[tostring(hash)] = {x = pos.X, y = pos.Y, z = pos.Z}
                end
            end
        end
    end
end)

-- Khởi tạo
setupMovingSkillHook()

print("✅ TDX Moving Skill Recorder đã hoạt động!")
print("📁 Dữ liệu moving skills sẽ được ghi vào: " .. outJson)
print("🎯 Sẽ ghi lại: Helicopter (skill 1,3), Cryo Helicopter (skill 1), Jet Trooper (skill 1)")