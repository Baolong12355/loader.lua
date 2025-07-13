local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Configuration
local CONFIG = {
    RECORD_FILE = "tdx_macro_records.txt",
    OUTPUT_JSON = "tdx/macros/x-1.json",
    VERSION = "2.3",
    DELAY = 0.1, -- Optimized delay for TDX
    MAX_RETRIES = 2,
    DEBUG_MODE = true
}

-- Initialize logging system
local Logger = {
    log = function(self, message, level)
        if CONFIG.DEBUG_MODE then
            appendfile("tdx_macro_debug.log", string.format("[%s][%s] %s\n", os.date("%X"), level, message))
        end
    end
}

-- TowerClass loader with enhanced error handling
local TowerClass
local function loadTowerClass()
    if TowerClass then return true end
    
    local startTime = os.clock()
    local success, result = pcall(function()
        local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts", 5)
        if not PlayerScripts then return nil end
        
        local client = PlayerScripts:FindFirstChild("Client")
        if not client then return nil end
        
        local gameClass = client:FindFirstChild("GameClass")
        if not gameClass then return nil end
        
        return require(gameClass:WaitForChild("TowerClass"))
    end)
    
    if success and result then
        TowerClass = result
        Logger:log(string.format("TowerClass loaded in %.3fs", os.clock()-startTime), "INFO")
        return true
    else
        Logger:log("Failed to load TowerClass: "..tostring(result), "ERROR")
        return false
    end
end

-- Precise value serialization
local function serialize(value)
    if typeof(value) == "number" then
        return string.format("%.17g", value)
    elseif typeof(value) == "Vector3" then
        return string.format("Vector3.new(%.17g, %.17g, %.17g)", value.X, value.Y, value.Z)
    elseif typeof(value) == "CFrame" then
        local components = {value:GetComponents()}
        local parts = {}
        for i, v in ipairs(components) do
            table.insert(parts, string.format("%.17g", v))
        end
        return string.format("CFrame.new(%s)", table.concat(parts, ", "))
    elseif type(value) == "string" then
        return string.format("%q", value)
    elseif type(value) == "boolean" then
        return tostring(value)
    elseif type(value) == "table" then
        local parts = {}
        for k, v in pairs(value) do
            table.insert(parts, string.format("[%s] = %s", serialize(k), serialize(v)))
        end
        return "{"..table.concat(parts, ", ").."}"
    end
    return tostring(value)
end

-- Enhanced Tower Tracker
local TowerTracker = {
    positions = {},
    _connections = {},
    _running = false,
    
    start = function(self)
        if self._running or not loadTowerClass() then return end
        self._running = true
        
        -- Clean up previous connections
        self:stop()
        
        -- Main tracking loop
        table.insert(self._connections, RunService.Heartbeat:Connect(function()
            local success, err = pcall(function()
                local towers = TowerClass.GetTowers()
                for hash, tower in pairs(towers) do
                    if tower and tower.Character then
                        local model = tower.Character:GetCharacterModel()
                        if model then
                            local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
                            if root then
                                self.positions[tostring(hash)] = root.Position
                            end
                        end
                    end
                end
            end)
            
            if not success then
                Logger:log("Tracker error: "..tostring(err), "ERROR")
            end
        end))
    end,
    
    stop = function(self)
        self._running = false
        for _, conn in ipairs(self._connections) do
            conn:Disconnect()
        end
        self._connections = {}
    end,
    
    getPosition = function(self, hash)
        return self.positions[tostring(hash)]
    end
}

-- Visual Feedback System
local VisualFeedback = {
    showMarker = function(position, color, text, duration)
        local part = Instance.new("Part")
        part.Anchored = true
        part.CanCollide = false
        part.Size = Vector3.new(1, 1, 1)
        part.Position = position
        part.Color = color
        part.Transparency = 0.7
        part.Parent = workspace
        
        local billboard = Instance.new("BillboardGui")
        billboard.Size = UDim2.new(5, 0, 5, 0)
        billboard.Adornee = part
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.Text = text
        label.TextScaled = true
        label.BackgroundTransparency = 1
        label.TextColor3 = Color3.new(1, 1, 1)
        label.Parent = billboard
        
        billboard.Parent = part
        
        game:GetService("Debris"):AddItem(part, duration or 3)
    end
}

