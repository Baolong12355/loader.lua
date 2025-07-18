-- ✅ TDX Macro Recorder with Auto Rebuild Integration (from macro file + correct hook style)

local ReplicatedStorage = game:GetService("ReplicatedStorage") local Players = game:GetService("Players") local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")

local fileName = "record.txt" local macroPath = "tdx/naviai.json" local startTime = time() local offset = 0

if isfile(fileName) then delfile(fileName) end writefile(fileName, "")

local pending = nil local timeout = 2 local isRebuilding = false local enableRebuild = true local soldAxis = {}

local function serialize(v) if typeof(v) == "Vector3" then return string.format("Vector3.new(%s,%s,%s)", v.X, v.Y, v.Z) elseif typeof(v) == "Vector2int16" then return string.format("Vector2int16.new(%s,%s)", v.X, v.Y) elseif type(v) == "table" then local out = {} for k, val in pairs(v) do table.insert(out, string.format("[%s]=%s", tostring(k), serialize(val))) end return "{" .. table.concat(out, ",") .. "}" else return tostring(v) end end

local function serializeArgs(...) local args = {...} local out = {} for i, v in ipairs(args) do out[i] = serialize(v) end return table.concat(out, ", ") end

local function confirmAndWrite() if not pending or isRebuilding then return end appendfile(fileName, string.format("task.wait(%s)\n", (time() - offset) - startTime)) appendfile(fileName, pending.code .. "\n") startTime = time() - offset pending = nil end

local function tryConfirm(typeStr) if pending and pending.type == typeStr then confirmAndWrite() end end

local function setPending(typeStr, code) if typeStr == "Sell" then local match = string.match(code, "TDX:sellTower%((.-)%)") if match then local args = loadstring("return {" .. match .. "}")() if args and typeof(args[1]) == "number" then soldAxis[args[1]] = true end end end pending = { type = typeStr, code = code, created = tick() } end

ReplicatedStorage.Remotes.TowerFactoryQueueUpdated.OnClientEvent:Connect(function(data) local d = data[1] if not d then return end tryConfirm(d.Creation and "Place" or "Sell") end)

ReplicatedStorage.Remotes.TowerUpgradeQueueUpdated.OnClientEvent:Connect(function(data) if data[1] then tryConfirm("Upgrade") end end)

ReplicatedStorage.Remotes.TowerQueryTypeIndexChanged.OnClientEvent:Connect(function(data) if data[1] then tryConfirm("Target") end end)

spawn(function() while true do task.wait(0.3) if pending and tick() - pending.created > timeout then pending = nil end end end)

local oldNamecall = hookmetamethod(game, "__namecall", function(self, ...) if not isRebuilding and not checkcaller() then local method = getnamecallmethod() if method == "FireServer" or method == "InvokeServer" then local args = serializeArgs(...) local name = self.Name if name == "PlaceTower" then setPending("Place", "TDX:placeTower(" .. args .. ")") elseif name == "SellTower" then setPending("Sell", "TDX:sellTower(" .. args .. ")") elseif name == "TowerUpgradeRequest" then setPending("Upgrade", "TDX:upgradeTower(" .. args .. ")") elseif name == "ChangeQueryType" then setPending("Target", "TDX:changeQueryType(" .. args .. ")") end end end return oldNamecall(self, ...) end)

local TowerClass = require(player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("GameClass"):WaitForChild("TowerClass")) local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local function GetTowerByAxis(axisX) for _, tower in pairs(TowerClass.GetTowers()) do local model = tower.Character and tower.Character:GetCharacterModel() local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")) if root and root.Position.X == axisX then return tower end end end

local function GetCurrentUpgradeCost(tower, path) if not tower or not tower.LevelHandler then return nil end local maxLvl = tower.LevelHandler:GetMaxLevel() local curLvl = tower.LevelHandler:GetLevelOnPath(path) if curLvl >= maxLvl then return nil end local ok, baseCost = pcall(function() return tower.LevelHandler:GetLevelUpgradeCost(path, 1) end) if not ok then return nil end local disc = 0 local ok2, d = pcall(function() return tower.BuffHandler and tower.BuffHandler:GetDiscount() or 0 end) if ok2 and typeof(d) == "number" then disc = d end return math.floor(baseCost * (1 - disc)) end

local function WaitForCash(amount) while cashStat.Value < amount do task.wait() end end

local function PlaceTowerRetry(args, axisValue) if soldAxis[axisValue] then return end while true do Remotes.PlaceTower:InvokeServer(unpack(args)) task.wait(0.1) if GetTowerByAxis(axisValue) then return end end end

local function UpgradeTowerRetry(axisValue, path) while true do local tower = GetTowerByAxis(axisValue) if not tower then task.wait() continue end local before = tower.LevelHandler:GetLevelOnPath(path) local cost = GetCurrentUpgradeCost(tower, path) if not cost then return end WaitForCash(cost) Remotes.TowerUpgradeRequest:FireServer(tower.Hash, path, 1) task.wait(0.1) local t = GetTowerByAxis(axisValue) if t and t.LevelHandler:GetLevelOnPath(path) > before then return end end end

local function ChangeTargetRetry(axisValue, targetType) while true do local tower = GetTowerByAxis(axisValue) if tower then Remotes.ChangeQueryType:FireServer(tower.Hash, targetType) return end task.wait() end end

if isfile(macroPath) then local success, macro = pcall(function() return HttpService:JSONDecode(readfile(macroPath)) end) if success and type(macro) == "table" then spawn(function() while true do if enableRebuild and not isRebuilding then isRebuilding = true for _, entry in ipairs(macro) do if entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then local vecTab = entry.TowerVector:split(", ") local pos = Vector3.new(unpack(vecTab)) local args = { tonumber(entry.TowerA1), entry.TowerPlaced, pos, tonumber(entry.Rotation or 0) } WaitForCash(entry.TowerPlaceCost) PlaceTowerRetry(args, pos.X) elseif entry.UpgradePath and entry.TowerUpgraded then UpgradeTowerRetry(tonumber(entry.TowerUpgraded), entry.UpgradePath) elseif entry.ChangeTarget then ChangeTargetRetry(tonumber(entry.ChangeTarget), entry.TargetType) end task.wait(0.1) end isRebuilding = false end task.wait(0.25) end end) end end

print("📌 Recorder + Auto Rebuild Ready with correct hook.")




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