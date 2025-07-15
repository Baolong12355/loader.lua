local ReplicatedStorage = game:GetService("ReplicatedStorage")
local fileName = "record.txt"
local offset = 0
local startTime = time()

-- Reset file
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

local function serializeArgs(args)
    local output = {}
    for i, v in ipairs(args) do
        output[i] = serialize(v)
    end
    return table.concat(output, ", ")
end

-- Tạm lưu thao tác chờ xác nhận
local pending = {
    PlaceTower = {},
    SellTower = {},
    TowerUpgradeRequest = {},
    ChangeQueryType = {}
}

-- Hook FireServer để lưu thao tác chờ xác nhận
local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
    local args = {...}
    local name = tostring(self.Name)
    if pending[name] then
        table.insert(pending[name], {
            time = time(),
            args = args
        })
    end
    return oldFireServer(self, unpack(args))
end)

-- Hook InvokeServer để lưu thao tác chờ xác nhận
local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
    local args = {...}
    local name = tostring(self.Name)
    if pending[name] then
        table.insert(pending[name], {
            time = time(),
            args = args
        })
    end
    return oldInvokeServer(self, unpack(args))
end)

-- Xác nhận từ server: Place & Sell
local TowerFactoryQueueUpdated = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerFactoryQueueUpdated")
TowerFactoryQueueUpdated.OnClientEvent:Connect(function(data)
    for _, v in ipairs(data) do
        local info = v.Data[1]
        if typeof(info) == "table" then
            -- PLACE (có Vector3)
            local foundVector = false
            for _, field in pairs(info) do
                if typeof(field) == "Vector3" then
                    foundVector = true
                    break
                end
            end
            if foundVector and #pending.PlaceTower > 0 then
                -- Ghi thao tác Place (lấy thao tác gần nhất)
                local entry = table.remove(pending.PlaceTower, 1)
                local waitTime = (entry.time - offset) - startTime
                appendfile(fileName, ("task.wait(%s)\nTDX:placeTower(%s)\n"):format(waitTime, serializeArgs(entry.args)))
                startTime = entry.time - offset
            end
        else
            -- SELL (không có Vector3)
            if #pending.SellTower > 0 then
                local entry = table.remove(pending.SellTower, 1)
                local waitTime = (entry.time - offset) - startTime
                appendfile(fileName, ("task.wait(%s)\nTDX:sellTower(%s)\n"):format(waitTime, serializeArgs(entry.args)))
                startTime = entry.time - offset
            end
        end
    end
end)

-- Xác nhận từ server: Upgrade
local TowerUpgradeQueueUpdated = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUpgradeQueueUpdated")
TowerUpgradeQueueUpdated.OnClientEvent:Connect(function(data)
    if #pending.TowerUpgradeRequest > 0 then
        local entry = table.remove(pending.TowerUpgradeRequest, 1)
        local waitTime = (entry.time - offset) - startTime
        appendfile(fileName, ("task.wait(%s)\nTDX:upgradeTower(%s)\n"):format(waitTime, serializeArgs(entry.args)))
        startTime = entry.time - offset
    end
end)

-- Xác nhận từ server: Change target/query
local TowerQueryTypeIndexChanged = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerQueryTypeIndexChanged")
TowerQueryTypeIndexChanged.OnClientEvent:Connect(function(data)
    if #pending.ChangeQueryType > 0 then
        local entry = table.remove(pending.ChangeQueryType, 1)
        local waitTime = (entry.time - offset) - startTime
        appendfile(fileName, ("task.wait(%s)\nTDX:changeQueryType(%s)\n"):format(waitTime, serializeArgs(entry.args)))
        startTime = entry.time - offset
    end
end)

print("✅ Macro recorder TDX chỉ ghi thao tác thành công vào record.txt!")

-- Nếu muốn chuyển đổi sang macro runner/JSON thì giữ nguyên phần sau
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
