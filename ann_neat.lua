-- Guilherme Cunha Prada 2022
local ANN = {}
ANN.__index = ANN

local qpd_gamestate = require "qpd.gamestate"
local qpd_table = require "qpd.table"
local qpd_random = require "qpd.random"
local ann_activation_functions = require "qpd.ann_activation_functions"

local MAX_LOOPBACK_LINK_TRIES = 5
local MAX_LINK_TRIES = 10
local MAX_NEURON_TRIES = 5

local Innovation_manager -- create singleton instance, will be initialized after _Innovation_manager implementation

local _genome_count = 0
local _species_count = 0

------------------------------------------------------------------------------- Types
local _link_types = {
	"forward",
	"recurrent",
	"looped_recurrent"
}

local _neuron_types = {
	"input",
	"hidden",
	"bias",
	"output",
	"none",
}

local _ann_run_types = {
	"snapshot",
	"active"
-- you have to select one of these types when updating the network
-- If snapshot is chosen the network depth is used to completely
-- flush the inputs through the network. active just updates the
-- network each time-step
}

-- internal functions
local function _get_random_link_weight_only_positive(scale)
	scale = scale or 1
	return qpd_random.random() * scale
end

local function _get_random_link_weight_maybe_negative(scale)
	scale = scale or 1
	return qpd_random.choose(-1, 1) * qpd_random.random() * scale
end

local _get_random_link_weight = _get_random_link_weight_only_positive

local function _get_random_activation_response(scale)
	scale = scale or 1
	return qpd_random.random() * scale
end

local function _get_unit_activation_response(scale)
	scale = scale or 1
	return scale
end

local _get_initial_activation_response = _get_random_activation_response

local function _innovation_sorter(a, b)
	return a._innovation_id < b._innovation_id
end

-- Internal Classes
-------------------------------------------------------------------------------
------------------------------------------------------------------------------- Link
local _Link_Gene = {}
_Link_Gene.__index = _Link_Gene

function _Link_Gene:new(input_neuron_gene, output_neuron_gene, weight, innovation_id, o)
	local o = o or {}
	setmetatable(o, self)

	o._input_neuron = input_neuron_gene
	o._output_neuron = output_neuron_gene
	o._weight = weight
	o._enabled = true
	o._innovation_id = innovation_id


	o._recurrent = false

	o._recurrent = o._input_neuron:is_link_recurrent(o._output_neuron)

	return o
end

function _Link_Gene:mutate(mutate_chance, mutate_percentage)
	self._weight = self._weight * (qpd_random.toss(mutate_chance) and (qpd_random.choose(-mutate_percentage, mutate_percentage) + 1) or 1)
end

function _Link_Gene:inherit(mutate_chance, mutate_percentage)
	local clone = qpd_table.clone(self)
	clone:mutate(mutate_chance, mutate_percentage)
	return clone
end

function _Link_Gene:get_weight()
	return self._weight
end

function _Link_Gene:is_enabled()
	return self._enabled
end

function _Link_Gene:set_enabled(value)
	self._enabled = value or true
end

function _Link_Gene:get_input_neuron()
	return self._input_neuron
end

function _Link_Gene:get_output_neuron()
	return self._output_neuron
end

function _Link_Gene:get_input_x()
	return self._input_neuron:get_x()
end

function _Link_Gene:get_input_y()
	return self._input_neuron:get_y()
end

function _Link_Gene:get_output_x()
	return self._output_neuron:get_x()
end

function _Link_Gene:get_output_y()
	return self._output_neuron:get_y()
end

function _Link_Gene:get_id()
	return self._innovation_id
end

function _Link_Gene:is_recurrent()
	return self._recurrent
end

function _Link_Gene:type()
	return "_Link_Gene"
end

-------------------------------------------------------------------------------
local _Link = {}
_Link.__index = _Link

function _Link:new(input_neuron, output_neuron, weight, recurrent, o)
	local o = o or {}
	setmetatable(o, self)

	o._input_neuron = input_neuron
	o._output_neuron = output_neuron
	o._weight = weight
	o._recurrent = recurrent

	return o
end

function _Link:new_from_gene(link_gene, layers, neuron_id_to_position)
	local input_neuron_position  = neuron_id_to_position[link_gene:get_input_neuron():get_id()]
	local output_neuron_position = neuron_id_to_position[link_gene:get_output_neuron():get_id()]

	local input_neuron = layers[input_neuron_position.x][input_neuron_position.y]
	local output_neuron = layers[output_neuron_position.x][output_neuron_position.y]

	return _Link:new(input_neuron, output_neuron, link_gene:get_weight(), link_gene:is_recurrent())
end

function _Link:get_input_neuron()
	return self._input_neuron
end

function _Link:get_output_neuron()
	return self._output_neuron
end

function _Link:get_output()
	return self._weight * self:get_input_neuron():get_output()
end

function _Link:type()
	return "_Link"
end

-------------------------------------------------------------------------------
------------------------------------------------------------------------------- Neuron
local _Neuron_Gene = {}
_Neuron_Gene.__index = _Neuron_Gene

