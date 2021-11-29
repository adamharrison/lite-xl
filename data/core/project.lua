local common = require "core.common"
local config = require "core.config"
local project = {}

function project:new(dir)
  self.dir = common.normalize_volume(dir)
  self.directories = {}
  self:add_directory(dir)
end


local function strip_leading_path(filename)
    return filename:sub(2)
end

local function strip_trailing_slash(filename)
  if filename:match("[^:][/\\]$") then
    return filename:sub(1, -2)
  end
  return filename
end

local function compare_file(a, b)
  return a.filename < b.filename
end


-- compute a file's info entry completed with "filename" to be used
-- in project scan or falsy if it shouldn't appear in the list.
local function get_project_file_info(root, file)
  local info = system.get_file_info(root .. file)
  if info then
    info.filename = strip_leading_path(file)
    return (info.size < config.file_size_limit * 1e6 and
      not common.match_pattern(info.filename, config.ignore_files)
      and info)
  end
end


function project:add_directory(path)
  -- top directories has a file-like "item" but the item.filename
  -- will be simply the name of the directory, without its path.
  -- The field item.topdir will identify it as a top level directory.
  path = common.normalize_volume(path)
  local dir = {
    name = path,
    item = {filename = common.basename(path), type = "dir", topdir = true},
    files_limit = false,
    is_dirty = true,
    shown_subdir = {},
    id_mapping = {}
  }
  table.insert(core.project_directories, dir)
  local fstype = PLATFORM == "Linux" and system.get_fs_type(dir.name)
  dir.scan_type = fstype and (fstype == "nfs" or fstype == "fuse") and "scan" or "monitor"
  if dir.scan_type == "monitor" then dir.monitor = dirmonitor.new() end
  
  local t, complete, entries_count = get_directory_files(dir, dir.name, "", {}, 0, timed_max_files_pred, dir.scan_type == "monitor" and function(path) 
    local id = dir.monitor.watch(path)
    if id then
      dir.id_mapping[id] = path
    else
      dir.scan_type = "scan"
      dir.monitor = nil
      dir.id_mapping = {}
    end
  end)
  if not complete then
    dir.slow_filesystem = not complete and (entries_count <= config.max_project_files)
    dir.files_limit = true
    if core.status_view then
      core.show_max_files_warning(dir)
    end
  end
  dir.files = t
  return dir
end 


local function files_info_equal(a, b)
  return a.filename == b.filename and a.type == b.type
end

-- for "a" inclusive from i1 + 1 and i1 + n
local function files_list_match(a, i1, n, b)
  if n ~= #b then return false end
  for i = 1, n do
    if not files_info_equal(a[i1 + i], b[i]) then
      return false
    end
  end
  return true
end

-- arguments like for files_list_match
local function files_list_replace(as, i1, n, bs)
  local m = #bs
  local i, j = 1, 1
  while i <= m or i <= n do
    local a, b = as[i1 + i], bs[j]
    if i > n or (j <= m and not files_info_equal(a, b) and
      not system.path_compare(a.filename, a.type, b.filename, b.type))
    then
      table.insert(as, i1 + i, b)
      i, j, n = i + 1, j + 1, n + 1
    elseif j > m or system.path_compare(a.filename, a.type, b.filename, b.type) then
      table.remove(as, i1 + i)
      n = n - 1
    else
      i, j = i + 1, j + 1
    end
  end
end

local function project_subdir_bounds(dir, filename)
  local index, n = 0, #dir.files
  for i, file in ipairs(dir.files) do
    local file = dir.files[i]
    if file.filename == filename then
      index, n = i, #dir.files - i
      for j = 1, #dir.files - i do
        if not common.path_belongs_to(dir.files[i + j].filename, filename) then
          n = j - 1
          break
        end
      end
      return index, n, file
    end
  end
end

local function rescan_project_subdir(dir, filename_rooted)
  local new_files = get_directory_files(dir, dir.name, filename_rooted, {}, 0, core.project_subdir_is_shown, coroutine.yield)
  local index, n = 0, #dir.files
  if filename_rooted ~= "" then
    local filename = strip_leading_path(filename_rooted)
    index, n = project_subdir_bounds(dir, filename)
  end

  if not files_list_match(dir.files, index, n, new_files) then
    files_list_replace(dir.files, index, n, new_files)
    dir.is_dirty = true
    return true
  end
end

