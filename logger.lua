local logger = {}
logger.__index = logger

local MAX_LINE_IN_SINGLE_FILE = 15000

local function create_file(file_path)
	local file, err = io.open(file_path, "w")
	if not file then
		print("[ERROR] - logger:new() - Error creating file:", file_path,". io.open() returned:", err)
		return nil
	else
		return file
	end
end

function logger:new(file_path, columns, autoflush_limit, o)
	local o = o or {}
	setmetatable(o, self)

	o._file_path_root = file_path

	o._split_counter = 0
	o._lines_in_file = 0
	o._file_path = string.format("%s-%s", o._file_path_root, tostring(o._split_counter))

	o._columns = columns

	local file = create_file(o._file_path)
	if file then
		for i = 1, #o._columns do
			local this_column = o._columns[i]
			if i == 1 then
				file:write(this_column)
			else
				file:write(", ", this_column)
			end
		end
		file:write("\n")
		file:flush()

		if autoflush_limit then
			o._autoflush_limit = autoflush_limit
		end

		o._log_tables = {}
		o._dirty_counter = 0

		file:close()

		return o
	end

	return nil
end

function logger:log(log_table)
	self._dirty_counter = self._dirty_counter + 1
	self._log_tables[self._dirty_counter] = log_table

	if self._autoflush_limit then
		if self._dirty_counter > self._autoflush_limit then
			self:flush()
		end
	end
end

function logger:split_file(file)
	file:flush()
	file:close()

	self._split_counter = self._split_counter + 1
	self._lines_in_file = 0
	self._file_path = string.format("%s-%s", self._file_path_root, tostring(self._split_counter))

	local file = create_file(self._file_path)
	if file then
		return file
	else
		return nil
	end
end

local function write_log_table(log_table, file, columns)
	for i = 1, #columns do
		local this_column = columns[i]

		local this_value = log_table[this_column] or "null"
		if i == 1 then
			file:write(this_value)
		else
			file:write(", ", this_value)
		end
	end
	file:write("\n")
end

function logger:flush()
	local file, err = io.open(self._file_path, "a+")
	if not file then
		print("[ERROR] - logger:flush() error opening file:", o._file_path,". io.open() returned:", err)
		return
	end

	for i = 1, self._dirty_counter do
		write_log_table(self._log_tables[i], file, self._columns)

		self._lines_in_file = self._lines_in_file + 1
		self._dirty_counter = self._dirty_counter - 1

		if self._lines_in_file > MAX_LINE_IN_SINGLE_FILE then
			file = self:split_file(file)
			if not file then
				return
			end
		end
	end

	file:flush()
	file:close()
end

return logger