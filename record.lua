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

-- 📦 Rewrite record.txt thành macro JSON chuẩn TDX

local txtFile = "record.txt"
local outJson = "tdx/macros/y.json"

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local HttpService = game:GetService("HttpService")
local PlayerScripts = player:WaitForChild("PlayerScripts")

-- Load TowerClass
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

-- Làm gọn số
local function floatfix(x)
    return tonumber(string.format("%.8g", tonumber(x)))
end

-- Hash -> Vị trí X
local hash2x = {}

-- Cập nhật ánh xạ hash -> x
task.spawn(function()
    while true do
        for hash, tower in pairs(TowerClass.GetTowers()) do
            local char = tower.Character
            if char then
                local model = char:GetCharacterModel()
                local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
                if root then
                    hash2x[tostring(hash)] = floatfix(root.Position.X)
                end
            end
        end
        task.wait(0.15)
    end
end)

-- Lấy giá đặt tower từ GUI
local function GetTowerPlaceCostByName(name)
    local interface = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("Interface")
    local towersBar = interface and interface:FindFirstChild("BottomBar") and interface.BottomBar:FindFirstChild("TowersBar")
    if not towersBar then return 0 end

    for _, tower in ipairs(towersBar:GetChildren()) do
        if tower.Name == name then
            local text = tower:FindFirstChild("CostFrame") and tower.CostFrame:FindFirstChild("CostText")
            if text then
                return tonumber(text.Text:match("%d+")) or 0
            end
        end
    end
    return 0
end

-- Lấy giá nâng cấp hiện tại (trước khi nâng)
local function GetUpgradeCost(hash, path)
    local tower = TowerClass.GetTowers()[hash]
    if not tower or not tower.LevelHandler then return 0 end
    local lvl = tower.LevelHandler:GetLevelOnPath(path)
    local ok, cost = pcall(function()
        return tower.LevelHandler:GetLevelUpgradeCost(path, 1)
    end)
    return (ok and type(cost) == "number") and math.floor(cost) or 0
end

-- Xử lý macro -> JSON
while true do
    if isfile(txtFile) then
        local lines = readfile(txtFile)
        local logs = {}

        for line in lines:gmatch("[^\r\n]+") do
            -- placeTower
            local x, name, y, rot, z, a1 = line:match("TDX:placeTower%(([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)")
            if x and name and y and rot and z and a1 then
                name = name:gsub('^%s*"(.-)"%s*$', '%1')
                table.insert(logs, {
                    TowerPlaceCost = GetTowerPlaceCostByName(name),
                    TowerPlaced = name,
                    TowerVector = string.format("%.8g, %.8g, %.8g", floatfix(x), floatfix(y), floatfix(z)),
                    Rotation = floatfix(rot),
                    TowerA1 = tostring(floatfix(a1))
                })

            -- upgradeTower
            else
                local hash, path = line:match("TDX:upgradeTower%(([^,]+),%s*([^%)]+)%)")
                if hash and path then
                    local x = hash2x[tostring(hash)]
                    if x then
                        table.insert(logs, {
                            UpgradeCost = GetUpgradeCost(hash, tonumber(path)),
                            UpgradePath = tonumber(path),
                            TowerUpgraded = x
                        })
                    end

                -- changeQueryType
                else
                    local hash, targetType = line:match("TDX:changeQueryType%(([^,]+),%s*([^%)]+)%)")
                    if hash and targetType then
                        local x = hash2x[tostring(hash)]
                        if x then
                            table.insert(logs, {
                                ChangeTarget = x,
                                TargetType = tonumber(targetType)
                            })
                        end

                    -- sellTower
                    else
                        local hash = line:match("TDX:sellTower%(([^%)]+)%)")
                        if hash then
                            local x = hash2x[tostring(hash)]
                            if x then
                                table.insert(logs, {
                                    SellTower = x
                                })
                            end
                        end
                    end
                end
            end
        end

        writefile(outJson, HttpService:JSONEncode(logs))
    end
    wait(0.22)
end
