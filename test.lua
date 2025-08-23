-- Auto Quest Accept Script
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

-- Remotes
local CheckDialogue = ReplicatedStorage.ReplicatedModules.KnitPackage.Knit.Services.DialogueService.RF.CheckDialogue
local QuestLineService = require(ReplicatedStorage.ReplicatedModules.KnitPackage.Knit).GetService("QuestLineService")

-- Cấu hình quest muốn nhận
local QUEST_CONFIG = {
    questLine = "Slayer_Quest",
    preferredQuests = {
        "Finger Bearer",  -- Ưu tiên cao nhất
        "Gojo",          -- Ưu tiên trung bình  
        "Xeno"           -- Ưu tiên thấp
    }
}

-- Hàm kiểm tra level của player
local function getPlayerAbilityLevel()
    if player.Data and player.Data.Ability then
        return player.Data.Ability:GetAttribute("AbilityLevel") or 0
    end
    return 0
end

-- Hàm lấy thông tin questline
local function getQuestlineInfo()
    local success, questInfo = pcall(function()
        return QuestLineService:GetQuestlineInfo(QUEST_CONFIG.questLine):expect()
    end)
    
    if success and questInfo then
        return questInfo
    end
    return nil
end

-- Hàm kiểm tra quest có sẵn sàng không
local function checkQuestAvailability(questName)
    local success, result = pcall(function()
        return CheckDialogue:InvokeServer(QUEST_CONFIG.questLine, questName)
    end)
    
    if not success then
        return false, "Error checking quest"
    end
    
    -- result có thể là:
    -- true = có thể nhận quest
    -- false = không đủ điều kiện  
    -- number = thời gian cooldown (giây)
    if result == true then
        return true, "Ready"
    elseif result == false then
        return false, "Not eligible"
    elseif type(result) == "number" then
        local minutes = math.floor(result / 60)
        local seconds = result % 60
        return false, string.format("Cooldown: %02d:%02d", minutes, seconds)
    end
    
    return false, "Unknown status"
end

-- Hàm nhận quest
local function acceptQuest(questName)
    -- Sử dụng CheckDialogue để nhận quest (dựa trên logic trong code gốc)
    local success, result = pcall(function()
        return CheckDialogue:InvokeServer(QUEST_CONFIG.questLine, questName)
    end)
    
    if success and result == true then
        print("✅ Đã nhận quest:", questName)
        return true
    else
        print("❌ Không thể nhận quest:", questName, "Result:", result)
        return false
    end
end

-- Hàm tìm và nhận quest phù hợp
local function findAndAcceptQuest()
    local questInfo = getQuestlineInfo()
    if not questInfo or not questInfo.Metadata or not questInfo.Metadata.Slayers then
        print("❌ Không tìm thấy thông tin quest")
        return false
    end
    
    local playerLevel = getPlayerAbilityLevel()
    print("🎯 Player Level:", playerLevel)
    
    local availableQuests = {}
    
    -- Kiểm tra từng quest trong danh sách ưu tiên
    for priority, questName in ipairs(QUEST_CONFIG.preferredQuests) do
        local slayerInfo = questInfo.Metadata.Slayers[questName]
        
        if slayerInfo then
            local requiredLevel = slayerInfo.Level or 0
            
            -- Kiểm tra level requirement
            if playerLevel >= requiredLevel then
                local canAccept, status = checkQuestAvailability(questName)
                
                print(string.format("Quest: %s (Level %d+) - %s", questName, requiredLevel, status))
                
                if canAccept then
                    table.insert(availableQuests, {
                        name = questName,
                        priority = priority,
                        level = requiredLevel
                    })
                end
            else
                print(string.format("Quest: %s (Level %d+) - Not high enough level", questName, requiredLevel))
            end
        end
    end
    
    -- Nhận quest có ưu tiên cao nhất
    if #availableQuests > 0 then
        -- Sort theo priority (thấp hơn = ưu tiên cao hơn)
        table.sort(availableQuests, function(a, b)
            return a.priority < b.priority
        end)
        
        local bestQuest = availableQuests[1]
        print("🎯 Attempting to accept quest:", bestQuest.name)
        return acceptQuest(bestQuest.name)
    else
        print("❌ Không có quest nào khả dụng")
        return false
    end
end

-- Hàm hiển thị trạng thái tất cả quest
local function showQuestStatus()
    print("=== QUEST STATUS ===")
    local questInfo = getQuestlineInfo()
    if not questInfo then
        print("❌ Không tìm thấy quest info")
        return
    end
    
    local playerLevel = getPlayerAbilityLevel()
    print("Player Level:", playerLevel)
    print("Current Quest Step:", questInfo.Step or "None")
    
    for _, questName in ipairs(QUEST_CONFIG.preferredQuests) do
        local slayerInfo = questInfo.Metadata.Slayers[questName]
        if slayerInfo then
            local canAccept, status = checkQuestAvailability(questName)
            local levelReq = slayerInfo.Level or 0
            local eligible = playerLevel >= levelReq
            
            print(string.format("%s (Lv%d+): %s %s", 
                questName, 
                levelReq, 
                status,
                eligible and "✅" or "❌"
            ))
        end
    end
    print("==================")
end

-- Auto loop
spawn(function()
    wait(5) -- Đợi game load
    
    while true do
        pcall(function()
            findAndAcceptQuest()
        end)
        
        wait(30) -- Check mỗi 30 giây
    end
end)

-- Export functions
_G.AcceptQuest = findAndAcceptQuest
_G.QuestStatus = showQuestStatus

print("🚀 Auto Quest Accept loaded!")
print("Functions: _G.AcceptQuest(), _G.QuestStatus()")
print("Preferred quests:", table.concat(QUEST_CONFIG.preferredQuests, ", "))