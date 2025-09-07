local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
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
local hash2pos = {} -- Ánh xạ hash của tower tới vị trí SpawnCFrame

-- THÊM: Universal compatibility functions
local function getGlobalEnv()
    if getgenv then return getgenv() end
    if getfenv then return getfenv() end
    return _G
end

local globalEnv = getGlobalEnv()

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

-- SỬA: Lấy vị trí SpawnCFrame của tower (thay vì position hiện tại)
local function GetTowerSpawnPosition(tower)
    if not tower then return nil end

    -- Sử dụng SpawnCFrame để khớp với Runner
    local spawnCFrame = tower.SpawnCFrame
    if spawnCFrame and typeof(spawnCFrame) == "CFrame" then
        return spawnCFrame.Position
    end

    return nil
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

-- Chuyển đổi chuỗi thời gian (vd: "1:23") thành số (vd: 123)
local function convertTimeToNumber(timeStr)
    if not timeStr then return nil end
    local mins, secs = timeStr:match("(%d+):(%d+)")
    if mins and secs then
        return tonumber(mins) * 100 + tonumber(secs)
    end
    return nil
end

-- THÊM: Lấy tên tower từ hash
local function GetTowerNameByHash(towerHash)
    if not TowerClass or not TowerClass.GetTowers then return nil end
    local towers = TowerClass.GetTowers()
    local tower = towers[towerHash]
    if tower and tower.Type then
        return tower.Type
    end
    return nil
end

-- THÊM: Kiểm tra xem tower có phải moving skill tower không
local function IsMovingSkillTower(towerName, skillIndex)
    if not towerName or not skillIndex then return false end

    -- Helicopter: skill 1, 3
    if towerName == "Helicopter" and (skillIndex == 1 or skillIndex == 3) then
        return true
    end

    -- Cryo Helicopter: skill 1, 3  
    if towerName == "Cryo Helicopter" and (skillIndex == 1 or skillIndex == 3) then
        return true
    end

    -- Jet Trooper: skill 1
    if towerName == "Jet Trooper" and skillIndex == 1 then
        return true
    end

    return false
end

-- THÊM: Kiểm tra skill có cần position không
local function IsPositionRequiredSkill(towerName, skillIndex)
    if not towerName or not skillIndex then return false end

    -- Skill 1: cần position (moving skill)
    if skillIndex == 1 then
        return true
    end

    -- Skill 3: không cần position (buff/ability skill)
    if skillIndex == 3 then
        return false
    end

    return true -- mặc định cần position
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
    -- THÊM: Phân tích lệnh skip wave
    if line:match('TDX:skipWave%(%)') then
        local currentWave, currentTime = getCurrentWaveAndTime()
        return {{
            SkipWave = currentWave,
            SkipWhen = convertTimeToNumber(currentTime)
        }}
    end

    -- THÊM: Phân tích lệnh moving skill WITH position
    local hash, skillIndex, x, y, z = line:match('TDX:useMovingSkill%(([^,]+),%s*([^,]+),%s*Vector3%.new%(([^,]+),%s*([^,]+),%s*([^%)]+)%)%)')
    if hash and skillIndex and x and y and z then
        local pos = hash2pos[tostring(hash)]
        if pos then
            local currentWave, currentTime = getCurrentWaveAndTime()
            return {{
                towermoving = pos.x,
                skillindex = tonumber(skillIndex),
                location = string.format("%s, %s, %s", x, y, z),
                wave = currentWave,
                time = convertTimeToNumber(currentTime)
            }}
        end
    end

    -- THÊM: Phân tích lệnh skill WITHOUT position (skill 3)
    local hash, skillIndex = line:match('TDX:useSkill%(([^,]+),%s*([^%)]+)%)')
    if hash and skillIndex then
        local pos = hash2pos[tostring(hash)]
        if pos then
            local currentWave, currentTime = getCurrentWaveAndTime()
            return {{
                towermoving = pos.x,
                skillindex = tonumber(skillIndex),
                location = "no_pos", -- skill 3 không có position
                wave = currentWave,
                time = convertTimeToNumber(currentTime)
            }}
        end
    end

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
    -- SỬA: Cải thiện điều kiện ngăn log hành động khi rebuild
    if globalEnv.TDX_REBUILDING_TOWERS then
        -- Phân tích command để lấy axis X
        local axisX = nil

        -- Kiểm tra nếu là PlaceTower
        local a1, towerName, vec, rot = commandString:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*Vector3%.new%(([^,]+),%s*([^,]+),%s*([^%)]+)%)%s*,%s*([^%)]+)%)')
        if vec then
            axisX = tonumber(vec)
        end

        -- Kiểm tra nếu là UpgradeTower
        if not axisX then
            local hash = commandString:match('TDX:upgradeTower%(([^,]+),')
            if hash then
                local pos = hash2pos[tostring(hash)]
                if pos then
                    axisX = pos.x
                end
            end
        end

        -- Kiểm tra nếu là ChangeQueryType
        if not axisX then
            local hash = commandString:match('TDX:changeQueryType%(([^,]+),')
            if hash then
                local pos = hash2pos[tostring(hash)]
                if pos then
                    axisX = pos.x
                end
            end
        end

        -- Kiểm tra nếu là UseMovingSkill
        if not axisX then
            local hash = commandString:match('TDX:useMovingSkill%(([^,]+),')
            if not hash then
                hash = commandString:match('TDX:useSkill%(([^,]+),')
            end
            if hash then
                local pos = hash2pos[tostring(hash)]
                if pos then
                    axisX = pos.x
                end
            end
        end

        -- Nếu tower đang được rebuild thì bỏ qua log
        if axisX and globalEnv.TDX_REBUILDING_TOWERS[axisX] then
            return
        end
    end

    -- Tiếp tục xử lý bình thường nếu không phải rebuild
    local entries = parseMacroLine(commandString)
    if entries then
        for _, entry in ipairs(entries) do
            table.insert(recordedActions, entry)
        end
        updateJsonFile()
    end
