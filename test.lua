local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

-- Cấu hình
local fileName = "TDX_Upgrade_Log_Verified.txt"
local startTime = time()
local offset = 0

-- Xóa file cũ (nếu có)
if isfile(fileName) then delfile(fileName) end
writefile(fileName, "-- TDX Upgrade Log (Server Verified)\n")
writefile(fileName, "-- Generated at: " .. os.date("%d/%m/%Y %X") .. "\n\n")

-- Biến lưu trạng thái
local pendingUpgrades = {} -- [towerHash] = {path, towerID, targetLevel, prevLevel}

-- Hàm lấy level hiện tại từ TowerClass
local function getCurrentLevel(towerHash)
    local tower = require(script.Parent:WaitForChild("TowerClass")).GetTower(towerHash)
    if tower then
        return tower.LevelHandler:GetLevelStats().Level -- Giả sử trả về {path1Level, path2Level}
    end
    return {0, 0} -- Mặc định nếu không tìm thấy
end

-- Ghi log chuẩn
local function writeVerifiedAction(action)
    local elapsed = string.format("%.2f", (time() - offset) - startTime)
    appendfile(fileName, "task.wait(" .. elapsed .. ") -- " .. os.date("%X") .. "\n")
    appendfile(fileName, action .. "\n\n")
    startTime = time() - offset
end

-- Bắt sự kiện xác nhận từ server
ReplicatedStorage.Remotes.TowerUpgradeQueueUpdated.OnClientEvent:Connect(function(data)
    if not data[1] then return end
    
    local upgradeData = data[1]
    local pending = pendingUpgrades[upgradeData.Hash]
    
    if pending then
        local path1Level, path2Level = unpack(upgradeData.LevelReplicationData)
        local currentLevel = (pending.path == 1) and path1Level or path2Level
        
        local logMsg = string.format(
            "TDX:upgradeTower(%d, %d, %d) -- Cost: $%d (Path%d: %d→%d)",
            pending.path,
            pending.towerID,
            currentLevel,
            upgradeData.TotalCost,
            pending.path,
            pending.prevLevel or 0,
            currentLevel
        )
        
        writeVerifiedAction(logMsg)
        pendingUpgrades[upgradeData.Hash] = nil
    end
end)

-- Hook FireServer để lưu thông tin tạm
local oldFireServer
oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
    if self.Name == "TowerUpgradeRequest" then
        local path, towerID, targetLevel = ...
        local towerHash = tostring(towerID) -- Giả định hash là towerID (có thể điều chỉnh)
        
        -- Lấy level hiện tại trước khi nâng cấp
        local prevLevels = getCurrentLevel(towerHash)
        local prevLevel = prevLevels[path] or 0
        
        pendingUpgrades[towerHash] = {
            path = path,
            towerID = towerID,
            targetLevel = targetLevel,
            prevLevel = prevLevel
        }
    end
    return oldFireServer(self, ...)
end)

-- Hook __namecall để bắt mọi gọi remote
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    if getnamecallmethod() == "FireServer" and self.Name == "TowerUpgradeRequest" then
        local path, towerID, targetLevel = ...
        local towerHash = tostring(towerID)
        
        local prevLevels = getCurrentLevel(towerHash)
        local prevLevel = prevLevels[path] or 0
        
        pendingUpgrades[towerHash] = {
            path = path,
            towerID = towerID,
            targetLevel = targetLevel,
            prevLevel = prevLevel
        }
    end
    return oldNamecall(self, ...)
end

print("✅ TDX Upgrade Logger Activated - Server Verified Mode")