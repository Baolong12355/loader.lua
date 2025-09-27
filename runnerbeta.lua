local http = game:GetService("HttpService")
local storage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")
local run = game:GetService("RunService")
local player = players.LocalPlayer
local cash = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local remotes = storage:WaitForChild("Remotes")
local gui = players.LocalPlayer:WaitForChild("PlayerGui")

local function getEnv()
    if getgenv then return getgenv() end
    if getfenv then return getfenv() end
    return _G
end

local function readFile(path)
    if readfile and typeof(readfile) == "function" then
        local ok, result = pcall(readfile, path)
        return ok and result or nil
    end
    return nil
end

local function fileExists(path)
    if isfile and typeof(isfile) == "function" then
        local ok, result = pcall(isfile, path)
        return ok and result or false
    end
    return false
end

local config = {
    ["Macro Name"] = "endless",
    ["PlaceMode"] = "Rewrite",
    ["ForceRebuildEvenIfSold"] = false,
    ["MaxRebuildRetry"] = nil,
    ["SellAllDelay"] = 0.1,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"},
    ["TargetChangeCheckDelay"] = 0.05,
    ["RebuildPriority"] = false,
    ["RebuildCheckInterval"] = 0,
    ["MacroStepDelay"] = 0.1,
    ["MaxConcurrentRebuilds"] = 120,
    ["MonitorCheckDelay"] = 0.05,
    ["AllowParallelTargets"] = false,
    ["AllowParallelSkips"] = true
}

local env = getEnv()
env.TDX_Config = env.TDX_Config or {}

for key, value in pairs(config) do
    if env.TDX_Config[key] == nil then
        env.TDX_Config[key] = value
    end
end

local function getRetries()
    local mode = env.TDX_Config.PlaceMode or "Ashed"
    if mode == "Ashed" then return 1 end
    if mode == "Rewrite" then return 10 end
    return 1
end

local function safeReq(path, time)
    time = time or 5
    local start = tick()
    while tick() - start < time do
        local ok, result = pcall(function() return require(path) end)
        if ok and result then return result end
        run.RenderStepped:Wait()
    end
    return nil
end

local function loadTowers()
    local ps = player:FindFirstChild("PlayerScripts")
    if not ps then return nil end
    local client = ps:FindFirstChild("Client")
    if not client then return nil end
    local game = client:FindFirstChild("GameClass")
    if not game then return nil end
    local tower = game:FindFirstChild("TowerClass")
    if not tower then return nil end
    return safeReq(tower)
end

local towers = loadTowers()
if not towers then 
    error("Cannot load TowerClass")
end

task.spawn(function()
    while task.wait(0.5) do
        for hash, tower in pairs(towers.GetTowers()) do
            if tower.Converted == true then
                pcall(function() remotes.SellTower:FireServer(hash) end)
                task.wait(env.TDX_Config.MacroStepDelay)
            end
        end
    end
end)

local function getTower(x)
    for hash, tower in pairs(towers.GetTowers()) do
        local spawn = tower.SpawnCFrame
        if spawn and typeof(spawn) == "CFrame" then
            if spawn.Position.X == x then
                return hash, tower
            end
        end
    end
    return nil, nil
end

local function waitTower(x, time)
    time = time or 5
    local start = tick()
    while tick() - start < time do
        local hash, tower = getTower(x)
        if hash and tower and tower.LevelHandler then
            return hash, tower
        end
        run.RenderStepped:Wait()
    end
    return nil, nil
end

local function getUI()
    local tries = 0
    while tries < 30 do
        local ui = gui:FindFirstChild("Interface")
        if ui and ui.Parent then
            local bar = ui:FindFirstChild("GameInfoBar")
            if bar and bar.Parent then
                local wave = bar:FindFirstChild("Wave")
                local time = bar:FindFirstChild("TimeLeft")
                if wave and time and wave.Parent and time.Parent then
                    local waveText = wave:FindFirstChild("WaveText")
                    local timeText = time:FindFirstChild("TimeLeftText")
                    if waveText and timeText and waveText.Parent and timeText.Parent then
                        return { wave = waveText, time = timeText }
                    end
                end
            end
        end
        tries = tries + 1
        task.wait(1)
    end
    error("Cannot find Game UI")
end

local function timeFormat(num)
    local mins = math.floor(num / 100)
    local secs = num % 100
    return string.format("%02d:%02d", mins, secs)
