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

local txtFile = "record.txt"
local outJson = "tdx/macros/x.json"

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local HttpService = game:GetService("HttpService")
local PlayerScripts = player:WaitForChild("PlayerScripts")
local Workspace = game:GetService("Workspace")

-- Debug settings
local DEBUG_MODE = true
local function DebugPrint(...)
    if DEBUG_MODE then
        print("[DEBUG]", ...)
    end
end

-- Safe require tower module
local function SafeRequire(module)
    local ok, result = pcall(require, module)
    if not ok then
        DebugPrint("Require failed for:", module:GetFullName(), "Error:", result)
    end
    return ok and result or nil
end

-- Load TowerClass with extensive debugging
local TowerClass
do
    DebugPrint("⏳ Đang tìm TowerClass...")
    local client = PlayerScripts:FindFirstChild("Client")
    DebugPrint("Client found:", client ~= nil)
    
    local gameClass = client and client:FindFirstChild("GameClass")
    DebugPrint("GameClass found:", gameClass ~= nil)
    
    local towerModule = gameClass and gameClass:FindFirstChild("TowerClass") or gameClass and gameClass:FindFirstChild("TowerModule")
    DebugPrint("Tower module found:", towerModule ~= nil, towerModule and towerModule:GetFullName() or "N/A")
    
    TowerClass = towerModule and SafeRequire(towerModule)
    DebugPrint("TowerClass loaded:", TowerClass ~= nil)
    
    if TowerClass and DEBUG_MODE then
        DebugPrint("TowerClass methods:")
        for k,v in pairs(getmetatable(TowerClass).__index) do
            if type(v) == "function" then
                DebugPrint("Method:", k)
            end
        end
    end
end

if not TowerClass then
    warn("❌ Critical Error: Không thể load TowerClass")
    return
end

-- Enhanced GetPathLevel with debug
local function GetPathLevel(tower, path)
    if not tower then
        DebugPrint("GetPathLevel: tower is nil")
        return nil
    end
    
    if not tower.LevelHandler then
        DebugPrint("GetPathLevel: LevelHandler is nil for tower", tower.Type or "unknown")
        return nil
    end
    
    local ok, result = pcall(function()
        -- Thử nhiều tên hàm khác nhau
        return tower.LevelHandler:GetPathLevel(path)
            or tower.LevelHandler:GetLevelOnPath(path)
            or tower.LevelHandler:GetLevel(path)
    end)
    
    if not ok then
        DebugPrint("GetPathLevel failed for path", path, "Error:", result)
        return nil
    end
    
    DebugPrint("GetPathLevel success:", tower.Type or "unknown", "path", path, "=", result)
    return result
end

-- Cache system with version tracking
local upgradeCache = {}
local cacheVersion = 0

