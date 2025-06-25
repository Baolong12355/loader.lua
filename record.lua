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

-- ⚙️ Script rewrite TDX macro chuẩn
-- Ghi đúng hash → tọa độ X, UpgradeCost trước khi nâng cấp, ghi JSON chuẩn

local txtFile = "record.txt"
local outJson = "tdx/macros/y.json"

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local HttpService = game:GetService("HttpService")
local PlayerScripts = player:WaitForChild("PlayerScripts")

-- Hàm require an toàn
local function SafeRequire(module)
    local success, result = pcall(require, module)
    return success and result or nil
end

-- Load TowerClass
local TowerClass
do
    local client = PlayerScripts:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    TowerClass = SafeRequire(towerModule)
    if not TowerClass then
        warn("❌ Không thể load TowerClass")
        return
    end
end

-- Làm gọn số
local function floatfix(x)
    return tonumber(string.format("%.8g", tonumber(x)))
end

-- Lấy vị trí X của tower theo hash
local hash2pos = {}

task.spawn(function()
    while true do
        for hash, tower in pairs(TowerClass.GetTowers()) do
            local char = tower.Character
            if char then
                local model = char:GetCharacterModel()
                local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
                if root then
                    hash2pos[tostring(hash)] = {
                        x = floatfix(root.Position.X),
                        y = floatfix(root.Position.Y),
                        z = floatfix(root.Position.Z)
                    }
                end
            end
        end
        task.wait(0.1)
    end
end)

-- Lấy giá đặt tower từ giao diện
local function GetTowerPlaceCostByName(name)
    local gui = player:FindFirstChild("PlayerGui")
    local bar = gui and gui:FindFirstChild("Interface") and gui.Interface:FindFirstChild("BottomBar") and gui.Interface.BottomBar:FindFirstChild("TowersBar")
    if not bar then return 0 end
    for _, btn in ipairs(bar:GetChildren()) do
        if btn.Name == name then
            local text = btn:FindFirstChild("CostFrame") and btn.CostFrame:FindFirstChild("CostText")
            if text then
                return tonumber(text.Text:gsub("%D", "")) or 0
            end
        end
    end
    return 0
end

-- Lấy giá nâng cấp path (level hiện tại → level kế tiếp)
local function GetUpgradeCost(tower, path)
    if not tower or not tower.LevelHandler then return 0 end
    local level = tower.LevelHandler:GetLevelOnPath(path)
    local max = tower.LevelHandler:GetMaxLevel()
    if level >= max then return 0 end
    local ok, cost = pcall(function()
        return tower.LevelHandler:GetLevelUpgradeCost(path, 1)
    end)
    return (ok and tonumber(cost)) and math.floor(cost) or 0
end

-- Tạo folder nếu chưa có
if makefolder then
    pcall(function() makefolder("tdx") end)
    pcall(function() makefolder("tdx/macros") end)
end

-- Main loop
while true do
    if isfile(txtFile) then
        local raw = readfile(txtFile)
        local logs = {}

        for line in raw:gmatch("[^\r\n]+") do
            -- PlaceTower
            local x, name, y, rot, z, a1 = line:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)')
            if x and name and y and rot and z and a1 then
                name = tostring(name):gsub('^%s*"(.-)"%s*$', '%1')
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
                -- UpgradeTower
                local hash, path = line:match("TDX:upgradeTower%(([^,]+),%s*([^%)]+)%)")
                if hash and path then
                    local tower = TowerClass.GetTowers()[hash]
                    local pos = hash2pos[tostring(hash)]
                    local cost = GetUpgradeCost(tower, tonumber(path))
                    if pos and cost > 0 then
                        table.insert(logs, {
                            UpgradeCost = cost,
                            UpgradePath = tonumber(path),
                            TowerUpgraded = pos.x -- ✅ đúng X
                        })
                    end
                else
                    -- ChangeQueryType
                    local hash, targetType = line:match("TDX:changeQueryType%(([^,]+),%s*([^%)]+)%)")
                    if hash and targetType then
                        local pos = hash2pos[tostring(hash)]
                        if pos then
                            table.insert(logs, {
                                TargetType = tonumber(targetType),
                                ChangeTarget = pos.x
                            })
                        end
                    else
                        -- SellTower
                        local hash = line:match("TDX:sellTower%(([^%)]+)%)")
                        if hash then
                            local pos = hash2pos[tostring(hash)]
                            if pos then
                                table.insert(logs, {
                                    SellTower = pos.x
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
