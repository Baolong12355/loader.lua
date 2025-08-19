-- Auto Feed Shards Script (Skip Max Level Abilities)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Remotes
local GetAllAbilityShards = ReplicatedStorage.ReplicatedModules.KnitPackage.Knit.Services.CraftingService.RF.GetAllAbilityShards
local ConsumeShardsForXP = ReplicatedStorage.ReplicatedModules.KnitPackage.Knit.Services.LevelService.RF.ConsumeShardsForXP
local GetAbilityPVEInfo = ReplicatedStorage.ReplicatedModules.KnitPackage.Knit.Services.LevelService.RF.GetAbilityPVEInfo

local function feedAllShards()
    print("[DEBUG] Bắt đầu feedAllShards")
    
    -- Lấy tất cả shards hiện có
    local success, allShards = pcall(function()
        return GetAllAbilityShards:InvokeServer()
    end)

    if not success then
        print("[DEBUG] Lỗi khi lấy shards:", allShards)
        return
    end
    
    if not allShards then 
        print("[DEBUG] allShards = nil")
        return 
    end
    
    print("[DEBUG] Đã lấy được shards")
    
    -- Đếm tổng số abilities có shards
    local totalAbilitiesWithShards = 0
    for abilityId, shardInfo in pairs(allShards) do
        if shardInfo.Shards and shardInfo.Shards > 0 then
            totalAbilitiesWithShards = totalAbilitiesWithShards + 1
        end
    end
    print("[DEBUG] Tổng abilities có shards:", totalAbilitiesWithShards)
      
    -- Tạo bảng feed chỉ những abilities chưa max level  
    local shardsToFeed = {}
    local processedCount = 0
    local addedToFeed = 0
    local skippedMaxLevel = 0
    local skippedNoShards = 0
    local errorCount = 0
      
    for abilityId, shardInfo in pairs(allShards) do
        processedCount = processedCount + 1
        print("[DEBUG] Xử lý ability", processedCount .. "/" .. totalAbilitiesWithShards, "- ID:", abilityId, "- Shards:", shardInfo.Shards or "nil")
        
        if shardInfo.Shards and shardInfo.Shards > 0 then  
            -- Kiểm tra level của ability  
            local abilitySuccess, abilityInfo = pcall(function()  
                return GetAbilityPVEInfo:InvokeServer(abilityId)  
            end)
            
            if not abilitySuccess then
                errorCount = errorCount + 1
                print("[DEBUG] ❌ Lỗi khi lấy info ability", abilityId, ":", abilityInfo)
            elseif not abilityInfo then
                errorCount = errorCount + 1
                print("[DEBUG] ❌ abilityInfo = nil cho ability", abilityId)
            else
                print("[DEBUG] Raw abilityInfo:", game:GetService("HttpService"):JSONEncode(abilityInfo))
                
                -- Thử các cách khác nhau để lấy level
                local currentLevel = nil
                if abilityInfo.CurrentLevel then
                    currentLevel = abilityInfo.CurrentLevel
                elseif abilityInfo[1] and abilityInfo[1].CurrentLevel then
                    currentLevel = abilityInfo[1].CurrentLevel
                elseif abilityInfo.Level then
                    currentLevel = abilityInfo.Level
                end
                
                print("[DEBUG] Current Level tìm được:", currentLevel)
                
                if currentLevel and currentLevel < 200 then  
                    shardsToFeed[abilityId] = shardInfo.Shards
                    addedToFeed = addedToFeed + 1
                    print("[DEBUG] ✅ Thêm vào feed - Ability ID:", abilityId, "Level:", currentLevel, "Shards:", shardInfo.Shards)
                else
                    skippedMaxLevel = skippedMaxLevel + 1
                    print("[DEBUG] ❌ Bỏ qua (max level hoặc không có level) - Ability ID:", abilityId, "Level:", currentLevel or "nil")
                end
            end
        else
            skippedNoShards = skippedNoShards + 1
            print("[DEBUG] Bỏ qua (không có shards) - Ability ID:", abilityId)
        end  
    end
    
    print("[DEBUG] === TỔNG KẾT ===")
    print("[DEBUG] Đã xử lý:", processedCount, "abilities")
    print("[DEBUG] Có shards:", totalAbilitiesWithShards)
    print("[DEBUG] Không có shards:", skippedNoShards)
    print("[DEBUG] Lỗi khi lấy info:", errorCount)
    print("[DEBUG] Bỏ qua (max level):", skippedMaxLevel)
    print("[DEBUG] Thêm vào feed:", addedToFeed)
      
    -- Nếu không có shard nào để feed thì return  
    if next(shardsToFeed) == nil then
        print("[DEBUG] Không có shard nào để feed")
        return 
    end
    
    print("[DEBUG] Danh sách sẽ feed:")
    for abilityId, shards in pairs(shardsToFeed) do
        print("[DEBUG] - Ability ID:", abilityId, "Shards:", shards)
    end
      
    print("[DEBUG] Bắt đầu feed shards...")
    -- Feed các shards của abilities chưa max level  
    local feedSuccess, feedError = pcall(function()  
        ConsumeShardsForXP:InvokeServer(shardsToFeed)  
    end)
    
    if feedSuccess then
        print("[DEBUG] ✅ Feed thành công!")
    else
        print("[DEBUG] ❌ Lỗi khi feed:", feedError)
    end
end

-- Auto run
spawn(function()
    wait(3)
    feedAllShards()

    while true do  
        wait(8)  
        feedAllShards()  
    end
end)

_G.FeedAllShards = feedAllShards