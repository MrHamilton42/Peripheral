local _, FW = ...
local L = {}
FW.Layout = L

local function finite(n)
    return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end
L.Finite = finite

-- Blizzard PixelUtil converts physical pixels through a 768-high screen space.
-- GetPhysicalScreenSize's width can remain at the display mode after a native
-- horizontal window resize. Use the live UI root extent with the height-based
-- conversion instead; never substitute exported dimensions for observations.
function L.PixelsPerUnit(scale, physicalHeight)
    if not finite(scale) or scale<=0 or not finite(physicalHeight) or physicalHeight<=0 then return nil end
    return scale*physicalHeight/768
end
function L.Canvas(physicalWidth,physicalHeight,rootWidth,rootHeight,rootScale)
    local pixelsPerUnit=L.PixelsPerUnit(rootScale,physicalHeight)
    if not pixelsPerUnit or not finite(rootWidth) or not finite(rootHeight) or rootWidth<=0 or rootHeight<=0 then
        return nil,"The live UI canvas dimensions are unavailable."
    end
    if math.abs(rootHeight*rootScale-768)>1 then
        return nil,"The UI root does not cover the normalized screen height. Disable other viewport/UI-root modifiers and copy /fws diag."
    end
    return {width=rootWidth*pixelsPerUnit,height=rootHeight*pixelsPerUnit,
        pixelsPerUnit=pixelsPerUnit,physicalWidth=physicalWidth,physicalHeight=physicalHeight}
end

-- Only an explicit user action requests a graphics size change. Keep the
-- original engine size across /reload so recovery remains available afterwards.
local V={}
FW.Video=V
function V.CheckMode()
    if GetCVar then
        local ok,value=pcall(GetCVar,"gxMaximize")
        if ok and (value=="1" or value==1 or value==true) then
            return nil,"Select standard Windowed in WoW Graphics settings and Apply, then use /fws align. Windowed (Fullscreen) is not supported."
        end
    end
    return true
end
function V.Size()
    if not C_VideoOptions or not C_VideoOptions.GetCurrentGameWindowSize then return nil end
    local ok,result=pcall(function()
        local size,second=C_VideoOptions.GetCurrentGameWindowSize()
        local x,y
        if type(size)=='number' then x,y=size,second
        elseif type(size)=='table' or type(size)=='userdata' then
            x,y=size.x,size.y;if size.GetXY then x,y=size:GetXY() end
        end
        if finite(x) and finite(y) and x>0 and y>0 then return {width=x,height=y} end
    end)
    if ok then return result end
end
function V.Sync(g,db)
    if InCombatLockdown and InCombatLockdown() then return nil,"Sync the game size outside combat." end
    if db.video and db.video.restoring then return nil,"Finish restoring the previous size request before requesting another size." end
    local modeOK,modeError=V.CheckMode()
    if not modeOK then return nil,modeError end
    if not C_VideoOptions or not C_VideoOptions.SetGameWindowSize or type(UpdateWindow)~="function" then return nil,"Window sizing is unavailable. Resize manually to the target client area using borders/Graphics settings, then use /fws align. Copy /fws diag if the required size is capped." end
    local valid,err=L.ValidateGeometry(g,g and g.width,g and g.height)
    if not valid then return nil,err end
    local previous=V.Size()
    if not previous then return nil,"The original game-window size is unavailable; no graphics change was requested." end
    if db.video and db.video.requested and (math.abs(previous.width-db.video.requested.width)>2 or math.abs(previous.height-db.video.requested.height)>2) then
        -- A manual size change starts a new request's recovery baseline. Never
        -- shrink back to an older session's size after the user has resized.
        db.video=nil
    end
    db.video=db.video or {original=previous}
    db.video.requested={width=g.width,height=g.height}
    db.video.requestPending=true;db.video.restoring=nil
    local ok,failure=pcall(function() C_VideoOptions.SetGameWindowSize(g.width,g.height);UpdateWindow() end)
    if not ok then return nil,"Game size request was blocked: "..tostring(failure)..". The original size remains saved." end
    local observed=V.Size()
    if observed and math.abs(observed.width-g.width)<=2 and math.abs(observed.height-g.height)<=2 then db.video.requestPending=nil end
    return true,"Requested "..g.width.." x "..g.height.." client area through WoW. Use /fws align to check observed size; a successful request does not prove the engine accepted a spanning size. Move manually, then Apply trial / Keep."
end
function V.Restore(db)
    if not db or not db.video then return true,"No saved game size to restore." end
    if InCombatLockdown and InCombatLockdown() then return nil,"Restore the game size outside combat." end
    local record=db.video
    if not C_VideoOptions or not C_VideoOptions.SetGameWindowSize or type(UpdateWindow)~="function" then return nil,"Restore the window size in Graphics settings." end
    local current=V.Size()
    if not current then return nil,"The current game size is unavailable; recovery settings were retained." end
    local originalMatches=math.abs(current.width-record.original.width)<=2 and math.abs(current.height-record.original.height)<=2
    if record.restoring and originalMatches then db.video=nil;return true,"Original game size restored." end
    if math.abs(current.width-record.requested.width)>2 or math.abs(current.height-record.requested.height)>2 then
        if record.requestPending and originalMatches then
            -- The engine has not applied our request yet. Explicitly cancel it;
            -- merely discarding recovery could let an asynchronous resize land.
            local cancelled,err=pcall(function() C_VideoOptions.SetGameWindowSize(record.original.width,record.original.height);UpdateWindow() end)
            if not cancelled then return nil,"Size cancellation was blocked: "..tostring(err) end
            record.requestPending=nil;record.restoring=true
            return nil,"Original size requested to cancel an unsettled resize; waiting for readback."
        end
        db.video=nil;return true,"Your independently changed game size was left unchanged."
    end
    record.requestPending=nil;record.restoring=true
    local ok,err=pcall(function() C_VideoOptions.SetGameWindowSize(record.original.width,record.original.height);UpdateWindow() end)
    if not ok then return nil,"Game size restore was blocked: "..tostring(err) end
    -- Engine resize can be asynchronous. Retain recovery until readback agrees.
    current=V.Size()
    if not current or math.abs(current.width-record.original.width)>2 or math.abs(current.height-record.original.height)>2 then
        return nil,"Original game size requested; check Graphics settings. Recovery settings were retained."
    end
    db.video=nil;return true,"Original game size restored. Restore any manual desktop move yourself; the optional helper can restore moves it owns."
end

local function rectOK(r, width, height)
    return type(r) == "table" and finite(r.x) and finite(r.y)
        and finite(r.width) and finite(r.height) and r.width > 0 and r.height > 0
        and r.x >= 0 and r.y >= 0 and r.x + r.width <= width + 1
        and r.y + r.height <= height + 1
end

