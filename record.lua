local startTime = time()
local offset = 0
local fileName = 1

-- Tìm tên file mới chưa tồn tại
while isfile(tostring(fileName)..".txt") do
    fileName += 1
end
fileName = tostring(fileName)..".txt"
writefile(fileName, "")

-- ==== DỮ LIỆU JSON ĐỊNH DẠNG MỚI ====
local jsonData = {}
local towerPriceTable = {}      -- towerName -> price
local towerUpgradeTable = {}    -- towerX -> { [path]=cost }
local hashToVector = {}         -- towerX -> vector string, dùng để suy ra vị trí
local hashToName = {}           -- towerX -> towerName

-- Helper: chuyển Vector3 thành string
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
    writefile(string.gsub(fileName, ".txt$", ".json"), encoded)
end

-- === HÀM BẠN GỌI TỪ NGOÀI ===
function SetTowerPlaceCost(towerName, cost) towerPriceTable[towerName] = cost end
function SetTowerUpgradeCost(towerX, path, cost)
    towerUpgradeTable[towerX] = towerUpgradeTable[towerX] or {}
    towerUpgradeTable[towerX][path] = cost
end

-- ==== GHI JSON ĐÚNG ĐỊNH DẠNG MỚI ====
local function logJsonPlaceTower(towerName, vec, rotation, towerA1)
    local cost = towerPriceTable[towerName] or 0
    local vectorStr = vector3ToString(vec)
    local x = getXFromVector(vec)
    if x then
        hashToVector[x] = vectorStr
        hashToName[x] = towerName
    end
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

-- === SERIALIZE CHO MACRO TXT CŨ ===
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

-- === GHI LOG TXT & JSON ===
local function log(method, self, serializedArgs, ...)
    local name = tostring(self.Name)
    if name == "PlaceTower" then
        appendfile(fileName, "task.wait(" .. tostring((time() - offset) - startTime) .. ")\n")
        appendfile(fileName, "TDX:placeTower(" .. serializedArgs .. ")\n")
        startTime = time() - offset

        local args = {...}
        local towerName, vec, rotation = args[1], args[2], args[3]
        logJsonPlaceTower(towerName, vec, rotation, tick())

    elseif name == "SellTower" then
        appendfile(fileName, "task.wait(" .. tostring((time() - offset) - startTime) .. ")\n")
        appendfile(fileName, "TDX:sellTower(" .. serializedArgs .. ")\n")
        startTime = time() - offset

    elseif name == "TowerUpgradeRequest" then
        appendfile(fileName, "task.wait(" .. tostring((time() - offset) - startTime) .. ")\n")
        appendfile(fileName, "TDX:upgradeTower(" .. serializedArgs .. ")\n")
        startTime = time() - offset

        local args = {...}
        local towerHash = args[1]
        local upgradePath = tonumber(args[2])
        local x = getXFromVector(towerHash)
        logJsonUpgrade(x, upgradePath)

    elseif name == "ChangeQueryType" then
        appendfile(fileName, "task.wait(" .. tostring((time() - offset) - startTime) .. ")\n")
        appendfile(fileName, "TDX:changeQueryType(" .. serializedArgs .. ")\n")
        startTime = time() - offset

    elseif name == "TowerTargetChange" then
        local args = {...}
        local at, wanted, changedAt = args[1], args[2], args[3]
        logJsonTargetChange(at, wanted, changedAt)
    end
end

-- === HOOKS ===
local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
    local args = {...}
    log("FireServer", self, serializeArgs(...), ...)
    return oldFireServer(self, ...)
end)

local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
    local args = {...}
    log("InvokeServer", self, serializeArgs(...), ...)
    return oldInvokeServer(self, ...)
end)

local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    if method == "FireServer" or method == "InvokeServer" then
        log(method, self, serializeArgs(...), ...)
    end
    return oldNamecall(self, ...)
end)

print("✅ Ghi macro TDX (JSON định dạng mới, hash = X vector) đã bắt đầu.")

-- Gọi SetTowerPlaceCost("Tên tower", giá) khi lấy được giá thực tế
-- Gọi SetTowerUpgradeCost(X, path, giá) khi lấy được giá nâng path tại X (X là X của vector vị trí tower)
