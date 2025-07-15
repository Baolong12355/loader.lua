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

local function serializeArgs(...)
    local args = {...}
    local output = {}
    for i, v in ipairs(args) do
        output[i] = serialize(v)
    end
    return table.concat(output, ", ")
end

-- Ghi log vào file
local function log(method, self, serializedArgs, upgradeSuccess)
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
        -- Chỉ ghi lại nâng cấp nếu upgradeSuccess là true
        if upgradeSuccess then
            appendfile(fileName, "task.wait(" .. ((time() - offset) - startTime) .. ")\n")
            appendfile(fileName, "TDX:upgradeTower(" .. serializedArgs .. ")\n")
            startTime = time() - offset
        end

    elseif name == "ChangeQueryType" then
        appendfile(fileName, "task.wait(" .. ((time() - offset) - startTime) .. ")\n")
        appendfile(fileName, "TDX:changeQueryType(" .. serializedArgs .. ")\n")
        startTime = time() - offset
    end
end

-- Hook FireServer
local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
    local args = {...}
    local serialized = serializeArgs(...)
    -- Nếu là upgrade thì kiểm tra kết quả trả về (giả sử trả về true nếu thành công)
    if tostring(self.Name) == "TowerUpgradeRequest" then
        local upgradeSuccess = oldFireServer(self, unpack(args))
        log("FireServer", self, serialized, upgradeSuccess)
        return upgradeSuccess
    else
        log("FireServer", self, serialized)
        return oldFireServer(self, unpack(args))
    end
end)

-- Hook InvokeServer
local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
    local args = {...}
    local serialized = serializeArgs(...)
    if tostring(self.Name) == "TowerUpgradeRequest" then
        local upgradeSuccess = oldInvokeServer(self, unpack(args))
        log("InvokeServer", self, serialized, upgradeSuccess)
        return upgradeSuccess
    else
        log("InvokeServer", self, serialized)
        return oldInvokeServer(self, unpack(args))
    end
end)

-- Hook __namecall
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    local args = {...}
    local serialized = serializeArgs(...)
    if method == "FireServer" or method == "InvokeServer" then
        if tostring(self.Name) == "TowerUpgradeRequest" then
            local upgradeSuccess = oldNamecall(self, unpack(args))
            log(method, self, serialized, upgradeSuccess)
            return upgradeSuccess
        else
            log(method, self, serialized)
            return oldNamecall(self, unpack(args))
        end
    end
    return oldNamecall(self, unpack(args))
end)

print("✅ Ghi macro TDX đã bắt đầu (chỉ ghi nâng cấp thành công vào record.txt).")

-- Phần chuyển đổi sang macro runner giữ nguyên như cũ
-- ... (phần chuyển đổi macro sang JSON)
-- Script chuyển đổi record.txt thành macro runner (dùng trục X), với thứ tự trường upgrade là: UpgradeCost, UpgradePath, TowerUpgraded
-- Đặt script này trong môi trường Roblox hoặc môi trường hỗ trợ các API Roblox tương ứng

local txtFile = "record.txt"
local outJson = "tdx/macros/x.json"

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local HttpService = game:GetService("HttpService")
local PlayerScripts = player:WaitForChild("PlayerScripts")

-- Safe require tower module
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

local function GetTowerPosition(tower)
    if not tower or not tower.Character then return nil end
    local model = tower.Character:GetCharacterModel()
    local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
    return root and root.Position or nil
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

-- Ánh xạ hash -> pos liên tục
local hash2pos = {}
task.spawn(function()
    while true do
        for hash, tower in pairs(TowerClass and TowerClass.GetTowers() or {}) do
            local pos = GetTowerPosition(tower)
            if pos then
                hash2pos[tostring(hash)] = {x = pos.X, y = pos.Y, z = pos.Z}
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
        local macro = readfile(txtFile)
        local logs = {}

        for line in macro:gmatch("[^\r\n]+") do
            -- Đặt tower: a1, name, x, y, z, rot
            local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)')
            if a1 and name and x and y and z and rot then
                name = tostring(name):gsub('^%s*"(.-)"%s*$', '%1')
                local cost = GetTowerPlaceCostByName(name)
                local vector = x .. ", " .. y .. ", " .. z
                table.insert(logs, {
                    TowerPlaceCost = tonumber(cost) or 0,
                    TowerPlaced = name,
                    TowerVector = vector,
                    Rotation = rot,
                    TowerA1 = tostring(a1)
                })
            else
                -- Nâng cấp tower: chuyển đổi đúng thứ tự UpgradeCost, UpgradePath, TowerUpgraded (X)
                local hash, path = line:match('TDX:upgradeTower%(([^,]+),%s*([^,]+),%s*[^%)]+%)')
                if hash and path then
                    local pos = hash2pos[tostring(hash)]
                    local tower = TowerClass and TowerClass.GetTowers()[hash]
                    local upgradeCost = GetUpgradeCost(tower, tonumber(path))
                    if pos then
                        table.insert(logs, {
                            UpgradeCost = upgradeCost,
                            UpgradePath = tonumber(path),
                            TowerUpgraded = pos.x
                        })
                    end
                else
                    -- Đổi target
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
                        -- Bán tower
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
