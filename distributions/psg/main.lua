local TIMEOUT = 2
local CHANNEL_EVENT = 47
local CHANNEL_COMMAND = 46

local theme = {
	FrameBG = colors.lightGray,
	FrameFG = colors.black,
	SelectionText = colors.white,
}

-------------------------

local basalt = require 'basalt'
local addresses = require 'psg.addresses'
local addressbook = require 'psg.addressbook'
local job = require 'ktlo.job'
local rpc = require 'ktlo.rpc'
local keyring = require 'psg.keyring'
local vault = require 'psg.vault'
local keys = require 'psg.keys'
local concurrent = require 'ktlo.concurrent'
local resources = require 'ktlo.resources'
local container = require 'ktlo.container'
local modal = require 'psg.modal'
local feedback = require 'psg.feedback'

local version = VERSION or "dev"

local modem = peripheral.find("modem", function(_, modem) return modem.isWireless() end) or peripheral.find("modem")
if not modem then
	error "No modem found; exiting..."
end

settings.define("psg.fastDialMode", {
	description = "Dial as fast as possible",
	default = false,
	type = "boolean",
})

local fastDialModeInit = settings.get("psg.fastDialMode", false)
local fastDialMode = fastDialModeInit

local stargate = rpc.client_network(modem, CHANNEL_COMMAND, TIMEOUT)

local othersideResponses = concurrent.channel()

local function othersideExchanger(request)
	job.async(function()
		local message = tostring(container.datum(request, true))
		pcall(stargate.tell, message)
	end)
	while true do
		local response = othersideResponses:recv()
		if rpc.is_response(request, response) then
			return response
		end
	end
end

local otherside = rpc.client(othersideExchanger, TIMEOUT)

basalt.setVariable("addressLength", 0)

local addressesState = concurrent.property(addresses.create(addressbook.load()))

local statsProperty = concurrent.property(nil)

local modalMutex = concurrent.mutex()
local modalMutexVault = concurrent.mutex()

local function synchPasswordButtonText(passwordButtonElement)
	local passwordButtonText
	if vault.is_encrypted() then
		passwordButtonText = "Del password"
	else
		passwordButtonText = "Set password"
	end
	passwordButtonElement:setText(passwordButtonText)
end

local function setHostName(element)
	local name = element:getValue()
	job.async(function()
		local newName = modalMutexVault:with_lock(modal.text, name)
		if newName then
			element:setText(newName)
			if newName == "" then
				newName = nil
			end
			vault.set_name(newName)
		end
	end)
end

local function getLocalAddress(stats)
	local localAddress = stats.localAddress
	if localAddress then
		return localAddress
	end
	local advanced = stats.advanced
	if advanced then
		return advanced.localAddress
	end
end

local function vaultSetup(frame, future)
	frame:addLayoutFromString(resources.load("vault.xml"))
	local window = frame:getObject('window')
	window:getObject('exit'):onClick(function()
		future:complete()
	end)
	local passwordButton = window:getObject('password')
	synchPasswordButtonText(passwordButton)
	local hostName = window:getObject('hostName')
	hostName:onClick(setHostName)
	hostName:setText(vault.get_name() or "")
	local authKeysList = window:getObject('list')
	local function addKeyToKeyringList(key, name)
		local fingerprint = keys.fingerprint(key)
		local text
		if name then
			text = name..' '..fingerprint
		else
			text = fingerprint
		end
		authKeysList:addItem(text, nil, nil, { key=key, name=name })
	end
	local hostKeyElement = window:getObject('hostKey')
	hostKeyElement:setText(keys.fingerprint(vault.public_key()))
	local authKeys = keyring.get_all()
	for _, key in ipairs(authKeys) do
		addKeyToKeyringList(key.key, key.name)
	end
	window:getObject('register'):onClick(function()
		local stats = statsProperty.value
		if stats then
			job.async(function()
				local hostKey = stargate.register(vault.public_key(), vault.get_name())
				local localAddress = getLocalAddress(stats)
				local name
				if localAddress then
					name = addressesState.value:getname(localAddress)
				end
				name = name or addressesState.value:getname_by_key(stats.solarSystem)
				if keyring.trust(hostKey, name) then
					addKeyToKeyringList(hostKey, name)
				end
			end)
		end
	end)
	window:getObject('forget'):onClick(function()
		local i = authKeysList:getItemIndex()
		if i then
			local item = authKeysList:getItem(i)
			keyring.forget(item.args[1].key)
			authKeysList:removeItem(i)
		end
	end)
	passwordButton:onClick(function(button)
		job.async(function()
			if vault.is_encrypted() then
				local password = modalMutexVault:with_lock(modal.passwd)
				if not password then
					return
				end
				local ok, reason = vault.decrypt_key(password)
				if not ok then
					modalMutexVault:with_lock(modal.alert, {"Failed to decrypt:", reason}, nil, "OK")
					return
				end
				synchPasswordButtonText(button)
			else
				local password = modalMutexVault:with_lock(modal.chpass)
				if not password then
					return
				end
				vault.encrypt_key(password)
				synchPasswordButtonText(button)
			end
		end)
	end)
