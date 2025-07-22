-- ✅ TDX JSON Record (full version with internal confirmation only for upgrade)

local ReplicatedStorage = game:GetService("ReplicatedStorage") local Players = game:GetService("Players") local RunService = game:GetService("RunService") local HttpService = game:GetService("HttpService") local player = Players.LocalPlayer

local jsonFile = "tdx/macros/record.json"

if makefolder then pcall(function() makefolder("tdx") end) pcall(function() makefolder("tdx/macros") end) end

if not isfile(jsonFile) then writefile(jsonFile, "[]") end

local function SafeRequire(path, timeout) timeout = timeout or 5 local startTime = tick() while tick() - startTime < timeout do local success, result = pcall(function() return require(path) end) if success and result then return result end RunService.Heartbeat:Wait() end return nil end

local function LoadTowerClass() local ps = player:FindFirstChild("PlayerScripts") if not ps then return nil end local client = ps:FindFirstChild("Client") if not client then return nil end local gameClass = client:FindFirstChild("GameClass") if not gameClass then return nil end local towerModule = gameClass:FindFirstChild("TowerClass") if not towerModule then return nil end return SafeRequire(towerModule) end

local TowerClass = LoadTowerClass() if not TowerClass then warn("Không thể load TowerClass") end

local function GetTowerByAxis(axisX) if not TowerClass then return nil, nil, nil end for hash, tower in pairs(TowerClass.GetTowers()) do local success, pos, name = pcall(function() local model = tower.Character:GetCharacterModel() local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")) return root and root.Position, model and (root and root.Name or model.Name) end) if success and pos and pos.X == axisX then local hp = 1 pcall(function() hp = tower.HealthHandler and tower.HealthHandler:GetHealth() or 1 end) if hp and hp > 0 then return hash, tower, name or "(NoName)" end end end return nil, nil, nil end

local function serialize(v) if typeof(v) == "Vector3" then return "Vector3.new(" .. v.X .. "," .. v.Y .. "," .. v.Z .. ")" elseif typeof(v) == "Vector2int16" then return "Vector2int16.new(" .. v.X .. "," .. v.Y .. ")" elseif type(v) == "table" then local out = {} for k, val in pairs(v) do out[#out + 1] = "[" .. tostring(k) .. "]=" .. serialize(val) end return "{" .. table.concat(out, ",") .. "}" else return tostring(v) end end

local function serializeArgs(...) local args = {...} local out = {} for i, v in ipairs(args) do out[i] = serialize(v) end return table.concat(out, ", ") end

local hash2pos = {} if TowerClass then task.spawn(function() while true do for hash, tower in pairs(TowerClass.GetTowers()) do local success, pos = pcall(function() local model = tower.Character:GetCharacterModel() local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")) return root and root.Position end) if success and pos then hash2pos[tostring(hash)] = pos end end task.wait(0.1) end end) end

local function readCurrentJSON() if not isfile(jsonFile) then return {} end local content = readfile(jsonFile) if not content or content == "" then return {} end local success, result = pcall(function() return HttpService:JSONDecode(content) end) if success and type(result) == "table" then return result end return {} end

local function addJSONEntry(entry) local currentData = readCurrentJSON() table.insert(currentData, entry) local success = pcall(function() local jsonString = HttpService:JSONEncode(currentData) writefile(jsonFile, jsonString) end) if success then print("✅ Đã ghi: " .. (entry.TowerPlaced or entry.TowerUpgraded or entry.TowerTargetChange or entry.SellTower or "Unknown")) else warn("❌ Lỗi ghi JSON") end end

local pending = nil local timeout = 2

local function setPending(typeStr, entryData) pending = { type = typeStr, entry = entryData, created = tick() }

if typeStr == "Upgrade" and entryData.TowerUpgraded and entryData.UpgradePath then
    local axisX = tonumber(entryData.TowerUpgraded)
    local path = tonumber(entryData.UpgradePath)

    task.spawn(function()
        local tries = 0
        local previousLevel = nil
        while tries < 5 do
            local _, tower = GetTowerByAxis(axisX)
            if tower and tower.LevelHandler then
                previousLevel = tower.LevelHandler:GetLevelOnPath(path)
                break
            end
            tries += 1
            task.wait(0.1)
        end
        if previousLevel == nil then return end
        tries = 0
        while tries < 30 do
            local _, tower = GetTowerByAxis(axisX)
            if tower and tower.LevelHandler then
                local newLevel = tower.LevelHandler:GetLevelOnPath(path)
                if newLevel > previousLevel then
                    tryConfirm("Upgrade")
                    break
                end
            end
            tries += 1
            task.wait(0.1)
        end
    end)
end

end

local function confirmAndWrite() if not pending then return end addJSONEntry(pending.entry) pending = nil end

local function tryConfirm(typeStr) if pending and pending.type == typeStr then confirmAndWrite() end end

task.spawn(function() while true do task.wait() if pending and tick() - pending.created > timeout then warn("❌ Không xác thực được: " .. pending.type) pending = nil end end end)

ReplicatedStorage.Remotes.TowerFactoryQueueUpdated.OnClientEvent:Connect(function(data) local d = data[1] if not d then return end if d.Creation then tryConfirm("Place") else tryConfirm("Sell") end end)

ReplicatedStorage.Remotes.TowerUpgradeQueueUpdated.OnClientEvent:Connect(function(data) if data[1] then tryConfirm("Upgrade") end end)

ReplicatedStorage.Remotes.TowerQueryTypeIndexChanged.OnClientEvent:Connect(function(data) if data[1] then tryConfirm("Target") end end)

local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...) local args = serializeArgs(...) local name = self.Name if name == "PlaceTower" then local line = "TDX:placeTower(" .. args .. ")" local entry = convertToJSON(line) if entry then setPending("Place", entry) end elseif name == "SellTower" then local line = "TDX:sellTower(" .. args .. ")" local entry = convertToJSON(line) if entry then setPending("Sell", entry) end elseif name == "TowerUpgradeRequest" then local line = "TDX:upgradeTower(" .. args .. ")" local entry = convertToJSON(line) if entry then setPending("Upgrade", entry) end elseif name == "ChangeQueryType" then local line = "TDX:changeQueryType(" .. args .. ")" local entry = convertToJSON(line) if entry then setPending("Target", entry) end end return oldFireServer(self, ...) end)

print("🎯 TDX JSON Record khởi động lại (upgrade nội bộ, còn lại dùng server)")

