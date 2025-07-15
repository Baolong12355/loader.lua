-- TDX Runner - Phiên bản chuẩn hóa
-- Cải thiện: Error handling, logging, performance, code structure

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Constants
local CONSTANTS = {
    SAFE_REQUIRE_TIMEOUT = 5,
    TOWER_SEARCH_TOLERANCE = 1,
    UPGRADE_TIMEOUT = 3,
    PLACEMENT_TIMEOUT = 3,
    RETRY_DELAY = 0.1,
    UPGRADE_CHECK_INTERVAL = 0.1,
    MAX_RETRIES = 3
}

-- Logging system
local Logger = {
    prefix = "[TDX Runner]",
    
    info = function(self, ...)
        print(self.prefix .. " [INFO]", ...)
    end,
    
    warn = function(self, ...)
        warn(self.prefix .. " [WARN]", ...)
    end,
    
    error = function(self, ...)
        error(self.prefix .. " [ERROR] " .. table.concat({...}, " "))
    end,
    
    debug = function(self, ...)
        if getgenv().TDX_DEBUG then
            print(self.prefix .. " [DEBUG]", ...)
        end
    end
}

-- Safe require with timeout
local function SafeRequire(modulePath, timeout)
    timeout = timeout or CONSTANTS.SAFE_REQUIRE_TIMEOUT
    local startTime = os.clock()
    
    while os.clock() - startTime < timeout do
        local success, result = pcall(require, modulePath)
        if success then
            return result
        end
        task.wait()
    end
    
    return nil
end

-- Load TowerClass module
local function LoadTowerClass()
    local playerScripts = player:WaitForChild("PlayerScripts")
    local client = playerScripts:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    
    return SafeRequire(towerModule)
end

-- Initialize TowerClass
local TowerClass = LoadTowerClass()
if not TowerClass then
    Logger:error("Không thể tải TowerClass module")
end

-- Tower management functions
local TowerManager = {
    -- Find tower by X coordinate
    findByAxis = function(self, axisX)
        for hash, tower in pairs(TowerClass.GetTowers()) do
            local success, position = pcall(function()
                local model = tower.Character:GetCharacterModel()
                local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
                return root and root.Position
            end)
            
            if success and position and math.abs(position.X - axisX) <= CONSTANTS.TOWER_SEARCH_TOLERANCE then
                local health = tower.HealthHandler and tower.HealthHandler:GetHealth()
                if health and health > 0 then
                    return hash, tower
                end
            end
        end
        return nil, nil
    end,
    
    -- Get upgrade cost for tower
    getUpgradeCost = function(self, tower, path)
        if not tower or not tower.LevelHandler then
            return nil
        end
        
        local success, cost = pcall(function()
            return tower.LevelHandler:GetLevelUpgradeCost(path, 1)
        end)
        
        return success and cost or nil
    end,
    
    -- Wait for sufficient cash
    waitForCash = function(self, amount)
        Logger:debug("Chờ đủ tiền:", amount)
        while cashStat.Value < amount do
            task.wait()
        end
    end,
    
    -- Place tower with retry logic
    placeTower = function(self, args, axisValue, towerName)
        Logger:info("Đặt tower:", towerName, "tại X =", axisValue)
        
        while true do
            local success, result = pcall(function()
                return Remotes.PlaceTower:InvokeServer(unpack(args))
            end)
            
            if not success then
                Logger:warn("Lỗi khi đặt tower:", result)
                task.wait(CONSTANTS.RETRY_DELAY)
                continue
            end
            
            -- Wait for tower to appear
            local startTime = tick()
            repeat
                task.wait(CONSTANTS.RETRY_DELAY)
                local hash = self:findByAxis(axisValue)
                if hash then
                    Logger:debug("Đặt tower thành công:", towerName)
                    return
                end
            until tick() - startTime > CONSTANTS.PLACEMENT_TIMEOUT
            
            Logger:warn("Đặt tower thất bại, thử lại:", towerName)
        end
    end,
    
    -- Upgrade tower with retry logic
    upgradeTower = function(self, axisValue, upgradePath)
        Logger:info("Nâng cấp tower tại X =", axisValue, "Path =", upgradePath)
        
        local maxTries = (globalPlaceMode == "rewrite") and math.huge or CONSTANTS.MAX_RETRIES
        local tries = 0
        
        while tries < maxTries do
            local hash, tower = self:findByAxis(axisValue)
            if not hash or not tower then
                Logger:warn("Không tìm thấy tower tại X =", axisValue)
                if globalPlaceMode == "rewrite" then
                    tries = tries + 1
                    task.wait()
                    continue
                end
                return
            end
            
            -- Check tower health
            local health = tower.HealthHandler and tower.HealthHandler:GetHealth()
            if not health or health <= 0 then
                Logger:warn("Tower đã chết tại X =", axisValue)
                if globalPlaceMode == "rewrite" then
                    tries = tries + 1
                    task.wait()
                    continue
                end
                return
            end
            
            -- Get current level and cost
            local currentLevel = tower.LevelHandler:GetLevelOnPath(upgradePath)
            local cost = self:getUpgradeCost(tower, upgradePath)
            
            if not cost then
                Logger:warn("Không thể lấy giá nâng cấp")
                return
            end
            
            -- Wait for cash and upgrade
            self:waitForCash(cost)
            
            local success = pcall(function()
                Remotes.TowerUpgradeRequest:FireServer(hash, upgradePath, 1)
            end)
            
            if not success then
                Logger:warn("Lỗi khi gửi yêu cầu nâng cấp")
                tries = tries + 1
                task.wait()
                continue
            end
            
            -- Verify upgrade
            local upgraded = false
            local startTime = tick()
            repeat
                task.wait(CONSTANTS.UPGRADE_CHECK_INTERVAL)
                local _, updatedTower = self:findByAxis(axisValue)
                if updatedTower and updatedTower.LevelHandler then
                    local newLevel = updatedTower.LevelHandler:GetLevelOnPath(upgradePath)
                    if newLevel > currentLevel then
                        upgraded = true
                        break
                    end
                end
            until tick() - startTime > CONSTANTS.UPGRADE_TIMEOUT
            
            if upgraded then
                Logger:debug("Nâng cấp thành công")
                return
            end
            
            tries = tries + 1
            task.wait()
        end
        
        Logger:warn("Nâng cấp thất bại sau", tries, "lần thử")
    end,
    
    -- Change tower target
    changeTarget = function(self, axisValue, targetType)
        Logger:info("Đổi target tại X =", axisValue, "Type:", targetType)
        
        while true do
            local hash = self:findByAxis(axisValue)
            if hash then
                local success = pcall(function()
                    Remotes.ChangeQueryType:FireServer(hash, targetType)
                end)
                
                if success then
                    Logger:debug("Đổi target thành công")
                    return
                else
                    Logger:warn("Lỗi khi đổi target")
                end
            end
            task.wait()
        end
    end,
    
    -- Sell tower
    sellTower = function(self, axisValue)
        Logger:info("Bán tower tại X =", axisValue)
        
        while true do
            local hash = self:findByAxis(axisValue)
            if hash then
                local success = pcall(function()
                    Remotes.SellTower:FireServer(hash)
                end)
                
                if success then
                    task.wait(CONSTANTS.RETRY_DELAY)
                    -- Verify tower was sold
                    if not self:findByAxis(axisValue) then
                        Logger:debug("Bán tower thành công")
                        return
                    end
                else
                    Logger:warn("Lỗi khi bán tower")
                end
            end
            task.wait()
        end
    end
}

