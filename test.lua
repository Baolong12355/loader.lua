local replStorage = game:GetService("ReplicatedStorage")
local remotes = replStorage:WaitForChild("Remotes")
local TowerUseAbilityRequest = remotes:WaitForChild("TowerUseAbilityRequest")
local localPlayer = game:GetService("Players").LocalPlayer

-- Cache lưu trữ skill data
local skillCache = {}
local cacheIndex = 1

-- Moving skills cần track (Helio skill 1,3 và Cryo Helio, Jet Trooper skill 1)
local MOVING_SKILLS = {
    [1] = "Helio Skill 1",
    [3] = "Helio Skill 3", 
    [1] = "Cryo Helio Skill 1",
    [1] = "Jet Trooper Skill 1"
}

-- Hàm lấy wave hiện tại
local function getCurrentWave()
    -- Logic lấy wave từ game (cần adapt theo game structure)
    local gameState = replStorage:FindFirstChild("GameState")
    if gameState and gameState:FindFirstChild("Wave") then
        return gameState.Wave.Value
    end
    return 1
end

-- Hàm lấy thời gian game
local function getGameTime()
    return tick()
end

-- Hàm kiểm tra skill có phải moving skill không
local function isMovingSkill(skillIndex, towerHash)
    -- Logic kiểm tra dựa trên tower type và skill index
    return MOVING_SKILLS[skillIndex] ~= nil
end

-- Biến lưu hàm gốc
local originalInvokeServer

-- Hook function chính
local function setupMovingSkillHook()
    -- Hook namecall để bắt TowerUseAbilityRequest
    local originalNamecall
    originalNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        
        if method == "InvokeServer" and self == TowerUseAbilityRequest then
            local args = {...}
            local towerHash = args[1]
            local skillIndex = args[2] 
            local targetPos = args[3]
            
            -- Kiểm tra nếu là moving skill
            if isMovingSkill(skillIndex, towerHash) then
                -- Lưu vào cache trước
                local skillData = {
                    towermoving = towerHash,
                    skillIndex = skillIndex,
                    location = targetPos,
                    wave = getCurrentWave(),
                    time = getGameTime(),
                    timestamp = os.time()
                }
                
                skillCache[cacheIndex] = skillData
                cacheIndex = cacheIndex + 1
                
                -- In thông tin record
                print(string.format("🎯 [Moving Skill Recorded] Tower: %d | Skill: %d | Pos: %s | Wave: %d | Time: %.2f",
                    towerHash, skillIndex, tostring(targetPos), skillData.wave, skillData.time))
                
                -- Gọi hàm xử lý cache sau khi lưu
                spawn(function()
                    wait(0.1) -- Delay nhỏ để đảm bảo data đã lưu
                    processSkillCache()
                end)
            end
            
            -- Return kết quả từ server
            local result = originalNamecall(self, ...)
            return result
        end
        
        return originalNamecall(self, ...)
    end)
    
    print("✅ Moving Skill Hook với Recorder đã kích hoạt")
end

-- Hàm xử lý cache đã lưu
function processSkillCache()
    if #skillCache == 0 then return end
    
    print(string.format("📊 [Processing Cache] Có %d skills trong cache", #skillCache))
    
    for i, skillData in pairs(skillCache) do
        -- Format output như yêu cầu
        print(string.format([[
🎮 [Skill Record #%d]
towermoving = %d
skill index = %d  
location = %s
wave = %d
time = %.2f
        ]], i, skillData.towermoving, skillData.skillIndex, 
            tostring(skillData.location), skillData.wave, skillData.time))
        
        -- Có thể thêm logic xử lý khác ở đây
        -- Ví dụ: ghi vào file, gửi lên server, etc.
    end
end

-- Hàm replay skill từ cache
function replaySkillFromCache(index)
    if not skillCache[index] then
        print("❌ Không tìm thấy skill data tại index: " .. tostring(index))
        return false
    end
    
    local skillData = skillCache[index]
    local args = {
        skillData.towermoving,
        skillData.skillIndex,
        skillData.location
    }
    
    print(string.format("🔄 [Replaying Skill] Tower: %d | Skill: %d | Pos: %s", 
        args[1], args[2], tostring(args[3])))
    
    -- Execute skill
    local success, result = pcall(function()
        return TowerUseAbilityRequest:InvokeServer(unpack(args))
    end)
    
    if success then
        print("✅ Skill replay thành công")
        return result
    else
        print("❌ Skill replay thất bại: " .. tostring(result))
        return false
    end
end

-- Hàm export cache thành script format
function exportCacheAsScript()
    if #skillCache == 0 then
        print("📝 Cache trống - không có gì để export")
        return
    end
    
    print("📝 [Exporting Cache as Script Format]")
    print("-- Generated Moving Skills Script --")
    
    for i, skillData in pairs(skillCache) do
        print(string.format([[
-- Skill Record #%d (Wave: %d, Time: %.2f)
local args = {
    %d, -- tower hash
    %d, -- skill index  
    Vector3.new(%.6f, %.6f, %.6f) -- target position
}
game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("TowerUseAbilityRequest"):InvokeServer(unpack(args))
wait(0.1)
        ]], i, skillData.wave, skillData.time,
            skillData.towermoving, skillData.skillIndex,
            skillData.location.X, skillData.location.Y, skillData.location.Z))
    end
end

-- Utility functions
function clearCache()
    skillCache = {}
    cacheIndex = 1
    print("🗑️ Cache đã được xóa")
end

function getCacheSize()
    return #skillCache
end

function printCacheStats()
    print(string.format("📈 [Cache Stats] Size: %d | Last Index: %d", #skillCache, cacheIndex - 1))
end

-- Khởi tạo hook
setupMovingSkillHook()

-- Export các function để sử dụng
_G.SkillRecorder = {
    processCache = processSkillCache,
    replaySkill = replaySkillFromCache,
    exportScript = exportCacheAsScript,
    clearCache = clearCache,
    getCacheSize = getCacheSize,
    printStats = printCacheStats,
    getCache = function() return skillCache end
}

print("🚀 Moving Skill Recorder khởi tạo hoàn tất!")
print("📋 Sử dụng: _G.SkillRecorder.exportScript() để export cache")
print("🔄 Sử dụng: _G.SkillRecorder.replaySkill(index) để replay skill")