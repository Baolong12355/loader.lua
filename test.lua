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

-- Load TowerClass
local TowerClass
do
    local client = PlayerScripts:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    TowerClass = SafeRequire(towerModule)
end

-- Lấy vị trí của tower
local function GetTowerPosition(tower)
    if not tower or not tower.Character then return nil end
    local model = tower.Character:GetCharacterModel()
    local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
    return root and root.Position or nil
end

-- Hàm lấy giá nâng cấp hiện tại
local function GetCurrentUpgradeCosts(tower)
    if not tower or not tower.LevelHandler then
        return {
            path1 = {cost = "N/A", currentLevel = "N/A", maxLevel = "N/A", exists = true},
            path2 = {cost = "N/A", currentLevel = "N/A", maxLevel = "N/A", exists = false}
        }
    end

    local result = {
        path1 = {cost = "MAX", currentLevel = 0, maxLevel = 0, exists = true},
        path2 = {cost = "MAX", currentLevel = 0, maxLevel = 0, exists = false}
    }

    local maxLevel = tower.LevelHandler:GetMaxLevel()
    local currentLvl1 = tower.LevelHandler:GetLevelOnPath(1)
    result.path1.currentLevel = currentLvl1
    result.path1.maxLevel = maxLevel

    if currentLvl1 < maxLevel then
        local success, cost = pcall(function()
            return tower.LevelHandler:GetLevelUpgradeCost(1, 1)
        end)
        if success then result.path1.cost = math.floor(cost) else result.path1.cost = "LỖI" end
    end

    local hasPath2 = pcall(function()
        return tower.LevelHandler:GetLevelOnPath(2) ~= nil
    end)

    if hasPath2 then
        result.path2.exists = true
        local currentLvl2 = tower.LevelHandler:GetLevelOnPath(2)
        result.path2.currentLevel = currentLvl2
        result.path2.maxLevel = maxLevel

        if currentLvl2 < maxLevel then
            local success, cost = pcall(function()
                return tower.LevelHandler:GetLevelUpgradeCost(2, 1)
            end)
            if success then result.path2.cost = math.floor(cost) else result.path2.cost = "LỖI" end
        end
    end

    return result
end

-- ánh xạ hash → vị trí
local hash2pos = {}
task.spawn(function()
    while true do
        for hash, tower in pairs(TowerClass.GetTowers()) do
            local pos = GetTowerPosition(tower)
            if pos then
                hash2pos[tostring(hash)] = {x = pos.X, y = pos.Y, z = pos.Z}
            end
        end
        task.wait(0.1)
    end
end)

-- Ghi file macro
if makefolder then
    pcall(function() makefolder("tdx") end)
    pcall(function() makefolder("tdx/macros") end)
end

-- Vòng lặp convert
while true do
    if isfile(txtFile) then
        local macro = readfile(txtFile)
        local logs = {}

        for line in macro:gmatch("[^\r\n]+") do
            local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)')
            if a1 and name and x and y and z and rot then
                name = tostring(name):gsub('^%s*"(.-)"%s*$', '%1')
                local vector = x .. ", " .. y .. ", " .. z
                table.insert(logs, {
                    TowerPlaceCost = 0,
                    TowerPlaced = name,
                    TowerVector = vector,
                    Rotation = rot,
                    TowerA1 = tostring(a1)
                })

            else
                local hash, path = line:match('TDX:upgradeTower%(([^,]+),%s*([^,]+),%s*[^%)]+%)')
                if hash and path then
                    local pathNum = tonumber(path)
                    local tower = TowerClass.GetTowers()[hash]
                    local pos = hash2pos[tostring(hash)]

                    if tower and pos then
                        local info = GetCurrentUpgradeCosts(tower)
                        local pathInfo = pathNum == 1 and info.path1 or info.path2
                        local before = pathInfo.currentLevel
                        task.wait(0.1)
                        local after = tower.LevelHandler:GetLevelOnPath(pathNum)
                        if after > before then
                            table.insert(logs, {
                                UpgradeCost = 0,
                                UpgradePath = pathNum,
                                TowerUpgraded = pos.x
                            })
                            print(string.format("✅ Upgrade OK: X=%.2f | Path=%d | %d → %d", pos.x, pathNum, before, after))
                        else
                            print(string.format("⛔ Bỏ ghi upgrade: X=%.2f | Không tăng cấp", pos.x or 0))
                        end
                    else
                        print("[WARNING] Không tìm thấy tower từ hash:", hash)
                    end

                else
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
        print("✅ Macro đã được ghi vào:", outJson)
    end
    wait(0.22)
end
