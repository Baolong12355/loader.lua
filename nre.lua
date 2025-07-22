local ReplicatedStorage = game:GetService("ReplicatedStorage")

local fileName = "record.txt"

if isfile(fileName) then delfile(fileName) end writefile(fileName, "")

local pendingQueue = {} local timeout = 2

local function serialize(v) if typeof(v) == "Vector3" then return "Vector3.new(" .. v.X .. "," .. v.Y .. "," .. v.Z .. ")" elseif typeof(v) == "Vector2int16" then return "Vector2int16.new(" .. v.X .. "," .. v.Y .. ")" elseif type(v) == "table" then local out = {} for k, val in pairs(v) do out[#out + 1] = "[" .. tostring(k) .. "]=" .. serialize(val) end return "{" .. table.concat(out, ",") .. "}" else return tostring(v) end end

local function serializeArgs(...) local args = {...} local out = {} for i, v in ipairs(args) do out[i] = serialize(v) end return table.concat(out, ", ") end

local function tryConfirm(typeStr) for i, item in ipairs(pendingQueue) do if item.type == typeStr then appendfile(fileName, item.code .. "\n") table.remove(pendingQueue, i) return end end end

local function setPending(typeStr, code) table.insert(pendingQueue, { type = typeStr, code = code, created = tick() }) end

ReplicatedStorage.Remotes.TowerFactoryQueueUpdated.OnClientEvent:Connect(function(data) local d = data[1] if not d then return end if d.Creation then tryConfirm("Place") else tryConfirm("Sell") end end)

ReplicatedStorage.Remotes.TowerUpgradeQueueUpdated.OnClientEvent:Connect(function(data) if data[1] then tryConfirm("Upgrade") end end)

ReplicatedStorage.Remotes.TowerQueryTypeIndexChanged.OnClientEvent:Connect(function(data) if data[1] then tryConfirm("Target") end end)

task.spawn(function() while true do task.wait(0.05) local now = tick() for i = #pendingQueue, 1, -1 do if now - pendingQueue[i].created > timeout then warn("❌ Không xác thực được: " .. pendingQueue[i].type) table.remove(pendingQueue, i) end end end end)

local function handleRemote(name, args) if name == "TowerUpgradeRequest" then local hash, path, count = unpack(args) if typeof(hash) == "number" and typeof(path) == "number" and typeof(count) == "number" then if path >= 0 and path <= 2 and count > 0 and count <= 5 then for _ = 1, count do setPending("Upgrade", string.format("TDX:upgradeTower(%s, %d, 1)", tostring(hash), path)) end end end elseif name == "PlaceTower" then setPending("Place", "TDX:placeTower(" .. serializeArgs(unpack(args)) .. ")") elseif name == "SellTower" then setPending("Sell", "TDX:sellTower(" .. serializeArgs(unpack(args)) .. ")") elseif name == "ChangeQueryType" then setPending("Target", "TDX:changeQueryType(" .. serializeArgs(unpack(args)) .. ")") end end

local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...) local name = self.Name local args = {...} handleRemote(name, args) return oldFireServer(self, ...) end)

local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...) return oldInvokeServer(self, ...) end)

local oldNamecall oldNamecall = hookmetamethod(game, "__namecall", function(self, ...) if checkcaller() then return oldNamecall(self, ...) end local method = getnamecallmethod() if method ~= "FireServer" then return oldNamecall(self, ...) end local name = self.Name local args = {...} handleRemote(name, args) return oldNamecall(self, ...) end)

print("✅ Queue ghi log đa kênh + chống lộn path đã bật")



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

-- Hàm lấy wave và time hiện tại từ game UI
local function getCurrentWaveAndTime()
    local playerGui = player:FindFirstChild("PlayerGui")
    if not playerGui then return nil, nil end
    local interface = playerGui:FindFirstChild("Interface")
    if not interface then return nil, nil end
    local gameInfoBar = interface:FindFirstChild("GameInfoBar")
    if not gameInfoBar then return nil, nil end

    local wave = gameInfoBar.Wave.WaveText.Text
    local time = gameInfoBar.TimeLeft.TimeLeftText.Text
    return wave, time
end