-- Configuration management
local function LoadConfig()
    local config = getgenv().TDX_Config or {}
    local macroName = config["Macro Name"] or "x"
    local macroPath = "tdx/macros/" .. macroName .. ".json"
    
    -- Normalize place mode
    local placeMode = config["PlaceMode"] or "normal"
    if placeMode == "unsure" then
        placeMode = "rewrite"
    elseif placeMode == "normal" then
        placeMode = "ashed"
    end
    
    return {
        macroName = macroName,
        macroPath = macroPath,
        placeMode = placeMode
    }
end

-- Macro execution
local function ExecuteMacro()
    local config = LoadConfig()
    globalPlaceMode = config.placeMode
    
    -- Load macro file
    if not isfile(config.macroPath) then
        Logger:error("Không tìm thấy macro file:", config.macroPath)
    end
    
    local success, macro = pcall(function()
        return HttpService:JSONDecode(readfile(config.macroPath))
    end)
    
    if not success then
        Logger:error("Lỗi khi đọc macro file:", macro)
    end
    
    Logger:info("Bắt đầu thực thi macro:", config.macroName)
    Logger:info("Tổng số lệnh:", #macro)
    
    -- Execute macro commands
    for index, entry in ipairs(macro) do
        Logger:debug("Thực thi lệnh", index .. "/" .. #macro)
        
        if entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then
            -- Place tower
            local vectorParts = entry.TowerVector:split(", ")
            local position = Vector3.new(unpack(vectorParts))
            local args = {
                tonumber(entry.TowerA1),
                entry.TowerPlaced,
                position,
                tonumber(entry.Rotation or 0)
            }
            
            TowerManager:waitForCash(entry.TowerPlaceCost)
            TowerManager:placeTower(args, position.X, entry.TowerPlaced)
            
        elseif entry.TowerUpgraded and entry.UpgradePath and entry.UpgradeCost then
            -- Upgrade tower
            local axisValue = tonumber(entry.TowerUpgraded)
            TowerManager:upgradeTower(axisValue, entry.UpgradePath)
            
        elseif entry.ChangeTarget and entry.TargetType then
            -- Change target
            local axisValue = tonumber(entry.ChangeTarget)
            TowerManager:changeTarget(axisValue, entry.TargetType)
            
        elseif entry.SellTower then
            -- Sell tower
            local axisValue = tonumber(entry.SellTower)
            TowerManager:sellTower(axisValue)
            
        else
            Logger:warn("Lệnh không hợp lệ tại index", index)
        end
    end
    
    Logger:info("✅ Macro hoàn tất thành công!")
end

-- Error handling wrapper
local function SafeExecute()
    local success, error = pcall(ExecuteMacro)
    if not success then
        Logger:error("Lỗi nghiêm trọng:", error)
    end
end

-- Start execution
SafeExecute()
