local addonName, FW = ...
local L = FW.Layout
local D=FW.Dock
local VERSION = "0.11.3"
FW.Version = VERSION
local active, originalPoints, deadline, pendingRestore, pendingHudRestore
local pendingWindowRestore
local pendingBagRestore, lockedPartyLayouts
local zoning, zoneResumeAt, appliedPixelRatio, loadingScreen
local sampleFrames, controls, diagnosticBox = {}, nil, nil
local bagControls
local configControls,openConfigOptions,beginAlignment,drawAlignment,fitCurrentWindow
local alignmentFrame,alignmentBox,alignmentActive,alignmentDeadline,alignmentRequested,pendingAlignmentRestore
local alignmentRefreshAt=0
local alignmentRestoreAt,alignmentRestoreAttempts=0,0
local questsDirty, questRefreshAt = true, 0
local groupsDirty, groupRefreshAt = true, 0
local providerRefreshAt=0
local selected = 1
local appliedPanels, reflowPanels
local dockPreferences={left=D.Options(),right=D.Options()}
local appliedDocks,toggleMinimized,openDockOptions,openInvite
local pendingMinimize={}
local defaults = {
    {id="party", title="Party overview", region="left", min=120, preferred=190, max=280, fill=false},
    {id="raid", title="Raid overview", region="left", min=160, preferred=300, max=600, fill=true},
    {id="dungeon", title="Dungeon reference", region="right", min=160, preferred=260, max=420, fill=false},
    {id="quests", title="Quest objectives", region="right", min=180, preferred=320, max=700, fill=true},
    {id="minimap", title="Minimap", region="right", min=320, preferred=330, max=500, fill=false,enabled=false},
    {id="tomtom", title="TomTom coordinates", region="right", min=120, preferred=140, max=260, fill=false,enabled=false},
}
local preferences = {}
local textSizes = {}
local textProviders={tomtom={}}
local pendingProviders={}
local providerCount=0
local function secret(value) return issecretvalue and issecretvalue(value) end
local function providerID(id)
    return not secret(id) and type(id)=='string' and #id<=64 and id:match('^[a-z][a-z0-9_%-]*%.[a-z0-9][a-z0-9_%-]*$')~=nil
end
local function plainText(value,maxBytes)
    return not secret(value) and type(value)=='string' and #value<=maxBytes and not value:find('[|%z\1-\9\11-\31\127]')
