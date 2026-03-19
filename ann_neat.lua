-- Guilherme Cunha Prada 2022
--
-- NEAT (NeuroEvolution of Augmenting Topologies) implementation.
-- Based on Kenneth O. Stanley & Risto Miikkulainen's original paper and
-- "AI Techniques for Game Programming" by Mat Buckland (chapters 14-15).
--
-- ============================================================
-- HIGH-LEVEL OVERVIEW
-- ============================================================
-- NEAT evolves both the weights AND the structure (topology) of neural
-- networks simultaneously. Each individual network is encoded as a "genome"
-- containing two sorted gene lists:
--
--   NeuronGenes -- describe neurons: type (input/hidden/output/bias),
--                  position (x = layer depth, y = position within layer),
--                  and activation function + response parameter.
--
--   LinkGenes   -- describe connections: which neuron connects to which,
--                  the weight, whether the link is currently enabled, and
--                  whether it is recurrent.
--
-- Every gene carries a globally unique "innovation number" assigned by the
-- Innovation Manager singleton. This number lets crossover align genes from
-- two different genomes by ID alone, without expensive graph-matching.
-- Genes with the same innovation ID represent the same structural feature
-- (Buckland calls these "matching genes").
--
-- Networks that are structurally similar are grouped into Species via a
-- compatibility score. Fitness sharing within a species prevents one topology
-- from taking over the population before other structures are explored.
--
-- ============================================================
-- MODULE-PRIVATE CLASSES (prefixed with _)
-- ============================================================
--   _Link_Gene          gene describing one connection in the genome
--   _Link               live connection object used during forward pass
--   _Neuron_Gene        gene describing one neuron in the genome
--   _Neuron             live neuron object used during forward pass
--   _Innovation_manager singleton that issues globally unique gene IDs
--   _Species            a group of genetically compatible genomes
--   _Genome             a complete genome: NeuronGene[] + LinkGene[]
--
-- ============================================================
-- PUBLIC API  (the returned module table is named ANN)
-- ============================================================
--   ANN:new_genome(...)                               build a fresh network
--   ANN:new(genome)                                   build network from genome
--   ANN:crossover(mom, dad, ...)                      breed two networks
--   ANN:speciate(species, threshold)                  assign network to species
--   ANN:get_outputs(inputs)                           run a forward pass
--   ANN:get_gene_count()
--   ANN:get_genome()
--   ANN:to_string()
--   ANN:set_negative_weight_and_activation_initialization(bool)
--       When true, link weights and activation responses may be initialised
--       with a random sign (positive or negative).
--   ANN:set_input_proportional_activation(bool)
--       When true, each neuron's effective activation response is scaled by
--       the number of its incoming links, so busier neurons have a larger
--       response. Useful for larger, denser evolved topologies.

local ANN = {}
ANN.__index = ANN

local qpd_gamestate = require "qpd.gamestate"
local qpd_array     = require "qpd.array"
local qpd_table     = require "qpd.table"
local qpd_random    = require "qpd.random"
local ann_activation_functions = require "qpd.ann_activation_functions"

-- Maximum attempts before giving up on finding a valid candidate when
-- mutating the topology (avoids infinite loops on dense/small genomes).
local MAX_LOOPBACK_LINK_TRIES = 5
local MAX_LINK_TRIES          = 10
local MAX_NEURON_TRIES        = 5

-- Feature flags toggled via the public setters below.
-- NEGATIVE_WEIGHT_AND_ACTIVATION: allow negative initial weights/responses.
-- INPUT_PROPORTIONAL_ACTIVATION:  scale activation response by link count.
local NEGATIVE_WEIGHT_AND_ACTIVATION = false
local INPUT_PROPORTIONAL_ACTIVATION  = false

-- Singleton instance declared here; defined after _Innovation_manager class.
local Innovation_manager

-- Global counters for unique genome/species IDs (used for debugging).
local _genome_count  = 0
local _species_count = 0

-- ============================================================
-- INTERNAL HELPERS
-- ============================================================

-- Returns a random link weight in [0, scale] (or signed if flag is set).
local function _get_random_link_weight(scale)
	scale = scale or 1
	scale = NEGATIVE_WEIGHT_AND_ACTIVATION and (qpd_random.choose(1, -1) * scale) or scale
	return qpd_random.random() * scale
end

-- Returns a random activation response in [0, scale] (or signed if flag is set).
-- The activation response is the steepness/bias term fed into the activation
-- function alongside the summed weighted input.
local function _get_random_activation_response(scale)
	scale = scale or 1
	scale = NEGATIVE_WEIGHT_AND_ACTIVATION and (qpd_random.choose(1, -1) * scale) or scale
	return qpd_random.random() * scale
end

-- Comparator used to keep gene lists sorted by ascending innovation ID.
-- Sorted lists are required for the O(n) crossover and compatibility algorithms.
local function _innovation_sorter(a, b)
	return a._innovation_id < b._innovation_id
end

-- ============================================================
-- _Link_Gene
-- ============================================================
-- A gene that encodes one directed connection between two NeuronGenes.
-- Stored inside a _Genome. During network construction (_ANN:new) each
-- enabled LinkGene becomes a live _Link object.
--
-- Fields:
--   _input_neuron   _Neuron_Gene  source neuron gene
--   _output_neuron  _Neuron_Gene  target neuron gene
--   _weight         number        connection strength
--   _enabled        bool          disabled links are kept in the genome but
--                                 skipped at runtime (standard NEAT technique)
--   _innovation_id  number        globally unique structural ID
--   _recurrent      bool          true if the link goes "backward" in layer order
local _Link_Gene = {}
_Link_Gene.__index = _Link_Gene

-- weight is optional; defaults to a fresh random weight if omitted.
-- This lets create_link() avoid computing a weight before calling new().
function _Link_Gene:new(input_neuron_gene, output_neuron_gene, innovation_id, weight, o)
	local o = o or {}
	setmetatable(o, self)

	o._input_neuron  = input_neuron_gene
	o._output_neuron = output_neuron_gene
	o._weight        = weight or _get_random_link_weight()
	o._enabled       = true
	o._innovation_id = innovation_id

	-- A link is recurrent if it points to a neuron in the same or an earlier
	-- layer. Determined by comparing the (x, y) grid positions of the genes.
	o._recurrent = o._input_neuron:is_link_recurrent(o._output_neuron)

	return o
end

