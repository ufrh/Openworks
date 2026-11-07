local Tooling = {
	Metrics = {},
	Traces = {},
	Tests = {},
	Providers = {},
	Activity = {},
	TraceLimit = 250,
	ActivityLimit = 500,
	NextActivityId = 0,
}

local Metric = {} do
	Metric.__index = Metric
	Metric.ClassName = 'Metric'

	function Metric.new(Name)
		return setmetatable({
			Name = Name,
			Value = 0,
			Count = 0,
			Sum = 0,
			Min = nil,
			Max = nil,
			Last = nil
		}, Metric)
	end

	function Metric:Add(Amount)
		Amount = tonumber(Amount) or 1
		self.Value += Amount
		self:Observe(Amount)
		return self.Value
	end

	function Metric:Set(Value)
		Value = tonumber(Value) or 0
		self.Value = Value
		self:Observe(Value)
		return self.Value
	end

	function Metric:Observe(Value)
		Value = tonumber(Value)
		if not Value then return self end

		self.Count += 1
		self.Sum += Value
		self.Last = Value
		self.Min = self.Min == nil and Value or math.min(self.Min, Value)
		self.Max = self.Max == nil and Value or math.max(self.Max, Value)
		return self
	end

	function Metric:Reset()
		self.Value = 0
		self.Count = 0
		self.Sum = 0
		self.Min = nil
		self.Max = nil
		self.Last = nil
		return self
	end

	function Metric:Snapshot()
		return {
			Name = self.Name,
			Value = self.Value,
			Count = self.Count,
			Sum = self.Sum,
			Min = self.Min,
			Max = self.Max,
			Last = self.Last,
			Average = self.Count > 0 and self.Sum / self.Count or 0
		}
	end
end

local TestContext = {} do
	TestContext.__index = TestContext

	local function fail(Message)
		error(Message or 'assertion failed', 3)
	end

	function TestContext.new(Name)
		return setmetatable({Name = Name, Assertions = 0}, TestContext)
	end

	function TestContext:Equal(Actual, Expected, Message)
		self.Assertions += 1
		if Actual ~= Expected then
			fail(Message or string.format('expected %s, got %s', tostring(Expected), tostring(Actual)))
		end
		return Actual
	end

	function TestContext:Truthy(Value, Message)
		self.Assertions += 1
		if not Value then fail(Message or 'expected truthy value') end
		return Value
	end

	function TestContext:Falsy(Value, Message)
		self.Assertions += 1
		if Value then fail(Message or 'expected falsy value') end
		return Value
	end

	function TestContext:Near(Actual, Expected, Epsilon, Message)
		self.Assertions += 1
		Epsilon = tonumber(Epsilon) or 1e-5
		if math.abs(Actual - Expected) > Epsilon then
			fail(Message or string.format('expected %s within %s of %s', tostring(Actual), tostring(Epsilon), tostring(Expected)))
		end
		return Actual
	end

	function TestContext:Type(Value, Expected, Message)
		self.Assertions += 1
		local Actual = typeof(Value)
		if Actual ~= Expected then fail(Message or string.format('expected type %s, got %s', Expected, Actual)) end
		return Value
	end

	function TestContext:Throws(Callback, Message)
		self.Assertions += 1
		local Success = pcall(Callback)
		if Success then fail(Message or 'expected callback to throw') end
		return true
	end

	function TestContext:NoError(Callback, Message)
		self.Assertions += 1
		local Success, Result = pcall(Callback)
		if not Success then fail(Message or tostring(Result)) end
		return Result
	end
end

local Simulate = {} do
	local Actor = {}
	Actor.__index = Actor

	function Actor.new(Index, Options)
		Options = Options or {}
		return setmetatable({
			UserId = Options.UserId or -Index,
			Name = Options.Name or ('Synthetic' .. tostring(Index)),
			DisplayName = Options.DisplayName or Options.Name or ('Synthetic ' .. tostring(Index)),
			Attributes = {},
			Data = Options.Data or {},
			Synthetic = true
		}, Actor)
	end

	function Actor:GetAttribute(Name)
		return self.Attributes[Name]
	end

	function Actor:SetAttribute(Name, Value)
		self.Attributes[Name] = Value
	end

	function Simulate.Players(Count, Factory)
		Count = math.max(math.floor(tonumber(Count) or 0), 0)
		local Result = {}

		for Index = 1, Count do
			local Options = type(Factory) == 'function' and Factory(Index) or nil
			Result[Index] = Actor.new(Index, Options)
		end

		return Result
	end

	function Simulate.Run(Name, Callback, Options)
		assert(type(Name) == 'string' and Name ~= '', 'FORGE.Simulate.Run requires a name.')
		assert(type(Callback) == 'function', 'FORGE.Simulate.Run requires a callback.')

		Options = Options or {}
		local Context = {
			Name = Name,
			Players = Simulate.Players(Options.Players or 0, Options.PlayerFactory),
			Options = Options,
			StartedAt = os.clock()
		}

		local Success, Result = xpcall(function()
			return Callback(Context)
		end, debug.traceback)

		return {
			Name = Name,
			Success = Success,
			Result = Success and Result or nil,
			Error = Success and nil or tostring(Result),
			Duration = os.clock() - Context.StartedAt,
			Players = #Context.Players
		}
	end
end

Tooling.Simulate = Simulate

function Tooling:Metric(Name)
	assert(type(Name) == 'string' and Name ~= '', 'FORGE.Metric requires a name.')
	local Existing = self.Metrics[Name]
	if Existing then return Existing end

	local Created = Metric.new(Name)
	self.Metrics[Name] = Created
	return Created
