local startTime = time()
local offset = 0
local fileName = "record.txt"

-- Xóa file cũ nếu có
if isfile(fileName) then
    delfile(fileName)
end
writefile(fileName, "")

-- Serialize giá trị
local function serialize(value)
    if type(value) == "table" then
        local result = "{"
        for k, v in pairs(value) do
            result ..= "[" .. serialize(k) .. "]=" .. serialize(v) .. ", "
        end
        if result ~= "{" then
            result = result:sub(1, -3)
        end
        return result .. "}"
    else
        return tostring(value)
    end
end

-- Serialize toàn bộ argument
local function serializeArgs(...)
    local args = {...}
    local output = {}
    for i, v in ipairs(args) do
        output[i] = serialize(v)
    end
    return table.concat(output, ", ")
end

-- Ghi log vào file
local function log(method, self, serializedArgs)
    local name = tostring(self.Name)

    if name == "PlaceTower" then
        appendfile(fileName, "task.wait(" .. ((time() - offset) - startTime) .. ")\n")
        appendfile(fileName, "TDX:placeTower(" .. serializedArgs .. ")\n")
        startTime = time() - offset

    elseif name == "SellTower" then
        appendfile(fileName, "task.wait(" .. ((time() - offset) - startTime) .. ")\n")
        appendfile(fileName, "TDX:sellTower(" .. serializedArgs .. ")\n")
        startTime = time() - offset

    elseif name == "TowerUpgradeRequest" then
        appendfile(fileName, "task.wait(" .. ((time() - offset) - startTime) .. ")\n")
        appendfile(fileName, "TDX:upgradeTower(" .. serializedArgs .. ")\n")
        startTime = time() - offset

    elseif name == "ChangeQueryType" then
        appendfile(fileName, "task.wait(" .. ((time() - offset) - startTime) .. ")\n")
        appendfile(fileName, "TDX:changeQueryType(" .. serializedArgs .. ")\n")
        startTime = time() - offset
    end
end

-- Hook FireServer
local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
    local args = serializeArgs(...)
    log("FireServer", self, args)
    return oldFireServer(self, ...)
end)

-- Hook InvokeServer
local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
    local args = serializeArgs(...)
    log("InvokeServer", self, args)
    return oldInvokeServer(self, ...)
end)

-- Hook __namecall
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    if method == "FireServer" or method == "InvokeServer" then
        local args = serializeArgs(...)
        log(method, self, args)
    end
    return oldNamecall(self, ...)
end)

print("✅ Ghi macro TDX đã bắt đầu (luôn dùng tên record.txt).")

-- Script chuyển đổi record.txt thành macro runner (dùng trục X), với thứ tự trường upgrade là: UpgradeCost, UpgradePath, TowerUpgraded
-- Đặt script này trong môi trường Roblox hoặc môi trường hỗ trợ các API Roblox tương ứng

local txtFile = "record.txt"
local outJson = "tdx/macros/x.json"

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local HttpService = game:GetService("HttpService")
local PlayerScripts = player:WaitForChild("PlayerScripts")

-- Safe require tower module
local function SafeRequire(module)
    local success, result = pcall(require, module)
    return success and result or nil
end

local TowerClass
do
    local client = PlayerScripts:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    TowerClass = SafeRequire(towerModule)
end

local function GetTowerPosition(tower)
    if not tower or not tower.Character then return nil end
    local model = tower.Character:GetCharacterModel()
    local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
    return root and root.Position or nil
end

local function GetTowerPlaceCostByName(name)
    local playerGui = player:FindFirstChild("PlayerGui")
    if not playerGui then return 0 end
    local interface = playerGui:FindFirstChild("Interface")
    if not interface then return 0 end
    local bottomBar = interface:FindFirstChild("BottomBar")
    if not bottomBar then return 0 end
    local towersBar = bottomBar:FindFirstChild("TowersBar")
    if not towersBar then return 0 end
    for _, tower in ipairs(towersBar:GetChildren()) do
        if tower.Name == name then
            local costFrame = tower:FindFirstChild("CostFrame")
            local costText = costFrame and costFrame:FindFirstChild("CostText")
            if costText then
                local raw = tostring(costText.Text):gsub("%D", "")
                return tonumber(raw) or 0
            end
        end
    end
    return 0
end

local function ParseUpgradeCost(costStr)
    local num = tostring(costStr):gsub("[^%d]", "")
    return tonumber(num) or 0
end

