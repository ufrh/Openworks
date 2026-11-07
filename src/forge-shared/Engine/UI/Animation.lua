local TweenService = game:GetService('TweenService')
local Signal = require(script.Parent.Parent.Parent.Kernel.Core.Signal)

local Animation = {} do
	Animation.__index = Animation

	function Animation.new(Duration, EasingStyle, EasingDirection)
		local self = setmetatable({}, Animation)
		self.Duration = Duration or .25
		self.EasingStyle = EasingStyle or Enum.EasingStyle.Quad
		self.EasingDirection = EasingDirection or Enum.EasingDirection.Out
		self.RepeatCount = 0
		self.Reverses = false
		self.DelayTime = 0
		self.Tracks = {}
		self.Active = {}
		self.Baselines = {}
		self.OnStarted = Signal.new()
		self.OnCompleted = Signal.new()
		self.OnStopped = Signal.new()
		return self
	end

	function Animation:SetPlayback(RepeatCount, Reverses, DelayTime)
		self.RepeatCount = RepeatCount or 0
		self.Reverses = Reverses == true
		self.DelayTime = DelayTime or 0
		return self
	end

	function Animation:AddTrack(Target, Goals, StartTime, Duration, EasingStyle, EasingDirection)
		table.insert(self.Tracks, {
			Target = Target, Goals = Goals, StartTime = StartTime or 0, Duration = Duration,
			EasingStyle = EasingStyle, EasingDirection = EasingDirection
		})
		return self
	end

	function Animation:_CompleteTrack(Owner, Session)
		if self.Active[Owner] ~= Session or Session.Cancelled then return end
		Session.Remaining -= 1
		if Session.Remaining > 0 then return end
		self.Active[Owner] = nil
		self.OnCompleted:Fire(Owner)
	end

	function Animation:Play(Owner, PlaybackSpeed, Reverse)
		self:Stop(Owner, false)
		local Speed = math.max(PlaybackSpeed or 1, .001)
		local Session = {Tweens = {}, Connections = {}, Cancelled = false, Remaining = #self.Tracks}
		self.Active[Owner] = Session
		self.Baselines[Owner] = self.Baselines[Owner] or {}
		self.OnStarted:Fire(Owner, Reverse == true)

		if Session.Remaining == 0 then
			self.Active[Owner] = nil
			self.OnCompleted:Fire(Owner)
			return Session
		end

		for Index, Track in ipairs(self.Tracks) do
			local Delay = (Track.StartTime + self.DelayTime) / Speed
			local function StartTrack()
				if self.Active[Owner] ~= Session or Session.Cancelled then return end
				local Target = Track.Target
				if type(Target) == 'function' then Target = Target(Owner) end
				if type(Target) == 'table' and Target.Object then Target = Target.Object end
				if typeof(Target) ~= 'Instance' then
					self:_CompleteTrack(Owner, Session)
					return
				end

				local Goals = Track.Goals
				if type(Goals) == 'function' then
					Goals = Goals(Owner, Reverse == true, Index)
				elseif Reverse == true then
					Goals = self.Baselines[Owner][Index] or Goals
				else
					local Baseline = {}
					for Property in pairs(Goals) do
						local Success, Value = pcall(function() return Target[Property] end)
						if Success then Baseline[Property] = Value end
					end
					self.Baselines[Owner][Index] = Baseline
				end
				if type(Goals) ~= 'table' or next(Goals) == nil then
					self:_CompleteTrack(Owner, Session)
					return
				end
				local Info = TweenInfo.new(
					(Track.Duration or self.Duration) / Speed,
					Track.EasingStyle or self.EasingStyle,
					Track.EasingDirection or self.EasingDirection,
					self.RepeatCount, self.Reverses, 0
				)
				local Tween = TweenService:Create(Target, Info, Goals)
				table.insert(Session.Tweens, Tween)

				local Connection
				Connection = Tween.Completed:Connect(function()
					if Connection then Connection:Disconnect() end
					self:_CompleteTrack(Owner, Session)
				end)
				table.insert(Session.Connections, Connection)
				Tween:Play()
			end

			if Delay > 0 then task.delay(Delay, StartTrack) else StartTrack() end
		end
		return Session
	end

	function Animation:IsPlaying(Owner)
		return self.Active[Owner] ~= nil
	end

	function Animation:Stop(Owner, FireSignal)
		local Session = self.Active[Owner]
		if not Session then return self end
		self.Active[Owner] = nil
		Session.Cancelled = true
		for _, Connection in ipairs(Session.Connections or {}) do Connection:Disconnect() end
		for _, Tween in ipairs(Session.Tweens) do Tween:Cancel() end
		if FireSignal ~= false then self.OnStopped:Fire(Owner) end
		return self
	end

	function Animation:Destroy()
		for Owner in pairs(self.Active) do self:Stop(Owner, false) end
		self.OnStarted:Destroy()
		self.OnCompleted:Destroy()
		self.OnStopped:Destroy()
		table.clear(self.Tracks)
		table.clear(self.Baselines)
	end
end

return Animation;