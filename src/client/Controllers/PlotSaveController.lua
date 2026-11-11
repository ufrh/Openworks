--!strict
-- Manual save UI: opening this panel DOES NOT save; only pressing SAVE does.
-- The server loads the most recent explicitly saved plot on join.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local UserInputService=game:GetService("UserInputService")
local Theme=require(script.Parent:WaitForChild("StudioTheme"))

local player=Players.LocalPlayer
local remote=ReplicatedStorage:WaitForChild("OPENWORKS_ConstructionRequest")
local UI={}
UI.__index=UI

local BG=Theme.Window
local PANEL=Theme.Raised
local TEXT=Theme.Text
local MUTED=Theme.Muted
local ACCENT=Theme.Accent

local function make(class,parent,props)
    local object=Instance.new(class)
    for name,value in pairs(props or {}) do object[name]=value end
    object.Parent=parent
    return object
end

local function round(object,n)
    make("UICorner",object,{CornerRadius=UDim.new(0,Theme.Radius)})
    return object
end

local function text(parent,value,y,h,size,bold,color)
    return make("TextLabel",parent,{
        Position=UDim2.fromOffset(16,y),Size=UDim2.new(1,-32,0,h),
        BackgroundTransparency=1,Text=value,
        Font=if bold then Enum.Font.GothamBold else Enum.Font.Gotham,
        TextColor3=color or TEXT,TextSize=size or 12,
        TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Center,
        ZIndex=4,
    })
end

local function button(parent,value,y,color)
    local b=round(make("TextButton",parent,{
        Position=UDim2.fromOffset(16,y),Size=UDim2.new(1,-32,0,40),
        BackgroundColor3=color or PANEL,BorderSizePixel=0,
        Text=value,TextColor3=TEXT,TextSize=13,
        Font=Enum.Font.GothamBold,AutoButtonColor=true,ZIndex=4,
    }),7)
    return b
end

function UI.new()
    return setmetatable({Open=false,Busy=false,Confirm=false,
        Connections={}},UI)
end

function UI:Refresh()
    if not self.Gui then return end
    local slot=player:GetAttribute("OPENWORKS_PlotIndex")
    local state=player:GetAttribute("OPENWORKS_SaveState") or "Loading"
    local saved=player:GetAttribute("OPENWORKS_LastSavedAt") or 0
    self.Toggle.Text="PLOT "..tostring(slot or "—").."  /  F6"
    self.Toggle.Visible=player:GetAttribute("OPENWORKS_ActiveTool")~="Simulate"
        or self.Open
    local message=player:GetAttribute("OPENWORKS_SaveMessage") or ""
    local stamp=if type(saved)=="number" and saved>0
        then os.date("%b %d  •  %I:%M %p",saved)
        else "Never saved"
    self.Saved.Text="LAST MANUAL SAVE  /  "..stamp
    self.State.Text=if self.Busy then "WORKING..."
        else string.upper(state).."  ·  "..message
    self.State.TextColor3=if state=="Error" then Color3.fromRGB(251,140,124)
        elseif state=="Ready" then Color3.fromRGB(124,219,192) else MUTED
    self.Save.Text=if self.Busy then "SAVING / LOADING…"
        else "SAVE PLOT"
    self.Save.Active=state=="Ready" and not self.Busy
    self.Save.AutoButtonColor=state=="Ready" and not self.Busy
    self.Save.BackgroundColor3=if self.Save.Active then ACCENT else PANEL
    self.Load.Text=if self.Confirm then "CONFIRM RELOAD  /  DISCARD UNSAVED"
        elseif state=="Error" then "RETRY STORAGE / LOAD PLOT"
        else "LOAD LAST MANUAL SAVE"
    self.Load.Active=(state=="Ready" or state=="Error") and not self.Busy
    self.Load.AutoButtonColor=self.Load.Active
end

function UI:Show(enabled)
    self.Open=enabled
    self.Confirm=false
    player:SetAttribute("OPENWORKS_PlotMenuOpen",enabled)
    self.Panel.Visible=enabled
    self.Backdrop.Visible=enabled
    self:Refresh()
    if enabled then
        UserInputService.MouseBehavior=Enum.MouseBehavior.Default
        UserInputService.MouseIconEnabled=true
    elseif player:GetAttribute("OPENWORKS_PropertiesOpen")~=true then
        UserInputService.MouseBehavior=Enum.MouseBehavior.LockCenter
        UserInputService.MouseIconEnabled=false
    end
