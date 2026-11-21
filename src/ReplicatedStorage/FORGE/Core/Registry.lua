-- Author -> lolokdev.
-- Last Edit -> September 13, 2026 8:44 AM CDT

local State = require(script.Parent.State)

local Registry = {} do
	-- Register -> table
	-- Registers one unique FORGE component.
	-- @param Component, table -> Service or Controller instance.
	function Registry.Register(Component)
		assert(type(Component) == 'table' and Component._FORGEComponent, 'Registry.Register expected a FORGE component.')
		assert(type(Component.Name) == 'string' and Component.Name ~= '', 'FORGE components require a non-empty Name.')
		assert(not State.Registered[Component.Name], 'Duplicate FORGE component name: ' .. Component.Name)

		State.Registered[Component.Name] = Component
		table.insert(State.Order, Component)
		return Component;
	end

	-- Get -> table?
	-- Returns a registered component by name.
	-- @param Name, string -> Component name.
	function Registry.Get(Name)
		return State.Registered[Name];
	end

	-- GetService -> table?
	-- Returns a registered server Service by name.
	-- @param Name, string -> Service name.
	function Registry.GetService(Name)
		local Component = State.Registered[Name]
		return Component and Component.Kind == 'Service' and Component or nil;
	end

	-- GetController -> table?
	-- Returns a registered client Controller by name.
	-- @param Name, string -> Controller name.
	function Registry.GetController(Name)
		local Component = State.Registered[Name]
		return Component and Component.Kind == 'Controller' and Component or nil;
	end

	-- List -> {table}
	-- Returns registered components for the requested kind or every kind.
	-- @param Kind, string? -> Optional Service or Controller filter.
	function Registry.List(Kind)
		local Result = {}
		for _, Component in ipairs(State.Order) do
			if not Kind or Component.Kind == Kind then table.insert(Result, Component) end
		end
		return Result;
	end

	-- Remove -> nil
	-- Removes a component from the active registry.
	-- @param Name, string -> Component name.
	function Registry.Remove(Name)
		local Component = State.Registered[Name]
		if not Component then return end
		State.Registered[Name] = nil

		for Index = #State.Order, 1, -1 do
			if State.Order[Index] == Component then table.remove(State.Order, Index); break end
		end
	end
end

return Registry;
