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

-- Helper
local function floatfix(x)
    return tonumber(string.format("%.15g", tonumber(x)))
end

-- TowerClass lấy 1 lần
local function SafeRequire(path) local ok, result = pcall(require, path) return ok and result or nil end
local function LoadTowerClass()
    local ps = player:FindFirstChild("PlayerScripts")
    local client = ps and ps:FindFirstChild("Client")
    local gameClass = client and client:FindFirstChild("GameClass")
    local towerModule = gameClass and gameClass:FindFirstChild("TowerClass")
    return towerModule and SafeRequire(towerModule)
end
local TowerClass = LoadTowerClass()
if not TowerClass then error("Không load được TowerClass!") end

-- Lấy giá đặt từ UI (chỉ khi thiếu)
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

-- Cache trạng thái tower: { [X] = {Name=..., Level={[1]=..., [2]=...}} }
local towerCache = {}

-- Main chuyển đổi
local macro = readfile(txtFile)
local logs = {}
for line in macro:gmatch("[^\r\n]+") do
    -- PlaceTower: TDX:placeTower("Name", Vector3.new(x, y, z), rot, a1, cost)
    local towerName, x, y, z, rot, a1, cost = line:match('TDX:placeTower%(%s*"([^"]+)",%s*Vector3%.new%(([^,]+),%s*([^,]+),%s*([^%)]+)%)%s*,%s*([^,]+),%s*([^,]+),%s*([^,%s%)]+)')
    if towerName and x and y and z and rot and a1 then
        local towerX = floatfix(x)
        local realCost = tonumber(cost)
        if not realCost or realCost == 0 then
            realCost = GetTowerPlaceCostByName(towerName)
        end
        -- Khi đặt mới tower, cache trạng thái: level path 1, 2 = 0
        towerCache[towerX] = {Name=towerName, Level={[1]=0, [2]=0}}
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
            local towerX = floatfix(X)
            local pathNum = tonumber(path)
            -- Cache phải có towerX
            local tw = towerCache[towerX]
            local realCost = tonumber(ucost)
            -- Nếu thiếu giá, tự tra lookup đúng level
            if not realCost or realCost == 0 then
                if tw then
                    local towerDef = TowerClass.TowerNameMap[tw.Name]
                    if towerDef and towerDef.LevelHandler then
                        local nextLevel = (tw.Level[pathNum] or 0) + 1
                        -- Lấy giá nâng cấp đúng path/level
                        realCost = towerDef.LevelHandler:GetLevelUpgradeCost(pathNum, nextLevel)
                    end
                end
            end
            table.insert(logs, {
                UpgradeCost = realCost or 0,
                UpgradePath = pathNum,
                TowerUpgraded = towerX
            })
            -- Sau khi nâng cấp, cập nhật level path cache
            if tw then tw.Level[pathNum] = (tw.Level[pathNum] or 0) + 1 end
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
                    local towerX = floatfix(X)
                    table.insert(logs, {
                        SellTower = towerX
                    })
                    -- Xoá khỏi cache
                    towerCache[towerX] = nil
                end
            end
        end
    end
end

writefile(outJson, HttpService:JSONEncode(logs))
print("✅ Đã tạo macro " .. outJson .. " (cache đầy đủ trạng thái tower, luôn đúng giá upgrade và giá đặt)")