end

function UI:Request(action)
    if self.Busy then return end
    local state=player:GetAttribute("OPENWORKS_SaveState")
    if state~="Ready" and not (action=="LoadPlot" and state=="Error") then
        self.State.Text="STORAGE NOT READY  /  RETRY LOADING"
        return
    end
    self.Busy=true
    self.Confirm=false
    self:Refresh()
    local ok,result=pcall(function()
        return remote:InvokeServer({action=action})
    end)
    self.Busy=false
    if not ok then
        self.State.Text="REQUEST ERROR  /  "..tostring(result)
        self.State.TextColor3=Color3.fromRGB(251,140,124)
    elseif type(result)=="table" and result.ok==true then
        self:Refresh()
        self.State.Text=tostring(result.message or "Complete")
    else
        self:Refresh()
        self.State.Text=tostring(
            type(result)=="table" and result.message or result)
        self.State.TextColor3=Color3.fromRGB(251,140,124)
    end
end

function UI:Start()
    local gui=make("ScreenGui",player:WaitForChild("PlayerGui"),{
        Name="OPENWORKS_ManualPlotSave",ResetOnSpawn=false,
        IgnoreGuiInset=true,DisplayOrder=97,
        ZIndexBehavior=Enum.ZIndexBehavior.Sibling,
    })
    self.Gui=gui
    local opener=round(make("TextButton",gui,{
        Name="PlotMenuButton",Position=UDim2.fromOffset(14,18),
        Size=UDim2.fromOffset(140,32),Text="PLOT  /  F6",
        BackgroundColor3=BG,BackgroundTransparency=0.03,
        TextColor3=TEXT,TextSize=12,Font=Enum.Font.GothamBold,
        BorderSizePixel=0,ZIndex=2,
    }),7)
    self.Toggle=opener
    local overlay=make("TextButton",gui,{
        Name="UnlockAndDismiss",Size=UDim2.fromScale(1,1),
        BackgroundTransparency=1,Text="",Modal=true,Visible=false,
        ZIndex=2,
    })
    self.Backdrop=overlay
    local panel=round(make("Frame",gui,{
        Name="ManualPersistencePanel",
        Position=UDim2.fromOffset(14,60),Size=UDim2.fromOffset(302,254),
        BackgroundColor3=BG,BackgroundTransparency=0.02,
        BorderSizePixel=0,Visible=false,ZIndex=3,
    }),10)
    self.Panel=panel
    text(panel,"MY PLOT  /  MANUAL PERSISTENCE",11,26,13,true)
    text(panel,"No autosaving. Only SAVE PLOT writes your work.",39,35,12,false,MUTED)
    self.Save=button(panel,"SAVE PLOT",83,ACCENT)
    self.Load=button(panel,"LOAD LAST MANUAL SAVE",133,PANEL)
    self.Saved=text(panel,"LAST MANUAL SAVE  /  Never saved",184,22,11,false,MUTED)
    self.State=text(panel,"LOADING PLOT…",208,36,11,false,MUTED)

    opener.Activated:Connect(function() self:Show(not self.Open) end)
    overlay.Activated:Connect(function() self:Show(false) end)
    self.Save.Activated:Connect(function() self:Request("SavePlot") end)
    self.Load.Activated:Connect(function()
        if self.Busy then return end
        if not self.Confirm then
            self.Confirm=true
            self:Refresh()
        else
            self:Request("LoadPlot")
        end
    end)
    table.insert(self.Connections,Theme.Attach(gui))
    for _,name in ipairs({"OPENWORKS_PlotIndex","OPENWORKS_SaveState",
        "OPENWORKS_SaveMessage","OPENWORKS_LastSavedAt",
        "OPENWORKS_ActiveTool"}) do
        table.insert(self.Connections,
            player:GetAttributeChangedSignal(name):Connect(function()
                self:Refresh()
            end))
    end
    table.insert(self.Connections,
        UserInputService.InputBegan:Connect(function(input,processed)
            if processed or UserInputService:GetFocusedTextBox() then return end
            if input.KeyCode==Enum.KeyCode.F6 then
                self:Show(not self.Open)
            elseif input.KeyCode==Enum.KeyCode.Escape and self.Open then
                self:Show(false)
            end
        end))
    self:Refresh()
end

return UI
