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

-- Duy trì cache giá đặt tower (tên -> cost)
local function GetTowerPlaceCostByName(name)
    -- Lấy từ UI nếu có (TowersBar)
    local playerGui = player:FindFirstChild("PlayerGui")
    if playerGui then
        local interface = playerGui:FindFirstChild("Interface")
        local bottomBar = interface and interface:FindFirstChild("BottomBar")
        local towersBar = bottomBar and bottomBar:FindFirstChild("TowersBar")
        if towersBar then
            for _, tower in ipairs(towersBar:GetChildren()) do
                if tower.Name ~= "TowerTemplate" and not tower:IsA("UIGridLayout") then
                    local costFrame = tower:FindFirstChild("CostFrame")
                    local costText = costFrame and costFrame:FindFirstChild("CostText")
                    if costText and tower.Name == name then
                        local raw = tostring(costText.Text):gsub("%D", "")
                        return tonumber(raw) or 0
                    end
                end
            end
        end
    end
    return nil
end

-- Lấy TowerClass
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

local TowerClass = nil

-- Helper: giống mẫu
local function floatfix(x)
    return tonumber(string.format("%.15g", tonumber(x)))
end

-- Helper: parse vector "x, y, z"
local function parseVec(str)
    local x, y, z = str:match("([-0-9%.]+),%s*([-0-9%.]+),%s*([-0-9%.]+)")
    return x and tonumber(x), y and tonumber(y), z and tonumber(z)
end

-- Lấy giá nâng cấp thực tế (theo X, Path, Level)
local function getUpgradeCostByXandPath(xTarget, path)
    TowerClass = TowerClass or LoadTowerClass()
    if not TowerClass then return nil end
    for _, tower in pairs(TowerClass.GetTowers()) do
        local model = tower.Character and tower.Character:GetCharacterModel()
        local root = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
        if root and math.abs(root.Position.X - xTarget) < 0.1 then
            -- Lấy cost nâng cấp path hiện tại
            local lvl = tower.LevelHandler:GetLevelOnPath(path)
            local cost = tower.LevelHandler:GetLevelUpgradeCost(path, lvl+1)
            return cost
        end
    end
    return nil
end

-- Tự động chuyển đổi liên tục
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
                    realCost = GetTowerPlaceCostByName(towerName) or 0
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
                    local realCost = tonumber(ucost)
                    if not realCost or realCost == 0 then
                        realCost = getUpgradeCostByXandPath(floatfix(X), tonumber(path)) or 0
                    end
                    table.insert(logs, {
                        UpgradeCost = realCost,
                        UpgradePath = tonumber(path),
                        TowerUpgraded = floatfix(X)
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
        -- print("✅ [auto] Đã update macro " .. outJson)
    end
    wait(2)
end
