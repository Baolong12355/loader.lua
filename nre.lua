--[[
    TDX Direct JSON Recorder (Append Mode)
    Version: 2.0
    Description: This script hooks into game events to record tower placements, upgrades, sales, and target changes.
    It writes data directly to a JSON file in an append-only fashion, without caching the entire file in memory.
    This is more efficient and robust for logging over long periods.
]]

-- Roblox Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

-- Local Player and Scripts
local player = Players.LocalPlayer
local PlayerScripts = player:WaitForChild("PlayerScripts")

-- Configuration
local outJson = "tdx/macros/x.json"

-- Create output directories if they don't exist
-- This relies on the executor providing the 'makefolder' function.
if makefolder then
    pcall(function() makefolder("tdx") end)
    pcall(function() makefolder("tdx/macros") end)
end

--==============================================================================
-- File I/O - Append-Only JSON Writer
--==============================================================================

-- This function appends new log entries to the JSON file without reading the whole
-- file into a Lua table. It works by manipulating the file content as a string.
local function appendLogsToFile(entries)
    if not entries or #entries == 0 or not HttpService or not writefile then return end

    -- Step 1: Encode the new entries into JSON strings.
    local newJsonStrings = {}
    for _, entry in ipairs(entries) do
        -- Indent each new line for better readability in the final JSON file.
        table.insert(newJsonStrings, "    " .. HttpService:JSONEncode(entry))
    end
    if #newJsonStrings == 0 then return end
    local newJsonBlock = table.concat(newJsonStrings, ",\n")

    -- Step 2: Read the current content of the file, if it exists.
    local currentContent = ""
    if isfile and isfile(outJson) then
        local success, content = pcall(readfile, outJson)
        if success and content then
            currentContent = content
        end
    end

    local finalJson

    -- Step 3: Determine how to add the new content.
    local lastBracketPos
    if #currentContent > 0 then
        -- Find the position of the last closing bracket ']'
        for i = #currentContent, 1, -1 do
            if currentContent:sub(i, i) == ']' then
                lastBracketPos = i
                break
            end
        end
    end

    if lastBracketPos then
        -- Case A: The file already exists. We need to insert the new data before the final ']'.
        local contentBeforeBracket = currentContent:sub(1, lastBracketPos - 1)
        
        -- Only add a preceding comma if there's already a JSON object in the array (indicated by a '}' character).
        if contentBeforeBracket:match("}") then
            -- Append a comma to the existing content, then add the new block.
            finalJson = contentBeforeBracket .. ",\n" .. newJsonBlock .. "\n]"
        else
            -- The file exists but is empty (e.g., "[]"). Start the array with the new block.
            finalJson = "[\n" .. newJsonBlock .. "\n]"
        end
    else
        -- Case B: The file is new or completely empty. Create a new JSON array.
        finalJson = "[\n" .. newJsonBlock .. "\n]"
    end

    -- Step 4: Write the updated content back to the file.
    pcall(writefile, outJson, finalJson)
end

-- Wrapper function to add a single log entry.
local function addLogEntry(entry)
    appendLogsToFile({entry})
end

-- Wrapper function to add multiple log entries at once.
local function addLogEntries(entries)
    appendLogsToFile(entries)
end


--==============================================================================
-- Game Data & Logic (Largely Unchanged)
--==============================================================================

-- Variables for tracking game state
local pendingQueue = {}
local timeout = 2
local lastKnownLevels = {} -- { [towerHash] = {path1Level, path2Level} }
local lastUpgradeTime = {} -- { [towerHash] = timestamp } to detect duplicate upgrade events

-- Fetch the TowerClass module from the game scripts
local TowerClass
pcall(function()
    local client = PlayerScripts:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    TowerClass = require(towerModule)
end)

-- Function to get a tower's world position
local function GetTowerPosition(tower)
    if not TowerClass or not tower then return nil end
    -- A series of attempts to get the tower's position, as different tower types might store it differently.
    if tower.CFrame and typeof(tower.CFrame) == "CFrame" then return tower.CFrame.Position end
    if tower.GetPosition and pcall(tower.GetPosition, tower) then return tower:GetPosition() end
    if tower.GetTorsoPosition and pcall(tower.GetTorsoPosition, tower) then return tower:GetTorsoPosition() end
    if tower.Character and tower.Character.PrimaryPart then return tower.Character.PrimaryPart.Position end
    return nil
end

-- Function to get tower placement cost by scraping the UI
local function GetTowerPlaceCostByName(name)
    local playerGui = player:FindFirstChild("PlayerGui")
    local costText = playerGui and playerGui:FindFirstChild("Interface.BottomBar.TowersBar." .. name .. ".CostFrame.CostText", true)
    if costText then
        local raw = tostring(costText.Text):gsub("%D", "")
        return tonumber(raw) or 0
    end
    return 0
end

