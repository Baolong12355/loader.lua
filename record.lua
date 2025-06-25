local startTime = time()
local offset = 0
local fileName = "record.txt"  -- <--- Äáº¶T TĂN FILE Cá» Äá»NH á» ÄĂ‚Y

-- Náº¿u file Ä‘Ă£ tá»“n táº¡i thĂ¬ xĂ³a Ä‘á»ƒ táº¡o má»›i
if isfile(fileName) then
    delfile(fileName)
end
writefile(fileName, "")

-- HĂ m serialize giĂ¡ trá»‹
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

-- HĂ m serialize táº¥t cáº£ argument
local function serializeArgs(...)
    local args = {...}
    local output = {}
    for i, v in ipairs(args) do
        output[i] = serialize(v)
    end
    return table.concat(output, ", ")
end

-- HĂ m log thao tĂ¡c vĂ o file
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

print("âœ… Ghi macro TDX Ä‘Ă£ báº¯t Ä‘áº§u (luĂ´n dĂ¹ng tĂªn record.txt).")

-- Script rewrite macro TDX: Ă¡nh xáº¡ hash <-> vá»‹ trĂ­ liĂªn tá»¥c, láº¥y giĂ¡ nĂ¢ng cáº¥p Ä‘Ăºng, xuáº¥t macro runner dáº¡ng X

local txtFile = "record.txt"
local outJson = "tdx/macros/y.json"

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local HttpService = game:GetService("HttpService")
local PlayerScripts = player:WaitForChild("PlayerScripts")

-- HĂ m require an toĂ n
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

-- Láº¥y vá»‹ trĂ­ tower
local function GetTowerPosition(tower)
    if not tower or not tower.Character then return nil end
    local model = tower.Character:GetCharacterModel()
    local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
    return root and root.Position or nil
end

-- LĂ m Ä‘áº¹p sá»‘
local function floatfix(x)
    return tonumber(string.format("%.8g", tonumber(x)))
end

-- Láº¥y giĂ¡ Ä‘áº·t tower
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

-- Parse giĂ¡ nĂ¢ng cáº¥p path (láº¥y sá»‘ thĂ´i)
local function ParseUpgradeCost(costStr)
    local num = tostring(costStr):gsub("[^%d]", "")
    return tonumber(num) or 0
end

-- Láº¥y giĂ¡ nĂ¢ng cáº¥p hiá»‡n táº¡i (lá»c kĂ½ tá»± láº¡)
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

-- Ănh xáº¡ liĂªn tá»¥c hash <-> vá»‹ trĂ­
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