-- Action Verifier
local ActionVerifier = {
    verifyPlace = function(self, towerType, position)
        for i = 1, CONFIG.MAX_RETRIES do
            task.wait(CONFIG.DELAY)
            if not loadTowerClass() then return false end
            
            for _, tower in pairs(TowerClass.GetTowers()) do
                if tower.Type == towerType then
                    local towerPos = tower:GetPosition()
                    if (towerPos - position).Magnitude < 0.15 then
                        if CONFIG.DEBUG_MODE then
                            VisualFeedback.showMarker(position, Color3.new(0, 1, 0), "✓", 2)
                        end
                        return true
                    end
                end
            end
        end
        
        if CONFIG.DEBUG_MODE then
            VisualFeedback.showMarker(position, Color3.new(1, 0, 0), "✗", 2)
        end
        return false
    end,
    
    verifyUpgrade = function(self, towerHash, path)
        task.wait(CONFIG.DELAY)
        if not TowerClass then return false end
        
        local tower = TowerClass.GetTower(towerHash)
        local success = tower and tower.LevelHandler and tower.LevelHandler:GetLevelOnPath(path) > 0
        
        if success and CONFIG.DEBUG_MODE then
            local pos = TowerTracker:getPosition(towerHash)
            if pos then
                VisualFeedback.showMarker(pos, Color3.new(0, 0, 1), "↑", 2)
            end
        end
        
        return success
    end,
    
    verifySell = function(self, towerHash)
        task.wait(CONFIG.DELAY)
        if not TowerClass then return false end
        
        local tower = TowerClass.GetTower(towerHash)
        local success = tower == nil
        
        if success and CONFIG.DEBUG_MODE then
            local pos = TowerTracker.positions[tostring(towerHash)]
            if pos then
                VisualFeedback.showMarker(pos, Color3.new(1, 0.5, 0), "$", 2)
            end
        end
        
        return success
    end
}

-- Tower Cost Helper
local CostHelper = {
    getTowerCost = function(towerName)
        local success, cost = pcall(function()
            local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
            local interface = PlayerGui:WaitForChild("Interface")
            local bottomBar = interface:WaitForChild("BottomBar")
            local towersBar = bottomBar:WaitForChild("TowersBar")
            
            for _, btn in ipairs(towersBar:GetChildren()) do
                if btn.Name == towerName then
                    local costText = btn:FindFirstChild("CostFrame"):FindFirstChild("CostText")
                    return tonumber(costText.Text:match("%d+")) or 0
                end
            end
            return 0
        end)
        return success and cost or 0
    end
}

-- Macro Recorder
local MacroRecorder = {
    _initialized = false,
    
    init = function(self)
        if self._initialized then return end
        self._initialized = true
        
        -- Initialize files
        if isfile(CONFIG.RECORD_FILE) then
            delfile(CONFIG.RECORD_FILE)
        end
        writefile(CONFIG.RECORD_FILE, "-- TDX Macro v"..CONFIG.VERSION.."\n")
        
        -- Create directories if needed
        if makefolder and not isfolder("tdx/macros") then
            makefolder("tdx")
            makefolder("tdx/macros")
        end
        
        -- Hook RemoteEvent
        local originalFireServer = nil
        originalFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
            if not self:IsA("RemoteEvent") then
                return originalFireServer(self, ...)
            end

            local eventName = self.Name
            local args = {...}
            
            if table.find({"PlaceTower", "SellTower", "TowerUpgradeRequest", "ChangeQueryType"}, eventName) then
                local serializedArgs = {}
                for _, arg in ipairs(args) do
                    table.insert(serializedArgs, serialize(arg))
                end
                
                local recordLine = string.format("wait(%s)\n%s:FireServer(%s)\n",
                    string.format("%.17g", os.clock()),
                    serialize(self),
                    table.concat(serializedArgs, ", ")
                )
                
                appendfile(CONFIG.RECORD_FILE, recordLine)
            end
            
            return originalFireServer(self, ...)
        end)

        TowerTracker:start()
    end
}