end

function Tooling:Pulse(Source, Kind, Target, Fields)
	self.NextActivityId += 1
	local Entry = {
		Id = self.NextActivityId,
		Source = tostring(Source or 'Runtime'),
		Kind = tostring(Kind or 'Activity'),
		Target = Target ~= nil and tostring(Target) or nil,
		Fields = type(Fields) == 'table' and table.clone(Fields) or {},
		At = os.clock(),
	}

	table.insert(self.Activity, Entry)
	while #self.Activity > self.ActivityLimit do table.remove(self.Activity, 1) end
	self:Metric('Activity.' .. Entry.Kind):Add(1)
	return Entry
end

function Tooling:RegisterProvider(Name, Callback)
	assert(type(Name) == 'string' and Name ~= '', 'FORGE debug provider requires a name.')
	assert(type(Callback) == 'function', 'FORGE debug provider requires a callback.')
	self.Providers[Name] = Callback
	self:Pulse(Name, 'ProviderRegistered')
	return Callback
end

function Tooling:UnregisterProvider(Name)
	if self.Providers[Name] == nil then return false end
	self.Providers[Name] = nil
	self:Pulse(Name, 'ProviderUnregistered')
	return true
end

function Tooling:BeginTrace(Name, Fields)
	assert(type(Name) == 'string' and Name ~= '', 'FORGE.Trace requires a name.')

	local Span = {
		Name = Name,
		Fields = type(Fields) == 'table' and table.clone(Fields) or {},
		StartedAt = os.clock(),
		Finished = false
	}

	function Span:Finish(Success, Error)
		if self.Finished then return self end
		self.Finished = true
		self.Success = Success ~= false
		self.Error = Error and tostring(Error) or nil
		self.Duration = os.clock() - self.StartedAt

		table.insert(Tooling.Traces, {
			Name = self.Name,
			Fields = self.Fields,
			StartedAt = self.StartedAt,
			Duration = self.Duration,
			Success = self.Success,
			Error = self.Error
		})

		while #Tooling.Traces > Tooling.TraceLimit do table.remove(Tooling.Traces, 1) end
		Tooling:Metric('Trace.' .. self.Name .. '.Duration'):Observe(self.Duration * 1000)
		if not self.Success then Tooling:Metric('Trace.' .. self.Name .. '.Errors'):Add(1) end
		return self
	end

	return Span
end

function Tooling:Trace(Name, Callback, Fields, ...)
	if type(Callback) ~= 'function' then return self:BeginTrace(Name, Callback) end

	local Span = self:BeginTrace(Name, Fields)
	local Packed = table.pack(xpcall(function(...)
		return Callback(...)
	end, debug.traceback, ...))

	local Success = Packed[1]
	if not Success then
		Span:Finish(false, Packed[2])
		error(Packed[2], 2)
	end

	Span:Finish(true)
	for Index = 1, Packed.n - 1 do Packed[Index] = Packed[Index + 1] end
	Packed.n -= 1
	return table.unpack(Packed, 1, Packed.n)
end

function Tooling:RegisterTest(Name, Callback, Options)
	assert(type(Name) == 'string' and Name ~= '', 'FORGE.Test requires a name.')
	assert(type(Callback) == 'function', 'FORGE.Test requires a callback.')

	self.Tests[Name] = {
		Name = Name,
		Callback = Callback,
		Options = type(Options) == 'table' and table.clone(Options) or {},
		Last = nil
	}

	return self.Tests[Name]
end

function Tooling:RunTests(Filter)
	local Names = {}
	for Name in pairs(self.Tests) do
		if not Filter or string.find(string.lower(Name), string.lower(Filter), 1, true) then table.insert(Names, Name) end
	end
	table.sort(Names)

	local Report = {
		Total = #Names,
		Passed = 0,
		Failed = 0,
		Duration = 0,
		Results = {}
	}

	for _, Name in ipairs(Names) do
		local Definition = self.Tests[Name]
		local Context = TestContext.new(Name)
		local Started = os.clock()

		local Success, Error = xpcall(function()
			return Definition.Callback(Context)
		end, debug.traceback)

		local Result = {
			Name = Name,
			Passed = Success,
			Error = Success and nil or tostring(Error),
			Assertions = Context.Assertions,
			Duration = os.clock() - Started
		}

		Definition.Last = Result
		Report.Duration += Result.Duration
		if Success then Report.Passed += 1 else Report.Failed += 1 end
		table.insert(Report.Results, Result)
	end

	self:Metric('Tests.Runs'):Add(1)
	self:Metric('Tests.Failures'):Add(Report.Failed)
	return Report
end

function Tooling:Snapshot()
	local Metrics = {}
	for Name, Value in pairs(self.Metrics) do Metrics[Name] = Value:Snapshot() end

	local Tests = {}
	for Name, Definition in pairs(self.Tests) do
		Tests[Name] = {
			Registered = true,
			Last = Definition.Last
		}
	end

	local Providers = {}
	for Name, Callback in pairs(self.Providers) do
		local Success, Value = pcall(Callback)
		Providers[Name] = Success and Value or {Error = tostring(Value)}
	end

	return {
		Metrics = Metrics,
		Traces = table.clone(self.Traces),
		Activity = table.clone(self.Activity),
		Providers = Providers,
		Tests = Tests
	}
end

function Tooling:Reset()
	for _, MetricObject in pairs(self.Metrics) do MetricObject:Reset() end
	table.clear(self.Traces)
	table.clear(self.Activity)
	table.clear(self.Providers)
	for _, Definition in pairs(self.Tests) do Definition.Last = nil end
end

return Tooling