-- Randomly scale the weight up or down by at most mutate_percentage.
-- With probability (1 - mutate_chance) the weight is left unchanged.
function _Link_Gene:mutate(mutate_chance, mutate_percentage)
	self:set_weight(self._weight * (qpd_random.toss(mutate_chance)
		and (qpd_random.choose(-mutate_percentage, mutate_percentage) + 1)
		or 1))
end

-- Deep-clone this gene and immediately mutate it.
-- Used during crossover to produce a child gene from one parent's gene.
function _Link_Gene:inherit(mutate_chance, mutate_percentage)
	local clone = qpd_table.deep_clone(self)
	clone:mutate(mutate_chance, mutate_percentage)
	return clone
end

function _Link_Gene:set_weight(value)   self._weight = value        end
function _Link_Gene:get_weight()        return self._weight         end
function _Link_Gene:is_enabled()        return self._enabled        end
function _Link_Gene:set_enabled(value)  self._enabled = value or true end
function _Link_Gene:get_input_neuron()  return self._input_neuron   end
function _Link_Gene:get_output_neuron() return self._output_neuron  end
function _Link_Gene:get_input_x()       return self._input_neuron:get_x()  end
function _Link_Gene:get_input_y()       return self._input_neuron:get_y()  end
function _Link_Gene:get_output_x()      return self._output_neuron:get_x() end
function _Link_Gene:get_output_y()      return self._output_neuron:get_y() end
function _Link_Gene:get_id()            return self._innovation_id  end
function _Link_Gene:is_recurrent()      return self._recurrent      end
function _Link_Gene:type()              return "_Link_Gene"         end

-- ============================================================
-- _Link
-- ============================================================
-- The live (runtime) connection between two _Neuron objects.
-- Created from a _Link_Gene during ANN:new(). Registers itself with both
-- endpoint neurons so forward-pass traversal works without extra lookups.
--
-- Fields:
--   _input_neuron   _Neuron   source neuron (already connected on creation)
--   _output_neuron  _Neuron   target neuron (already connected on creation)
--   _weight         number    copied from the gene
--   _recurrent      bool      copied from the gene
local _Link = {}
_Link.__index = _Link

function _Link:new(input_neuron, output_neuron, weight, recurrent, o)
	local o = o or {}
	setmetatable(o, self)

	o._input_neuron  = input_neuron
	o._output_neuron = output_neuron
	o._weight        = weight
	o._recurrent     = recurrent

	-- Self-register with both endpoint neurons so each neuron knows its
	-- incoming and outgoing connections without a separate wiring pass.
	o._input_neuron:add_output_link(o)
	o._output_neuron:add_input_link(o)

	return o
end

-- Convenience constructor: resolves the two neurons from a gene + lookup table
-- and delegates to _Link:new (which self-registers).
function _Link:new_from_gene(link_gene, input_neuron, output_neuron)
	return _Link:new(input_neuron, output_neuron,
		link_gene:get_weight(), link_gene:is_recurrent())
end

function _Link:get_input_neuron()  return self._input_neuron  end
function _Link:get_output_neuron() return self._output_neuron end

-- The contribution of this link to its output neuron's activation sum:
-- weight * (output value of the input neuron).
function _Link:get_output()
	return self._weight * self:get_input_neuron():get_output()
end

function _Link:type() return "_Link" end

-- ============================================================
-- _Neuron_Gene
-- ============================================================
-- A gene encoding one neuron in the genome.
-- Position (x, y) determines the neuron's layer (x = depth) and its slot
-- within that layer (y). Hidden neurons are placed at the midpoint between
-- the two neurons they split when add_neuron() fires.
--
-- Fields:
--   _type                               "input"|"hidden"|"output"|"bias"|"none"
--   _recurrent                          bool (currently unused flag)
--   _activation_response                number; steepness/bias term for the
--                                       activation function; evolvable
--   _activation_function_name           string key into ann_activation_functions
--   _activation_function_parameters     any extra parameters the function needs
--   _innovation_id                      globally unique ID
--   _x, _y                              grid position (float; midpoints allowed)
--   _loopback                           bool; true if a self-loop link exists
local _Neuron_Gene = {}
_Neuron_Gene.__index = _Neuron_Gene

-- activation_response is optional; defaults to a fresh random value so callers
-- (especially add_neuron) don't need to supply one explicitly.
function _Neuron_Gene:new(type, recurrent,
		activation_function_name, activation_function_parameters,
		innovation_id, x, y,
		activation_response, o)
	local o = o or {}
	setmetatable(o, self)

	o._type                           = type
	o._recurrent                      = recurrent
	o._activation_response            = activation_response or _get_random_activation_response()
	o._activation_function_name       = activation_function_name
	o._activation_function_parameters = activation_function_parameters
	o._innovation_id                  = innovation_id
	o._x                              = x
	o._y                              = y

	return o
end

-- Randomly perturb the activation response (same probability model as links).
function _Neuron_Gene:mutate(mutate_chance, mutate_percentage)
	self:set_activation_response(self:get_activation_response()
		* (qpd_random.toss(mutate_chance)
			and (qpd_random.choose(-mutate_percentage, mutate_percentage) + 1)
			or 1))
end

-- Deep-clone and mutate; used during crossover.
function _Neuron_Gene:inherit(mutate_chance, mutate_percentage)
	local clone = qpd_table.deep_clone(self)
	clone:mutate(mutate_chance, mutate_percentage)
	return clone
end

-- A link FROM self TO other is recurrent when self is in the same or a later
-- layer than other (i.e. the signal would flow backwards or sideways).
-- Layer order is determined by the x coordinate; within a layer, y determines
-- position. Equal-x-equal-y (self-loop) is also recurrent.
function _Neuron_Gene:is_link_recurrent(other)
	if self:get_x() > other:get_x() then return true end
	if self:get_x() == other:get_x() then
		if self:get_y() >= other:get_y() then return true end
	end
	return false
end

function _Neuron_Gene:get_activation_response()        return self._activation_response            end
function _Neuron_Gene:set_activation_response(value)   self._activation_response = value           end
function _Neuron_Gene:get_activation_function()        return ann_activation_functions[self._activation_function_name] end
function _Neuron_Gene:get_activation_function_parameters() return self._activation_function_parameters end
function _Neuron_Gene:get_x()                          return self._x                              end
function _Neuron_Gene:get_y()                          return self._y                              end
function _Neuron_Gene:set_loopback(value)              self._loopback = value or true              end
function _Neuron_Gene:is_loopback()                    return self._loopback                       end
function _Neuron_Gene:get_id()                         return self._innovation_id                  end
function _Neuron_Gene:get_neuron_type()                return self._type                           end
function _Neuron_Gene:type()                           return "_Neuron_Gene"                       end

