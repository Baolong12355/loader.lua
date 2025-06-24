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
local outJson = "tdx/macros/y.json"

-- Tải config tower
local TDX_Shared = game:GetService("ReplicatedStorage"):WaitForChild("TDX_Shared")
local Common = TDX_Shared:WaitForChild("Common")
local ResourceManager = require(Common:WaitForChild("ResourceManager"))

local HttpService = game:GetService("HttpService")

-- Tạo folder nếu cần
if makefolder then
    pcall(function() makefolder("tdx") end)
    pcall(function() makefolder("tdx/macros") end)
end

-- Map hash -> towerName, đặt khi placeTower
local hash2tower = {} -- hash => {name=..., vector=...}

while true do
    if isfile(txtFile) then
        local macro = readfile(txtFile)
        local logs = {}
        local macroLines = {}
        for l in macro:gmatch("[^\r\n]+") do table.insert(macroLines, l) end

        -- Quét từng thao tác
        for idx, line in ipairs(macroLines) do
            -- PlaceTower
            local x, name, y, rot, z, a1 = line:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)')
            if x and name and y and rot and z and a1 then
                name = tostring(name):gsub('^%s*"(.-)"%s*$', '%1')
                local vector = string.format("%.8g, %.8g, %.8g", tonumber(x), tonumber(y), tonumber(z))
                -- Tạo fake hash, trên thực tế nếu macro gốc log hash thì dùng hash thật
                local hash = vector.."_"..name
                -- Lưu ánh xạ hash -> tên để tra sau này
                hash2tower[hash] = {name=name, vector=vector}
                -- Lấy giá đặt tower từ config
                local towerConfig = ResourceManager.GetTowerConfig(name)
                local cost = towerConfig and towerConfig.Cost or 0
                table.insert(logs, {
                    TowerPlaceCost = cost,
                    TowerPlaced = name,
                    TowerVector = vector,
                    Rotation = tonumber(rot),
                    TowerA1 = tostring(a1),
                    Hash = hash -- log lại hash để upgrade tra
                })
            else
                -- UpgradeTower
                local hash, path, dummy = line:match('TDX:upgradeTower%(([^,]+),%s*([^,]+),%s*([^%)]+)%)')
                if hash and path then
                    local towerInfo = hash2tower[hash]
                    if towerInfo then
                        local towerName = towerInfo.name
                        -- Phải log lại cấp path trước khi nâng mới đúng (giả sử cấp path hiện tại là curLevel)
                        -- Ở đây ví dụ macro gốc đã log cấp path trước khi nâng ở biến dummy, hoặc bạn tự quản lý biến này.
                        local curLevel = tonumber(dummy)
                        -- Lấy giá nâng cấp từ config:
                        local towerConfig = ResourceManager.GetTowerConfig(towerName)
                        local pathData = towerConfig and towerConfig.UpgradePathData["Path"..path.."Data"]
                        local upgradeInfo = pathData and pathData[curLevel+1]
                        local upgradeCost = (upgradeInfo and upgradeInfo.Cost) or 0
                        table.insert(logs, {
                            UpgradeCost = upgradeCost,
                            UpgradePath = tonumber(path),
                            TowerUpgraded = towerInfo.vector
                        })
                    end
                end
                -- Các thao tác khác giữ nguyên...
            end
        end

        writefile(outJson, HttpService:JSONEncode(logs))
    end
    wait(0.1)
end
