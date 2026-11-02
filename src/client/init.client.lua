local StockUI = require(script:WaitForChild('StockUI'))
local SawUI = require(script:WaitForChild('SawUI'))

local workpieces = StockUI.start()
SawUI.start(workpieces)