-- ============================================================
-- _Neuron
-- ============================================================
-- The live (runtime) neuron used during a forward pass.
-- Created from a _Neuron_Gene by ANN:new(). Links register themselves via
-- add_input_link / add_output_link when they are constructed.
--
-- Fields:
--   _input_links    {_Link}   incoming connections (populated by _Link:new)
--   _output_links   {_Link}   outgoing connections (populated by _Link:new)
--   _activation_response        copied from gene; evolvable steepness term
--   _activation_function        resolved function reference
--   _activation_function_parameters
--   _activation_sum             weighted sum of inputs (computed in update)
--   _activation_output          result of applying activation to the sum
--   _x, _y                      grid position (for layer assignment)
local _Neuron = {}
_Neuron.__index = _Neuron

function _Neuron:new(type, input_links, output_links,
		activation_response, activation_function, activation_function_parameters,
		innovation_id, x, y, o)
	local o = o or {}
	setmetatable(o, self)

	o._input_links  = input_links  or {}
	o._output_links = output_links or {}

	o._innovation_id = innovation_id
	o._type          = type

	o._activation_response            = activation_response
	o._activation_function            = activation_function
	o._activation_function_parameters = activation_function_parameters

	o._activation_sum    = 0
	o._activation_output = 0

	o._x = x
	o._y = y

	return o
end

function _Neuron:new_from_gene(neuron_gene)
	return _Neuron:new(
		neuron_gene:get_neuron_type(),
		nil, nil,
		neuron_gene:get_activation_response(),
		neuron_gene:get_activation_function(),
		neuron_gene:get_activation_function_parameters(),
		neuron_gene:get_id(),
		neuron_gene:get_x(),
		neuron_gene:get_y())
end

-- Called by _Link:new to register an incoming connection.
function _Neuron:add_input_link(link)
	table.insert(self._input_links, link)
end

-- Called by _Link:new to register an outgoing connection.
function _Neuron:add_output_link(link)
	table.insert(self._output_links, link)
end

-- Forward-pass update.
-- Input neurons: called with an explicit scalar `input` from the environment.
-- Hidden/output neurons: called with no argument; sum weighted inputs from links.
function _Neuron:update(input)
	if input then
		-- Input layer: the environment value is passed directly as the activation sum.
		self._activation_sum = input
	else
		-- Hidden / output layer: sum contributions from all incoming links.
		-- Each link computes weight * input_neuron.output.
		self._activation_sum = 0
		for i = 1, #self._input_links do
			self._activation_sum = self._activation_sum + self._input_links[i]:get_output()
		end
	end

	self._activation_output = self:get_activation_function()(
		self:get_activation_sum(),
		self:get_activation_response_value(),
		self:get_activation_function_parameters())
end

-- Returns the effective activation response, optionally scaled by the number
-- of incoming links when INPUT_PROPORTIONAL_ACTIVATION is enabled.
-- Rationale: a neuron receiving many inputs needs a proportionally larger
-- response threshold to avoid always saturating.
function _Neuron:get_activation_response_value()
	local factor = INPUT_PROPORTIONAL_ACTIVATION and #(self._input_links) or 1
	return self:get_activation_response() * factor
end

function _Neuron:get_activation_response()        return self._activation_response            end
function _Neuron:get_activation_function()         return self._activation_function            end
function _Neuron:get_activation_function_parameters() return self._activation_function_parameters end
function _Neuron:get_activation_sum()              return self._activation_sum                 end
function _Neuron:get_output()                      return self._activation_output              end
function _Neuron:get_x()                           return self._x                              end
function _Neuron:get_y()                           return self._y                              end
function _Neuron:get_id()                          return self._innovation_id                  end
function _Neuron:get_neuron_type()                 return self._type                           end
function _Neuron:type()                            return "_Neuron"                            end

-- ============================================================
-- _Innovation_manager  (singleton)
-- ============================================================
-- Issues globally unique integer IDs for new structural genes.
-- Ensures that the same structure invented independently in different
-- genomes receives the same ID within one run, which is the cornerstone
-- of NEAT's crossover alignment.
--
-- Two lookup tables (keyed by neuron positions or neuron-pair IDs) let us
-- find existing IDs before minting new ones.
--
-- NOTE: The singleton is reset when the Lua module is reloaded. Within a
-- single run it is global state shared across all genomes/populations.
local _Innovation_manager = {}
_Innovation_manager.__index = _Innovation_manager

function _Innovation_manager:new(o)
	local o = o or {}
	setmetatable(o, self)

	o._id_count = 0
	o._links    = {}  -- [input_id][output_id] -> innovation_id
	o._neurons  = {}  -- [x][y]                -> innovation_id

	return o
end

function _Innovation_manager:_new_innovation()
	self._id_count = self._id_count + 1
	return self._id_count
end

-- Returns the innovation ID for a link between two neuron genes.
-- Creates a new ID if this exact (input, output) pair has never been seen.
function _Innovation_manager:get_link_innovation_id(input_neuron_gene, output_neuron_gene)
	local input_id  = input_neuron_gene:get_id()
	local output_id = output_neuron_gene:get_id()

	if not self._links[input_id] then
		self._links[input_id] = {}
	end

	if not self._links[input_id][output_id] then
		self._links[input_id][output_id] = self:_new_innovation()
	end

	return self._links[input_id][output_id]
end

-- Returns the innovation ID for a neuron at grid position (x, y).
-- add_neuron places new neurons at the midpoint of split links, so (x, y)
-- uniquely identifies the structural event.
function _Innovation_manager:get_neuron_innovation_id(x, y)
	if not self._neurons[x] then
		self._neurons[x] = {}
	end

	if not self._neurons[x][y] then
		self._neurons[x][y] = self:_new_innovation()
	end

	return self._neurons[x][y]
end

function _Innovation_manager:type() return "_Innovation_manager" end

-- Returns a plain-table snapshot of the innovation registry.
-- Call before saving population; pass to load_state() on resume.
function _Innovation_manager:get_state()
	-- Deep-copy the nested tables so the snapshot is independent.
	local links_copy = {}
	for in_id, outs in pairs(self._links) do
		links_copy[in_id] = {}
		for out_id, innov_id in pairs(outs) do
			links_copy[in_id][out_id] = innov_id
		end
	end
	local neurons_copy = {}
	for x, ys in pairs(self._neurons) do
		neurons_copy[x] = {}
		for y, innov_id in pairs(ys) do
			neurons_copy[x][y] = innov_id
		end
	end
	return { id_count = self._id_count, links = links_copy, neurons = neurons_copy }
