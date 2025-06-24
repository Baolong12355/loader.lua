-- Macro TXT: record.txt (chỉ ghi thao tác cũ)
local startTime = time()
local offset = 0
local macroFile = "record.txt"
if not isfile(macroFile) then writefile(macroFile, "") end

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
local function serializeArgs(...)
    local args = {...}
    local output = {}
    for i, v in ipairs(args) do
        output[i] = serialize(v)
    end
    return table.concat(output, ", ")
end

local oldFireServer, oldInvokeServer, oldNamecall

local function macro_log(method, self, serializedArgs, ...)
    local name = tostring(self.Name)
    if name == "PlaceTower" then
        appendfile(macroFile, "task.wait(" .. tostring((time() - offset) - startTime) .. ")\n")
        appendfile(macroFile, "TDX:placeTower(" .. serializedArgs .. ")\n")
        startTime = time() - offset
    elseif name == "SellTower" then
        appendfile(macroFile, "task.wait(" .. tostring((time() - offset) - startTime) .. ")\n")
        appendfile(macroFile, "TDX:sellTower(" .. serializedArgs .. ")\n")
        startTime = time() - offset
    elseif name == "TowerUpgradeRequest" then
        appendfile(macroFile, "task.wait(" .. tostring((time() - offset) - startTime) .. ")\n")
        appendfile(macroFile, "TDX:upgradeTower(" .. serializedArgs .. ")\n")
        startTime = time() - offset
    elseif name == "ChangeQueryType" then
        appendfile(macroFile, "task.wait(" .. tostring((time() - offset) - startTime) .. ")\n")
        appendfile(macroFile, "TDX:changeQueryType(" .. serializedArgs .. ")\n")
        startTime = time() - offset
    end
end

-- Macro TXT hook
oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
    macro_log("FireServer", self, serializeArgs(...), ...)
    return oldFireServer(self, ...)
end)
oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
    macro_log("InvokeServer", self, serializeArgs(...), ...)
    return oldInvokeServer(self, ...)
end)
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    if method == "FireServer" or method == "InvokeServer" then
        macro_log(method, self, serializeArgs(...), ...)
    end
    return oldNamecall(self, ...)
end)

print("✅ Macro TXT ghi riêng ở record.txt")

--------------------------------------------------------------------------------
-- JSON LOG: record.json (chỉ ghi định dạng mới, KHÔNG liên quan gì tới TXT)
local jsonData = {}
local towerPriceTable = {}      -- towerName -> price
local towerUpgradeTable = {}    -- towerX -> { [path]=cost }
local hashToVector = {}         -- towerX -> vector string

local function vector3ToString(vec)
    if typeof(vec) == "Vector3" then
        return string.format("%.8f, %.8f, %.8f", vec.X, vec.Y, vec.Z)
    elseif type(vec) == "table" and vec.X and vec.Y and vec.Z then
        return string.format("%.8f, %.8f, %.8f", vec.X, vec.Y, vec.Z)
    end
    return tostring(vec)
end
local function getXFromVector(vec)
    if typeof(vec) == "Vector3" then return vec.X
    elseif type(vec) == "table" and vec.X then return vec.X
    elseif type(vec) == "number" then return vec
    elseif type(vec) == "string" then
        local x = tonumber((vec):match("^[^,]+"))
        return x
    end
    return nil
end

local function saveJson()
    local encoded = game:GetService("HttpService"):JSONEncode(jsonData)
    writefile("record.json", encoded)
end

function SetTowerPlaceCost(towerName, cost) towerPriceTable[towerName] = cost end
function SetTowerUpgradeCost(towerX, path, cost)
    towerUpgradeTable[towerX] = towerUpgradeTable[towerX] or {}
    towerUpgradeTable[towerX][path] = cost
end

local function logJsonPlaceTower(towerName, vec, rotation, towerA1)
    local cost = towerPriceTable[towerName] or 0
    local vectorStr = vector3ToString(vec)
    local x = getXFromVector(vec)
    if x then hashToVector[x] = vectorStr end
    local entry = {
        TowerPlaceCost = cost,
        TowerPlaced = towerName,
        TowerVector = vectorStr,
        Rotation = rotation or 0,
        TowerA1 = tostring(towerA1 or tick())
    }
    table.insert(jsonData, entry)
    saveJson()
end
local function logJsonUpgrade(towerX, upgradePath)
    local cost = (towerUpgradeTable[towerX] and towerUpgradeTable[towerX][upgradePath]) or 0
    local entry = {
        UpgradeCost = cost,
        UpgradePath = upgradePath,
        TowerUpgraded = towerX
    }
    table.insert(jsonData, entry)
    saveJson()
end
local function logJsonTargetChange(at, wanted, changedAt)
    local entry = {
        TowerTargetChange = at,
        TargetWanted = wanted,
        TargetChangedAt = changedAt
    }
    table.insert(jsonData, entry)
    saveJson()
end

-- JSON log HOOK riêng biệt
local oldFireServer_JSON, oldInvokeServer_JSON, oldNamecall_JSON
oldFireServer_JSON = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
    local name = tostring(self.Name)
    if name == "PlaceTower" then
        local args = {...}
        logJsonPlaceTower(args[1], args[2], args[3], tick())
    elseif name == "TowerUpgradeRequest" then
        local args = {...}
        local towerHash = args[1]
        local upgradePath = tonumber(args[2])
        local x = getXFromVector(towerHash)
        logJsonUpgrade(x, upgradePath)
    elseif name == "TowerTargetChange" then
        local args = {...}
        logJsonTargetChange(args[1], args[2], args[3])
    end
    return oldFireServer_JSON(self, ...)
end)
oldInvokeServer_JSON = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
    local name = tostring(self.Name)
    if name == "PlaceTower" then
        local args = {...}
        logJsonPlaceTower(args[1], args[2], args[3], tick())
    elseif name == "TowerUpgradeRequest" then
        local args = {...}
        local towerHash = args[1]
        local upgradePath = tonumber(args[2])
        local x = getXFromVector(towerHash)
        logJsonUpgrade(x, upgradePath)
    elseif name == "TowerTargetChange" then
        local args = {...}
        logJsonTargetChange(args[1], args[2], args[3])
    end
    return oldInvokeServer_JSON(self, ...)
end)
oldNamecall_JSON = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    if method == "FireServer" or method == "InvokeServer" then
        local name = tostring(self.Name)
        if name == "PlaceTower" then
            local args = {...}
            logJsonPlaceTower(args[1], args[2], args[3], tick())
        elseif name == "TowerUpgradeRequest" then
            local args = {...}
            local towerHash = args[1]
            local upgradePath = tonumber(args[2])
            local x = getXFromVector(towerHash)
            logJsonUpgrade(x, upgradePath)
        elseif name == "TowerTargetChange" then
            local args = {...}
            logJsonTargetChange(args[1], args[2], args[3])
        end
    end
    return oldNamecall_JSON(self, ...)
end)

print("✅ JSON log chạy riêng ở record.json (format mới, độc lập với macro txt)")

-- Gọi SetTowerPlaceCost("Tên tower", giá) khi lấy được giá thực tế
-- Gọi SetTowerUpgradeCost(X, path, giá) khi lấy được giá nâng path tại X (X là X của vector vị trí tower)