-- Macro Processor
local MacroProcessor = {
    process = function(self)
        if not loadTowerClass() then return end
        Logger:log("Starting macro processing", "INFO")
        
        while true do
            if isfile(CONFIG.RECORD_FILE) then
                local content = readfile(CONFIG.RECORD_FILE)
                local output = {
                    metadata = {
                        version = CONFIG.VERSION,
                        created = os.date("%Y-%m-%d %H:%M:%S"),
                        map = workspace:GetAttribute("CurrentMap") or "unknown",
                        precision = "full"
                    },
                    actions = {}
                }

                local stats = {
                    total = 0,
                    success = 0
                }

                for line in content:gmatch("[^\r\n]+") do
                    if line:match("FireServer%(") then
                        local eventPath = line:match("^(.-):FireServer%(")
                        local argsStr = line:match("FireServer%((.-)%)$")
                        
                        if eventPath and argsStr then
                            local eventName = eventPath:match("%.([%w_]+)$") or eventPath
                            local success, args = pcall(function()
                                return loadstring("return "..argsStr)()
                            end)
                            
                            if success and type(args) == "table" then
                                stats.total = stats.total + 1
                                local action = {
                                    type = eventName,
                                    raw_args = args,
                                    verified = false
                                }

                                -- Process specific action types
                                if eventName == "PlaceTower" and #args >= 5 then
                                    action.TowerPlaceCost = CostHelper.getTowerCost(args[1])
                                    action.TowerPlaced = args[1]
                                    action.TowerVector = string.format("%.17g, %.17g, %.17g", args[2], args[3], args[4])
                                    action.Rotation = args[5]
                                    action.TowerA1 = args[6] or ""
                                    
                                    action.verified = ActionVerifier:verifyPlace(
                                        args[1], 
                                        Vector3.new(args[2], args[3], args[4])
                                    )
                                    
                                elseif eventName == "TowerUpgradeRequest" and #args >= 2 then
                                    local towerPos = TowerTracker:getPosition(args[1])
                                    if towerPos then
                                        action.TowerUpgraded = towerPos.X
                                        action.UpgradeCost = 0
                                        action.UpgradePath = args[2]
                                        
                                        action.verified = ActionVerifier:verifyUpgrade(args[1], args[2])
                                    end
                                    
                                elseif eventName == "SellTower" and #args >= 1 then
                                    local towerPos = TowerTracker:getPosition(args[1])
                                    if towerPos then
                                        action.SellTower = towerPos.X
                                        action.verified = ActionVerifier:verifySell(args[1])
                                    end
                                end
                                
                                if action.verified then
                                    stats.success = stats.success + 1
                                end
                                
                                table.insert(output.actions, action)
                            end
                        end
                    end
                end

                -- Save output
                if #output.actions > 0 then
                    writefile(CONFIG.OUTPUT_JSON, HttpService:JSONEncode(output))
                    delfile(CONFIG.RECORD_FILE)
                    
                    Logger:log(string.format(
                        "Processed %d actions (%d successful, %.1f%%)",
                        stats.total,
                        stats.success,
                        (stats.success/math.max(1, stats.total)) * 100
                    ), "INFO")
                end
            end
            task.wait(CONFIG.DELAY)
        end
    end
}

-- Initialize and run system
local function main()
    Logger:log("Initializing TDX Macro System v"..CONFIG.VERSION, "INFO")
    
    MacroRecorder:init()
    task.spawn(function()
        MacroProcessor:process()
    end)
    
    -- Cleanup on script termination
    game:BindToClose(function()
        TowerTracker:stop()
        Logger:log("System shutdown", "INFO")
    end)
end

main()

print(([[

TDX Macro System v%s Ready
---------------------------------
• Output File: %s
• Verify Delay: %.2fs
• Debug Mode: %s
• Tower Tracking: %s
]]):format(
    CONFIG.VERSION,
    CONFIG.OUTPUT_JSON,
    CONFIG.DELAY,
    CONFIG.DEBUG_MODE and "ON" or "OFF",
    TowerTracker._running and "ACTIVE" or "INACTIVE"
))
