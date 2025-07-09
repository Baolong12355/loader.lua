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

-- Lấy vị trí tower
local function GetTowerPosition(tower)
    if not tower or not tower.Character then return nil end
    local model = tower.Character:GetCharacterModel()
    local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
    return root and root.Position or nil
end

-- Lấy giá đặt tower
local function GetTowerPlaceCostByName(name)
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return 0 end
    local interface = gui:FindFirstChild("Interface")
    local bottomBar = interface and interface:FindFirstChild("BottomBar")
    local towersBar = bottomBar and bottomBar:FindFirstChild("TowersBar")
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

-- Lấy cấp tower hiện tại
local function GetLevel(tower, path)
    if not tower or not tower.LevelHandler then return 0 end
    local ok, lvl = pcall(function()
        return tower.LevelHandler:GetLevelOnPath(path)
    end)
    return (ok and lvl) or 0
end

-- Tìm tower theo hash
local function GetTowerByHash(hash)
    return TowerClass and TowerClass.GetTowers() and TowerClass.GetTowers()[hash]
end

-- Tìm vị trí theo hash
local function GetPositionByHash(hash)
    local tower = GetTowerByHash(hash)
    return tower and GetTowerPosition(tower)
end

-- Tạo thư mục nếu chưa có
if makefolder then
    pcall(function() makefolder("tdx") end)
    pcall(function() makefolder("tdx/macros") end)
end

print("✅ Convert bắt đầu...")

while true do
    if isfile(txtFile) then
        local macro = readfile(txtFile)
        local logs = {}

        for line in macro:gmatch("[^\r\n]+") do
            local parsed = false

            -- PLACE
            local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*"([^"]+)",%s*([%d%.%-]+),%s*([%d%.%-]+),%s*([%d%.%-]+),%s*([%d%.%-]+)%)')
            if a1 and name and x and y and z and rot then
                table.insert(logs, {
                    TowerA1 = a1,
                    TowerPlaced = name,
                    TowerVector = x .. ", " .. y .. ", " .. z,
                    Rotation = rot,
                    TowerPlaceCost = GetTowerPlaceCostByName(name)
                })
                parsed = true
            end

            -- UPGRADE
            if not parsed then
                local hash, path = line:match('TDX:upgradeTower%(([^,]+),%s*(%d),')
                if hash and path then
                    local tower = GetTowerByHash(hash)
                    local pos = GetPositionByHash(hash)
                    local pathNum = tonumber(path)
                    if tower and pos then
                        local before = GetLevel(tower, pathNum)
                        task.wait(0.1)
                        local after = GetLevel(tower, pathNum)
                        if after > before then
                            table.insert(logs, {
                                UpgradeCost = 0,
                                UpgradePath = pathNum,
                                TowerUpgraded = pos.X
                            })
                        end
                    end
                    parsed = true
                end
            end

            -- TARGET
            if not parsed then
                local hash, targetType = line:match('TDX:changeQueryType%(([^,]+),%s*(%d)%)')
                if hash and targetType then
                    local pos = GetPositionByHash(hash)
                    if pos then
                        table.insert(logs, {
                            ChangeTarget = pos.X,
                            TargetType = tonumber(targetType)
                        })
                    end
                    parsed = true
                end
            end

            -- SELL
            if not parsed then
                local hash = line:match('TDX:sellTower%(([^%)]+)%)')
                if hash then
                    local pos = GetPositionByHash(hash)
                    if pos then
                        table.insert(logs, {
                            SellTower = pos.X
                        })
                    end
                end
            end
        end

        writefile(outJson, HttpService:JSONEncode(logs))
    end
    wait(0.22)
end
