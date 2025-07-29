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
    print("🔍 TowerUseAbilityRequest found:", TowerUseAbilityRequest)
    
    -- Hook InvokeServer trực tiếp (giống recorder.lua)
    local oldInvokeServer = hookfunction(TowerUseAbilityRequest.InvokeServer, function(self, ...)
        local args = {...}
        local hash, skillIndex, targetPos = args[1], args[2], args[3]
        
        -- DEBUG: In ra tất cả skill calls
        print("🔧 Skill call detected:", hash, skillIndex, targetPos and "with pos" or "no pos")
        
        -- Lấy tower type
        local towerType = getTowerTypeFromHash(hash)
        print("🏗️ Tower type:", towerType)
        
        -- Kiểm tra moving skill
        local isMoving = isMovingSkill(towerType, skillIndex)
        print("🎯 Is moving skill:", isMoving)
        
        -- GỌI FUNCTION GỐC TRƯỚC (quan trọng!)
        local result = oldInvokeServer(self, ...)
        
        -- XỬ LÝ SAU KHI GỌI GỐC
        if towerType and isMoving and targetPos then
            print("✅ Recording moving skill...")
            
            -- ==== ĐIỀU KIỆN NGĂN LOG HÀNH ĐỘNG KHI REBUILD ====
            if _G and _G.TDX_REBUILD_RUNNING then
                print("⏸️ Skipped due to rebuild running")
                return result
            end
            -- ==================================================
            
            local currentWave, currentTime = getCurrentWaveAndTime()
            print("📊 Wave/Time:", currentWave, currentTime)
            
            -- Lấy vị trí tower
            local towerPos = nil
            if TowerClass and TowerClass.GetTowers then
                local towers = TowerClass.GetTowers()
                local tower = towers[hash]
                if tower then
                    towerPos = GetTowerPosition(tower)
                    print("📍 Tower position:", towerPos)
                end
            end
            
            local entry = {
                TowerMoving = towerPos and towerPos.X or 0,
                SkillIndex = skillIndex,
                Location = string.format("%s, %s, %s", targetPos.X, targetPos.Y, targetPos.Z),
                Wave = currentWave,
                Time = convertTimeToNumber(currentTime)
            }
            
            table.insert(recordedMovingSkills, entry)
            updateJsonFile()
            
            print("🎯 ✅ Đã ghi moving skill: " .. towerType .. " skill " .. skillIndex)
            print("📄 Total entries:", #recordedMovingSkills)
        end
        
        -- Return kết quả từ function gốc
        return result
    end)

    -- Hook namecall method (backup)
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if checkcaller() then return oldNamecall(self, ...) end
        
        local method = getnamecallmethod()
        if method == "InvokeServer" and self == TowerUseAbilityRequest then
            local args = {...}
            local hash, skillIndex, targetPos = args[1], args[2], args[3]
            
            -- Lấy tower type
            local towerType = getTowerTypeFromHash(hash)
            
            -- GỌI FUNCTION GỐC TRƯỚC
            local result = oldNamecall(self, ...)
            
            -- XỬ LÝ SAU KHI GỌI GỐC
            if towerType and isMovingSkill(towerType, skillIndex) and targetPos then
                -- ==== ĐIỀU KIỆN NGĂN LOG HÀNH ĐỘNG KHI REBUILD ====
                if _G and _G.TDX_REBUILD_RUNNING then
                    return result
                end
                -- ==================================================
                
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
                    Location = string.format("%s, %s, %s", targetPos.X, targetPos.Y, targetPos.Z),
                    Wave = currentWave,
                    Time = convertTimeToNumber(currentTime)
                }
                
                table.insert(recordedMovingSkills, entry)
                updateJsonFile()
                
                print("🎯 Đã ghi moving skill: " .. towerType .. " skill " .. skillIndex)
            end
            
            return result
        end
        
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