-- TDX FULL RECORDER (method hook, tận dụng handleRemote cho mọi remote, không patch từng remote riêng)
-- Author: Copilot (2024), hỗ trợ macro, moving skill, các remote chính, logic thống nhất

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local PlayerScripts = player:WaitForChild("PlayerScripts")

-- File macro
local outJson = "tdx/macros/recorder_output.json"

-- Xóa file nếu đã tồn tại
if isfile and isfile(outJson) and delfile then pcall(delfile, outJson) end

local recordedActions = {}
local hash2pos = {}
local pendingQueue = {}
local timeout = 2
local lastKnownLevels = {}
local lastUpgradeTime = {}

-- TowerClass safe require
local TowerClass
pcall(function()
    local client = PlayerScripts:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    TowerClass = require(towerModule)
end)

if makefolder then
    pcall(makefolder, "tdx")
    pcall(makefolder, "tdx/macros")
end

-- Helpers
local function safeWriteFile(path, content)
    if writefile then pcall(writefile, path, content) end
end
local function safeReadFile(path)
    if isfile and isfile(path) and readfile then
        local ok, content = pcall(readfile, path)
        if ok then return content end
    end
    return ""
end

local function GetTowerPosition(tower)
    if not TowerClass or not tower then return nil end
    local ok, cframe = pcall(function() return tower.CFrame end)
    if ok and typeof(cframe) == "CFrame" then return cframe.Position end
    if tower.GetPosition then
        local ok2, pos = pcall(tower.GetPosition, tower)
        if ok2 and typeof(pos) == "Vector3" then return pos end
    end
    if tower.Model and tower.Model:FindFirstChild("Root") then
        return tower.Model.Root.Position
    end
    if tower.Character and tower.Character:GetCharacterModel() and tower.Character:GetCharacterModel().PrimaryPart then
        return tower.Character:GetCharacterModel().PrimaryPart.Position
    end
    return nil
end

local function GetTowerPlaceCostByName(name)
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return 0 end
    local interface = playerGui:FindFirstChild("Interface")
    if not interface then return 0 end
    local bottomBar = interface:FindFirstChild("BottomBar")
    if not bottomBar then return 0 end
    local towersBar = bottomBar:FindFirstChild("TowersBar")
    if not towersBar then return 0 end
    for _, towerButton in ipairs(towersBar:GetChildren()) do
        if towerButton.Name == name then
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

local function convertTimeToNumber(timeStr)
    if not timeStr then return nil end
    local mins, secs = timeStr:match("(%d+):(%d+)")
    if mins and secs then
        return tonumber(mins) * 100 + tonumber(secs)
    end
    return nil
end

local function updateJsonFile()
    local jsonLines = {}
    for i, entry in ipairs(recordedActions) do
        local ok, jsonStr = pcall(HttpService.JSONEncode, HttpService, entry)
        if ok then
            if i < #recordedActions then jsonStr = jsonStr .. "," end
            table.insert(jsonLines, jsonStr)
        end
    end
    local finalJson = "[\n" .. table.concat(jsonLines, "\n") .. "\n]"
    safeWriteFile(outJson, finalJson)
end

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
    if #recordedActions > 0 then updateJsonFile() end
end

local function parseMacroLine(line)
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
    local hash, path, upgradeCount = line:match('TDX:upgradeTower%(([^,]+),%s*([^,]+),%s*([^%)]+)%)')
    if hash and path and upgradeCount then
        local pos = hash2pos[tostring(hash)]
        local pathNum, count = tonumber(path), tonumber(upgradeCount)
        if pos and pathNum and count and count > 0 then
            local entries = {}
            for _ = 1, count do
                table.insert(entries, {
                    UpgradeCost = 0,
                    UpgradePath = pathNum,
                    TowerUpgraded = pos.x
                })
            end
            return entries
        end
    end
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
    local hash = line:match('TDX:sellTower%(([^%)]+)%)')
    if hash then
        local pos = hash2pos[tostring(hash)]
        if pos then
            return {{ SellTower = pos.x }}
        end
    end
    return nil
end

local function processAndWriteAction(commandString)
    if _G and _G.TDX_REBUILD_RUNNING then return end
    local entries = parseMacroLine(commandString)
    if entries then
        for _, entry in ipairs(entries) do
            table.insert(recordedActions, entry)
        end
        updateJsonFile()
    end
end

-- MOVING SKILL: chỉ đúng các tower/skill đặc biệt
local movingTowerSkills = {
    ["Helicopter"] = { [1]=true, [3]=true },
    ["Cryo Helicopter"] = { [1]=true, [3]=true },
    ["Jet Trooper"] = { [1]=true }
}
local function recordMovingSkillByHash(hash, skillIndex)
    local towers = TowerClass and TowerClass.GetTowers and TowerClass.GetTowers() or {}
    local tower = towers and towers[hash]
    if not tower then return end
    if not (movingTowerSkills[tower.Type] and movingTowerSkills[tower.Type][skillIndex]) then return end
    local pos = GetTowerPosition(tower)
    if not pos then return end
    local x = math.floor(pos.X * 100) / 100
    local wave, t = getCurrentWaveAndTime()
    wave = wave and tonumber(wave:match("(%d+)")) or 0
    local mins, secs = t and t:match("(%d+):(%d+)") or 0,0
    local timeNum = (tonumber(mins) or 0) * 60 + (tonumber(secs) or 0)
    local entry = string.format(":%s,%d,%d,%d", tostring(x), skillIndex, wave, timeNum)
    local macroTable = {}
    local content = safeReadFile(outJson)
    if content and #content > 3 then
        local ok, tbl = pcall(function() return HttpService:JSONDecode(content) end)
        if ok and typeof(tbl) == "table" then macroTable = tbl end
    end
    table.insert(macroTable, { MovingSkillRecord = entry })
    local lines = {}
    for i, act in ipairs(macroTable) do
        local ok, js = pcall(HttpService.JSONEncode, HttpService, act)
        if ok then
            if i < #macroTable then js = js .. "," end
            table.insert(lines, js)
        end
    end
    local macroStr = "[\n" .. table.concat(lines, "\n") .. "\n]"
    safeWriteFile(outJson, macroStr)