end

local function parseTime(str)
    if not str then return nil end
    local mins, secs = str:match("(%d+):(%d+)")
    if mins and secs then
        return tonumber(mins) * 100 + tonumber(secs)
    end
    return nil
end

local function getPriority(name)
    for i, tower in ipairs(env.TDX_Config.PriorityRebuildOrder or {}) do
        if name == tower then return i end
    end
    return math.huge
end

local function sellAll(skip)
    local skipMap = {}
    if skip then for _, name in ipairs(skip) do skipMap[name] = true end end
    for hash, tower in pairs(towers.GetTowers()) do
        if not skipMap[tower.Type] then
            pcall(function() remotes.SellTower:FireServer(hash) end)
            task.wait(env.TDX_Config.MacroStepDelay)
        end
    end
end

local function getCost(tower, path)
    if not tower or not tower.LevelHandler then return nil end
    local max = tower.LevelHandler:GetMaxLevel()
    local cur = tower.LevelHandler:GetLevelOnPath(path)
    if cur >= max then return nil end
    local ok, base = pcall(function() return tower.LevelHandler:GetLevelUpgradeCost(path, 1) end)
    if not ok then return nil end
    local disc = 0
    pcall(function() disc = tower.BuffHandler and tower.BuffHandler:GetDiscount() or 0 end)
    return math.floor(base * (1 - disc))
end

local function waitCash(amount)
    while cash.Value < amount do run.RenderStepped:Wait() end
end

local function placeTower(args, x)
    for i = 1, getRetries() do
        pcall(function() remotes.PlaceTower:InvokeServer(unpack(args)) end)
        task.wait(env.TDX_Config.MacroStepDelay)
        local _, tower = waitTower(x, 3)
        if tower then return true end
    end
    return false
end

local function upgradeTower(x, path)
    for i = 1, getRetries() do
        local hash, tower = waitTower(x)
        if not hash then task.wait(env.TDX_Config.MacroStepDelay); continue end
        local before = tower.LevelHandler:GetLevelOnPath(path)
        local cost = getCost(tower, path)
        if not cost then return true end
        waitCash(cost)
        pcall(function() remotes.TowerUpgradeRequest:FireServer(hash, path, 1) end)
        task.wait(env.TDX_Config.MacroStepDelay)
        local start = tick()
        repeat
            run.RenderStepped:Wait()
            local _, t = getTower(x)
            if t and t.LevelHandler and t.LevelHandler:GetLevelOnPath(path) > before then return true end
        until tick() - start > 3
    end
    return false
end

local function changeTarget(x, target)
    for i = 1, getRetries() do
        local hash = getTower(x)
        if hash then
            pcall(function() remotes.ChangeQueryType:FireServer(hash, target) end)
            task.wait(env.TDX_Config.MacroStepDelay)
            return true
        end
        task.wait(env.TDX_Config.MacroStepDelay)
    end
    return false
end

local function skipWave()
    pcall(function() remotes.SkipWaveVoteCast:FireServer(true) end)
    task.wait(env.TDX_Config.MacroStepDelay)
    return true
end

local function useSkill(x, skill, pos)
    local req = remotes:FindFirstChild("TowerUseAbilityRequest")
    if not req then return false end
    local fire = req:IsA("RemoteEvent")

    for i = 1, getRetries() do
        local hash, tower = waitTower(x)
        if hash and tower and tower.AbilityHandler then
            local ability = tower.AbilityHandler:GetAbilityFromIndex(skill)
            if ability then
                local cd = ability.CooldownRemaining or 0
                if cd > 0 then task.wait(cd + 0.1) end

                local ok = false
                if pos == "no_pos" then
                    ok = pcall(function()
                        if fire then req:FireServer(hash, skill) else req:InvokeServer(hash, skill) end
                    end)
                else
                    local x, y, z = pos:match("([^,%s]+),%s*([^,%s]+),%s*([^,%s]+)")
                    if x and y and z then
                        local vec = Vector3.new(tonumber(x), tonumber(y), tonumber(z))
                        ok = pcall(function()
                            if fire then req:FireServer(hash, skill, vec) else req:InvokeServer(hash, skill, vec) end
                        end)
                    end
                end
                if ok then 
                    task.wait(env.TDX_Config.MacroStepDelay)
                    return true 
                end
            end
        end
        task.wait(env.TDX_Config.MacroStepDelay)
    end
    return false
