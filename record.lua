local rs = game:GetService("ReplicatedStorage")
local p = game:GetService("Players")
local hs = game:GetService("HttpService")
local run = game:GetService("RunService")
local plr = p.LocalPlayer
local ps = plr:WaitForChild("PlayerScripts")

local out = "tdx/macros/recorder_output.json"

if isfile and isfile(out) and delfile then
    local ok, err = pcall(delfile, out)
    if not ok then
        warn("Cannot delete old file: " .. tostring(err))
    end
end

local rec = {}
local h2p = {}
local pq = {}
local to = 2
local lkl = {}
local lut = {}

local function ge()
    if getgenv then return getgenv() end
    if getfenv then return getfenv() end
    return _G
end

local g = ge()

local tc
pcall(function()
    local c = ps:WaitForChild("Client")
    local gc = c:WaitForChild("GameClass")
    local tm = gc:WaitForChild("TowerClass")
    tc = require(tm)
end)

if makefolder then
    pcall(makefolder, "tdx")
    pcall(makefolder, "tdx/macros")
end

local function swf(path, content)
    if writefile then
        local success, err = pcall(writefile, path, content)
        if not success then
            warn("Write error: " .. tostring(err))
        end
    end
end

local function srf(path)
    if isfile and isfile(path) and readfile then
        local success, content = pcall(readfile, path)
        if success then
            return content
        end
    end
    return ""
end

local function gtsp(tower)
    if not tower then return nil end
    local sc = tower.SpawnCFrame
    if sc and typeof(sc) == "CFrame" then
        return sc.Position
    end
    return nil
end

local function gtpc(name)
    local pg = plr:FindFirstChildOfClass("PlayerGui")
    if not pg then return 0 end

    local i = pg:FindFirstChild("Interface")
    if not i then return 0 end
    local bb = i:FindFirstChild("BottomBar")
    if not bb then return 0 end
    local tb = bb:FindFirstChild("TowersBar")
    if not tb then return 0 end

    for _, btn in ipairs(tb:GetChildren()) do
        if btn.Name == name then
            local cf = btn:FindFirstChild("CostFrame")
            if cf then
                local ct = cf:FindFirstChild("CostText")
                if ct and ct:IsA("TextLabel") then
                    local raw = tostring(ct.Text):gsub("%D", "")
                    return tonumber(raw) or 0
                end
            end
        end
    end
    return 0
end

local function gwt()
    local pg = plr:FindFirstChildOfClass("PlayerGui")
    if not pg then return nil, nil end

    local i = pg:FindFirstChild("Interface")
    if not i then return nil, nil end
    local gib = i:FindFirstChild("GameInfoBar")
    if not gib then return nil, nil end

    local w = gib.Wave.WaveText.Text
    local t = gib.TimeLeft.TimeLeftText.Text
    return w, t
end

local function ctn(ts)
    if not ts then return nil end
    local m, s = ts:match("(%d+):(%d+)")
    if m and s then
        return tonumber(m) * 100 + tonumber(s)
    end
    return nil
end

local function gtn(th)
    if not tc or not tc.GetTowers then return nil end
    local towers = tc.GetTowers()
    local tower = towers[th]
    if tower and tower.Type then
        return tower.Type
    end
    return nil
end

local function imst(tn, si)
    if not tn or not si then return false end

    if tn == "Helicopter" and (si == 1 or si == 3) then
        return true
    end

    if tn == "Cryo Helicopter" and (si == 1 or si == 3) then
        return true
    end

    if tn == "Jet Trooper" and si == 1 then
        return true
    end

    return false
end

local function iprs(tn, si)
    if not tn or not si then return false end

    if si == 1 then
        return true
    end

    if si == 3 then
        return false
    end

    return true
end

local function ujf()
    if not hs then return end
    local jl = {}
    for i, e in ipairs(rec) do
        local ok, js = pcall(hs.JSONEncode, hs, e)
        if ok then
            if i < #rec then
                js = js .. ","
            end
            table.insert(jl, js)
        end
    end
    local fj = "[\n" .. table.concat(jl, "\n") .. "\n]"
    swf(out, fj)
end

local function psf()
    local c = srf(out)
    if c == "" then return end

    c = c:gsub("^%[%s*", ""):gsub("%s*%]$", "")
    for l in c:gmatch("[^\r\n]+") do
        l = l:gsub(",$", "")
        if l:match("%S") then
            local ok, dec = pcall(hs.JSONDecode, hs, l)
            if ok and dec and dec.SuperFunction then
                table.insert(rec, dec)
            end
        end
    end
    if #rec > 0 then
        ujf()
    end
end

