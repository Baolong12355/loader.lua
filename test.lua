local ReplicatedStorage = game:GetService("ReplicatedStorage")

local fileName = "record.txt"
local startTime = time()
local offset = 0

-- Xoá file cũ
if isfile(fileName) then delfile(fileName) end
writefile(fileName, "")

-- Pending xác nhận
local pending = nil
local timeout = 2

-- Serialize giá trị
local function serialize(v)
    if typeof(v) == "Vector3" then
        return "Vector3.new(" .. v.X .. "," .. v.Y .. "," .. v.Z .. ")"
    elseif typeof(v) == "Vector2int16" then
        return "Vector2int16.new(" .. v.X .. "," .. v.Y .. ")"
    elseif type(v) == "table" then
        local out = {}
        for k, val in pairs(v) do
            out[#out + 1] = "[" .. tostring(k) .. "]=" .. serialize(val)
        end
        return "{" .. table.concat(out, ",") .. "}"
    else
        return tostring(v)
    end
end

-- Serialize args
local function serializeArgs(...)
    local args = {...}
    local out = {}
    for i, v in ipairs(args) do
        out[i] = serialize(v)
    end
    return table.concat(out, ", ")
end

-- Xác nhận và ghi
local function confirmAndWrite()
    if not pending then return end
    appendfile(fileName, "task.wait(" .. ((time() - offset) - startTime) .. ")\n")
    appendfile(fileName, pending.code .. "\n")
    startTime = time() - offset
    pending = nil
end

-- Ghi nếu server phản hồi đúng loại
local function tryConfirm(typeStr)
    if pending and pending.type == typeStr then
        confirmAndWrite()
    end
end

-- Ghi log
local function setPending(typeStr, code)
    pending = {
        type = typeStr,
        code = code,
        created = tick()
    }
end

-- Lắng nghe Remote xác thực
ReplicatedStorage.Remotes.TowerFactoryQueueUpdated.OnClientEvent:Connect(function(data)
    local d = data[1]
    if not d then return end
    if d.Creation then
        tryConfirm("Place")
    else
        tryConfirm("Sell")
    end
end)

ReplicatedStorage.Remotes.TowerUpgradeQueueUpdated.OnClientEvent:Connect(function(data)
    if data[1] then
        tryConfirm("Upgrade")
    end
end)

ReplicatedStorage.Remotes.TowerQueryTypeIndexChanged.OnClientEvent:Connect(function(data)
    if data[1] then
        tryConfirm("Target")
    end
end)

-- Timeout check
task.spawn(function()
    while true do
        task.wait(0.3)
        if pending and tick() - pending.created > timeout then
            warn("❌ Không xác thực được: " .. pending.type)
            pending = nil
        end
    end
end)

-- Hook FireServer
local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
    local args = serializeArgs(...)
    local name = self.Name

    if name == "PlaceTower" then
        setPending("Place", "TDX:placeTower(" .. args .. ")")
    elseif name == "SellTower" then
        setPending("Sell", "TDX:sellTower(" .. args .. ")")
    elseif name == "TowerUpgradeRequest" then
        setPending("Upgrade", "TDX:upgradeTower(" .. args .. ")")
    elseif name == "ChangeQueryType" then
        setPending("Target", "TDX:changeQueryType(" .. args .. ")")
    end

    return oldFireServer(self, ...)
end)

-- Hook InvokeServer
local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
    local args = serializeArgs(...)
    return oldInvokeServer(self, ...)
end)

-- Hook __namecall
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    if method == "FireServer" or method == "InvokeServer" then
        local args = serializeArgs(...)
        local name = self.Name

        if name == "PlaceTower" then
            setPending("Place", "TDX:placeTower(" .. args .. ")")
        elseif name == "SellTower" then
            setPending("Sell", "TDX:sellTower(" .. args .. ")")
        elseif name == "TowerUpgradeRequest" then
            setPending("Upgrade", "TDX:upgradeTower(" .. args .. ")")
        elseif name == "ChangeQueryType" then
            setPending("Target", "TDX:changeQueryType(" .. args .. ")")
        end
    end
    return oldNamecall(self, ...)
end)

