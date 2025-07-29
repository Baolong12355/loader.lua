local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local PlayerScripts = player:WaitForChild("PlayerScripts")

-- XÓA FILE CŨ NẾU ĐÃ TỒN TẠI TRƯỚC KHI GHI RECORD
local outJson = "tdx/macros/recorder_output.json"

-- Xóa file nếu đã tồn tại
if isfile and isfile(outJson) and delfile then
    local ok, err = pcall(delfile, outJson)
    if not ok then
        warn("Không thể xóa file cũ: " .. tostring(err))
    end
end

local recordedActions = {} -- Bảng lưu trữ tất cả các hành động dưới dạng table
local hash2pos = {} -- Ánh xạ hash của tower tới vị trí Vector3

-- Hàng đợi và cấu hình cho việc ghi nhận
local pendingQueue = {}
local timeout = 2
local lastKnownLevels = {} -- { [towerHash] = {path1Level, path2Level} }
local lastUpgradeTime = {} -- { [towerHash] = timestamp } để phát hiện upgrade sinh đôi

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

-- Lấy vị trí tower từ hash
local function getTowerPositionFromHash(hash)
    if not TowerClass or not TowerClass.GetTowers then return nil end
    
    local towers = TowerClass.GetTowers()
    local tower = towers[hash]
    if not tower then return nil end
    
    return GetTowerPosition(tower)
end

-- Lấy loại tower từ hash
local function getTowerTypeFromHash(hash)
    if not TowerClass or not TowerClass.GetTowers then return nil end
    
    local towers = TowerClass.GetTowers()
    local tower = towers[hash]
    return tower and tower.Type or nil
end

-- [SỬA LỖI] Lấy chi phí đặt tower dựa trên tên, sử dụng FindFirstChild
local function GetTowerPlaceCostByName(name)
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return 0 end

    -- Sử dụng chuỗi FindFirstChild thay vì FindFirstDescendant để đảm bảo tương thích
    local interface = playerGui:FindFirstChild("Interface")
    if not interface then return 0 end
    local bottomBar = interface:FindFirstChild("BottomBar")
    if not bottomBar then return 0 end
    local towersBar = bottomBar:FindFirstChild("TowersBar")
    if not towersBar then return 0 end

    for _, towerButton in ipairs(towersBar:GetChildren()) do
        if towerButton.Name == name then
            -- Tương tự, sử dụng FindFirstChild ở đây
            local costFrame = towerButton:FindFirstChild("CostFrame")
            if costFrame then
                local costText = costFrame:FindFirstChild("CostText")
                if costText and costText:IsA("TextLabel") then
                    local raw = tostring(costText.Text):gsub("%D", "")
                    return tonumber(raw) or 0
                end
            end
        end
    end
    return 0
end

-- [SỬA LỖI] Lấy thông tin wave và thời gian hiện tại, sử dụng FindFirstChild
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

-- Kiểm tra xem có phải skill di chuyển không
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

-- Phân tích một dòng lệnh macro và trả về một bảng dữ liệu
local function parseMacroLine(line)
    -- Phân tích lệnh đặt tower
    local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*Vector3%.new%(([^,]+),%s*([^,]+),%s*([^%)]+)%)%s*,%s*([^%)]+)%)')
    if a1 and name and x and y and z and rot then
        name = tostring(name):gsub('^%s*"(.-)"%s*$', '%1')
        return {{
            TowerPlaceCost = GetTowerPlaceCostByName(name),
            TowerPlaced = name,
            TowerVector = string.format("%s, %s, %s", x, y, z),
            Rotation = rot,
            TowerA1 = a1
        }}
    end

    -- Phân tích lệnh nâng cấp tower
    local hash, path, upgradeCount = line:match('TDX:upgradeTower%(([^,]+),%s*([^,]+),%s*([^%)]+)%)')
    if hash and path and upgradeCount then
        local pos = hash2pos[tostring(hash)]
        local pathNum, count = tonumber(path), tonumber(upgradeCount)
        if pos and pathNum and count and count > 0 then
            local entries = {}
            for _ = 1, count do
                table.insert(entries, {
                    UpgradeCost = 0, -- Chi phí nâng cấp sẽ được tính toán bởi trình phát lại
                    UpgradePath = pathNum,
                    TowerUpgraded = pos.x
                })
            end
            return entries
        end
    end

    -- Phân tích lệnh thay đổi mục tiêu
    local hash, targetType = line:match('TDX:changeQueryType%(([^,]+),%s*([^%)]+)%)')
    if hash and targetType then
        local pos = hash2pos[tostring(hash)]
        if pos then
            local currentWave, currentTime = getCurrentWaveAndTime()
            local entry = {
                TowerTargetChange = pos.x,
                TargetWanted = tonumber(targetType),
                TargetWave = currentWave,
                TargetChangedAt = convertTimeToNumber(currentTime)
            }
            return {entry}
        end
    end

    -- Phân tích lệnh bán tower
    local hash = line:match('TDX:sellTower%(([^%)]+)%)')
    if hash then
        local pos = hash2pos[tostring(hash)]
        if pos then
            return {{ SellTower = pos.x }}
        end
    end

    return nil
