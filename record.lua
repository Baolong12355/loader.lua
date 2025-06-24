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

local TDX_Shared = game:GetService("ReplicatedStorage"):WaitForChild("TDX_Shared")
local Common = TDX_Shared:WaitForChild("Common")
local ResourceManager = require(Common:WaitForChild("ResourceManager"))

-- Lấy giá đặt tower từ GUI
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

-- Lấy giá nâng cấp từ config
local function GetUpgradeCost(towerName, path, targetLevel, discount)
    local towerConfig = ResourceManager.GetTowerConfig(towerName)
    if not towerConfig then return 0 end
    local pathData = towerConfig.UpgradePathData["Path"..path.."Data"]
    if not pathData then return 0 end
    local upgradeInfo = pathData[targetLevel]
    if not upgradeInfo then return 0 end
    local baseCost = upgradeInfo.Cost
    local finalCost = baseCost * (1 - (discount or 0))
    finalCost = math.floor(finalCost)
    return finalCost
end

-- Map x (tọa độ X) -> thông tin đặt tower
local x2tower = {}

if makefolder then
    pcall(function() makefolder("tdx") end)
    pcall(function() makefolder("tdx/macros") end)
end

while true do
    if isfile(txtFile) then
        local macro = readfile(txtFile)
        local logs = {}
        local macroLines = {}
        for l in macro:gmatch("[^\r\n]+") do table.insert(macroLines, l) end

        for idx, line in ipairs(macroLines) do
            -- PlaceTower: log x2tower
            local x, name, y, rot, z, a1 = line:match('TDX:placeTower%(([^,]+),%s*"([^"]+)",%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)')
            if x and name and y and rot and z and a1 then
                local fx = tonumber(x)
                x2tower[fx] = {name=name, y=tonumber(y), z=tonumber(z), rot=tonumber(rot), a1=a1}
                local cost = GetTowerPlaceCostByName(name)
                table.insert(logs, {
                    TowerPlaceCost = cost,
                    TowerPlaced = name,
                    TowerVector = string.format("%.8g, %.8g, %.8g", fx, tonumber(y), tonumber(z)),
                    Rotation = tonumber(rot),
                    TowerA1 = tostring(a1)
                })
            else
                -- UpgradeTower: log UpgradeCost, UpgradePath, TowerUpgraded = x
                local x, path, levelBefore, discount = line:match('TDX:upgradeTower%(([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)')
                if x and path and levelBefore then
                    local fx = tonumber(x)
                    local towerInfo = x2tower[fx]
                    if towerInfo then
                        local upgradeCost = GetUpgradeCost(towerInfo.name, tonumber(path), tonumber(levelBefore)+1, tonumber(discount) or 0)
                        table.insert(logs, {
                            UpgradeCost = upgradeCost,
                            UpgradePath = tonumber(path),
                            TowerUpgraded = fx
                        })
                    end
                else
                    -- SellTower: log SellTower = x
                    local x = line:match('TDX:sellTower%(([^%)]+)%)')
                    if x then
                        local fx = tonumber(x)
                        if x2tower[fx] then
                            table.insert(logs, {
                                SellTower = fx
                            })
                        end
                    else
                        -- ChangeTarget: log TowerTargetChange = x, TargetWanted, TargetChangedAt
                        local x, target, tick = line:match('TDX:changeQueryType%(([^,]+),%s*([^,]+),%s*([^%)]+)%)')
                        if x and target and tick then
                            local fx = tonumber(x)
                            if x2tower[fx] then
                                table.insert(logs, {
                                    TowerTargetChange = fx,
                                    TargetWanted = tonumber(target),
                                    TargetChangedAt = tonumber(tick)
                                })
                            end
                        end
                    end
                end
            end
        end

        writefile(outJson, HttpService:JSONEncode(logs))
    end
    wait(0.15)
end
