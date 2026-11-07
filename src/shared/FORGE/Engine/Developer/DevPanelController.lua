local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')
local Stats = game:GetService('Stats')
local UserInputService = game:GetService('UserInputService')

local FORGE = require(ReplicatedStorage:WaitForChild('FORGE'))

local Controller = FORGE.Controller('ForgeDevPanelController', {
	Priority = 1000,
})

local Player = Players.LocalPlayer
local HISTORY = 120
local SAMPLE_INTERVAL = 0.20

local COLORS = {
	Background = Color3.fromRGB(13, 14, 18),
	Panel = Color3.fromRGB(23, 25, 31),
	Panel2 = Color3.fromRGB(31, 34, 42),
	Text = Color3.fromRGB(235, 238, 245),
	Muted = Color3.fromRGB(148, 154, 168),
	Accent = Color3.fromRGB(111, 210, 164),
	Pulse = Color3.fromRGB(255, 213, 106),
	Line = Color3.fromRGB(68, 73, 86),
}

local function corner(Object, Radius)
	local C = Instance.new('UICorner')
	C.CornerRadius = UDim.new(0, Radius or 6)
	C.Parent = Object
end

local function textLabel(Parent, Text, Size, Bold)
	local Label = Instance.new('TextLabel')
	Label.BackgroundTransparency = 1
	Label.Font = Bold and Enum.Font.GothamBold or Enum.Font.Gotham
	Label.Text = Text or ''
	Label.TextColor3 = COLORS.Text
	Label.TextSize = Size or 13
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.TextYAlignment = Enum.TextYAlignment.Top
	Label.TextWrapped = false
	Label.Parent = Parent
	return Label
end

local function push(History, Value)
	table.insert(History, tonumber(Value) or 0)
	while #History > HISTORY do table.remove(History, 1) end
end

local function maximum(Values, Floor)
	local Max = Floor or 0
	for _, Value in ipairs(Values) do Max = math.max(Max, Value) end
	return Max
end

local function clearTagged(Parent, Tag)
	for _, Child in ipairs(Parent:GetChildren()) do
		if Child:GetAttribute('ForgeDebugTag') == Tag then Child:Destroy() end
	end
end

local function line(Parent, A, B, Thickness, Color, Tag)
	local Delta = B - A
	local Length = Delta.Magnitude
	if Length <= 0.5 then return nil end
	local F = Instance.new('Frame')
	F.AnchorPoint = Vector2.new(0, 0.5)
	F.Position = UDim2.fromOffset(A.X, A.Y)
	F.Size = UDim2.fromOffset(Length, Thickness or 1)
	F.Rotation = math.deg(math.atan2(Delta.Y, Delta.X))
	F.BackgroundColor3 = Color or COLORS.Line
	F.BorderSizePixel = 0
	F:SetAttribute('ForgeDebugTag', Tag)
	F.Parent = Parent
	return F
end

