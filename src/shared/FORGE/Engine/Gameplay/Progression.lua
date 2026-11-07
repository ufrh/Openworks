local Progression = {} do
	local function integer(Value, Default)
		Value = tonumber(Value)
		if not Value or Value ~= Value then
			return Default or 0;
		end
		return math.floor(Value);
	end

	local function config(Config)
		Config = Config or {}
		local Curve = Config.Curve or {}
		return {
			MaxLevel = math.max(integer(Config.MaxLevel, 100), 1);
			Base = math.max(tonumber(Curve.Base) or 450, 1);
			Linear = math.max(tonumber(Curve.Linear) or 90, 0);
			Power = math.max(tonumber(Curve.Power) or 18, 0);
			Exponent = math.max(tonumber(Curve.Exponent) or 1.35, 1);
		};
	end

	function Progression.RequiredXP(Level, Config)
		local Settings = config(Config)
		Level = math.clamp(integer(Level, 1), 1, Settings.MaxLevel)
		if Level >= Settings.MaxLevel then
			return 0;
		end

		local Index = Level - 1
		return math.max(1, math.floor(
			Settings.Base +
			Settings.Linear * Index +
			Settings.Power * (Index ^ Settings.Exponent) +
			.5
		));
	end

	function Progression.TotalForLevel(Level, Config)
		local Settings = config(Config)
		Level = math.clamp(integer(Level, 1), 1, Settings.MaxLevel)
		local Total = 0

		for Current = 1, Level - 1 do
			Total += Progression.RequiredXP(Current, Config)
		end

		return Total;
	end

	function Progression.MaximumTotalXP(Config)
		return Progression.TotalForLevel(config(Config).MaxLevel, Config);
	end

	function Progression.TotalXP(Level, XP, Config)
		local Settings = config(Config)
		Level = math.clamp(integer(Level, 1), 1, Settings.MaxLevel)
		XP = math.max(integer(XP, 0), 0)

		if Level >= Settings.MaxLevel then
			return Progression.MaximumTotalXP(Config);
		end

		return math.min(
			Progression.TotalForLevel(Level, Config) + XP,
			Progression.MaximumTotalXP(Config)
		);
	end

	function Progression.Title(Level, Config)
		Level = math.max(integer(Level, 1), 1)
		local Result = 'ROOKIE'

		for _, Definition in ipairs(Config and Config.Titles or {}) do
			local Minimum = math.max(integer(Definition.Level, 1), 1)
			if Level >= Minimum then
				Result = tostring(Definition.Name or Result)
			else
				break
			end
		end

		return Result;
	end

	function Progression.FromTotalXP(TotalXP, Config)
		local Settings = config(Config)
		local Maximum = Progression.MaximumTotalXP(Config)
		TotalXP = math.clamp(integer(TotalXP, 0), 0, Maximum)

		local Level = 1
		local Remaining = TotalXP

		while Level < Settings.MaxLevel do
			local Required = Progression.RequiredXP(Level, Config)
			if Remaining < Required then
				break
			end

			Remaining -= Required
			Level += 1
		end

		local Required = Progression.RequiredXP(Level, Config)
		local Maxed = Level >= Settings.MaxLevel
		local XP = Maxed and 0 or Remaining
		local Progress = Maxed and 1 or math.clamp(XP / math.max(Required, 1), 0, 1)

		return {
			Level = Level;
			XP = XP;
			TotalXP = TotalXP;
			RequiredXP = Required;
			RemainingXP = Maxed and 0 or math.max(Required - XP, 0);
			Progress = Progress;
			Percent = math.floor(Progress * 100 + .5);
			MaxLevel = Settings.MaxLevel;
			Maxed = Maxed;
			Title = Progression.Title(Level, Config);
		};
	end

	function Progression.Normalize(Data, Config)
		Data = type(Data) == 'table' and Data or {}
		local Total = tonumber(Data.TotalXP)

		if not Total then
			Total = Progression.TotalXP(Data.Level, Data.XP, Config)
		end

		return Progression.FromTotalXP(Total, Config);
	end

	function Progression.Add(Data, Amount, Config)
		Amount = math.max(integer(Amount, 0), 0)
		local Before = Progression.Normalize(Data, Config)
		local After = Progression.FromTotalXP(Before.TotalXP + Amount, Config)

		return After, {
			Amount = After.TotalXP - Before.TotalXP;
			BeforeLevel = Before.Level;
			Level = After.Level;
			LevelsGained = math.max(After.Level - Before.Level, 0);
			BeforeXP = Before.XP;
			XP = After.XP;
			TotalXP = After.TotalXP;
			RequiredXP = After.RequiredXP;
			Progress = After.Progress;
			Maxed = After.Maxed;
			Title = After.Title;
		};
	end

	function Progression.MatchXP(Result, Config)
		Result = type(Result) == 'table' and Result or {}
		if Result.Completed == false then
			return 0;
		end

		local Awards = Config and Config.Awards or {}
		local Amount = math.max(integer(Awards.MatchComplete, 0), 0)

		if Result.Won == true then
			Amount += math.max(integer(Awards.Win, 0), 0)
		end

		local Placement = tonumber(Result.Placement)
		if Placement and Placement > 0 and Placement <= 3 then
			Amount += math.max(integer(Awards.Podium, 0), 0)
		end

		return Amount;
	end
end

return Progression;
