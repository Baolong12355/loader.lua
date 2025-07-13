local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

-- Sử dụng NetworkingHandler từ game
local Common = game:GetService("ReplicatedStorage"):WaitForChild("TDX_Shared"):WaitForChild("Common")
local NetworkingHandler = require(Common:WaitForChild("NetworkingHandler"))
local BindableHandler = require(Common:WaitForChild("BindableHandler"))

-- Config
local CONFIG = {
    RECORD_FILE = "record.txt",
    OUTPUT_JSON = "x-1.json"
}

-- Lấy TowerClass từ hệ thống game
local TowerClass
local function GetTowerClass()
    if not TowerClass then
        local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
        local Client = PlayerScripts:WaitForChild("Client")
        local GameClass = Client:WaitForChild("GameClass")
        TowerClass = require(GameClass:WaitForChild("TowerClass"))
    end
    return TowerClass
end

-- Hệ thống ghi macro
local MacroRecorder = {
    _remoteEvents = {},
    _towerPositions = {},
    
    Init = function(self)
        -- Hook các remote event quan trọng
        self:_HookRemoteEvent("PlaceTower")
        self:_HookRemoteEvent("TowerUpgradeRequest")
        self:_HookRemoteEvent("SellTower")
        
        -- Bắt đầu theo dõi vị trí tower
        self:_StartTracking()
    end,
    
    _HookRemoteEvent = function(self, eventName)
        local event = NetworkingHandler.GetEvent(eventName)
        
        local originalFireServer = event.FireServer
        event.FireServer = function(_, ...)
            local args = {...}
            self:_ProcessEvent(eventName, args)
            return originalFireServer(event, ...)
        end
        
        table.insert(self._remoteEvents, event)
    end,
    
    _ProcessEvent = function(self, eventName, args)
        if eventName == "PlaceTower" and #args >= 5 then
            local towerType = args[1]
            local position = Vector3.new(args[2], args[3], args[4])
            local rotation = args[5]
            local a1 = args[6] or ""
            
            -- Lấy giá từ BindableEvent (nếu cần)
            local costEvent = BindableHandler.GetEvent("GetTowerCost")
            local cost = costEvent and costEvent:Invoke(towerType) or 0
            
            appendfile(CONFIG.RECORD_FILE, string.format(
                "Place|%s|%d|%.17g,%.17g,%.17g|%.17g|%s\n",
                towerType,
                cost,
                position.X, position.Y, position.Z,
                rotation,
                a1
            ))
            
        elseif eventName == "TowerUpgradeRequest" and #args >= 2 then
            local towerHash = args[1]
            local path = args[2]
            local pos = self._towerPositions[tostring(towerHash)]
            
            if pos then
                appendfile(CONFIG.RECORD_FILE, string.format(
                    "Upgrade|%.17g|0|%d\n",
                    pos.X,
                    path
                ))
            end
            
        elseif eventName == "SellTower" and #args >= 1 then
            local towerHash = args[1]
            local pos = self._towerPositions[tostring(towerHash)]
            
            if pos then
                appendfile(CONFIG.RECORD_FILE, string.format(
                    "Sell|%.17g\n",
                    pos.X
                ))
            end
        end
    end,
    
    _StartTracking = function(self)
        task.spawn(function()
            while true do
                local towers = GetTowerClass().GetTowers()
                for hash, tower in pairs(towers) do
                    if tower and tower.Character then
                        local model = tower.Character:GetCharacterModel()
                        local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
                        if root then
                            self._towerPositions[tostring(hash)] = root.Position
                        end
                    end
                end
                task.wait(0.1)
            end
        end)
    end,
    
    ProcessToJson = function(self)
        while true do
            task.wait(1)
            if isfile(CONFIG.RECORD_FILE) then
                local content = readfile(CONFIG.RECORD_FILE)
                local actions = {}
                
                for line in content:gmatch("[^\r\n]+") do
                    local parts = {}
                    for part in line:gmatch("([^|]+)") do
                        table.insert(parts, part)
                    end
                    
                    local action = {}
                    if parts[1] == "Place" then
                        action.TowerPlaceCost = tonumber(parts[3])
                        action.TowerPlaced = parts[2]
                        action.TowerVector = parts[4]
                        action.Rotation = parts[5]
                        action.TowerA1 = parts[6] or ""
                        
                    elseif parts[1] == "Upgrade" then
                        action.TowerUpgraded = parts[2]
                        action.UpgradeCost = 0
                        action.UpgradePath = tonumber(parts[4])
                        
                    elseif parts[1] == "Sell" then
                        action.SellTower = parts[2]
                    end
                    
                    table.insert(actions, action)
                end
                
                if #actions > 0 then
                    writefile(CONFIG.OUTPUT_JSON, HttpService:JSONEncode(actions))
                    delfile(CONFIG.RECORD_FILE)
                end
            end
        end
    end
}

-- Khởi động hệ thống
if isfile(CONFIG.RECORD_FILE) then
    delfile(CONFIG.RECORD_FILE)
end
writefile(CONFIG.RECORD_FILE, "")

MacroRecorder:Init()
MacroRecorder:ProcessToJson()
