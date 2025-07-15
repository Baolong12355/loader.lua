-- Dành cho môi trường exploit (Synapse, Fluxus, etc.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- File record
local fileName = "record.txt"
if isfile(fileName) then delfile(fileName) end
writefile(fileName, "")

-- Timing
local startTime = time()
local offset = 0

-- Pending xác nhận
local pendingAction = nil -- {type="Place"/"Sell"/"Upgrade"/"Target", code=function()}
local timeoutDuration = 2

-- ✅ Ghi vào record.txt
local function confirmAndWrite(code)
    appendfile(fileName, "task.wait(" .. ((time() - offset) - startTime) .. ")\n")
    appendfile(fileName, code .. "\n")
    startTime = time() - offset
end

-- 🕒 Đặt hành động chờ xác thực
local function setPending(typeStr, codeStr)
    pendingAction = {
        type = typeStr,
        code = codeStr,
        created = tick()
    }
end

-- Helper serialize
local function serialize(v)
    if typeof(v) == "Vector3" then
        return "Vector3.new(" .. v.X .. "," .. v.Y .. "," .. v.Z .. ")"
    elseif typeof(v) == "Vector2int16" then
        return "Vector2int16.new(" .. v.X .. "," .. v.Y .. ")"
    elseif type(v) == "table" then
        local result = "{"
        for k, val in pairs(v) do
            result = result .. "[" .. tostring(k) .. "]=" .. serialize(val) .. ","
        end
        return result .. "}"
    else
        return tostring(v)
    end
end

-- 🎯 Ghi khi server xác thực
local function tryConfirm(typeCheck)
    if pendingAction and pendingAction.type == typeCheck then
        confirmAndWrite(pendingAction.code)
        pendingAction = nil
    end
end

-- 1. Upgrade Tower
ReplicatedStorage.Remotes.TowerUpgradeQueueUpdated.OnClientEvent:Connect(function(data)
    if data[1] then
        tryConfirm("Upgrade")
    end
end)

-- 2. Sell / Place Tower
ReplicatedStorage.Remotes.TowerFactoryQueueUpdated.OnClientEvent:Connect(function(data)
    local v = data[1]
    if not v then return end
    if v.Creation then
        tryConfirm("Place")
    else
        tryConfirm("Sell")
    end
end)

-- 3. Change Target
ReplicatedStorage.Remotes.TowerQueryTypeIndexChanged.OnClientEvent:Connect(function(data)
    if data[1] then
        tryConfirm("Target")
    end
end)

-- Hook __namecall
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local args = {...}
    local method = getnamecallmethod()
    if (method == "FireServer" or method == "InvokeServer") and typeof(self) == "Instance" then
        local name = self.Name
        local serialized = table.concat(args, ", ")
        if name == "PlaceTower" then
            local code = "TDX:placeTower(" .. serialized .. ")"
            setPending("Place", code)
        elseif name == "SellTower" then
            local code = "TDX:sellTower(" .. serialized .. ")"
            setPending("Sell", code)
        elseif name == "TowerUpgradeRequest" then
            local code = "TDX:upgradeTower(" .. serialized .. ")"
            setPending("Upgrade", code)
        elseif name == "ChangeQueryType" then
            local code = "TDX:changeQueryType(" .. serialized .. ")"
            setPending("Target", code)
        end
    end
    return oldNamecall(self, ...)
end)

-- Timeout kiểm tra
task.spawn(function()
    while true do
        task.wait(0.5)
        if pendingAction and tick() - pendingAction.created > timeoutDuration then
            warn("❌ Không xác thực được hành động: " .. pendingAction.type)
            pendingAction = nil
        end
    end
end)

print("📦 Ghi macro đang chạy (sử dụng xác nhận từ server trước khi ghi).")