function _Neuron_Gene:new(type, recurrent, activation_response, activation_function_name, activation_function_parameters, innovation_id, x, y, o)
	local o = o or {}
	setmetatable(o, self)

	o._type = type
	o._recurrent = recurrent
	o._activation_response = activation_response
	o._activation_function_name = activation_function_name
	o._activation_function_parameters = activation_function_parameters
	o._innovation_id = innovation_id
	o._x = x
	o._y = y

	return o
end

function _Neuron_Gene:mutate(mutate_chance, mutate_percentage)
	self:set_activation_response(self:get_activation_response() * (qpd_random.toss(mutate_chance) and (qpd_random.choose(-mutate_percentage, mutate_percentage) + 1) or 1))
end

function _Neuron_Gene:inherit(mutate_chance, mutate_percentage)
	local clone = qpd_table.clone(self)
	clone:mutate(mutate_chance, mutate_percentage)
	return clone
end

function _Neuron_Gene:is_link_recurrent(other)
	if self:get_x() > other:get_x() then
		return true
	end
	if self:get_x() == other:get_x() then
		if self:get_y() >= other:get_y() then
			return true
		end
	end

	return false
end

function _Neuron_Gene:get_activation_response()
	return self._activation_response
end

function _Neuron_Gene:set_activation_response(value)
	self._activation_response = value
end

function _Neuron_Gene:get_activation_function()
	return ann_activation_functions[self._activation_function_name]
end

function _Neuron_Gene:get_activation_function_parameters()
	return self._activation_function_parameters
end

function _Neuron_Gene:get_x()
	return self._x
end

function _Neuron_Gene:get_y()
	return self._y
end

function _Neuron_Gene:set_loopback(value)
	self._loopback = value or true
end

function _Neuron_Gene:is_loopback()
	return self._loopback
end

function _Neuron_Gene:get_id()
	return self._innovation_id
end

function _Neuron_Gene:get_neuron_type()
	return self._type
end

function _Neuron_Gene:type()
	return "_Neuron_Gene"
end

-------------------------------------------------------------------------------
local _Neuron = {}
_Neuron.__index = _Neuron

function _Neuron:new(type, innovation_id, input_links, output_links, activation_response, activation_function, activation_function_parameters, x, y, o)
	local o = o or {}
	setmetatable(o, self)

	o._input_links = input_links or {}
	o._output_links = output_links or {}

	o._innovation_id = innovation_id

	o._type = type

	o._activation_response = activation_response
	o._activation_function = activation_function
	o._activation_function_parameters = activation_function_parameters

	o._inputs = {}
	for i = 1, #o._input_links do
		o._inputs[i] = 0
	end
	o._activation_sum = 0
	o._activation_output = 0

	o._x = x
	o._y = y

	return o
end

function _Neuron:new_from_gene(neuron_gene)
	return _Neuron:new(
		neuron_gene:get_neuron_type(),
		neuron_gene:get_id(),
		nil,
		nil,
		neuron_gene:get_activation_response(),
		neuron_gene:get_activation_function(),
		neuron_gene:get_activation_function_parameters(),
		neuron_gene:get_x(),
		neuron_gene:get_y())
end

function _Neuron:add_input_link(link)
	table.insert(self._input_links, link)
	table.insert(self._inputs, 0)
end

function _Neuron:add_output_link(link)
	table.insert(self._output_links, link)
end

function _Neuron:update(input)
	if input then
		self._activation_sum = input
		self._activation_output = self:get_activation_function()(self:get_activation_sum(), self:get_activation_response(), self:get_activation_function_parameters())
	else
		self._activation_sum = 0
		for i = 1, #self._input_links do
			local this_link = self._input_links[i]
			self._activation_sum = self._activation_sum + this_link:get_output()
		end
		self._activation_output = self:get_activation_function()(self:get_activation_sum(), self:get_activation_response(), self:get_activation_function_parameters())
	end
end

function _Neuron:get_activation_response()
	return self._activation_response
end

function _Neuron:get_activation_function()
	return self._activation_function
end

function _Neuron:get_activation_function_parameters()
	return self._activation_function_parameters
end

function _Neuron:get_activation_sum()
	return self._activation_sum
end

function _Neuron:get_output()
	return self._activation_output
end

function _Neuron:get_x()
	return self._x
end

function _Neuron:get_y()
	return self._y
end

function _Neuron:get_id()
	return self._innovation_id
end

function _Neuron:get_neuron_type()
	return self._type
end

function _Neuron:type()
	return "_Neuron"
end

-------------------------------------------------------------------------------
------------------------------------------------------------------------------- Innovation Manager
local _Innovation_manager = {}
_Innovation_manager.__index = _Innovation_manager

function _Innovation_manager:new(o)
	local o = o or {}
	setmetatable(o, self)

	o._id_count = 0
	o._links = {}
	o._neurons = {}

	return o
end

function _Innovation_manager:_new_innovation()
	self._id_count = self._id_count + 1
	return self._id_count
