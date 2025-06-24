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

local function SafeRequire(module)
    local success, result = pcall(require, module)
    if not success then
        print("[DEBUG] SafeRequire fail for module:", module, "Error:", result)
    end
    return success and result or nil
end

-- Load TowerClass
local TowerClass
do
    local client = PlayerScripts:WaitForChild("Client")
    print("[DEBUG] client loaded:", client)
    local gameClass = client:WaitForChild("GameClass")
    print("[DEBUG] gameClass loaded:", gameClass)
    local towerModule = gameClass:WaitForChild("TowerClass")
    print("[DEBUG] towerModule loaded:", towerModule)
    TowerClass = SafeRequire(towerModule)
    print("[DEBUG] TowerClass required:", TowerClass)
end

local function floatfix(x)
    return tonumber(string.format("%.8g", tonumber(x)))
end

local function GetTowerPosition(tower)
    if not tower then print("[DEBUG] GetTowerPosition: tower nil") return nil end
    if not tower.Character then print("[DEBUG] GetTowerPosition: tower.Character nil") return nil end
    local model = tower.Character:GetCharacterModel()
    if not model then print("[DEBUG] GetTowerPosition: model nil") return nil end
    local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
    if not root then print("[DEBUG] GetTowerPosition: root nil") return nil end
    return root.Position
end

local function ParseUpgradeCost(costStr)
    local num = tostring(costStr):gsub("[^%d]", "")
    if not num or num == "" then print("[DEBUG] ParseUpgradeCost fail:", costStr) end
    return tonumber(num) or 0
end

local function GetUpgradeCost(tower, path)
    if not tower then print("[DEBUG] GetUpgradeCost: tower nil") return 0 end
    if not tower.LevelHandler then print("[DEBUG] GetUpgradeCost: tower.LevelHandler nil") return 0 end
    local lvl = tower.LevelHandler:GetLevelOnPath(path)
    local ok, cost = pcall(function()
        return tower.LevelHandler:GetLevelUpgradeCost(path, lvl+1)
    end)
    if not ok then print("[DEBUG] GetUpgradeCost: pcall fail", cost) end
    if ok and cost then
        local parsed = ParseUpgradeCost(cost)
        print("[DEBUG] GetUpgradeCost:", "path", path, "lvl", lvl, "raw", cost, "parsed", parsed)
        return parsed
    end
    print("[DEBUG] GetUpgradeCost: fallback 0")
    return 0
end

local function GetTowerPlaceCostByName(name)
    local playerGui = player:FindFirstChild("PlayerGui")
    if not playerGui then print("[DEBUG] PlayerGui nil") return 0 end
    local interface = playerGui:FindFirstChild("Interface")
    if not interface then print("[DEBUG] Interface nil") return 0 end
    local bottomBar = interface:FindFirstChild("BottomBar")
    if not bottomBar then print("[DEBUG] BottomBar nil") return 0 end
    local towersBar = bottomBar:FindFirstChild("TowersBar")
    if not towersBar then print("[DEBUG] TowersBar nil") return 0 end
    for _, tower in ipairs(towersBar:GetChildren()) do
        if tower.Name == name then
            local costFrame = tower:FindFirstChild("CostFrame")
            local costText = costFrame and costFrame:FindFirstChild("CostText")
            if costText then
                local raw = tostring(costText.Text):gsub("%D", "")
                print("[DEBUG] PlaceCost for", name, "is", raw)
                return tonumber(raw) or 0
            end
        end
    end
    print("[DEBUG] Tower", name, "not found in TowersBar")
    return 0
end

local upgradeCostSnapshot = {}

