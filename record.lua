local startTime = time()
local offset = 0
local fileName = "record.txt"  -- <--- ĐẶT TÊN FILE CỐ ĐỊNH Ở ĐÂY

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


local txtFile = "record.txt"
local outJson = "tdx/macros/y.json"  -- đổi tên nếu cần

if not isfile(txtFile) then
    error("Chưa có file record.txt!")
end

local HttpService = game:GetService("HttpService")
local macro = readfile(txtFile)
local logs = {}

-- Helper: Đảm bảo số float giống mẫu
local function floatfix(x)
    return tonumber(string.format("%.15g", tonumber(x)))
end

for line in macro:gmatch("[^\r\n]+") do
    -- PlaceTower: TDX:placeTower("Name", Vector3.new(x, y, z), rot, a1, cost)
    local towerName, x, y, z, rot, a1, cost = line:match('TDX:placeTower%(%s*"([^"]+)",%s*Vector3%.new%(([^,]+),%s*([^,]+),%s*([^%)]+)%)%s*,%s*([^,]+),%s*([^,]+),%s*([^,%s%)]+)')
    if towerName and x and y and z and rot and a1 and cost then
        table.insert(logs, {
            TowerPlaceCost = tonumber(cost),
            TowerPlaced = towerName,
            TowerVector = string.format("%s, %s, %s", floatfix(x), floatfix(y), floatfix(z)),
            Rotation = tonumber(rot),
            TowerA1 = tostring(a1)
        })
    else
        -- UpgradeTower: TDX:upgradeTower(X, path, cost)
        local X, path, cost = line:match('TDX:upgradeTower%(([^,]+),%s*([^,]+),%s*([^%)]+)%)')
        if X and path and cost then
            table.insert(logs, {
                UpgradeCost = tonumber(cost),
                UpgradePath = tonumber(path),
                TowerUpgraded = floatfix(X)
            })
        else
            -- ChangeTarget: TDX:changeQueryType(X, targetType)
            local X, targetType = line:match('TDX:changeQueryType%(([^,]+),%s*([^%)]+)%)')
            if X and targetType then
                table.insert(logs, {
                    ChangeTarget = floatfix(X),
                    TargetType = tonumber(targetType)
                })
            else
                -- SellTower: TDX:sellTower(X)
                local X = line:match('TDX:sellTower%(([^%)]+)%)')
                if X then
                    table.insert(logs, {
                        SellTower = floatfix(X)
                    })
                end
            end
        end
    end
end

-- Đảm bảo thư mục tdx/macros tồn tại (nếu dùng synapse hoặc executor có makefolder)
if makefolder then
    pcall(function() makefolder("tdx") end)
    pcall(function() makefolder("tdx/macros") end)
end

writefile(outJson, HttpService:JSONEncode(logs)) 
print("✅ Đã tạo macro " .. outJson .. " tương thích Macro Runner!")            
