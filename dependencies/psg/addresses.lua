local setmetatable, ipairs, pairs = setmetatable, ipairs, pairs

---------------------------------------------

local addresses_index = {}

local addresses_meta = {
	__index = addresses_index;
}

local function addresses_tostring(address)
	return table.concat(address, '-')
end

local addresses = {
	tostring = addresses_tostring
}

local function galaxy_key(galaxy, address)
	return galaxy..":"..addresses_tostring(address)
end

function addresses.create(addressbook)
	local nameByAddress = {}

	for _, record in ipairs(addressbook.identity or {}) do
		nameByAddress[addresses_tostring(record.address)] = record.name
	end

	for _, record in ipairs(addressbook.position or {}) do
		local extragalactic = record.extragalactic
		if extragalactic then
			nameByAddress[addresses_tostring(extragalactic)] = record.name
		end
		for galaxy, address in pairs(record.interstellar or {}) do
			local key = galaxy_key(galaxy, address)
			nameByAddress[key] = record.name
		end
	end

	local obj = {
		addressbook = addressbook;
		nameByAddress = nameByAddress;
	}
	return setmetatable(obj, addresses_meta)
end

function addresses_index:interstellar(galaxies, solarSystem)
	local result = {}
	for _, solar in ipairs(self.addressbook.position or {}) do
		if solar.key ~= solarSystem then
			if solar.interstellar then
				for _, galaxy in ipairs(galaxies) do
					local address = solar.interstellar[galaxy]
					if address then
						local record = {
							name = solar.name or "?????",
							address = address
						}
						table.insert(result, record)
						break
					end
				end
			end
		end
	end
	return result
end

function addresses_index:extragalactic(galaxies)
	local result = {}
	for _, solar in ipairs(self.addressbook.position or {}) do
		if solar.extragalactic then
			local notSkip = true
			for _, galaxy in ipairs(galaxies) do
				if solar.interstellar[galaxy] then
					notSkip = false
					break
				end
			end
			if notSkip then
				local record = {
					name = solar.name or "?????",
					address = solar.extragalactic
				}
				table.insert(result, record)
			end
		end
	end
	return result
end

local function tableEquals(a, b)
	if #a == #b then
		for i = 1, #a do
			if a[i] ~= b[i] then
				return false
			end
		end
		return true
	else
		return false
	end
end

function addresses_index:direct(localAddress)
	local result = {}
	for _, record in ipairs(self.addressbook.identity or {}) do
		if not localAddress or not tableEquals(record.address, localAddress) then
			table.insert(result, record)
		end
	end
	return result
end

function addresses_index:getname_by_key(key)
	for _, solar in ipairs(self.addressbook.position or {}) do
		local name = solar.name
		if solar.key == key and name then
			return name
		end
	end
	return nil
end

function addresses_index:getname(address, galaxies)
	local n = #address
	if n == 6 then
		if galaxies then
			for _, galaxy in ipairs(galaxies) do
				local key = galaxy_key(galaxy, address)
				local name = self.nameByAddress[key]
				if name then
					return name
				end
			end
		end
		return nil
	else
		return self.nameByAddress[addresses.tostring(address)]
	end
end

return addresses