local function pml(l)
    if l:match('TDX:skipWave%(%)') then
        local cw, ct = gwt()
        return {{
            SkipWave = cw,
            SkipWhen = ctn(ct)
        }}
    end

    local h, si, x, y, z = l:match('TDX:useMovingSkill%(([^,]+),%s*([^,]+),%s*Vector3%.new%(([^,]+),%s*([^,]+),%s*([^%)]+)%)%)')
    if h and si and x and y and z then
        local pos = h2p[tostring(h)]
        if pos then
            local cw, ct = gwt()
            return {{
                towermoving = pos.x,
                skillindex = tonumber(si),
                location = string.format("%s, %s, %s", x, y, z),
                wave = cw,
                time = ctn(ct)
            }}
        end
    end

    local h, si = l:match('TDX:useSkill%(([^,]+),%s*([^%)]+)%)')
    if h and si then
        local pos = h2p[tostring(h)]
        if pos then
            local cw, ct = gwt()
            return {{
                towermoving = pos.x,
                skillindex = tonumber(si),
                location = "no_pos",
                wave = cw,
                time = ctn(ct)
            }}
        end
    end

    local a1, n, x, y, z, r = l:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*Vector3%.new%(([^,]+),%s*([^,]+),%s*([^%)]+)%)%s*,%s*([^%)]+)%)')
    if a1 and n and x and y and z and r then
        n = tostring(n):gsub('^%s*"(.-)"%s*$', '%1')
        return {{
            TowerPlaceCost = gtpc(n),
            TowerPlaced = n,
            TowerVector = string.format("%s, %s, %s", x, y, z),
            Rotation = r,
            TowerA1 = a1
        }}
    end

    local h, p, uc = l:match('TDX:upgradeTower%(([^,]+),%s*([^,]+),%s*([^%)]+)%)')
    if h and p and uc then
        local pos = h2p[tostring(h)]
        local pn, c = tonumber(p), tonumber(uc)
        if pos and pn and c and c > 0 then
            local ent = {}
            for _ = 1, c do
                table.insert(ent, {
                    UpgradeCost = 0,
                    UpgradePath = pn,
                    TowerUpgraded = pos.x
                })
            end
            return ent
        end
    end

    local h, tt = l:match('TDX:changeQueryType%(([^,]+),%s*([^%)]+)%)')
    if h and tt then
        local pos = h2p[tostring(h)]
        if pos then
            local cw, ct = gwt()
            local ent = {
                TowerTargetChange = pos.x,
                TargetWanted = tonumber(tt),
                TargetWave = cw,
                TargetChangedAt = ctn(ct)
            }
            return {ent}
        end
    end

    local h = l:match('TDX:sellTower%(([^%)]+)%)')
    if h then
        local pos = h2p[tostring(h)]
        if pos then
            return {{ SellTower = pos.x }}
        end
    end

    return nil
end

local function pwa(cs)
    if g.TDX_REBUILDING_TOWERS then
        local ax = nil

        local a1, tn, v, r = cs:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*Vector3%.new%(([^,]+),%s*([^,]+),%s*([^%)]+)%)%s*,%s*([^%)]+)%)')
        if v then
            ax = tonumber(v)
        end

        if not ax then
            local h = cs:match('TDX:upgradeTower%(([^,]+),')
            if h then
                local pos = h2p[tostring(h)]
                if pos then
                    ax = pos.x
                end
            end
        end

        if not ax then
            local h = cs:match('TDX:changeQueryType%(([^,]+),')
            if h then
                local pos = h2p[tostring(h)]
                if pos then
                    ax = pos.x
                end
            end
        end

        if not ax then
            local h = cs:match('TDX:useMovingSkill%(([^,]+),')
            if not h then
                h = cs:match('TDX:useSkill%(([^,]+),')
            end
            if h then
                local pos = h2p[tostring(h)]
                if pos then
                    ax = pos.x
                end
            end
        end

        if ax and g.TDX_REBUILDING_TOWERS[ax] then
            return
        end
    end

    local ent = pml(cs)
    if ent then
        for _, e in ipairs(ent) do
            table.insert(rec, e)
        end
        ujf()
    end
end

local function sp(t, c, h)
    table.insert(pq, {
        type = t,
        code = c,
        created = tick(),
        hash = h
    })
end

local function tc(t, sh)
    for i = #pq, 1, -1 do
        local item = pq[i]
        if item.type == t then
            if not sh or string.find(item.code, tostring(sh)) then
                pwa(item.code)
                table.remove(pq, i)
                return
            end
        end
    end
end

rs.Remotes.TowerFactoryQueueUpdated.OnClientEvent:Connect(function(d)
    local dt = d and d[1]
    if not dt then return end
    if dt.Creation then
        tc("Place")
    else
        tc("Sell")
    end
end)

