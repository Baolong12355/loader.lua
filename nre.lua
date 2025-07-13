local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Cấu hình
local OUTPUT_JSON = "x-1.json"
local DELAY = 0.1 -- Độ trễ tối ưu cho TDX

-- Lấy TowerClass thẳng từ game (không qua require)
local TowerClass
for _, v in pairs(getgc(true)) do
    if type(v) == "table" and rawget(v, "GetTowers") then
        TowerClass = v
        break
    end
end

-- Dictionary lưu vị trí tower
local towerPositions = {}

-- Hàm chính
local function StartRecording()
    -- Khởi tạo file output
    writefile(OUTPUT_JSON, "[]")
    
    -- Bắt đầu theo dõi vị trí tower
    RunService.Heartbeat:Connect(function()
        for hash, tower in pairs(TowerClass.GetTowers()) do
            if tower and tower.Character then
                local root = tower.Character:GetCharacterModel().PrimaryPart
                if root then
                    towerPositions[tostring(hash)] = root.Position.X -- Chỉ lấy trục X
                end
            end
        end
    end)
    
    -- Hook RemoteEvent
    local originalFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
        local args = {...}
        local eventName = self.Name
        local currentActions = HttpService:JSONDecode(readfile(OUTPUT_JSON))
        local newAction = {}

        if eventName == "PlaceTower" and #args >= 5 then
            -- Lấy giá từ UI
            local cost = 0
            pcall(function()
                cost = tonumber(Players.LocalPlayer.PlayerGui.Interface.BottomBar.TowersBar[args[1]].CostFrame.CostText.Text:match("%d+")) or 0
            end)
            
            newAction = {
                TowerPlaceCost = cost,
                TowerPlaced = args[1],
                TowerVector = string.format("%.17g, %.17g, %.17g", args[2], args[3], args[4]),
                Rotation = args[5],
                TowerA1 = args[6] or ""
            }
            
        elseif eventName == "TowerUpgradeRequest" and #args >= 2 then
            local posX = towerPositions[tostring(args[1])]
            if posX then
                newAction = {
                    TowerUpgraded = posX,
                    UpgradeCost = 0,
                    UpgradePath = args[2]
                }
            end
            
        elseif eventName == "ChangeQueryType" and #args >= 2 then
            local posX = towerPositions[tostring(args[1])]
            if posX then
                newAction = {
                    ChangeTarget = posX,
                    TargetType = args[2]
                }
            end
            
        elseif eventName == "SellTower" and #args >= 1 then
            local posX = towerPositions[tostring(args[1])]
            if posX then
                newAction = {
                    SellTower = posX
                }
            end
        end

        -- Thêm action mới vào file
        if next(newAction) ~= nil then
            table.insert(currentActions, newAction)
            writefile(OUTPUT_JSON, HttpService:JSONEncode(currentActions))
        end

        return originalFireServer(self, ...)
    end)
end

-- Bắt đầu
StartRecording()
