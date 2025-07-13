local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Config
local RECORD_FILE = "tdx_raw_records.txt"
local OUTPUT_JSON = "tdx_macros/x-1.json"
local DELAY = 0.1

-- Initialize files
if isfile(RECORD_FILE) then delfile(RECORD_FILE) end
writefile(RECORD_FILE, "-- Raw TDX Macro Data --\n")

-- Track tower positions precisely
local TowerPositions = {}
RunService.Heartbeat:Connect(function()
    for _, inst in pairs(workspace:GetDescendants()) do
        if inst:GetAttribute("IsTower") then
            local root = inst:FindFirstChild("HumanoidRootPart") or inst.PrimaryPart
            if root then
                TowerPositions[inst:GetAttribute("Hash")] = {
                    x = root.Position.X,
                    y = root.Position.Y, 
                    z = root.Position.Z
                }
            end
        end
    end
end)

-- Exact serialization without rounding
local function SerializeExactly(value)
    if typeof(value) == "number" then
        -- Prevent any rounding by using string.format with maximum precision
        local s = string.format("%.17g", value)
        -- Remove trailing .0 for whole numbers
        return s:find("%.") and s or s .. ".0"
    elseif typeof(value) == "Vector3" then
        return string.format(
            "%s,%s,%s", 
            SerializeExactly(value.X),
            SerializeExactly(value.Y),
            SerializeExactly(value.Z)
        )
    end
    return tostring(value)
end

-- Record raw actions
local function RecordAction(eventName, ...)
    local args = {...}
    local timestamp = os.clock()
    
    if eventName == "PlaceTower" and #args >= 5 then
        -- Get raw tower values without rounding
        local pos = Vector3.new(args[2], args[3], args[4])
        appendfile(RECORD_FILE, string.format(
            "PLACE|%s|%s|%s|%s|%s\n",
            tostring(args[1]),
            SerializeExactly(pos),
            SerializeExactly(args[5]),
            args[6] or "",
            timestamp
        ))
    elseif eventName == "TowerUpgradeRequest" and #args >= 2 then
        local hash = tostring(args[1])
        local pos = TowerPositions[hash]
        if pos then
            appendfile(RECORD_FILE, string.format(
                "UPGRADE|%s|%s|%s\n",
                SerializeExactly(pos.x),
                tostring(args[2]),
                timestamp
            ))
        end
    end
end

-- Hook core remotes
local Remotes = {
    PlaceTower = game:GetService("ReplicatedStorage").Remotes.PlaceTower,
    TowerUpgradeRequest = game:GetService("ReplicatedStorage").Remotes.TowerUpgradeRequest
}

for name, remote in pairs(Remotes) do
    local original = remote.FireServer
    remote.FireServer = function(_, ...)
        RecordAction(name, ...)
        return original(remote, ...)
    end
end

-- Convert to exact JSON format
while task.wait(1) do
    if not isfile(RECORD_FILE) then continue end
    
    local actions = {}
    for line in readfile(RECORD_FILE):gmatch("[^\r\n]+") do
        local cmd, argsStr = line:match("([^|]+)|(.+)")
        if not cmd then continue end
        
        local parts = {}
        for part in argsStr:gmatch("([^|]+)") do
            table.insert(parts, part)
        end

        if cmd == "PLACE" and #parts >= 4 then
            table.insert(actions, {
                TowerPlaceCost = tonumber(parts[1]),
                TowerPlaced = parts[2],
                TowerVector = parts[3], -- Already in exact format
                Rotation = parts[4],
                TowerA1 = parts[5] or "",
                _timestamp = parts[6]
            })
        elseif cmd == "UPGRADE" and #parts >= 2 then
            table.insert(actions, {
                TowerUpgraded = parts[1], -- Exact position
                UpgradeCost = 0,
                UpgradePath = tonumber(parts[2]),
                _timestamp = parts[3]
            })
        end
    end

    if #actions > 0 then
        writefile(OUTPUT_JSON, HttpService:JSONEncode(actions))
    end
end
