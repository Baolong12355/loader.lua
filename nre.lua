local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

-- Config
local CONFIG = {
    RECORD_FILE = "record.txt",
    OUTPUT_JSON = "x-1.json"
}

-- Initialize TowerClass
local TowerClass
do
    local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
    local Client = PlayerScripts:WaitForChild("Client")
    local GameClass = Client:WaitForChild("GameClass")
    TowerClass = require(GameClass:WaitForChild("TowerClass"))
end

-- Lấy giá tower từ UI (update theo cách hoạt động của game)
local function GetTowerCost(towerName)
    local interface = Players.LocalPlayer.PlayerGui:WaitForChild("Interface")
    local bottomBar = interface:WaitForChild("BottomBar")
    local towersBar = bottomBar:WaitForChild("TowersBar")
    
    for _, towerBtn in ipairs(towersBar:GetChildren()) do
        if towerBtn.Name == towerName then
            local costText = towerBtn.CostFrame.CostText.Text
            return tonumber(string.match(costText, "%d+")) or 0
        end
    end
    return 0
end

-- Main recorder
local function RecordActions()
    -- Clear old file
    if isfile(CONFIG.RECORD_FILE) then
        delfile(CONFIG.RECORD_FILE)
    end
    writefile(CONFIG.RECORD_FILE, "")
    
    -- Track tower positions
    local towerPositions = {}
    local function UpdateTowerPositions()
        while true do
            local towers = TowerClass.GetTowers()
            for hash, tower in pairs(towers) do
                if tower and tower.Character then
                    local model = tower.Character:GetCharacterModel()
                    if model then
                        local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
                        if root then
                            towerPositions[tostring(hash)] = root.Position
                        end
                    end
                end
            end
            task.wait(0.1)
        end
    end
    task.spawn(UpdateTowerPositions)
    
    -- Hook remote events
    local originalFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
        local args = {...}
        local eventName = self.Name
        
        if eventName == "PlaceTower" then
            local towerType = args[1]
            local pos = Vector3.new(args[2], args[3], args[4])
            local rotation = args[5]
            local a1 = args[6] or ""
            
            appendfile(CONFIG.RECORD_FILE, string.format(
                "Place|%s|%s|%.17g,%.17g,%.17g|%s|%s\n",
                towerType,
                GetTowerCost(towerType),
                pos.X, pos.Y, pos.Z,
                rotation,
                a1
            ))
            
        elseif eventName == "TowerUpgradeRequest" then
            local hash = args[1]
            local path = args[2]
            local pos = towerPositions[tostring(hash)]
            
            if pos then
                appendfile(CONFIG.RECORD_FILE, string.format(
                    "Upgrade|%.17g|0|%s\n",  -- UpgradeCost luôn 0 theo yêu cầu
                    pos.X,
                    path
                ))
            end
            
        elseif eventName == "SellTower" then
            local hash = args[1]
            local pos = towerPositions[tostring(hash)]
            
            if pos then
                appendfile(CONFIG.RECORD_FILE, string.format(
                    "Sell|%.17g\n",
                    pos.X
                ))
            end
        end
        
        return originalFireServer(self, ...)
    end)
    
    -- Process and convert to JSON
    while true do
        task.wait(1)
        if isfile(CONFIG.RECORD_FILE) then
            local actions = {}
            
            for line in readfile(CONFIG.RECORD_FILE):gmatch("[^\r\n]+") do
                local parts = {}
                for part in line:gmatch("([^|]+)") do
                    table.insert(parts, part)
                end
                
                local actionType = parts[1]
                local action = {}
                
                if actionType == "Place" then
                    action.TowerPlaceCost = tonumber(parts[2])
                    action.TowerPlaced = parts[3]
                    action.TowerVector = parts[4]
                    action.Rotation = parts[5]
                    action.TowerA1 = parts[6] or ""
                    
                elseif actionType == "Upgrade" then
                    action.TowerUpgraded = parts[2]
                    action.UpgradeCost = tonumber(parts[3])
                    action.UpgradePath = parts[4]
                    
                elseif actionType == "Sell" then
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

-- Start
RecordActions()
