-- HUSH hub · Luau / Madium-Chimera
-- ESP: light labels, proximity detail, screen-space declutter.

-- Camera-only compatibility build: no weapon/namecall/upvalue hooks.
if getgenv().__HushNamecallHooked or getgenv().__HushOrigSight or getgenv().__HushOrigSpread then
    local previous = getgenv().HushSession
    local old = previous and previous.state
    if old then
        if old.aim then old.aim.enabled, old.aim.no_recoil, old.aim.no_spread = false, false, false end
        if old.silencer then old.silencer.enabled = false end
        previous.active = false
    end
    getgenv().__HushNamecallState = nil
    local runtime = getgenv().__HushNamecallRuntime
    if runtime then runtime.state = nil end
    warn("[hush] Restart Roblox before loading this build. Old weapon hooks are still installed; hot-unhook is not attempted.")
    return
end

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local REPO = "https://raw.githubusercontent.com/joustingmatch/Alexandria/main/"
local WINDOW_TITLE = "hush"
local REFRESH_SECONDS = 3
local GUI_CONTAINER_NAME = "Obsidian"

-- ---------------------------------------------------------------------------
-- state global
-- ---------------------------------------------------------------------------

local State = {
    connections = {},
    guis = {},
    threads = {},
    live = false,
    esp = {
        enabled = true,
        declutter = false,
        outline_monsters = false,
        outline_players = false,
        outline_containers = false,
        outline_loot = false,
        outline_traps = false,
        label_budget = 24,
        render_limit = 48,
        outline_limit = 24,
        detail_distance = 120,
        visible_labels = 0,
        screen_candidates = 0,
        monsters = false,
        loot = false,
        containers = false,
        containers_high_only = false,
        auto_take_loot = false,
        instant_prompt = false,
        traps = false,
        players = false,
        loot_high_tier_only = false,
        max_monster_dist = 1500,
        max_loot_dist = 800,
        max_container_dist = 250,
        max_trap_dist = 40,
        max_player_dist = 1500,
        folder = nil,
        cache_tags = {},         -- [Instance] = { bbg, l1, l2, adornee }
        cache_highlights = {},   -- [Instance] = { hl, adornee }
        cached_prompts = {},     -- daftar SearchPrompt hasil scan berkala
        last_prompt_scan = 0,
        prompt_index = {},
        prompt_meta = {},
        nearby_prompts = {},
        prompt_holds = {},
        player_los_cache = setmetatable({}, { __mode = "k" }),
        player_los_cursor = 1,
        prompt_cache_started = false,
        index_ready = false,
        container_items = {},    -- [Instance] = "RPK · Heavy Ammo x30"
        container_empty = {},    -- [Instance] = true jika sudah kosong/diambil semua
        active_loot_part = nil,
        active_loot_slots = {},
    },
    silencer = {
        enabled = false,
    },
    visuals = {
        fullbright = false,
        remove_fog = false,
        fb_undo = {},
        fog_undo = {},
    },
    movement = {
        enabled = false,
        speed = 18,
        default_speed = 12,
    },
    perf = {
        shadows = true,
        particles = true,
        effects = true,
        terrain = true,
        fps_cap = 240,
        undo = {},
        undo_keys = {},
        disabled_particles = {},
        groups = {},
        generations = {},
        jobs = {},
        potato = false,
        flat = false,
        saved_preset = nil,
    },
    aim = {
        enabled = false,
        mode = "camera",          -- "camera" | "silent" | "look"
        fov = 90,
        fov_origin = "center",    -- "center" | "mouse"
        fov_circle = false,
        fov_circle_color = Color3.fromRGB(255, 80, 80),
        fov_circle_locked_color = Color3.fromRGB(80, 255, 140),
        fov_circle_transparency = 0.75,
        activation_picker = nil,
        smooth = 35,
        max_distance = 600,
        bone = "vital",           -- "vital" | "head" | "body" | "legs"
        gravity_comp = false,
        visible_only = false,
        wall_fallback = false,     -- jika part utama tertutup, cari part lain yang terlihat
        sticky_lock = false,       -- pertahankan target selama masih valid di dalam FOV
        silent_look_sync = false,  -- sinkronkan Remotes.Look saat silent fire
        no_recoil = false,        -- nolkan recoil climb & side di PlayerScripts.Client.Guns
        no_spread = false,        -- nolkan spread sudut tembakan (args[3] & u14)
        target_kind = "all",
        locked = nil,
        locked_model = nil,
        aim_delta_deg = 0,
        session_hits = 0,
        session_victims = {},
        last_victim = nil,
        hold_off = 0,
        last_sent = 0,
        jitter_vec = Vector3.zero,
        jitter_expires = 0,
        gun_cache = { slot = nil, def = nil, at = 0 },
        ray_exclude = {},
        ray_exclude_char = nil,
        stats = {
            acquired = 0,
            steps = 0,
            frames = 0,
            peak_deg = 0,
            fired = 0,
            args_logged = false,
            gun_arg_shape = "",
            gun_arg_count = 0,
        },
    },
}

-- ---------------------------------------------------------------------------
-- pembongkaran bersih (teardown)
-- ---------------------------------------------------------------------------

local function all_gui_containers()
    local found = {}
    local roblox_gui = CoreGui:FindFirstChild("RobloxGui")
    if not roblox_gui then return found end
    for _, child in ipairs(roblox_gui:GetChildren()) do
        if child.Name == GUI_CONTAINER_NAME and child.ClassName == "ScreenGui" then
            table.insert(found, child)
        end
    end
    return found
end

local function cancel_threads()
    for _, thread in ipairs(State.threads) do
        pcall(task.cancel, thread)
    end
    table.clear(State.threads)
end