end
local api={version=1}
PeripheralAPI=api
function api.RegisterTextPanel(spec)
    if secret(spec) or type(spec)~='table' or getmetatable(spec)~=nil then return nil,'Expected a panel definition table.' end
    if secret(spec.apiVersion) or spec.apiVersion~=api.version then return nil,'Unsupported Peripheral provider API version.' end
    local id,title,side=spec.id,spec.title,spec.defaultSide
    if not providerID(id) then return nil,'Use a unique ID such as myaddon.status.' end
    if textProviders[id] then return nil,'Panel ID is already registered.' end
    if not plainText(title,48) or title:find('\n',1,true) or not title:find('%S') then return nil,'Use a short plain-text title.' end
    if secret(side) or (side~=nil and side~='left' and side~='right') then return nil,'Choose left or right as the default side.' end
    if providerCount>=32 then return nil,'Peripheral supports up to 32 external text panels.' end
    local entry={}
    local panel={id=id,title=title,region=side or 'right',min=120,preferred=160,max=400,fill=false,enabled=false}
    textProviders[id]=entry;providerCount=providerCount+1
    defaults[#defaults+1]=panel
    if controls then pendingProviders[#pendingProviders+1]=panel end
    local handle={}
    function handle:SetText(value)
        if not plainText(value,4096) then return nil,'Expected up to 4096 bytes of plain text.' end
        entry.text=value
        return true
    end
    function handle:IsVisible()
        local frame=sampleFrames[id]
        return active==true and not zoning and not loadingScreen and not zoneResumeAt
            and frame~=nil and frame:IsShown() and not frame.minimized
    end
    return handle
end
local T={minimum=10,maximum=28,default=14}
FW.TextSizing=T
function T.Normalize(value)
    if not L.Finite(value) then return T.default end
    return math.max(T.minimum,math.min(T.maximum,math.floor(value+0.5)))
end
function T.Load(saved)
    local sizes={}
    for _,panel in ipairs(defaults) do sizes[panel.id]=T.Normalize(type(saved)=="table" and saved[panel.id] or nil) end
    return sizes
end
local J={dirty=true}
function J.IsRetail()
    return not (WOW_PROJECT_ID and WOW_PROJECT_MAINLINE and WOW_PROJECT_ID~=WOW_PROJECT_MAINLINE)
end
local function readDungeon()
    local journal=C_EncounterJournal
    if not J.IsRetail() or not (journal and journal.GetInstanceForGameMap and GetInstanceInfo and EJ_GetEncounterInfoByIndex) then
        return 'The built-in Dungeon reference currently requires Retail WoW.'
    end
    local name,kind,_,_,_,_,_,mapID=GetInstanceInfo()
    if secret(kind) or secret(mapID) then return 'Dungeon information is temporarily unavailable.' end
    if kind~='party' and kind~='raid' then
        return 'Enter a dungeon or raid to see its bosses here.'
    end
    if type(mapID)~='number' or mapID<=0 then return 'Dungeon information is temporarily unavailable.' end
    local instanceID=journal.GetInstanceForGameMap(mapID)
    if secret(instanceID) or type(instanceID)~='number' or instanceID<=0 then
        return 'The Adventure Guide has no entry for this instance.'
    end
    local lines={plainText(name,256) and name or 'Current instance',''}
    -- Pass the instance explicitly so the read leaves the open guide's selection alone.
    for index=1,100 do
        local boss,_,encounterID=EJ_GetEncounterInfoByIndex(index,instanceID)
        if secret(encounterID) or type(encounterID)~='number' or encounterID<=0 then break end
        if plainText(boss,256) then lines[#lines+1]=index..'. '..boss end
    end
    if #lines==2 then lines[3]='No bosses are listed for this instance.' end
    return table.concat(lines,'\n'),instanceID
end

-- Consume only TomTom's published text feed. Neither the provider's frame,
-- settings nor its embedded libraries are owned by Peripheral.
local TT={}
FW.TomTom=TT
function TT.Read(env)
    env=env or _G
    local ok,value=pcall(function()
        local broker=env.LibStub and env.LibStub('LibDataBroker-1.1',true)
        local feed=broker and broker:GetDataObjectByName('TomTom_Coords')
        if feed then return feed.text or '' end
    end)
    if not ok then return 'TomTom coordinates are temporarily unavailable.' end
    if env.issecretvalue and env.issecretvalue(value) then return 'TomTom coordinates are temporarily unavailable.' end
    if value==nil then return 'Install and enable TomTom separately to use this panel.' end
    if value=='' then return 'In /tomtom, open Data Feed Options and enable the coordinates feed. If already enabled, move or try outdoors.' end
    if type(value)~='string' or #value>96 or value:find('[|%c]') then return 'TomTom coordinates are temporarily unavailable.' end
    return 'Player coordinates\n'..value
end

-- Read-only provider, separate from placement and rendering. Normal and world
-- quest watches share a deduplicated list; watching/unwatching remains Blizzard's.
local Q={requested={},lastStatus="not read",lastCount=0}
FW.Quests=Q
function Q.Read(api)
    api=api or C_QuestLog
    if not api or type(api.GetNumQuestWatches)~="function" or type(api.GetQuestIDForQuestWatchIndex)~="function"
        or type(api.GetTitleForQuestID)~="function" or type(api.GetQuestObjectives)~="function" then
        return {items={},status="unsupported",message="Tracked quest data is unavailable on this client."}
    end
    local ok,result=pcall(function()
        local items,seen,ids,pending={}, {}, {}, {}
        local function add(id)
            if not L.Finite(id) or id<=0 or seen[id] then return end
            seen[id]=true;ids[#ids+1]=tostring(id)
            local title=api.GetTitleForQuestID(id)
            local haveTitle=type(title)=="string" and title~=""
            local raw=api.GetQuestObjectives(id)
            local item={id=id,title=haveTitle and title or ("Quest "..id.." (loading...)"),objectives={}}
            item.complete=api.IsComplete and api.IsComplete(id) or false
            item.failed=api.IsFailed and api.IsFailed(id) or false
            item.loading=not haveTitle or raw==nil
            if item.loading then pending[#pending+1]=id end
            for _,objective in ipairs(raw or {}) do
                local text=objective.text
                if type(text)~="string" or text=="" then
                    text="Objective"
                    if L.Finite(objective.numFulfilled) and L.Finite(objective.numRequired) then
                        text=text..": "..objective.numFulfilled.." / "..objective.numRequired
                    end
                end
                if objective.type=="progressbar" and type(GetQuestProgressBarPercent)=="function" then
                    local progress=GetQuestProgressBarPercent(id)
                    if L.Finite(progress) then text=text..string.format(" (%.0f%%)",math.max(0,math.min(100,progress))) end
                end
                item.objectives[#item.objectives+1]={text=text,finished=objective.finished==true}
            end
            items[#items+1]=item
        end
        local function watches(countFn,idFn)
            local count=countFn()
            if not L.Finite(count) or count<0 or count>1000 then error("Invalid quest watch count") end
            for index=1,count do add(idFn(index)) end
        end
        watches(api.GetNumQuestWatches,api.GetQuestIDForQuestWatchIndex)
        if type(api.GetNumWorldQuestWatches)=="function" and type(api.GetQuestIDForWorldQuestWatchIndex)=="function" then
            watches(api.GetNumWorldQuestWatches,api.GetQuestIDForWorldQuestWatchIndex)
        end
        -- Requests happen after the snapshot so a synchronous data event cannot
        -- change the list halfway through enumeration. Request each pending ID once.
        for _,id in ipairs(pending) do
            if not Q.requested[id] and api.RequestLoadQuestByID then
                Q.requested[id]=true;pcall(api.RequestLoadQuestByID,id)
            end
        end
        return {items=items,status=#items==0 and "empty" or "ready",signature=table.concat(ids,",")}
    end)
    if not ok then return {items={},status="error",message="Quest data is temporarily unavailable. Use /fws diag for details.",error=tostring(result)} end
    return result
end
function Q.Text(model)
    if model.message then return model.message end
    if #model.items==0 then return "No tracked quests.\n\nTrack a quest in Blizzard's quest log to show it here.\n\nThis panel reads your tracked quests automatically." end
    local lines={}
    for _,item in ipairs(model.items) do
        lines[#lines+1]="|cffffd080"..item.title.."|r"
        if item.failed then lines[#lines+1]="  |cffff6666Failed|r"
        elseif item.complete then lines[#lines+1]="  |cff70db90Ready to turn in|r" end
        for _,objective in ipairs(item.objectives) do
            local prefix=objective.finished and "  |cff70db90[x] " or "  [ ] "
            lines[#lines+1]=prefix..objective.text..(objective.finished and "|r" or "")
        end
        if item.loading then lines[#lines+1]="  Loading quest data..."
        elseif #item.objectives==0 and not item.complete and not item.failed then lines[#lines+1]="  See the quest log for details." end
        lines[#lines+1]=""
    end
    return table.concat(lines,"\n")
end

-- Read-only roster summaries. Never compare, format or retain secret values.
-- Missing/restricted optional fields do not discard otherwise available members.
local G={lastStatus="not read",lastCount=0}
FW.Groups=G
function G.Read(api)
    api=api or _G
    if type(api.GetNumGroupMembers)~="function" or type(api.IsInRaid)~="function" or type(api.UnitName)~="function" then
        return {party={},raid={},status="unsupported",message="Group roster data is unavailable on this client."}
    end
    local ok,model=pcall(function()
        local restricted,unavailable=false,false
        local secret=api.issecretvalue or issecretvalue
        local function plain(value)
            if type(secret)=="function" and secret(value) then restricted=true;return nil end
            return value
        end
        local function read(fn,...)
            if type(fn)~="function" then return nil end
            local success,value=pcall(fn,...)
            if not success then unavailable=true;return nil end
            return plain(value)
        end
        local count=read(api.GetNumGroupMembers)
        local raid=read(api.IsInRaid)
        if not L.Finite(count) or count<0 or count>40 or count~=math.floor(count) or type(raid)~="boolean" then
            return {party={},raid={},status=restricted and "restricted" or "error",message="Group roster is temporarily unavailable. Use /fws diag for details."}
        end
        local result={party={},raid={},count=count,mode=raid and "raid" or (count>0 and "party" or "solo")}
        local signatures={party={},raid={}}
        local function member(unit,index,subgroup,rank)
            local success,name,realm=pcall(api.UnitName,unit)
            if not success then unavailable=true;name,realm=nil,nil end
            name,realm=plain(name),plain(realm)
            if type(name)~="string" or name=="" then name="Member "..index.." (unavailable)" end
            if type(realm)=="string" and realm~="" then name=name.."-"..realm end
            local role=read(api.UnitGroupRolesAssigned,unit)
            if role~="TANK" and role~="HEALER" and role~="DAMAGER" then role="NONE" end
            local class=read(api.UnitClass,unit)
            local entry={unit=unit,name=name,role=role,subgroup=subgroup,
                class=type(class)=="string" and class or nil,
                connected=read(api.UnitIsConnected,unit),dead=read(api.UnitIsDeadOrGhost,unit),
                leader=read(api.UnitIsGroupLeader,unit)==true or rank==2,
                assistant=read(api.UnitIsGroupAssistant,unit)==true or rank==1}
            return entry
        end
        local function add(list,entry)
            result[list][#result[list]+1]=entry
            signatures[list][#signatures[list]+1]=entry.unit..":"..entry.name..":"..tostring(entry.subgroup)
        end
        if raid then
            for index=1,count do
                local unit="raid"..index
                local subgroup,rank
                if type(api.GetRaidRosterInfo)=="function" then
                    local success,_,rawRank,rawGroup=pcall(api.GetRaidRosterInfo,index)
                    if success then
                        rank,subgroup=plain(rawRank),plain(rawGroup)
                        if not L.Finite(subgroup) or subgroup<1 or subgroup>8 or subgroup~=math.floor(subgroup) then subgroup=nil end
                    else unavailable=true end
                end
                local entry=member(unit,index,subgroup,rank)
                add("raid",entry)
                if read(api.UnitIsUnit,unit,"player")==true then result.playerSubgroup=subgroup end
            end
            if result.playerSubgroup then
                for _,entry in ipairs(result.raid) do if entry.subgroup==result.playerSubgroup then add("party",entry) end end
            end
        elseif count>0 then
            if count>5 then error("Invalid party member count") end
            add("party",member("player",1))
            for index=1,count-1 do add("party",member("party"..index,index+1)) end
        end
        result.status=restricted and "restricted" or (unavailable and "limited" or "ready")
        result.note=restricted and "Some roster details are restricted by this client." or (unavailable and "Some roster details are temporarily unavailable." or nil)
        result.signatures={party=table.concat(signatures.party,"|"),raid=table.concat(signatures.raid,"|")}
        return result
    end)
    if not ok then return {party={},raid={},status="error",message="Group roster is temporarily unavailable. Use /fws diag for details.",error=tostring(model)} end
    return model
end
function G.Text(model,kind)
    if model.message then return model.message end
    local entries=model[kind]
    if #entries==0 then
        if kind=="raid" then return "You are not in a raid.\n\nJoin a raid to see its roster and subgroups." end
        if model.mode=="raid" then return "Your raid subgroup is unavailable.\n\nSee Raid overview for the available roster." end
        return "You are not in a party.\n\nJoin a party to see its members and assigned roles."
    end
    local roles={TANK="Tank",HEALER="Healer",DAMAGER="Damage",NONE="Unassigned"}
    local tanks,healers,damage,unassigned=0,0,0,0
    for _,entry in ipairs(entries) do
        if entry.role=="TANK" then tanks=tanks+1 elseif entry.role=="HEALER" then healers=healers+1
        elseif entry.role=="DAMAGER" then damage=damage+1 else unassigned=unassigned+1 end
    end
    local lines={string.format("Roles: %d tank / %d healer / %d damage",tanks,healers,damage)}
    if unassigned>0 then lines[#lines+1]=unassigned.." role(s) unassigned" end
    if model.note then lines[#lines+1]=model.note end
    lines[#lines+1]=""
    local function row(entry)
        local tags={roles[entry.role]}
        if entry.class then tags[#tags+1]=entry.class end
        if entry.leader then tags[#tags+1]="Leader" elseif entry.assistant then tags[#tags+1]="Assistant" end
        if entry.connected==false then tags[#tags+1]="Offline" elseif entry.dead==true then tags[#tags+1]="Dead / ghost" end
        lines[#lines+1]="|cffffd080"..entry.name.."|r\n  "..table.concat(tags," / ")
    end
    if kind=="raid" then
        for group=1,8 do
            local haveGroup=false
            for _,entry in ipairs(entries) do
                if entry.subgroup==group then
                    if not haveGroup then lines[#lines+1]="|cff90c8ffGroup "..group.."|r";haveGroup=true end
                    row(entry)
                end
            end
            if haveGroup then lines[#lines+1]="" end
        end
        local unknown=false
        for _,entry in ipairs(entries) do
            if not entry.subgroup then
                if not unknown then lines[#lines+1]="Subgroup unavailable";unknown=true end
                row(entry)
            end
        end
    else
        if model.playerSubgroup then lines[#lines+1]="Raid subgroup "..model.playerSubgroup end
        for _,entry in ipairs(entries) do row(entry) end
    end
    return table.concat(lines,"\n")
end
function G.RelevantUnit(unit)
    if type(issecretvalue)=="function" and issecretvalue(unit) then return false end
    if type(unit)~="string" then return false end
    return unit=="player" or unit:match("^party[1-4]$")~=nil or unit:match("^raid%d+$")~=nil
end

local N={}
FW.NativePanels=N
function N.Read(env)
    env=env or _G
    return {
        {name="Chat",present=env.ChatFrame1~=nil,detail="Native tabs, links and input; placement adapter planned."},
        {name="Minimap",present=env.MinimapCluster~=nil,detail="Optional native panel; Edit Mode capability is checked on Apply."},
        {name="Bags",present=env.ContainerFrameCombinedBags~=nil or env.ContainerFrame1~=nil,
            detail="Main placement available through Center Blizzard HUD; native items and layout retained."},
    }
end

local function say(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffffd080Peripheral:|r " .. tostring(message)) end
end
local function geometrySummary()
    local g=FW.Geometry
    if not g then return "No monitor configuration. Connect the Windows helper or use Setup / Import." end
    local parts={"Taskbar clearance: "..(g.respectWorkArea and "ON" or "OFF")}
    for _,r in ipairs(g.regions or {}) do parts[#parts+1]=r.id.." "..r.width.." x "..r.height end
    return table.concat(parts," | ")
end
local function clone(t)
    local r = {}
    for k, v in pairs(t) do r[k] = type(v) == "table" and clone(v) or v end
    return r
end
local function inCombat() return InCombatLockdown and InCombatLockdown() end
local function openDungeonGuide(instanceID)
    if inCombat() then say('Open the Adventure Guide outside combat.');return end
    local ok,shown=pcall(function()
        if C_AdventureJournal and C_AdventureJournal.CanBeShown and not C_AdventureJournal.CanBeShown() then return false end
        if not EncounterJournal then
            if EncounterJournal_LoadUI then EncounterJournal_LoadUI()
            elseif C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn('Blizzard_EncounterJournal') end
        end
        if EncounterJournal and instanceID and EncounterJournal_OpenJournal then
            EncounterJournal_OpenJournal(nil,instanceID)
        elseif not (EncounterJournal and EncounterJournal:IsShown()) then
            if ToggleEncounterJournal then ToggleEncounterJournal()
            elseif EncounterJournal and ShowUIPanel then ShowUIPanel(EncounterJournal) end
        end
        if not EncounterJournal or not EncounterJournal:IsShown() then return false end
        if not instanceID and EncounterJournal.dungeonsTab and EncounterJournal.dungeonsTab.Click then
            EncounterJournal.dungeonsTab:Click()
        end
        return true
    end)
    if not ok or not shown then say('The Adventure Guide could not be opened on this client.');return end
    local placed,fits=pcall(FW.NativeWindows.PlaceGuide,FW.Geometry)
    if not placed or not fits then say('The Adventure Guide opened at its native position. Peripheral could not fit it on Main.') end
end
local function canvasInfo()
    local physicalWidth,physicalHeight
    if GetPhysicalScreenSize then physicalWidth,physicalHeight=GetPhysicalScreenSize() end
    return L.Canvas(physicalWidth,physicalHeight,UIParent:GetWidth(),UIParent:GetHeight(),UIParent:GetEffectiveScale())
end
local function button(parent, text, x, y, width, action)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 24); b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y); b:SetText(text)
    b:SetScript("OnClick", action)
    return b
end
local function label(parent, text, x, y, width)
    local f = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y); f:SetWidth(width or 560)
    f:SetJustifyH("LEFT"); f:SetText(text)
    return f
end
local function setTextFont(fontString,size)
    local file,_,flags=fontString:GetFont()
    if file then fontString:SetFont(file,size,flags or "") end
end
openInvite=function()
    if not controls.inviteBox then
        local box=CreateFrame('Frame',nil,UIParent,'BackdropTemplate');controls.inviteBox=box
        box:SetSize(420,170);box:SetPoint('CENTER');box:SetFrameStrata('DIALOG');box:EnableMouse(true)
        box:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1});box:SetBackdropColor(.04,.06,.08,1)
        label(box,'Invite to party / raid',16,-12,388)
        local edit=CreateFrame('EditBox',nil,box,'InputBoxTemplate');box.edit=edit;edit:SetSize(370,26);edit:SetPoint('TOPLEFT',22,-42);edit:SetAutoFocus(false)
        if edit.SetMaxLetters then edit:SetMaxLetters(160) end
        box.status=label(box,'Enter Character-Realm. Nothing is sent until Send invite.',16,-80,388)
        button(box,'Send invite',16,-128,180,function()local ok,message=FW.GroupActions.Run('invite',edit:GetText());box.status:SetText(message);if ok and edit.ClearFocus then edit:ClearFocus() end end)
        button(box,'Close',208,-128,196,function()box:Hide()end)
        edit:SetScript('OnEscapePressed',function()box:Hide()end)
    end
    local canvas=canvasInfo();local g=FW.Geometry
    if canvas and g then local box=controls.inviteBox;box:ClearAllPoints();box:SetPoint('CENTER',UIParent,'TOPLEFT',(g.main.x+g.main.width/2)/canvas.pixelsPerUnit,-(g.main.y+g.main.height/2)/canvas.pixelsPerUnit)end
    controls.inviteBox:Show();controls.inviteBox.edit:SetFocus()
end
local function openBagOptions()
    if not bagControls then
        bagControls=CreateFrame("Frame","ForeverWorkspaceBagControls",controls.settingsHost)
        bagControls:SetAllPoints(controls.settingsHost);bagControls:EnableMouse(true)
        setTextFont(label(bagControls,"Bags - destination and layer",16,-14,568),16)
        label(bagControls,"Left/Right use the configured monitor strips. Native item scale stays unchanged.",16,-48,568)
        local destinations={"main","left","right","native"}
        local names={main="Main monitor",left="Left monitor strip",right="Right monitor strip",native="Blizzard placement"}
        bagControls.destination=button(bagControls,"",16,-96,568,function()
            for i,id in ipairs(destinations) do
                if id==bagControls.options.destination then bagControls.options.destination=destinations[i%#destinations+1];break end
            end
            bagControls.destination:SetText("Destination: "..names[bagControls.options.destination])
        end)
        bagControls.above=CreateFrame("CheckButton",nil,bagControls,"UICheckButtonTemplate")
        bagControls.above:SetPoint("TOPLEFT",16,-136)
        label(bagControls,"Above side panels",52,-143,524)
        bagControls.status=label(bagControls,"",16,-184,568);bagControls.status:SetHeight(82);bagControls.status:SetJustifyV("TOP")
        button(bagControls,"Apply and save",16,-310,270,function()
            if not active then bagControls.status:SetText("Apply and Keep the workspace viewport first.");return end
            if inCombat() then bagControls.status:SetText("Apply bag placement outside combat.");return end
            local canvas=canvasInfo()
            if not canvas or not L.ValidateGeometry(FW.Geometry,canvas.width,canvas.height) then bagControls.status:SetText("Align/size the current configuration and apply the viewport first.");return end
            local options=FW.Bags.Options(bagControls.options);options.above=bagControls.above:GetChecked()==true
            local ok,message=FW.Bags.Center(FW.Geometry,options)
            if ok then ForeverWorkspaceDB.bags=options end
            bagControls.status:SetText(message)
        end)
        button(bagControls,"Back to panel",302,-310,282,function() controls.SelectPanel(preferences[selected].id) end)
        bagControls.options=FW.Bags.Options(ForeverWorkspaceDB.bags)
        bagControls.destination:SetText("Destination: "..names[bagControls.options.destination])
        bagControls.above:SetChecked(bagControls.options.above)
        bagControls.status:SetText("Click Destination to cycle. Apply and save updates open bags and saves these options separately.")
    end
    controls.bagView=true;controls.configView=false;controls.dockView=nil
    controls.RefreshPanelSelection();controls:Show()
end
openDockOptions=function(side)
    if not controls.dockControls then
        local pane=CreateFrame('Frame',nil,controls.settingsHost);controls.dockControls=pane;pane:SetAllPoints(controls.settingsHost)
        pane.heading=label(pane,'',16,-14,568)
        pane.anchor=button(pane,'',16,-58,568,function()
            local o=dockPreferences[controls.dockView]
            for i,id in ipairs(D.anchors) do if id==o.anchor then o.anchor=D.anchors[i%#D.anchors+1];break end end
            openDockOptions(controls.dockView)
        end)
        pane.columns=button(pane,'',16,-102,568,function()local o=dockPreferences[controls.dockView];o.columns=o.columns%3+1;openDockOptions(controls.dockView)end)
        pane.widthCaption=label(pane,'',16,-154,568)
        pane.width=CreateFrame('Slider',nil,pane,'OptionsSliderTemplate');pane.width:SetPoint('TOPLEFT',pane,'TOPLEFT',20,-188);pane.width:SetSize(548,16)
        pane.width:SetOrientation('HORIZONTAL');pane.width:SetMinMaxValues(30,100);pane.width:SetValueStep(1);pane.width:SetObeyStepOnDrag(true)
        pane.width:SetScript('OnValueChanged',function(_,value)if pane.refreshing or not controls.dockView then return end;dockPreferences[controls.dockView].width=math.floor(value+.5);pane.widthCaption:SetText('Dock width: '..dockPreferences[controls.dockView].width..'% of the usable strip')end)
        label(pane,'Panels fill columns in list order, one row at a time. Each column stacks independently at the selected anchor. Wide native panels may require fewer columns or a wider monitor strip.',16,-234,568)
        label(pane,'Dock edits are staged. Apply trial previews all panel/dock changes; Keep saves them. Main 3D placement is unchanged.',16,-310,568)
    end
    controls.dockView=side;controls.bagView=false;controls.configView=false
    local pane=controls.dockControls;local o=dockPreferences[side];pane.refreshing=true
    pane.heading:SetText((side=='left' and 'Left' or 'Right')..' dock layout')
    pane.anchor:SetText('Anchor: '..o.anchor);pane.columns:SetText('Columns: '..o.columns)
    pane.widthCaption:SetText('Dock width: '..o.width..'% of the usable strip');pane.width:SetValue(o.width);pane.refreshing=false
    controls.RefreshPanelSelection();controls:Show()
end
local function openPanelSettings(panelID)
    if controls and controls.SelectPanel then controls.SelectPanel(panelID) end
end
local function contentPanel(panel)
    local frame=CreateFrame("Frame",nil,UIParent,"BackdropTemplate")
    frame.panelID=panel.id
    frame:SetFrameStrata("HIGH")
    frame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    frame:SetBackdropColor(0.08,0.10,0.13,0.98);frame:SetBackdropBorderColor(0.65,0.53,0.29,1)
    frame.title=label(frame,panel.title..(panel.id=="dungeon" and "" or " - LIVE v"..VERSION),12,-12,250)
    frame.title:SetWordWrap(true);frame.title:SetJustifyV("TOP")
    frame.settings=button(frame,"Settings",0,0,72,function() openPanelSettings(panel.id) end)
    frame.settings:ClearAllPoints();frame.settings:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-12,-10)
    frame.settings:ClearAllPoints();frame.settings:SetPoint('TOPRIGHT',frame,'TOPRIGHT',-44,-10)
    frame.minimize=button(frame,'-',0,0,24,function()toggleMinimized(panel.id)end)
    frame.minimize:ClearAllPoints();frame.minimize:SetPoint('TOPRIGHT',frame,'TOPRIGHT',-10,-10)
    frame.scroll=CreateFrame("ScrollFrame",nil,frame)
    frame.scroll:SetPoint("TOPLEFT",frame,"TOPLEFT",12,-38)
    frame.content=CreateFrame("Frame",nil,frame.scroll)
    frame.body=label(frame.content,"",0,0,250);frame.body:SetJustifyV("TOP")
    frame.body:SetWordWrap(true)
    if frame.body.SetNonSpaceWrap then frame.body:SetNonSpaceWrap(true) end
    frame.scroll:SetScrollChild(frame.content)
    frame.offset=0;frame.maximum=0
    frame.footer=label(frame,"Mouse wheel to scroll",116,-12,100)
    frame.footer:ClearAllPoints();frame.footer:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",116,15)
    function frame:ScrollBy(delta)
        self.offset=math.max(0,math.min(self.maximum,self.offset+delta))
        self.scroll:SetVerticalScroll(self.offset)
        self.footer:SetText(self.maximum>0 and string.format("%.0f / %.0f",self.offset,self.maximum) or "All shown")
    end
    function frame:LayoutContent()
        local width=math.max(1,self:GetWidth()-24)
        local collapsed=self.minimized==true
        if collapsed then self.title:SetText(({party='Party',raid='Raid',dungeon='Dungeon',quests='Quests',minimap='Minimap'})[panel.id] or panel.title) end
        self.title:SetWordWrap(not collapsed)
        self.title:SetWidth(math.max(1,width-(collapsed and 28 or 112)));self.title:SetHeight(0)
        if collapsed then self.title:SetHeight(math.max(24,(self.textSize or 14)+6));self.settings:Hide();self.minimize:SetText('+')
            for _,child in ipairs({self.scroll,self.up,self.down,self.footer,self.nativeHint})do child:Hide()end
            for _,child in ipairs(self.actions or {})do child:Hide()end
            return
        end
        self.settings:Show();self.minimize:SetText('-')
        if not self.interactive and panel.id~='minimap' then self.scroll:Show();self.up:Show();self.down:Show();self.footer:Show() end
        if panel.id=='minimap' then self.scroll:Hide();self.up:Hide();self.down:Hide();self.footer:Hide() end
        for _,child in ipairs(self.actions or {})do child:Show()end
        local titleHeight=math.min(math.max(1,self.title:GetStringHeight()),math.max(1,self:GetHeight()-96))
        self.title:SetHeight(titleHeight)
        local top=self.interactive and 96 or math.max(38,12+titleHeight+10)
        local height=math.max(1,self:GetHeight()-top-(self.actions and 70 or 42))
        self.scroll:ClearAllPoints();self.scroll:SetPoint("TOPLEFT",self,"TOPLEFT",12,-top);self.scroll:SetSize(width,height)
        self.content:SetWidth(width);self.body:SetWidth(width);self.body:SetHeight(0)
        local textHeight=math.max(1,self.body:GetStringHeight()+8)
        self.body:SetHeight(textHeight);self.content:SetHeight(math.max(height,textHeight))
        self.maximum=math.max(0,textHeight-height)
        self.footer:SetWidth(math.max(1,width-104));self:ScrollBy(0)
        for index,child in ipairs(self.actions or {})do
            local w=(width-4*(#self.actions-1))/#self.actions
            child:ClearAllPoints();child:SetPoint('BOTTOMLEFT',self,'BOTTOMLEFT',12+(index-1)*(w+4),40);child:SetWidth(w)
            if child.action then
                local enabled=FW.GroupActions.State(child.action,nil,self.groupModel or G.lastModel)
                if enabled and child.Enable then child:Enable() elseif not enabled and child.Disable then child:Disable() end
            end
        end
    end
    function frame:SetMinimized(value)
        if value and not self.minimized then self.expandedTitle=self.title:GetText() end
        if not value and self.minimized and self.expandedTitle then self.title:SetText(self.expandedTitle) end
        self.minimized=value==true
    end
    function frame:SetInteractive(enabled)
        self.interactive=enabled==true
        self:SetFrameStrata(self.interactive and "BACKGROUND" or "HIGH")
        for _,child in ipairs({self.scroll,self.up,self.down,self.footer}) do
            if self.interactive then child:Hide() else child:Show() end
        end
        if not self.nativeHint then self.nativeHint=label(self,"Native party frames; size in Edit Mode",12,0,250);self.nativeHint:ClearAllPoints();self.nativeHint:SetPoint("BOTTOMLEFT",self,"BOTTOMLEFT",12,15) end
        if self.interactive then self.nativeHint:SetWidth(math.max(1,self:GetWidth()-24));self.nativeHint:Show() else self.nativeHint:Hide() end
    end
    function frame:ContentHeight(panelWidth)
        -- Separate measuring strings leave visible content untouched if allocation fails.
        if not self.measureTitle then
            self.measureTitle=label(self,"",0,0,1);self.measureTitle:Hide()
            self.measureBody=label(self,"",0,0,1);self.measureBody:Hide()
            self.measureTitle:SetWordWrap(true);self.measureBody:SetWordWrap(true)
            if self.measureBody.SetNonSpaceWrap then self.measureBody:SetNonSpaceWrap(true) end
        end
        local width=math.max(1,panelWidth-24)
        self.measureTitle:SetFont(self.title:GetFont());self.measureBody:SetFont(self.body:GetFont())
        self.measureTitle:SetText(self.title:GetText());self.measureBody:SetText(self.body:GetText())
        self.measureTitle:SetWidth(math.max(1,width-112));self.measureTitle:SetHeight(0)
        self.measureBody:SetWidth(width);self.measureBody:SetHeight(0)
        return math.ceil(math.max(38,22+self.measureTitle:GetStringHeight())+self.measureBody:GetStringHeight()+8+(self.actions and 70 or 42))
    end
    function frame:ApplyTextSize(size)
        self.textSize=T.Normalize(size)
        -- Override only these font strings, retaining the client's font file.
        -- No shared Blizzard font object or UIParent scale is changed.
        setTextFont(self.body,self.textSize);setTextFont(self.title,self.textSize+2)
        self:LayoutContent()
    end
    function frame:Refresh(groupModel)
        if self.panelID=='dungeon' then
            J.dirty=false
            local ok,text,instanceID=pcall(readDungeon)
            self.journalInstanceID=instanceID
            if not ok then text='Dungeon information is temporarily unavailable.';self.journalInstanceID=nil end
            if text==self.body:GetText() then return end
            self.offset=0;self.body:SetText(text);self:LayoutContent()
            return true
        end
        local provider=textProviders[self.panelID]
        if provider then
            if self.minimized then return end
            local text=self.panelID=='tomtom' and TT.Read() or provider.text
            if not text or text=='' then text='Waiting for data from the provider.' end
            if self.providerText==text then return end
            self.providerText=text
            self.title:SetText(panel.title);self.body:SetText(text);self:LayoutContent()
            return true
        end
        if self.panelID=="party" or self.panelID=="raid" then
            local model=groupModel or G.Read()
            self.groupModel=model
            local signature=model.signatures and model.signatures[self.panelID]
            if self.watchSignature~=signature then self.offset=0 end
            self.watchSignature=signature
            self.title:SetText(self.interactive and "Party - native" or ((self.panelID=='party' and 'Party' or 'Raid').." - "..#model[self.panelID].." members"))
            self.body:SetText(G.Text(model,self.panelID));self:LayoutContent()
            return
        end
        if self.panelID~="quests" then return end
        local model=Q.Read()
        if self.watchSignature~=model.signature then self.offset=0 end
        self.watchSignature=model.signature
        self.title:SetText("Quests - "..#model.items.." tracked")
        self.body:SetText(Q.Text(model))
        Q.lastStatus,Q.lastCount,Q.lastError=model.status,#model.items,model.error
        self:LayoutContent()
    end
    frame:EnableMouseWheel(true);frame.scroll:EnableMouseWheel(true)
    local wheel=function(_,delta) frame:ScrollBy(-delta*36) end
    frame:SetScript("OnMouseWheel",wheel);frame.scroll:SetScript("OnMouseWheel",wheel)
    local up=button(frame,"Up",12,0,44,function() frame:ScrollBy(-72) end)
    local down=button(frame,"Down",60,0,48,function() frame:ScrollBy(72) end)
    up:ClearAllPoints();up:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",12,10)
    down:ClearAllPoints();down:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",60,10)
    frame.up,frame.down=up,down
    if panel.id=='party' or panel.id=='raid' then
        frame.actions={}
        for index,entry in ipairs({{'Invite','invite'},{'Start raid','raid'},{'Ready','ready'}})do
            local action=entry[2]
            local b=button(frame,entry[1],12+(index-1)*80,0,76,function()
                if action=='invite' then local ok,message=FW.GroupActions.State(action);if ok then openInvite()else say(message)end
                else local _,message=FW.GroupActions.Run(action);say(message)end
            end)
            b.action=action;frame.actions[#frame.actions+1]=b
            b:SetScript('OnEnter',function(self)
                if not GameTooltip then return end
                local allowed,message=FW.GroupActions.State(action)
                GameTooltip:SetOwner(self,'ANCHOR_TOP');GameTooltip:SetText(self:GetText())
                GameTooltip:AddLine(allowed and ({invite='Enter Character-Realm in the invite window.',raid='Convert your existing party into a raid.',ready='Start a group ready check.'})[action] or message,1,1,1,true);GameTooltip:Show()
            end)
            b:SetScript('OnLeave',function()if GameTooltip then GameTooltip:Hide()end end)
        end
    end
    if panel.id=='minimap' then frame:SetFrameStrata('BACKGROUND') end
    if panel.id=='dungeon' and J.IsRetail()
        and (ToggleEncounterJournal or EncounterJournal_LoadUI or (C_AddOns and C_AddOns.LoadAddOn)) then
        frame.actions={button(frame,'Open full guide',12,0,120,function()
            if zoning or loadingScreen or zoneResumeAt then return end
            if J.dirty and not inCombat() and frame:Refresh() then reflowPanels() end
            openDungeonGuide(frame.journalInstanceID)
        end)}
    end
    return frame
end
local function saveTextSize(panelID,size)
    size=T.Normalize(size);textSizes[panelID]=size
    if type(ForeverWorkspaceDB.panelFonts)~="table" then ForeverWorkspaceDB.panelFonts={} end
    ForeverWorkspaceDB.panelFonts[panelID]=size
    local frame=sampleFrames[panelID]
    if frame then frame:ApplyTextSize(size) end
    if active and reflowPanels then reflowPanels() end
end
local function refreshQuests()
    if sampleFrames.quests then sampleFrames.quests:Refresh() end
    if active and reflowPanels then reflowPanels() end
end
local function readGroups()
    local model=G.Read()
    G.lastModel=model
    G.lastStatus,G.lastCount,G.lastError=model.status,#model.raid>0 and #model.raid or #model.party,model.error
    return model
end
local function refreshGroups()
    local model=readGroups()
    for _,id in ipairs({"party","raid"}) do if sampleFrames[id] then sampleFrames[id]:Refresh(model) end end
    if active and reflowPanels then reflowPanels() end
end
local function pointsOf(frame)
    local result = {}
    for i = 1, frame:GetNumPoints() do result[i] = {frame:GetPoint(i)} end
    return result
end
local function restoreWorld()
    if not originalPoints then return true end
    if inCombat() and WorldFrame.IsProtected and WorldFrame:IsProtected() then
        pendingRestore = true; say("Viewport restoration is pending until combat ends."); return false
    end
    local ok, err = pcall(function()
        WorldFrame:ClearAllPoints()
        if #originalPoints == 0 then WorldFrame:SetAllPoints(UIParent) end
        for _, p in ipairs(originalPoints) do WorldFrame:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
    end)
    if not ok then
        pcall(function() WorldFrame:ClearAllPoints(); WorldFrame:SetAllPoints(UIParent) end)
        say("Original anchors could not be restored; attempted full-window fallback: " .. tostring(err))
    end
    originalPoints = nil
    return ok
end
local function reset(reason)
    active, deadline = false, nil
    zoning,zoneResumeAt,appliedPixelRatio=nil,nil,nil
    alignmentActive,alignmentDeadline=nil,nil
    if alignmentFrame then alignmentFrame:Hide() end
    if alignmentBox then alignmentBox:Hide() end
    if alignmentRequested then
        alignmentRequested=nil
        local restored,message=FW.Video.Restore(ForeverWorkspaceDB)
        pendingAlignmentRestore=not restored
        alignmentRestoreAttempts=0;alignmentRestoreAt=GetTime()+1
        if not restored then say(message.." Use Restore game size outside combat.") end
    end
    appliedPanels=nil
    appliedDocks=nil;pendingMinimize={}
    if controls and controls.inviteBox then controls.inviteBox:Hide()end
    lockedPartyLayouts=nil
    for _, f in pairs(sampleFrames) do f:Hide() end
    if FW.outline then FW.outline:Hide() end
    restoreWorld()
    local hudRestored,hudMessage=FW.HUD.Restore(ForeverWorkspaceDB)
    pendingHudRestore=not hudRestored
    if not hudRestored then say(hudMessage) end
    local windowsRestored,windowMessage=FW.NativeWindows.Restore()
    pendingWindowRestore=not windowsRestored
    if not windowsRestored then say(windowMessage) end
    local bagsRestored,bagMessage=FW.Bags.Restore();pendingBagRestore=not bagsRestored
    if not bagsRestored then say(bagMessage) end
    if controls then
        controls:ClearAllPoints(); controls:SetPoint("TOP", UIParent, "TOP", 0, -40)
        controls.status:SetText((reason or "Viewport restored. Restore game size reverses requested sizing; manual desktop moves must be restored manually.")..(not hudRestored and " "..hudMessage or ""))
    end
end
FW.Reset = reset

local function centerHud()
    if not active then say("Apply and Keep the viewport trial before centering the HUD.");return end
    local canvas,canvasError=canvasInfo()
    if not canvas then say(canvasError);return end
    local valid,err=L.ValidateGeometry(FW.Geometry,canvas.width,canvas.height)
    if not valid then say(err);return end
    local ok,message=FW.HUD.Center(FW.Geometry,canvas.pixelsPerUnit,ForeverWorkspaceDB)
    if ok and lockedPartyLayouts then
        for _,region in pairs(lockedPartyLayouts) do
            for _,a in ipairs(region) do
                if a.panel.interactive and not a.panel.minimized then
                    local docked,dockMessage=FW.HUD.DockParty(FW.Geometry,canvas.pixelsPerUnit,
                        {x=a.x*canvas.pixelsPerUnit,y=a.y*canvas.pixelsPerUnit,width=a.width*canvas.pixelsPerUnit,height=a.height*canvas.pixelsPerUnit},ForeverWorkspaceDB,a.panel)
                    message=message.." "..dockMessage
                elseif a.panel.id=='minimap' and not a.panel.minimized then
                    local _,dockMessage=FW.HUD.DockMinimap(FW.Geometry,canvas.pixelsPerUnit,{x=a.x*canvas.pixelsPerUnit,y=a.y*canvas.pixelsPerUnit,width=a.width*canvas.pixelsPerUnit,height=a.height*canvas.pixelsPerUnit},ForeverWorkspaceDB)
                    message=message..' '..tostring(dockMessage)
                end
            end
        end
    end
    FW.HUD.RefreshVisibility()
    local windowsOK,windowMessage=FW.NativeWindows.Center(FW.Geometry,canvas.pixelsPerUnit)
    local bagsOK,bagMessage=FW.Bags.Center(FW.Geometry,FW.Bags.Options(ForeverWorkspaceDB.bags))
    message=message.." Windows: "..windowMessage.." Bags: "..bagMessage
    ForeverWorkspaceDB.lastHudStatus=message
    controls.status:SetText(message);say(message)
    if not ok then say("You can still use the viewport. The HUD requires a supported Edit Mode layout.") end
end
local function restoreHud()
    local ok,message=FW.HUD.Restore(ForeverWorkspaceDB)
    pendingHudRestore=not ok
    if ok and lockedPartyLayouts then
        lockedPartyLayouts=nil
        for _,list in ipairs({preferences,appliedPanels or {},ForeverWorkspaceDB.panels or {}}) do
            for _,p in ipairs(list) do if p.id=="party" then p.interactive=false end end
        end
        if sampleFrames.party then sampleFrames.party:SetInteractive(false);sampleFrames.party:Refresh(readGroups()) end
        for _,list in ipairs({preferences,appliedPanels or {},ForeverWorkspaceDB.panels or {}})do for _,p in ipairs(list)do if p.id=='minimap' then p.enabled=false end end end
        if sampleFrames.minimap then sampleFrames.minimap:Hide()end
        if controls and controls.RefreshPanelSelection then controls.RefreshPanelSelection() end
        if active and reflowPanels then reflowPanels() end
    end
    local windowsOK,windowMessage=FW.NativeWindows.Restore()
    pendingWindowRestore=not windowsOK
    local bagsOK,bagMessage=FW.Bags.Restore();pendingBagRestore=not bagsOK
    message=message.." Windows: "..windowMessage.." Bags: "..bagMessage
    ForeverWorkspaceDB.lastHudStatus=message
    controls.status:SetText(message);say(message)
end
local function videoAction(restore)
    if inCombat() then say("Change the game size outside combat.");return end
    reset("Viewport reset before changing the game size.")
    local ok,message
    if restore then ok,message=FW.Video.Restore(ForeverWorkspaceDB)
    else ok,message=FW.Video.Sync(FW.Geometry,ForeverWorkspaceDB) end
    ForeverWorkspaceDB.lastVideoStatus=message
    if restore and ok then pendingAlignmentRestore=nil end
    controls.status:SetText(message);say(message)
    if not ok then say("No viewport trial was started. /fws diag includes the engine size.") end
end

local function panelLayouts(config,ratioX,ratioY,locked,docks)
    local layouts,available={},{}
    docks=docks or dockPreferences
    for _,region in ipairs(FW.Geometry.regions)do available[region.id]=true end
    for _,p in ipairs(config)do if p.enabled~=false and not available[p.region] then return nil,p.title..' needs an imported '..p.region..' region. Move or remove it in panel settings.' end end
    for _,region in ipairs(FW.Geometry.regions) do
        local panels={}
        for _,p in ipairs(config)do if p.enabled~=false and p.region==region.id then panels[#panels+1]=p end end
        local lockedRegion=locked and locked[region.id]
        if lockedRegion then for _,a in ipairs(lockedRegion)do layouts[#layouts+1]=a end
        else
            local uiRegion={x=region.x/ratioX,y=region.y/ratioY,width=region.width/ratioX,height=region.height/ratioY}
            local allocation,err=D.Layout(uiRegion,panels,docks[region.id],function(p,panelWidth)
                local candidate=clone(p)
                if p.minimized then local height=math.max(42,T.Normalize(textSizes[p.id])+24);candidate.min=height;candidate.preferred=height;candidate.max=height;candidate.fixed=true;candidate.fill=false;candidate.fit=false
                elseif p.interactive or p.id=='minimap' then
                    local metrics,message
                    if p.id=='minimap' then metrics,message=FW.HUD.MinimapMetrics(FW.Geometry,ratioX)
                    else metrics,message=FW.HUD.PartyMetrics(FW.Geometry,ratioX,p) end
                    if not metrics then return nil,message end
                    local padding=p.id=='minimap' and 0 or 24
                    if metrics.width>(panelWidth-padding)*ratioX then return nil,'Native '..p.title..' is too wide. Widen the dock/strip, use fewer columns or resize it in Edit Mode.' end
                    if p.max<metrics.slotHeight then return nil,'Increase '..p.title..' Max height to at least '..metrics.slotHeight..'.' end
                    candidate.min=math.max(p.min,metrics.slotHeight);candidate.preferred=math.max(candidate.min,p.preferred);candidate.fill=false;candidate.fit=false
                elseif p.fit then
                    local frame=sampleFrames[p.id];local desired=frame and frame:ContentHeight(panelWidth) or p.preferred
                    candidate.preferred=math.max(p.min,math.min(p.max,desired));candidate.fill=false
                end
                return candidate
            end)
            if not allocation then return nil,region.id..': '..err end
            for _,a in ipairs(allocation)do layouts[#layouts+1]=a end
        end
    end
    return layouts
end
reflowPanels=function()
    if not active or not appliedPanels then return end
    local hasFit=false
    for _,p in ipairs(appliedPanels) do if p.fit then hasFit=true;break end end
    if not hasFit then return end
    local canvas=canvasInfo()
    if not canvas or not L.ValidateGeometry(FW.Geometry,canvas.width,canvas.height) then return end
    local layouts,err=panelLayouts(appliedPanels,canvas.width/UIParent:GetWidth(),canvas.height/UIParent:GetHeight(),lockedPartyLayouts,appliedDocks)
    if not layouts then controls.status:SetText(err);return end
    for _,a in ipairs(layouts) do
        local frame=sampleFrames[a.panel.id]
        if frame then
            frame:ClearAllPoints();frame:SetPoint("TOPLEFT",UIParent,"TOPLEFT",a.x,-a.y)
            frame:SetSize(a.width,a.height);frame:LayoutContent()
        end
    end
end
local function prepare()
    if zoning or loadingScreen then return nil,"Wait until the loading screen finishes before applying." end
    if inCombat() then return nil, "Apply the test outside combat." end
    local modeOK,modeError=FW.Video.CheckMode()
    if not modeOK then return nil,modeError end
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Offhand") then
        return nil, "Disable Offhand before testing this viewport controller."
    end
    if not WorldFrame or not WorldFrame.ClearAllPoints then return nil, "WorldFrame is unavailable." end
    local canvas,canvasError=canvasInfo()
    if not canvas then return nil,canvasError end
    local width,height=canvas.width,canvas.height
    local valid, err = L.ValidateGeometry(FW.Geometry, width, height)
    if not valid then return nil, err end
    local engine=FW.Video.Size()
    if ForeverWorkspaceDB.configuration and engine and (math.abs(engine.width-FW.Geometry.width)>2 or math.abs(engine.height-FW.Geometry.height)>2) then
        return nil,string.format("WoW's size API reports %.0f x %.0f; configuration needs %d x %d. Use /fws align to request/check size. If the engine caps the span, cancel and resize manually or choose a smaller layout.",engine.width,engine.height,FW.Geometry.width,FW.Geometry.height)
    end
    local ratioX, ratioY = width / UIParent:GetWidth(), height / UIParent:GetHeight()
    if math.abs(ratioX - ratioY) > 0.02 then return nil, "Nonuniform UI coordinates; calibration is required." end
    local layouts,allocationError=panelLayouts(preferences,ratioX,ratioY)
    if not layouts then return nil,allocationError end
    return {layouts=layouts, width=width, height=height, ratioX=ratioX, ratioY=ratioY}
end
local function sampleFrame(panel)
    local frame = sampleFrames[panel.id]
    if frame then return frame end
    frame=contentPanel(panel)
    sampleFrames[panel.id] = frame
    return frame
end
local function placeWorld(g,height)
    local worldScale=L.PixelsPerUnit(WorldFrame:GetEffectiveScale(),height)
    if not worldScale then error("Invalid WorldFrame scale") end
    WorldFrame:ClearAllPoints()
    WorldFrame:SetPoint("TOPLEFT",UIParent,"TOPLEFT",g.main.x/worldScale,-g.main.y/worldScale)
    WorldFrame:SetPoint("BOTTOMRIGHT",UIParent,"BOTTOMRIGHT",
        -(g.width-g.main.x-g.main.width)/worldScale,(g.height-g.main.y-g.main.height)/worldScale)
end
local function resumeAfterZone()
    if not zoneResumeAt or zoning or GetTime()<zoneResumeAt or inCombat() then return end
    zoneResumeAt=nil
    if not active or deadline or not appliedPanels then return end
    local canvas,err=canvasInfo()
    local valid
    if canvas then valid,err=L.ValidateGeometry(FW.Geometry,canvas.width,canvas.height) end
    if not valid or not appliedPixelRatio or math.abs(canvas.pixelsPerUnit-appliedPixelRatio)>0.02 then
        reset("Display geometry or UI scale changed during loading; recalibrate before applying. "..(err or ""))
        return
    end
    -- Keep the selected native Edit Mode layout and its party settings intact.
    -- Reassert only the viewport; never apply staged panel settings on zoning.
    local ok,message=pcall(function()
        placeWorld(FW.Geometry,canvas.height)
        reflowPanels()
        if FW.NativeWindows.enabled then FW.NativeWindows.Refresh() end
        if FW.Bags.enabled then FW.Bags.Refresh() end
    end)
    if not ok then reset("Workspace could not resume after loading.");say(tostring(message));return end
    controls.status:SetText("Workspace kept through zoning. /fws reset restores the viewport.")
end
local function apply(quietTrial)
    local prepared, err = prepare()
    if not prepared then say(err); controls.status:SetText(err); return end
    local g = FW.Geometry
    if not originalPoints then originalPoints = pointsOf(WorldFrame) end
    local ok, applyError = pcall(function()
        local interactive,minimap,partyPanel,mapPanel
        for _,a in ipairs(prepared.layouts) do
            if a.panel.id=='party' then partyPanel=a.panel;if a.panel.interactive and not a.panel.minimized then interactive=a end end
            if a.panel.id=='minimap' then mapPanel=a.panel;if not a.panel.minimized then minimap=a end end
        end
        for _,entry in ipairs({{'PartyFrame',partyPanel and partyPanel.interactive and partyPanel.minimized==true},{'MinimapCluster',mapPanel and mapPanel.minimized==true}})do
            local restored,message=FW.HUD.NativeHidden(entry[1],entry[2]==true);if not restored then error(message)end
        end
        if interactive or minimap then local centered,message=FW.HUD.Center(g,prepared.ratioX,ForeverWorkspaceDB);if not centered then error(message)end end
        if interactive then
            local docked,dockMessage=FW.HUD.DockParty(g,prepared.ratioX,
                {x=interactive.x*prepared.ratioX,y=interactive.y*prepared.ratioY,width=interactive.width*prepared.ratioX,height=interactive.height*prepared.ratioY},ForeverWorkspaceDB,interactive.panel)
            if not docked then error(dockMessage) end
        else
            local restored,message=FW.HUD.UndockParty(ForeverWorkspaceDB)
            if not restored then error(message) end
        end
        if minimap then
            local docked,message=FW.HUD.DockMinimap(g,prepared.ratioX,{x=minimap.x*prepared.ratioX,y=minimap.y*prepared.ratioY,width=minimap.width*prepared.ratioX,height=minimap.height*prepared.ratioY},ForeverWorkspaceDB)
            if not docked then error(message)end
        else local restored,message=FW.HUD.UndockMinimap(ForeverWorkspaceDB);if not restored then error(message)end end
        -- Convert physical pixels to this frame's normalized screen units.
        placeWorld(g,prepared.height)
        for _, f in pairs(sampleFrames) do f:Hide() end
        questsDirty=false;questRefreshAt=0
        groupsDirty=false;groupRefreshAt=0
        local groupModel=readGroups()
        for _, a in ipairs(prepared.layouts) do
            local f = sampleFrame(a.panel)
            f:ClearAllPoints(); f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", a.x, -a.y)
            f:SetSize(a.width, a.height)
            f:SetMinimized(a.panel.minimized)
            if a.panel.id=="party" then f:SetInteractive(a.panel.interactive) end
            f:ApplyTextSize(textSizes[a.panel.id])
            f:Refresh(groupModel)
            f:Show()
        end
        FW.HUD.RefreshVisibility()
        if not FW.outline then
            FW.outline = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
            FW.outline:EnableMouse(false); FW.outline:SetFrameStrata("HIGH")
            FW.outline:SetBackdrop({edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=2})
            FW.outline:SetBackdropBorderColor(0.3,0.8,0.6,0.8)
        end
        FW.outline:ClearAllPoints(); FW.outline:SetPoint("TOPLEFT",UIParent,"TOPLEFT",g.main.x/prepared.ratioX,-g.main.y/prepared.ratioY)
        FW.outline:SetSize(g.main.width/prepared.ratioX,g.main.height/prepared.ratioY); FW.outline:Show()
        controls:ClearAllPoints(); controls:SetPoint("TOPLEFT",UIParent,"TOPLEFT",g.main.x/prepared.ratioX+24,-g.main.y/prepared.ratioY-24)
    end)
    if not ok then reset("Apply failed; viewport restored."); say(applyError); return end
    active, deadline = true, GetTime()+20
    alignmentDeadline=nil
    zoning,zoneResumeAt=nil,nil
    appliedPixelRatio=prepared.ratioX
    appliedPanels=clone(preferences)
    appliedDocks=clone(dockPreferences)
    lockedPartyLayouts=nil
    for _,a in ipairs(prepared.layouts) do
        if not a.panel.minimized and (a.panel.interactive or a.panel.id=='minimap') then
            lockedPartyLayouts=lockedPartyLayouts or {}
            local region=a.panel.region
            lockedPartyLayouts[region]={}
            for _,entry in ipairs(prepared.layouts) do if entry.panel.region==region then lockedPartyLayouts[region][#lockedPartyLayouts[region]+1]=clone(entry) end end
        end
    end
    reflowPanels()
    if FW.NativeWindows.enabled then FW.NativeWindows.Center(FW.Geometry,prepared.ratioX) end
    if FW.Bags.enabled then FW.Bags.Center(FW.Geometry,FW.Bags.Options(ForeverWorkspaceDB.bags)) end
    controls.status:SetText("Trial applied. Click Keep within 20 seconds, or the viewport resets.")
    if quietTrial~=true then say("20-second viewport trial started. Green border marks the requested 3D area.") end
end
local function keep()
    if not active then return end
    deadline = nil
    local kept=clone(appliedPanels);local present={}
    for _,p in ipairs(kept) do present[p.id]=true end
    -- Keeping a layout while an optional addon is absent must not erase its
    -- placement preferences. Fonts are already persisted separately by ID.
    for _,p in ipairs(type(ForeverWorkspaceDB.panels)=='table' and ForeverWorkspaceDB.panels or {}) do
        if type(p)=='table' and providerID(p.id) and not present[p.id] then
            kept[#kept+1]=clone(p);present[p.id]=true
        end
    end
    ForeverWorkspaceDB.panels=kept
    ForeverWorkspaceDB.docks=clone(appliedDocks)
    ForeverWorkspaceDB.lastKeptBuild = {GetBuildInfo()}
    ForeverWorkspaceDB.lastWorkingGeometry=clone(FW.Geometry)
    ForeverWorkspaceDB.lastWorkingConfiguration=ForeverWorkspaceDB.configuration and clone(ForeverWorkspaceDB.configuration) or nil
    ForeverWorkspaceDB.geometryMigrationNotice=nil
    alignmentActive,alignmentDeadline,alignmentRequested=nil,nil,nil
    if alignmentFrame then alignmentFrame:Hide() end
    if alignmentBox then alignmentBox:Hide() end
    controls.status:SetText("Kept through zoning for this session. /fws reset restores the viewport. Reload/login starts disabled.")
end
local function sameSavedGeometry(current,saved)
    if type(current)~='table' or type(saved)~='table' then return false end
    local function sameRect(a,b)
        return type(a)=='table' and type(b)=='table' and a.x==b.x and a.y==b.y and a.width==b.width and a.height==b.height
    end
    if not sameRect(current,saved) or current.respectWorkArea~=saved.respectWorkArea or not sameRect(current.main,saved.main)
        or type(saved.regions)~='table' or type(current.regions)~='table' or #current.regions~=#saved.regions then return false end
    for i,region in ipairs(current.regions) do
        local other=saved.regions[i]
        if not sameRect(region,other) or region.id~=other.id then return false end
    end
    return true
end
local function useSavedLayout()
    local db=ForeverWorkspaceDB
    if deadline then controls.status:SetText('Keep or reset the current trial first.');return end
    if type(db.panels)~='table' or not sameSavedGeometry(FW.Geometry,db.lastWorkingGeometry) then
        controls.status:SetText('This geometry has not been kept yet. Use Apply trial and Keep once.');return
    end
    -- An explicit user action applies only the last confirmed preferences.
    -- Keep any unrelated edits staged in the settings window.
    local stagedPanels,stagedDocks=preferences,dockPreferences
    local savedDocks=type(db.docks)=='table' and db.docks or {}
    preferences=D.LoadPanels(db.panels,defaults)
    dockPreferences={left=D.Options(savedDocks.left),right=D.Options(savedDocks.right)}
    apply(true)
    if active and deadline then keep() end
    preferences,dockPreferences=stagedPanels,stagedDocks
    controls.RefreshPanelSelection()
end
toggleMinimized=function(id,desired)
    if not active or not appliedPanels then return end
    if deadline then say('Keep the current trial before using panel minimize buttons.');return end
    local candidate=clone(appliedPanels);local changed
    for _,p in ipairs(candidate)do if p.id==id then
        if desired==nil then local current=p.minimized==true;if pendingMinimize[id]~=nil then current=pendingMinimize[id]end;desired=not current end
        p.minimized=desired==true;changed=p;break
    end end
    if not changed then return end
    if inCombat() then pendingMinimize[id]=changed.minimized;say('Panel minimize/restore queued until combat ends.');return end
    local staged,stagedDocks=preferences,dockPreferences
    preferences=candidate;dockPreferences=clone(appliedDocks)
    apply()
    local success=active and deadline~=nil
    if success then keep();for _,p in ipairs(staged)do if p.id==id then p.minimized=changed.minimized end end end
    preferences,dockPreferences=staged,stagedDocks
    if controls.RefreshPanelSelection then controls.RefreshPanelSelection()end
end
local function configurationIdle()
    if inCombat() then return nil,"Import and restore configuration outside combat." end
    if active or originalPoints or alignmentActive then return nil,"Cancel alignment / Reset viewport before changing monitor configuration." end
    if pendingRestore or pendingHudRestore or pendingWindowRestore or pendingBagRestore or pendingAlignmentRestore then
        return nil,"Finish pending restoration outside combat before changing configuration."
    end
    return true
end
local function updateGeometryLabel()
    if controls.geometryLabel then controls.geometryLabel:SetText(geometrySummary()) end
end
openConfigOptions=function()
    if not configControls then
        configControls=CreateFrame("Frame","ForeverWorkspaceConfigControls",controls.settingsHost)
        configControls:SetAllPoints(controls.settingsHost);configControls:EnableMouse(true)
        setTextFont(label(configControls,"Monitor configuration",16,-14,568),16)
        label(configControls,"Windows: use Start Peripheral in the helper. HTML setup: paste your configuration below. Saving never activates.",16,-42,568)
        local scroll=CreateFrame("ScrollFrame",nil,configControls,"UIPanelScrollFrameTemplate")
        scroll:SetSize(540,146);scroll:SetPoint("TOPLEFT",configControls,"TOPLEFT",16,-80)
        local edit=CreateFrame("EditBox",nil,scroll)
        edit:SetMultiLine(true);edit:SetFontObject(ChatFontNormal);edit:SetAutoFocus(false);edit:SetWidth(532);edit:SetHeight(146)
        if edit.SetMaxLetters then edit:SetMaxLetters(FW.Config.maxBytes) end
        edit:SetScript("OnEscapePressed",function(self) if self.ClearFocus then self:ClearFocus() end end)
        edit:SetScript("OnTextChanged",function(self)
            local height=self.GetTextHeight and self:GetTextHeight() or (self.GetNumLines and self:GetNumLines()*16) or 146
            self:SetHeight(math.max(146,math.min(32768,height+20)))
        end)
        scroll:SetScrollChild(edit);configControls.edit=edit
        configControls.status=label(configControls,"",16,-280,568);configControls.status:SetHeight(66);configControls.status:SetJustifyV("TOP")
        setTextFont(label(configControls,"About Peripheral",16,-348,568),14)
        local about=label(configControls,"An optional window management program on Peripheral's GitHub project page simplifies setup on Windows.",16,-370,568)
        about:SetWordWrap(true)
        button(configControls,"Import / save only",16,-240,174,function()
            local idle,err=configurationIdle();if not idle then configControls.status:SetText(err);return end
            local config,g=FW.Config.Parse(edit:GetText())
            if not config then configControls.status:SetText("Rejected: "..tostring(g).." Previous configuration retained.");return end
            local old=FW.Geometry and clone(FW.Geometry)
            local saved,message=FW.Config.Save(ForeverWorkspaceDB,config)
            if not saved then configControls.status:SetText(message);return end
            ForeverWorkspaceDB.previousGeometry=old;FW.Geometry=saved;updateGeometryLabel()
            edit:SetText(FW.Config.Encode(config))
            configControls.status:SetText("Saved to SavedVariables; viewport remains disabled. Next: Align / size, then Apply trial and Keep. WoW cannot detect removed physical monitors; verify the guides after display changes.")
        end)
        button(configControls,"Previous / working",198,-240,186,function()
            local idle,err=configurationIdle();if not idle then configControls.status:SetText(err);return end
            local db=ForeverWorkspaceDB
            local candidate=db.lastWorkingConfiguration
            if candidate and db.configuration and FW.Config.Encode(candidate)==FW.Config.Encode(db.configuration) then candidate=db.previousConfiguration end
            local config,g
            if candidate then config,g=FW.Config.Validate(candidate) end
            if config then db.configuration=config;FW.Geometry=g;edit:SetText(FW.Config.Encode(config))
            else
                local legacy=FW.Config.Legacy(db.lastWorkingGeometry or db.previousGeometry or db.legacyGeometry)
                if not legacy then configControls.status:SetText("No previous working configuration is available.");return end
                db.configuration=nil;db.legacyGeometry=legacy;FW.Geometry=legacy;edit:SetText("")
            end
            db.configurationError=nil;updateGeometryLabel();configControls.status:SetText("Previous geometry restored; viewport remains disabled.")
        end)
        button(configControls,"Align / size",396,-240,188,function() beginAlignment() end)
        edit:SetText(ForeverWorkspaceDB.configuration and FW.Config.Encode(ForeverWorkspaceDB.configuration) or "")
        configControls.status:SetText(ForeverWorkspaceDB.helperBridgeError or ForeverWorkspaceDB.configurationError or ForeverWorkspaceDB.geometryMigrationNotice or (FW.Geometry and "Geometry is saved. Helper handoffs load on restart/reload. An unchanged layout can be applied with Use saved layout." or "Use Start Peripheral in the Windows helper, or open Configurator.html and paste its JSON here."))
    end
    controls.configView=true;controls.bagView=false;controls.dockView=nil;controls.RefreshPanelSelection();controls:Show()
end
drawAlignment=function()
    if not alignmentActive then return end
    local g=FW.Geometry;local canvas=canvasInfo()
    if not g or not canvas then return end
    local sx,sy=UIParent:GetWidth()/g.width,UIParent:GetHeight()/g.height
    local matched=FW.Layout.ValidateGeometry(g,canvas.width,canvas.height)
    local engine=FW.Video.Size()
    if engine and (math.abs(engine.width-g.width)>2 or math.abs(engine.height-g.height)>2) then matched=false end
    local edges={
        {g.main.x,g.main.y,3,g.main.height},
        {g.main.x+g.main.width-3,g.main.y,3,g.main.height},
        {g.main.x,g.main.y,g.main.width,3},
        {g.main.x,g.main.y+g.main.height-3,g.main.width,3},
    }
    for index,r in ipairs(edges) do
        local guide=alignmentFrame.edges[index]
        guide:ClearAllPoints();guide:SetPoint("TOPLEFT",UIParent,"TOPLEFT",r[1]*sx,-r[2]*sy);guide:SetSize(math.max(1,r[3]*sx),math.max(1,r[4]*sy))
        guide:SetBackdropColor(matched and 0.2 or 1,matched and 0.9 or 0.6,0.3,1)
    end
    alignmentFrame.heading:ClearAllPoints();alignmentFrame.heading:SetPoint("TOPLEFT",UIParent,"TOPLEFT",g.main.x*sx+12,-g.main.y*sy-12)
    alignmentFrame.heading:SetText("MAIN GAME REGION - target "..g.main.width.." x "..g.main.height)
    for index,side in ipairs({'left','right'}) do
        local text=alignmentFrame.sides[index];text:Hide()
        for _,region in ipairs(g.regions) do if region.id==side then
            text:ClearAllPoints();text:SetPoint("TOPLEFT",UIParent,"TOPLEFT",region.x*sx+12,-region.y*sy-12)
            text:SetWidth(math.max(80,region.width*sx-24));text:SetText(side:upper().." - UI ONLY");text:Show()
        end end
    end
    local target=g.x and string.format("Target client origin (%d,%d). ",g.x,g.y) or "Legacy desktop origin unknown. "
    local engineText=engine and string.format(" Engine API: %.0f x %.0f.",engine.width,engine.height) or " Engine size API unavailable."
    alignmentBox.status:SetText(string.format("Canvas: %.0f x %.0f.%s Target: %d x %d. %s%s\nMove manually: green edges must match Main's left, right and top. Desktop position is not measured. Borders/title bar are outside the client area.",canvas.width,canvas.height,engineText,g.width,g.height,matched and "Size matches. " or "AMBER: SIZE/PREVIEW NOT CONFIRMED. ",target))
end
beginAlignment=function()
    if active then say("Reset the viewport before starting manual alignment.");return end
    if inCombat() then say("Start alignment outside combat.");return end
    local valid,err=L.ValidateGeometry(FW.Geometry,FW.Geometry and FW.Geometry.width,FW.Geometry and FW.Geometry.height)
    if not valid then say(err);openConfigOptions();return end
    local mode,message=FW.Video.CheckMode();if not mode then say(message);return end
    if not alignmentFrame then
        alignmentFrame=CreateFrame("Frame",nil,UIParent);alignmentFrame:SetAllPoints(UIParent);alignmentFrame:SetFrameStrata("HIGH");alignmentFrame:EnableMouse(false)
        alignmentFrame.edges={}
        for index=1,4 do
            local edge=CreateFrame("Frame",nil,alignmentFrame,"BackdropTemplate");edge:EnableMouse(false)
            edge:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"});alignmentFrame.edges[index]=edge
        end
        alignmentFrame.heading=label(alignmentFrame,"",0,0,560)
        alignmentFrame.sides={label(alignmentFrame,"",0,0,240),label(alignmentFrame,"",0,0,240)}
        alignmentBox=CreateFrame("Frame",nil,UIParent,"BackdropTemplate");alignmentBox:SetSize(620,252);alignmentBox:SetPoint("CENTER")
        alignmentBox:SetFrameStrata("DIALOG");alignmentBox:SetFrameLevel(controls:GetFrameLevel()+30);alignmentBox:EnableMouse(true)
        alignmentBox:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
        alignmentBox:SetBackdropColor(0.04,0.06,0.08,1);alignmentBox:SetBackdropBorderColor(0.3,0.9,0.6,1)
        label(alignmentBox,"Manual alignment - guides do not capture the mouse",16,-12,588)
        alignmentBox.status=label(alignmentBox,"",16,-38,588);alignmentBox.status:SetHeight(100);alignmentBox.status:SetJustifyV("TOP")
        button(alignmentBox,"Request window size",16,-142,174,function()
            local ok,status=FW.Video.Sync(FW.Geometry,ForeverWorkspaceDB)
            if ok then alignmentRequested=true;alignmentDeadline=GetTime()+30 end
            say(status);drawAlignment()
        end)
        button(alignmentBox,"Apply trial",198,-142,114,apply)
        button(alignmentBox,"Keep",320,-142,80,function() if active then keep() else say("Apply a viewport trial before Keep.") end end)
        button(alignmentBox,"Cancel / restore",408,-142,196,function() reset("Alignment cancelled; viewport restored.") end)
        fitCurrentWindow=function()
            if active or inCombat() or pendingAlignmentRestore or alignmentRequested or ForeverWorkspaceDB.video then say("Cancel the size trial / restore game size before fitting a manually resized window.");return end
            local canvas=canvasInfo();local engine=FW.Video.Size()
            if not canvas or (engine and (math.abs(engine.width-canvas.width)>2 or math.abs(engine.height-canvas.height)>2)) then say("Wait for the live canvas and engine dimensions to agree before fitting.");return end
            local config,g=FW.Config.Fit(ForeverWorkspaceDB.configuration,math.floor(canvas.width+0.5),math.floor(canvas.height+0.5))
            if not config then say(g);return end
            local old=clone(FW.Geometry);local saved,message=FW.Config.Save(ForeverWorkspaceDB,config)
            if not saved then say(message);return end
            ForeverWorkspaceDB.previousGeometry=old;FW.Geometry=saved;updateGeometryLabel()
            if configControls then configControls.edit:SetText(FW.Config.Encode(config)) end
            say("Fitted and saved without activation or native resizing. Main width is unchanged; outer padding/strips and bottom height were adjusted. Verify guides, then Apply trial / Keep. Previous / working can restore the prior configuration.")
            drawAlignment()
        end
        button(alignmentBox,"Fit current window",16,-180,174,fitCurrentWindow)
        label(alignmentBox,"Fit saves a nearby achieved size; Main keeps its width. Align the green guides before Apply / Keep.",198,-180,402)
        label(alignmentBox,"Sizing is a 30-second trial. Cancel restores owned size requests, not manual moves. Alt+Space, M: move.",16,-226,588)
    end
    alignmentActive=true;alignmentFrame:Show();alignmentBox:Show();controls:Hide();drawAlignment()
end
local function diagnostics()
    if not diagnosticBox then
        diagnosticBox = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        diagnosticBox:SetSize(620,440); diagnosticBox:SetPoint("CENTER"); diagnosticBox:SetFrameStrata("DIALOG")
        diagnosticBox:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"}); diagnosticBox:SetBackdropColor(0.06,0.07,0.09,1)
        local edit = CreateFrame("EditBox", nil, diagnosticBox)
        edit:SetMultiLine(true); edit:SetFontObject(ChatFontNormal); edit:SetAutoFocus(false)
        edit:SetPoint("TOPLEFT",16,-16); edit:SetPoint("BOTTOMRIGHT",-16,48)
        edit:SetScript("OnEscapePressed",function() diagnosticBox:Hide() end)
        diagnosticBox.edit = edit
        button(diagnosticBox,"Close",16,-402,100,function() diagnosticBox:Hide() end)
    end
    local canvas,canvasError=canvasInfo()
    local width,height=canvas and canvas.width,canvas and canvas.height
    local physicalWidth,physicalHeight
    if GetPhysicalScreenSize then physicalWidth,physicalHeight=GetPhysicalScreenSize() end
    local version,build,date,interface = GetBuildInfo()
    local g=FW.Geometry
    local text=string.format("Peripheral %s\nClient: %s build %s / interface %s\nDate: %s\nCanvas: %s x %s\nUIParent: %.2f x %.2f scale %.4f\nWorldFrame scale: %.4f\nActive: %s / combat: %s\nExport: %s\nExpected canvas: %s x %s\nMain: %s\nDungeon reference uses the Retail Adventure Guide.",
        VERSION,tostring(version),tostring(build),tostring(interface),tostring(date),tostring(width),tostring(height),
        UIParent:GetWidth(),UIParent:GetHeight(),UIParent:GetEffectiveScale(),WorldFrame:GetEffectiveScale(),
        tostring(active==true),tostring(inCombat()==true),g and tostring(g.generated) or "none",
        g and tostring(g.width) or "none",g and tostring(g.height) or "none",
        g and string.format("%s,%s %sx%s",g.main.x,g.main.y,g.main.width,g.main.height) or "none")
    text=text..string.format("\nPhysical API: %s x %s / pixels per UI unit: %s",tostring(physicalWidth),tostring(physicalHeight),canvas and string.format("%.5f",canvas.pixelsPerUnit) or tostring(canvasError))
    local gameSize=FW.Video.Size()
    text=text.."\nGame size API: "..(gameSize and string.format("%.0f x %.0f",gameSize.width,gameSize.height) or "unavailable")
    text=text.."\nVideo: "..tostring(ForeverWorkspaceDB.lastVideoStatus or "not synced")
    text=text.."\nConfiguration: "..(ForeverWorkspaceDB.configuration and "SavedVariables JSON schema 1" or (g and "SavedVariables legacy migration" or "none"))
    text=text.."\nTaskbar clearance: "..(g and g.respectWorkArea and "enabled" or "off / older export")
    text=text.."\nOptional helper exporter: "..tostring(g and g.helperVersion or "n/a (manual/import)")
    for _,r in ipairs(g and g.regions or {}) do
        text=text..string.format("\n%s region: %s,%s %sx%s",r.id,r.x,r.y,r.width,r.height)
    end
    if GetCVar then
        for _,name in ipairs({"gxWindow","gxMaximize","gxWindowedResolution","gxAspect","RenderScale"}) do
            local ok,value=pcall(GetCVar,name)
            if ok then text=text.."\n"..name..": "..tostring(value) end
        end
    end
    text=text.."\nHUD: "..tostring(ForeverWorkspaceDB.lastHudStatus or "not centered")
    text=text.."\nHUD layout: "..tostring(ForeverWorkspaceDB.hud and ForeverWorkspaceDB.hud.generatedName or "none")
    text=text.."\nQuest provider: "..Q.lastStatus.." / "..Q.lastCount.." tracked"
    if Q.lastError then text=text.."\nQuest error: "..Q.lastError end
    text=text.."\nGroup provider: "..G.lastStatus.." / "..G.lastCount.." members"
    text=text.."\nNative windows: "..FW.NativeWindows.lastStatus
    text=text.."\nBags: "..FW.Bags.lastStatus
    text=text.."\nBag layers: "..tostring(FW.Bags.lastLayerStatus or "not applied")
    text=text.."\nParty mode: "..(lockedPartyLayouts and "interactive native trial (fixed dock)" or "summary")
    text=text.."\nZoning: "..(zoning and "loading" or (zoneResumeAt and "resume pending (waits for combat)" or "ready"))
    if G.lastError then text=text.."\nGroup error: "..G.lastError end
    local sizes={}
    for _,p in ipairs(defaults) do sizes[#sizes+1]=p.id.."="..tostring(textSizes[p.id]) end
    text=text.."\nPanel text (UI px): "..table.concat(sizes,", ")
    ForeverWorkspaceDB.lastDiagnostics=text
    diagnosticBox:SetFrameLevel(controls:GetFrameLevel()+20)
    diagnosticBox.edit:SetText(text); diagnosticBox:Show(); diagnosticBox.edit:SetFocus(); diagnosticBox.edit:HighlightText()
    say("Diagnostics opened; Ctrl+C copies the selected text.")
end

local function createControls()
    controls=CreateFrame("Frame","ForeverWorkspaceControls",UIParent,"BackdropTemplate")
    controls:SetSize(840,702); controls:SetPoint("TOP",UIParent,"TOP",0,-40); controls:SetFrameStrata("DIALOG")
    controls:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    controls:SetBackdropColor(0.06,0.07,0.09,0.98); controls:SetBackdropBorderColor(0.65,0.53,0.29,1)
    controls:EnableMouse(true); controls:SetMovable(true); controls:RegisterForDrag("LeftButton")
    controls:SetScript("OnDragStart",function(self) self:StartMoving() end)
    controls:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
    controls.logo=controls:CreateTexture(nil,"ARTWORK")
    controls.logo:SetTexture("Interface\\AddOns\\"..addonName.."\\Assets\\Peripheral.tga")
    controls.logo:SetSize(32,32);controls.logo:SetPoint("TOPLEFT",controls,"TOPLEFT",16,-8)
    setTextFont(label(controls,"Peripheral v"..VERSION,60,-14,764),16)
    controls.geometryLabel=label(controls,geometrySummary(),16,-40,808)
    controls.status=label(controls,"Disabled. Import monitor configuration, align/size the window, then Apply trial.",16,-64,808)
    controls.status:SetHeight(42); controls.status:SetJustifyV("TOP")
    button(controls,"Use saved layout",16,-112,130,useSavedLayout)
    button(controls,"Apply trial",154,-112,94,apply)
    button(controls,"Keep",256,-112,58,keep)
    button(controls,"Reset viewport",322,-112,115,function() reset(); say("Viewport reset. Restore game size reverses requested sizing; restore manual desktop placement yourself.") end)
    button(controls,"Align / size",445,-112,94,function() beginAlignment() end)
    button(controls,"Import",547,-112,78,function() openConfigOptions() end)
    button(controls,"Diagnostics",633,-112,100,diagnostics)
    button(controls,"Hide",741,-112,83,function() controls:Hide() end)
    controls.panelList=CreateFrame("Frame",nil,controls,"BackdropTemplate")
    controls.panelList:SetSize(196,396);controls.panelList:SetPoint("TOPLEFT",controls,"TOPLEFT",16,-150)
    controls.panelList:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"})
    controls.panelList:SetBackdropColor(0.04,0.05,0.07,1)
    label(controls.panelList,"PANELS",10,-10,176)
    local navigation=CreateFrame('ScrollFrame',nil,controls.panelList,'UIPanelScrollFrameTemplate')
    navigation:SetPoint('TOPLEFT',controls.panelList,'TOPLEFT',8,-28)
    navigation:SetPoint('BOTTOMRIGHT',controls.panelList,'BOTTOMRIGHT',-24,8)
    local navigationContent=CreateFrame('Frame',nil,navigation)
    navigationContent:SetSize(164,360);navigation:SetScrollChild(navigationContent)
    controls.settingsHost=CreateFrame("Frame",nil,controls,"BackdropTemplate")
    controls.settingsHost:SetSize(600,396);controls.settingsHost:SetPoint("TOPLEFT",controls,"TOPLEFT",224,-150)
    controls.settingsHost:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    controls.settingsHost:SetBackdropColor(0.08,0.10,0.13,1);controls.settingsHost:SetBackdropBorderColor(0.25,0.28,0.32,1)
    local panelHost=CreateFrame("Frame",nil,controls.settingsHost)
    panelHost:SetAllPoints(controls.settingsHost);controls.panelSettings=panelHost
    controls.panelButtons={}
    local function navigationRow(id,title,detail,index,action)
        local row=CreateFrame("Button",nil,navigationContent,"BackdropTemplate")
        row:SetSize(164,32);row:SetPoint("TOPLEFT",navigationContent,"TOPLEFT",0,-(index-1)*36)
        row:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
        setTextFont(label(row,title,10,-3,144),12);row.detail=label(row,detail,10,-18,144);setTextFont(row.detail,9)
        row:SetScript("OnClick",action);controls.panelButtons[id]=row
    end
    for index,panel in ipairs(defaults) do
        local id=panel.id
        navigationRow(id,panel.title,panel.region=="left" and "Left dock" or "Right dock",index,function() controls.SelectPanel(id) end)
    end
    navigationRow("bags","Bags","Native inventory",#defaults+1,openBagOptions)
    navigationRow('dockleft','Left dock','Anchor / columns / width',#defaults+2,function()openDockOptions('left')end)
    navigationRow('dockright','Right dock','Anchor / columns / width',#defaults+3,function()openDockOptions('right')end)
    navigationRow("setup","Setup / Import","Monitor geometry",#defaults+4,function() openConfigOptions() end)
    controls.panelLabel=label(panelHost,"",16,-7,568)
    local sliders={}
    local refreshing=false
    local function refresh()
        refreshing=true
        local p=preferences[selected]
        for index,panel in ipairs(preferences) do
            local row=controls.panelButtons[panel.id]
            row:ClearAllPoints();row:SetPoint("TOPLEFT",navigationContent,"TOPLEFT",0,-(index-1)*36)
            row.detail:SetText(panel.region..(panel.enabled==false and ' / removed' or (panel.minimized and ' / minimized' or ' dock')))
        end
        for index,id in ipairs({'bags','dockleft','dockright','setup'}) do
            local row=controls.panelButtons[id]
            row:ClearAllPoints();row:SetPoint('TOPLEFT',navigationContent,'TOPLEFT',0,-(#preferences+index-1)*36)
        end
        navigationContent:SetHeight(math.max(360,(#preferences+4)*36))
        for id,row in pairs(controls.panelButtons) do
            local view=controls.dockView and ('dock'..controls.dockView) or (controls.configView and 'setup' or (controls.bagView and 'bags' or p.id))
            local chosen=id==view
            if chosen then row:SetBackdropColor(0.24,0.19,0.10,1);row:SetBackdropBorderColor(0.85,0.68,0.28,1)
            else row:SetBackdropColor(0.08,0.10,0.13,1);row:SetBackdropBorderColor(0.18,0.21,0.25,1) end
        end
        if controls.bagView or controls.configView or controls.dockView then panelHost:Hide() else panelHost:Show() end
        if controls.dockControls then if controls.dockView then controls.dockControls:Show()else controls.dockControls:Hide()end end
        if bagControls then if controls.bagView then bagControls:Show() else bagControls:Hide() end end
        if configControls then if controls.configView then configControls:Show() else configControls:Hide() end end
        controls.panelLabel:SetText("Panel: "..p.title.." / "..p.region.." dock")
        if controls.destination then controls.destination:SetText('Side: '..p.region);controls.enabled:SetText(p.enabled==false and 'Restore to sides' or 'Remove from sides');controls.minimized:SetText(p.minimized and 'Start minimized: yes' or 'Start minimized: no')end
        for field,s in pairs(sliders) do s:SetValue(p[field]); s.caption:SetText(field..": "..math.floor(p[field]).." UI px") end
        controls.fill:SetChecked(p.fill==true)
        controls.fit:SetChecked(p.fit==true)
        controls.interactive:SetChecked(p.interactive==true)
        if controls.nativeScale then
            controls.nativeScale:SetValue(p.nativeScale or FW.HUD.CurrentPartyScale())
            controls.nativeScaleLabel:SetText("Native size: "..(p.nativeScale or FW.HUD.CurrentPartyScale()).."%")
            controls.nativeAlign:SetText("Align: "..FW.HUD.PartyAlign(p.nativeAlign))
            for _,widget in ipairs({controls.nativeScale,controls.nativeScaleLabel,controls.nativeAlign}) do
                if p.id=="party" then widget:Show() else widget:Hide() end
            end
        end
        if p.id=="party" then controls.interactive:Show();controls.interactiveLabel:Show()
        else controls.interactive:Hide();controls.interactiveLabel:Hide() end
        if controls.textSlider then
            controls.textSlider:SetValue(textSizes[p.id])
            controls.textCaption:SetText("Text: "..textSizes[p.id].." UI px")
        end
        refreshing=false
    end
    controls.RefreshPanelSelection=refresh
    controls.SelectPanel=function(id)
        -- Panel shortcuts and navigation follow identity even after reordering.
        for index,panel in ipairs(preferences) do
            if panel.id==id then selected=index;controls.bagView=false;controls.configView=false;controls.dockView=nil;refresh();controls:Show();return end
        end
    end
    pendingProviders={}
    controls.SyncProviderPanels=function()
        if #pendingProviders==0 or inCombat() then return end
        for _,panel in ipairs(pendingProviders) do
            local saved
            for _,p in ipairs(type(ForeverWorkspaceDB.panels)=='table' and ForeverWorkspaceDB.panels or {}) do
                if type(p)=='table' and p.id==panel.id then saved=p;break end
            end
            preferences[#preferences+1]=D.LoadPanels(saved and {saved}, {panel})[1]
            textSizes[panel.id]=T.Normalize(type(ForeverWorkspaceDB.panelFonts)=='table' and ForeverWorkspaceDB.panelFonts[panel.id] or nil)
            local id=panel.id
            navigationRow(id,panel.title,'Addon provider',#preferences,function()controls.SelectPanel(id)end)
        end
        pendingProviders={};refresh()
    end
    controls.destination=button(panelHost,'',16,-30,160,function()local p=preferences[selected];p.region=p.region=='left' and 'right' or 'left';refresh();controls.status:SetText('Side change staged. Apply trial / Keep.')end)
    controls.enabled=button(panelHost,'',184,-30,184,function()local p=preferences[selected];p.enabled=p.enabled==false;refresh();controls.status:SetText('Panel removal/restoration staged. Apply trial / Keep. Native panels return to Blizzard placement when removed.')end)
    controls.minimized=button(panelHost,'',376,-30,200,function()local p=preferences[selected];p.minimized=not p.minimized;refresh();controls.status:SetText('Initial minimized state staged. Apply trial / Keep.')end)
    local fields={"min","preferred","max"}
    for index,field in ipairs(fields) do
        local slider=CreateFrame("Slider",nil,panelHost,"OptionsSliderTemplate")
        slider:SetOrientation("HORIZONTAL"); slider:SetMinMaxValues(80,1000); slider:SetValueStep(10)
        slider:SetObeyStepOnDrag(true); slider:SetSize(360,16); slider:SetPoint("TOPLEFT",panelHost,"TOPLEFT",205,-80-(index-1)*38)
        slider.caption=label(panelHost,"",16,-79-(index-1)*38,180)
        slider:SetScript("OnValueChanged",function(_,value)
            if refreshing then return end
            local p=preferences[selected]; value=math.floor(value/10+0.5)*10; p[field]=value
            if field=="min" then p.preferred=math.max(p.preferred,value); p.max=math.max(p.max,p.preferred)
            elseif field=="max" then p.preferred=math.min(p.preferred,value); p.min=math.min(p.min,p.preferred)
            else p.min=math.min(p.min,value); p.max=math.max(p.max,value) end
            refresh(); controls.status:SetText("Size edits are staged. Apply trial previews them; Keep saves them.")
        end)
        sliders[field]=slider
    end
    controls.textCaption=label(panelHost,"",16,-193,180)
    controls.textSlider=CreateFrame("Slider",nil,panelHost,"OptionsSliderTemplate")
    controls.textSlider:SetOrientation("HORIZONTAL");controls.textSlider:SetMinMaxValues(T.minimum,T.maximum)
    controls.textSlider:SetValueStep(1);controls.textSlider:SetObeyStepOnDrag(true)
    controls.textSlider:SetSize(250,16);controls.textSlider:SetPoint("TOPLEFT",panelHost,"TOPLEFT",205,-194)
    controls.textSlider:SetScript("OnValueChanged",function(_,value)
        if refreshing then return end
        local panel=preferences[selected]
        saveTextSize(panel.id,value);refresh()
        controls.status:SetText(panel.interactive and "Panel title size saved. Use Native size to scale the interactive party frames."
            or (panel.title.." text: "..textSizes[panel.id].." UI px. Saved; visible panels update immediately."))
    end)
    button(panelHost,"Apply to all",470,-183,105,function()
        local size=textSizes[preferences[selected].id]
        for _,panel in ipairs(defaults) do saveTextSize(panel.id,size) end
        refresh();controls.status:SetText("All side-panel text set to "..size.." UI px and saved.")
    end)
    controls.fill=CreateFrame("CheckButton",nil,panelHost,"UICheckButtonTemplate")
    controls.fill:SetPoint("TOPLEFT",16,-220)
    label(panelHost,"Fill available dock height",52,-227,300)
    controls.fill:SetScript("OnClick",function(self)
        local p=preferences[selected]
        if p.interactive then self:SetChecked(false);p.fill=false;controls.status:SetText("Interactive Party uses a fixed reserved slot.");return end
        p.fill=self:GetChecked()==true
    end)
    button(panelHost,"Swap stack order",370,-222,205,function()
        local id=preferences[selected].region
        local a,b
        for i,p in ipairs(preferences) do if p.region==id then if not a then a=i else b=i end end end
        if a and b then
            preferences[a],preferences[b]=preferences[b],preferences[a]
            selected=selected==a and b or a
            refresh()
        end
    end)
    controls.fit=CreateFrame("CheckButton",nil,panelHost,"UICheckButtonTemplate")
    controls.fit:SetPoint("TOPLEFT",16,-254)
    label(panelHost,"Fit content: auto height within min/max (overrides Fill)",52,-261,520)
    controls.fit:SetScript("OnClick",function(self)
        if preferences[selected].interactive then self:SetChecked(false);preferences[selected].fit=false;controls.status:SetText("Interactive Party uses a fixed reserved slot.");return end
        preferences[selected].fit=self:GetChecked()==true
        controls.status:SetText("Fit content is staged. Apply trial, then Keep to enable automatic height updates.")
    end)
    controls.interactive=CreateFrame("CheckButton",nil,panelHost,"UICheckButtonTemplate")
    controls.interactive:SetPoint("TOPLEFT",16,-288)
    controls.interactiveLabel=label(panelHost,"Interactive Party trial (standard Blizzard frames)",52,-295,520)
    controls.interactive:SetScript("OnClick",function(self)
        local p=preferences[selected]
        if p.id~="party" then self:SetChecked(false);return end
        if inCombat() then self:SetChecked(p.interactive==true);controls.status:SetText("Change interactive Party mode outside combat.");return end
        if self:GetChecked() then
            local canvas=canvasInfo()
            local metrics,err
            if canvas and FW.Geometry then metrics,err=FW.HUD.PartyMetrics(FW.Geometry,canvas.pixelsPerUnit,p) end
            if not metrics or metrics.slotHeight>1000 then self:SetChecked(false);controls.status:SetText(err or "Native party frames cannot fit the available height.");return end
            p.min=math.max(p.min,metrics.slotHeight);p.preferred=math.max(p.preferred,p.min);p.max=math.max(p.max,p.preferred)
            p.fill=false;p.fit=false;p.interactive=true
            controls.status:SetText("Native party space reserved; Fit content off. Adjust Native size below, then Apply trial / Keep.")
        else p.interactive=false;controls.status:SetText("Summary mode staged. Apply trial / Keep restores native party placement.") end
        refresh()
    end)
    controls.nativeScaleLabel=label(panelHost,"",16,-331,185)
    controls.nativeScale=CreateFrame("Slider",nil,panelHost,"OptionsSliderTemplate")
    controls.nativeScale:SetOrientation("HORIZONTAL");controls.nativeScale:SetMinMaxValues(100,200)
    controls.nativeScale:SetValueStep(5);controls.nativeScale:SetObeyStepOnDrag(true)
    controls.nativeScale:SetSize(360,16);controls.nativeScale:SetPoint("TOPLEFT",panelHost,"TOPLEFT",205,-332)
    controls.nativeScale:SetScript("OnValueChanged",function(_,value)
        if refreshing then return end
        local p=preferences[selected]
        if p.id~="party" then return end
        if inCombat() then refresh();controls.status:SetText("Stage native party size outside combat.");return end
        local old=p.nativeScale;p.nativeScale=FW.HUD.PartyScale(value)
        if p.interactive then
            local canvas=canvasInfo()
            local metrics,err
            if canvas and FW.Geometry then metrics,err=FW.HUD.PartyMetrics(FW.Geometry,canvas.pixelsPerUnit,p) end
            if not metrics or metrics.slotHeight>1000 then p.nativeScale=old;refresh();controls.status:SetText(err or "The requested native size cannot fit the panel height limits.");return end
            p.min=math.max(p.min,metrics.slotHeight);p.preferred=math.max(p.preferred,p.min);p.max=math.max(p.max,p.preferred)
        end
        refresh();controls.status:SetText("Native party size staged. Apply trial / Keep; width and dock limits are checked on Apply.")
    end)
    controls.nativeAlign=button(panelHost,"",205,-362,360,function()
        if inCombat() then controls.status:SetText("Stage party alignment outside combat.");return end
        local p=preferences[selected]
        if p.id~="party" then return end
        local align=FW.HUD.PartyAlign(p.nativeAlign)
        p.nativeAlign=align=="left" and "center" or (align=="center" and "right" or "left")
        refresh();controls.status:SetText("Native party alignment staged. Apply trial / Keep.")
    end)
    button(controls,"Center Blizzard HUD",16,-568,396,centerHud)
    button(controls,"Restore Blizzard HUD",428,-568,396,restoreHud)
    button(controls,"Sync game size",16,-612,396,function() videoAction(false) end)
    button(controls,"Restore game size",428,-612,396,function() videoAction(true) end)
    label(controls,"Text saves immediately. Panel layout and Party mode use Apply trial / Keep.",16,-657,808)
    label(controls,"Bags has its own Apply and save. Left/Right refer to your configured monitor strips.",16,-677,808)
    refresh()
    controls:SetScript("OnUpdate",function()
        if deadline then
            local remaining=math.ceil(deadline-GetTime())
            if remaining<=0 then reset("Trial timed out; viewport restored.")
            else controls.status:SetText("Trial active: "..remaining.." seconds remaining. Keep or Reset viewport.") end
        end
    end)
    -- The timer must survive hiding the settings window.
    local watchdog=CreateFrame("Frame")
    watchdog:SetScript("OnUpdate",function()
        if #pendingProviders>0 then controls.SyncProviderPanels() end
        if deadline and GetTime()>=deadline then reset("Trial timed out; viewport restored.") end
        if alignmentDeadline and GetTime()>=alignmentDeadline then reset("Alignment size trial timed out; restoring.") end
        if alignmentActive and GetTime()>=alignmentRefreshAt then alignmentRefreshAt=GetTime()+0.25;drawAlignment() end
        if pendingAlignmentRestore and not inCombat() and alignmentRestoreAttempts<5 and GetTime()>=alignmentRestoreAt then
            alignmentRestoreAt=GetTime()+1;alignmentRestoreAttempts=alignmentRestoreAttempts+1
            local restored,message=FW.Video.Restore(ForeverWorkspaceDB);pendingAlignmentRestore=not restored
            if not restored and alignmentRestoreAttempts==5 then say(message.." Use Restore game size; recovery settings remain saved.") end
        end
        resumeAfterZone()
        if zoning or zoneResumeAt then return end
        if active and questsDirty and GetTime()>=questRefreshAt then questsDirty=false;refreshQuests() end
        if active and groupsDirty and GetTime()>=groupRefreshAt then groupsDirty=false;refreshGroups() end
        if active and not inCombat() and GetTime()>=providerRefreshAt then
            providerRefreshAt=GetTime()+0.5
            local fitChanged=false
            for _,p in ipairs(appliedPanels or {}) do
                local frame=sampleFrames[p.id]
                local refresh=textProviders[p.id] or (p.id=='dungeon' and J.dirty)
                if refresh and frame and frame:IsShown() and (p.id=='dungeon' or not frame.minimized) and frame:Refresh() and p.fit then fitChanged=true end
            end
            if fitChanged then reflowPanels() end
        end
        if active then FW.HUD.RefreshVisibility()end
    end)
    controls:Hide()
end

local events=CreateFrame("Frame")
for _,event in ipairs({"ADDON_LOADED","PLAYER_LOGOUT","PLAYER_LEAVING_WORLD","PLAYER_ENTERING_WORLD","DISPLAY_SIZE_CHANGED","UI_SCALE_CHANGED","PLAYER_REGEN_ENABLED"}) do events:RegisterEvent(event) end
for _,event in ipairs({"LOADING_SCREEN_ENABLED","LOADING_SCREEN_DISABLED"}) do pcall(events.RegisterEvent,events,event) end
local questEvents={QUEST_LOG_UPDATE=true,QUEST_WATCH_LIST_CHANGED=true,QUEST_WATCH_UPDATE=true,
    QUEST_ACCEPTED=true,QUEST_REMOVED=true,QUEST_TURNED_IN=true,QUEST_AUTOCOMPLETE=true,QUEST_DATA_LOAD_RESULT=true}
for event in pairs(questEvents) do pcall(events.RegisterEvent,events,event) end
local groupEvents={GROUP_ROSTER_UPDATE=true,PLAYER_ROLES_ASSIGNED=true,ROLE_CHANGED_INFORM=true,
    PARTY_LEADER_CHANGED=true,UNIT_NAME_UPDATE=true,UNIT_CONNECTION=true,UNIT_FLAGS=true,
    PLAYER_DEAD=true,PLAYER_ALIVE=true,PLAYER_UNGHOST=true,PLAYER_REGEN_ENABLED=true,PLAYER_REGEN_DISABLED=true,
    ZONE_CHANGED_NEW_AREA=true,ADDON_RESTRICTION_STATE_CHANGED=true}
local groupUnitEvents={UNIT_NAME_UPDATE=true,UNIT_CONNECTION=true,UNIT_FLAGS=true}
for event in pairs(groupEvents) do pcall(events.RegisterEvent,events,event) end
events:SetScript("OnEvent",function(_,event,name)
    if event=='PLAYER_ENTERING_WORLD' or event=='ZONE_CHANGED_NEW_AREA'
        or (event=='ADDON_LOADED' and name=='Blizzard_EncounterJournal') then J.dirty=true end
    if event=="LOADING_SCREEN_ENABLED" then
        loadingScreen=true
        if active and not deadline then zoning=true end
    elseif event=="LOADING_SCREEN_DISABLED" then
        loadingScreen=false
        if active and not deadline and (zoning or zoneResumeAt) then
            zoning,zoneResumeAt=false,GetTime()+0.2
        end
    end
    if questEvents[event] or event=="PLAYER_ENTERING_WORLD" then
        if not questsDirty then questRefreshAt=GetTime()+0.15 end
        questsDirty=true
    end
    if (groupEvents[event] and (not groupUnitEvents[event] or G.RelevantUnit(name))) or event=="PLAYER_ENTERING_WORLD" then
        if not groupsDirty then groupRefreshAt=GetTime()+0.15 end
        groupsDirty=true
    end
    if event=="ADDON_LOADED" and name==addonName then
        if type(ForeverWorkspaceDB)~="table" then ForeverWorkspaceDB={} end
        FW.Geometry=FW.Config.Load(ForeverWorkspaceDB,FW.Geometry)
        local helperGeometry,helperMessage=FW.Config.HelperBridge(ForeverWorkspaceDB,PeripheralHelperExport)
        if helperGeometry then FW.Geometry=helperGeometry end
        textSizes=T.Load(ForeverWorkspaceDB.panelFonts)
        FW.Bags.options=FW.Bags.Options(ForeverWorkspaceDB.bags)
        preferences=D.LoadPanels(ForeverWorkspaceDB.panels,defaults)
        local savedDocks=type(ForeverWorkspaceDB.docks)=='table' and ForeverWorkspaceDB.docks or {}
        dockPreferences={left=D.Options(savedDocks.left),right=D.Options(savedDocks.right)}
        createControls()
        say("v"..VERSION.." loaded disabled. "..geometrySummary()..". /fws opens controls."..(ForeverWorkspaceDB.geometryMigrationNotice and " "..ForeverWorkspaceDB.geometryMigrationNotice or ""))
        if helperMessage then say(helperMessage) end
    elseif event=="ADDON_LOADED" then
        if FW.NativeWindows.enabled then FW.NativeWindows.Refresh() end
        if FW.Bags.enabled then FW.Bags.Refresh() end
    elseif event=="PLAYER_LOGOUT" then
        if active or originalPoints or alignmentActive then reset("Viewport restored for logout. Reapply after login/reload.") end
    elseif event=="PLAYER_LEAVING_WORLD" then
        if active and not deadline then
            zoning,zoneResumeAt=true,nil
        elseif active or originalPoints or alignmentActive then
            reset("Unconfirmed trial restored for loading. Apply and Keep after entering the world.")
        end
    elseif event=="DISPLAY_SIZE_CHANGED" or event=="UI_SCALE_CHANGED" then
        -- Loading can report temporary canvas dimensions. Validate once settled.
        if not zoning and not zoneResumeAt and (active or originalPoints) then reset("Display or UI scale changed; viewport restored. Recalibrate before applying.") end
    elseif event=="PLAYER_ENTERING_WORLD" and active and not deadline then
        zoning,zoneResumeAt=loadingScreen==true,GetTime()+0.2
    elseif event=="PLAYER_ENTERING_WORLD" and not active and ForeverWorkspaceDB and ForeverWorkspaceDB.hud then
        local restored,message=FW.HUD.Restore(ForeverWorkspaceDB)
        pendingHudRestore=not restored
        if not restored then say(message.." /fws opens Restore Blizzard HUD.") end
    elseif event=="PLAYER_REGEN_ENABLED" then
        local queued=pendingMinimize;pendingMinimize={}
        if pendingRestore then pendingRestore=nil;reset("Pending viewport restoration completed.") end
        if pendingHudRestore then restoreHud() end
        if pendingWindowRestore then
            local restored,message=FW.NativeWindows.Restore();pendingWindowRestore=not restored
            if not restored then say(message) end
        elseif FW.NativeWindows.pending then FW.NativeWindows.Refresh() end
        if pendingBagRestore then
            local restored,message=FW.Bags.Restore();pendingBagRestore=not restored
            if not restored then say(message) end
        elseif FW.Bags.pending then FW.Bags.Refresh() end
        if pendingAlignmentRestore then
            local restored,message=FW.Video.Restore(ForeverWorkspaceDB);pendingAlignmentRestore=not restored
            if not restored then say(message) end
        end
        for id,value in pairs(queued)do toggleMinimized(id,value)end
    end
end)

SLASH_FOREVERWORKSPACE1="/fws"
SLASH_FOREVERWORKSPACE2="/peripheral"
SlashCmdList.FOREVERWORKSPACE=function(message)
    local command=(message or ""):lower():match("^%s*(%S*)")
    if not controls then return end
    if command=="reset" or command=="off" then reset(); say("Viewport reset. Restore requested game size separately; manual desktop position is not measured.")
    elseif command=="diag" then diagnostics()
    elseif command=="import" or command=="setup" then openConfigOptions()
    elseif command=="start" then useSavedLayout()
    elseif command=="align" then beginAlignment()
    elseif command=="fit" then
        if not alignmentActive then beginAlignment() end
        if alignmentActive and fitCurrentWindow then fitCurrentWindow() end
    elseif command=="version" then
        local bridge=ForeverWorkspaceDB.helperBridgeError or (ForeverWorkspaceDB.helperBridgeID and "Helper bridge connected; new handoffs load on /reload, without activation." or "No helper handoff received. Use Start Peripheral, restart WoW once and enable Peripheral - Windows Helper Bridge; or use HTML/import.")
        say("Addon v"..VERSION.."; helper export v"..tostring(FW.Geometry and FW.Geometry.helperVersion or "n/a (manual/import)")..". "..geometrySummary().."\n"..bridge)
    elseif command=="hud" then centerHud()
    elseif command=="restorehud" then restoreHud()
    elseif command=="syncvideo" then videoAction(false)
    elseif command=="restorevideo" then videoAction(true)
    elseif command=="quests" then
        Q.requested={}
        questsDirty=true;questRefreshAt=0
        if active then questsDirty=false;refreshQuests();say("Quest panel refreshed.")
        else say("Apply and Keep the viewport to show live tracked quests.") end
    elseif command=="groups" then
        groupsDirty=true;groupRefreshAt=0
        if active then groupsDirty=false;refreshGroups();say("Party and raid panels refreshed.")
        else say("Apply and Keep the viewport to show live group data.") end
    elseif command=="native" then
        for _,candidate in ipairs(N.Read()) do
            say(candidate.name..": "..(candidate.present and "native frame present. " or "native frame not loaded. ")..candidate.detail)
        end
        say("Minimap is an optional native panel in /fws. Chat docking is not implemented; Bags has its own destination settings.")
    elseif command=="bags" then openBagOptions()
    elseif command=="enable" or command=="test" then controls:Show(); apply()
    elseif command=="keep" then keep()
    else controls:Show() end
end
