local startTime = time()
local offset = 0
local fileName = "record_1.txt"  -- <--- ĐẶT TÊN FILE CỐ ĐỊNH Ở ĐÂY

-- Nếu file đã tồn tại thì xóa để tạo mới
if isfile(fileName) then
    delfile(fileName)
end
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

print("✅ Ghi macro TDX đã bắt đầu (luôn dùng tên record.txt).")



local txtFile = "record_1.txt"
local jsonFile = "record_1.json"
local outFile = "record_1_rewritten.json"

-- Helper: parse vector string "x, y, z"
local function parseVector(str)
    local x, y, z = string.match(str, "([-0-9%.]+),%s*([-0-9%.]+),%s*([-0-9%.]+)")
    if x and y and z then return tonumber(x), tonumber(y), tonumber(z) end
end

-- Parse macro TXT, lấy mapping hash <-> vector theo thời gian
local macro = readfile(txtFile)
local hashToVector = {}
local liveTowers = {}  -- hash -> vector
for line in macro:gmatch("[^\r\n]+") do
    if line:find("TDX:placeTower") then
        -- TDX:placeTower("TowerName", Vector3.new(x, y, z), rot, hash, ...)
        local towerName, x, y, z, rot, hash = line:match('TDX:placeTower%(%s*"([^"]+)",%s*Vector3%.new%(([^,]+),%s*([^,]+),%s*([^%)]+)%)%s*,%s*([^,]+),%s*([^,%s%)]+)')
        if hash then
            liveTowers[hash] = {x=tonumber(x), y=tonumber(y), z=tonumber(z)}
            hashToVector[hash] = string.format("%s, %s, %s", x, y, z)
        end
    elseif line:find("TDX:sellTower") then
        -- TDX:sellTower(hash)
        local hash = line:match("TDX:sellTower%(([^%)]+)%)")
        if hash then
            liveTowers[hash] = nil
        end
    end
end

-- Đọc JSON log gốc
local HttpService = game:GetService("HttpService")
local logArr = HttpService:JSONDecode(readfile(jsonFile))
local rewritten = {}

-- Rewrite từng record
for i, rec in ipairs(logArr) do
    if rec.TowerPlaceCost then
        -- Đặt tower: giữ nguyên format, bổ sung hash nếu muốn
        table.insert(rewritten, rec)
    elseif rec.UpgradeCost then
        -- Nâng cấp: tìm hash thực với vector X hiện tại (an toàn hơn)
        local towerX = rec.TowerUpgraded or rec.TowerHash
        local resolvedHash
        if towerX then
            -- Nếu hash vẫn còn, dùng
            for h, v in pairs(liveTowers) do
                if math.abs(v.x - tonumber(towerX)) < 1e-5 then
                    resolvedHash = h
                    break
                end
            end
        end
        table.insert(rewritten, {
            UpgradeCost = rec.UpgradeCost,
            UpgradePath = rec.UpgradePath,
            TowerUpgraded = towerX -- hoặc resolvedHash nếu cần
        })
    elseif rec.TowerTargetChange then
        table.insert(rewritten, rec)
    elseif rec.TowerSold then
        table.insert(rewritten, rec)
    end
end

writefile(outFile, HttpService:JSONEncode(rewritten))
print("✅ Đã rewrite JSON an toàn, đối chiếu hash từ TXT macro!")
