local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local PlayerScripts = player:WaitForChild("PlayerScripts")

-- XÓA FILE CŨ NẾU ĐÃ TỒN TẠI TRƯỚC KHI GHI RECORD
local outJson = "tdx/macros/moving_skills_output.json"

-- Xóa file nếu đã tồn tại
if isfile and isfile(outJson) and delfile then
    local ok, err = pcall(delfile, outJson)
    if not ok then
        warn("Không thể xóa file cũ: " .. tostring(err))
    end
end

local recordedActions = {} -- Bảng lưu trữ tất cả các moving skill dưới dạng table
local hash2pos = {} -- Ánh xạ hash của tower tới vị trí Vector3

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

-- Lấy vị trí của một tower
local function GetTowerPosition(tower)
    if not TowerClass or not tower then return nil end

    -- Thử nhiều phương thức để có được vị trí chính xác
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

-- Lấy thông tin wave và thời gian hiện tại, sử dụng FindFirstChild
local function getCurrentWaveAndTime()
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return nil, nil end

    -- Sử dụng chuỗi FindFirstChild thay vì FindFirstDescendant
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

-- Đọc file JSON hiện có để bảo toàn các "SuperFunction"
local function preserveSuperFunctions()
    local content = safeReadFile(outJson)
    if content == "" then return end

    content = content:gsub("^%[%s*", ""):gsub("%s*%]$", "")
    for line in content:gmatch("[^\r\n]+") do
        line = line:gsub(",$", "")
        if line:match("%S") then
            local ok, decoded = pcall(HttpService.JSONDecode, HttpService, line)
            if ok and decoded and decoded.SuperFunction then
                table.insert(recordedActions, decoded)
            end
        end
    end
    if #recordedActions > 0 then
        updateJsonFile() -- Cập nhật lại file để đảm bảo định dạng đúng
    end
end

-- Lấy tower type từ hash
local function getTowerTypeByHash(hash)
    if not TowerClass then return nil end
    for towerHash, tower in pairs(TowerClass.GetTowers()) do
        if towerHash == hash then
            return tower.Type
        end
    end
    return nil
end

-- Kiểm tra xem có phải moving skill không
local function isMovingSkill(towerType, skillIndex)
    local movingSkills = {
        ["Helicopter"] = {[1] = true, [3] = true},
        ["Cryo Helicopter"] = {[1] = true, [3] = true},
        ["Jet Trooper"] = {[1] = true}
    }
    
    if movingSkills[towerType] then
        return movingSkills[towerType][skillIndex] == true
    end
    return false
end

-- Xử lý và ghi moving skill
local function processMovingSkill(hash, skillIndex, targetPos)
    -- ==== ĐIỀU KIỆN NGĂN LOG HÀNH ĐỘNG KHI REBUILD ====
    if _G and _G.TDX_REBUILD_RUNNING then
        return
    end
    -- ==================================================
    
    local towerType = getTowerTypeByHash(hash)
    if not towerType then return end
    
    if not isMovingSkill(towerType, skillIndex) then return end
    
    local towerPos = hash2pos[tostring(hash)]
    if not towerPos then return end
    
    local currentWave, currentTime = getCurrentWaveAndTime()
    
    local entry = {
        TowerMoving = towerPos.x,
        SkillIndex = skillIndex,
        Location = string.format("%s, %s, %s", targetPos.X, targetPos.Y, targetPos.Z),
        Wave = currentWave,
        Time = convertTimeToNumber(currentTime)
    }
    
    table.insert(recordedActions, entry)
    updateJsonFile()
    
    print("✅ Recorded moving skill: " .. towerType .. " skill " .. skillIndex .. " to " .. entry.Location)
end

--==============================================================================
--=                      XỬ LÝ SỰ KIỆN & HOOKS                                 =
--==============================================================================

-- Hook TowerUseAbilityRequest
local function setupHooks()
    if not hookfunction or not hookmetamethod or not checkcaller then
        warn("Executor không hỗ trợ đầy đủ các hàm hook cần thiết.")
        return
    end

    -- Hook namecall để bắt TowerUseAbilityRequest
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local args = {...}
        local method = getnamecallmethod()
        
        -- Kiểm tra nếu đây là TowerUseAbilityRequest và là InvokeServer
        if method == "InvokeServer" and self.Name == "TowerUseAbilityRequest" then
            if not checkcaller() then
                -- args[1] = hash, args[2] = skillIndex, args[3] = targetPos (Vector3)
                local hash = args[1]
                local skillIndex = args[2] 
                local targetPos = args[3]
                
                if typeof(hash) == "number" and typeof(skillIndex) == "number" and typeof(targetPos) == "Vector3" then
                    processMovingSkill(hash, skillIndex, targetPos)
                end
            end
        end
        
        -- Trả về giá trị gốc
        return oldNamecall(self, ...)
    end)
end

--==============================================================================
--=                         VÒNG LẶP & KHỞI TẠO                               =
--==============================================================================

-- Vòng lặp cập nhật vị trí tower
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
preserveSuperFunctions()
setupHooks()

print("✅ TDX Moving Skill Recorder đã hoạt động!")
print("📁 Dữ liệu moving skills sẽ được ghi vào: " .. outJson)
print("🎯 Đang theo dõi moving skills của: Helicopter (skill 1,3), Cryo Helicopter (skill 1,3), Jet Trooper (skill 1)")