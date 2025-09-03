local RaycastModule = require(game.ReplicatedStorage.ReplicatedModules.Hitbox.Raycast)
local oldNew = RaycastModule.new

RaycastModule.new = function(HitboxData)
    HitboxData.Offset = 50 -- ép offset raycast

    local hitbox = oldNew(HitboxData)

    -- Hook tiếp BindObject
    local oldBind = hitbox.BindObject
    hitbox.BindObject = function(self, object, attachments)
        -- Duyệt qua tất cả DmgPoint và di chuyển chúng lên trên
        for _, v in ipairs(object:GetDescendants()) do
            if v:IsA("Attachment") and v.Name == "DmgPoint" then
                -- Di chuyển lên trên 25 studs (tuỳ bạn)
                v.Position = v.Position + Vector3.new(0, 25, 0)

                -- Debug: tạo sphere hiển thị
                local sphere = Instance.new("Part")
                sphere.Shape = Enum.PartType.Ball
                sphere.Size = Vector3.new(5, 5, 5)
                sphere.Anchored = true
                sphere.CanCollide = false
                sphere.Transparency = 0.5