-- Function to get the current wave and time from the UI
local function getCurrentWaveAndTime()
    local playerGui = player:FindFirstChild("PlayerGui")
    local gameInfoBar = playerGui and playerGui:FindFirstChild("Interface.GameInfoBar", true)
    if gameInfoBar then
        local wave = gameInfoBar.Wave.WaveText.Text
        local time = gameInfoBar.TimeLeft.TimeLeftText.Text
        return wave, time
    end
    return nil, nil
end

-- Convert "MM:SS" time format to a number (e.g., "01:23" -> 123)
local function convertTimeToNumber(timeStr)
    if not timeStr then return nil end
    local mins, secs = timeStr:match("(%d+):(%d+)")
    if mins and secs then
        return tonumber(mins) * 100 + tonumber(secs)
    end
    return nil
end

-- Cache tower positions by their hash for quick lookups
local hash2pos = {}
task.spawn(function()
    while task.wait() do
        if TowerClass and TowerClass.GetTowers then
            for hash, tower in pairs(TowerClass.GetTowers() or {}) do
                local pos = GetTowerPosition(tower)
                if pos then
                    hash2pos[tostring(hash)] = {x = pos.X, y = pos.Y, z = pos.Z}
                end
            end
        end
    end
end)

-- Serialize different data types into a string format for the pending queue
local function serialize(v)
    if typeof(v) == "Vector3" then
        return "Vector3.new("..v.X..","..v.Y..","..v.Z..")"
    elseif typeof(v) == "Vector2int16" then
        return "Vector2int16.new("..v.X..","..v.Y..")"
    elseif type(v) == "table" then
        local out = {}
        for k, val in pairs(v) do
            out[#out+1] = "["..tostring(k).."]="..serialize(val)
        end
        return "{"..table.concat(out, ",").."}"
    else
        return tostring(v)
    end
end

local function serializeArgs(...)
    local args = {...}
    local out = {}
    for i, v in ipairs(args) do
        out[i] = serialize(v)
    end
    return table.concat(out, ", ")
end

-- This function parses the pending action string and converts it into a structured table for JSON logging.
function parseMacroLine(line)
    -- Parse "placeTower" actions
    local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*Vector3%.new%(([^,]+),%s*([^,]+),%s*([^%)]+)%)%s*,%s*([^%)]+)%)')
    if a1 and name and x and y and z and rot then
        name = tostring(name):gsub('^%s*"(.-)"%s*$', '%1')
        return {{
            TowerPlaceCost = GetTowerPlaceCostByName(name),
            TowerPlaced = name,
            TowerVector = string.format("%s, %s, %s", tostring(tonumber(x) or x), tostring(tonumber(y) or y), tostring(tonumber(z) or z)),
            Rotation = tonumber(rot),
            TowerA1 = tostring(a1)
        }}
    end

    -- Parse "upgradeTower" actions
    local hash, path, upgradeCount = line:match('TDX:upgradeTower%(([^,]+),%s*([^,]+),%s*([^%)]+)%)')
    if hash and path and upgradeCount then
        local pos = hash2pos[tostring(hash)]
        local pathNum = tonumber(path)
        local count = tonumber(upgradeCount)
        if pos and pathNum and count and count > 0 then
            local entries = {}
            for _ = 1, count do
                table.insert(entries, {
                    UpgradeCost = 0, -- Cost is not easily available here, so defaulting to 0
                    UpgradePath = pathNum,
                    TowerUpgraded = pos.x -- Using X coordinate as a simple identifier
                })
            end
            return entries
        end
    end

    -- Parse "changeQueryType" (targeting) actions
    local hash, targetType = line:match('TDX:changeQueryType%(([^,]+),%s*([^%)]+)%)')
    if hash and targetType then
        local pos = hash2pos[tostring(hash)]
        if pos then
            local currentWave, currentTime = getCurrentWaveAndTime()
            local targetEntry = {
                TowerTargetChange = pos.x,
                TargetWanted = tonumber(targetType),
                TargetWave = currentWave,
                TargetChangedAt = convertTimeToNumber(currentTime)
            }
            return {targetEntry}
        end
    end

    -- Parse "sellTower" actions
    local hash = line:match('TDX:sellTower%(([^%)]+)%)')
    if hash then
        local pos = hash2pos[tostring(hash)]
        if pos then
            return {{ SellTower = pos.x }}
        end
    end

    return nil
end

-- Tries to confirm a pending action from the queue when a corresponding server event is received.
local function tryConfirm(typeStr, specificHash)
    for i, item in ipairs(pendingQueue) do
        if item.type == typeStr then
            if not specificHash or string.find(item.code, tostring(specificHash)) then
                -- Action confirmed. Parse the stored command and log it.
                local result = parseMacroLine(item.code)
                if result then
                    addLogEntries(result)
                end
                table.remove(pendingQueue, i)
                return
            end
        end
    end
end

