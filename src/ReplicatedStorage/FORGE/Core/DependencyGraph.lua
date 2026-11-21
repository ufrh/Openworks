-- Author -> lolokdev.
-- Last Edit -> September 14, 2026 4:25 PM CDT

local Registry = require(script.Parent.Registry)

local DependencyGraph = {} do
	-- injectDependencies -> nil
	-- Resolves hard and optional dependencies into one component's lookup table.
	-- @param Component, table -> Component receiving dependency references.
	local function injectDependencies(Component)
		Component.Dependencies = {}

		for _, Name in ipairs(Component._Dependencies) do
			local Dependency = Registry.Get(Name)
			if not Dependency then error(string.format('%s requires missing dependency %s.', Component.Name, Name)) end
			Component.Dependencies[Name] = Dependency
		end

		for _, Name in ipairs(Component._OptionalDependencies) do
			local Dependency = Registry.Get(Name)
			if Dependency then Component.Dependencies[Name] = Dependency end
		end
	end

	-- Resolve -> {table}
	-- Topologically sorts components and rejects circular hard dependencies.
	-- @param Components, {table} -> Components being ordered.
	function DependencyGraph.Resolve(Components)
		local Included = {}
		local Visiting = {}
		local Visited = {}
		local Result = {}

		for _, Component in ipairs(Components) do Included[Component.Name] = Component end

		-- visit -> nil
		-- Recursively visits one dependency branch and appends it in topological order.
		-- @param Component, table -> Component being visited.
		-- @param Trail, table -> Current dependency path for cycle reporting.
		local function visit(Component, Trail)
			if Visited[Component] then return end
			if Visiting[Component] then error('Circular FORGE dependency: ' .. table.concat(Trail, ' -> ') .. ' -> ' .. Component.Name) end

			Visiting[Component] = true
			table.insert(Trail, Component.Name)

			for _, Name in ipairs(Component._Dependencies) do
				local Dependency = Included[Name] or Registry.Get(Name)
				if not Dependency then error(string.format('%s requires missing dependency %s.', Component.Name, Name)) end
				visit(Dependency, Trail)
			end

			table.remove(Trail)
			Visiting[Component] = nil
			Visited[Component] = true
			injectDependencies(Component)
			table.insert(Result, Component)
		end

		table.sort(Components, function(A, B) return A.Priority < B.Priority end)
		for _, Component in ipairs(Components) do visit(Component, {}) end
		return Result;
	end
end

return DependencyGraph;
