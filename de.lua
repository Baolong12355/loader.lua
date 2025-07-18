-- ✅ TDX Macro Recorder with Ultra-Optimized Rebuild System

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

-- 🧑‍💻 Player Setup
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")

-- 📁 File Configuration
local fileName = "record.txt"
local macroPath = "tdx/naviai.json"
local startTime = time()
local offset = 0

-- 🧹 Initialize Files
if isfile(fileName) then delfile(fileName) end
writefile(fileName, "")

-- ⚙️ System Variables
local pending = nil
local timeout = 2
local isRebuilding = false
local enableRebuild = true
local soldAxis = {}

-- 🏗️ Tower Priority System (Updated)
local PRIORITY_LIST = {
    ["Medic"] = 1,          -- Highest priority
    ["Golden Mobster"] = 2,
    ["Mobster"] = 3,
    ["EDJ"] = 4,
    ["Commander"] = 5,
    ["Sniper"] = 6,
    ["Farm"] = 7,           -- Lowest priority
    -- Add more towers as needed
}

-- 🔄 Serialization Functions (Optimized)
local function serialize(v)
    local t = typeof(v)
    if t == "Vector3" then
        return string.format("Vector3.new(%s, %s, %s)", v.X, v.Y, v.Z)
    elseif t == "Vector2int16" then
        return string.format("Vector2int16.new(%s, %s)", v.X, v.Y)
    elseif type(v) == "table" then
        local out = {}
        for k, val in pairs(v) do
            table.insert(out, string.format("[%s] = %s", tostring(k), serialize(val)))
        end
        return "{"..table.concat(out, ", ").."}"
    end
    return tostring(v)
end

local function serializeArgs(...)
    local out = {}
    for i, v in ipairs({...}) do
        out[i] = serialize(v)
    end
    return table.concat(out, ", ")
end

-- 📝 Recording System (Enhanced)
local function confirmAndWrite()
    if not pending or isRebuilding then return end
    appendfile(fileName, string.format("task.wait(%.2f)\n", (time() - offset) - startTime))
    appendfile(fileName, pending.code.."\n")
    startTime = time() - offset
    pending = nil
end

local function tryConfirm(typeStr)
    if pending and pending.type == typeStr then
        confirmAndWrite()
    end
end

local function setPending(typeStr, code)
    if typeStr == "Sell" then
        local axis = tonumber(code:match("TDX:sellTower%((%d+)%)"))
        if axis then soldAxis[axis] = true end
    end
    pending = {type = typeStr, code = code, created = tick()}
end

-- 🎣 Advanced Hooking System
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    if not isRebuilding and not checkcaller() then
        local method = getnamecallmethod()
        if method == "FireServer" or method == "InvokeServer" then
            local args = serializeArgs(...)
            local name = self.Name
            
            local actionMap = {
                ["PlaceTower"] = "Place",
                ["SellTower"] = "Sell",
                ["TowerUpgradeRequest"] = "Upgrade",
                ["ChangeQueryType"] = "Target"
            }
            
            if actionMap[name] then
                setPending(actionMap[name], "TDX:"..name:lower().."("..args..")")
            end
        end
    end
    return oldNamecall(self, ...)
end)

-- 📡 Event Connections (Optimized)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
Remotes.TowerFactoryQueueUpdated.OnClientEvent:Connect(function(data)
    local d = data[1]
    if d then tryConfirm(d.Creation and "Place" or "Sell") end
end)

Remotes.TowerUpgradeQueueUpdated.OnClientEvent:Connect(function(data)
    if data[1] then tryConfirm("Upgrade") end
end)

Remotes.TowerQueryTypeIndexChanged.OnClientEvent:Connect(function(data)
    if data[1] then tryConfirm("Target") end
end)

-- ⏳ Pending Timeout Handler
spawn(function()
    while task.wait(0.3) do
        if pending and tick() - pending.created > timeout then
            pending = nil
        end
    end
end)

-- 🏰 Tower Management System
local TowerClass = require(player.PlayerScripts.Client.GameClass.TowerClass)

local function GetTowerByAxis(axisX)
    for _, tower in pairs(TowerClass.GetTowers()) do
        local model = tower.Character and tower.Character:GetCharacterModel()
        local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
        if root and math.floor(root.Position.X) == math.floor(axisX) then
            return tower
        end
    end
end

