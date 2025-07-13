local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Cấu hình chính xác
local CONFIG = {
    RECORD_FILE = "tdx_macro_records.txt",
    OUTPUT_JSON = "tdx/macros/processed.json",
    TOWER_POSITION_UPDATE_INTERVAL = 0.05,  -- Giảm khoảng thời gian cập nhật
    FILE_CHECK_INTERVAL = 0.2,
    VERSION = "2.2",
    PRECISION = 17  -- Số chữ số thập phân tối đa (double precision)
}

-- Khởi tạo TowerClass với xử lý lỗi chi tiết
local TowerClass
local function loadTowerClass()
    if TowerClass then return true end
    
    local function warnLoadFailure(step)
        warn("[TDX Macro] Không thể load TowerClass tại bước:", step)
    end

    local success, result = pcall(function()
        local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts", 5)
        if not PlayerScripts then warnLoadFailure("PlayerScripts"); return nil end
        
        local client = PlayerScripts:FindFirstChild("Client")
        if not client then warnLoadFailure("Client"); return nil end
        
        local gameClass = client:FindFirstChild("GameClass")
        if not gameClass then warnLoadFailure("GameClass"); return nil end
        
        local towerModule = gameClass:FindFirstChild("TowerClass")
        if not towerModule then warnLoadFailure("TowerClass module"); return nil end
        
        return require(towerModule)
    end)

    if success and result then
        TowerClass = result
        return true
    end
    return false
end

-- Serializer chính xác tuyệt đối
local function serializeExactValue(value)
    if typeof(value) == "Vector3" then
        return string.format("Vector3.new(%.17g, %.17g, %.17g)", value.X, value.Y, value.Z)
    elseif typeof(value) == "CFrame" then
        local components = {value:GetComponents()}
        local parts = {}
        for i, v in ipairs(components) do
            table.insert(parts, string.format("%.17g", v))
        end
        return string.format("CFrame.new(%s)", table.concat(parts, ", "))
    elseif typeof(value) == "Instance" then
        return string.format('game:GetService("%s"):WaitForChild("%s")', value.Parent.ClassName, value.Name)
    elseif type(value) == "number" then
        return string.format("%.17g", value)
    elseif type(value) == "table" then
        local parts = {}
        for k, v in pairs(value) do
            table.insert(parts, string.format("[%s] = %s", 
                serializeExactValue(k), 
                serializeExactValue(v)))
        end
        return "{"..table.concat(parts, ", ").."}"
    elseif type(value) == "string" then
        return string.format("%q", value)
    end
    return tostring(value)
end

-- Bộ đếm thời gian chính xác cao
local HighPrecisionTimer = {
    _lastTime = os.clock(),
    getElapsed = function(self)
        local current = os.clock()
        local elapsed = current - self._lastTime
        self._lastTime = current
        return string.format("%.17g", elapsed)
    end,
    reset = function(self)
        self._lastTime = os.clock()
    end
}

-- Trình theo dõi vị trí tower chính xác
local PrecisionTowerTracker = {
    _positions = {},
    _connections = {},
    _isRunning = false,
    
    start = function(self)
        if self._isRunning then return end
        self._isRunning = true
        
        if not loadTowerClass() then
            warn("[Tracker] Không thể khởi động do thiếu TowerClass")
            return
        end

        -- Kết nối Heartbeat với tốc độ cao
        table.insert(self._connections, 
            RunService.Heartbeat:Connect(function()
                local towers = TowerClass.GetTowers()
                for hash, tower in pairs(towers) do
                    if tower and tower.Character then
                        local model = tower.Character:GetCharacterModel()
                        local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
                        if root then
                            local pos = root.Position
                            self._positions[tostring(hash)] = {
                                x = pos.X,
                                y = pos.Y,
                                z = pos.Z
                            }
                        end
                    end
                end
            end)
        )
    end,
    
    stop = function(self)
        self._isRunning = false
        for _, conn in ipairs(self._connections) do
            conn:Disconnect()
        end
        self._connections = {}
    end,
    
    getPosition = function(self, hash)
        return self._positions[tostring(hash)] or false
    end
}