-- Chuyển time format từ "MM:SS" thành số (ví dụ: "02:35" -> 235)
local function convertTimeToNumber(timeStr)
    if not timeStr then return nil end
    local mins, secs = timeStr:match("(%d+):(%d+)")
    if mins and secs then
        return tonumber(mins) * 100 + tonumber(secs)
    end
    return nil
end

-- ánh xạ hash -> pos liên tục
local hash2pos = {}
task.spawn(function()
    while true do
        for hash, tower in pairs(TowerClass and TowerClass.GetTowers() or {}) do
            local pos = GetTowerPosition(tower)
            if pos then
                hash2pos[tostring(hash)] = {x = pos.X, y = pos.Y, z = pos.Z}
            end
        end
        task.wait()
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

        -- giữ dòng SuperFunction
        local preservedSuper = {}
        if isfile(outJson) then
            local content = readfile(outJson)
            -- Remove brackets and split by lines
            content = content:gsub("^%[%s*", ""):gsub("%s*%]$", "")
            for line in content:gmatch("[^\r\n]+") do
                line = line:gsub(",$", "") -- Remove trailing comma
                if line:match("%S") then -- Only non-empty lines
                    local ok, decoded = pcall(HttpService.JSONDecode, HttpService, line)
                    if ok and decoded and decoded.SuperFunction then
                        table.insert(preservedSuper, decoded)
                    end
                end
            end
        end

        for line in macro:gmatch("[^\r\n]+") do
            -- parser mới cho placeTower với Vector3.new(...)
            local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*Vector3%.new%(([^,]+),%s*([^,]+),%s*([^%)]+)%)%s*,%s*([^%)]+)%)')
            if a1 and name and x and y and z and rot then
                name = tostring(name):gsub('^%s*"(.-)"%s*$', '%1')
                local cost = GetTowerPlaceCostByName(name)
                local vector = string.format("%s, %s, %s", tostring(tonumber(x) or x), tostring(tonumber(y) or y), tostring(tonumber(z) or z))
                table.insert(logs, {
                    TowerPlaceCost = tonumber(cost) or 0,
                    TowerPlaced = name,
                    TowerVector = vector,
                    Rotation = rot,
                    TowerA1 = tostring(a1)
                })
            else
                -- nâng cấp
                local hash, path, upgradeCount = line:match('TDX:upgradeTower%(([^,]+),%s*([^,]+),%s*([^%)]+)%)')
                if hash and path and upgradeCount then
                    local pos = hash2pos[tostring(hash)]
                    local pathNum = tonumber(path)
                    local count = tonumber(upgradeCount)
                    if pos and pathNum and count and count > 0 then
                        for _ = 1, count do
                            table.insert(logs, {
                                UpgradeCost = 0,
                                UpgradePath = pathNum,
                                TowerUpgraded = pos.x
                            })
                        end
                    end
                else
                    -- đổi target - TỰ ĐỘNG LẤY WAVE VÀ TIME HIỆN TẠI
                    local hash, targetType = line:match('TDX:changeQueryType%(([^,]+),%s*([^%)]+)%)')
                    if hash and targetType then
                        local pos = hash2pos[tostring(hash)]
                        if pos then
                            -- Lấy wave và time hiện tại
                            local currentWave, currentTime = getCurrentWaveAndTime()
                            local timeNumber = convertTimeToNumber(currentTime)

                            local targetEntry = {
                                TowerTargetChange = pos.x,
                                TargetWanted = tonumber(targetType)
                            }

                            -- Thêm wave nếu có
                            if currentWave then
                                targetEntry.TargetWave = currentWave
                            end

                            -- Thêm time nếu có
                            if timeNumber then
                                targetEntry.TargetChangedAt = timeNumber
                            end

                            table.insert(logs, targetEntry)
                        end
                    else
                        -- bán
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

        -- Add preserved SuperFunction entries
        for _, entry in ipairs(preservedSuper) do
            table.insert(logs, entry)
        end

        -- Convert to proper JSON array format
        local jsonLines = {}
        for i, entry in ipairs(logs) do
            local jsonStr = HttpService:JSONEncode(entry)
            if i < #logs then
                jsonStr = jsonStr .. ","
            end
            table.insert(jsonLines, jsonStr)
        end

        -- Write with brackets
        local finalJson = "[\n" .. table.concat(jsonLines, "\n") .. "\n]"
        writefile(outJson, finalJson)
    end
    wait()
end