end

-- Xử lý một dòng lệnh, phân tích và ghi vào file JSON
local function processAndWriteAction(commandString)
    -- ==== ĐIỀU KIỆN NGĂN LOG HÀNH ĐỘNG KHI REBUILD ====
    if _G and _G.TDX_REBUILD_RUNNING then
        return
    end
    -- ==================================================
    local entries = parseMacroLine(commandString)
    if entries then
        for _, entry in ipairs(entries) do
            table.insert(recordedActions, entry)
        end
        updateJsonFile()
    end
end

-- Ghi record moving skill với format đúng
local function recordMovingSkill(hash, skillIndex, targetPos, towerType)
    -- ==== ĐIỀU KIỆN NGĂN LOG HÀNH ĐỘNG KHI REBUILD ====
    if _G and _G.TDX_REBUILD_RUNNING then
        return
    end
    -- ==================================================
    
    local towerPos = getTowerPositionFromHash(hash)
    if not towerPos then return end
    
    local wave, time = getCurrentWaveAndTime()
    
    local skillRecord = {
        towermoving = towerPos.X,
        skillindex = skillIndex,
        location = string.format("%.1f, %.1f, %.1f", targetPos.X, targetPos.Y, targetPos.Z),
        wave = wave,
        time = time
    }
    
    table.insert(recordedActions, skillRecord)
    updateJsonFile()
    
    print(string.format("📝 Recorded moving skill: %s (%.1f) skill %d -> %s", 
        towerType, towerPos.X, skillIndex, skillRecord.location))
end

--==============================================================================
--=                      XỬ LÝ SỰ KIỆN & HOOKS                                 =
--==============================================================================

-- Thêm một yêu cầu vào hàng đợi chờ xác nhận
local function setPending(typeStr, code, hash)
    table.insert(pendingQueue, {
        type = typeStr,
        code = code,
        created = tick(),
        hash = hash
    })
end

-- Xác nhận một yêu cầu từ hàng đợi và xử lý nó
local function tryConfirm(typeStr, specificHash)
    for i = #pendingQueue, 1, -1 do
        local item = pendingQueue[i]
        if item.type == typeStr then
            if not specificHash or string.find(item.code, tostring(specificHash)) then
                processAndWriteAction(item.code) -- Thay thế việc ghi file txt
                table.remove(pendingQueue, i)
                return
            end
        end
    end
end

-- Xử lý sự kiện đặt/bán tower
ReplicatedStorage.Remotes.TowerFactoryQueueUpdated.OnClientEvent:Connect(function(data)
    local d = data and data[1]
    if not d then return end
    if d.Creation then
        tryConfirm("Place")
    else
        tryConfirm("Sell")
    end
end)

-- Xử lý sự kiện nâng cấp tower
ReplicatedStorage.Remotes.TowerUpgradeQueueUpdated.OnClientEvent:Connect(function(data)
    if not data or not data[1] then return end

    local towerData = data[1]
    local hash = towerData.Hash
    local newLevels = towerData.LevelReplicationData
    local currentTime = tick()

    -- Chống upgrade sinh đôi
    if lastUpgradeTime[hash] and (currentTime - lastUpgradeTime[hash]) < 0.0001 then
        return
    end
    lastUpgradeTime[hash] = currentTime

    local upgradedPath, upgradeCount = nil, 0
    if lastKnownLevels[hash] then
        for path = 1, 2 do
            local oldLevel = lastKnownLevels[hash][path] or 0
            local newLevel = newLevels[path] or 0
            if newLevel > oldLevel then
                upgradedPath = path
                upgradeCount = newLevel - oldLevel
                break
            end
        end
    end

    if upgradedPath and upgradeCount > 0 then
        local code = string.format("TDX:upgradeTower(%s, %d, %d)", tostring(hash), upgradedPath, upgradeCount)
        processAndWriteAction(code) -- Thay thế việc ghi file txt

        -- Xóa các yêu cầu nâng cấp đang chờ cho tower này
        for i = #pendingQueue, 1, -1 do
            if pendingQueue[i].type == "Upgrade" and pendingQueue[i].hash == hash then
                table.remove(pendingQueue, i)
            end
        end
    else
        tryConfirm("Upgrade", hash)
    end

    lastKnownLevels[hash] = newLevels or {}
end)

