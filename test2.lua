local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local ps = player:WaitForChild("PlayerScripts")
local client = ps:WaitForChild("Client")
local gameClass = client:WaitForChild("GameClass")
local towerModule = gameClass:WaitForChild("TowerClass")

local TowerClass = require(towerModule)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local function testXWMUpgrade()
    local towers = TowerClass.GetTowers()
    
    for hash, tower in pairs(towers) do
        local name = tower.Type or tower.DisplayName or ""
        if string.find(string.upper(name), "XWM") then
            print("=== XWM UPGRADE TEST ===")
            print("Hash:", hash)
            print("Type:", tower.Type)
            print("OverallLevel:", tower.LevelHandler:GetOverallLevel())
            
            -- Test GetLevelUpgradeCost
            for path = 1, 2 do
                print("\n--- Path", path, "---")
                local pathLevel = tower.LevelHandler:GetLevelOnPath(path)
                print("Current Level:", pathLevel)
                
                local success, cost = pcall(function()
                    return tower.LevelHandler:GetLevelUpgradeCost(path, 1)
                end)
                
                if success then
                    print("Next Upgrade Cost:", cost)
                else
                    print("ERROR getting cost:", cost)
                end
                
                -- Check if can upgrade
                local maxLevel = tower.LevelHandler:GetMaxLevel()
                print("Can upgrade?", pathLevel < maxLevel)
            end
            
            -- Test BuffHandler discount
            if tower.BuffHandler then
                local success2, discount = pcall(function()
                    return tower.BuffHandler:GetDiscount()
                end)
                print("\nDiscount:", success2 and discount or "ERROR")
                
                local success3, multipliers = pcall(function()
                    return tower.BuffHandler:GetStatMultipliers()
                end)
                if success3 then
                    print("Stat Multipliers:")
                    for k, v in pairs(multipliers) do
                        print("  ", k, "=", v)
                    end
                end
            end
            
            -- Try to trigger upgrade via remote
            print("\n=== TESTING UPGRADE PATH 1 ===")
            local upgradeRemote = Remotes:FindFirstChild("TowerUpgradeRequest")
            if upgradeRemote then
                print("Found upgrade remote:", upgradeRemote.ClassName)
                
                -- Monitor what happens when we send upgrade request
                local oldFireServer = upgradeRemote.FireServer
                upgradeRemote.FireServer = function(self, ...)
                    local args = {...}
                    print("[INTERCEPTED] Upgrade request sent:")
                    for i, v in ipairs(args) do
                        print("  Arg", i, "=", v, type(v))
                    end
                    return oldFireServer(self, ...)
                end
                
                -- Try upgrade
                print("Attempting to upgrade...")
                upgradeRemote:FireServer(hash, 1, 1) -- hash, path, levels
                
                task.wait(0.5)
                print("Level after attempt:", tower.LevelHandler:GetOverallLevel())
            else
                warn("TowerUpgradeRequest remote not found!")
            end
            
            return tower
        end
    end
    
    warn("No XWM tower found!")
end

testXWMUpgrade()