end

local function scrollList(list, increment)
	local offset = list:getOffset()
	if increment < 0 and offset <= 0 then
		return
	end
	if increment > 0 and offset > #(list:getAll()) - list:getHeight() then
		return
	end
	list:setOffset(offset + increment)
end

local function scroll(button, increment)
	local list = button:getParent():getObject("list")
	scrollList(list, increment)
end

local function scrollParentList(button, increment)
	local list = button:getParent():getObject("list")
	scrollList(list, increment)
end

local function selectFrom(bar, ...)
	local index = bar:getItemIndex()
	for i=1, select('#', ...) do
		local tab = select(i, ...)
		if tab then
			if i == index then
				tab:show()
			else
				tab:hide()
			end
		end
	end
	local tab = select(index, ...)
	return tab
end

local function asnSetup(frame, future)
	local address = require 'psg.address'
	frame:addLayoutFromString(resources.load("asn.xml"))
	local window = frame:getObject('window')
	window:getObject('exit'):onClick(function()
		future:complete(nil)
	end)
	local positionList = window:getObject('position')
	local identityList = window:getObject('identity')
	local activeList = positionList
	window:getObject('selectList'):onChange(function(bar)
		activeList = selectFrom(
			bar,
			positionList,
			identityList
		)
	end)
	local modalMutex = concurrent.mutex()
	local modalMutexPosition = concurrent.mutex()

	local function getInputOrNil(input)
		local value = input:getValue()
		if value == "" then
			return nil
		else
			return value
		end
	end
	local function addressForm(mutex, record, kind)
		record = record or {}
		return modal.open(function(frame, future)
			local width = math.min(30, frame:getParent():getSize() - 2)
			frame:setSize(width, 12)
			frame:setPosition("(parent.w - self.w)/2 + 1", "(parent.h - self.h)/2")
			frame:addLayoutFromString(resources.load "record.xml")
			local window = frame:getObject("window")
			local nameInput = window:getObject("name")
			nameInput:setValue(record.name or "")
			local addressInput = window:getObject("address")
			addressInput:setValue(record.address and tostring(record.address) or "")

			window:getObject("submit"):onClick(function()
				local ok, value = pcall(address.parse, addressInput:getValue())
				if not ok then
					job.async(function()
						mutex:with_lock(modal.alert, "Invalid address:\n"..value, nil, "OK")
					end)
					return
				end
				if value.kind ~= kind then
					job.async(function()
						mutex:with_lock(
							modal.alert,
							"Invalid address:\nexpected "..kind.." ("..address.sizeof(kind).." symbols), but got "
							..value.kind.." ("..value.n.." symbols)", nil, "OK"
						)
					end)
					return
				end
				future:complete {
					name = nameInput:getValue();
					address = value;
				}
			end)
			window:getObject("cancel"):onClick(function()
				future:complete(nil)
			end)
		end)
	end

	local function positionForm(position)
		position = position or { interstellar = {} }
		return modalMutex:with_lock(modal.open, function(frame, future)
			local recordMutex = concurrent.mutex()
			frame:addLayoutFromString(resources.load "position.xml")
			local window = frame:getObject("window")
			local nameInput = window:getObject("name")
			nameInput:setValue(position.name or "")
			local keyInput = window:getObject("key")
			keyInput:setValue(position.key or "")
			local extragalacticInput = window:getObject("extragalactic")
			extragalacticInput:setValue(position.extragalactic and tostring(position.extragalactic) or "")
			local interstellarList = window:getObject("list")
			local function interstellarItem(galaxy, addr)
				return galaxy.." "..tostring(addr), nil, nil, { galaxy = galaxy, address = addr }
			end
			local function addInterstellar(galaxy, addr)
				interstellarList:addItem(interstellarItem(galaxy, addr))
			end
			for galaxy, addr in pairs(position.interstellar) do
				addInterstellar(galaxy, addr)
			end
			window:getObject("add"):onClick(function()
				job.async(function()
					local record = modalMutexPosition:with_lock(addressForm, recordMutex, nil, 'interstellar')
					if record then
						addInterstellar(record.name, record.address)
					end
				end)
			end)
			window:getObject("edit"):onClick(function()
				local index = interstellarList:getItemIndex()
				if not index or index <= 0 then
					return
				end
				local item = interstellarList:getItem(index)
				local record = item.args[1]
				job.async(function()
					local newRecord = modalMutexPosition:with_lock(
						addressForm, recordMutex, {name = record.galaxy, address = record.address}, 'interstellar'
					)
					if newRecord then
						interstellarList:editItem(index, interstellarItem(newRecord.name, newRecord.address))
					end
				end)
			end)
			window:getObject("delete"):onClick(function()
				local index = interstellarList:getItemIndex()
				if not index or index <= 0 then
					return
				end
				job.async(function()
					local isSure = modalMutexPosition:with_lock(modal.alert, "Are you sure?", "Yes", "No")
					if isSure then
						interstellarList:removeItem(index)
					end
				end)
			end)

			window:getObject("submit"):onClick(function()
				local extragalactic = getInputOrNil(extragalacticInput)
				if extragalactic then
					local ok, value = pcall(address.parse, extragalactic)
					if not ok then
						job.async(function()
							modalMutexPosition:with_lock(
								modal.alert,
								"Invalid extragalactic address:\n"..value, nil, "OK"
							)
						end)
						return
					end
					if value.kind ~= 'extragalactic' then
						job.async(function()
							modalMutexPosition:with_lock(
								modal.alert,
								"Invalid extragalactic address:\nexpected extragalactic address (7 symbols), but got "
								..value.kind.." ("..value.n.." symbols)", nil, "OK"
							)
						end)
						return
					end
					extragalactic = value
				end
				local interstellar = {}
				local count = interstellarList:getItemCount()
				for i=1, count do
					local item = interstellarList:getItem(i)
					local record = item.args[1]
					interstellar[record.galaxy] = record.address
				end
				future:complete {
					name = getInputOrNil(nameInput);
					key = getInputOrNil(keyInput);
					interstellar = interstellar;
					extragalactic = extragalactic;
				}
			end)
			window:getObject("cancel"):onClick(function()
				future:complete(nil)
			end)
		end)
	end
	local function listItem(record)
		return record.name or record.key or "???", nil, nil, record
	end
	window:getObject('addRecord'):onClick(function()
		job.async(function()
			local record
			if activeList == positionList then
				record = positionForm(nil)
			else
				record = modalMutex:with_lock(addressForm, modalMutexPosition, nil, 'systemwide')
			end
			if record then
				activeList:addItem(listItem(record))
			end
		end)
	end)
	window:getObject('editRecord'):onClick(function()
		local index = activeList:getItemIndex()
		if not index or index <= 0 then
			return
		end
		job.async(function()
			local record = activeList:getItem(index).args[1]
			if activeList == positionList then
				record = positionForm(record)
			else
				record = modalMutex:with_lock(addressForm, modalMutexPosition, record, 'systemwide')
			end
			if record then
				activeList:editItem(index, listItem(record))
			end
		end)
	end)
	window:getObject('deleteRecord'):onClick(function()
		local index = activeList:getItemIndex()
		if not index or index <= 0 then
			return
		end
		job.async(function()
			local isSure = modalMutex:with_lock(modal.alert, "Are you sure?", "Yes", "No")
			if isSure then
				activeList:removeItem(index)
			end
		end)
	end)
	local function editListItem(list, index, item)
		list:editItem(index, item.text, item.bgCol, item.fgCol, table.unpack(item.args))
	end
	local function swapListItems(list, a, b)
		local aItem = list:getItem(a)
		local bItem = list:getItem(b)
		editListItem(list, a, bItem)
		editListItem(list, b, aItem)
	end
	window:getObject('moveUp'):onClick(function()
		local index = activeList:getItemIndex()
		if not index or index <= 0 then
			return
		end
		if index == 1 then
			return
		end
		swapListItems(activeList, index - 1, index)
		activeList:selectItem(index - 1)
	end)
	window:getObject('moveDown'):onClick(function()
		local index = activeList:getItemIndex()
		if not index or index <= 0 then
			return
		end
		if index == activeList:getItemCount() then
			return
		end
		swapListItems(activeList, index, index + 1)
		activeList:selectItem(index + 1)
	end)
	window:getObject('up'):onClick(function()
		scrollList(activeList, -1)
	end)
	window:getObject('down'):onClick(function()
		scrollList(activeList, 1)
	end)
	local function transformList(list)
		local result = {}
		for i, item in ipairs(list:getAll()) do
			result[i] = item.args[1]
		end
		return result
	end
	window:getObject('save'):onClick(function()
		job.async(function()
			local ok, err = pcall(function()
				local result = {
					position = transformList(positionList);
					identity = transformList(identityList);
				}
				addressbook.save(result)
				return result
			end)
			if not ok then
				modalMutex:with_lock(modal.alert, "Saving failed:\n"..err, nil, "OK")
			else
				future:complete(err)
			end
		end)
	end)
	do
		local addressesVal = addressesState.value.addressbook
		for _, record in ipairs(addressesVal.position) do
			positionList:addItem(listItem(record))
		end
		for _, record in ipairs(addressesVal.identity) do
			identityList:addItem(listItem(record))
		end
	end
