local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local debugMode = true
local recording = false
local macroData = {}

local config = {
    ["Macro Name"] = "macro_" .. os.time(),
    ["Save Path"] = "tdx/macros/"
}

-- 🔍 Tìm tower từ workspace theo UniqueID
local function FindTowerById(id)
    local towers = workspace:FindFirstChild("Towers")
    if not towers then return nil end

    for _, tower in ipairs(towers:GetChildren()) do
        if tower:GetAttribute("UniqueID") == id then
            return tower
        end
    end
    return nil
end

-- 💰 Lấy thông tin giá đặt / nâng cấp tháp
local function GetTowerConfig()
    local TowerClass
    pcall(function()
        TowerClass = require(player.PlayerScripts.Client.GameClass.TowerClass)
    end)
    return TowerClass
end

local function GetPlaceCost(towerType)
    local towerClass = GetTowerConfig()
    if not towerClass then return 0 end
    local conf = towerClass.GetTowerConfig(towerType)
    return conf and conf.UpgradePathData.BaseLevelData.Cost or 0
end

local function GetUpgradeCost(towerType, path, level)
    local towerClass = GetTowerConfig()
    if not towerClass then return 0 end
    local conf = towerClass.GetTowerConfig(towerType)
    if not conf then return 0 end
    local upgrade = conf.UpgradePathData[path]
    return (upgrade and upgrade[level] and upgrade[level].Cost) or 0
end

-- 💾 Lưu file
local function SaveMacro()
    if not isfolder("tdx") then makefolder("tdx") end
    if not isfolder("tdx/macros") then makefolder("tdx/macros") end
    local path = config["Save Path"] .. config["Macro Name"] .. ".json"
    writefile(path, HttpService:JSONEncode(macroData))
    if debugMode then print("💾 Đã lưu vào:", path) end
end

-- 🛑 Dừng ghi
local function StopRecording()
    if not recording then return end
    recording = false
    SaveMacro()
    print("⏹️ Dừng ghi macro.")
end

-- 🗨️ Nghe lệnh dừng
player.Chatted:Connect(function(msg)
    if msg:lower() == "stop" and recording then
        StopRecording()
    end
end)

-- ✅ Hook __namecall an toàn
hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    local method = getnamecallmethod()
    local args = { ... }

    if recording and not checkcaller() and (method == "FireServer" or method == "InvokeServer") then
        local name = self.Name

        if name == "PlaceTower" then
            local towerType = args[2]
            local vec = args[3]
            local cost = GetPlaceCost(towerType)

            table.insert(macroData, {
                Action = "Place",
                TowerPlaced = towerType,
                TowerPlaceCost = cost,
                TowerVector = string.format("%.5f, %.5f, %.5f", vec.X, vec.Y, vec.Z),
                Rotation = args[4],
                Timestamp = os.time()
            })

            if debugMode then print("🏗️ Đặt:", towerType, "| Cost:", cost) end

        elseif name == "TowerUpgradeRequest" then
            local tower = FindTowerById(args[1])
            if tower then
                local path = args[2]
                local towerType = tower:GetAttribute("TowerType") or "Unknown"
                local level = tonumber(tower:GetAttribute("Upgrade_" .. path)) or 0
                local cost = GetUpgradeCost(towerType, path, level + 1)

                table.insert(macroData, {
                    Action = "Upgrade",
                    UpgradePath = path,
                    UpgradeCost = cost,
                    TowerUpgraded = tower.Position.X,
                    Timestamp = os.time()
                })

                if debugMode then print("⬆️ Nâng:", towerType, "| Path:", path, "| Level:", level + 1, "| Cost:", cost) end
            end

        elseif name == "ChangeQueryType" then
            local tower = FindTowerById(args[1])
            if tower then
                table.insert(macroData, {
                    Action = "TargetChange",
                    TowerTargetChange = tower.Position.X,
                    TargetWanted = args[2],
                    Timestamp = os.time()
                })
                if debugMode then print("🎯 Target ->", args[2]) end
            end

        elseif name == "SellTowerRequest" then
            local tower = FindTowerById(args[1])
            if tower then
                table.insert(macroData, {
                    Action = "Sell",
                    TowerSold = tower.Position.X,
                    Timestamp = os.time()
                })
                if debugMode then print("💸 Sell ->", tower.Position.X) end
            end
        end
    end

    return getrawmetatable(game).__namecall(self, table.unpack(args))
end))

-- ▶️ Bắt đầu ghi
getgenv().StartMacroRecording = function()
    if recording then return end
    recording = true
    macroData = {}
    print("🔴 Đang ghi macro. Chat 'stop' để dừng.")
end

getgenv().StopMacroRecording = StopRecording
print("✅ Macro Recorder (safe version) đã sẵn sàng.")
