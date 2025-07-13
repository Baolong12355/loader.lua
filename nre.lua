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

-- TDX Macro Recorder v2.5 (Universal Executor Version)
local txtFile = "tdx_records.txt"
local outJson = "tdx/macros/x.json"
local DELAY = 0.05 -- Ultra-fast 50ms processing

-- Universal service getter with fallback
local function GetService(serviceName)
    return pcall(function() 
        return game:GetService(serviceName) or game[serviceName]
    end)
end

-- Initialize essential services
local success, Players = GetService("Players")
local _, HttpService = GetService("HttpService")
if not success then error("Failed to get Players service") end

-- Debug mode for executors (enable for detailed logging)
local DEBUG_MODE = true

-- Enhanced directory creator
local function CreateDir(path)
    if not makefolder then return false end
    local parts = {}
    for part in path:gmatch("[^/]+") do
        table.insert(parts, part)
        local current = table.concat(parts, "/")
        if not isfolder(current) then
            local ok, _ = pcall(makefolder, current)
            if not ok and DEBUG_MODE then
                warn("Failed to create dir:", current)
            end
        end
    end
    return true
end

-- Safe require with executor detection
local function SafeRequire(module)
    local executorType = (identifyexecutor or getexecutorname or function() return "Unknown" end)()
    local isSynapse = string.find(tostring(executorType):lower(), "synapse") ~= nil

    -- Special handling for different executors
    if isSynapse then
        return pcall(require, module)
    elseif getrequired then
        return pcall(getrequired, module)
    elseif require then
        return pcall(require, module)
    else
        return false, "No require function available"
    end
end

-- Load game modules
local TowerClass
do
    local player = Players.LocalPlayer
    if player then
        local PlayerScripts = player:FindFirstChild("PlayerScripts")
        if PlayerScripts then
            local client = PlayerScripts:FindFirstChild("Client")
            if client then
                local gameClass = client:FindFirstChild("GameClass")
                if gameClass then
                    local towerModule = gameClass:FindFirstChild("TowerClass")
                    if towerModule then
                        local success, result = SafeRequire(towerModule)
                        if success then
                            TowerClass = result
                            if DEBUG_MODE then
                                print("✅ Successfully loaded TowerClass")
                            end
                        elseif DEBUG_MODE then
                            warn("Failed to require TowerClass:", result)
                        end
                    end
                end
            end
        end
    end
end

-- Tower position tracker (optimized)
local towerPositions = {}
local function TrackTowers()
    while true do
        if TowerClass and TowerClass.GetTowers then
            for hash, tower in pairs(TowerClass.GetTowers()) do
                if tower and tower.Character then
                    local model = tower.Character:GetCharacterModel()
                    local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
                    if root then
                        towerPositions[tostring(hash)] = {
                            x = root.Position.X,
                            y = root.Position.Y,
                            z = root.Position.Z
                        }
                    end
                end
            end
        end
        task.wait(0.1) -- Position update interval
    end
end
task.spawn(TrackTowers)

-- Cost utilities
local function ParseCost(text)
    if not text then return 0 end
    local num = tostring(text):gsub("%D", "")
    return tonumber(num) or 0
end

local function GetTowerCost(name)
    local interface = Players.LocalPlayer.PlayerGui:FindFirstChild("Interface")
    if not interface then return 0 end
    
    local towerBtn = interface:FindFirstChild("BottomBar/TowersBar/"..name, true)
    if not towerBtn then return 0 end
    
    local costFrame = towerBtn:FindFirstChild("CostFrame")
    if not costFrame then return 0 end
    
    local costText = costFrame:FindFirstChildWhichIsA("TextLabel", true)
    return ParseCost(costText and costText.Text)
end

-- Processing functions
local function ProcessPlace(a1, name, x, y, z, rot)
    rot = rot or "0"
    local cost = GetTowerCost(name:gsub('"', ''))
    
    if DEBUG_MODE then
        print(string.format(
            "🏗️ Place | %-12s | $%-4d | Pos: %8s,%-8s,%-8s | Rot: %-4s",
            name, cost, x, y, z, rot
        ))
    end
    
    return {
        TowerPlaceCost = cost,
        TowerPlaced = name:gsub('"', ''),
        TowerVector = string.format("%s,%s,%s", x, y, z),
        Rotation = rot,
        TowerA1 = tostring(a1)
    }
end

