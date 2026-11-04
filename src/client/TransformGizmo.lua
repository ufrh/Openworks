			elseif grip.mode == "Scale" then
				grip.part.Position = cf:PointToWorldSpace(
					grip.normal * (getAxis(size, grip.axis) / 2 + unit * 0.75))
				grip.part.Size = Vector3.one * unit * (1.35 + 0.18 * grip.hoverAlpha)			elseif grip.mode=="Scale" then
				grip.part.Position=cf:PointToWorldSpace(
					grip.normal*(getAxis(size,grip.axis)/2+unit*0.75))
				grip.part.Size=Vector3.one*unit*(1.35+0.18*grip.hoverAlpha)
				grip.marker.CFrame=CFrame.new(grip.part.Position)
				grip.marker.Radius=grip.part.Size.X*0.5
			else
				grip.part.Position = cf:PointToWorldSpace(grip.radial * (unit * 6))
				grip.part.Size = Vector3.one * unit * (1 + 0.14 * grip.hoverAlpha)
				grip.marker.CFrame=CFrame.new(grip.part.Position)
				grip.marker.Radius=grip.part.Size.X*0.5
			end
		end
	end
end

function TransformGizmo:destroy()
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	self.folder:Destroy()
	self.decorations:Destroy()
	self.anchor:Destroy()
	self.measurement:Destroy()
end

return TransformGizmo
