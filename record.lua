local startTime = time()
local offset = 0
local fileName = 1

-- Tìm tên file mới chưa tồn tại
while isfile(tostring(fileName)..".txt") do
    fileName += 1
end
fileName = tostring(fileName)..".txt"
writefile(fileName, "")

local jsonOldFile = string.gsub(fileName, ".txt$", ".json")
local jsonNewFile = string.gsub(fileName, ".txt$", "_new.json")

--=== DỮ LIỆU JSON LOG (CŨ) ===--
local jsonData = {}
local towerPriceTable = {}      -- towerName -> price
local towerUpgradeTable = {}    -- towerHash -> {[path]=cost}
local towerHashToVector = {}    -- towerHash -> TowerVector string

-- Helper: serialize value (cũ, giữ lại để không ảnh hưởng logic macro txt)
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

-- Helper: convert Vector3 to string
local function vector3ToString(vec)
    if typeof(vec) == "Vector3" then
        return string.format("%.8f, %.8f, %.8f", vec.X, vec.Y, vec.Z)
    elseif type(vec) == "table" and vec.X and vec.Y and vec.Z then
        return string.format("%.8f, %.8f, %.8f", vec.X, vec.Y, vec.Z)
    end
    return tostring(vec)
end

-- Helper: lấy X từ vector string ("x, y, z"), hoặc từ vector object
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

-- Helper: save JSON cũ (full hash)
local function saveJsonOld()
    local encoded = game:GetService("HttpService"):JSONEncode(jsonData)
    writefile(jsonOldFile, encoded)
end

-- Helper: convert và ghi lại JSON mới (chuẩn mới, chỉ X)
local function rewriteJsonNew()
    local HttpService = game:GetService("HttpService")
    local oldData = {}
    if isfile(jsonOldFile) then
        oldData = HttpService:JSONDecode(readfile(jsonOldFile))
    end

    -- hash -> X mapping
    local hashToX = {}
    for _, v in ipairs(oldData) do
        if v.TowerPlaceCost and v.TowerVector then
            -- Nếu có trường hash, lấy hash->X
            if v.hash then
                local x = tonumber((v.TowerVector):match("^[^,]+"))
                if x then hashToX[v.hash] = x end
            end
        end
    end

    local outData = {}
    for _, v in ipairs(oldData) do
        if v.TowerPlaceCost and v.TowerVector then
            table.insert(outData, v)
        elseif v.UpgradeCost and v.UpgradePath and v.TowerHash then
            -- lấy X từ hash
            local towerX = hashToX[v.TowerHash] or tonumber(v.TowerHash) or 0
            table.insert(outData, {
                UpgradeCost = v.UpgradeCost,
                UpgradePath = v.UpgradePath,
                TowerUpgraded = towerX
            })
        elseif v.TowerTargetChange then
            table.insert(outData, v)
        end
    end

    writefile(jsonNewFile, HttpService:JSONEncode(outData))
end

-- Các hàm hỗ trợ cập nhật bảng giá
function SetTowerPlaceCost(towerName, cost)
    towerPriceTable[towerName] = cost
end
function SetTowerUpgradeCost(towerHash, path, cost)
    towerUpgradeTable[towerHash] = towerUpgradeTable[towerHash] or {}
    towerUpgradeTable[towerHash][path] = cost
end

--=== LOGIC GHI LOG (KHÔNG ĐỔI) ===--
local function log(method, self, serializedArgs, ...)
    local name = tostring(self.Name)
    local text = name .. " " .. serializedArgs .. "\n"
    print(text)

    if name == "PlaceTower" then
        appendfile(fileName, "task.wait(" .. tostring((time() - offset) - startTime) .. ")\n")
        appendfile(fileName, "TDX:placeTower(" .. serializedArgs .. ")\n")
        startTime = time() - offset

        -- Ghi JSON cũ
        local args = {...}
        local towerName = args[1]
        local towerVec = vector3ToString(args[2])
        local rotation = args[3] or 0
        local towerHash = tostring(args[4] or #jsonData+1)

        local towerCost = towerPriceTable[towerName] or 0

        local towerEntry = {
            TowerPlaceCost = towerCost,
            TowerPlaced = towerName,
            TowerVector = towerVec,
            Rotation = rotation,
            TowerA1 = tick(),
            hash = towerHash -- để tiện chuyển đổi!
        }
        table.insert(jsonData, towerEntry)
        towerHashToVector[towerHash] = towerVec
        saveJsonOld()
        rewriteJsonNew()

    elseif name == "SellTower" then
        appendfile(fileName, "task.wait(" .. tostring((time() - offset) - startTime) .. ")\n")
        appendfile(fileName, "TDX:sellTower(" .. serializedArgs .. ")\n")
        startTime = time() - offset

    elseif name == "TowerUpgradeRequest" then
        appendfile(fileName, "task.wait(" .. tostring((time() - offset) - startTime) .. ")\n")
        appendfile(fileName, "TDX:upgradeTower(" .. serializedArgs .. ")\n")
        startTime = time() - offset

        local args = {...}
        local towerHash = tostring(args[1])
        local upgradePath = tonumber(args[2])
        local upgradeCost = 0
        if towerUpgradeTable[towerHash] and towerUpgradeTable[towerHash][upgradePath] then
            upgradeCost = towerUpgradeTable[towerHash][upgradePath]
        end
        if not towerUpgradeTable[towerHash] then towerUpgradeTable[towerHash] = {} end
        if not towerUpgradeTable[towerHash][upgradePath] then
            towerUpgradeTable[towerHash][upgradePath] = upgradeCost
        end

        -- Ghi JSON cũ
        local upgradeEntry = {
            UpgradeCost = upgradeCost,
            TowerHash = towerHash,
            UpgradePath = upgradePath
        }
        table.insert(jsonData, upgradeEntry)
        saveJsonOld()
        rewriteJsonNew()

    elseif name == "ChangeQueryType" then
        appendfile(fileName, "task.wait(" .. tostring((time() - offset) - startTime) .. ")\n")
        appendfile(fileName, "TDX:changeQueryType(" .. serializedArgs .. ")\n")
        startTime = time() - offset

    elseif name == "TowerTargetChange" then
        local args = {...}
        local at, wanted, changedAt = args[1], args[2], args[3]
        local targetEntry = {
            TowerTargetChange = at,
            TargetWanted = wanted,
            TargetChangedAt = changedAt
        }
        table.insert(jsonData, targetEntry)
        saveJsonOld()
        rewriteJsonNew()
    end
end

-- Hook FireServer
local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
    local args = {...}
    log("FireServer", self, serializeArgs(...), ...)
    return oldFireServer(self, ...)
end)

-- Hook InvokeServer
local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
    local args = {...}
    log("InvokeServer", self, serializeArgs(...), ...)
    return oldInvokeServer(self, ...)
end)

-- Hook __namecall
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    if method == "FireServer" or method == "InvokeServer" then
        log(method, self, serializeArgs(...), ...)
    end
    return oldNamecall(self, ...)
end)

print("✅ Macro record + xuất JSON chuẩn mới đồng thời! File _new.json sẽ luôn đúng format bạn cần.")

-- Gọi SetTowerPlaceCost("Tên tower", giá) khi lấy được giá thực tế
-- Gọi SetTowerUpgradeCost(hash, path, giá) khi lấy được giá nâng path (hash là id tower – chính là hash macro cũ dùng)