local function drawHistory(Frame, Values, PinnedMin, PinnedMax)
	clearTagged(Frame, 'History')
	if #Values < 2 then return end
	local W, H = Frame.AbsoluteSize.X, Frame.AbsoluteSize.Y
	if W <= 4 or H <= 4 then return end

	local Min, Max = PinnedMin, PinnedMax
	if Min == nil or Max == nil then
		Min, Max = math.huge, -math.huge
		for _, Value in ipairs(Values) do
			Min, Max = math.min(Min, Value), math.max(Max, Value)
		end
		if Max - Min < 1e-4 then Max = Min + 1 end
	end

	local Previous
	for Index, Value in ipairs(Values) do
		local X = (Index - 1) / math.max(#Values - 1, 1) * W
		local Alpha = math.clamp((Value - Min) / math.max(Max - Min, 1e-4), 0, 1)
		local P = Vector2.new(X, H - Alpha * H)
		if Previous then line(Frame, Previous, P, 2, COLORS.Accent, 'History') end
		Previous = P
	end
end

local function memoryBreakdown()
	local Rows = {}
	local Success, Items = pcall(function() return Enum.DeveloperMemoryTag:GetEnumItems() end)
	if not Success then return Rows end
	for _, Tag in ipairs(Items) do
		local Ok, Value = pcall(Stats.GetMemoryUsageMbForTag, Stats, Tag)
		if Ok and type(Value) == 'number' and Value > 0.01 then
			table.insert(Rows, {Name = Tag.Name, Value = Value})
		end
	end
	table.sort(Rows, function(A, B) return A.Value > B.Value end)
	return Rows
end

local function stringify(Value, Depth)
	Depth = Depth or 0
	if Depth > 3 then return '…' end
	if type(Value) ~= 'table' then return tostring(Value) end
	local Keys = {}
	for Key in pairs(Value) do table.insert(Keys, Key) end
	table.sort(Keys, function(A, B) return tostring(A) < tostring(B) end)
	local Out = {}
	for _, Key in ipairs(Keys) do
		table.insert(Out, string.rep('  ', Depth) .. tostring(Key) .. ': ' .. stringify(Value[Key], Depth + 1))
	end
	return table.concat(Out, '\n')
end

function Controller:Init()
	self.Gui = nil
	self.Pages = {}
	self.History = {FPS = {}, Frame = {}, Ping = {}, Memory = {}}
	self.LastFrameDt = 1 / 60
	self.SampleClock = 0
	self.LastActivityId = 0
	self.NodeFrames = {}
	self.PulseUntil = {}
end

function Controller:_MakePage(Name)
	local Page = Instance.new('Frame')
	Page.Name = Name
	Page.BackgroundTransparency = 1
	Page.Size = UDim2.fromScale(1, 1)
	Page.Visible = false
	Page.Parent = self.Content
	self.Pages[Name] = Page
	return Page
end

function Controller:_MetricCard(Parent, Title, Y)
	local Card = Instance.new('Frame')
	Card.Position = UDim2.fromOffset(0, Y)
	Card.Size = UDim2.new(1, 0, 0, 54)
	Card.BackgroundColor3 = COLORS.Panel2
	Card.BorderSizePixel = 0
	corner(Card, 6)
	Card.Parent = Parent

	local T = textLabel(Card, Title, 11, false)
	T.TextColor3 = COLORS.Muted
	T.Position = UDim2.fromOffset(12, 8)
	T.Size = UDim2.new(1, -24, 0, 16)

	local V = textLabel(Card, '--', 20, true)
	V.Position = UDim2.fromOffset(12, 24)
	V.Size = UDim2.new(1, -24, 0, 24)
	return V
end

function Controller:_GraphCard(Parent, Title, Y, Height)
	local Card = Instance.new('Frame')
	Card.Position = UDim2.fromOffset(0, Y)
	Card.Size = UDim2.new(1, 0, 0, Height or 150)
	Card.BackgroundColor3 = COLORS.Panel2
	Card.BorderSizePixel = 0
	corner(Card, 6)
	Card.Parent = Parent
	local T = textLabel(Card, Title, 12, true)
	T.Position = UDim2.fromOffset(10, 8)
	T.Size = UDim2.new(1, -20, 0, 18)
	local Plot = Instance.new('Frame')
	Plot.BackgroundTransparency = 1
	Plot.Position = UDim2.fromOffset(10, 30)
	Plot.Size = UDim2.new(1, -20, 1, -40)
	Plot.ClipsDescendants = true
	Plot.Parent = Card
	return Plot
end

function Controller:_BuildUI()
	local PlayerGui = Player:WaitForChild('PlayerGui')
	local Existing = PlayerGui:FindFirstChild('FORGEDevPanel')
	if Existing then Existing:Destroy() end

	local Gui = Instance.new('ScreenGui')
	Gui.Name = 'FORGEDevPanel'
	Gui.ResetOnSpawn = false
	Gui.IgnoreGuiInset = true
	Gui.DisplayOrder = 10000
	Gui.Enabled = false
	Gui.Parent = PlayerGui
	self.Gui = Gui

	local Main = Instance.new('Frame')
	Main.AnchorPoint = Vector2.new(0.5, 0.5)
	Main.Position = UDim2.fromScale(0.5, 0.5)
	Main.Size = UDim2.fromScale(0.86, 0.82)
	Main.BackgroundColor3 = COLORS.Background
	Main.BorderSizePixel = 0
	corner(Main, 9)
	Main.Parent = Gui

	local Top = Instance.new('Frame')
	Top.Size = UDim2.new(1, 0, 0, 44)
	Top.BackgroundColor3 = COLORS.Panel
	Top.BorderSizePixel = 0
	Top.Parent = Main
	local Title = textLabel(Top, 'FORGE // LIVE RUNTIME', 15, true)
	Title.Position = UDim2.fromOffset(14, 13)
	Title.Size = UDim2.new(0.6, 0, 0, 20)
	local Hint = textLabel(Top, 'F8 to toggle', 11, false)
	Hint.TextColor3 = COLORS.Muted
	Hint.TextXAlignment = Enum.TextXAlignment.Right
	Hint.Position = UDim2.new(1, -160, 0, 14)
	Hint.Size = UDim2.fromOffset(145, 18)

	local Nav = Instance.new('Frame')
	Nav.Position = UDim2.fromOffset(0, 44)
	Nav.Size = UDim2.new(0, 150, 1, -44)
	Nav.BackgroundColor3 = COLORS.Panel
	Nav.BorderSizePixel = 0
	Nav.Parent = Main

	self.Content = Instance.new('Frame')
	self.Content.Position = UDim2.fromOffset(164, 58)
	self.Content.Size = UDim2.new(1, -178, 1, -72)
	self.Content.BackgroundTransparency = 1
	self.Content.ClipsDescendants = true
	self.Content.Parent = Main

	local PageNames = {'Overview','Performance','Memory','Network','FORGE','Combat'}
	for Index, Name in ipairs(PageNames) do
		local Button = Instance.new('TextButton')
		Button.Position = UDim2.fromOffset(10, 12 + (Index - 1) * 38)
		Button.Size = UDim2.new(1, -20, 0, 30)
		Button.BackgroundColor3 = COLORS.Panel2
		Button.BorderSizePixel = 0
		Button.AutoButtonColor = false
		Button.Font = Enum.Font.GothamMedium
		Button.Text = Name
		Button.TextColor3 = COLORS.Text
		Button.TextSize = 12
		corner(Button, 5)
		Button.Parent = Nav
		Button.MouseButton1Click:Connect(function() self:_ShowPage(Name) end)
	end

	local Overview = self:_MakePage('Overview')
	self.OverviewFPS = self:_MetricCard(Overview, 'FPS', 0)
	self.OverviewFrame = self:_MetricCard(Overview, 'FRAME TIME', 62)
	self.OverviewPing = self:_MetricCard(Overview, 'PING', 124)
	self.OverviewMemory = self:_MetricCard(Overview, 'MEMORY', 186)
	self.OverviewStatus = textLabel(Overview, '', 12, false)
	self.OverviewStatus.Position = UDim2.fromOffset(0, 254)
	self.OverviewStatus.Size = UDim2.new(1, 0, 1, -254)
	self.OverviewStatus.TextColor3 = COLORS.Muted

	local Perf = self:_MakePage('Performance')
	self.FPSGraph = self:_GraphCard(Perf, 'FPS // last 24s', 0, 180)
	self.FrameGraph = self:_GraphCard(Perf, 'FRAME MS // last 24s', 190, 180)

	local Memory = self:_MakePage('Memory')
	self.MemoryGraph = self:_GraphCard(Memory, 'TOTAL MEMORY MB // last 24s', 0, 170)
	self.MemoryText = textLabel(Memory, '', 12, false)
	self.MemoryText.Position = UDim2.fromOffset(0, 182)
	self.MemoryText.Size = UDim2.new(1, 0, 1, -182)
	self.MemoryText.TextColor3 = COLORS.Muted

	local Network = self:_MakePage('Network')
	self.PingGraph = self:_GraphCard(Network, 'PING MS // last 24s', 0, 180)
	self.NetworkText = textLabel(Network, '', 12, false)
	self.NetworkText.Position = UDim2.fromOffset(0, 192)
	self.NetworkText.Size = UDim2.new(1, 0, 1, -192)
	self.NetworkText.TextColor3 = COLORS.Muted

	local Forge = self:_MakePage('FORGE')
	self.Neuron = Instance.new('Frame')
	self.Neuron.Size = UDim2.new(1, 0, 1, -32)
	self.Neuron.BackgroundColor3 = COLORS.Panel2
	self.Neuron.BorderSizePixel = 0
	self.Neuron.ClipsDescendants = true
	corner(self.Neuron, 6)
	self.Neuron.Parent = Forge
	local ForgeHint = textLabel(Forge, 'Live graph — nodes brighten when real FORGE activity fires.', 11, false)
	ForgeHint.TextColor3 = COLORS.Muted
	ForgeHint.Position = UDim2.new(0, 2, 1, -24)
	ForgeHint.Size = UDim2.new(1, -4, 0, 20)

	local Combat = self:_MakePage('Combat')
	self.CombatText = textLabel(Combat, 'Combat provider unavailable in this place.', 12, false)
	self.CombatText.Size = UDim2.fromScale(1, 1)
	self.CombatText.TextColor3 = COLORS.Muted

	self:_ShowPage('Overview')
end

function Controller:_ShowPage(Name)
	for PageName, Page in pairs(self.Pages) do Page.Visible = PageName == Name end
end

function Controller:_BuildNeuron(Snapshot)
	clearTagged(self.Neuron, 'Neuron')
	table.clear(self.NodeFrames)

	local Nodes = {}
	local Seen = {}
	local function addNode(Name, Kind, Requires)
		if Seen[Name] then return end
		Seen[Name] = true
		table.insert(Nodes, {Name=Name, Kind=Kind, Requires=Requires or {}})
	end

	for _, Node in ipairs(Snapshot.Graph or {}) do addNode(Node.Name, Node.Kind, Node.Requires) end
	for _, Name in ipairs((Snapshot.Network and Snapshot.Network.ServiceNames) or {}) do addNode(Name, 'ServiceProxy') end
	addNode('Network','Kernel')

	table.sort(Nodes, function(A,B)
		if A.Kind == B.Kind then return A.Name < B.Name end
		return A.Kind < B.Kind
	end)

	local W = math.max(self.Neuron.AbsoluteSize.X, 500)
	local H = math.max(self.Neuron.AbsoluteSize.Y, 300)
	local Positions = {}
	for I, Node in ipairs(Nodes) do
		local Angle = ((I - 1) / math.max(#Nodes,1)) * math.pi * 2 - math.pi/2
		Positions[Node.Name] = Vector2.new(
			W/2 + math.cos(Angle) * W * 0.38,
			H/2 + math.sin(Angle) * H * 0.36
		)
	end

	for _, Node in ipairs(Nodes) do
		for _, Req in ipairs(Node.Requires or {}) do
			if Positions[Req] then line(self.Neuron, Positions[Req], Positions[Node.Name], 1, COLORS.Line, 'Neuron') end
		end
	end
	for _, Service in ipairs((Snapshot.Network and Snapshot.Network.ServiceNames) or {}) do
		if Positions.Network and Positions[Service] then
			line(self.Neuron, Positions.Network, Positions[Service], 1, COLORS.Line, 'Neuron')
		end
	end

	for _, Node in ipairs(Nodes) do
		local P = Positions[Node.Name]
		local F = Instance.new('Frame')
		F.Name = Node.Name
		F.AnchorPoint = Vector2.new(0.5,0.5)
		F.Position = UDim2.fromOffset(P.X,P.Y)
		F.Size = UDim2.fromOffset(math.clamp(70 + #Node.Name*3, 82, 145), 28)
		F.BackgroundColor3 = COLORS.Panel
		F.BorderSizePixel = 0
		F:SetAttribute('ForgeDebugTag','Neuron')
		corner(F, 14)
		F.Parent = self.Neuron
		local L = textLabel(F, Node.Name, 10, true)
		L.TextXAlignment = Enum.TextXAlignment.Center
		L.TextYAlignment = Enum.TextYAlignment.Center
		L.Size = UDim2.fromScale(1,1)
		self.NodeFrames[Node.Name] = F
	end
end

function Controller:_Pulse(Name)
	if Name == nil then return end
	Name = tostring(Name)
	if self.NodeFrames[Name] then self.PulseUntil[Name] = os.clock() + 0.42 return end
	for NodeName in pairs(self.NodeFrames) do
		if string.find(string.lower(Name), string.lower(NodeName), 1, true) then
			self.PulseUntil[NodeName] = os.clock() + 0.42
			return
		end
	end
end

function Controller:_UpdateNeuron(Snapshot)
	if not next(self.NodeFrames) then self:_BuildNeuron(Snapshot) end
	for _, Entry in ipairs((Snapshot.Tooling and Snapshot.Tooling.Activity) or {}) do
		if (Entry.Id or 0) > self.LastActivityId then
			self.LastActivityId = math.max(self.LastActivityId, Entry.Id or 0)
			self:_Pulse(Entry.Source)
			self:_Pulse(Entry.Target)
		end
	end
	local Now = os.clock()
	for Name, Frame in pairs(self.NodeFrames) do
		Frame.BackgroundColor3 = (self.PulseUntil[Name] or 0) > Now and COLORS.Pulse or COLORS.Panel
	end
end

function Controller:_Sample()
	local FPS = self.LastFrameDt > 0 and 1 / self.LastFrameDt or 0
	local FrameMs = self.LastFrameDt * 1000
	local PingMs = 0
	pcall(function() PingMs = Player:GetNetworkPing() * 1000 end)
	local MemoryMb = 0
	pcall(function() MemoryMb = Stats:GetTotalMemoryUsageMb() end)

	push(self.History.FPS, FPS)
	push(self.History.Frame, FrameMs)
	push(self.History.Ping, PingMs)
	push(self.History.Memory, MemoryMb)

	local Snapshot = FORGE.Diagnostics:Snapshot()
	self.LastSnapshot = Snapshot

	self.OverviewFPS.Text = string.format('%.0f', FPS)
	self.OverviewFrame.Text = string.format('%.2f ms', FrameMs)
	self.OverviewPing.Text = string.format('%.1f ms', PingMs)
	self.OverviewMemory.Text = string.format('%.1f MB', MemoryMb)
	self.OverviewStatus.Text = string.format(
		'FORGE %s\n%s / %s\n%d components\nnetwork: %s • %d services\nhealth: %s',
		tostring(Snapshot.Version),
		tostring(Snapshot.Context and Snapshot.Context.Environment),
		tostring(Snapshot.Context and Snapshot.Context.Side),
		#(Snapshot.Components or {}),
		Snapshot.Network and Snapshot.Network.Active and 'online' or 'offline',
		Snapshot.Network and Snapshot.Network.Services or 0,
		Snapshot.Health and Snapshot.Health.Healthy and 'healthy' or 'issues detected'
	)

	if not self.Gui.Enabled then return end

	drawHistory(self.FPSGraph, self.History.FPS, 0, 120)
	drawHistory(self.FrameGraph, self.History.Frame, 0, 35)
	drawHistory(self.PingGraph, self.History.Ping, 0, maximum(self.History.Ping, 120))
	drawHistory(self.MemoryGraph, self.History.Memory)

	local Rows, Text = memoryBreakdown(), {}
	for I = 1, math.min(#Rows, 18) do
		table.insert(Text, string.format('%-24s %8.2f MB', Rows[I].Name, Rows[I].Value))
	end
	self.MemoryText.Text = table.concat(Text, '\n')

	local N = Snapshot.Network or {}
	local S = N.Stats or {}
	self.NetworkText.Text = string.format(
		'Active: %s\nServices: %d\nRPC: %s\nEvents: %s\nInbound: %s\nRefreshes: %s',
		tostring(N.Active), tonumber(N.Services) or 0,
		tostring(S.RPC or 0), tostring(S.Events or 0),
		tostring(S.Inbound or 0), tostring(S.Refreshes or 0)
	)

	local Provider = Snapshot.Tooling and Snapshot.Tooling.Providers and Snapshot.Tooling.Providers.Combat
	self.CombatText.Text = Provider and stringify(Provider) or 'Combat provider unavailable in this place.'
	self:_UpdateNeuron(Snapshot)
end

function Controller:Start()
	if not FORGE.IsStudio then return end
	self:_BuildUI()

	self:Connect(UserInputService.InputBegan, function(Input, Processed)
		if Processed then return end
		if Input.KeyCode == Enum.KeyCode.F8 then
			self.Gui.Enabled = not self.Gui.Enabled
			if self.Gui.Enabled and self.LastSnapshot then self:_BuildNeuron(self.LastSnapshot) end
		end
	end)

	self:Connect(RunService.RenderStepped, function(Dt)
		self.LastFrameDt = Dt
		self.SampleClock += Dt
		if self.SampleClock >= SAMPLE_INTERVAL then
			self.SampleClock -= SAMPLE_INTERVAL
			self:_Sample()
		end
	end)

	self:_Sample()
	FORGE.Tooling:Pulse('ForgeDevPanelController','Started')
end

function Controller:Destroy()
	if self.Gui then self.Gui:Destroy(); self.Gui=nil end
end

return Controller