end

function _Innovation_manager:get_link_innovation_id(input_neuron_gene, output_neuron_gene)
	local input_neuron_id = input_neuron_gene:get_id()
	local output_neuron_id = output_neuron_gene:get_id()
	local innovation_id

	if self._links[input_neuron_id] then
		if self._links[input_neuron_id][output_neuron_id] then
			innovation_id = self._links[input_neuron_id][output_neuron_id]
		end
	else
		self._links[input_neuron_id] = {}
	end

	if not innovation_id then
		innovation_id = self:_new_innovation()
		self._links[input_neuron_id][output_neuron_id] = innovation_id
	end

	return innovation_id
end

function _Innovation_manager:get_neuron_innovation_id(x, y)
	local innovation_id
	if self._neurons[x]	then
		if self._neurons[x][y] then
			innovation_id = self._neurons[x][y]
		end
	else
		self._neurons[x] = {}
	end

	if not innovation_id then
		innovation_id = self:_new_innovation()
		self._neurons[x][y] = innovation_id
	end

	return innovation_id
end

function _Innovation_manager:type()
	return "_Innovation_manager"
end
-- assign singleton instance
Innovation_manager = _Innovation_manager:new()

-------------------------------------------------------------------------------
------------------------------------------------------------------------------- Species
local _Species = {}
_Species.__index = _Species

function _Species:new(leader, o)
	local o = o or {}
	setmetatable(o, self)

	o._extinct = false
	o._leader = leader
	o._fitness_attribute = "_fitness"
	o._history_fitness_sum = 0
	o._history = {}
	_species_count = _species_count + 1
	o._id = _species_count
	-- o._best_fitness = o._leader:get_fitness()
	-- o._av_fitness = o._best_fitness
	-- o._generations_with_no_fitness_improvement = 0
	-- o._age = 0
	-- o._required_spawns = 0
	print("New Species :) ", o._id)
	return o
end

function _Species:get_leader()
	if self._extinct then
		print("Tried to :get_leader() on extinct species!")
	end
	return self._leader
end

function _Species:roulette()
	if self._extinct then
		print("Tried to :roulette() on extinct species!")
		return nil
	end

	local total_fitness = self._history_fitness_sum

	local slice = total_fitness * qpd_random.random()
	local sum = 0

	for _, actor in ipairs(self._history) do
		sum = sum + actor._fitness
		if (sum >= slice) then
			return actor
		end
	end

	print("[WARN] - GeneticPopulation:_roulette() - Returning last actor!")
	return qpd_random.choose_list(self._history) or self:get_leader()
end

function _Species:add_to_history(actor, size_limit)
	local actor_history = actor:get_history()

	-- if #self._history > math.floor(self._population_size/10) then
	if #self._history > size_limit then
		local lowest, lowest_index = qpd_table.get_lowest(self._history, self._fitness_attribute)

		if actor_history._fitness > lowest._fitness then
			self._history_fitness_sum = self._history_fitness_sum - lowest._fitness

			self._history[lowest_index] = actor_history
			self._history_fitness_sum = self._history_fitness_sum + actor_history._fitness
		end
	else
		table.insert(self._history, actor_history)
		self._history_fitness_sum = self._history_fitness_sum + actor_history._fitness
	end
end

function _Species:get_compatibility_score(ann)
	return ann:get_genome():get_compatibility_score(self:get_leader():get_genome())
end

function _Species:purge()
	self._extinct = true
	self._leader = nil
	self._fitness_attribute = nil
	self._history_fitness_sum = nil
	self._history = nil
	print("Species extinguished: ", self._id)
	self._id = nil
end

function _Species:adjusted_fitnesses()
	-- this method boosts the fitnesses of the young, penalizes the
	-- fitnesses of the old and then performs fitness sharing over
	-- all the members of the species(BUCKLAND, 392)

	-- 	void CSpecies::AdjustFitnesses()
	-- 	{
	-- 		double total = 0;
	-- 		for (int gen=0; gen<m_vecMembers.size(); ++gen) {
	-- 			double fitness = m_vecMembers[gen]->Fitness();
	--
	-- 			//boost the fitness scores if the species is young
	-- 			if (m_iAge < CParams::iYoungBonusAgeThreshhold) {
	-- 				fitness *= CParams::dYoungFitnessBonus;
	-- 			}
	--
	-- 			//punish older species
	-- 			if (m_iAge > CParams::iOldAgeThreshold) {
	-- 				fitness *= CParams::dOldAgePenalty;
	-- 			}
	--
	-- 			total += fitness;
	--
	-- 			//apply fitness sharing to adjusted fitnesses
	-- 			double AdjustedFitness = fitness/m_vecMembers.size();
	-- 			m_vecMembers[gen]->SetAdjFitness(AdjustedFitness);
	-- 		}
	-- 	}
end

function _Species:get_id()
	return self._id
end

function _Species:type()
	return "_Species"
