local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")

local fileName = "record.txt"
local macroPath = "tdx/macros/x.json"
local startTime = time()
local offset = 0

if isfile(fileName) then
    delfile(fileName)
end
writefile(fileName, "")

local pending = nil
local timeout = 2
local isRebuilding = false
local enableRebuild = true
local soldAxes = {}

-- ⚙️ Hàm kiểm tra thiếu tower
local function IsTowerMissing(x)
    local tower = GetTowerByAxis(x)
    return not tower
end

-- 🧠 Gộp dữ liệu từ macro
local function BuildTowerRecords(macro)
    local records = {}
    
    for _, entry in ipairs(macro) do
        local towerName = entry.TowerPlaced or entry.TowerName
        local x = nil

        if entry.TowerVector then
            local vecTab = entry.TowerVector:split(", ")
            x = tonumber(vecTab[1])
        elseif entry.TowerUpgraded or entry.ChangeTarget or entry.SellTower then
            x = tonumber(entry.TowerUpgraded or entry.ChangeTarget or entry.SellTower)
        end

        if x and towerName then
            records[x] = records[x] or { X = x, Actions = {} }
            table.insert(records[x].Actions, entry)
            records[x].TowerName = towerName
        end
    end
    return records
end

-- 🔼 Ưu tiên theo loại tower
local priorityMap = {
    Medic = 1,
    ["Golden Mobster"] = 2,
    Mobster = 2,
    EDJ = 3,
    Commander = 4
}

local function GetPriority(name)
    return priorityMap[name] or 5
end

-- 🚀 Watcher loop chính
local function startRebuildWatcher(macro)
    local towerRecords = BuildTowerRecords(macro)

    while enableRebuild do
        local rebuildList = {}
        for x, record in pairs(towerRecords) do
            if IsTowerMissing(x) then
                table.insert(rebuildList, record)
            end
        end

        table.sort(rebuildList, function(a, b)
            return GetPriority(a.TowerName) < GetPriority(b.TowerName)
        end)

        for _, record in ipairs(rebuildList) do
            for _, action in ipairs(record.Actions) do
                if action.TowerPlaced and action.TowerVector and action.TowerPlaceCost then
                    local vecTab = action.TowerVector:split(", ")
                    local pos = Vector3.new(unpack(vecTab))
                    local args = {
                        tonumber(action.TowerA1),
                        action.TowerPlaced,
                        pos,
                        tonumber(action.Rotation or 0)
                    }
                    WaitForCash(action.TowerPlaceCost)
                    PlaceTowerRetry(args, pos.X, action.TowerPlaced)
                elseif action.TowerUpgraded and action.UpgradePath and action.UpgradeCost then
                    UpgradeTowerRetry(tonumber(action.TowerUpgraded), action.UpgradePath)
                elseif action.ChangeTarget and action.TargetType then
                    ChangeTargetRetry(tonumber(action.ChangeTarget), action.TargetType)
                elseif action.SellTower then
                    SellTowerRetry(tonumber(action.SellTower))
                end
            end
        end

        task.wait(2)
    end
end

-- Serialization functions and other existing code...

local function serialize(v)
    if typeof(v) == "Vector3" then
        return string.format("Vector3.new(%s,%s,%s)", v.X, v.Y, v.Z)
    elseif typeof(v) == "Vector2int16" then
        return string.format("Vector2int16.new(%s,%s)", v.X, v.Y)
    elseif type(v) == "table" then
        local out = {}
        for k, val in pairs(v) do
            table.insert(out, string.format("[%s]=%s", tostring(k), serialize(val)))
        end
        return "{" .. table.concat(out, ",") .. "}"
    else
        return tostring(v)
    end
end

local function serializeArgs(...)
    local args = {...}
    local out = {}
    for i, v in ipairs(args) do
        out[i] = serialize(v)
    end
    return table.concat(out, ", ")
end

