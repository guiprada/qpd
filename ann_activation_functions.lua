local ann_activation_functions = {}

function ann_activation_functions.identity(a)
	return a
end

function ann_activation_functions.binary_step(a, bias)
	if a >= bias then
		return 1
	else
		return 0
	end
end

function ann_activation_functions.sigmoid(a, _bias, parameters)
	local p = parameters and parameters.sigmoid
	return 1 / (1 + math.exp(-a/p))
end

function ann_activation_functions.tanh(a)
	return (math.exp(a) - math.exp(-a))/(math.exp(a) + math.exp(-a))
end

function ann_activation_functions.tanh_lua(a)
	return math.tanh(a)
end

function ann_activation_functions.relu(a)
	if a <= 0 then
		return 0
	else
		return a
	end
end

function ann_activation_functions.softplus(a)
	return math.log(1 + math.exp(a))
end

function ann_activation_functions.silu(a)
	return a/(1 + math.exp(-a))
end

return ann_activation_functions