local function UpdateUpgradeSnapshot()
    print("[DEBUG] Updating upgradeCostSnapshot...")
    upgradeCostSnapshot = {}
    local towers = TowerClass and TowerClass.GetTowers() or {}
    print("[DEBUG] Tower list in UpdateUpgradeSnapshot:", towers)
    for hash, tower in pairs(towers) do
        print("[DEBUG] Snapshot tower hash:", hash, "object:", tower)
        upgradeCostSnapshot[tostring(hash)] = {
            [1] = GetUpgradeCost(tower, 1),
            [2] = GetUpgradeCost(tower, 2),
            [3] = GetUpgradeCost(tower, 3)
        }
    end
    print("[DEBUG] upgradeCostSnapshot:", upgradeCostSnapshot)
end

local hash2pos = {}

task.spawn(function()
    while true do
        local towers = TowerClass and TowerClass.GetTowers() or {}
        for hash, tower in pairs(towers) do
            local pos = GetTowerPosition(tower)
            if pos then
                hash2pos[tostring(hash)] = {x = floatfix(pos.X), y = floatfix(pos.Y), z = floatfix(pos.Z)}
                print("[DEBUG] hash2pos updated:", hash, hash2pos[tostring(hash)])
            else
                print("[DEBUG] No position for tower hash:", hash)
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
    print("[DEBUG] Loop tick...")
    if isfile(txtFile) then
        print("[DEBUG] Found", txtFile)
        UpdateUpgradeSnapshot()
        local macro = readfile(txtFile)
        print("[DEBUG] Macro content:", macro)
        local logs = {}
        local lineCount = 0

        for line in macro:gmatch("[^\r\n]+") do
            lineCount = lineCount + 1
            print("[DEBUG] Processing line", lineCount, ":", line)
            -- PlaceTower
            local x, name, y, rot, z, a1 = line:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)')
            if x and name and y and rot and z and a1 then
                print("[DEBUG] Match placeTower:", x, name, y, rot, z, a1)
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
                    print("[DEBUG] Match upgradeTower:", hash, path, dummy)
                    local pos = hash2pos[tostring(hash)]
                    print("[DEBUG] Tower pos for upgrade:", pos)
                    local upgradeCost = upgradeCostSnapshot[tostring(hash)] and upgradeCostSnapshot[tostring(hash)][tonumber(path)] or 0
                    print("[DEBUG] Upgrade cost for hash", hash, "path", path, ":", upgradeCost)
                    if pos then
                        table.insert(logs, {
                            UpgradeCost = upgradeCost,
                            UpgradePath = tonumber(path),
                            TowerUpgraded = pos.x
                        })
                    else
                        print("[DEBUG] No position for upgradeTower hash:", hash)
                    end
                    UpdateUpgradeSnapshot()
                else
                    -- ChangeQueryType
                    local hash, targetType = line:match('TDX:changeQueryType%(([^,]+),%s*([^%)]+)%)')
                    if hash and targetType then
                        print("[DEBUG] Match changeQueryType:", hash, targetType)
                        local pos = hash2pos[tostring(hash)]
                        if pos then
                            table.insert(logs, {
                                ChangeTarget = pos.x,
                                TargetType = tonumber(targetType)
                            })
                        else
                            print("[DEBUG] No position for changeQueryType hash:", hash)
                        end
                    else
                        -- SellTower
                        local hash = line:match('TDX:sellTower%(([^%)]+)%)')
                        if hash then
                            print("[DEBUG] Match sellTower:", hash)
                            local pos = hash2pos[tostring(hash)]
                            if pos then
                                table.insert(logs, {
                                    SellTower = pos.x
                                })
                            else
                                print("[DEBUG] No position for sellTower hash:", hash)
                            end
                        else
                            print("[DEBUG] No match for line:", line)
                        end
                    end
                end
            end
        end

        print("[DEBUG] Total lines processed:", lineCount)
        print("[DEBUG] Logs to write:", HttpService:JSONEncode(logs))
        writefile(outJson, HttpService:JSONEncode(logs))
        print("[DEBUG] Written to", outJson)
    else
        print("[DEBUG] File", txtFile, "not found!")
    end
    wait(0.22)
end
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
