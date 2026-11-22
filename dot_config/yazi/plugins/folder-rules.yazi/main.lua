-- Downloads sorts newest first; leaving it restores the tab's previous sort.
-- ind-sort also fires on file updates, so act only when a tab enters a directory.
local last, saved = {}, {}

local function setup()
	ps.sub("ind-sort", function(opt)
		local tab = cx.active
		local id, cwd = tab.id.value, tostring(tab.current.cwd)
		if last[id] == cwd then
			return opt
		end
		last[id] = cwd

		local pref = tab.pref
		if tab.current.cwd:ends_with("Downloads") then
			saved[id] = saved[id] or { pref.sort_by, pref.sort_reverse, pref.sort_dir_first }
			opt.by, opt.reverse, opt.dir_first = "mtime", true, false
		elseif saved[id] then
			opt.by, opt.reverse, opt.dir_first = table.unpack(saved[id])
			saved[id] = nil
		end
		return opt
	end)
end

return { setup = setup }
