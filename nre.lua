local startTime = time()
local offset = 0
local fileName = "record.txt"

-- Xóa file cũ nếu có
if isfile(fileName) then
    delfile(fileName)
end
writefile(fileName, "")

-- Serialize giá trị
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

-- Serialize toàn bộ argument
local function serializeArgs(...)
    local args = {...}
    local output = {}
    for i, v in ipairs(args) do
        output[i] = serialize(v)
    end
    return table.concat(output, ", ")
end

-- Ghi log vào file
local function log(method, self, serializedArgs)
    local name = tostring(self.Name)

    if name == "PlaceTower" then
        appendfile(fileName, "task.wait(" .. ((time() - offset) - startTime) .. ")\n")
        appendfile(fileName, "TDX:placeTower(" .. serializedArgs .. ")\n")
        startTime = time() - offset

    elseif name == "SellTower" then
        appendfile(fileName, "task.wait(" .. ((time() - offset) - startTime) .. ")\n")
        appendfile(fileName, "TDX:sellTower(" .. serializedArgs .. ")\n")
        startTime = time() - offset

    elseif name == "TowerUpgradeRequest" then
        appendfile(fileName, "task.wait(" .. ((time() - offset) - startTime) .. ")\n")
        appendfile(fileName, "TDX:upgradeTower(" .. serializedArgs .. ")\n")
        startTime = time() - offset

    elseif name == "ChangeQueryType" then
        appendfile(fileName, "task.wait(" .. ((time() - offset) - startTime) .. ")\n")
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
local outJson = "tdx/macros/x.json"

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local HttpService = game:GetService("HttpService")
local PlayerScripts = player:WaitForChild("PlayerScripts")
local Workspace = game:GetService("Workspace")

-- Safe require tower module
local function SafeRequire(module)
    local ok, result = pcall(require, module)
    return ok and result or nil
end

-- Load TowerClass
local TowerClass
do
    local client = PlayerScripts:FindFirstChild("Client")
    local gameClass = client and client:FindFirstChild("GameClass")
    local towerModule = gameClass and gameClass:FindFirstChild("TowerClass")
    TowerClass = towerModule and SafeRequire(towerModule)
end

if not TowerClass then
    warn("❌ Không thể load TowerClass")
    return
end

-- Lấy cấp path
local function GetPathLevel(tower, path)
    if not tower or not tower.LevelHandler then return nil end
    local ok, result = pcall(function()
        return tower.LevelHandler:GetLevelOnPath(path)
    end)
    return ok and result or nil
end

-- Cache cấp path
local upgradeCache = {}

-- Cập nhật cache trước khi nâng cấp
local function CacheCurrentLevels()
    for hash, tower in pairs(TowerClass.GetTowers()) do
        local h = tostring(hash)
        upgradeCache[h] = upgradeCache[h] or {}
        for path = 1, 2 do
            local lvl = GetPathLevel(tower, path)
            if lvl ~= nil then
                upgradeCache[h][path] = lvl
            end
        end
    end
end

-- Kiểm tra nâng cấp thành công
local function IsUpgradeSuccess(hash, path)
    local tower = TowerClass.GetTowers()[hash]
    if not tower then return false end
    local cur = GetPathLevel(tower, path)
    local old = upgradeCache[hash] and upgradeCache[hash][path]
    if old ~= nil and cur and cur > old then
        print(string.format("[UPGRADE SUCCESS] hash: %s | path: %d | %d ➜ %d", hash, path, old, cur))
        upgradeCache[hash][path] = cur
        return true
    end
    return false
end

-- Get Tower position
local function GetTowerPosition(tower)
    if not tower or not tower.Character then return nil end
    local ok, pos = pcall(function()
        local model = tower.Character:GetCharacterModel()
        local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
        return root and root.Position
    end)
    return ok and pos or nil
end

