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
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- Lấy TowerClass mỗi lần cần
local function SafeRequire(path)
    local ok, result = pcall(require, path)
    return ok and result or nil
end
local function LoadTowerClass()
    local ps = player:FindFirstChild("PlayerScripts")
    local client = ps and ps:FindFirstChild("Client")
    local gameClass = client and client:FindFirstChild("GameClass")
    local towerModule = gameClass and gameClass:FindFirstChild("TowerClass")
    return towerModule and SafeRequire(towerModule)
end

-- Helper lấy giá đặt từ UI realtime
local function GetTowerPlaceCostByName(name)
    local playerGui = player:FindFirstChild("PlayerGui")
    if playerGui then
        local interface = playerGui:FindFirstChild("Interface")
        local bottomBar = interface and interface:FindFirstChild("BottomBar")
        local towersBar = bottomBar and bottomBar:FindFirstChild("TowersBar")
        if towersBar then
            for _, tower in ipairs(towersBar:GetChildren()) do
                if tower.Name == name and tower:FindFirstChild("CostFrame") then
                    local costText = tower.CostFrame:FindFirstChild("CostText")
                    if costText then
                        local num = tonumber(costText.Text:match("%d+"))
                        if num then return num end
                    end
                end
            end
        end
    end
    return 0
end

local function floatfix(x)
    return tonumber(string.format("%.15g", tonumber(x)))
end

-- Lấy trạng thái tower hiện tại từ TowerClass mỗi khi cần
local function getUpgradeCostByXandPath(xTarget, path)
    local TowerClass = LoadTowerClass()
    if not TowerClass then return 0 end
    for _, tower in pairs(TowerClass.GetTowers()) do
        local model = tower.Character and tower.Character:GetCharacterModel()
        local root = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
        if root and math.abs(root.Position.X - xTarget) < 0.1 then
            local lvl = tower.LevelHandler:GetLevelOnPath(path)
            local cost = tower.LevelHandler:GetLevelUpgradeCost(path, lvl + 1)
            return cost or 0
        end
    end
    return 0
end

if makefolder then
    pcall(function() makefolder("tdx") end)
    pcall(function() makefolder("tdx/macros") end)
end

while true do
    if isfile(txtFile) then
        local macro = readfile(txtFile)
        local logs = {}
        for line in macro:gmatch("[^\r\n]+") do
            -- PlaceTower: TDX:placeTower("Name", Vector3.new(x, y, z), rot, a1, cost)
            local towerName, x, y, z, rot, a1, cost = line:match('TDX:placeTower%(%s*"([^"]+)",%s*Vector3%.new%(([^,]+),%s*([^,]+),%s*([^%)]+)%)%s*,%s*([^,]+),%s*([^,]+),%s*([^,%s%)]+)')
            if towerName and x and y and z and rot and a1 then
                local realCost = tonumber(cost)
                if not realCost or realCost == 0 then
                    realCost = GetTowerPlaceCostByName(towerName)
                end
                table.insert(logs, {
                    TowerPlaceCost = realCost,
                    TowerPlaced = towerName,
                    TowerVector = string.format("%s, %s, %s", floatfix(x), floatfix(y), floatfix(z)),
                    Rotation = tonumber(rot),
                    TowerA1 = tostring(a1)
                })
            else
                -- UpgradeTower: TDX:upgradeTower(X, path, cost)
                local X, path, ucost = line:match('TDX:upgradeTower%(([^,]+),%s*([^,]+),%s*([^%)]+)%)')
                if X and path then
                    local xVal = floatfix(X)
                    local pathNum = tonumber(path)
                    local realCost = tonumber(ucost)
                    if not realCost or realCost == 0 then
                        realCost = getUpgradeCostByXandPath(xVal, pathNum)
                    end
                    table.insert(logs, {
                        UpgradeCost = realCost,
                        UpgradePath = pathNum,
                        TowerUpgraded = xVal
                    })
                else
                    -- ChangeTarget: TDX:changeQueryType(X, targetType)
                    local X, targetType = line:match('TDX:changeQueryType%(([^,]+),%s*([^%)]+)%)')
                    if X and targetType then
                        table.insert(logs, {
                            ChangeTarget = floatfix(X),
                            TargetType = tonumber(targetType)
                        })
                    else
                        -- SellTower: TDX:sellTower(X)
                        local X = line:match('TDX:sellTower%(([^%)]+)%)')
                        if X then
                            table.insert(logs, {
                                SellTower = floatfix(X)
                            })
                        end
                    end
                end
            end
        end
        writefile(outJson, HttpService:JSONEncode(logs))
    end
    wait(2)
end
