-- Cấu hình file
local inputFile = "record.txt"
local outputFile = "tdx/macros/x.json"

-- Khởi tạo services
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer

-- 1. PHẦN GHI MACRO ==============================================
local macroStartTime = time()
local macroOffset = 0

-- Xóa file cũ nếu tồn tại
if isfile(inputFile) then
    delfile(inputFile)
end
writefile(inputFile, "-- TDX Macro Recording --\n")

-- Serialize dữ liệu
local function serialize(val)
    if type(val) == "string" then
        return string.format("%q", val)
    elseif type(val) == "table" then
        local parts = {}
        for k, v in pairs(val) do
            table.insert(parts, string.format("[%s]=%s", serialize(k), serialize(v)))
        end
        return "{" .. table.concat(parts, ",") .. "}"
    else
        return tostring(val)
    end
end

-- Ghi lệnh vào file
local function recordCommand(cmdName, ...)
    local args = {...}
    local serializedArgs = table.concat({serialize(v) for _, v in ipairs(args)}, ", ")
    local waitTime = time() - macroStartTime - macroOffset
    
    appendfile(inputFile, string.format(
        "task.wait(%.3f)\n%s(%s)\n",
        waitTime,
        cmdName,
        serializedArgs
    ))
    
    macroStartTime = time() - macroOffset
end

-- Hook RemoteEvents
local originalFireServer
originalFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
    local cmdName = self.Name
    if cmdName == "PlaceTower" then
        recordCommand("TDX:placeTower", ...)
    elseif cmdName == "SellTower" then
        recordCommand("TDX:sellTower", ...)
    elseif cmdName == "UpgradeTower" then
        recordCommand("TDX:upgradeTower", ...)
    elseif cmdName == "ChangeTarget" then
        recordCommand("TDX:changeQueryType", ...)
    end
    return originalFireServer(self, ...)
end)

print("🔴 Bắt đầu ghi macro TDX...")

-- 2. PHẦN CONVERT SANG JSON ======================================
local TowerClass
do
    local success, result = pcall(function()
        return require(player.PlayerScripts.Client.GameClass.TowerClass)
    end)
    TowerClass = success and result or nil
end

if not TowerClass then
    warn("Không thể load TowerClass - Chỉ có thể ghi macro cơ bản")
else
    print("✅ Đã load TowerClass - Sẵn sàng convert nâng cao")
    
    -- Hệ thống theo dõi tháp
    local towerData = {
        positions = {},
        levels = {}
    }
    
    -- Cập nhật vị trí tháp
    task.spawn(function()
        while true do
            local towers = TowerClass.GetTowers()
            if towers then
                for hash, tower in pairs(towers) do
                    local success, pos = pcall(function()
                        local model = tower.Character:GetCharacterModel()
                        local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
                        return root and root.Position
                    end)
                    if success and pos then
                        towerData.positions[tostring(hash)] = {
                            x = math.floor(pos.X * 100)/100,
                            y = math.floor(pos.Y * 100)/100,
                            z = math.floor(pos.Z * 100)/100
                        }
                    end
                end
            end
            task.wait(0.1)
        end
    end)
    
    -- Lấy giá tháp từ UI
    local function GetTowerCost(towerName)
        local gui = player:FindFirstChild("PlayerGui")
        if gui then
            local towerBtn = gui:FindFirstChild(towerName, true)
            if towerBtn then
                local costText = towerBtn:FindFirstChild("CostText", true)
                if costText then
                    return tonumber(costText.Text:match("%d+")) or 0
                end
            end
        end
        return 0
    end
    
    -- Convert tự động
    local function ConvertToJson()
        if not isfile(inputFile) then return end
        
        local logs = {}
        for line in readfile(inputFile):gmatch("[^\r\n]+") do
            -- Bỏ qua comment
            if not line:match("^%-%-") then
                -- Phát hiện lệnh place
                local placeArgs = {line:match('TDX:placeTower%(([^,]+),%s*"([^"]+)",%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)')}
                if #placeArgs >= 6 then
                    table.insert(logs, {
                        TowerPlaceCost = GetTowerCost(placeArgs[2]),
                        TowerPlaced = placeArgs[2],
                        TowerVector = table.concat({placeArgs[3], placeArgs[4], placeArgs[5]}, ", "),
                        Rotation = placeArgs[6],
                        TowerA1 = placeArgs[1]
                    })
                end
                
                -- Phát hiện lệnh upgrade
                local upgradeArgs = {line:match('TDX:upgradeTower%(([^,]+),%s*(%d)%)')}
                if #upgradeArgs >= 2 then
                    table.insert(logs, {
                        UpgradeCost = 0,
                        UpgradePath = tonumber(upgradeArgs[2]),
                        TowerUpgraded = towerData.positions[upgradeArgs[1]] and towerData.positions[upgradeArgs[1]].x or 0
                    })
                end
                
                -- Phát hiện lệnh sell
                local sellHash = line:match('TDX:sellTower%(([^%)]+)%)')
                if sellHash and towerData.positions[sellHash] then
                    table.insert(logs, {
                        SellTower = towerData.positions[sellHash].x
                    })
                end
                
                -- Phát hiện lệnh change target
                local targetArgs = {line:match('TDX:changeQueryType%(([^,]+),%s*(%d)%)')}
                if #targetArgs >= 2 then
                    table.insert(logs, {
                        ChangeTarget = towerData.positions[targetArgs[1]] and towerData.positions[targetArgs[1]].x or 0,
                        TargetType = tonumber(targetArgs[2])
                    })
                end
            end
        end
        
        -- Ghi file JSON
        if #logs > 0 then
            writefile(outputFile, HttpService:JSONEncode(logs))
            print("💾 Đã lưu", #logs, "lệnh vào", outputFile)
        end
    end
    
    -- Tự động convert mỗi 5 giây
    task.spawn(function()
        while true do
            ConvertToJson()
            task.wait(5)
        end
    end)
end

-- Hiển thị hướng dẫn
print([[
=======================================
  TDX MACRO RECORDER ĐÃ SẴN SÀNG
---------------------------------------
1. Mọi thao tác sẽ được ghi vào: record.txt
2. Dữ liệu JSON tự động lưu tại: tdx/macros/x.json
3. Nhấn F9 để xem console nếu cần
=======================================
]])
