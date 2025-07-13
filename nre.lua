local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Cấu hình hệ thống
local CONFIG = {
    RECORD_FILE = "tdx_actions.txt",
    OUTPUT_JSON = "x-1.json",
    VERSION = "1.2",
    PRECISION = 17,
    VERIFY_DELAY = 0.1, -- Đã tối ưu cho TDX
    MAX_RETRIES = 3
}

-- Khởi tạo TowerClass
local TowerClass
local function loadTowerClass()
    if TowerClass then return true end
    
    local success, result = pcall(function()
        local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts", 5)
        local client = PlayerScripts:WaitForChild("Client", 3)
        local gameClass = client:WaitForChild("GameClass", 3)
        return require(gameClass:WaitForChild("TowerClass"))
    end)
    
    if success then
        TowerClass = result
        return true
    end
    return false
end

-- Hệ thống ghi log
local Logger = {
    log = function(self, message, level)
        appendfile("tdx_debug.log", string.format("[%s] %s: %s\n", os.date("%X"), level, message))
    end
}

-- Serializer chính xác
local function serializeValue(value)
    if typeof(value) == "number" then
        return string.format("%.17g", value)
    elseif typeof(value) == "Vector3" then
        return string.format("%.17g, %.17g, %.17g", value.X, value.Y, value.Z)
    elseif typeof(value) == "CFrame" then
        local components = {value:GetComponents()}
        local parts = {}
        for _, v in ipairs(components) do
            table.insert(parts, string.format("%.17g", v))
        end
        return "CFrame.new("..table.concat(parts, ", ")..")"
    elseif type(value) == "string" then
        return string.format("%q", value)
    end
    return tostring(value)
end

-- Lấy giá tower từ UI
local function getTowerCost(towerName)
    local success, cost = pcall(function()
        local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
        local interface = PlayerGui:WaitForChild("Interface")
        local bottomBar = interface:WaitForChild("BottomBar")
        local towersBar = bottomBar:WaitForChild("TowersBar")
        
        for _, btn in ipairs(towersBar:GetChildren()) do
            if btn.Name == towerName then
                return tonumber(btn.CostFrame.CostText.Text:match("%d+")) or 0
            end
        end
        return 0
    end)
    return success and cost or 0
end

-- Tracker vị trí Tower
local TowerTracker = {
    positions = {},
    _running = false,
    
    start = function(self)
        if self._running or not loadTowerClass() then return end
        self._running = true
        
        local heartbeatConn
        heartbeatConn = RunService.Heartbeat:Connect(function()
            for hash, tower in pairs(TowerClass.GetTowers()) do
                if tower and tower.Character then
                    local model = tower.Character:GetCharacterModel()
                    local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
                    if root then
                        self.positions[tostring(hash)] = root.Position
                    end
                end
            end
        end)
        
        table.insert(self._connections, heartbeatConn)
    end,
    
    stop = function(self)
        self._running = false
        for _, conn in ipairs(self._connections) do
            conn:Disconnect()
        end
    end,
    
    getPosition = function(self, hash)
        return self.positions[tostring(hash)]
    end
}

-- Xác minh hành động
local ActionVerifier = {
    verifyPlace = function(self, towerType, position, retryCount)
        for i = 1, (retryCount or CONFIG.MAX_RETRIES) do
            task.wait(CONFIG.VERIFY_DELAY)
            if not loadTowerClass() then return false end
            
            local towers = TowerClass.GetTowers()
            for _, tower in pairs(towers) do
                if tower.Type == towerType then
                    local towerPos = tower:GetPosition()
                    if (towerPos - position).Magnitude < 0.15 then
                        return true
                    end
                end
            end
        end
        return false
    end,
    
    verifyUpgrade = function(self, towerHash, path)
        task.wait(CONFIG.VERIFY_DELAY)
        if not TowerClass then return false end
        
        local tower = TowerClass.GetTower(towerHash)
        return tower and tower.LevelHandler and tower.LevelHandler:GetLevelOnPath(path) > 1
    end,
    
    verifySell = function(self, towerHash)
        task.wait(CONFIG.VERIFY_DELAY)
        return not TowerClass or not TowerClass.GetTower(towerHash)
    end
}

