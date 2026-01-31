--[[
Town Names NML Generator, v1.0.0 (2026-01-31)
https://github.com/chujo-chujo/Town-Names-NML-Generator
Author: chujo
License: CC BY-NC-SA 4.0 (https://creativecommons.org/licenses/by-nc-sa/4.0/)

You may use, modify, and distribute this script for non-commercial purposes only (attribution required).
Any modifications or derivative works must be licensed under the same terms.
----------------------------------------------------------------------------

A GUI application that generates NML code for Town Name NewGRFs used in OpenTTD.

*** Quick Guide ***

1. Prepare your data as a simple list of names (saved as a plain text, ideally *.txt)
   or as a list of comma-separated pairs NAME, WEIGHTED PROBABILITY (saved as *.txt or *.csv)
   New York               New York, 2
   Los Angeles     or     Los Angeles, 1
   San Diego              San Diego, 1

   You can also use several separate lists to create compound names:
   New , 1        York, 1
   Los , 2        Angeles, 1        etc.        !! IMPORTANT: Pay attention to spaces (e.g. "New "),
   San , 1        Diego, 3                                    the names will be used verbatim.

2. Open this script with "START.bat", fill in the required fields (marked with *).
   Load your prepared data either by clicking on "Load data" or by dragging and dropping the file 
   directly onto the dialog window.
   If you have several parts, use the "Add" button to add another list.

3. Export your town names as NML code and/or compile it into a GRF file, which can be copied into
   OpenTTD's user files (something like "C:\Users\...\Documents\OpenTTD\newgrf").
   If you don't see the resulting *.grf file in the root folder of this app, try checking "nmlc_log.txt".
]]


require("iuplua")
require("iupluacontrols")
require("iupluaim")
local lfs = require "lfs"
math.randomseed(os.time())



-- Forward declaration, global variables
lfs.chdir("..")
local default_path = lfs.currentdir()
local last_folder = default_path

local matrix_tabs = iup.tabs{showclose = "NO"}
local current_matrix
local dlg = iup.dialog{}

local parts_probs = {}
local table_of_matrices = {}
-- Structure of stored data - each part is a table of tables, all parts stored sequentially in "table_of_matrices":
-- table_of_matrices = {
-- 	[1] = {
-- 		{name = "Name", prob = "1"},
-- 		{name = "Name", prob = "1"},
-- 		{name = "Name", prob = "1"},
-- 		etc.
-- 	},
-- 	[2] = {
-- 		{name = "Name", prob = "1"},
-- 		{name = "Name", prob = "1"},
-- 		{name = "Name", prob = "1"},
-- 		etc.
-- 	},
-- 	etc.
-- }



local function wait(t)
	local t0 = os.clock()
	while os.clock() - t0 <= t do end
end

local function trim(str)
	-- Remove leading and trailing whitespace
	return str:match("^%s*(.-)%s*$")
end

local function string_isspace(str)
	-- Returns "true" if str is a string and made only of whitespace characters
	return type(str) == "string" and str:match("^%s+$") ~= nil
end


local function generate_random_string(length)
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    local result = {}
    for i = 1, length do
        local index = math.random(1, tonumber(#chars))
        table.insert(result, chars:sub(index, index))
    end
    
    return table.concat(result)
end

local function parse_csv_string(csv_string)
	local result = {}
	local number_of_items = 0

	for line in csv_string:gmatch("[^\r\n]+") do
		if not line:find(",") then
			local key, value = line:match("^(.+)"), "1"
			if not key then
				goto continue
			else
				result[key] = value
				number_of_items = number_of_items + 1
			end
		else
			local key, value = line:match("^([^,]*),(.*)$")
			if value == "" or string_isspace(value) then
				result[key] = "1"
			else
				result[key] = trim(value)
			end
			number_of_items = number_of_items + 1
		end
		::continue::
	end

	return result, number_of_items
end

local function show_message(type, title, text, buttons)
	-- Wrapper function to display "iup.messagedlg"
	-- returns the number (as type NUMBER 1, 2 or 3) of the pressed button
	local msg = iup.messagedlg{
		dialogtype = type,
		title = title,
		value = text,
		buttons = buttons
	}
	msg:popup(iup.ANYWHERE, iup.ANYWHERE)
	return tonumber(msg.buttonresponse)
end

local function is_matrix_empty(matrix)
	if matrix:getcell(1, 1) == nil and matrix:getcell(1, 2) == nil then
		return true
	else
		return false
	end
end

local function read_matrix_data(matrix)
	-- Return table of tables of matrix data
	local matrix_data = {}
	for row = 1, tonumber(matrix.numlin) do
		local name = matrix:getcell(row, 1)
		local prob = matrix:getcell(row, 2)
		if name and (prob and prob ~= "") then
			table.insert(matrix_data, {name = name, prob = prob})
		end
	end
	return matrix_data
end

local function update_tab_labels()
	if tonumber(matrix_tabs.count) == 1 then
		matrix_tabs["tabtitle0"] = "List of names"
	else
		for i = 0, tonumber(matrix_tabs.count) - 1 do
			matrix_tabs["tabtitle" .. i] = "Part " .. i + 1
		end
	end
end

local function clear_list()
	current_matrix = iup.GetChild(matrix_tabs, matrix_tabs.valuepos)
	current_matrix.numlin = 0
	current_matrix.numlin = 3
end

local function remove_list()
	if tonumber(matrix_tabs.count) == 1 then
			return iup.DEFAULT
	else
		local current_tab_index = tonumber(matrix_tabs.valuepos)
		iup.Destroy(iup.GetChild(matrix_tabs, current_tab_index))
		iup.Refresh(matrix_tabs)
		update_tab_labels()
		matrix_tabs.valuepos = math.min(current_tab_index, tonumber(matrix_tabs.count - 1))
	end
end

local function close_app()
	local response = show_message(
		"QUESTION",
		"", 
		"  Are you sure you want to exit?", 
		"OKCANCEL")
	if response == 1 then
		return true
	else
		return false
	end
end

local function open_file(filepath)
	local filepath = filepath or nil
	if not filepath then
		local file_dlg = iup.filedlg{
			dialogtype = "OPEN",
			directory  = last_folder,     -- default filepath = one level up from this script
			filter     = "*.*",
			filterinfo = "All Files (*.*)",
		}
		file_dlg:popup(iup.ANYWHERE, iup.ANYWHERE)
		if file_dlg.status ~= "-1" then
			filepath = file_dlg.value
			last_folder = filepath:match("^(.*)[/\\][^/\\]+$")
		else
			return iup.DEFAULT
		end
	end

	local csv_file, err = io.open(filepath, "r")
	if not csv_file then
		show_message("ERROR", "Error", "  Could not open file: " .. filepath .. "\n  Error: " .. err, "OK")
		return
	end

	local csv_data = csv_file:read("*all")
	csv_file:close()

	if csv_data ~= "" and csv_data ~= " " then
		table_name_prob, number_of_items = parse_csv_string(csv_data)
	else
		show_message("ERROR", "Error", "  No usable data found in\n  " .. filepath)
		return
	end

	-- Clear matrix
	current_matrix = iup.GetChild(matrix_tabs, matrix_tabs.valuepos)
	clear_list()
	update_tab_labels()

	-- Sort data by name (ascending)
	local sorted_table = {}
	for name, prob in pairs(table_name_prob) do
		sorted_table[#sorted_table + 1] = {name = name, prob = prob}
	end
	table.sort(sorted_table, function(a, b) return a.name < b.name end)

	-- Fill the matrix
	current_matrix.numlin = number_of_items
	local i = 1
	for i, row in ipairs(sorted_table) do
		current_matrix[i .. ":1"] = row.name
		current_matrix[i .. ":2"] = tostring(row.prob)
		i = i + 1
	end

	current_matrix.redraw = "ALL"

	return iup.DEFAULT
end

local function get_parts_probs(dlg)
	local vbox_entries = iup.vbox{
		iup.label{title = "Assign weights to each part:"},
		iup.label{separator = "HORIZONTAL"},
		iup.fill{rastersize = "x20"}
	}

	for i = 0, tonumber(matrix_tabs.count) - 1 do
		iup.Append(vbox_entries,
			iup.hbox{
				iup.label{title = "Part " .. i + 1 .. ":", alignment = "ACENTER", rastersize = "70x"},
				iup.text{value = "1", alignment = "ACENTER", rastersize = "40x", mask = "[0-9]+",},
				margin = "0x3",
			}
		)
	end

	local btn_ok = iup.button{title = "OK", expand = "HORIZONTAL", rastersize = "x40"}
	function btn_ok:action()
		-- Make sure "parts_probs" is empty
		parts_probs = {}

		-- Iterate over hboxes with Part probs, read prob values and insert them into "parts_probs"
		local child = iup.GetChild(vbox_entries, 0)
		while child do
			if iup.GetClassName(child) == "hbox" then
				local text_prob = iup.GetChild(child, 1)
				if trim(text_prob.value) == "" or trim(text_prob.value) == "0" then
					text_prob.value = ""
					return
				end
				table.insert(parts_probs, text_prob.value)
			end
			child = iup.GetNextChild(vbox_entries, child)
		end
		return iup.CLOSE
	end
	iup.SetAttribute(btn_ok, "FONTSTYLE", "Bold")
	iup.Append(vbox_entries, iup.fill{rastersize = "x20"})
	iup.Append(vbox_entries, btn_ok)

	local dlg_parts = iup.dialog{
		vbox_entries,
		margin = "20x20",
		title = "",
		resize = "NO",
		menubox = "NO",
		icon = img_favicon,
		parentdialog = iup.GetDialog(dlg),
	}

	dlg_parts:popup(iup.CENTERPARENT, iup.CENTERPARENT)
end

local function generate_NML(grfid, version, grf_name, grf_menu, grf_desc, grf_url, only_NML)
	-- Check missign parameters
	if not grfid or trim(grfid) == "" then
		show_message("WARNING", "Missing GRFID", "  Grf ID is a mandatory parameter.", "OK")
		return false
	end
	if not version or trim(version) == "" then
		show_message("WARNING", "Missing version", "  Version number is a mandatory parameter.", "OK")
		return false
	end
	-- if not min_comp_version or min_comp_version == "" then
	-- 	show_message("WARNING", "Missing min. comp. version", "  Minimal compatible version number is a mandatory parameter.", "OK")
	-- 	return
	-- end
	-- if tonumber(version) < tonumber(min_comp_version) then
	-- 	show_message("WARNING", "", "  'Version' number has to be greater than or equal to\n  'minimal compatible version' number.", "OK")
	-- 	return
	-- end
	if not grf_name or trim(grf_name) == "" then
		show_message("WARNING", "Missing NewGRF name", "  NewGRF name is a mandatory parameter.", "OK")
		return false
	end
	if not grf_menu or trim(grf_menu) == "" then
		show_message("WARNING", "Missing Menu label", "  Menu label is a mandatory parameter.", "OK")
		return false
	end

	if trim(grf_url) == "" then
		grf_url = "https://github.com/chujo-chujo/Town-Names-NML-Generator"
	end
	if trim(grf_desc) == "" then
		grf_desc = string.format('{}Generated by {ORANGE}Town Names NML Generator{}{SILVER}https://github.com/chujo-chujo/Town-Names-NML-Generator{}{}{LTBLUE}%s', os.date("%B %d, %Y"))
	end

	-- Check if multipart - if so assign weights to each part (stored in "parts_probs")
	if tonumber(matrix_tabs.count) > 1 then
		get_parts_probs(dlg)
	else
		parts_probs = {"1"}
	end

	-- Read data from all matrices
	table_of_matrices = {}
	for i = 0, tonumber(matrix_tabs.count) - 1 do
		table.insert(table_of_matrices, read_matrix_data(iup.GetChild(matrix_tabs, i)))
	end


	local header = string.format(
		'grf {\n' ..
		'    grfid: "%s";\n' ..
		'    name: string(STR_GRF_NAME);\n' ..
		'    desc: string(STR_GRF_DESC);\n' ..
		'    url: string(STR_GRF_URL);\n' ..
		'    version: %s;\n' ..
		'    min_compatible_version: %s;\n' ..
		'}\n\n', grfid, version, version)


	local list_town_names = {}
	for i, part in ipairs(table_of_matrices) do
		local block_name = string.char(string.byte("A") + (i-1))
		table.insert(list_town_names, string.format("town_names(%s) {\n    {\n", block_name))
		for _, k in ipairs(part) do
			table.insert(list_town_names, string.format('        text("%s", %s),\n', k.name, k.prob))
		end
		table.insert(list_town_names, "    }\n}\n\n")
	end
	list_town_names = table.concat(list_town_names, "")


	local top_names_block = {"\ntown_names {\n    styles: string(STR_MENU);\n"}
	for i, v in ipairs(parts_probs) do
		table.insert(top_names_block,
			string.format("    {\n        town_names(%s, %s)\n    }\n",
				string.char(string.byte("A") + (i-1)), parts_probs[i]))
	end
	table.insert(top_names_block, "}")
	top_names_block = table.concat(top_names_block, "")


	local NML = 
		header ..
		list_town_names .. 
		top_names_block


	local lang = {
		"##grflangid 0x01",
		"",
		string.format("STR_GRF_NAME:%s", grf_name),
		string.format("STR_GRF_DESC:%s", grf_desc),
		string.format("STR_GRF_URL:%s", grf_url),
		string.format("STR_MENU:%s", grf_menu)
	}
	lang = table.concat(lang, "\n")


	-- Write results into files (in the root, .nml + 'lang' folder)
	lfs.mkdir(default_path .. "\\lang")

	local NML_filename_stem = grf_name:lower():gsub('[\\/:*?"<>| ]', '_')
	local NML_file = io.open(default_path .. "\\" .. NML_filename_stem .. ".nml", "w")
	NML_file:write(NML):close()
	
	local lang_file = io.open(default_path .. "\\lang\\english.lng", "w")
	lang_file:write(lang):close()

	if only_NML then
		show_message("INFORMATION", "", "  Done!", "OK")
	end

	return NML_filename_stem
end

local function compile(grfid, version, grf_name, grf_menu, grf_desc, grf_url)
	local NML_filename_stem = generate_NML(grfid, version, grf_name, grf_menu, grf_desc, grf_url, false)
	if not NML_filename_stem then
		return iup.DEFAULT
	end

	local dlg_compilation = iup.dialog{
		iup.label{title = "Compiling...", rastersize = "300x100", alignment = "ACENTER"},
		maxbox  = "NO",
		minbox  = "NO",
		menubox = "NO",
		resize  = "NO",
		title   = nil,
		background   = "209 210 222",
		parentdialog = iup.GetDialog(dlg),
	}
	iup.SetAttribute(iup.GetChild(dlg_compilation, 0), "FONTSTYLE", "Bold")
	dlg_compilation:showxy(iup.CENTERPARENT, iup.CENTERPARENT)

	local cmd = "files\\nmlc.exe " .. NML_filename_stem .. ".nml"
	local pipe = io.popen(cmd .. " 2>&1")
	local output = pipe:read("*all")
	pipe:close()

	local log_file = io.open(default_path .. "\\nmlc_log.txt", "w")
	log_file:write(output)
	log_file:close()

	dlg_compilation:destroy()

	-- Test if the grf file exists
	local grf_file = io.open(default_path .. "\\" .. NML_filename_stem .. ".grf", "r")
	if grf_file then
		show_message("INFORMATION", "", "  Done!", "OK")
		grf_file:close()
	else
		show_message("ERROR", "Sum Ting Wong", '  Compilation failed.\n  Check "nmlc_log.txt".', "OK")
	end
end

local function add_tab()
	local new_matrix = iup.matrix{
		numcol = 2,
		width1 = "140",
		width2 = "55",
		sortsign1 = "UP",
		numlin = 100,
		alignment1 = "ALEFT",
		readonly = "YES",
		rastersize = "328x410",
		expand = "NO",
	}
	new_matrix["0:1"] = "Name"
	new_matrix["0:2"] = "Probability"

	function new_matrix:click_cb(lin, col)
		current_matrix = iup.GetChild(matrix_tabs, matrix_tabs.valuepos)		
		local sorted_table = read_matrix_data(current_matrix)

		if lin == 0 and col == 2 then
			-- Sort by probabilities (descending)
			table.sort(sorted_table, function(a, b)
				return tonumber(a.prob) > tonumber(b.prob)
			end)

			for i, row in ipairs(sorted_table) do
				new_matrix[i .. ":1"] = row.name
				new_matrix[i .. ":2"] = tostring(row.prob)
			end

			new_matrix.sortsign1 = "NO"
			new_matrix.sortsign2 = "DOWN"

		elseif lin == 0 and col == 1 then
			-- Sort by names (ascending)
			table.sort(sorted_table, function(a, b)
				return a.name < b.name
			end)

			for i, row in ipairs(sorted_table) do
				new_matrix[i .. ":1"] = row.name
				new_matrix[i .. ":2"] = tostring(row.prob)
			end

			new_matrix.sortsign1 = "UP"
			new_matrix.sortsign2 = "NO"
		end
	end

	iup.Append(matrix_tabs, new_matrix)
	iup.Map(new_matrix)
	iup.Refresh(matrix_tabs)

	update_tab_labels()

	-- Focus on the new tab, set its matrix as current_matrix
	matrix_tabs.valuepos = tonumber(matrix_tabs.count) - 1
	current_matrix = new_matrix
end



-- ########################################################################################################

local function build_gui()
	-- Load icons
	img_favicon       = iup.LoadImage("files/gui/icon.png")
	local img_random  = iup.LoadImage("files/gui/random.png")
	local img_add     = iup.LoadImage("files/gui/add.png")
	local img_open    = iup.LoadImage("files/gui/open.png")
	local img_clear   = iup.LoadImage("files/gui/clear.png")
	local img_remove  = iup.LoadImage("files/gui/remove.png")
	local img_nml     = iup.LoadImage("files/gui/nml.png")
	local img_compile = iup.LoadImage("files/gui/compile.png")

	-- Define the main dialog window
	local dlg_width  = 460
	local dlg_height = 727

	dlg = iup.dialog{
		title = "Town Names NML Generator",
		rastersize = dlg_width .. "x" .. dlg_height,
		resize = "NO",
		maxbox = "NO",
		icon = img_favicon,
		dropfilestarget = "YES",
		dropfiles_cb = function(self, filepath, num, x, y) open_file(filepath) return iup.DEFAULT end,
		close_cb = function() if close_app() then return iup.CLOSE else return iup.IGNORE end end
	}

	function dlg:k_any(key)
		if key == iup.K_cQ or key == iup.K_ESC then
			if close_app() then
				return iup.CLOSE
			end
		elseif key == iup.K_cO then
			open_file()
		end
	end

	-- #### GRF PARAMETERS ###########################################################################################

	local textbox_width  = "123x"
	local cy_first_line  = 10
	local cy_second_line = 40
	local cy_third_line  = 70
	local cy_fourth_line = 100
	local cy_fifth_line  = 130

	local label_grfid = iup.label{title = "Grf ID*:"}
	-- iup.SetAttribute(label_grfid, "FONTSTYLE", "Bold")
	local text_grfid = iup.text{
		mask = "[A-Z0-9\\]+",
		NC = 12,
		rastersize = textbox_width,
		tip = "Four-byte string\n(can use escaped bytes)"
	}
	local label_version = iup.label{title = "Version*:"}
	-- iup.SetAttribute(label_version, "FONTSTYLE", "Bold")
	local text_version = iup.text{
		mask = "/d+",
		value = "1",
		spin = "YES",
		spinmin = "0",
		spininc = "1",
		rastersize = textbox_width
	}
	-- local label_min_comp_version = iup.label{title = "Min. comp. version:"}
	-- local text_min_comp_version = iup.text{
	-- 	mask = "/d+",
	-- 	value = "1",
	-- 	spin = "YES",
	-- 	spinmin = "0",
	-- 	spininc = "1",
	-- 	rastersize = textbox_width
	-- }
	local label_grf_name = iup.label{title = "NewGRF name*:"}
	-- iup.SetAttribute(label_grf_name, "FONTSTYLE", "Bold")
	local text_grf_name  = iup.text{rastersize = "303x", tip = 'Name displayed in "NewGRF Settings"'}
	local label_grf_menu = iup.label{title = "Menu label*:"}
	-- iup.SetAttribute(label_grf_menu, "FONTSTYLE", "Bold")
	local text_grf_menu  = iup.text{rastersize = "324x", tip = 'Label displayed in "World Generation"'}
	local label_grf_url  = iup.label{title = "NewGRF url:"}
	local text_grf_url   = iup.text{rastersize = "324x", tip = "Optional"}
	local label_grf_desc = iup.label{title = "Description:"}
	local text_grf_desc  = iup.text{rastersize = "324x", tip = "Optional"}

	local btn_random_grfid = iup.flatbutton{
		image = img_random,
		rastersize = "30x25",
		tip = "Generate random Grf ID"
	}
	function btn_random_grfid:flat_action()
		local grfid = ""
		for i = 1, 4 do grfid = grfid .. string.format("\\%02X", math.random(0, 255)) end
		text_grfid.value = grfid
	end

	label_grfid.cx = 10
	label_grfid.cy = cy_first_line
	text_grfid.cx = 56
	text_grfid.cy = cy_first_line - 2
	btn_random_grfid.cx = 179
	btn_random_grfid.cy = cy_first_line - 4
	label_version.cx = 230
	label_version.cy = cy_first_line
	text_version.cx = 286
	text_version.cy = cy_first_line - 2
	-- label_min_comp_version.cx = 430
	-- label_min_comp_version.cy = cy_first_line
	-- text_min_comp_version.cx = 548
	-- text_min_comp_version.cy = cy_first_line - 2

	label_grf_name.cx = 10
	label_grf_name.cy = cy_second_line
	text_grf_name.cx = 106
	text_grf_name.cy = cy_second_line - 2
	label_grf_menu.cx = 10
	label_grf_menu.cy = cy_third_line
	text_grf_menu.cx = 85
	text_grf_menu.cy = cy_third_line - 2
	label_grf_url.cx = 10
	label_grf_url.cy = cy_fourth_line
	text_grf_url.cx = 85
	text_grf_url.cy = cy_fourth_line - 2
	
	label_grf_desc.cx = 10
	label_grf_desc.cy = cy_fifth_line
	text_grf_desc.cx = 132-47
	text_grf_desc.cy = cy_fifth_line - 2

	local frame_header = iup.frame{
		iup.cbox{
			label_grfid,
			text_grfid,
			btn_random_grfid,
			label_version,
			text_version,
			-- label_min_comp_version,
			-- text_min_comp_version,
			label_grf_name,
			text_grf_name,
			label_grf_menu,
			text_grf_menu,

			label_grf_url,
			text_grf_url,
			label_grf_desc,
			text_grf_desc
		},
		rastersize = "425x180",
		expand = "NO",
		title = " GRF parameters ",
	}

	-- #### ACTIONS ###########################################################################################

	local btn_add = iup.button{
		flat = "YES",
		image = img_add,
		title = "Add",
		imageposition = "TOP",
		rastersize = "53x57",
		action = function() add_tab() return iup.DEFAULT end,
		canfocus = "NO",
		tip = "Add list"}
	-- local btn_clear = iup.button{
	-- 	flat = "YES",
	-- 	image = img_clear,
	-- 	title = "Clear",
	-- 	imageposition = "TOP",
	-- 	rastersize = "53x57",
	-- 	action = function() clear_list() return iup.DEFAULT end,
	-- 	canfocus = "NO",
	-- 	tip = "Clear list"}
	local btn_open = iup.button{
		flat = "YES",
		image = img_open,
		title = "Load data",
		imageposition = "TOP",
		rastersize = "53x57",
		action = function() open_file() return iup.DEFAULT end,
		canfocus = "NO",
		tip = "Load data from a file\n(or drag-n-drop)"}
	local btn_remove = iup.button{
		flat = "YES",
		image = img_remove,
		title = "Remove",
		imageposition = "TOP",
		rastersize = "53x57",
		action = function() remove_list() return iup.DEFAULT end,
		canfocus = "NO",
		tip = "Remove list"}

	local btn_nml = iup.button{
		flat = "YES",
		image = img_nml,
		title = "NML",
		imageposition = "TOP",
		rastersize = "53x57",
		action = function()
			generate_NML(text_grfid.value, text_version.value, text_grf_name.value, text_grf_menu.value, text_grf_desc.value, text_grf_url.value, true)
			return iup.DEFAULT
		end,
		canfocus = "NO",
		tip = "Generate NML"}
	local btn_compile = iup.button{
		flat = "YES",
		image = img_compile,
		title = "NML &&\nCompile",
		imageposition = "TOP",
		rastersize = "53x75",
		action = function()
			compile(text_grfid.value, text_version.value, text_grf_name.value, text_grf_menu.value, text_grf_desc.value, text_grf_url.value)
			return iup.DEFAULT
		end,
		canfocus = "NO",
		tip = "Generate NML and compile"}

	local vbox_actions = iup.vbox{
		btn_add,
		btn_open,
		-- btn_clear,
		btn_remove,
		iup.fill{rastersize = "x40"},
		iup.label{title = "EXPORT:", alignment = "ACENTER", rastersize = "53x"},
		btn_nml,
		btn_compile,
		rastersize = "50x300",
		margin = "0x0",
		gap = "9"
	}
	for i = 0, iup.GetChildCount(vbox_actions) - 1 do
		local child = iup.GetChild(vbox_actions, i)
		if child.title == "EXPORT:" then
			iup.SetAttribute(child, "FONTSTYLE", "Bold")
			break
		end
	end



	-- #### TOWN NAMES ###########################################################################################

	add_tab()
	current_matrix = iup.GetChild(matrix_tabs, 0)

	-- Closing a tab removes it
	function matrix_tabs:tabclose_cb(position)
		return iup.CONTINUE
	end
	-- Right click closes a tab
	function matrix_tabs:rightclick_cb(position)
		if tonumber(self.count) == 1 then
			return iup.DEFAULT
		else
			iup.Destroy(iup.GetChild(self, position))
			iup.Refresh(matrix_tabs)
			update_tab_labels()
		end
	end
	-- Set current matrix when tab changes
	function matrix_tabs:tabchange_cb(new_tab, old_tab)
		current_matrix = new_tab
	end


	local frame_names = iup.frame{
		iup.hbox{
			vbox_actions,
			matrix_tabs,
			margin = "10x10",
			rastersize = "420x",
		},
		title = " Town names ",
	}

	-- #### MAIN BOX ###########################################################################################

	local vbox_main = iup.vbox{
		frame_header,
		frame_names,
		margin = "10x10",
		gap = "10"
	}


	dlg:append(vbox_main)
	dlg:showxy(80, 5)

	if iup.MainLoopLevel() == 0 then
		iup.MainLoop()
		iup.Close()
	end

end


do
	build_gui()
end