local function CacheCurrentLevels()
    cacheVersion = cacheVersion + 1
    DebugPrint("🔁 Cập nhật cache (version", cacheVersion, ")")
    
    local towers = TowerClass.GetTowers()
    if not towers then
        DebugPrint("CacheCurrentLevels: GetTowers() returned nil")
        return
    end
    
    DebugPrint("Tổng số tháp:", #towers)
    
    for hash, tower in pairs(towers) do
        local h = tostring(hash)
        upgradeCache[h] = upgradeCache[h] or {}
        upgradeCache[h].version = cacheVersion
        
        for path = 1, 2 do
            local lvl = GetPathLevel(tower, path)
            if lvl ~= nil then
                upgradeCache[h][path] = lvl
                DebugPrint("Cached level:", h, "path", path, "=", lvl)
            else
                DebugPrint("Failed to get level for:", h, "path", path)
            end
        end
    end
end

-- Enhanced upgrade detection
local function IsUpgradeSuccess(hash, path)
    local h = tostring(hash)
    if not upgradeCache[h] then
        DebugPrint("IsUpgradeSuccess: No cache for hash", h)
        return false
    end
    
    if upgradeCache[h].version ~= cacheVersion then
        DebugPrint("IsUpgradeSuccess: Stale cache for hash", h)
        return false
    end
    
    local tower = TowerClass.GetTowers()[hash]
    if not tower then
        DebugPrint("IsUpgradeSuccess: Tower not found for hash", h)
        return false
    end
    
    local cur = GetPathLevel(tower, path)
    local old = upgradeCache[h][path]
    
    if old == nil or cur == nil then
        DebugPrint("IsUpgradeSuccess: Nil levels for", h, "path", path, "old:", old, "cur:", cur)
        return false
    end
    
    if cur > old then
        DebugPrint("🔥 Upgrade detected!", h, "path", path, old, "→", cur)
        upgradeCache[h][path] = cur
        return true
    end
    
    DebugPrint("No upgrade for", h, "path", path, "still at", cur)
    return false
end

-- Position tracking with validation
local hash2pos = {}
local positionUpdateCount = 0

task.spawn(function()
    while true do
        positionUpdateCount = positionUpdateCount + 1
        local towers = TowerClass.GetTowers()
        if not towers then
            DebugPrint("Position tracker: GetTowers() returned nil")
        else
            for hash, tower in pairs(towers) do
                local h = tostring(hash)
                if tower.Character then
                    local ok, pos = pcall(function()
                        local model = tower.Character:GetCharacterModel()
                        local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
                        return root and root.Position
                    end)
                    
                    if ok and pos then
                        hash2pos[h] = {
                            x = math.floor(pos.X * 100)/100,
                            y = math.floor(pos.Y * 100)/100,
                            z = math.floor(pos.Z * 100)/100,
                            updated = positionUpdateCount
                        }
                    else
                        DebugPrint("Position error for", h, ":", pos)
                    end
                end
            end
        end
        task.wait(0.1)
    end
end)

-- Enhanced cost detection
local function GetTowerPlaceCostByName(name)
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then
        DebugPrint("PlayerGui not found")
        return 0
    end
    
    local interface = gui:FindFirstChild("Interface")
    if not interface then
        DebugPrint("Interface not found")
        return 0
    end
    
    local bottomBar = interface:FindFirstChild("BottomBar")
    if not bottomBar then
        DebugPrint("BottomBar not found")
        return 0
    end
    
    local towersBar = bottomBar:FindFirstChild("TowersBar")
    if not towersBar then
        DebugPrint("TowersBar not found")
        return 0
    end
    
    for _, tower in ipairs(towersBar:GetChildren()) do
        if tower.Name == name then
            local costFrame = tower:FindFirstChild("CostFrame")
            if costFrame then
                local text = costFrame:FindFirstChild("CostText")
                if text then
                    local raw = text.Text:match("%d+")
                    local cost = tonumber(raw) or 0
                    DebugPrint("Cost for", name, "=", cost)
                    return cost
                end
            end
        end
    end
    
    DebugPrint("Cost not found for tower:", name)
    return 0
end

-- File system setup
if makefolder then
    pcall(function() makefolder("tdx") end)
    pcall(function() makefolder("tdx/macros") end)
end

-- Main conversion loop
DebugPrint("✅ Bắt đầu convert record.txt → x.json...")

while true do
    if isfile(txtFile) then
        DebugPrint("--- Bắt đầu xử lý file mới ---")
        local macro = readfile(txtFile)
        local logs = {}
        
        -- Initial cache update
        CacheCurrentLevels()
        DebugPrint("Cache version:", cacheVersion)
        
        -- Process each line
        for lineNum, line in ipairs(macro:split("\n")) do
            DebugPrint("\nProcessing line", lineNum, ":", line)
            
            -- PLACE command
            local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*"([^"]+)",%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)')
            if a1 and name and x and y and z and rot then
                DebugPrint("📌 Phát hiện lệnh PLACE:", name)
                local cost = GetTowerPlaceCostByName(name)
                local vector = string.format("%.2f, %.2f, %.2f", tonumber(x), tonumber(y), tonumber(z))
                
                table.insert(logs, {
                    action = "place",
                    TowerPlaceCost = cost,
                    TowerPlaced = name,
                    TowerVector = vector,
                    Rotation = tonumber(rot),
                    TowerA1 = tostring(a1),
                    timestamp = os.time()
                })
                
                DebugPrint("✅ Đã log place:", name, "at", vector)
            else
                -- UPGRADE command
                local hash, path = line:match('TDX:upgradeTower%(([^,]+),%s*(%d)%)')
                if hash and path then
                    DebugPrint("🔧 Phát hiện lệnh UPGRADE:", hash, "path", path)
                    path = tonumber(path)
                    
                    -- Pre-upgrade check
                    CacheCurrentLevels()
                    local oldLevel = GetPathLevel(TowerClass.GetTowers()[hash], path)
                    DebugPrint("Pre-upgrade level:", oldLevel)
                    
                    -- Post-upgrade check with delay
                    task.wait(0.15)
                    CacheCurrentLevels()
                    
                    local tower = TowerClass.GetTowers()[hash]
                    if not tower then
                        DebugPrint("❌ Tower not found after upgrade attempt")
                    else
                        local newLevel = GetPathLevel(tower, path)
                        DebugPrint("Post-upgrade level:", newLevel)
                        
                        local pos = hash2pos[tostring(hash)]
                        if pos then
                            if newLevel and oldLevel and newLevel > oldLevel then
                                table.insert(logs, {
                                    action = "upgrade",
                                    UpgradeCost = 0,
                                    UpgradePath = path,
                                    TowerUpgraded = pos.x,
                                    OldLevel = oldLevel,
                                    NewLevel = newLevel,
                                    Position = pos,
                                    timestamp = os.time()
                                })
                                DebugPrint("✅ Đã log upgrade:", hash, "path", path, oldLevel, "→", newLevel)
                            else
                                DebugPrint("⚠️ Không phát hiện nâng cấp", hash, "path", path, "level:", oldLevel, "→", newLevel)
                            end
                        else
                            DebugPrint("❌ Không tìm thấy vị trí cho hash", hash)
                        end
                    end
                else
                    -- Other commands (sell, change target, etc.)
                    DebugPrint("⚙️ Xử lý lệnh khác:", line)
                end
            end
        end
        
        -- Save to JSON
        if #logs > 0 then
            local json = HttpService:JSONEncode(logs)
            writefile(outJson, json)
            DebugPrint("💾 Đã ghi", #logs, "records vào", outJson)
        else
            DebugPrint("⚠️ Không có dữ liệu để ghi")
        end
    else
        DebugPrint("⌛ Đang chờ file input...")
    end
    
    task.wait(0.5)
end