end
-------------------------------------------------------------------------------
------------------------------------------------------------------------------- Genome
local _Genome = {}
_Genome.__index = _Genome

function _Genome:new(neurons, links, hidden_layers_activation_function_name, hidden_layers_activation_function_parameters, o)
	local o = o or {}
	setmetatable(o, self)

	_genome_count = _genome_count + 1
	o._id = _genome_count

	o._neurons = neurons
	o._links = links
	o:_sort_genes()

	o:reset_layer_config()

	o._hidden_layers_activation_function_name = hidden_layers_activation_function_name

	o._hidden_layers_activation_function_parameters = hidden_layers_activation_function_parameters

	-- o._amount_to_spawn = 0
	return o
end

function _Genome:_init_n_inputs()
	local n_inputs = 0
	for i = 1, #self._neurons do
		local this_neuron = self._neurons[i]
		if this_neuron:get_neuron_type() == "input" then
			n_inputs = n_inputs + 1
		end
	end
	self._n_inputs = n_inputs
end

function _Genome:_init_n_outputs()
	local n_outputs = 0
	for i = 1, #self._neurons do
		local this_neuron = self._neurons[i]
		if this_neuron:get_neuron_type() == "output" then
			n_outputs = n_outputs + 1
		end
	end
	self._n_outputs = n_outputs
end

