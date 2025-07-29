local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local PlayerScripts = player:WaitForChild("PlayerScripts")

-- Tận dụng logic từ recorder.lua
local outJson = "tdx/macros/moving_skills.json"

-- Xóa file cũ nếu tồn tại - Safe deletion
if safeIsFile(outJson) then
    local deleteResult = safeDelFile(outJson)
    if deleteResult then
        print("🗑️ Đã xóa file moving skills cũ")
    end
end

local recordedMovingSkills = {}
local hash2pos = {} -- Tái sử dụng từ recorder.lua

-- Lấy TowerClass (tái sử dụng logic) - Safe loading cho executor
local TowerClass
local function SafeRequire(path, timeout)
    timeout = timeout or 5
    local startTime = tick()
    while tick() - startTime < timeout do
        local success, result = pcall(function() return require(path) end)
        if success and result then return result end
        wait(0.1)
    end
    return nil
end

local function LoadTowerClass()
    local ps = player:FindFirstChild("PlayerScripts")
    if not ps then return nil end
    local client = ps:FindFirstChild("Client")
    if not client then return nil end
    local gameClass = client:FindFirstChild("GameClass")
    if not gameClass then return nil end
    local towerModule = gameClass:FindFirstChild("TowerClass")
    if not towerModule then return nil end
    return SafeRequire(towerModule)
end

TowerClass = LoadTowerClass()
if not TowerClass then 
    warn("Không thể load TowerClass - đảm bảo bạn đang trong game TDX")
    return
end

-- Tạo thư mục nếu chưa tồn tại - Safe folder creation
local function safeMakeFolder(path)
    if makefolder and typeof(makefolder) == "function" then
        local success = pcall(makefolder, path)
        return success
    end
    return false
end

safeMakeFolder("tdx")
safeMakeFolder("tdx/macros")

-- Hàm ghi file an toàn - Universal compatibility
local function safeWriteFile(path, content)
    if writefile and typeof(writefile) == "function" then
        local success, err = pcall(writefile, path, content)
        if not success then
            warn("Lỗi khi ghi file: " .. tostring(err))
        end
        return success
    end
    warn("writefile không được hỗ trợ bởi executor này")
    return false
end

-- Kiểm tra file tồn tại - Universal compatibility  
local function safeIsFile(path)
    if isfile and typeof(isfile) == "function" then
        local success, result = pcall(isfile, path)
        return success and result or false
    end
    return false
end

-- Xóa file an toàn - Universal compatibility
local function safeDelFile(path)
    if delfile and typeof(delfile) == "function" then
        local success, err = pcall(delfile, path)
        if not success then
            warn("Không thể xóa file: " .. tostring(err))
        end
        return success
    end
    return false
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

-- Hook TowerUseAbilityRequest - Universal executor compatibility
local function setupMovingSkillHook()
    -- Kiểm tra khả năng hook của executor
    if not hookmetamethod or typeof(hookmetamethod) ~= "function" then
        warn("❌ Executor không hỗ trợ hookmetamethod - cần executor có hook functions")
        return false
    end
    
    if not checkcaller or typeof(checkcaller) ~= "function" then
        warn("❌ Executor không hỗ trợ checkcaller - một số chức năng có thể không hoạt động")
    end
    
    if not getnamecallmethod or typeof(getnamecallmethod) ~= "function" then
        warn("❌ Executor không hỗ trợ getnamecallmethod - hook sẽ không hoạt động")
        return false
    end

    local success, TowerUseAbilityRequest = pcall(function()
        return ReplicatedStorage.Remotes:WaitForChild("TowerUseAbilityRequest", 10)
    end)
    
    if not success or not TowerUseAbilityRequest then
        warn("❌ Không thể tìm thấy TowerUseAbilityRequest - đảm bảo bạn đang trong game TDX")
        return false
    end
    
    print("🔍 TowerUseAbilityRequest found:", TowerUseAbilityRequest)
    
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

    -- Hook namecall method (universal compatibility)
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        -- Safe checkcaller
        if checkcaller and checkcaller() then 
            return oldNamecall(self, ...) 
        end
        
        local method = getnamecallmethod()
        if method == "InvokeServer" and self == TowerUseAbilityRequest then
            local args = {...}
            -- CHỈ QUAN SÁT, KHÔNG SỬA ĐỔI
            local success = pcall(handleMovingSkill, args[1], args[2], args[3])
            if not success then
                warn("Lỗi khi xử lý moving skill")
            end
        end
        
        -- GỌI GỐC VÀ RETURN
        return oldNamecall(self, ...)
    end)
    
    print("🪝 Hook setup completed!")
    return true
end

-- Vòng lặp cập nhật vị trí tower - Safe spawn
spawn(function()
    while true do
        if TowerClass and TowerClass.GetTowers then
            local success = pcall(function()
                for hash, tower in pairs(TowerClass.GetTowers()) do
                    local pos = GetTowerPosition(tower)
                    if pos then
                        hash2pos[tostring(hash)] = {x = pos.X, y = pos.Y, z = pos.Z}
                    end
                end
            end)
            if not success then
                wait(1) -- Chờ lâu hơn nếu có lỗi
            end
        end
        wait(0.5) -- Tần suất cập nhật hợp lý
    end
end)

-- Khởi tạo - Safe initialization
local hookSuccess = setupMovingSkillHook()

if hookSuccess then
    print("✅ TDX Moving Skill Recorder đã hoạt động!")
    print("📁 Dữ liệu moving skills sẽ được ghi vào: " .. outJson)
    print("🎯 Sẽ ghi lại: Helicopter (skill 1,3), Cryo Helicopter (skill 1), Jet Trooper (skill 1)")
    print("🔧 Executor compatibility: OK")
else
    warn("❌ Không thể khởi tạo Moving Skill Recorder - kiểm tra executor compatibility")
end