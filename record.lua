local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local macro = {}
local placedTowers = {}  -- key: X, value: {price, towerName, vector, rotation, tick}

local fileName = "tdx_macro.json"

-- Lấy giá tower từ GUI
local function get_tower_price_from_gui(towerName)
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return 0 end
    local interface = playerGui:FindFirstChild("Interface")
    if not interface then return 0 end
    local bottomBar = interface:FindFirstChild("BottomBar")
    if not bottomBar then return 0 end
    local towersBar = bottomBar:FindFirstChild("TowersBar")
    if not towersBar then return 0 end
    for _, tower in ipairs(towersBar:GetChildren()) do
        if tower.Name == towerName then
            local costFrame = tower:FindFirstChild("CostFrame")
            if costFrame then
                local costText = costFrame:FindFirstChild("CostText")
                if costText then
                    local num = tonumber(costText.Text:gsub("%D", ""))
                    return num or 0
                end
            end
        end
    end
    return 0
end

local function save_macro()
    writefile(fileName, HttpService:JSONEncode(macro))
end

-- Đặt tower
local function onPlaceTower(args)
    -- args = {hash, towerName, vector3, rotation, ...}
    local towerName = tostring(args[2])
    local vector3 = args[3]
    if typeof(vector3) ~= "Vector3" then return end
    local vectorStr = string.format("%.14f, %.14f, %.14f", vector3.X, vector3.Y, vector3.Z)
    local rotation = tonumber(args[4]) or 0
    local timeNow = tostring(tick())
    local price = get_tower_price_from_gui(towerName)
    local keyX = tonumber(string.format("%.14f", vector3.X))
    placedTowers[keyX] = {
        price = price,
        towerName = towerName,
        vector = vectorStr,
        rotation = rotation,
        tick = timeNow
    }
    local entry = {
        TowerPlaceCost = price,
        TowerPlaced = towerName,
        TowerVector = vectorStr,
        Rotation = rotation,
        TowerA1 = timeNow
    }
    table.insert(macro, entry)
    save_macro()
end

-- Nâng cấp tower
local function onUpgradeTower(args)
    -- args = {hash, upgradePath, ...}
    local towerHash = tostring(args[1])
    local upgradePath = tonumber(args[2])
    local keyX = tonumber(towerHash)
    local info = placedTowers[keyX]
    if info then
        local price = info.price or 0
        local entry = {
            UpgradeCost = price,
            UpgradePath = upgradePath,
            TowerUpgraded = keyX
        }
        table.insert(macro, entry)
        save_macro()
    else
        warn("[TDX Macro] Không tìm thấy vị trí X cho hash khi upgrade!")
    end
end

-- Bán tower
local function onSellTower(args)
    -- args = {hash, ...}
    local towerHash = tostring(args[1])
    local keyX = tonumber(towerHash)
    if placedTowers[keyX] then
        local entry = {
            TowerSold = keyX,
            SellAt = tick()
        }
        table.insert(macro, entry)
        save_macro()
    else
        warn("[TDX Macro] Không tìm thấy vị trí X cho hash khi bán tower!")
    end
end

-- Đổi target
local function onChangeTarget(args)
    -- args = {hash, targetWanted, ...}
    local towerHash = tostring(args[1])
    local targetWanted = tonumber(args[2])
    local keyX = tonumber(towerHash)
    if placedTowers[keyX] then
        local entry = {
            TowerTargetChange = keyX,
            TargetWanted = targetWanted,
            TargetChangedAt = tick()
        }
        table.insert(macro, entry)
        save_macro()
    else
        warn("[TDX Macro] Không tìm thấy vị trí X cho hash khi đổi target!")
    end
end

local function serializeArgs(...)
    local args = {...}
    local out = {}
    for i,v in ipairs(args) do out[i] = v end
    return out
end

local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    if not checkcaller() and (method == "FireServer" or method == "InvokeServer") then
        local remoteName = self.Name
        local args = serializeArgs(...)
        if remoteName == "PlaceTower" then
            onPlaceTower(args)
        elseif remoteName == "TowerUpgradeRequest" then
            onUpgradeTower(args)
        elseif remoteName == "SellTower" then
            onSellTower(args)
        elseif remoteName == "ChangeTarget" then
            onChangeTarget(args)
        end
    end
    return oldNamecall(self, ...)
end)

print("✅ Macro TDX (chuẩn format, chạy tốt với runner của bạn) đã HOẠT ĐỘNG.")