end

-- Restores the innovation registry from a previously saved state.
-- Must be called before any genome is reconstructed so that IDs are consistent.
function _Innovation_manager:load_state(state)
	self._id_count = state.id_count
	self._links    = state.links
	self._neurons  = state.neurons
end

-- Create the singleton.
Innovation_manager = _Innovation_manager:new()

-- ============================================================
-- _Species
-- ============================================================
-- A cluster of genomes that are structurally similar enough (within a
-- compatibility threshold) to be considered the same species.
-- Each species maintains a "leader" (the representative genome used for
-- compatibility comparison) and a history of best performers used for
-- roulette-wheel parent selection.
--
-- Fitness sharing: by limiting how many offspring each species produces
-- relative to its share of total fitness, NEAT prevents any one topology
-- from monopolising the population.
local _Species = {}
_Species.__index = _Species

function _Species:new(leader, o)
	local o = o or {}
	setmetatable(o, self)

	o._extinct             = false
	o._leader              = leader
	o._fitness_attribute   = "_fitness"   -- field name used in history records
	o._history_fitness_sum = 0
	o._history             = {}           -- rolling best-performer records

	_species_count = _species_count + 1
	o._id = _species_count

	print("New Species :) ", o._id)
	return o
end

-- Returns the species representative used for compatibility scoring.
function _Species:get_leader()
	if self._extinct then
		print("Tried to :get_leader() on extinct species!")
	end
	return self._leader
end

-- Roulette-wheel selection: pick a history entry with probability proportional
-- to its fitness. Falls back to a random entry or the leader if the wheel
-- fails (e.g. all fitnesses are 0).
function _Species:roulette()
	if self._extinct then
		print("Tried to :roulette() on extinct species!")
		return nil
	end

	local total_fitness = self._history_fitness_sum
	local slice = total_fitness * qpd_random.random()
	local sum   = 0

	for _, actor in ipairs(self._history) do
		sum = sum + actor._fitness
		if sum >= slice then
			return actor
		end
	end

	print("[WARN] - GeneticPopulation:_roulette() - Returning last actor!")
	return qpd_random.choose_list(self._history) or self:get_leader()
end

-- Adds actor's history record to the species pool, evicting the weakest
-- entry once the pool exceeds size_limit. This acts as a bounded elite store.
function _Species:add_to_history(actor, size_limit)
	local actor_history = actor:get_history()

	if #self._history > size_limit then
		-- Pool is full: only replace if the newcomer beats the weakest entry.
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

-- Delegates to the species leader's genome to score how different ann is
-- from this species (lower = more compatible).
function _Species:get_compatibility_score(ann)
	return ann:get_genome():get_compatibility_score(self:get_leader():get_genome())
end

-- Mark the species as extinct and release all references so Lua can GC them.
function _Species:purge()
	self._extinct           = true
	self._leader            = nil
	self._fitness_attribute = nil
	self._history_fitness_sum = nil
	self._history           = nil
	print("Species extinguished: ", self._id)
	self._id = nil
end

-- TODO: implement age-based fitness adjustments (Buckland p.392).
-- Young species should receive a fitness bonus to give new topologies time
-- to optimise; old species should be penalised to prevent stagnation.
-- This function is called from nowhere yet; wiring it in requires tracking
-- _age and _generations_with_no_improvement per species.
function _Species:adjusted_fitnesses()
end

function _Species:get_id() return self._id  end
function _Species:type()   return "_Species" end

-- ============================================================
-- _Genome
-- ============================================================
-- The genotype: a sorted list of NeuronGenes and a sorted list of LinkGenes.
-- Both lists are kept sorted by ascending innovation ID at all times, which
-- is required for the O(n+m) crossover and compatibility algorithms.
--
-- The genome also caches:
--   _n_inputs, _n_outputs   counts of each neuron type
--   _unique_layers          sorted list of distinct x-values (layer depths)
--   _hidden_layers_*        activation function info forwarded to new hidden neurons
local _Genome = {}
_Genome.__index = _Genome

function _Genome:new(neurons, links,
		hidden_layers_activation_function_name,
		hidden_layers_activation_function_parameters, o)
	local o = o or {}
	setmetatable(o, self)

	_genome_count = _genome_count + 1
	o._id = _genome_count

	o._neurons = neurons
	o._links   = links

	o._hidden_layers_activation_function_name       = hidden_layers_activation_function_name
	o._hidden_layers_activation_function_parameters = hidden_layers_activation_function_parameters

	-- Always sort on construction so crossover alignment is correct.
	o:_sort_genes()
	o:_init_n_inputs()
	o:_init_n_outputs()
	o:_reset_unique_layers()

	return o
end

-- ---- cache helpers ----

function _Genome:_init_n_inputs()
	local n = 0
	for i = 1, #self._neurons do
		if self._neurons[i]:get_neuron_type() == "input" then n = n + 1 end
	end
	self._n_inputs = n
end

function _Genome:_init_n_outputs()
	local n = 0
	for i = 1, #self._neurons do
		if self._neurons[i]:get_neuron_type() == "output" then n = n + 1 end
	end
	self._n_outputs = n
end