rs.Remotes.TowerUpgradeQueueUpdated.OnClientEvent:Connect(function(d)
    if not d or not d[1] then return end

    local td = d[1]
    local h = td.Hash
    local nl = td.LevelReplicationData
    local ct = tick()

    if lut[h] and (ct - lut[h]) < 0.0001 then
        return
    end
    lut[h] = ct

    local up, uc = nil, 0
    if lkl[h] then
        for pt = 1, 2 do
            local ol = lkl[h][pt] or 0
            local nl = nl[pt] or 0
            if nl > ol then
                up = pt
                uc = nl - ol
                break
            end
        end
    end

    if up and uc > 0 then
        local c = string.format("TDX:upgradeTower(%s, %d, %d)", tostring(h), up, uc)
        pwa(c)

        for i = #pq, 1, -1 do
            if pq[i].type == "Upgrade" and pq[i].hash == h then
                table.remove(pq, i)
            end
        end
    else
        tc("Upgrade", h)
    end

    lkl[h] = nl or {}
end)

rs.Remotes.TowerQueryTypeIndexChanged.OnClientEvent:Connect(function(d)
    if d and d[1] then
        tc("Target")
    end
end)

rs.Remotes.SkipWaveVoteCast.OnClientEvent:Connect(function()
    tc("SkipWave")
end)

pcall(function()
    task.spawn(function()
        while task.wait(0.2) do
            for i = #pq, 1, -1 do
                local item = pq[i]
                if item.type == "MovingSkill" and tick() - item.created > 0.1 then
                    pwa(item.code)
                    table.remove(pq, i)
                end
            end
        end
    end)
end)

local swc = run.Heartbeat:Connect(function()
    for i = #pq, 1, -1 do
        local item = pq[i]
        if item.type == "SkipWave" and tick() - item.created > 0.1 then
            pwa(item.code)
            table.remove(pq, i)
        end
    end
end)

local function hr(n, a)
    if n == "SkipWaveVoteCast" then
        if a and a[1] == true then
            sp("SkipWave", "TDX:skipWave()")
        end
    end

    if n == "TowerUseAbilityRequest" then
        local th, si, tp = unpack(a)
        if typeof(th) == "number" and typeof(si) == "number" then
            local tn = gtn(th)
            if imst(tn, si) then
                local c

                if iprs(tn, si) and typeof(tp) == "Vector3" then
                    c = string.format("TDX:useMovingSkill(%s, %d, Vector3.new(%s, %s, %s))", 
                        tostring(th), 
                        si, 
                        tostring(tp.X), 
                        tostring(tp.Y), 
                        tostring(tp.Z))

                elseif not iprs(tn, si) then
                    c = string.format("TDX:useSkill(%s, %d)", 
                        tostring(th), 
                        si)
                end

                if c then
                    sp("MovingSkill", c, th)
                end
            end
        end
    end

    if n == "TowerUpgradeRequest" then
        local h, p, c = unpack(a)
        if typeof(h) == "number" and typeof(p) == "number" and typeof(c) == "number" and p >= 0 and p <= 2 and c > 0 and c <= 5 then
            sp("Upgrade", string.format("TDX:upgradeTower(%s, %d, %d)", tostring(h), p, c), h)
        end
    elseif n == "PlaceTower" then
        local a1, tn, v, r = unpack(a)
        if typeof(a1) == "number" and typeof(tn) == "string" and typeof(v) == "Vector3" and typeof(r) == "number" then
            local c = string.format('TDX:placeTower(%s, "%s", Vector3.new(%s, %s, %s), %s)', tostring(a1), tn, tostring(v.X), tostring(v.Y), tostring(v.Z), tostring(r))
            sp("Place", c)
        end
    elseif n == "SellTower" then
        sp("Sell", "TDX:sellTower("..tostring(a[1])..")")
    elseif n == "ChangeQueryType" then
        sp("Target", string.format("TDX:changeQueryType(%s, %s)", tostring(a[1]), tostring(a[2])))
    end
end

local function sh()
    if not hookfunction or not hookmetamethod or not checkcaller then
        return
    end

    local ofs = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
        hr(self.Name, {...})
        return ofs(self, ...)
    end)

    local ois = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
        hr(self.Name, {...})
        return ois(self, ...)
    end)

    local onc
    onc = hookmetamethod(game, "__namecall", function(self, ...)
        if checkcaller() then return onc(self, ...) end
        local m = getnamecallmethod()
        if m == "FireServer" or m == "InvokeServer" then
            hr(self.Name, {...})
        end
        return onc(self, ...)
    end)
end

task.spawn(function()
    while task.wait(0.5) do
        local n = tick()
        for i = #pq, 1, -1 do
            if n - pq[i].created > to then
                table.remove(pq, i)
            end
        end
    end
end)

task.spawn(function()
    while task.wait() do
        if tc and tc.GetTowers then
            for h, t in pairs(tc.GetTowers()) do
                local pos = gtsp(t)
                if pos then
                    h2p[tostring(h)] = {x = pos.X, y = pos.Y, z = pos.Z}
                end
            end
        end
    end
end)

local function cswc()
    if swc then
        swc:Disconnect()
        swc = nil
    end
end

ge().TDX_CLEANUP_SKIP_WAVE = cswc

psf()
sh()