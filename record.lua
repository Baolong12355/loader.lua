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
end

local function floatfix(x)
    return tonumber(string.format("%.8g", tonumber(x)))
end

local function GetTowerPosition(tower)
    if not tower or not tower.Character then return nil end
    local model = tower.Character:GetCharacterModel()
    local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
    return root and root.Position or nil
end

local function ParseUpgradeCost(costStr)
    local num = tostring(costStr):gsub("[^%d]", "")
    return tonumber(num) or 0
end

local function GetUpgradeCost(tower, path)
    if not tower or not tower.LevelHandler then return 0 end
    local lvl = tower.LevelHandler:GetLevelOnPath(path)
    local ok, cost = pcall(function()
        return tower.LevelHandler:GetLevelUpgradeCost(path, lvl+1)
    end)
    if ok and cost then
        return ParseUpgradeCost(cost)
    end
    return 0
end

local function GetTowerPlaceCostByName(name)
    local playerGui = player:FindFirstChild("PlayerGui")
    if not playerGui then return 0 end
    local interface = playerGui:FindFirstChild("Interface")
    if not interface then return 0 end
    local bottomBar = interface:FindFirstChild("BottomBar")
    if not bottomBar then return 0 end
    local towersBar = bottomBar:FindFirstChild("TowersBar")
    if not towersBar then return 0 end
    for _, tower in ipairs(towersBar:GetChildren()) do
        if tower.Name == name then
            local costFrame = tower:FindFirstChild("CostFrame")
            local costText = costFrame and costFrame:FindFirstChild("CostText")
            if costText then
                local raw = tostring(costText.Text):gsub("%D", "")
                return tonumber(raw) or 0
            end
        end
    end
    return 0
end

-- Bảng ánh xạ hash -> giá nâng cấp hiện tại cho từng path
local upgradeCostSnapshot = {}

-- Cập nhật giá nâng cấp của tất cả tower hiện tại
local function UpdateUpgradeSnapshot()
    upgradeCostSnapshot = {}
    for hash, tower in pairs(TowerClass and TowerClass.GetTowers() or {}) do
        upgradeCostSnapshot[tostring(hash)] = {
            [1] = GetUpgradeCost(tower, 1),
            [2] = GetUpgradeCost(tower, 2),
            [3] = GetUpgradeCost(tower, 3)
        }
    end
end

-- Bảng ánh xạ hash -> vị trí
local hash2pos = {}

task.spawn(function()
    while true do
        for hash, tower in pairs(TowerClass and TowerClass.GetTowers() or {}) do
            local pos = GetTowerPosition(tower)
            if pos then
                hash2pos[tostring(hash)] = {x = floatfix(pos.X), y = floatfix(pos.Y), z = floatfix(pos.Z)}
            end
        end
        task.wait(0.1)
    end
end)

if makefolder then
    pcall(function() makefolder("tdx") end)
    pcall(function() makefolder("tdx/macros") end)
end

while true do
    if isfile(txtFile) then
        -- Cập nhật giá nâng cấp snapshot trước khi xử lý macro
        UpdateUpgradeSnapshot()

        local macro = readfile(txtFile)
        local logs = {}

        for line in macro:gmatch("[^\r\n]+") do
            -- PlaceTower
            local x, name, y, rot, z, a1 = line:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)')
            if x and name and y and rot and z and a1 then
                name = tostring(name):gsub('^%s*"(.-)"%s*$', '%1')
                local cost = GetTowerPlaceCostByName(name)
                local vector = string.format("%.8g, %.8g, %.8g", floatfix(x), floatfix(y), floatfix(z))
                table.insert(logs, {
                    TowerPlaceCost = cost,
                    TowerPlaced = name,
                    TowerVector = vector,
                    Rotation = floatfix(rot),
                    TowerA1 = tostring(floatfix(a1))
                })
            else
                -- UpgradeTower
                local hash, path, dummy = line:match('TDX:upgradeTower%(([^,]+),%s*([^,]+),%s*([^%)]+)%)')
                if hash and path then
                    local pos = hash2pos[tostring(hash)]
                    -- Lấy giá nâng cấp CŨ từ snapshot lưu trước khi nâng
                    local upgradeCost = upgradeCostSnapshot[tostring(hash)] and upgradeCostSnapshot[tostring(hash)][tonumber(path)] or 0
                    local tower = TowerClass and TowerClass.GetTowers()[hash]
                    if pos then
                        table.insert(logs, {
                            UpgradeCost = upgradeCost,
                            UpgradePath = tonumber(path),
                            TowerUpgraded = pos.x
                        })
                    end
                    -- Sau khi xử lý lệnh upgrade, cập nhật lại snapshot để chuẩn bị cho lần nâng tiếp theo!
                    UpdateUpgradeSnapshot()
                else
                    -- ChangeQueryType
                    local hash, targetType = line:match('TDX:changeQueryType%(([^,]+),%s*([^%)]+)%)')
                    if hash and targetType then
                        local pos = hash2pos[tostring(hash)]
                        if pos then
                            table.insert(logs, {
                                ChangeTarget = pos.x,
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