local function confirmAndWrite()
    if not pending or isRebuilding then return end
    appendfile(fileName, string.format("task.wait(%s)\n", (time() - offset) - startTime))
    appendfile(fileName, pending.code .. "\n")
    startTime = time() - offset
    pending = nil
end

local function tryConfirm(typeStr)
    if pending and pending.type == typeStr then
        confirmAndWrite()
    end
end

local function setPending(typeStr, code)
    pending = { type = typeStr, code = code, created = tick() }
end

ReplicatedStorage.Remotes.TowerFactoryQueueUpdated.OnClientEvent:Connect(function(data)
    local d = data[1]
    if not d then return end
    if not d.Creation and d.Hash and d.Axis then
        soldAxes[tonumber(d.Axis)] = true
    end
    tryConfirm(d.Creation and "Place" or "Sell")
end)

ReplicatedStorage.Remotes.TowerUpgradeQueueUpdated.OnClientEvent:Connect(function(data)
    if data[1] then
        tryConfirm("Upgrade")
    end
end)

ReplicatedStorage.Remotes.TowerQueryTypeIndexChanged.OnClientEvent:Connect(function(data)
    if data[1] then
        tryConfirm("Target")
    end
end)

spawn(function()
    while true do
        task.wait(0.3)
        if pending and tick() - pending.created > timeout then
            pending = nil
        end
    end
end)

local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
    local args, name = serializeArgs(...), self.Name
    if not isRebuilding then
        if name == "PlaceTower" then
            setPending("Place", "TDX:placeTower(" .. args .. ")")
        elseif name == "SellTower" then
            setPending("Sell", "TDX:sellTower(" .. args .. ")")
        elseif name == "TowerUpgradeRequest" then
            setPending("Upgrade", "TDX:upgradeTower(" .. args .. ")")
        elseif name == "ChangeQueryType" then
            setPending("Target", "TDX:changeQueryType(" .. args .. ")")
        end
    end
    return oldFireServer(self, ...)
end)

local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
    return oldInvokeServer(self, ...)
end)

local oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    if not isRebuilding and (method == "FireServer" or method == "InvokeServer") then
        local name = self.Name
        local args = serializeArgs(...)
        if name == "PlaceTower" then
            setPending("Place", "TDX:placeTower(" .. args .. ")")
        elseif name == "SellTower" then
            setPending("Sell", "TDX:sellTower(" .. args .. ")")
        elseif name == "TowerUpgradeRequest" then
            setPending("Upgrade", "TDX:upgradeTower(" .. args .. ")")
        elseif name == "ChangeQueryType" then
            setPending("Target", "TDX:changeQueryType(" .. args .. ")")
        end
    end
    return oldNamecall(self, ...)
end)

local TowerClass = require(Players.LocalPlayer.PlayerScripts.Client.GameClass.TowerClass)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local function GetTowerByAxis(axisX)
    for _, tower in pairs(TowerClass.GetTowers()) do
        local model = tower.Character and tower.Character:GetCharacterModel()
        local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
        if root and root.Position.X == axisX then
            return tower
        end
    end
end

local function GetCurrentUpgradeCost(tower, path)
    if not tower or not tower.LevelHandler then return nil end
    local maxLvl = tower.LevelHandler:GetMaxLevel()
    local curLvl = tower.LevelHandler:GetLevelOnPath(path)
    if curLvl >= maxLvl then return nil end
    local ok, baseCost = pcall(function()
        return tower.LevelHandler:GetLevelUpgradeCost(path, 1)
    end)
    if not ok then return nil end
    local disc = 0
    local ok2, d = pcall(function()
        return tower.BuffHandler and tower.BuffHandler:GetDiscount() or 0
    end)
    if ok2 and typeof(d) == "number" then disc = d end
    return math.floor(baseCost * (1 - disc))
end

local function WaitForCash(amount)
    while cashStat.Value < amount do
        task.wait()
    end
end

