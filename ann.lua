-- Guilherme Cunha Prada 2022
local ANN = {}
ANN.__index = ANN

local qpd_table = require "qpd.table"
local qpd_random = require "qpd.random"
local ann_activation_functions = require "qpd.ann_activation_functions"

local LEARNING_RATE = 0.1
local INITIALIZE_TO_VALUE = false
local RANDON_SPREAD = 1

function ANN.set_learning_rate(learning_rate)
	LEARNING_RATE = learning_rate
end

function ANN.set_initialize_value(value)
	INITIALIZE_TO_VALUE = value
end

function ANN.set_randon_spread(value)
	RANDON_SPREAD = value
end

-- Internal Classes
local _Neuron = {}
local _NeuronLayer = {}

function _Neuron:new(inputs, bias, activation_function, activation_function_parameters, o)
	-- if inputs is a number, it is used as n_inputs as the neuron is initialized with random values
	-- if inputs is a table, is is used as init values for the neuron
	local o = o or {}

	local this_type = type(inputs)
	local n_inputs
	if this_type == "table" then
		for key, value in ipairs(inputs) do
			o[key] = value
		end
		n_inputs = #inputs
	elseif this_type == "number" then
		for i = 1, inputs, 1 do
			local value = INITIALIZE_TO_VALUE
			if not INITIALIZE_TO_VALUE then
				value = qpd_random.random() * qpd_random.choose(1, -1) * RANDON_SPREAD
			end
			o[i] = value
		end
		n_inputs = inputs
	else
		print("[ERROR] - _Neuron:new() - Could not initialize Neuron with type:", this_type)
		return nil
	end

	local value = INITIALIZE_TO_VALUE
	if not INITIALIZE_TO_VALUE then
		value = qpd_random.random() * qpd_random.choose(1, -1) * RANDON_SPREAD * n_inputs
	end
	o.bias = bias or value
	o.activation_function = activation_function
	o.activation_function_parameters = activation_function_parameters

	o._activation_output = nil

	setmetatable(o, self)
	self.__index = self
	return o
end

function _Neuron:to_string()
	local str = string.format("(%s", self[1])
	for i = 2, #self do
		str = string.format("%s,%s", str, self[i])
	end
	str = string.format("%s, bias = %s", str, self.bias)
	str = string.format("%s)", str)
	return str
end

function _Neuron:update(inputs)
	local this_type = type(inputs)
	if this_type == "table" and inputs.get_outputs then
		inputs = inputs:get_outputs()
		local sum = 0
		for i = 1, #self do
			sum = sum + (self[i] * inputs[i])
		end
		self._activation_sum = sum
	elseif this_type == "number" then
		self._activation_sum = self[1] * inputs
	else
		print("[ERROR] - _Neuron:update() - Received a bogus input:", inputs)
		return
	end
	self._activation_output = self.activation_function(self._activation_sum, self.bias, self.activation_function_parameters)
end

function _Neuron:adjust_weights_output(inputs, output, target)
	local error = (target - output) * output * (1 - output)

	-- print(error)
	for i = 1, #self do
		-- io.write(LEARNING_RATE * error * inputs[i], " -- ")
		-- io.write(self[i], ", ")
		self[i] = self[i] + (LEARNING_RATE * error * inputs[i])
		-- io.write(self[i], "  :  ")
	end
	-- print()
	-- print()
	self.bias = self.bias + (LEARNING_RATE * error * 1)

	return error
end

function _Neuron:adjust_weights(index_in_layer, inputs, output_layer, output_errors, outputs)
	local total_error = 0
	for i = 1, #output_errors do
		total_error = total_error + output_errors[i] * output_layer[i][index_in_layer]
	end

	local output = self._activation_output
	local error = output * (1 - output) * total_error

	for i = 1, #self do
		self[i] = self[i] + (LEARNING_RATE * error * inputs[i])
	end
	self.bias = self.bias + (LEARNING_RATE * error * 1)

	return error
end

-------------------------------------------------------------------------------
function _NeuronLayer:new(neurons, inputs, bias, activation_function, activation_function_parameters, o)
	-- if neurons is a number, it is used as n_neurons as the layer is initialized with random neurons
	-- if neurons is a table, is is used as init values for neurons
	local o = o or {}

	local this_type = type(neurons)
	if this_type == "table" then
		for key, value in ipairs(neurons) do
			o[key] = value
		end
	elseif this_type == "number" then
		for i = 1, neurons, 1 do
			o[i] = _Neuron:new(inputs, bias, activation_function, activation_function_parameters)
		end
	else
		print("[ERROR] - _NeuronLayer:new() - Could not initialize NeuronLayer with type:", this_type)
		return nil
	end

	setmetatable(o, self)
	self.__index = self
	return o
end

function _NeuronLayer:to_string()
	local str = string.format("[%s", self[1]:to_string())
	for i = 2, #self do
		str = string.format("%s%s", str, self[i]:to_string())
	end
	str = string.format("%s]", str)
	return str
