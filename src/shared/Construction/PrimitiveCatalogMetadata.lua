--!strict
-- Human-facing catalog names and families. Template IDs remain immutable:
-- plots, mechanical relationships and saved component blueprints store them.
local Catalog={}
local ORDER={
    "Basic Shapes",
    "Plates & Profiles",
    "Shafts & Rods",
    "Tubes",
    "Holes & Slots",
    "Gears",
    "Pulleys",
    "Fasteners",
    "Actuators",
    "Other",
}
local RANK={}
for i,name in ipairs(ORDER) do RANK[name]=i end
Catalog.Categories=table.freeze(ORDER)

local function starts(s,p)
    return string.sub(s,1,#p)==p
end
local function numberLabel(num)
    local n=tonumber(num)
    return if n then tostring(n) else num
end
local function titleCase(s)
    -- For unrecognized older Studio primitives. Do not mutate template IDs.
    s=s:gsub("([a-z])([A-Z])","%1 %2")
        :gsub("([A-Za-z])(%d)","%1 %2")
        :gsub("(%d)([A-Za-z])","%1 %2")
        :gsub("_+"," "):gsub("%s+"," ")
    s=s:gsub("^%s+",""):gsub("%s+$","")
    s=s:gsub("^%l",string.upper)
    s=s:gsub("%f[%a]U%f[%A]","U")
    return s
end
local function familyFor(id,folder,model)
    local name=id:lower()
    local category=folder:lower()
    local family=tostring(model:GetAttribute("PrimitiveFamily") or ""):lower()
    if family=="bolt" or name:find("bolt",1,true)
        or name:find("screw",1,true)
        or category=="fasteners" then return "Fasteners" end
    if name:find("pulley",1,true) or family=="pulley"
        then return "Pulleys" end
    if name:find("gear",1,true) or name:find("bevel",1,true)
        or family=="gear" or family=="bevel"
        then return "Gears" end
    if name:find("crank",1,true) or name:find("motor",1,true)
        or category=="actuators" then return "Actuators" end
    if name:find("slot",1,true) or name:find("hole",1,true)
        or name:find("bore",1,true)
        then return "Holes & Slots" end
    if name:find("tube",1,true) or name:find("pipe",1,true)
        then return "Tubes" end
    if name:find("shaft",1,true) or name:find("rod",1,true)
        or name:find("axle",1,true)
        or category=="shafts" then return "Shafts & Rods" end
    if name:find("plate",1,true) or name:find("flat",1,true)
        or name:find("angle",1,true) or name:find("profile",1,true)
        or category=="profiles" then return "Plates & Profiles" end
    if name:find("block",1,true) or name:find("cylinder",1,true)
        or name:find("slope",1,true) or name:find("wedge",1,true)
        or name:find("cube",1,true)
        or category=="shapes" or category=="primitives"
        then return "Basic Shapes" end
    return "Other"
end
local function variantSuffix(id,prefix)
    local rest=id:sub(#prefix+1)
    if rest:sub(1,1)=="_" or rest:sub(1,1)=="-" then
        rest=rest:sub(2)
    end
    if rest=="" then return "" end
    local rendered=titleCase(rest)
    -- Keep the distinction between different fixed-size original templates,
    -- including diameter, wall and slot variants that share a shape family.
    return if rendered~="" then "  ·  "..rendered else ""
end
local function readable(id,model)
    local n=id:lower()
    if id=="HandCrank" then return "Hand Crank" end
    if id=="Shaft" then return "Round Shaft" end
    local teeth=n:match("^gear_(%d+)t$")
    if teeth then return "Spur Gear  ·  "..teeth.." teeth" end
    local angle,count=n:match("^bevel(%d+)_(%d+)t$")
    if angle then return angle.."° Bevel Gear  ·  "..count.." teeth" end
    local pulley=n:match("^pulley_(%d+)u$")
    if pulley then
        return "Belt Pulley  ·  Ø"..pulley.." U"
    end
    local bolt=n:match("^bolt_(%d+)u$")
    if bolt then
        local d=model:GetAttribute("BoltDiameterU")
        local length=model:GetAttribute("BoltLengthU")
        if type(d)=="number" and type(length)=="number" then
            return "Hex Bolt  ·  Ø"..numberLabel(d).." × "..numberLabel(length).." U"
        end
        -- Historic IDs use thousandths (050 = 0.50 U, 100 = 1.00 U).
        return "Hex Bolt  ·  "..tostring(tonumber(bolt)/100).." U"
    end
    local blockSize,diameter=n:match("^drilledblock_(%d+)u_d(%d+)$")
    if blockSize and diameter then
        return "Drilled Block  ·  "..blockSize.." U / Ø"
            ..tostring(tonumber(diameter)/100).." U"
    end
    if n:find("rectangulartube",1,true) then
        return "Rectangular Tube"..variantSuffix(id,"RectangularTube")
    end
    if n:find("recttube",1,true) then
        return "Rectangular Tube"..variantSuffix(id,"RectTube")
    end
    if n:find("squaretube",1,true) then
        return "Square Tube"..variantSuffix(id,"SquareTube")
    end
    if n:find("halftube",1,true) then
        return "Half-Round Tube"..variantSuffix(id,"HalfTube")
    end
    if n:find("circulartube",1,true) then
        return "Round Tube"..variantSuffix(id,"CircularTube")
    end
    if n=="tube" then return "Round Tube" end
    if n:find("slottedhole",1,true) then
        return "Slotted Hole"..variantSuffix(id,"SlottedHole")
    end
    if n:find("holeblock",1,true) then
        return "Bored Block"..variantSuffix(id,"HoleBlock")
    end
    if n=="block" then return "Solid Block" end
    if n=="plate" or n=="flat" then return "Flat Plate" end
    if n=="cylinder" then return "Solid Cylinder" end
    if n=="slope" or n=="wedge" then return "Wedge" end
    return titleCase(id)
end
function Catalog.Describe(id,sourceFolder,model)
    local category=familyFor(id,sourceFolder,model)
    local custom=model:GetAttribute("CatalogName")
    local title=if type(custom)=="string" and #custom>0 and #custom<=80
        then custom else readable(id,model)
    return {
        DisplayName=title,
        Group=category,
        GroupOrder=RANK[category] or #ORDER,
        -- Keep internal ID searchable for developer debugging.
        SearchText=(title.." "..id.." "..category):lower(),
    }
end
return table.freeze(Catalog)