function L.ValidateGeometry(g, width, height)
    if type(g) ~= "table" or g.schema ~= 1 then return nil, "Import monitor JSON in /fws Setup / Import first. Open the bundled Configurator.html in a browser; no helper is required." end
    if not finite(width) or not finite(height) or width <= 0 or height <= 0 then
        return nil, "The current client dimensions are unavailable."
    end
    if not finite(g.width) or not finite(g.height) or math.abs(g.width - width) > 2
        or math.abs(g.height - height) > 2 then
        return nil, string.format("WoW reports %.0f x %.0f; configuration expects %s x %s. Use /fws align to request size or resize the client manually. The optional helper can place the window precisely. If this persists, copy /fws diag.",
            width, height, tostring(g.width), tostring(g.height))
    end
    if not rectOK(g.main, width, height) then return nil, "Invalid Main rectangle." end
    if type(g.regions) ~= "table" or #g.regions < 1 then return nil, "No reference regions were exported." end
    local seen, rectangles = {}, {g.main}
    for _, r in ipairs(g.regions) do
        if not rectOK(r, width, height) or type(r.id) ~= "string" or seen[r.id] then
            return nil, "Invalid or duplicate reference region."
        end
        seen[r.id] = true
        for _, other in ipairs(rectangles) do
            local overlapW = math.min(r.x + r.width, other.x + other.width) - math.max(r.x, other.x)
            local overlapH = math.min(r.y + r.height, other.y + other.height) - math.max(r.y, other.y)
            if overlapW > 1 and overlapH > 1 then return nil, "A reference region overlaps another region or Main." end
        end
        rectangles[#rectangles + 1] = r
    end
    return true
end

-- A vertical prototype rail. Dock direction is supplied independently of order.
-- Return new dimensions without mutating preferences, so a rejected edit is atomic.
function L.Allocate(panels, height, padding, gap)
    padding, gap = padding or 12, gap or 10
    if not finite(height) or not finite(padding) or not finite(gap) or padding < 0 or gap < 0 then
        return nil, "Invalid dock dimensions."
    end
    if #panels == 0 then return {} end
    local budget = height - 2 * padding - (#panels - 1) * gap
    local sizes, floors, sum, minimumSum = {}, {}, 0, 0
    for i, p in ipairs(panels) do
        if not finite(p.min) or not finite(p.preferred) or not finite(p.max)
            or p.min <= 0 or p.min > p.preferred or p.preferred > p.max then
            return nil, "Each panel needs minimum <= preferred <= maximum."
        end
        sizes[i] = p.preferred
        floors[i] = p.fixed and p.preferred or p.min
        sum, minimumSum = sum + sizes[i], minimumSum + floors[i]
    end
    if minimumSum > budget + 0.001 then return nil, "Panel minimum sizes do not fit this dock." end
    if sum > budget then
        local capacity = sum - minimumSum
        local deficit = sum - budget
        for i in ipairs(panels) do sizes[i] = sizes[i] - deficit * (sizes[i] - floors[i]) / capacity end
    elseif sum < budget then
        local remaining = budget - sum
        for _ = 1, #panels do
            local eligible = {}
            for i, p in ipairs(panels) do
                if p.fill and not p.fixed and sizes[i] < p.max - 0.001 then eligible[#eligible + 1] = i end
            end
            if #eligible == 0 or remaining < 0.001 then break end
            local share, used = remaining / #eligible, 0
            for _, i in ipairs(eligible) do
                local growth = math.min(share, panels[i].max - sizes[i])
                sizes[i], used = sizes[i] + growth, used + growth
            end
            remaining = remaining - used
        end
    end
    local result, top = {}, padding
    for i, p in ipairs(panels) do
        result[i] = { id = p.id, y = top, height = sizes[i] }
        top = top + sizes[i] + gap
    end
    return result
end

-- Original Edit Mode adapter. Only public C_EditMode functions write layout state.
local D={anchors={'TOPLEFT','TOP','TOPRIGHT','LEFT','CENTER','RIGHT','BOTTOMLEFT','BOTTOM','BOTTOMRIGHT'}}
FW.Dock=D
local dockFactors={TOPLEFT={0,0},TOP={.5,0},TOPRIGHT={1,0},LEFT={0,.5},CENTER={.5,.5},RIGHT={1,.5},BOTTOMLEFT={0,1},BOTTOM={.5,1},BOTTOMRIGHT={1,1}}
function D.Options(raw)
    raw=type(raw)=='table' and raw or {}
    return {anchor=dockFactors[raw.anchor] and raw.anchor or 'TOP',
        columns=finite(raw.columns) and raw.columns==math.floor(raw.columns) and raw.columns>=1 and raw.columns<=3 and raw.columns or 1,
        width=finite(raw.width) and raw.width>=30 and raw.width<=100 and math.floor(raw.width) or 100}
end
function D.LoadPanels(saved,defaults)
    local result,seen,byID={},{},{}
    for _,p in ipairs(defaults) do byID[p.id]=p end
    local function add(raw)
        if type(raw)~='table' or not byID[raw.id] or seen[raw.id] then return end
        local p={};for k,v in pairs(byID[raw.id]) do p[k]=v end
        if finite(raw.min) and finite(raw.preferred) and finite(raw.max) and raw.min>=80 and raw.max<=1000 and raw.min<=raw.preferred and raw.preferred<=raw.max then
            p.min,p.preferred,p.max=raw.min,raw.preferred,raw.max
            p.fill,p.fit=raw.fill==true,raw.fit==true
            if raw.region=='left' or raw.region=='right' then p.region=raw.region end
            if type(raw.enabled)=='boolean' then p.enabled=raw.enabled end
            p.minimized=raw.minimized==true
            p.interactive=p.id=='party' and raw.interactive==true or false
            if p.id=='party' then p.nativeScale=FW.HUD.PartyScale(raw.nativeScale);p.nativeAlign=FW.HUD.PartyAlign(raw.nativeAlign) end
        end
        result[#result+1]=p;seen[p.id]=true
    end
    if type(saved)=='table' then for _,p in ipairs(saved) do add(p) end end
    for _,p in ipairs(defaults) do add(p) end
    return result
end
-- Columns contain independent ordered stacks. Anchors locate each stack within
-- the usable region; changing width makes horizontal anchoring meaningful.
function D.Layout(region,panels,options,measure)
    if #panels==0 then return {} end
    local o=D.Options(options);local factor=dockFactors[o.anchor]
    local width=(region.width-24)*o.width/100
    local columnWidth=(width-(o.columns-1)*10)/o.columns
    if columnWidth<160 then return nil,'Columns are too narrow. Widen the strip/dock or use fewer columns.' end
    local result={}
    for column=1,o.columns do
        local list,original={},{}
        for index,p in ipairs(panels) do if (index-1)%o.columns+1==column then
            local candidate,err=measure(p,columnWidth)
            if not candidate then return nil,err end
            list[#list+1]=candidate;original[#original+1]=p
        end end
        local allocation,err=L.Allocate(list,region.height-24,0,10)
        if not allocation then return nil,err end
        local used=#allocation>0 and allocation[#allocation].y+allocation[#allocation].height or 0
        local yShift=(region.height-24-used)*factor[2]
        for index,a in ipairs(allocation) do result[#result+1]={panel=original[index],
            x=region.x+12+(region.width-24-width)*factor[1]+(column-1)*(columnWidth+10),
            y=region.y+12+yShift+a.y,width=columnWidth,height=a.height} end
    end
    return result
end

-- Keep this in an already-declared file so an installed prototype can update via /reload.
local H = {}
FW.HUD = H
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k,v in pairs(value) do result[k] = copy(v) end
    return result
end
local function systemKey(system) return tostring(system.system)..":"..tostring(system.systemIndex or 0) end
local anchorFactors = {
    TOPLEFT={0,1}, TOP={0.5,1}, TOPRIGHT={1,1}, LEFT={0,0.5}, CENTER={0.5,0.5},
    RIGHT={1,0.5}, BOTTOMLEFT={0,0}, BOTTOM={0.5,0}, BOTTOMRIGHT={1,0},
}
local function signature(g, scale)
    local m=g.main
    return table.concat({g.width,g.height,m.x,m.y,m.width,m.height,string.format("%.4f",scale)},":")
end

-- Pure transform: edge offsets stay edge offsets; fonts and icon sizes are untouched.
function H.Transform(layout, g, pixelsPerUnit, measurements, registeredNames)
    if not finite(pixelsPerUnit) or pixelsPerUnit <= 0 then return nil,"Invalid HUD coordinate scale." end
    local result=copy(layout)
    if type(result.systems)~="table" then return nil,"Edit Mode layout has no systems." end
    local report={shifted=0,frozen=0,flattened=0,unresolved=0}
    local m=g.main
    local function transformAnchor(a)
        if type(a)~="table" then return false end
        if a.relativeTo~="UIParent" and a.relativeTo~="" and a.relativeTo~=nil then return false end
        local factors=anchorFactors[a.relativePoint]
        if not factors or not finite(a.offsetX) or not finite(a.offsetY) then error("Unsupported Edit Mode root anchor.") end
        local dx=(m.x+(m.width-g.width)*factors[1])/pixelsPerUnit
        local dy=(g.height-m.y-m.height+(m.height-g.height)*factors[2])/pixelsPerUnit
        a.relativeTo="UIParent"; a.offsetX=a.offsetX+dx; a.offsetY=a.offsetY+dy
        return math.abs(dx)>0.001 or math.abs(dy)>0.001,dx,dy
    end
    local ok,err=pcall(function()
        for _,system in ipairs(result.systems) do
            local wasDefault=system.isInDefaultPosition
            local shifted,dx,dy=transformAnchor(system.anchorInfo)
            local second=transformAnchor(system.anchorInfo2)
            if shifted or second then system.isInDefaultPosition=false;report.shifted=report.shifted+1 end
            local measured=(measurements or {})[systemKey(system)]
            if shifted and wasDefault and not system.anchorInfo2 then
                -- Default managers may place multiple bars from identical template
                -- anchors. Preserve their measured spacing before leaving that manager.
                if measured and measured.width<=m.width-8 and measured.height<=m.height-8 then
                    local x=math.max(m.x+4,math.min(measured.x+dx*pixelsPerUnit,m.x+m.width-4-measured.width))
                    local y=math.max(m.y+4,math.min(measured.y-dy*pixelsPerUnit,m.y+m.height-4-measured.height))
                    system.anchorInfo={point="TOPLEFT",relativeTo="UIParent",relativePoint="TOPLEFT",offsetX=x/pixelsPerUnit,offsetY=-y/pixelsPerUnit}
                    report.frozen=report.frozen+1
                else report.unresolved=report.unresolved+1 end
            end
            -- References to other Edit Mode systems follow those systems. External
            -- anchors (for example a legacy raid manager) need an absolute fallback.
            local a=system.anchorInfo
            local external=a and a.relativeTo~="UIParent" and not (registeredNames or {})[a.relativeTo]
            if external and not system.anchorInfo2 then
                if measured and measured.width<=m.width-24 and measured.height<=m.height-24 then
                    local x=math.max(m.x+12,math.min(measured.x,m.x+m.width-12-measured.width))
                    local y=math.max(m.y+12,math.min(measured.y,m.y+m.height-12-measured.height))
                    system.anchorInfo={point="TOPLEFT",relativeTo="UIParent",relativePoint="TOPLEFT",offsetX=x/pixelsPerUnit,offsetY=-y/pixelsPerUnit}
                    system.isInDefaultPosition=false;report.flattened=report.flattened+1
                else report.unresolved=report.unresolved+1 end
            end
        end
    end)
    if not ok then return nil,tostring(err) end
    return result,report
end

local function capabilities()
    return C_EditMode and type(C_EditMode.GetLayouts)=="function" and type(C_EditMode.SaveLayouts)=="function"
        and type(C_EditMode.OnLayoutAdded)=="function" and type(C_EditMode.SetActiveLayout)=="function"
        and Enum and Enum.EditModeLayoutType and Enum.EditModeLayoutType.Character~=nil
end
local function findLayout(data,name,layoutType)
    for index,layout in ipairs(data.layouts or {}) do
        if layout.layoutName==name and (layoutType==nil or layout.layoutType==layoutType) then return index,layout end
    end
end
local function readLayouts()
    local ok,data=pcall(C_EditMode.GetLayouts)
    if not ok or type(data)~="table" or type(data.layouts)~="table" then return nil end
    -- C_EditMode's active index includes presets, but its layouts array does
    -- not. Match Blizzard's manager: prepend copied presets before indexing
    -- or saving, and keep the live manager's table untouched.
    local manager=EditModePresetLayoutManager
    if not manager or not manager.GetCopyOfPresetLayouts then return nil end
    local presetsOK,presets=pcall(manager.GetCopyOfPresetLayouts,manager)
    if not presetsOK or type(presets)~="table" or #presets==0 then return nil end
    local result=copy(data);result.layouts=copy(presets)
    for _,layout in ipairs(data.layouts) do result.layouts[#result.layouts+1]=copy(layout) end
    return result
end
local function measure(g)
    local measurements,names={},{}
    local manager=EditModeManagerFrame
    for _,frame in ipairs(manager and manager.registeredSystemFrames or {}) do
        pcall(function()
            if frame.GetName then local name=frame:GetName();if name then names[name]=true end end
            if frame.GetRect then
                local x,bottom,w,h=frame:GetRect();local scale=L.PixelsPerUnit(frame:GetEffectiveScale(),g.height)
                if finite(x) and finite(bottom) and finite(w) and finite(h) and finite(scale) and w>0 and h>0 then
                    measurements[systemKey(frame)]={x=x*scale,y=g.height-(bottom+h)*scale,width=w*scale,height=h*scale}
                end
            end
        end)
    end
    return measurements,names
end

function H.Center(g,pixelsPerUnit,db)
    if InCombatLockdown and InCombatLockdown() then return nil,"Center the HUD outside combat." end
    if not capabilities() then return nil,"This client does not expose the required Edit Mode APIs." end
    if EditModeManagerFrame and EditModeManagerFrame.IsShown and EditModeManagerFrame:IsShown() then
        return nil,"Close Blizzard Edit Mode before centering the HUD."
    end
    if EditModeManagerFrame and EditModeManagerFrame.HasActiveChanges and EditModeManagerFrame:HasActiveChanges() then
        return nil,"Save or discard pending Blizzard Edit Mode changes first."
    end
    local data=readLayouts()
    if not data then return nil,"Edit Mode layouts or presets are not available yet. Open and close Blizzard Edit Mode, then retry." end
    local current=data.layouts[data.activeLayout]
    if not current then return nil,"No active Edit Mode layout was returned." end
    local record=db.hud
    if record and record.signature==signature(g,pixelsPerUnit)
        and (current.layoutName==record.generatedName or (current.layoutName==record.originalName and current.layoutType==record.originalType)) then
        local index=findLayout(data,record.generatedName,Enum.EditModeLayoutType.Character)
        if index then
            local switched,switchError=pcall(C_EditMode.SetActiveLayout,index)
            if not switched then return nil,"HUD layout selection was blocked: "..tostring(switchError) end
            local confirmed=C_EditMode.GetLayouts()
            if confirmed.activeLayout~=index then return nil,"Select "..record.generatedName.." in Blizzard Edit Mode." end
            return true,"Center HUD layout selected: "..record.generatedName
        end
    end
    if record and current.layoutName==record.generatedName then
        local _,source=findLayout(data,record.originalName,record.originalType)
        if not source then return nil,"Restore or select your original HUD layout before rebuilding." end
        current=source
    end
    local layoutType=Enum.EditModeLayoutType.Character
    local count=0
    for _,layout in ipairs(data.layouts) do if layout.layoutType==layoutType then count=count+1 end end
    local limit=Constants and Constants.EditModeConsts and Constants.EditModeConsts.EditModeMaxLayoutsPerType
    if limit and count>=limit then return nil,"Blizzard's character-layout limit is reached. Free a layout slot first." end
    local measurements,names=measure(g)
    local centered,report=H.Transform(current,g,pixelsPerUnit,measurements,names)
    if not centered then return nil,report end
    local name="FWS Center"
    local suffix=1
    while findLayout(data,name) do suffix=suffix+1;name="FWS Center "..suffix end
    centered.layoutName,centered.layoutType=name,layoutType
    if C_EditMode.IsValidLayoutName and not C_EditMode.IsValidLayoutName(name) then return nil,"Blizzard rejected the generated HUD layout name." end
    local originalIndex=findLayout(data,current.layoutName,current.layoutType)
    local newIndex=#data.layouts+1
    local candidate=copy(data);candidate.layouts[newIndex]=centered
    db.hud={originalName=current.layoutName,originalType=current.layoutType,originalIndex=originalIndex,
        generatedName=name,signature=signature(g,pixelsPerUnit),sourceBackup=copy(current),report=report}
    local saved,saveError=pcall(function()
        C_EditMode.SaveLayouts(candidate)
        C_EditMode.OnLayoutAdded(newIndex,true,false)
        local updated=readLayouts()
        if not updated then error("Edit Mode layout readback is unavailable.") end
        local index=findLayout(updated,name,layoutType)
        if not index then error("Generated layout was not accepted by the client.") end
        if updated.activeLayout~=index then C_EditMode.SetActiveLayout(index) end
        if C_EditMode.GetLayouts().activeLayout~=index then error("Generated layout could not be activated.") end
    end)
    if not saved then
        local _,restoreMessage=H.Restore(db)
        return nil,"HUD creation did not complete. "..tostring(restoreMessage).." Details: "..tostring(saveError)
    end
    return true,string.format("Created %s: %d shifted, %d managed positions preserved, %d external anchors centered, %d unresolved. Fine-tune in Edit Mode.",name,report.shifted,report.frozen,report.flattened,report.unresolved)
end

function H.Restore(db)
    if H.RestoreVisibility then local ok,message=H.RestoreVisibility();if not ok then return nil,message end end
    local record=db and db.hud
    if not record then return true,"No generated HUD layout to restore." end
    if InCombatLockdown and InCombatLockdown() then return nil,"HUD restoration pending until combat ends." end
    if not capabilities() then return nil,"Restore your original layout in Blizzard Edit Mode." end
    local data=readLayouts()
    if not data then return nil,"Edit Mode layouts or presets are not available yet." end
    local current=data.layouts and data.layouts[data.activeLayout]
    if not current or current.layoutName~=record.generatedName then return true,"Your selected HUD layout was left unchanged." end
    if EditModeManagerFrame and EditModeManagerFrame.HasActiveChanges and EditModeManagerFrame:HasActiveChanges() then
        return nil,"Save or discard pending Blizzard Edit Mode changes before restoring the HUD."
    end
    if record.partyDock then
        local restored,message=H.UndockParty(db)
        if not restored then return nil,message end
    end
    if record.minimapDock then
        local restored,message=H.UndockMinimap(db)
        if not restored then return nil,message end
    end
    local original=findLayout(data,record.originalName,record.originalType)
    if not original then return nil,"Original HUD layout not found; select a layout in Blizzard Edit Mode." end
    local restored,err=pcall(C_EditMode.SetActiveLayout,original)
    if not restored then return nil,"Click Restore Blizzard HUD outside combat: "..tostring(err) end
    if C_EditMode.GetLayouts().activeLayout~=original then return nil,"HUD restoration was not accepted; choose your original layout in Edit Mode." end
    return true,"Original Blizzard HUD layout restored."
end

-- Ordinary UI panels use a separate native layout manager, not Edit Mode.
-- Adjust its supported offsets once; let it retain opening, pushing and closing.
local W={enabled=false,lastStatus="not centered"}
FW.NativeWindows=W
local windowKeys={"LEFT_OFFSET","TOP_OFFSET","RIGHT_OFFSET_BUFFER"}
local function windowCombat() return InCombatLockdown and InCombatLockdown() end
local function windowCaps()
    return type(GetUIPanelLayoutAttribute)=="function" and type(SetUIPanelLayoutAttribute)=="function"
        and type(UpdateUIPanelPositions)=="function"
end
local function windowPoints(frame)
    local points={}
    for i=1,frame:GetNumPoints() do points[i]={frame:GetPoint(i)} end
    return points
end
local function sameWindowPoints(frame,points)
    if frame:GetNumPoints()~=#points then return false end
    for i,point in ipairs(points) do
        local current={frame:GetPoint(i)}
        for j=1,5 do if current[j]~=point[j] then return false end end
    end
    return true
end
local function restoreWindowPoints(saved)
    if not saved or not sameWindowPoints(saved.frame,saved.written) then return end
    saved.frame:ClearAllPoints()
    for _,point in ipairs(saved.original) do saved.frame:SetPoint(point[1],point[2],point[3],point[4],point[5]) end
end

-- Keep these native windows on Main even on clients without HUD centering.
local skillWindowNames={
    "SpellBookFrame","PlayerSpellsFrame","PlayerTalentFrame","CharacterFrame",
    "ProfessionsBookFrame","ProfessionsFrame","TradeSkillFrame","CraftFrame","ClassTrainerFrame",
    "CollectionsJournal",
}
local skillWindowHooks={}
local function clampSkillWindow(frame,g)
    if not frame:IsShown() or (frame.IsForbidden and frame:IsForbidden()) then return end
    local scale=L.PixelsPerUnit(frame:GetEffectiveScale(),g.height)
    local left,bottom,width,height=frame:GetRect()
    if not scale or not left or width<=0 or height<=0 then return end
    local main=g.main
    local saved=W.skillWindows[frame]
    if width*scale>main.width or height*scale>main.height then
        restoreWindowPoints(saved)
        W.skillWindows[frame]=nil
        return
    end
    local x,y=left*scale,g.height-(bottom+height)*scale
    local dx=math.max(main.x,math.min(x,main.x+main.width-width*scale))-x
    local dy=math.max(main.y,math.min(y,main.y+main.height-height*scale))-y
    if math.abs(dx)<1 and math.abs(dy)<1 then return end
    local before=windowPoints(frame)
    if #before==0 then return end
    if not saved or not sameWindowPoints(frame,saved.written) then saved={frame=frame,original=before} end
    local ok,message=pcall(function()
        frame:ClearAllPoints()
        for _,point in ipairs(before) do
            frame:SetPoint(point[1],point[2],point[3],(point[4] or 0)+dx/scale,(point[5] or 0)-dy/scale)
        end
    end)
    saved.written=windowPoints(frame)
    W.skillWindows[frame]=saved
    if not ok then
        restoreWindowPoints(saved)
        W.skillWindows[frame]=nil
        error(message)
    end
end
local function refreshSkillWindows()
    local g=W.skillGeometry
    if not g then return end
    if windowCombat() then W.skillPending=true;return end
    W.skillPending=nil
    for _,name in ipairs(skillWindowNames) do
        local frame=_G[name]
        if frame and frame.GetRect and not (frame.IsForbidden and frame:IsForbidden()) then
            if not skillWindowHooks[frame] and frame.HookScript then
                skillWindowHooks[frame]=true
                pcall(frame.HookScript,frame,"OnShow",function()
                    if W.skillGeometry and C_Timer and C_Timer.After then C_Timer.After(0,refreshSkillWindows)
                    else refreshSkillWindows() end
                end)
            end
            local ok,message=pcall(clampSkillWindow,frame,g)
            if not ok then W.lastStatus="Could not place "..name.." on Main: "..tostring(message) end
        end
    end
end
function W.RouteSkillWindows(g)
    W.skillGeometry=g
    W.skillWindows=W.skillWindows or {}
    if not W.skillHooks and type(hooksecurefunc)=="function" then
        for _,name in ipairs({"ShowUIPanel","UpdateUIPanelPositions"}) do
            if type(_G[name])=="function" then hooksecurefunc(name,refreshSkillWindows) end
        end
        W.skillHooks=true
    end
    refreshSkillWindows()
end

function W.PlaceGuide(geometry)
    local frame=EncounterJournal
    local saved=W.guide
    local g=geometry or (saved and saved.geometry)
    if not g or not frame or not frame:IsShown() or windowCombat() then return end
    if (frame.IsForbidden and frame:IsForbidden()) or (frame.IsProtected and frame:IsProtected()) then return end
    local scale=L.PixelsPerUnit(frame:GetEffectiveScale(),g.height)
    if not scale or frame:GetWidth()*scale>g.main.width or frame:GetHeight()*scale>g.main.height then return end
    if not saved or saved.frame~=frame or not sameWindowPoints(frame,saved.written) then
        saved={frame=frame,original=windowPoints(frame)}
    end
    frame:ClearAllPoints()
    frame:SetPoint('CENTER',UIParent,'TOPLEFT',(g.main.x+g.main.width/2)/scale,-(g.main.y+g.main.height/2)/scale)
    saved.written=windowPoints(frame);saved.geometry=g;W.guide=saved
    if not W.guideHook and type(hooksecurefunc)=='function' and type(UpdateUIPanelPositions)=='function' then
        hooksecurefunc('UpdateUIPanelPositions',function() if W.guide then pcall(W.PlaceGuide) end end)
        W.guideHook=true
    end
    return true
end
function W.AlignMap(frame)
    if not W.enabled or W.busy or windowCombat() or frame~=WorldMapFrame then return end
    if not frame.IsMaximized or not frame:IsMaximized() or not frame:IsShown() then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    if frame.IsProtected and frame:IsProtected() then return end
    local g=W.geometry
    local scale=L.PixelsPerUnit(frame:GetEffectiveScale(),g.height)
    if not scale then return end
    if frame:GetWidth()*scale>g.main.width or frame:GetHeight()*scale>g.main.height then
        W.lastStatus="Standard windows use Main. Minimize Map & Quest Log to fit this viewport."
        return
    end
    local previous=W.map
    if not previous or not sameWindowPoints(frame,previous.written) then
        previous={frame=frame,original=windowPoints(frame)}
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOP",UIParent,"TOP",(g.main.x+g.main.width/2-g.width/2)/scale,-g.main.y/scale)
    previous.written=windowPoints(frame);W.map=previous
end
local function centerWindowAttributes()
    local record=W.record
    if type(SetUIPanelAttribute)~="function" then return end
    local delta=W.geometry.main.x+W.geometry.main.width/2-W.geometry.width/2
    for name,attributes in pairs(UIPanelWindows or {}) do
        local frame=_G[name]
        if frame and frame.GetAttribute and not (frame.IsForbidden and frame:IsForbidden())
            and not (frame.IsProtected and frame:IsProtected()) then
            local defined=frame:GetAttribute("UIPanelLayout-defined")
            local area=defined and frame:GetAttribute("UIPanelLayout-area") or attributes.area
            local skip=defined and frame:GetAttribute("UIPanelLayout-centerFrameSkipAnchoring") or attributes.centerFrameSkipAnchoring
            if (area=="center" or area=="centerOrLeft") and not skip then
                local saved=record.centers[frame]
                local current=defined and frame:GetAttribute("UIPanelLayout-centerXOffset") or attributes.centerXOffset
                if not saved then saved={original=current};record.centers[frame]=saved
                elseif current~=saved.written then saved=nil end -- another owner changed it
                local scale=L.PixelsPerUnit(frame:GetEffectiveScale(),W.geometry.height)
                if saved and scale then
                    saved.written=(saved.original or 0)+delta/scale
                    SetUIPanelAttribute(frame,"centerXOffset",saved.written)
                end
            end
        end
    end
end
function W.Refresh()
    refreshSkillWindows()
    if not W.enabled then return end
    if windowCombat() then W.pending=true;return end
    W.pending=nil
    local ok,err=pcall(function()
        centerWindowAttributes()
        W.busy=true;UpdateUIPanelPositions();W.busy=nil
        if WorldMapFrame then W.AlignMap(WorldMapFrame) end
    end)
    W.busy=nil
    if not ok then W.lastStatus="Native window placement was blocked: "..tostring(err) end
    return ok
end
function W.Center(g,pixelsPerUnit)
    if windowCombat() then return nil,"Center native windows outside combat." end
    if not windowCaps() then return nil,"Native window layout APIs are unavailable on this client." end
    if not g or not g.main or not finite(pixelsPerUnit) or pixelsPerUnit<=0 then return nil,"Invalid native window geometry." end
    local record=W.record or {original={},written={},centers={}}
    for _,key in ipairs(windowKeys) do
        local current=GetUIPanelLayoutAttribute(key)
        if not finite(current) then return nil,"Native window layout offsets are unavailable." end
        if record.original[key]==nil then record.original[key]=current
        elseif current~=record.written[key] then return nil,"Another UI owner changed native window offsets. Restore before retrying." end
    end
    W.record,W.geometry=record,copy(g)
    record.written.LEFT_OFFSET=record.original.LEFT_OFFSET+g.main.x/pixelsPerUnit
    record.written.TOP_OFFSET=record.original.TOP_OFFSET-g.main.y/pixelsPerUnit
    record.written.RIGHT_OFFSET_BUFFER=record.original.RIGHT_OFFSET_BUFFER+(g.width-g.main.x-g.main.width)/pixelsPerUnit
    local ok,err=pcall(function()
        for _,key in ipairs(windowKeys) do SetUIPanelLayoutAttribute(key,record.written[key]) end
    end)
    if not ok then W.Restore();return nil,"Native window layout was blocked: "..tostring(err) end
    W.enabled=true;W.lastStatus="Standard Blizzard windows use Main; custom addon windows need their own adapters."
    if not W.mapHook and type(hooksecurefunc)=="function" and type(MaximizeUIPanel)=="function" then
        hooksecurefunc("MaximizeUIPanel",function(frame) W.AlignMap(frame) end);W.mapHook=true
    end
    if not W.Refresh() then local message=W.lastStatus;W.Restore();return nil,message end
    return true,W.lastStatus
end
function W.Restore()
    W.enabled=false;W.pending=nil
    W.skillGeometry=nil;W.skillPending=nil
    local record=W.record
    if not record and not W.guide and not next(W.skillWindows or {}) then return true,"No native window offsets to restore." end
    if windowCombat() then return nil,"Native window restoration pending until combat ends." end
    if record and not windowCaps() then return nil,"Native window layout APIs are unavailable for restoration." end
    local ok,err=pcall(function()
        restoreWindowPoints(W.guide);W.guide=nil
        for frame,saved in pairs(W.skillWindows or {}) do
            restoreWindowPoints(saved)
            W.skillWindows[frame]=nil
        end
        if not record then return end
        for _,key in ipairs(windowKeys) do
            if record.written[key]~=nil and GetUIPanelLayoutAttribute(key)==record.written[key] then
                SetUIPanelLayoutAttribute(key,record.original[key])
            end
        end
        for frame,saved in pairs(record.centers) do
            if frame:GetAttribute("UIPanelLayout-centerXOffset")==saved.written then
                SetUIPanelAttribute(frame,"centerXOffset",saved.original)
            end
        end
        UpdateUIPanelPositions()
        restoreWindowPoints(W.map)
    end)
    if not ok then W.lastStatus="Native window restoration was blocked: "..tostring(err);return nil,W.lastStatus end
    W.record,W.map=nil,nil;W.lastStatus="Original native window offsets restored."
    return true,W.lastStatus
end

-- Inventory has its own anchor pass. Route known native bag frames in physical
-- pixels, without reparenting them or changing item buttons or native scale.
local B={enabled=false,records={},lastStatus="not centered"}
FW.Bags=B
function B.Options(saved)
    saved=type(saved)=="table" and saved or {}
    local destination=saved.destination
    if destination~="main" and destination~="left" and destination~="right" and destination~="native" then destination="main" end
    return {destination=destination,above=saved.above~=false}
end
function B.Target(g,destination)
    if destination=="main" then return g.main end
    for _,region in ipairs(g.regions or {}) do if region.id==destination then return region end end
end
function B.Pack(items,rect,bottom)
    local right=rect.x+rect.width-12
    local top=rect.y+12
    local floor=rect.y+rect.height-(bottom or 12)
    local columnRight,columnLeft,nextBottom=right,right,floor
    local result={}
    for index,item in ipairs(items) do
        if not finite(item.width) or not finite(item.height) or item.width<=0 or item.height<=0 then return nil,"Native bag dimensions are unavailable." end
        if item.height>floor-top then return nil,"Bags are too tall for this destination. Choose Main or enlarge the usable region." end
        if index>1 and (nextBottom-item.height<top or items[index-1].combined) then
            columnRight=columnLeft-11;nextBottom=floor
        end
        local x,y=columnRight-item.width,nextBottom-item.height
        if x<rect.x+12 then return nil,"Bags are too wide for this destination. Choose Main or widen the monitor strip." end
        result[index]={x=x,y=y};columnLeft=math.min(columnLeft,x);nextBottom=y-8
    end
    return result
end
local function nativeBagsShown()
    local frames,seen={},{}
    local function add(frame)
        if not frame or seen[frame] or not frame:IsShown() or (frame.IsForbidden and frame:IsForbidden()) then return end
        local name=frame:GetName()
        if name=="ContainerFrameCombinedBags" or (type(name)=="string" and name:match("^ContainerFrame%d+$")) then
            seen[frame]=true;frames[#frames+1]=frame
        end
    end
    if ContainerFrameSettingsManager and ContainerFrameSettingsManager.GetBagsShown then
        for _,frame in ipairs(ContainerFrameSettingsManager:GetBagsShown()) do add(frame) end
    end
    if #frames==0 then
        add(ContainerFrameCombinedBags)
        for index=1,(NUM_CONTAINER_FRAMES or 13) do add(_G["ContainerFrame"..index]) end
    end
    return frames
end
local function restoreBagLayers()
    for frame,record in pairs(B.records) do
        if record.writtenStrata then
            if frame:GetFrameStrata()==record.writtenStrata then frame:SetFrameStrata(record.strata) end
            record.writtenStrata=nil
        end
    end
end
local function foregroundBag(frame)
    local record=B.records[frame] or {}
    B.records[frame]=record
    local current=frame:GetFrameStrata()
    if not record.writtenStrata or current~=record.writtenStrata then record.strata=current end
    frame:SetFrameStrata("DIALOG")
    if frame:GetFrameStrata()~="DIALOG" then error("Native bag foreground layer was not accepted.") end
    record.writtenStrata="DIALOG"
end
local function layerBags(frames)
    if B.options.above then
        -- Individual bags share a native top-level container; keep that owner in
        -- the same layer as its bags without reparenting or altering item buttons.
        for _,frame in ipairs(frames) do
            if ContainerFrameContainer and frame.GetParent and frame:GetParent()==ContainerFrameContainer then
                foregroundBag(ContainerFrameContainer)
                break
            end
        end
        for _,frame in ipairs(frames) do foregroundBag(frame) end
    else restoreBagLayers() end
    local details={}
    for _,frame in ipairs(frames) do
        details[#details+1]=frame:GetName().."="..frame:GetFrameStrata().."/"..frame:GetFrameLevel()
    end
    if ContainerFrameContainer then details[#details+1]="owner="..ContainerFrameContainer:GetFrameStrata() end
    B.lastLayerStatus=(B.options.above and "foreground requested: " or "native requested: ")..(#details>0 and table.concat(details,", ") or "no visible bags")
end
function B.Refresh()
    if not B.enabled then return end
    if windowCombat() then B.pending=true;return end
    B.pending=nil
    B.placementFailed=nil
    local placed=true
    local ok,err=pcall(function()
        local rect=B.Target(B.geometry,B.options.destination)
        if not rect then placed=false;B.lastStatus="The selected bag destination is not in the current export.";return end
        local frames=nativeBagsShown()
        -- Foreground is independent of packing. In particular, opening another
        -- bag can overflow a strip that fitted when the route was first saved.
        layerBags(frames)
        local items={}
        for index,frame in ipairs(frames) do
            local scale=L.PixelsPerUnit(frame:GetEffectiveScale(),B.geometry.height)
            if not scale then error("Native bag scale is unavailable.") end
            items[index]={width=frame:GetWidth()*scale,height=frame:GetHeight()*scale,scale=scale,
                combined=frame.IsCombinedBagContainer and frame:IsCombinedBagContainer() or false}
        end
        local positions,failure=B.Pack(items,rect,B.options.destination=="main" and 85 or 12)
        if not positions then placed=false;B.placementFailed=true;B.lastStatus=failure;return end
        for index,frame in ipairs(frames) do
            local record=B.records[frame]
            if not record then record={};B.records[frame]=record end
            if not record.written or not sameWindowPoints(frame,record.written) then record.original=windowPoints(frame) end
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT",UIParent,"TOPLEFT",positions[index].x/items[index].scale,-positions[index].y/items[index].scale)
            record.written=windowPoints(frame)
        end
        B.lastStatus="Bags: "..B.options.destination.." / "..#frames.." visible / "..(B.options.above and "above side panels" or "native layer")
    end)
    if not ok then B.lastStatus="Native bag placement was blocked: "..tostring(err) end
    return ok and placed
end
function B.Center(g,options)
    if windowCombat() then return nil,"Center bags outside combat." end
    options=B.Options(options or B.options)
    if options.destination=="native" then B.options=options;return B.Restore() end
    if type(hooksecurefunc)~="function" or type(UpdateContainerFrameAnchors)~="function" then
        return nil,"Native bag anchor API is unavailable on this client."
    end
    if not B.Target(g,options.destination) then return nil,"The selected monitor strip is not in the current export." end
    local oldGeometry,oldOptions,oldEnabled=B.geometry,B.options,B.enabled
    B.geometry=copy(g);B.options=options;B.enabled=true
    if not B.hooked then
        hooksecurefunc("UpdateContainerFrameAnchors",function() B.Refresh() end);B.hooked=true
    end
    local ok,err=pcall(UpdateContainerFrameAnchors)
    local placed=ok and B.Refresh()
    if not placed then
        local failure=ok and B.lastStatus or ("Native bag layout refresh was blocked: "..tostring(err))
        local previous=oldEnabled and oldGeometry and oldOptions and B.Target(oldGeometry,oldOptions.destination)
        local target=B.Target(g,options.destination)
        if ok and B.placementFailed and previous and options.destination==oldOptions.destination
            and options.above~=oldOptions.above and g.width==oldGeometry.width and g.height==oldGeometry.height
            and previous.x==target.x and previous.y==target.y and previous.width==target.width and previous.height==target.height then
            B.lastStatus="Bag layer saved. "..failure
            return true,B.lastStatus
        end
        B.geometry,B.options,B.enabled=oldGeometry,oldOptions,oldEnabled
        if oldEnabled then B.Refresh() else B.Restore() end
        B.lastStatus=failure;return nil,failure
    end
    return true,B.lastStatus
end
function B.Restore()
    B.enabled=false;B.pending=nil
    if next(B.records)==nil then B.lastStatus="Blizzard bag placement (routing disabled).";return true,B.lastStatus end
    if windowCombat() then return nil,"Bag restoration pending until combat ends." end
    local ok,err=pcall(function()
        for frame,record in pairs(B.records) do
            if record.written and sameWindowPoints(frame,record.written) then
                frame:ClearAllPoints()
                for _,point in ipairs(record.original) do frame:SetPoint(point[1],point[2],point[3],point[4],point[5]) end
            end
        end
        restoreBagLayers()
    end)
    if not ok then return nil,"Bag restoration was blocked: "..tostring(err) end
    B.records={};B.lastStatus="Original bag anchors restored.";B.lastLayerStatus="Owned foreground changes restored (routing disabled)."
    return true,B.lastStatus
end

-- First interactive mode routes standard Blizzard party frames by editing only
-- their anchor in our generated layout. No unit buttons or health logic are replaced.
function H.PartyScale(value)
    if not finite(value) then return nil end
    return math.max(100,math.min(200,math.floor(value/5+0.5)*5))
end
function H.PartyAlign(value)
    return (value=="center" or value=="right") and value or "left"
end
function H.CurrentPartyScale()
    return PartyFrame and PartyFrame.GetScale and H.PartyScale(PartyFrame:GetScale()*100) or 100
end
function H.PartyMetrics(g,pixelsPerUnit,options)
    local frame=PartyFrame
    if not frame or not frame.system or not frame.GetEffectiveScale then return nil,"Native PartyFrame is unavailable." end
    local manager=EditModeManagerFrame
    if not manager or type(manager.UseRaidStylePartyFrames)~="function" then return nil,"Party frame style cannot be validated on this client." end
    if manager:UseRaidStylePartyFrames() then return nil,"This first trial needs standard party frames. Turn off raid-style party frames in Edit Mode first." end
    local registered=false
    for _,entry in ipairs(manager.registeredSystemFrames or {}) do if entry==frame then registered=true end end
    if not registered then return nil,"The native party frame is not registered with Edit Mode." end
    local scale=L.PixelsPerUnit(frame:GetEffectiveScale(),g.height)
    if not scale or not finite(pixelsPerUnit) or pixelsPerUnit<=0 then return nil,"Party frame scale is unavailable." end
    options=options or {}
    local requested=H.PartyScale(options.nativeScale)
    local scaleSetting=Enum and Enum.EditModeUnitFrameSetting and Enum.EditModeUnitFrameSetting.FrameSize
    if requested then
        if C_GameRules and C_GameRules.IsGameRuleActive and Enum and Enum.GameRule and Enum.GameRule.ForcedPartyFrameScale
            and C_GameRules.IsGameRuleActive(Enum.GameRule.ForcedPartyFrameScale) then return nil,"This client forces the native party frame scale." end
        if not scaleSetting or (frame.HasSetting and not frame:HasSetting(scaleSetting)) then return nil,"Native party scaling is unavailable on this client." end
        local current=frame:GetScale()
        if not finite(current) or current<=0 then return nil,"Native party scale is unavailable." end
        scale=scale*(requested/100)/current
    end
    local width,height=0,0
    for index=1,4 do
        local member=frame["MemberFrame"..index]
        if not member then return nil,"Native party member frames are not initialized. Join a party, then retry." end
        local w,h=member:GetWidth(),member:GetHeight()
        if not finite(w) or not finite(h) or w<=0 or h<=0 then return nil,"Native party frame dimensions are unavailable." end
        local pet=member.PetFrame
        local petHeight=pet and pet:GetHeight() or 0
        if not finite(petHeight) or petHeight<0 then return nil,"Native party pet dimensions are unavailable." end
        width=math.max(width,w);height=height+h+petHeight
    end
    -- Reserve four members, pet space, native spacing, and aura/edge padding.
    width=math.max(width,frame:GetWidth())+64
    height=math.max(height+3*26+24,frame:GetHeight()+24)
    return {width=width*scale,height=height*scale,slotHeight=math.ceil((height*scale/pixelsPerUnit+166)/10)*10,
        system=frame.system,systemIndex=frame.systemIndex or 0,nativeScale=requested,scaleSetting=scaleSetting}
end
local function partyAnchorMatches(a,b)
    return a and b and a.point==b.point and a.relativeTo==b.relativeTo and a.relativePoint==b.relativePoint
        and finite(a.offsetX) and finite(a.offsetY) and finite(b.offsetX) and finite(b.offsetY)
        and math.abs(a.offsetX-b.offsetX)<0.05 and math.abs(a.offsetY-b.offsetY)<0.05
end
function H.DockParty(g,pixelsPerUnit,rect,db,options)
    if windowCombat() then return nil,"Apply interactive Party mode outside combat." end
    local metrics,err=H.PartyMetrics(g,pixelsPerUnit,options)
    if not metrics then return nil,err end
    if EditModeManagerFrame:IsShown() or EditModeManagerFrame:HasActiveChanges() then return nil,"Close Edit Mode and save or discard its edits first." end
    if metrics.width>rect.width-24*pixelsPerUnit or metrics.height>rect.height-166*pixelsPerUnit then
        return nil,"Native party frames do not fit the reserved slot. Adjust their size in Edit Mode or widen the strip."
    end
    local record=db.hud
    local data=readLayouts()
    local layout=data and data.layouts[data.activeLayout]
    if not record or not layout or layout.layoutName~=record.generatedName then return nil,"Center Blizzard HUD before docking interactive party frames." end
    local candidate=copy(data)
    local target
    for _,system in ipairs(candidate.layouts[data.activeLayout].systems) do
        if system.system==metrics.system and (system.systemIndex or 0)==metrics.systemIndex then target=system;break end
    end
    if not target then return nil,"The party frame system is absent from this layout." end
    for _,system in ipairs(candidate.layouts[data.activeLayout].systems) do
        if system~=target then
            for _,anchor in ipairs({system.anchorInfo or {},system.anchorInfo2 or {}}) do
                if anchor.relativeTo=="PartyFrame" or anchor.relativeTo=="CompactPartyFrame" then
                    return nil,"Another HUD element is snapped to PartyFrame. Unsnap it in Edit Mode before this trial."
                end
            end
        end
    end
    local source=record.partyDock and record.partyDock.source or copy(target)
    local align=H.PartyAlign(options and options.nativeAlign)
    local extra=rect.width-24*pixelsPerUnit-metrics.width
    local shift=align=="right" and extra or (align=="center" and extra/2 or 0)
    local anchor={point="TOPLEFT",relativeTo="UIParent",relativePoint="TOPLEFT",
        offsetX=(rect.x+12*pixelsPerUnit+shift)/pixelsPerUnit,offsetY=-(rect.y+96*pixelsPerUnit)/pixelsPerUnit}
    target.anchorInfo=anchor;target.anchorInfo2=nil;target.isInDefaultPosition=false
    if metrics.nativeScale then
        target.settings=target.settings or {}
        local setting
        for _,entry in ipairs(target.settings) do if entry.setting==metrics.scaleSetting then setting=entry;break end end
        if not setting then setting={setting=metrics.scaleSetting};target.settings[#target.settings+1]=setting end
        setting.value=(metrics.nativeScale-100)/5
    end
    local ok,failure=pcall(function()
        C_EditMode.SaveLayouts(candidate);C_EditMode.SetActiveLayout(data.activeLayout)
        local updated=readLayouts();local current=updated and updated.layouts[updated.activeLayout]
        local accepted=false
        for _,system in ipairs(current and current.systems or {}) do
            if system.system==metrics.system and (system.systemIndex or 0)==metrics.systemIndex then
                local a=system.anchorInfo
                accepted=partyAnchorMatches(a,anchor)
                if accepted and metrics.nativeScale then
                    accepted=false
                    for _,entry in ipairs(system.settings or {}) do
                        if entry.setting==metrics.scaleSetting and entry.value==(metrics.nativeScale-100)/5 then accepted=true end
                    end
                end
            end
        end
        if not accepted then error("Party anchor readback did not match.") end
    end)
    if not ok then
        pcall(function() C_EditMode.SaveLayouts(data);C_EditMode.SetActiveLayout(data.activeLayout) end)
        return nil,"Native party docking failed: "..tostring(failure)
    end
    record.partyDock={source=source,written=copy(target),scaleSetting=metrics.nativeScale and metrics.scaleSetting or nil}
    return true,"Interactive Party trial: native targeting and health/resource UI docked; verify in a party."
end
function H.UndockParty(db)
    local record=db and db.hud
    if not record or not record.partyDock then return true end
    if windowCombat() then return nil,"Party restoration pending until combat ends." end
    if EditModeManagerFrame:IsShown() or EditModeManagerFrame:HasActiveChanges() then return nil,"Close Edit Mode and save or discard its edits before restoring Party mode." end
    local data=readLayouts();local layout=data and data.layouts[data.activeLayout]
    if not layout or layout.layoutName~=record.generatedName then return true end
    local dock=record.partyDock
    for index,system in ipairs(layout.systems) do
        if systemKey(system)==systemKey(dock.written) then
            local a,b=system.anchorInfo,dock.written.anchorInfo
            if not partyAnchorMatches(a,b) then
                return nil,"Party frames were moved independently. Restore their position in Edit Mode before switching modes."
            end
            local restoredSystem=copy(system)
            restoredSystem.anchorInfo=copy(dock.source.anchorInfo);restoredSystem.anchorInfo2=copy(dock.source.anchorInfo2)
            restoredSystem.isInDefaultPosition=dock.source.isInDefaultPosition
            if dock.scaleSetting then
                local writtenValue,sourceValue
                for _,entry in ipairs(dock.written.settings or {}) do if entry.setting==dock.scaleSetting then writtenValue=entry.value end end
                for _,entry in ipairs(dock.source.settings or {}) do if entry.setting==dock.scaleSetting then sourceValue=entry.value end end
                for settingIndex,entry in ipairs(restoredSystem.settings or {}) do
                    if entry.setting==dock.scaleSetting and entry.value==writtenValue then
                        if sourceValue~=nil then entry.value=sourceValue else table.remove(restoredSystem.settings,settingIndex) end
                        break
                    end
                end
            end
            local candidate=copy(data);candidate.layouts[data.activeLayout].systems[index]=restoredSystem
            local ok,err=pcall(function()
                C_EditMode.SaveLayouts(candidate);C_EditMode.SetActiveLayout(data.activeLayout)
                local updated=readLayouts();local current=updated and updated.layouts[updated.activeLayout]
                local restored=current and current.systems[index]
                local a,b=restored and restored.anchorInfo,dock.source.anchorInfo
                if not partyAnchorMatches(a,b) then error("Restored party anchor readback did not match.") end
                if dock.scaleSetting then
                    local expected,actual
                    for _,entry in ipairs(restoredSystem.settings or {}) do if entry.setting==dock.scaleSetting then expected=entry.value end end
                    for _,entry in ipairs(restored.settings or {}) do if entry.setting==dock.scaleSetting then actual=entry.value end end
                    if expected~=actual then error("Restored party size readback did not match.") end
                end
            end)
            if not ok then return nil,"Party restoration failed: "..tostring(err) end
            record.partyDock=nil;return true
        end
    end
    return nil,"The docked party system is unavailable for restoration."
end

-- Native Minimap uses the same owned Edit Mode layout as Party. Move the whole
-- cluster so native tracking, zoom, mail and calendar controls keep their behavior.
function H.MinimapMetrics(g,pixelsPerUnit)
    local frame=MinimapCluster
    if not frame or not frame.system or not frame.GetEffectiveScale then return nil,'Native MinimapCluster/Edit Mode is unavailable on this client.' end
    local registered=false
    for _,entry in ipairs(EditModeManagerFrame and EditModeManagerFrame.registeredSystemFrames or {}) do if entry==frame then registered=true end end
    if not registered then return nil,'Minimap is not registered with Edit Mode.' end
    local scale=L.PixelsPerUnit(frame:GetEffectiveScale(),g.height)
    local w,h=frame:GetWidth(),frame:GetHeight()
    if not scale or not finite(w) or not finite(h) or w<=0 or h<=0 then return nil,'Native minimap dimensions are unavailable.' end
    return {width=w*scale,height=h*scale,slotHeight=math.ceil(h*scale/pixelsPerUnit+64),system=frame.system,systemIndex=frame.systemIndex or 0}
end
local function minimapAnchor(a)
    return a and (a.relativeTo=='MinimapCluster' or a.relativeTo=='Minimap')
end
local function anchorStateMatches(a,b)
    if not a or not b then return false end
    local function matches(x,y) return (x==nil and y==nil) or partyAnchorMatches(x,y) end
    return matches(a.anchorInfo,b.anchorInfo) and matches(a.anchorInfo2,b.anchorInfo2)
        and (a.isInDefaultPosition==true)==(b.isInDefaultPosition==true)
end
local function setAnchorState(target,source)
    target.anchorInfo=copy(source.anchorInfo);target.anchorInfo2=copy(source.anchorInfo2)
    target.isInDefaultPosition=source.isInDefaultPosition
end
local function saveMinimapAnchors(data,candidate,layoutName,expected)
    local ok,message=pcall(function()
        C_EditMode.SaveLayouts(candidate);C_EditMode.SetActiveLayout(data.activeLayout)
        local updated=readLayouts();local layout=updated and updated.layouts[updated.activeLayout]
        if not layout or layout.layoutName~=layoutName then error('Owned HUD layout was not accepted.') end
        local readback={};for _,system in ipairs(layout.systems) do readback[systemKey(system)]=system end
        for key,anchors in pairs(expected) do
            if not anchorStateMatches(readback[key],anchors) then error('HUD anchor readback did not match for system '..key..'.') end
        end
    end)
    if not ok then pcall(function()C_EditMode.SaveLayouts(data);C_EditMode.SetActiveLayout(data.activeLayout)end);return nil,tostring(message) end
    return true
end
local function pinMinimapDependent(system,rect,main,ppu)
    if not rect or rect.width>main.width or rect.height>main.height then return nil end
    local x=math.max(main.x,math.min(rect.x,main.x+main.width-rect.width))
    local y=math.max(main.y,math.min(rect.y,main.y+main.height-rect.height))
    local function pin(anchor)
        local factor=anchor and anchorFactors[anchor.point]
        if not factor then return nil end
        return {point=anchor.point,relativeTo='UIParent',relativePoint='TOPLEFT',
            offsetX=(x+factor[1]*rect.width)/ppu,offsetY=-(y+(1-factor[2])*rect.height)/ppu}
    end
    local first,second=pin(system.anchorInfo),pin(system.anchorInfo2)
    if not first or (system.anchorInfo2 and not second) then return nil end
    return {anchorInfo=first,anchorInfo2=second,isInDefaultPosition=false}
end
function H.DockMinimap(g,pixelsPerUnit,rect,db)
    if windowCombat() then return nil,'Dock Minimap outside combat.' end
    local metrics,err=H.MinimapMetrics(g,pixelsPerUnit);if not metrics then return nil,err end
    if EditModeManagerFrame:IsShown() or EditModeManagerFrame:HasActiveChanges() then return nil,'Save/discard Edit Mode edits and close it before docking Minimap.' end
    if metrics.width>rect.width or metrics.height>rect.height-64*pixelsPerUnit then return nil,'Native minimap does not fit. Widen the dock/use fewer columns, or resize it in Edit Mode.' end
    local record=db.hud;local data=readLayouts();local layout=data and data.layouts[data.activeLayout]
    if not record or not layout or layout.layoutName~=record.generatedName then return nil,'Center Blizzard HUD before docking Minimap.' end
    local candidate=copy(data);local target
    for _,system in ipairs(candidate.layouts[data.activeLayout].systems) do
        if system.system==metrics.system and (system.systemIndex or 0)==metrics.systemIndex then target=system end
    end
    if not target then return nil,'Minimap system is absent from the native layout.' end
    local dependents=copy(record.minimapDock and record.minimapDock.dependents or {})
    local measurements=measure(g)
    local expected={}
    for _,system in ipairs(candidate.layouts[data.activeLayout].systems) do
        if system~=target and (minimapAnchor(system.anchorInfo) or minimapAnchor(system.anchorInfo2)) then
            local key=systemKey(system)
            local pinned=pinMinimapDependent(system,measurements[key],g.main,pixelsPerUnit)
            if not pinned then return nil,'Cannot keep HUD system '..key..' on Main. Show it or unsnap it from Minimap in Edit Mode, then retry.' end
            dependents[key]={source=copy(system),written=pinned}
            setAnchorState(system,pinned);expected[key]=pinned
        end
    end
    local source=record.minimapDock and record.minimapDock.source or copy(target)
    local anchor={point='TOPRIGHT',relativeTo='UIParent',relativePoint='TOPLEFT',
        offsetX=(rect.x+(rect.width+metrics.width)/2)/pixelsPerUnit,offsetY=-(rect.y+52*pixelsPerUnit)/pixelsPerUnit}
    target.anchorInfo=anchor;target.anchorInfo2=nil;target.isInDefaultPosition=false
    expected[systemKey(target)]=target
    local ok,message=saveMinimapAnchors(data,candidate,record.generatedName,expected)
    if not ok then return nil,'Minimap docking failed: '..message end
    record.minimapDock={source=source,written=copy(target),dependents=dependents}
    return true,'Native minimap docked; its native controls remain in use.'
end
function H.UndockMinimap(db)
    local record=db and db.hud;local dock=record and record.minimapDock
    if not dock then return true end
    if windowCombat() then return nil,'Minimap restoration waits for combat to end.' end
    if EditModeManagerFrame:IsShown() or EditModeManagerFrame:HasActiveChanges() then return nil,'Close Edit Mode before restoring Minimap.' end
    local data=readLayouts();local layout=data and data.layouts[data.activeLayout]
    if not layout or layout.layoutName~=record.generatedName then return true end
    local candidate=copy(data);local expected={};local found=false
    for _,system in ipairs(candidate.layouts[data.activeLayout].systems) do
        local key=systemKey(system)
        if key==systemKey(dock.written) then
            if not anchorStateMatches(system,dock.written) then return nil,'Minimap was moved independently. Restore its anchor in Edit Mode before removing this panel.' end
            setAnchorState(system,dock.source);expected[key]=dock.source;found=true
        else
            local saved=dock.dependents and dock.dependents[key]
            -- A user edit to a detached system owns its new position.
            if saved and anchorStateMatches(system,saved.written) then
                setAnchorState(system,saved.source);expected[key]=saved.source
            end
        end
    end
    if not found then return nil,'Minimap system unavailable for restoration.' end
    local ok,message=saveMinimapAnchors(data,candidate,record.generatedName,expected)
    if not ok then return nil,message end
    record.minimapDock=nil;return true
end
local nativeHidden={}
function H.NativeHidden(name,hidden)
    if windowCombat() then return nil,'Native panel visibility waits for combat to end.' end
    local frame=_G[name]
    if not frame then return not hidden,'Native frame unavailable: '..name end
    if hidden then
        nativeHidden[name]=nativeHidden[name] or {shown=frame:IsShown()}
        frame:Hide()
    else
        local record=nativeHidden[name]
        if record and record.shown and not frame:IsShown() then frame:Show() end
        nativeHidden[name]=nil
    end
    return true
end
function H.RestoreVisibility()
    if windowCombat() and next(nativeHidden) then return nil,'Native visibility restoration pending.' end
    for name in pairs(nativeHidden) do local ok,message=H.NativeHidden(name,false);if not ok then return nil,message end end
    return true
end
function H.RefreshVisibility()
    if windowCombat() then return end
    for name in pairs(nativeHidden) do local frame=_G[name];if frame and frame:IsShown() then frame:Hide() end end
end

-- Client capability/permission checks are repeated at click time. Never use the
-- Confirm* APIs that bypass Blizzard's own conversion/invite confirmation flows.
local A={}
FW.GroupActions=A
local function groupRead(api,name,...)
    local fn=api[name];if type(fn)~='function' then return nil end
    local ok,value=pcall(fn,...)
    local secret=api.issecretvalue or issecretvalue
    if not ok or (type(secret)=='function' and secret(value)) then return nil end
    return value
end
function A.State(action,api,context)
    api=api or _G;local info=api.C_PartyInfo or {}
    if groupRead(api,'InCombatLockdown')==true then return nil,'Group actions are available outside combat.' end
    local count,raid
    if context then count=context.count;raid=context.mode=='raid'
    else count=groupRead(api,'GetNumGroupMembers');raid=groupRead(api,'IsInRaid') end
    if not finite(count) or type(raid)~='boolean' then return nil,'Group state is unavailable.' end
    local leader=groupRead(api,'UnitIsGroupLeader','player')==true
    local assistant=groupRead(api,'UnitIsGroupAssistant','player')==true
    if action=='invite' then
        local allowed;if type(info.CanInvite)=='function' then allowed=groupRead(info,'CanInvite') end
        if type(info.CanInvite)=='function' and allowed==nil then return nil,'Invite permission is unavailable.' end
        if allowed==false or (allowed==nil and count>0 and not leader and not assistant) then return nil,'You do not have invite permission.' end
        local fn=info.InviteUnit or api.InviteUnit
        return type(fn)=='function' and fn or nil,'Invite API unavailable on this client.'
    elseif action=='raid' then
        if raid then return nil,'You are already in a raid.' end
        if count<2 then return nil,'Invite a player to form a party first.' end
        if not leader then return nil,'Only the group leader can convert to raid.' end
        if type(info.AllowedToDoPartyConversion)=='function' and groupRead(info,'AllowedToDoPartyConversion',true)~=true then return nil,'This party cannot currently convert to a raid.' end
        local fn=info.ConvertToRaid or api.ConvertToRaid
        return type(fn)=='function' and fn or nil,'Raid conversion API unavailable.'
    elseif action=='ready' then
        if count<2 or (not leader and not assistant) then return nil,'Ready check needs a group and leader/assistant permission.' end
        local fn=info.DoReadyCheck or api.DoReadyCheck
        return type(fn)=='function' and fn or nil,'Ready-check API unavailable.'
    end
    return nil,'Unknown group action.'
end
function A.Run(action,name,api)
    local fn,message=A.State(action,api);if not fn then return nil,message end
    if action=='invite' then
        if type(name)~='string' then return nil,'Enter Character-Realm.' end
        name=name:gsub('^%s+',''):gsub('%s+$','')
        if name=='' or #name>160 or name:find('[%z\1-\31]') then return nil,'Enter a valid Character-Realm name.' end
    end
    local ok,err
    if action=='invite' then ok,err=pcall(fn,name) else ok,err=pcall(fn) end
    if not ok then return nil,'Group action was blocked: '..tostring(err) end
    return true,action=='invite' and 'Invite requested; Blizzard may ask for confirmation.' or 'Action requested through Blizzard.'
end