local function disconnect_all()
    for _, connection in ipairs(State.connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(State.connections)
end

local function destroy_guis()
    for _, gui in ipairs(State.guis) do
        if gui and gui.Parent then
            pcall(function() gui:Destroy() end)
        end
    end
    table.clear(State.guis)

    for _, container in ipairs(all_gui_containers()) do
        pcall(function() container:Destroy() end)
    end
end

-- Deklarasi maju fungsi restorasi
local restore_all_perf
local restore_visuals
local restore_movement
local clear_esp
local restore_aim
local restore_prompt_holds

local function teardown()
    State.session.active = false
    pcall(restore_prompt_holds)
    State.live = false
    State.silencer.enabled = false
    State.aim.enabled = false
    if getgenv().__HushNamecallState == State then
        getgenv().__HushNamecallState = nil
    end
    local runtime = getgenv().__HushNamecallRuntime
    if runtime and runtime.state == State then runtime.state = nil end
    pcall(restore_all_perf)
    pcall(restore_visuals)
    pcall(restore_movement)
    pcall(restore_aim)
    pcall(clear_esp)
    cancel_threads()
    disconnect_all()
    destroy_guis()
    if getgenv().HushSession == State.session then
        getgenv().HushSession = nil
    end
end

State.session = { teardown = teardown, state = State, active = true }

local previous = getgenv().HushSession
if previous and type(previous.teardown) == "function" then
    pcall(previous.teardown)
end
getgenv().HushSession = State.session

-- ---------------------------------------------------------------------------
-- helper pembacaan, penulisan & UI kompatibilitas
-- ---------------------------------------------------------------------------

local function read_property(object, prop)
    local ok, value = pcall(function() return object[prop] end)
    if ok then return value end
    return nil
end

local function write_property(object, prop, value)
    pcall(function() object[prop] = value end)
end

local function record_property_once(tbl, key_map, object, prop)
    if not object then return end
    local key = tostring(object) .. "::" .. prop
    if key_map and key_map[key] then return end
    local original = read_property(object, prop)
    if original ~= nil then
        if key_map then key_map[key] = true end
        table.insert(tbl, { object = object, prop = prop, value = original })
    end
end

local function add_button_compat(groupbox, id_or_opts, maybe_opts)
    local opts = type(id_or_opts) == "table" and id_or_opts or maybe_opts
    if type(opts) == "table" then
        local fn = opts.Func or opts.Callback
        opts.Func = fn
        opts.Callback = fn
    end
    if type(id_or_opts) == "string" then
        local ok, res = pcall(function() return groupbox:AddButton(id_or_opts, opts) end)
        if ok and res then return res end
    end
    return groupbox:AddButton(opts)
end

local function get_origin_pos()
    local player = Players.LocalPlayer
    local char = player and player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if root then
        return root.Position
    end
    local cam = workspace.CurrentCamera
    if cam then
        return cam.CFrame.Position
    end
    return Vector3.zero
end

-- ---------------------------------------------------------------------------
-- modul visual & booster grafis (dedup undo & terpisah)
-- ---------------------------------------------------------------------------

local function restore_fullbright_only()
    for _, entry in ipairs(State.visuals.fb_undo) do
        write_property(entry.object, entry.prop, entry.value)
    end
    table.clear(State.visuals.fb_undo)
    State.visuals.fullbright = false
end

local function restore_fog_only()
    for _, entry in ipairs(State.visuals.fog_undo) do
        write_property(entry.object, entry.prop, entry.value)
    end
    table.clear(State.visuals.fog_undo)
    State.visuals.remove_fog = false
end

function restore_visuals()
    restore_fullbright_only()
    restore_fog_only()
end

local function apply_fullbright(enabled)
    if not enabled then
        restore_fullbright_only()
        return
    end
    if #State.visuals.fb_undo == 0 then
        local props = { "Ambient", "OutdoorAmbient", "Brightness", "ClockTime" }
        for _, p in ipairs(props) do
            record_property_once(State.visuals.fb_undo, nil, Lighting, p)
        end
    end
    State.visuals.fullbright = true
    write_property(Lighting, "Ambient", Color3.fromRGB(160, 160, 160))
    write_property(Lighting, "OutdoorAmbient", Color3.fromRGB(160, 160, 160))
    write_property(Lighting, "Brightness", 2.2)
    write_property(Lighting, "ClockTime", 14)
end

local function apply_remove_fog(enabled)
    if not enabled then
        restore_fog_only()
        return
    end
    if #State.visuals.fog_undo == 0 then
        record_property_once(State.visuals.fog_undo, nil, Lighting, "FogEnd")
        record_property_once(State.visuals.fog_undo, nil, Lighting, "FogStart")
    end
    State.visuals.remove_fog = true
    write_property(Lighting, "FogEnd", 100000)
    write_property(Lighting, "FogStart", 0)
end

-- Independent, identity-keyed snapshots; restoring never enables an originally-off effect.
local set_potato
local function perf_set(group, object, prop, value)
    local groups = State.perf.groups
    groups[group] = groups[group] or {}
    local props = groups[group][object]
    if not props then props = {}; groups[group][object] = props end
    if props[prop] == nil then
        local ok, original = pcall(function() return object[prop] end)
        if not ok then return end
        props[prop] = { value = original }
    end
    pcall(function() if object[prop] ~= value then object[prop] = value end end)
end

local function restore_perf_group(group)
    local job = State.perf.jobs[group]
    if job then pcall(task.cancel, job); State.perf.jobs[group] = nil end
    State.perf.generations[group] = (State.perf.generations[group] or 0) + 1
    for object, props in pairs(State.perf.groups[group] or {}) do
        if object.Parent then
            for prop, original in pairs(props) do
                pcall(function() object[prop] = original.value end)
            end
        end
    end
    State.perf.groups[group] = nil
end

local function perf_scan(group, root, selector, apply)
    local previous = State.perf.jobs[group]
    if previous then pcall(task.cancel, previous) end
    local gen = (State.perf.generations[group] or 0) + 1
    State.perf.generations[group] = gen
    local thread = task.spawn(function()
        local ok, objects = pcall(function() return root:QueryDescendants(selector) end)
        if not ok then warn("[hush] graphics query: " .. tostring(objects)); return end
        local slice = os.clock()
        for _, object in ipairs(objects) do
            if not State.session.active or State.perf.generations[group] ~= gen then return end
            if object.Parent then apply(object) end
            if os.clock() - slice > 0.002 then
                RunService.Heartbeat:Wait()
                slice = os.clock()
            end
        end
    end)
    State.perf.jobs[group] = thread
end

local function is_particle(object)
    return object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Smoke")
        or object:IsA("Fire") or object:IsA("Sparkles")
end

local function apply_flat(object)
    local town = workspace:FindFirstChild("Town")
    if not town then return end
    local details, wild = town:FindFirstChild("Details"), town:FindFirstChild("Wild")
    if not ((details and object:IsDescendantOf(details)) or (wild and object:IsDescendantOf(wild))) then return end
    -- Only decorative roots; protect interactive models and actors.
    local ancestor = object
    while ancestor and ancestor ~= town do
        if ancestor:FindFirstChildOfClass("Humanoid") or ancestor:FindFirstChild("SearchPrompt")
            or ancestor:GetAttribute("ContainerType") ~= nil then return end
        ancestor = ancestor.Parent
    end
    if object:IsA("BasePart") then
        perf_set("flat", object, "CastShadow", false)
        perf_set("flat", object, "Reflectance", 0)
        if object:IsA("MeshPart") then
            perf_set("flat", object, "RenderFidelity", Enum.RenderFidelity.Performance)
        end
    elseif object:IsA("Decal") or object:IsA("Texture") then
        perf_set("flat", object, "Transparency", 1)
    end
end

local function init_perf_watchers()
    if State.perf.watchers_started then return end
    State.perf.watchers_started = true
    local function added(object)
        if not State.perf.particles and is_particle(object) then perf_set("particles", object, "Enabled", false) end
        if not State.perf.effects and object:IsA("PostEffect") then perf_set("effects", object, "Enabled", false) end
        if State.perf.flat and (object:IsA("BasePart") or object:IsA("Decal") or object:IsA("Texture")) then
            apply_flat(object)
        end
    end
    table.insert(State.connections, workspace.DescendantAdded:Connect(added))
    table.insert(State.connections, Lighting.DescendantAdded:Connect(added))
    local function removed(object)
        for _, group in pairs(State.perf.groups) do
            local props = group[object]
            if props then
                for prop, original in pairs(props) do pcall(function() object[prop] = original.value end) end
                group[object] = nil
            end
        end
    end
    table.insert(State.connections, workspace.DescendantRemoving:Connect(removed))
    table.insert(State.connections, Lighting.DescendantRemoving:Connect(removed))
end

local function toggle_shadows(enabled)
    State.perf.shadows = enabled
    if enabled then restore_perf_group("shadows")
    else perf_set("shadows", Lighting, "GlobalShadows", false) end
end

local function toggle_particles(enabled)
    State.perf.particles = enabled
    if enabled then restore_perf_group("particles"); return end
    init_perf_watchers()
    perf_scan("particles", workspace, "ParticleEmitter, Trail, Smoke, Fire, Sparkles", function(object)
        perf_set("particles", object, "Enabled", false)
    end)
end

local function toggle_effects(enabled)
    State.perf.effects = enabled
    if enabled then restore_perf_group("effects"); return end
    init_perf_watchers()
    for _, object in ipairs(Lighting:GetChildren()) do
        if object:IsA("PostEffect") then perf_set("effects", object, "Enabled", false) end
    end
    local cam = workspace.CurrentCamera
    if cam then
        for _, object in ipairs(cam:GetChildren()) do
            if object:IsA("PostEffect") then perf_set("effects", object, "Enabled", false) end
        end
    end
end

local function toggle_terrain(enabled)
    State.perf.terrain = enabled
    if enabled then restore_perf_group("terrain"); return end
    local terrain = workspace:FindFirstChildOfClass("Terrain")
    if terrain then
        perf_set("terrain", terrain, "WaterWaveSize", 0)
        perf_set("terrain", terrain, "WaterWaveSpeed", 0)
        perf_set("terrain", terrain, "WaterReflectance", 0)
    end
end

local function toggle_flat(enabled)
    State.perf.flat = enabled
    if not enabled then restore_perf_group("flat"); return end
    init_perf_watchers()
    local town = workspace:FindFirstChild("Town")
    if town then
        perf_scan("flat", town, "#Details >> BasePart, #Wild >> BasePart, #Details >> Decal, #Wild >> Decal, #Details >> Texture, #Wild >> Texture", apply_flat)
    end
end

set_potato = function(enabled)
    local lib = getgenv().HushLibrary
    if enabled == State.perf.potato then return end
    local ids = { "HushShadows", "HushParticles", "HushPostEffects", "HushTerrainOpt", "HushFlatWorld" }
    if enabled then
        local saved = { toggles = {}, budget = State.esp.label_budget, detail = State.esp.detail_distance,
            outlines = {}, declutter = State.esp.declutter }
        for _, id in ipairs({ "HushMonsterOutline", "HushPlayerOutline", "HushContainerOutline", "HushLootOutline", "HushTrapOutline" }) do
            saved.outlines[id] = lib.Toggles[id].Value
        end
        for _, id in ipairs(ids) do saved.toggles[id] = lib.Toggles[id].Value end
        State.perf.saved_preset = saved
        State.perf.potato = true
        for _, id in ipairs(ids) do lib.Toggles[id]:SetValue(id ~= "HushFlatWorld") end
        lib.Options.HushESPBudget:SetValue(12)
        lib.Options.HushESPDetailDistance:SetValue(70)
        for _, id in ipairs({ "HushMonsterOutline", "HushPlayerOutline", "HushContainerOutline", "HushLootOutline", "HushTrapOutline" }) do
            lib.Toggles[id]:SetValue(false)
        end
        lib.Toggles.HushESPDeclutter:SetValue(true)
    else
        State.perf.potato = false
        local saved = State.perf.saved_preset
        if saved then
            for _, id in ipairs(ids) do lib.Toggles[id]:SetValue(saved.toggles[id]) end
            lib.Options.HushESPBudget:SetValue(saved.budget)
            lib.Options.HushESPDetailDistance:SetValue(saved.detail)
            for id, value in pairs(saved.outlines) do lib.Toggles[id]:SetValue(value) end
            lib.Toggles.HushESPDeclutter:SetValue(saved.declutter)
        end
        State.perf.saved_preset = nil
    end
end

function restore_all_perf()
    if State.perf.potato then set_potato(false) end
    State.perf.shadows, State.perf.particles, State.perf.effects, State.perf.terrain = true, true, true, true
    State.perf.flat = false
    for _, group in ipairs({ "shadows", "particles", "effects", "terrain", "flat" }) do restore_perf_group(group) end
    table.clear(State.perf.undo)
    table.clear(State.perf.undo_keys)
    table.clear(State.perf.disabled_particles)
end

local function apply_fps_cap(cap)
    State.perf.fps_cap = cap
    if type(setfpscap) == "function" then
        pcall(setfpscap, cap)
    end
end

local function measure_fps_quick(duration)
    local frames = 0
    local start_clock = os.clock()
    local conn = RunService.RenderStepped:Connect(function()
        frames = frames + 1
    end)
    task.wait(duration)
    conn:Disconnect()
    local elapsed = math.max(os.clock() - start_clock, 0.001)
    return frames / elapsed
end

-- ---------------------------------------------------------------------------
-- modul radar & esp (differential pooling — bebas churn Instance.new/Destroy)
-- ---------------------------------------------------------------------------

local function get_esp_folder()
    if State.esp.folder and State.esp.folder.Parent then
        return State.esp.folder
    end
    local folder = Instance.new("Folder")
    folder.Name = "HushESP"
    pcall(function() folder.Parent = CoreGui end)
    if not folder.Parent then
        folder.Parent = workspace
    end
    State.esp.folder = folder
    table.insert(State.guis, folder)
    return folder
end

function clear_esp()
    for _, entry in pairs(State.esp.cache_tags) do
        if entry.bbg then pcall(function() entry.bbg:Destroy() end) end
    end
    for _, entry in pairs(State.esp.cache_highlights) do
        if entry.hl then pcall(function() entry.hl:Destroy() end) end
    end
    table.clear(State.esp.cache_tags)
    table.clear(State.esp.cache_highlights)

    if State.esp.folder and State.esp.folder.Parent then
        pcall(function() State.esp.folder:Destroy() end)
    end
    State.esp.folder = nil
end

local function format_clean_name(raw)
    local clean = raw:gsub("Dropped_", ""):gsub("Find_", ""):gsub("_", " ")
    return clean:gsub("(%a)([%w']*)", function(a, b)
        return string.upper(a) .. string.lower(b)
    end)
end

-- Text stays neutral; color only marks category or danger.
local function esp_escape(text)
    return tostring(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
end

local function render_esp_billboard(key, target_part, primary_text, secondary_text, accent_color, offset_y, is_compact, seen_tags, category)
    seen_tags[key] = true
    local entry = State.esp.cache_tags[key]
    if not entry or not entry.bbg or not entry.bbg.Parent then
        local bbg = Instance.new("BillboardGui")
        bbg.Name = "Tag"
        bbg.AlwaysOnTop = true
        bbg.LightInfluence = 0
        bbg.Size = UDim2.fromOffset(192, 34)
        bbg.Enabled = false

        local mark = Instance.new("Frame")
        mark.Name = "Accent"
        mark.BorderSizePixel = 0
        mark.Position = UDim2.fromOffset(0, 2)
        mark.Size = UDim2.fromOffset(2, 10)
        mark.Parent = bbg

        local l1 = Instance.new("TextLabel")
        l1.Name = "Line1"
        l1.BackgroundTransparency = 1
        l1.Position = UDim2.fromOffset(7, 0)
        l1.Size = UDim2.new(1, -7, 0, 16)
        l1.Font = Enum.Font.GothamMedium
        l1.TextSize = 13
        l1.RichText = true
        l1.TextColor3 = Color3.fromRGB(237, 239, 241)
        l1.TextXAlignment = Enum.TextXAlignment.Left
        l1.TextTruncate = Enum.TextTruncate.AtEnd
        l1.TextStrokeColor3 = Color3.new(0, 0, 0)
        l1.TextStrokeTransparency = 0.25
        l1.Parent = bbg

        local l2 = Instance.new("TextLabel")
        l2.Name = "Line2"
        l2.BackgroundTransparency = 1
        l2.Position = UDim2.fromOffset(7, 16)
        l2.Size = UDim2.new(1, -7, 0, 14)
        l2.Font = Enum.Font.Gotham
        l2.TextSize = 10
        l2.TextColor3 = Color3.fromRGB(181, 188, 197)
        l2.TextXAlignment = Enum.TextXAlignment.Left
        l2.TextTruncate = Enum.TextTruncate.AtEnd
        l2.TextStrokeColor3 = Color3.new(0, 0, 0)
        l2.TextStrokeTransparency = 0.35
        l2.Parent = bbg

        bbg.Parent = get_esp_folder()
        entry = { bbg = bbg, mark = mark, l1 = l1, l2 = l2, visible = false }
        State.esp.cache_tags[key] = entry
    end
    entry.bbg.Adornee = target_part
    entry.bbg.StudsOffsetWorldSpace = Vector3.new(0, offset_y or 3.2, 0)
    entry.mark.BackgroundColor3 = accent_color or Color3.fromRGB(180, 190, 200)
    entry.l1.TextColor3 = category == "players" and accent_color or Color3.fromRGB(237, 239, 241)
    entry.compact = is_compact
    local now = os.clock()
    if now < (entry.next_text or 0) then return end
    local distance = (target_part.Position - get_origin_pos()).Magnitude
    entry.next_text = now + (distance > 200 and (State.perf.potato and 1 or 0.6) or 0.15)
    if entry.l1.Text ~= (primary_text or "") then entry.l1.Text = primary_text or "" end
    if entry.l2.Text ~= (secondary_text or "") then entry.l2.Text = secondary_text or "" end
end

local function set_outline(category, enabled)
    State.esp["outline_" .. category] = enabled
    if enabled then return end
    for key, entry in pairs(State.esp.cache_highlights) do
        if entry.category == category then
            if entry.hl then entry.hl:Destroy() end
            State.esp.cache_highlights[key] = nil
        end
    end
end

local function render_highlight(key, model, fill_color, outline_color, fill_trans, seen_hl, category)
    if not State.esp["outline_" .. category] then return end
    if not model:IsA("Model") and not model:IsA("BasePart") then return end
    seen_hl[key] = true
    local entry = State.esp.cache_highlights[key]
    if not entry or not entry.hl or not entry.hl.Parent then
        local hl = Instance.new("Highlight")
        hl.Name = "HushHighlight"
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = get_esp_folder()
        entry = { hl = hl, category = category }
        State.esp.cache_highlights[key] = entry
    end
    entry.hl.Adornee = model
    entry.hl.FillColor = fill_color or Color3.fromRGB(210, 150, 90)
    entry.hl.OutlineColor = outline_color or entry.hl.FillColor
    entry.hl.FillTransparency = 1
    entry.hl.OutlineTransparency = 0.25
end

local function upsert_esp_billboard(key, part, text, detail, color, offset, compact, seen, category)
    local cam = workspace.CurrentCamera
    if not cam then return end
    local screen, visible = cam:WorldToViewportPoint(part.Position + Vector3.new(0, offset or 3.2, 0))
    if not visible or screen.Z <= 0 then return end
    local args = { key, part, text, detail, color, offset, compact, seen, category }
    table.insert(State.esp.pending_tags, { args = args, distance = (part.Position - State.esp.cycle_origin).Magnitude,
        locked = key == State.aim.locked_model })
end

local function upsert_highlight(key, model, fill, outline, alpha, seen, category)
    if not State.esp["outline_" .. category] then return end
    local part = model:IsA("BasePart") and model or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
    if not part then return end
    table.insert(State.esp.pending_outlines, { args = { key, model, fill, outline, alpha, seen, category },
        distance = (part.Position - State.esp.cycle_origin).Magnitude, locked = key == State.aim.locked_model })
end

local function flush_esp_requests()
    local function nearer(a, b)
        if a.locked ~= b.locked then return a.locked end
        return a.distance < b.distance
    end
    table.sort(State.esp.pending_tags, nearer)
    table.sort(State.esp.pending_outlines, nearer)
    local slice = os.clock()
    for i, request in ipairs(State.esp.pending_tags) do
        if i > (State.perf.potato and 20 or State.esp.render_limit) then break end
        render_esp_billboard(table.unpack(request.args, 1, 9))
        if os.clock() - slice > 0.0015 then RunService.Heartbeat:Wait(); slice = os.clock() end
    end
    for i, request in ipairs(State.esp.pending_outlines) do
        if i > (State.perf.potato and 12 or State.esp.outline_limit) then break end
        render_highlight(table.unpack(request.args, 1, 7))
        if os.clock() - slice > 0.0015 then RunService.Heartbeat:Wait(); slice = os.clock() end
    end
    table.clear(State.esp.pending_tags)
    table.clear(State.esp.pending_outlines)
end

-- Layout runs on the ESP tick, never every render frame.
local function layout_esp_labels(origin)
    local cam = workspace.CurrentCamera
    if not cam then
        for _, entry in pairs(State.esp.cache_tags) do entry.bbg.Enabled = false end
        return
    end
    local viewport = cam.ViewportSize
    local candidates = {}
    for key, entry in pairs(State.esp.cache_tags) do
        entry.bbg.Enabled = false
        local part = entry.bbg.Adornee
        if part and part.Parent then
            local distance = (part.Position - origin).Magnitude
            local screen, on_screen = cam:WorldToViewportPoint(part.Position + entry.bbg.StudsOffsetWorldSpace)
            local parent_name = key.Parent and key.Parent.Name or ""
            local threat = parent_name == "Monsters" or parent_name == "Watchers"
            local player = not threat and key:IsA("Model") and Players:GetPlayerFromCharacter(key) ~= nil
            local locked = State.aim.locked_model == key
            local urgent = threat and distance < 120 and (
                tostring(key:GetAttribute("State")):upper() == "CHASE"
                or tostring(key:GetAttribute("State")):upper() == "LISTEN"
            )
            entry.l2.Visible = not entry.compact and (locked or distance <= State.esp.detail_distance)
                and entry.l2.Text ~= ""
            local height = entry.l2.Visible and 32 or 17
            local plain = entry.l1.Text:gsub("<[^>]+>", ""):gsub("%d+ st", "0000 st")
            if entry.measure_key ~= plain then
                entry.measure_key = plain
                entry.width = math.clamp(game:GetService("TextService"):GetTextSize(
                    plain, 13, Enum.Font.GothamMedium, Vector2.new(1000, 20)
                ).X + 12, 64, 192)
            end
            local width = entry.width
            entry.bbg.Size = UDim2.fromOffset(width, height)
            entry.l1.TextTransparency = distance > 600 and 0.18 or 0
            entry.l2.TextTransparency = 0.08
            local cx, cy = viewport.X * 0.5, viewport.Y * 0.5
            local quiet = State.esp.declutter and not locked and not urgent
                and math.abs(screen.X - cx) < 85 and math.abs(screen.Y - cy) < 55
            local x, y = screen.X - width * 0.5, screen.Y - height * 0.5
            if on_screen and screen.Z > 0 and not quiet and x >= 8 and y >= 52
                and x + width <= viewport.X - 8 and y + height <= viewport.Y - 32 then
                table.insert(candidates, {
                    entry = entry, x = x, y = y, w = width, h = height, distance = distance,
                    rank = locked and 0 or urgent and 1 or threat and 2 or player and 3 or 4,
                    id = key:GetFullName(),
                })
            end
            local hl = State.esp.cache_highlights[key]
            if hl then
                hl.hl.FillTransparency = 1
                hl.hl.OutlineTransparency = locked and 0.18 or urgent and 0.28
                    or math.clamp(0.25 + distance / 5000, 0.25, 0.65)
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        -- Small distance buckets keep near-equal targets from swapping every tick.
        local da, db = math.floor(a.distance / 25), math.floor(b.distance / 25)
        if da ~= db then return da < db end
        if a.entry.visible ~= b.entry.visible then return a.entry.visible end
        return a.id < b.id
    end)
    local placed = {}
    for _, candidate in ipairs(candidates) do
        local show = not State.esp.declutter or #placed < State.esp.label_budget
        if show and State.esp.declutter then
            for _, other in ipairs(placed) do
                if candidate.x < other.x + other.w + 8 and candidate.x + candidate.w + 8 > other.x
                    and candidate.y < other.y + other.h + 5 and candidate.y + candidate.h + 5 > other.y then
                    show = false
                    break
                end
            end
        end
        candidate.entry.bbg.Enabled = show
        if show then table.insert(placed, candidate) end
    end
    for _, entry in pairs(State.esp.cache_tags) do entry.visible = entry.bbg.Enabled end
    State.esp.visible_labels = #placed
    State.esp.screen_candidates = #candidates
end

local HIGH_TIER_KEYWORDS = {
    "flare", "rocket", "heavy_ammo", "medium_ammo", "defib", "double_barrel",
    "gun_parts", "mag_extended", "bag", "chest", "sniper", "rifle", "silencer", "grip"
}

local CONTAINER_TIERS = {
    -- High-Tier Military / Bunker / Special
    WeaponCrate    = { tier = "high", label = "Weapon Crate",    color = Color3.fromRGB(255, 200, 65) },
    SupplyCrate    = { tier = "high", label = "Supply Crate",    color = Color3.fromRGB(255, 200, 65) },
    AmmoCrate      = { tier = "high", label = "Ammo Crate",      color = Color3.fromRGB(245, 185, 55) },
    TruckAmmo      = { tier = "high", label = "Truck Ammo",      color = Color3.fromRGB(245, 185, 55) },
    BunkerArmory   = { tier = "high", label = "Bunker Armory",   color = Color3.fromRGB(255, 115, 70) },
    BunkerMedical  = { tier = "high", label = "Bunker Medical",  color = Color3.fromRGB(255, 115, 70) },
    Lockbox        = { tier = "high", label = "Lockbox",         color = Color3.fromRGB(255, 210, 75) },
    Briefcase      = { tier = "high", label = "Briefcase",       color = Color3.fromRGB(255, 210, 75) },
    -- Med / Tech / Vehicle Tier
    MedicalCabinet = { tier = "med",  label = "Med Cabinet",     color = Color3.fromRGB(175, 135, 255) },
    MedicalShelf   = { tier = "med",  label = "Med Shelf",       color = Color3.fromRGB(175, 135, 255) },
    CarTrunk       = { tier = "med",  label = "Car Trunk",       color = Color3.fromRGB(95, 205, 245) },
    Toolbox        = { tier = "med",  label = "Toolbox",         color = Color3.fromRGB(95, 205, 245) },
    HardwareShelf  = { tier = "med",  label = "Hardware Shelf",  color = Color3.fromRGB(95, 205, 245) },
    Locker         = { tier = "med",  label = "Locker",          color = Color3.fromRGB(130, 185, 230) },
    Register       = { tier = "med",  label = "Cash Register",   color = Color3.fromRGB(120, 225, 160) },
}

local function classify_container(ctype, fallback_obj)
    local info = ctype and CONTAINER_TIERS[ctype]
    if info then
        return info.tier, info.label, info.color
    end
    local lbl = (fallback_obj and fallback_obj ~= "") and fallback_obj or (ctype and format_clean_name(ctype)) or "Container"
    return "common", lbl, Color3.fromRGB(145, 155, 170)
end

local function classify_loot(name)
    local lower = string.lower(name)
    for _, kw in ipairs(HIGH_TIER_KEYWORDS) do
        if string.find(lower, kw, 1, true) then
            return "high", Color3.fromRGB(245, 198, 66) -- Amber Gold
        end
    end
    if string.find(lower, "med", 1, true) or string.find(lower, "bottle", 1, true) or string.find(lower, "chemicals", 1, true) then
        return "med", Color3.fromRGB(168, 130, 255) -- Soft Violet
    end
    return "common", Color3.fromRGB(150, 162, 178) -- Tactical Slate
end

local function rebuild_container_summary(part, slots)
    if not part then return end
    local names = {}
    local has_hidden = false
    for _, s in pairs(slots or {}) do
        if type(s) == "table" then
            if s.hidden then
                has_hidden = true
            elseif s.id and s.id ~= "" and (tonumber(s.qty) or 1) > 0 then
                local q = tonumber(s.qty) or 1
                local clean = format_clean_name(tostring(s.id))
                table.insert(names, q > 1 and (clean .. " x" .. tostring(q)) or clean)
            end
        end
    end
    if #names > 0 then
        State.esp.container_items[part] = table.concat(names, " · ")
        State.esp.container_empty[part] = nil
    elseif not has_hidden then
        State.esp.container_items[part] = nil
        State.esp.container_empty[part] = true
    end
end

local function init_loot_sniffer()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local loot_remote = remotes and remotes:FindFirstChild("Loot")
    if not loot_remote or not loot_remote:IsA("RemoteEvent") then return end

    local conn = loot_remote.OnClientEvent:Connect(function(action, a, b)
        if action == "open" and type(a) == "table" then
            local part = a.part
            State.esp.active_loot_part = part
            State.esp.active_loot_slots = type(a.slots) == "table" and a.slots or {}
            rebuild_container_summary(part, State.esp.active_loot_slots)

            if State.esp.auto_take_loot and part then
                task.defer(function()
                    pcall(function() loot_remote:FireServer("takeAll", part) end)
                end)
            end
        elseif action == "reveal" then
            local idx = tonumber(a)
            local item = b
            local part = State.esp.active_loot_part
            if idx and type(item) == "table" and State.esp.active_loot_slots then
                State.esp.active_loot_slots[idx] = item
                rebuild_container_summary(part, State.esp.active_loot_slots)
            end
            if State.esp.auto_take_loot and part and type(item) == "table" and item.id and item.id ~= "" then
                task.defer(function()
                    pcall(function() loot_remote:FireServer("takeAll", part) end)
                end)
            end
        elseif action == "close" then
            State.esp.active_loot_part = nil
            State.esp.active_loot_slots = {}
        end
    end)
    table.insert(State.connections, conn)
end

restore_prompt_holds = function()
    for prompt, original in pairs(State.esp.prompt_holds) do
        if prompt.Parent then pcall(function() prompt.HoldDuration = original end) end
    end
    table.clear(State.esp.prompt_holds)
end

local function apply_prompt_hold(prompt)
    if State.esp.instant_prompt and State.esp.prompt_holds[prompt] == nil then
        State.esp.prompt_holds[prompt] = prompt.HoldDuration
        prompt.HoldDuration = 0
    end
end

-- One indexed query, then events; nearby selection is spread across frames.
local function refresh_search_prompts_cache()
    local e = State.esp
    if e.prompt_cache_started then return e.nearby_prompts end
    e.prompt_cache_started = true
    local function add(prompt)
        if not prompt:IsA("ProximityPrompt") or prompt.Name ~= "SearchPrompt" or e.prompt_index[prompt] then return end
        table.insert(e.cached_prompts, prompt)
        e.prompt_index[prompt] = #e.cached_prompts
        apply_prompt_hold(prompt)
        local container = prompt.Parent
        local part = container and (container:IsA("BasePart") and container
            or (container:IsA("Model") and (container.PrimaryPart or container:FindFirstChildWhichIsA("BasePart", true))))
        e.prompt_meta[prompt] = { part = part, container = container }
    end
    local function remove(prompt)
        local index = e.prompt_index[prompt]
        if not index then return end
        local last = table.remove(e.cached_prompts)
        if last ~= prompt then e.cached_prompts[index] = last; e.prompt_index[last] = index end
        e.prompt_index[prompt], e.prompt_meta[prompt] = nil, nil
        local hold = e.prompt_holds[prompt]
        if hold ~= nil then pcall(function() prompt.HoldDuration = hold end); e.prompt_holds[prompt] = nil end
    end
    table.insert(State.connections, workspace.DescendantAdded:Connect(function(object)
        if object:IsA("ProximityPrompt") then task.defer(function() if object:IsDescendantOf(workspace) then add(object) end end) end
    end))
    table.insert(State.connections, workspace.DescendantRemoving:Connect(remove))
    local thread = task.spawn(function()
        local initial = workspace:QueryDescendants("ProximityPrompt#SearchPrompt")
        for i, prompt in ipairs(initial) do
            if not State.session.active then return end
            if prompt:IsDescendantOf(workspace) then add(prompt) end
            if i % 64 == 0 then RunService.Heartbeat:Wait() end
        end
        e.index_ready = true
        while State.session.active do
            if not e.containers then
                e.nearby_prompts = {}
                task.wait(0.5)
                continue
            end
            local origin, near = get_origin_pos(), {}
            local list = table.clone(e.cached_prompts)
            local radius = e.max_container_dist + 80
            for i, prompt in ipairs(list) do
                if not State.session.active then return end
                local meta = e.prompt_meta[prompt]
                if meta and prompt.Parent then
                    if not meta.part or not meta.part.Parent then
                        local container = prompt.Parent
                        meta.container = container
                        meta.part = container:IsA("BasePart") and container
                            or (container:IsA("Model") and (container.PrimaryPart or container:FindFirstChildWhichIsA("BasePart", true)))
                    end
                    if meta.part and (meta.part.Position - origin).Magnitude <= radius then table.insert(near, prompt) end
                end
                if i % 64 == 0 then RunService.Heartbeat:Wait() end
            end
            e.nearby_prompts = near
            e.last_prompt_scan = os.clock()
            task.wait(0.3)
        end
    end)
    table.insert(State.threads, thread)
    return e.nearby_prompts
end

local function set_instant_prompt(enabled)
    State.esp.instant_prompt = enabled
    if not enabled then restore_prompt_holds(); return end
    refresh_search_prompts_cache()
    for _, prompt in ipairs(State.esp.cached_prompts) do if prompt.Parent then apply_prompt_hold(prompt) end end
end

-- Separate from aim visibility: camera line-of-sight, cached and ray-budgeted.
local player_los_params = RaycastParams.new()
player_los_params.FilterType = Enum.RaycastFilterType.Exclude
player_los_params.IgnoreWater = true
local function player_is_visible(character, root)
    local cam = workspace.CurrentCamera
    if not cam then return false end
    local cache = State.esp.player_los_cache
    local now = os.clock()
    local old = cache[character]
    if old and now - old.at < 0.4 then return old.visible end
    if (State.esp.player_los_rays or 0) <= 0 then
        return old ~= nil and now - old.at < 2 and old.visible or false
    end
    local excluded = { cam }
    local lp = Players.LocalPlayer
    if lp and lp.Character then table.insert(excluded, lp.Character) end
    if State.esp.folder then table.insert(excluded, State.esp.folder) end
    player_los_params.FilterDescendantsInstances = excluded
    local origin = cam.CFrame.Position
    local head = character:FindFirstChild("Head")
    local visible = false
    for _, target in ipairs(head and { head, root } or { root }) do
        if State.esp.player_los_rays <= 0 then break end
        State.esp.player_los_rays -= 1
        local hit = workspace:Raycast(origin, target.Position - origin, player_los_params)
        if not hit or hit.Instance:IsDescendantOf(character) then visible = true; break end
    end
    cache[character] = { at = now, visible = visible }
    return visible
end

local function run_esp_cycle()
    if not State.esp.enabled or not (State.esp.monsters or State.esp.players or State.esp.loot
        or State.esp.containers or State.esp.traps) then
        if next(State.esp.cache_tags) or next(State.esp.cache_highlights) then clear_esp() end
        return
    end

    State.esp.player_los_rays = 8
    local my_pos = get_origin_pos()
    State.esp.cycle_origin = my_pos
    State.esp.pending_tags, State.esp.pending_outlines = {}, {}
    local slice = os.clock()
    local function esp_yield()
        if os.clock() - slice > 0.0015 then RunService.Heartbeat:Wait(); slice = os.clock() end
    end
    local seen_tags = {}
    local seen_hl = {}

    -- Monsters
    if State.esp.monsters then
        local mf = workspace:FindFirstChild("Monsters")
        local wf = workspace:FindFirstChild("Watchers")

        local function process_monster(monster, default_kind)
            local ppart = monster.PrimaryPart or monster:FindFirstChildWhichIsA("BasePart", true)
            if not ppart then return end
            local dist = (ppart.Position - my_pos).Magnitude
            if dist > State.esp.max_monster_dist then return end

            local kind = tostring(monster:GetAttribute("Kind") or default_kind):upper()
            local state = tostring(monster:GetAttribute("State") or "IDLE"):upper()
            local heard_db = monster:GetAttribute("HeardDb")

            local color = Color3.fromRGB(240, 165, 55)
            local fill_trans = 0.86
            local sub_str = format_clean_name(state)

            if State.aim.locked_model == monster then
                color = Color3.fromRGB(75, 245, 150)
                fill_trans = 0.72
                sub_str = "Locked · " .. format_clean_name(state)
            elseif (type(heard_db) == "number" and heard_db > 0) or state == "CHASE" or state == "LISTEN" then
                color = Color3.fromRGB(255, 68, 68)
                fill_trans = 0.76
                local db_str = type(heard_db) == "number" and string.format("%.0fdB", heard_db) or "ALERT"
                sub_str = format_clean_name(state) .. " · " .. db_str
            elseif state == "SLEEP" or state == "BURIED" then
                color = Color3.fromRGB(95, 175, 225)
                fill_trans = 0.90
            end

            upsert_highlight(monster, monster, color, color, fill_trans, seen_hl, "monsters")
            upsert_esp_billboard(
                monster,
                ppart,
                string.format("%s  <font color='#a8afb9'>%.0f st</font>", esp_escape(format_clean_name(kind)), dist),
                sub_str,
                color,
                4.2,
                false,
                seen_tags
            )
        end

        if mf then
            for _, m in ipairs(mf:GetChildren()) do
            esp_yield()
                process_monster(m, "Monster")
            end
        end
        if wf then
            for _, w in ipairs(wf:GetChildren()) do
            esp_yield()
                process_monster(w, "Watcher")
            end
        end
    end

    -- Loot
    if State.esp.loot then
        local loot_containers = {
            { folder = workspace:FindFirstChild("WorldFinds"), is_bag = false },
            { folder = workspace:FindFirstChild("LootBags"), is_bag = true },
            { folder = workspace:FindFirstChild("Bodies"), is_body = true },
            { folder = workspace:FindFirstChild("SupplyDrops"), is_drop = true },
        }

        for _, group in ipairs(loot_containers) do
            if group.folder then
                for _, item in ipairs(group.folder:GetChildren()) do
            esp_yield()
                    local ppart = item:IsA("BasePart") and item or item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart", true)
                    if ppart then
                        local dist = (ppart.Position - my_pos).Magnitude
                        if dist <= State.esp.max_loot_dist then
                            local clean_name = format_clean_name(item.Name)
                            local category, color = classify_loot(item.Name)

                            if group.is_bag then
                                clean_name = "Bag · " .. clean_name
                                color = Color3.fromRGB(225, 130, 255)
                            elseif group.is_body then
                                clean_name = "Corpse"
                                color = Color3.fromRGB(235, 145, 75)
                            elseif group.is_drop then
                                clean_name = "SUPPLY DROP"
                                color = Color3.fromRGB(255, 210, 60)
                            end

                             if not State.esp.loot_high_tier_only or category == "high" or group.is_bag or group.is_body or group.is_drop then
                                upsert_highlight(item, item:IsA("Model") and item or ppart, color, color, 1, seen_hl, "loot")
                                upsert_esp_billboard(
                                    item,
                                    ppart,
                                    string.format("%s <font color='#a8afb9'>%.0f st</font>", esp_escape(clean_name), dist),
                                    nil,
                                    color,
                                    1.8,
                                    true,
                                    seen_tags
                                )
                            end
                        end
                    end
                end
            end
        end
    end

    -- Containers
    if State.esp.containers then
        local prompts = refresh_search_prompts_cache()
        for _, prompt in ipairs(prompts) do
            esp_yield()
            if prompt and prompt.Parent and prompt.Enabled then
                local container = prompt.Parent
                if not State.esp.container_empty[container] then
                    local meta = State.esp.prompt_meta[prompt]
                    local ppart = meta and meta.part
                    if ppart then
                        local dist = (ppart.Position - my_pos).Magnitude
                        if dist <= State.esp.max_container_dist then
                            local ctype = container:GetAttribute("ContainerType")
                            local tier, label, color = classify_container(ctype, prompt.ObjectText)
                            local known_items = State.esp.container_items[container]

                            if not State.esp.containers_high_only or tier == "high" or tier == "med" or known_items ~= nil then
                                local outline_color = known_items and Color3.fromRGB(80, 245, 155) or color
                                upsert_highlight(container, container, outline_color, outline_color, 1, seen_hl, "containers")
                                if known_items then
                                    upsert_esp_billboard(
                                        container,
                                        ppart,
                                        string.format("%s  <font color='#a8afb9'>%.0f st</font>", esp_escape(label), dist),
                                        known_items,
                                        Color3.fromRGB(80, 245, 155),
                                        1.6,
                                        false,
                                        seen_tags
                                    )
                                else
                                    upsert_esp_billboard(
                                        container,
                                        ppart,
                                        string.format("%s <font color='#a8afb9'>%.0f st</font>", esp_escape(label), dist),
                                        nil,
                                        color,
                                        1.4,
                                        true,
                                        seen_tags
                                    )
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Traps
    if State.esp.traps then
        local tf = workspace:FindFirstChild("NoiseTraps")
        if tf then
            for _, trap in ipairs(tf:GetChildren()) do
            esp_yield()
                if trap:IsA("BasePart") then
                    local dist = (trap.Position - my_pos).Magnitude
                    if dist <= State.esp.max_trap_dist then
                        local color = Color3.fromRGB(245, 95, 95)
                        upsert_highlight(trap, trap, color, color, 1, seen_hl, "traps")
                        upsert_esp_billboard(
                            trap,
                            trap,
                            string.format("%s <font color='#a8afb9'>%.0f st</font>", esp_escape(format_clean_name(trap.Name)), dist),
                            nil,
                            Color3.fromRGB(245, 95, 95),
                            1.0,
                            true,
                            seen_tags
                        )
                    end
                end
            end
        end
    end

    -- Players
    if State.esp.players then
        local local_player = Players.LocalPlayer
        local players = Players:GetPlayers()
        local cursor = State.esp.player_los_cursor
        for i = 1, #players do
            local p = players[(cursor + i - 2) % #players + 1]
            esp_yield()
            if p ~= local_player and p.Character then
                local ochar = p.Character
                local oroot = ochar:FindFirstChild("HumanoidRootPart")
                local ohum = ochar:FindFirstChildOfClass("Humanoid")
                if oroot then
                    local dist = (oroot.Position - my_pos).Magnitude
                    if dist <= State.esp.max_player_dist then
                        local hp_num = ohum and ohum.Health or 100
                        local visible = player_is_visible(ochar, oroot)
                        local p_color = visible and Color3.fromRGB(85, 225, 145) or Color3.fromRGB(255, 205, 65)
                        upsert_highlight(ochar, ochar, p_color, p_color, 1, seen_hl, "players")
                        upsert_esp_billboard(
                            ochar,
                            oroot,
                            string.format("%s  <font color='#a8afb9'>%.0f st</font>", esp_escape(p.DisplayName), dist),
                            string.format("%.0f HP · %s", hp_num, visible and "Visible" or "Occluded / unchecked"),
                            p_color,
                            3.6,
                            false,
                            seen_tags, "players"
                        )
                    end
                end
            end
        end
        State.esp.player_los_cursor = cursor + 4
    end

    flush_esp_requests()

    -- Release entries that left range or were removed.
    for key, entry in pairs(State.esp.cache_tags) do
        if not seen_tags[key] then
            if entry.bbg then pcall(function() entry.bbg:Destroy() end) end
            State.esp.cache_tags[key] = nil
        end
    end
    for key, entry in pairs(State.esp.cache_highlights) do
        if not seen_hl[key] then
            if entry.hl then pcall(function() entry.hl:Destroy() end) end
            State.esp.cache_highlights[key] = nil
        end
    end
    layout_esp_labels(my_pos)
end

-- ---------------------------------------------------------------------------
-- modul aimbot (Quaternion/Axis-Angle, Sticky Lock, Multi-Point Vis, Anti-Flag)
-- ---------------------------------------------------------------------------
-- Angka pengaman Config.CheatFlags:
--   SnapDeg=25, SnapWindow={0.1,0.45}  -> lompatan >25 deg dalam jendela itu = bukti snap.
--   PreciseErr=0.25, LrPrecise=1.15    -> error bidik < 0.25 stud konsisten = bukti aimbot.
--   MinHits=12, MinVictims=2           -> evaluasi aktif setelah 12 hit ke >=2 korban.

local AIM_SNAP_GUARD_DEG = 8.0
local AIM_MIN_STEP_DEG = 0.28
local AIM_JITTER_DEG = 0.12
local AIM_MAX_GAIN_DEG = 3.0
local AIM_HOLD_OFF_SECONDS = 1.4
local AIM_SPATIAL_JITTER_STUDS = 0.30 -- > PreciseErr (0.25) agar LrPrecise tidak naik

local AIM_BONES = {
    head = {
        "Head", "Pupil", "Core", "Iris", "Ball",
        "JawPlateF", "JawPlateT", "JawPlateL", "JawPlateB", "Gum", "Throat", "EarDrum",
    },
    body = {
        "Chest", "Ribs", "Belly", "Neck", "Core", "Ball",
        "UpperTorso", "LowerTorso", "Torso", "HumanoidRootPart",
        "UpperArmR", "UpperArmL", "UpperArmB", "UpperBL", "UpperFL",
    },
    legs = {
        "ThighFR", "ThighFL", "ThighBR", "ThighBL",
        "ShinFR", "ShinFL", "ShinBR", "ShinBL",
        "LowerFR", "LowerFL", "LowerBR", "LowerBL",
        "LeftUpperLeg", "RightUpperLeg",
    },
    vital = {
        "Head", "Pupil", "Core", "Iris", "Chest", "Neck", "Throat",
        "JawPlateF", "Ribs", "EarDrum", "Ball", "UpperTorso", "Torso", "HumanoidRootPart",
    },
}

local AIM_BONE_NOISE = {
    Tooth = true, Talons = true, TailClaw = true,
    Tail1 = true, Tail2 = true, Tail3 = true, Tail4 = true, Tail5 = true, Tail6 = true, Tail7 = true,
    TailSkin1 = true, TailSkin2 = true, TailSkin3 = true,
    JawFlapB = true, JawFlapL = true, WitheredArm = true, Glint = true, Nerve = true,
}

local aim_conn = nil
local fov_circle = nil

-- ---------------------------------------------------------------------------
-- ballistik nyata & cache definisi senjata
-- ---------------------------------------------------------------------------

local AIM_GRAVITY_FALLBACK = 110
local AIM_VELOCITY_FALLBACK = 1000

-- Di HUSH, peluru spawn dari Character.Head.Position (arg[5] pada Remotes.Gun),
-- bukan dari Camera.CFrame.Position (yang punya offset bahu ~10.3 stud).
local function get_muzzle_origin()
    local player = Players.LocalPlayer
    local char = player and player.Character
    local head = char and char:FindFirstChild("Head")
    if head and head:IsA("BasePart") then
        return head.Position
    end
    local cam = workspace.CurrentCamera
    return cam and cam.CFrame.Position or Vector3.zero
end

local function aim_gun_def()
    local player = Players.LocalPlayer
    if not player then return nil end

    -- 1. Prioritaskan heldId() langsung dari modul Client.Guns agar saat ganti
    -- antara senjata utama (SlotMain) dan pistol (SlotSide) kecepatan peluru selalu akurat
    local slot = nil
    pcall(function()
        local ps = player:FindFirstChild("PlayerScripts")
        local cl = ps and ps:FindFirstChild("Client")
        local gmod = cl and cl:FindFirstChild("Guns")
        if gmod then
            local cg = require(gmod)
            if type(cg) == "table" and type(cg.heldId) == "function" then
                local hid = cg.heldId()
                if type(hid) == "string" and hid ~= "" then
                    slot = hid
                end
            end
        end
    end)

    -- 2. Fallback ke atribut Character / Player jika sedang tidak memegang senjata di tangan
    if not slot then
        local char = player.Character
        local candidates = {
            char and char:GetAttribute("Equipped"),
            char and char:GetAttribute("Holding"),
            char and char:GetAttribute("SlotMain"),
            char and char:GetAttribute("SlotSide"),
            player:GetAttribute("SlotMain"),
        }
        for _, name in ipairs(candidates) do
            if type(name) == "string" and name ~= "" then
                slot = name
                break
            end
        end
    end
    if not slot then return nil end

    local now = os.clock()
    local cache = State.aim.gun_cache
    if cache.slot == slot and cache.def and (now - cache.at) < 1.0 then
        return cache.def, slot
    end

    local guns_root = ReplicatedStorage:FindFirstChild("Shared")
    local gun_module = guns_root and guns_root:FindFirstChild("Guns")
    if not gun_module then return nil end

    local ok, def = pcall(function()
        local guns = require(gun_module)
        if type(guns.get) == "function" then
            return guns.get(slot)
        end
        return guns.Defs and guns.Defs[slot] or nil
    end)
    if not ok or type(def) ~= "table" then return nil end

    cache.slot = slot
    cache.def = def
    cache.at = now
    return def, slot
end

local function aim_ballistics()
    local def, slot = aim_gun_def()
    local velocity = AIM_VELOCITY_FALLBACK
    local gravity = AIM_GRAVITY_FALLBACK
    local range = 500
    local pen = 1
    local pellets = 1

    if def then
        velocity = tonumber(def.velocity) or velocity
        gravity = tonumber(def.drop) or gravity
        range = tonumber(def.range) or range
        pen = tonumber(def.pen) or pen
        pellets = tonumber(def.pellets) or pellets
    end
    return {
        slot = slot or "default",
        velocity = math.max(velocity, 100),
        gravity = gravity,
        range = range,
        pen = pen,
        pellets = pellets,
    }
end

-- Offset spasial 3D yang berubah halus tiap 0.25s agar error bidik > PreciseErr (0.25 stud)
local function get_spatial_jitter()
    local now = os.clock()
    if now >= State.aim.jitter_expires then
        State.aim.jitter_expires = now + 0.25
        local angle = math.random() * math.pi * 2
        local mag = AIM_SPATIAL_JITTER_STUDS * (0.85 + math.random() * 0.35)
        State.aim.jitter_vec = Vector3.new(
            math.cos(angle) * mag,
            (math.random() - 0.5) * mag * 0.6,
            math.sin(angle) * mag
        )
    end
    return State.aim.jitter_vec
end

-- Solver balistik 4-iterasi eksak sesuai Shared.Ballistics.arcAt(p0, v0, drop, t):
-- P(t) = origin + (predicted - origin).Unit * speed * t - Vector3(0, 0.5 * g * t^2, 0)
-- Dengan memasukkan drop ke dalam iterasi jarak tempuh busur, (predicted - origin).Magnitude == speed * t,
-- sehingga saat peluru sampai di t, posisi peluru tepat 100% di titik target.
local function aim_solve_point(origin, target_pos, target_vel, ballistics, include_jitter)
    local speed = ballistics.velocity
    local gravity = State.aim.gravity_comp and ballistics.gravity or 0
    local t_vel = target_vel or Vector3.zero

    local flight = (target_pos - origin).Magnitude / math.max(speed, 100)
    local predicted = target_pos

    for _ = 1, 4 do
        local drop = (gravity > 0) and (0.5 * gravity * flight * flight) or 0
        predicted = target_pos + (t_vel * flight) + Vector3.new(0, drop, 0)
        flight = (predicted - origin).Magnitude / math.max(speed, 100)
    end

    if include_jitter then
        predicted = predicted + get_spatial_jitter()
    end

    return predicted, flight
end

-- Raycast visibilitas sesuai CollisionGroup = "Bullets" milik Shared.Ballistics
local aim_ray_params = RaycastParams.new()
aim_ray_params.FilterType = Enum.RaycastFilterType.Exclude
aim_ray_params.IgnoreWater = true
aim_ray_params.RespectCanCollide = false
pcall(function() aim_ray_params.CollisionGroup = "Bullets" end)

local function aim_visible(origin, target_part, target_model)
    if not target_part then return false end
    local char = Players.LocalPlayer and Players.LocalPlayer.Character
    local exclude = {}
    if char then exclude[#exclude + 1] = char end
    if State.esp.folder then exclude[#exclude + 1] = State.esp.folder end

    local root_model = target_model or target_part.Parent
    local cur_origin = origin
    local goal_pos = target_part.Position

    -- Bound expensive ray work across the entire discovery pass.
    -- Tembus hingga 6 lapis kaca atau part transparan (>=0.9) sesuai Shared.Ballistics.walk
    for _ = 1, 6 do
        if (State.aim.rays_left or 16) <= 0 then return false end
        State.aim.rays_left = (State.aim.rays_left or 16) - 1
        aim_ray_params.FilterDescendantsInstances = exclude
        local dir = goal_pos - cur_origin
        if dir.Magnitude < 0.3 then return true end
        local hit = workspace:Raycast(cur_origin, dir, aim_ray_params)
        if not hit then return true end
        local inst = hit.Instance
        if inst == target_part or (root_model and inst:IsDescendantOf(root_model)) then
            return true
        end
        if inst:IsA("BasePart") and ((inst.Transparency >= 0.9 and inst:GetAttribute("Hitbox") ~= true) or hit.Material == Enum.Material.Glass) then
            exclude[#exclude + 1] = inst
            cur_origin = hit.Position
        else
            return false
        end
    end
    return false
end

local function is_model_alive(model)
    if not model or not model.Parent then return false end
    local state = model:GetAttribute("State")
    if state == "Dead" or state == "Corpse" or state == "Killed" then
        return false
    end
    local hp_attr = model:GetAttribute("Health") or model:GetAttribute("HP")
    if type(hp_attr) == "number" and hp_attr <= 0 then
        return false
    end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health <= 0 then
        return false
    end
    return true
end

-- Cache body-part lookup for camera targeting.
local aim_rig_cache = setmetatable({}, { __mode = "k" })
local aim_cache_events_started = false
local function aim_rig(model)
    local now = os.clock()
    local rig = aim_rig_cache[model]
    if rig and now < rig.expires and (not rig.root or rig.root.Parent) then return rig end
    if not aim_cache_events_started then
        aim_cache_events_started = true
        local function changed(object)
            if object:IsA("Model") then aim_rig_cache[object] = nil; return end
            local parent = object.Parent
            if parent and aim_rig_cache[parent] and object:IsA("BasePart") then aim_rig_cache[parent] = nil end
        end
        table.insert(State.connections, workspace.DescendantAdded:Connect(changed))
        table.insert(State.connections, workspace.DescendantRemoving:Connect(changed))
    end
    local named, direct = {}, {}
    for _, part in ipairs(model:GetChildren()) do
        if part:IsA("BasePart") and not AIM_BONE_NOISE[part.Name] then
            table.insert(direct, part)
            local name = part.Name
            named[name] = named[name] or {}
            table.insert(named[name], part)
        end
    end
    local root = model.PrimaryPart or named.HumanoidRootPart and named.HumanoidRootPart[1] or direct[1]
    rig = { named = named, direct = direct, root = root, expires = now + 30 }
    aim_rig_cache[model] = rig
    return rig
end

local function aim_pick_vital(model, origin, require_vis)
    local order = AIM_BONES[State.aim.bone] or AIM_BONES.vital
    local rig = aim_rig(model)
    local best_any, best_score, best_vis, vis_score = nil, math.huge, nil, math.huge
    for rank, name in ipairs(order) do
        for _, part in ipairs(rig.named[name] or {}) do
            if part.Parent then
                local score = (part.Position - origin).Magnitude + rank * 1.5
                if score < best_score then best_any, best_score = part, score end
                if require_vis and score < vis_score and aim_visible(origin, part, model) then
                    best_vis, vis_score = part, score
                end
            end
        end
    end
    if best_vis then return best_vis, true end
    if require_vis and State.aim.wall_fallback then
        for _, part in ipairs(rig.direct) do
            if (State.aim.rays_left or 16) <= 0 then break end
            if part.Parent then
                local score = (part.Position - origin).Magnitude
                if score < vis_score and aim_visible(origin, part, model) then best_vis, vis_score = part, score end
            end
        end
        if best_vis then return best_vis, true end
    end
    if best_any then return best_any, false end
    if not rig.descendants then
        rig.descendants = model:QueryDescendants("BasePart")
    end
    for _, part in ipairs(rig.descendants) do
        if part.Parent and not AIM_BONE_NOISE[part.Name] then
            local score = (part.Position - origin).Magnitude
            if score < best_score then best_any, best_score = part, score end
        end
    end
    local fallback = best_any or model.PrimaryPart
    return fallback, require_vis and fallback ~= nil and aim_visible(origin, fallback, model) or false
end

local function aim_target_kind(model)
    local kind = model:GetAttribute("Kind")
    if kind then return tostring(kind) end
    local parent = model.Parent
    if parent and parent.Name == "Watchers" then return "Watcher" end
    if model:FindFirstChildOfClass("Humanoid") then return "Player" end
    return "Unknown"
end

local function get_fov_reference_screen_pos(cam)
    if State.aim.fov_origin == "mouse" then
        local ok, mpos = pcall(function() return UserInputService:GetMouseLocation() end)
        if ok and mpos then return mpos end
    end
    local vp = cam.ViewportSize
    return Vector2.new(vp.X * 0.5, vp.Y * 0.5)
end

local function get_fov_radius_px(cam)
    local vp = cam.ViewportSize
    local rad_fov = math.rad(math.clamp(State.aim.fov, 1, 179) * 0.5)
    local rad_cam = math.rad(math.clamp(cam.FieldOfView, 1, 179) * 0.5)
    return math.tan(rad_fov) / math.tan(rad_cam) * (vp.Y * 0.5)
end

-- FOV Circle Drawing handler
local function ensure_fov_circle()
    if type(Drawing) ~= "table" or type(Drawing.new) ~= "function" then
        return nil
    end
    if not fov_circle then
        local circle = Drawing.new("Circle")
        circle.Thickness = 1.5
        circle.NumSides = 64
        circle.Filled = false
        circle.Visible = false
        fov_circle = circle
    end
    return fov_circle
end

local function update_fov_circle()
    if not State.aim.enabled or not State.aim.fov_circle then
        if fov_circle then fov_circle.Visible = false end
        return
    end
    if os.clock() < (State.aim.next_circle or 0) then return end
    State.aim.next_circle = os.clock() + 1 / 30
    local circle = ensure_fov_circle()
    if not circle then return end

    if not State.aim.enabled or not State.aim.fov_circle then
        circle.Visible = false
        return
    end

    local cam = workspace.CurrentCamera
    if not cam then
        circle.Visible = false
        return
    end

    circle.Position = get_fov_reference_screen_pos(cam)
    circle.Radius = get_fov_radius_px(cam)
    if State.aim.locked and State.aim.locked.part then
        circle.Color = State.aim.fov_circle_locked_color or Color3.fromRGB(80, 255, 140)
    else
        circle.Color = State.aim.fov_circle_color or Color3.fromRGB(255, 80, 80)
    end
    circle.Transparency = State.aim.fov_circle_transparency or 0.75
    circle.Visible = true
end

local function aim_kind_allowed(kind)
    local filter = State.aim.target_kind
    if filter == "all" then return true end
    if filter == "listener" then return kind == "Listener" end
    if filter == "hound" then return kind == "Hound" end
    if filter == "brute" then return kind == "Brute" end
    if filter == "watcher" then return kind == "Watcher" end
    if filter == "human" then return kind == "Player" end
    return true
end

local function evaluate_single_model(model, kind, origin, fwd, cam, ref_screen, max_radius_px, half_fov_cos, is_sticky_check)
    if not is_model_alive(model) then return nil end
    if not aim_kind_allowed(kind) then return nil end

    local part, is_vis = aim_pick_vital(model, origin, State.aim.visible_only)
    if not part then return nil end
    if State.aim.visible_only and not is_vis then return nil end

    local delta = part.Position - origin
    local dist = delta.Magnitude
    local limit = State.aim.max_distance
    if dist < 1 or dist > limit then return nil end

    local unit = delta / dist
    -- Jika sticky lock aktif, beri toleransi sudut FOV 15% lebih lebar agar tidak putus-nyambung
    local cos_gate = is_sticky_check and math.cos(math.rad(math.min(180, State.aim.fov * 0.575))) or half_fov_cos
    if State.aim.fov < 360 and fwd:Dot(unit) < cos_gate then
        return nil
    end

    local screen, on_screen = cam:WorldToViewportPoint(part.Position)
    if not on_screen or screen.Z <= 0 then
        if State.aim.fov < 180 then return nil end
    end

    local screen_dist = (Vector2.new(screen.X, screen.Y) - ref_screen).Magnitude
    if State.aim.fov_origin == "mouse" and State.aim.fov < 180 then
        local gate_px = is_sticky_check and (max_radius_px * 1.15) or max_radius_px
        if screen_dist > gate_px then return nil end
    end

    local state = model:GetAttribute("State")
    local humanoid = model:FindFirstChildOfClass("Humanoid")

    return {
        model = model,
        part = part,
        visible = is_vis,
        kind = kind,
        dist = dist,
        state = state and tostring(state) or nil,
        health = humanoid and humanoid.Health or nil,
        velocity = part.AssemblyLinearVelocity,
        screen_dist = screen_dist,
    }
end

local function aim_scan_target()
    local cam = workspace.CurrentCamera
    if not cam then return nil end

    local origin = cam.CFrame.Position
    local fwd = cam.CFrame.LookVector
    local ref_screen = get_fov_reference_screen_pos(cam)
    local max_radius_px = get_fov_radius_px(cam)
    local half_fov_cos = math.cos(math.rad(State.aim.fov * 0.5))

    State.aim.rays_left = 16
    local pool = {}
    local previous = State.aim.target_cache or State.aim.locked
    if previous and previous.model.Parent then
        local kept = evaluate_single_model(previous.model, aim_target_kind(previous.model), origin, fwd,
            cam, ref_screen, max_radius_px, half_fov_cos, State.aim.sticky_lock)
        if kept then
            if State.aim.sticky_lock then return kept end
            pool[1] = kept
        end
    end
    local now = os.clock()
    if now >= (State.aim.roster_at or 0) then
        local roster = {}
        for _, name in ipairs({ "Monsters", "Watchers" }) do
            local folder = workspace:FindFirstChild(name)
            if folder then for _, model in ipairs(folder:GetChildren()) do
                table.insert(roster, { model = model, kind = name == "Watchers" and "Watcher" or aim_target_kind(model) })
            end end
        end
        if State.aim.target_kind == "all" or State.aim.target_kind == "human" then
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= Players.LocalPlayer and player.Character then table.insert(roster, { model = player.Character, kind = "Player" }) end
            end
        end
        State.aim.roster, State.aim.roster_at = roster, now + 1
        State.aim.roster_cursor = State.aim.roster_cursor or 1
    end
    local roster = State.aim.roster or {}
    local slice = os.clock()
    local evaluated = 0
    for i = 1, math.min(8, #roster) do
        local index = ((State.aim.roster_cursor or 1) - 1) % #roster + 1
        local entry = roster[index]
        State.aim.roster_cursor = index + 1
        if entry.model.Parent and aim_kind_allowed(entry.kind) then
            local candidate = evaluate_single_model(entry.model, entry.kind, origin, fwd, cam,
                ref_screen, max_radius_px, half_fov_cos, false)
            if candidate then table.insert(pool, candidate) end
            evaluated += 1
        end
        if os.clock() - slice > 0.0015 then RunService.Heartbeat:Wait(); slice = os.clock() end
    end
    State.aim.models_per_pass = evaluated

    if #pool == 0 then return nil end

    local threat = {
        Chase = 1, Investigate = 2, Listen = 2, Lurk = 3, Wander = 4,
        Sleep = 5, Leave = 6, Buried = 7,
    }

    table.sort(pool, function(a, b)
        if a.visible ~= b.visible then
            return a.visible and not b.visible
        end
        local ta = threat[a.state or ""] or 4
        local tb = threat[b.state or ""] or 4
        if ta ~= tb then return ta < tb end
        local sa, sb = math.floor(a.screen_dist / 35), math.floor(b.screen_dist / 35)
        if sa ~= sb then return sa < sb end
        return a.dist < b.dist
    end)

    return pool[1]
end

-- Fast, non-yielding accessor used by render and weapon hooks.
local function aim_get_current_target()
    local target = State.aim.target_cache
    if not target or os.clock() - (State.aim.target_cache_at or 0) > 0.5 then return nil end
    if not target.model.Parent or not target.part.Parent then return nil end
    return target
end

-- Rotasi kamera berbasis sudut bola sejati (bebas camera roll miring):
-- Menginterpolasi vektor arah pandang dengan batas kecepatan sudut per-frame,
-- lalu membangun CFrame.lookAt tegak lurus terhadap Vector3.yAxis.
local function aim_step_towards(cam, target_pos)
    local current_cf = cam.CFrame
    local origin = current_cf.Position
    local current_look = current_cf.LookVector
    local delta = target_pos - origin
    if delta.Magnitude < 0.01 then return current_cf end
    local desired_look = delta.Unit

    local dot = math.clamp(current_look:Dot(desired_look), -1, 1)
    local total_deg = math.deg(math.acos(dot))
    if total_deg < 0.02 then return current_cf end

    local fraction = math.clamp(State.aim.smooth, 2, 100) / 100
    local step_deg = total_deg * fraction

    local ceiling = math.min(AIM_SNAP_GUARD_DEG, AIM_MAX_GAIN_DEG)
    if step_deg > ceiling then
        step_deg = ceiling
    elseif step_deg < AIM_MIN_STEP_DEG and total_deg > AIM_MIN_STEP_DEG then
        step_deg = AIM_MIN_STEP_DEG
    end

    local alpha = math.clamp(step_deg / total_deg, 0, 1)
    local desired_cf = CFrame.lookAt(origin, origin + desired_look, Vector3.yAxis)
    local next_cf = current_cf:Lerp(desired_cf, alpha)

    -- Jitter sudut mikro agar kurva angular velocity menyerupai tangan manusia
    local jitter_rad = math.rad(AIM_JITTER_DEG)
    local jx = (math.random() - 0.5) * jitter_rad
    local jy = (math.random() - 0.5) * jitter_rad
    local noisy_look = (next_cf * CFrame.Angles(jx, jy, 0)).LookVector

    State.aim.aim_delta_deg = step_deg
    if step_deg > State.aim.stats.peak_deg then
        State.aim.stats.peak_deg = step_deg
    end
    State.aim.stats.steps = (State.aim.stats.steps or 0) + 1

    return CFrame.lookAt(origin, origin + noisy_look, Vector3.yAxis)
end





function restore_aim()
    State.aim.enabled = false
    if State.aim.scan_worker then pcall(task.cancel, State.aim.scan_worker); State.aim.scan_worker = nil end
    State.aim.target_cache = nil
    State.aim.target_cache_at = 0
    State.aim.roster = nil
    State.aim.roster_at = 0
    table.clear(aim_rig_cache)
    State.aim.locked = nil
    State.aim.locked_model = nil
    State.aim.hold_off = 0
    if aim_conn then
        pcall(function() aim_conn:Disconnect() end)
        aim_conn = nil
    end
    if fov_circle then
        pcall(function()
            fov_circle.Visible = false
            fov_circle:Remove()
        end)
        fov_circle = nil
    end
end

local function aim_note_victim(model)
    if not model then return end
    local name = model.Name
    State.aim.session_hits = (State.aim.session_hits or 0) + 1
    if State.aim.last_victim ~= name then
        State.aim.session_victims[name] = true
        State.aim.last_victim = name
    end
end

local function aim_victim_count()
    local n = 0
    for _ in pairs(State.aim.session_victims) do n = n + 1 end
    return n
end

local function is_trigger_active()
    return State.aim.enabled and UserInputService:GetFocusedTextBox() == nil
end

local function apply_aim(enabled)
    State.aim.enabled = enabled
    if not enabled then
        restore_aim()
        return
    end

    local lib = getgenv().HushLibrary
    if lib and lib.Toggles.HushAimCircle then lib.Toggles.HushAimCircle:SetValue(true) end

    if aim_conn then return end

    local worker = task.spawn(function()
        while State.session.active and State.aim.enabled do
            if not is_trigger_active() then
                State.aim.target_cache = nil
                task.wait(0.05)
                continue
            end
            local start = os.clock()
            local ok, target = pcall(aim_scan_target)
            if ok then
                State.aim.target_cache = target
                State.aim.target_cache_at = os.clock()
            else
                State.aim.target_cache = nil
                if os.clock() - (State.aim.last_scan_error or -10) > 5 then
                    State.aim.last_scan_error = os.clock()
                    warn("[hush] target scan: " .. tostring(target))
                end
            end
            State.aim.scan_ms = (os.clock() - start) * 1000
            State.aim.scan_count = (State.aim.scan_count or 0) + 1
            task.wait(State.perf.potato and 0.25 or 0.15)
        end
    end)
    State.aim.scan_worker = worker

    aim_conn = RunService.RenderStepped:Connect(function()
        if not State.aim.enabled then
            if fov_circle then fov_circle.Visible = false end
            return
        end

        local cam = workspace.CurrentCamera
        if not cam then return end

        State.aim.stats.frames = (State.aim.stats.frames or 0) + 1

        local now = os.clock()
        if now < State.aim.hold_off then
            update_fov_circle()
            return
        end

        local target = aim_get_current_target()
        if target and State.aim.locked and target.model ~= State.aim.locked.model then
            State.aim.hold_off = now + AIM_HOLD_OFF_SECONDS
            aim_note_victim(State.aim.locked.model)
        end
        State.aim.locked = target
        State.aim.locked_model = target and target.model or nil

        update_fov_circle()

        if not is_trigger_active() then return end
        if not target or not target.part then return end

        local muzzle_origin = get_muzzle_origin()
        if now >= (State.aim.frame_ballistics_at or 0) then
            State.aim.frame_ballistics = aim_ballistics()
            State.aim.frame_ballistics_at = now + 0.1
        end
        local ballistics = State.aim.frame_ballistics
        local target_pos = aim_solve_point(
            muzzle_origin, target.part.Position, target.part.AssemblyLinearVelocity, ballistics, true
        )

        if State.aim.stats.acquired == 0 or State.aim.last_acquired_model ~= target.model then
            State.aim.stats.acquired = (State.aim.stats.acquired or 0) + 1
            State.aim.last_acquired_model = target.model
        end

        if State.aim.mode == "camera" then
            cam.CFrame = aim_step_towards(cam, target_pos)

        end
    end)
end

-- ---------------------------------------------------------------------------
-- modul silencer & gerak aman
-- ---------------------------------------------------------------------------

local ws_prop_conn = nil
local ws_bound_hum = nil

function restore_movement()
    State.movement.enabled = false
    if ws_prop_conn then
        pcall(function() ws_prop_conn:Disconnect() end)
        ws_prop_conn = nil
        ws_bound_hum = nil
    end
    local player = Players.LocalPlayer
    local char = player and player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.WalkSpeed = State.movement.default_speed
    end
end

local function enforce_walkspeed(hum)
    if not State.movement.enabled or not hum then return end
    local target_speed = math.clamp(State.movement.speed, 12, 20)
    -- Hanya angkat jika kecepatan di bawah target (jangan memotong sprint normal 21 stud/s)
    if hum.WalkSpeed < target_speed and hum.WalkSpeed > 4 then
        hum.WalkSpeed = target_speed
    end
end

local function bind_walkspeed_guard(hum)
    if not hum then return end
    if ws_bound_hum == hum and ws_prop_conn then return end
    if ws_prop_conn then
        pcall(function() ws_prop_conn:Disconnect() end)
    end
    ws_bound_hum = hum
    ws_prop_conn = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
        if State.movement.enabled then
            enforce_walkspeed(hum)
        end
    end)
end

local function apply_movement(enabled, speed)
    State.movement.enabled = enabled
    State.movement.speed = speed or State.movement.speed
    if not enabled then
        restore_movement()
        return
    end
    local player = Players.LocalPlayer
    local char = player and player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        bind_walkspeed_guard(hum)
        enforce_walkspeed(hum)
    end
end



-- ---------------------------------------------------------------------------
-- pembuatan tab UI Alexandria (5-Tab Streamlined Tactical Layout)
-- ---------------------------------------------------------------------------

local function safe_label_write(label, text)
    local ok = pcall(function() label:SetText(text) end)
    if ok then return end
    pcall(function()
        if label.TextLabel then label.TextLabel.Text = text end
    end)
end

-- TAB 1: COMBAT (Aimbot + Weapon Mods & Diagnostics)
local function init_combat_tab(tab)
    local panel = tab:AddGroupbox({
        Side = "Left",
        Name = "Aimbot & Targeting",
        IconName = "crosshair",
    })

    local aim_toggle = panel:AddToggle("HushAimToggle", {
        Text = "Enable Aimbot",
        Default = false,
        Tooltip = "Aktifkan penguncian target di dalam radius FOV.",
        Callback = function(v) apply_aim(v) end,
    })

    panel:AddDropdown("HushAimMode", {
        Text = "Aim Mode",
        Values = { "Kamera" },
        Default = "Kamera",
        Tooltip = "Camera-only compatibility build. Shooting uses the unmodified game weapon pipeline.",
        Callback = function(v)
            State.aim.mode = "camera"
        end,
    })

    panel:AddDropdown("HushAimBone", {
        Text = "Target Hitbox",
        Values = { "Vital", "Kepala", "Badan", "Kaki" },
        Default = "Vital",
        Tooltip = "Prioritize valid vital parts; no weapon modification.",
        Callback = function(v)
            local map = {
                ["Vital"] = "vital", ["Kepala"] = "head",
                ["Badan"] = "body", ["Kaki"] = "legs",
            }
            State.aim.bone = map[v] or "vital"
        end,
    })

    panel:AddDropdown("HushAimKind", {
        Text = "Target Filter",
        Values = { "Semua", "Listener", "Hound", "Brute", "Watcher", "Pemain" },
        Default = "Semua",
        Callback = function(v)
            local map = {
                ["Semua"] = "all",
                ["Listener"] = "listener",
                ["Hound"] = "hound",
                ["Brute"] = "brute",
                ["Watcher"] = "watcher",
                ["Pemain"] = "human",
            }
            State.aim.target_kind = map[v] or "all"
        end,
    })

    State.aim.activation_picker = aim_toggle:AddKeyPicker("HushAimKeybind", {
        Default = "MB2", Mode = "Hold", Modes = { "Hold", "Toggle" },
        SyncToggleState = true, Text = "Aimbot activation",
    })
    panel:AddLabel("Click key box to rebind; right-click for Hold / Toggle.")


    panel:AddDropdown("HushAimFovOrigin", {
        Text = "FOV Center",
        Values = { "Tengah Layar", "Kursor Mouse" },
        Default = "Tengah Layar",
        Callback = function(v)
            State.aim.fov_origin = (v == "Kursor Mouse") and "mouse" or "center"
        end,
    })

    panel:AddDivider()

    panel:AddSlider("HushAimFov", {
        Text = "FOV Radius",
        Default = 90,
        Min = 10,
        Max = 360,
        Rounding = 0,
        Suffix = "°",
        Callback = function(v) State.aim.fov = v end,
    })

    panel:AddSlider("HushAimSmooth", {
        Text = "Smoothness",
        Default = 35,
        Min = 2,
        Max = 100,
        Rounding = 0,
        Suffix = "%",
        Tooltip = "Kecepatan interpolasi kamera per frame (dikunci maksimal 3.0 deg/frame).",
        Callback = function(v) State.aim.smooth = v end,
    })

    panel:AddSlider("HushAimDist", {
        Text = "Max Distance",
        Default = 600,
        Min = 50,
        Max = 1500,
        Rounding = 0,
        Suffix = "m",
        Callback = function(v) State.aim.max_distance = v end,
    })

    local panel2 = tab:AddGroupbox({
        Side = "Right",
        Name = "Camera Aim & Visibility",
        IconName = "shield",
    })





    panel2:AddLabel("Compatibility: weapon hooks disabled.")
    panel2:AddLabel("Silent / No Recoil / No Spread / Voice block quarantined.")
    panel2:AddDivider()

    panel2:AddToggle("HushAimVisible", {
        Text = "Visible Only (Bullet Raycast)",
        Default = false,
        Tooltip = "Raycast CollisionGroup = 'Bullets' (tembus kaca & part transparan minimal 0.9).",
        Callback = function(v) State.aim.visible_only = v end,
    })

    panel2:AddToggle("HushAimWallFallback", {
        Text = "Multi-Point Wall Fallback",
        Default = false,
        Tooltip = "Jika kepala tertutup tembok, otomatis cari anggota tubuh lain yang terlihat.",
        Callback = function(v) State.aim.wall_fallback = v end,
    })

    panel2:AddToggle("HushAimSticky", {
        Text = "Sticky Target Lock",
        Default = false,
        Tooltip = "Pertahankan target yang sedang dikunci sampai mati atau keluar FOV.",
        Callback = function(v) State.aim.sticky_lock = v end,
    })

    panel2:AddToggle("HushAimGravity", {
        Text = "Ballistic Drop & Velocity Lead",
        Default = false,
        Tooltip = "Solver 4-iterasi eksak Shared.Ballistics.arcAt sesuai senjata di tangan (heldId).",
        Callback = function(v) State.aim.gravity_comp = v end,
    })



    panel2:AddToggle("HushAimCircle", {
        Text = "Show FOV Circle",
        Default = false,
        Tooltip = "Otomatis ON saat Aimbot diaktifkan. Bisa dimatikan manual; hijau saat target terkunci.",
        Callback = function(v) State.aim.fov_circle = v end,
    })

    panel2:AddDivider()

    local status = panel2:AddLabel("Target: Ready")
    local function status_write(text)
        State.aim.last_diag = text
        safe_label_write(status, text)
    end

    add_button_compat(panel2, "HushAimProbe", {
        Text = "Inspect Locked Target",
        Func = function()
            local cam = workspace.CurrentCamera
            if not cam then
                status_write("Target: No camera")
                return
            end
            local target = aim_get_current_target()
            local ballistics = aim_ballistics()
            if not target then
                status_write(string.format("Target: None in %d° / %dm", State.aim.fov, State.aim.max_distance))
                return
            end
            local origin = get_muzzle_origin()
            local _, flight = aim_solve_point(
                origin, target.part.Position, target.part.AssemblyLinearVelocity, ballistics, false
            )
            status_write(string.format(
                "%s · %s (%.0fm) | %.3fs | %s v=%.0f",
                target.model.Name, target.part.Name, target.dist, flight, tostring(ballistics.slot), ballistics.velocity
            ))
        end,
    })

    add_button_compat(panel2, "HushAimStats", {
        Text = "Read Session Telemetry",
        Func = function()
            local s = State.aim.stats
            status_write(string.format(
                "Lock %d | Peak %.2f° | Shots %d | Hits %d (%d victims)",
                s.acquired or 0, s.peak_deg or 0, s.fired or 0, State.aim.session_hits or 0, aim_victim_count()
            ))
        end,
    })

    add_button_compat(panel2, "HushAimReset", {
        Text = "Reset Telemetry Counters",
        Func = function()
            State.aim.session_hits = 0
            State.aim.session_victims = {}
            State.aim.last_victim = nil
            State.aim.stats = {
                acquired = 0, steps = 0, frames = 0, peak_deg = 0, fired = 0,
                args_logged = false, gun_arg_shape = "", gun_arg_count = 0,
            }
            status_write("Telemetry reset.")
        end,
    })
end

-- TAB 2: VISUALS (Entity ESP + World Lighting + Loot & Container Radar)
local function init_visuals_tab(tab)
    local layout = tab:AddGroupbox({ Side = "Left", Name = "ESP Layout", IconName = "scan-eye" })
    layout:AddToggle("HushESPDeclutter", {
        Text = "Reduce label overlap", Default = false,
        Tooltip = "Prioritize threats, keep the crosshair clear, and hide overlapping labels. Outlines stay visible.",
        Callback = function(v) State.esp.declutter = v end,
    })
    layout:AddSlider("HushESPInstances", {
        Text = "Label objects (nearest first)", Default = 48, Min = 12, Max = 96, Rounding = 0,
        Callback = function(v) State.esp.render_limit = v end,
    })
    layout:AddSlider("HushOutlineBudget", {
        Text = "Outline objects (nearest first)", Default = 24, Min = 4, Max = 48, Rounding = 0,
        Callback = function(v) State.esp.outline_limit = v end,
    })
    layout:AddSlider("HushESPBudget", {
        Text = "Visible labels", Default = 24, Min = 6, Max = 48, Rounding = 0,
        Callback = function(v) State.esp.label_budget = v end,
    })
    layout:AddSlider("HushESPDetailDistance", {
        Text = "Show status / contents within", Default = 120, Min = 30, Max = 400,
        Rounding = 0, Suffix = " st",
        Callback = function(v) State.esp.detail_distance = v end,
    })
    local panel_ent = tab:AddGroupbox({
        Side = "Left",
        Name = "Entity & Threat ESP",
        IconName = "eye",
    })

    panel_ent:AddToggle("HushMonsterESP", {
        Text = "Monster & Watcher ESP",
        Default = false,
        Tooltip = "Label ringan, detail jarak dekat, dan outline tipis. Warna menandai jenis / ancaman.",
        Callback = function(v) State.esp.monsters = v end,
    })

    panel_ent:AddToggle("HushMonsterOutline", {
        Text = "Creature Outline", Default = false,
        Tooltip = "Outline through walls for this ESP category only. Enable the matching ESP and choose its distance/filter above.",
        Callback = function(v) set_outline("monsters", v) end,
    })

    panel_ent:AddSlider("HushMonsterDist", {
        Text = "Monster Distance",
        Default = 1500,
        Min = 200,
        Max = 2500,
        Rounding = 0,
        Suffix = " st",
        Callback = function(v) State.esp.max_monster_dist = v end,
    })

    panel_ent:AddDivider()

    panel_ent:AddToggle("HushPlayerESP", {
        Text = "Raider / Player ESP",
        Default = false,
        Tooltip = "Player LOS: green when head/root is clear, yellow when blocked or not yet checked. Bounded cached checks; outline uses the same color.",
        Callback = function(v) State.esp.players = v end,
    })

    panel_ent:AddToggle("HushPlayerOutline", {
        Text = "Player Outline", Default = false,
        Tooltip = "Outline through walls for this ESP category only. Enable the matching ESP and choose its distance/filter above.",
        Callback = function(v) set_outline("players", v) end,
    })

    panel_ent:AddSlider("HushPlayerDist", {
        Text = "Player Distance",
        Default = 1500,
        Min = 200,
        Max = 2500,
        Rounding = 0,
        Suffix = " st",
        Callback = function(v) State.esp.max_player_dist = v end,
    })

    panel_ent:AddDivider()

    panel_ent:AddToggle("HushTrapESP", {
        Text = "Noise Trap ESP (Glass / Cans)",
        Default = false,
        Tooltip = "Tampilkan pecahan kaca, kaleng, dan alarm bunyi di sekitar karakter.",
        Callback = function(v) State.esp.traps = v end,
    })

    panel_ent:AddToggle("HushTrapOutline", {
        Text = "Trap Outline", Default = false,
        Tooltip = "Outline through walls for this ESP category only. Enable the matching ESP and choose its distance/filter above.",
        Callback = function(v) set_outline("traps", v) end,
    })

    panel_ent:AddSlider("HushTrapDist", {
        Text = "Trap Distance",
        Default = 40,
        Min = 20,
        Max = 100,
        Rounding = 0,
        Suffix = " st",
        Callback = function(v) State.esp.max_trap_dist = v end,
    })

    local panel_env = tab:AddGroupbox({
        Side = "Left",
        Name = "Environment Lighting",
        IconName = "sun",
    })

    panel_env:AddToggle("HushFullbright", {
        Text = "Fullbright (Nightvision)",
        Default = false,
        Tooltip = "Terangi area gelap dan bunker tanpa merusak state kabut.",
        Callback = function(v) apply_fullbright(v) end,
    })

    panel_env:AddToggle("HushRemoveFog", {
        Text = "No Fog / Clear Atmosphere",
        Default = false,
        Tooltip = "Hilangkan kabut tebal untuk jarak pandang maksimal.",
        Callback = function(v) apply_remove_fog(v) end,
    })

    local panel_loot = tab:AddGroupbox({
        Side = "Right",
        Name = "Loot & Container Radar",
        IconName = "package",
    })

    panel_loot:AddToggle("HushContainerESP", {
        Text = "Container ESP (Crates & Lockers)",
        Default = false,
        Tooltip = "Tampilkan lokasi container (SearchPrompt) & otomatis catat isi itemnya setelah dibuka.",
        Callback = function(v) State.esp.containers = v end,
    })

    panel_loot:AddToggle("HushContainerOutline", {
        Text = "Container Outline", Default = false,
        Tooltip = "Outline through walls for this ESP category only. Enable the matching ESP and choose its distance/filter above.",
        Callback = function(v) set_outline("containers", v) end,
    })

    panel_loot:AddToggle("HushContainerHighOnly", {
        Text = "High-Tier Containers Only",
        Default = false,
        Tooltip = "Fokus ke WeaponCrate, SupplyCrate, AmmoCrate, Lockbox, BunkerArmory, MedCabinet, dan CarTrunk.",
        Callback = function(v) State.esp.containers_high_only = v end,
    })

    panel_loot:AddSlider("HushContainerDist", {
        Text = "Container Distance",
        Default = 250,
        Min = 50,
        Max = 1000,
        Rounding = 0,
        Suffix = " st",
        Callback = function(v) State.esp.max_container_dist = v end,
    })

    panel_loot:AddToggle("HushAutoTakeLoot", {
        Text = "Auto Take All on Reveal",
        Default = false,
        Tooltip = "Otomatis panggil Remotes.Loot:FireServer('takeAll', part) saat item container terbuka.",
        Callback = function(v) State.esp.auto_take_loot = v end,
    })

    panel_loot:AddToggle("HushInstantPrompt", {
        Text = "Instant Open Container (0s Hold)",
        Default = false,
        Tooltip = "Ubah HoldDuration SearchPrompt menjadi 0 detik agar buka container instan.",
        Callback = function(v)
            set_instant_prompt(v)
        end,
    })

    panel_loot:AddDivider()

    panel_loot:AddToggle("HushLootESP", {
        Text = "Ground Loot, Bags & Corpses",
        Default = false,
        Tooltip = "Tampilkan item di WorldFinds, LootBags, Bodies, dan SupplyDrops.",
        Callback = function(v) State.esp.loot = v end,
    })

    panel_loot:AddToggle("HushLootOutline", {
        Text = "Ground Loot / Bag Outline", Default = false,
        Tooltip = "Outline through walls for this ESP category only. Enable the matching ESP and choose its distance/filter above.",
        Callback = function(v) set_outline("loot", v) end,
    })

    panel_loot:AddToggle("HushLootHighTierOnly", {
        Text = "High-Tier Ground Loot Only",
        Default = false,
        Tooltip = "Saring hanya senjata, amunisi, defib, dan tas.",
        Callback = function(v) State.esp.loot_high_tier_only = v end,
    })

    panel_loot:AddSlider("HushLootDist", {
        Text = "Ground Loot Distance",
        Default = 800,
        Min = 100,
        Max = 2000,
        Rounding = 0,
        Suffix = " st",
        Callback = function(v) State.esp.max_loot_dist = v end,
    })
end

-- TAB 3: PLAYER & AUDIO (Movement + Acoustic Stealth)
local function init_player_audio_tab(tab)
    local panel_mov = tab:AddGroupbox({
        Side = "Left",
        Name = "Movement Booster",
        IconName = "wind",
    })

    panel_mov:AddToggle("HushSafeSpeed", {
        Text = "Safe WalkSpeed Override",
        Default = false,
        Tooltip = "Naikkan kecepatan jalan tanpa menguras stamina (dikunci maksimal 20 stud/s di bawah SustainSpeed 24).",
        Callback = function(v) apply_movement(v) end,
    })

    panel_mov:AddSlider("HushSpeedVal", {
        Text = "WalkSpeed",
        Default = 18,
        Min = 12,
        Max = 20,
        Rounding = 0,
        Suffix = " stud/s",
        Callback = function(v)
            State.movement.speed = v
            if State.movement.enabled then
                apply_movement(true, v)
            end
        end,
    })

    panel_mov:AddLabel("Server SustainSpeed = 24 stud/s.\nBatas 20 stud/s bebas dari rubberband & strike.")

    local panel_aud = tab:AddGroupbox({
        Side = "Right",
        Name = "Acoustic Stealth & Threat",
        IconName = "mic-off",
    })

    local status = panel_aud:AddLabel("Mic Shield : ACTIVE")



    panel_aud:AddDivider()

    local threat_label = panel_aud:AddLabel("Threat     : Scanning...")

    local thread = task.spawn(function()
        while true do
            task.wait(1.5)
            local mf = workspace:FindFirstChild("Monsters")
            if mf then
                local hearing = 0
                for _, m in ipairs(mf:GetChildren()) do
                    if m:GetAttribute("HeardDb") ~= nil or m:GetAttribute("State") == "Chase" then
                        hearing = hearing + 1
                    end
                end
                if hearing > 0 then
                    safe_label_write(threat_label, "ALERT      : " .. hearing .. " Monster(s) Hunting / Alerted!")
                else
                    safe_label_write(threat_label, "Threat     : Clear (0 Alerted)")
                end
            else
                safe_label_write(threat_label, "Threat     : In Lobby")
            end
        end
    end)
    table.insert(State.threads, thread)

    panel_aud:AddLabel("Noise Reference:\n• Walk: ~14m  |  Sprint: ~170m  |  Gunshot: 1200m")
end

-- TAB 4: SYSTEM & HOP (Session Info + Server Hop + FPS Booster)
local function init_system_tab(tab)
    local panel_ses = tab:AddGroupbox({
        Side = "Left",
        Name = "Session & Server Hop",
        IconName = "activity",
    })

    local labels = {
        player = panel_ses:AddLabel("Player  : ..."),
        status = panel_ses:AddLabel("State   : Scanning..."),
        coords = panel_ses:AddLabel("Pos     : ..."),
        hop    = panel_ses:AddLabel("Hopper  : Ready"),
    }

    local function refresh()
        local player = Players.LocalPlayer
        safe_label_write(labels.player, "Player  : " .. (player and player.Name or "None"))
        local raid_state = player and player:GetAttribute("RaidState") or "Unknown"
        local raid_locked = ReplicatedStorage:GetAttribute("RaidLocked") == true
        safe_label_write(labels.status, "State   : " .. tostring(raid_state) .. (raid_locked and " (TOWN LOCKED)" or " (OPEN)"))
        local pos = get_origin_pos()
        safe_label_write(labels.coords, string.format("Pos     : %.0f, %.0f, %.0f", pos.X, pos.Y, pos.Z))
    end

    refresh()

    panel_ses:AddToggle("HushLiveRefresh", {
        Text = "Auto-Refresh Telemetry (" .. REFRESH_SECONDS .. "s)",
        Default = false,
        Callback = function(enabled)
            State.live = enabled
            if not enabled then return end
            local thread = task.spawn(function()
                while State.live do
                    refresh()
                    task.wait(REFRESH_SECONDS)
                end
            end)
            table.insert(State.threads, thread)
        end,
    })

    panel_ses:AddDivider()

    add_button_compat(panel_ses, "HushServerHopBtn", {
        Text = "Server Hop (Find Open Town)",
        Func = function()
            task.spawn(function()
                safe_label_write(labels.hop, "Hopper  : Fetching active servers...")
                local ok, res = pcall(function()
                    local HttpService = game:GetService("HttpService")
                    local url = "https://games.roblox.com/v1/games/" .. tostring(game.PlaceId) .. "/servers/Public?sortOrder=Desc&limit=50"
                    return HttpService:JSONDecode(game:HttpGet(url))
                end)
                if not ok or type(res) ~= "table" or type(res.data) ~= "table" then
                    safe_label_write(labels.hop, "Hopper  : API fetch failed")
                    return
                end
                local candidates = {}
                for _, srv in ipairs(res.data) do
                    local playing = tonumber(srv.playing) or 0
                    local maxp = tonumber(srv.maxPlayers) or 30
                    if srv.id and srv.id ~= game.JobId and playing >= 4 and playing <= (maxp - 2) then
                        table.insert(candidates, srv)
                    end
                end
                table.sort(candidates, function(a, b)
                    return (tonumber(a.ping) or 999) < (tonumber(b.ping) or 999)
                end)
                local target_srv = candidates[1]
                if not target_srv then
                    safe_label_write(labels.hop, "Hopper  : No alternate server found")
                    return
                end
                safe_label_write(labels.hop, string.format("Hopper  : -> %s (%dms)", string.sub(target_srv.id, 1, 8), target_srv.ping or 0))
                pcall(function()
                    game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, target_srv.id, Players.LocalPlayer)
                end)
            end)
        end,
    })

    add_button_compat(panel_ses, "HushTeardownBtn", {
        Text = "Unload HUSH Hub (Teardown)",
        Callback = function()
            teardown()
        end,
    })

    local panel_perf = tab:AddGroupbox({
        Side = "Right",
        Name = "FPS Booster & Benchmark",
        IconName = "zap",
    })

    panel_perf:AddToggle("HushShadows", {
        Text = "Disable Global Shadows",
        Default = false,
        Callback = function(v) toggle_shadows(not v) end,
    })

    panel_perf:AddToggle("HushParticles", {
        Text = "Disable Weather & Particles",
        Default = false,
        Callback = function(v) toggle_particles(not v) end,
    })

    panel_perf:AddToggle("HushPostEffects", {
        Text = "Disable Post-Processing Effects",
        Default = false,
        Callback = function(v) toggle_effects(not v) end,
    })

    panel_perf:AddToggle("HushTerrainOpt", {
        Text = "Simplify Water (waves & reflections)",
        Default = false,
        Callback = function(v) toggle_terrain(not v) end,
    })

    panel_perf:AddToggle("HushFlatWorld", {
        Text = "Flat scenery (decorative roots only)", Default = false,
        Tooltip = "Hide decorative decals, reduce mesh detail and shadows; keep materials, collision, actors and interactables unchanged.",
        Callback = function(v) toggle_flat(v) end,
    })
    panel_perf:AddToggle("HushPotato", {
        Text = "Super Potato", Default = false,
        Tooltip = "Reversible graphics preset + 12 ESP labels, 70-stud detail, no outlines. Does not enable ESP or touch weapon settings.",
        Callback = function(v) set_potato(v) end,
    })

    panel_perf:AddDivider()

    panel_perf:AddSlider("HushFPSCap", {
        Text = "FPS Limit",
        Default = 240,
        Min = 60,
        Max = 360,
        Rounding = 0,
        Suffix = " fps",
        Callback = function(v) apply_fps_cap(v) end,
    })

    add_button_compat(panel_perf, "HushUncapFPSBtn", {
        Text = "Uncap FPS (999)",
        Callback = function() apply_fps_cap(999) end,
    })

    local perf_status = panel_perf:AddLabel("FPS Probe : Ready")

    add_button_compat(panel_perf, "HushMeasureFPSBtn", {
        Text = "Run 2s FPS Benchmark",
        Callback = function()
            task.spawn(function()
                safe_label_write(perf_status, "FPS Probe : Measuring (2s)...")
                local fps = measure_fps_quick(2)
                safe_label_write(perf_status, string.format("FPS Probe : %.1f FPS", fps))
            end)
        end,
    })

    add_button_compat(panel_perf, "HushRestorePerfBtn", {
        Text = "Restore Default Graphics",
        Callback = function()
            local lib = getgenv().HushLibrary
            for _, id in ipairs({ "HushPotato", "HushFlatWorld", "HushShadows", "HushParticles", "HushPostEffects", "HushTerrainOpt" }) do
                lib.Toggles[id]:SetValue(false)
            end
            restore_all_perf()
            restore_visuals()
            safe_label_write(perf_status, "FPS Probe : Graphics restored")
        end,
    })
end

-- TAB 5: CONFIG (ThemeManager & SaveManager)
local function init_settings_tab(tab, ThemeManager, SaveManager)
    if not (ThemeManager and SaveManager) then
        local panel = tab:AddGroupbox({
            Side = "Left",
            Name = "Configuration",
            IconName = "settings",
        })
        panel:AddLabel("ThemeManager / SaveManager tidak termuat.")
        return
    end

    pcall(function()
        ThemeManager:SetLibrary(getgenv().HushLibrary)
        SaveManager:SetLibrary(getgenv().HushLibrary)
        SaveManager:IgnoreThemeSettings()
        ThemeManager:SetFolder("hush")
        SaveManager:SetFolder("hush/" .. tostring(game.PlaceId))
        ThemeManager:ApplyToTab(tab)
        SaveManager:BuildConfigSection(tab)
        -- Manual config loading only: fresh execution always starts OFF.
    end)
end

-- ---------------------------------------------------------------------------
-- boot utama
-- ---------------------------------------------------------------------------

local function load_module(name)
    local ok, result = pcall(function()
        return loadstring(game:HttpGet(REPO .. name))()
    end)
    if ok then return result end
    warn("[hush] gagal memuat " .. name .. ": " .. tostring(result))
    return nil
end

local function boot()
    local library = load_module("Library.lua")

    if type(library) ~= "table" then
        warn("[hush] Library.lua tidak termuat.")
        return
    end

    getgenv().HushLibrary = library

    local window = library:CreateWindow({
        Title = WINDOW_TITLE,
        Footer = "v1.4.0 · Tactical Suite | " .. tostring(game.PlaceId),
        Badge = "v1.4",
        Size = UDim2.fromOffset(720, 540),
        Center = true,
        AutoShow = true,
        Resizable = true,
        NotifySide = "Right",
        ToggleKeybind = Enum.KeyCode.RightShift,
    })

    local combat_tab  = window:AddTab("Combat", "crosshair")
    local visuals_tab = window:AddTab("Visuals", "eye")
    local player_tab  = window:AddTab("Player & Audio", "shield")
    local system_tab  = window:AddTab("System & Hop", "zap")
    local config_tab  = window:AddTab("Config", "settings")

    init_combat_tab(combat_tab)
    init_visuals_tab(visuals_tab)
    init_player_audio_tab(player_tab)
    init_system_tab(system_tab)
    init_settings_tab(config_tab, load_module("addons/ThemeManager.lua"), load_module("addons/SaveManager.lua"))

    -- Enforce cold-start OFF, including library-created toggles.
    for _, toggle in pairs(library.Toggles) do
        if toggle.Value == true then toggle:SetValue(false) end
    end

    -- No weapon hooks are installed in this build.
    init_loot_sniffer()

    -- Thread Loop ESP (Differential Pooling)
    local esp_thread = task.spawn(function()
        while true do
            task.wait(State.perf.potato and 0.6 or 0.35)
            local ok, err = pcall(run_esp_cycle)
            if not ok and os.clock() - (State.esp.last_error_at or -10) > 5 then
                State.esp.last_error_at = os.clock()
                warn("[hush] ESP: " .. tostring(err))
            end
        end
    end)
    table.insert(State.threads, esp_thread)

    -- Loop sinkronisasi WalkSpeed di Stepped (sebelum langkah fisika & sesudah Controls RenderStepped)
    local speed_conn = RunService.Stepped:Connect(function()
        if State.movement.enabled then
            local p = Players.LocalPlayer
            local c = p and p.Character
            local h = c and c:FindFirstChildOfClass("Humanoid")
            if h then
                bind_walkspeed_guard(h)
                enforce_walkspeed(h)
            end
        end
    end)
    table.insert(State.connections, speed_conn)

    library:Notify({
        Title = "hush",
        Content = "Hub v1.4.0 termuat. Tekan RightShift untuk toggle.",
        Duration = 4,
        Icon = "check",
    })

    State.session.library = library
    State.session.window = window
    return window
end

boot()