end

-- handleRemote: gom mọi remote logic về một mối, phân biệt action
local function handleRemote(name, args)
    if _G and _G.TDX_REBUILD_RUNNING then return end
    if name == "TowerUseAbilityRequest" then
        local hash, skillIndex = args[1], args[2]
        recordMovingSkillByHash(hash, skillIndex)
        return
    end
    if name == "TowerUpgradeRequest" then
        local hash, path, count = unpack(args)
        if typeof(hash) == "number" and typeof(path) == "number" and typeof(count) == "number" and path >= 0 and path <= 2 and count > 0 and count <= 5 then
            table.insert(pendingQueue, {
                type = "Upgrade",
                code = string.format("TDX:upgradeTower(%s, %d, %d)", tostring(hash), path, count),
                created = tick(),
                hash = hash
            })
        end
    elseif name == "PlaceTower" then
        local a1, towerName, vec, rot = unpack(args)
        if typeof(a1) == "number" and typeof(towerName) == "string" and typeof(vec) == "Vector3" and typeof(rot) == "number" then
            local code = string.format('TDX:placeTower(%s, "%s", Vector3.new(%s, %s, %s), %s)', tostring(a1), towerName, tostring(vec.X), tostring(vec.Y), tostring(vec.Z), tostring(rot))
            table.insert(pendingQueue, {
                type = "Place",
                code = code,
                created = tick(),
                hash = a1
            })
        end
    elseif name == "SellTower" then
        table.insert(pendingQueue, {
            type = "Sell",
            code = "TDX:sellTower("..tostring(args[1])..")",
            created = tick(),
            hash = args[1]
        })
    elseif name == "ChangeQueryType" then
        table.insert(pendingQueue, {
            type = "Target",
            code = string.format("TDX:changeQueryType(%s, %s)", tostring(args[1]), tostring(args[2])),
            created = tick(),
            hash = args[1]
        })
    end
end

-- method hook: duy nhất, không patch từng remote
local function setupHooks()
    if not hookfunction or not hookmetamethod or not checkcaller then
        warn("Executor không hỗ trợ đầy đủ các hàm hook cần thiết.")
        return
    end
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

-- Xác nhận pending và cập nhật hash2pos
ReplicatedStorage.Remotes.TowerFactoryQueueUpdated.OnClientEvent:Connect(function(data)
    local d = data and data[1]
    if not d then return end
    for i = #pendingQueue, 1, -1 do
        local item = pendingQueue[i]
        if (item.type == "Place" and d.Creation) or (item.type == "Sell" and not d.Creation) then
            processAndWriteAction(item.code)
            table.remove(pendingQueue, i)
        end
    end
end)
ReplicatedStorage.Remotes.TowerUpgradeQueueUpdated.OnClientEvent:Connect(function(data)
    if not data or not data[1] then return end
    local towerData = data[1]
    local hash = towerData.Hash
    local newLevels = towerData.LevelReplicationData
    local currentTime = tick()
    if lastUpgradeTime[hash] and (currentTime - lastUpgradeTime[hash]) < 0.0001 then return end
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
        processAndWriteAction(code)
        for i = #pendingQueue, 1, -1 do
            if pendingQueue[i].type == "Upgrade" and pendingQueue[i].hash == hash then
                table.remove(pendingQueue, i)
            end
        end
    else
        for i = #pendingQueue, 1, -1 do
            if pendingQueue[i].type == "Upgrade" and pendingQueue[i].hash == hash then
                processAndWriteAction(pendingQueue[i].code)
                table.remove(pendingQueue, i)
                break
            end
        end
    end
    lastKnownLevels[hash] = newLevels or {}
end)
ReplicatedStorage.Remotes.TowerQueryTypeIndexChanged.OnClientEvent:Connect(function(data)
    if data and data[1] then
        for i = #pendingQueue, 1, -1 do
            if pendingQueue[i].type == "Target" then
                processAndWriteAction(pendingQueue[i].code)
                table.remove(pendingQueue, i)
            end
        end
    end
end)

task.spawn(function()
    while task.wait(0.5) do
        local now = tick()
        for i = #pendingQueue, 1, -1 do
            if now - pendingQueue[i].created > timeout then
                table.remove(pendingQueue, i)
            end
        end
    end
end)

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

preserveSuperFunctions()
setupHooks()
print("✅ TDX FULL RECORDER (method hook + handleRemote) hoạt động!")
print("📁 Ghi vào: " .. outJson)