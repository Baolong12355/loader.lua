local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local TowerClass = nil
local success, result = pcall(function()
    return require(player.PlayerScripts.Client.GameClass.TowerClass)
end)
if success then
    TowerClass = result
else
    warn("⚠️ Không thể load TowerClass.")
end

local debugMode = true -- bật tắt in debug
local macroData = {}
local recording = false
local oldNamecall

local config = {
    ["Macro Name"] = "macro_" .. os.time(),
    ["Save Path"] = "tdx/macros/"
}

-- lấy giá
local function GetTowerCost(towerType, path, level)
    if not TowerClass then return 0 end

    local towerConfig
    pcall(function()
        towerConfig = TowerClass.GetTowerConfig(towerType)
    end)

    if not towerConfig then return 0 end

    if path and level then
        local upgradePath = towerConfig.UpgradePathData[path]
        if upgradePath and upgradePath[level] then
            return upgradePath[level].Cost or 0
        end
    else
        return towerConfig.UpgradePathData.BaseLevelData.Cost or 0
    end

    return 0
end

-- lưu file
local function SaveMacro()
    if not isfolder("tdx") then makefolder("tdx") end
    if not isfolder("tdx/macros") then makefolder("tdx/macros") end

    local fileName = config["Macro Name"]:gsub("%.json$", "") .. ".json"
    local filePath = config["Save Path"] .. fileName

    writefile(filePath, HttpService:JSONEncode(macroData))
    if debugMode then print("💾 Đã lưu macro:", filePath) end
end

-- dừng
local function StopRecording()
    if not recording then return end
    recording = false
    SaveMacro()

    print("⏹️ Đã dừng ghi macro")

    -- khôi phục namecall
    if oldNamecall then
        hookmetamethod(game, "__namecall", oldNamecall)
    end
end

-- bắt chat "stop"
local function ListenForStopCommand()
    player.Chatted:Connect(function(msg)
        if msg:lower() == "stop" and recording then
            print("🛑 Đã phát hiện 'stop'")
            StopRecording()
        end
    end)
end

-- bắt remote bằng __namecall
local function HookRemoteCalls()
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local args = {...}
        local method = getnamecallmethod()

        if not checkcaller() and recording and (method == "FireServer" or method == "InvokeServer") then
            local name = self.Name

            if name == "PlaceTower" then
                local towerType = args[2]
                local vec = args[3]
                local cost = GetTowerCost(towerType)
                table.insert(macroData, {
                    TowerPlaceCost = cost,
                    TowerPlaced = towerType,
                    TowerVector = string.format("%.15g, %.15g, %.15g", vec.X, vec.Y, vec.Z),
                    Rotation = args[4],
                    TowerA1 = tostring(os.time())
                })
                if debugMode then print("📌 Ghi đặt tháp:", towerType, " | Cost:", cost) end

            elseif name == "TowerUpgradeRequest" and TowerClass then
                local tower = TowerClass.GetTowers()[args[1]]
                if tower then
                    local towerType = tower.Type
                    local path = args[2]
                    local currentLevel = tower.LevelHandler:GetPathLevel(path)
                    local cost = GetTowerCost(towerType, path, currentLevel + 1)
                    table.insert(macroData, {
                        UpgradeCost = cost,
                        UpgradePath = path,
                        TowerUpgraded = tower:GetPosition().X
                    })
                    if debugMode then print("📌 Ghi nâng cấp | Path:", path, " | Cost:", cost) end
                end

            elseif name == "ChangeQueryType" and TowerClass then
                local tower = TowerClass.GetTowers()[args[1]]
                if tower then
                    table.insert(macroData, {
                        TowerTargetChange = tower:GetPosition().X,
                        TargetWanted = args[2],
                        TargetChangedAt = os.time()
                    })
                    if debugMode then print("📌 Ghi đổi mục tiêu:", args[2]) end
                end
            end
        end

        return oldNamecall(self, unpack(args))
    end)
end

-- bắt đầu
local function StartRecording()
    if recording then return end
    macroData = {}
    recording = true

    HookRemoteCalls()
    ListenForStopCommand()

    print("🔴 Đang ghi macro... Chat 'stop' để dừng.")
end

-- export toàn cục
getgenv().StartMacroRecording = StartRecording
getgenv().StopMacroRecording = StopRecording

print("✅ Macro Recorder (hookmetamethod version) sẵn sàng")