function _Genome:_init_unique_layers()
	local unique_layer_dict = {}
	for i = 1, #self._neurons do
		local this_layer = self._neurons[i]:get_x()
		if not unique_layer_dict[this_layer] then
			unique_layer_dict[this_layer] = true
		end
	end

	-- find and sort layers
	local unique_layers = {}
	for layer, _ in pairs(unique_layer_dict) do
		unique_layers[#unique_layers + 1] = layer
	end

	-- table.sort(unique_layers)

	self._unique_layers = unique_layers
end

function _Genome:reset_layer_config()
	self:_init_n_inputs()
	self:_init_n_outputs()
	self:_init_unique_layers()
end

function _Genome:crossover(dad, mutate_chance, mutate_percentage, chance_add_neuron, chance_add_link, chance_loopback, crossover)
	-- mom is always fitter or shorter
	local mom = self
	if crossover == false then
		dad = mom
	end

	local neurons = {}
	-- neurons
	local mom_index = 1
	local dad_index = 1

	local mom_neuron_gene = mom._neurons[mom_index]
	local dad_neuron_gene = dad._neurons[dad_index]
	while mom_neuron_gene do -- or dad_neuron_gene do
		if mom_neuron_gene and dad_neuron_gene then
			if mom_neuron_gene:get_id() == dad_neuron_gene:get_id() then
				local chosen = qpd_random.choose(mom_neuron_gene, dad_neuron_gene)
				local new_neuron = chosen:inherit(mutate_chance, mutate_percentage)
				table.insert(neurons, new_neuron)
				mom_index = mom_index + 1
				dad_index = dad_index + 1
			elseif mom_neuron_gene:get_id() < dad_neuron_gene:get_id() then
				local new_neuron = mom_neuron_gene:inherit(mutate_chance, mutate_percentage)
				table.insert(neurons, new_neuron)
				mom_index = mom_index + 1
			else
				dad_index = dad_index + 1
			end
		elseif mom_neuron_gene then
			local new_neuron = mom_neuron_gene:inherit(mutate_chance, mutate_percentage)
			table.insert(neurons, new_neuron)
			mom_index = mom_index + 1
		end

		mom_neuron_gene = mom._neurons[mom_index]
		dad_neuron_gene = dad._neurons[dad_index]
	end

	-- links
	local links = {}
	mom_index = 1
	dad_index = 1

	local mom_link_gene = mom._links[mom_index]
	local dad_link_gene = dad._links[dad_index]
	while mom_link_gene do -- or dad_link_gene do
		if mom_link_gene and dad_link_gene then
			if mom_link_gene:get_id() == dad_link_gene:get_id() then
				local chosen = qpd_random.choose(mom_link_gene, dad_link_gene)
				local new_link = chosen:inherit(mutate_chance, mutate_percentage)
				table.insert(links, new_link)
				mom_index = mom_index + 1
				dad_index = dad_index + 1
			elseif mom_link_gene:get_id() < dad_link_gene:get_id() then
				local new_link = mom_link_gene:inherit(mutate_chance, mutate_percentage)
				table.insert(links, new_link)
				mom_index = mom_index + 1
			else
				dad_index = dad_index + 1
			end
		elseif mom_link_gene then
			local new_link = mom_link_gene:inherit(mutate_chance, mutate_percentage)
			table.insert(links, new_link)
			mom_index = mom_index + 1
		end

		mom_link_gene = mom._links[mom_index]
		dad_link_gene = dad._links[dad_index]
	end

	local new_genome = _Genome:new(neurons, links, mom._hidden_layers_activation_function_name, mom._hidden_layers_activation_function_parameters)

	if qpd_random.toss(chance_add_neuron) then
		new_genome:add_neuron()
	end
	if qpd_random.toss(chance_add_link) then
		new_genome:add_link(chance_loopback)
	end

	for i = 1, #new_genome._links do
		local this_link = new_genome._links[i]
		if not new_genome:_is_link_valid(this_link) then
			print("ERROR - _Genome:crossover() - Genome has invalid link!")
			print("Link is enabled: ", this_link:is_enabled())
		end
	end
	print("neurons ", new_genome:get_neuron_count())
	print("links ", new_genome:get_link_count())

	return new_genome
end

function _Genome:get_neuron_count()
	return #self._neurons
end

function _Genome:get_link_count()
	return #self._links
end

function _Genome:get_gene_count()
	return self:get_neuron_count() + self:get_link_count()
end

function _Genome:get_n_inputs()
	return self._n_inputs
end

function _Genome:get_n_outputs()
	return self._n_outputs
end

function _Genome:_sort_links()
	table.sort(self._links, _innovation_sorter)
end

function _Genome:_sort_neurons()
	table.sort(self._neurons, _innovation_sorter)
end

function _Genome:_sort_genes()
	self:_sort_neurons()
	self:_sort_links()
end

function _Genome:_has_link(link_gene_id)
	-- self:_sort_links()
	for i = 1, #self._links do
		local this_link_gene_id = self._links[i]:get_id()
		if this_link_gene_id == link_gene_id then
			return true
		elseif this_link_gene_id > link_gene_id then -- the links are ordered, so we can do an early exit
			return false
		end
	end
	return false
end

function _Genome:_has_neuron(neuron_gene_id)
	-- self:_sort_neurons()
	for i = 1, #self._neurons do
		local this_neuron_gene_id = self._neurons[i]:get_id()
		if this_neuron_gene_id == neuron_gene_id then
			return true
		elseif this_neuron_gene_id > neuron_gene_id then -- the links are ordered, so we can do an early exit
			return false
		end
	end
	return false
end

function _Genome:_is_link_valid(link_gene)
	local input_neuron_gene_id = link_gene:get_input_neuron():get_id()
	if not self:_has_neuron(input_neuron_gene_id) then
		return false
	end

	local output_neuron_gene_id = link_gene:get_output_neuron():get_id()
	if not self:_has_neuron(output_neuron_gene_id) then
		return false
	end

	return true
end

function _Genome:create_link(input_neuron, output_neuron, innovation_id)
	if input_neuron and output_neuron then
		-- create link
		-- _Link_Gene:new(input_neuron_gene, output_neuron_gene, weight, innovation_id, o)
		local new_link = _Link_Gene:new(
			input_neuron,
			output_neuron,
			_get_random_link_weight(),
			innovation_id
		)
		if not self:_has_link(new_link:get_id()) then
			table.insert(self._links, new_link)
			self:_sort_links()
		end
	end
end

function _Genome:add_link(chance_loopback)
	local selected_input_neuron
	local selected_output_neuron
	local innovation_id

	-- check if we should attempt to create a loopback link
	if qpd_random.toss(chance_loopback) then
		-- create loopback
		-- find suitable neuron(no input, no bias and not already looped)
		local tries = MAX_LOOPBACK_LINK_TRIES
		while (tries > 0) do
			local neuron_index = qpd_random.random(#self._neurons)
			if 	self._neurons[neuron_index]:get_neuron_type() ~= "input" and
				self._neurons[neuron_index]:get_neuron_type() ~= "bias" and
				self._neurons[neuron_index]:is_loopback() then

				innovation_id = Innovation_manager:get_link_innovation_id(self._neurons[neuron_index]:get_id(), self._neurons[neuron_index]:get_id())
				if not self:_has_link(innovation_id) then
					tries = 0
					local selected_neuron = self._neurons[neuron_index]
					selected_neuron:set_loopback(true)
					selected_input_neuron = selected_neuron
					selected_output_neuron = selected_neuron
				end
			else
				tries = tries - 1
			end
		end
	else
		-- try to find to unlinked neurons
		local tries = MAX_LINK_TRIES
		while (tries > 0) do
			local input_neuron_index = qpd_random.random(#self._neurons)
			local output_neuron_index = qpd_random.random(#self._neurons)
			-- the output_neuron can not be an input
			-- they can not be the same
			if 	self._neurons[input_neuron_index]:get_id() ~= self._neurons[output_neuron_index]:get_id() and
				self._neurons[output_neuron_index]:get_neuron_type() ~= "input" then
				innovation_id = Innovation_manager:get_link_innovation_id(self._neurons[input_neuron_index], self._neurons[output_neuron_index])
				if not self:_has_link(innovation_id) then
					tries = 0
					selected_input_neuron = self._neurons[input_neuron_index]
					selected_output_neuron = self._neurons[input_neuron_index]
				end
			else
				tries = tries - 1
			end
		end
	end

	self:create_link(selected_input_neuron, selected_output_neuron, innovation_id)
end

function _Genome:add_neuron()
	local chosen_link
	-- if the genome is smaller than threshold we select with a bias towards older links to avoid a chaining effect
	local size_threshold = self:get_n_inputs() + self:get_n_outputs() + 5

	if self:get_gene_count() < size_threshold then
		-- choose a link with a bias towards the older links in the genome
		-- ChosenLink = RandInt(0, NumGenes()-1-(int)sqrt(NumGenes()));
		local tries = MAX_NEURON_TRIES
		while (tries > 0) do
			local n_links = #self._links
			local chosen_link_index = qpd_random.random(1, n_links - math.floor(math.sqrt(n_links)))
			chosen_link_index = (chosen_link_index >= 1) and chosen_link_index or 1
			chosen_link = self._links[chosen_link_index]

			-- link has to be enabled, not recurrent and does not have a bias input neuron
			local input_neuron = chosen_link:get_input_neuron()
			if	chosen_link:is_enabled() and
				(not chosen_link:is_recurrent()) and
				input_neuron:get_neuron_type() ~= "bias" then
					break
			else
				chosen_link = nil
			end
			tries = tries - 1
		end
	else
		local tries = MAX_NEURON_TRIES
		while (tries > 0) do
			local n_links = #self._links
			chosen_link = self._links[qpd_random.random(1, n_links)]

			-- link has to be enabled, not recurrent and does not have a bias input neuron
			local input_neuron = chosen_link:get_input_neuron()
			if 	chosen_link:is_enabled() and
				(not chosen_link:is_recurrent()) and
				input_neuron:get_neuron_type() ~= "bias" then
					break
			else
				chosen_link = nil
			end
			tries = tries - 1
		end
	end

	if chosen_link then
		-- disable link
		chosen_link:set_enabled(false)

		-- create new neuron
		local x = (chosen_link:get_input_x() + chosen_link:get_output_x())/2
		local y = (chosen_link:get_input_y() + chosen_link:get_output_y())/2

		local new_neuron_innovation_id = Innovation_manager:get_neuron_innovation_id(x, y)
		local new_neuron = _Neuron_Gene:new(
			"hidden",
			false,
			_get_initial_activation_response(1),
			self._hidden_layers_activation_function_name,
			self._hidden_layers_activation_function_parameters,
			new_neuron_innovation_id,
			x,
			y
		)
		table.insert(self._neurons, new_neuron)

		-- create new links
		local new_link_input_innovation_id = Innovation_manager:get_link_innovation_id(chosen_link:get_input_neuron(), new_neuron)
		local new_link_input = _Link_Gene:new(
			chosen_link:get_input_neuron(),
			new_neuron,
			_get_random_link_weight(),
			new_link_input_innovation_id
		)
		table.insert(self._links, new_link_input)

		local new_link_output_innovation_id = Innovation_manager:get_link_innovation_id(new_neuron, chosen_link:get_output_neuron())
		local new_link_output = _Link_Gene:new(
			new_neuron,
			chosen_link:get_output_neuron(),
			_get_random_link_weight(),
			new_link_output_innovation_id
		)
		table.insert(self._links, new_link_output)

		self:_sort_genes()
		self:_init_unique_layers()
	end
end

function _Genome:duplicate_link()
	-- returns true if the specified link is already part of the genome
end

function _Genome:get_element_pos(neuron_id)
	-- given a neuron id this function just finds its position in neurons array
end

function _Genome:already_have_this_neuron_id(id)
	-- tests if the passed ID is the same as any existing neuron IDs. Used in add_neuron()
end

function _Genome:get_compatibility_score(other)
	-- calculates the compatibility score between this genome and another genome(BUCKLAND, 387)

	-- travel down the length of each genome counting the number of
	-- disjoint genes, the number of excess genes and the number of
	-- matched genes
	local n_disjoint = 0
	local n_excess = 0
	local n_matched = 0

	-- this records the summed difference of weights in matched genes
	local acc_weight_difference = 0

	local this_index = 1
	local other_index = 1

	local this_neuron_gene = self._neurons[this_index]
	local other_neuron_gene = other._neurons[other_index]
	while this_neuron_gene or other_neuron_gene do
		if this_neuron_gene and other_neuron_gene then
			local this_id = this_neuron_gene:get_id()
			local other_id = other_neuron_gene:get_id()
			if this_id == other_id then
				n_matched = n_matched + 1
				local weight_difference = math.abs(this_neuron_gene:get_activation_response() - other_neuron_gene:get_activation_response())
				acc_weight_difference = acc_weight_difference + weight_difference

				this_index = this_index + 1
				other_index = other_index + 1
			elseif this_id > other_id then
				n_disjoint = n_disjoint + 1
				other_index = other_index + 1
			else -- if other_id > this_id then
				n_disjoint = n_disjoint + 1
				this_index = this_index + 1
			end
		elseif this_neuron_gene then
			n_excess = n_excess + 1
			this_index = this_index + 1
		else -- if other_neuron_gene then
			n_excess = n_excess + 1
			other_index = other_index + 1
		end

		this_neuron_gene = self._neurons[this_index]
		other_neuron_gene = other._neurons[other_index]
	end

	this_index = 1
	other_index = 1
	local this_link_gene = self._links[this_index]
	local other_link_gene = other._links[other_index]
	while this_link_gene or other_link_gene do
		if this_link_gene and other_link_gene then
			local this_id = this_link_gene:get_id()
			local other_id = other_link_gene:get_id()
			if this_id == other_id then
				n_matched = n_matched + 1
				local weight_difference = math.abs(this_link_gene:get_weight() - other_link_gene:get_weight())
				acc_weight_difference = acc_weight_difference + weight_difference

				this_index = this_index + 1
				other_index = other_index + 1
			elseif this_id > other_id then
				n_disjoint = n_disjoint + 1
				other_index = other_index + 1
			else -- if other_id > this_id then
				n_disjoint = n_disjoint + 1
				this_index = this_index + 1
			end
		elseif this_link_gene then
			n_excess = n_excess + 1
			this_index = this_index + 1
		else -- if other_link_gene then
			n_excess = n_excess + 1
			other_index = other_index + 1
		end

		this_link_gene = self._links[this_index]
		other_link_gene = other._links[other_index]
	end

	local disjoint_factor = 1
	local excess_factor = 1
	local matched_factor = 0.4

	-- get the longest length
	local longest_length = self:get_gene_count()
	if other:get_gene_count() > longest_length then
		longest_length = other:get_gene_count()
	end

	local score = 	((disjoint_factor * n_disjoint) / longest_length) +
					((excess_factor * n_excess) + (matched_factor * n_matched) / longest_length) +
					((matched_factor * acc_weight_difference) / n_matched)
	return score
end

function _Genome:type()
	return "_Genome"
end

-------------------------------------------------------------------------------
------------------------------------------------------------------------------- ANN
local ANN = {}
ANN.__index = ANN

function ANN:new_genome(
		n_inputs,
		input_layer_activation_function_name,
		input_layer_activation_function_parameters,
		n_outputs,
		output_layer_activation_function_name,
		output_layer_activation_function_parameters,
		initial_links,
		fully_connected,
		hidden_layers_activation_function_name,
		hidden_layers_activation_function_parameters,
		o)
	-- input neurons
	local neurons = {}
	local input_neurons = {}
	local x, y = 0, 0
	local increment = 1/(n_inputs - 1)
	for i = 1, n_inputs do
		local innovation_id = Innovation_manager:get_neuron_innovation_id(x, y)
		local new_neuron = _Neuron_Gene:new("input", false, _get_initial_activation_response(1), input_layer_activation_function_name, input_layer_activation_function_parameters, innovation_id, x, y)
		table.insert(neurons, new_neuron)
		table.insert(input_neurons, new_neuron)
		y = y + increment
	end

	-- output neurons
	local output_neurons = {}
	x, y = 1, 0
	increment = 1/(n_outputs - 1)
	for i = 1, n_outputs do
		local innovation_id = Innovation_manager:get_neuron_innovation_id(x, y)

		local new_neuron = _Neuron_Gene:new("output", false, _get_initial_activation_response(1), output_layer_activation_function_name, output_layer_activation_function_parameters, innovation_id, x, y)
		table.insert(neurons, new_neuron)
		table.insert(output_neurons, new_neuron)
		y = y + increment
	end

	-- create genome
	local genome = _Genome:new(neurons, {}, hidden_layers_activation_function_name, hidden_layers_activation_function_parameters, o)

	-- links(at least one)
	while true do
		if not fully_connected then
			-- local n_links = ((n_hidden_layer) >= 1) and n_hidden_layer or 1
			-- local n_links = n_inputs * n_outputs * initial_link_factor
			local n_links = initial_links and initial_links or n_inputs * n_outputs
			for i = 1, n_links do
				local input_neuron = qpd_random.choose_list(input_neurons)
				local output_neuron = qpd_random.choose_list(output_neurons)
				local innovation_id = Innovation_manager:get_link_innovation_id(input_neuron, output_neuron)
				genome:create_link(input_neuron, output_neuron, innovation_id)
			end
		else
			for i = 1, #input_neurons do
				for j = 1, #output_neurons do
					local innovation_id = Innovation_manager:get_link_innovation_id(input_neurons[i], output_neurons[j])
					genome:create_link(input_neurons[i], output_neurons[j], innovation_id)
				end
			end
		end

		if #genome._links < 1 then
			print("ERROR - _ANN:new_genome() - New _Genome does not have a link!")
		else
			return ANN:new(genome, o)
		end
	end
end

function ANN:new(genome, o)
	local o = o or {}
	setmetatable(o, self)

	o._genome = genome
	o._specie = false

	-- fill in layer_to_layer_position_dict and start layers array.
	o._layers = {}
	local layer_to_layer_position_dict = {}
	for i = 1, #genome._unique_layers do
		local this_layer = genome._unique_layers[i]
		layer_to_layer_position_dict[this_layer] = i
		o._layers[i] = {}
	end

	-- fill in layers
	for i = 1, #genome._neurons do
		local this_neuron_gene = genome._neurons[i]
		local this_layer = layer_to_layer_position_dict[this_neuron_gene:get_x()]
		local this_neuron = _Neuron:new_from_gene(this_neuron_gene)

		if not this_neuron then
			print("Invalid Neuron")
			qpd_gamestate.switch("menu")
		end

		table.insert(o._layers[this_layer], this_neuron)
	end

	-- sort layer and fill neuron_id_to_position
	local neuron_id_to_position = {}
	for i = 1, #o._layers do
		table.sort(o._layers[i], function (a, b) return a:get_y() < b:get_y() end)

		for j = 1, #o._layers[i] do
			local this_neuron = o._layers[i][j]
			neuron_id_to_position[this_neuron:get_id()] = {x = i, y = j}
		end
	end

	-- create links
	for i = 1, #genome._links do
		local this_link_gene = genome._links[i]
		if this_link_gene:is_enabled() then
			-- check neurons exist in this genome
			if 	neuron_id_to_position[this_link_gene:get_input_neuron():get_id()] and
				neuron_id_to_position[this_link_gene:get_output_neuron():get_id()] then

				local this_link = _Link:new_from_gene(this_link_gene, o._layers, neuron_id_to_position)
				this_link:get_input_neuron():add_output_link(this_link)
				this_link:get_output_neuron():add_input_link(this_link)
			else
				print("ERROR - _ANN:new() - Invalid Link - Neuron not registered in neuron_id_to_position!")
				qpd_gamestate.switch("menu")
			end
		end
	end

	return o
end

function ANN:crossover(mom, dad, mutate_chance, mutate_percentage, chance_add_neuron, chance_add_link, chance_loopback, crossover)
	local new_genome = mom._genome:crossover(dad._genome, mutate_chance, mutate_percentage, chance_add_neuron, chance_add_link, chance_loopback, crossover)
	local new_ann = self:new(new_genome)
	return new_ann
end

function ANN:speciate(species, threshold)
	local ann_specie
	local closest_compatibility
	local closest_specie

	for i = 1, #species do
		local this_specie = species[i]
		if this_specie then
			local this_compatibility = this_specie:get_compatibility_score(self)
			if this_compatibility <= (closest_compatibility or this_compatibility)  then
				closest_specie = this_specie
				closest_compatibility = this_compatibility
			end
		end
	end

	if closest_compatibility then
		threshold = threshold or 3
		print("closest_compatibility: ", closest_compatibility, closest_specie:get_id())
		if closest_compatibility < threshold then
			ann_specie = closest_specie
		end
	end

	if ann_specie then
		-- ann_specie:add_member(self)
		self._specie = ann_specie
		return false
	else
		local new_specie = _Species:new(self)
		self._specie = new_specie
		table.insert(species, new_specie)
		if new_specie:get_id() ~= #species then
			print("ERROR - _ANN:speciate() - species indexing is invalid!")
			qpd_gamestate.switch("menu")
		end
		return new_specie
	end
end

function ANN:get_gene_count()
	return self._genome:get_gene_count()
end

function ANN:get_outputs(inputs, run_type)
	-- update input layer
	-- print(#self._layers[1])
	-- for i = 1, #(self._layers[1]) do
	-- 	local this_neuron = self._layers[1][i]
	-- 	-- if not this_neuron then
	-- 	-- 	print(i)
	-- 	-- 	print(#self._layers[1])
	-- 	-- 	print(":")
	-- 	-- 	print(self)
	-- 	-- 	print(self._layers)
	-- 	-- 	print(self._layers[1][i])
	-- 	-- 	print(this_neuron:type())
	-- 	-- end
	-- 	this_neuron:update(inputs[i])
	-- end

	for index, value in ipairs(self._layers[1]) do
		value:update(inputs[index])
	end

	-- update other layers
	for i = 2, #self._layers do
		for j = 1, #self._layers[i] do
			local this_neuron = self._layers[i][j]
			this_neuron:update()
		end
	end

	-- get outputs
	local outputs = {}
	for i = 1, #self._layers[#self._layers] do
		outputs[i] = self._layers[#self._layers][i]:get_output()
	end

	return outputs
end

function ANN:set_negative_weight_initialization(value)
	-- value = value or false
	if value == true then
		_get_random_link_weight = _get_random_link_weight_maybe_negative
	else
		_get_random_link_weight = _get_random_link_weight_only_positive
	end
end

function ANN:set_add_neuron_with_unit_activation(value)
	if value == true then
		_get_initial_activation_response = _get_unit_activation_response
	else
		_get_initial_activation_response = _get_random_activation_response
	end
end

function ANN:to_string()
	return "{neuron count: " .. self._genome:get_neuron_count() .. ", link count: " .. self._genome:get_link_count() .. (self._specie and (", species: " .. self._specie:get_id()) or "") .. "}"
end

function ANN:get_genome()
	return self._genome
end

function ANN:type()
	return "ANN_neat"
end

return ANN