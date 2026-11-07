local Players = game:GetService('Players')

local Avatar = {} do
	Avatar.__index = Avatar
	Avatar.ClassName = 'Avatar'

	local Requests = setmetatable({}, {__mode = 'k'})
	local RandomGenerator = Random.new()

	local function Option(Options, Name, Default)
		if Options and Options[Name] ~= nil then return Options[Name] end
		return Default;
	end

	local function Retry(Options, Callback)
		local Attempts = math.max(math.floor(Option(Options, 'Retries', 3)), 1)
		local Delay = math.max(Option(Options, 'RetryDelay', .15), 0)
		local LastError

		for Attempt = 1, Attempts do
			local Success, A, B = pcall(Callback)
			if Success and A ~= nil then return true, A, B end
			LastError = Success and B or A
			if Attempt < Attempts and Delay > 0 then task.wait(Delay * Attempt) end
		end

		return false, nil, LastError;
	end

	local function FindBodyAttachment(Character, Name)
		for _, Object in ipairs(Character:GetDescendants()) do
			if not Object:IsA('Attachment') or Object.Name ~= Name then continue end
			if Object:FindFirstAncestorOfClass('Accessory') then continue end
			return Object;
		end
		return nil;
	end

	local function FindBodyPart(Character, Name)
		for _, Object in ipairs(Character:GetDescendants()) do
			if not Object:IsA('BasePart') or Object.Name ~= Name then continue end
			if Object:FindFirstAncestorOfClass('Accessory') then continue end
			return Object;
		end
		return nil;
	end

	local function GetPartScale(SourcePart, TargetPart, Mode)
		if not SourcePart or not TargetPart then return 1 end

		local Source, Target = SourcePart.Size, TargetPart.Size
		local X = Target.X / math.max(Source.X, .001)
		local Y = Target.Y / math.max(Source.Y, .001)
		local Z = Target.Z / math.max(Source.Z, .001)

		if Mode == 'Horizontal' then
			return math.sqrt(math.max(X, .001) * math.max(Z, .001));
		elseif Mode == 'Width' then
			return math.max(X, .001);
		elseif Mode == 'Height' then
			return math.max(Y, .001);
		elseif Mode == 'Depth' then
			return math.max(Z, .001);
		elseif Mode == 'Minimum' then
			return math.max(math.min(X, Y, Z), .001);
		elseif Mode == 'Maximum' then
			return math.max(X, Y, Z, .001);
		elseif Mode == 'Geometric' then
			return math.max((math.max(X, .001) * math.max(Y, .001) * math.max(Z, .001)) ^ (1 / 3), .001);
		end

		local Ratios = {X, Y, Z}
		table.sort(Ratios)
		return math.max(Ratios[2], .001);
	end

	local function ApplyUniformScale(Accessory, Scale)
		if not Scale or Scale <= 0 or math.abs(Scale - 1) <= 1e-4 then return end

		local Handle = Accessory:FindFirstChild('Handle')
		local PartFrames = {}

		if Handle and Handle:IsA('BasePart') then
			for _, Object in ipairs(Accessory:GetDescendants()) do
				if Object:IsA('BasePart') and Object ~= Handle then
					PartFrames[Object] = Handle.CFrame:ToObjectSpace(Object.CFrame)
				end
			end
		end

		for _, Object in ipairs(Accessory:GetDescendants()) do
			if Object:IsA('BasePart') then
				if Object:IsA('MeshPart') then
					Object.Size *= Scale
				else
					local Mesh = Object:FindFirstChildOfClass('SpecialMesh')
					if Mesh then Mesh.Scale *= Scale else Object.Size *= Scale end
				end
			elseif Object:IsA('Attachment') then
				Object.Position *= Scale
			end
		end

		if Handle and Handle:IsA('BasePart') then
			for Object, Relative in pairs(PartFrames) do
				if Object.Parent then
					Object.CFrame = Handle.CFrame * CFrame.new(Relative.Position * Scale) * Relative.Rotation
				end
			end
		end
	end

	local function NormalizeMount(SourcePart, SourceAttachment, TargetPart)
		local Relative = SourcePart.CFrame:ToObjectSpace(SourceAttachment.WorldCFrame)
		local SourceSize = SourcePart.Size
		local TargetSize = TargetPart.Size
		local Position = Relative.Position

		Position = Vector3.new(
			Position.X * TargetSize.X / math.max(SourceSize.X, .001),
			Position.Y * TargetSize.Y / math.max(SourceSize.Y, .001),
			Position.Z * TargetSize.Z / math.max(SourceSize.Z, .001)
		)

		return TargetPart.CFrame * CFrame.new(Position) * Relative.Rotation;
	end

	local function ResolveMount(SourceCharacter, Character, Accessory)
		local Handle = Accessory:FindFirstChild('Handle')
		if not Handle or not Handle:IsA('BasePart') then return nil end

		local Fallback

		for _, HandleAttachment in ipairs(Handle:GetChildren()) do
			if not HandleAttachment:IsA('Attachment') then continue end

			local SourceAttachment = FindBodyAttachment(SourceCharacter, HandleAttachment.Name)
			local TargetAttachment = FindBodyAttachment(Character, HandleAttachment.Name)
			local SourcePart = SourceAttachment and SourceAttachment:FindFirstAncestorWhichIsA('BasePart')
			local TargetPart = TargetAttachment and TargetAttachment:FindFirstAncestorWhichIsA('BasePart')

			if SourcePart and TargetPart then
				return {
					Handle = Handle;
					HandleAttachment = HandleAttachment;
					SourceAttachment = SourceAttachment;
					TargetAttachment = TargetAttachment;
					SourcePart = SourcePart;
					TargetPart = TargetPart;
					WorldCFrame = TargetAttachment.WorldCFrame;
				};
			end

			if SourcePart and not Fallback then
				local MatchingPart = FindBodyPart(Character, SourcePart.Name)
				if MatchingPart then
					Fallback = {
						Handle = Handle;
						HandleAttachment = HandleAttachment;
						SourceAttachment = SourceAttachment;
						SourcePart = SourcePart;
						TargetPart = MatchingPart;
						WorldCFrame = NormalizeMount(SourcePart, SourceAttachment, MatchingPart);
					};
				end
			end
		end

		return Fallback;
	end

	local function IsTargetAccessoryType(Accessory, Options)
		local Types = Option(Options, 'AccessoryTypes', nil)

		if Types then
			for Key, Value in pairs(Types) do
				local TypeValue = typeof(Key) == 'EnumItem' and Key or Value
				if TypeValue == Accessory.AccessoryType then return true end
			end
			return false
		end

		return Accessory.AccessoryType == Enum.AccessoryType.Hair and Option(Options, 'Hair', true) ~= false;
	end

	local function IsAllowedAccessory(Accessory, Options)
		if not IsTargetAccessoryType(Accessory, Options) then return false end

		local Name = string.lower(Accessory.Name)
		local Blocked = Option(Options, 'DisallowedAccessoryNames', Option(Options, 'DisallowedHairNames', {}))
		for _, Pattern in ipairs(Blocked) do
			if string.find(Name, string.lower(tostring(Pattern)), 1, true) then return false end
		end

		local Filter = Option(Options, 'AccessoryFilter', nil)
		if Filter then
			local Success, Allowed = pcall(Filter, Accessory)
			if not Success or Allowed == false then return false end
		end

		return true;
	end

	local function CollectSource(SourceCharacter, Options)
		local Clothing = {}
		local Accessories = {}
		local HairCount = 0
		local MaximumAccessories = math.max(math.floor(Option(Options, 'MaximumAccessories', 12)), 0)

		for _, Object in ipairs(SourceCharacter:GetChildren()) do
			if Object:IsA('Shirt') and Option(Options, 'Shirt', true) then
				table.insert(Clothing, Object:Clone())
			elseif Object:IsA('Pants') and Option(Options, 'Pants', true) then
				table.insert(Clothing, Object:Clone())
			elseif Object:IsA('ShirtGraphic') and Option(Options, 'ShirtGraphic', true) then
				table.insert(Clothing, Object:Clone())
			elseif Object:IsA('Accessory') and #Accessories < MaximumAccessories and IsAllowedAccessory(Object, Options) then
				local Clone = Object:Clone()
				Clone:SetAttribute('_FORGEPartialAvatar', true)
				table.insert(Accessories, Clone)
				if Object.AccessoryType == Enum.AccessoryType.Hair then HairCount += 1 end
			end
		end

		if Option(Options, 'RequireHair', false) and HairCount <= 0 then
			for _, Object in ipairs(Clothing) do Object:Destroy() end
			for _, Object in ipairs(Accessories) do Object:Destroy() end
			return nil, nil, 'Source avatar has no compatible hair.';
		end

		return Clothing, Accessories, nil;
	end

	local function ClearTarget(Character, Options)
		for _, Object in ipairs(Character:GetChildren()) do
			if Object:IsA('Shirt') and Option(Options, 'Shirt', true) and Option(Options, 'ClearClothing', true) then
				Object:Destroy()
			elseif Object:IsA('Pants') and Option(Options, 'Pants', true) and Option(Options, 'ClearClothing', true) then
				Object:Destroy()
			elseif Object:IsA('ShirtGraphic') and Option(Options, 'ShirtGraphic', true) and Option(Options, 'ClearClothing', true) then
				Object:Destroy()
			elseif Object:IsA('Accessory') and Option(Options, 'ClearAccessories', true) then
				if IsTargetAccessoryType(Object, Options) or Object:GetAttribute('_FORGEPartialAvatar') then Object:Destroy() end
			end
		end
	end


	local function PrepareAccessoryParts(Accessory)
		for _, Object in ipairs(Accessory:GetDescendants()) do
			if Object:IsA('BasePart') then
				Object.Anchored = false
				Object.CanCollide = false
				Object.CanTouch = false
				Object.CanQuery = false
				Object.Massless = true
			elseif Object.Name == 'AccessoryWeld' and (Object:IsA('Weld') or Object:IsA('WeldConstraint') or Object:IsA('Motor6D')) then
				Object:Destroy()
			end
		end
	end

	local function MountAccessory(SourceCharacter, Character, Accessory, Options)
		local Mount = ResolveMount(SourceCharacter, Character, Accessory)
		if not Mount then Accessory:Destroy(); return false end

		local IsHair = Accessory.AccessoryType == Enum.AccessoryType.Hair
		local ScaleMode = IsHair and Option(Options, 'HairScaleMode', 'Horizontal') or Option(Options, 'AccessoryScaleMode', 'Median')
		local BaseScale = GetPartScale(Mount.SourcePart, Mount.TargetPart, ScaleMode)
		local StyleScale = Option(Options, 'AccessoryScale', 1)
		if IsHair then StyleScale *= Option(Options, 'HairScale', 1) end

		local MinimumScale = math.max(Option(Options, 'MinimumAccessoryScale', .025), .001)
		local MaximumScale = math.max(Option(Options, 'MaximumAccessoryScale', 32), MinimumScale)
		local FinalScale = math.clamp(BaseScale * StyleScale, MinimumScale, MaximumScale)

		ApplyUniformScale(Accessory, FinalScale)
		PrepareAccessoryParts(Accessory)

		local Offset = Accessory.AccessoryType == Enum.AccessoryType.Hair and Option(Options, 'HairOffset', Vector3.zero) or Option(Options, 'AccessoryOffset', Vector3.zero)
		if Option(Options, 'ScaleOffsets', true) then Offset *= BaseScale end

		Accessory.Parent = Character
		Mount.Handle.CFrame = Mount.WorldCFrame * CFrame.new(Offset) * Mount.HandleAttachment.CFrame:Inverse()

		local Weld = Instance.new('WeldConstraint')
		Weld.Name = 'AccessoryWeld'
		Weld.Part0 = Mount.TargetPart
		Weld.Part1 = Mount.Handle
		Weld.Parent = Mount.Handle
		return true;
	end

	local function ResolveSource(Source, Character, Options)
		if typeof(Source) == 'Instance' and Source:IsA('Model') then
			return Source:Clone(), nil, nil;
		end

		local Description
		local UserId

		if typeof(Source) == 'Instance' and Source:IsA('Player') then
			UserId = Source.UserId
		elseif typeof(Source) == 'Instance' and Source:IsA('HumanoidDescription') then
			Description = Source:Clone()
		elseif type(Source) == 'number' then
			UserId = math.floor(Source)
		elseif type(Source) == 'table' and type(Source.UserId) == 'number' then
			UserId = math.floor(Source.UserId)
		end

		if not Description then
			if not UserId or UserId <= 0 then return nil, nil, 'Avatar source must be a Player, user id, HumanoidDescription, or Model.' end

			local Success, Result, Error = Retry(Options, function()
				return Players:GetHumanoidDescriptionFromUserIdAsync(UserId)
			end)
			if not Success or not Result then return nil, UserId, Error or 'Unable to load HumanoidDescription.' end
			Description = Result
		end

		local Humanoid = Character:FindFirstChildOfClass('Humanoid')
		local RigType = Humanoid and Humanoid.RigType or Enum.HumanoidRigType.R15
		local Success, Result, Error = Retry(Options, function()
			return Players:CreateHumanoidModelFromDescriptionAsync(Description, RigType)
		end)

		Description:Destroy()
		if not Success or not Result then return nil, UserId, Error or 'Unable to build source avatar.' end
		return Result, UserId, nil;
	end

	function Avatar.ApplyPartial(Source, Character, Options)
		if not Character or not Character:IsA('Model') or not Character.Parent then return false, {Reason = 'Invalid target character.';} end

		Requests[Character] = (Requests[Character] or 0) + 1
		local Request = Requests[Character]
		local SourceCharacter, UserId, Error = ResolveSource(Source, Character, Options)
		if not SourceCharacter then return false, {Reason = tostring(Error or 'Unable to resolve avatar source.'); UserId = UserId;} end

		if not Character.Parent or Requests[Character] ~= Request then
			SourceCharacter:Destroy()
			return false, {Reason = 'Superseded.'; UserId = UserId;}
		end

		local Clothing, Accessories, CollectError = CollectSource(SourceCharacter, Options)
		if not Clothing then
			SourceCharacter:Destroy()
			return false, {Reason = CollectError; UserId = UserId;}
		end

		ClearTarget(Character, Options)

		for _, Object in ipairs(Clothing) do Object.Parent = Character end

		local AppliedAccessories = 0
		local SkippedAccessories = 0

		for _, Accessory in ipairs(Accessories) do
			if MountAccessory(SourceCharacter, Character, Accessory, Options) then AppliedAccessories += 1 else SkippedAccessories += 1 end
		end

		SourceCharacter:Destroy()
		Character:SetAttribute('_FORGEAvatarUserId', UserId or 0)
		Character:SetAttribute('_FORGEAvatarApplied', true)

		return true, {
			UserId = UserId;
			Clothing = #Clothing;
			Accessories = AppliedAccessories;
			SkippedAccessories = SkippedAccessories;
		};
	end

	function Avatar.ApplyRandomPartial(Character, Options)
		local Attempts = math.max(math.floor(Option(Options, 'RandomAttempts', 75)), 1)
		local Minimum = math.max(math.floor(Option(Options, 'RandomMinimumUserId', 1)), 1)
		local Maximum = math.max(math.floor(Option(Options, 'RandomMaximumUserId', 8_000_000_000)), Minimum)
		local LastReport

		for _ = 1, Attempts do
			local UserId = RandomGenerator:NextInteger(Minimum, Maximum)
			local Success, Report = Avatar.ApplyPartial(UserId, Character, Options)
			if Success then return true, Report end
			LastReport = Report
			task.wait(Option(Options, 'RandomRetryDelay', .02))
		end

		return false, LastReport or {Reason = 'Unable to find a valid random avatar.';};
	end

	function Avatar.Cancel(Character)
		if not Character then return end
		Requests[Character] = (Requests[Character] or 0) + 1
	end
end

return Avatar;