-- "root" will by an absolute path without trailing '/'
-- "path" will be a path starting with '/' and without trailing '/'
--    or the empty string.
--    It will identifies a sub-path within "root.
-- The current path location will therefore always be: root .. path.
-- When recursing "root" will always be the same, only "path" will change.
-- Returns a list of file "items". In eash item the "filename" will be the
-- complete file path relative to "root" *without* the trailing '/'.
function project:get_directory_files(dir, root, path, t, entries_count, recurse_pred, begin_hook)
  if begin_hook then begin_hook(t) end
  local t0 = system.get_time()
  local all = system.list_dir(root .. path) or {}
  local t_elapsed = system.get_time() - t0
  local dirs, files = {}, {}

  for _, file in ipairs(all) do
    local info = get_project_file_info(root, path .. PATHSEP .. file)
    if info then
      table.insert(info.type == "dir" and dirs or files, info)
      entries_count = entries_count + 1
    end
  end

  local recurse_complete = true
  table.sort(dirs, compare_file)
  for _, f in ipairs(dirs) do
    table.insert(t, f)
    if recurse_pred(dir, f.filename, entries_count, t_elapsed) then
      local _, complete, n = self:get_directory_files(dir, root, PATHSEP .. f.filename, t, entries_count, recurse_pred, begin_hook)
      recurse_complete = recurse_complete and complete
      entries_count = n
    else
      recurse_complete = false
    end
  end

  table.sort(files, compare_file)
  for _, f in ipairs(files) do
    table.insert(t, f)
  end

  return t, recurse_complete, entries_count
end



local function file_search(files, info)
  local filename, type = info.filename, info.type
  local inf, sup = 1, #files
  while sup - inf > 8 do
    local curr = math.floor((inf + sup) / 2)
    if system.path_compare(filename, type, files[curr].filename, files[curr].type) then
      sup = curr - 1
    else
      inf = curr
    end
  end
  while inf <= sup and not system.path_compare(filename, type, files[inf].filename, files[inf].type) do
    if files[inf].filename == filename then
      return inf, true
    end
    inf = inf + 1
  end
  return inf, false
end


local function project_scan_add_entry(dir, fileinfo)
  local index, match = file_search(dir.files, fileinfo)
  if not match then
    table.insert(dir.files, index, fileinfo)
    dir.is_dirty = true
  end
end


function project:update_project_subdir(dir, filename, expanded)
  local index, n, file = project_subdir_bounds(dir, filename)
  if index then
    local new_files = expanded and get_directory_files(dir, dir.name, PATHSEP .. filename, {}, 0, core.project_subdir_is_shown) or {}
    files_list_replace(dir.files, index, n, new_files)
    dir.is_dirty = true
    return true
  end
end


-- Find files and directories recursively reading from the filesystem.
-- Filter files and yields file's directory and info table. This latter
-- is filled to be like required by project directories "files" list.
local function find_files_rec(root, path)
  local all = system.list_dir(root .. path) or {}
  for _, file in ipairs(all) do
    local file = path .. PATHSEP .. file
    local info = system.get_file_info(root .. file)
    if info then
      info.filename = strip_leading_path(file)
      if info.type == "file" then
        coroutine.yield(root, info)
      else
        find_files_rec(root, PATHSEP .. info.filename)
      end
    end
  end
end


-- Iterator function to list all project files
local function project_files_iter(state)
  local dir = state.project.directories[state.dir_index]
  if state.co then
    -- We have a coroutine to fetch for files, use the coroutine.
    -- Used for directories that exceeds the files nuumber limit.
    local ok, name, file = coroutine.resume(state.co, dir.name, "")
    if ok and name then
      return name, file
    else
      -- The coroutine terminated, increment file/dir counter to scan
      -- next project directory.
      state.co = false
      state.file_index = 1
      state.dir_index = state.dir_index + 1
      dir = state.project.directories[state.dir_index]
    end
  else
    -- Increase file/dir counter
    state.file_index = state.file_index + 1
    while dir and state.file_index > #dir.files do
      state.dir_index = state.dir_index + 1
      state.file_index = 1
      dir = state.project.directories[state.dir_index]
    end
  end
  if not dir then return end
  if dir.files_limit then
    -- The current project directory is files limited: create a couroutine
    -- to read files from the filesystem.
    state.co = coroutine.create(find_files_rec)
    return project_files_iter(state)
  end
  return dir.name, dir.files[state.file_index]
end


function project:get_project_files()
  local state = { dir_index = 1, file_index = 0, project = self }
  return project_files_iter, state
end


function project:project_files_number()
  local n = 0
  for i = 1, #self.directories do
    if self.directories[i].files_limit then return end
    n = n + #self.directories[i].files
  end
  return n
end

function project:scan()
  for i, dir in ipairs(self.directories) do
    if dir.scan_type == "monitor"
      dir.monitor:check(function(id)
        rescan_project_subdir(dir, dir.id_mapping[id])
      end)
    else
      
    end
  end
end

function project:step()
  self:scan()
end

return project
