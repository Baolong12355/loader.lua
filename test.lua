local function checkQuestStatus(slayerName)-- AUTO SLAYER QUEST SCRIPT - SIMPLIFIED
-- Automatically accepts selected Slayer quest when not on cooldown and player meets level requirements

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.ReplicatedModules.KnitPackage.Knit)

local LocalPlayer = Players.LocalPlayer
local QuestLineService = Knit.GetService("QuestLineService")
local CheckDialogue = ReplicatedStorage.ReplicatedModules.KnitPackage.Knit.Services.DialogueService.RF.CheckDialogue

-- ===== CONFIG =====
local CONFIG = {
    ENABLED = true,
    SELECTED_QUEST = "Gojo", -- Change this to your desired quest: "Gojo", "Finger Bearer", "Xeno"
    CHECK_INTERVAL = 1, -- Check every 30 seconds
    DEBUG = true
}

-- ===== FUNCTIONS =====
local function debugPrint(message)
    if CONFIG.DEBUG then
        print("[SLAYER QUEST] " .. message)
    end
end

local function getPlayerLevel()
    local success, level = pcall(function()
        return LocalPlayer.Data.Ability:GetAttribute("AbilityLevel")
    end)
    
    if success and level then
        debugPrint("Current player level: " .. tostring(level))
        return level
    end
    
    debugPrint("Failed to retrieve player level")
    return 0
end

local function getAvailableQuests()
    local success, questInfo = pcall(function()
        return QuestLineService:GetQuestlineInfo("Slayer_Quest"):expect()
    end)
    
    if not success then
        debugPrint("Lỗi khi lấy thông tin quest: " .. tostring(questInfo))
        return {}
    end
    
    if not questInfo or not questInfo.Metadata or not questInfo.Metadata.Slayers then
        debugPrint("Không tìm thấy dữ liệu Slayers")
        return {}
    end
    
    local playerLevel = getPlayerLevel()
    local availableQuests = {}
    
    debugPrint("Kiểm tra quest khả dụng cho level: " .. playerLevel)
    
    -- Duyệt qua tất cả slayers (key-value pairs)
    for questKey, slayerData in pairs(questInfo.Metadata.Slayers) do
        if slayerData and slayerData.Level then
            local requiredLevel = slayerData.Level
            local slayerName = slayerData.Slayer or questKey
            
            if playerLevel >= requiredLevel then
                debugPrint("Có thể nhận: " .. questKey .. " (" .. slayerName .. ") - Level " .. requiredLevel)
                table.insert(availableQuests, questKey)
            else
                debugPrint("Chưa đủ level: " .. questKey .. " (" .. slayerName .. ") - Cần level " .. requiredLevel)
            end
        else
            debugPrint("Dữ liệu không hợp lệ cho: " .. tostring(questKey))
        end
    end
    
    return availableQuests
end
    local success, result = pcall(function()
        return CheckDialogue:InvokeServer("Slayer_Quest", slayerName)
    end)
    
    if not success then
        return "error"
    elseif result == false then
        return "level_too_low"
    elseif type(result) == "number" then
        return "cooldown", result
    elseif result == true then
        return "available"
    end
    
    return "unknown"
end

local function isLevelSufficient(slayerName)
    local questInfo = QuestLineService:GetQuestlineInfo("Slayer_Quest"):expect()
    if not questInfo or not questInfo.Metadata or not questInfo.Metadata.Slayers then
        return false
    end
    
    local slayerData = questInfo.Metadata.Slayers[slayerName]
    if not slayerData then
        return false
    end
    
    local playerLevel = getPlayerLevel()
    return playerLevel >= slayerData.Level
end

local function attemptAcceptQuest()
    debugPrint("Getting available quests...")
    local availableQuests = getAvailableQuests()
    
    if #availableQuests == 0 then
        debugPrint("No quests available for current level")
        return false
    end
    
    debugPrint("Available quests: " .. table.concat(availableQuests, ", "))
    
    -- Check if selected quest is available
    local questFound = false
    for _, questName in ipairs(availableQuests) do
        if questName == CONFIG.SELECTED_QUEST then
            questFound = true
            break
        end
    end
    
    if not questFound then
        debugPrint("Selected quest not available: " .. CONFIG.SELECTED_QUEST)
        return false
    end
    
    debugPrint("Checking quest: " .. CONFIG.SELECTED_QUEST)
    
    local status, cooldownTime = checkQuestStatus(CONFIG.SELECTED_QUEST)
    
    if status == "available" then
        debugPrint("Successfully accepted: " .. CONFIG.SELECTED_QUEST)
        return true
    elseif status == "cooldown" then
        local minutes = math.floor(cooldownTime / 60)
        local seconds = cooldownTime % 60
        debugPrint(string.format("Quest on cooldown: %02d:%02d remaining", minutes, seconds))
    elseif status == "level_too_low" then
        debugPrint("Level requirement not met")
    else
        debugPrint("Quest unavailable: " .. status)
    end
    
    return false
end

-- ===== MAIN LOOP =====
spawn(function()
    debugPrint("Auto Slayer Quest started for: " .. CONFIG.SELECTED_QUEST)
    
    while CONFIG.ENABLED do
        attemptAcceptQuest()
        wait(CONFIG.CHECK_INTERVAL)
    end
end)