local function PlaceTowerRetry(args, axisValue, towerName)
    if soldAxes[axisValue] then return end
    local attempts = 0
    while attempts < 20 do
        Remotes.PlaceTower:InvokeServer(unpack(args))
        task.wait(0.1)
        if GetTowerByAxis(axisValue) then
            return true
        end
        attempts = attempts + 1
    end
    return false
end

local function UpgradeTowerRetry(axisValue, path)
    local attempts = 0
    while attempts < 20 do
        local tower = GetTowerByAxis(axisValue)
        if not tower then
            task.wait()
            attempts = attempts + 1
            continue
        end
        
        local before = tower.LevelHandler:GetLevelOnPath(path)
        local cost = GetCurrentUpgradeCost(tower, path)
        if not cost then return end
        
        WaitForCash(cost)
        Remotes.TowerUpgradeRequest:FireServer(tower.Hash, path, 1)
        task.wait(0.1)
        
        local t = GetTowerByAxis(axisValue)
        if t and t.LevelHandler:GetLevelOnPath(path) > before then
            return true
        end
        attempts = attempts + 1
    end
    return false
end

local function ChangeTargetRetry(axisValue, targetType)
    local attempts = 0
    while attempts < 20 do
        local tower = GetTowerByAxis(axisValue)
        if tower then
            Remotes.ChangeQueryType:FireServer(tower.Hash, targetType)
            return true
        end
        task.wait()
        attempts = attempts + 1
    end
    return false
end

if isfile(macroPath) then
    local success, macro = pcall(function()
        return HttpService:JSONDecode(readfile(macroPath))
    end)
    if success and type(macro) == "table" then
        spawn(function()
            while true do
                if enableRebuild and not isRebuilding then
                    isRebuilding = true
                    startRebuildWatcher(macro)
                    isRebuilding = false
                end
                task.wait(0.25)
            end
        end)
    end
end

pcall(function()
    local gui = Instance.new("ScreenGui", player:WaitForChild("PlayerGui"))
    gui.Name = "TDX_GUI"
    local frame = Instance.new("Frame", gui)
    frame.Size = UDim2.new(0, 160, 0, 50)
    frame.Position = UDim2.new(0, 20, 0, 60)
    frame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    frame.Active = true
    frame.Draggable = true
    
    local button = Instance.new("TextButton", frame)
    button.Size = UDim2.new(1, 0, 1, 0)
    button.Text = "🔁 Rebuild: ON"
    button.BackgroundColor3 = Color3.fromRGB(40, 180, 40)
    button.MouseButton1Click:Connect(function()
        enableRebuild = not enableRebuild
        button.Text = enableRebuild and "🔁 Rebuild: ON" or "⛔ Rebuild: OFF"
        button.BackgroundColor3 = enableRebuild and Color3.fromRGB(40, 180, 40) or Color3.fromRGB(180, 40, 40)
    end)
end)

print("📌 Macro Recorder + Improved Rebuild Ready")








local txtFile = "record.txt"
local outJson = "tdx/macros/x.json"

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local HttpService = game:GetService("HttpService")
local PlayerScripts = player:WaitForChild("PlayerScripts")

-- Safe require tower module
local function SafeRequire(module)
    local success, result = pcall(require, module)
    return success and result or nil
end

local TowerClass
do
    local client = PlayerScripts:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    TowerClass = SafeRequire(towerModule)
end

local function GetTowerPosition(tower)
    if not tower or not tower.Character then return nil end
    local model = tower.Character:GetCharacterModel()
    local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
    return root and root.Position or nil
end

