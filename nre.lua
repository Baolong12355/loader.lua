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
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Load TowerClass
local TowerClass
do
    local client = PlayerScripts:FindFirstChild("Client")
    local gameClass = client and client:FindFirstChild("GameClass")
    local towerModule = gameClass and (gameClass:FindFirstChild("TowerClass") or gameClass:FindFirstChild("TowerModule"))
    TowerClass = towerModule and require(towerModule)
end

if not TowerClass then
    warn("Không thể load TowerClass")
    return
end

-- Hàm lấy giá đặt tháp từ UI
local function GetTowerPlaceCost(towerName)
    -- Kiểm tra các vị trí UI phổ biến
    local uiLocations = {
        player.PlayerGui:FindFirstChild("Interface") and player.PlayerGui.Interface:FindFirstChild("BottomBar"),
        player.PlayerGui:FindFirstChild("TowerSelect"),
        player.PlayerGui:FindFirstChild("BuildMenu")
    }
    
    for _, location in ipairs(uiLocations) do
        if location then
            local towerBar = location:FindFirstChild("TowersBar") or location:FindFirstChild("TowerContainer")
            if towerBar then
                for _, towerBtn in ipairs(towerBar:GetChildren()) do
                    if towerBtn.Name == towerName then
                        local costText = towerBtn:FindFirstChild("CostText") or 
                                        (towerBtn:FindFirstChild("CostFrame") and towerBtn.CostFrame:FindFirstChild("CostText"))
                        if costText then
                            local cost = tonumber(costText.Text:match("%d+"))
                            return cost or 0
                        end
                    end
                end
            end
        end
    end
    
    -- Fallback: Thử từ ReplicatedStorage nếu có config
    local towerConfig = ReplicatedStorage:FindFirstChild("TowerConfigs")
    if towerConfig then
        local config = towerConfig:FindFirstChild(towerName)
        if config and config:FindFirstChild("Cost") then
            return config.Cost.Value
        end
    end
    
    return 0
end

-- Cache system
local upgradeCache = {}
local function CacheCurrentLevels()
    for hash, tower in pairs(TowerClass.GetTowers()) do
        upgradeCache[tostring(hash)] = {}
        for path = 1, 2 do
            local success, level = pcall(function()
                return tower.LevelHandler:GetPathLevel(path)
                    or tower.LevelHandler:GetLevelOnPath(path)
                    or tower.LevelHandler:GetLevel(path)
            end)
            if success then
                upgradeCache[tostring(hash)][path] = level
            end
        end
    end
end

-- Position tracking
local hash2pos = {}
task.spawn(function()
    while true do
        for hash, tower in pairs(TowerClass.GetTowers()) do
            local success, pos = pcall(function()
                local model = tower.Character:GetCharacterModel()
                local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
                return root and root.Position
            end)
            if success and pos then
                hash2pos[tostring(hash)] = {
                    x = math.floor(pos.X * 100)/100,
                    y = math.floor(pos.Y * 100)/100,
                    z = math.floor(pos.Z * 100)/100
                }
            end
        end
        task.wait(0.1)
    end
end)

-- Tạo thư mục nếu cần
if makefolder then
    pcall(makefolder, "tdx")
    pcall(makefolder, "tdx/macros")
end

-- Main conversion loop
while true do
    if isfile(txtFile) then
        local logs = {}
        CacheCurrentLevels()
        
        for line in readfile(txtFile):gmatch("[^\r\n]+") do
            -- PLACE command
            local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*"([^"]+)",%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)')
            if a1 and name and x and y and z and rot then
                local placeCost = GetTowerPlaceCost(name)
                table.insert(logs, {
                    action = "place",
                    TowerPlaceCost = placeCost,
                    TowerPlaced = name,
                    TowerVector = string.format("%.2f, %.2f, %.2f", tonumber(x), tonumber(y), tonumber(z)),
                    Rotation = tonumber(rot),
                    TowerA1 = a1
                })
            end
            
            -- UPGRADE command
            local hash, path = line:match('TDX:upgradeTower%(([^,]+),%s*(%d)%)')
            if hash and path then
                path = tonumber(path)
                task.wait(0.15) -- Chờ hệ thống xử lý nâng cấp
                
                local tower = TowerClass.GetTowers()[hash]
                if tower then
                    local success, newLevel = pcall(function()
                        return tower.LevelHandler:GetPathLevel(path)
                            or tower.LevelHandler:GetLevelOnPath(path)
                            or tower.LevelHandler:GetLevel(path)
                    end)
                    
                    if success and upgradeCache[tostring(hash)] and newLevel and (newLevel > (upgradeCache[tostring(hash)][path] or 0)) then
                        local pos = hash2pos[tostring(hash)]
                        if pos then
                            table.insert(logs, {
                                action = "upgrade",
                                UpgradePath = path,
                                TowerUpgraded = pos.x,
                                NewLevel = newLevel
                            })
                        end
                    end
                end
            end
            
            -- SELL command
            local hash = line:match('TDX:sellTower%(([^%)]+)%)')
            if hash and hash2pos[tostring(hash)] then
                table.insert(logs, {
                    action = "sell",
                    SellTower = hash2pos[tostring(hash)].x
                })
            end
            
            -- CHANGE TARGET command
            local hash, qtype = line:match('TDX:changeQueryType%(([^,]+),%s*(%d)%)')
            if hash and qtype and hash2pos[tostring(hash)] then
                table.insert(logs, {
                    action = "change_target",
                    TargetType = tonumber(qtype),
                    Position = hash2pos[tostring(hash)].x
                })
            end
        end
        
        if #logs > 0 then
            writefile(outJson, HttpService:JSONEncode(logs))
            print("Đã ghi", #logs, "bản ghi vào", outJson)
        end
    end
    task.wait(1)
end
