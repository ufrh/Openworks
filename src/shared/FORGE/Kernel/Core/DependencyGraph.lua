-- Author -> lolokdev.
-- Last Edit -> September 14, 2026 4:25 PM CDT

local Registry = require(script.Parent.Registry)

local DependencyGraph = {} do
	-- injectDependencies -> nil
	-- Resolves hard and optional dependencies into one component's lookup table.
	-- @param Component, table -> Component receiving dependency references.
	local function injectDependencies(Component)
		Component.Dependencies = {}

		local function inject(Name, Required)
			local Dependency = Registry.Get(Name)
			if not Dependency and Required then error(string.format('%s requires missing dependency %s.', Component.Name, Name)) end
			if not Dependency then return end

			Component.Dependencies[Name] = Dependency
			for Alias, Target in pairs(Component._DependencyAliases or {}) do
				if Target == Name then
					Component.Dependencies[Alias] = Dependency
					if rawget(Component, Alias) == nil then rawset(Component, Alias, Dependency) end
				end
			end
		end

		for _, Name in ipairs(Component._Dependencies) do inject(Name, true) end
		for _, Name in ipairs(Component._OptionalDependencies) do inject(Name, false) end
	end

	-- Resolve -> {table}
	-- Topologically sorts components and rejects circular hard dependencies.
	-- @param Components, {table} -> Components being ordered.
	function DependencyGraph.Snapshot(Components)
		Components = Components or Registry.List()

		local Nodes = {}
		local Dependents = {}

		for _, Component in ipairs(Components) do
			for _, Dependency in ipairs(Component._Dependencies or {}) do
				Dependents[Dependency] = Dependents[Dependency] or {}
				table.insert(Dependents[Dependency], Component.Name)
			end
		end

		for _, Component in ipairs(Components) do
			local Required = table.clone(Component._Dependencies or {})
			local Optional = table.clone(Component._OptionalDependencies or {})
			local UsedBy = table.clone(Dependents[Component.Name] or {})
			table.sort(Required)
			table.sort(Optional)
			table.sort(UsedBy)

			table.insert(Nodes, {
				Name = Component.Name,
				Kind = Component.Kind,
				Priority = Component.Priority or 0,
				Requires = Required,
				Optional = Optional,
				Dependents = UsedBy
			})
		end

		table.sort(Nodes, function(A, B) return A.Name < B.Name end)
		return Nodes
	end

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