local function GetTowerPlaceCostByName(name)
    local playerGui = player:FindFirstChild("PlayerGui")
    if not playerGui then return 0 end
    local interface = playerGui:FindFirstChild("Interface")
    if not interface then return 0 end
    local bottomBar = interface:FindFirstChild("BottomBar")
    if not bottomBar then return 0 end
    local towersBar = bottomBar:FindFirstChild("TowersBar")
    if not towersBar then return 0 end
    for _, tower in ipairs(towersBar:GetChildren()) do
        if tower.Name == name then
            local costFrame = tower:FindFirstChild("CostFrame")
            local costText = costFrame and costFrame:FindFirstChild("CostText")
            if costText then
                local raw = tostring(costText.Text):gsub("%D", "")
                return tonumber(raw) or 0
            end
        end
    end
    return 0
end

-- ánh xạ hash -> pos liên tục
local hash2pos = {}
task.spawn(function()
    while true do
        for hash, tower in pairs(TowerClass and TowerClass.GetTowers() or {}) do
            local pos = GetTowerPosition(tower)
            if pos then
                hash2pos[tostring(hash)] = {x = pos.X, y = pos.Y, z = pos.Z}
            end
        end
        task.wait(0.1)
    end
end)

if makefolder then
    pcall(function() makefolder("tdx") end)
    pcall(function() makefolder("tdx/macros") end)
end

while true do
    if isfile(txtFile) then
        local macro = readfile(txtFile)
        local logs = {}

        -- giữ dòng SuperFunction
        local preservedSuper = {}
        if isfile(outJson) then
            for line in readfile(outJson):gmatch("[^\r\n]+") do
                local ok, decoded = pcall(HttpService.JSONDecode, HttpService, line)
                if ok and decoded and decoded.SuperFunction then
                    table.insert(preservedSuper, line)
                end
            end
        end

        for line in macro:gmatch("[^\r\n]+") do
            -- parser mới cho placeTower với Vector3.new(...)
            local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*Vector3%.new%(([^,]+),%s*([^,]+),%s*([^%)]+)%)%s*,%s*([^%)]+)%)')
            if a1 and name and x and y and z and rot then
                name = tostring(name):gsub('^%s*"(.-)"%s*$', '%1')
                local cost = GetTowerPlaceCostByName(name)
                local vector = string.format("%s, %s, %s", tostring(tonumber(x) or x), tostring(tonumber(y) or y), tostring(tonumber(z) or z))
                table.insert(logs, HttpService:JSONEncode({
                    TowerPlaceCost = tonumber(cost) or 0,
                    TowerPlaced = name,
                    TowerVector = vector,
                    Rotation = rot,
                    TowerA1 = tostring(a1)
                }))
            else
                -- nâng cấp
                local hash, path, upgradeCount = line:match('TDX:upgradeTower%(([^,]+),%s*([^,]+),%s*([^%)]+)%)')
                if hash and path and upgradeCount then
                    local pos = hash2pos[tostring(hash)]
                    local pathNum = tonumber(path)
                    local count = tonumber(upgradeCount)
                    if pos and pathNum and count and count > 0 then
                        for _ = 1, count do
                            table.insert(logs, HttpService:JSONEncode({
                                UpgradeCost = 0,
                                UpgradePath = pathNum,
                                TowerUpgraded = pos.x
                            }))
                        end
                    end
                else
                    -- đổi target
                    local hash, targetType = line:match('TDX:changeQueryType%(([^,]+),%s*([^%)]+)%)')
                    if hash and targetType then
                        local pos = hash2pos[tostring(hash)]
                        if pos then
                            table.insert(logs, HttpService:JSONEncode({
                                ChangeTarget = pos.x,
                                TargetType = tonumber(targetType)
                            }))
                        end
                    else
                        -- bán
                        local hash = line:match('TDX:sellTower%(([^%)]+)%)')
                        if hash then
                            local pos = hash2pos[tostring(hash)]
                            if pos then
                                table.insert(logs, HttpService:JSONEncode({
                                    SellTower = pos.x
                                }))
                            end
                        end
                    end
                end
            end
        end

        for _, line in ipairs(preservedSuper) do
            table.insert(logs, line)
        end

        writefile(outJson, table.concat(logs, "\n"))
    end
    wait(0.22)
end