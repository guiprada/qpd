-- population_io.lua
-- Save and load a GeneticPopulation (NEAT) to/from disk.
--
-- File written: <run_dir>/population.lua
-- Format: a Lua file that returns a plain table (no metatables, no cycles).
-- Load with: local data = loadfile(path)()
--
-- What is saved:
--   innovation_manager      – Innovation_manager registry (restore first!)
--   species                 – live species, each with history + leader genome
--   specie_threshold        – compatibility threshold
--   history                 – GeneticPopulation rolling best-performer list
--   history_fitness_sum     – cached sum
--   active_size             – _active_size
--   population_size         – _population_size
--   genetic_population_size – _genetic_population_size
--   count                   – total replacements so far (generation counter)
--
-- Usage:
--   local pop_io = require "qpd.population_io"
--   pop_io.save(run_dir, genetic_population)   -- checkpoint
--   local data = pop_io.load(run_dir)          -- raw table
--   pop_io.restore(genetic_population, data)   -- wire it back up

local pop_io = {}

local ANN = require "qpd.ann_neat"

-- ============================================================
-- Strategy-folder naming
-- ============================================================
-- Derives a human-readable folder name from the game conf so runs are
-- grouped by experiment type automatically under runs/.
function pop_io.strategy_name(conf)
	local parts = {}
	if conf.autoplayer_neat_enable then
		table.insert(parts, "neat")
	else
		table.insert(parts, "fixed")
	end
	if conf.autoplayer_ann_mode and conf.autoplayer_ann_mode ~= "" then
		table.insert(parts, tostring(conf.autoplayer_ann_mode))
	end
	if conf.autoplayer_fitness_mode and conf.autoplayer_fitness_mode ~= "" then
		table.insert(parts, tostring(conf.autoplayer_fitness_mode))
	end
	if #parts == 0 then return "unknown" end
	-- Replace whitespace and non-safe chars with underscores.
	local name = table.concat(parts, "_")
	return name:gsub("[^%w_%-]", "_")
end

