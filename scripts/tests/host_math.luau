local nativeTypeof = typeof

local function typeof(v)
	return type(v) == 'table' and v._type or nativeTypeof(v)
end

local Vector3 = {}
local V = {}

function Vector3.new(x, y, z)
	return setmetatable({_type = 'Vector3', X = x or 0, Y = y or 0, Z = z or 0}, V)
end

function V.__index(v, k)
	if k == 'Magnitude' then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	end
	if k == 'Unit' then
		return v / v.Magnitude
	end
	return V[k]
end

function V.__add(a, b)
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end

function V.__sub(a, b)
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end

function V.__unm(a)
	return a * -1
end

function V.__mul(a, b)
	if type(a) == 'number' then
		return b * a
	end
	return Vector3.new(a.X * b, a.Y * b, a.Z * b)
end

function V.__div(a, b)
	return a * (1 / b)
end

function V:Dot(b)
	return self.X * b.X + self.Y * b.Y + self.Z * b.Z
end

function V:Cross(b)
	return Vector3.new(
		self.Y * b.Z - self.Z * b.Y,
		self.Z * b.X - self.X * b.Z,
		self.X * b.Y - self.Y * b.X
	)
end

Vector3.zero = Vector3.new()
Vector3.one = Vector3.new(1, 1, 1)
Vector3.xAxis = Vector3.new(1, 0, 0)
Vector3.yAxis = Vector3.new(0, 1, 0)
Vector3.zAxis = Vector3.new(0, 0, 1)

local Vector2 = {
	new = function(x, y)
		return {X = x, Y = y}
	end
}

local CFrame = {}
local C = {}
C.__index = C

function CFrame.fromMatrix(p, x, y, z)
	return setmetatable({
		_type = 'CFrame',
		Position = p,
		XVector = x,
		YVector = y,
		ZVector = z or x:Cross(y)
	}, C)
end

function CFrame.new(x, y, z)
	return CFrame.fromMatrix(
		if typeof(x) == 'Vector3' then x else Vector3.new(x, y, z),
		Vector3.xAxis,
		Vector3.yAxis,
		Vector3.zAxis
	)
end

function C:VectorToWorldSpace(v)
	return self.XVector * v.X + self.YVector * v.Y + self.ZVector * v.Z
end

function C:PointToWorldSpace(v)
	return self.Position + self:VectorToWorldSpace(v)
end

function C.__mul(a, b)
	return CFrame.fromMatrix(
		a:PointToWorldSpace(b.Position),
		a:VectorToWorldSpace(b.XVector),
		a:VectorToWorldSpace(b.YVector),
		a:VectorToWorldSpace(b.ZVector)
	)
end

function C.__add(a, v)
	return CFrame.fromMatrix(a.Position + v, a.XVector, a.YVector, a.ZVector)
end

function CFrame.fromAxisAngle(axis, theta)
	local function turn(v)
		return v * math.cos(theta)
			+ axis:Cross(v) * math.sin(theta)
			+ axis * axis:Dot(v) * (1 - math.cos(theta))
	end

	return CFrame.fromMatrix(
		Vector3.zero,
		turn(Vector3.xAxis),
		turn(Vector3.yAxis),
		turn(Vector3.zAxis)
	)
end

function CFrame.fromOrientation(x, y, z)
	return CFrame.fromAxisAngle(Vector3.yAxis, y)
		* CFrame.fromAxisAngle(Vector3.xAxis, x)
		* CFrame.fromAxisAngle(Vector3.zAxis, z)
end

function C:GetComponents()
	local p, x, y, z = self.Position, self.XVector, self.YVector, self.ZVector
	return p.X, p.Y, p.Z, x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z
end

CFrame.identity = CFrame.new()
