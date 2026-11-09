local Enum = { ActuatorType = { None = "None" } }
local Instance = {}
function Instance.new(class)
	local instance = { ClassName = class, Anchored = false, CanCollide = true }
	function instance:IsA(name)
		return self.ClassName == name
	end
	function instance:Destroy()
		self.destroyed = true
		self.Parent = nil
	end
	function instance:SetNetworkOwner(owner)
		self.owner = owner
	end
	return instance
end