end

local addressesTypeMenubar
local addressesList

local currentAddresses = {}

local function dom(path)
	local current = basalt.getActiveFrame()
	for _, segment in ipairs(path) do
		current = current:getObject(segment)
	end
	return current
end

local function loadAddresses()
	local stats = statsProperty.value
	if stats then
		local index = addressesTypeMenubar:getItemIndex()
		local newAddresses
		local addressesVal = addressesState.value
		if index == 1 then -- interstellar
			newAddresses = addressesVal:interstellar(stats.galaxies, stats.solarSystem)
		elseif index == 2 then -- extragalactic
			newAddresses = addressesVal:extragalactic(stats.galaxies)
		else -- direct
			newAddresses = addressesVal:direct((stats.advanced or {}).localAddress)
		end
		currentAddresses = newAddresses
		addressesList:clear()
		addressesList:setOffset(0)
		for _, record in ipairs(currentAddresses) do
			addressesList:addItem(record.name)
		end
	end
end

basalt.setVariable("loadAddresses", loadAddresses)

local function selectFrame(self)
	local index = self:getItemIndex()
	local tabs = {
		dom { 'root', 'main', 'addressbook' },
		dom { 'root', 'main', 'dhd' },
		dom { 'root', 'main', 'stats' },
	}
	for i, tab in ipairs(tabs) do
		if i == index then
			tab:show()
		else
			tab:hide()
		end
	end
