-- Tower Defense Macro Recorder (TowerClass Version) - Updated
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- Tùy chỉnh
local debugMode = true -- bật/tắt in log chi tiết

-- Tải TowerClass
local function LoadTowerClass()
    local success, result = pcall(function()
        return require(player.PlayerScripts.Client.GameClass.TowerClass)
    end)
    return success and result or nil
end

local TowerClass = LoadTowerClass()
if not TowerClass then
    warn("⚠️ Không thể tải TowerClass! Một số tính năng sẽ bị hạn chế")
end

-- Cấu hình
local config = {
    ["Macro Name"] = "macro_" .. os.time(),
    ["Save Path"] = "tdx/macros/"
}
local macroData = {}
local recording = false
local originalFunctions = {}

-- Hàm lưu macro
local function SaveMacro()
    if not recording then return end
    
    if not isfolder("tdx") then makefolder("tdx") end
    if not isfolder("tdx/macros") then makefolder("tdx/macros") end
    
    local fileName = config["Macro Name"]:gsub("%.json$", "") .. ".json"
    local filePath = config["Save Path"] .. fileName
    
    writefile(filePath, HttpService:JSONEncode(macroData))
    if debugMode then print("💾 Đã lưu macro:", filePath) end
end

-- Hook function
local function HookFunction(remote, callback)
    if typeof(remote) == "Instance" and remote:IsA("RemoteFunction") then
        originalFunctions[remote] = remote.InvokeServer
        remote.InvokeServer = function(self, ...)
            local args = {...}
            callback(args)
            return originalFunctions[remote](self, unpack(args))
        end
    elseif typeof(remote) == "Instance" and remote:IsA("RemoteEvent") then
        originalFunctions[remote] = remote.FireServer
        remote.FireServer = function(self, ...)
            local args = {...}
            callback(args)
            return originalFunctions[remote](self, unpack(args))
        end
    end
end

-- Lấy giá
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

-- Dừng ghi macro
local function StopRecording()
    if not recording then return end
    recording = false
    SaveMacro()
    
    for remote, original in pairs(originalFunctions) do
        if remote:IsA("RemoteFunction") then
            remote.InvokeServer = original
        elseif remote:IsA("RemoteEvent") then
            remote.FireServer = original
        end
    end
    originalFunctions = {}
    
    print("⏹️ Đã dừng ghi macro")
end

-- Theo dõi chat
local function ListenToChatForStop()
    player.Chatted:Connect(function(msg)
        if msg:lower():match("^stop$") and recording then
            print("🛑 Phát hiện chat 'stop' → Dừng ghi macro")
            StopRecording()
        end
    end)
end

-- Ghi macro
local function StartRecording()
    if recording then return end
    
    macroData = {}
    recording = true
    
    ListenToChatForStop()
    
    local placeTower = game:GetService("ReplicatedStorage"):FindFirstChild("PlaceTower")
    if placeTower then
        HookFunction(placeTower, function(args)
            if recording then
                local cost = GetTowerCost(args[2])
                table.insert(macroData, {
                    TowerPlaceCost = cost,
                    TowerPlaced = args[2],
                    TowerVector = string.format("%.15g, %.15g, %.15g", args[3].X, args[3].Y, args[3].Z),
                    Rotation = args[4],
                    TowerA1 = tostring(os.time())
                })
                if debugMode then
                    print("📝 Đã ghi đặt tháp:", args[2], "| Giá:", cost)
                end
            end
        end)
    end

    local upgradeRemote = game:GetService("ReplicatedStorage"):FindFirstChild("TowerUpgradeRequest")
    if upgradeRemote then
        HookFunction(upgradeRemote, function(args)
            if recording and TowerClass then
                local tower = TowerClass.GetTowers()[args[1]]
                if tower then
                    local towerType = tower.Type
                    local currentLevel = tower.LevelHandler:GetPathLevel(args[2])
                    local cost = GetTowerCost(towerType, args[2], currentLevel + 1)
                    
                    table.insert(macroData, {
                        UpgradeCost = cost,
                        UpgradePath = args[2],
                        TowerUpgraded = tower:GetPosition().X
                    })
                    if debugMode then
                        print("📝 Đã ghi nâng cấp | Đường:", args[2], "| Giá:", cost)
                    end
                end
            end
        end)
    end

    local targetRemote = game:GetService("ReplicatedStorage"):FindFirstChild("ChangeQueryType")
    if targetRemote then
        HookFunction(targetRemote, function(args)
            if recording and TowerClass then
                local tower = TowerClass.GetTowers()[args[1]]
                if tower then
                    table.insert(macroData, {
                        TowerTargetChange = tower:GetPosition().X,
                        TargetWanted = args[2],
                        TargetChangedAt = os.time()
                    })
                    if debugMode then
                        print("📝 Đã ghi thay đổi mục tiêu:", args[2])
                    end
                end
            end
        end)
    end

    print("🔴 Bắt đầu ghi macro...")
end

-- Toàn cục
getgenv().StartMacroRecording = StartRecording
getgenv().StopMacroRecording = StopRecording

print("✅ Macro Recorder (TowerClass Version) sẵn sàng")
print("💡 Gõ StartMacroRecording() để bắt đầu | Chat 'stop' để dừng")
