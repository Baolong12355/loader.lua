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

-- 📦 Require an toàn
local function SafeRequire(module)
    local success, result = pcall(require, module)
    return success and result or nil
end

-- 📦 Load TowerClass
local TowerClass
do
    local client = PlayerScripts:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    TowerClass = SafeRequire(towerModule)
end

-- 📌 Lấy vị trí tower
local function GetTowerPosition(tower)
    if not tower or not tower.Character then return nil end
    local model = tower.Character:GetCharacterModel()
    local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
    return root and root.Position or nil
end

-- 📌 Lấy giá đặt tower
local function GetTowerPlaceCostByName(name)
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return 0 end
    local interface = gui:FindFirstChild("Interface")
    local bar = interface and interface:FindFirstChild("BottomBar")
    local towersBar = bar and bar:FindFirstChild("TowersBar")
    if not towersBar then return 0 end
    for _, tower in ipairs(towersBar:GetChildren()) do
        if tower.Name == name then
            local text = tower:FindFirstChild("CostFrame") and tower.CostFrame:FindFirstChild("CostText")
            if text then
                return tonumber(text.Text:gsub("%D", "")) or 0
            end
        end
    end
    return 0
end

-- 📌 Giá nâng cấp path
local function GetUpgradeCost(tower, path)
    if not tower or not tower.LevelHandler then return 0 end
    local lvl = tower.LevelHandler:GetLevelOnPath(path)
    local ok, cost = pcall(function()
        return tower.LevelHandler:GetLevelUpgradeCost(path, lvl + 1)
    end)
    return ok and tonumber(cost) or 0
end

-- 📌 Ánh xạ hash → vị trí (liên tục)
local hash2pos = {}
task.spawn(function()
    while true do
        for hash, tower in pairs(TowerClass and TowerClass.GetTowers() or {}) do
            local pos = GetTowerPosition(tower)
            if pos then
                hash2pos[tostring(hash)] = { x = pos.X, y = pos.Y, z = pos.Z }
            end
        end
        task.wait(0.1)
    end
end)

-- 📂 Tạo folder nếu cần
if makefolder then
    pcall(function() makefolder("tdx") end)
    pcall(function() makefolder("tdx/macros") end)
end

-- 📥 Main Loop
while true do
    if isfile(txtFile) then
        local macro = readfile(txtFile)
        local logs = {}

        for line in macro:gmatch("[^\r\n]+") do
            -- PlaceTower
            local x, name, y, rot, z, a1 = line:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)')
            if x and name and y and rot and z and a1 then
                name = tostring(name):gsub('^%s*"(.-)"%s*$', '%1')
                local cost = GetTowerPlaceCostByName(name)
                local vector = table.concat({x, y, z}, ", ")
                table.insert(logs, {
                    TowerPlaceCost = cost,
                    TowerPlaced = name,
                    TowerVector = vector,
                    Rotation = tonumber(rot),
                    TowerA1 = tostring(a1)
                })
            else
                -- UpgradeTower
                local hash, path = line:match('TDX:upgradeTower%(([^,]+),%s*([^,]+),')
                if hash and path then
                    local pos = hash2pos[tostring(hash)]
                    local tower = TowerClass and TowerClass.GetTowers()[hash]
                    if pos then
                        local upgradeCost = GetUpgradeCost(tower, tonumber(path))
                        table.insert(logs, {
                            UpgradeCost = upgradeCost,
                            UpgradePath = tonumber(path),
                            TowerUpgraded = pos.X
                        })
                    end
                else
                    -- ChangeQueryType
                    local hash, targetType = line:match('TDX:changeQueryType%(([^,]+),%s*([^%)]+)%)')
                    if hash and targetType then
                        local pos = hash2pos[tostring(hash)]
                        if pos then
                            table.insert(logs, {
                                ChangeTarget = pos.X,
                                TargetType = tonumber(targetType)
                            })
                        end
                    else
                        -- SellTower
                        local hash = line:match('TDX:sellTower%(([^%)]+)%)')
                        if hash then
                            local pos = hash2pos[tostring(hash)]
                            if pos then
                                table.insert(logs, {
                                    SellTower = pos.X
                                })
                            end
                        end
                    end
                end
            end
        end

        writefile(outJson, HttpService:JSONEncode(logs))
    end
    task.wait(0.22)
end
