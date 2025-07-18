-- ✅ TDX Macro Recorder with Auto Rebuild Integration (from macro file + toggle GUI)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")

local fileName = "record.txt"
local macroPath = "tdx/macros/x.json"
local startTime = time()
local offset = 0

if isfile(fileName) then delfile(fileName) end
writefile(fileName, "")

local pending = nil
local timeout = 2
local isRebuilding = false
local enableRebuild = true

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
    pending = {
        type = typeStr,
        code = code,
        created = tick()
    }
end

ReplicatedStorage.Remotes.TowerFactoryQueueUpdated.OnClientEvent:Connect(function(data)
    local d = data[1]
    if not d then return end
    if d.Creation then
        tryConfirm("Place")
    else
        tryConfirm("Sell")
    end
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
    if not isRebuilding then
        local args = serializeArgs(...)
        local name = self.Name
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

local oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    if not isRebuilding then
        local method = getnamecallmethod()
        if method == "FireServer" or method == "InvokeServer" then
            local args = serializeArgs(...)
            local name = self.Name
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
    end
    return oldNamecall(self, ...)
end)

local TowerClass do
    local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    TowerClass = require(towerModule)
end

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
    local ok, baseCost = pcall(function() return tower.LevelHandler:GetLevelUpgradeCost(path, 1) end)
    if not ok then return nil end
    local disc = 0
    local ok2, d = pcall(function() return tower.BuffHandler and tower.BuffHandler:GetDiscount() or 0 end)
    if ok2 and typeof(d) == "number" then disc = d end
    return math.floor(baseCost * (1 - disc))
end

local function WaitForCash(amount)
    while cashStat.Value < amount do task.wait() end
end

local function PlaceTowerRetry(args, axisValue)
    while true do
        Remotes.PlaceTower:InvokeServer(unpack(args))
        task.wait(0.1)
        if GetTowerByAxis(axisValue) then return end
    end
end

local function UpgradeTowerRetry(axisValue, path)
    while true do
        local tower = GetTowerByAxis(axisValue)
        if not tower then task.wait() continue end
        local before = tower.LevelHandler:GetLevelOnPath(path)
        local cost = GetCurrentUpgradeCost(tower, path)
        if not cost then return end
        WaitForCash(cost)
        Remotes.TowerUpgradeRequest:FireServer(tower.Hash, path, 1)
        task.wait(0.1)
        local t = GetTowerByAxis(axisValue)
        if t and t.LevelHandler:GetLevelOnPath(path) > before then return end
    end
end

local function ChangeTargetRetry(axisValue, targetType)
    while true do
        local tower = GetTowerByAxis(axisValue)
        if tower then
            Remotes.ChangeQueryType:FireServer(tower.Hash, targetType)
            return
        end
        task.wait()
    end
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
                    for _, entry in ipairs(macro) do
                        if entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then
                            local vecTab = entry.TowerVector:split(", ")
                            local pos = Vector3.new(unpack(vecTab))
                            local args = { tonumber(entry.TowerA1), entry.TowerPlaced, pos, tonumber(entry.Rotation or 0) }
                            WaitForCash(entry.TowerPlaceCost)
                            PlaceTowerRetry(args, pos.X)
                        elseif entry.UpgradePath and entry.TowerUpgraded then
                            UpgradeTowerRetry(tonumber(entry.TowerUpgraded), entry.UpgradePath)
                        elseif entry.ChangeTarget then
                            ChangeTargetRetry(tonumber(entry.ChangeTarget), entry.TargetType)
                        end
                        task.wait(0.1)
                    end
                    isRebuilding = false
                end
                task.wait(0.25)
            end
        end)
    end
end

pcall(function()
    local ScreenGui = Instance.new("ScreenGui", player:WaitForChild("PlayerGui"))
    ScreenGui.Name = "TDX_GUI"

    local Frame = Instance.new("Frame", ScreenGui)
    Frame.Size = UDim2.new(0, 160, 0, 50)
    Frame.Position = UDim2.new(0, 20, 0, 60)
    Frame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    Frame.Active = true
    Frame.Draggable = true

    local button = Instance.new("TextButton", Frame)
    button.Size = UDim2.new(1, 0, 1, 0)
    button.Text = "🔁 Rebuild: ON"
    button.BackgroundColor3 = Color3.fromRGB(40, 180, 40)

    button.MouseButton1Click:Connect(function()
        enableRebuild = not enableRebuild
        button.Text = enableRebuild and "🔁 Rebuild: ON" or "⛔ Rebuild: OFF"
        button.BackgroundColor3 = enableRebuild and Color3.fromRGB(40, 180, 40) or Color3.fromRGB(180, 40, 40)
    end)
end)

print("📌 Macro Recorder + Rebuild Ready with GUI toggle")