end

local function sellTower(x)
    for i = 1, getRetries() do
        local hash = getTower(x)
        if hash then
            pcall(function() remotes.SellTower:FireServer(hash) end)
            task.wait(env.TDX_Config.MacroStepDelay)
            if not getTower(x) then return true end
        end
        task.wait(env.TDX_Config.MacroStepDelay)
    end
    return false
end

local function startMonitor(entries, ui)
    local processed = {}
    local skipAttempts = {}

    local function shouldRun(entry, wave, time)
        if entry.SkipWave then
            if skipAttempts[entry.SkipWave] then return false end
            if entry.SkipWave ~= wave then return false end
            if entry.SkipWhen then
                local timeNum = parseTime(time)
                if not timeNum or timeNum > entry.SkipWhen then return false end
            end
            return true
        end
        if entry.TowerTargetChange then
            if entry.TargetWave and entry.TargetWave ~= wave then return false end
            if entry.TargetChangedAt then
                if time ~= timeFormat(entry.TargetChangedAt) then return false end
            end
            return true
        end
        if entry.towermoving then
            if entry.wave and entry.wave ~= wave then return false end
            if entry.time then
                if time ~= timeFormat(entry.time) then return false end
            end
            return true
        end
        return false
    end

    local function runEntry(entry)
        if entry.SkipWave then
            skipAttempts[entry.SkipWave] = true
            if env.TDX_Config.AllowParallelSkips then task.spawn(skipWave) else return skipWave() end
            return true
        end
        if entry.TowerTargetChange then
            if env.TDX_Config.AllowParallelTargets then task.spawn(function() changeTarget(entry.TowerTargetChange, entry.TargetWanted) end) else return changeTarget(entry.TowerTargetChange, entry.TargetWanted) end
            return true
        end
        if entry.towermoving then
            return useSkill(entry.towermoving, entry.skillindex, entry.location)
        end
        return false
    end

    task.spawn(function()
        while true do
            local ok, wave, time = pcall(function() return ui.wave.Text, ui.time.Text end)
            if ok then
                for i, entry in ipairs(entries) do
                    if not processed[i] and shouldRun(entry, wave, time) then
                        if runEntry(entry) then
                            processed[i] = true
                        end
                    end
                end
            end
            task.wait(env.TDX_Config.MonitorCheckDelay or 0.1)
        end
    end)
end