-- Hệ thống ghi macro
local MacroRecorder = {
    init = function(self)
        if isfile(CONFIG.RECORD_FILE) then
            delfile(CONFIG.RECORD_FILE)
        end
        writefile(CONFIG.RECORD_FILE, "")
        
        -- Hook FireServer
        local originalFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
            local args = {...}
            local eventName = self.Name
            
            if table.find({"PlaceTower", "TowerUpgradeRequest", "SellTower"}, eventName) then
                local serialized = {}
                for _, v in ipairs(args) do
                    table.insert(serialized, serializeValue(v))
                end
                
                appendfile(CONFIG.RECORD_FILE, string.format(
                    "%s:%s(%s)\n", 
                    os.clock(),
                    eventName,
                    table.concat(serialized, ",")
                ))
            end
            
            return originalFireServer(self, ...)
        end)
        
        TowerTracker:start()
    end
}

-- Xử lý macro
local function processAndVerify()
    while true do
        if isfile(CONFIG.RECORD_FILE) then
            local actions = {}
            local verificationLog = {}
            local stats = {
                total = 0,
                success = 0,
                startTime = os.clock()
            }
            
            -- Đọc file ghi
            for line in readfile(CONFIG.RECORD_FILE):gmatch("[^\r\n]+") do
                local time, actionType, argsStr = line:match("([^:]+):([^%(]+)%(([^%)]*)%)")
                if actionType and argsStr then
                    local args = {}
                    for arg in argsStr:gmatch("([^,]+)") do
                        local num = tonumber(arg)
                        table.insert(args, num or arg:gsub('[\'"]', ''))
                    end
                    
                    local action = {
                        raw = args,
                        timestamp = tonumber(time)
                    }
                    
                    -- Phân tích hành động cụ thể
                    if actionType == "PlaceTower" and #args >= 5 then
                        local towerType = args[1]
                        local position = Vector3.new(args[2], args[3], args[4])
                        
                        action.output = {
                            TowerPlaceCost = getTowerCost(towerType),
                            TowerPlaced = towerType,
                            TowerVector = string.format("%.17g, %.17g, %.17g", position.X, position.Y, position.Z),
                            Rotation = args[5],
                            TowerA1 = args[6] or ""
                        }
                        
                        action.verify = ActionVerifier.verifyPlace(towerType, position)
                        
                    elseif actionType == "TowerUpgradeRequest" and #args >= 2 then
                        local towerPos = TowerTracker.getPosition(args[1])
                        if towerPos then
                            action.output = {
                                TowerUpgraded = towerPos.X,
                                UpgradeCost = 0,
                                UpgradePath = args[2]
                            }
                            action.verify = ActionVerifier.verifyUpgrade(args[1], args[2])
                        end
                        
                    elseif actionType == "SellTower" and #args >= 1 then
                        local towerPos = TowerTracker.getPosition(args[1])
                        if towerPos then
                            action.output = { SellTower = towerPos.X }
                            action.verify = ActionVerifier.verifySell(args[1])
                        end
                    end
                    
                    if action.output then
                        stats.total = stats.total + 1
                        if action.verify then stats.success = stats.success + 1 end
                        
                        action.output.Verified = action.verify
                        table.insert(actions, action.output)
                        table.insert(verificationLog, action)
                    end
                end
            end
            
            -- Ghi file đầu ra
            if #actions > 0 then
                writefile(CONFIG.OUTPUT_JSON, HttpService:JSONEncode(actions))
                writefile("tdx_verification.json", HttpService:JSONEncode({
                    stats = {
                        successRate = stats.total > 0 and (stats.success/stats.total)*100 or 0,
                        elapsed = os.clock() - stats.startTime
                    },
                    actions = verificationLog
                }))
                
                Logger:log(string.format("Processed %d actions (%.1f%% success)", 
                    stats.total, stats.success/stats.total*100), "INFO")
            end
            
            delfile(CONFIG.RECORD_FILE)
        end
        task.wait(0.1)
    end
end

-- Khởi chạy hệ thống
MacroRecorder.init()
task.spawn(processAndVerify)

print(([[
TDX Macro System v%s Initialized
--------------------------------
Recording File: %s
Output JSON: %s
Verification Delay: %.2fs
Tower Tracking: %s
]]):format(
    CONFIG.VERSION,
    CONFIG.RECORD_FILE,
    CONFIG.OUTPUT_JSON,
    CONFIG.VERIFY_DELAY,
    TowerTracker._running and "ACTIVE" or "INACTIVE"
))
