-- ==== DỮ LIỆU JSON ĐỊNH DẠNG MỚI ====
local fileName = 1
while isfile(tostring(fileName)..".json") do
    fileName += 1
end
fileName = tostring(fileName)..".json"
writefile(fileName, "")

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
    writefile(fileName, encoded)
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

local function logJsonSellTower(towerX)
    local entry = {
        TowerSold = towerX
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

-- === Bạn cần tự hook/call các hàm sau đây ở script điều khiển của bạn ===
-- logJsonPlaceTower(towerName, vector3, rotation, towerA1)
-- logJsonUpgrade(x, path)
-- logJsonTargetChange(at, wanted, changedAt)
-- logJsonSellTower(x) <--- GỌI KHI BÁN TOWER

print("✅ JSON logger đã bắt đầu (KHÔNG ghi TXT, chỉ JSON mới, CÓ SELL).")



local startTime = time()
local offset = 0
local fileName = 1

-- Tìm tên file mới chưa tồn tại
while isfile(tostring(fileName)..".txt") do
    fileName += 1
end
fileName = tostring(fileName)..".txt"
writefile(fileName, "")

-- Hàm serialize giá trị
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

-- Hàm serialize tất cả argument
local function serializeArgs(...)
    local args = {...}
    local output = {}
    for i, v in ipairs(args) do
        output[i] = serialize(v)
    end
    return table.concat(output, ", ")
end

-- Hàm log thao tác vào file
local function log(method, self, serializedArgs)
    local name = tostring(self.Name)
    local text = name .. " " .. serializedArgs .. "\n"
    print(text)

    if name == "PlaceTower" then
        appendfile(fileName, "task.wait(" .. tostring((time() - offset) - startTime) .. ")\n")
        appendfile(fileName, "TDX:placeTower(" .. serializedArgs .. ")\n")
        startTime = time() - offset

    elseif name == "SellTower" then
        appendfile(fileName, "task.wait(" .. tostring((time() - offset) - startTime) .. ")\n")
        appendfile(fileName, "TDX:sellTower(" .. serializedArgs .. ")\n")
        startTime = time() - offset

    elseif name == "TowerUpgradeRequest" then
        appendfile(fileName, "task.wait(" .. tostring((time() - offset) - startTime) .. ")\n")
        appendfile(fileName, "TDX:upgradeTower(" .. serializedArgs .. ")\n")
        startTime = time() - offset

    -- Ghi thêm ChangeQueryType
    elseif name == "ChangeQueryType" then
        appendfile(fileName, "task.wait(" .. tostring((time() - offset) - startTime) .. ")\n")
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

print("✅ Ghi macro TDX đã bắt đầu.")