-- Rebuild the sorted list of distinct layer x-values.
-- MUST be called any time a neuron is added (add_neuron) because a new
-- hidden layer may have appeared at a midpoint x-coordinate.
-- The list is sorted numerically so ANN:new() visits layers left-to-right
-- (input → hidden → output).
function _Genome:_reset_unique_layers()
	local seen = {}
	for i = 1, #self._neurons do
		local x = self._neurons[i]:get_x()
		if not seen[x] then seen[x] = true end
	end

	local layers = {}
	for x, _ in pairs(seen) do
		layers[#layers + 1] = x
	end

	table.sort(layers)   -- deterministic left-to-right ordering

	self._unique_layers = layers
end

-- ---- gene sorting ----

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

-- ---- gene existence checks (exploit sorted order for early exit) ----

function _Genome:_has_link(link_gene_id)
	for i = 1, #self._links do
		local id = self._links[i]:get_id()
		if id == link_gene_id then return true  end
		if id >  link_gene_id then return false end  -- sorted: no point continuing
	end
	return false
end

function _Genome:_has_neuron(neuron_gene_id)
	for i = 1, #self._neurons do
		local id = self._neurons[i]:get_id()
		if id == neuron_gene_id then return true  end
		if id >  neuron_gene_id then return false end
	end
	return false
end

-- Returns true only when both endpoint neurons exist in this genome.
function _Genome:_is_link_valid(link_gene)
	return self:_has_neuron(link_gene:get_input_neuron():get_id())
		and self:_has_neuron(link_gene:get_output_neuron():get_id())
end

-- ---- structural mutations ----

-- Create and insert a new LinkGene between two existing NeuronGenes.
-- Silently skips duplicates (same innovation ID already present).
function _Genome:create_link(input_neuron, output_neuron, innovation_id)
	if not (input_neuron and output_neuron) then return end

	local new_link = _Link_Gene:new(input_neuron, output_neuron, innovation_id)
	-- _Link_Gene:new with no weight argument randomises one internally.

	if not self:_has_link(new_link:get_id()) then
		table.insert(self._links, new_link)
		self:_sort_links()
	end
end

-- Structural mutation: attempt to add a new link gene.
-- Two modes, chosen by chance:
--   Loopback  – a self-recurrent link on a single hidden/output neuron.
--   Forward   – a new directed link between any two distinct neurons
--               (the output neuron must not be an input neuron).
function _Genome:add_link(chance_loopback)
	local selected_input_neuron
	local selected_output_neuron
	local innovation_id

	if qpd_random.toss(chance_loopback) then
		-- ---- loopback path ----
		-- Look for a non-input, non-bias neuron without a self-loop yet.
		local tries = MAX_LOOPBACK_LINK_TRIES
		while tries > 0 do
			local idx = qpd_random.random(#self._neurons)
			local n   = self._neurons[idx]
			if n:get_neuron_type() ~= "input"
			and n:get_neuron_type() ~= "bias"
			and not n:is_loopback() then
				innovation_id = Innovation_manager:get_link_innovation_id(n, n)
				if not self:_has_link(innovation_id) then
					tries = 0
					n:set_loopback(true)
					selected_input_neuron  = n
					selected_output_neuron = n
				end
			else
				tries = tries - 1
			end
		end
	else
		-- ---- forward link path ----
		-- Pick two random distinct neurons; the target must not be an input neuron.
		local tries = MAX_LINK_TRIES
		while tries > 0 do
			local in_idx  = qpd_random.random(#self._neurons)
			local out_idx = qpd_random.random(#self._neurons)

			if self._neurons[in_idx]:get_id() ~= self._neurons[out_idx]:get_id()
			and self._neurons[out_idx]:get_neuron_type() ~= "input" then
				innovation_id = Innovation_manager:get_link_innovation_id(
					self._neurons[in_idx], self._neurons[out_idx])
				if not self:_has_link(innovation_id) then
					tries = 0
					-- FIX: was `self._neurons[in_idx]` for both — that created a
					-- self-loop instead of a forward link (copy-paste bug).
					selected_input_neuron  = self._neurons[in_idx]
					selected_output_neuron = self._neurons[out_idx]
				end
			else
				tries = tries - 1
			end
		end
	end

	self:create_link(selected_input_neuron, selected_output_neuron, innovation_id)
	self:_sort_links()
end

-- Structural mutation: split an existing link by inserting a new hidden neuron.
-- The original link is disabled; two new links bridge through the new neuron.
-- The new neuron is placed at the geometric midpoint between its two endpoints.
--
-- When the genome is small, older links are preferred (bias away from
-- chaining — Buckland p.390) to encourage breadth over depth early on.
function _Genome:add_neuron()
	local chosen_link
	-- Small-genome heuristic: favour links with lower innovation IDs (older,
	-- more established links) to avoid repeatedly splitting the same recent link.
	local size_threshold = self:get_n_inputs() + self:get_n_outputs() + 5

	if self:get_gene_count() < size_threshold then
		local tries  = MAX_NEURON_TRIES
		local n_links = #self._links
		while tries > 0 do
			-- Upper bound excludes the sqrt(n) newest links (Buckland's formula).
			local idx = qpd_random.random(1, n_links - math.floor(math.sqrt(n_links)))
			idx = (idx >= 1) and idx or 1
			local candidate = self._links[idx]
			local in_neuron = candidate:get_input_neuron()

			if candidate:is_enabled()
			and not candidate:is_recurrent()
			and in_neuron:get_neuron_type() ~= "bias" then
				chosen_link = candidate
				break
			end
			tries = tries - 1
		end
	else
		local tries  = MAX_NEURON_TRIES
		local n_links = #self._links
		while tries > 0 do
			local candidate = self._links[qpd_random.random(1, n_links)]
			local in_neuron = candidate:get_input_neuron()

			if candidate:is_enabled()
			and not candidate:is_recurrent()
			and in_neuron:get_neuron_type() ~= "bias" then
				chosen_link = candidate
				break
			end
			tries = tries - 1
		end
	end

	if not chosen_link then return end

	-- Disable the old link; it stays in the genome for compatibility scoring.
	chosen_link:set_enabled(false)

	-- Place the new neuron at the midpoint of the split link.
	local x = (chosen_link:get_input_x() + chosen_link:get_output_x()) / 2
	local y = (chosen_link:get_input_y() + chosen_link:get_output_y()) / 2

	local new_neuron_id = Innovation_manager:get_neuron_innovation_id(x, y)
	local new_neuron    = _Neuron_Gene:new(
		"hidden", false,
		self._hidden_layers_activation_function_name,
		self._hidden_layers_activation_function_parameters,
		new_neuron_id, x, y
		-- activation_response defaults to random inside _Neuron_Gene:new
	)
	table.insert(self._neurons, new_neuron)

	-- New link: original input  -->  new neuron
	local id_in   = Innovation_manager:get_link_innovation_id(chosen_link:get_input_neuron(), new_neuron)
	local link_in = _Link_Gene:new(chosen_link:get_input_neuron(), new_neuron, id_in)
	table.insert(self._links, link_in)

	-- New link: new neuron  -->  original output
	local id_out   = Innovation_manager:get_link_innovation_id(new_neuron, chosen_link:get_output_neuron())
	local link_out = _Link_Gene:new(new_neuron, chosen_link:get_output_neuron(), id_out)
	table.insert(self._links, link_out)

	self:_sort_genes()
	self:_reset_unique_layers()
end

-- ============================================================
-- _Genome:crossover
-- ============================================================
-- Breed a child genome from mom (self, always the fitter/shorter) and dad.
-- When crossover == false, dad is replaced by mom (asexual reproduction).
--
-- Algorithm (Buckland p.386 / Stanley & Miikkulainen):
--   Walk both sorted gene lists in parallel by innovation ID.
--   Matching genes (same ID in both parents): randomly pick one and mutate it.
--   Disjoint/excess genes (only in mom): inherit from mom.
--   Disjoint/excess genes (only in dad): skipped (mom is fitter).
--
-- After alignment, structural mutations (add_neuron, add_link) are applied
-- with their respective chance parameters.
function _Genome:crossover(dad, mutate_chance, mutate_percentage,
		chance_add_neuron, chance_add_link, chance_loopback, crossover)
	local mom = self
	if crossover == false then dad = mom end

	-- ---- Align and merge NeuronGenes ----
	local neurons   = {}
	local mom_index = 1
	local dad_index = 1
	local mom_gene  = mom._neurons[mom_index]
	local dad_gene  = dad._neurons[dad_index]

	while mom_gene do
		if mom_gene and dad_gene then
			if mom_gene:get_id() == dad_gene:get_id() then
				-- Matching: pick one parent randomly, then mutate.
				local new_n = qpd_random.choose(mom_gene, dad_gene)
					:inherit(mutate_chance, mutate_percentage)
				table.insert(neurons, new_n)
				mom_index = mom_index + 1
				dad_index = dad_index + 1
			elseif mom_gene:get_id() < dad_gene:get_id() then
				-- Mom has a gene dad doesn't (disjoint/excess): inherit from mom.
				table.insert(neurons, mom_gene:inherit(mutate_chance, mutate_percentage))
				mom_index = mom_index + 1
			else
				-- Dad has a gene mom doesn't: skip (mom is fitter).
				dad_index = dad_index + 1
			end
		elseif mom_gene then
			-- Excess genes at end of mom's list.
			table.insert(neurons, mom_gene:inherit(mutate_chance, mutate_percentage))
			mom_index = mom_index + 1
		end
		mom_gene = mom._neurons[mom_index]
		dad_gene = dad._neurons[dad_index]
	end

	-- ---- Align and merge LinkGenes (same logic as neurons) ----
	local links    = {}
	mom_index = 1
	dad_index = 1
	local mom_link = mom._links[mom_index]
	local dad_link = dad._links[dad_index]

	while mom_link do
		if mom_link and dad_link then
			if mom_link:get_id() == dad_link:get_id() then
				local new_l = qpd_random.choose(mom_link, dad_link)
					:inherit(mutate_chance, mutate_percentage)
				table.insert(links, new_l)
				mom_index = mom_index + 1
				dad_index = dad_index + 1
			elseif mom_link:get_id() < dad_link:get_id() then
				table.insert(links, mom_link:inherit(mutate_chance, mutate_percentage))
				mom_index = mom_index + 1
			else
				dad_index = dad_index + 1
			end
		elseif mom_link then
			table.insert(links, mom_link:inherit(mutate_chance, mutate_percentage))
			mom_index = mom_index + 1
		end
		mom_link = mom._links[mom_index]
		dad_link = dad._links[dad_index]
	end

	-- Build the child genome; structural mutations fire immediately after.
	local child = _Genome:new(neurons, links,
		mom._hidden_layers_activation_function_name,
		mom._hidden_layers_activation_function_parameters)

	if qpd_random.toss(chance_add_neuron) then child:add_neuron() end
	if qpd_random.toss(chance_add_link)   then child:add_link(chance_loopback) end

	-- Sanity check: every link must reference neurons that exist in this genome.
	for i = 1, #child._links do
		local lnk = child._links[i]
		if not child:_is_link_valid(lnk) then
			print("ERROR - _Genome:crossover() - Genome has invalid link!")
			print("Link is enabled: ", lnk:is_enabled())
		end
	end

	return child
end

-- ============================================================
-- _Genome:get_compatibility_score
-- ============================================================
-- Measures how different two genomes are (Buckland p.387).
-- Lower score = more compatible = more likely to be in the same species.
--
-- The score combines three terms:
--   disjoint genes: genes present in one genome but within the ID range of both
--   excess genes:   genes present only in the longer genome beyond the other's range
--   weight difference: average absolute weight delta for matching genes
--
-- Tuning factors:
--   disjoint_factor, excess_factor: penalise structural differences
--   matched_factor:                 penalise weight divergence on shared structure
function _Genome:get_compatibility_score(other)
	local n_disjoint = 0
	local n_excess   = 0
	local n_matched  = 0
	local acc_weight_difference = 0

	-- ---- Neuron genes ----
	local this_index  = 1
	local other_index = 1
	local this_g  = self._neurons[this_index]
	local other_g = other._neurons[other_index]

	while this_g or other_g do
		if this_g and other_g then
			local this_id  = this_g:get_id()
			local other_id = other_g:get_id()
			if this_id == other_id then
				n_matched = n_matched + 1
				acc_weight_difference = acc_weight_difference
					+ math.abs(this_g:get_activation_response() - other_g:get_activation_response())
				this_index  = this_index  + 1
				other_index = other_index + 1
			elseif this_id > other_id then
				n_disjoint  = n_disjoint + 1
				other_index = other_index + 1
			else
				n_disjoint = n_disjoint + 1
				this_index = this_index + 1
			end
		elseif this_g then
			n_excess   = n_excess   + 1
			this_index = this_index + 1
		else
			n_excess    = n_excess    + 1
			other_index = other_index + 1
		end
		this_g  = self._neurons[this_index]
		other_g = other._neurons[other_index]
	end

	-- ---- Link genes ----
	this_index  = 1
	other_index = 1
	local this_l  = self._links[this_index]
	local other_l = other._links[other_index]

	while this_l or other_l do
		if this_l and other_l then
			local this_id  = this_l:get_id()
			local other_id = other_l:get_id()
			if this_id == other_id then
				n_matched = n_matched + 1
				acc_weight_difference = acc_weight_difference
					+ math.abs(this_l:get_weight() - other_l:get_weight())
				this_index  = this_index  + 1
				other_index = other_index + 1
			elseif this_id > other_id then
				n_disjoint  = n_disjoint  + 1
				other_index = other_index + 1
			else
				n_disjoint = n_disjoint + 1
				this_index = this_index + 1
			end
		elseif this_l then
			n_excess   = n_excess   + 1
			this_index = this_index + 1
		else
			n_excess    = n_excess    + 1
			other_index = other_index + 1
		end
		this_l  = self._links[this_index]
		other_l = other._links[other_index]
	end

	local disjoint_factor = 1
	local excess_factor   = 1
	local matched_factor  = 0.4

	local longest = math.max(self:get_gene_count(), other:get_gene_count())

	-- Guard against division by zero when n_matched == 0.
	local avg_weight_diff = (n_matched > 0) and (acc_weight_difference / n_matched) or 0

	local score =
		((disjoint_factor * n_disjoint) / longest) +
		((excess_factor   * n_excess)   / longest) +
		(matched_factor   * avg_weight_diff)

	return score
end

-- ---- accessors ----
function _Genome:get_neuron_count() return #self._neurons                               end
function _Genome:get_link_count()   return #self._links                                 end
function _Genome:get_gene_count()   return self:get_neuron_count() + self:get_link_count() end
function _Genome:get_n_inputs()     return self._n_inputs                               end
function _Genome:get_n_outputs()    return self._n_outputs                              end
function _Genome:type()             return "_Genome"                                    end

-- ---- serialization ----

-- Returns a plain table that fully describes this genome.
-- All neuron and link genes are encoded as scalar-only records; no Lua
-- object references survive the round-trip.
function _Genome:serialize()
	local neurons = {}
	for i, ng in ipairs(self._neurons) do
		neurons[i] = {
			id                              = ng:get_id(),
			neuron_type                     = ng:get_neuron_type(),
			x                               = ng:get_x(),
			y                               = ng:get_y(),
			activation_function_name        = ng._activation_function_name,
			activation_function_parameters  = ng._activation_function_parameters,
			activation_response             = ng:get_activation_response(),
			recurrent                       = ng._recurrent,
			loopback                        = ng._loopback or false,
		}
	end

	local links = {}
	for i, lg in ipairs(self._links) do
		links[i] = {
			id              = lg:get_id(),
			input_neuron_id = lg:get_input_neuron():get_id(),
			output_neuron_id= lg:get_output_neuron():get_id(),
			weight          = lg:get_weight(),
			enabled         = lg:is_enabled(),
			recurrent       = lg:is_recurrent(),
		}
	end

	return {
		neurons                                  = neurons,
		links                                    = links,
		hidden_layers_activation_function_name   = self._hidden_layers_activation_function_name,
		hidden_layers_activation_function_parameters = self._hidden_layers_activation_function_parameters,
	}
end

-- Rebuilds a _Genome from the plain table produced by serialize().
-- Requires Innovation_manager to already be loaded (IDs are reused, not minted).
function _Genome.from_data(data)
	-- Rebuild neuron genes; build an id→gene lookup for link reconstruction.
	local id_to_gene = {}
	local neurons    = {}
	for _, nd in ipairs(data.neurons) do
		local ng = _Neuron_Gene:new(
			nd.neuron_type,
			nd.recurrent,
			nd.activation_function_name,
			nd.activation_function_parameters,
			nd.id,
			nd.x,
			nd.y,
			nd.activation_response)
		if nd.loopback then ng:set_loopback(true) end
		id_to_gene[nd.id] = ng
		table.insert(neurons, ng)
	end

	-- Rebuild link genes using the neuron-gene references.
	local links = {}
	for _, ld in ipairs(data.links) do
		local in_gene  = id_to_gene[ld.input_neuron_id]
		local out_gene = id_to_gene[ld.output_neuron_id]
		local lg = _Link_Gene:new(in_gene, out_gene, ld.id, ld.weight)
		if not ld.enabled then lg:set_enabled(false) end
		table.insert(links, lg)
	end

	return _Genome:new(neurons, links,
		data.hidden_layers_activation_function_name,
		data.hidden_layers_activation_function_parameters)
end

-- ============================================================
-- ANN  (public module)
-- ============================================================
-- The phenotype: a genome compiled into a layered network of live _Neuron
-- and _Link objects, ready for forward-pass evaluation.
--
-- Layers are keyed by the sorted unique x-values from _unique_layers.
-- Within each layer, neurons are sorted by ascending y for deterministic order.
local ANN = {}
ANN.__index = ANN

-- ============================================================
-- ANN:new_genome
-- ============================================================
-- Build a completely fresh network with the given input/output structure.
-- Links are either fully-connected or sampled randomly (initial_links count).
-- Loops until at least one link exists (degenerate topologies are retried).
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

	-- ---- Input neurons (x = 0, y evenly spaced in [0, 1]) ----
	local neurons       = {}
	local input_neurons = {}
	local x, y         = 0, 0
	local increment     = 1 / (n_inputs - 1)

	for i = 1, n_inputs do
		local id = Innovation_manager:get_neuron_innovation_id(x, y)
		local n  = _Neuron_Gene:new("input", false,
			input_layer_activation_function_name,
			input_layer_activation_function_parameters,
			id, x, y)
		table.insert(neurons, n)
		table.insert(input_neurons, n)
		y = y + increment
	end

	-- ---- Output neurons (x = 1, y evenly spaced in [0, 1]) ----
	local output_neurons = {}
	x, y      = 1, 0
	increment = 1 / (n_outputs - 1)

	for i = 1, n_outputs do
		local id = Innovation_manager:get_neuron_innovation_id(x, y)
		local n  = _Neuron_Gene:new("output", false,
			output_layer_activation_function_name,
			output_layer_activation_function_parameters,
			id, x, y)
		table.insert(neurons, n)
		table.insert(output_neurons, n)
		y = y + increment
	end

	-- ---- Build genome and wire initial links ----
	local genome = _Genome:new(neurons, {},
		hidden_layers_activation_function_name,
		hidden_layers_activation_function_parameters, o)

	-- Retry until we get at least one link (rare edge case with small counts).
	while true do
		if fully_connected then
			-- Every input connects to every output.
			for i = 1, #input_neurons do
				for j = 1, #output_neurons do
					local id = Innovation_manager:get_link_innovation_id(input_neurons[i], output_neurons[j])
					genome:create_link(input_neurons[i], output_neurons[j], id)
				end
			end
		else
			-- Sample initial_links random (input, output) pairs.
			local n_links = initial_links and initial_links or (n_inputs * n_outputs)
			for i = 1, n_links do
				local inp = qpd_random.choose_list(input_neurons)
				local out = qpd_random.choose_list(output_neurons)
				local id  = Innovation_manager:get_link_innovation_id(inp, out)
				genome:create_link(inp, out, id)
			end
		end

		if #genome._links >= 1 then
			return ANN:new(genome, o)
		end
		print("ERROR - _ANN:new_genome() - New _Genome does not have a link!")
	end
end

-- ============================================================
-- ANN:new
-- ============================================================
-- Compile a genome into a runnable network.
-- Builds the _layers[][] structure (sorted by x then y) and creates
-- live _Link objects (which self-register with their endpoint neurons).
function ANN:new(genome, o)
	local o = o or {}
	setmetatable(o, self)

	o._genome = genome
	o._specie = false

	-- Map each unique layer x-value to a sequential layer index [1 .. N].
	-- Layer 1 = inputs (x=0), layer N = outputs (x=1), others = hidden.
	o._layers = {}
	local x_to_layer_index = {}
	for i = 1, #genome._unique_layers do
		local x = genome._unique_layers[i]
		x_to_layer_index[x] = i
		o._layers[i] = {}
	end

	-- Place each neuron gene into the correct layer bucket.
	for i = 1, #genome._neurons do
		local gene        = genome._neurons[i]
		local layer_index = x_to_layer_index[gene:get_x()]
		local neuron      = _Neuron:new_from_gene(gene)

		if not neuron then
			print("Invalid Neuron")
			qpd_gamestate.switch("menu")
		end

		table.insert(o._layers[layer_index], neuron)
	end

	-- Sort neurons within each layer by ascending y, then build a flat
	-- id -> neuron lookup table for O(1) link wiring below.
	-- The sort uses a clone comparison to detect accidental length changes
	-- (defensive; was a real bug during development).
	local id_to_neuron = {}
	for i = 1, #o._layers do
		local before = qpd_table.shallow_clone(o._layers[i])
		table.sort(o._layers[i], function(a, b) return a:get_y() < b:get_y() end)

		if #before ~= #o._layers[i] then
			-- Sorting should never change length; recover original references.
			print("sorting messed up the length")
			local recovered = {}
			for k = 1, #before do recovered[k] = before[k] end
			o._layers[i] = recovered
			print("fixed?", #before, #o._layers[i])
		end

		for j = 1, #o._layers[i] do
			local n = o._layers[i][j]
			id_to_neuron[n:get_id()] = n
		end
	end

	-- Create live _Link objects for all enabled link genes.
	-- _Link:new self-registers with both endpoint neurons.
	for i = 1, #genome._links do
		local gene = genome._links[i]
		if gene:is_enabled() then
			local inp = id_to_neuron[gene:get_input_neuron():get_id()]
			local out = id_to_neuron[gene:get_output_neuron():get_id()]
			if inp and out then
				_Link:new_from_gene(gene, inp, out)
			else
				print("ERROR - _ANN:new() - Invalid Link - Neuron not in id_to_neuron!")
				qpd_gamestate.switch("menu")
			end
		end
	end

	return o
end

-- ============================================================
-- ANN:crossover
-- ============================================================
-- Public crossover: delegates genome breeding then compiles the child genome.
function ANN:crossover(mom, dad, mutate_chance, mutate_percentage,
		chance_add_neuron, chance_add_link, chance_loopback, crossover)
	local new_genome = mom._genome:crossover(dad._genome,
		mutate_chance, mutate_percentage,
		chance_add_neuron, chance_add_link, chance_loopback, crossover)
	return self:new(new_genome)
end

-- ============================================================
-- ANN:speciate
-- ============================================================
-- Assign this network to the closest compatible species.
-- If no species scores below threshold, a new species is created.
-- Returns the new _Species object on creation, or false if an existing
-- species accepted the network.
--
-- The species list may contain gaps (nil entries after purge()).
function ANN:speciate(species, threshold)
	local ann_specie
	local closest_compatibility
	local closest_specie

	-- Find the existing species with the lowest compatibility score.
	for i = 1, #species do
		local sp = species[i]
		if sp then
			local compat = sp:get_compatibility_score(self)
			-- <= means ties go to the first species found (stable assignment).
			if compat <= (closest_compatibility or compat) then
				closest_specie        = sp
				closest_compatibility = compat
			end
		end
	end

	if closest_compatibility then
		if closest_compatibility < threshold then
			ann_specie = closest_specie
		end
	end

	if ann_specie then
		self._specie = ann_specie
		return false
	else
		-- No compatible species found; found a new one with this network as leader.
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

-- ============================================================
-- ANN:get_outputs
-- ============================================================
-- Run a single forward pass through the network.
-- Layers are visited left-to-right (input → hidden → output).
-- Input neurons receive raw environment values; all others sum their links.
function ANN:get_outputs(inputs, run_type)
	-- Feed inputs into the first (input) layer.
	for index, neuron in ipairs(self._layers[1]) do
		neuron:update(inputs[index])
	end

	-- Propagate through hidden and output layers.
	for i = 2, #self._layers do
		for j = 1, #self._layers[i] do
			self._layers[i][j]:update()
		end
	end

	-- Collect outputs from the last layer.
	local outputs = {}
	local last    = self._layers[#self._layers]
	for i = 1, #last do
		outputs[i] = last[i]:get_output()
	end

	return outputs
end

-- ============================================================
-- Public configuration setters
-- ============================================================

-- When true, initial link weights and neuron activation responses can be
-- negative (sign is randomised). Useful for exploring a wider weight space.
function ANN:set_negative_weight_and_activation_initialization(value)
	NEGATIVE_WEIGHT_AND_ACTIVATION = value
end

-- When true, each neuron's effective activation response is multiplied by the
-- number of its incoming links. Helps avoid saturation in dense evolved networks.
function ANN:set_input_proportional_activation(value)
	INPUT_PROPORTIONAL_ACTIVATION = value
end

-- ============================================================
-- Miscellaneous
-- ============================================================

function ANN:to_string()
	return "{neuron count: " .. self._genome:get_neuron_count()
		.. ", link count: "  .. self._genome:get_link_count()
		.. (self._specie and (", species: " .. self._specie:get_id()) or "")
		.. "}"
end

function ANN:get_gene_count() return self._genome:get_gene_count() end
function ANN:get_genome()     return self._genome                  end
function ANN:type()           return "ANN_neat"                    end

-- ---- Innovation_manager accessors (module-level, not per-instance) ----
-- These expose the module-private singleton to callers such as population_io.

function ANN.get_innovation_state()
	return Innovation_manager:get_state()
end

function ANN.load_innovation_state(state)
	Innovation_manager:load_state(state)
end

-- Reconstructs an ANN from a serialized genome data table.
-- Used when resuming a run: the genome is restored without going through
-- new_genome(), so Innovation_manager IDs are reused rather than minted.
-- The full phenotype (_layers, _specie, etc.) is built via ANN:new() so the
-- network is immediately ready for forward-pass evaluation via get_outputs().
function ANN.from_genome_data(data)
	local genome = _Genome.from_data(data)
	return ANN:new(genome)
end

return ANN
