-- Recorder Moving Skill (TDX)
-- Log skill di chuyển cho Helio (1,3), Cryo Helio (1), Jet Trooper (1)
-- Format record:
-- towermoving=<hash>
-- <skill_index>
-- location=<pos>
-- wave
-- time

local replStorage = game:GetService("ReplicatedStorage")
local remotes = replStorage:WaitForChild("Remotes")
local TowerUseAbilityRequest = remotes:WaitForChild("TowerUseAbilityRequest")
local localPlayer = game:GetService("Players").LocalPlayer

-- Cấu hình skill cần ghi
local MOVING_SKILL = {
    ["Helicopter"] = {1, 3},
    ["Cryo Helicopter"] = {1},
    ["Jet Trooper"] = {1},
}
local LOG_PATH = "tdx/moving_skill_log.txt"

-- Xác định loại tower từ hash
local function getTowerTypeByHash(hash)
    local TowerClass
    pcall(function()
        local ps = localPlayer:FindFirstChild("PlayerScripts")
        local client = ps and ps:FindFirstChild("Client")
        local gameClass = client and client:FindFirstChild("GameClass")
        local towerModule = gameClass and gameClass:FindFirstChild("TowerClass")
        TowerClass = towerModule and require(towerModule)
    end)
    if TowerClass and TowerClass.GetTowers then
        local towers = TowerClass.GetTowers()
        local tw = towers and towers[hash]
        return tw and (tw.Type or tw.Name)
    end
end

-- Lấy wave và time hiện tại
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

-- Ghi log
local function writeLog(hash, skillIdx, pos, wave, time)
    local logLine = (
        "towermoving=" .. tostring(hash) .. "\n" ..
        tostring(skillIdx) .. "\n" ..
        "location=" .. tostring(pos) .. "\n" ..
        "wave=" .. tostring(wave) .. "\n" ..
        "time=" .. tostring(time) .. "\n\n"
    )
    if appendfile then
        appendfile(LOG_PATH, logLine)
    else
        print("[MovingSkillLog]", logLine)
    end
end

-- # HOOK invokeServer/namecall và cache/log ngay khi gọi, không delay xác nhận!
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    if getnamecallmethod() == "InvokeServer" and self == TowerUseAbilityRequest and not checkcaller() then
        local args = {...}
        local hash, skillIdx, pos = args[1], args[2], args[3]
        local ttype = getTowerTypeByHash(hash)
        if ttype and MOVING_SKILL[ttype] then
            for _, idx in ipairs(MOVING_SKILL[ttype]) do
                if skillIdx == idx then
                    local wave, time = getWaveAndTime()
                    writeLog(hash, skillIdx, pos, wave, time)
                    break
                end
            end
        end
    end
    return oldNamecall(self, ...)
end)

print("✅ Recorder Moving Skill HOOKED - Ghi log skill di chuyển Helio/Cryo Helio/Jet Trooper (dùng namecall, record tức thì)")