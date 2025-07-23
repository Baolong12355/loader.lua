-- Thêm vào phần xử lý TowerUpgradeQueueUpdated
ReplicatedStorage.Remotes.TowerUpgradeQueueUpdated.OnClientEvent:Connect(function(data)
    if not data or not data[1] then return end
    
    local towerData = data[1]
    local hash = towerData.Hash
    local newLevels = towerData.LevelReplicationData
    
    -- Kiểm tra nâng cấp không khớp
    local function logMismatch(expectedPath, actualPath)
        local logEntry = string.format(
            "⚠️ CẢNH BÁO: Yêu cầu path %d nhưng server nâng path %d | Tower %s | Cấp độ: %s\n",
            expectedPath,
            actualPath,
            tostring(hash),
            serialize(newLevels)
        )
        appendfile(fileName, logEntry)
        warn(logEntry)
    end

    if lastLevelData[hash] then
        -- Tìm path nào thực sự được nâng cấp
        local upgradedPaths = {}
        for path = 1, 2 do
            if newLevels[path] > (lastLevelData[hash][path] or 0) then
                table.insert(upgradedPaths, path)
            end
        end

        -- Kiểm tra với yêu cầu đang chờ
        for i, pending in ipairs(pendingUpgrades) do
            if pending.hash == hash then
                if #upgradedPaths == 0 then
                    -- Server không nâng cấp path nào
                    appendfile(fileName, string.format(
                        "❌ Yêu cầu path %d nhưng KHÔNG path nào được nâng | Tower %s\n",
                        pending.path,
                        tostring(hash)
                    ))
                elseif not table.find(upgradedPaths, pending.path) then
                    -- Path nâng không khớp với yêu cầu
                    logMismatch(pending.path, upgradedPaths[1])
                    
                    -- Vẫn ghi lại path thực tế được nâng
                    for _, actualPath in ipairs(upgradedPaths) do
                        appendfile(fileName, string.format(
                            "TDX:upgradeTower(%s, %d, 1) -- Path %d: %d → %d (THỰC TẾ)\n",
                            tostring(hash),
                            actualPath,
                            actualPath,
                            lastLevelData[hash][actualPath] or 0,
                            newLevels[actualPath]
                        ))
                    end
                else
                    -- Trường hợp bình thường
                    appendfile(fileName, string.format(
                        "TDX:upgradeTower(%s, %d, 1) -- Path %d: %d → %d (Chi phí: $%d)\n",
                        tostring(hash),
                        pending.path,
                        pending.path,
                        lastLevelData[hash][pending.path] or 0,
                        newLevels[pending.path],
                        towerData.TotalCost or 0
                    ))
                end
                
                table.remove(pendingUpgrades, i)
                break
            end
        end

        -- Cập nhật dữ liệu level mới nhất
        lastLevelData[hash] = newLevels
    else
        -- Tower mới được phát hiện
        lastLevelData[hash] = newLevels
        appendfile(fileName, string.format(
            "🆕 Tower mới: %s | Cấp độ khởi tạo: Path1=%d, Path2=%d\n",
            tostring(hash),
            newLevels[1] or 0,
            newLevels[2] or 0
        ))
    end
end)