local function GetCurrentUpgradeCost(tower, path)
    if not tower or not tower.LevelHandler then return nil end
    
    local maxLvl = tower.LevelHandler:GetMaxLevel()
    local curLvl = tower.LevelHandler:GetLevelOnPath(path)
    if curLvl >= maxLvl then return nil end
    
    local success, baseCost = pcall(function()
        return tower.LevelHandler:GetLevelUpgradeCost(path, 1)
    end)
    
    if not success then return nil end
    
    local discount = 0
    local ok, disc = pcall(function()
        return tower.BuffHandler and tower.BuffHandler:GetDiscount() or 0
    end)
    if ok and type(disc) == "number" then discount = disc end
    
    return math.floor(baseCost * (1 - discount))
end

-- 💰 Cash Handling
local function WaitForCash(amount)
    while cashStat.Value < amount do
        task.wait(0.1)
    end
end

-- 🔄 Unlimited Retry System (0.1s delay)
local function UnlimitedPlaceTowerRetry(args, axisValue)
    if soldAxis[axisValue] then return false end
    while true do
        Remotes.PlaceTower:InvokeServer(unpack(args))
        task.wait(0.1)
        if GetTowerByAxis(axisValue) then
            return true
        end
    end
end

local function UnlimitedUpgradeTowerRetry(axisValue, path)
    while true do
        local tower = GetTowerByAxis(axisValue)
        if not tower then
            task.wait(0.1)
            continue
        end

        local cost = GetCurrentUpgradeCost(tower, path)
        if not cost then return true end

        WaitForCash(cost)
        
        local before = tower.LevelHandler:GetLevelOnPath(path)
        Remotes.TowerUpgradeRequest:FireServer(tower.Hash, path, 1)
        task.wait(0.1)

        if GetTowerByAxis(axisValue).LevelHandler:GetLevelOnPath(path) > before then
            return true
        end
    end
end

local function UnlimitedChangeTargetRetry(axisValue, targetType)
    while true do
        local tower = GetTowerByAxis(axisValue)
        if tower then
            Remotes.ChangeQueryType:FireServer(tower.Hash, targetType)
            return true
        end
        task.wait(0.1)
    end
end

-- 🏗️ Smart Rebuild System
local function BuildTowerRecords(macro)
    local records = {}
    
    for _, entry in ipairs(macro) do
        local x = entry.TowerVector and tonumber(entry.TowerVector:split(", ")[1]) 
                 or tonumber(entry.TowerUpgraded or entry.ChangeTarget or entry.SellTower)
        
        if x and (entry.TowerPlaced or entry.TowerName) then
            records[x] = records[x] or {
                X = x,
                Actions = {},
                TowerName = entry.TowerPlaced or entry.TowerName,
                Priority = PRIORITY_LIST[entry.TowerPlaced or entry.TowerName] or 10
            }
            table.insert(records[x].Actions, entry)
        end
    end
    
    return records
end

local function StartSmartRebuild(macro)
    local records = BuildTowerRecords(macro)
    
    while enableRebuild do
        local missing = {}
        
        -- Find missing towers
        for x, record in pairs(records) do
            if not soldAxis[x] and not GetTowerByAxis(x) then
                table.insert(missing, record)
            end
        end
        
        -- Sort by priority
        table.sort(missing, function(a, b) return a.Priority < b.Priority end)
        
        -- Rebuild missing towers
        for _, record in ipairs(missing) do
            for _, action in ipairs(record.Actions) do
                if action.TowerPlaced and action.TowerVector then
                    local vec = action.TowerVector:split(", ")
                    local pos = Vector3.new(unpack(vec))
                    local args = {
                        tonumber(action.TowerA1),
                        action.TowerPlaced,
                        pos,
                        tonumber(action.Rotation or 0)
                    }
                    WaitForCash(action.TowerPlaceCost)
                    UnlimitedPlaceTowerRetry(args, pos.X)
                elseif action.TowerUpgraded then
                    UnlimitedUpgradeTowerRetry(tonumber(action.TowerUpgraded), action.UpgradePath)
                elseif action.ChangeTarget then
                    UnlimitedChangeTargetRetry(tonumber(action.ChangeTarget), action.TargetType)
                end
                task.wait(0.1) -- Short delay between actions
            end
        end
        
        task.wait(0.25) -- Main rebuild cycle delay
    end
end



-- 🚀 Initialize System
if isfile(macroPath) then
    local success, macro = pcall(function()
        return HttpService:JSONDecode(readfile(macroPath))
    end)
    
    if success and type(macro) == "table" then
        spawn(function()
            while task.wait(0.25) do
                if enableRebuild and not isRebuilding then
                    isRebuilding = true
                    StartSmartRebuild(macro)
                    isRebuilding = false
                end
            end
        end)
    end
end

print("✅ TDX Ultimate Recorder + Reboot System Activated")




local txtFile = "record.txt"
local outJson = "tdx/naviai.json"

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