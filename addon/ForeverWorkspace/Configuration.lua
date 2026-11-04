local _, FW = ...
local C = {schema=1, maxBytes=65536}
FW.Config=C
local function finite(n) return type(n)=="number" and n==n and n>-math.huge and n<math.huge end
local function copy(t)
    if type(t)~="table" then return t end
    local r={};for k,v in pairs(t) do r[k]=copy(v) end;return r
end
C.Copy=copy
local function validUTF8(text)
    local i=1
    while i<=#text do
        local b=text:byte(i)
        if b<128 then i=i+1
        else
            local count,min,code
            if b>=194 and b<=223 then count,min,code=2,128,b-192
            elseif b>=224 and b<=239 then count,min,code=3,2048,b-224
            elseif b>=240 and b<=244 then count,min,code=4,65536,b-240
            else return false end
            for offset=1,count-1 do local nextByte=text:byte(i+offset);if not nextByte or nextByte<128 or nextByte>191 then return false end;code=code*64+nextByte-128 end
            if code<min or code>1114111 or (code>=55296 and code<=57343) then return false end
            i=i+count
        end
    end
    return true
end

-- Original, bounded JSON reader. Pasted text is never compiled or executed.
function C.Decode(text)
    if type(text)~="string" or #text==0 or #text>C.maxBytes then return nil,"Paste JSON configuration (maximum 64 KiB)." end
    if not validUTF8(text) then return nil,"Configuration must contain valid UTF-8 text." end
    local i,n,nodes=1,#text,0
    local function fail(message) error(message.." at byte "..i,0) end
    local function space() while i<=n and text:sub(i,i):match("[ \t\r\n]") do i=i+1 end end
    local function utf8(code)
        if code<128 then return string.char(code)
        elseif code<2048 then return string.char(192+math.floor(code/64),128+code%64)
        elseif code<65536 then return string.char(224+math.floor(code/4096),128+math.floor(code/64)%64,128+code%64)
        else return string.char(240+math.floor(code/262144),128+math.floor(code/4096)%64,128+math.floor(code/64)%64,128+code%64) end
    end
    local function quoted()
        if text:sub(i,i)~='"' then fail("Expected string") end
        i=i+1;local parts={}
        while i<=n do
            local ch=text:sub(i,i);i=i+1
            if ch=='"' then return table.concat(parts) end
            if ch=='\\' then
                ch=text:sub(i,i);i=i+1
                local escapes={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}
                if escapes[ch] then parts[#parts+1]=escapes[ch]
                elseif ch=='u' then
                    local h=text:sub(i,i+3);if #h~=4 or not h:match('^%x%x%x%x$') then fail("Invalid Unicode escape") end
                    local code=tonumber(h,16);i=i+4
                    if code>=55296 and code<=56319 then
                        if text:sub(i,i+1)~='\\u' then fail("Missing low surrogate") end
                        h=text:sub(i+2,i+5);if #h~=4 or not h:match('^%x%x%x%x$') then fail("Invalid low surrogate") end
                        local low=tonumber(h,16);if low<56320 or low>57343 then fail("Invalid low surrogate") end
                        code=65536+(code-55296)*1024+low-56320;i=i+6
                    elseif code>=56320 and code<=57343 then fail("Unexpected low surrogate") end
                    parts[#parts+1]=utf8(code)
                else fail("Invalid escape") end
            elseif ch:byte()<32 then fail("Unescaped control character")
            else parts[#parts+1]=ch end
        end
        fail("Unterminated string")
    end
    local value
    value=function(depth)
        nodes=nodes+1;if depth>12 or nodes>1500 then fail("Configuration is too complex") end
        space();local ch=text:sub(i,i)
        if ch=='"' then return quoted() end
        if ch=='{' or ch=='[' then
            local object=ch=='{';local close=object and '}' or ']';local result={};i=i+1;space()
            if text:sub(i,i)==close then i=i+1;return result end
            local index=1
            while true do
                local key=index
                if object then
                    space();key=quoted();space();if result[key]~=nil then fail("Duplicate object key") end
                    if text:sub(i,i)~=':' then fail("Expected colon") end;i=i+1
                end
                result[key]=value(depth+1);index=index+1;space();ch=text:sub(i,i);i=i+1
                if ch==close then return result end
                if ch~=',' then fail("Expected comma or closing delimiter") end
            end
        end
        if text:sub(i,i+3)=='true' then i=i+4;return true end
        if text:sub(i,i+4)=='false' then i=i+5;return false end
        -- Null is not part of this format, including optional monitor roles.
        if text:sub(i,i+3)=='null' then fail("Use an omitted field instead of null") end
        local start=i
        if ch=='-' then i=i+1 end
        ch=text:sub(i,i)
        if ch=='0' then i=i+1
        elseif ch:match('[1-9]') then repeat i=i+1 until not text:sub(i,i):match('%d')
        else fail("Expected JSON data") end
        if text:sub(i,i)=='.' then
            i=i+1;if not text:sub(i,i):match('%d') then fail("Expected fraction") end
            repeat i=i+1 until not text:sub(i,i):match('%d')
        end
        if text:sub(i,i):match('[eE]') then
            i=i+1;if text:sub(i,i):match('[+-]') then i=i+1 end
            if not text:sub(i,i):match('%d') then fail("Expected exponent") end
            repeat i=i+1 until not text:sub(i,i):match('%d')
        end
        local number=tonumber(text:sub(start,i-1));if not finite(number) then fail("Non-finite number") end
        return number
    end
    local ok,result=pcall(function() local r=value(0);space();if i<=n then fail("Trailing data") end;return r end)
    if not ok then return nil,tostring(result) end
    return result
end
function C.Encode(value)
    local function encode(v)
        if type(v)=="number" then assert(finite(v));return string.format("%.15g",v) end
        if type(v)=="boolean" then return v and "true" or "false" end
        if type(v)=="string" then
            return '"'..v:gsub('[%z\1-\31\\"]',function(ch)
                if ch=='"' then return '\\"' elseif ch=='\\' then return '\\\\' end
                return string.format('\\u%04x',ch:byte())
            end)..'"'
        end
        assert(type(v)=="table","Unsupported JSON value")
        local items={}
        if #v>0 then for _,item in ipairs(v) do items[#items+1]=encode(item) end;return '['..table.concat(items,',')..']' end
        local keys={};for key in pairs(v) do assert(type(key)=="string");keys[#keys+1]=key end;table.sort(keys)
        for _,key in ipairs(keys) do items[#items+1]=encode(key)..':'..encode(v[key]) end
        return '{'..table.concat(items,',')..'}'
    end
    return encode(value)
end
local function keys(t,allowed)
    if type(t)~="table" then return false end
    for k in pairs(t) do if not allowed[k] then return false end end
    return true
end
local function integer(n,lo,hi) return finite(n) and n==math.floor(n) and n>=lo and n<=hi end
local function rect(r)
    return type(r)=="table" and integer(r.x,-65536,65536) and integer(r.y,-65536,65536)
        and integer(r.width,1,16384) and integer(r.height,1,16384)
end
function C.Validate(raw)
    if not keys(raw,{format=true,schema=true,units=true,monitors=true,roles=true,strips=true,respectWorkArea=true,source=true,producerVersion=true,canvasInsets=true})
        or raw.format~="ForeverWorkspace" or raw.schema~=1 or raw.units~="physical-px" then
        return nil,"Expected ForeverWorkspace schema 1 JSON in physical-px units."
    end
    if type(raw.respectWorkArea)~="boolean" or not keys(raw.roles,{main=true,left=true,right=true})
        or not keys(raw.strips,{left=true,right=true}) then return nil,"Invalid roles, strips or work-area flag." end
    if raw.source~=nil and raw.source~="manual" and raw.source~="browser" and raw.source~="helper" then return nil,"Invalid source." end
    if raw.producerVersion~=nil and (type(raw.producerVersion)~="string" or #raw.producerVersion>20 or not raw.producerVersion:match('^%d+%.%d+%.%d+$')) then return nil,"Invalid producer version." end
    local monitors,byID={},{}
    if type(raw.monitors)~="table" or #raw.monitors<2 or #raw.monitors>12 then return nil,"Supply 2 to 12 monitor rectangles." end
    for k in pairs(raw.monitors) do if not integer(k,1,#raw.monitors) then return nil,"Monitors must be an array." end end
    for _,m in ipairs(raw.monitors) do
        if not keys(m,{id=true,label=true,x=true,y=true,width=true,height=true,work=true}) or not rect(m)
            or m.width<320 or m.height<240 or type(m.id)~="string" or #m.id<1 or #m.id>64
            or not m.id:match('^[A-Za-z0-9_.-]+$') or byID[m.id] then return nil,"Invalid monitor rectangle or duplicate monitor ID." end
        if m.label~=nil and (type(m.label)~="string" or #m.label>160 or not validUTF8(m.label) or m.label:find('[%z\1-\31]')) then return nil,"Invalid monitor label." end
        local work=m.work or {x=m.x,y=m.y,width=m.width,height=m.height}
        if not keys(work,{x=true,y=true,width=true,height=true}) or not rect(work) or work.x<m.x or work.y<m.y
            or work.x+work.width>m.x+m.width or work.y+work.height>m.y+m.height then return nil,"Work areas must stay inside their monitor." end
        local normalized={id=m.id,label=m.label,x=m.x,y=m.y,width=m.width,height=m.height,work=copy(work)}
        monitors[#monitors+1]=normalized;byID[m.id]=normalized
    end
    for _,side in ipairs({'left','right'}) do
        if not integer(raw.strips[side],15,70) then return nil,"Both strip percentages must be whole numbers from 15 to 70." end
    end
    local main=byID[raw.roles.main]
    if not main then return nil,"Main must reference an existing monitor." end
    local regions,selected={}, {[main.id]=true}
    local x0,y0,x1,y1=main.x,main.y,main.x+main.width,main.y+main.height
    local absolute={}
    for _,side in ipairs({'left','right'}) do
        local id=raw.roles[side]
        if id~=nil then
            local m=byID[id]
            if not m or selected[id] then return nil,"Each selected role needs a different existing monitor." end;selected[id]=true
            if (side=='left' and m.x+m.width>main.x) or (side=='right' and m.x<main.x+main.width)
                or m.y>=main.y+main.height or m.y+m.height<=main.y then return nil,"Only horizontal side monitors with overlapping heights are supported." end
            local width=math.floor(m.width*raw.strips[side]/100+0.5)
            local r={id=side,x=side=='left' and m.x+m.width-width or m.x,y=m.y,width=width,height=m.height}
            x0=math.min(x0,r.x);y0=math.min(y0,r.y);x1=math.max(x1,r.x+r.width);y1=math.max(y1,r.y+r.height)
            if raw.respectWorkArea then
                local w=m.work;local right,bottom=math.min(r.x+r.width,w.x+w.width),math.min(r.y+r.height,w.y+w.height)
                r.x=math.max(r.x,w.x);r.y=math.max(r.y,w.y);r.width=right-r.x;r.height=bottom-r.y
            end
            if r.width<160 or r.height<240 then return nil,"A reference strip has too little usable space." end
            absolute[#absolute+1]=r
        end
    end
    if #absolute==0 then return nil,"Select at least one side monitor." end
    if x1-x0>32768 or y1-y0>16384 or (x1-x0)*(y1-y0)>134217728 then return nil,"The requested canvas exceeds supported bounds." end
    local insets=raw.canvasInsets
    if insets~=nil then
        if not keys(insets,{left=true,right=true,top=true,bottom=true}) then return nil,"Invalid canvas insets." end
        for _,edge in ipairs({'left','right','top','bottom'}) do
            local minimum=(edge=='left' or edge=='right') and -256 or 0
            if not integer(insets[edge],minimum,512) then return nil,"Canvas insets must be whole pixels: horizontal -256 to 512; vertical 0 to 512." end
        end
        x0=x0+insets.left;y0=y0+insets.top;x1=x1-insets.right;y1=y1-insets.bottom
    end
    local leftMonitor=raw.roles.left and byID[raw.roles.left] or main
    local rightMonitor=raw.roles.right and byID[raw.roles.right] or main
    if x0<leftMonitor.x or x1>rightMonitor.x+rightMonitor.width or x1-x0>32768 or y1-y0>16384 or (x1-x0)*(y1-y0)>134217728 then return nil,"Adjusted canvas must remain inside the selected horizontal monitor span and supported bounds." end
    -- Preserve Main's physical width. A bordered manual window can leave a
    -- vertical gap, but may never squeeze or stretch the world to hide a mismatch.
    local mainTop,mainBottom=math.max(main.y,y0),math.min(main.y+main.height,y1)
    if x0>main.x or x1<main.x+main.width or mainBottom-mainTop<240 then return nil,"Canvas insets must preserve Main's full width and at least 240 pixels of height." end
    for _,r in ipairs(absolute) do
        local right,bottom=math.min(r.x+r.width,x1),math.min(r.y+r.height,y1)
        r.x=math.max(r.x,x0);r.y=math.max(r.y,y0);r.width=right-r.x;r.height=bottom-r.y
        if r.width<160 or r.height<240 then return nil,"Canvas insets leave a reference strip too small." end
    end
    for _,r in ipairs(absolute) do r.x=r.x-x0;r.y=r.y-y0;regions[#regions+1]=r end
    local normalized={format='ForeverWorkspace',schema=1,units='physical-px',monitors=monitors,roles=copy(raw.roles),strips=copy(raw.strips),respectWorkArea=raw.respectWorkArea,source=raw.source,producerVersion=raw.producerVersion,canvasInsets=copy(insets)}
    local geometry={schema=1,generated='SavedVariables configuration',x=x0,y=y0,width=x1-x0,height=y1-y0,
        main={x=main.x-x0,y=mainTop-y0,width=main.width,height=mainBottom-mainTop},regions=regions,respectWorkArea=raw.respectWorkArea,
        helperVersion=raw.source=='helper' and raw.producerVersion or nil}
    return normalized,geometry
end
function C.Fit(config,width,height)
    if not integer(width,320,32768) or not integer(height,240,16384) then return nil,"Live client dimensions are unavailable." end
    local candidate=copy(config)
    if type(candidate)~='table' then return nil,"Import a monitor configuration before fitting." end
    candidate.canvasInsets=nil
    local normalized,g=C.Validate(candidate);if not normalized then return nil,g end
    local dx,dy=g.width-width,g.height-height
    if math.abs(dx)>256 or dy<0 or dy>256 then return nil,"Resize close to the target first. Fit accepts width within 256 pixels of target and height up to 256 pixels shorter, inside the selected monitors." end
    local left=g.main.x;local right=g.width-g.main.x-g.main.width
    local trimLeft=left+right>0 and math.floor(dx*left/(left+right)) or 0
    normalized.canvasInsets={left=trimLeft,right=dx-trimLeft,top=0,bottom=dy}
    return C.Validate(normalized)
end
function C.Parse(text)
    local raw,err=C.Decode(text);if not raw then return nil,err end
    return C.Validate(raw)
end
function C.Legacy(g)
    if type(g)~='table' or not integer(g.width,320,32768) or not integer(g.height,240,16384)
        or g.width*g.height>134217728 or not FW.Layout.ValidateGeometry(g,g.width,g.height) then return nil end
    if #g.regions>2 then return nil end
    for _,r in ipairs(g.regions) do if r.id~='left' and r.id~='right' then return nil end end
    return {schema=1,width=g.width,height=g.height,main=copy(g.main),regions=copy(g.regions),respectWorkArea=g.respectWorkArea==true,
        generated='Migrated legacy geometry',helperVersion=type(g.helperVersion)=='string' and g.helperVersion or nil}
end
function C.FromDiagnostics(text)
    if type(text)~='string' or #text>65536 then return nil end
    local width,height=text:match('\nExpected canvas: (%d+) x (%d+)')
    local x,y,w,h=text:match('\nMain: (%d+),(%d+) (%d+)x(%d+)')
    if not width or not x then return nil end
    local g={schema=1,width=tonumber(width),height=tonumber(height),main={x=tonumber(x),y=tonumber(y),width=tonumber(w),height=tonumber(h)},regions={},respectWorkArea=text:find('\nTaskbar clearance: enabled',1,true)~=nil}
    for _,side in ipairs({'left','right'}) do
        x,y,w,h=text:match('\n'..side..' region: (%d+),(%d+) (%d+)x(%d+)')
        if x then g.regions[#g.regions+1]={id=side,x=tonumber(x),y=tonumber(y),width=tonumber(w),height=tonumber(h)} end
    end
    return C.Legacy(g)
end
function C.Load(db,legacy)
    if db.configuration then
        local config,g=C.Validate(db.configuration)
        if config then db.configuration=config;db.configurationError=nil;return g end
        db.configurationError=g
        if db.lastWorkingConfiguration then local previous,working=C.Validate(db.lastWorkingConfiguration);if previous then db.configuration=previous;return working end end
        db.configuration=nil
    end
    if not db.geometryMigrationDone then
        local g=C.Legacy(legacy)
        if not g then
            g=C.FromDiagnostics(db.lastDiagnostics)
            if g then db.geometryMigrationNotice='Recovered the last saved diagnostic geometry; it may be stale. Verify alignment or import a fresh configuration before Keep.' end
        end
        if g then db.legacyGeometry=g;db.geometryMigrationDone=true end
    end
    return C.Legacy(db.legacyGeometry)
end
function C.Save(db,config)
    local normalized,g=C.Validate(config);if not normalized then return nil,g end
    db.previousConfiguration=copy(db.configuration)
    db.configuration=normalized;db.configurationError=nil;db.geometryMigrationNotice=nil
    return g
end

-- Optional helper-owned companion. Each handoff is consumed once so an old
-- bridge cannot override a later HTML/manual import or Previous / working.
function C.HelperBridge(db,export)
    if export==nil then return nil end
    local function reject(message) db.helperBridgeError=message;return nil,message end
    if type(export)~='table' or export.schema~=1 or type(export.id)~='string' or #export.id~=32
        or not export.id:match('^[a-f0-9]+$') or type(export.payload)~='string' then
        return reject('Helper handoff is invalid; previous settings retained.')
    end
    if export.id==db.helperBridgeID then db.helperBridgeError=nil;return nil end
    local config,g=C.Parse(export.payload)
    if not config or config.source~='helper' then return reject('Helper handoff rejected: '..tostring(config and 'expected helper source' or g)) end
    local saved,message=C.Save(db,config);if not saved then return reject(message) end
    db.helperBridgeID=export.id;db.helperBridgeError=nil
    return saved,'Windows helper layout received; viewport remains disabled. Apply trial and Keep.'
end