-- Ánh xạ hash → pos
local hash2pos = {}
task.spawn(function()
    while true do
        for hash, tower in pairs(TowerClass.GetTowers()) do
            local pos = GetTowerPosition(tower)
            if pos then
                hash2pos[tostring(hash)] = {x = pos.X, y = pos.Y, z = pos.Z}
            end
        end
        task.wait(0.05)
    end
end)

-- Lấy giá đặt tower
local function GetTowerPlaceCostByName(name)
    local gui = player:FindFirstChild("PlayerGui")
    local interface = gui and gui:FindFirstChild("Interface")
    local bottomBar = interface and interface:FindFirstChild("BottomBar")
    local towersBar = bottomBar and bottomBar:FindFirstChild("TowersBar")
    if not towersBar then return 0 end
    for _, tower in ipairs(towersBar:GetChildren()) do
        if tower.Name == name then
            local text = tower:FindFirstChild("CostFrame") and tower.CostFrame:FindFirstChild("CostText")
            if text and typeof(text.Text) == "string" then
                local raw = text.Text:match("%d+")
                return tonumber(raw) or 0
            end
        end
    end
    return 0
end

-- Tạo thư mục nếu cần
if makefolder then
    pcall(function() makefolder("tdx") end)
    pcall(function() makefolder("tdx/macros") end)
end

print("✅ Bắt đầu convert record.txt → x.json...")

while true do
    if isfile(txtFile) then
        local macro = readfile(txtFile)
        local logs = {}
        CacheCurrentLevels()

        for line in macro:gmatch("[^\r\n]+") do
            -- PLACE
            local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)')
            if a1 and name and x and y and z and rot then
                name = tostring(name):gsub('^%s*"(.-)"%s*$', '%1')
                if name == "" then
                    warn("⚠️ Không tìm được tên tower:", line)
                else
                    local cost = GetTowerPlaceCostByName(name)
                    local vector = x .. ", " .. y .. ", " .. z
                    table.insert(logs, {
                        TowerPlaceCost = tonumber(cost) or 0,
                        TowerPlaced = name,
                        TowerVector = vector,
                        Rotation = rot,
                        TowerA1 = tostring(a1)
                    })
                    print("[LOG] Place:", name, vector)
                end
            else
                -- UPGRADE
                local hash, path = line:match('TDX:upgradeTower%(([^,]+),%s*(%d),')
                if hash and path then
                    path = tonumber(path)
                    local tower = TowerClass.GetTowers()[hash]
                    local pos = hash2pos[hash]
                    if tower and pos then
                        if IsUpgradeSuccess(hash, path) then
                            table.insert(logs, {
                                UpgradeCost = 0,
                                UpgradePath = path,
                                TowerUpgraded = pos.x
                            })
                            print("[LOG] Upgrade:", hash, "path:", path)
                        else
                            print("[SKIP] Upgrade failed (no level increase):", hash)
                        end
                    else
                        print("[SKIP] Upgrade: tower or pos nil:", hash)
                    end
                end

                -- CHANGE TARGET
                local hash, qtype = line:match('TDX:changeQueryType%(([^,]+),%s*(%d)%)')
                if hash and qtype then
                    local pos = hash2pos[hash]
                    if pos then
                        table.insert(logs, {
                            ChangeTarget = pos.x,
                            TargetType = tonumber(qtype)
                        })
                        print("[LOG] ChangeTarget:", pos.x, qtype)
                    else
                        print("[SKIP] ChangeTarget pos nil:", hash)
                    end
                end

                -- SELL
                local hash = line:match('TDX:sellTower%(([^%)]+)%)')
                if hash then
                    local pos = hash2pos[hash]
                    if pos then
                        table.insert(logs, {
                            SellTower = pos.x
                        })
                        print("[LOG] Sell:", pos.x)
                    else
                        print("[SKIP] Sell pos nil:", hash)
                    end
                end
            end
        end

        writefile(outJson, HttpService:JSONEncode(logs))
        print("✅ Đã ghi vào:", outJson)
    end
    task.wait(0.22)
end