-- Bản ghi macro chính xác
local MacroRecorder = {
    _initialized = false,
    
    init = function(self)
        if self._initialized then return end
        self._initialized = true

        -- Chuẩn bị file
        if isfile(CONFIG.RECORD_FILE) then
            delfile(CONFIG.RECORD_FILE)
        end
        writefile(CONFIG.RECORD_FILE, "-- TDX Macro v"..CONFIG.VERSION.." (Precision Mode)\n")
        
        -- Hook hàm FireServer chính xác
        local originalFireServer = nil
        originalFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
            if not self:IsA("RemoteEvent") then
                return originalFireServer(self, ...)
            end

            local eventName = self.Name
            local args = {...}
            
            -- Chỉ ghi lại các event quan trọng của TDX
            if table.find({"PlaceTower", "SellTower", "TowerUpgradeRequest", "ChangeQueryType"}, eventName) then
                local serializedArgs = {}
                for _, arg in ipairs(args) do
                    table.insert(serializedArgs, serializeExactValue(arg))
                end
                
                local recordLine = string.format("wait(%s)\n%s:FireServer(%s)\n",
                    HighPrecisionTimer:getElapsed(),
                    serializeExactValue(self),
                    table.concat(serializedArgs, ", ")
                )
                
                appendfile(CONFIG.RECORD_FILE, recordLine)
            end
            
            return originalFireServer(self, ...)
        end)

        -- Bắt đầu theo dõi tower
        PrecisionTowerTracker:start()
    end
}

-- Bộ xử lý macro
local MacroProcessor = {
    process = function(self)
        if not loadTowerClass() then return end
        
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
                                local action = {
                                    type = eventName,
                                    time = HighPrecisionTimer:getElapsed(),
                                    raw_args = args
                                }

                                -- Xử lý đặc biệt cho từng loại event
                                if eventName == "PlaceTower" and #args >= 5 then
                                    action.action = "place"
                                    action.tower_type = args[1]
                                    action.position = {x = args[2], y = args[3], z = args[4]}
                                    action.rotation = args[5]
                                    
                                elseif eventName == "TowerUpgradeRequest" and #args >= 2 then
                                    local towerPos = PrecisionTowerTracker:getPosition(args[1])
                                    if towerPos then
                                        action.action = "upgrade"
                                        action.tower_position = towerPos
                                        action.path = args[2]
                                    end
                                    
                                elseif eventName == "SellTower" and #args >= 1 then
                                    local towerPos = PrecisionTowerTracker:getPosition(args[1])
                                    if towerPos then
                                        action.action = "sell"
                                        action.tower_position = towerPos
                                    end
                                    
                                elseif eventName == "ChangeQueryType" and #args >= 2 then
                                    local towerPos = PrecisionTowerTracker:getPosition(args[1])
                                    if towerPos then
                                        action.action = "change_target"
                                        action.tower_position = towerPos
                                        action.target_type = args[2]
                                    end
                                end

                                table.insert(output.actions, action)
                            end
                        end
                    end
                end

                -- Ghi file JSON với đầy đủ độ chính xác
                writefile(CONFIG.OUTPUT_JSON, HttpService:JSONEncode(output))
            end
            wait(CONFIG.FILE_CHECK_INTERVAL)
        end
    end
}

-- Khởi động hệ thống
MacroRecorder:init()
task.spawn(MacroProcessor.process)

print(([[

TDX Macro System (Precision Mode) v%s
-------------------------------------------------
• Độ chính xác: %d chữ số thập phân
• File ghi: %s
• File xuất: %s
• Theo dõi vị trí: %s
• Tần số cập nhật: %.0fHz
]])).format(
    CONFIG.VERSION,
    CONFIG.PRECISION,
    CONFIG.RECORD_FILE,
    CONFIG.OUTPUT_JSON,
    PrecisionTowerTracker._isRunning and "BẬT" or "TẮT",
    1/CONFIG.TOWER_POSITION_UPDATE_INTERVAL
))