print("📌 Đã bật ghi macro có xác nhận từ server.")



-- Script chuyển đổi record.txt thành macro runner (dùng trục X), với thứ tự trường upgrade là: UpgradeCost, UpgradePath, TowerUpgraded
-- Đặt script này trong môi trường Roblox hoặc môi trường hỗ trợ các API Roblox tương ứng

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

local TowerClass
do
    local client = PlayerScripts:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    TowerClass = SafeRequire(towerModule)
end

local function GetTowerPosition(tower)
    if not tower or not tower.Character then return nil end
    local model = tower.Character:GetCharacterModel()
    local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
    return root and root.Position or nil
end

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

-- Ánh xạ hash -> pos liên tục
local hash2pos = {}
task.spawn(function()
    while true do
        for hash, tower in pairs(TowerClass and TowerClass.GetTowers() or {}) do
            local pos = GetTowerPosition(tower)
            if pos then
                hash2pos[tostring(hash)] = {x = pos.X, y = pos.Y, z = pos.Z}
            end
        end
        task.wait(0.1)
    end
end)

-- Tạo thư mục
if makefolder then
    pcall(function() makefolder("tdx") end)
    pcall(function() makefolder("tdx/macros") end)
end

-- Ghi SuperFunction khi gọi từ console
local function InsertSuper(cmd, skipList)
    if type(skipList) ~= "table" then skipList = {} end
    local line = HttpService:JSONEncode({
        SuperFunction = cmd,
        Skip = skipList
    })
    appendfile(outJson, line .. "\n")
    warn("✅ SuperFunction ghi vào macros:", cmd, "→", table.concat(skipList, ", "))
end

getgenv().rebuild = function(skip) InsertSuper("rebuild", skip) end
getgenv().SellAll = function(skip) InsertSuper("SellAll", skip) end

-- Vòng lặp chuyển đổi record.txt → x.json
while true do
    if isfile(txtFile) then
        delfile(outJson)
        local macro = readfile(txtFile)
        local logs = {}

        for line in macro:gmatch("[^\r\n]+") do
            -- Đặt tower
            local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)')
            if a1 and name and x and y and z and rot then
                name = tostring(name):gsub('^%s*"(.-)"%s*$', '%1')
                local cost = GetTowerPlaceCostByName(name)
                local vector = x .. ", " .. y .. ", " .. z
                table.insert(logs, HttpService:JSONEncode({
                    TowerPlaceCost = tonumber(cost) or 0,
                    TowerPlaced = name,
                    TowerVector = vector,
                    Rotation = rot,
                    TowerA1 = tostring(a1)
                }))
            else
                -- Upgrade tower
                local hash, path, upgradeCount = line:match('TDX:upgradeTower%(([^,]+),%s*([^,]+),%s*([^%)]+)%)')
                if hash and path and upgradeCount then
                    local pos = hash2pos[tostring(hash)]
                    local pathNum = tonumber(path)
                    local count = tonumber(upgradeCount)
                    if pos and pathNum and count and count > 0 then
                        for i = 1, count do
                            table.insert(logs, HttpService:JSONEncode({
                                UpgradeCost = 0,
                                UpgradePath = pathNum,
                                TowerUpgraded = pos.x
                            }))
                        end
                    end
                else
                    -- Change target
                    local hash, targetType = line:match('TDX:changeQueryType%(([^,]+),%s*([^%)]+)%)')
                    if hash and targetType then
                        local pos = hash2pos[tostring(hash)]
                        if pos then
                            table.insert(logs, HttpService:JSONEncode({
                                ChangeTarget = pos.x,
                                TargetType = tonumber(targetType)
                            }))
                        end
                    else
                        -- Sell tower
                        local hash = line:match('TDX:sellTower%(([^%)]+)%)')
                        if hash then
                            local pos = hash2pos[tostring(hash)]
                            if pos then
                                table.insert(logs, HttpService:JSONEncode({
                                    SellTower = pos.x
                                }))
                            end
                        end
                    end
                end
            end
        end

        -- Ghi tất cả thao tác ra file
        writefile(outJson, table.concat(logs, "\n"))
    end
    wait(0.22)
end
