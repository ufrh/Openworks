local RunService = game:GetService('RunService')

local Context = {} do
	Context.Server = RunService:IsServer()
	Context.Client = RunService:IsClient()
	Context.Studio = RunService:IsStudio()
	Context.Production = not Context.Studio
	Context.Running = RunService:IsRunning()
	Context.PlaceId = game.PlaceId
	Context.GameId = game.GameId
	Context.JobId = game.JobId
	Context.Side = Context.Server and 'Server' or 'Client'
	Context.Environment = Context.Studio and 'Studio' or 'Production'

	function Context:Is(Name)
		if Name == 'Server' then return self.Server end
		if Name == 'Client' then return self.Client end
		if Name == 'Studio' then return self.Studio end
		if Name == 'Production' then return self.Production end
		if Name == 'Running' then return self.Running end
		return false
	end

	function Context:Snapshot()
		return {
			Server = self.Server,
			Client = self.Client,
			Studio = self.Studio,
			Production = self.Production,
			Running = self.Running,
			PlaceId = self.PlaceId,
			GameId = self.GameId,
			JobId = self.JobId,
			Side = self.Side,
			Environment = self.Environment
		}
	end
end

return Context
