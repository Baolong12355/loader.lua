--[[
    TDX JSON Recorder (Định dạng gốc, Ghi trực tiếp)
    Phiên bản: 4.0
    Mô tả: Script này kết hợp định dạng file JSON nhiều dòng của phiên bản gốc
    với phương pháp ghi trực tiếp (append-only) để tăng hiệu quả.
    Nó sẽ không đọc toàn bộ file vào bộ nhớ, thay vào đó sẽ nối các log mới vào cuối file.
]]

-- Dịch vụ Roblox
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

-- Người chơi cục bộ và Script
local player = Players.LocalPlayer
local PlayerScripts = player:WaitForChild("PlayerScripts")

-- Cấu hình
local outJson = "tdx/macros/x.json"

-- Tạo thư mục nếu cần
if makefolder then
    pcall(function() makefolder("tdx") end)
    pcall(function() makefolder("tdx/macros") end)
end

--==============================================================================
-- Chức năng Ghi File (Ghi nối tiếp, không cache)
--==============================================================================

-- Hàm này sẽ nối các log mới vào file JSON mà không cần đọc/ghi lại toàn bộ file.
local function appendLogsToFile(entries)
    if not entries or #entries == 0 or not writefile or not HttpService then return end

    -- 1. Chuyển các entry mới thành chuỗi JSON.
    local newJsonStrings = {}
    for _, entry in ipairs(entries) do
        table.insert(newJsonStrings, HttpService:JSONEncode(entry))
    end
    if #newJsonStrings == 0 then return end
    
    -- Nối các chuỗi JSON mới lại với nhau, mỗi chuỗi trên một dòng
    local newJsonBlock = table.concat(newJsonStrings, ",\n")

    -- 2. Đọc nội dung file hiện tại (nếu có).
    local currentContent = ""
    if isfile and isfile(outJson) then
        local success, content = pcall(readfile, outJson)
        if success and content then
            currentContent = content
        end
    end

    local finalJson

    -- 3. Xác định cách thêm nội dung mới vào file.
    if #currentContent > 2 then -- Nếu file đã có nội dung (ví dụ: "[]")
        -- Tìm vị trí của dấu ngoặc vuông đóng ']' cuối cùng.
        local lastBracketPos = #currentContent
        while currentContent:sub(lastBracketPos, lastBracketPos) ~= ']' and lastBracketPos > 1 do
            lastBracketPos = lastBracketPos - 1
        end

        if lastBracketPos > 1 then
            -- Lấy phần nội dung trước dấu ']'
            local contentBeforeBracket = currentContent:sub(1, lastBracketPos - 1)
            -- Thêm dấu phẩy và dòng mới, sau đó thêm khối JSON mới, và cuối cùng là đóng ngoặc.
            finalJson = contentBeforeBracket .. ",\n" .. newJsonBlock .. "\n]"
        else
            -- Trường hợp file bị lỗi, tạo file mới
            finalJson = "[\n" .. newJsonBlock .. "\n]"
        end
    else
        -- Nếu file mới hoặc rỗng, tạo một mảng JSON mới.
        finalJson = "[\n" .. newJsonBlock .. "\n]"
    end

    -- 4. Ghi lại nội dung cuối cùng vào file.
    pcall(writefile, outJson, finalJson)
end

-- Hàm thêm nhiều log entries và lưu lại
local function addLogEntries(entries)
    appendLogsToFile(entries)
end

--==============================================================================
-- Logic Game & Lấy Dữ Liệu (Giữ nguyên từ bản gốc)
--==============================================================================

local pendingQueue = {}
local timeout = 2
local lastKnownLevels = {}
local lastUpgradeTime = {}

local TowerClass
pcall(function() TowerClass = require(PlayerScripts:WaitForChild("Client"):WaitForChild("GameClass"):WaitForChild("TowerClass")) end)

local function GetTowerPosition(tower)
    if not TowerClass or not tower then return nil end
    if tower.CFrame and typeof(tower.CFrame) == "CFrame" then return tower.CFrame.Position end
    if tower.GetPosition and pcall(tower.GetPosition, tower) then return tower:GetPosition() end
    if tower.GetTorsoPosition and pcall(tower.GetTorsoPosition, tower) then return tower:GetTorsoPosition() end
    if tower.Character and tower.Character.PrimaryPart then return tower.Character.PrimaryPart.Position end
    return nil
