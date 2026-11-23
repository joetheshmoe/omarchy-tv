-- Omarchy TV: the Hyprland config for the 10-foot session.
--
-- Runs nested inside the desktop for now (`omarchy-tv`), and is written so the
-- same file can later drive a real login session on a TV. Everything here is
-- about three things: draw as little as possible, make every key on a remote
-- do something sensible, and keep each app fullscreen on its own workspace so
-- it can always be found again and closed.

local home = os.getenv("HOME")
local root = os.getenv("OMARCHY_TV_ROOT") or (home .. "/.local/share/omarchy-tv")
local state = os.getenv("OMARCHY_TV_STATE") or ((os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/omarchy-tv")
local headless = os.getenv("OMARCHY_TV_HEADLESS") == "1"
local omarchy_state = home .. "/.local/state/omarchy/current/theme"

local function q(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

-- ---------------------------------------------------------------------------
-- Theme: borrow the Omarchy palette so the compositor background matches the
-- shell during the frames before it maps (no white or black flash).
-- ---------------------------------------------------------------------------
local function theme_color(key, fallback)
  local toml = read_file(omarchy_state .. "/colors.toml") or ""
  local hex = toml:match("\n" .. key .. '%s*=%s*"#(%x%x%x%x%x%x)"') or toml:match("^" .. key .. '%s*=%s*"#(%x%x%x%x%x%x)"')
  return tonumber("ff" .. (hex or fallback), 16)
end

-- ---------------------------------------------------------------------------
-- Keyboard layout and the like come from the desktop, so a keyboard plugged
-- into the TV types the same as it does on the desk.
-- ---------------------------------------------------------------------------
package.path = home .. "/.config/?.lua;" .. root .. "/hypr/?.lua;" .. package.path
pcall(require, "hypr.input")

-- ---------------------------------------------------------------------------
-- Display
-- ---------------------------------------------------------------------------
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

-- ---------------------------------------------------------------------------
-- Look: nothing that costs a shader pass. No gaps, borders, rounding, blur,
-- shadows or dimming; apps are fullscreen and the shell draws its own chrome.
-- ---------------------------------------------------------------------------
hl.config({
  general = {
    gaps_in = 0,
    gaps_out = 0,
    border_size = 0,
    layout = "dwindle",
    resize_on_border = false,
    allow_tearing = true, -- only honoured for windows that ask (games)
  },
  decoration = {
    rounding = 0,
    active_opacity = 1.0,
    inactive_opacity = 1.0,
    fullscreen_opacity = 1.0,
    dim_inactive = false,
    dim_special = 0,
    blur = { enabled = false },
    shadow = { enabled = false },
  },
  animations = { enabled = true },
  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    force_default_wallpaper = 0,
    background_color = theme_color("background", "101315"),
    vrr = 2, -- variable refresh for fullscreen apps only
    render_unfocused_fps = 5, -- apps on hidden workspaces barely tick
    enable_anr_dialog = false, -- the guide's Force quit replaces the mouse-only dialog
    focus_on_activate = true,
    key_press_enables_dpms = true,
    mouse_move_enables_dpms = true,
    exit_window_retains_fullscreen = true,
    middle_click_paste = false,
    -- Nested, the scope omarchy-tv starts it in is the watchdog.
    disable_watchdog_warning = true,
  },
  layers = {
    layers_hog_keyboard_focus = true,
  },
  render = {
    direct_scanout = 2, -- fullscreen video and games skip composition
  },
  cursor = {
    inactive_timeout = 3, -- the pointer is a guest on a TV
    hide_on_key_press = true,
    no_warps = true,
  },
  binds = {
    workspace_back_and_forth = false,
  },
  input = {
    follow_mouse = 1,
    -- Match binds by the key's symbol, not its keycode, so Home and Volume
    -- work from virtual keyboards too: phone remote apps, HDMI-CEC bridges,
    -- the gamepad bridge.
    resolve_binds_by_sym = true,
  },
  ecosystem = {
    no_update_news = true,
    no_donation_nag = true,
  },
})

-- Short, cheap fades. Slides and pop-ins cost more and read as lag on a TV.
hl.curve("tvOut", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } })
hl.animation({ leaf = "global", enabled = true, speed = 3, bezier = "tvOut" })
hl.animation({ leaf = "windows", enabled = true, speed = 2.5, bezier = "tvOut", style = "popin 96%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.5, bezier = "tvOut", style = "popin 96%" })
hl.animation({ leaf = "fade", enabled = true, speed = 2.5, bezier = "tvOut" })
hl.animation({ leaf = "layers", enabled = true, speed = 2.5, bezier = "tvOut", style = "fade" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 2.5, bezier = "tvOut", style = "fade" })
hl.animation({ leaf = "border", enabled = false })
hl.animation({ leaf = "borderangle", enabled = false })

-- ---------------------------------------------------------------------------
-- Windows: every app gets the workspace "tv-<app id>", fullscreen. The app id
-- comes from the systemd scope omarchy-tv-app launched it in, read straight
-- from /proc, so nothing is spawned per window.
-- ---------------------------------------------------------------------------
local function parent_of(pid)
  local stat = read_file("/proc/" .. pid .. "/stat")
  -- The command name is in parentheses and may hold spaces; ppid follows it.
  return stat and tonumber(stat:match("%) %a (%d+)")) or nil
end

local function app_for_pid(pid)
  if not pid or pid <= 0 then return nil end
  local cgroup = read_file("/proc/" .. pid .. "/cgroup")
  -- omarchy-tv-app-<id>-<n>.scope, or omarchy-tvtest-app-... in test sessions
  local id = cgroup and cgroup:match("omarchy%-tv%a*%-app%-([%w_]+)%-%w+%.scope")
  if id then return id end

  -- The app moved itself to a scope of its own (Chromium does): find it by the
  -- root pid omarchy-tv-app recorded, walking up from the window's process.
  local registry = {}
  for line in (read_file(state .. "/pids") or ""):gmatch("[^\n]+") do
    local p, app = line:match("^(%d+) ([%w_]+)$")
    if p then registry[tonumber(p)] = app end
  end
  local current = pid
  for _ = 1, 12 do
    if registry[current] then return registry[current] end
    current = parent_of(current)
    if not current or current <= 1 then break end
  end
  return nil
end

o = o or {}
o.tv_app_for_pid = app_for_pid

hl.on("window.open", function(window)
  if not window or not window.address then return end
  local id = app_for_pid(window.pid) or "other"
  local target = "address:" .. window.address
  local ws = "tv-" .. id

  if not (window.workspace and window.workspace.name == ws) then
    hl.dispatch(hl.dsp.window.move({ workspace = "name:" .. ws, window = target, follow = true }))
  end
  if not window.floating then
    -- A loop later, once the move has landed.
    hl.timer(function()
      hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen", action = "set", window = target }))
    end, { timeout = 1, type = "oneshot" })
  end
end)

-- Dialogs (file pickers, logins) float centred above their app.
hl.window_rule({ name = "tv-dialogs", match = { float = true }, center = true })
-- Games that ask for tearing get it, for the lowest latency.
hl.window_rule({ name = "tv-steam-games", match = { class = "^steam_app_.*" }, immediate = true })

-- No fades: the TV's layers appear and go at once (snappier, and a fading
-- layer can flash a stale frame).
hl.layer_rule({ name = "tv-shell-layers", match = { namespace = "^omarchy-tv.*" }, no_anim = true })

-- ---------------------------------------------------------------------------
-- Bindings. Navigation inside the shell is handled by the shell itself; here
-- are only the keys that must work everywhere, including inside apps. They go
-- to the shell as Hyprland global shortcuts, so a key press spawns nothing.
-- ---------------------------------------------------------------------------
local function shell(name)
  return hl.dsp.global("omarchy-tv:" .. name)
end

-- Home / guide. Remotes send XF86HomePage; a keyboard taps Super.
hl.bind("XF86HomePage", shell("home"))
hl.bind("XF86Favorites", shell("home"))
hl.bind("SUPER + SUPER_L", shell("home"), { release = true })
hl.bind("SUPER + H", shell("home"))
hl.bind("SUPER + G", shell("guide"))

-- Leave the app in front.
hl.bind("XF86Close", shell("close"))
hl.bind("SUPER + Q", shell("close"))
hl.bind("SUPER + W", shell("close"))
hl.bind("SUPER + SHIFT + Q", shell("force-quit"))

-- Switch between running apps.
hl.bind("ALT + TAB", shell("next-app"))
hl.bind("SUPER + TAB", shell("next-app"))

-- Volume, with the shell's OSD. Play/pause, next and previous are left
-- unbound so they reach the app in front, which knows what "pause" means;
-- on Home the shell handles them.
hl.bind("XF86AudioRaiseVolume", shell("volume-up"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", shell("volume-down"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", shell("mute"), { locked = true })

-- Power: the remote's power key, or Super+Escape, opens the power menu.
hl.bind("XF86PowerOff", shell("power"))
hl.bind("SUPER + ESCAPE", shell("power"))

-- On-screen keyboard, mouse mode, voice and the assistant. F20-F23 come from
-- the gamepad bridge (Select, L3, R3, hold Guide); the Super chords are for
-- keyboards and remotes.
hl.bind("F21", shell("keyboard"))
hl.bind("SUPER + K", shell("keyboard"))
hl.bind("F20", shell("pointer"))
hl.bind("SUPER + M", shell("pointer-keys"))
hl.bind("F23", shell("assistant"))
hl.bind("SUPER + A", shell("assistant"))
hl.bind("F22", shell("talk"))
hl.bind("F22", shell("talk-end"), { release = true })
hl.bind("SUPER + T", shell("talk"))
hl.bind("SUPER + T", shell("talk-end"), { release = true })

-- Mouse mode for remotes without a stick: arrows move the pointer, OK clicks,
-- Menu right-clicks, Back leaves. The gamepad bridge owns the virtual mouse,
-- so moves and clicks go to it through its control pipe.
local fifo = state .. "/pointer.ctl"
local function pointer(cmd)
  return hl.dsp.exec_cmd("timeout 1 sh -c " .. q("echo " .. cmd .. " > " .. q(fifo)))
end
hl.define_submap("tv-pointer", function()
  local step = 28
  hl.bind("LEFT", pointer("move -" .. step .. " 0"), { repeating = true })
  hl.bind("RIGHT", pointer("move " .. step .. " 0"), { repeating = true })
  hl.bind("UP", pointer("move 0 -" .. step), { repeating = true })
  hl.bind("DOWN", pointer("move 0 " .. step), { repeating = true })
  hl.bind("SHIFT + LEFT", pointer("move -6 0"), { repeating = true })
  hl.bind("SHIFT + RIGHT", pointer("move 6 0"), { repeating = true })
  hl.bind("SHIFT + UP", pointer("move 0 -6"), { repeating = true })
  hl.bind("SHIFT + DOWN", pointer("move 0 6"), { repeating = true })
  hl.bind("RETURN", pointer("click left"))
  hl.bind("KP_ENTER", pointer("click left"))
  hl.bind("MENU", pointer("click right"))
  hl.bind("PRIOR", pointer("scroll 3"), { repeating = true })
  hl.bind("NEXT", pointer("scroll -3"), { repeating = true })
  hl.bind("ESCAPE", shell("pointer-keys"))
  hl.bind("SUPER + M", shell("pointer-keys"))
  hl.bind("XF86HomePage", shell("home"))
  hl.bind("XF86AudioRaiseVolume", shell("volume-up"), { repeating = true })
  hl.bind("XF86AudioLowerVolume", shell("volume-down"), { repeating = true })
end)

-- Fullscreen escape hatch for the odd app that leaves it.
hl.bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))