local function startRebuild(rebuildEntry, records, skipMap)
    local cfg = env.TDX_Config
    local attempts, sold, jobs, active = {}, {}, {}, {}

    local function worker()
        task.spawn(function()
            while true do
                if #jobs > 0 then
                    local job = table.remove(jobs, 1)
                    local recs = job.records
                    local place, upgrades, targets, moves = nil, {}, {}, {}
                    for _, rec in ipairs(recs) do
                        local act = rec.entry
                        if act.TowerPlaced then place = rec
                        elseif act.TowerUpgraded then table.insert(upgrades, rec)
                        elseif act.TowerTargetChange then table.insert(targets, rec)
                        elseif act.towermoving then table.insert(moves, rec) end
                    end
                    local success = true
                    if place then
                        local act = place.entry; local coords = {}
                        for coord in act.TowerVector:gmatch("[^,%s]+") do table.insert(coords, tonumber(coord)) end
                        if #coords == 3 then
                            local pos = Vector3.new(coords[1], coords[2], coords[3])
                            local args = {tonumber(act.TowerA1), act.TowerPlaced, pos, tonumber(act.Rotation or 0)}
                            waitCash(act.TowerPlaceCost)
                            if not placeTower(args, pos.X) then success = false end
                        end
                    end
                    if success then
                        table.sort(upgrades, function(a, b) return a.line < b.line end)
                        for _, rec in ipairs(upgrades) do
                            if not upgradeTower(tonumber(rec.entry.TowerUpgraded), rec.entry.UpgradePath) then success = false; break end
                        end
                    end
                    if success and #moves > 0 then
                        task.spawn(function()
                            local last = moves[#moves].entry
                            useSkill(last.towermoving, last.skillindex, last.location)
                        end)
                    end
                    if success then
                        for _, rec in ipairs(targets) do
                            changeTarget(tonumber(rec.entry.TowerTargetChange), rec.entry.TargetWanted)
                        end
                    end
                    active[job.x] = nil
                else
                    run.RenderStepped:Wait()
                end
            end
        end)
    end

    for i = 1, cfg.MaxConcurrentRebuilds do worker() end

    task.spawn(function()
        while true do
            local existing = {}
            for hash, tower in pairs(towers.GetTowers()) do
                if tower.SpawnCFrame and typeof(tower.SpawnCFrame) == "CFrame" then
                    existing[tower.SpawnCFrame.Position.X] = true
                end
            end
            local added = false
            for x, recs in pairs(records) do
                if not existing[x] and not active[x] and not (cfg.ForceRebuildEvenIfSold == false and sold[x]) then
                    local type, first = nil, nil
                    for _, rec in ipairs(recs) do
                        if rec.entry.TowerPlaced then type, first = rec.entry.TowerPlaced, rec; break end
                    end
                    if type then
                        local skip = skipMap[type]
                        local shouldSkip = false
                        if skip then
                            if skip.beOnly and first.line < skip.fromLine then shouldSkip = true
                            elseif not skip.beOnly then shouldSkip = true end
                        end
                        if not shouldSkip then
                            attempts[x] = (attempts[x] or 0) + 1
                            if not cfg.MaxRebuildRetry or attempts[x] <= cfg.MaxRebuildRetry then
                                active[x] = true
                                table.insert(jobs, { x = x, records = recs, priority = getPriority(type), death = tick() })
                                added = true
                            end
                        end
                    end
                end
            end
            if added and #jobs > 1 then
                table.sort(jobs, function(a, b) 
                    if a.priority == b.priority then return a.death < b.death end
                    return a.priority < b.priority 
                end)
            end
            task.wait(cfg.RebuildCheckInterval or 0)
        end
    end)
end

local function runMacro()
    local cfg = env.TDX_Config
    local name = cfg["Macro Name"] or "event"
    local path = "tdx/macros/" .. name .. ".json"
    if not fileExists(path) then error("Macro not found: " .. path) end
    local content = readFile(path)
    if not content then error("Cannot read macro") end
    local ok, macro = pcall(function() return http:JSONDecode(content) end)
    if not ok or type(macro) ~= "table" then error("Cannot parse macro") end

    local ui, records, skipMap, monitors, rebuildActive = getUI(), {}, {}, {}, false

    for i, entry in ipairs(macro) do
        if entry.TowerTargetChange or entry.towermoving or entry.SkipWave then table.insert(monitors, entry) end
    end
    if #monitors > 0 then startMonitor(monitors, ui) end

    for i, entry in ipairs(macro) do
        if entry.SuperFunction == "sell_all" then sellAll(entry.Skip)
        elseif entry.SuperFunction == "rebuild" then
            if not rebuildActive then
                for _, skip in ipairs(entry.Skip or {}) do skipMap[skip] = { beOnly = entry.Be == true, fromLine = i } end
                startRebuild(entry, records, skipMap)
                rebuildActive = true
            end
        elseif entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then
            local coords = {}; for coord in entry.TowerVector:gmatch("[^,%s]+") do table.insert(coords, tonumber(coord)) end
            if #coords == 3 then
                local pos = Vector3.new(coords[1], coords[2], coords[3])
                local args = {tonumber(entry.TowerA1), entry.TowerPlaced, pos, tonumber(entry.Rotation or 0)}
                waitCash(entry.TowerPlaceCost)
                placeTower(args, pos.X)
                records[pos.X] = records[pos.X] or {}; table.insert(records[pos.X], { line = i, entry = entry })
            end
        elseif entry.TowerUpgraded and entry.UpgradePath then
            local x = tonumber(entry.TowerUpgraded)
            upgradeTower(x, entry.UpgradePath)
            records[x] = records[x] or {}; table.insert(records[x], { line = i, entry = entry })
        elseif entry.TowerTargetChange and entry.TargetWanted then
            local x = tonumber(entry.TowerTargetChange)
            records[x] = records[x] or {}; table.insert(records[x], { line = i, entry = entry })
        elseif entry.SellTower then
            local x = tonumber(entry.SellTower)
            sellTower(x)
            records[x] = nil
        elseif entry.towermoving and entry.skillindex and entry.location then
            local x = entry.towermoving
            records[x] = records[x] or {}; table.insert(records[x], { line = i, entry = entry })
        end
        task.wait(env.TDX_Config.MacroStepDelay)
    end
end

pcall(runMacro)