end

basalt.setVariable("selectFrame", selectFrame)

basalt.setVariable("selectSubFrame", function(self)
	local index = self:getItemIndex()
	local tabs = {
		dom { 'root', 'main', 'stats', 'general' },
		dom { 'root', 'main', 'stats', 'energy' },
		dom { 'root', 'main', 'stats', 'status' },
	}
	for i, tab in ipairs(tabs) do
		if i == index then
			tab:show()
		else
			tab:hide()
		end
	end
end)

basalt.setVariable("scrollUp", function(button)
	scroll(button, -1)
end)

basalt.setVariable("scrollDown", function(button)
	scroll(button, 1)
end)

basalt.setVariable("parentScrollUp", function(button)
	scrollParentList(button, -1)
end)

basalt.setVariable("parentScrollDown", function(button)
	scrollParentList(button, 1)
end)

basalt.setVariable("onFast", function(element)
	fastDialMode = element:getValue()
	settings.set("psg.fastDialMode", fastDialMode)
	settings.save()
end)

basalt.setVariable("dial", function()
	local stats = statsProperty.value
	if stats then
		job.async(function()
			if stats.basic.isConnected then
				stargate.disconnect()
			else
				local index = addressesList:getItemIndex()
				if index > 0 then
					local dialAddress = currentAddresses[index].address
					stargate.dial(dialAddress, not fastDialMode)
				end
			end
		end)
	end
end)

