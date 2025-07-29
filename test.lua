-- Script: recorder_moving_skill.lua
-- Mục đích: Ghi log các lần sử dụng skill di chuyển (moving skill) cho các tower Helio, Cryo Helio, Jet Trooper (skill 1,3), Cryo Helio (skill 1)
-- Format xuất ra:
-- towermoving = <hash>
-- <skill_index>
-- location = <pos>
-- wave
-- time

local replStorage = game:GetService("ReplicatedStorage")
local remotes = replStorage:WaitForChild("Remotes")
local TowerUseAbilityRequest = remotes:WaitForChild("TowerUseAbilityRequest")
local localPlayer = game:GetService("Players").LocalPlayer

-- Cấu hình các tower và skill index cần log
local TOWER_MOVING_SKILL = {
    ["Helicopter"] = {1, 3},
    ["Cryo Helicopter"] = {1},
    ["Jet Trooper"] = {1},
}

-- File log (có thể chỉnh lại đường dẫn)
local outFile = "tdx/moving_skill_log.txt"

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

local function writeLog(hash, skillIdx, pos, wave, time)
    local logLine = (
        "towermoving=" .. tostring(hash) .. "\n" ..
        tostring(skillIdx) .. "\n" ..
        "location=" .. tostring(pos) .. "\n" ..
        "wave=" .. tostring(wave) .. "\n" ..
        "time=" .. tostring(time) .. "\n\n"
    )
    if appendfile then
        appendfile(outFile, logLine)
    else
        print("[MovingSkillLog]", logLine)
    end
end

-- Lấy type tower theo hash (dựa vào TowerClass nếu có)
local function getTowerTypeByHash(hash)
    local success, TowerClass = pcall(function()
        local ps = localPlayer:FindFirstChild("PlayerScripts")
        local client = ps and ps:FindFirstChild("Client")
        local gameClass = client and client:FindFirstChild("GameClass")
        local towerModule = gameClass and gameClass:FindFirstChild("TowerClass")
        return require(towerModule)
    end)
    if success and TowerClass and TowerClass.GetTowers then
        local towers = TowerClass.GetTowers()
        local tower = towers and towers[hash]
        if tower then return tower.Type or tower.Name end
    end
    return nil
end

-- Hook __namecall chuẩn, đảm bảo skill vẫn hoạt động
local mt = getrawmetatable(game)
local oldNamecall = mt.__namecall
setreadonly(mt, false)
mt.__namecall = function(self, ...)
    if getnamecallmethod() == "InvokeServer" and self == TowerUseAbilityRequest and not checkcaller() then
        local args = {...}
        local hash = args[1]
        local skillIdx = args[2]
        local pos = args[3]
        local ttype = getTowerTypeByHash(hash)
        if ttype and TOWER_MOVING_SKILL[ttype] then
            for _, idx in ipairs(TOWER_MOVING_SKILL[ttype]) do
                if skillIdx == idx then
                    local wave, time = getWaveAndTime()
                    writeLog(hash, skillIdx, pos, wave, time)
                    break
                end
            end
        end
    end
    return oldNamecall(self, ...)
end
setreadonly(mt, true)

print("✅ Recorder Moving Skill đã hoạt động - Sẽ log các lần dùng skill di chuyển của Helio, Cryo Helio, Jet Trooper!")