-- ============================================================
-- Lua-literal serializer
-- ============================================================
-- Converts a plain table (numbers, strings, booleans, nested tables) to a
-- Lua source string.  No circular refs or metatables supported.
local function _val(v, indent)
	local t = type(v)
	if t == "number" then
		return string.format("%.17g", v)
	elseif t == "string" then
		return string.format("%q", v)
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "nil" then
		return "nil"
	elseif t == "table" then
		local lines = {"{"}
		local inner = indent .. "  "

		-- Find the contiguous array length.
		local max_n = 0
		for k in pairs(v) do
			if type(k) == "number" and k == math.floor(k) and k >= 1 then
				if k > max_n then max_n = k end
			end
		end
		-- Array part in order.
		for i = 1, max_n do
			if v[i] ~= nil then
				lines[#lines+1] = inner .. _val(v[i], inner) .. ","
			end
		end
		-- Hash part sorted for deterministic output.
		local hkeys = {}
		for k in pairs(v) do
			local is_array = type(k) == "number" and k == math.floor(k) and k >= 1 and k <= max_n
			if not is_array then hkeys[#hkeys+1] = k end
		end
		table.sort(hkeys, function(a, b)
			local ta, tb = type(a), type(b)
			if ta ~= tb then return ta < tb end
			return tostring(a) < tostring(b)
		end)
		for _, k in ipairs(hkeys) do
			local ks = (type(k) == "string" and k:match("^[%a_][%w_]*$"))
				and k or ("[" .. _val(k, inner) .. "]")
			lines[#lines+1] = inner .. ks .. " = " .. _val(v[k], inner) .. ","
		end
		lines[#lines+1] = indent .. "}"
		return table.concat(lines, "\n")
	else
		error("population_io: cannot serialize type: " .. t)
	end
end

local function _write_table(file, tbl)
	file:write("return ")
	file:write(_val(tbl, ""))
	file:write("\n")
end

-- ============================================================
-- Internal helpers
-- ============================================================

local function _serialize_history_entry(entry)
	return {
		fitness   = entry._fitness,
		specie_id = entry._specie_id,
		genome    = entry._genome and entry._genome:serialize() or nil,
	}
end

local function _serialize_species(species_map)
	local out = {}
	for id, sp in pairs(species_map) do
		if sp and not sp._extinct then
			local history = {}
			for _, e in ipairs(sp._history) do
				history[#history+1] = _serialize_history_entry(e)
			end
			out[#out+1] = {
				id                  = id,
				history_fitness_sum = sp._history_fitness_sum,
				history             = history,
				leader_genome       = sp:get_leader():get_genome():serialize(),
			}
		end
	end
	return out
end

-- ============================================================
-- Public API
-- ============================================================

-- Writes a full checkpoint of genetic_population to <run_dir>/population.lua.
function pop_io.save(run_dir, genetic_population)
	local species_data = {}
	if genetic_population._species then
		species_data = _serialize_species(genetic_population._species)
	end

	local history_data = {}
	for _, e in ipairs(genetic_population._history) do
		history_data[#history_data+1] = _serialize_history_entry(e)
	end

	local snapshot = {
		innovation_manager      = ANN.get_innovation_state(),
		species                 = species_data,
		specie_threshold        = genetic_population._specie_threshold,
		history                 = history_data,
		history_fitness_sum     = genetic_population._history_fitness_sum,
		active_size             = genetic_population._active_size,
		population_size         = genetic_population._population_size,
		genetic_population_size = genetic_population._genetic_population_size,
		count                   = genetic_population._count,
	}

	local path = run_dir .. "/population.lua"
	local file, err = io.open(path, "w")
	if not file then
		print("[ERROR] population_io.save: cannot open " .. path .. ": " .. tostring(err))
		return false
	end
	_write_table(file, snapshot)
	file:close()
	print(string.format("[pop_io] saved  gen=%d  species=%d  history=%d  -> %s",
		math.floor(genetic_population._count / math.max(genetic_population._active_size, 1)),
		#species_data, #history_data, path))
	return true
end

-- Reads and evaluates <run_dir>/population.lua, returning the raw data table.
function pop_io.load(run_dir)
	local path = run_dir .. "/population.lua"
	local chunk, err = loadfile(path)
	if not chunk then
		print("[ERROR] population_io.load: cannot load " .. path .. ": " .. tostring(err))
		return nil
	end
	local ok, data = pcall(chunk)
	if not ok then
		print("[ERROR] population_io.load: error running " .. path .. ": " .. tostring(data))
		return nil
	end
	return data
end

-- Applies a previously saved snapshot to an (already constructed) GeneticPopulation.
-- Restores Innovation_manager, all species with their histories, and the
-- population-level history.  The live _population actor slots retain
-- their freshly-initialised genomes and will be replaced normally by
-- GeneticPopulation:replace() as soon as each actor dies — at that point
-- crossover will draw from the restored gene pool.
function pop_io.restore(genetic_population, data)
	-- 1. Innovation_manager must come first so genome reconstruction reuses
	--    existing IDs instead of minting new (colliding) ones.
	ANN.load_innovation_state(data.innovation_manager)

	local function ann_from(genome_data)
		return ANN.from_genome_data(genome_data)
	end

	-- 2. Rebuild species.
	if data.species and genetic_population._species then
		for _, sp_data in ipairs(data.species) do
			local leader_ann = ann_from(sp_data.leader_genome)

			-- speciate() with force_new=true skips the compatibility check and
			-- always creates a fresh _Species with leader_ann as its leader.
			local new_specie = leader_ann:speciate(
				genetic_population:get_species(),
				genetic_population._specie_threshold,
				true)
			if new_specie then
				genetic_population:new_specie(new_specie)
			end

			-- Restore species history.
			local sp_obj = leader_ann._specie
			if sp_obj then
				sp_obj._history             = {}
				sp_obj._history_fitness_sum = sp_data.history_fitness_sum
				for _, he in ipairs(sp_data.history) do
					local ann = he.genome and ann_from(he.genome) or leader_ann
					sp_obj._history[#sp_obj._history+1] = {
						_fitness   = he.fitness,
						_genome    = ann:get_genome(),
						_specie_id = he.specie_id,
					}
				end
			end
		end
	end

	-- 3. Restore population-level history.
	genetic_population._history             = {}
	genetic_population._history_fitness_sum = data.history_fitness_sum or 0
	for _, he in ipairs(data.history) do
		local ann = he.genome and ann_from(he.genome) or nil
		genetic_population._history[#genetic_population._history+1] = {
			_fitness   = he.fitness,
			_genome    = ann and ann:get_genome() or nil,
			_specie_id = he.specie_id,
		}
	end

	-- 4. Scalar counters.
	genetic_population._count = data.count or 0

	print(string.format("[pop_io] restored  gen=%d  species=%d  history=%d",
		genetic_population:get_generation(),
		#data.species, #genetic_population._history))
end

return pop_io