end

--==============================================================================
--=                      XỬ LÝ SỰ KIỆN & HOOKS                                 =
--==============================================================================

-- Xử lý các lệnh gọi remote với return value check
local function handleRemote(name, args, returnValue)
    -- SỬA: Điều kiện ngăn log được xử lý trong processAndWriteAction

    -- THÊM: Xử lý SkipWaveVoteCast - chỉ ghi khi return value là true
    if name == "SkipWaveVoteCast" then
        if returnValue == true then
            processAndWriteAction("TDX:skipWave()")
        end
    end

    -- THÊM: Xử lý TowerUseAbilityRequest cho moving skills - chỉ ghi khi return value là true
    if name == "TowerUseAbilityRequest" then
        if returnValue == true then
            local towerHash, skillIndex, targetPos = unpack(args)
            if typeof(towerHash) == "number" and typeof(skillIndex) == "number" then
                local towerName = GetTowerNameByHash(towerHash)
                if IsMovingSkillTower(towerName, skillIndex) then
                    local code

                    -- Skill cần position (skill 1)
                    if IsPositionRequiredSkill(towerName, skillIndex) and typeof(targetPos) == "Vector3" then
                        code = string.format("TDX:useMovingSkill(%s, %d, Vector3.new(%s, %s, %s))", 
                            tostring(towerHash), 
                            skillIndex, 
                            tostring(targetPos.X), 
                            tostring(targetPos.Y), 
                            tostring(targetPos.Z))

                    -- Skill không cần position (skill 3)
                    elseif not IsPositionRequiredSkill(towerName, skillIndex) then
                        code = string.format("TDX:useSkill(%s, %d)", 
                            tostring(towerHash), 
                            skillIndex)
                    end

                    if code then
                        processAndWriteAction(code)
                    end
                end
            end
        end
    end

    -- Xử lý các remote khác khi return value là true/success
    if returnValue == true then
        if name == "TowerUpgradeRequest" then
            local hash, path, count = unpack(args)
            if typeof(hash) == "number" and typeof(path) == "number" and typeof(count) == "number" and path >= 0 and path <= 2 and count > 0 and count <= 5 then
                local code = string.format("TDX:upgradeTower(%s, %d, %d)", tostring(hash), path, count)
                processAndWriteAction(code)
            end
        elseif name == "PlaceTower" then
            local a1, towerName, vec, rot = unpack(args)
            if typeof(a1) == "number" and typeof(towerName) == "string" and typeof(vec) == "Vector3" and typeof(rot) == "number" then
                local code = string.format('TDX:placeTower(%s, "%s", Vector3.new(%s, %s, %s), %s)', tostring(a1), towerName, tostring(vec.X), tostring(vec.Y), tostring(vec.Z), tostring(rot))
                processAndWriteAction(code)
            end
        elseif name == "SellTower" then
            processAndWriteAction("TDX:sellTower("..tostring(args[1])..")")
        elseif name == "ChangeQueryType" then
            processAndWriteAction(string.format("TDX:changeQueryType(%s, %s)", tostring(args[1]), tostring(args[2])))
        end
    end
end

-- Hook các hàm remote
local function setupHooks()
    if not hookfunction or not hookmetamethod or not checkcaller then
        warn("Executor không hỗ trợ đầy đủ các hàm hook cần thiết.")
        return
    end

    -- Hook FireServer
    local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
        local result = oldFireServer(self, ...)
        handleRemote(self.Name, {...}, result)
        return result
    end)

    -- Hook InvokeServer - ĐẶC BIỆT QUAN TRỌNG CHO TowerUseAbilityRequest
    local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
        local result = oldInvokeServer(self, ...)
        handleRemote(self.Name, {...}, result)
        return result
    end)

    -- Hook namecall - QUAN TRỌNG NHẤT CHO ABILITY REQUEST
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if checkcaller() then return oldNamecall(self, ...) end
        local method = getnamecallmethod()
        local result = oldNamecall(self, ...)
        
        if method == "FireServer" or method == "InvokeServer" then
            handleRemote(self.Name, {...}, result)
        end
        
        return result
    end)
end

--==============================================================================
--=                         VÒNG LẶP & KHỞI TẠO                               =
--==============================================================================

-- SỬA: Vòng lặp cập nhật vị trí SpawnCFrame của tower
task.spawn(function()
    while task.wait() do
        if TowerClass and TowerClass.GetTowers then
            for hash, tower in pairs(TowerClass.GetTowers()) do
                local pos = GetTowerSpawnPosition(tower)
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

print("✅ TDX Recorder Return Value Check đã hoạt động!")
print("📁 Dữ liệu sẽ được ghi trực tiếp vào: " .. outJson)
print("🔄 Đã tích hợp với hệ thống rebuild mới!")
print("✔️ Chỉ ghi khi server trả về true (thành công)!")
print("🚀 Tối ưu hóa hiệu suất với return value validation!")