basalt.setVariable("openVault", function()
	job.async(function()
		modalMutex:with_lock(modal.open, vaultSetup)
	end)
end)

basalt.setVariable("editAddressbook", function()
	job.async(function()
		local newAddresses = modalMutex:with_lock(modal.open, asnSetup)
		if newAddresses then
			addressesState:set(addresses.create(newAddresses))
		end
	end)
end)

basalt.setVariable("engage", function(self)
	local symbol = tonumber(self:getValue())
	job.async(function()
		if self:getBackground() == colors.gray then
			stargate.engage(symbol)
		end
	end)
end)

basalt.setVariable("engagePoo", function()
	local stats = statsProperty.value
	if stats and not stats.pooPressed then
		job.async(function() stargate.engage(0) end)
	end
end)

basalt.setVariable("reset", function()
	job.async(stargate.disconnect)
end)

basalt.setVariable("tell", function()
	local message = dom { 'root', 'main', 'stats', 'status', 'message' }
	local value = table.concat(message:getLines(), '\n')
	job.async(function()
		stargate.tell(value)
	end)
end)

job.run(function()

local serverIdProperty = job.livedata.combine(function(stats)
	if stats then
		return stats.id
	else
		return nil
	end
end, statsProperty)

basalt.createFrame()
	:setTheme(theme)
	:addLayoutFromString(resources.load("psg.xml"))

local mainFrame = dom { 'root', 'main' }

addressesTypeMenubar = dom { 'root', 'main', 'addressbook', 'addressType' }
addressesList = dom { 'root', 'main', 'addressbook', 'list' }
local dialButton = dom { 'root', 'main', 'addressbook', 'dial' }

local function updateDialButtonText(stats)
	local text
	if stats.basic.isConnected then
		if stats.basic.isWormholeOpen then
			text = "Disconnect"
		else
			text = "Dialing..."
		end
	else
		text = "Dial"
	end
	dialButton:setText(text)
end

local dialFrame = dom { 'root', 'main', 'dhd' }
local dialNameLabel = dialFrame:getObject('name')
local dialAddress = dialFrame:getObject('dialAddress')
local bufferAddress = dialFrame:getObject('bufferAddress')
local pooButton = dialFrame:getObject('poo')

local function updateDialAddress(stats)
	local dialAddressText, bufferAddressText
	local dialedAddress = stats.dialedAddress
	dialAddressText = addresses.tostring(dialedAddress)
	bufferAddressText = addresses.tostring(stats.addressBuffer)
	if dialAddressText ~= "" and bufferAddressText ~= "" then
		bufferAddressText = "-"..bufferAddressText
	end
	local totalWidth = #dialAddressText + #bufferAddressText
	dialAddress:setText(dialAddressText)
	dialAddress:setPosition("(parent.w - "..totalWidth..")/2")
	bufferAddress:setText(bufferAddressText)
	if not next(dialedAddress) then
		dialNameLabel:setText("")
	elseif stats.basic.isWormholeOpen or stats.basic.isDialingOut then
		dialNameLabel:setText(addressesState.value:getname(dialedAddress, stats.galaxies) or "")
	end
end

-- stats begin

local versionLabel = dom { 'root', 'main', 'stats', 'general', 'version' }

local localAddressLabel = dom { 'root', 'main', 'stats', 'general', 'localAddress' }
local generationLabel = dom { 'root', 'main', 'stats', 'general', 'generation' }
local typeLabel = dom { 'root', 'main', 'stats', 'general', 'type' }
local variantLabel = dom { 'root', 'main', 'stats', 'general', 'variant' }
local feedbackCodeLabel = dom { 'root', 'main', 'stats', 'general', 'feedbackCode' }
local feedbackMessageLabel = dom { 'root', 'main', 'stats', 'general', 'feedbackMessage' }

local energyLabel = dom { 'root', 'main', 'stats', 'energy', 'interface', 'energy' }
local energyCapacityLabel = dom { 'root', 'main', 'stats', 'energy', 'interface', 'capacity' }
local energyInterfaceProgressbar = dom { 'root', 'main', 'stats', 'energy', 'interface', 'progress' }
local stargateEnergyLabel = dom { 'root', 'main', 'stats', 'energy', 'stargate', 'energy' }
local targetEnergyLabel = dom { 'root', 'main', 'stats', 'energy', 'stargate', 'target' }
local energyProgressbar = dom { 'root', 'main', 'stats', 'energy', 'stargate', 'progress' }

local isConnectedCheckbox = dom { 'root', 'main', 'stats', 'status', 'isConnected' }
local isWormholeCheckbox = dom { 'root', 'main', 'stats', 'status', 'isWormhole' }
local isDialingOutCheckbox = dom { 'root', 'main', 'stats', 'status', 'isDialingOut' }
local openTimeLabel = dom { 'root', 'main', 'stats', 'status', 'openTime' }
local chevronsLabel = dom { 'root', 'main', 'stats', 'status', 'chevrons' }
local connectedNameLabel = dom { 'root', 'main', 'stats', 'status', 'connectedName' }
local connectedAddressLabel = dom { 'root', 'main', 'stats', 'status', 'connectedAddress' }

local function updateConnectedAddresds(stats)
	local address = stats.advanced.connectedAddress
	if not next(address) then
		connectedNameLabel:setText("")
	elseif stats.basic.isWormholeOpen or stats.basic.isDialingOut then
		connectedNameLabel:setText(addressesState.value:getname(address, stats.galaxies) or "")
	end
	connectedAddressLabel:setText(addresses.tostring(address))
end

local function populateLookupTable(lookup, data)
	for _, value in ipairs(data) do
		lookup[value] = true
	end
end

local maxSymbolByStargate = {
	["sgjourney:universe_stargate"] = 35;
}

local function updateDialButtons(stats)
	local lookup = {}
	populateLookupTable(lookup, stats.dialedAddress)
	populateLookupTable(lookup, stats.addressBuffer)
	local maxSymbol = maxSymbolByStargate[stats.basic.type] or 38
	for i=1, maxSymbol do
		local button = dialFrame:getObject("s"..i)
		local color = lookup[i] and colors.orange or colors.gray
		button:setBackground(color)
	end
	for i=maxSymbol + 1, 38 do
		local button = dialFrame:getObject("s"..i)
		button:setBackground(colors.black)
	end
	local color = stats.pooPressed and colors.orange or colors.gray
	pooButton:setBackground(color)
end

local function updateStats(stats)
	versionLabel:setText("psg "..version.."; sgs "..(stats.version or "?"))
	generationLabel:setText(tostring(stats.basic.generation))
	typeLabel:setText(tostring(stats.basic.type))
	variantLabel:setText(tostring(stats.basic.variant))
	local localAddress = getLocalAddress(stats)
	if localAddress then
		localAddressLabel:setText(addresses.tostring(localAddress))
	else
		localAddressLabel:setText("N/A")
	end
	feedbackCodeLabel:setText(tostring(stats.basic.recentFeedbackCode))
	if stats.crystal then
		feedbackMessageLabel:setText(stats.crystal.recentFeedbackName)
	else
		feedbackMessageLabel:setText(feedback[stats.basic.recentFeedbackCode] or "N/A")
	end

	energyLabel:setText(tostring(stats.basic.energy).." FE")
	stargateEnergyLabel:setText(tostring(stats.basic.stargateEnergy).." FE")
	targetEnergyLabel:setText(tostring(stats.basic.energyTarget).." FE")
	if stats.basic.stargateEnergy > stats.basic.energyTarget then
		energyProgressbar:setProgress(100)
	else
		energyProgressbar:setProgress(stats.basic.stargateEnergy/stats.basic.energyTarget*100)
	end
	local energyCapacity = stats.basic.energyCapacity;
	if energyCapacity then
		energyCapacityLabel:setText(tostring(energyCapacity).." FE")
		energyInterfaceProgressbar:setProgress(stats.basic.energy/energyCapacity*100)
	else
		energyCapacityLabel:setText("N/A")
		energyInterfaceProgressbar:setProgress(0)
	end

	isConnectedCheckbox:setValue(stats.basic.isConnected)
	isWormholeCheckbox:setValue(stats.basic.isWormholeOpen)
	isDialingOutCheckbox:setValue(stats.basic.isDialingOut)
	openTimeLabel:setValue(tostring(stats.basic.openTime).." ticks")
	chevronsLabel:setText(tostring(stats.basic.chevronsEngaged))
	if stats.advanced then
		updateConnectedAddresds(stats)
	else
		connectedAddressLabel:setText("N/A")
		connectedNameLabel:setText("")
	end
end

job.livedata.subscribe(statsProperty, function(stats)
	if stats then
		updateDialButtons(stats)
		updateStats(stats)
		updateDialAddress(stats)
		updateDialButtonText(stats)
		mainFrame:show()
	else
		mainFrame:hide()
	end
end)

-- stats end

local shouldAuthorizeProperty = job.livedata.combine(function(stats)
	if not stats then
		return nil
	end
	local basic = stats.basic
	if basic.isWormholeOpen and basic.isDialingOut then
		return stats.id
	else
		return nil
	end
end, statsProperty)

job.livedata.subscribe(serverIdProperty, function(id)
	loadAddresses()
	stargate._state.server = id
end)

job.livedata.subscribe(addressesState, function()
	loadAddresses()
end)

local lastJob = job.async(function()end)

job.livedata.subscribe(shouldAuthorizeProperty, function(shouldAuthorize)
	lastJob:cancel()
	if shouldAuthorize then
		lastJob = job.running()
		local nonce = vault.gen_nonce()
		local ok, response = pcall(job.retry, 5, otherside.info, nonce)
		if ok then
			local valid, reason = vault.verify(nonce, response)
			local message = textutils.unserialise(response.message)
			local isIrisClosed = message.payload.isIrisClosed
			if valid and not isIrisClosed then
				return
			end
			local verificationMessage
			if valid then
				verificationMessage = "Known destination"
			else
				verificationMessage = "WARN: "..reason
			end
			local irisMessage
			local acceptText
			if isIrisClosed then
				irisMessage = "Iris is closed!"
				acceptText = "Open iris"
			else
				irisMessage = "Iris is opened, trust?"
				acceptText = false
			end
			local doOpen = modalMutex:with_lock(modal.alert,
				{
					"Dest: ".. keys.fingerprint(message.key);
					verificationMessage;
					irisMessage;
				},
				acceptText, "Cancel"
			)
			if doOpen then
				local key = vault.private_key()
				if not key then
					while true do
						local password = modalMutex:with_lock(modal.passwd)
						if not password then
							return
						end
						key, reason = vault.private_key(password)
						if key then
							break
						end
						modalMutex:with_lock(modal.alert, {reason}, nil, "Retry")
					end
				end
				local request = vault.make_auth_request(key, message.session)
				ok, reason = otherside.auth(request)
				if not ok then
					modalMutex:with_lock(modal.alert, {"NOT AUTHORIZED:", reason}, false, "OK")
				else
					modalMutex:with_lock(modal.alert, {"Authorized!"}, false, "OK")
				end
			end
		elseif response:sub(-10) == "Terminated" then
			error("Terminated", 0)
		else
			modalMutex:with_lock(modal.alert, {"No response!", "Iris state is unknown!"}, false, "OK")
		end
	end
end)

local function spawnHaltTimeout()
	return job.async(function()
		sleep(TIMEOUT)
		statsProperty:set(nil)
	end)
end

local haltJob = spawnHaltTimeout()

local messagesSemaphore = concurrent.semaphore(10)

rpc.subscribe_network(modem, CHANNEL_EVENT, function(event, meta)
	local distance = meta.distance
	if not distance then
		-- ignore ender modem messages
		return
	end
	local type = event.type
	local data = event.data
	if type == 'discover' then
		local stats = statsProperty.value
		if stats and stats.id ~= data.id and distance > stats.distance then
			-- prefer closest PSG server
			return
		end
		haltJob:cancel()
		haltJob = spawnHaltTimeout()
		data.distance = distance
		statsProperty:set(data)
	elseif type == 'message' then
		local message = data
		local decoded = textutils.unserialise(message)
		if _G.type(decoded) == 'table' and decoded.magic == 'rpc' then
			othersideResponses:send(decoded)
		else
			messagesSemaphore:with_try_lock(modalMutex.with_lock, modalMutex, modal.message, "Received Message", message)
		end
	end
end)

job.async(basalt.autoUpdate)

do
	local fastElement = dom { 'root', 'main', 'addressbook', 'fast' }
	fastElement:setValue(fastDialModeInit)
	dom { 'root', 'version' }:setText(version)
	if addressbook.resolve_location() == 'file' then
		(dom { 'root', 'editAddrsA' }):show();
		(dom { 'root', 'main', 'addressbook', 'editAddrsB' }):show()
	end
end

end)
