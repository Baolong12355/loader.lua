local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local interface = playerGui:WaitForChild("Interface")
local bottomBar = interface:WaitForChild("BottomBar")
local towersBar = bottomBar:WaitForChild("TowersBar")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local output = {}
local start = os.clock()

-- Cache các hàm thường dùng
local table_insert = table.insert
local string_format = string.format
local tonumber = tonumber
local tostring = tostring
local ipairs = ipairs
local pcall = pcall
local task_wait = task.wait
local os_clock = os.clock

-- Load TowerClass
local function SafeRequire(path, timeout)
    timeout = timeout or 5
    local t0 = os_clock()
    while os_clock() - t0 < timeout do
        local success, result = pcall(function()
            return require(path)
        end)
        if success then return result end
        task_wait()
    end
    return nil
end

local TowerClass
local function LoadTowerClass()
    local ps = LocalPlayer:WaitForChild("PlayerScripts")
    local client = ps:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    return SafeRequire(towerModule)
end

TowerClass = LoadTowerClass()
if not TowerClass then error("Không thể tải TowerClass") end

-- Lấy giá tower theo tên
local function getTowerCostByName(towerName)
    for _, tower in ipairs(towersBar:GetChildren()) do
        if tower.Name == towerName then
            local costFrame = tower:FindFirstChild("CostFrame")
            if costFrame then
                local costText = costFrame:FindFirstChild("CostText")
                if costText then
                    return tonumber(costText.Text) or 0
                end
            end
        end
    end
    return 0
end

-- Serialize vector3
local function vecToStr(vec)
    return string_format("%.5f, %.5f, %.5f", vec.X, vec.Y, vec.Z)
end

-- Lấy vị trí X của tower bằng hash
local function GetTowerXFromHash(hash)
    local towers = TowerClass.GetTowers()
    if not towers then return nil end
    
    local tower = towers[hash]
    if not tower then return nil end

    local success, pos = pcall(function()
        if not tower.Character then return nil end
        local model = tower.Character:GetCharacterModel()
        if not model then return nil end
        local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
        return root and root.Position
    end)

    if success and pos then
        return tonumber(string_format("%.3f", pos.X))
    end
    return nil
end

-- Log đặt tower
local function logTowerPlacement(args)
    if type(args) ~= "table" or #args < 3 then return end
    
    local towerName = args[2]
    if type(towerName) ~= "string" then return end
    
    local towerCost = getTowerCostByName(towerName)
    local towerVector = vecToStr(args[3])

    table_insert(output, {
        TowerPlaceCost = towerCost,
        TowerPlaced = towerName,
        TowerVector = towerVector,
        Rotation = 0,
        TowerA1 = 0
    })
end

-- Log upgrade
local function logUpgrade(args)
    if type(args) ~= "table" or #args < 2 then return end
    
    local hash = tostring(args[1])
    local path = args[2]

    local tower = TowerClass.GetTowers()[hash]
    if not tower or not tower.Config then return end

    local upgradeData = tower.Config.UpgradePathData and tower.Config.UpgradePathData[path]
    local currentLevel = tower.LevelHandler and tower.LevelHandler:GetLevelOnPath(path) or 0
    local cost = upgradeData and upgradeData[currentLevel + 1] and upgradeData[currentLevel + 1].Cost or 0

    local x = GetTowerXFromHash(hash)
    if x then
        table_insert(output, {
            TowerUpgraded = tostring(x),
            UpgradeCost = cost,
            UpgradePath = path
        })
    end
end

-- Log bán tower
local function logSell(args)
    if type(args) ~= "table" or #args < 1 then return end
    
    local hash = tostring(args[1])
    local x = GetTowerXFromHash(hash)
    if x then
        table_insert(output, {
            SellTower = tostring(x)
        })
    end
end

-- Log đổi mục tiêu
local function logChangeTarget(args)
    if type(args) ~= "table" or #args < 2 then return end
    
    local hash = tostring(args[1])
    local targetWanted = args[2]
    local x = GetTowerXFromHash(hash)
    if x then
        table_insert(output, {
            TowerTargetChange = x,
            TargetWanted = targetWanted,
            TargetChangedAt = os_clock() - start
        })
    end
end

-- Hook __namecall
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    if not checkcaller() and (method == "FireServer" or method == "InvokeServer") then
        if not self:IsA("RemoteEvent") and not self:IsA("RemoteFunction") then
            return oldNamecall(self, ...)
        end

        local remoteName = tostring(self.Name)
        local args = {...}

        if remoteName == "PlaceTower" then
            pcall(logTowerPlacement, args)
        elseif remoteName == "TowerUpgradeRequest" then
            pcall(logUpgrade, args)
        elseif remoteName == "SellTower" then
            pcall(logSell, args)
        elseif remoteName == "ChangeQueryType" then
            pcall(logChangeTarget, args)
        end
    end

    return oldNamecall(self, ...)
end)

-- Auto save
task.spawn(function()
    while true do
        task_wait(10)
        local success, json = pcall(function()
            return HttpService:JSONEncode(output)
        end)
        if success and type(json) == "string" then
            pcall(function()
                writefile("tdx_macro_record.json", json)
            end)
        end
    end
end)

print("✅ Đã bật ghi macro vào tdx_macro_record.json")