-- Always-works exit, even if the shell is gone.
hl.bind("CTRL + ALT + SHIFT + ESCAPE", hl.dsp.exit())

-- ---------------------------------------------------------------------------
-- Start-up
-- ---------------------------------------------------------------------------
local env = "OMARCHY_TV_ROOT=" .. q(root) .. " OMARCHY_TV_STATE=" .. q(state)

-- Test mode keeps only the headless output, also after a config reload
-- (which would otherwise bring the hidden nested window's output back).
function headless_only()
  local has = false
  for _, m in ipairs(hl.get_monitors({ all = true })) do
    if m.name == "TV-HEADLESS" then has = true end
  end
  if not has then return end
  hl.monitor({ output = "TV-HEADLESS", mode = "1920x1080@60", position = "0x0", scale = 1 })
  for _, m in ipairs(hl.get_monitors({ all = true })) do
    if m.name ~= "TV-HEADLESS" then hl.monitor({ output = m.name, disabled = true }) end
  end
end
if headless then
  hl.on("config.reloaded", function() hl.timer(headless_only, { timeout = 50, type = "oneshot" }) end)
end

hl.on("hyprland.start", function()
  -- Tell `omarchy-tv` how to reach this compositor.
  hl.exec_cmd("mkdir -p " .. q(state) .. " && printf 'HYPRLAND_INSTANCE_SIGNATURE=%s\\nWAYLAND_DISPLAY=%s\\n' \"$HYPRLAND_INSTANCE_SIGNATURE\" \"$WAYLAND_DISPLAY\" > " .. q(state .. "/session.env"))

  local start_shell = "env " .. env .. " " .. q(root .. "/bin/omarchy-tv-shell")
  local start_pad = "env " .. env .. " " .. q(root .. "/bin/omarchy-tv-gamepad")

  if headless then
    -- Test mode: render to an invisible 1080p output so screenshots work while
    -- the nested window itself sits hidden on the desktop.
    hl.exec_cmd("hyprctl output create headless TV-HEADLESS")
    hl.timer(function()
      headless_only()
      hl.timer(function() hl.exec_cmd(start_shell) end, { timeout = 400, type = "oneshot" })
    end, { timeout = 400, type = "oneshot" })
  else
    hl.exec_cmd(start_shell)
    hl.exec_cmd(start_pad)
  end
end)

-- Personal overrides, loaded last: ~/.config/omarchy-tv/hyprland.lua
pcall(require, "omarchy-tv.hyprland")
