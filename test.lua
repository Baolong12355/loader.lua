-- Recorder Moving Skill (Axis X, chuẩn hookfunction + namecall như main)
-- Chỉ log Helio (1,3), Cryo Helio (1), Jet Trooper (1)
-- Định dạng log chuẩn recorder/runner

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local TowerUseAbilityRequest = Remotes:WaitForChild("TowerUseAbilityRequest")

local outFile = "tdx/moving_skill_log.txt"

local TOWER_MOVING_SKILL = {
    ["Helicopter"] = {1, 3},
    ["Cryo Helicopter"] = {1},
    ["Jet Trooper"] = {1},
}

local function getWaveAndTime()
    local gui = localPlayer:FindFirstChildOfClass("PlayerGui")
    if not gui then return "?", "?" end
    local interface = gui:FindFirstChild("Interface")
    if not interface then return "?", "?" end
    local gameInfoBar = interface:FindFirstChild("GameInfoBar")
    if not gameInfoBar then return "?", "?" end
    local wave = gameInfoBar:FindFirstChild("Wave")
    local timeLeft = gameInfoBar:FindFirstChild("TimeLeft")
    if not wave or not timeLeft then return "?", "?" end
    local waveText = wave:FindFirstChild("WaveText")
    local timeText = timeLeft:FindFirstChild("TimeLeftText")
    return waveText and waveText.Text or "?", timeText and timeText.Text or "?"
end

local function serializePos(pos)
    if typeof(pos) == "Vector3" then
        return string.format("%0.6f,%0.6f,%0.6f", pos.X, pos.Y, pos.Z)
    elseif typeof(pos) == "CFrame" then
        local p = pos.Position
        return string.format("%0.6f,%0.6f,%0.6f", p.X, p.Y, p.Z)
    end
    return tostring(pos)
end

local function getTowerTypeAndObjByHash(hash)
    local TowerClass
    local success = pcall(function()
        local ps = localPlayer:FindFirstChild("PlayerScripts")
        local client = ps and ps:FindFirstChild("Client")
        local gameClass = client and client:FindFirstChild("GameClass")
        local towerModule = gameClass and gameClass:FindFirstChild("TowerClass")
        TowerClass = towerModule and require(towerModule)
    end)
    if success and TowerClass and TowerClass.GetTowers then
        local towers = TowerClass.GetTowers()
        local tower = towers and towers[hash]
        if tower then
            return tower.Type or tower.Name, tower
        end
    end
    return nil
end

local function getAxisXByHash(hash)
    local _, tower = getTowerTypeAndObjByHash(hash)
    if tower then
        local ok, pos = pcall(function()
            if tower.GetPosition then
                return tower:GetPosition()
            elseif tower.CFrame then
                return tower.CFrame.Position
            end
        end)
        if ok and pos and typeof(pos) == "Vector3" then
            return string.format("%0.6f", pos.X)
        end
    end
    return "?"
end

local function writeLog(axisX, skillIdx, pos, wave, time)
    local logLine =
        "towermoving=" .. tostring(axisX) .. "\n" ..
        tostring(skillIdx) .. "\n" ..
        "location=" .. serializePos(pos) .. "\n" ..
        tostring(wave) .. "\n" ..
        tostring(time) .. "\n\n"
    if appendfile then
        appendfile(outFile, logLine)
    else
        print("[MovingSkillLog]", logLine)
    end
end

-- HOOKFUNCTION lên RemoteFunction để giữ đúng logic game!
local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
    -- Chỉ log, không can thiệp trả về
    if self == TowerUseAbilityRequest then
        local args = {...}
        local hash, skillIdx, pos = args[1], args[2], args[3]
        local ttype = getTowerTypeAndObjByHash(hash)
        if ttype and TOWER_MOVING_SKILL[ttype] then
            for _, idx in ipairs(TOWER_MOVING_SKILL[ttype]) do
                if skillIdx == idx then
                    local axisX = getAxisXByHash(hash)
                    local wave, time = getWaveAndTime()
                    writeLog(axisX, skillIdx, pos, wave, time)
                    break
                end
            end
        end
    end
    return oldInvokeServer(self, ...)
end)

-- HOOKMETAMETHOD namecall như trong hook.lua
local oldNameCall
oldNameCall = hookmetamethod(game, "__namecall", function(self, ...)
    if not checkcaller()
        and self == TowerUseAbilityRequest
        and getnamecallmethod() == "InvokeServer"
    then
        local args = {...}
        local hash, skillIdx, pos = args[1], args[2], args[3]
        local ttype = getTowerTypeAndObjByHash(hash)
        if ttype and TOWER_MOVING_SKILL[ttype] then
            for _, idx in ipairs(TOWER_MOVING_SKILL[ttype]) do
                if skillIdx == idx then
                    local axisX = getAxisXByHash(hash)
                    local wave, time = getWaveAndTime()
                    writeLog(axisX, skillIdx, pos, wave, time)
                    break
                end
            end
        end
    end
    return oldNameCall(self, ...)
end)

print("✅ Recorder Moving Skill (axis X, hookfunction + namecall CHUẨN main) đã hoạt động!")