-- Adds an action to the pending queue, waiting for server confirmation.
local function setPending(typeStr, code, hash)
    table.insert(pendingQueue, {
        type = typeStr,
        code = code,
        created = tick(),
        hash = hash
    })
end


--==============================================================================
-- Remote Event Listeners & Hooks
--==============================================================================

-- Listen for tower creation/selling confirmation
ReplicatedStorage.Remotes.TowerFactoryQueueUpdated.OnClientEvent:Connect(function(data)
    local d = data and data[1]
    if not d then return end
    if d.Creation then tryConfirm("Place") else tryConfirm("Sell") end
end)

-- Listen for tower upgrade confirmation
ReplicatedStorage.Remotes.TowerUpgradeQueueUpdated.OnClientEvent:Connect(function(data)
    if not data or not data[1] then return end

    local towerData = data[1]
    local hash = towerData.Hash
    local newLevels = towerData.LevelReplicationData
    
    -- Prevent duplicate event processing
    local currentTime = tick()
    if lastUpgradeTime[hash] and (currentTime - lastUpgradeTime[hash]) < 0.01 then return end
    lastUpgradeTime[hash] = currentTime

    -- Compare old levels with new levels to find what was upgraded
    local upgradedPath, upgradeCount = nil, 0
    if lastKnownLevels[hash] then
        for path = 1, 2 do
            if (newLevels[path] or 0) > (lastKnownLevels[hash][path] or 0) then
                upgradedPath = path
                upgradeCount = newLevels[path] - lastKnownLevels[hash][path]
                break
            end
        end
    end

    if upgradedPath and upgradeCount > 0 then
        -- We detected the specific upgrade, log it directly.
        local code = string.format("TDX:upgradeTower(%s, %d, %d)", tostring(hash), upgradedPath, upgradeCount)
        local result = parseMacroLine(code)
        if result then addLogEntries(result) end
        
        -- Clear any related pending upgrades for this tower
        for i = #pendingQueue, 1, -1 do
            if pendingQueue[i].type == "Upgrade" and pendingQueue[i].hash == hash then
                table.remove(pendingQueue, i)
            end
        end
    else
        -- Fallback to the general confirmation method
        tryConfirm("Upgrade", hash)
    end

    lastKnownLevels[hash] = newLevels or {}
end)

-- Listen for targeting change confirmation
ReplicatedStorage.Remotes.TowerQueryTypeIndexChanged.OnClientEvent:Connect(function(data)
    if data and data[1] then
        tryConfirm("Target")
    end
end)

-- Background task to clean up actions in the queue that never get confirmed
task.spawn(function()
    while task.wait(0.05) do
        local now = tick()
        for i = #pendingQueue, 1, -1 do
            if now - pendingQueue[i].created > timeout then
                warn("❌ Timed out waiting for server confirmation: " .. pendingQueue[i].type)
                table.remove(pendingQueue, i)
            end
        end
    end
end)

-- Intercept remote calls made by the client to log actions before they are sent.
local function handleRemote(name, args)
    if name == "TowerUpgradeRequest" then
        local hash, path, count = unpack(args)
        if typeof(hash) == "number" and typeof(path) == "number" and typeof(count) == "number" then
            setPending("Upgrade", string.format("TDX:upgradeTower(%s, %d, %d)", tostring(hash), path, count), hash)
        end
    elseif name == "PlaceTower" then
        local a1, towerName, vec, rot = unpack(args)
        if typeof(a1) == "number" and typeof(towerName) == "string" and typeof(vec) == "Vector3" and typeof(rot) == "number" then
            local code = string.format('TDX:placeTower(%d, "%s", Vector3.new(%s, %s, %s), %d)', a1, towerName, vec.X, vec.Y, vec.Z, rot)
            setPending("Place", code)
        end
    elseif name == "SellTower" then
        setPending("Sell", "TDX:sellTower("..serializeArgs(unpack(args))..")")
    elseif name == "ChangeQueryType" then
        setPending("Target", "TDX:changeQueryType("..serializeArgs(unpack(args))..")")
    end
end

-- Hook into the game's remote functions using the executor's capabilities.
-- We must call the original function to ensure the game works correctly.
if hookfunction and hookmetamethod and getnamecallmethod and checkcaller then
    local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
        handleRemote(self.Name, {...})
        return oldFireServer(self, ...)
    end)

    local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
        handleRemote(self.Name, {...})
        return oldInvokeServer(self, ...)
    end)

    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if not checkcaller() then
            local method = getnamecallmethod()
            if method == "FireServer" or method == "InvokeServer" then
                handleRemote(self.Name, {...})
            end
        end
        return oldNamecall(self, ...)
    end)
else
    warn("Executor does not support required hooking functions.")
end

print("✅ TDX Direct JSON Recorder (Append Mode) has started!")
print("📁 Logging actions directly to: " .. outJson)