end

function _NeuronLayer:update(inputs)
	for i = 1, #self do
		local neuron = self[i]
		neuron:update(inputs)
	end
end

function _NeuronLayer:update_entry_layer(inputs)
	for i = 1, #self do
		local neuron = self[i]
		local input = inputs[i]
		neuron:update(input)
	end
end


function _NeuronLayer:adjust_weights_output(inputs, outputs, targets)
	local errors = {}
	for i = 1, #self do
		errors[i] = self[i]:adjust_weights_output(inputs, outputs[i], targets[i])
	end

	return errors
end

function _NeuronLayer:adjust_weights(inputs, output_layer, output_errors)
	local outputs = output_layer:get_outputs()
	local errors = {}
	for i = 1, #self do
		errors[i] = self[i]:adjust_weights(i, inputs, output_layer, output_errors, outputs)
	end

	return errors
end

function _NeuronLayer:get_outputs()
	local outputs = {}
	for i = 1, #self do
		outputs[i] = self[i]._activation_output
	end
	return outputs
end
-------------------------------------------------------------------------------
-- ANN Class
-- layers = {
-- 	{
-- 		count = 5,
-- 		activation_function = "identity",
-- 	},
-- 	{
-- 		count = 3,
-- 		activation_function = "sigmoid",
--		activation_function_parameters = {p = 1}
-- 	},
-- }

function ANN:new(layers, bias, o)
	local o = o or {}
	setmetatable(o, self)

	if #layers < 2 then
		print("[ERROR] - ANN:new() - Neural Network must have at least 2 layers!")
		return nil
	end

	local last_layer_count = 1 -- first layer has 1 input
	for i, layer in ipairs(layers) do
		local activation_function = ann_activation_functions[layer.activation_function_name]
		if not activation_function then
			print("[ERROR] - ANN:new() - Invalid activation function:", layer.activation_function_name)
		end
		o[i] = _NeuronLayer:new(layer.count, last_layer_count, bias, activation_function, layer.activation_function_parameters)
		last_layer_count = layer.count
	end

	return o
end

local function mutate_gene(gene, mutate_chance, mutate_percentage)
	return gene * (qpd_random.toss(mutate_chance) and (qpd_random.choose(-mutate_percentage, mutate_percentage) + 1) or 1)
	-- return qpd_random.choose(mom[i][j][k], dad[i][j][k]) * (qpd_random.toss(mutate_chance) and (qpd_random.choose(-mutate_percentage, mutate_percentage) + 1) or 1)
end

function ANN:crossover(mom, dad, mutate_chance, mutate_percentage, crossover)
	local son = {}
	setmetatable(son, self)

	for i = 1, #mom do
		local layer = qpd_table.deep_clone(mom[i])
		local new_layer = {}

		local crossover_layer
		local crossover_neuron
		if crossover == false then
			crossover_layer = 0
			crossover_neuron = 0
		else
			crossover_layer = qpd_random.random(1, #layer)
			crossover_neuron = qpd_random.random(1, #layer[1])
		end

		for j = 1, #layer do
			local inputs = {}
			for k = 1, #layer[j] do
				if crossover and j >= crossover_layer and k >= crossover_neuron then
					inputs[k] = mutate_gene(dad[i][j][k], mutate_chance, mutate_percentage)
				else
					inputs[k] = mutate_gene(mom[i][j][k], mutate_chance, mutate_percentage)
				end
			end

			local bias
			if crossover and j >= crossover_layer then
				bias = mutate_gene(dad[i][j].bias, mutate_chance, mutate_percentage)
			else
				bias = mutate_gene(mom[i][j].bias, mutate_chance, mutate_percentage)
			end

			new_layer[j] = _Neuron:new(inputs, bias, mom[i][j].activation_function, mom[i][j].activation_function_parameters)
		end

		son[i] = _NeuronLayer:new(new_layer)
	end

	return son
end

function ANN:to_string()
	local str = string.format("{%s", self[1]:to_string())
	for i = 2, #self do
		str = string.format("%s%s", str, self[i]:to_string())
	end
	str = string.format("%s}", str)
	return str
end

function ANN:get_outputs(inputs)
	self[1]:update_entry_layer(inputs)
	local last_layer = self[1]

	for i = 2, #self do
		local neuron_layer = self[i]
		neuron_layer:update(last_layer)
		last_layer = neuron_layer
	end

	return last_layer:get_outputs()
end

function ANN:adjust_weights(inputs, targets, outputs)
	local outputs = outputs or self:get_outputs(inputs)
	local errors = self[#self]:adjust_weights_output(self[#self - 1]:get_outputs(), outputs, targets)

	for i = #self - 1, 2, -1 do
		errors = self[i]:adjust_weights(self[i - 1]:get_outputs(), self[i + 1], errors)
	end

	self[1]:adjust_weights(inputs, self[2], errors)
end

return ANN