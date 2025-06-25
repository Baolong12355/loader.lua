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

-- ⚙️ Cấu hình
local txtFile = "record.txt"
local outJson = "tdx/macros/y.json"

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local HttpService = game:GetService("HttpService")
local PlayerScripts = player:WaitForChild("PlayerScripts")

-- ✅ Require an toàn
local function SafeRequire(module)
    local ok, result = pcall(require, module)
    return ok and result or nil
end

-- ✅ Load TowerClass
local TowerClass
do
    local client = PlayerScripts:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    TowerClass = SafeRequire(towerModule)
end

-- ✅ Lấy vị trí X của tower
local function GetTowerPositionX(tower)
    if not tower or not tower.Character then return nil end
    local model = tower.Character:GetCharacterModel()
    local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
    return root and tonumber(root.Position.X)
end

-- ✅ Làm gọn số
local function floatfix(x)
    return tonumber(string.format("%.8g", tonumber(x)))
end

-- ✅ Lấy giá đặt tower theo tên
local function GetTowerPlaceCostByName(name)
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return 0 end
    local interface = gui:FindFirstChild("Interface")
    if not interface then return 0 end
    local bar = interface:FindFirstChild("BottomBar")
    if not bar then return 0 end
    local towersBar = bar:FindFirstChild("TowersBar")
    if not towersBar then return 0 end

    for _, tower in ipairs(towersBar:GetChildren()) do
        if tower.Name == name then
            local text = tower:FindFirstChild("CostFrame") and tower.CostFrame:FindFirstChild("CostText")
            if text then
                local raw = tostring(text.Text):gsub("%D", "")
                return tonumber(raw) or 0
            end
        end
    end
    return 0
end

-- ✅ Lấy UpgradeCost trước khi nâng
local function GetUpgradeCostBeforeUpgrade(tower, path)
    if not tower or not tower.LevelHandler then return 0 end
    local currentLevel = tower.LevelHandler:GetLevelOnPath(path)
    local ok, cost = pcall(function()
        return tower.LevelHandler:GetLevelUpgradeCost(path, currentLevel + 1)
    end)
    if ok and cost then
        return math.floor(cost)
    end
    return 0
end

-- ✅ Map hash → x liên tục
local hash2x = {}
task.spawn(function()
    while true do
        local towers = TowerClass and TowerClass.GetTowers() or {}
        for hash, tower in pairs(towers) do
            local x = GetTowerPositionX(tower)
            if x then
                hash2x[tostring(hash)] = floatfix(x)
            end
        end
        task.wait(0.1)
    end
end)

-- ✅ Main rewrite loop
if makefolder then
    pcall(function() makefolder("tdx") end)
    pcall(function() makefolder("tdx/macros") end)
end

while true do
    if isfile(txtFile) then
        local macro = readfile(txtFile)
        local logs = {}

        for line in macro:gmatch("[^\r\n]+") do
            -- 🎯 Đặt tower
            local x, name, y, rot, z, a1 = line:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)')
            if x and name and y and rot and z and a1 then
                name = name:gsub('^%s*"(.-)"%s*$', '%1')
                local cost = GetTowerPlaceCostByName(name)
                local vec = string.format("%.8g, %.8g, %.8g", floatfix(x), floatfix(y), floatfix(z))
                table.insert(logs, {
                    TowerPlaceCost = cost,
                    TowerPlaced = name,
                    TowerVector = vec,
                    Rotation = floatfix(rot),
                    TowerA1 = tostring(floatfix(a1))
                })
            else
                -- 🎯 Nâng cấp
                local hash, path = line:match('TDX:upgradeTower%(([^,]+),%s*([^,]+),')
                if hash and path then
                    local tower = TowerClass and TowerClass.GetTowers()[tostring(hash)]
                    local x = hash2x[tostring(hash)]
                    local upgradeCost = tower and GetUpgradeCostBeforeUpgrade(tower, tonumber(path)) or 0
                    if x then
                        table.insert(logs, {
                            UpgradeCost = upgradeCost,
                            UpgradePath = tonumber(path),
                            TowerUpgraded = x
                        })
                    end
                else
                    -- 🎯 Target change
                    local hash, target = line:match('TDX:changeQueryType%(([^,]+),%s*([^%)]+)%)')
                    if hash and target then
                        local x = hash2x[tostring(hash)]
                        if x then
                            table.insert(logs, {
                                ChangeTarget = x,
                                TargetType = tonumber(target)
                            })
                        end
                    else
                        -- 🎯 Bán tower
                        local hash = line:match('TDX:sellTower%(([^%)]+)%)')
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
    wait(0.25)
end
