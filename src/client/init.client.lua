local StockUI = require(script:WaitForChild('StockUI'))
local SawUI = require(script:WaitForChild('SawUI'))
local FileUI = require(script:WaitForChild('FileUI'))

local workpieces = StockUI.start()
SawUI.start(workpieces)
FileUI.start(workpieces)
