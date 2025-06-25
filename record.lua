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

-- ⚙️ Rewrite từ record.txt -> y.json (macro chính thức)
local txtFile = "record.txt"
local outJson = "tdx/macros/y.json"

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local HttpService = game:GetService("HttpService")
local PlayerScripts = player:WaitForChild("PlayerScripts")

-- Require TowerClass (chuẩn)
local function SafeRequire(module)
    local ok, result = pcall(require, module)
    return ok and result or nil
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

-- Lấy giá đặt tower từ GUI
local function GetTowerPlaceCostByName(name)
    local playerGui = player:FindFirstChild("PlayerGui")
    local interface = playerGui and playerGui:FindFirstChild("Interface")
    local towersBar = interface and interface:FindFirstChild("BottomBar") and interface.BottomBar:FindFirstChild("TowersBar")
    if not towersBar then return 0 end

    for _, tower in ipairs(towersBar:GetChildren()) do
        if tower.Name == name then
            local costText = tower:FindFirstChild("CostFrame") and tower.CostFrame:FindFirstChild("CostText")
            if costText then
                local raw = tostring(costText.Text):gsub("%D", "")
                return tonumber(raw) or 0
            end
        end
    end
    return 0
end

-- Lấy UpgradeCost hiện tại của tower
local function GetUpgradeCost(tower, path)
    if not tower or not tower.LevelHandler then return 0 end
    local level = tower.LevelHandler:GetLevelOnPath(path)
    local ok, cost = pcall(function()
        return tower.LevelHandler:GetLevelUpgradeCost(path, 1)
    end)
    if ok and cost then
        return tonumber(cost) or 0
    end
    return 0
end

-- Ánh xạ hash -> pos liên tục
local hash2pos = {}
task.spawn(function()
    while true do
        local towers = TowerClass and TowerClass.GetTowers()
        for hash, tower in pairs(towers or {}) do
            local pos = GetTowerPosition(tower)
            if pos then
                hash2pos[tostring(hash)] = { x = pos.X, y = pos.Y, z = pos.Z }
            end
        end
        task.wait(0.1)
    end
end)

-- Đảm bảo thư mục tồn tại
if makefolder then
    pcall(function() makefolder("tdx") end)
    pcall(function() makefolder("tdx/macros") end)
end

-- Loop rewrite file
while true do
    if isfile(txtFile) then
        local macro = readfile(txtFile)
        local logs = {}

        for line in macro:gmatch("[^\r\n]+") do
            -- PlaceTower
            local x, name, y, rot, z, a1 = line:match('TDX:placeTower%(([^,]+),%s*"([^"]+)",%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)')
            if x and name and y and rot and z and a1 then
                local vector = string.format("%s, %s, %s", x, y, z)
                table.insert(logs, {
                    TowerPlaceCost = GetTowerPlaceCostByName(name),
                    TowerPlaced = name,
                    TowerVector = vector,
                    Rotation = tonumber(rot),
                    TowerA1 = a1
                })
            else
                -- UpgradeTower
                local hash, path = line:match('TDX:upgradeTower%(([^,]+),%s*([^%)]+)%)')
                if hash and path then
                    local pos = hash2pos[tostring(hash)]
                    local tower = TowerClass and TowerClass.GetTowers()[hash]
                    if pos then
                        table.insert(logs, {
                            UpgradeCost = GetUpgradeCost(tower, tonumber(path)),
                            UpgradePath = tonumber(path),
                            TowerUpgraded = pos.x -- không làm tròn, giữ nguyên số
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
    wait(0.2)
end
