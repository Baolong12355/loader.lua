-- TDX Macro Recorder (Safe, compatible, no argument mutation)
-- Chỉ log, không serialize lại argument, không đổi kiểu dữ liệu, luôn trả đúng args gốc cho hàm gốc

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Tìm tên file macro chưa bị trùng
local fileIndex = 1
while isfile("tdx_macro_"..fileIndex..".json") do
    fileIndex += 1
end
local fileName = "tdx_macro_"..fileIndex..".json"
writefile(fileName, "[]")

local macro = {}
local placedTowers = {}

-- Lấy giá tower từ GUI (giá trị tham khảo)
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

local function vector3ToString(v3)
    return string.format("%.14f, %.14f, %.14f", v3.X, v3.Y, v3.Z)
end

-- Chỉ log, không sửa/serialize lại args
local function handleRemote(self, args)
    local remoteName = tostring(self.Name)
    if remoteName == "PlaceTower" then
        local towerName = tostring(args[2])
        local vector3 = args[3]
        if typeof(vector3) ~= "Vector3" then return end
        local vectorStr = vector3ToString(vector3)
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
    elseif remoteName == "TowerUpgradeRequest" then
        local towerHash = tonumber(args[1])
        local upgradePath = tonumber(args[2])
        local info = placedTowers[towerHash]
        if info then
            local price = info.price or 0
            local entry = {
                UpgradeCost = price,
                UpgradePath = upgradePath,
                TowerUpgraded = towerHash
            }
            table.insert(macro, entry)
            save_macro()
        end
    elseif remoteName == "SellTower" then
        local towerHash = tonumber(args[1])
        if placedTowers[towerHash] then
            local entry = {
                TowerSold = towerHash,
                SellAt = tick()
            }
            table.insert(macro, entry)
            save_macro()
        end
    elseif remoteName == "ChangeTarget" or remoteName == "ChangeQueryType" then
        local towerHash = tonumber(args[1])
        local targetWanted = tonumber(args[2])
        if placedTowers[towerHash] then
            local entry = {
                TowerTargetChange = towerHash,
                TargetWanted = targetWanted,
                TargetChangedAt = tick()
            }
            table.insert(macro, entry)
            save_macro()
        end
    end
end

-- Chỉ lấy args để log, KHÔNG serialize lại, KHÔNG truyền lại!
local function getArgs(...)
    local args = {...}
    return args
end

-- Hook FireServer
local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
    local args = getArgs(...)
    -- Chỉ log, không sửa, không serialize lại
    pcall(handleRemote, self, args)
    return oldFireServer(self, ...)
end)

-- Hook InvokeServer
local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
    local args = getArgs(...)
    pcall(handleRemote, self, args)
    return oldInvokeServer(self, ...)
end)

-- Hook __namecall
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    if method == "FireServer" or method == "InvokeServer" then
        local args = getArgs(...)
        pcall(handleRemote, self, args)
    end
    return oldNamecall(self, ...)
end)

print("✅ Ghi macro TDX (hook an toàn, không sửa args, luôn trả lại hàm gốc, format chuẩn runner) đã bắt đầu. File:", fileName)