-- Xử lý sự kiện thay đổi mục tiêu
ReplicatedStorage.Remotes.TowerQueryTypeIndexChanged.OnClientEvent:Connect(function(data)
    if data and data[1] then
        tryConfirm("Target")
    end
end)

-- Xử lý các lệnh gọi remote
local function handleRemote(name, args)
    -- ==== ĐIỀU KIỆN NGĂN LOG HÀNH ĐỘNG KHI REBUILD ====
    if _G and _G.TDX_REBUILD_RUNNING then
        return
    end
    -- ==================================================

    if name == "TowerUpgradeRequest" then
        local hash, path, count = unpack(args)
        if typeof(hash) == "number" and typeof(path) == "number" and typeof(count) == "number" and path >= 0 and path <= 2 and count > 0 and count <= 5 then
            setPending("Upgrade", string.format("TDX:upgradeTower(%s, %d, %d)", tostring(hash), path, count), hash)
        end
    elseif name == "PlaceTower" then
        local a1, towerName, vec, rot = unpack(args)
        if typeof(a1) == "number" and typeof(towerName) == "string" and typeof(vec) == "Vector3" and typeof(rot) == "number" then
            local code = string.format('TDX:placeTower(%s, "%s", Vector3.new(%s, %s, %s), %s)', tostring(a1), towerName, tostring(vec.X), tostring(vec.Y), tostring(vec.Z), tostring(rot))
            setPending("Place", code)
        end
    elseif name == "SellTower" then
        setPending("Sell", "TDX:sellTower("..tostring(args[1])..")")
    elseif name == "ChangeQueryType" then
        setPending("Target", string.format("TDX:changeQueryType(%s, %s)", tostring(args[1]), tostring(args[2])))
    end
end

-- Hook các hàm remote (giữ nguyên logic như script gốc)
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

    -- Hook InvokeServer  
    local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
        handleRemote(self.Name, {...})
        return oldInvokeServer(self, ...)
    end)

    -- Hook namecall (sử dụng logic như script gốc của bạn)
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if not checkcaller() then
            local method = getnamecallmethod()
            if method == "FireServer" or method == "InvokeServer" then
                handleRemote(self.Name, {...})
            end
            
            -- Xử lý riêng TowerUseAbilityRequest như script gốc của bạn
            if method == "InvokeServer" and self.Name == "TowerUseAbilityRequest" then
                local args = {...}
                if #args >= 3 then
                    local hash = args[1]
                    local skillIndex = args[2] 
                    local targetPos = args[3]
                    
                    if typeof(hash) == "number" and typeof(skillIndex) == "number" and typeof(targetPos) == "Vector3" then
                        local towerType = getTowerTypeFromHash(hash)
                        if towerType and isMovingSkill(towerType, skillIndex) then
                            recordMovingSkill(hash, skillIndex, targetPos, towerType)
                        end
                    end
                end
            end
        end
        return oldNamecall(self, ...)
    end)
end

--==============================================================================
--=                         VÒNG LẶP & KHỞI TẠO                               =
--==============================================================================

-- Vòng lặp dọn dẹp hàng đợi chờ
task.spawn(function()
    while task.wait(0.5) do
        local now = tick()
        for i = #pendingQueue, 1, -1 do
            if now - pendingQueue[i].created > timeout then
                warn("❌ Không xác thực được: " .. pendingQueue[i].type .. " | Code: " .. pendingQueue[i].code)
                table.remove(pendingQueue, i)
            end
        end
    end
end)

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

print("✅ TDX Recorder với Moving Skills đã hoạt động!")
print("🎯 Đang theo dõi moving skills: Helicopter (1,3), Cryo Helicopter (1,3), Jet Trooper (1)")
print("📁 Dữ liệu sẽ được ghi trực tiếp vào: " .. outJson)