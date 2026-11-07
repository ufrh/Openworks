local API = {
	Version = '1.0.0',
	Status = 'Frozen',
	Namespace = 'FORGE.UI',

	Widgets = {
		'Widget', 'UserWidget', 'Component', 'PanelWidget', 'ContentWidget', 'WidgetTree'
	},

	Panels = {
		'CanvasPanel', 'Overlay', 'HorizontalBox', 'VerticalBox', 'GridPanel', 'ScrollBox',
		'SizeBox', 'Border', 'ScaleBox', 'SafeZone', 'WidgetSwitcher'
	},

	Controls = {
		'TextBlock', 'Image', 'Spacer', 'Button', 'ProgressBar', 'CheckBox', 'Slider', 'TextBox'
	},

	Slots = {
		'Slot', 'PanelSlot', 'CanvasSlot', 'BoxSlot', 'GridSlot', 'OverlaySlot', 'SizeBoxSlot'
	},

	Systems = {
		'Animation', 'StyleSet', 'State', 'UIEvent', 'InputRouter'
	}
}

table.freeze(API.Widgets)
table.freeze(API.Panels)
table.freeze(API.Controls)
table.freeze(API.Slots)
table.freeze(API.Systems)

return table.freeze(API)
