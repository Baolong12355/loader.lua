local replStorage = game:GetService("ReplicatedStorage")
local remotes = replStorage:WaitForChild("Remotes")
local TowerUseAbilityRequest = remotes:WaitForChild("TowerUseAbilityRequest")
local localPlayer = game:GetService("Players").LocalPlayer
local PlayerScripts = localPlayer:WaitForChild("PlayerScripts")
local HttpService = game:GetService("HttpService")

-- Biến lưu hàm gốc
local originalInvokeServer

-- Đường dẫn file output
local outJson = "tdx/macros/recorder_output.json"

-- Lấy TowerClass để ánh xạ hash tới tower type
local TowerClass
pcall(function()
    local client = PlayerScripts:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    TowerClass = require(towerModule)
end)

-- Tạo thư mục nếu chưa tồn tại
pcall(function() makefolder("tdx") end)
pcall(function() makefolder("tdx/macros") end)

-- Hàm ghi file an toàn
local function safeWriteFile(path, content)
    if writefile then
        local success, err = pcall(writefile, path, content)
        if not success then
            warn("Lỗi khi ghi file: " .. tostring(err))
        end
    end
end

-- Hàm đọc file an toàn
local function safeReadFile(path)
    if isfile and isfile(path) and readfile then
        local success, content = pcall(readfile, path)
        if success then
            return content
        end
    end
    return ""
end

-- Lấy thông tin wave và thời gian hiện tại
local function getCurrentWaveAndTime()
    local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
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

-- Đọc file JSON hiện có
local function loadExistingActions()
    local content = safeReadFile(outJson)
    if content == "" then return {} end

    local ok, decoded = pcall(HttpService.JSONDecode, HttpService, content)
    if ok and type(decoded) == "table" then
        return decoded
    end
    return {}
end

-- Cập nhật file JSON với entry mới
local function addMovingSkillEntry(entry)
    local existingActions = loadExistingActions()
    table.insert(existingActions, entry)
    
    local ok, jsonStr = pcall(HttpService.JSONEncode, HttpService, existingActions)
    if ok then
        safeWriteFile(outJson, jsonStr)
    end
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
        time = timeNumber
    }
    
    -- Ghi vào file
    addMovingSkillEntry(entry)
    
    print(string.format("✅ Recorded moving skill: %s (X=%.1f) skill %d -> (%.1f, %.1f, %.1f) at wave %s time %s", 
        towerType, towerX, skillIndex, targetPos.X, targetPos.Y, targetPos.Z, currentWave or "?", currentTime or "?"))
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

-- Khởi tạo hook
setupAbilityHook()

print("✅ TDX Moving Skills Recorder Hook đã hoạt động!")
print("🎯 Tracking: Helicopter (skill 1,3), Cryo Helicopter (skill 1,3), Jet Trooper (skill 1)")
print("📁 Dữ liệu sẽ được ghi vào: " .. outJson)