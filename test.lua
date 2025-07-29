local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local PlayerScripts = player:WaitForChild("PlayerScripts")

-- Lấy các service cần thiết
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local TowerUseAbilityRequest = Remotes:WaitForChild("TowerUseAbilityRequest")

-- Lấy TowerClass để xác định loại tower
local TowerClass
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

-- File output
local outJson = "tdx/macros/recorder_output.json"
local recordedActions = {}

-- Tạo thư mục nếu chưa tồn tại
if makefolder then
    pcall(makefolder, "tdx")
    pcall(makefolder, "tdx/macros")
end

--==============================================================================
--=                           HÀM TIỆN ÍCH (HELPERS)                           =
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

-- Chuyển đổi chuỗi thời gian (vd: "1:23") thành số (vd: 123)
local function convertTimeToNumber(timeStr)
    if not timeStr then return nil end
    local mins, secs = timeStr:match("(%d+):(%d+)")
    if mins and secs then
        return tonumber(mins) * 100 + tonumber(secs)
    end
    return nil
end

-- Cập nhật file JSON với dữ liệu mới
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

-- Đọc file JSON hiện có để bảo toàn dữ liệu
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

-- Lấy loại tower từ hash
local function getTowerTypeFromHash(hash)
    if not TowerClass then return nil end
    
    local towers = TowerClass.GetTowers()
    local tower = towers[hash]
    return tower and tower.Type or nil
end

-- Lấy vị trí X của tower từ hash (để tương thích với format hiện có)
local function getTowerXFromHash(hash)
    if not TowerClass then return nil end
    
    local towers = TowerClass.GetTowers()
    local tower = towers[hash]
    if not tower then return nil end
    
    -- Thử lấy vị trí spawn
    if tower.SpawnCFrame and typeof(tower.SpawnCFrame) == "CFrame" then
        return tower.SpawnCFrame.Position.X
    end
    
    -- Thử lấy vị trí hiện tại
    local success, pos = pcall(function() return tower:GetPosition() end)
    if success and typeof(pos) == "Vector3" then
        return pos.X
    end
    
    return nil
end

-- Xử lý và ghi lại moving skill
local function recordMovingSkill(hash, skillIndex, targetPos)
    -- ==== ĐIỀU KIỆN NGĂN LOG HÀNH ĐỘNG KHI REBUILD ====
    if _G and _G.TDX_REBUILD_RUNNING then
        return
    end
    -- ==================================================
    
    local towerType = getTowerTypeFromHash(hash)
    if not towerType then return end
    
    -- Kiểm tra xem có phải tower cần ghi lại không
    local skillsToRecord = MOVING_SKILL_CONFIG[towerType]
    if not skillsToRecord then return end
    
    -- Kiểm tra xem skill index có trong danh sách cần ghi lại không
    local shouldRecord = false
    for _, allowedSkill in ipairs(skillsToRecord) do
        if skillIndex == allowedSkill then
            shouldRecord = true
            break
        end
    end
    
    if not shouldRecord then return end
    
    -- Lấy thông tin wave và time
    local currentWave, currentTime = getCurrentWaveAndTime()
    local towerX = getTowerXFromHash(hash)
    
    if not towerX or not targetPos then return end
    
    -- Tạo entry theo format yêu cầu
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
    
    -- Thêm vào recordedActions và cập nhật file
    table.insert(recordedActions, entry)
    updateJsonFile()
    
    print(string.format("✅ [Moving Skill Recorded] %s (X: %s) | Skill: %d | Pos: %s | Wave: %s | Time: %s",
        towerType, tostring(towerX), skillIndex, entry.Location, 
        currentWave or "N/A", currentTime or "N/A"))
end

--==============================================================================
--=                      SETUP HOOKS                                           =
--==============================================================================

local function setupMovingSkillHooks()
    if not hookfunction or not hookmetamethod or not checkcaller then
        warn("Executor không hỗ trợ đầy đủ các hàm hook cần thiết.")
        return
    end

    -- Hook InvokeServer cho TowerUseAbilityRequest
    if TowerUseAbilityRequest:IsA("RemoteFunction") then
        local originalInvokeServer = hookfunction(TowerUseAbilityRequest.InvokeServer, function(self, ...)
            local args = {...}
            
            -- Ghi lại moving skill nếu cần
            if #args >= 3 and typeof(args[1]) == "number" and typeof(args[2]) == "number" and typeof(args[3]) == "Vector3" then
                recordMovingSkill(args[1], args[2], args[3])
            end
            
            -- Trả về kết quả gốc
            return originalInvokeServer(self, ...)
        end)
    end
    
    -- Hook namecall để bắt mọi trường hợp
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if not checkcaller() and getnamecallmethod() == "InvokeServer" and self == TowerUseAbilityRequest then
            local args = {...}
            
            -- Ghi lại moving skill nếu cần
            if #args >= 3 and typeof(args[1]) == "number" and typeof(args[2]) == "number" and typeof(args[3]) == "Vector3" then
                recordMovingSkill(args[1], args[2], args[3])
            end
        end
        
        return oldNamecall(self, ...)
    end)
end

--==============================================================================
--=                         KHỞI TẠO                                           =
--==============================================================================

-- Bảo toàn dữ liệu hiện có
preserveExistingData()

-- Thiết lập hooks
setupMovingSkillHooks()

print("✅ TDX Moving Skill Recorder Hook đã hoạt động!")
print("🎯 Đang theo dõi: Helicopter (skill 1,3), Cryo Helicopter (skill 1,3), Jet Trooper (skill 1)")
print("📁 Dữ liệu sẽ được ghi vào: " .. outJson)