local function GetUpgradeCost(tower, path)
    if not tower or not tower.LevelHandler then return 0 end
    local lvl = tower.LevelHandler:GetLevelOnPath(path)
    local ok, cost = pcall(function()
        return tower.LevelHandler:GetLevelUpgradeCost(path, lvl+1)
local txtFile = "record.txt"
local outJson = "tdx/macros/x.json"
local DELAY = 0.05  -- Ultra-fast processing

-- Services
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")

-- Initialize TowerClass
local TowerClass
do
    local client = PlayerScripts:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    local success, result = pcall(require, towerModule)
    TowerClass = success and result or nil
end

-- Tracking and Utility Functions
local hash2pos = {}

local function TrackTowerPositions()
    while true do
        if TowerClass then
            for hash, tower in pairs(TowerClass.GetTowers()) do
                if tower and tower.Character then
                    local model = tower.Character:GetCharacterModel()
                    local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
                    if root then
                        hash2pos[tostring(hash)] = {x = root.Position.X, y = root.Position.Y, z = root.Position.Z}
                    end
                end
            end
        end
        task.wait(0.1)
    end
end

task.spawn(TrackTowerPositions)

-- Processing Functions with Verification
local function ProcessPlace(a1, name, x, y, z, rot)
    local cost = 0
    pcall(function()
        local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
        if playerGui then
            local towerBtn = playerGui:FindFirstChild("Interface/BottomBar/TowersBar/"..name)
            if towerBtn then
                local costText = towerBtn:FindFirstChild("CostFrame/CostText") or towerBtn:FindFirstChild("CostFrame/OrderText")
                if costText then
                    cost = tonumber(costText.Text:match("%d+")) or 0
                end
            end
        end
    end)
    
    print(string.format("🏗️ Placed | %-15s | Cost: $%-5d | Pos: %s,%s,%s | Rot: %s",
        name, cost, x, y, z, rot))
    
    return {
        TowerPlaceCost = cost,
        TowerPlaced = name,
        TowerVector = x..","..y..","..z,
        Rotation = rot,
        TowerA1 = tostring(a1)
    }
end

local function ProcessUpgrade(hash, path)
    local pos = hash2pos[tostring(hash)]
    if not pos then return nil end
    
    local tower = TowerClass and TowerClass.GetTower(hash)
    if not tower then return nil end
    
    local initialLevel = tower.LevelHandler:GetLevelOnPath(path)
    task.wait(DELAY) -- Wait for game processing
    
    local newLevel = tower.LevelHandler:GetLevelOnPath(path)
    local success = newLevel > initialLevel
    local cost = GetUpgradeCost(tower, path)
    
    print(string.format("%s Upgrade | %-15s | Path: %d | %s | Cost: $%d",
        success and "✅" or "❌",
        hash:sub(1, 15),
        path,
        success and string.format("Success (Lv.%d→Lv.%d)", initialLevel, newLevel) 
               or string.format("Failed (Lv.%d)", initialLevel),
        cost
    ))
    
    return {
        UpgradeCost = cost,
        UpgradePath = path,
        TowerUpgraded = pos.x,
        _success = success
    }
end

local function ProcessTargetChange(hash, targetType)
    local pos = hash2pos[tostring(hash)]
    if pos then
        print(string.format("🎯 Target Change | %-15s | Type: %d | Pos: %.1f",
            hash:sub(1, 15), targetType, pos.x))
        return {
            ChangeTarget = pos.x,
            TargetType = targetType
        }
    end
    return nil
end

local function ProcessSell(hash)
    local pos = hash2pos[tostring(hash)]
    if pos then
        print(string.format("💵 Sold | %-15s | Pos: %.1f", hash:sub(1, 15), pos.x))
        return {
            SellTower = pos.x
        }
    end
    return nil
end

-- Main Processing Loop
while true do
    if isfile(txtFile) then
        local macro = readfile(txtFile)
        local logs = {}
        local stats = {
            place = 0,
            upgrade = {total = 0, success = 0},
            target = 0,
            sell = 0
        }

        for line in macro:gmatch("[^\r\n]+") do
            -- Place Tower
            local placeData = {line:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),?%s*([^%)]*)%)')}
            if #placeData >= 5 then
                local record = ProcessPlace(
                    placeData[1], -- a1
                    placeData[2]:gsub('["\']', ''), -- name
                    placeData[3], -- x
                    placeData[4], -- y
                    placeData[5], -- z
                    placeData[6] or "0" -- rot
                )
                if record then
                    table.insert(logs, record)
                    stats.place = stats.place + 1
                end
            else
                -- Upgrade Tower
                local upgradeData = {line:match('TDX:upgradeTower%(([^,]+),%s*([^,]+)')}
                if #upgradeData >= 2 then
                    local record = ProcessUpgrade(upgradeData[1], tonumber(upgradeData[2]))
                    if record then
                        table.insert(logs, record)
                        stats.upgrade.total = stats.upgrade.total + 1
                        if record._success then
                            stats.upgrade.success = stats.upgrade.success + 1
                        end
                    end
                else
                    -- Target Change
                    local targetData = {line:match('TDX:changeQueryType%(([^,]+),%s*([^,]+)')}
                    if #targetData >= 2 then
                        local record = ProcessTargetChange(targetData[1], tonumber(targetData[2]))
                        if record then
                            table.insert(logs, record)
                            stats.target = stats.target + 1
                        end
                    else
                        -- Sell Tower
                        local sellData = {line:match('TDX:sellTower%(([^%)]+)')}
                        if #sellData >= 1 then
                            local record = ProcessSell(sellData[1])
                            if record then
                                table.insert(logs, record)
                                stats.sell = stats.sell + 1
                            end
                        end
                    end
                end
            end
        end

        -- Print summary
        print("\n📊 Macro Processing Complete:")
        print(string.format("• Placed: %d towers", stats.place))
        print(string.format("• Upgrades: %d/%d successful (%.1f%%)", 
            stats.upgrade.success, stats.upgrade.total,
            stats.upgrade.total > 0 and (stats.upgrade.success/stats.upgrade.total)*100 or 0))
        print(string.format("• Target Changes: %d", stats.target))
        print(string.format("• Sold: %d towers", stats.sell))

        writefile(outJson, HttpService:JSONEncode(logs))
        delfile(txtFile)
    end
    task.wait(DELAY)
end