local function ProcessUpgrade(hash, path)
    local pos = towerPositions[hash]
    if not pos then return nil end
    
    local tower = TowerClass and TowerClass.GetTower(tonumber(hash) or hash)
    if not tower then return nil end
    
    local initialLevel = tower.LevelHandler:GetLevelOnPath(path)
    task.wait(DELAY) -- Let game process
    
    local newLevel = tower.LevelHandler:GetLevelOnPath(path)
    local success = newLevel > initialLevel
    local cost = 0 -- Default as requested
    
    if DEBUG_MODE then
        print(string.format(
            "%s Upgrade | %-12s | Path: %d | %s",
            success and "✅" or "❌", 
            hash:sub(1, 12),
            path,
            success and string.format("Lv.%d→Lv.%d", initialLevel, newLevel) 
                   or string.format("Stuck at Lv.%d", initialLevel)
        ))
    end
    
    return {
        UpgradeCost = cost,
        UpgradePath = path,
        TowerUpgraded = pos.x,
        _success = success
    }
end

local function ProcessTarget(hash, targetType)
    local pos = towerPositions[hash]
    if not pos then return nil end

    if DEBUG_MODE then
        print(string.format(
            "🎯 Target | %-12s | Type: %d | Pos: %.1f",
            hash:sub(1, 12), targetType, pos.x
        ))
    end
    
    return {
        ChangeTarget = pos.x,
        TargetType = targetType
    }
end

local function ProcessSell(hash)
    local pos = towerPositions[hash]
    if not pos then return nil end
    
    if DEBUG_MODE then
        print(string.format("💵 Sold | %-12s | Pos: %.1f", hash:sub(1, 12), pos.x))
    end
    
    return {
        SellTower = pos.x
    }
end

-- Main processing loop
CreateDir("tdx/macros")

while true do
    if not isfile(txtFile) then
        task.wait(DELAY)
        continue
    end

    local content = readfile(txtFile)
    local records = {}
    local stats = {
        place = 0,
        upgrade = { total = 0, success = 0 },
        target = 0,
        sell = 0
    }

    -- Process each line
    for line in content:gmatch("[^\r\n]+") do
        -- Place Tower
        local placeArgs = { line:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),?%s*([^%)]*)%)') }
        if #placeArgs >= 5 then
            local record = ProcessPlace(
                placeArgs[1], placeArgs[2], 
                placeArgs[3], placeArgs[4], 
                placeArgs[5], placeArgs[6]
            )
            if record then
                table.insert(records, record)
                stats.place = stats.place + 1
            end
        else
            -- Upgrade Tower
            local upgradeArgs = { line:match('TDX:upgradeTower%(([^,]+),%s*([^,]+)') }
            if #upgradeArgs >= 2 then
                local record = ProcessUpgrade(upgradeArgs[1], tonumber(upgradeArgs[2]))
                if record then
                    table.insert(records, record)
                    stats.upgrade.total = stats.upgrade.total + 1
                    if record._success then
                        stats.upgrade.success = stats.upgrade.success + 1
                    end
                end
            else
                -- Change Target
                local targetArgs = { line:match('TDX:changeQueryType%(([^,]+),%s*([^,]+)') }
                if #targetArgs >= 2 then
                    local record = ProcessTarget(targetArgs[1], tonumber(targetArgs[2]))
                    if record then
                        table.insert(records, record)
                        stats.target = stats.target + 1
                    end
                else
                    -- Sell Tower
                    local sellArgs = { line:match('TDX:sellTower%(([^%)]+)') }
                    if #sellArgs >= 1 then
                        local record = ProcessSell(sellArgs[1])
                        if record then
                            table.insert(records, record)
                            stats.sell = stats.sell + 1
                        end
                    end
                end
            end
        end
    end

    -- Save output
    if #records > 0 then
        writefile(outJson, HttpService:JSONEncode(records))
    end
    delfile(txtFile)

    -- Print summary
    if DEBUG_MODE then
        print("\n📊 Session Summary:")
        print(string.format("Placed: %d towers", stats.place))
        print(string.format("Upgrades: %d/%d successful", stats.upgrade.success, stats.upgrade.total))
        print(string.format("Target Changes: %d", stats.target))
        print(string.format("Sold: %d towers\n", stats.sell))
    end

    task.wait(DELAY)
end

print("✅ TDX Macro Recorder is running! Press F9 to see debug output")