end

local function GetTowerPlaceCostByName(name)
    local playerGui = player:FindFirstChild("PlayerGui")
    local costText = playerGui and playerGui:FindFirstChild("Interface.BottomBar.TowersBar." .. name .. ".CostFrame.CostText", true)
    if costText then return tonumber(tostring(costText.Text):gsub("%D", "")) or 0 end
    return 0
end

local function getCurrentWaveAndTime()
    local playerGui = player:FindFirstChild("PlayerGui")
    local gameInfoBar = playerGui and playerGui:FindFirstChild("Interface.GameInfoBar", true)
    if gameInfoBar then return gameInfoBar.Wave.WaveText.Text, gameInfoBar.TimeLeft.TimeLeftText.Text end
    return nil, nil
end

local function convertTimeToNumber(timeStr)
    if not timeStr then return nil end
    local mins, secs = timeStr:match("(%d+):(%d+)")
    if mins and secs then return tonumber(mins) * 100 + tonumber(secs) end
    return nil
end

local hash2pos = {}
task.spawn(function()
    while task.wait() do
        if TowerClass and TowerClass.GetTowers then
            for hash, tower in pairs(TowerClass.GetTowers() or {}) do
                local pos = GetTowerPosition(tower)
                if pos then hash2pos[tostring(hash)] = {x = pos.X, y = pos.Y, z = pos.Z} end
            end
        end
    end
end)

local function serialize(v)
    if typeof(v) == "Vector3" then return "Vector3.new("..v.X..","..v.Y..","..v.Z..")"
    elseif typeof(v) == "Vector2int16" then return "Vector2int16.new("..v.X..","..v.Y..")"
    elseif type(v) == "table" then
        local out = {}
        for k, val in pairs(v) do out[#out+1] = "["..tostring(k).."]="..serialize(val) end
        return "{"..table.concat(out, ",").."}"
    else return tostring(v) end
end

local function serializeArgs(...)
    local args, out = {...}, {}
    for i, v in ipairs(args) do out[i] = serialize(v) end
    return table.concat(out, ", ")
end

function parseMacroLine(line)
    local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*Vector3%.new%(([^,]+),%s*([^,]+),%s*([^%)]+)%)%s*,%s*([^%)]+)%)')
    if a1 and name and x and y and z and rot then
        name = tostring(name):gsub('^%s*"(.-)"%s*$', '%1')
        return {{
            TowerPlaceCost = GetTowerPlaceCostByName(name), TowerPlaced = name,
            TowerVector = string.format("%s, %s, %s", tonumber(x) or x, tonumber(y) or y, tonumber(z) or z),
            Rotation = tonumber(rot), TowerA1 = tostring(a1)
        }}
    end
    local hash, path, upgradeCount = line:match('TDX:upgradeTower%(([^,]+),%s*([^,]+),%s*([^%)]+)%)')
    if hash and path and upgradeCount then
        local pos, pathNum, count = hash2pos[tostring(hash)], tonumber(path), tonumber(upgradeCount)
        if pos and pathNum and count > 0 then
            local entries = {}
            for _ = 1, count do table.insert(entries, {UpgradeCost = 0, UpgradePath = pathNum, TowerUpgraded = pos.x}) end
            return entries
        end
    end
    local hash, targetType = line:match('TDX:changeQueryType%(([^,]+),%s*([^%)]+)%)')
    if hash and targetType then
        local pos = hash2pos[tostring(hash)]
        if pos then
            local currentWave, currentTime = getCurrentWaveAndTime()
            return {{
                TowerTargetChange = pos.x, TargetWanted = tonumber(targetType),
                TargetWave = currentWave, TargetChangedAt = convertTimeToNumber(currentTime)
            }}
        end
    end
    local hash = line:match('TDX:sellTower%(([^%)]+)%)')
    if hash then
        local pos = hash2pos[tostring(hash)]
        if pos then return {{SellTower = pos.x}} end
    end
    return nil
end

local function tryConfirm(typeStr, specificHash)
    for i = #pendingQueue, 1, -1 do
        local item = pendingQueue[i]
        if item.type == typeStr and (not specificHash or string.find(item.code, tostring(specificHash))) then
            local result = parseMacroLine(item.code)
            if result then addLogEntries(result) end
            table.remove(pendingQueue, i)
            if not specificHash then return end
        end
    end
