function Packet:Register(id, componentId, oldValue)
	local self: EntityPacket = self -- remove
	local cursor = self.cursor
	local Entities = self.Entities
	local LookUp = self.LookUp
	
	local unique = id > componentId and id * id + id + componentId or componentId * componentId + id
	local registered = LookUp[unique]
	if registered then
		Entities[registered] = oldValue
		return
	end
	
	local cursor3 = cursor + 2
	
	Entities[cursor] = id
	Entities[cursor + 1] = componentId
	Entities[cursor3] = oldValue

	LookUp[unique] = cursor3

	self.cursor += 3
end

function Packet:CompileData()
	local cursor = self.cursor
	if cursor == 1 then return end
	
	local Entities = self.Entities
	local LookUp = self.LookUp
	local Objects = self.Objects
	
	local cursor1 = cursor - 1
	
	local maxIdSize = 0
	local maxChangeSize = 1
	local maxComponentBitSize = 0
	
	local packetSize = 10
	
	for index = 1, cursor1, 3 do
		local index2 = index + 1
		local index3 = index + 2
		
		local id = Entities[index]
		local componentName = Entities[index2]
		local oldValue = Entities[index3]
		local currentValue = Objects[id]["LookUpLocation"][componentName]
		
		local Component = StringToComponent[componentName]
		local componentData, value
		
		if currentValue and oldValue then
			local delta = currentValue - oldValue
			local deltaZigZag = (delta >= 0) and (delta + delta) or (- delta - delta - 1)
			
			if currentValue and oldValue and deltaZigZag < abs(currentValue) then
				local comp2 = Component[2]
				if comp2 then componentData = comp2 else

					local comp4 = Component[4]
					for i = 1, #comp4 - 2, 2 do
						local nextMin = comp4[i + 2]
						local data = comp4[i + 1]
						if delta < nextMin then componentData = data break end
					end
				end
				value = deltaZigZag
			else
				local comp1 = Component[1]
				if comp1 then componentData = comp1 else

					local comp3 = Component[3]
					for i = 1, #comp3 - 2, 2 do
						local nextMin = comp3[i + 2]
						local data = comp3[i + 1]
						if currentValue < nextMin then componentData = data break end
					end
				end
				value = currentValue
			end
		else
			local comp1 = Component[1]
			if comp1 then componentData = comp1 else

				local comp3 = Component[3]
				for i = 1, #comp3 - 2, 2 do
					local nextMin = comp3[i + 2]
					local data = comp3[i + 1]
					if currentValue < nextMin then componentData = data break end
				end
			end
			value = currentValue
		end
		
		Entities[index2] = componentData
		Entities[index3] = value
		
		local componentBit = componentData[2]
		if componentBit > maxComponentBitSize then maxComponentBitSize = componentBit end
		
		local valueBit = componentData[3]
		packetSize += valueBit
		
		local state = LookUp[id]
		if not state or state > 0 then
			if id > maxIdSize then maxIdSize = id end
			
			LookUp[id] = -cursor
			Entities[cursor] = valueBit
			Entities[cursor + 1] = 1
			cursor += 2
		else
			local start = -state
			local start1 = start + 1
			Entities[start] += valueBit
			
			local changeCount = Entities[start1] + 1
			Entities[start1] = changeCount
			
			if changeCount > maxChangeSize then maxChangeSize = changeCount end
		end
	end
	
	local maxIdBitSize = floor(log(maxIdSize, 2)) + 1
	local maxChangeBitSize = floor(log(maxChangeSize, 2)) + 1
	
	packetSize += cursor1 / 3 * maxComponentBitSize + (cursor - cursor1 - 1) / 2 * (maxIdBitSize + maxChangeBitSize)
	
	local packet = bufferCreate(ceil(packetSize / 8))
	local writeCursor = 1
	
	writeBits(packet, writeCursor, 4, maxIdBitSize - 1)
	writeCursor += 4
	writeBits(packet, writeCursor, 3, maxChangeBitSize - 1)
	writeCursor += 3
	writeBits(packet, writeCursor, 3, maxComponentBitSize - 1)
	writeCursor += 3
	
	local newCount = 1
	for index = 1, cursor1, 3 do
		local id = Entities[index]
		local componentData = Entities[index + 1]
		local valueBit = componentData[3]
		
		local state = LookUp[id]
		if state > 0 then
			local continueCursor: number = state
			
			writeBits(packet, continueCursor, maxComponentBitSize, componentData[1]) -- component id
			continueCursor += maxComponentBitSize
			
			writeBits(packet, continueCursor, valueBit, Entities[index + 2]) -- value
			LookUp[id] = continueCursor + valueBit
		else
			local metaIndex = cursor1 + newCount
			local changeCount = Entities[metaIndex + 1]
			local nextWrite = writeCursor + maxIdBitSize + maxChangeBitSize + changeCount * (maxComponentBitSize) + Entities[metaIndex]
			
			writeBits(packet, writeCursor, maxIdBitSize, id) -- id
			writeCursor += maxIdBitSize
			
			writeBits(packet, writeCursor, maxChangeBitSize, changeCount) -- change count
			writeCursor += maxChangeBitSize
			
			writeBits(packet, writeCursor, maxComponentBitSize, componentData[1]) -- component id
			writeCursor += maxComponentBitSize
			
			writeBits(packet, writeCursor, valueBit, Entities[index + 2]) -- value
			LookUp[id] = writeCursor + valueBit
			writeCursor = nextWrite
			
			newCount += 2
		end
	end
	
	return packet
end