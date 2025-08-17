-- Script lấy vị trí các crates trên map
-- Dựa trên code phân tích từ chest spawning system

local function getCratePositions()
    print("=== GETTING CRATE POSITIONS ===")
    
    local crates = {}
    
    -- Method 1: Tìm crates đã spawn trong workspace
    for _, obj in pairs(workspace:GetChildren()) do
        if obj.Name:find("_Chest") or obj.Name:find("_Crate") then
            table.insert(crates, {
                Name = obj.Name,
                Position = obj:FindFirstChild("HumanoidRootPart") and obj.HumanoidRootPart.Position or obj.PrimaryPart and obj.PrimaryPart.Position or obj:GetPivot().Position,
                Object = obj,
                Rarity = obj:GetAttribute("Rarity"),
                Distance = obj:FindFirstChild("HumanoidRootPart") and (game.Players.LocalPlayer.Character.HumanoidRootPart.Position - obj.HumanoidRootPart.Position).Magnitude or nil
            })
        end
    end
    
    -- Method 2: Tìm trong folder specific (nếu có)
    local possibleFolders = {"Chests", "Crates", "Items", "Spawns", "Map"}
    for _, folderName in pairs(possibleFolders) do
        local folder = workspace:FindFirstChild(folderName)
        if folder then
            for _, obj in pairs(folder:GetChildren()) do
                if obj.Name:find("Chest") or obj.Name:find("Crate") then
                    table.insert(crates, {
                        Name = obj.Name,
                        Position = obj:FindFirstChild("HumanoidRootPart") and obj.HumanoidRootPart.Position or obj.PrimaryPart and obj.PrimaryPart.Position or obj:GetPivot().Position,
                        Object = obj,
                        Rarity = obj:GetAttribute("Rarity"),
                        Folder = folderName,
                        Distance = obj:FindFirstChild("HumanoidRootPart") and (game.Players.LocalPlayer.Character.HumanoidRootPart.Position - obj.HumanoidRootPart.Position).Magnitude or nil
                    })
                end
            end
        end
    end
    
    -- Sắp xếp theo khoảng cách
    table.sort(crates, function(a, b)
        return (a.Distance or math.huge) < (b.Distance or math.huge)
    end)
    
    -- Display results
    print("✅ Found", #crates, "crates/chests")
    for i, crate in ipairs(crates) do
        print(string.format("[%d] %s", i, crate.Name))
        print(string.format("    Position: %.1f, %.1f, %.1f", crate.Position.X, crate.Position.Y, crate.Position.Z))
        if crate.Distance then
            print(string.format("    Distance: %.1f studs", crate.Distance))
        end
        if crate.Rarity then
            print("    Rarity:", crate.Rarity)
        end
        if crate.Folder then
            print("    Folder:", crate.Folder)
        end
        print("    ─────────────────")
    end
    
    return crates
end

-- Quick function to get closest crate
local function getClosestCrate()
    local crates = getCratePositions()
    if #crates > 0 then
        local closest = crates[1]
        print("🎯 CLOSEST CRATE:", closest.Name)
        print("Position:", closest.Position)
        print("Distance:", closest.Distance, "studs")
        return closest
    else
        print("❌ No crates found")
        return nil
    end
end

-- Function to teleport to crate (if you have teleport script)
local function teleportToCrate(index)
    local crates = getCratePositions()
    if crates[index] then
        local crate = crates[index]
        print("📍 Teleporting to:", crate.Name)
        -- Add your teleport code here
        -- game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(crate.Position + Vector3.new(0, 5, 0))
        return crate.Position
    else
        warn("❌ Crate index not found")
        return nil
    end
end

-- Global functions
_G.getCratePositions = getCratePositions
_G.getClosestCrate = getClosestCrate  
_G.teleportToCrate = teleportToCrate

-- Auto execute
print("=== CRATE POSITION GETTER LOADED ===")
print("Use _G.getCratePositions() to get all crates")
print("Use _G.getClosestCrate() to find closest crate")
print("Use _G.teleportToCrate(index) to get position for teleport")

getCratePositions()