end

local function setPending(typeStr, code, hash)
    table.insert(pendingQueue, {type = typeStr, code = code, created = tick(), hash = hash})
end

--==============================================================================
-- Hook và Lắng nghe Sự kiện Remote (Giữ nguyên từ bản gốc)
--==============================================================================

ReplicatedStorage.Remotes.TowerFactoryQueueUpdated.OnClientEvent:Connect(function(data)
    if data and data[1] then if data[1].Creation then tryConfirm("Place") else tryConfirm("Sell") end end
end)

ReplicatedStorage.Remotes.TowerUpgradeQueueUpdated.OnClientEvent:Connect(function(data)
    if not data or not data[1] then return end
    local towerData, hash, newLevels = data[1], data[1].Hash, data[1].LevelReplicationData
    local currentTime = tick()
    if lastUpgradeTime[hash] and (currentTime - lastUpgradeTime[hash]) < 0.01 then return end
    lastUpgradeTime[hash] = currentTime
    local upgradedPath, upgradeCount = nil, 0
    if lastKnownLevels[hash] then
        for path = 1, 2 do
            if (newLevels[path] or 0) > (lastKnownLevels[hash][path] or 0) then
                upgradedPath, upgradeCount = path, newLevels[path] - lastKnownLevels[hash][path]
                break
            end
        end
    end
    if upgradedPath and upgradeCount > 0 then
        local code = string.format("TDX:upgradeTower(%s, %d, %d)", tostring(hash), upgradedPath, upgradeCount)
        local result = parseMacroLine(code)
        if result then addLogEntries(result) end
        for i = #pendingQueue, 1, -1 do
            if pendingQueue[i].type == "Upgrade" and pendingQueue[i].hash == hash then table.remove(pendingQueue, i) end
        end
    else
        tryConfirm("Upgrade", hash)
    end
    lastKnownLevels[hash] = newLevels or {}
end)

ReplicatedStorage.Remotes.TowerQueryTypeIndexChanged.OnClientEvent:Connect(function(data)
    if data and data[1] then tryConfirm("Target") end
end)

task.spawn(function()
    while task.wait(0.05) do
        local now = tick()
        for i = #pendingQueue, 1, -1 do
            if now - pendingQueue[i].created > timeout then
                warn("❌ Hết thời gian chờ xác nhận: " .. pendingQueue[i].type)
                table.remove(pendingQueue, i)
            end
        end
    end
end)

local function handleRemote(name, args)
    if name == "TowerUpgradeRequest" then
        local hash, path, count = unpack(args)
        if typeof(hash) == "number" and typeof(path) == "number" and typeof(count) == "number" then
            setPending("Upgrade", string.format("TDX:upgradeTower(%s, %d, %d)", tostring(hash), path, count), hash)
        end
    elseif name == "PlaceTower" then
        local a1, towerName, vec, rot = unpack(args)
        if typeof(a1) == "number" and typeof(towerName) == "string" and typeof(vec) == "Vector3" and typeof(rot) == "number" then
            local code = string.format('TDX:placeTower(%d, "%s", Vector3.new(%s, %s, %s), %d)', a1, towerName, vec.X, vec.Y, vec.Z, rot)
            setPending("Place", code)
        end
    elseif name == "SellTower" then
        setPending("Sell", "TDX:sellTower("..serializeArgs(unpack(args))..")")
    elseif name == "ChangeQueryType" then
        setPending("Target", "TDX:changeQueryType("..serializeArgs(unpack(args))..")")
    end
end

if hookfunction and hookmetamethod and getnamecallmethod and checkcaller then
    local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
        handleRemote(self.Name, {...})
        return oldFireServer(self, ...)
    end)
    local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
        handleRemote(self.Name, {...})
        return oldInvokeServer(self, ...)
    end)
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if not checkcaller() then
            local method = getnamecallmethod()
            if method == "FireServer" or method == "InvokeServer" then handleRemote(self.Name, {...}) end
        end
        return oldNamecall(self, ...)
    end)
else
    warn("Executor này không hỗ trợ các hàm hook cần thiết.")
end

print("✅ TDX JSON Recorder (Định dạng gốc) đã khởi động!")
print("📁 Ghi trực tiếp vào file: " .. outJson)

