local utils = {}

function utils.teste()
	print "tested .. sure"
end

function utils.table_merge(t1, t2)
	if t1 and t2 then
		for key, value in pairs(t2) do
			t1[key] = value
		end
	else
		print("ERROR: try to merge nil table")
	end
end

function utils.array_append(t1, t2)
	if t1 and t2 then
		for key, value in ipairs(t2) do
			t1[key + #t1] = value
		end
	else
		print("ERROR: try to append nil table")
	end
end

function utils.check_collision(x1,y1,w1,h1, x2,y2,w2,h2)
  return x1 < x2+w2 and
         x2 < x1+w1 and
         y1 < y2+h2 and
         y2 < y1+h1
end

function utils.dist(p1, p2)
    return ( (p1.x - p2.x)^2 + (p1.y - p2.y)^2 )^0.5
end

function utils.array_shuffler(array)
	for i=1,#array, 1 do
		local j = love.math.random(1, #array)
		array[i], array[j] = array[j], array[i]
	end
end

function utils.average( tables, indexer)
	-- returns the average of parameter indexer of a list of tables
	local lenght = #tables
	local average = 0
	for  i=1, lenght, 1 do
		average = average + tables[i][indexer]/lenght
	end
	return average
end

function utils.std_deviation(tables, indexer)
	local lenght = #tables
	local sum = 0
	local average = utils.average( tables, indexer )
	for  i=1, lenght, 1 do
		sum = sum + ( tables[i][indexer] - average )^2
	end
	local std_dev = sum^(1/2)
	return std_dev
end

function utils.get_highest( tables, indexer)
	local lenght = #tables
	local highest = 1
	for i=1, lenght, 1 do
		if(tables[i][indexer]> tables[highest][indexer])then
			highest = i
		end
	end
	return tables[highest]
end

function utils.get_lowest( tables, indexer)
	local lenght = #tables
	local lowest = 1
	for i=1, lenght, 1 do
		if(tables[i][indexer] < tables[lowest][indexer])then
			lowest = i
		end
	end
	return tables[lowest]
end

function utils.get_highest_index( tables, indexer)
	local lenght = #tables
	local highest = 1
	for i=1, lenght, 1 do
		if(tables[i][indexer]> tables[highest][indexer])then
			highest = i
		end
	end
	return highest
end

function utils.remove_key( table, key)
	for i=1,#table, 1 do
		if (table[i]== key) then
			table.remove(tables, i)
		end
	end
end

function utils.get_n_best( tables, indexer, n)
	local copy = {}
	for i=1, #tables, 1 do
		copy[i]= tables[i]
	end
	local highest_stack = {}

	local limit = 3
	if (#tables < limit) then
		limit = #tables
	end
	for i=1, limit, 1 do
		local new_top_index = utils.get_highest_index(copy, indexer)
		table.insert(highest_stack, tables[new_top_index])
		table.remove(copy, index)
	end
	return highest_stack
end

function utils.round_2_dec(value)
	if ( value >= 0 ) then
		return math.floor(value*100)/100
	else
		return math.ceil(value*100)/100
	end
end

function utils.midle_point(p1, p2)
	local midle = {}
	midle.x = (p1.x + p2.x)/2
	midle.y = (p1.y +p2.y)/2
	return midle
end

return utils
