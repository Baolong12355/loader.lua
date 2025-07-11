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

-- Load TowerClass
local TowerClass
do
    local client = PlayerScripts:FindFirstChild("Client")
    local gameClass = client and client:FindFirstChild("GameClass")
    local towerModule = gameClass and gameClass:FindFirstChild("TowerClass")
    TowerClass = towerModule and require(towerModule)
end

if not TowerClass then
    warn("Không thể load TowerClass")
    return
end

-- Hàm lấy giá đặt tháp từ UI (theo đúng định dạng bạn cần)
local function GetTowerPlaceCostByName(name)
    local gui = player:FindFirstChild("PlayerGui")
    local interface = gui and gui:FindFirstChild("Interface")
    local bottomBar = interface and interface:FindFirstChild("BottomBar")
    local towersBar = bottomBar and bottomBar:FindFirstChild("TowersBar")
    
    if towersBar then
        for _, towerBtn in ipairs(towersBar:GetChildren()) do
            if towerBtn.Name == name then
                local costFrame = towerBtn:FindFirstChild("CostFrame")
                if costFrame then
                    local costText = costFrame:FindFirstChild("CostText")
                    if costText then
                        local cost = tonumber(costText.Text:match("%d+"))
                        return cost or 0
                    end
                end
            end
        end
    end
    return 0
end

-- Cache và Position Tracker (giữ nguyên từ script gốc của bạn)
local upgradeCache = {}
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
        task.wait(0.05)
    end
end)

local function CacheCurrentLevels()
    for hash, tower in pairs(TowerClass.GetTowers()) do
        upgradeCache[tostring(hash)] = {}
        for path = 1, 2 do
            local success, level = pcall(function()
                return tower.LevelHandler:GetPathLevel(path)
            end)
            if success then
                upgradeCache[tostring(hash)][path] = level
            end
        end
    end
end

local function IsUpgradeSuccess(hash, path)
    local h = tostring(hash)
    if not upgradeCache[h] then return false end
    
    local tower = TowerClass.GetTowers()[hash]
    if not tower then return false end
    
    local cur = tower.LevelHandler:GetPathLevel(path)
    local old = upgradeCache[h][path]
    
    return old and cur and cur > old
end

-- Tạo thư mục
if makefolder then
    pcall(makefolder, "tdx")
    pcall(makefolder, "tdx/macros")
end

-- Main loop (đúng định dạng đầu ra bạn yêu cầu)
while true do
    if isfile(txtFile) then
        local logs = {}
        CacheCurrentLevels()
        
        for line in readfile(txtFile):gmatch("[^\r\n]+") do
            -- PLACE (giữ nguyên định dạng đầu ra)
            local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*"([^"]+)",%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)')
            if a1 and name and x and y and z and rot then
                table.insert(logs, {
                    TowerPlaceCost = GetTowerPlaceCostByName(name),
                    TowerPlaced = name,
                    TowerVector = x..", "..y..", "..z,
                    Rotation = rot,
                    TowerA1 = a1
                })
            end
            
            -- UPGRADE (đúng định dạng)
            local hash, path = line:match('TDX:upgradeTower%(([^,]+),%s*(%d)%)')
            if hash and path then
                path = tonumber(path)
                task.wait(0.05)
                
                if IsUpgradeSuccess(hash, path) then
                    local pos = hash2pos[tostring(hash)]
                    if pos then
                        table.insert(logs, {
                            UpgradeCost = 0,  -- Có thể thay bằng giá thực tế
                            UpgradePath = path,
                            TowerUpgraded = pos.x
                        })
                    end
                end
            end
            
            -- SELL (đúng định dạng)
            local hash = line:match('TDX:sellTower%(([^%)]+)%)')
            if hash and hash2pos[tostring(hash)] then
                table.insert(logs, {
                    SellTower = hash2pos[tostring(hash)].x
                })
            end
            
            -- CHANGE TARGET (đúng định dạng)
            local hash, qtype = line:match('TDX:changeQueryType%(([^,]+),%s*(%d)%)')
            if hash and qtype and hash2pos[tostring(hash)] then
                table.insert(logs, {
                    ChangeTarget = hash2pos[tostring(hash)].x,
                    TargetType = tonumber(qtype)
                })
            end
        end
        
        if #logs > 0 then
            writefile(outJson, HttpService:JSONEncode(logs))
            print("✅ Đã ghi", #logs, "bản ghi vào x.json")
        end
    end
    task.wait(1)
end
