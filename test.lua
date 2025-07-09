-- 1) Đợi game load
repeat task.wait() until game:IsLoaded() and game.Players.LocalPlayer

-- 2) Bắt đầu ghi record.txt
local fileName = "record.txt"
if isfile(fileName) then delfile(fileName) end
writefile(fileName, "")

local lastTime = tick()

local function serialize(v)
    if type(v)=="table" then
        local s="{" for k,x in pairs(v) do s=s.."["..serialize(k).."]="..serialize(x).."," end
        return s.."}"
    else return tostring(v) end
end

local function serializeArgs(...)
    local t={} for i,v in ipairs({...}) do t[i]=serialize(v) end
    return table.concat(t,", ")
end

local function logRemote(self,...)
    local now = tick()
    local delta = now - lastTime
    lastTime = now
    local name = tostring(self.Name)
    local prefix = "task.wait("..delta..")\nTDX:"
    local args = serializeArgs(...)
    if name=="PlaceTower" then
        appendfile(fileName,prefix.."placeTower("..args..")\n")
    elseif name=="SellTower" then
        appendfile(fileName,prefix.."sellTower("..args..")\n")
    elseif name=="TowerUpgradeRequest" then
        appendfile(fileName,prefix.."upgradeTower("..args..")\n")
    elseif name=="ChangeQueryType" then
        appendfile(fileName,prefix.."changeQueryType("..args..")\n")
    end
end

-- 3) Hook mọi FireServer/InvokeServer
local oldNamecall
oldNamecall = hookmetamethod(game,"__namecall",function(self,...)
    local method = getnamecallmethod()
    if (method=="FireServer" or method=="InvokeServer") and typeof(self)=="Instance" then
        logRemote(self,...)
    end
    return oldNamecall(self,...)
end)

print("✅ Recording started")

-- 4) Convert record.txt → tdx/macros/x.json
task.spawn(function()
    local txt="record.txt"
    local out="tdx/macros/x.json"
    local HttpService=game:GetService("HttpService")
    local players=game:GetService("Players")
    local pl=players.LocalPlayer
    local ps=pl:WaitForChild("PlayerScripts")

    local function SafeRequire(m) local ok,r=pcall(require,m);return ok and r end
    local gameClass=ps:WaitForChild("Client"):WaitForChild("GameClass")
    local TowerClass=SafeRequire(gameClass:WaitForChild("TowerClass"))

    local function posX(hash)
        local t=TowerClass.GetTowers()[hash]
        if t and t.Character then
            local mdl=t.Character:GetCharacterModel()
            local rp=mdl.PrimaryPart or mdl:FindFirstChild("HumanoidRootPart")
            return rp and rp.Position.X
        end
    end

    if makefolder then pcall(makefolder,"tdx");pcall(makefolder,"tdx/macros") end

    while true do
        if isfile(txt) then
            local lines=readfile(txt)
            local logs={}
            for line in lines:gmatch("[^\r\n]+") do
                local a1,name,x,y,z,rot = line:match('TDX:placeTower%(([^,]+),%s*"([^"]+)",%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)')
                if a1 then
                    table.insert(logs,{
                        TowerPlaceCost=0,
                        TowerPlaced=name,
                        TowerVector=x..", "..y..", "..z,
                        Rotation=rot,
                        TowerA1=a1
                    })
                else
                    local hash,path=line:match('TDX:upgradeTower%(([^,]+),%s*(%d),')
                    if hash then
                        local xval=posX(hash)
                        if xval then
                            table.insert(logs,{
                                UpgradeCost=0,
                                UpgradePath=tonumber(path),
                                TowerUpgraded=xval
                            })
                        end
                    else
                        local xt,tt=line:match('TDX:changeQueryType%(([%d%.]+),%s*(%d)%)')
                        if xt then table.insert(logs,{ChangeTarget=tonumber(xt),TargetType=tonumber(tt)}) end
                        local xs=line:match('TDX:sellTower%(([%d%.]+)%)')
                        if xs then table.insert(logs,{SellTower=tonumber(xs)}) end
                    end
                end
            end
            writefile(out, HttpService:JSONEncode(logs))
        end
        task.wait(0.2)
    end
end)
