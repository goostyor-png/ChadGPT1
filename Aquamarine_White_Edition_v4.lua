--[[
AQUAMARINE WHITE EDITION | v4.0 | Original mobile-first Luau project

Independent implementation. This file does not fetch, execute, or copy remote code.

Implemented systems:
  - Mobile-first draggable window, reopen orb, tabs, responsive scale, reduced-motion mode
  - Real toggles/sliders/search lists and runtime theme application
  - Local-only Lighting post-processing and scene presets with restore support
  - Local character aura, particle halo, orbiting motes, highlight, trail and ambient dust
  - Effect profiles and searchable preset catalogs; all listed presets are data-backed
  - Optional executor file persistence, guarded by feature detection
  - Central cleanup, singleton reload protection, low/medium/high effect budgets

Safety / compatibility:
  - Visual changes are local cosmetic effects only.
  - No remote-event abuse, anti-cheat bypasses, aimbot, teleport, inventory manipulation,
    or changes to other players' clients are included.
  - Lua executor APIs are optional and vary. The script uses standard Roblox client APIs
    for its core UI and local visual systems. Test in a controlled place first.
]]

if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then return end

local ENV = (type(getgenv) == "function" and getgenv()) or _G
if type(ENV.__AQUAMARINE_WHITE_EDITION_V4) == "table" then
    pcall(function() ENV.__AQUAMARINE_WHITE_EDITION_V4:Destroy() end)
end

local AWE = {}
AWE.__index = AWE
AWE.Version = "4.0.0"
AWE.Destroyed = false
AWE.Connections = {}
AWE.Instances = {}
AWE.ThemeBindings = {}
AWE.EffectInstances = {}
AWE.Catalog = { Effects = {}, Scenes = {}, Themes = {} }
AWE.Active = { Tab = "HOME", Effect = nil, Scene = nil, Theme = nil }
AWE.ToggleControls = {}

local function safeCall(fn, ...)
    local ok, a, b, c = pcall(fn, ...)
    if ok then return true, a, b, c end
    return false, a
end

local function connect(signal, fn)
    local ok, connection = safeCall(function() return signal:Connect(fn) end)
    if ok and connection then
        table.insert(AWE.Connections, connection)
        return connection
    end
end

local function keep(instance)
    if instance then table.insert(AWE.Instances, instance) end
    return instance
end

local function disconnectAll()
    for _, connection in ipairs(AWE.Connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(AWE.Connections)
end

local function destroyAll(list)
    for i = #list, 1, -1 do
        local instance = list[i]
        pcall(function() instance:Destroy() end)
        list[i] = nil
    end
end

local function make(className, props, parent)
    local object = Instance.new(className)
    for key, value in pairs(props or {}) do
        pcall(function() object[key] = value end)
    end
    if parent then object.Parent = parent end
    return object
end

local function tween(object, seconds, goal, style, direction)
    if not object or not object.Parent then return end
    if AWE.State and AWE.State.ReducedMotion then
        for key, value in pairs(goal) do pcall(function() object[key] = value end) end
        return
    end
    local ok, animation = safeCall(function()
        return TweenService:Create(object, TweenInfo.new(
            seconds or 0.22,
            style or Enum.EasingStyle.Quint,
            direction or Enum.EasingDirection.Out
        ), goal)
    end)
    if ok and animation then animation:Play() end
end

local function round(parent, radius)
    return make("UICorner", { CornerRadius = UDim.new(0, radius or 12) }, parent)
end

local function stroke(parent, color, thickness, transparency)
    return make("UIStroke", {
        Color = color or Color3.fromRGB(235, 250, 255),
        Thickness = thickness or 1,
        Transparency = transparency or 0.2,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, parent)
end

local function pad(parent, left, top, right, bottom)
    return make("UIPadding", {
        PaddingLeft = UDim.new(0, left or 0),
        PaddingTop = UDim.new(0, top or 0),
        PaddingRight = UDim.new(0, right or 0),
        PaddingBottom = UDim.new(0, bottom or 0),
    }, parent)
end

local function listLayout(parent, direction, gap, horizontalAlignment)
    return make("UIListLayout", {
        FillDirection = direction or Enum.FillDirection.Vertical,
        Padding = UDim.new(0, gap or 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
        HorizontalAlignment = horizontalAlignment or Enum.HorizontalAlignment.Left,
    }, parent)
end

local function rgb(r, g, b)
    return Color3.fromRGB(math.clamp(math.floor(r), 0, 255), math.clamp(math.floor(g), 0, 255), math.clamp(math.floor(b), 0, 255))
end

local function colorHex(color)
    return string.format("#%02X%02X%02X", math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255))
end

local function clampNumber(value, minValue, maxValue, fallback)
    local number = tonumber(value)
    if not number then return fallback end
    return math.clamp(number, minValue, maxValue)
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function matches(query, ...)
    query = lower(query)
    if query == "" then return true end
    local text = lower(table.concat({...}, " "))
    return string.find(text, query, 1, true) ~= nil
end

local PALETTE = {
    Window = Color3.fromRGB(248, 252, 255),
    Panel = Color3.fromRGB(239, 247, 252),
    Card = Color3.fromRGB(255, 255, 255),
    Text = Color3.fromRGB(30, 48, 61),
    Muted = Color3.fromRGB(103, 126, 142),
    Accent = Color3.fromRGB(88, 221, 235),
    Accent2 = Color3.fromRGB(173, 246, 255),
    Border = Color3.fromRGB(199, 231, 239),
    Selected = Color3.fromRGB(224, 250, 253),
    Danger = Color3.fromRGB(231, 103, 132),
    Track = Color3.fromRGB(220, 235, 241),
}

AWE.State = {
    Open = true,
    Scale = 0.92,
    Transparency = 0.04,
    Glow = true,
    GlowStrength = 1.15,
    BackgroundParticles = true,
    Bloom = true,
    ColorGrade = false,
    Blur = false,
    SunRays = false,
    DepthOfField = false,
    Atmosphere = false,
    AvatarAura = false,
    AvatarTrail = false,
    AvatarHighlight = false,
    OrbitMotes = false,
    AmbientDust = false,
    BurstOnTap = true,
    ReducedMotion = false,
    Performance = "MEDIUM",
    ParticleBudget = 1,
    AmbientRate = 8,
    AuraRate = 20,
    OrbitCount = 5,
    OrbitSpeed = 1,
    BrightnessBoost = false,
    CustomAccent = Color3.fromRGB(100, 233, 244),
}

local ORIG = {
    Lighting = {},
    Camera = {},
    Character = nil,
}
for _, property in ipairs({
    "Brightness", "ClockTime", "ExposureCompensation", "Ambient", "OutdoorAmbient",
    "FogColor", "FogStart", "FogEnd", "ColorShift_Top", "ColorShift_Bottom",
    "EnvironmentDiffuseScale", "EnvironmentSpecularScale", "GlobalShadows",
}) do
    pcall(function() ORIG.Lighting[property] = Lighting[property] end)
end

local function registerThemeBinding(object, role, property)
    table.insert(AWE.ThemeBindings, { Object = object, Role = role, Property = property or "BackgroundColor3" })
end

local function setThemeColor(name, color)
    PALETTE[name] = color
    for _, binding in ipairs(AWE.ThemeBindings) do
        if binding.Role == name and binding.Object and binding.Object.Parent then
            pcall(function() binding.Object[binding.Property] = color end)
        end
    end
end

local function paint(object, role, property)
    property = property or "BackgroundColor3"
    registerThemeBinding(object, role, property)
    pcall(function() object[property] = PALETTE[role] end)
    return object
end

local function themeText(object, role)
    return paint(object, role or "Text", "TextColor3")
end

local function setAccent(color)
    AWE.State.CustomAccent = color
    setThemeColor("Accent", color)
    setThemeColor("Accent2", color:Lerp(Color3.new(1, 1, 1), 0.48))
    setThemeColor("Selected", color:Lerp(Color3.new(1, 1, 1), 0.82))
    setThemeColor("Border", color:Lerp(Color3.new(1, 1, 1), 0.62))
end

local function colorSequence(a, b)
    return ColorSequence.new({
        ColorSequenceKeypoint.new(0, a),
        ColorSequenceKeypoint.new(1, b),
    })
end

local function newScreenGui()
    local gui = Instance.new("ScreenGui")
    gui.Name = "AquamarineWhiteEdition_v4"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 9600
    local attached = pcall(function() gui.Parent = CoreGui end)
    if not attached then
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui")
        gui.Parent = playerGui
    end
    return keep(gui)
end

AWE.Gui = newScreenGui()

AWE.ScreenScale = make("UIScale", { Scale = AWE.State.Scale }, AWE.Gui)
AWE.Root = make("Frame", {
    Name = "MainWindow",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.52),
    Size = UDim2.fromOffset(540, 620),
    BackgroundTransparency = AWE.State.Transparency,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Active = true,
    ZIndex = 5,
}, AWE.Gui)
round(AWE.Root, 18)
AWE.RootStroke = stroke(AWE.Root, PALETTE.Border, 1.3, 0.03)
paint(AWE.Root, "Window")

AWE.DecorLayer = make("Frame", {
    Name = "FloatingPearlMotes",
    Size = UDim2.fromScale(1,1),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    ZIndex = 7,
}, AWE.Root)
AWE.DecorMotes = {}
for index = 1, 22 do
    local diameter = 3 + (index % 4)
    local mote = make("Frame", {
        Name = "PearlMote_" .. index,
        Position = UDim2.fromScale(math.random(4,96)/100, math.random(8,92)/100),
        Size = UDim2.fromOffset(diameter, diameter),
        BackgroundColor3 = index % 2 == 0 and PALETTE.Accent2 or Color3.fromRGB(255,255,255),
        BackgroundTransparency = 0.76 + (index % 4) * 0.04,
        BorderSizePixel = 0,
        ZIndex = 7,
    }, AWE.DecorLayer)
    round(mote, 8)
    table.insert(AWE.DecorMotes, { Object=mote, Phase=index*0.51, X=math.random(4,96)/100, Y=math.random(8,92)/100 })
end

AWE.TopGlow = make("Frame", {
    Name = "TopGlow",
    Position = UDim2.new(0, 0, 0, 0),
    Size = UDim2.new(1, 0, 0, 3),
    BorderSizePixel = 0,
    BackgroundColor3 = PALETTE.Accent,
    ZIndex = 20,
}, AWE.Root)
make("UIGradient", {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(0.45, PALETTE.Accent),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
    }),
    Rotation = 0,
}, AWE.TopGlow)

AWE.Header = make("Frame", {
    Name = "Header",
    Position = UDim2.fromOffset(0, 3),
    Size = UDim2.new(1, 0, 0, 62),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Active = true,
    ZIndex = 8,
}, AWE.Root)

AWE.Logo = make("Frame", {
    Position = UDim2.fromOffset(14, 13),
    Size = UDim2.fromOffset(36, 36),
    BackgroundColor3 = PALETTE.Accent,
    BorderSizePixel = 0,
    ZIndex = 10,
}, AWE.Header)
round(AWE.Logo, 12)
make("UIGradient", { Color = colorSequence(Color3.fromRGB(255,255,255), PALETTE.Accent) }, AWE.Logo)
local logoMark = make("TextLabel", {
    BackgroundTransparency = 1,
    Size = UDim2.fromScale(1, 1),
    Text = "A",
    Font = Enum.Font.GothamBlack,
    TextSize = 21,
    TextColor3 = Color3.fromRGB(255,255,255),
    ZIndex = 11,
}, AWE.Logo)

AWE.Title = make("TextLabel", {
    Name = "Title",
    Position = UDim2.fromOffset(60, 10),
    Size = UDim2.new(1, -160, 0, 25),
    BackgroundTransparency = 1,
    Text = "AQUAMARINE",
    TextXAlignment = Enum.TextXAlignment.Left,
    TextColor3 = PALETTE.Text,
    Font = Enum.Font.GothamBold,
    TextSize = 16,
    ZIndex = 9,
}, AWE.Header)
themeText(AWE.Title)
AWE.Subtitle = make("TextLabel", {
    Position = UDim2.fromOffset(61, 33),
    Size = UDim2.new(1, -170, 0, 17),
    BackgroundTransparency = 1,
    Text = "WHITE EDITION  ·  LOCAL VISUAL LAB",
    TextXAlignment = Enum.TextXAlignment.Left,
    TextColor3 = PALETTE.Muted,
    Font = Enum.Font.GothamMedium,
    TextSize = 9,
    ZIndex = 9,
}, AWE.Header)
themeText(AWE.Subtitle, "Muted")

AWE.HeaderActions = make("Frame", {
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -12, 0, 13),
    Size = UDim2.fromOffset(92, 36),
    BackgroundTransparency = 1,
    ZIndex = 11,
}, AWE.Header)
listLayout(AWE.HeaderActions, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right)

local function makeHeaderButton(text, name, parent)
    local button = make("TextButton", {
        Name = name,
        Size = UDim2.fromOffset(36, 36),
        Text = text,
        Font = Enum.Font.GothamBold,
        TextSize = 15,
        TextColor3 = PALETTE.Text,
        BackgroundColor3 = PALETTE.Card,
        AutoButtonColor = false,
        BorderSizePixel = 0,
        ZIndex = 12,
    }, parent)
    round(button, 11)
    stroke(button, PALETTE.Border, 1, 0.12)
    paint(button, "Card")
    themeText(button)
    return button
end

AWE.MinimizeButton = makeHeaderButton("—", "Minimize", AWE.HeaderActions)
AWE.CloseButton = makeHeaderButton("×", "Close", AWE.HeaderActions)
AWE.MinimizeButton.TextSize = 18
AWE.CloseButton.TextSize = 21

AWE.Body = make("Frame", {
    Name = "Body",
    Position = UDim2.fromOffset(10, 70),
    Size = UDim2.new(1, -20, 1, -80),
    BackgroundTransparency = 1,
    ZIndex = 6,
}, AWE.Root)

AWE.Sidebar = make("Frame", {
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.new(0, 104, 1, 0),
    BackgroundColor3 = PALETTE.Panel,
    BorderSizePixel = 0,
    ZIndex = 6,
}, AWE.Body)
round(AWE.Sidebar, 14)
paint(AWE.Sidebar, "Panel")
pad(AWE.Sidebar, 7, 9, 7, 8)
AWE.SidebarList = make("Frame", {
    BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 1, -44),
    ZIndex = 7,
}, AWE.Sidebar)
listLayout(AWE.SidebarList, Enum.FillDirection.Vertical, 5)
AWE.SidebarFooter = make("TextLabel", {
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 0, 1, 0),
    Size = UDim2.new(1, 0, 0, 31),
    BackgroundTransparency = 1,
    Text = "v" .. AWE.Version .. "\nMOBILE BUILD",
    TextColor3 = PALETTE.Muted,
    Font = Enum.Font.GothamMedium,
    TextSize = 8,
    TextWrapped = true,
    ZIndex = 7,
}, AWE.Sidebar)
themeText(AWE.SidebarFooter, "Muted")

AWE.Content = make("Frame", {
    Name = "Content",
    Position = UDim2.new(0, 112, 0, 0),
    Size = UDim2.new(1, -112, 1, 0),
    BackgroundTransparency = 1,
    ZIndex = 6,
}, AWE.Body)
AWE.Pages = {}
AWE.TabButtons = {}
AWE.PageTitle = nil
AWE.PageHint = nil
AWE.Notice = nil
AWE.Reopen = make("TextButton", {
    Name = "ReopenAquamarine",
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -14, 0.52, 0),
    Size = UDim2.fromOffset(54, 54),
    Text = "A",
    Font = Enum.Font.GothamBlack,
    TextSize = 23,
    TextColor3 = Color3.fromRGB(255,255,255),
    BackgroundColor3 = PALETTE.Accent,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Visible = false,
    ZIndex = 100,
}, AWE.Gui)
round(AWE.Reopen, 20)
stroke(AWE.Reopen, Color3.fromRGB(255,255,255), 1.7, 0)
make("UIGradient", { Color = colorSequence(Color3.fromRGB(255,255,255), PALETTE.Accent) }, AWE.Reopen)

local function showNotice(message, duration)
    if not AWE.Root or not AWE.Root.Parent then return end
    if AWE.Notice and AWE.Notice.Parent then AWE.Notice:Destroy() end
    AWE.Notice = make("TextLabel", {
        Name = "Toast",
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -12),
        Size = UDim2.new(1, -26, 0, 35),
        BackgroundColor3 = PALETTE.Card,
        BackgroundTransparency = 0.02,
        BorderSizePixel = 0,
        Text = tostring(message),
        Font = Enum.Font.GothamMedium,
        TextSize = 11,
        TextColor3 = PALETTE.Text,
        TextWrapped = true,
        ZIndex = 99,
    }, AWE.Root)
    round(AWE.Notice, 11)
    stroke(AWE.Notice, PALETTE.Accent, 1.2, 0.1)
    task.delay(duration or 2.5, function()
        if AWE.Notice and AWE.Notice.Parent then
            tween(AWE.Notice, 0.15, { BackgroundTransparency = 1, TextTransparency = 1 })
            task.delay(0.2, function()
                if AWE.Notice and AWE.Notice.Parent then AWE.Notice:Destroy() end
            end)
        end
    end)
end

local function pageScroll(name, title, hint)
    local page = make("ScrollingFrame", {
        Name = name,
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = PALETTE.Accent,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        Visible = false,
        ZIndex = 7,
    }, AWE.Content)
    pad(page, 1, 2, 4, 10)
    listLayout(page, Enum.FillDirection.Vertical, 9)
    local head = make("Frame", {
        Size = UDim2.new(1, -2, 0, 51),
        BackgroundTransparency = 1,
        ZIndex = 8,
    }, page)
    local heading = make("TextLabel", {
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(1, 0, 0, 27),
        BackgroundTransparency = 1,
        Text = title,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = PALETTE.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 17,
        ZIndex = 8,
    }, head)
    themeText(heading)
    local sub = make("TextLabel", {
        Position = UDim2.fromOffset(0, 27),
        Size = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
        Text = hint or "LOCAL COSMETIC CONTROLS",
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = PALETTE.Muted,
        Font = Enum.Font.GothamMedium,
        TextSize = 9,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 8,
    }, head)
    themeText(sub, "Muted")
    AWE.Pages[name] = page
    return page
end

local function section(parent, title, subtitle)
    local card = make("Frame", {
        Name = string.gsub(title, "%W", "") .. "Section",
        Size = UDim2.new(1, -2, 0, 10),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = PALETTE.Card,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        ZIndex = 8,
    }, parent)
    round(card, 13)
    stroke(card, PALETTE.Border, 1, 0.23)
    paint(card, "Card")
    pad(card, 10, 10, 10, 10)
    local layout = listLayout(card, Enum.FillDirection.Vertical, 7)
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        if card and card.Parent then card.Size = UDim2.new(1, -2, 0, layout.AbsoluteContentSize.Y + 20) end
    end)
    local head = make("Frame", {
        Size = UDim2.new(1, 0, 0, subtitle and 36 or 22),
        BackgroundTransparency = 1,
        ZIndex = 9,
    }, card)
    local titleLabel = make("TextLabel", {
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        Text = title,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = PALETTE.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        ZIndex = 9,
    }, head)
    themeText(titleLabel)
    if subtitle then
        local sub = make("TextLabel", {
            Position = UDim2.fromOffset(0, 19),
            Size = UDim2.new(1, 0, 0, 15),
            BackgroundTransparency = 1,
            Text = subtitle,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextColor3 = PALETTE.Muted,
            Font = Enum.Font.Gotham,
            TextSize = 9,
            TextTruncate = Enum.TextTruncate.AtEnd,
            ZIndex = 9,
        }, head)
        themeText(sub, "Muted")
    end
    return card
end

local function label(parent, text, height)
    local item = make("TextLabel", {
        Size = UDim2.new(1, 0, 0, height or 25),
        BackgroundTransparency = 1,
        Text = text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        TextColor3 = PALETTE.Muted,
        Font = Enum.Font.Gotham,
        TextSize = 10,
        ZIndex = 9,
    }, parent)
    themeText(item, "Muted")
    return item
end

local function actionButton(parent, text, callback, opts)
    opts = opts or {}
    local button = make("TextButton", {
        Size = UDim2.new(1, 0, 0, opts.Height or 34),
        BackgroundColor3 = opts.Accent and PALETTE.Accent or PALETTE.Panel,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = text,
        TextColor3 = opts.Accent and Color3.fromRGB(255,255,255) or PALETTE.Text,
        Font = Enum.Font.GothamSemibold,
        TextSize = opts.TextSize or 10,
        TextWrapped = true,
        ZIndex = 10,
    }, parent)
    round(button, 10)
    stroke(button, opts.Accent and PALETTE.Accent or PALETTE.Border, 1, 0.18)
    if not opts.Accent then paint(button, "Panel") end
    if not opts.Accent then themeText(button) end
    connect(button.Activated, function()
        if AWE.Destroyed then return end
        if AWE.State.BurstOnTap then AWE:TapBurst(button) end
        local ok, err = pcall(callback or function() end)
        if not ok then warn("[Aquamarine] Action failed:", err); showNotice("Action failed — see console", 2.5) end
    end)
    connect(button.MouseEnter, function() tween(button, 0.12, { BackgroundTransparency = 0.08 }) end)
    connect(button.MouseLeave, function() tween(button, 0.12, { BackgroundTransparency = 0 }) end)
    return button
end

local function toggleRow(parent, title, description, initial, callback)
    local row = make("Frame", {
        Size = UDim2.new(1, 0, 0, description and 51 or 37),
        BackgroundTransparency = 1,
        ZIndex = 9,
    }, parent)
    local titleLabel = make("TextLabel", {
        Position = UDim2.fromOffset(0, 1),
        Size = UDim2.new(1, -54, 0, description and 21 or 35),
        BackgroundTransparency = 1,
        Text = title,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = description and Enum.TextYAlignment.Bottom or Enum.TextYAlignment.Center,
        TextColor3 = PALETTE.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 10,
        TextWrapped = true,
        ZIndex = 10,
    }, row)
    themeText(titleLabel)
    if description then
        local desc = make("TextLabel", {
            Position = UDim2.fromOffset(0, 24),
            Size = UDim2.new(1, -54, 0, 20),
            BackgroundTransparency = 1,
            Text = description,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            TextColor3 = PALETTE.Muted,
            Font = Enum.Font.Gotham,
            TextSize = 8,
            TextWrapped = true,
            ZIndex = 10,
        }, row)
        themeText(desc, "Muted")
    end
    local hit = make("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(43, 25),
        BackgroundColor3 = initial and PALETTE.Accent or PALETTE.Track,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 11,
    }, row)
    round(hit, 13)
    local dot = make("Frame", {
        Position = initial and UDim2.new(1, -21, 0.5, -8) or UDim2.new(0, 5, 0.5, -8),
        Size = UDim2.fromOffset(16, 16),
        BackgroundColor3 = Color3.new(1,1,1),
        BorderSizePixel = 0,
        ZIndex = 12,
    }, hit)
    round(dot, 8)
    local value = not not initial
    local function apply(notify)
        tween(hit, 0.14, { BackgroundColor3 = value and PALETTE.Accent or PALETTE.Track })
        tween(dot, 0.14, { Position = value and UDim2.new(1, -21, 0.5, -8) or UDim2.new(0, 5, 0.5, -8) })
        if notify and callback then callback(value) end
    end
    connect(hit.Activated, function() value = not value; apply(true) end)
    local control = {
        Title = title,
        Set = function(v, notify) value = not not v; apply(notify) end,
        Get = function() return value end,
        Button = hit,
        Row = row,
    }
    table.insert(AWE.ToggleControls, control)
    return control
end

local function sliderRow(parent, title, minValue, maxValue, startValue, decimals, callback, suffix)
    local row = make("Frame", { Size = UDim2.new(1,0,0,54), BackgroundTransparency = 1, ZIndex = 9 }, parent)
    local heading = make("TextLabel", {
        Size = UDim2.new(1, -52, 0, 20), BackgroundTransparency = 1,
        Text = title, TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = PALETTE.Text, Font = Enum.Font.GothamMedium, TextSize = 10, ZIndex = 10,
    }, row)
    themeText(heading)
    local valueLabel = make("TextLabel", {
        AnchorPoint = Vector2.new(1,0), Position = UDim2.new(1,0,0,0),
        Size = UDim2.fromOffset(52,20), BackgroundTransparency = 1,
        Text = tostring(startValue) .. (suffix or ""), TextXAlignment = Enum.TextXAlignment.Right,
        TextColor3 = PALETTE.Muted, Font = Enum.Font.GothamSemibold, TextSize = 9, ZIndex = 10,
    }, row)
    themeText(valueLabel, "Muted")
    local track = make("Frame", {
        Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1,0,0,7),
        BackgroundColor3 = PALETTE.Track, BorderSizePixel = 0, ZIndex = 10,
    }, row)
    round(track, 5); paint(track, "Track")
    local fraction = (startValue - minValue) / math.max(0.00001, maxValue - minValue)
    local fill = make("Frame", { Size = UDim2.new(fraction,0,1,0), BackgroundColor3 = PALETTE.Accent, BorderSizePixel = 0, ZIndex = 11 }, track)
    round(fill, 5); paint(fill, "Accent")
    local knob = make("Frame", { AnchorPoint = Vector2.new(0.5,0.5), Position = UDim2.new(fraction,0,0.5,0), Size = UDim2.fromOffset(15,15), BackgroundColor3 = Color3.new(1,1,1), BorderSizePixel = 0, ZIndex = 12 }, track)
    round(knob, 8); stroke(knob, PALETTE.Accent, 2, 0)
    local active = false
    local value = startValue
    local function updateFromX(x, notify)
        local width = math.max(1, track.AbsoluteSize.X)
        local percent = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
        value = minValue + ((maxValue - minValue) * percent)
        local mult = 10 ^ (decimals or 0)
        value = math.floor(value * mult + 0.5) / mult
        fill.Size = UDim2.new(percent,0,1,0)
        knob.Position = UDim2.new(percent,0,0.5,0)
        valueLabel.Text = tostring(value) .. (suffix or "")
        if notify and callback then callback(value) end
    end
    connect(track.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            active = true; updateFromX(input.Position.X, true)
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if active and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then updateFromX(input.Position.X, true) end
    end)
    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then active = false end
    end)
    return {
        Set = function(v, notify)
            value = clampNumber(v, minValue, maxValue, startValue)
            local percent = (value - minValue) / math.max(0.00001, maxValue - minValue)
            fill.Size = UDim2.new(percent,0,1,0); knob.Position = UDim2.new(percent,0,0.5,0)
            valueLabel.Text = tostring(value) .. (suffix or "")
            if notify and callback then callback(value) end
        end,
        Get = function() return value end,
    }
end

local function searchBox(parent, placeholder)
    local box = make("TextBox", {
        Size = UDim2.new(1,0,0,34), BackgroundColor3 = PALETTE.Panel,
        BorderSizePixel = 0, ClearTextOnFocus = false, Text = "",
        PlaceholderText = placeholder or "Search presets...", PlaceholderColor3 = PALETTE.Muted,
        TextColor3 = PALETTE.Text, Font = Enum.Font.Gotham, TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 10,
    }, parent)
    round(box, 10); stroke(box, PALETTE.Border, 1, 0.2); pad(box, 10, 0, 8, 0)
    paint(box, "Panel"); themeText(box)
    return box
end

local function presetCard(parent, name, subtitle, swatch, callback)
    local row = make("TextButton", {
        Size = UDim2.new(1,0,0,49), BackgroundColor3 = PALETTE.Panel,
        BorderSizePixel = 0, Text = "", AutoButtonColor = false, ZIndex = 10,
    }, parent)
    round(row, 10); stroke(row, PALETTE.Border, 1, 0.35); paint(row, "Panel")
    local chip = make("Frame", { Position = UDim2.fromOffset(8,9), Size = UDim2.fromOffset(29,29), BackgroundColor3 = swatch or PALETTE.Accent, BorderSizePixel = 0, ZIndex = 11 }, row)
    round(chip, 9)
    local title = make("TextLabel", { Position = UDim2.fromOffset(45,6), Size = UDim2.new(1,-53,0,18), BackgroundTransparency = 1, Text = name, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = PALETTE.Text, Font = Enum.Font.GothamSemibold, TextSize = 9, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 11 }, row)
    themeText(title)
    local desc = make("TextLabel", { Position = UDim2.fromOffset(45,24), Size = UDim2.new(1,-53,0,15), BackgroundTransparency = 1, Text = subtitle or "Preset", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = PALETTE.Muted, Font = Enum.Font.Gotham, TextSize = 8, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 11 }, row)
    themeText(desc, "Muted")
    connect(row.Activated, function() if callback then callback() end end)
    return row
end

local function clearChildren(container, preserve)
    for _, child in ipairs(container:GetChildren()) do
        if child ~= preserve and not child:IsA("UIListLayout") and not child:IsA("UIPadding") then child:Destroy() end
    end
end

local function hideWindow()
    AWE.State.Open = false
    tween(AWE.Root, 0.18, { BackgroundTransparency = 1, Size = UDim2.fromOffset(500, 0) })
    task.delay(0.2, function()
        if AWE.Root and AWE.Root.Parent and not AWE.State.Open then AWE.Root.Visible = false end
    end)
    AWE.Reopen.Visible = true
    AWE.Reopen.Size = UDim2.fromOffset(12,12)
    tween(AWE.Reopen, 0.24, { Size = UDim2.fromOffset(54,54) }, Enum.EasingStyle.Back)
end

local function showWindow()
    AWE.State.Open = true
    AWE.Root.Visible = true
    AWE.Reopen.Visible = false
    AWE.Root.Size = UDim2.fromOffset(500, 0)
    AWE.Root.BackgroundTransparency = 1
    tween(AWE.Root, 0.26, { Size = UDim2.fromOffset(540,620), BackgroundTransparency = AWE.State.Transparency }, Enum.EasingStyle.Back)
end

connect(AWE.MinimizeButton.Activated, hideWindow)
connect(AWE.CloseButton.Activated, hideWindow)
connect(AWE.Reopen.Activated, showWindow)

-- Drag support is deliberately limited to the header so content remains usable.
do
    local dragging = false
    local dragStart, startPosition
    connect(AWE.Header.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = AWE.Root.Position
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            AWE.Root.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X, startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
end

local function applyResponsiveScale()
    local camera = Workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(800, 600)
    local availableW = math.max(290, viewport.X - 20)
    local availableH = math.max(360, viewport.Y - 80)
    local scale = math.min(AWE.State.Scale, availableW / 540, availableH / 620)
    AWE.ScreenScale.Scale = math.clamp(scale, 0.52, 1.15)
    local rootWidth = math.min(540, math.max(300, availableW / AWE.ScreenScale.Scale))
    local rootHeight = math.min(620, math.max(420, availableH / AWE.ScreenScale.Scale))
    AWE.Root.Size = UDim2.fromOffset(rootWidth, rootHeight)
end

connect(UserInputService:GetPropertyChangedSignal("TouchEnabled"), applyResponsiveScale)
connect(Workspace:GetPropertyChangedSignal("CurrentCamera"), function() task.defer(applyResponsiveScale) end)

function AWE:TapBurst(button)
    if not self.State.BurstOnTap or self.State.ReducedMotion then return end
    local profile = self:GetProfile()
    local burstCount = profile and profile.BurstCount or 8
    local ripple = make("Frame", {
        AnchorPoint = Vector2.new(0.5,0.5), Position = UDim2.fromScale(0.5,0.5),
        Size = UDim2.fromOffset(4 + burstCount % 5, 4 + burstCount % 5), BackgroundTransparency = 0.45,
        BackgroundColor3 = PALETTE.Accent, BorderSizePixel = 0, ZIndex = 25,
    }, button)
    round(ripple, 30)
    tween(ripple, 0.28, { Size = UDim2.new(1,18 + burstCount,1,18 + burstCount), BackgroundTransparency = 1 })
    task.delay(0.32, function() if ripple.Parent then ripple:Destroy() end end)
end

function AWE:DestroyEffect(name)
    local item = self.EffectInstances[name]
    if item then
        if type(item) == "table" then
            for _, instance in pairs(item) do pcall(function() instance:Destroy() end) end
        else
            pcall(function() item:Destroy() end)
        end
        self.EffectInstances[name] = nil
    end
end

function AWE:DestroyAllEffects()
    local names = {}
    for name in pairs(self.EffectInstances) do table.insert(names, name) end
    for _, name in ipairs(names) do self:DestroyEffect(name) end
end

function AWE:GetRootPart()
    local character = LocalPlayer.Character
    return character and (character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso"))
end

function AWE:GetProfile()
    if self.Active.Effect and self.Catalog.Effects[self.Active.Effect] then return self.Catalog.Effects[self.Active.Effect] end
    for _, profile in pairs(self.Catalog.Effects) do return profile end
    return nil
end

function AWE:ApplyEmitterProfile(emitter, profile, rateOverride)
    if not emitter or not profile then return end
    pcall(function()
        emitter.Color = colorSequence(profile.Color1, profile.Color2)
        local requestedRate = rateOverride or profile.Rate
        if rateOverride then requestedRate = requestedRate * math.clamp(profile.Rate / 10, 0.4, 1.8) end
        requestedRate = requestedRate * (self.State.ParticleBudget or 1)
        emitter.Rate = math.clamp(requestedRate, 0, self.State.Performance == "LOW" and 16 or 100)
        emitter.Lifetime = NumberRange.new(profile.LifetimeMin, profile.LifetimeMax)
        emitter.Speed = NumberRange.new(profile.SpeedMin, profile.SpeedMax)
        emitter.SpreadAngle = Vector2.new(profile.Spread, profile.Spread)
        emitter.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, profile.SizeStart),
            NumberSequenceKeypoint.new(1, profile.SizeEnd),
        })
        emitter.LightEmission = profile.LightEmission
        emitter.Rotation = NumberRange.new(profile.RotMin, profile.RotMax)
        emitter.RotSpeed = NumberRange.new(-profile.RotSpeed, profile.RotSpeed)
        emitter.Drag = profile.Drag
        emitter.Acceleration = Vector3.new(0, profile.AccelerationY, 0)
        emitter.ZOffset = profile.ZOffset
        emitter.Enabled = true
    end)
end

function AWE:CreateEmitter(parent, name, rate)
    local existing = parent and parent:FindFirstChild(name)
    if existing and existing:IsA("ParticleEmitter") then return existing end
    local texture = "rbxasset://textures/particles/sparkles_main.dds"
    local emitter = make("ParticleEmitter", {
        Name = name,
        Texture = texture,
        Enabled = false,
        Rate = rate or 10,
        Lifetime = NumberRange.new(0.7, 1.4),
        Speed = NumberRange.new(0.3, 1.8),
        SpreadAngle = Vector2.new(180,180),
        LightEmission = 0.8,
        EmissionDirection = Enum.NormalId.Top,
        Orientation = Enum.ParticleOrientation.FacingCamera,
        LockedToPart = false,
        RotSpeed = NumberRange.new(-45,45),
        Parent = parent,
    })
    return emitter
end

function AWE:CreateAttachment(root, name, offset)
    local attachment = make("Attachment", { Name = name, Position = offset or Vector3.zero }, root)
    return attachment
end

function AWE:RefreshAvatarAura()
    self:DestroyEffect("AvatarAura")
    if not self.State.AvatarAura then return end
    local root = self:GetRootPart()
    local profile = self:GetProfile()
    if not root or not profile then return end
    local attachment = self:CreateAttachment(root, "AWE_AuraAttachment", Vector3.new(0,0,0))
    local emitter = self:CreateEmitter(attachment, "AWE_AuraEmitter", self.State.AuraRate)
    emitter.Shape = Enum.ParticleEmitterShape.Sphere
    emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
    emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
    self:ApplyEmitterProfile(emitter, profile, self.State.AuraRate)
    emitter.Speed = NumberRange.new(0.15, 0.8)
    emitter.SpreadAngle = Vector2.new(180, 180)
    self.EffectInstances.AvatarAura = { attachment, emitter }
end

function AWE:RefreshAmbientDust()
    self:DestroyEffect("AmbientDust")
    if not self.State.AmbientDust then return end
    local root = self:GetRootPart()
    local profile = self:GetProfile()
    if not root or not profile then return end
    local attachment = self:CreateAttachment(root, "AWE_DustAttachment", Vector3.new(0,1.5,0))
    local emitter = self:CreateEmitter(attachment, "AWE_DustEmitter", self.State.AmbientRate)
    self:ApplyEmitterProfile(emitter, profile, self.State.AmbientRate)
    emitter.Shape = Enum.ParticleEmitterShape.Sphere
    emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
    emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
    emitter.SpreadAngle = Vector2.new(180, 180)
    emitter.Acceleration = Vector3.new(0, 0.15, 0)
    self.EffectInstances.AmbientDust = { attachment, emitter }
end

function AWE:RefreshTrail()
    self:DestroyEffect("AvatarTrail")
    if not self.State.AvatarTrail then return end
    local root = self:GetRootPart()
    local profile = self:GetProfile()
    if not root or not profile then return end
    local a0 = self:CreateAttachment(root, "AWE_TrailTop", Vector3.new(0, 0.8, 0))
    local a1 = self:CreateAttachment(root, "AWE_TrailBottom", Vector3.new(0, -0.8, 0))
    local trail = make("Trail", {
        Name = "AWE_CharacterTrail",
        Attachment0 = a0,
        Attachment1 = a1,
        Lifetime = profile.TrailLifetime,
        MinLength = 0.05,
        FaceCamera = true,
        LightEmission = profile.LightEmission,
        Color = colorSequence(profile.Color1, profile.Color2),
        Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,0.18), NumberSequenceKeypoint.new(1,1) }),
        WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0,0.9), NumberSequenceKeypoint.new(1,0) }),
        Enabled = true,
    }, root)
    self.EffectInstances.AvatarTrail = { a0, a1, trail }
end

function AWE:RefreshHighlight()
    self:DestroyEffect("AvatarHighlight")
    if not self.State.AvatarHighlight then return end
    local character = LocalPlayer.Character
    local profile = self:GetProfile()
    if not character or not profile then return end
    local highlight = make("Highlight", {
        Name = "AWE_LocalHighlight",
        Adornee = character,
        FillColor = profile.Color1,
        OutlineColor = profile.Color2,
        FillTransparency = 0.78,
        OutlineTransparency = 0.06,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
        Enabled = true,
    }, character)
    self.EffectInstances.AvatarHighlight = highlight
end

function AWE:RefreshOrbitMotes()
    self:DestroyEffect("OrbitMotes")
    if not self.State.OrbitMotes then return end
    local root = self:GetRootPart()
    local profile = self:GetProfile()
    if not root or not profile then return end
    local motes = {}
    local count = math.clamp(self.State.OrbitCount, 2, self.State.Performance == "LOW" and 5 or 12)
    for index = 1, count do
        local mote = make("Part", {
            Name = "AWE_OrbitMote_" .. index,
            Shape = Enum.PartType.Ball,
            Size = Vector3.new(profile.MoteSize, profile.MoteSize, profile.MoteSize),
            Material = Enum.Material.Neon,
            Color = index % 2 == 0 and profile.Color1 or profile.Color2,
            Transparency = 0.12,
            Anchored = true,
            CanCollide = false,
            CanTouch = false,
            CanQuery = false,
            CastShadow = false,
        }, Workspace)
        table.insert(motes, mote)
    end
    self.EffectInstances.OrbitMotes = motes
end

function AWE:RefreshAllAvatarEffects()
    self:RefreshAvatarAura()
    self:RefreshAmbientDust()
    self:RefreshTrail()
    self:RefreshHighlight()
    self:RefreshOrbitMotes()
end

function AWE:SetEffectProfile(key)
    local profile = self.Catalog.Effects[key]
    if not profile then return false end
    self.Active.Effect = key
    self:RefreshAllAvatarEffects()
    self:RefreshLightingFx()
    showNotice("Effect profile: " .. profile.Name, 2)
    return true
end

function AWE:ApplyActiveThemeAccent(color)
    if not self.State.ThemeLocksAccent then setAccent(color) end
end

function AWE:CreateLightFx(className, name, properties, enabled)
    local fx = Lighting:FindFirstChild(name)
    if not fx or not fx:IsA(className) then
        if fx then fx:Destroy() end
        fx = make(className, { Name = name, Enabled = false }, Lighting)
    end
    for key, value in pairs(properties or {}) do pcall(function() fx[key] = value end) end
    fx.Enabled = not not enabled
    self.EffectInstances[name] = fx
    return fx
end

function AWE:RefreshLightingFx()
    local profile = self:GetProfile()
    local accent = profile and profile.Color1 or self.State.CustomAccent
    self:CreateLightFx("BloomEffect", "AWE_Bloom", {
        Intensity = 0.9 * self.State.GlowStrength,
        Size = 32,
        Threshold = 0.86,
    }, self.State.Bloom and self.State.Glow)
    self:CreateLightFx("ColorCorrectionEffect", "AWE_ColorGrade", {
        Brightness = self.State.BrightnessBoost and 0.04 or 0,
        Contrast = self.State.ColorGrade and 0.12 or (self.State.SceneContrast or 0),
        Saturation = self.State.ColorGrade and 0.08 or (self.State.SceneSaturation or 0),
        TintColor = self.State.SceneTint or accent:Lerp(Color3.new(1,1,1), 0.72),
    }, self.State.ColorGrade or self.State.BrightnessBoost)
    self:CreateLightFx("BlurEffect", "AWE_SoftBlur", { Size = self.State.Blur and 3 or 0 }, self.State.Blur)
    self:CreateLightFx("SunRaysEffect", "AWE_SunRays", { Intensity = 0.08 * self.State.GlowStrength, Spread = 0.7 }, self.State.SunRays)
    self:CreateLightFx("DepthOfFieldEffect", "AWE_DepthOfField", {
        FarIntensity = 0.12, NearIntensity = 0.02, FocusDistance = 30, InFocusRadius = 45,
    }, self.State.DepthOfField)
    if self.State.Atmosphere then
        local atmosphere = Lighting:FindFirstChild("AWE_Atmosphere")
        if not atmosphere or not atmosphere:IsA("Atmosphere") then atmosphere = make("Atmosphere", { Name="AWE_Atmosphere" }, Lighting) end
        atmosphere.Color = accent:Lerp(Color3.new(1,1,1), 0.54)
        atmosphere.Decay = accent:Lerp(Color3.fromRGB(160,190,220), 0.5)
        atmosphere.Density = self.State.SceneDensity or 0.22
        atmosphere.Offset = 0.1
        atmosphere.Glare = self.State.SceneGlare or 0.18
        atmosphere.Haze = self.State.SceneHaze or 1.1
        self.EffectInstances.AWE_Atmosphere = atmosphere
        atmosphere.Enabled = true
    else
        local atmosphere = Lighting:FindFirstChild("AWE_Atmosphere")
        if atmosphere then atmosphere.Enabled = false end
    end
end

function AWE:ApplyScene(key)
    local preset = self.Catalog.Scenes[key]
    if not preset then return false end
    self.Active.Scene = key
    local map = {
        Brightness = preset.Brightness,
        ClockTime = preset.ClockTime,
        ExposureCompensation = preset.Exposure,
        Ambient = preset.Ambient,
        OutdoorAmbient = preset.OutdoorAmbient,
        FogColor = preset.FogColor,
        FogStart = preset.FogStart,
        FogEnd = preset.FogEnd,
        EnvironmentDiffuseScale = preset.Diffuse,
        EnvironmentSpecularScale = preset.Specular,
    }
    for property, value in pairs(map) do pcall(function() Lighting[property] = value end) end
    self.State.SceneTint = preset.Tint
    self.State.SceneContrast = preset.Contrast
    self.State.SceneSaturation = preset.Saturation
    self.State.SceneDensity = preset.AtmosphereDensity
    self.State.SceneHaze = preset.Haze
    self.State.SceneGlare = preset.Glare
    self.State.Atmosphere = preset.AtmosphereOn
    self:RefreshLightingFx()
    showNotice("Scene preset applied: " .. preset.Name, 2.2)
    return true
end

function AWE:RestoreLighting()
    self.Active.Scene = nil
    self.State.Bloom = false
    self.State.ColorGrade = false
    self.State.Blur = false
    self.State.SunRays = false
    self.State.DepthOfField = false
    self.State.Atmosphere = false
    self.State.BrightnessBoost = false
    self.State.SceneTint = nil
    self.State.SceneContrast = nil
    self.State.SceneSaturation = nil
    self.State.SceneDensity = nil
    self.State.SceneHaze = nil
    self.State.SceneGlare = nil
    for property, value in pairs(ORIG.Lighting) do pcall(function() Lighting[property] = value end) end
    for _, name in ipairs({ "AWE_Bloom", "AWE_ColorGrade", "AWE_SoftBlur", "AWE_SunRays", "AWE_DepthOfField", "AWE_Atmosphere" }) do
        local object = Lighting:FindFirstChild(name)
        if object then pcall(function() object:Destroy() end) end
    end
    if type(self.SyncControlsFromState) == "function" then self:SyncControlsFromState() end
end

function AWE:ResetVisuals()
    self.State.Bloom = false
    self.State.ColorGrade = false
    self.State.Blur = false
    self.State.SunRays = false
    self.State.DepthOfField = false
    self.State.Atmosphere = false
    self.State.AvatarAura = false
    self.State.AvatarTrail = false
    self.State.AvatarHighlight = false
    self.State.OrbitMotes = false
    self.State.AmbientDust = false
    self.State.BackgroundParticles = false
    self.State.BurstOnTap = false
    self:RefreshLightingFx()
    self:RefreshAllAvatarEffects()
    self:RestoreLighting()
    if type(self.SyncControlsFromState) == "function" then self:SyncControlsFromState() end
    if self.DecorLayer then self.DecorLayer.Visible = self.State.BackgroundParticles end
    showNotice("Visual effects disabled and lighting restored", 2.5)
end

-- Optional persistence: available only where executor file APIs exist.
local SAVE_PATH = "AquamarineWhiteEdition_v4.json"
function AWE:SaveSettings()
    local snapshot = {}
    for key, value in pairs(self.State) do
        if type(value) == "boolean" or type(value) == "number" or type(value) == "string" then snapshot[key] = value end
    end
    snapshot.Theme = self.Active.Theme
    snapshot.Effect = self.Active.Effect
    snapshot.Scene = self.Active.Scene
    snapshot.ThemeColors = {}
    for role, color in pairs(PALETTE) do snapshot.ThemeColors[role] = colorHex(color) end
    local okEncode, json = pcall(function() return HttpService:JSONEncode(snapshot) end)
    if not okEncode then showNotice("Could not encode settings", 2); return false end
    if type(writefile) == "function" then
        local ok = pcall(writefile, SAVE_PATH, json)
        if ok then showNotice("Settings saved to " .. SAVE_PATH, 2.4); return true end
    end
    ENV.__AWE_LOCAL_SETTINGS = snapshot
    showNotice("Saved for this executor session (file API unavailable)", 2.5)
    return true
end

function AWE:LoadSettings()
    local snapshot
    if type(readfile) == "function" and type(isfile) == "function" then
        local ok, exists = pcall(isfile, SAVE_PATH)
        if ok and exists then
            local readOk, contents = pcall(readfile, SAVE_PATH)
            if readOk then pcall(function() snapshot = HttpService:JSONDecode(contents) end) end
        end
    end
    if type(snapshot) ~= "table" and type(ENV.__AWE_LOCAL_SETTINGS) == "table" then snapshot = ENV.__AWE_LOCAL_SETTINGS end
    if type(snapshot) ~= "table" then return false end
    for key, value in pairs(snapshot) do
        if self.State[key] ~= nil and type(self.State[key]) == type(value) then self.State[key] = value end
    end
    if snapshot.Effect and self.Catalog.Effects[snapshot.Effect] then self.Active.Effect = snapshot.Effect end
    if snapshot.Theme and self.Catalog.Themes[snapshot.Theme] then self.Active.Theme = snapshot.Theme end
    if snapshot.Scene and self.Catalog.Scenes[snapshot.Scene] then self.Active.Scene = snapshot.Scene end
    if self.Active.Theme and self.Catalog.Themes[self.Active.Theme] then self:ApplyTheme(self.Active.Theme) end
    if type(snapshot.ThemeColors) == "table" then
        for role, hex in pairs(snapshot.ThemeColors) do
            if PALETTE[role] and type(hex) == "string" then
                local r, g, b = string.match(hex, "^#?(%x%x)(%x%x)(%x%x)$")
                if r and g and b then setThemeColor(role, Color3.fromRGB(tonumber(r,16), tonumber(g,16), tonumber(b,16))) end
            end
        end
    end
    if type(self.SyncControlsFromState) == "function" then self:SyncControlsFromState() end
    if self.Root and self.Root.Parent then self.Root.BackgroundTransparency = self.State.Transparency end
    if type(self.RefreshLightingFx) == "function" then self:RefreshLightingFx() end
    if type(self.RefreshAllAvatarEffects) == "function" then self:RefreshAllAvatarEffects() end
    return true
end

function AWE:ApplyTheme(key)
    local theme = self.Catalog.Themes[key]
    if not theme then return false end
    self.Active.Theme = key
    local map = {
        Window = theme.Window, Panel = theme.Panel, Card = theme.Card,
        Text = theme.Text, Muted = theme.Muted, Accent = theme.Accent,
        Accent2 = theme.Accent2, Border = theme.Border, Selected = theme.Selected,
        Track = theme.Track, Danger = theme.Danger,
    }
    for role, color in pairs(map) do setThemeColor(role, color) end
    self.State.CustomAccent = theme.Accent
    showNotice("Theme applied: " .. theme.Name, 2)
    return true
end

function AWE:SetPerformance(level)
    level = string.upper(tostring(level or "MEDIUM"))
    if level ~= "LOW" and level ~= "MEDIUM" and level ~= "HIGH" then level = "MEDIUM" end
    self.State.Performance = level
    if level == "LOW" then
        self.State.ParticleBudget = 0.45
        self.State.OrbitCount = math.min(self.State.OrbitCount, 4)
    elseif level == "MEDIUM" then
        self.State.ParticleBudget = 1
    else
        self.State.ParticleBudget = 1.5
    end
    self:RefreshAllAvatarEffects()
    self:RefreshLightingFx()
    showNotice("Performance profile: " .. level, 1.8)
end

function AWE:SyncControlsFromState()
    local titleToState = {
        ["Bloom glow"] = "Bloom", ["Bloom"] = "Bloom",
        ["Ambient dust"] = "AmbientDust", ["Pearl aura"] = "AvatarAura",
        ["Particle aura"] = "AvatarAura", ["Prismatic trail"] = "AvatarTrail",
        ["Movement trail"] = "AvatarTrail", ["Pearl outline"] = "AvatarHighlight",
        ["Orbiting motes"] = "OrbitMotes", ["Color grade"] = "ColorGrade",
        ["Soft blur"] = "Blur", ["Sun rays"] = "SunRays",
        ["Depth of field"] = "DepthOfField", ["Aquamarine atmosphere"] = "Atmosphere",
        ["Brightness boost"] = "BrightnessBoost", ["Reduced motion"] = "ReducedMotion",
        ["Tap ripple"] = "BurstOnTap", ["Soft glow master switch"] = "Glow",
        ["Floating UI motes"] = "BackgroundParticles",
    }
    for _, control in ipairs(self.ToggleControls) do
        local stateKey = titleToState[control.Title]
        if stateKey and self.State[stateKey] ~= nil then control.Set(self.State[stateKey], false) end
    end
end

-- UI pages
local home = pageScroll("HOME", "Welcome back", "A QUIET, PEARL-WHITE VISUAL WORKSPACE")
local effectsPage = pageScroll("EFFECTS", "Effect library", "SEARCH AND APPLY LOCAL PARTICLE PROFILES")
local worldPage = pageScroll("WORLD", "World atmosphere", "CLIENT-SIDE LIGHTING AND COLOR TREATMENT")
local avatarPage = pageScroll("AVATAR", "Avatar cosmetics", "LOCAL CHARACTER DECORATION ONLY")
local themesPage = pageScroll("THEMES", "Theme studio", "PALETTES FOR ALL UI COLOR ROLES")
local scenesPage = pageScroll("SCENES", "Scene presets", "LIGHTING PRESETS WITH RESTORE SUPPORT")
local settingsPage = pageScroll("SETTINGS", "Preferences", "TOUCH, SCALE, MOTION AND PERSISTENCE")
local performancePage = pageScroll("PERFORMANCE", "Performance lab", "KEEP EFFECTS RESPONSIVE ON MOBILE")

local function sectionButtonGrid(parent, items, columns)
    local holder = make("Frame", { Size = UDim2.new(1,0,0,36), BackgroundTransparency = 1, ZIndex = 9 }, parent)
    local grid = make("UIGridLayout", {
        CellPadding = UDim2.fromOffset(6,6),
        CellSize = UDim2.new(1 / (columns or 2), -4, 0, 34),
        FillDirectionMaxCells = columns or 2,
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, holder)
    for index, item in ipairs(items) do
        local button = make("TextButton", {
            LayoutOrder = index,
            BackgroundColor3 = PALETTE.Panel,
            BorderSizePixel = 0,
            Text = item.Text,
            TextColor3 = PALETTE.Text,
            Font = Enum.Font.GothamSemibold,
            TextSize = 9,
            TextWrapped = true,
            AutoButtonColor = false,
            ZIndex = 10,
        }, holder)
        round(button, 9); stroke(button, PALETTE.Border, 1, 0.2); paint(button,"Panel"); themeText(button)
        connect(button.Activated, item.Callback)
    end
    grid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        holder.Size = UDim2.new(1,0,0,grid.AbsoluteContentSize.Y)
    end)
    task.defer(function() holder.Size = UDim2.new(1,0,0,grid.AbsoluteContentSize.Y) end)
    return holder
end

local homeHero = section(home, "AQUAMARINE WHITE", "Soft light, gentle motion and live local visual controls")
local heroText = label(homeHero, "A mobile-first visual layer built around clean glass panels, custom palettes and independent effects. Tap a category on the left to open its controls.", 48)
local statusLine = label(homeHero, "Status: ready", 20)
sectionButtonGrid(homeHero, {
    { Text = "ENABLE SOFT GLOW", Callback = function() AWE.State.Glow = true; AWE.State.Bloom = true; AWE:RefreshLightingFx(); showNotice("Soft glow enabled", 1.7) end },
    { Text = "DISABLE ALL FX", Callback = function() AWE:ResetVisuals() end },
}, 2)

local homeQuick = section(home, "QUICK CONTROLS", "Frequently used local effects")
local quickBloom = toggleRow(homeQuick, "Bloom glow", "Soft highlights around bright objects", AWE.State.Bloom, function(v) AWE.State.Bloom=v; AWE:RefreshLightingFx() end)
local quickDust = toggleRow(homeQuick, "Ambient dust", "Small local particles around your character", AWE.State.AmbientDust, function(v) AWE.State.AmbientDust=v; AWE:RefreshAmbientDust() end)
local quickAura = toggleRow(homeQuick, "Pearl aura", "A configurable particle halo around your avatar", AWE.State.AvatarAura, function(v) AWE.State.AvatarAura=v; AWE:RefreshAvatarAura() end)
local quickTrail = toggleRow(homeQuick, "Prismatic trail", "A two-tone trail following local movement", AWE.State.AvatarTrail, function(v) AWE.State.AvatarTrail=v; AWE:RefreshTrail() end)
toggleRow(homeQuick, "Floating UI motes", "Tiny pearl particles drifting behind panels", AWE.State.BackgroundParticles, function(v) AWE.State.BackgroundParticles=v; if AWE.DecorLayer then AWE.DecorLayer.Visible=v end end)

local homeActions = section(home, "SESSION ACTIONS", "Small quality-of-life controls")
sectionButtonGrid(homeActions, {
    { Text="SAVE SETTINGS", Callback=function() AWE:SaveSettings() end },
    { Text="RESTORE LIGHTING", Callback=function() AWE:RestoreLighting(); showNotice("Original lighting restored", 2) end },
    { Text="RANDOM EFFECT", Callback=function() local keys={}; for key in pairs(AWE.Catalog.Effects) do table.insert(keys,key) end; if #keys>0 then AWE:SetEffectProfile(keys[math.random(1,#keys)]) end end },
    { Text="RANDOM THEME", Callback=function() local keys={}; for key in pairs(AWE.Catalog.Themes) do table.insert(keys,key) end; if #keys>0 then AWE:ApplyTheme(keys[math.random(1,#keys)]) end end },
}, 2)

local fxSection = section(effectsPage, "PROFILE SELECTOR", "A searchable library; selecting a profile refreshes active visuals")
local effectSearch = searchBox(fxSection, "Search effects: pearl, aurora, stars...")
local effectCount = label(fxSection, "Catalog loading...", 17)
local effectResults = make("Frame", { Size = UDim2.new(1,0,0,10), AutomaticSize=Enum.AutomaticSize.Y, BackgroundTransparency=1, ZIndex=9 }, fxSection)
local effectListLayout = listLayout(effectResults, Enum.FillDirection.Vertical, 5)
local effectPageOffset = 0
local effectNextButton = actionButton(fxSection, "SHOW NEXT RESULTS", function() end)
local activeProfileLabel = label(fxSection, "Active profile: default", 28)
local fxControls = section(effectsPage, "EMISSION CONTROLS", "Changes apply to enabled emitters")
sliderRow(fxControls, "Aura particle rate", 1, 60, AWE.State.AuraRate, 0, function(v) AWE.State.AuraRate=v; if AWE.State.AvatarAura then AWE:RefreshAvatarAura() end end, "/s")
sliderRow(fxControls, "Ambient particle rate", 0, 40, AWE.State.AmbientRate, 0, function(v) AWE.State.AmbientRate=v; if AWE.State.AmbientDust then AWE:RefreshAmbientDust() end end, "/s")
sliderRow(fxControls, "Orbit count", 2, 12, AWE.State.OrbitCount, 0, function(v) AWE.State.OrbitCount=v; if AWE.State.OrbitMotes then AWE:RefreshOrbitMotes() end end, " motes")
sliderRow(fxControls, "Orbit speed", 0.2, 3, AWE.State.OrbitSpeed, 1, function(v) AWE.State.OrbitSpeed=v end, "x")

local worldSection = section(worldPage, "LIGHTING LAYERS", "Post-processing is client-side and can be turned off")
toggleRow(worldSection, "Bloom", "Soft glow highlights", AWE.State.Bloom, function(v) AWE.State.Bloom=v; AWE:RefreshLightingFx() end)
toggleRow(worldSection, "Color grade", "Gentle contrast, saturation and tint", AWE.State.ColorGrade, function(v) AWE.State.ColorGrade=v; AWE:RefreshLightingFx() end)
toggleRow(worldSection, "Soft blur", "Subtle background softening", AWE.State.Blur, function(v) AWE.State.Blur=v; AWE:RefreshLightingFx() end)
toggleRow(worldSection, "Sun rays", "Light shafts when scene lighting supports them", AWE.State.SunRays, function(v) AWE.State.SunRays=v; AWE:RefreshLightingFx() end)
toggleRow(worldSection, "Depth of field", "Mild cinematic focus", AWE.State.DepthOfField, function(v) AWE.State.DepthOfField=v; AWE:RefreshLightingFx() end)
toggleRow(worldSection, "Aquamarine atmosphere", "Adds a separate, toggleable Atmosphere instance", AWE.State.Atmosphere, function(v) AWE.State.Atmosphere=v; AWE:RefreshLightingFx() end)
toggleRow(worldSection, "Brightness boost", "A small local brightness adjustment", AWE.State.BrightnessBoost, function(v) AWE.State.BrightnessBoost=v; AWE:RefreshLightingFx() end)
sliderRow(worldSection, "Glow strength", 0.2, 2.5, AWE.State.GlowStrength, 1, function(v) AWE.State.GlowStrength=v; AWE:RefreshLightingFx() end, "x")

local worldActions = section(worldPage, "WORLD ACTIONS", "Apply presets from the Scene Presets page")
sectionButtonGrid(worldActions, {
    { Text="RESTORE ORIGINAL", Callback=function() AWE:RestoreLighting() end },
    { Text="REBUILD FX", Callback=function() AWE:RefreshLightingFx(); showNotice("Lighting effects refreshed", 1.5) end },
}, 2)

local avSection = section(avatarPage, "LOCAL AVATAR FX", "Only decorative objects attached to your local character")
toggleRow(avSection, "Particle aura", "A soft halo emitter around the root", AWE.State.AvatarAura, function(v) AWE.State.AvatarAura=v; AWE:RefreshAvatarAura() end)
toggleRow(avSection, "Movement trail", "Two-color trail behind your character", AWE.State.AvatarTrail, function(v) AWE.State.AvatarTrail=v; AWE:RefreshTrail() end)
toggleRow(avSection, "Pearl outline", "Local Highlight on your own character", AWE.State.AvatarHighlight, function(v) AWE.State.AvatarHighlight=v; AWE:RefreshHighlight() end)
toggleRow(avSection, "Orbiting motes", "Neon spheres orbiting the local character", AWE.State.OrbitMotes, function(v) AWE.State.OrbitMotes=v; AWE:RefreshOrbitMotes() end)
toggleRow(avSection, "Ambient dust", "Local spark particles around your avatar", AWE.State.AmbientDust, function(v) AWE.State.AmbientDust=v; AWE:RefreshAmbientDust() end)
local avTuning = section(avatarPage, "APPEARANCE TUNING", "Choose a profile in Effect Library first")
sliderRow(avTuning, "Aura rate", 1, 60, AWE.State.AuraRate, 0, function(v) AWE.State.AuraRate=v; if AWE.State.AvatarAura then AWE:RefreshAvatarAura() end end, "/s")
sliderRow(avTuning, "Orbit motes", 2, 12, AWE.State.OrbitCount, 0, function(v) AWE.State.OrbitCount=v; if AWE.State.OrbitMotes then AWE:RefreshOrbitMotes() end end, "")

local themeSection = section(themesPage, "PALETTE LIBRARY", "Applies a complete color set to UI roles")
local themeSearch = searchBox(themeSection, "Search themes: ice, pearl, dusk...")
local themeCount = label(themeSection, "Catalog loading...", 17)
local themeResults = make("Frame", { Size = UDim2.new(1,0,0,10), AutomaticSize=Enum.AutomaticSize.Y, BackgroundTransparency=1, ZIndex=9 }, themeSection)
listLayout(themeResults, Enum.FillDirection.Vertical, 5)
local themeOffset = 0
local themeNextButton = actionButton(themeSection, "SHOW NEXT THEMES", function() end)
local themeFine = section(themesPage, "COLOR ROLE STUDIO", "Edit any UI color role; changes can be saved with settings")
local roleNameBox = searchBox(themeFine, "Role: Window, Panel, Card, Text, Muted, Accent...")
roleNameBox.Text = "Accent"
local accentSample = make("Frame", { Size = UDim2.new(1,0,0,24), BackgroundColor3=AWE.State.CustomAccent, BorderSizePixel=0, ZIndex=10 }, themeFine)
round(accentSample, 8)
local draftRole = "Accent"
local draftR, draftG, draftB = 100, 233, 244
local roleRSlider, roleGSlider, roleBSlider
local function updateRoleDraft()
    accentSample.BackgroundColor3 = rgb(draftR,draftG,draftB)
end
roleRSlider = sliderRow(themeFine, "Red component", 0, 255, draftR, 0, function(v) draftR=v; updateRoleDraft() end, "")
roleGSlider = sliderRow(themeFine, "Green component", 0, 255, draftG, 0, function(v) draftG=v; updateRoleDraft() end, "")
roleBSlider = sliderRow(themeFine, "Blue component", 0, 255, draftB, 0, function(v) draftB=v; updateRoleDraft() end, "")
actionButton(themeFine, "LOAD SELECTED ROLE", function()
    local requested = string.gsub(roleNameBox.Text, "%s+", "")
    if not PALETTE[requested] then showNotice("Unknown role. Try Window, Panel, Card, Text, Muted, Accent, Accent2, Border, Selected, Track or Danger.", 3); return end
    draftRole = requested
    local current = PALETTE[draftRole]
    draftR, draftG, draftB = math.floor(current.R*255+0.5), math.floor(current.G*255+0.5), math.floor(current.B*255+0.5)
    roleRSlider.Set(draftR, false); roleGSlider.Set(draftG, false); roleBSlider.Set(draftB, false)
    accentSample.BackgroundColor3 = current
    showNotice("Editing role: " .. draftRole, 1.6)
end)
actionButton(themeFine, "APPLY COLOR TO ROLE", function()
    local requested = string.gsub(roleNameBox.Text, "%s+", "")
    if not PALETTE[requested] then showNotice("Unknown color role", 2); return end
    draftRole = requested
    local color = rgb(draftR,draftG,draftB)
    setThemeColor(draftRole, color)
    if draftRole == "Accent" then AWE.State.CustomAccent = color end
    accentSample.BackgroundColor3 = color
    showNotice("Applied " .. draftRole .. " " .. colorHex(color), 2)
end)

local sceneSection = section(scenesPage, "ENVIRONMENT PRESETS", "Searchable local Lighting configurations")
local sceneSearch = searchBox(sceneSection, "Search scenes: dawn, moon, frost...")
local sceneCount = label(sceneSection, "Catalog loading...", 17)
local sceneResults = make("Frame", { Size = UDim2.new(1,0,0,10), AutomaticSize=Enum.AutomaticSize.Y, BackgroundTransparency=1, ZIndex=9 }, sceneSection)
listLayout(sceneResults, Enum.FillDirection.Vertical, 5)
local sceneOffset = 0
local sceneNextButton = actionButton(sceneSection, "SHOW NEXT SCENES", function() end)
actionButton(sceneSection, "RESTORE STARTING LIGHTING", function() AWE:RestoreLighting(); AWE.Active.Scene=nil; showNotice("Lighting restored", 2) end)

local settingsSection = section(settingsPage, "INTERFACE", "Designed for thumb controls and smaller screens")
sliderRow(settingsSection, "Window scale", 0.55, 1.15, AWE.State.Scale, 2, function(v) AWE.State.Scale=v; applyResponsiveScale() end, "x")
sliderRow(settingsSection, "Panel transparency", 0, 0.25, AWE.State.Transparency, 2, function(v) AWE.State.Transparency=v; AWE.Root.BackgroundTransparency=v end, "")
toggleRow(settingsSection, "Reduced motion", "Disable most movement animations", AWE.State.ReducedMotion, function(v) AWE.State.ReducedMotion=v end)
toggleRow(settingsSection, "Tap ripple", "Small decorative ripple on button taps", AWE.State.BurstOnTap, function(v) AWE.State.BurstOnTap=v end)
toggleRow(settingsSection, "Soft glow master switch", "Master control for bloom/glow behavior", AWE.State.Glow, function(v) AWE.State.Glow=v; AWE:RefreshLightingFx() end)
local settingsActions = section(settingsPage, "SETTINGS STORAGE", "Uses executor file functions only if available")
sectionButtonGrid(settingsActions, {
    { Text="SAVE SETTINGS", Callback=function() AWE:SaveSettings() end },
    { Text="RELOAD SETTINGS", Callback=function() if AWE:LoadSettings() then showNotice("Settings loaded. Reopen page to refresh controls.",2.2) else showNotice("No saved settings found",2) end end },
    { Text="RESET VISUALS", Callback=function() AWE:ResetVisuals() end },
    { Text="RESTORE DEFAULT THEME", Callback=function() for key,theme in pairs(AWE.Catalog.Themes) do if theme.Name=="White Pearl Default" then AWE:ApplyTheme(key); break end end end },
}, 2)

local perfSection = section(performancePage, "QUALITY PRESETS", "Lower budgets reduce moving particles and orbit parts")
sectionButtonGrid(perfSection, {
    { Text="LOW", Callback=function() AWE:SetPerformance("LOW") end },
    { Text="MEDIUM", Callback=function() AWE:SetPerformance("MEDIUM") end },
    { Text="HIGH", Callback=function() AWE:SetPerformance("HIGH") end },
}, 3)
local budgetLabel = label(perfSection, "Profile: " .. AWE.State.Performance, 22)
local perfMore = section(performancePage, "DIAGNOSTICS", "Lightweight runtime information")
local diagText = label(perfMore, "Waiting for first sample...", 64)
actionButton(perfMore, "REFRESH DIAGNOSTICS", function()
    local camera = Workspace.CurrentCamera
    local size = camera and camera.ViewportSize or Vector2.new(0,0)
    local effectCountValue = 0
    for _ in pairs(AWE.EffectInstances) do effectCountValue=effectCountValue+1 end
    diagText.Text = string.format("Version: %s\nViewport: %d × %d\nTracked effect groups: %d\nProfile catalog: %d FX / %d scenes / %d themes",
        AWE.Version, size.X, size.Y, effectCountValue,
        #AWE.Catalog.EffectOrder, #AWE.Catalog.SceneOrder, #AWE.Catalog.ThemeOrder)
end)

local tabDefinitions = {
    { Key="HOME", Icon="⌂", Label="Home" },
    { Key="EFFECTS", Icon="✧", Label="Effects" },
    { Key="WORLD", Icon="◌", Label="World" },
    { Key="AVATAR", Icon="◇", Label="Avatar" },
    { Key="THEMES", Icon="◈", Label="Themes" },
    { Key="SCENES", Icon="☼", Label="Scenes" },
    { Key="SETTINGS", Icon="⚙", Label="Settings" },
    { Key="PERFORMANCE", Icon="▦", Label="Perf" },
}

function AWE:SelectTab(key)
    if not self.Pages[key] then return end
    self.Active.Tab = key
    for pageKey, page in pairs(self.Pages) do page.Visible = pageKey == key end
    for tabKey, button in pairs(self.TabButtons) do
        local selected = tabKey == key
        tween(button, 0.12, { BackgroundColor3 = selected and PALETTE.Selected or PALETTE.Panel })
        local icon = button:FindFirstChild("IconLabel")
        local caption = button:FindFirstChild("Caption")
        if icon then icon.TextColor3 = selected and PALETTE.Accent or PALETTE.Muted end
        if caption then caption.TextColor3 = selected and PALETTE.Text or PALETTE.Muted end
    end
end

for _, definition in ipairs(tabDefinitions) do
    local button = make("TextButton", {
        Name = "Tab_" .. definition.Key,
        Size = UDim2.new(1,0,0,42),
        BackgroundColor3 = PALETTE.Panel,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 8,
    }, AWE.SidebarList)
    round(button, 10); paint(button,"Panel")
    local icon = make("TextLabel", { Name="IconLabel", Position=UDim2.fromOffset(0,4), Size=UDim2.new(1,0,0,19), BackgroundTransparency=1, Text=definition.Icon, TextColor3=PALETTE.Muted, Font=Enum.Font.GothamBold, TextSize=15, ZIndex=9 }, button)
    local caption = make("TextLabel", { Name="Caption", Position=UDim2.fromOffset(0,22), Size=UDim2.new(1,0,0,14), BackgroundTransparency=1, Text=definition.Label, TextColor3=PALETTE.Muted, Font=Enum.Font.GothamMedium, TextSize=8, ZIndex=9 }, button)
    connect(button.Activated, function() AWE:SelectTab(definition.Key) end)
    AWE.TabButtons[definition.Key] = button
end

-- The effect registry below is generated as data, not filler; UI selectors and effect
-- engines consume every entry. It is intentionally local and self-contained.

AWE.Catalog.EffectOrder = {}
AWE.Catalog.Effects["FX_001"] = {
    Key = "FX_001",
    Name = "Pearl Bloom 001",
    Category = "Bloom",
    Description = "Pearl bloom cosmetic profile 001",
    Color1 = rgb(247, 255, 255),
    Color2 = rgb(104, 220, 236),
    Rate = 10,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 3.05,
    Spread = 90,
    SizeStart = 0.3,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 27,
    Drag = 0.45,
    AccelerationY = -0.2,
    AuraRadius = 2.17,
    OrbitSpeed = 1.39,
    OrbitCount = 4,
    TrailLifetime = 0.46,
    BurstCount = 7,
    MoteSize = 0.19,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_001")

AWE.Catalog.Effects["FX_002"] = {
    Key = "FX_002",
    Name = "Aurora Bloom 002",
    Category = "Bloom",
    Description = "Aurora bloom cosmetic profile 002",
    Color1 = rgb(97, 237, 223),
    Color2 = rgb(115, 151, 255),
    Rate = 17,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 3.22,
    Spread = 120,
    SizeStart = 0.47,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 36,
    Drag = 0.9,
    AccelerationY = 0.3,
    AuraRadius = 2.94,
    OrbitSpeed = 0.43,
    OrbitCount = 5,
    TrailLifetime = 0.67,
    BurstCount = 10,
    MoteSize = 0.26,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_002")

AWE.Catalog.Effects["FX_003"] = {
    Key = "FX_003",
    Name = "Moonlight Bloom 003",
    Category = "Bloom",
    Description = "Moonlight bloom cosmetic profile 003",
    Color1 = rgb(238, 247, 255),
    Color2 = rgb(160, 183, 251),
    Rate = 9,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 2.43,
    Spread = 150,
    SizeStart = 0.15,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 45,
    Drag = 0.15,
    AccelerationY = -0.7,
    AuraRadius = 1.73,
    OrbitSpeed = 1.47,
    OrbitCount = 6,
    TrailLifetime = 0.88,
    BurstCount = 13,
    MoteSize = 0.33,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_003")

AWE.Catalog.Effects["FX_004"] = {
    Key = "FX_004",
    Name = "Rose Quartz Bloom 004",
    Category = "Bloom",
    Description = "Rose Quartz bloom cosmetic profile 004",
    Color1 = rgb(251, 206, 228),
    Color2 = rgb(241, 134, 195),
    Rate = 16,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 2.6,
    Spread = 180,
    SizeStart = 0.33,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 54,
    Drag = 0.6,
    AccelerationY = -0.2,
    AuraRadius = 2.5,
    OrbitSpeed = 0.51,
    OrbitCount = 7,
    TrailLifetime = 1.09,
    BurstCount = 16,
    MoteSize = 0.4,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_004")

AWE.Catalog.Effects["FX_005"] = {
    Key = "FX_005",
    Name = "Starlace Bloom 005",
    Category = "Bloom",
    Description = "Starlace bloom cosmetic profile 005",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(182, 215, 248),
    Rate = 8,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.77,
    Spread = 60,
    SizeStart = 0.51,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 63,
    Drag = 1.05,
    AccelerationY = 0.3,
    AuraRadius = 3.27,
    OrbitSpeed = 1.55,
    OrbitCount = 8,
    TrailLifetime = 0.39,
    BurstCount = 19,
    MoteSize = 0.15,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_005")

AWE.Catalog.Effects["FX_006"] = {
    Key = "FX_006",
    Name = "Glacier Bloom 006",
    Category = "Bloom",
    Description = "Glacier bloom cosmetic profile 006",
    Color1 = rgb(201, 249, 255),
    Color2 = rgb(73, 184, 234),
    Rate = 15,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.98,
    Spread = 90,
    SizeStart = 0.19,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 72,
    Drag = 0.3,
    AccelerationY = -0.7,
    AuraRadius = 2.06,
    OrbitSpeed = 0.59,
    OrbitCount = 9,
    TrailLifetime = 0.6,
    BurstCount = 22,
    MoteSize = 0.23,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_006")

AWE.Catalog.Effects["FX_007"] = {
    Key = "FX_007",
    Name = "Opaline Bloom 007",
    Category = "Bloom",
    Description = "Opaline bloom cosmetic profile 007",
    Color1 = rgb(234, 213, 244),
    Color2 = rgb(183, 159, 255),
    Rate = 7,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.15,
    Spread = 120,
    SizeStart = 0.36,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 81,
    Drag = 0.75,
    AccelerationY = -0.2,
    AuraRadius = 2.83,
    OrbitSpeed = 1.63,
    OrbitCount = 10,
    TrailLifetime = 0.81,
    BurstCount = 4,
    MoteSize = 0.3,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_007")

AWE.Catalog.Effects["FX_008"] = {
    Key = "FX_008",
    Name = "Sea Glass Bloom 008",
    Category = "Bloom",
    Description = "Sea Glass bloom cosmetic profile 008",
    Color1 = rgb(190, 255, 245),
    Color2 = rgb(48, 202, 176),
    Rate = 14,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 1.36,
    Spread = 150,
    SizeStart = 0.54,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 90,
    Drag = 0.0,
    AccelerationY = 0.3,
    AuraRadius = 1.62,
    OrbitSpeed = 0.67,
    OrbitCount = 3,
    TrailLifetime = 1.02,
    BurstCount = 7,
    MoteSize = 0.36,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_008")

AWE.Catalog.Effects["FX_009"] = {
    Key = "FX_009",
    Name = "Halo Bloom 009",
    Category = "Bloom",
    Description = "Halo bloom cosmetic profile 009",
    Color1 = rgb(249, 239, 201),
    Color2 = rgb(255, 217, 126),
    Rate = 6,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 1.53,
    Spread = 180,
    SizeStart = 0.23,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 99,
    Drag = 0.45,
    AccelerationY = -0.7,
    AuraRadius = 2.39,
    OrbitSpeed = 1.71,
    OrbitCount = 4,
    TrailLifetime = 0.32,
    BurstCount = 10,
    MoteSize = 0.12,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_009")

AWE.Catalog.Effects["FX_010"] = {
    Key = "FX_010",
    Name = "Frostfire Bloom 010",
    Category = "Bloom",
    Description = "Frostfire bloom cosmetic profile 010",
    Color1 = rgb(253, 255, 255),
    Color2 = rgb(108, 191, 249),
    Rate = 13,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 1.7,
    Spread = 60,
    SizeStart = 0.4,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 108,
    Drag = 0.9,
    AccelerationY = -0.2,
    AuraRadius = 3.16,
    OrbitSpeed = 0.75,
    OrbitCount = 5,
    TrailLifetime = 0.53,
    BurstCount = 13,
    MoteSize = 0.19,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_010")

AWE.Catalog.Effects["FX_011"] = {
    Key = "FX_011",
    Name = "Iridescent Bloom 011",
    Category = "Bloom",
    Description = "Iridescent bloom cosmetic profile 011",
    Color1 = rgb(254, 217, 245),
    Color2 = rgb(166, 230, 255),
    Rate = 5,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 0.91,
    Spread = 90,
    SizeStart = 0.58,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 117,
    Drag = 0.15,
    AccelerationY = 0.3,
    AuraRadius = 1.95,
    OrbitSpeed = 1.79,
    OrbitCount = 6,
    TrailLifetime = 0.74,
    BurstCount = 16,
    MoteSize = 0.26,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_011")

AWE.Catalog.Effects["FX_012"] = {
    Key = "FX_012",
    Name = "Cloud Nine Bloom 012",
    Category = "Bloom",
    Description = "Cloud Nine bloom cosmetic profile 012",
    Color1 = rgb(242, 242, 242),
    Color2 = rgb(212, 238, 255),
    Rate = 12,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.08,
    Spread = 120,
    SizeStart = 0.26,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 126,
    Drag = 0.6,
    AccelerationY = -0.7,
    AuraRadius = 2.72,
    OrbitSpeed = 0.83,
    OrbitCount = 7,
    TrailLifetime = 0.95,
    BurstCount = 19,
    MoteSize = 0.33,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_012")

AWE.Catalog.Effects["FX_013"] = {
    Key = "FX_013",
    Name = "Deep Aqua Bloom 013",
    Category = "Bloom",
    Description = "Deep Aqua bloom cosmetic profile 013",
    Color1 = rgb(112, 249, 249),
    Color2 = rgb(25, 154, 201),
    Rate = 4,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 3.53,
    Spread = 150,
    SizeStart = 0.44,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 135,
    Drag = 1.05,
    AccelerationY = -0.2,
    AuraRadius = 1.51,
    OrbitSpeed = 1.87,
    OrbitCount = 8,
    TrailLifetime = 0.25,
    BurstCount = 22,
    MoteSize = 0.4,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_013")

AWE.Catalog.Effects["FX_014"] = {
    Key = "FX_014",
    Name = "Lilac Mist Bloom 014",
    Category = "Bloom",
    Description = "Lilac Mist bloom cosmetic profile 014",
    Color1 = rgb(222, 209, 247),
    Color2 = rgb(168, 155, 240),
    Rate = 11,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 2.74,
    Spread = 180,
    SizeStart = 0.12,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 144,
    Drag = 0.3,
    AccelerationY = 0.3,
    AuraRadius = 2.28,
    OrbitSpeed = 0.91,
    OrbitCount = 9,
    TrailLifetime = 0.46,
    BurstCount = 4,
    MoteSize = 0.15,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_014")

AWE.Catalog.Effects["FX_015"] = {
    Key = "FX_015",
    Name = "Silver Rain Bloom 015",
    Category = "Bloom",
    Description = "Silver Rain bloom cosmetic profile 015",
    Color1 = rgb(247, 255, 255),
    Color2 = rgb(150, 177, 202),
    Rate = 3,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.91,
    Spread = 60,
    SizeStart = 0.3,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 23,
    Drag = 0.75,
    AccelerationY = -0.7,
    AuraRadius = 3.05,
    OrbitSpeed = 1.95,
    OrbitCount = 10,
    TrailLifetime = 0.67,
    BurstCount = 7,
    MoteSize = 0.23,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_015")

AWE.Catalog.Effects["FX_016"] = {
    Key = "FX_016",
    Name = "Pearl Dust 016",
    Category = "Dust",
    Description = "Pearl dust cosmetic profile 016",
    Color1 = rgb(241, 249, 252),
    Color2 = rgb(107, 223, 239),
    Rate = 10,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 2.12,
    Spread = 90,
    SizeStart = 0.47,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 32,
    Drag = 0.0,
    AccelerationY = -0.2,
    AuraRadius = 1.84,
    OrbitSpeed = 0.99,
    OrbitCount = 3,
    TrailLifetime = 0.88,
    BurstCount = 10,
    MoteSize = 0.3,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_016")

AWE.Catalog.Effects["FX_017"] = {
    Key = "FX_017",
    Name = "Aurora Dust 017",
    Category = "Dust",
    Description = "Aurora dust cosmetic profile 017",
    Color1 = rgb(120, 255, 246),
    Color2 = rgb(104, 140, 248),
    Rate = 17,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 2.29,
    Spread = 120,
    SizeStart = 0.15,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 41,
    Drag = 0.45,
    AccelerationY = 0.3,
    AuraRadius = 2.61,
    OrbitSpeed = 2.03,
    OrbitCount = 4,
    TrailLifetime = 1.09,
    BurstCount = 13,
    MoteSize = 0.36,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_017")

AWE.Catalog.Effects["FX_018"] = {
    Key = "FX_018",
    Name = "Moonlight Dust 018",
    Category = "Dust",
    Description = "Moonlight dust cosmetic profile 018",
    Color1 = rgb(232, 241, 255),
    Color2 = rgb(163, 186, 254),
    Rate = 9,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 2.46,
    Spread = 150,
    SizeStart = 0.33,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 50,
    Drag = 0.9,
    AccelerationY = -0.7,
    AuraRadius = 1.4,
    OrbitSpeed = 1.07,
    OrbitCount = 5,
    TrailLifetime = 0.39,
    BurstCount = 16,
    MoteSize = 0.12,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_018")

AWE.Catalog.Effects["FX_019"] = {
    Key = "FX_019",
    Name = "Rose Quartz Dust 019",
    Category = "Dust",
    Description = "Rose Quartz dust cosmetic profile 019",
    Color1 = rgb(245, 200, 222),
    Color2 = rgb(244, 137, 198),
    Rate = 16,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 1.67,
    Spread = 180,
    SizeStart = 0.51,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 59,
    Drag = 0.15,
    AccelerationY = -0.2,
    AuraRadius = 2.17,
    OrbitSpeed = 2.11,
    OrbitCount = 6,
    TrailLifetime = 0.6,
    BurstCount = 19,
    MoteSize = 0.19,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_019")

AWE.Catalog.Effects["FX_020"] = {
    Key = "FX_020",
    Name = "Starlace Dust 020",
    Category = "Dust",
    Description = "Starlace dust cosmetic profile 020",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(185, 218, 251),
    Rate = 8,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.84,
    Spread = 60,
    SizeStart = 0.19,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 68,
    Drag = 0.6,
    AccelerationY = 0.3,
    AuraRadius = 2.94,
    OrbitSpeed = 1.15,
    OrbitCount = 7,
    TrailLifetime = 0.81,
    BurstCount = 22,
    MoteSize = 0.26,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_020")

AWE.Catalog.Effects["FX_021"] = {
    Key = "FX_021",
    Name = "Glacier Dust 021",
    Category = "Dust",
    Description = "Glacier dust cosmetic profile 021",
    Color1 = rgb(195, 243, 250),
    Color2 = rgb(76, 187, 237),
    Rate = 15,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.01,
    Spread = 90,
    SizeStart = 0.36,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 77,
    Drag = 1.05,
    AccelerationY = -0.7,
    AuraRadius = 1.73,
    OrbitSpeed = 2.19,
    OrbitCount = 8,
    TrailLifetime = 1.02,
    BurstCount = 4,
    MoteSize = 0.33,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_021")

AWE.Catalog.Effects["FX_022"] = {
    Key = "FX_022",
    Name = "Opaline Dust 022",
    Category = "Dust",
    Description = "Opaline dust cosmetic profile 022",
    Color1 = rgb(255, 236, 255),
    Color2 = rgb(172, 148, 249),
    Rate = 7,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.22,
    Spread = 120,
    SizeStart = 0.54,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 86,
    Drag = 0.3,
    AccelerationY = -0.2,
    AuraRadius = 2.5,
    OrbitSpeed = 1.23,
    OrbitCount = 9,
    TrailLifetime = 0.32,
    BurstCount = 7,
    MoteSize = 0.4,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_022")

AWE.Catalog.Effects["FX_023"] = {
    Key = "FX_023",
    Name = "Sea Glass Dust 023",
    Category = "Dust",
    Description = "Sea Glass dust cosmetic profile 023",
    Color1 = rgb(184, 255, 239),
    Color2 = rgb(51, 205, 179),
    Rate = 14,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 1.39,
    Spread = 150,
    SizeStart = 0.23,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 95,
    Drag = 0.75,
    AccelerationY = 0.3,
    AuraRadius = 3.27,
    OrbitSpeed = 2.27,
    OrbitCount = 10,
    TrailLifetime = 0.53,
    BurstCount = 10,
    MoteSize = 0.15,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_023")

AWE.Catalog.Effects["FX_024"] = {
    Key = "FX_024",
    Name = "Halo Dust 024",
    Category = "Dust",
    Description = "Halo dust cosmetic profile 024",
    Color1 = rgb(243, 233, 195),
    Color2 = rgb(255, 220, 129),
    Rate = 6,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 0.6,
    Spread = 180,
    SizeStart = 0.4,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 104,
    Drag = 0.0,
    AccelerationY = -0.7,
    AuraRadius = 2.06,
    OrbitSpeed = 1.31,
    OrbitCount = 3,
    TrailLifetime = 0.74,
    BurstCount = 13,
    MoteSize = 0.23,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_024")

AWE.Catalog.Effects["FX_025"] = {
    Key = "FX_025",
    Name = "Frostfire Dust 025",
    Category = "Dust",
    Description = "Frostfire dust cosmetic profile 025",
    Color1 = rgb(247, 255, 255),
    Color2 = rgb(111, 194, 252),
    Rate = 13,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 3.05,
    Spread = 60,
    SizeStart = 0.58,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 113,
    Drag = 0.45,
    AccelerationY = -0.2,
    AuraRadius = 2.83,
    OrbitSpeed = 0.35,
    OrbitCount = 4,
    TrailLifetime = 0.95,
    BurstCount = 16,
    MoteSize = 0.3,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_025")

AWE.Catalog.Effects["FX_026"] = {
    Key = "FX_026",
    Name = "Iridescent Dust 026",
    Category = "Dust",
    Description = "Iridescent dust cosmetic profile 026",
    Color1 = rgb(248, 211, 239),
    Color2 = rgb(169, 233, 255),
    Rate = 5,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 3.22,
    Spread = 90,
    SizeStart = 0.26,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 122,
    Drag = 0.9,
    AccelerationY = 0.3,
    AuraRadius = 1.62,
    OrbitSpeed = 1.39,
    OrbitCount = 5,
    TrailLifetime = 0.25,
    BurstCount = 19,
    MoteSize = 0.36,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_026")

AWE.Catalog.Effects["FX_027"] = {
    Key = "FX_027",
    Name = "Cloud Nine Dust 027",
    Category = "Dust",
    Description = "Cloud Nine dust cosmetic profile 027",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(201, 227, 250),
    Rate = 12,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 2.43,
    Spread = 120,
    SizeStart = 0.44,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 131,
    Drag = 0.15,
    AccelerationY = -0.7,
    AuraRadius = 2.39,
    OrbitSpeed = 0.43,
    OrbitCount = 6,
    TrailLifetime = 0.46,
    BurstCount = 22,
    MoteSize = 0.12,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_027")

AWE.Catalog.Effects["FX_028"] = {
    Key = "FX_028",
    Name = "Deep Aqua Dust 028",
    Category = "Dust",
    Description = "Deep Aqua dust cosmetic profile 028",
    Color1 = rgb(106, 243, 243),
    Color2 = rgb(28, 157, 204),
    Rate = 4,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 2.6,
    Spread = 150,
    SizeStart = 0.12,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 140,
    Drag = 0.6,
    AccelerationY = -0.2,
    AuraRadius = 3.16,
    OrbitSpeed = 1.47,
    OrbitCount = 7,
    TrailLifetime = 0.67,
    BurstCount = 4,
    MoteSize = 0.19,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_028")

AWE.Catalog.Effects["FX_029"] = {
    Key = "FX_029",
    Name = "Lilac Mist Dust 029",
    Category = "Dust",
    Description = "Lilac Mist dust cosmetic profile 029",
    Color1 = rgb(216, 203, 241),
    Color2 = rgb(171, 158, 243),
    Rate = 11,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.77,
    Spread = 180,
    SizeStart = 0.3,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 19,
    Drag = 1.05,
    AccelerationY = 0.3,
    AuraRadius = 1.95,
    OrbitSpeed = 0.51,
    OrbitCount = 8,
    TrailLifetime = 0.88,
    BurstCount = 7,
    MoteSize = 0.26,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_029")

AWE.Catalog.Effects["FX_030"] = {
    Key = "FX_030",
    Name = "Silver Rain Dust 030",
    Category = "Dust",
    Description = "Silver Rain dust cosmetic profile 030",
    Color1 = rgb(241, 249, 255),
    Color2 = rgb(153, 180, 205),
    Rate = 3,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.98,
    Spread = 60,
    SizeStart = 0.47,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 28,
    Drag = 0.3,
    AccelerationY = -0.7,
    AuraRadius = 2.72,
    OrbitSpeed = 1.55,
    OrbitCount = 9,
    TrailLifetime = 1.09,
    BurstCount = 10,
    MoteSize = 0.33,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_030")

AWE.Catalog.Effects["FX_031"] = {
    Key = "FX_031",
    Name = "Pearl Comet 031",
    Category = "Comet",
    Description = "Pearl comet cosmetic profile 031",
    Color1 = rgb(235, 243, 246),
    Color2 = rgb(110, 226, 242),
    Rate = 10,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.15,
    Spread = 90,
    SizeStart = 0.15,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 37,
    Drag = 0.75,
    AccelerationY = -0.2,
    AuraRadius = 1.51,
    OrbitSpeed = 0.59,
    OrbitCount = 10,
    TrailLifetime = 0.39,
    BurstCount = 13,
    MoteSize = 0.4,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_031")

AWE.Catalog.Effects["FX_032"] = {
    Key = "FX_032",
    Name = "Aurora Comet 032",
    Category = "Comet",
    Description = "Aurora comet cosmetic profile 032",
    Color1 = rgb(114, 254, 240),
    Color2 = rgb(107, 143, 251),
    Rate = 17,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 1.36,
    Spread = 120,
    SizeStart = 0.33,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 46,
    Drag = 0.0,
    AccelerationY = 0.3,
    AuraRadius = 2.28,
    OrbitSpeed = 1.63,
    OrbitCount = 3,
    TrailLifetime = 0.6,
    BurstCount = 16,
    MoteSize = 0.15,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_032")

AWE.Catalog.Effects["FX_033"] = {
    Key = "FX_033",
    Name = "Moonlight Comet 033",
    Category = "Comet",
    Description = "Moonlight comet cosmetic profile 033",
    Color1 = rgb(226, 235, 251),
    Color2 = rgb(166, 189, 255),
    Rate = 9,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 1.53,
    Spread = 150,
    SizeStart = 0.51,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 55,
    Drag = 0.45,
    AccelerationY = -0.7,
    AuraRadius = 3.05,
    OrbitSpeed = 0.67,
    OrbitCount = 4,
    TrailLifetime = 0.81,
    BurstCount = 19,
    MoteSize = 0.23,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_033")

AWE.Catalog.Effects["FX_034"] = {
    Key = "FX_034",
    Name = "Rose Quartz Comet 034",
    Category = "Comet",
    Description = "Rose Quartz comet cosmetic profile 034",
    Color1 = rgb(255, 223, 245),
    Color2 = rgb(232, 125, 186),
    Rate = 16,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 1.7,
    Spread = 180,
    SizeStart = 0.19,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 64,
    Drag = 0.9,
    AccelerationY = -0.2,
    AuraRadius = 1.84,
    OrbitSpeed = 1.71,
    OrbitCount = 5,
    TrailLifetime = 1.02,
    BurstCount = 22,
    MoteSize = 0.3,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_034")

AWE.Catalog.Effects["FX_035"] = {
    Key = "FX_035",
    Name = "Starlace Comet 035",
    Category = "Comet",
    Description = "Starlace comet cosmetic profile 035",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(188, 221, 254),
    Rate = 8,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 0.91,
    Spread = 60,
    SizeStart = 0.36,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 73,
    Drag = 0.15,
    AccelerationY = 0.3,
    AuraRadius = 2.61,
    OrbitSpeed = 0.75,
    OrbitCount = 6,
    TrailLifetime = 0.32,
    BurstCount = 4,
    MoteSize = 0.36,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_035")

AWE.Catalog.Effects["FX_036"] = {
    Key = "FX_036",
    Name = "Glacier Comet 036",
    Category = "Comet",
    Description = "Glacier comet cosmetic profile 036",
    Color1 = rgb(189, 237, 244),
    Color2 = rgb(79, 190, 240),
    Rate = 15,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.08,
    Spread = 90,
    SizeStart = 0.54,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 82,
    Drag = 0.6,
    AccelerationY = -0.7,
    AuraRadius = 1.4,
    OrbitSpeed = 1.79,
    OrbitCount = 7,
    TrailLifetime = 0.53,
    BurstCount = 7,
    MoteSize = 0.12,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_036")

AWE.Catalog.Effects["FX_037"] = {
    Key = "FX_037",
    Name = "Opaline Comet 037",
    Category = "Comet",
    Description = "Opaline comet cosmetic profile 037",
    Color1 = rgb(251, 230, 255),
    Color2 = rgb(175, 151, 252),
    Rate = 7,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 3.53,
    Spread = 120,
    SizeStart = 0.23,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 91,
    Drag = 1.05,
    AccelerationY = -0.2,
    AuraRadius = 2.17,
    OrbitSpeed = 0.83,
    OrbitCount = 8,
    TrailLifetime = 0.74,
    BurstCount = 10,
    MoteSize = 0.19,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_037")

AWE.Catalog.Effects["FX_038"] = {
    Key = "FX_038",
    Name = "Sea Glass Comet 038",
    Category = "Comet",
    Description = "Sea Glass comet cosmetic profile 038",
    Color1 = rgb(178, 249, 233),
    Color2 = rgb(54, 208, 182),
    Rate = 14,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 2.74,
    Spread = 150,
    SizeStart = 0.4,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 100,
    Drag = 0.3,
    AccelerationY = 0.3,
    AuraRadius = 2.94,
    OrbitSpeed = 1.87,
    OrbitCount = 9,
    TrailLifetime = 0.95,
    BurstCount = 13,
    MoteSize = 0.26,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_038")

AWE.Catalog.Effects["FX_039"] = {
    Key = "FX_039",
    Name = "Halo Comet 039",
    Category = "Comet",
    Description = "Halo comet cosmetic profile 039",
    Color1 = rgb(255, 255, 218),
    Color2 = rgb(249, 208, 117),
    Rate = 6,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.91,
    Spread = 180,
    SizeStart = 0.58,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 109,
    Drag = 0.75,
    AccelerationY = -0.7,
    AuraRadius = 1.73,
    OrbitSpeed = 0.91,
    OrbitCount = 10,
    TrailLifetime = 0.25,
    BurstCount = 16,
    MoteSize = 0.33,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_039")

AWE.Catalog.Effects["FX_040"] = {
    Key = "FX_040",
    Name = "Frostfire Comet 040",
    Category = "Comet",
    Description = "Frostfire comet cosmetic profile 040",
    Color1 = rgb(241, 252, 254),
    Color2 = rgb(114, 197, 255),
    Rate = 13,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 2.12,
    Spread = 60,
    SizeStart = 0.26,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 118,
    Drag = 0.0,
    AccelerationY = -0.2,
    AuraRadius = 2.5,
    OrbitSpeed = 1.95,
    OrbitCount = 3,
    TrailLifetime = 0.46,
    BurstCount = 19,
    MoteSize = 0.4,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_040")

AWE.Catalog.Effects["FX_041"] = {
    Key = "FX_041",
    Name = "Iridescent Comet 041",
    Category = "Comet",
    Description = "Iridescent comet cosmetic profile 041",
    Color1 = rgb(242, 205, 233),
    Color2 = rgb(172, 236, 255),
    Rate = 5,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 2.29,
    Spread = 90,
    SizeStart = 0.44,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 127,
    Drag = 0.45,
    AccelerationY = 0.3,
    AuraRadius = 3.27,
    OrbitSpeed = 0.99,
    OrbitCount = 4,
    TrailLifetime = 0.67,
    BurstCount = 22,
    MoteSize = 0.15,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_041")

AWE.Catalog.Effects["FX_042"] = {
    Key = "FX_042",
    Name = "Cloud Nine Comet 042",
    Category = "Comet",
    Description = "Cloud Nine comet cosmetic profile 042",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(204, 230, 253),
    Rate = 12,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 2.46,
    Spread = 120,
    SizeStart = 0.12,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 136,
    Drag = 0.9,
    AccelerationY = -0.7,
    AuraRadius = 2.06,
    OrbitSpeed = 2.03,
    OrbitCount = 5,
    TrailLifetime = 0.88,
    BurstCount = 4,
    MoteSize = 0.23,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_042")

AWE.Catalog.Effects["FX_043"] = {
    Key = "FX_043",
    Name = "Deep Aqua Comet 043",
    Category = "Comet",
    Description = "Deep Aqua comet cosmetic profile 043",
    Color1 = rgb(100, 237, 237),
    Color2 = rgb(31, 160, 207),
    Rate = 4,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 1.67,
    Spread = 150,
    SizeStart = 0.3,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 145,
    Drag = 0.15,
    AccelerationY = -0.2,
    AuraRadius = 2.83,
    OrbitSpeed = 1.07,
    OrbitCount = 6,
    TrailLifetime = 1.09,
    BurstCount = 7,
    MoteSize = 0.3,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_043")

AWE.Catalog.Effects["FX_044"] = {
    Key = "FX_044",
    Name = "Lilac Mist Comet 044",
    Category = "Comet",
    Description = "Lilac Mist comet cosmetic profile 044",
    Color1 = rgb(239, 226, 255),
    Color2 = rgb(159, 146, 231),
    Rate = 11,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.84,
    Spread = 180,
    SizeStart = 0.47,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 24,
    Drag = 0.6,
    AccelerationY = 0.3,
    AuraRadius = 1.62,
    OrbitSpeed = 2.11,
    OrbitCount = 7,
    TrailLifetime = 0.39,
    BurstCount = 10,
    MoteSize = 0.36,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_044")

AWE.Catalog.Effects["FX_045"] = {
    Key = "FX_045",
    Name = "Silver Rain Comet 045",
    Category = "Comet",
    Description = "Silver Rain comet cosmetic profile 045",
    Color1 = rgb(235, 243, 252),
    Color2 = rgb(156, 183, 208),
    Rate = 3,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.01,
    Spread = 60,
    SizeStart = 0.15,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 33,
    Drag = 1.05,
    AccelerationY = -0.7,
    AuraRadius = 2.39,
    OrbitSpeed = 1.15,
    OrbitCount = 8,
    TrailLifetime = 0.6,
    BurstCount = 13,
    MoteSize = 0.12,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_045")

AWE.Catalog.Effects["FX_046"] = {
    Key = "FX_046",
    Name = "Pearl Halo 046",
    Category = "Halo",
    Description = "Pearl halo cosmetic profile 046",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(99, 215, 231),
    Rate = 10,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.22,
    Spread = 90,
    SizeStart = 0.33,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 42,
    Drag = 0.3,
    AccelerationY = -0.2,
    AuraRadius = 3.16,
    OrbitSpeed = 2.19,
    OrbitCount = 9,
    TrailLifetime = 0.81,
    BurstCount = 16,
    MoteSize = 0.19,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_046")

AWE.Catalog.Effects["FX_047"] = {
    Key = "FX_047",
    Name = "Aurora Halo 047",
    Category = "Halo",
    Description = "Aurora halo cosmetic profile 047",
    Color1 = rgb(108, 248, 234),
    Color2 = rgb(110, 146, 254),
    Rate = 17,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 1.39,
    Spread = 120,
    SizeStart = 0.51,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 51,
    Drag = 0.75,
    AccelerationY = 0.3,
    AuraRadius = 1.95,
    OrbitSpeed = 1.23,
    OrbitCount = 10,
    TrailLifetime = 1.02,
    BurstCount = 19,
    MoteSize = 0.26,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_047")

AWE.Catalog.Effects["FX_048"] = {
    Key = "FX_048",
    Name = "Moonlight Halo 048",
    Category = "Halo",
    Description = "Moonlight halo cosmetic profile 048",
    Color1 = rgb(220, 229, 245),
    Color2 = rgb(169, 192, 255),
    Rate = 9,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 0.6,
    Spread = 150,
    SizeStart = 0.19,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 60,
    Drag = 0.0,
    AccelerationY = -0.7,
    AuraRadius = 2.72,
    OrbitSpeed = 2.27,
    OrbitCount = 3,
    TrailLifetime = 0.32,
    BurstCount = 22,
    MoteSize = 0.33,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_048")

AWE.Catalog.Effects["FX_049"] = {
    Key = "FX_049",
    Name = "Rose Quartz Halo 049",
    Category = "Halo",
    Description = "Rose Quartz halo cosmetic profile 049",
    Color1 = rgb(255, 217, 239),
    Color2 = rgb(235, 128, 189),
    Rate = 16,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 3.05,
    Spread = 180,
    SizeStart = 0.36,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 69,
    Drag = 0.45,
    AccelerationY = -0.2,
    AuraRadius = 1.51,
    OrbitSpeed = 1.31,
    OrbitCount = 4,
    TrailLifetime = 0.53,
    BurstCount = 4,
    MoteSize = 0.4,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_049")

AWE.Catalog.Effects["FX_050"] = {
    Key = "FX_050",
    Name = "Starlace Halo 050",
    Category = "Halo",
    Description = "Starlace halo cosmetic profile 050",
    Color1 = rgb(250, 250, 250),
    Color2 = rgb(191, 224, 255),
    Rate = 8,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 3.22,
    Spread = 60,
    SizeStart = 0.54,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 78,
    Drag = 0.9,
    AccelerationY = 0.3,
    AuraRadius = 2.28,
    OrbitSpeed = 0.35,
    OrbitCount = 5,
    TrailLifetime = 0.74,
    BurstCount = 7,
    MoteSize = 0.15,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_050")

AWE.Catalog.Effects["FX_051"] = {
    Key = "FX_051",
    Name = "Glacier Halo 051",
    Category = "Halo",
    Description = "Glacier halo cosmetic profile 051",
    Color1 = rgb(212, 255, 255),
    Color2 = rgb(68, 179, 229),
    Rate = 15,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 2.43,
    Spread = 90,
    SizeStart = 0.23,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 87,
    Drag = 0.15,
    AccelerationY = -0.7,
    AuraRadius = 3.05,
    OrbitSpeed = 1.39,
    OrbitCount = 6,
    TrailLifetime = 0.95,
    BurstCount = 10,
    MoteSize = 0.23,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_051")

AWE.Catalog.Effects["FX_052"] = {
    Key = "FX_052",
    Name = "Opaline Halo 052",
    Category = "Halo",
    Description = "Opaline halo cosmetic profile 052",
    Color1 = rgb(245, 224, 255),
    Color2 = rgb(178, 154, 255),
    Rate = 7,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 2.6,
    Spread = 120,
    SizeStart = 0.4,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 96,
    Drag = 0.6,
    AccelerationY = -0.2,
    AuraRadius = 1.84,
    OrbitSpeed = 0.43,
    OrbitCount = 7,
    TrailLifetime = 0.25,
    BurstCount = 13,
    MoteSize = 0.3,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_052")

AWE.Catalog.Effects["FX_053"] = {
    Key = "FX_053",
    Name = "Sea Glass Halo 053",
    Category = "Halo",
    Description = "Sea Glass halo cosmetic profile 053",
    Color1 = rgb(172, 243, 227),
    Color2 = rgb(57, 211, 185),
    Rate = 14,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.77,
    Spread = 150,
    SizeStart = 0.58,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 105,
    Drag = 1.05,
    AccelerationY = 0.3,
    AuraRadius = 2.61,
    OrbitSpeed = 1.47,
    OrbitCount = 8,
    TrailLifetime = 0.46,
    BurstCount = 16,
    MoteSize = 0.36,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_053")

AWE.Catalog.Effects["FX_054"] = {
    Key = "FX_054",
    Name = "Halo Halo 054",
    Category = "Halo",
    Description = "Halo halo cosmetic profile 054",
    Color1 = rgb(255, 250, 212),
    Color2 = rgb(252, 211, 120),
    Rate = 6,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.98,
    Spread = 180,
    SizeStart = 0.26,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 114,
    Drag = 0.3,
    AccelerationY = -0.7,
    AuraRadius = 1.4,
    OrbitSpeed = 0.51,
    OrbitCount = 9,
    TrailLifetime = 0.67,
    BurstCount = 19,
    MoteSize = 0.12,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_054")

AWE.Catalog.Effects["FX_055"] = {
    Key = "FX_055",
    Name = "Frostfire Halo 055",
    Category = "Halo",
    Description = "Frostfire halo cosmetic profile 055",
    Color1 = rgb(235, 246, 248),
    Color2 = rgb(117, 200, 255),
    Rate = 13,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.15,
    Spread = 60,
    SizeStart = 0.44,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 123,
    Drag = 0.75,
    AccelerationY = -0.2,
    AuraRadius = 2.17,
    OrbitSpeed = 1.55,
    OrbitCount = 10,
    TrailLifetime = 0.88,
    BurstCount = 22,
    MoteSize = 0.19,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_055")

AWE.Catalog.Effects["FX_056"] = {
    Key = "FX_056",
    Name = "Iridescent Halo 056",
    Category = "Halo",
    Description = "Iridescent halo cosmetic profile 056",
    Color1 = rgb(255, 228, 255),
    Color2 = rgb(161, 225, 250),
    Rate = 5,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 1.36,
    Spread = 90,
    SizeStart = 0.12,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 132,
    Drag = 0.0,
    AccelerationY = 0.3,
    AuraRadius = 2.94,
    OrbitSpeed = 0.59,
    OrbitCount = 3,
    TrailLifetime = 1.09,
    BurstCount = 4,
    MoteSize = 0.26,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_056")

AWE.Catalog.Effects["FX_057"] = {
    Key = "FX_057",
    Name = "Cloud Nine Halo 057",
    Category = "Halo",
    Description = "Cloud Nine halo cosmetic profile 057",
    Color1 = rgb(253, 253, 253),
    Color2 = rgb(207, 233, 255),
    Rate = 12,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 1.53,
    Spread = 120,
    SizeStart = 0.3,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 141,
    Drag = 0.45,
    AccelerationY = -0.7,
    AuraRadius = 1.73,
    OrbitSpeed = 1.63,
    OrbitCount = 4,
    TrailLifetime = 0.39,
    BurstCount = 7,
    MoteSize = 0.33,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_057")

AWE.Catalog.Effects["FX_058"] = {
    Key = "FX_058",
    Name = "Deep Aqua Halo 058",
    Category = "Halo",
    Description = "Deep Aqua halo cosmetic profile 058",
    Color1 = rgb(94, 231, 231),
    Color2 = rgb(34, 163, 210),
    Rate = 4,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 1.7,
    Spread = 150,
    SizeStart = 0.47,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 20,
    Drag = 0.9,
    AccelerationY = -0.2,
    AuraRadius = 2.5,
    OrbitSpeed = 0.67,
    OrbitCount = 5,
    TrailLifetime = 0.6,
    BurstCount = 10,
    MoteSize = 0.4,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_058")

AWE.Catalog.Effects["FX_059"] = {
    Key = "FX_059",
    Name = "Lilac Mist Halo 059",
    Category = "Halo",
    Description = "Lilac Mist halo cosmetic profile 059",
    Color1 = rgb(233, 220, 255),
    Color2 = rgb(162, 149, 234),
    Rate = 11,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 0.91,
    Spread = 180,
    SizeStart = 0.15,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 29,
    Drag = 0.15,
    AccelerationY = 0.3,
    AuraRadius = 3.27,
    OrbitSpeed = 1.71,
    OrbitCount = 6,
    TrailLifetime = 0.81,
    BurstCount = 13,
    MoteSize = 0.15,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_059")

AWE.Catalog.Effects["FX_060"] = {
    Key = "FX_060",
    Name = "Silver Rain Halo 060",
    Category = "Halo",
    Description = "Silver Rain halo cosmetic profile 060",
    Color1 = rgb(229, 237, 246),
    Color2 = rgb(159, 186, 211),
    Rate = 3,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.08,
    Spread = 60,
    SizeStart = 0.33,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 38,
    Drag = 0.6,
    AccelerationY = -0.7,
    AuraRadius = 2.06,
    OrbitSpeed = 0.75,
    OrbitCount = 7,
    TrailLifetime = 1.02,
    BurstCount = 16,
    MoteSize = 0.23,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_060")

AWE.Catalog.Effects["FX_061"] = {
    Key = "FX_061",
    Name = "Pearl Spark 061",
    Category = "Spark",
    Description = "Pearl spark cosmetic profile 061",
    Color1 = rgb(252, 255, 255),
    Color2 = rgb(102, 218, 234),
    Rate = 10,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 3.53,
    Spread = 90,
    SizeStart = 0.51,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 47,
    Drag = 1.05,
    AccelerationY = -0.2,
    AuraRadius = 2.83,
    OrbitSpeed = 1.79,
    OrbitCount = 8,
    TrailLifetime = 0.32,
    BurstCount = 19,
    MoteSize = 0.3,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_061")

AWE.Catalog.Effects["FX_062"] = {
    Key = "FX_062",
    Name = "Aurora Spark 062",
    Category = "Spark",
    Description = "Aurora spark cosmetic profile 062",
    Color1 = rgb(102, 242, 228),
    Color2 = rgb(113, 149, 255),
    Rate = 17,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 2.74,
    Spread = 120,
    SizeStart = 0.19,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 56,
    Drag = 0.3,
    AccelerationY = 0.3,
    AuraRadius = 1.62,
    OrbitSpeed = 0.83,
    OrbitCount = 9,
    TrailLifetime = 0.53,
    BurstCount = 22,
    MoteSize = 0.36,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_062")

AWE.Catalog.Effects["FX_063"] = {
    Key = "FX_063",
    Name = "Moonlight Spark 063",
    Category = "Spark",
    Description = "Moonlight spark cosmetic profile 063",
    Color1 = rgb(243, 252, 255),
    Color2 = rgb(157, 180, 248),
    Rate = 9,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.91,
    Spread = 150,
    SizeStart = 0.36,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 65,
    Drag = 0.75,
    AccelerationY = -0.7,
    AuraRadius = 2.39,
    OrbitSpeed = 1.87,
    OrbitCount = 10,
    TrailLifetime = 0.74,
    BurstCount = 4,
    MoteSize = 0.12,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_063")

AWE.Catalog.Effects["FX_064"] = {
    Key = "FX_064",
    Name = "Rose Quartz Spark 064",
    Category = "Spark",
    Description = "Rose Quartz spark cosmetic profile 064",
    Color1 = rgb(255, 211, 233),
    Color2 = rgb(238, 131, 192),
    Rate = 16,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 2.12,
    Spread = 180,
    SizeStart = 0.54,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 74,
    Drag = 0.0,
    AccelerationY = -0.2,
    AuraRadius = 3.16,
    OrbitSpeed = 0.91,
    OrbitCount = 3,
    TrailLifetime = 0.95,
    BurstCount = 7,
    MoteSize = 0.19,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_064")

AWE.Catalog.Effects["FX_065"] = {
    Key = "FX_065",
    Name = "Starlace Spark 065",
    Category = "Spark",
    Description = "Starlace spark cosmetic profile 065",
    Color1 = rgb(244, 244, 244),
    Color2 = rgb(194, 227, 255),
    Rate = 8,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 2.29,
    Spread = 60,
    SizeStart = 0.23,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 83,
    Drag = 0.45,
    AccelerationY = 0.3,
    AuraRadius = 1.95,
    OrbitSpeed = 1.95,
    OrbitCount = 4,
    TrailLifetime = 0.25,
    BurstCount = 10,
    MoteSize = 0.26,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_065")

AWE.Catalog.Effects["FX_066"] = {
    Key = "FX_066",
    Name = "Glacier Spark 066",
    Category = "Spark",
    Description = "Glacier spark cosmetic profile 066",
    Color1 = rgb(206, 254, 255),
    Color2 = rgb(71, 182, 232),
    Rate = 15,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 2.46,
    Spread = 90,
    SizeStart = 0.4,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 92,
    Drag = 0.9,
    AccelerationY = -0.7,
    AuraRadius = 2.72,
    OrbitSpeed = 0.99,
    OrbitCount = 5,
    TrailLifetime = 0.46,
    BurstCount = 13,
    MoteSize = 0.33,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_066")

AWE.Catalog.Effects["FX_067"] = {
    Key = "FX_067",
    Name = "Opaline Spark 067",
    Category = "Spark",
    Description = "Opaline spark cosmetic profile 067",
    Color1 = rgb(239, 218, 249),
    Color2 = rgb(181, 157, 255),
    Rate = 7,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 1.67,
    Spread = 120,
    SizeStart = 0.58,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 101,
    Drag = 0.15,
    AccelerationY = -0.2,
    AuraRadius = 1.51,
    OrbitSpeed = 2.03,
    OrbitCount = 6,
    TrailLifetime = 0.67,
    BurstCount = 16,
    MoteSize = 0.4,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_067")

AWE.Catalog.Effects["FX_068"] = {
    Key = "FX_068",
    Name = "Sea Glass Spark 068",
    Category = "Spark",
    Description = "Sea Glass spark cosmetic profile 068",
    Color1 = rgb(195, 255, 250),
    Color2 = rgb(45, 199, 173),
    Rate = 14,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.84,
    Spread = 150,
    SizeStart = 0.26,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 110,
    Drag = 0.6,
    AccelerationY = 0.3,
    AuraRadius = 2.28,
    OrbitSpeed = 1.07,
    OrbitCount = 7,
    TrailLifetime = 0.88,
    BurstCount = 19,
    MoteSize = 0.15,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_068")

AWE.Catalog.Effects["FX_069"] = {
    Key = "FX_069",
    Name = "Halo Spark 069",
    Category = "Spark",
    Description = "Halo spark cosmetic profile 069",
    Color1 = rgb(254, 244, 206),
    Color2 = rgb(255, 214, 123),
    Rate = 6,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.01,
    Spread = 180,
    SizeStart = 0.44,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 119,
    Drag = 1.05,
    AccelerationY = -0.7,
    AuraRadius = 3.05,
    OrbitSpeed = 2.11,
    OrbitCount = 8,
    TrailLifetime = 1.09,
    BurstCount = 22,
    MoteSize = 0.23,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_069")

AWE.Catalog.Effects["FX_070"] = {
    Key = "FX_070",
    Name = "Frostfire Spark 070",
    Category = "Spark",
    Description = "Frostfire spark cosmetic profile 070",
    Color1 = rgb(229, 240, 242),
    Color2 = rgb(120, 203, 255),
    Rate = 13,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.22,
    Spread = 60,
    SizeStart = 0.12,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 128,
    Drag = 0.3,
    AccelerationY = -0.2,
    AuraRadius = 1.84,
    OrbitSpeed = 1.15,
    OrbitCount = 9,
    TrailLifetime = 0.39,
    BurstCount = 4,
    MoteSize = 0.3,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_070")

AWE.Catalog.Effects["FX_071"] = {
    Key = "FX_071",
    Name = "Iridescent Spark 071",
    Category = "Spark",
    Description = "Iridescent spark cosmetic profile 071",
    Color1 = rgb(255, 222, 250),
    Color2 = rgb(164, 228, 253),
    Rate = 5,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 1.39,
    Spread = 90,
    SizeStart = 0.3,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 137,
    Drag = 0.75,
    AccelerationY = 0.3,
    AuraRadius = 2.61,
    OrbitSpeed = 2.19,
    OrbitCount = 10,
    TrailLifetime = 0.6,
    BurstCount = 7,
    MoteSize = 0.36,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_071")

AWE.Catalog.Effects["FX_072"] = {
    Key = "FX_072",
    Name = "Cloud Nine Spark 072",
    Category = "Spark",
    Description = "Cloud Nine spark cosmetic profile 072",
    Color1 = rgb(247, 247, 247),
    Color2 = rgb(210, 236, 255),
    Rate = 12,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 0.6,
    Spread = 120,
    SizeStart = 0.47,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 146,
    Drag = 0.0,
    AccelerationY = -0.7,
    AuraRadius = 1.4,
    OrbitSpeed = 1.23,
    OrbitCount = 3,
    TrailLifetime = 0.81,
    BurstCount = 10,
    MoteSize = 0.12,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_072")

AWE.Catalog.Effects["FX_073"] = {
    Key = "FX_073",
    Name = "Deep Aqua Spark 073",
    Category = "Spark",
    Description = "Deep Aqua spark cosmetic profile 073",
    Color1 = rgb(117, 254, 254),
    Color2 = rgb(22, 151, 198),
    Rate = 4,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 3.05,
    Spread = 150,
    SizeStart = 0.15,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 25,
    Drag = 0.45,
    AccelerationY = -0.2,
    AuraRadius = 2.17,
    OrbitSpeed = 2.27,
    OrbitCount = 4,
    TrailLifetime = 1.02,
    BurstCount = 13,
    MoteSize = 0.19,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_073")

AWE.Catalog.Effects["FX_074"] = {
    Key = "FX_074",
    Name = "Lilac Mist Spark 074",
    Category = "Spark",
    Description = "Lilac Mist spark cosmetic profile 074",
    Color1 = rgb(227, 214, 252),
    Color2 = rgb(165, 152, 237),
    Rate = 11,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 3.22,
    Spread = 180,
    SizeStart = 0.33,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 34,
    Drag = 0.9,
    AccelerationY = 0.3,
    AuraRadius = 2.94,
    OrbitSpeed = 1.31,
    OrbitCount = 5,
    TrailLifetime = 0.32,
    BurstCount = 16,
    MoteSize = 0.26,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_074")

AWE.Catalog.Effects["FX_075"] = {
    Key = "FX_075",
    Name = "Silver Rain Spark 075",
    Category = "Spark",
    Description = "Silver Rain spark cosmetic profile 075",
    Color1 = rgb(252, 255, 255),
    Color2 = rgb(148, 175, 200),
    Rate = 3,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 2.43,
    Spread = 60,
    SizeStart = 0.51,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 43,
    Drag = 0.15,
    AccelerationY = -0.7,
    AuraRadius = 1.73,
    OrbitSpeed = 0.35,
    OrbitCount = 6,
    TrailLifetime = 0.53,
    BurstCount = 19,
    MoteSize = 0.33,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_075")

AWE.Catalog.Effects["FX_076"] = {
    Key = "FX_076",
    Name = "Pearl Ribbon 076",
    Category = "Ribbon",
    Description = "Pearl ribbon cosmetic profile 076",
    Color1 = rgb(246, 254, 255),
    Color2 = rgb(105, 221, 237),
    Rate = 10,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 2.6,
    Spread = 90,
    SizeStart = 0.19,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 52,
    Drag = 0.6,
    AccelerationY = -0.2,
    AuraRadius = 2.5,
    OrbitSpeed = 1.39,
    OrbitCount = 7,
    TrailLifetime = 0.74,
    BurstCount = 22,
    MoteSize = 0.4,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_076")

AWE.Catalog.Effects["FX_077"] = {
    Key = "FX_077",
    Name = "Aurora Ribbon 077",
    Category = "Ribbon",
    Description = "Aurora ribbon cosmetic profile 077",
    Color1 = rgb(96, 236, 222),
    Color2 = rgb(116, 152, 255),
    Rate = 17,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.77,
    Spread = 120,
    SizeStart = 0.36,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 61,
    Drag = 1.05,
    AccelerationY = 0.3,
    AuraRadius = 3.27,
    OrbitSpeed = 0.43,
    OrbitCount = 8,
    TrailLifetime = 0.95,
    BurstCount = 4,
    MoteSize = 0.15,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_077")

AWE.Catalog.Effects["FX_078"] = {
    Key = "FX_078",
    Name = "Moonlight Ribbon 078",
    Category = "Ribbon",
    Description = "Moonlight ribbon cosmetic profile 078",
    Color1 = rgb(237, 246, 255),
    Color2 = rgb(160, 183, 251),
    Rate = 9,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.98,
    Spread = 150,
    SizeStart = 0.54,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 70,
    Drag = 0.3,
    AccelerationY = -0.7,
    AuraRadius = 2.06,
    OrbitSpeed = 1.47,
    OrbitCount = 9,
    TrailLifetime = 0.25,
    BurstCount = 7,
    MoteSize = 0.23,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_078")

AWE.Catalog.Effects["FX_079"] = {
    Key = "FX_079",
    Name = "Rose Quartz Ribbon 079",
    Category = "Ribbon",
    Description = "Rose Quartz ribbon cosmetic profile 079",
    Color1 = rgb(250, 205, 227),
    Color2 = rgb(241, 134, 195),
    Rate = 16,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.15,
    Spread = 180,
    SizeStart = 0.23,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 79,
    Drag = 0.75,
    AccelerationY = -0.2,
    AuraRadius = 2.83,
    OrbitSpeed = 0.51,
    OrbitCount = 10,
    TrailLifetime = 0.46,
    BurstCount = 10,
    MoteSize = 0.3,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_079")

AWE.Catalog.Effects["FX_080"] = {
    Key = "FX_080",
    Name = "Starlace Ribbon 080",
    Category = "Ribbon",
    Description = "Starlace ribbon cosmetic profile 080",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(183, 216, 249),
    Rate = 8,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 1.36,
    Spread = 60,
    SizeStart = 0.4,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 88,
    Drag = 0.0,
    AccelerationY = 0.3,
    AuraRadius = 1.62,
    OrbitSpeed = 1.55,
    OrbitCount = 3,
    TrailLifetime = 0.67,
    BurstCount = 13,
    MoteSize = 0.36,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_080")

AWE.Catalog.Effects["FX_081"] = {
    Key = "FX_081",
    Name = "Glacier Ribbon 081",
    Category = "Ribbon",
    Description = "Glacier ribbon cosmetic profile 081",
    Color1 = rgb(200, 248, 255),
    Color2 = rgb(74, 185, 235),
    Rate = 15,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 1.53,
    Spread = 90,
    SizeStart = 0.58,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 97,
    Drag = 0.45,
    AccelerationY = -0.7,
    AuraRadius = 2.39,
    OrbitSpeed = 0.59,
    OrbitCount = 4,
    TrailLifetime = 0.88,
    BurstCount = 16,
    MoteSize = 0.12,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_081")

AWE.Catalog.Effects["FX_082"] = {
    Key = "FX_082",
    Name = "Opaline Ribbon 082",
    Category = "Ribbon",
    Description = "Opaline ribbon cosmetic profile 082",
    Color1 = rgb(233, 212, 243),
    Color2 = rgb(184, 160, 255),
    Rate = 7,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 1.7,
    Spread = 120,
    SizeStart = 0.26,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 106,
    Drag = 0.9,
    AccelerationY = -0.2,
    AuraRadius = 3.16,
    OrbitSpeed = 1.63,
    OrbitCount = 5,
    TrailLifetime = 1.09,
    BurstCount = 19,
    MoteSize = 0.19,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_082")

AWE.Catalog.Effects["FX_083"] = {
    Key = "FX_083",
    Name = "Sea Glass Ribbon 083",
    Category = "Ribbon",
    Description = "Sea Glass ribbon cosmetic profile 083",
    Color1 = rgb(189, 255, 244),
    Color2 = rgb(48, 202, 176),
    Rate = 14,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 0.91,
    Spread = 150,
    SizeStart = 0.44,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 115,
    Drag = 0.15,
    AccelerationY = 0.3,
    AuraRadius = 1.95,
    OrbitSpeed = 0.67,
    OrbitCount = 6,
    TrailLifetime = 0.39,
    BurstCount = 22,
    MoteSize = 0.26,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_083")

AWE.Catalog.Effects["FX_084"] = {
    Key = "FX_084",
    Name = "Halo Ribbon 084",
    Category = "Ribbon",
    Description = "Halo ribbon cosmetic profile 084",
    Color1 = rgb(248, 238, 200),
    Color2 = rgb(255, 217, 126),
    Rate = 6,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.08,
    Spread = 180,
    SizeStart = 0.12,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 124,
    Drag = 0.6,
    AccelerationY = -0.7,
    AuraRadius = 2.72,
    OrbitSpeed = 1.71,
    OrbitCount = 7,
    TrailLifetime = 0.6,
    BurstCount = 4,
    MoteSize = 0.33,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_084")

AWE.Catalog.Effects["FX_085"] = {
    Key = "FX_085",
    Name = "Frostfire Ribbon 085",
    Category = "Ribbon",
    Description = "Frostfire ribbon cosmetic profile 085",
    Color1 = rgb(252, 255, 255),
    Color2 = rgb(109, 192, 250),
    Rate = 13,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 3.53,
    Spread = 60,
    SizeStart = 0.3,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 133,
    Drag = 1.05,
    AccelerationY = -0.2,
    AuraRadius = 1.51,
    OrbitSpeed = 0.75,
    OrbitCount = 8,
    TrailLifetime = 0.81,
    BurstCount = 7,
    MoteSize = 0.4,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_085")

AWE.Catalog.Effects["FX_086"] = {
    Key = "FX_086",
    Name = "Iridescent Ribbon 086",
    Category = "Ribbon",
    Description = "Iridescent ribbon cosmetic profile 086",
    Color1 = rgb(253, 216, 244),
    Color2 = rgb(167, 231, 255),
    Rate = 5,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 2.74,
    Spread = 90,
    SizeStart = 0.47,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 142,
    Drag = 0.3,
    AccelerationY = 0.3,
    AuraRadius = 2.28,
    OrbitSpeed = 1.79,
    OrbitCount = 9,
    TrailLifetime = 1.02,
    BurstCount = 10,
    MoteSize = 0.15,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_086")

AWE.Catalog.Effects["FX_087"] = {
    Key = "FX_087",
    Name = "Cloud Nine Ribbon 087",
    Category = "Ribbon",
    Description = "Cloud Nine ribbon cosmetic profile 087",
    Color1 = rgb(241, 241, 241),
    Color2 = rgb(213, 239, 255),
    Rate = 12,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.91,
    Spread = 120,
    SizeStart = 0.15,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 21,
    Drag = 0.75,
    AccelerationY = -0.7,
    AuraRadius = 3.05,
    OrbitSpeed = 0.83,
    OrbitCount = 10,
    TrailLifetime = 0.32,
    BurstCount = 13,
    MoteSize = 0.23,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_087")

AWE.Catalog.Effects["FX_088"] = {
    Key = "FX_088",
    Name = "Deep Aqua Ribbon 088",
    Category = "Ribbon",
    Description = "Deep Aqua ribbon cosmetic profile 088",
    Color1 = rgb(111, 248, 248),
    Color2 = rgb(25, 154, 201),
    Rate = 4,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 2.12,
    Spread = 150,
    SizeStart = 0.33,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 30,
    Drag = 0.0,
    AccelerationY = -0.2,
    AuraRadius = 1.84,
    OrbitSpeed = 1.87,
    OrbitCount = 3,
    TrailLifetime = 0.53,
    BurstCount = 16,
    MoteSize = 0.3,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_088")

AWE.Catalog.Effects["FX_089"] = {
    Key = "FX_089",
    Name = "Lilac Mist Ribbon 089",
    Category = "Ribbon",
    Description = "Lilac Mist ribbon cosmetic profile 089",
    Color1 = rgb(221, 208, 246),
    Color2 = rgb(168, 155, 240),
    Rate = 11,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 2.29,
    Spread = 180,
    SizeStart = 0.51,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 39,
    Drag = 0.45,
    AccelerationY = 0.3,
    AuraRadius = 2.61,
    OrbitSpeed = 0.91,
    OrbitCount = 4,
    TrailLifetime = 0.74,
    BurstCount = 19,
    MoteSize = 0.36,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_089")

AWE.Catalog.Effects["FX_090"] = {
    Key = "FX_090",
    Name = "Silver Rain Ribbon 090",
    Category = "Ribbon",
    Description = "Silver Rain ribbon cosmetic profile 090",
    Color1 = rgb(246, 254, 255),
    Color2 = rgb(151, 178, 203),
    Rate = 3,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 2.46,
    Spread = 60,
    SizeStart = 0.19,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 48,
    Drag = 0.9,
    AccelerationY = -0.7,
    AuraRadius = 1.4,
    OrbitSpeed = 1.95,
    OrbitCount = 5,
    TrailLifetime = 0.95,
    BurstCount = 22,
    MoteSize = 0.12,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_090")

AWE.Catalog.Effects["FX_091"] = {
    Key = "FX_091",
    Name = "Pearl Orbit 091",
    Category = "Orbit",
    Description = "Pearl orbit cosmetic profile 091",
    Color1 = rgb(240, 248, 251),
    Color2 = rgb(108, 224, 240),
    Rate = 10,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 1.67,
    Spread = 90,
    SizeStart = 0.36,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 57,
    Drag = 0.15,
    AccelerationY = -0.2,
    AuraRadius = 2.17,
    OrbitSpeed = 0.99,
    OrbitCount = 6,
    TrailLifetime = 0.25,
    BurstCount = 4,
    MoteSize = 0.19,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_091")

AWE.Catalog.Effects["FX_092"] = {
    Key = "FX_092",
    Name = "Aurora Orbit 092",
    Category = "Orbit",
    Description = "Aurora orbit cosmetic profile 092",
    Color1 = rgb(119, 255, 245),
    Color2 = rgb(104, 140, 248),
    Rate = 17,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.84,
    Spread = 120,
    SizeStart = 0.54,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 66,
    Drag = 0.6,
    AccelerationY = 0.3,
    AuraRadius = 2.94,
    OrbitSpeed = 2.03,
    OrbitCount = 7,
    TrailLifetime = 0.46,
    BurstCount = 7,
    MoteSize = 0.26,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_092")

AWE.Catalog.Effects["FX_093"] = {
    Key = "FX_093",
    Name = "Moonlight Orbit 093",
    Category = "Orbit",
    Description = "Moonlight orbit cosmetic profile 093",
    Color1 = rgb(231, 240, 255),
    Color2 = rgb(163, 186, 254),
    Rate = 9,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.01,
    Spread = 150,
    SizeStart = 0.23,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 75,
    Drag = 1.05,
    AccelerationY = -0.7,
    AuraRadius = 1.73,
    OrbitSpeed = 1.07,
    OrbitCount = 8,
    TrailLifetime = 0.67,
    BurstCount = 10,
    MoteSize = 0.33,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_093")

AWE.Catalog.Effects["FX_094"] = {
    Key = "FX_094",
    Name = "Rose Quartz Orbit 094",
    Category = "Orbit",
    Description = "Rose Quartz orbit cosmetic profile 094",
    Color1 = rgb(244, 199, 221),
    Color2 = rgb(244, 137, 198),
    Rate = 16,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.22,
    Spread = 180,
    SizeStart = 0.4,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 84,
    Drag = 0.3,
    AccelerationY = -0.2,
    AuraRadius = 2.5,
    OrbitSpeed = 2.11,
    OrbitCount = 9,
    TrailLifetime = 0.88,
    BurstCount = 13,
    MoteSize = 0.4,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_094")

AWE.Catalog.Effects["FX_095"] = {
    Key = "FX_095",
    Name = "Starlace Orbit 095",
    Category = "Orbit",
    Description = "Starlace orbit cosmetic profile 095",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(186, 219, 252),
    Rate = 8,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 1.39,
    Spread = 60,
    SizeStart = 0.58,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 93,
    Drag = 0.75,
    AccelerationY = 0.3,
    AuraRadius = 3.27,
    OrbitSpeed = 1.15,
    OrbitCount = 10,
    TrailLifetime = 1.09,
    BurstCount = 16,
    MoteSize = 0.15,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_095")

AWE.Catalog.Effects["FX_096"] = {
    Key = "FX_096",
    Name = "Glacier Orbit 096",
    Category = "Orbit",
    Description = "Glacier orbit cosmetic profile 096",
    Color1 = rgb(194, 242, 249),
    Color2 = rgb(77, 188, 238),
    Rate = 15,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 0.6,
    Spread = 90,
    SizeStart = 0.26,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 102,
    Drag = 0.0,
    AccelerationY = -0.7,
    AuraRadius = 2.06,
    OrbitSpeed = 2.19,
    OrbitCount = 3,
    TrailLifetime = 0.39,
    BurstCount = 19,
    MoteSize = 0.23,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_096")

AWE.Catalog.Effects["FX_097"] = {
    Key = "FX_097",
    Name = "Opaline Orbit 097",
    Category = "Orbit",
    Description = "Opaline orbit cosmetic profile 097",
    Color1 = rgb(255, 235, 255),
    Color2 = rgb(172, 148, 249),
    Rate = 7,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 3.05,
    Spread = 120,
    SizeStart = 0.44,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 111,
    Drag = 0.45,
    AccelerationY = -0.2,
    AuraRadius = 2.83,
    OrbitSpeed = 1.23,
    OrbitCount = 4,
    TrailLifetime = 0.6,
    BurstCount = 22,
    MoteSize = 0.3,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_097")

AWE.Catalog.Effects["FX_098"] = {
    Key = "FX_098",
    Name = "Sea Glass Orbit 098",
    Category = "Orbit",
    Description = "Sea Glass orbit cosmetic profile 098",
    Color1 = rgb(183, 254, 238),
    Color2 = rgb(51, 205, 179),
    Rate = 14,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 3.22,
    Spread = 150,
    SizeStart = 0.12,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 120,
    Drag = 0.9,
    AccelerationY = 0.3,
    AuraRadius = 1.62,
    OrbitSpeed = 2.27,
    OrbitCount = 5,
    TrailLifetime = 0.81,
    BurstCount = 4,
    MoteSize = 0.36,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_098")

AWE.Catalog.Effects["FX_099"] = {
    Key = "FX_099",
    Name = "Halo Orbit 099",
    Category = "Orbit",
    Description = "Halo orbit cosmetic profile 099",
    Color1 = rgb(242, 232, 194),
    Color2 = rgb(255, 220, 129),
    Rate = 6,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 2.43,
    Spread = 180,
    SizeStart = 0.3,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 129,
    Drag = 0.15,
    AccelerationY = -0.7,
    AuraRadius = 2.39,
    OrbitSpeed = 1.31,
    OrbitCount = 6,
    TrailLifetime = 1.02,
    BurstCount = 7,
    MoteSize = 0.12,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_099")

AWE.Catalog.Effects["FX_100"] = {
    Key = "FX_100",
    Name = "Frostfire Orbit 100",
    Category = "Orbit",
    Description = "Frostfire orbit cosmetic profile 100",
    Color1 = rgb(246, 255, 255),
    Color2 = rgb(112, 195, 253),
    Rate = 13,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 2.6,
    Spread = 60,
    SizeStart = 0.47,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 138,
    Drag = 0.6,
    AccelerationY = -0.2,
    AuraRadius = 3.16,
    OrbitSpeed = 0.35,
    OrbitCount = 7,
    TrailLifetime = 0.32,
    BurstCount = 10,
    MoteSize = 0.19,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_100")

AWE.Catalog.Effects["FX_101"] = {
    Key = "FX_101",
    Name = "Iridescent Orbit 101",
    Category = "Orbit",
    Description = "Iridescent orbit cosmetic profile 101",
    Color1 = rgb(247, 210, 238),
    Color2 = rgb(170, 234, 255),
    Rate = 5,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.77,
    Spread = 90,
    SizeStart = 0.15,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 147,
    Drag = 1.05,
    AccelerationY = 0.3,
    AuraRadius = 1.95,
    OrbitSpeed = 1.39,
    OrbitCount = 8,
    TrailLifetime = 0.53,
    BurstCount = 13,
    MoteSize = 0.26,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_101")

AWE.Catalog.Effects["FX_102"] = {
    Key = "FX_102",
    Name = "Cloud Nine Orbit 102",
    Category = "Orbit",
    Description = "Cloud Nine orbit cosmetic profile 102",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(201, 227, 250),
    Rate = 12,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.98,
    Spread = 120,
    SizeStart = 0.33,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 26,
    Drag = 0.3,
    AccelerationY = -0.7,
    AuraRadius = 2.72,
    OrbitSpeed = 0.43,
    OrbitCount = 9,
    TrailLifetime = 0.74,
    BurstCount = 16,
    MoteSize = 0.33,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_102")

AWE.Catalog.Effects["FX_103"] = {
    Key = "FX_103",
    Name = "Deep Aqua Orbit 103",
    Category = "Orbit",
    Description = "Deep Aqua orbit cosmetic profile 103",
    Color1 = rgb(105, 242, 242),
    Color2 = rgb(28, 157, 204),
    Rate = 4,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.15,
    Spread = 150,
    SizeStart = 0.51,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 35,
    Drag = 0.75,
    AccelerationY = -0.2,
    AuraRadius = 1.51,
    OrbitSpeed = 1.47,
    OrbitCount = 10,
    TrailLifetime = 0.95,
    BurstCount = 19,
    MoteSize = 0.4,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_103")

AWE.Catalog.Effects["FX_104"] = {
    Key = "FX_104",
    Name = "Lilac Mist Orbit 104",
    Category = "Orbit",
    Description = "Lilac Mist orbit cosmetic profile 104",
    Color1 = rgb(244, 231, 255),
    Color2 = rgb(157, 144, 229),
    Rate = 11,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 1.36,
    Spread = 180,
    SizeStart = 0.19,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 44,
    Drag = 0.0,
    AccelerationY = 0.3,
    AuraRadius = 2.28,
    OrbitSpeed = 0.51,
    OrbitCount = 3,
    TrailLifetime = 0.25,
    BurstCount = 22,
    MoteSize = 0.15,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_104")

AWE.Catalog.Effects["FX_105"] = {
    Key = "FX_105",
    Name = "Silver Rain Orbit 105",
    Category = "Orbit",
    Description = "Silver Rain orbit cosmetic profile 105",
    Color1 = rgb(240, 248, 255),
    Color2 = rgb(154, 181, 206),
    Rate = 3,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 1.53,
    Spread = 60,
    SizeStart = 0.36,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 53,
    Drag = 0.45,
    AccelerationY = -0.7,
    AuraRadius = 3.05,
    OrbitSpeed = 1.55,
    OrbitCount = 4,
    TrailLifetime = 0.46,
    BurstCount = 4,
    MoteSize = 0.23,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_105")

AWE.Catalog.Effects["FX_106"] = {
    Key = "FX_106",
    Name = "Pearl Prism 106",
    Category = "Prism",
    Description = "Pearl prism cosmetic profile 106",
    Color1 = rgb(234, 242, 245),
    Color2 = rgb(111, 227, 243),
    Rate = 10,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 1.7,
    Spread = 90,
    SizeStart = 0.54,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 62,
    Drag = 0.9,
    AccelerationY = -0.2,
    AuraRadius = 1.84,
    OrbitSpeed = 0.59,
    OrbitCount = 5,
    TrailLifetime = 0.67,
    BurstCount = 7,
    MoteSize = 0.3,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_106")

AWE.Catalog.Effects["FX_107"] = {
    Key = "FX_107",
    Name = "Aurora Prism 107",
    Category = "Prism",
    Description = "Aurora prism cosmetic profile 107",
    Color1 = rgb(113, 253, 239),
    Color2 = rgb(107, 143, 251),
    Rate = 17,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 0.91,
    Spread = 120,
    SizeStart = 0.23,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 71,
    Drag = 0.15,
    AccelerationY = 0.3,
    AuraRadius = 2.61,
    OrbitSpeed = 1.63,
    OrbitCount = 6,
    TrailLifetime = 0.88,
    BurstCount = 10,
    MoteSize = 0.36,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_107")

AWE.Catalog.Effects["FX_108"] = {
    Key = "FX_108",
    Name = "Moonlight Prism 108",
    Category = "Prism",
    Description = "Moonlight prism cosmetic profile 108",
    Color1 = rgb(225, 234, 250),
    Color2 = rgb(166, 189, 255),
    Rate = 9,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.08,
    Spread = 150,
    SizeStart = 0.4,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 80,
    Drag = 0.6,
    AccelerationY = -0.7,
    AuraRadius = 1.4,
    OrbitSpeed = 0.67,
    OrbitCount = 7,
    TrailLifetime = 1.09,
    BurstCount = 13,
    MoteSize = 0.12,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_108")

AWE.Catalog.Effects["FX_109"] = {
    Key = "FX_109",
    Name = "Rose Quartz Prism 109",
    Category = "Prism",
    Description = "Rose Quartz prism cosmetic profile 109",
    Color1 = rgb(255, 222, 244),
    Color2 = rgb(233, 126, 187),
    Rate = 16,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 3.53,
    Spread = 180,
    SizeStart = 0.58,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 89,
    Drag = 1.05,
    AccelerationY = -0.2,
    AuraRadius = 2.17,
    OrbitSpeed = 1.71,
    OrbitCount = 8,
    TrailLifetime = 0.39,
    BurstCount = 16,
    MoteSize = 0.19,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_109")

AWE.Catalog.Effects["FX_110"] = {
    Key = "FX_110",
    Name = "Starlace Prism 110",
    Category = "Prism",
    Description = "Starlace prism cosmetic profile 110",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(189, 222, 255),
    Rate = 8,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 2.74,
    Spread = 60,
    SizeStart = 0.26,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 98,
    Drag = 0.3,
    AccelerationY = 0.3,
    AuraRadius = 2.94,
    OrbitSpeed = 0.75,
    OrbitCount = 9,
    TrailLifetime = 0.6,
    BurstCount = 19,
    MoteSize = 0.26,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_110")

AWE.Catalog.Effects["FX_111"] = {
    Key = "FX_111",
    Name = "Glacier Prism 111",
    Category = "Prism",
    Description = "Glacier prism cosmetic profile 111",
    Color1 = rgb(188, 236, 243),
    Color2 = rgb(80, 191, 241),
    Rate = 15,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.91,
    Spread = 90,
    SizeStart = 0.44,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 107,
    Drag = 0.75,
    AccelerationY = -0.7,
    AuraRadius = 1.73,
    OrbitSpeed = 1.79,
    OrbitCount = 10,
    TrailLifetime = 0.81,
    BurstCount = 22,
    MoteSize = 0.33,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_111")

AWE.Catalog.Effects["FX_112"] = {
    Key = "FX_112",
    Name = "Opaline Prism 112",
    Category = "Prism",
    Description = "Opaline prism cosmetic profile 112",
    Color1 = rgb(250, 229, 255),
    Color2 = rgb(175, 151, 252),
    Rate = 7,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 2.12,
    Spread = 120,
    SizeStart = 0.12,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 116,
    Drag = 0.0,
    AccelerationY = -0.2,
    AuraRadius = 2.5,
    OrbitSpeed = 0.83,
    OrbitCount = 3,
    TrailLifetime = 1.02,
    BurstCount = 4,
    MoteSize = 0.4,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_112")

AWE.Catalog.Effects["FX_113"] = {
    Key = "FX_113",
    Name = "Sea Glass Prism 113",
    Category = "Prism",
    Description = "Sea Glass prism cosmetic profile 113",
    Color1 = rgb(177, 248, 232),
    Color2 = rgb(54, 208, 182),
    Rate = 14,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 2.29,
    Spread = 150,
    SizeStart = 0.3,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 125,
    Drag = 0.45,
    AccelerationY = 0.3,
    AuraRadius = 3.27,
    OrbitSpeed = 1.87,
    OrbitCount = 4,
    TrailLifetime = 0.32,
    BurstCount = 7,
    MoteSize = 0.15,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_113")

AWE.Catalog.Effects["FX_114"] = {
    Key = "FX_114",
    Name = "Halo Prism 114",
    Category = "Prism",
    Description = "Halo prism cosmetic profile 114",
    Color1 = rgb(255, 255, 217),
    Color2 = rgb(250, 209, 118),
    Rate = 6,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 2.46,
    Spread = 180,
    SizeStart = 0.47,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 134,
    Drag = 0.9,
    AccelerationY = -0.7,
    AuraRadius = 2.06,
    OrbitSpeed = 0.91,
    OrbitCount = 5,
    TrailLifetime = 0.53,
    BurstCount = 10,
    MoteSize = 0.23,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_114")

AWE.Catalog.Effects["FX_115"] = {
    Key = "FX_115",
    Name = "Frostfire Prism 115",
    Category = "Prism",
    Description = "Frostfire prism cosmetic profile 115",
    Color1 = rgb(240, 251, 253),
    Color2 = rgb(115, 198, 255),
    Rate = 13,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 1.67,
    Spread = 60,
    SizeStart = 0.15,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 143,
    Drag = 0.15,
    AccelerationY = -0.2,
    AuraRadius = 2.83,
    OrbitSpeed = 1.95,
    OrbitCount = 6,
    TrailLifetime = 0.74,
    BurstCount = 13,
    MoteSize = 0.3,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_115")

AWE.Catalog.Effects["FX_116"] = {
    Key = "FX_116",
    Name = "Iridescent Prism 116",
    Category = "Prism",
    Description = "Iridescent prism cosmetic profile 116",
    Color1 = rgb(241, 204, 232),
    Color2 = rgb(173, 237, 255),
    Rate = 5,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.84,
    Spread = 90,
    SizeStart = 0.33,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 22,
    Drag = 0.6,
    AccelerationY = 0.3,
    AuraRadius = 1.62,
    OrbitSpeed = 0.99,
    OrbitCount = 7,
    TrailLifetime = 0.95,
    BurstCount = 16,
    MoteSize = 0.36,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_116")

AWE.Catalog.Effects["FX_117"] = {
    Key = "FX_117",
    Name = "Cloud Nine Prism 117",
    Category = "Prism",
    Description = "Cloud Nine prism cosmetic profile 117",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(204, 230, 253),
    Rate = 12,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.01,
    Spread = 120,
    SizeStart = 0.51,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 31,
    Drag = 1.05,
    AccelerationY = -0.7,
    AuraRadius = 2.39,
    OrbitSpeed = 2.03,
    OrbitCount = 8,
    TrailLifetime = 0.25,
    BurstCount = 19,
    MoteSize = 0.12,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_117")

AWE.Catalog.Effects["FX_118"] = {
    Key = "FX_118",
    Name = "Deep Aqua Prism 118",
    Category = "Prism",
    Description = "Deep Aqua prism cosmetic profile 118",
    Color1 = rgb(99, 236, 236),
    Color2 = rgb(31, 160, 207),
    Rate = 4,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.22,
    Spread = 150,
    SizeStart = 0.19,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 40,
    Drag = 0.3,
    AccelerationY = -0.2,
    AuraRadius = 3.16,
    OrbitSpeed = 1.07,
    OrbitCount = 9,
    TrailLifetime = 0.46,
    BurstCount = 22,
    MoteSize = 0.19,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_118")

AWE.Catalog.Effects["FX_119"] = {
    Key = "FX_119",
    Name = "Lilac Mist Prism 119",
    Category = "Prism",
    Description = "Lilac Mist prism cosmetic profile 119",
    Color1 = rgb(238, 225, 255),
    Color2 = rgb(160, 147, 232),
    Rate = 11,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 1.39,
    Spread = 180,
    SizeStart = 0.36,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 49,
    Drag = 0.75,
    AccelerationY = 0.3,
    AuraRadius = 1.95,
    OrbitSpeed = 2.11,
    OrbitCount = 10,
    TrailLifetime = 0.67,
    BurstCount = 4,
    MoteSize = 0.26,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_119")

AWE.Catalog.Effects["FX_120"] = {
    Key = "FX_120",
    Name = "Silver Rain Prism 120",
    Category = "Prism",
    Description = "Silver Rain prism cosmetic profile 120",
    Color1 = rgb(234, 242, 251),
    Color2 = rgb(157, 184, 209),
    Rate = 3,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 0.6,
    Spread = 60,
    SizeStart = 0.54,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 58,
    Drag = 0.0,
    AccelerationY = -0.7,
    AuraRadius = 2.72,
    OrbitSpeed = 1.15,
    OrbitCount = 3,
    TrailLifetime = 0.88,
    BurstCount = 7,
    MoteSize = 0.33,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_120")

AWE.Catalog.Effects["FX_121"] = {
    Key = "FX_121",
    Name = "Pearl Dew 121",
    Category = "Dew",
    Description = "Pearl dew cosmetic profile 121",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(99, 215, 231),
    Rate = 10,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 3.05,
    Spread = 90,
    SizeStart = 0.23,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 67,
    Drag = 0.45,
    AccelerationY = -0.2,
    AuraRadius = 1.51,
    OrbitSpeed = 2.19,
    OrbitCount = 4,
    TrailLifetime = 1.09,
    BurstCount = 10,
    MoteSize = 0.4,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_121")

AWE.Catalog.Effects["FX_122"] = {
    Key = "FX_122",
    Name = "Aurora Dew 122",
    Category = "Dew",
    Description = "Aurora dew cosmetic profile 122",
    Color1 = rgb(107, 247, 233),
    Color2 = rgb(110, 146, 254),
    Rate = 17,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 3.22,
    Spread = 120,
    SizeStart = 0.4,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 76,
    Drag = 0.9,
    AccelerationY = 0.3,
    AuraRadius = 2.28,
    OrbitSpeed = 1.23,
    OrbitCount = 5,
    TrailLifetime = 0.39,
    BurstCount = 13,
    MoteSize = 0.15,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_122")

AWE.Catalog.Effects["FX_123"] = {
    Key = "FX_123",
    Name = "Moonlight Dew 123",
    Category = "Dew",
    Description = "Moonlight dew cosmetic profile 123",
    Color1 = rgb(219, 228, 244),
    Color2 = rgb(169, 192, 255),
    Rate = 9,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 2.43,
    Spread = 150,
    SizeStart = 0.58,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 85,
    Drag = 0.15,
    AccelerationY = -0.7,
    AuraRadius = 3.05,
    OrbitSpeed = 2.27,
    OrbitCount = 6,
    TrailLifetime = 0.6,
    BurstCount = 16,
    MoteSize = 0.23,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_123")

AWE.Catalog.Effects["FX_124"] = {
    Key = "FX_124",
    Name = "Rose Quartz Dew 124",
    Category = "Dew",
    Description = "Rose Quartz dew cosmetic profile 124",
    Color1 = rgb(255, 216, 238),
    Color2 = rgb(236, 129, 190),
    Rate = 16,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 2.6,
    Spread = 180,
    SizeStart = 0.26,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 94,
    Drag = 0.6,
    AccelerationY = -0.2,
    AuraRadius = 1.84,
    OrbitSpeed = 1.31,
    OrbitCount = 7,
    TrailLifetime = 0.81,
    BurstCount = 19,
    MoteSize = 0.3,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_124")

AWE.Catalog.Effects["FX_125"] = {
    Key = "FX_125",
    Name = "Starlace Dew 125",
    Category = "Dew",
    Description = "Starlace dew cosmetic profile 125",
    Color1 = rgb(249, 249, 249),
    Color2 = rgb(192, 225, 255),
    Rate = 8,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.77,
    Spread = 60,
    SizeStart = 0.44,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 103,
    Drag = 1.05,
    AccelerationY = 0.3,
    AuraRadius = 2.61,
    OrbitSpeed = 0.35,
    OrbitCount = 8,
    TrailLifetime = 1.02,
    BurstCount = 22,
    MoteSize = 0.36,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_125")

AWE.Catalog.Effects["FX_126"] = {
    Key = "FX_126",
    Name = "Glacier Dew 126",
    Category = "Dew",
    Description = "Glacier dew cosmetic profile 126",
    Color1 = rgb(211, 255, 255),
    Color2 = rgb(68, 179, 229),
    Rate = 15,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.98,
    Spread = 90,
    SizeStart = 0.12,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 112,
    Drag = 0.3,
    AccelerationY = -0.7,
    AuraRadius = 1.4,
    OrbitSpeed = 1.39,
    OrbitCount = 9,
    TrailLifetime = 0.32,
    BurstCount = 4,
    MoteSize = 0.12,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_126")

AWE.Catalog.Effects["FX_127"] = {
    Key = "FX_127",
    Name = "Opaline Dew 127",
    Category = "Dew",
    Description = "Opaline dew cosmetic profile 127",
    Color1 = rgb(244, 223, 254),
    Color2 = rgb(178, 154, 255),
    Rate = 7,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.15,
    Spread = 120,
    SizeStart = 0.3,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 121,
    Drag = 0.75,
    AccelerationY = -0.2,
    AuraRadius = 2.17,
    OrbitSpeed = 0.43,
    OrbitCount = 10,
    TrailLifetime = 0.53,
    BurstCount = 7,
    MoteSize = 0.19,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_127")

AWE.Catalog.Effects["FX_128"] = {
    Key = "FX_128",
    Name = "Sea Glass Dew 128",
    Category = "Dew",
    Description = "Sea Glass dew cosmetic profile 128",
    Color1 = rgb(171, 242, 226),
    Color2 = rgb(57, 211, 185),
    Rate = 14,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 1.36,
    Spread = 150,
    SizeStart = 0.47,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 130,
    Drag = 0.0,
    AccelerationY = 0.3,
    AuraRadius = 2.94,
    OrbitSpeed = 1.47,
    OrbitCount = 3,
    TrailLifetime = 0.74,
    BurstCount = 10,
    MoteSize = 0.26,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_128")

AWE.Catalog.Effects["FX_129"] = {
    Key = "FX_129",
    Name = "Halo Dew 129",
    Category = "Dew",
    Description = "Halo dew cosmetic profile 129",
    Color1 = rgb(255, 249, 211),
    Color2 = rgb(253, 212, 121),
    Rate = 6,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 1.53,
    Spread = 180,
    SizeStart = 0.15,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 139,
    Drag = 0.45,
    AccelerationY = -0.7,
    AuraRadius = 1.73,
    OrbitSpeed = 0.51,
    OrbitCount = 4,
    TrailLifetime = 0.95,
    BurstCount = 13,
    MoteSize = 0.33,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_129")

AWE.Catalog.Effects["FX_130"] = {
    Key = "FX_130",
    Name = "Frostfire Dew 130",
    Category = "Dew",
    Description = "Frostfire dew cosmetic profile 130",
    Color1 = rgb(234, 245, 247),
    Color2 = rgb(118, 201, 255),
    Rate = 13,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 1.7,
    Spread = 60,
    SizeStart = 0.33,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 18,
    Drag = 0.9,
    AccelerationY = -0.2,
    AuraRadius = 2.5,
    OrbitSpeed = 1.55,
    OrbitCount = 5,
    TrailLifetime = 0.25,
    BurstCount = 16,
    MoteSize = 0.4,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_130")

AWE.Catalog.Effects["FX_131"] = {
    Key = "FX_131",
    Name = "Iridescent Dew 131",
    Category = "Dew",
    Description = "Iridescent dew cosmetic profile 131",
    Color1 = rgb(255, 227, 255),
    Color2 = rgb(161, 225, 250),
    Rate = 5,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 0.91,
    Spread = 90,
    SizeStart = 0.51,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 27,
    Drag = 0.15,
    AccelerationY = 0.3,
    AuraRadius = 3.27,
    OrbitSpeed = 0.59,
    OrbitCount = 6,
    TrailLifetime = 0.46,
    BurstCount = 19,
    MoteSize = 0.15,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_131")

AWE.Catalog.Effects["FX_132"] = {
    Key = "FX_132",
    Name = "Cloud Nine Dew 132",
    Category = "Dew",
    Description = "Cloud Nine dew cosmetic profile 132",
    Color1 = rgb(252, 252, 252),
    Color2 = rgb(207, 233, 255),
    Rate = 12,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.08,
    Spread = 120,
    SizeStart = 0.19,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 36,
    Drag = 0.6,
    AccelerationY = -0.7,
    AuraRadius = 2.06,
    OrbitSpeed = 1.63,
    OrbitCount = 7,
    TrailLifetime = 0.67,
    BurstCount = 22,
    MoteSize = 0.23,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_132")

AWE.Catalog.Effects["FX_133"] = {
    Key = "FX_133",
    Name = "Deep Aqua Dew 133",
    Category = "Dew",
    Description = "Deep Aqua dew cosmetic profile 133",
    Color1 = rgb(122, 255, 255),
    Color2 = rgb(20, 149, 196),
    Rate = 4,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 3.53,
    Spread = 150,
    SizeStart = 0.36,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 45,
    Drag = 1.05,
    AccelerationY = -0.2,
    AuraRadius = 2.83,
    OrbitSpeed = 0.67,
    OrbitCount = 8,
    TrailLifetime = 0.88,
    BurstCount = 4,
    MoteSize = 0.3,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_133")

AWE.Catalog.Effects["FX_134"] = {
    Key = "FX_134",
    Name = "Lilac Mist Dew 134",
    Category = "Dew",
    Description = "Lilac Mist dew cosmetic profile 134",
    Color1 = rgb(232, 219, 255),
    Color2 = rgb(163, 150, 235),
    Rate = 11,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 2.74,
    Spread = 180,
    SizeStart = 0.54,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 54,
    Drag = 0.3,
    AccelerationY = 0.3,
    AuraRadius = 1.62,
    OrbitSpeed = 1.71,
    OrbitCount = 9,
    TrailLifetime = 1.09,
    BurstCount = 7,
    MoteSize = 0.36,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_134")

AWE.Catalog.Effects["FX_135"] = {
    Key = "FX_135",
    Name = "Silver Rain Dew 135",
    Category = "Dew",
    Description = "Silver Rain dew cosmetic profile 135",
    Color1 = rgb(228, 236, 245),
    Color2 = rgb(160, 187, 212),
    Rate = 3,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.91,
    Spread = 60,
    SizeStart = 0.23,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 63,
    Drag = 0.75,
    AccelerationY = -0.7,
    AuraRadius = 2.39,
    OrbitSpeed = 0.75,
    OrbitCount = 10,
    TrailLifetime = 0.39,
    BurstCount = 10,
    MoteSize = 0.12,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_135")

AWE.Catalog.Effects["FX_136"] = {
    Key = "FX_136",
    Name = "Pearl Flurry 136",
    Category = "Flurry",
    Description = "Pearl flurry cosmetic profile 136",
    Color1 = rgb(251, 255, 255),
    Color2 = rgb(102, 218, 234),
    Rate = 10,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 2.12,
    Spread = 90,
    SizeStart = 0.4,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 72,
    Drag = 0.0,
    AccelerationY = -0.2,
    AuraRadius = 3.16,
    OrbitSpeed = 1.79,
    OrbitCount = 3,
    TrailLifetime = 0.6,
    BurstCount = 13,
    MoteSize = 0.19,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_136")

AWE.Catalog.Effects["FX_137"] = {
    Key = "FX_137",
    Name = "Aurora Flurry 137",
    Category = "Flurry",
    Description = "Aurora flurry cosmetic profile 137",
    Color1 = rgb(101, 241, 227),
    Color2 = rgb(113, 149, 255),
    Rate = 17,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 2.29,
    Spread = 120,
    SizeStart = 0.58,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 81,
    Drag = 0.45,
    AccelerationY = 0.3,
    AuraRadius = 1.95,
    OrbitSpeed = 0.83,
    OrbitCount = 4,
    TrailLifetime = 0.81,
    BurstCount = 16,
    MoteSize = 0.26,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_137")

AWE.Catalog.Effects["FX_138"] = {
    Key = "FX_138",
    Name = "Moonlight Flurry 138",
    Category = "Flurry",
    Description = "Moonlight flurry cosmetic profile 138",
    Color1 = rgb(242, 251, 255),
    Color2 = rgb(158, 181, 249),
    Rate = 9,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 2.46,
    Spread = 150,
    SizeStart = 0.26,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 90,
    Drag = 0.9,
    AccelerationY = -0.7,
    AuraRadius = 2.72,
    OrbitSpeed = 1.87,
    OrbitCount = 5,
    TrailLifetime = 1.02,
    BurstCount = 19,
    MoteSize = 0.33,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_138")

AWE.Catalog.Effects["FX_139"] = {
    Key = "FX_139",
    Name = "Rose Quartz Flurry 139",
    Category = "Flurry",
    Description = "Rose Quartz flurry cosmetic profile 139",
    Color1 = rgb(255, 210, 232),
    Color2 = rgb(239, 132, 193),
    Rate = 16,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 1.67,
    Spread = 180,
    SizeStart = 0.44,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 99,
    Drag = 0.15,
    AccelerationY = -0.2,
    AuraRadius = 1.51,
    OrbitSpeed = 0.91,
    OrbitCount = 6,
    TrailLifetime = 0.32,
    BurstCount = 22,
    MoteSize = 0.4,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_139")

AWE.Catalog.Effects["FX_140"] = {
    Key = "FX_140",
    Name = "Starlace Flurry 140",
    Category = "Flurry",
    Description = "Starlace flurry cosmetic profile 140",
    Color1 = rgb(243, 243, 243),
    Color2 = rgb(195, 228, 255),
    Rate = 8,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.84,
    Spread = 60,
    SizeStart = 0.12,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 108,
    Drag = 0.6,
    AccelerationY = 0.3,
    AuraRadius = 2.28,
    OrbitSpeed = 1.95,
    OrbitCount = 7,
    TrailLifetime = 0.53,
    BurstCount = 4,
    MoteSize = 0.15,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_140")

AWE.Catalog.Effects["FX_141"] = {
    Key = "FX_141",
    Name = "Glacier Flurry 141",
    Category = "Flurry",
    Description = "Glacier flurry cosmetic profile 141",
    Color1 = rgb(205, 253, 255),
    Color2 = rgb(71, 182, 232),
    Rate = 15,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.01,
    Spread = 90,
    SizeStart = 0.3,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 117,
    Drag = 1.05,
    AccelerationY = -0.7,
    AuraRadius = 3.05,
    OrbitSpeed = 0.99,
    OrbitCount = 8,
    TrailLifetime = 0.74,
    BurstCount = 7,
    MoteSize = 0.23,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_141")

AWE.Catalog.Effects["FX_142"] = {
    Key = "FX_142",
    Name = "Opaline Flurry 142",
    Category = "Flurry",
    Description = "Opaline flurry cosmetic profile 142",
    Color1 = rgb(238, 217, 248),
    Color2 = rgb(181, 157, 255),
    Rate = 7,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.22,
    Spread = 120,
    SizeStart = 0.47,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 126,
    Drag = 0.3,
    AccelerationY = -0.2,
    AuraRadius = 1.84,
    OrbitSpeed = 2.03,
    OrbitCount = 9,
    TrailLifetime = 0.95,
    BurstCount = 10,
    MoteSize = 0.3,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_142")

AWE.Catalog.Effects["FX_143"] = {
    Key = "FX_143",
    Name = "Sea Glass Flurry 143",
    Category = "Flurry",
    Description = "Sea Glass flurry cosmetic profile 143",
    Color1 = rgb(194, 255, 249),
    Color2 = rgb(46, 200, 174),
    Rate = 14,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 1.39,
    Spread = 150,
    SizeStart = 0.15,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 135,
    Drag = 0.75,
    AccelerationY = 0.3,
    AuraRadius = 2.61,
    OrbitSpeed = 1.07,
    OrbitCount = 10,
    TrailLifetime = 0.25,
    BurstCount = 13,
    MoteSize = 0.36,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_143")

AWE.Catalog.Effects["FX_144"] = {
    Key = "FX_144",
    Name = "Halo Flurry 144",
    Category = "Flurry",
    Description = "Halo flurry cosmetic profile 144",
    Color1 = rgb(253, 243, 205),
    Color2 = rgb(255, 215, 124),
    Rate = 6,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 0.6,
    Spread = 180,
    SizeStart = 0.33,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 144,
    Drag = 0.0,
    AccelerationY = -0.7,
    AuraRadius = 1.4,
    OrbitSpeed = 2.11,
    OrbitCount = 3,
    TrailLifetime = 0.46,
    BurstCount = 16,
    MoteSize = 0.12,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_144")

AWE.Catalog.Effects["FX_145"] = {
    Key = "FX_145",
    Name = "Frostfire Flurry 145",
    Category = "Flurry",
    Description = "Frostfire flurry cosmetic profile 145",
    Color1 = rgb(228, 239, 241),
    Color2 = rgb(121, 204, 255),
    Rate = 13,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 3.05,
    Spread = 60,
    SizeStart = 0.51,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 23,
    Drag = 0.45,
    AccelerationY = -0.2,
    AuraRadius = 2.17,
    OrbitSpeed = 1.15,
    OrbitCount = 4,
    TrailLifetime = 0.67,
    BurstCount = 19,
    MoteSize = 0.19,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_145")

AWE.Catalog.Effects["FX_146"] = {
    Key = "FX_146",
    Name = "Iridescent Flurry 146",
    Category = "Flurry",
    Description = "Iridescent flurry cosmetic profile 146",
    Color1 = rgb(255, 221, 249),
    Color2 = rgb(164, 228, 253),
    Rate = 5,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 3.22,
    Spread = 90,
    SizeStart = 0.19,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 32,
    Drag = 0.9,
    AccelerationY = 0.3,
    AuraRadius = 2.94,
    OrbitSpeed = 2.19,
    OrbitCount = 5,
    TrailLifetime = 0.88,
    BurstCount = 22,
    MoteSize = 0.26,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_146")

AWE.Catalog.Effects["FX_147"] = {
    Key = "FX_147",
    Name = "Cloud Nine Flurry 147",
    Category = "Flurry",
    Description = "Cloud Nine flurry cosmetic profile 147",
    Color1 = rgb(246, 246, 246),
    Color2 = rgb(210, 236, 255),
    Rate = 12,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 2.43,
    Spread = 120,
    SizeStart = 0.36,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 41,
    Drag = 0.15,
    AccelerationY = -0.7,
    AuraRadius = 1.73,
    OrbitSpeed = 1.23,
    OrbitCount = 6,
    TrailLifetime = 1.09,
    BurstCount = 4,
    MoteSize = 0.33,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_147")

AWE.Catalog.Effects["FX_148"] = {
    Key = "FX_148",
    Name = "Deep Aqua Flurry 148",
    Category = "Flurry",
    Description = "Deep Aqua flurry cosmetic profile 148",
    Color1 = rgb(116, 253, 253),
    Color2 = rgb(23, 152, 199),
    Rate = 4,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 2.6,
    Spread = 150,
    SizeStart = 0.54,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 50,
    Drag = 0.6,
    AccelerationY = -0.2,
    AuraRadius = 2.5,
    OrbitSpeed = 2.27,
    OrbitCount = 7,
    TrailLifetime = 0.39,
    BurstCount = 7,
    MoteSize = 0.4,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_148")

AWE.Catalog.Effects["FX_149"] = {
    Key = "FX_149",
    Name = "Lilac Mist Flurry 149",
    Category = "Flurry",
    Description = "Lilac Mist flurry cosmetic profile 149",
    Color1 = rgb(226, 213, 251),
    Color2 = rgb(166, 153, 238),
    Rate = 11,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.77,
    Spread = 180,
    SizeStart = 0.23,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 59,
    Drag = 1.05,
    AccelerationY = 0.3,
    AuraRadius = 3.27,
    OrbitSpeed = 1.31,
    OrbitCount = 8,
    TrailLifetime = 0.6,
    BurstCount = 10,
    MoteSize = 0.15,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_149")

AWE.Catalog.Effects["FX_150"] = {
    Key = "FX_150",
    Name = "Silver Rain Flurry 150",
    Category = "Flurry",
    Description = "Silver Rain flurry cosmetic profile 150",
    Color1 = rgb(251, 255, 255),
    Color2 = rgb(148, 175, 200),
    Rate = 3,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.98,
    Spread = 60,
    SizeStart = 0.4,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 68,
    Drag = 0.3,
    AccelerationY = -0.7,
    AuraRadius = 2.06,
    OrbitSpeed = 0.35,
    OrbitCount = 9,
    TrailLifetime = 0.81,
    BurstCount = 13,
    MoteSize = 0.23,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_150")

AWE.Catalog.Effects["FX_151"] = {
    Key = "FX_151",
    Name = "Pearl Pulse 151",
    Category = "Pulse",
    Description = "Pearl pulse cosmetic profile 151",
    Color1 = rgb(245, 253, 255),
    Color2 = rgb(105, 221, 237),
    Rate = 10,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.15,
    Spread = 90,
    SizeStart = 0.58,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 77,
    Drag = 0.75,
    AccelerationY = -0.2,
    AuraRadius = 2.83,
    OrbitSpeed = 1.39,
    OrbitCount = 10,
    TrailLifetime = 1.02,
    BurstCount = 16,
    MoteSize = 0.3,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_151")

AWE.Catalog.Effects["FX_152"] = {
    Key = "FX_152",
    Name = "Aurora Pulse 152",
    Category = "Pulse",
    Description = "Aurora pulse cosmetic profile 152",
    Color1 = rgb(95, 235, 221),
    Color2 = rgb(116, 152, 255),
    Rate = 17,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 1.36,
    Spread = 120,
    SizeStart = 0.26,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 86,
    Drag = 0.0,
    AccelerationY = 0.3,
    AuraRadius = 1.62,
    OrbitSpeed = 0.43,
    OrbitCount = 3,
    TrailLifetime = 0.32,
    BurstCount = 19,
    MoteSize = 0.36,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_152")

AWE.Catalog.Effects["FX_153"] = {
    Key = "FX_153",
    Name = "Moonlight Pulse 153",
    Category = "Pulse",
    Description = "Moonlight pulse cosmetic profile 153",
    Color1 = rgb(236, 245, 255),
    Color2 = rgb(161, 184, 252),
    Rate = 9,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 1.53,
    Spread = 150,
    SizeStart = 0.44,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 95,
    Drag = 0.45,
    AccelerationY = -0.7,
    AuraRadius = 2.39,
    OrbitSpeed = 1.47,
    OrbitCount = 4,
    TrailLifetime = 0.53,
    BurstCount = 22,
    MoteSize = 0.12,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_153")

AWE.Catalog.Effects["FX_154"] = {
    Key = "FX_154",
    Name = "Rose Quartz Pulse 154",
    Category = "Pulse",
    Description = "Rose Quartz pulse cosmetic profile 154",
    Color1 = rgb(249, 204, 226),
    Color2 = rgb(242, 135, 196),
    Rate = 16,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 1.7,
    Spread = 180,
    SizeStart = 0.12,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 104,
    Drag = 0.9,
    AccelerationY = -0.2,
    AuraRadius = 3.16,
    OrbitSpeed = 0.51,
    OrbitCount = 5,
    TrailLifetime = 0.74,
    BurstCount = 4,
    MoteSize = 0.19,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_154")

AWE.Catalog.Effects["FX_155"] = {
    Key = "FX_155",
    Name = "Starlace Pulse 155",
    Category = "Pulse",
    Description = "Starlace pulse cosmetic profile 155",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(183, 216, 249),
    Rate = 8,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 0.91,
    Spread = 60,
    SizeStart = 0.3,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 113,
    Drag = 0.15,
    AccelerationY = 0.3,
    AuraRadius = 1.95,
    OrbitSpeed = 1.55,
    OrbitCount = 6,
    TrailLifetime = 0.95,
    BurstCount = 7,
    MoteSize = 0.26,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_155")

AWE.Catalog.Effects["FX_156"] = {
    Key = "FX_156",
    Name = "Glacier Pulse 156",
    Category = "Pulse",
    Description = "Glacier pulse cosmetic profile 156",
    Color1 = rgb(199, 247, 254),
    Color2 = rgb(74, 185, 235),
    Rate = 15,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.08,
    Spread = 90,
    SizeStart = 0.47,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 122,
    Drag = 0.6,
    AccelerationY = -0.7,
    AuraRadius = 2.72,
    OrbitSpeed = 0.59,
    OrbitCount = 7,
    TrailLifetime = 0.25,
    BurstCount = 10,
    MoteSize = 0.33,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_156")

AWE.Catalog.Effects["FX_157"] = {
    Key = "FX_157",
    Name = "Opaline Pulse 157",
    Category = "Pulse",
    Description = "Opaline pulse cosmetic profile 157",
    Color1 = rgb(232, 211, 242),
    Color2 = rgb(184, 160, 255),
    Rate = 7,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 3.53,
    Spread = 120,
    SizeStart = 0.15,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 131,
    Drag = 1.05,
    AccelerationY = -0.2,
    AuraRadius = 1.51,
    OrbitSpeed = 1.63,
    OrbitCount = 8,
    TrailLifetime = 0.46,
    BurstCount = 13,
    MoteSize = 0.4,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_157")

AWE.Catalog.Effects["FX_158"] = {
    Key = "FX_158",
    Name = "Sea Glass Pulse 158",
    Category = "Pulse",
    Description = "Sea Glass pulse cosmetic profile 158",
    Color1 = rgb(188, 255, 243),
    Color2 = rgb(49, 203, 177),
    Rate = 14,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 2.74,
    Spread = 150,
    SizeStart = 0.33,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 140,
    Drag = 0.3,
    AccelerationY = 0.3,
    AuraRadius = 2.28,
    OrbitSpeed = 0.67,
    OrbitCount = 9,
    TrailLifetime = 0.67,
    BurstCount = 16,
    MoteSize = 0.15,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_158")

AWE.Catalog.Effects["FX_159"] = {
    Key = "FX_159",
    Name = "Halo Pulse 159",
    Category = "Pulse",
    Description = "Halo pulse cosmetic profile 159",
    Color1 = rgb(247, 237, 199),
    Color2 = rgb(255, 218, 127),
    Rate = 6,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.91,
    Spread = 180,
    SizeStart = 0.51,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 19,
    Drag = 0.75,
    AccelerationY = -0.7,
    AuraRadius = 3.05,
    OrbitSpeed = 1.71,
    OrbitCount = 10,
    TrailLifetime = 0.88,
    BurstCount = 19,
    MoteSize = 0.23,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_159")

AWE.Catalog.Effects["FX_160"] = {
    Key = "FX_160",
    Name = "Frostfire Pulse 160",
    Category = "Pulse",
    Description = "Frostfire pulse cosmetic profile 160",
    Color1 = rgb(251, 255, 255),
    Color2 = rgb(109, 192, 250),
    Rate = 13,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 2.12,
    Spread = 60,
    SizeStart = 0.19,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 28,
    Drag = 0.0,
    AccelerationY = -0.2,
    AuraRadius = 1.84,
    OrbitSpeed = 0.75,
    OrbitCount = 3,
    TrailLifetime = 1.09,
    BurstCount = 22,
    MoteSize = 0.3,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_160")

AWE.Catalog.Effects["FX_161"] = {
    Key = "FX_161",
    Name = "Iridescent Pulse 161",
    Category = "Pulse",
    Description = "Iridescent pulse cosmetic profile 161",
    Color1 = rgb(252, 215, 243),
    Color2 = rgb(167, 231, 255),
    Rate = 5,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 2.29,
    Spread = 90,
    SizeStart = 0.36,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 37,
    Drag = 0.45,
    AccelerationY = 0.3,
    AuraRadius = 2.61,
    OrbitSpeed = 1.79,
    OrbitCount = 4,
    TrailLifetime = 0.39,
    BurstCount = 4,
    MoteSize = 0.36,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_161")

AWE.Catalog.Effects["FX_162"] = {
    Key = "FX_162",
    Name = "Cloud Nine Pulse 162",
    Category = "Pulse",
    Description = "Cloud Nine pulse cosmetic profile 162",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(199, 225, 248),
    Rate = 12,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 2.46,
    Spread = 120,
    SizeStart = 0.54,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 46,
    Drag = 0.9,
    AccelerationY = -0.7,
    AuraRadius = 1.4,
    OrbitSpeed = 0.83,
    OrbitCount = 5,
    TrailLifetime = 0.6,
    BurstCount = 7,
    MoteSize = 0.12,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_162")

AWE.Catalog.Effects["FX_163"] = {
    Key = "FX_163",
    Name = "Deep Aqua Pulse 163",
    Category = "Pulse",
    Description = "Deep Aqua pulse cosmetic profile 163",
    Color1 = rgb(110, 247, 247),
    Color2 = rgb(26, 155, 202),
    Rate = 4,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 1.67,
    Spread = 150,
    SizeStart = 0.23,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 55,
    Drag = 0.15,
    AccelerationY = -0.2,
    AuraRadius = 2.17,
    OrbitSpeed = 1.87,
    OrbitCount = 6,
    TrailLifetime = 0.81,
    BurstCount = 10,
    MoteSize = 0.19,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_163")

AWE.Catalog.Effects["FX_164"] = {
    Key = "FX_164",
    Name = "Lilac Mist Pulse 164",
    Category = "Pulse",
    Description = "Lilac Mist pulse cosmetic profile 164",
    Color1 = rgb(220, 207, 245),
    Color2 = rgb(169, 156, 241),
    Rate = 11,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.84,
    Spread = 180,
    SizeStart = 0.4,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 64,
    Drag = 0.6,
    AccelerationY = 0.3,
    AuraRadius = 2.94,
    OrbitSpeed = 0.91,
    OrbitCount = 7,
    TrailLifetime = 1.02,
    BurstCount = 13,
    MoteSize = 0.26,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_164")

AWE.Catalog.Effects["FX_165"] = {
    Key = "FX_165",
    Name = "Silver Rain Pulse 165",
    Category = "Pulse",
    Description = "Silver Rain pulse cosmetic profile 165",
    Color1 = rgb(245, 253, 255),
    Color2 = rgb(151, 178, 203),
    Rate = 3,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.01,
    Spread = 60,
    SizeStart = 0.58,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 73,
    Drag = 1.05,
    AccelerationY = -0.7,
    AuraRadius = 1.73,
    OrbitSpeed = 1.95,
    OrbitCount = 8,
    TrailLifetime = 0.32,
    BurstCount = 16,
    MoteSize = 0.33,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_165")

AWE.Catalog.Effects["FX_166"] = {
    Key = "FX_166",
    Name = "Pearl Nova 166",
    Category = "Nova",
    Description = "Pearl nova cosmetic profile 166",
    Color1 = rgb(239, 247, 250),
    Color2 = rgb(108, 224, 240),
    Rate = 10,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.22,
    Spread = 90,
    SizeStart = 0.26,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 82,
    Drag = 0.3,
    AccelerationY = -0.2,
    AuraRadius = 2.5,
    OrbitSpeed = 0.99,
    OrbitCount = 9,
    TrailLifetime = 0.53,
    BurstCount = 19,
    MoteSize = 0.4,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_166")

AWE.Catalog.Effects["FX_167"] = {
    Key = "FX_167",
    Name = "Aurora Nova 167",
    Category = "Nova",
    Description = "Aurora nova cosmetic profile 167",
    Color1 = rgb(118, 255, 244),
    Color2 = rgb(105, 141, 249),
    Rate = 17,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 1.39,
    Spread = 120,
    SizeStart = 0.44,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 91,
    Drag = 0.75,
    AccelerationY = 0.3,
    AuraRadius = 3.27,
    OrbitSpeed = 2.03,
    OrbitCount = 10,
    TrailLifetime = 0.74,
    BurstCount = 22,
    MoteSize = 0.15,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_167")

AWE.Catalog.Effects["FX_168"] = {
    Key = "FX_168",
    Name = "Moonlight Nova 168",
    Category = "Nova",
    Description = "Moonlight nova cosmetic profile 168",
    Color1 = rgb(230, 239, 255),
    Color2 = rgb(164, 187, 255),
    Rate = 9,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 0.6,
    Spread = 150,
    SizeStart = 0.12,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 100,
    Drag = 0.0,
    AccelerationY = -0.7,
    AuraRadius = 2.06,
    OrbitSpeed = 1.07,
    OrbitCount = 3,
    TrailLifetime = 0.95,
    BurstCount = 4,
    MoteSize = 0.23,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_168")

AWE.Catalog.Effects["FX_169"] = {
    Key = "FX_169",
    Name = "Rose Quartz Nova 169",
    Category = "Nova",
    Description = "Rose Quartz nova cosmetic profile 169",
    Color1 = rgb(243, 198, 220),
    Color2 = rgb(245, 138, 199),
    Rate = 16,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 3.05,
    Spread = 180,
    SizeStart = 0.3,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 109,
    Drag = 0.45,
    AccelerationY = -0.2,
    AuraRadius = 2.83,
    OrbitSpeed = 2.11,
    OrbitCount = 4,
    TrailLifetime = 0.25,
    BurstCount = 7,
    MoteSize = 0.3,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_169")

AWE.Catalog.Effects["FX_170"] = {
    Key = "FX_170",
    Name = "Starlace Nova 170",
    Category = "Nova",
    Description = "Starlace nova cosmetic profile 170",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(186, 219, 252),
    Rate = 8,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 3.22,
    Spread = 60,
    SizeStart = 0.47,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 118,
    Drag = 0.9,
    AccelerationY = 0.3,
    AuraRadius = 1.62,
    OrbitSpeed = 1.15,
    OrbitCount = 5,
    TrailLifetime = 0.46,
    BurstCount = 10,
    MoteSize = 0.36,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_170")

AWE.Catalog.Effects["FX_171"] = {
    Key = "FX_171",
    Name = "Glacier Nova 171",
    Category = "Nova",
    Description = "Glacier nova cosmetic profile 171",
    Color1 = rgb(193, 241, 248),
    Color2 = rgb(77, 188, 238),
    Rate = 15,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 2.43,
    Spread = 90,
    SizeStart = 0.15,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 127,
    Drag = 0.15,
    AccelerationY = -0.7,
    AuraRadius = 2.39,
    OrbitSpeed = 2.19,
    OrbitCount = 6,
    TrailLifetime = 0.67,
    BurstCount = 13,
    MoteSize = 0.12,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_171")

AWE.Catalog.Effects["FX_172"] = {
    Key = "FX_172",
    Name = "Opaline Nova 172",
    Category = "Nova",
    Description = "Opaline nova cosmetic profile 172",
    Color1 = rgb(255, 234, 255),
    Color2 = rgb(173, 149, 250),
    Rate = 7,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 2.6,
    Spread = 120,
    SizeStart = 0.33,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 136,
    Drag = 0.6,
    AccelerationY = -0.2,
    AuraRadius = 3.16,
    OrbitSpeed = 1.23,
    OrbitCount = 7,
    TrailLifetime = 0.88,
    BurstCount = 16,
    MoteSize = 0.19,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_172")

AWE.Catalog.Effects["FX_173"] = {
    Key = "FX_173",
    Name = "Sea Glass Nova 173",
    Category = "Nova",
    Description = "Sea Glass nova cosmetic profile 173",
    Color1 = rgb(182, 253, 237),
    Color2 = rgb(52, 206, 180),
    Rate = 14,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.77,
    Spread = 150,
    SizeStart = 0.51,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 145,
    Drag = 1.05,
    AccelerationY = 0.3,
    AuraRadius = 1.95,
    OrbitSpeed = 2.27,
    OrbitCount = 8,
    TrailLifetime = 1.09,
    BurstCount = 19,
    MoteSize = 0.26,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_173")

AWE.Catalog.Effects["FX_174"] = {
    Key = "FX_174",
    Name = "Halo Nova 174",
    Category = "Nova",
    Description = "Halo nova cosmetic profile 174",
    Color1 = rgb(241, 231, 193),
    Color2 = rgb(255, 221, 130),
    Rate = 6,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.98,
    Spread = 180,
    SizeStart = 0.19,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 24,
    Drag = 0.3,
    AccelerationY = -0.7,
    AuraRadius = 2.72,
    OrbitSpeed = 1.31,
    OrbitCount = 9,
    TrailLifetime = 0.39,
    BurstCount = 22,
    MoteSize = 0.33,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_174")

AWE.Catalog.Effects["FX_175"] = {
    Key = "FX_175",
    Name = "Frostfire Nova 175",
    Category = "Nova",
    Description = "Frostfire nova cosmetic profile 175",
    Color1 = rgb(245, 255, 255),
    Color2 = rgb(112, 195, 253),
    Rate = 13,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.15,
    Spread = 60,
    SizeStart = 0.36,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 33,
    Drag = 0.75,
    AccelerationY = -0.2,
    AuraRadius = 1.51,
    OrbitSpeed = 0.35,
    OrbitCount = 10,
    TrailLifetime = 0.6,
    BurstCount = 4,
    MoteSize = 0.4,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_175")

AWE.Catalog.Effects["FX_176"] = {
    Key = "FX_176",
    Name = "Iridescent Nova 176",
    Category = "Nova",
    Description = "Iridescent nova cosmetic profile 176",
    Color1 = rgb(246, 209, 237),
    Color2 = rgb(170, 234, 255),
    Rate = 5,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 1.36,
    Spread = 90,
    SizeStart = 0.54,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 42,
    Drag = 0.0,
    AccelerationY = 0.3,
    AuraRadius = 2.28,
    OrbitSpeed = 1.39,
    OrbitCount = 3,
    TrailLifetime = 0.81,
    BurstCount = 7,
    MoteSize = 0.15,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_176")

AWE.Catalog.Effects["FX_177"] = {
    Key = "FX_177",
    Name = "Cloud Nine Nova 177",
    Category = "Nova",
    Description = "Cloud Nine nova cosmetic profile 177",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(202, 228, 251),
    Rate = 12,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 1.53,
    Spread = 120,
    SizeStart = 0.23,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 51,
    Drag = 0.45,
    AccelerationY = -0.7,
    AuraRadius = 3.05,
    OrbitSpeed = 0.43,
    OrbitCount = 4,
    TrailLifetime = 1.02,
    BurstCount = 10,
    MoteSize = 0.23,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_177")

AWE.Catalog.Effects["FX_178"] = {
    Key = "FX_178",
    Name = "Deep Aqua Nova 178",
    Category = "Nova",
    Description = "Deep Aqua nova cosmetic profile 178",
    Color1 = rgb(104, 241, 241),
    Color2 = rgb(29, 158, 205),
    Rate = 4,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 1.7,
    Spread = 150,
    SizeStart = 0.4,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 60,
    Drag = 0.9,
    AccelerationY = -0.2,
    AuraRadius = 1.84,
    OrbitSpeed = 1.47,
    OrbitCount = 5,
    TrailLifetime = 0.32,
    BurstCount = 13,
    MoteSize = 0.3,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_178")

AWE.Catalog.Effects["FX_179"] = {
    Key = "FX_179",
    Name = "Lilac Mist Nova 179",
    Category = "Nova",
    Description = "Lilac Mist nova cosmetic profile 179",
    Color1 = rgb(243, 230, 255),
    Color2 = rgb(157, 144, 229),
    Rate = 11,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 0.91,
    Spread = 180,
    SizeStart = 0.58,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 69,
    Drag = 0.15,
    AccelerationY = 0.3,
    AuraRadius = 2.61,
    OrbitSpeed = 0.51,
    OrbitCount = 6,
    TrailLifetime = 0.53,
    BurstCount = 16,
    MoteSize = 0.36,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_179")

AWE.Catalog.Effects["FX_180"] = {
    Key = "FX_180",
    Name = "Silver Rain Nova 180",
    Category = "Nova",
    Description = "Silver Rain nova cosmetic profile 180",
    Color1 = rgb(239, 247, 255),
    Color2 = rgb(154, 181, 206),
    Rate = 3,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.08,
    Spread = 60,
    SizeStart = 0.26,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 78,
    Drag = 0.6,
    AccelerationY = -0.7,
    AuraRadius = 1.4,
    OrbitSpeed = 1.55,
    OrbitCount = 7,
    TrailLifetime = 0.74,
    BurstCount = 19,
    MoteSize = 0.12,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_180")

AWE.Catalog.Effects["FX_181"] = {
    Key = "FX_181",
    Name = "Pearl Bloom 181",
    Category = "Bloom",
    Description = "Pearl bloom cosmetic profile 181",
    Color1 = rgb(233, 241, 244),
    Color2 = rgb(111, 227, 243),
    Rate = 10,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 3.53,
    Spread = 90,
    SizeStart = 0.44,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 87,
    Drag = 1.05,
    AccelerationY = -0.2,
    AuraRadius = 2.17,
    OrbitSpeed = 0.59,
    OrbitCount = 8,
    TrailLifetime = 0.95,
    BurstCount = 22,
    MoteSize = 0.19,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_181")

AWE.Catalog.Effects["FX_182"] = {
    Key = "FX_182",
    Name = "Aurora Bloom 182",
    Category = "Bloom",
    Description = "Aurora bloom cosmetic profile 182",
    Color1 = rgb(112, 252, 238),
    Color2 = rgb(108, 144, 252),
    Rate = 17,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 2.74,
    Spread = 120,
    SizeStart = 0.12,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 96,
    Drag = 0.3,
    AccelerationY = 0.3,
    AuraRadius = 2.94,
    OrbitSpeed = 1.63,
    OrbitCount = 9,
    TrailLifetime = 0.25,
    BurstCount = 4,
    MoteSize = 0.26,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_182")

AWE.Catalog.Effects["FX_183"] = {
    Key = "FX_183",
    Name = "Moonlight Bloom 183",
    Category = "Bloom",
    Description = "Moonlight bloom cosmetic profile 183",
    Color1 = rgb(224, 233, 249),
    Color2 = rgb(167, 190, 255),
    Rate = 9,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.91,
    Spread = 150,
    SizeStart = 0.3,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 105,
    Drag = 0.75,
    AccelerationY = -0.7,
    AuraRadius = 1.73,
    OrbitSpeed = 0.67,
    OrbitCount = 10,
    TrailLifetime = 0.46,
    BurstCount = 7,
    MoteSize = 0.33,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_183")

AWE.Catalog.Effects["FX_184"] = {
    Key = "FX_184",
    Name = "Rose Quartz Bloom 184",
    Category = "Bloom",
    Description = "Rose Quartz bloom cosmetic profile 184",
    Color1 = rgb(255, 221, 243),
    Color2 = rgb(233, 126, 187),
    Rate = 16,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 2.12,
    Spread = 180,
    SizeStart = 0.47,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 114,
    Drag = 0.0,
    AccelerationY = -0.2,
    AuraRadius = 2.5,
    OrbitSpeed = 1.71,
    OrbitCount = 3,
    TrailLifetime = 0.67,
    BurstCount = 10,
    MoteSize = 0.4,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_184")

AWE.Catalog.Effects["FX_185"] = {
    Key = "FX_185",
    Name = "Starlace Bloom 185",
    Category = "Bloom",
    Description = "Starlace bloom cosmetic profile 185",
    Color1 = rgb(254, 254, 254),
    Color2 = rgb(189, 222, 255),
    Rate = 8,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 2.29,
    Spread = 60,
    SizeStart = 0.15,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 123,
    Drag = 0.45,
    AccelerationY = 0.3,
    AuraRadius = 3.27,
    OrbitSpeed = 0.75,
    OrbitCount = 4,
    TrailLifetime = 0.88,
    BurstCount = 13,
    MoteSize = 0.15,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_185")

AWE.Catalog.Effects["FX_186"] = {
    Key = "FX_186",
    Name = "Glacier Bloom 186",
    Category = "Bloom",
    Description = "Glacier bloom cosmetic profile 186",
    Color1 = rgb(187, 235, 242),
    Color2 = rgb(80, 191, 241),
    Rate = 15,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 2.46,
    Spread = 90,
    SizeStart = 0.33,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 132,
    Drag = 0.9,
    AccelerationY = -0.7,
    AuraRadius = 2.06,
    OrbitSpeed = 1.79,
    OrbitCount = 5,
    TrailLifetime = 1.09,
    BurstCount = 16,
    MoteSize = 0.23,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_186")

AWE.Catalog.Effects["FX_187"] = {
    Key = "FX_187",
    Name = "Opaline Bloom 187",
    Category = "Bloom",
    Description = "Opaline bloom cosmetic profile 187",
    Color1 = rgb(249, 228, 255),
    Color2 = rgb(176, 152, 253),
    Rate = 7,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 1.67,
    Spread = 120,
    SizeStart = 0.51,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 141,
    Drag = 0.15,
    AccelerationY = -0.2,
    AuraRadius = 2.83,
    OrbitSpeed = 0.83,
    OrbitCount = 6,
    TrailLifetime = 0.39,
    BurstCount = 19,
    MoteSize = 0.3,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_187")

AWE.Catalog.Effects["FX_188"] = {
    Key = "FX_188",
    Name = "Sea Glass Bloom 188",
    Category = "Bloom",
    Description = "Sea Glass bloom cosmetic profile 188",
    Color1 = rgb(176, 247, 231),
    Color2 = rgb(55, 209, 183),
    Rate = 14,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.84,
    Spread = 150,
    SizeStart = 0.19,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 20,
    Drag = 0.6,
    AccelerationY = 0.3,
    AuraRadius = 1.62,
    OrbitSpeed = 1.87,
    OrbitCount = 7,
    TrailLifetime = 0.6,
    BurstCount = 22,
    MoteSize = 0.36,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_188")

AWE.Catalog.Effects["FX_189"] = {
    Key = "FX_189",
    Name = "Halo Bloom 189",
    Category = "Bloom",
    Description = "Halo bloom cosmetic profile 189",
    Color1 = rgb(255, 254, 216),
    Color2 = rgb(250, 209, 118),
    Rate = 6,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.01,
    Spread = 180,
    SizeStart = 0.36,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 29,
    Drag = 1.05,
    AccelerationY = -0.7,
    AuraRadius = 2.39,
    OrbitSpeed = 0.91,
    OrbitCount = 8,
    TrailLifetime = 0.81,
    BurstCount = 4,
    MoteSize = 0.12,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_189")

AWE.Catalog.Effects["FX_190"] = {
    Key = "FX_190",
    Name = "Frostfire Bloom 190",
    Category = "Bloom",
    Description = "Frostfire bloom cosmetic profile 190",
    Color1 = rgb(239, 250, 252),
    Color2 = rgb(115, 198, 255),
    Rate = 13,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.22,
    Spread = 60,
    SizeStart = 0.54,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 38,
    Drag = 0.3,
    AccelerationY = -0.2,
    AuraRadius = 3.16,
    OrbitSpeed = 1.95,
    OrbitCount = 9,
    TrailLifetime = 1.02,
    BurstCount = 7,
    MoteSize = 0.19,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_190")

AWE.Catalog.Effects["FX_191"] = {
    Key = "FX_191",
    Name = "Iridescent Bloom 191",
    Category = "Bloom",
    Description = "Iridescent bloom cosmetic profile 191",
    Color1 = rgb(255, 232, 255),
    Color2 = rgb(159, 223, 248),
    Rate = 5,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 1.39,
    Spread = 90,
    SizeStart = 0.23,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 47,
    Drag = 0.75,
    AccelerationY = 0.3,
    AuraRadius = 1.95,
    OrbitSpeed = 0.99,
    OrbitCount = 10,
    TrailLifetime = 0.32,
    BurstCount = 10,
    MoteSize = 0.26,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_191")

AWE.Catalog.Effects["FX_192"] = {
    Key = "FX_192",
    Name = "Cloud Nine Bloom 192",
    Category = "Bloom",
    Description = "Cloud Nine bloom cosmetic profile 192",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(205, 231, 254),
    Rate = 12,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 0.6,
    Spread = 120,
    SizeStart = 0.4,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 56,
    Drag = 0.0,
    AccelerationY = -0.7,
    AuraRadius = 2.72,
    OrbitSpeed = 2.03,
    OrbitCount = 3,
    TrailLifetime = 0.53,
    BurstCount = 13,
    MoteSize = 0.33,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_192")

AWE.Catalog.Effects["FX_193"] = {
    Key = "FX_193",
    Name = "Deep Aqua Bloom 193",
    Category = "Bloom",
    Description = "Deep Aqua bloom cosmetic profile 193",
    Color1 = rgb(98, 235, 235),
    Color2 = rgb(32, 161, 208),
    Rate = 4,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 3.05,
    Spread = 150,
    SizeStart = 0.58,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 65,
    Drag = 0.45,
    AccelerationY = -0.2,
    AuraRadius = 1.51,
    OrbitSpeed = 1.07,
    OrbitCount = 4,
    TrailLifetime = 0.74,
    BurstCount = 16,
    MoteSize = 0.4,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_193")

AWE.Catalog.Effects["FX_194"] = {
    Key = "FX_194",
    Name = "Lilac Mist Bloom 194",
    Category = "Bloom",
    Description = "Lilac Mist bloom cosmetic profile 194",
    Color1 = rgb(237, 224, 255),
    Color2 = rgb(160, 147, 232),
    Rate = 11,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 3.22,
    Spread = 180,
    SizeStart = 0.26,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 74,
    Drag = 0.9,
    AccelerationY = 0.3,
    AuraRadius = 2.28,
    OrbitSpeed = 2.11,
    OrbitCount = 5,
    TrailLifetime = 0.95,
    BurstCount = 19,
    MoteSize = 0.15,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_194")

AWE.Catalog.Effects["FX_195"] = {
    Key = "FX_195",
    Name = "Silver Rain Bloom 195",
    Category = "Bloom",
    Description = "Silver Rain bloom cosmetic profile 195",
    Color1 = rgb(233, 241, 250),
    Color2 = rgb(157, 184, 209),
    Rate = 3,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 2.43,
    Spread = 60,
    SizeStart = 0.44,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 83,
    Drag = 0.15,
    AccelerationY = -0.7,
    AuraRadius = 3.05,
    OrbitSpeed = 1.15,
    OrbitCount = 6,
    TrailLifetime = 0.25,
    BurstCount = 22,
    MoteSize = 0.23,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_195")

AWE.Catalog.Effects["FX_196"] = {
    Key = "FX_196",
    Name = "Pearl Dust 196",
    Category = "Dust",
    Description = "Pearl dust cosmetic profile 196",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(100, 216, 232),
    Rate = 10,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 2.6,
    Spread = 90,
    SizeStart = 0.12,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 92,
    Drag = 0.6,
    AccelerationY = -0.2,
    AuraRadius = 1.84,
    OrbitSpeed = 2.19,
    OrbitCount = 7,
    TrailLifetime = 0.46,
    BurstCount = 4,
    MoteSize = 0.3,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_196")

AWE.Catalog.Effects["FX_197"] = {
    Key = "FX_197",
    Name = "Aurora Dust 197",
    Category = "Dust",
    Description = "Aurora dust cosmetic profile 197",
    Color1 = rgb(106, 246, 232),
    Color2 = rgb(111, 147, 255),
    Rate = 17,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.77,
    Spread = 120,
    SizeStart = 0.3,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 101,
    Drag = 1.05,
    AccelerationY = 0.3,
    AuraRadius = 2.61,
    OrbitSpeed = 1.23,
    OrbitCount = 8,
    TrailLifetime = 0.67,
    BurstCount = 7,
    MoteSize = 0.36,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_197")

AWE.Catalog.Effects["FX_198"] = {
    Key = "FX_198",
    Name = "Moonlight Dust 198",
    Category = "Dust",
    Description = "Moonlight dust cosmetic profile 198",
    Color1 = rgb(218, 227, 243),
    Color2 = rgb(170, 193, 255),
    Rate = 9,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.98,
    Spread = 150,
    SizeStart = 0.47,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 110,
    Drag = 0.3,
    AccelerationY = -0.7,
    AuraRadius = 1.4,
    OrbitSpeed = 2.27,
    OrbitCount = 9,
    TrailLifetime = 0.88,
    BurstCount = 10,
    MoteSize = 0.12,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_198")

AWE.Catalog.Effects["FX_199"] = {
    Key = "FX_199",
    Name = "Rose Quartz Dust 199",
    Category = "Dust",
    Description = "Rose Quartz dust cosmetic profile 199",
    Color1 = rgb(255, 215, 237),
    Color2 = rgb(236, 129, 190),
    Rate = 16,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.15,
    Spread = 180,
    SizeStart = 0.15,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 119,
    Drag = 0.75,
    AccelerationY = -0.2,
    AuraRadius = 2.17,
    OrbitSpeed = 1.31,
    OrbitCount = 10,
    TrailLifetime = 1.09,
    BurstCount = 13,
    MoteSize = 0.19,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_199")

AWE.Catalog.Effects["FX_200"] = {
    Key = "FX_200",
    Name = "Starlace Dust 200",
    Category = "Dust",
    Description = "Starlace dust cosmetic profile 200",
    Color1 = rgb(248, 248, 248),
    Color2 = rgb(192, 225, 255),
    Rate = 8,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 1.36,
    Spread = 60,
    SizeStart = 0.33,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 128,
    Drag = 0.0,
    AccelerationY = 0.3,
    AuraRadius = 2.94,
    OrbitSpeed = 0.35,
    OrbitCount = 3,
    TrailLifetime = 0.39,
    BurstCount = 16,
    MoteSize = 0.26,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_200")

AWE.Catalog.Effects["FX_201"] = {
    Key = "FX_201",
    Name = "Glacier Dust 201",
    Category = "Dust",
    Description = "Glacier dust cosmetic profile 201",
    Color1 = rgb(210, 255, 255),
    Color2 = rgb(69, 180, 230),
    Rate = 15,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 1.53,
    Spread = 90,
    SizeStart = 0.51,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 137,
    Drag = 0.45,
    AccelerationY = -0.7,
    AuraRadius = 1.73,
    OrbitSpeed = 1.39,
    OrbitCount = 4,
    TrailLifetime = 0.6,
    BurstCount = 19,
    MoteSize = 0.33,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_201")

AWE.Catalog.Effects["FX_202"] = {
    Key = "FX_202",
    Name = "Opaline Dust 202",
    Category = "Dust",
    Description = "Opaline dust cosmetic profile 202",
    Color1 = rgb(243, 222, 253),
    Color2 = rgb(179, 155, 255),
    Rate = 7,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 1.7,
    Spread = 120,
    SizeStart = 0.19,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 146,
    Drag = 0.9,
    AccelerationY = -0.2,
    AuraRadius = 2.5,
    OrbitSpeed = 0.43,
    OrbitCount = 5,
    TrailLifetime = 0.81,
    BurstCount = 22,
    MoteSize = 0.4,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_202")

AWE.Catalog.Effects["FX_203"] = {
    Key = "FX_203",
    Name = "Sea Glass Dust 203",
    Category = "Dust",
    Description = "Sea Glass dust cosmetic profile 203",
    Color1 = rgb(170, 241, 225),
    Color2 = rgb(58, 212, 186),
    Rate = 14,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 0.91,
    Spread = 150,
    SizeStart = 0.36,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 25,
    Drag = 0.15,
    AccelerationY = 0.3,
    AuraRadius = 3.27,
    OrbitSpeed = 1.47,
    OrbitCount = 6,
    TrailLifetime = 1.02,
    BurstCount = 4,
    MoteSize = 0.15,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_203")

AWE.Catalog.Effects["FX_204"] = {
    Key = "FX_204",
    Name = "Halo Dust 204",
    Category = "Dust",
    Description = "Halo dust cosmetic profile 204",
    Color1 = rgb(255, 248, 210),
    Color2 = rgb(253, 212, 121),
    Rate = 6,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.08,
    Spread = 180,
    SizeStart = 0.54,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 34,
    Drag = 0.6,
    AccelerationY = -0.7,
    AuraRadius = 2.06,
    OrbitSpeed = 0.51,
    OrbitCount = 7,
    TrailLifetime = 0.32,
    BurstCount = 7,
    MoteSize = 0.23,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_204")

AWE.Catalog.Effects["FX_205"] = {
    Key = "FX_205",
    Name = "Frostfire Dust 205",
    Category = "Dust",
    Description = "Frostfire dust cosmetic profile 205",
    Color1 = rgb(233, 244, 246),
    Color2 = rgb(118, 201, 255),
    Rate = 13,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 3.53,
    Spread = 60,
    SizeStart = 0.23,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 43,
    Drag = 1.05,
    AccelerationY = -0.2,
    AuraRadius = 2.83,
    OrbitSpeed = 1.55,
    OrbitCount = 8,
    TrailLifetime = 0.53,
    BurstCount = 10,
    MoteSize = 0.3,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_205")

AWE.Catalog.Effects["FX_206"] = {
    Key = "FX_206",
    Name = "Iridescent Dust 206",
    Category = "Dust",
    Description = "Iridescent dust cosmetic profile 206",
    Color1 = rgb(255, 226, 254),
    Color2 = rgb(162, 226, 251),
    Rate = 5,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 2.74,
    Spread = 90,
    SizeStart = 0.4,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 52,
    Drag = 0.3,
    AccelerationY = 0.3,
    AuraRadius = 1.62,
    OrbitSpeed = 0.59,
    OrbitCount = 9,
    TrailLifetime = 0.74,
    BurstCount = 13,
    MoteSize = 0.36,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_206")

AWE.Catalog.Effects["FX_207"] = {
    Key = "FX_207",
    Name = "Cloud Nine Dust 207",
    Category = "Dust",
    Description = "Cloud Nine dust cosmetic profile 207",
    Color1 = rgb(251, 251, 251),
    Color2 = rgb(208, 234, 255),
    Rate = 12,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.91,
    Spread = 120,
    SizeStart = 0.58,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 61,
    Drag = 0.75,
    AccelerationY = -0.7,
    AuraRadius = 2.39,
    OrbitSpeed = 1.63,
    OrbitCount = 10,
    TrailLifetime = 0.95,
    BurstCount = 16,
    MoteSize = 0.12,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_207")

AWE.Catalog.Effects["FX_208"] = {
    Key = "FX_208",
    Name = "Deep Aqua Dust 208",
    Category = "Dust",
    Description = "Deep Aqua dust cosmetic profile 208",
    Color1 = rgb(121, 255, 255),
    Color2 = rgb(20, 149, 196),
    Rate = 4,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 2.12,
    Spread = 150,
    SizeStart = 0.26,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 70,
    Drag = 0.0,
    AccelerationY = -0.2,
    AuraRadius = 3.16,
    OrbitSpeed = 0.67,
    OrbitCount = 3,
    TrailLifetime = 0.25,
    BurstCount = 19,
    MoteSize = 0.19,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_208")

AWE.Catalog.Effects["FX_209"] = {
    Key = "FX_209",
    Name = "Lilac Mist Dust 209",
    Category = "Dust",
    Description = "Lilac Mist dust cosmetic profile 209",
    Color1 = rgb(231, 218, 255),
    Color2 = rgb(163, 150, 235),
    Rate = 11,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 2.29,
    Spread = 180,
    SizeStart = 0.44,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 79,
    Drag = 0.45,
    AccelerationY = 0.3,
    AuraRadius = 1.95,
    OrbitSpeed = 1.71,
    OrbitCount = 4,
    TrailLifetime = 0.46,
    BurstCount = 22,
    MoteSize = 0.26,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_209")

AWE.Catalog.Effects["FX_210"] = {
    Key = "FX_210",
    Name = "Silver Rain Dust 210",
    Category = "Dust",
    Description = "Silver Rain dust cosmetic profile 210",
    Color1 = rgb(227, 235, 244),
    Color2 = rgb(160, 187, 212),
    Rate = 3,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 2.46,
    Spread = 60,
    SizeStart = 0.12,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 88,
    Drag = 0.9,
    AccelerationY = -0.7,
    AuraRadius = 2.72,
    OrbitSpeed = 0.75,
    OrbitCount = 5,
    TrailLifetime = 0.67,
    BurstCount = 4,
    MoteSize = 0.33,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_210")

AWE.Catalog.Effects["FX_211"] = {
    Key = "FX_211",
    Name = "Pearl Comet 211",
    Category = "Comet",
    Description = "Pearl comet cosmetic profile 211",
    Color1 = rgb(250, 255, 255),
    Color2 = rgb(103, 219, 235),
    Rate = 10,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 1.67,
    Spread = 90,
    SizeStart = 0.3,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 97,
    Drag = 0.15,
    AccelerationY = -0.2,
    AuraRadius = 1.51,
    OrbitSpeed = 1.79,
    OrbitCount = 6,
    TrailLifetime = 0.88,
    BurstCount = 7,
    MoteSize = 0.4,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_211")

AWE.Catalog.Effects["FX_212"] = {
    Key = "FX_212",
    Name = "Aurora Comet 212",
    Category = "Comet",
    Description = "Aurora comet cosmetic profile 212",
    Color1 = rgb(100, 240, 226),
    Color2 = rgb(114, 150, 255),
    Rate = 17,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.84,
    Spread = 120,
    SizeStart = 0.47,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 106,
    Drag = 0.6,
    AccelerationY = 0.3,
    AuraRadius = 2.28,
    OrbitSpeed = 0.83,
    OrbitCount = 7,
    TrailLifetime = 1.09,
    BurstCount = 10,
    MoteSize = 0.15,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_212")

AWE.Catalog.Effects["FX_213"] = {
    Key = "FX_213",
    Name = "Moonlight Comet 213",
    Category = "Comet",
    Description = "Moonlight comet cosmetic profile 213",
    Color1 = rgb(241, 250, 255),
    Color2 = rgb(158, 181, 249),
    Rate = 9,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.01,
    Spread = 150,
    SizeStart = 0.15,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 115,
    Drag = 1.05,
    AccelerationY = -0.7,
    AuraRadius = 3.05,
    OrbitSpeed = 1.87,
    OrbitCount = 8,
    TrailLifetime = 0.39,
    BurstCount = 13,
    MoteSize = 0.23,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_213")

AWE.Catalog.Effects["FX_214"] = {
    Key = "FX_214",
    Name = "Rose Quartz Comet 214",
    Category = "Comet",
    Description = "Rose Quartz comet cosmetic profile 214",
    Color1 = rgb(254, 209, 231),
    Color2 = rgb(239, 132, 193),
    Rate = 16,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.22,
    Spread = 180,
    SizeStart = 0.33,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 124,
    Drag = 0.3,
    AccelerationY = -0.2,
    AuraRadius = 1.84,
    OrbitSpeed = 0.91,
    OrbitCount = 9,
    TrailLifetime = 0.6,
    BurstCount = 16,
    MoteSize = 0.3,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_214")

AWE.Catalog.Effects["FX_215"] = {
    Key = "FX_215",
    Name = "Starlace Comet 215",
    Category = "Comet",
    Description = "Starlace comet cosmetic profile 215",
    Color1 = rgb(242, 242, 242),
    Color2 = rgb(195, 228, 255),
    Rate = 8,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 1.39,
    Spread = 60,
    SizeStart = 0.51,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 133,
    Drag = 0.75,
    AccelerationY = 0.3,
    AuraRadius = 2.61,
    OrbitSpeed = 1.95,
    OrbitCount = 10,
    TrailLifetime = 0.81,
    BurstCount = 19,
    MoteSize = 0.36,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_215")

AWE.Catalog.Effects["FX_216"] = {
    Key = "FX_216",
    Name = "Glacier Comet 216",
    Category = "Comet",
    Description = "Glacier comet cosmetic profile 216",
    Color1 = rgb(204, 252, 255),
    Color2 = rgb(72, 183, 233),
    Rate = 15,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 0.6,
    Spread = 90,
    SizeStart = 0.19,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 142,
    Drag = 0.0,
    AccelerationY = -0.7,
    AuraRadius = 1.4,
    OrbitSpeed = 0.99,
    OrbitCount = 3,
    TrailLifetime = 1.02,
    BurstCount = 22,
    MoteSize = 0.12,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_216")

AWE.Catalog.Effects["FX_217"] = {
    Key = "FX_217",
    Name = "Opaline Comet 217",
    Category = "Comet",
    Description = "Opaline comet cosmetic profile 217",
    Color1 = rgb(237, 216, 247),
    Color2 = rgb(182, 158, 255),
    Rate = 7,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 3.05,
    Spread = 120,
    SizeStart = 0.36,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 21,
    Drag = 0.45,
    AccelerationY = -0.2,
    AuraRadius = 2.17,
    OrbitSpeed = 2.03,
    OrbitCount = 4,
    TrailLifetime = 0.32,
    BurstCount = 4,
    MoteSize = 0.19,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_217")

AWE.Catalog.Effects["FX_218"] = {
    Key = "FX_218",
    Name = "Sea Glass Comet 218",
    Category = "Comet",
    Description = "Sea Glass comet cosmetic profile 218",
    Color1 = rgb(193, 255, 248),
    Color2 = rgb(46, 200, 174),
    Rate = 14,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 3.22,
    Spread = 150,
    SizeStart = 0.54,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 30,
    Drag = 0.9,
    AccelerationY = 0.3,
    AuraRadius = 2.94,
    OrbitSpeed = 1.07,
    OrbitCount = 5,
    TrailLifetime = 0.53,
    BurstCount = 7,
    MoteSize = 0.26,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_218")

AWE.Catalog.Effects["FX_219"] = {
    Key = "FX_219",
    Name = "Halo Comet 219",
    Category = "Comet",
    Description = "Halo comet cosmetic profile 219",
    Color1 = rgb(252, 242, 204),
    Color2 = rgb(255, 215, 124),
    Rate = 6,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 2.43,
    Spread = 180,
    SizeStart = 0.23,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 39,
    Drag = 0.15,
    AccelerationY = -0.7,
    AuraRadius = 1.73,
    OrbitSpeed = 2.11,
    OrbitCount = 6,
    TrailLifetime = 0.74,
    BurstCount = 10,
    MoteSize = 0.33,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_219")

AWE.Catalog.Effects["FX_220"] = {
    Key = "FX_220",
    Name = "Frostfire Comet 220",
    Category = "Comet",
    Description = "Frostfire comet cosmetic profile 220",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(107, 190, 248),
    Rate = 13,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 2.6,
    Spread = 60,
    SizeStart = 0.4,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 48,
    Drag = 0.6,
    AccelerationY = -0.2,
    AuraRadius = 2.5,
    OrbitSpeed = 1.15,
    OrbitCount = 7,
    TrailLifetime = 0.95,
    BurstCount = 13,
    MoteSize = 0.4,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_220")

AWE.Catalog.Effects["FX_221"] = {
    Key = "FX_221",
    Name = "Iridescent Comet 221",
    Category = "Comet",
    Description = "Iridescent comet cosmetic profile 221",
    Color1 = rgb(255, 220, 248),
    Color2 = rgb(165, 229, 254),
    Rate = 5,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.77,
    Spread = 90,
    SizeStart = 0.58,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 57,
    Drag = 1.05,
    AccelerationY = 0.3,
    AuraRadius = 3.27,
    OrbitSpeed = 2.19,
    OrbitCount = 8,
    TrailLifetime = 0.25,
    BurstCount = 16,
    MoteSize = 0.15,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_221")

AWE.Catalog.Effects["FX_222"] = {
    Key = "FX_222",
    Name = "Cloud Nine Comet 222",
    Category = "Comet",
    Description = "Cloud Nine comet cosmetic profile 222",
    Color1 = rgb(245, 245, 245),
    Color2 = rgb(211, 237, 255),
    Rate = 12,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.98,
    Spread = 120,
    SizeStart = 0.26,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 66,
    Drag = 0.3,
    AccelerationY = -0.7,
    AuraRadius = 2.06,
    OrbitSpeed = 1.23,
    OrbitCount = 9,
    TrailLifetime = 0.46,
    BurstCount = 19,
    MoteSize = 0.23,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_222")

AWE.Catalog.Effects["FX_223"] = {
    Key = "FX_223",
    Name = "Deep Aqua Comet 223",
    Category = "Comet",
    Description = "Deep Aqua comet cosmetic profile 223",
    Color1 = rgb(115, 252, 252),
    Color2 = rgb(23, 152, 199),
    Rate = 4,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.15,
    Spread = 150,
    SizeStart = 0.44,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 75,
    Drag = 0.75,
    AccelerationY = -0.2,
    AuraRadius = 2.83,
    OrbitSpeed = 2.27,
    OrbitCount = 10,
    TrailLifetime = 0.67,
    BurstCount = 22,
    MoteSize = 0.3,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_223")

AWE.Catalog.Effects["FX_224"] = {
    Key = "FX_224",
    Name = "Lilac Mist Comet 224",
    Category = "Comet",
    Description = "Lilac Mist comet cosmetic profile 224",
    Color1 = rgb(225, 212, 250),
    Color2 = rgb(166, 153, 238),
    Rate = 11,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 1.36,
    Spread = 180,
    SizeStart = 0.12,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 84,
    Drag = 0.0,
    AccelerationY = 0.3,
    AuraRadius = 1.62,
    OrbitSpeed = 1.31,
    OrbitCount = 3,
    TrailLifetime = 0.88,
    BurstCount = 4,
    MoteSize = 0.36,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_224")

AWE.Catalog.Effects["FX_225"] = {
    Key = "FX_225",
    Name = "Silver Rain Comet 225",
    Category = "Comet",
    Description = "Silver Rain comet cosmetic profile 225",
    Color1 = rgb(250, 255, 255),
    Color2 = rgb(149, 176, 201),
    Rate = 3,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 1.53,
    Spread = 60,
    SizeStart = 0.3,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 93,
    Drag = 0.45,
    AccelerationY = -0.7,
    AuraRadius = 2.39,
    OrbitSpeed = 0.35,
    OrbitCount = 4,
    TrailLifetime = 1.09,
    BurstCount = 7,
    MoteSize = 0.12,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_225")

AWE.Catalog.Effects["FX_226"] = {
    Key = "FX_226",
    Name = "Pearl Halo 226",
    Category = "Halo",
    Description = "Pearl halo cosmetic profile 226",
    Color1 = rgb(244, 252, 255),
    Color2 = rgb(106, 222, 238),
    Rate = 10,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 1.7,
    Spread = 90,
    SizeStart = 0.47,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 102,
    Drag = 0.9,
    AccelerationY = -0.2,
    AuraRadius = 3.16,
    OrbitSpeed = 1.39,
    OrbitCount = 5,
    TrailLifetime = 0.39,
    BurstCount = 10,
    MoteSize = 0.19,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_226")

AWE.Catalog.Effects["FX_227"] = {
    Key = "FX_227",
    Name = "Aurora Halo 227",
    Category = "Halo",
    Description = "Aurora halo cosmetic profile 227",
    Color1 = rgb(94, 234, 220),
    Color2 = rgb(117, 153, 255),
    Rate = 17,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 0.91,
    Spread = 120,
    SizeStart = 0.15,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 111,
    Drag = 0.15,
    AccelerationY = 0.3,
    AuraRadius = 1.95,
    OrbitSpeed = 0.43,
    OrbitCount = 6,
    TrailLifetime = 0.6,
    BurstCount = 13,
    MoteSize = 0.26,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_227")

AWE.Catalog.Effects["FX_228"] = {
    Key = "FX_228",
    Name = "Moonlight Halo 228",
    Category = "Halo",
    Description = "Moonlight halo cosmetic profile 228",
    Color1 = rgb(235, 244, 255),
    Color2 = rgb(161, 184, 252),
    Rate = 9,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.08,
    Spread = 150,
    SizeStart = 0.33,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 120,
    Drag = 0.6,
    AccelerationY = -0.7,
    AuraRadius = 2.72,
    OrbitSpeed = 1.47,
    OrbitCount = 7,
    TrailLifetime = 0.81,
    BurstCount = 16,
    MoteSize = 0.33,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_228")

AWE.Catalog.Effects["FX_229"] = {
    Key = "FX_229",
    Name = "Rose Quartz Halo 229",
    Category = "Halo",
    Description = "Rose Quartz halo cosmetic profile 229",
    Color1 = rgb(248, 203, 225),
    Color2 = rgb(242, 135, 196),
    Rate = 16,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 3.53,
    Spread = 180,
    SizeStart = 0.51,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 129,
    Drag = 1.05,
    AccelerationY = -0.2,
    AuraRadius = 1.51,
    OrbitSpeed = 0.51,
    OrbitCount = 8,
    TrailLifetime = 1.02,
    BurstCount = 19,
    MoteSize = 0.4,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_229")

AWE.Catalog.Effects["FX_230"] = {
    Key = "FX_230",
    Name = "Starlace Halo 230",
    Category = "Halo",
    Description = "Starlace halo cosmetic profile 230",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(184, 217, 250),
    Rate = 8,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 2.74,
    Spread = 60,
    SizeStart = 0.19,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 138,
    Drag = 0.3,
    AccelerationY = 0.3,
    AuraRadius = 2.28,
    OrbitSpeed = 1.55,
    OrbitCount = 9,
    TrailLifetime = 0.32,
    BurstCount = 22,
    MoteSize = 0.15,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_230")

AWE.Catalog.Effects["FX_231"] = {
    Key = "FX_231",
    Name = "Glacier Halo 231",
    Category = "Halo",
    Description = "Glacier halo cosmetic profile 231",
    Color1 = rgb(198, 246, 253),
    Color2 = rgb(75, 186, 236),
    Rate = 15,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.91,
    Spread = 90,
    SizeStart = 0.36,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 147,
    Drag = 0.75,
    AccelerationY = -0.7,
    AuraRadius = 3.05,
    OrbitSpeed = 0.59,
    OrbitCount = 10,
    TrailLifetime = 0.53,
    BurstCount = 4,
    MoteSize = 0.23,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_231")

AWE.Catalog.Effects["FX_232"] = {
    Key = "FX_232",
    Name = "Opaline Halo 232",
    Category = "Halo",
    Description = "Opaline halo cosmetic profile 232",
    Color1 = rgb(231, 210, 241),
    Color2 = rgb(185, 161, 255),
    Rate = 7,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 2.12,
    Spread = 120,
    SizeStart = 0.54,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 26,
    Drag = 0.0,
    AccelerationY = -0.2,
    AuraRadius = 1.84,
    OrbitSpeed = 1.63,
    OrbitCount = 3,
    TrailLifetime = 0.74,
    BurstCount = 7,
    MoteSize = 0.3,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_232")

AWE.Catalog.Effects["FX_233"] = {
    Key = "FX_233",
    Name = "Sea Glass Halo 233",
    Category = "Halo",
    Description = "Sea Glass halo cosmetic profile 233",
    Color1 = rgb(187, 255, 242),
    Color2 = rgb(49, 203, 177),
    Rate = 14,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 2.29,
    Spread = 150,
    SizeStart = 0.23,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 35,
    Drag = 0.45,
    AccelerationY = 0.3,
    AuraRadius = 2.61,
    OrbitSpeed = 0.67,
    OrbitCount = 4,
    TrailLifetime = 0.95,
    BurstCount = 10,
    MoteSize = 0.36,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_233")

AWE.Catalog.Effects["FX_234"] = {
    Key = "FX_234",
    Name = "Halo Halo 234",
    Category = "Halo",
    Description = "Halo halo cosmetic profile 234",
    Color1 = rgb(246, 236, 198),
    Color2 = rgb(255, 218, 127),
    Rate = 6,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 2.46,
    Spread = 180,
    SizeStart = 0.4,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 44,
    Drag = 0.9,
    AccelerationY = -0.7,
    AuraRadius = 1.4,
    OrbitSpeed = 1.71,
    OrbitCount = 5,
    TrailLifetime = 0.25,
    BurstCount = 13,
    MoteSize = 0.12,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_234")

AWE.Catalog.Effects["FX_235"] = {
    Key = "FX_235",
    Name = "Frostfire Halo 235",
    Category = "Halo",
    Description = "Frostfire halo cosmetic profile 235",
    Color1 = rgb(250, 255, 255),
    Color2 = rgb(110, 193, 251),
    Rate = 13,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 1.67,
    Spread = 60,
    SizeStart = 0.58,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 53,
    Drag = 0.15,
    AccelerationY = -0.2,
    AuraRadius = 2.17,
    OrbitSpeed = 0.75,
    OrbitCount = 6,
    TrailLifetime = 0.46,
    BurstCount = 16,
    MoteSize = 0.19,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_235")

AWE.Catalog.Effects["FX_236"] = {
    Key = "FX_236",
    Name = "Iridescent Halo 236",
    Category = "Halo",
    Description = "Iridescent halo cosmetic profile 236",
    Color1 = rgb(251, 214, 242),
    Color2 = rgb(168, 232, 255),
    Rate = 5,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.84,
    Spread = 90,
    SizeStart = 0.26,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 62,
    Drag = 0.6,
    AccelerationY = 0.3,
    AuraRadius = 2.94,
    OrbitSpeed = 1.79,
    OrbitCount = 7,
    TrailLifetime = 0.67,
    BurstCount = 19,
    MoteSize = 0.26,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_236")

AWE.Catalog.Effects["FX_237"] = {
    Key = "FX_237",
    Name = "Cloud Nine Halo 237",
    Category = "Halo",
    Description = "Cloud Nine halo cosmetic profile 237",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(199, 225, 248),
    Rate = 12,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.01,
    Spread = 120,
    SizeStart = 0.44,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 71,
    Drag = 1.05,
    AccelerationY = -0.7,
    AuraRadius = 1.73,
    OrbitSpeed = 0.83,
    OrbitCount = 8,
    TrailLifetime = 0.88,
    BurstCount = 22,
    MoteSize = 0.33,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_237")

AWE.Catalog.Effects["FX_238"] = {
    Key = "FX_238",
    Name = "Deep Aqua Halo 238",
    Category = "Halo",
    Description = "Deep Aqua halo cosmetic profile 238",
    Color1 = rgb(109, 246, 246),
    Color2 = rgb(26, 155, 202),
    Rate = 4,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.22,
    Spread = 150,
    SizeStart = 0.12,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 80,
    Drag = 0.3,
    AccelerationY = -0.2,
    AuraRadius = 2.5,
    OrbitSpeed = 1.87,
    OrbitCount = 9,
    TrailLifetime = 1.09,
    BurstCount = 4,
    MoteSize = 0.4,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_238")

AWE.Catalog.Effects["FX_239"] = {
    Key = "FX_239",
    Name = "Lilac Mist Halo 239",
    Category = "Halo",
    Description = "Lilac Mist halo cosmetic profile 239",
    Color1 = rgb(219, 206, 244),
    Color2 = rgb(169, 156, 241),
    Rate = 11,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 1.39,
    Spread = 180,
    SizeStart = 0.3,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 89,
    Drag = 0.75,
    AccelerationY = 0.3,
    AuraRadius = 3.27,
    OrbitSpeed = 0.91,
    OrbitCount = 10,
    TrailLifetime = 0.39,
    BurstCount = 7,
    MoteSize = 0.15,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_239")

AWE.Catalog.Effects["FX_240"] = {
    Key = "FX_240",
    Name = "Silver Rain Halo 240",
    Category = "Halo",
    Description = "Silver Rain halo cosmetic profile 240",
    Color1 = rgb(244, 252, 255),
    Color2 = rgb(152, 179, 204),
    Rate = 3,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 0.6,
    Spread = 60,
    SizeStart = 0.47,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 98,
    Drag = 0.0,
    AccelerationY = -0.7,
    AuraRadius = 2.06,
    OrbitSpeed = 1.95,
    OrbitCount = 3,
    TrailLifetime = 0.6,
    BurstCount = 10,
    MoteSize = 0.23,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_240")

AWE.Catalog.Effects["FX_241"] = {
    Key = "FX_241",
    Name = "Pearl Spark 241",
    Category = "Spark",
    Description = "Pearl spark cosmetic profile 241",
    Color1 = rgb(238, 246, 249),
    Color2 = rgb(109, 225, 241),
    Rate = 10,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 3.05,
    Spread = 90,
    SizeStart = 0.15,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 107,
    Drag = 0.45,
    AccelerationY = -0.2,
    AuraRadius = 2.83,
    OrbitSpeed = 0.99,
    OrbitCount = 4,
    TrailLifetime = 0.81,
    BurstCount = 13,
    MoteSize = 0.3,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_241")

AWE.Catalog.Effects["FX_242"] = {
    Key = "FX_242",
    Name = "Aurora Spark 242",
    Category = "Spark",
    Description = "Aurora spark cosmetic profile 242",
    Color1 = rgb(117, 255, 243),
    Color2 = rgb(105, 141, 249),
    Rate = 17,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 3.22,
    Spread = 120,
    SizeStart = 0.33,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 116,
    Drag = 0.9,
    AccelerationY = 0.3,
    AuraRadius = 1.62,
    OrbitSpeed = 2.03,
    OrbitCount = 5,
    TrailLifetime = 1.02,
    BurstCount = 16,
    MoteSize = 0.36,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_242")

AWE.Catalog.Effects["FX_243"] = {
    Key = "FX_243",
    Name = "Moonlight Spark 243",
    Category = "Spark",
    Description = "Moonlight spark cosmetic profile 243",
    Color1 = rgb(229, 238, 254),
    Color2 = rgb(164, 187, 255),
    Rate = 9,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 2.43,
    Spread = 150,
    SizeStart = 0.51,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 125,
    Drag = 0.15,
    AccelerationY = -0.7,
    AuraRadius = 2.39,
    OrbitSpeed = 1.07,
    OrbitCount = 6,
    TrailLifetime = 0.32,
    BurstCount = 19,
    MoteSize = 0.12,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_243")

AWE.Catalog.Effects["FX_244"] = {
    Key = "FX_244",
    Name = "Rose Quartz Spark 244",
    Category = "Spark",
    Description = "Rose Quartz spark cosmetic profile 244",
    Color1 = rgb(242, 197, 219),
    Color2 = rgb(245, 138, 199),
    Rate = 16,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 2.6,
    Spread = 180,
    SizeStart = 0.19,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 134,
    Drag = 0.6,
    AccelerationY = -0.2,
    AuraRadius = 3.16,
    OrbitSpeed = 2.11,
    OrbitCount = 7,
    TrailLifetime = 0.53,
    BurstCount = 22,
    MoteSize = 0.19,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_244")

AWE.Catalog.Effects["FX_245"] = {
    Key = "FX_245",
    Name = "Starlace Spark 245",
    Category = "Spark",
    Description = "Starlace spark cosmetic profile 245",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(187, 220, 253),
    Rate = 8,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.77,
    Spread = 60,
    SizeStart = 0.36,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 143,
    Drag = 1.05,
    AccelerationY = 0.3,
    AuraRadius = 1.95,
    OrbitSpeed = 1.15,
    OrbitCount = 8,
    TrailLifetime = 0.74,
    BurstCount = 4,
    MoteSize = 0.26,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_245")

AWE.Catalog.Effects["FX_246"] = {
    Key = "FX_246",
    Name = "Glacier Spark 246",
    Category = "Spark",
    Description = "Glacier spark cosmetic profile 246",
    Color1 = rgb(192, 240, 247),
    Color2 = rgb(78, 189, 239),
    Rate = 15,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.98,
    Spread = 90,
    SizeStart = 0.54,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 22,
    Drag = 0.3,
    AccelerationY = -0.7,
    AuraRadius = 2.72,
    OrbitSpeed = 2.19,
    OrbitCount = 9,
    TrailLifetime = 0.95,
    BurstCount = 7,
    MoteSize = 0.33,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_246")

AWE.Catalog.Effects["FX_247"] = {
    Key = "FX_247",
    Name = "Opaline Spark 247",
    Category = "Spark",
    Description = "Opaline spark cosmetic profile 247",
    Color1 = rgb(254, 233, 255),
    Color2 = rgb(173, 149, 250),
    Rate = 7,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.15,
    Spread = 120,
    SizeStart = 0.23,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 31,
    Drag = 0.75,
    AccelerationY = -0.2,
    AuraRadius = 1.51,
    OrbitSpeed = 1.23,
    OrbitCount = 10,
    TrailLifetime = 0.25,
    BurstCount = 10,
    MoteSize = 0.4,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_247")

AWE.Catalog.Effects["FX_248"] = {
    Key = "FX_248",
    Name = "Sea Glass Spark 248",
    Category = "Spark",
    Description = "Sea Glass spark cosmetic profile 248",
    Color1 = rgb(181, 252, 236),
    Color2 = rgb(52, 206, 180),
    Rate = 14,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 1.36,
    Spread = 150,
    SizeStart = 0.4,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 40,
    Drag = 0.0,
    AccelerationY = 0.3,
    AuraRadius = 2.28,
    OrbitSpeed = 2.27,
    OrbitCount = 3,
    TrailLifetime = 0.46,
    BurstCount = 13,
    MoteSize = 0.15,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_248")

AWE.Catalog.Effects["FX_249"] = {
    Key = "FX_249",
    Name = "Halo Spark 249",
    Category = "Spark",
    Description = "Halo spark cosmetic profile 249",
    Color1 = rgb(255, 255, 221),
    Color2 = rgb(248, 207, 116),
    Rate = 6,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 1.53,
    Spread = 180,
    SizeStart = 0.58,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 49,
    Drag = 0.45,
    AccelerationY = -0.7,
    AuraRadius = 3.05,
    OrbitSpeed = 1.31,
    OrbitCount = 4,
    TrailLifetime = 0.67,
    BurstCount = 16,
    MoteSize = 0.23,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_249")

AWE.Catalog.Effects["FX_250"] = {
    Key = "FX_250",
    Name = "Frostfire Spark 250",
    Category = "Spark",
    Description = "Frostfire spark cosmetic profile 250",
    Color1 = rgb(244, 255, 255),
    Color2 = rgb(113, 196, 254),
    Rate = 13,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 1.7,
    Spread = 60,
    SizeStart = 0.26,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 58,
    Drag = 0.9,
    AccelerationY = -0.2,
    AuraRadius = 1.84,
    OrbitSpeed = 0.35,
    OrbitCount = 5,
    TrailLifetime = 0.88,
    BurstCount = 19,
    MoteSize = 0.3,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_250")

AWE.Catalog.Effects["FX_251"] = {
    Key = "FX_251",
    Name = "Iridescent Spark 251",
    Category = "Spark",
    Description = "Iridescent spark cosmetic profile 251",
    Color1 = rgb(245, 208, 236),
    Color2 = rgb(171, 235, 255),
    Rate = 5,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 0.91,
    Spread = 90,
    SizeStart = 0.44,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 67,
    Drag = 0.15,
    AccelerationY = 0.3,
    AuraRadius = 2.61,
    OrbitSpeed = 1.39,
    OrbitCount = 6,
    TrailLifetime = 1.09,
    BurstCount = 22,
    MoteSize = 0.36,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_251")

AWE.Catalog.Effects["FX_252"] = {
    Key = "FX_252",
    Name = "Cloud Nine Spark 252",
    Category = "Spark",
    Description = "Cloud Nine spark cosmetic profile 252",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(202, 228, 251),
    Rate = 12,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.08,
    Spread = 120,
    SizeStart = 0.12,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 76,
    Drag = 0.6,
    AccelerationY = -0.7,
    AuraRadius = 1.4,
    OrbitSpeed = 0.43,
    OrbitCount = 7,
    TrailLifetime = 0.39,
    BurstCount = 4,
    MoteSize = 0.12,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_252")

AWE.Catalog.Effects["FX_253"] = {
    Key = "FX_253",
    Name = "Deep Aqua Spark 253",
    Category = "Spark",
    Description = "Deep Aqua spark cosmetic profile 253",
    Color1 = rgb(103, 240, 240),
    Color2 = rgb(29, 158, 205),
    Rate = 4,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 3.53,
    Spread = 150,
    SizeStart = 0.3,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 85,
    Drag = 1.05,
    AccelerationY = -0.2,
    AuraRadius = 2.17,
    OrbitSpeed = 1.47,
    OrbitCount = 8,
    TrailLifetime = 0.6,
    BurstCount = 7,
    MoteSize = 0.19,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_253")

AWE.Catalog.Effects["FX_254"] = {
    Key = "FX_254",
    Name = "Lilac Mist Spark 254",
    Category = "Spark",
    Description = "Lilac Mist spark cosmetic profile 254",
    Color1 = rgb(242, 229, 255),
    Color2 = rgb(158, 145, 230),
    Rate = 11,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 2.74,
    Spread = 180,
    SizeStart = 0.47,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 94,
    Drag = 0.3,
    AccelerationY = 0.3,
    AuraRadius = 2.94,
    OrbitSpeed = 0.51,
    OrbitCount = 9,
    TrailLifetime = 0.81,
    BurstCount = 10,
    MoteSize = 0.26,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_254")

AWE.Catalog.Effects["FX_255"] = {
    Key = "FX_255",
    Name = "Silver Rain Spark 255",
    Category = "Spark",
    Description = "Silver Rain spark cosmetic profile 255",
    Color1 = rgb(238, 246, 255),
    Color2 = rgb(155, 182, 207),
    Rate = 3,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.91,
    Spread = 60,
    SizeStart = 0.15,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 103,
    Drag = 0.75,
    AccelerationY = -0.7,
    AuraRadius = 1.73,
    OrbitSpeed = 1.55,
    OrbitCount = 10,
    TrailLifetime = 1.02,
    BurstCount = 13,
    MoteSize = 0.33,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_255")

AWE.Catalog.Effects["FX_256"] = {
    Key = "FX_256",
    Name = "Pearl Ribbon 256",
    Category = "Ribbon",
    Description = "Pearl ribbon cosmetic profile 256",
    Color1 = rgb(232, 240, 243),
    Color2 = rgb(112, 228, 244),
    Rate = 10,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 2.12,
    Spread = 90,
    SizeStart = 0.33,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 112,
    Drag = 0.0,
    AccelerationY = -0.2,
    AuraRadius = 2.5,
    OrbitSpeed = 0.59,
    OrbitCount = 3,
    TrailLifetime = 0.32,
    BurstCount = 16,
    MoteSize = 0.4,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_256")

AWE.Catalog.Effects["FX_257"] = {
    Key = "FX_257",
    Name = "Aurora Ribbon 257",
    Category = "Ribbon",
    Description = "Aurora ribbon cosmetic profile 257",
    Color1 = rgb(111, 251, 237),
    Color2 = rgb(108, 144, 252),
    Rate = 17,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 2.29,
    Spread = 120,
    SizeStart = 0.51,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 121,
    Drag = 0.45,
    AccelerationY = 0.3,
    AuraRadius = 3.27,
    OrbitSpeed = 1.63,
    OrbitCount = 4,
    TrailLifetime = 0.53,
    BurstCount = 19,
    MoteSize = 0.15,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_257")

AWE.Catalog.Effects["FX_258"] = {
    Key = "FX_258",
    Name = "Moonlight Ribbon 258",
    Category = "Ribbon",
    Description = "Moonlight ribbon cosmetic profile 258",
    Color1 = rgb(223, 232, 248),
    Color2 = rgb(167, 190, 255),
    Rate = 9,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 2.46,
    Spread = 150,
    SizeStart = 0.19,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 130,
    Drag = 0.9,
    AccelerationY = -0.7,
    AuraRadius = 2.06,
    OrbitSpeed = 0.67,
    OrbitCount = 5,
    TrailLifetime = 0.74,
    BurstCount = 22,
    MoteSize = 0.23,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_258")

AWE.Catalog.Effects["FX_259"] = {
    Key = "FX_259",
    Name = "Rose Quartz Ribbon 259",
    Category = "Ribbon",
    Description = "Rose Quartz ribbon cosmetic profile 259",
    Color1 = rgb(255, 220, 242),
    Color2 = rgb(234, 127, 188),
    Rate = 16,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 1.67,
    Spread = 180,
    SizeStart = 0.36,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 139,
    Drag = 0.15,
    AccelerationY = -0.2,
    AuraRadius = 2.83,
    OrbitSpeed = 1.71,
    OrbitCount = 6,
    TrailLifetime = 0.95,
    BurstCount = 4,
    MoteSize = 0.3,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_259")

AWE.Catalog.Effects["FX_260"] = {
    Key = "FX_260",
    Name = "Starlace Ribbon 260",
    Category = "Ribbon",
    Description = "Starlace ribbon cosmetic profile 260",
    Color1 = rgb(253, 253, 253),
    Color2 = rgb(190, 223, 255),
    Rate = 8,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.84,
    Spread = 60,
    SizeStart = 0.54,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 18,
    Drag = 0.6,
    AccelerationY = 0.3,
    AuraRadius = 1.62,
    OrbitSpeed = 0.75,
    OrbitCount = 7,
    TrailLifetime = 0.25,
    BurstCount = 7,
    MoteSize = 0.36,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_260")

AWE.Catalog.Effects["FX_261"] = {
    Key = "FX_261",
    Name = "Glacier Ribbon 261",
    Category = "Ribbon",
    Description = "Glacier ribbon cosmetic profile 261",
    Color1 = rgb(186, 234, 241),
    Color2 = rgb(81, 192, 242),
    Rate = 15,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.01,
    Spread = 90,
    SizeStart = 0.23,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 27,
    Drag = 1.05,
    AccelerationY = -0.7,
    AuraRadius = 2.39,
    OrbitSpeed = 1.79,
    OrbitCount = 8,
    TrailLifetime = 0.46,
    BurstCount = 10,
    MoteSize = 0.12,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_261")

AWE.Catalog.Effects["FX_262"] = {
    Key = "FX_262",
    Name = "Opaline Ribbon 262",
    Category = "Ribbon",
    Description = "Opaline ribbon cosmetic profile 262",
    Color1 = rgb(248, 227, 255),
    Color2 = rgb(176, 152, 253),
    Rate = 7,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.22,
    Spread = 120,
    SizeStart = 0.4,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 36,
    Drag = 0.3,
    AccelerationY = -0.2,
    AuraRadius = 3.16,
    OrbitSpeed = 0.83,
    OrbitCount = 9,
    TrailLifetime = 0.67,
    BurstCount = 13,
    MoteSize = 0.19,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_262")

AWE.Catalog.Effects["FX_263"] = {
    Key = "FX_263",
    Name = "Sea Glass Ribbon 263",
    Category = "Ribbon",
    Description = "Sea Glass ribbon cosmetic profile 263",
    Color1 = rgb(175, 246, 230),
    Color2 = rgb(55, 209, 183),
    Rate = 14,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 1.39,
    Spread = 150,
    SizeStart = 0.58,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 45,
    Drag = 0.75,
    AccelerationY = 0.3,
    AuraRadius = 1.95,
    OrbitSpeed = 1.87,
    OrbitCount = 10,
    TrailLifetime = 0.88,
    BurstCount = 16,
    MoteSize = 0.26,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_263")

AWE.Catalog.Effects["FX_264"] = {
    Key = "FX_264",
    Name = "Halo Ribbon 264",
    Category = "Ribbon",
    Description = "Halo ribbon cosmetic profile 264",
    Color1 = rgb(255, 253, 215),
    Color2 = rgb(251, 210, 119),
    Rate = 6,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 0.6,
    Spread = 180,
    SizeStart = 0.26,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 54,
    Drag = 0.0,
    AccelerationY = -0.7,
    AuraRadius = 2.72,
    OrbitSpeed = 0.91,
    OrbitCount = 3,
    TrailLifetime = 1.09,
    BurstCount = 19,
    MoteSize = 0.33,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_264")

AWE.Catalog.Effects["FX_265"] = {
    Key = "FX_265",
    Name = "Frostfire Ribbon 265",
    Category = "Ribbon",
    Description = "Frostfire ribbon cosmetic profile 265",
    Color1 = rgb(238, 249, 251),
    Color2 = rgb(116, 199, 255),
    Rate = 13,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 3.05,
    Spread = 60,
    SizeStart = 0.44,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 63,
    Drag = 0.45,
    AccelerationY = -0.2,
    AuraRadius = 1.51,
    OrbitSpeed = 1.95,
    OrbitCount = 4,
    TrailLifetime = 0.39,
    BurstCount = 22,
    MoteSize = 0.4,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_265")

AWE.Catalog.Effects["FX_266"] = {
    Key = "FX_266",
    Name = "Iridescent Ribbon 266",
    Category = "Ribbon",
    Description = "Iridescent ribbon cosmetic profile 266",
    Color1 = rgb(255, 231, 255),
    Color2 = rgb(159, 223, 248),
    Rate = 5,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 3.22,
    Spread = 90,
    SizeStart = 0.12,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 72,
    Drag = 0.9,
    AccelerationY = 0.3,
    AuraRadius = 2.28,
    OrbitSpeed = 0.99,
    OrbitCount = 5,
    TrailLifetime = 0.6,
    BurstCount = 4,
    MoteSize = 0.15,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_266")

AWE.Catalog.Effects["FX_267"] = {
    Key = "FX_267",
    Name = "Cloud Nine Ribbon 267",
    Category = "Ribbon",
    Description = "Cloud Nine ribbon cosmetic profile 267",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(205, 231, 254),
    Rate = 12,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 2.43,
    Spread = 120,
    SizeStart = 0.3,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 81,
    Drag = 0.15,
    AccelerationY = -0.7,
    AuraRadius = 3.05,
    OrbitSpeed = 2.03,
    OrbitCount = 6,
    TrailLifetime = 0.81,
    BurstCount = 7,
    MoteSize = 0.23,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_267")

AWE.Catalog.Effects["FX_268"] = {
    Key = "FX_268",
    Name = "Deep Aqua Ribbon 268",
    Category = "Ribbon",
    Description = "Deep Aqua ribbon cosmetic profile 268",
    Color1 = rgb(97, 234, 234),
    Color2 = rgb(32, 161, 208),
    Rate = 4,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 2.6,
    Spread = 150,
    SizeStart = 0.47,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 90,
    Drag = 0.6,
    AccelerationY = -0.2,
    AuraRadius = 1.84,
    OrbitSpeed = 1.07,
    OrbitCount = 7,
    TrailLifetime = 1.02,
    BurstCount = 10,
    MoteSize = 0.3,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_268")

AWE.Catalog.Effects["FX_269"] = {
    Key = "FX_269",
    Name = "Lilac Mist Ribbon 269",
    Category = "Ribbon",
    Description = "Lilac Mist ribbon cosmetic profile 269",
    Color1 = rgb(236, 223, 255),
    Color2 = rgb(161, 148, 233),
    Rate = 11,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.77,
    Spread = 180,
    SizeStart = 0.15,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 99,
    Drag = 1.05,
    AccelerationY = 0.3,
    AuraRadius = 2.61,
    OrbitSpeed = 2.11,
    OrbitCount = 8,
    TrailLifetime = 0.32,
    BurstCount = 13,
    MoteSize = 0.36,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_269")

AWE.Catalog.Effects["FX_270"] = {
    Key = "FX_270",
    Name = "Silver Rain Ribbon 270",
    Category = "Ribbon",
    Description = "Silver Rain ribbon cosmetic profile 270",
    Color1 = rgb(232, 240, 249),
    Color2 = rgb(158, 185, 210),
    Rate = 3,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.98,
    Spread = 60,
    SizeStart = 0.33,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 108,
    Drag = 0.3,
    AccelerationY = -0.7,
    AuraRadius = 1.4,
    OrbitSpeed = 1.15,
    OrbitCount = 9,
    TrailLifetime = 0.53,
    BurstCount = 16,
    MoteSize = 0.12,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_270")

AWE.Catalog.Effects["FX_271"] = {
    Key = "FX_271",
    Name = "Pearl Orbit 271",
    Category = "Orbit",
    Description = "Pearl orbit cosmetic profile 271",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(100, 216, 232),
    Rate = 10,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.15,
    Spread = 90,
    SizeStart = 0.51,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 117,
    Drag = 0.75,
    AccelerationY = -0.2,
    AuraRadius = 2.17,
    OrbitSpeed = 2.19,
    OrbitCount = 10,
    TrailLifetime = 0.74,
    BurstCount = 19,
    MoteSize = 0.19,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_271")

AWE.Catalog.Effects["FX_272"] = {
    Key = "FX_272",
    Name = "Aurora Orbit 272",
    Category = "Orbit",
    Description = "Aurora orbit cosmetic profile 272",
    Color1 = rgb(105, 245, 231),
    Color2 = rgb(111, 147, 255),
    Rate = 17,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 1.36,
    Spread = 120,
    SizeStart = 0.19,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 126,
    Drag = 0.0,
    AccelerationY = 0.3,
    AuraRadius = 2.94,
    OrbitSpeed = 1.23,
    OrbitCount = 3,
    TrailLifetime = 0.95,
    BurstCount = 22,
    MoteSize = 0.26,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_272")

AWE.Catalog.Effects["FX_273"] = {
    Key = "FX_273",
    Name = "Moonlight Orbit 273",
    Category = "Orbit",
    Description = "Moonlight orbit cosmetic profile 273",
    Color1 = rgb(217, 226, 242),
    Color2 = rgb(170, 193, 255),
    Rate = 9,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 1.53,
    Spread = 150,
    SizeStart = 0.36,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 135,
    Drag = 0.45,
    AccelerationY = -0.7,
    AuraRadius = 1.73,
    OrbitSpeed = 2.27,
    OrbitCount = 4,
    TrailLifetime = 0.25,
    BurstCount = 4,
    MoteSize = 0.33,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_273")

AWE.Catalog.Effects["FX_274"] = {
    Key = "FX_274",
    Name = "Rose Quartz Orbit 274",
    Category = "Orbit",
    Description = "Rose Quartz orbit cosmetic profile 274",
    Color1 = rgb(255, 214, 236),
    Color2 = rgb(237, 130, 191),
    Rate = 16,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 1.7,
    Spread = 180,
    SizeStart = 0.54,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 144,
    Drag = 0.9,
    AccelerationY = -0.2,
    AuraRadius = 2.5,
    OrbitSpeed = 1.31,
    OrbitCount = 5,
    TrailLifetime = 0.46,
    BurstCount = 7,
    MoteSize = 0.4,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_274")

AWE.Catalog.Effects["FX_275"] = {
    Key = "FX_275",
    Name = "Starlace Orbit 275",
    Category = "Orbit",
    Description = "Starlace orbit cosmetic profile 275",
    Color1 = rgb(247, 247, 247),
    Color2 = rgb(193, 226, 255),
    Rate = 8,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 0.91,
    Spread = 60,
    SizeStart = 0.23,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 23,
    Drag = 0.15,
    AccelerationY = 0.3,
    AuraRadius = 3.27,
    OrbitSpeed = 0.35,
    OrbitCount = 6,
    TrailLifetime = 0.67,
    BurstCount = 10,
    MoteSize = 0.15,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_275")

AWE.Catalog.Effects["FX_276"] = {
    Key = "FX_276",
    Name = "Glacier Orbit 276",
    Category = "Orbit",
    Description = "Glacier orbit cosmetic profile 276",
    Color1 = rgb(209, 255, 255),
    Color2 = rgb(69, 180, 230),
    Rate = 15,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.08,
    Spread = 90,
    SizeStart = 0.4,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 32,
    Drag = 0.6,
    AccelerationY = -0.7,
    AuraRadius = 2.06,
    OrbitSpeed = 1.39,
    OrbitCount = 7,
    TrailLifetime = 0.88,
    BurstCount = 13,
    MoteSize = 0.23,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_276")

AWE.Catalog.Effects["FX_277"] = {
    Key = "FX_277",
    Name = "Opaline Orbit 277",
    Category = "Orbit",
    Description = "Opaline orbit cosmetic profile 277",
    Color1 = rgb(242, 221, 252),
    Color2 = rgb(179, 155, 255),
    Rate = 7,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 3.53,
    Spread = 120,
    SizeStart = 0.58,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 41,
    Drag = 1.05,
    AccelerationY = -0.2,
    AuraRadius = 2.83,
    OrbitSpeed = 0.43,
    OrbitCount = 8,
    TrailLifetime = 1.09,
    BurstCount = 16,
    MoteSize = 0.3,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_277")

AWE.Catalog.Effects["FX_278"] = {
    Key = "FX_278",
    Name = "Sea Glass Orbit 278",
    Category = "Orbit",
    Description = "Sea Glass orbit cosmetic profile 278",
    Color1 = rgb(198, 255, 253),
    Color2 = rgb(44, 198, 172),
    Rate = 14,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 2.74,
    Spread = 150,
    SizeStart = 0.26,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 50,
    Drag = 0.3,
    AccelerationY = 0.3,
    AuraRadius = 1.62,
    OrbitSpeed = 1.47,
    OrbitCount = 9,
    TrailLifetime = 0.39,
    BurstCount = 19,
    MoteSize = 0.36,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_278")

AWE.Catalog.Effects["FX_279"] = {
    Key = "FX_279",
    Name = "Halo Orbit 279",
    Category = "Orbit",
    Description = "Halo orbit cosmetic profile 279",
    Color1 = rgb(255, 247, 209),
    Color2 = rgb(254, 213, 122),
    Rate = 6,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.91,
    Spread = 180,
    SizeStart = 0.44,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 59,
    Drag = 0.75,
    AccelerationY = -0.7,
    AuraRadius = 2.39,
    OrbitSpeed = 0.51,
    OrbitCount = 10,
    TrailLifetime = 0.6,
    BurstCount = 22,
    MoteSize = 0.12,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_279")

AWE.Catalog.Effects["FX_280"] = {
    Key = "FX_280",
    Name = "Frostfire Orbit 280",
    Category = "Orbit",
    Description = "Frostfire orbit cosmetic profile 280",
    Color1 = rgb(232, 243, 245),
    Color2 = rgb(119, 202, 255),
    Rate = 13,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 2.12,
    Spread = 60,
    SizeStart = 0.12,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 68,
    Drag = 0.0,
    AccelerationY = -0.2,
    AuraRadius = 3.16,
    OrbitSpeed = 1.55,
    OrbitCount = 3,
    TrailLifetime = 0.81,
    BurstCount = 4,
    MoteSize = 0.19,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_280")

AWE.Catalog.Effects["FX_281"] = {
    Key = "FX_281",
    Name = "Iridescent Orbit 281",
    Category = "Orbit",
    Description = "Iridescent orbit cosmetic profile 281",
    Color1 = rgb(255, 225, 253),
    Color2 = rgb(162, 226, 251),
    Rate = 5,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 2.29,
    Spread = 90,
    SizeStart = 0.3,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 77,
    Drag = 0.45,
    AccelerationY = 0.3,
    AuraRadius = 1.95,
    OrbitSpeed = 0.59,
    OrbitCount = 4,
    TrailLifetime = 1.02,
    BurstCount = 7,
    MoteSize = 0.26,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_281")

AWE.Catalog.Effects["FX_282"] = {
    Key = "FX_282",
    Name = "Cloud Nine Orbit 282",
    Category = "Orbit",
    Description = "Cloud Nine orbit cosmetic profile 282",
    Color1 = rgb(250, 250, 250),
    Color2 = rgb(208, 234, 255),
    Rate = 12,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 2.46,
    Spread = 120,
    SizeStart = 0.47,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 86,
    Drag = 0.9,
    AccelerationY = -0.7,
    AuraRadius = 2.72,
    OrbitSpeed = 1.63,
    OrbitCount = 5,
    TrailLifetime = 0.32,
    BurstCount = 10,
    MoteSize = 0.33,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_282")

AWE.Catalog.Effects["FX_283"] = {
    Key = "FX_283",
    Name = "Deep Aqua Orbit 283",
    Category = "Orbit",
    Description = "Deep Aqua orbit cosmetic profile 283",
    Color1 = rgb(120, 255, 255),
    Color2 = rgb(21, 150, 197),
    Rate = 4,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 1.67,
    Spread = 150,
    SizeStart = 0.15,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 95,
    Drag = 0.15,
    AccelerationY = -0.2,
    AuraRadius = 1.51,
    OrbitSpeed = 0.67,
    OrbitCount = 6,
    TrailLifetime = 0.53,
    BurstCount = 13,
    MoteSize = 0.4,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_283")

AWE.Catalog.Effects["FX_284"] = {
    Key = "FX_284",
    Name = "Lilac Mist Orbit 284",
    Category = "Orbit",
    Description = "Lilac Mist orbit cosmetic profile 284",
    Color1 = rgb(230, 217, 255),
    Color2 = rgb(164, 151, 236),
    Rate = 11,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.84,
    Spread = 180,
    SizeStart = 0.33,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 104,
    Drag = 0.6,
    AccelerationY = 0.3,
    AuraRadius = 2.28,
    OrbitSpeed = 1.71,
    OrbitCount = 7,
    TrailLifetime = 0.74,
    BurstCount = 16,
    MoteSize = 0.15,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_284")

AWE.Catalog.Effects["FX_285"] = {
    Key = "FX_285",
    Name = "Silver Rain Orbit 285",
    Category = "Orbit",
    Description = "Silver Rain orbit cosmetic profile 285",
    Color1 = rgb(226, 234, 243),
    Color2 = rgb(161, 188, 213),
    Rate = 3,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.01,
    Spread = 60,
    SizeStart = 0.51,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 113,
    Drag = 1.05,
    AccelerationY = -0.7,
    AuraRadius = 3.05,
    OrbitSpeed = 0.75,
    OrbitCount = 8,
    TrailLifetime = 0.95,
    BurstCount = 19,
    MoteSize = 0.23,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_285")

AWE.Catalog.Effects["FX_286"] = {
    Key = "FX_286",
    Name = "Pearl Prism 286",
    Category = "Prism",
    Description = "Pearl prism cosmetic profile 286",
    Color1 = rgb(249, 255, 255),
    Color2 = rgb(103, 219, 235),
    Rate = 10,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.22,
    Spread = 90,
    SizeStart = 0.19,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 122,
    Drag = 0.3,
    AccelerationY = -0.2,
    AuraRadius = 1.84,
    OrbitSpeed = 1.79,
    OrbitCount = 9,
    TrailLifetime = 0.25,
    BurstCount = 22,
    MoteSize = 0.3,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_286")

AWE.Catalog.Effects["FX_287"] = {
    Key = "FX_287",
    Name = "Aurora Prism 287",
    Category = "Prism",
    Description = "Aurora prism cosmetic profile 287",
    Color1 = rgb(99, 239, 225),
    Color2 = rgb(114, 150, 255),
    Rate = 17,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 1.39,
    Spread = 120,
    SizeStart = 0.36,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 131,
    Drag = 0.75,
    AccelerationY = 0.3,
    AuraRadius = 2.61,
    OrbitSpeed = 0.83,
    OrbitCount = 10,
    TrailLifetime = 0.46,
    BurstCount = 4,
    MoteSize = 0.36,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_287")

AWE.Catalog.Effects["FX_288"] = {
    Key = "FX_288",
    Name = "Moonlight Prism 288",
    Category = "Prism",
    Description = "Moonlight prism cosmetic profile 288",
    Color1 = rgb(240, 249, 255),
    Color2 = rgb(159, 182, 250),
    Rate = 9,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 0.6,
    Spread = 150,
    SizeStart = 0.54,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 140,
    Drag = 0.0,
    AccelerationY = -0.7,
    AuraRadius = 1.4,
    OrbitSpeed = 1.87,
    OrbitCount = 3,
    TrailLifetime = 0.67,
    BurstCount = 7,
    MoteSize = 0.12,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_288")

AWE.Catalog.Effects["FX_289"] = {
    Key = "FX_289",
    Name = "Rose Quartz Prism 289",
    Category = "Prism",
    Description = "Rose Quartz prism cosmetic profile 289",
    Color1 = rgb(253, 208, 230),
    Color2 = rgb(240, 133, 194),
    Rate = 16,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 3.05,
    Spread = 180,
    SizeStart = 0.23,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 19,
    Drag = 0.45,
    AccelerationY = -0.2,
    AuraRadius = 2.17,
    OrbitSpeed = 0.91,
    OrbitCount = 4,
    TrailLifetime = 0.88,
    BurstCount = 10,
    MoteSize = 0.19,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_289")

AWE.Catalog.Effects["FX_290"] = {
    Key = "FX_290",
    Name = "Starlace Prism 290",
    Category = "Prism",
    Description = "Starlace prism cosmetic profile 290",
    Color1 = rgb(241, 241, 241),
    Color2 = rgb(196, 229, 255),
    Rate = 8,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 3.22,
    Spread = 60,
    SizeStart = 0.4,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 28,
    Drag = 0.9,
    AccelerationY = 0.3,
    AuraRadius = 2.94,
    OrbitSpeed = 1.95,
    OrbitCount = 5,
    TrailLifetime = 1.09,
    BurstCount = 13,
    MoteSize = 0.26,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_290")

AWE.Catalog.Effects["FX_291"] = {
    Key = "FX_291",
    Name = "Glacier Prism 291",
    Category = "Prism",
    Description = "Glacier prism cosmetic profile 291",
    Color1 = rgb(203, 251, 255),
    Color2 = rgb(72, 183, 233),
    Rate = 15,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 2.43,
    Spread = 90,
    SizeStart = 0.58,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 37,
    Drag = 0.15,
    AccelerationY = -0.7,
    AuraRadius = 1.73,
    OrbitSpeed = 0.99,
    OrbitCount = 6,
    TrailLifetime = 0.39,
    BurstCount = 16,
    MoteSize = 0.33,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_291")

AWE.Catalog.Effects["FX_292"] = {
    Key = "FX_292",
    Name = "Opaline Prism 292",
    Category = "Prism",
    Description = "Opaline prism cosmetic profile 292",
    Color1 = rgb(236, 215, 246),
    Color2 = rgb(182, 158, 255),
    Rate = 7,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 2.6,
    Spread = 120,
    SizeStart = 0.26,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 46,
    Drag = 0.6,
    AccelerationY = -0.2,
    AuraRadius = 2.5,
    OrbitSpeed = 2.03,
    OrbitCount = 7,
    TrailLifetime = 0.6,
    BurstCount = 19,
    MoteSize = 0.4,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_292")

AWE.Catalog.Effects["FX_293"] = {
    Key = "FX_293",
    Name = "Sea Glass Prism 293",
    Category = "Prism",
    Description = "Sea Glass prism cosmetic profile 293",
    Color1 = rgb(192, 255, 247),
    Color2 = rgb(47, 201, 175),
    Rate = 14,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.77,
    Spread = 150,
    SizeStart = 0.44,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 55,
    Drag = 1.05,
    AccelerationY = 0.3,
    AuraRadius = 3.27,
    OrbitSpeed = 1.07,
    OrbitCount = 8,
    TrailLifetime = 0.81,
    BurstCount = 22,
    MoteSize = 0.15,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_293")

AWE.Catalog.Effects["FX_294"] = {
    Key = "FX_294",
    Name = "Halo Prism 294",
    Category = "Prism",
    Description = "Halo prism cosmetic profile 294",
    Color1 = rgb(251, 241, 203),
    Color2 = rgb(255, 216, 125),
    Rate = 6,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.98,
    Spread = 180,
    SizeStart = 0.12,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 64,
    Drag = 0.3,
    AccelerationY = -0.7,
    AuraRadius = 2.06,
    OrbitSpeed = 2.11,
    OrbitCount = 9,
    TrailLifetime = 1.02,
    BurstCount = 4,
    MoteSize = 0.23,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_294")

AWE.Catalog.Effects["FX_295"] = {
    Key = "FX_295",
    Name = "Frostfire Prism 295",
    Category = "Prism",
    Description = "Frostfire prism cosmetic profile 295",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(107, 190, 248),
    Rate = 13,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.15,
    Spread = 60,
    SizeStart = 0.3,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 73,
    Drag = 0.75,
    AccelerationY = -0.2,
    AuraRadius = 2.83,
    OrbitSpeed = 1.15,
    OrbitCount = 10,
    TrailLifetime = 0.32,
    BurstCount = 7,
    MoteSize = 0.3,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_295")

AWE.Catalog.Effects["FX_296"] = {
    Key = "FX_296",
    Name = "Iridescent Prism 296",
    Category = "Prism",
    Description = "Iridescent prism cosmetic profile 296",
    Color1 = rgb(255, 219, 247),
    Color2 = rgb(165, 229, 254),
    Rate = 5,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 1.36,
    Spread = 90,
    SizeStart = 0.47,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 82,
    Drag = 0.0,
    AccelerationY = 0.3,
    AuraRadius = 1.62,
    OrbitSpeed = 2.19,
    OrbitCount = 3,
    TrailLifetime = 0.53,
    BurstCount = 10,
    MoteSize = 0.36,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_296")

AWE.Catalog.Effects["FX_297"] = {
    Key = "FX_297",
    Name = "Cloud Nine Prism 297",
    Category = "Prism",
    Description = "Cloud Nine prism cosmetic profile 297",
    Color1 = rgb(244, 244, 244),
    Color2 = rgb(211, 237, 255),
    Rate = 12,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 1.53,
    Spread = 120,
    SizeStart = 0.15,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 91,
    Drag = 0.45,
    AccelerationY = -0.7,
    AuraRadius = 2.39,
    OrbitSpeed = 1.23,
    OrbitCount = 4,
    TrailLifetime = 0.74,
    BurstCount = 13,
    MoteSize = 0.12,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_297")

AWE.Catalog.Effects["FX_298"] = {
    Key = "FX_298",
    Name = "Deep Aqua Prism 298",
    Category = "Prism",
    Description = "Deep Aqua prism cosmetic profile 298",
    Color1 = rgb(114, 251, 251),
    Color2 = rgb(24, 153, 200),
    Rate = 4,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 1.7,
    Spread = 150,
    SizeStart = 0.33,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 100,
    Drag = 0.9,
    AccelerationY = -0.2,
    AuraRadius = 3.16,
    OrbitSpeed = 2.27,
    OrbitCount = 5,
    TrailLifetime = 0.95,
    BurstCount = 16,
    MoteSize = 0.19,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_298")

AWE.Catalog.Effects["FX_299"] = {
    Key = "FX_299",
    Name = "Lilac Mist Prism 299",
    Category = "Prism",
    Description = "Lilac Mist prism cosmetic profile 299",
    Color1 = rgb(224, 211, 249),
    Color2 = rgb(167, 154, 239),
    Rate = 11,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 0.91,
    Spread = 180,
    SizeStart = 0.51,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 109,
    Drag = 0.15,
    AccelerationY = 0.3,
    AuraRadius = 1.95,
    OrbitSpeed = 1.31,
    OrbitCount = 6,
    TrailLifetime = 0.25,
    BurstCount = 19,
    MoteSize = 0.26,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_299")

AWE.Catalog.Effects["FX_300"] = {
    Key = "FX_300",
    Name = "Silver Rain Prism 300",
    Category = "Prism",
    Description = "Silver Rain prism cosmetic profile 300",
    Color1 = rgb(249, 255, 255),
    Color2 = rgb(149, 176, 201),
    Rate = 3,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.08,
    Spread = 60,
    SizeStart = 0.19,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 118,
    Drag = 0.6,
    AccelerationY = -0.7,
    AuraRadius = 2.72,
    OrbitSpeed = 0.35,
    OrbitCount = 7,
    TrailLifetime = 0.46,
    BurstCount = 22,
    MoteSize = 0.33,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_300")

AWE.Catalog.Effects["FX_301"] = {
    Key = "FX_301",
    Name = "Pearl Dew 301",
    Category = "Dew",
    Description = "Pearl dew cosmetic profile 301",
    Color1 = rgb(243, 251, 254),
    Color2 = rgb(106, 222, 238),
    Rate = 10,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 3.53,
    Spread = 90,
    SizeStart = 0.36,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 127,
    Drag = 1.05,
    AccelerationY = -0.2,
    AuraRadius = 1.51,
    OrbitSpeed = 1.39,
    OrbitCount = 8,
    TrailLifetime = 0.67,
    BurstCount = 4,
    MoteSize = 0.4,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_301")

AWE.Catalog.Effects["FX_302"] = {
    Key = "FX_302",
    Name = "Aurora Dew 302",
    Category = "Dew",
    Description = "Aurora dew cosmetic profile 302",
    Color1 = rgb(93, 233, 219),
    Color2 = rgb(117, 153, 255),
    Rate = 17,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 2.74,
    Spread = 120,
    SizeStart = 0.54,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 136,
    Drag = 0.3,
    AccelerationY = 0.3,
    AuraRadius = 2.28,
    OrbitSpeed = 0.43,
    OrbitCount = 9,
    TrailLifetime = 0.88,
    BurstCount = 7,
    MoteSize = 0.15,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_302")

AWE.Catalog.Effects["FX_303"] = {
    Key = "FX_303",
    Name = "Moonlight Dew 303",
    Category = "Dew",
    Description = "Moonlight dew cosmetic profile 303",
    Color1 = rgb(234, 243, 255),
    Color2 = rgb(162, 185, 253),
    Rate = 9,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.91,
    Spread = 150,
    SizeStart = 0.23,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 145,
    Drag = 0.75,
    AccelerationY = -0.7,
    AuraRadius = 3.05,
    OrbitSpeed = 1.47,
    OrbitCount = 10,
    TrailLifetime = 1.09,
    BurstCount = 10,
    MoteSize = 0.23,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_303")

AWE.Catalog.Effects["FX_304"] = {
    Key = "FX_304",
    Name = "Rose Quartz Dew 304",
    Category = "Dew",
    Description = "Rose Quartz dew cosmetic profile 304",
    Color1 = rgb(247, 202, 224),
    Color2 = rgb(243, 136, 197),
    Rate = 16,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 2.12,
    Spread = 180,
    SizeStart = 0.4,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 24,
    Drag = 0.0,
    AccelerationY = -0.2,
    AuraRadius = 1.84,
    OrbitSpeed = 0.51,
    OrbitCount = 3,
    TrailLifetime = 0.39,
    BurstCount = 13,
    MoteSize = 0.3,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_304")

AWE.Catalog.Effects["FX_305"] = {
    Key = "FX_305",
    Name = "Starlace Dew 305",
    Category = "Dew",
    Description = "Starlace dew cosmetic profile 305",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(184, 217, 250),
    Rate = 8,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 2.29,
    Spread = 60,
    SizeStart = 0.58,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 33,
    Drag = 0.45,
    AccelerationY = 0.3,
    AuraRadius = 2.61,
    OrbitSpeed = 1.55,
    OrbitCount = 4,
    TrailLifetime = 0.6,
    BurstCount = 16,
    MoteSize = 0.36,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_305")

AWE.Catalog.Effects["FX_306"] = {
    Key = "FX_306",
    Name = "Glacier Dew 306",
    Category = "Dew",
    Description = "Glacier dew cosmetic profile 306",
    Color1 = rgb(197, 245, 252),
    Color2 = rgb(75, 186, 236),
    Rate = 15,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 2.46,
    Spread = 90,
    SizeStart = 0.26,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 42,
    Drag = 0.9,
    AccelerationY = -0.7,
    AuraRadius = 1.4,
    OrbitSpeed = 0.59,
    OrbitCount = 5,
    TrailLifetime = 0.81,
    BurstCount = 19,
    MoteSize = 0.12,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_306")

AWE.Catalog.Effects["FX_307"] = {
    Key = "FX_307",
    Name = "Opaline Dew 307",
    Category = "Dew",
    Description = "Opaline dew cosmetic profile 307",
    Color1 = rgb(255, 238, 255),
    Color2 = rgb(171, 147, 248),
    Rate = 7,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 1.67,
    Spread = 120,
    SizeStart = 0.44,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 51,
    Drag = 0.15,
    AccelerationY = -0.2,
    AuraRadius = 2.17,
    OrbitSpeed = 1.63,
    OrbitCount = 6,
    TrailLifetime = 1.02,
    BurstCount = 22,
    MoteSize = 0.19,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_307")

AWE.Catalog.Effects["FX_308"] = {
    Key = "FX_308",
    Name = "Sea Glass Dew 308",
    Category = "Dew",
    Description = "Sea Glass dew cosmetic profile 308",
    Color1 = rgb(186, 255, 241),
    Color2 = rgb(50, 204, 178),
    Rate = 14,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.84,
    Spread = 150,
    SizeStart = 0.12,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 60,
    Drag = 0.6,
    AccelerationY = 0.3,
    AuraRadius = 2.94,
    OrbitSpeed = 0.67,
    OrbitCount = 7,
    TrailLifetime = 0.32,
    BurstCount = 4,
    MoteSize = 0.26,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_308")

AWE.Catalog.Effects["FX_309"] = {
    Key = "FX_309",
    Name = "Halo Dew 309",
    Category = "Dew",
    Description = "Halo dew cosmetic profile 309",
    Color1 = rgb(245, 235, 197),
    Color2 = rgb(255, 219, 128),
    Rate = 6,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.01,
    Spread = 180,
    SizeStart = 0.3,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 69,
    Drag = 1.05,
    AccelerationY = -0.7,
    AuraRadius = 1.73,
    OrbitSpeed = 1.71,
    OrbitCount = 8,
    TrailLifetime = 0.53,
    BurstCount = 7,
    MoteSize = 0.33,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_309")

AWE.Catalog.Effects["FX_310"] = {
    Key = "FX_310",
    Name = "Frostfire Dew 310",
    Category = "Dew",
    Description = "Frostfire dew cosmetic profile 310",
    Color1 = rgb(249, 255, 255),
    Color2 = rgb(110, 193, 251),
    Rate = 13,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.22,
    Spread = 60,
    SizeStart = 0.47,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 78,
    Drag = 0.3,
    AccelerationY = -0.2,
    AuraRadius = 2.5,
    OrbitSpeed = 0.75,
    OrbitCount = 9,
    TrailLifetime = 0.74,
    BurstCount = 10,
    MoteSize = 0.4,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_310")

AWE.Catalog.Effects["FX_311"] = {
    Key = "FX_311",
    Name = "Iridescent Dew 311",
    Category = "Dew",
    Description = "Iridescent dew cosmetic profile 311",
    Color1 = rgb(250, 213, 241),
    Color2 = rgb(168, 232, 255),
    Rate = 5,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 1.39,
    Spread = 90,
    SizeStart = 0.15,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 87,
    Drag = 0.75,
    AccelerationY = 0.3,
    AuraRadius = 3.27,
    OrbitSpeed = 1.79,
    OrbitCount = 10,
    TrailLifetime = 0.95,
    BurstCount = 13,
    MoteSize = 0.15,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_311")

AWE.Catalog.Effects["FX_312"] = {
    Key = "FX_312",
    Name = "Cloud Nine Dew 312",
    Category = "Dew",
    Description = "Cloud Nine dew cosmetic profile 312",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(200, 226, 249),
    Rate = 12,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 0.6,
    Spread = 120,
    SizeStart = 0.33,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 96,
    Drag = 0.0,
    AccelerationY = -0.7,
    AuraRadius = 2.06,
    OrbitSpeed = 0.83,
    OrbitCount = 3,
    TrailLifetime = 0.25,
    BurstCount = 16,
    MoteSize = 0.23,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_312")

AWE.Catalog.Effects["FX_313"] = {
    Key = "FX_313",
    Name = "Deep Aqua Dew 313",
    Category = "Dew",
    Description = "Deep Aqua dew cosmetic profile 313",
    Color1 = rgb(108, 245, 245),
    Color2 = rgb(27, 156, 203),
    Rate = 4,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 3.05,
    Spread = 150,
    SizeStart = 0.51,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 105,
    Drag = 0.45,
    AccelerationY = -0.2,
    AuraRadius = 2.83,
    OrbitSpeed = 1.87,
    OrbitCount = 4,
    TrailLifetime = 0.46,
    BurstCount = 19,
    MoteSize = 0.3,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_313")

AWE.Catalog.Effects["FX_314"] = {
    Key = "FX_314",
    Name = "Lilac Mist Dew 314",
    Category = "Dew",
    Description = "Lilac Mist dew cosmetic profile 314",
    Color1 = rgb(218, 205, 243),
    Color2 = rgb(170, 157, 242),
    Rate = 11,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 3.22,
    Spread = 180,
    SizeStart = 0.19,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 114,
    Drag = 0.9,
    AccelerationY = 0.3,
    AuraRadius = 1.62,
    OrbitSpeed = 0.91,
    OrbitCount = 5,
    TrailLifetime = 0.67,
    BurstCount = 22,
    MoteSize = 0.36,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_314")

AWE.Catalog.Effects["FX_315"] = {
    Key = "FX_315",
    Name = "Silver Rain Dew 315",
    Category = "Dew",
    Description = "Silver Rain dew cosmetic profile 315",
    Color1 = rgb(243, 251, 255),
    Color2 = rgb(152, 179, 204),
    Rate = 3,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 2.43,
    Spread = 60,
    SizeStart = 0.36,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 123,
    Drag = 0.15,
    AccelerationY = -0.7,
    AuraRadius = 2.39,
    OrbitSpeed = 1.95,
    OrbitCount = 6,
    TrailLifetime = 0.88,
    BurstCount = 4,
    MoteSize = 0.12,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_315")

AWE.Catalog.Effects["FX_316"] = {
    Key = "FX_316",
    Name = "Pearl Flurry 316",
    Category = "Flurry",
    Description = "Pearl flurry cosmetic profile 316",
    Color1 = rgb(237, 245, 248),
    Color2 = rgb(109, 225, 241),
    Rate = 10,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 2.6,
    Spread = 90,
    SizeStart = 0.54,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 132,
    Drag = 0.6,
    AccelerationY = -0.2,
    AuraRadius = 3.16,
    OrbitSpeed = 0.99,
    OrbitCount = 7,
    TrailLifetime = 1.09,
    BurstCount = 7,
    MoteSize = 0.19,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_316")

AWE.Catalog.Effects["FX_317"] = {
    Key = "FX_317",
    Name = "Aurora Flurry 317",
    Category = "Flurry",
    Description = "Aurora flurry cosmetic profile 317",
    Color1 = rgb(116, 255, 242),
    Color2 = rgb(106, 142, 250),
    Rate = 17,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.77,
    Spread = 120,
    SizeStart = 0.23,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 141,
    Drag = 1.05,
    AccelerationY = 0.3,
    AuraRadius = 1.95,
    OrbitSpeed = 2.03,
    OrbitCount = 8,
    TrailLifetime = 0.39,
    BurstCount = 10,
    MoteSize = 0.26,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_317")

AWE.Catalog.Effects["FX_318"] = {
    Key = "FX_318",
    Name = "Moonlight Flurry 318",
    Category = "Flurry",
    Description = "Moonlight flurry cosmetic profile 318",
    Color1 = rgb(228, 237, 253),
    Color2 = rgb(165, 188, 255),
    Rate = 9,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.98,
    Spread = 150,
    SizeStart = 0.4,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 20,
    Drag = 0.3,
    AccelerationY = -0.7,
    AuraRadius = 2.72,
    OrbitSpeed = 1.07,
    OrbitCount = 9,
    TrailLifetime = 0.6,
    BurstCount = 13,
    MoteSize = 0.33,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_318")

AWE.Catalog.Effects["FX_319"] = {
    Key = "FX_319",
    Name = "Rose Quartz Flurry 319",
    Category = "Flurry",
    Description = "Rose Quartz flurry cosmetic profile 319",
    Color1 = rgb(241, 196, 218),
    Color2 = rgb(246, 139, 200),
    Rate = 16,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.15,
    Spread = 180,
    SizeStart = 0.58,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 29,
    Drag = 0.75,
    AccelerationY = -0.2,
    AuraRadius = 1.51,
    OrbitSpeed = 2.11,
    OrbitCount = 10,
    TrailLifetime = 0.81,
    BurstCount = 16,
    MoteSize = 0.4,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_319")

AWE.Catalog.Effects["FX_320"] = {
    Key = "FX_320",
    Name = "Starlace Flurry 320",
    Category = "Flurry",
    Description = "Starlace flurry cosmetic profile 320",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(187, 220, 253),
    Rate = 8,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 1.36,
    Spread = 60,
    SizeStart = 0.26,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 38,
    Drag = 0.0,
    AccelerationY = 0.3,
    AuraRadius = 2.28,
    OrbitSpeed = 1.15,
    OrbitCount = 3,
    TrailLifetime = 1.02,
    BurstCount = 19,
    MoteSize = 0.15,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_320")

AWE.Catalog.Effects["FX_321"] = {
    Key = "FX_321",
    Name = "Glacier Flurry 321",
    Category = "Flurry",
    Description = "Glacier flurry cosmetic profile 321",
    Color1 = rgb(191, 239, 246),
    Color2 = rgb(78, 189, 239),
    Rate = 15,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 1.53,
    Spread = 90,
    SizeStart = 0.44,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 47,
    Drag = 0.45,
    AccelerationY = -0.7,
    AuraRadius = 3.05,
    OrbitSpeed = 2.19,
    OrbitCount = 4,
    TrailLifetime = 0.32,
    BurstCount = 22,
    MoteSize = 0.23,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_321")

AWE.Catalog.Effects["FX_322"] = {
    Key = "FX_322",
    Name = "Opaline Flurry 322",
    Category = "Flurry",
    Description = "Opaline flurry cosmetic profile 322",
    Color1 = rgb(253, 232, 255),
    Color2 = rgb(174, 150, 251),
    Rate = 7,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 1.7,
    Spread = 120,
    SizeStart = 0.12,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 56,
    Drag = 0.9,
    AccelerationY = -0.2,
    AuraRadius = 1.84,
    OrbitSpeed = 1.23,
    OrbitCount = 5,
    TrailLifetime = 0.53,
    BurstCount = 4,
    MoteSize = 0.3,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_322")

AWE.Catalog.Effects["FX_323"] = {
    Key = "FX_323",
    Name = "Sea Glass Flurry 323",
    Category = "Flurry",
    Description = "Sea Glass flurry cosmetic profile 323",
    Color1 = rgb(180, 251, 235),
    Color2 = rgb(53, 207, 181),
    Rate = 14,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 0.91,
    Spread = 150,
    SizeStart = 0.3,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 65,
    Drag = 0.15,
    AccelerationY = 0.3,
    AuraRadius = 2.61,
    OrbitSpeed = 2.27,
    OrbitCount = 6,
    TrailLifetime = 0.74,
    BurstCount = 7,
    MoteSize = 0.36,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_323")

AWE.Catalog.Effects["FX_324"] = {
    Key = "FX_324",
    Name = "Halo Flurry 324",
    Category = "Flurry",
    Description = "Halo flurry cosmetic profile 324",
    Color1 = rgb(255, 255, 220),
    Color2 = rgb(248, 207, 116),
    Rate = 6,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.08,
    Spread = 180,
    SizeStart = 0.47,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 74,
    Drag = 0.6,
    AccelerationY = -0.7,
    AuraRadius = 1.4,
    OrbitSpeed = 1.31,
    OrbitCount = 7,
    TrailLifetime = 0.95,
    BurstCount = 10,
    MoteSize = 0.12,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_324")

AWE.Catalog.Effects["FX_325"] = {
    Key = "FX_325",
    Name = "Frostfire Flurry 325",
    Category = "Flurry",
    Description = "Frostfire flurry cosmetic profile 325",
    Color1 = rgb(243, 254, 255),
    Color2 = rgb(113, 196, 254),
    Rate = 13,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 3.53,
    Spread = 60,
    SizeStart = 0.15,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 83,
    Drag = 1.05,
    AccelerationY = -0.2,
    AuraRadius = 2.17,
    OrbitSpeed = 0.35,
    OrbitCount = 8,
    TrailLifetime = 0.25,
    BurstCount = 13,
    MoteSize = 0.19,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_325")

AWE.Catalog.Effects["FX_326"] = {
    Key = "FX_326",
    Name = "Iridescent Flurry 326",
    Category = "Flurry",
    Description = "Iridescent flurry cosmetic profile 326",
    Color1 = rgb(244, 207, 235),
    Color2 = rgb(171, 235, 255),
    Rate = 5,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 2.74,
    Spread = 90,
    SizeStart = 0.33,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 92,
    Drag = 0.3,
    AccelerationY = 0.3,
    AuraRadius = 2.94,
    OrbitSpeed = 1.39,
    OrbitCount = 9,
    TrailLifetime = 0.46,
    BurstCount = 16,
    MoteSize = 0.26,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_326")

AWE.Catalog.Effects["FX_327"] = {
    Key = "FX_327",
    Name = "Cloud Nine Flurry 327",
    Category = "Flurry",
    Description = "Cloud Nine flurry cosmetic profile 327",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(203, 229, 252),
    Rate = 12,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.91,
    Spread = 120,
    SizeStart = 0.51,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 101,
    Drag = 0.75,
    AccelerationY = -0.7,
    AuraRadius = 1.73,
    OrbitSpeed = 0.43,
    OrbitCount = 10,
    TrailLifetime = 0.67,
    BurstCount = 19,
    MoteSize = 0.33,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_327")

AWE.Catalog.Effects["FX_328"] = {
    Key = "FX_328",
    Name = "Deep Aqua Flurry 328",
    Category = "Flurry",
    Description = "Deep Aqua flurry cosmetic profile 328",
    Color1 = rgb(102, 239, 239),
    Color2 = rgb(30, 159, 206),
    Rate = 4,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 2.12,
    Spread = 150,
    SizeStart = 0.19,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 110,
    Drag = 0.0,
    AccelerationY = -0.2,
    AuraRadius = 2.5,
    OrbitSpeed = 1.47,
    OrbitCount = 3,
    TrailLifetime = 0.88,
    BurstCount = 22,
    MoteSize = 0.4,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_328")

AWE.Catalog.Effects["FX_329"] = {
    Key = "FX_329",
    Name = "Lilac Mist Flurry 329",
    Category = "Flurry",
    Description = "Lilac Mist flurry cosmetic profile 329",
    Color1 = rgb(241, 228, 255),
    Color2 = rgb(158, 145, 230),
    Rate = 11,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 2.29,
    Spread = 180,
    SizeStart = 0.36,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 119,
    Drag = 0.45,
    AccelerationY = 0.3,
    AuraRadius = 3.27,
    OrbitSpeed = 0.51,
    OrbitCount = 4,
    TrailLifetime = 1.09,
    BurstCount = 4,
    MoteSize = 0.15,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_329")

AWE.Catalog.Effects["FX_330"] = {
    Key = "FX_330",
    Name = "Silver Rain Flurry 330",
    Category = "Flurry",
    Description = "Silver Rain flurry cosmetic profile 330",
    Color1 = rgb(237, 245, 254),
    Color2 = rgb(155, 182, 207),
    Rate = 3,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 2.46,
    Spread = 60,
    SizeStart = 0.54,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 128,
    Drag = 0.9,
    AccelerationY = -0.7,
    AuraRadius = 2.06,
    OrbitSpeed = 1.55,
    OrbitCount = 5,
    TrailLifetime = 0.39,
    BurstCount = 7,
    MoteSize = 0.23,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_330")

AWE.Catalog.Effects["FX_331"] = {
    Key = "FX_331",
    Name = "Pearl Pulse 331",
    Category = "Pulse",
    Description = "Pearl pulse cosmetic profile 331",
    Color1 = rgb(231, 239, 242),
    Color2 = rgb(112, 228, 244),
    Rate = 10,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 1.67,
    Spread = 90,
    SizeStart = 0.23,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 137,
    Drag = 0.15,
    AccelerationY = -0.2,
    AuraRadius = 2.83,
    OrbitSpeed = 0.59,
    OrbitCount = 6,
    TrailLifetime = 0.6,
    BurstCount = 10,
    MoteSize = 0.3,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_331")

AWE.Catalog.Effects["FX_332"] = {
    Key = "FX_332",
    Name = "Aurora Pulse 332",
    Category = "Pulse",
    Description = "Aurora pulse cosmetic profile 332",
    Color1 = rgb(110, 250, 236),
    Color2 = rgb(109, 145, 253),
    Rate = 17,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.84,
    Spread = 120,
    SizeStart = 0.4,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 146,
    Drag = 0.6,
    AccelerationY = 0.3,
    AuraRadius = 1.62,
    OrbitSpeed = 1.63,
    OrbitCount = 7,
    TrailLifetime = 0.81,
    BurstCount = 13,
    MoteSize = 0.36,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_332")

AWE.Catalog.Effects["FX_333"] = {
    Key = "FX_333",
    Name = "Moonlight Pulse 333",
    Category = "Pulse",
    Description = "Moonlight pulse cosmetic profile 333",
    Color1 = rgb(222, 231, 247),
    Color2 = rgb(168, 191, 255),
    Rate = 9,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.01,
    Spread = 150,
    SizeStart = 0.58,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 25,
    Drag = 1.05,
    AccelerationY = -0.7,
    AuraRadius = 2.39,
    OrbitSpeed = 0.67,
    OrbitCount = 8,
    TrailLifetime = 1.02,
    BurstCount = 16,
    MoteSize = 0.12,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_333")

AWE.Catalog.Effects["FX_334"] = {
    Key = "FX_334",
    Name = "Rose Quartz Pulse 334",
    Category = "Pulse",
    Description = "Rose Quartz pulse cosmetic profile 334",
    Color1 = rgb(255, 219, 241),
    Color2 = rgb(234, 127, 188),
    Rate = 16,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.22,
    Spread = 180,
    SizeStart = 0.26,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 34,
    Drag = 0.3,
    AccelerationY = -0.2,
    AuraRadius = 3.16,
    OrbitSpeed = 1.71,
    OrbitCount = 9,
    TrailLifetime = 0.32,
    BurstCount = 19,
    MoteSize = 0.19,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_334")

AWE.Catalog.Effects["FX_335"] = {
    Key = "FX_335",
    Name = "Starlace Pulse 335",
    Category = "Pulse",
    Description = "Starlace pulse cosmetic profile 335",
    Color1 = rgb(252, 252, 252),
    Color2 = rgb(190, 223, 255),
    Rate = 8,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 1.39,
    Spread = 60,
    SizeStart = 0.44,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 43,
    Drag = 0.75,
    AccelerationY = 0.3,
    AuraRadius = 1.95,
    OrbitSpeed = 0.75,
    OrbitCount = 10,
    TrailLifetime = 0.53,
    BurstCount = 22,
    MoteSize = 0.26,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_335")

AWE.Catalog.Effects["FX_336"] = {
    Key = "FX_336",
    Name = "Glacier Pulse 336",
    Category = "Pulse",
    Description = "Glacier pulse cosmetic profile 336",
    Color1 = rgb(214, 255, 255),
    Color2 = rgb(67, 178, 228),
    Rate = 15,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 0.6,
    Spread = 90,
    SizeStart = 0.12,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 52,
    Drag = 0.0,
    AccelerationY = -0.7,
    AuraRadius = 2.72,
    OrbitSpeed = 1.79,
    OrbitCount = 3,
    TrailLifetime = 0.74,
    BurstCount = 4,
    MoteSize = 0.33,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_336")

AWE.Catalog.Effects["FX_337"] = {
    Key = "FX_337",
    Name = "Opaline Pulse 337",
    Category = "Pulse",
    Description = "Opaline pulse cosmetic profile 337",
    Color1 = rgb(247, 226, 255),
    Color2 = rgb(177, 153, 254),
    Rate = 7,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 3.05,
    Spread = 120,
    SizeStart = 0.3,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 61,
    Drag = 0.45,
    AccelerationY = -0.2,
    AuraRadius = 1.51,
    OrbitSpeed = 0.83,
    OrbitCount = 4,
    TrailLifetime = 0.95,
    BurstCount = 7,
    MoteSize = 0.4,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_337")

AWE.Catalog.Effects["FX_338"] = {
    Key = "FX_338",
    Name = "Sea Glass Pulse 338",
    Category = "Pulse",
    Description = "Sea Glass pulse cosmetic profile 338",
    Color1 = rgb(174, 245, 229),
    Color2 = rgb(56, 210, 184),
    Rate = 14,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 3.22,
    Spread = 150,
    SizeStart = 0.47,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 70,
    Drag = 0.9,
    AccelerationY = 0.3,
    AuraRadius = 2.28,
    OrbitSpeed = 1.87,
    OrbitCount = 5,
    TrailLifetime = 0.25,
    BurstCount = 10,
    MoteSize = 0.15,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_338")

AWE.Catalog.Effects["FX_339"] = {
    Key = "FX_339",
    Name = "Halo Pulse 339",
    Category = "Pulse",
    Description = "Halo pulse cosmetic profile 339",
    Color1 = rgb(255, 252, 214),
    Color2 = rgb(251, 210, 119),
    Rate = 6,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 2.43,
    Spread = 180,
    SizeStart = 0.15,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 79,
    Drag = 0.15,
    AccelerationY = -0.7,
    AuraRadius = 3.05,
    OrbitSpeed = 0.91,
    OrbitCount = 6,
    TrailLifetime = 0.46,
    BurstCount = 13,
    MoteSize = 0.23,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_339")

AWE.Catalog.Effects["FX_340"] = {
    Key = "FX_340",
    Name = "Frostfire Pulse 340",
    Category = "Pulse",
    Description = "Frostfire pulse cosmetic profile 340",
    Color1 = rgb(237, 248, 250),
    Color2 = rgb(116, 199, 255),
    Rate = 13,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 2.6,
    Spread = 60,
    SizeStart = 0.33,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 88,
    Drag = 0.6,
    AccelerationY = -0.2,
    AuraRadius = 1.84,
    OrbitSpeed = 1.95,
    OrbitCount = 7,
    TrailLifetime = 0.67,
    BurstCount = 16,
    MoteSize = 0.3,
    ZOffset = 0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_340")

AWE.Catalog.Effects["FX_341"] = {
    Key = "FX_341",
    Name = "Iridescent Pulse 341",
    Category = "Pulse",
    Description = "Iridescent pulse cosmetic profile 341",
    Color1 = rgb(255, 230, 255),
    Color2 = rgb(160, 224, 249),
    Rate = 5,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 2.77,
    Spread = 90,
    SizeStart = 0.51,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 97,
    Drag = 1.05,
    AccelerationY = 0.3,
    AuraRadius = 2.61,
    OrbitSpeed = 0.99,
    OrbitCount = 8,
    TrailLifetime = 0.88,
    BurstCount = 19,
    MoteSize = 0.36,
    ZOffset = -0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_341")

AWE.Catalog.Effects["FX_342"] = {
    Key = "FX_342",
    Name = "Cloud Nine Pulse 342",
    Category = "Pulse",
    Description = "Cloud Nine pulse cosmetic profile 342",
    Color1 = rgb(255, 255, 255),
    Color2 = rgb(206, 232, 255),
    Rate = 12,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 1.98,
    Spread = 120,
    SizeStart = 0.19,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 106,
    Drag = 0.3,
    AccelerationY = -0.7,
    AuraRadius = 1.4,
    OrbitSpeed = 2.03,
    OrbitCount = 9,
    TrailLifetime = 1.09,
    BurstCount = 22,
    MoteSize = 0.12,
    ZOffset = 0.0,
}
table.insert(AWE.Catalog.EffectOrder, "FX_342")

AWE.Catalog.Effects["FX_343"] = {
    Key = "FX_343",
    Name = "Deep Aqua Pulse 343",
    Category = "Pulse",
    Description = "Deep Aqua pulse cosmetic profile 343",
    Color1 = rgb(96, 233, 233),
    Color2 = rgb(33, 162, 209),
    Rate = 4,
    LifetimeMin = 0.72,
    LifetimeMax = 1.72,
    SpeedMin = 0.7,
    SpeedMax = 2.15,
    Spread = 150,
    SizeStart = 0.36,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 115,
    Drag = 0.75,
    AccelerationY = -0.2,
    AuraRadius = 2.17,
    OrbitSpeed = 1.07,
    OrbitCount = 10,
    TrailLifetime = 0.39,
    BurstCount = 4,
    MoteSize = 0.19,
    ZOffset = 0.5,
}
table.insert(AWE.Catalog.EffectOrder, "FX_343")

AWE.Catalog.Effects["FX_344"] = {
    Key = "FX_344",
    Name = "Lilac Mist Pulse 344",
    Category = "Pulse",
    Description = "Lilac Mist pulse cosmetic profile 344",
    Color1 = rgb(235, 222, 255),
    Color2 = rgb(161, 148, 233),
    Rate = 11,
    LifetimeMin = 0.45,
    LifetimeMax = 0.9,
    SpeedMin = 0.1,
    SpeedMax = 1.36,
    Spread = 180,
    SizeStart = 0.54,
    SizeEnd = 0.01,
    LightEmission = 0.75,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 124,
    Drag = 0.0,
    AccelerationY = 0.3,
    AuraRadius = 2.94,
    OrbitSpeed = 2.11,
    OrbitCount = 3,
    TrailLifetime = 0.6,
    BurstCount = 7,
    MoteSize = 0.26,
    ZOffset = -0.1,
}
table.insert(AWE.Catalog.EffectOrder, "FX_344")

AWE.Catalog.Effects["FX_345"] = {
    Key = "FX_345",
    Name = "Silver Rain Pulse 345",
    Category = "Pulse",
    Description = "Silver Rain pulse cosmetic profile 345",
    Color1 = rgb(231, 239, 248),
    Color2 = rgb(158, 185, 210),
    Rate = 3,
    LifetimeMin = 0.9,
    LifetimeMax = 1.9,
    SpeedMin = 0.46,
    SpeedMax = 1.53,
    Spread = 60,
    SizeStart = 0.23,
    SizeEnd = 0.01,
    LightEmission = 0.45,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 133,
    Drag = 0.45,
    AccelerationY = -0.7,
    AuraRadius = 1.73,
    OrbitSpeed = 1.15,
    OrbitCount = 4,
    TrailLifetime = 0.81,
    BurstCount = 10,
    MoteSize = 0.33,
    ZOffset = 0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_345")

AWE.Catalog.Effects["FX_346"] = {
    Key = "FX_346",
    Name = "Pearl Nova 346",
    Category = "Nova",
    Description = "Pearl nova cosmetic profile 346",
    Color1 = rgb(254, 255, 255),
    Color2 = rgb(101, 217, 233),
    Rate = 10,
    LifetimeMin = 0.63,
    LifetimeMax = 1.08,
    SpeedMin = 0.82,
    SpeedMax = 1.7,
    Spread = 90,
    SizeStart = 0.4,
    SizeEnd = 0.01,
    LightEmission = 0.85,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 142,
    Drag = 0.9,
    AccelerationY = -0.2,
    AuraRadius = 2.5,
    OrbitSpeed = 2.19,
    OrbitCount = 5,
    TrailLifetime = 1.02,
    BurstCount = 13,
    MoteSize = 0.4,
    ZOffset = -0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_346")

AWE.Catalog.Effects["FX_347"] = {
    Key = "FX_347",
    Name = "Aurora Nova 347",
    Category = "Nova",
    Description = "Aurora nova cosmetic profile 347",
    Color1 = rgb(104, 244, 230),
    Color2 = rgb(112, 148, 255),
    Rate = 17,
    LifetimeMin = 1.08,
    LifetimeMax = 2.08,
    SpeedMin = 0.22,
    SpeedMax = 0.91,
    Spread = 120,
    SizeStart = 0.58,
    SizeEnd = 0.01,
    LightEmission = 0.55,
    RotMin = -120,
    RotMax = 120,
    RotSpeed = 21,
    Drag = 0.15,
    AccelerationY = 0.3,
    AuraRadius = 3.27,
    OrbitSpeed = 1.23,
    OrbitCount = 6,
    TrailLifetime = 0.32,
    BurstCount = 16,
    MoteSize = 0.15,
    ZOffset = 0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_347")

AWE.Catalog.Effects["FX_348"] = {
    Key = "FX_348",
    Name = "Moonlight Nova 348",
    Category = "Nova",
    Description = "Moonlight nova cosmetic profile 348",
    Color1 = rgb(216, 225, 241),
    Color2 = rgb(171, 194, 255),
    Rate = 9,
    LifetimeMin = 0.81,
    LifetimeMax = 1.26,
    SpeedMin = 0.58,
    SpeedMax = 1.08,
    Spread = 150,
    SizeStart = 0.26,
    SizeEnd = 0.01,
    LightEmission = 0.95,
    RotMin = -180,
    RotMax = 180,
    RotSpeed = 30,
    Drag = 0.6,
    AccelerationY = -0.7,
    AuraRadius = 2.06,
    OrbitSpeed = 2.27,
    OrbitCount = 7,
    TrailLifetime = 0.53,
    BurstCount = 19,
    MoteSize = 0.23,
    ZOffset = -0.3,
}
table.insert(AWE.Catalog.EffectOrder, "FX_348")

AWE.Catalog.Effects["FX_349"] = {
    Key = "FX_349",
    Name = "Rose Quartz Nova 349",
    Category = "Nova",
    Description = "Rose Quartz nova cosmetic profile 349",
    Color1 = rgb(255, 213, 235),
    Color2 = rgb(237, 130, 191),
    Rate = 16,
    LifetimeMin = 0.54,
    LifetimeMax = 1.54,
    SpeedMin = 0.94,
    SpeedMax = 3.53,
    Spread = 180,
    SizeStart = 0.44,
    SizeEnd = 0.01,
    LightEmission = 0.65,
    RotMin = -160,
    RotMax = 160,
    RotSpeed = 39,
    Drag = 1.05,
    AccelerationY = -0.2,
    AuraRadius = 2.83,
    OrbitSpeed = 1.31,
    OrbitCount = 8,
    TrailLifetime = 0.74,
    BurstCount = 22,
    MoteSize = 0.3,
    ZOffset = 0.2,
}
table.insert(AWE.Catalog.EffectOrder, "FX_349")

AWE.Catalog.Effects["FX_350"] = {
    Key = "FX_350",
    Name = "Starlace Nova 350",
    Category = "Nova",
    Description = "Starlace nova cosmetic profile 350",
    Color1 = rgb(246, 246, 246),
    Color2 = rgb(193, 226, 255),
    Rate = 8,
    LifetimeMin = 0.99,
    LifetimeMax = 1.44,
    SpeedMin = 0.34,
    SpeedMax = 2.74,
    Spread = 60,
    SizeStart = 0.12,
    SizeEnd = 0.01,
    LightEmission = 0.35,
    RotMin = -140,
    RotMax = 140,
    RotSpeed = 48,
    Drag = 0.3,
    AccelerationY = 0.3,
    AuraRadius = 1.62,
    OrbitSpeed = 0.35,
    OrbitCount = 9,
    TrailLifetime = 0.95,
    BurstCount = 4,
    MoteSize = 0.36,
    ZOffset = -0.4,
}
table.insert(AWE.Catalog.EffectOrder, "FX_350")


-- Scene presets: all values are consumed by AWE:ApplyScene.
AWE.Catalog.SceneOrder = {}
AWE.Catalog.Scenes["SCENE_001"] = {
    Key = "SCENE_001",
    Name = "Pearl Dawn 001",
    Description = "pearl dawn lighting preset",
    Brightness = 1.2,
    ClockTime = 5.89,
    Exposure = 0.01,
    Ambient = rgb(175, 209, 229),
    OutdoorAmbient = rgb(120, 161, 193),
    FogColor = rgb(118, 159, 191),
    FogStart = 46,
    FogEnd = 583,
    Diffuse = 0.9,
    Specular = 0.9,
    Tint = rgb(169, 203, 223),
    Contrast = 0.02,
    Saturation = 0.075,
    AtmosphereDensity = 0.164,
    Haze = 0.53,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_001")

AWE.Catalog.Scenes["SCENE_002"] = {
    Key = "SCENE_002",
    Name = "Moonlit Harbor 002",
    Description = "moonlit harbor lighting preset",
    Brightness = -0.1,
    ClockTime = 23.96,
    Exposure = -0.105,
    Ambient = rgb(98, 128, 178),
    OutdoorAmbient = rgb(48, 68, 107),
    FogColor = rgb(57, 77, 116),
    FogStart = 57,
    FogEnd = 631,
    Diffuse = 0.85,
    Specular = 0.85,
    Tint = rgb(95, 125, 175),
    Contrast = 0.08,
    Saturation = 0.25,
    AtmosphereDensity = 0.248,
    Haze = 0.86,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_002")

AWE.Catalog.Scenes["SCENE_003"] = {
    Key = "SCENE_003",
    Name = "Arctic Morning 003",
    Description = "arctic morning lighting preset",
    Brightness = 1.0,
    ClockTime = 7.93,
    Exposure = 0.03,
    Ambient = rgb(197, 226, 240),
    OutdoorAmbient = rgb(160, 197, 216),
    FogColor = rgb(154, 191, 210),
    FogStart = 68,
    FogEnd = 679,
    Diffuse = 0.8,
    Specular = 0.8,
    Tint = rgb(197, 226, 240),
    Contrast = 0.14,
    Saturation = 0.05,
    AtmosphereDensity = 0.104,
    Haze = 1.19,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_003")

AWE.Catalog.Scenes["SCENE_004"] = {
    Key = "SCENE_004",
    Name = "Aquamarine Noon 004",
    Description = "aquamarine noon lighting preset",
    Brightness = 1.1,
    ClockTime = 12.7,
    Exposure = 0.045,
    Ambient = rgb(155, 228, 237),
    OutdoorAmbient = rgb(109, 174, 197),
    FogColor = rgb(114, 179, 202),
    FogStart = 79,
    FogEnd = 727,
    Diffuse = 0.75,
    Specular = 0.75,
    Tint = rgb(158, 231, 240),
    Contrast = -0.04,
    Saturation = 0.225,
    AtmosphereDensity = 0.188,
    Haze = 1.52,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_004")

AWE.Catalog.Scenes["SCENE_005"] = {
    Key = "SCENE_005",
    Name = "Silver Sunset 005",
    Description = "silver sunset lighting preset",
    Brightness = 1.2,
    ClockTime = 17.97,
    Exposure = 0.09,
    Ambient = rgb(223, 177, 165),
    OutdoorAmbient = rgb(168, 133, 157),
    FogColor = rgb(158, 123, 147),
    FogStart = 90,
    FogEnd = 775,
    Diffuse = 0.7,
    Specular = 0.7,
    Tint = rgb(229, 183, 171),
    Contrast = 0.02,
    Saturation = 0.025,
    AtmosphereDensity = 0.272,
    Haze = 1.85,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_005")

AWE.Catalog.Scenes["SCENE_006"] = {
    Key = "SCENE_006",
    Name = "Cloud Cathedral 006",
    Description = "cloud cathedral lighting preset",
    Brightness = 1.0,
    ClockTime = 14.54,
    Exposure = 0.135,
    Ambient = rgb(214, 226, 246),
    OutdoorAmbient = rgb(159, 185, 225),
    FogColor = rgb(160, 186, 226),
    FogStart = 101,
    FogEnd = 823,
    Diffuse = 0.65,
    Specular = 0.65,
    Tint = rgb(223, 235, 255),
    Contrast = 0.08,
    Saturation = 0.2,
    AtmosphereDensity = 0.128,
    Haze = 0.31,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_006")

AWE.Catalog.Scenes["SCENE_007"] = {
    Key = "SCENE_007",
    Name = "Blue Hour 007",
    Description = "blue hour lighting preset",
    Brightness = 0.7,
    ClockTime = 19.91,
    Exposure = -0.115,
    Ambient = rgb(116, 137, 189),
    OutdoorAmbient = rgb(55, 70, 121),
    FogColor = rgb(66, 81, 132),
    FogStart = 112,
    FogEnd = 871,
    Diffuse = 0.6,
    Specular = 0.6,
    Tint = rgb(107, 128, 180),
    Contrast = 0.14,
    Saturation = 0.0,
    AtmosphereDensity = 0.212,
    Haze = 0.64,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_007")

AWE.Catalog.Scenes["SCENE_008"] = {
    Key = "SCENE_008",
    Name = "Lavender Fog 008",
    Description = "lavender fog lighting preset",
    Brightness = 1.1,
    ClockTime = 6.48,
    Exposure = 0.03,
    Ambient = rgb(190, 177, 220),
    OutdoorAmbient = rgb(135, 127, 182),
    FogColor = rgb(131, 123, 178),
    FogStart = 123,
    FogEnd = 919,
    Diffuse = 0.55,
    Specular = 0.55,
    Tint = rgb(184, 171, 214),
    Contrast = -0.04,
    Saturation = 0.175,
    AtmosphereDensity = 0.296,
    Haze = 0.97,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_008")

AWE.Catalog.Scenes["SCENE_009"] = {
    Key = "SCENE_009",
    Name = "Glacier Cave 009",
    Description = "glacier cave lighting preset",
    Brightness = 0.6,
    ClockTime = 0.32,
    Exposure = -0.125,
    Ambient = rgb(122, 186, 207),
    OutdoorAmbient = rgb(63, 108, 141),
    FogColor = rgb(71, 116, 149),
    FogStart = 134,
    FogEnd = 967,
    Diffuse = 0.5,
    Specular = 0.5,
    Tint = rgb(119, 183, 204),
    Contrast = 0.02,
    Saturation = -0.025,
    AtmosphereDensity = 0.152,
    Haze = 1.3,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_009")

AWE.Catalog.Scenes["SCENE_010"] = {
    Key = "SCENE_010",
    Name = "Warm Pearl 010",
    Description = "warm pearl lighting preset",
    Brightness = 1.0,
    ClockTime = 9.69,
    Exposure = 0.03,
    Ambient = rgb(226, 215, 196),
    OutdoorAmbient = rgb(181, 164, 147),
    FogColor = rgb(174, 157, 140),
    FogStart = 145,
    FogEnd = 1015,
    Diffuse = 0.45,
    Specular = 0.45,
    Tint = rgb(226, 215, 196),
    Contrast = 0.08,
    Saturation = 0.15,
    AtmosphereDensity = 0.236,
    Haze = 1.63,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_010")

AWE.Catalog.Scenes["SCENE_011"] = {
    Key = "SCENE_011",
    Name = "Pearl Dawn 011",
    Description = "pearl dawn lighting preset",
    Brightness = 1.2,
    ClockTime = 6.06,
    Exposure = 0.085,
    Ambient = rgb(181, 215, 235),
    OutdoorAmbient = rgb(117, 158, 190),
    FogColor = rgb(120, 161, 193),
    FogStart = 156,
    FogEnd = 1063,
    Diffuse = 0.4,
    Specular = 0.4,
    Tint = rgb(184, 218, 238),
    Contrast = 0.14,
    Saturation = -0.05,
    AtmosphereDensity = 0.092,
    Haze = 1.96,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_011")

AWE.Catalog.Scenes["SCENE_012"] = {
    Key = "SCENE_012",
    Name = "Moonlit Harbor 012",
    Description = "moonlit harbor lighting preset",
    Brightness = -0.1,
    ClockTime = 0.13,
    Exposure = -0.03,
    Ambient = rgb(73, 103, 153),
    OutdoorAmbient = rgb(61, 81, 120),
    FogColor = rgb(49, 69, 108),
    FogStart = 167,
    FogEnd = 1111,
    Diffuse = 0.35,
    Specular = 0.35,
    Tint = rgb(79, 109, 159),
    Contrast = -0.04,
    Saturation = 0.125,
    AtmosphereDensity = 0.176,
    Haze = 0.42,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_012")

AWE.Catalog.Scenes["SCENE_013"] = {
    Key = "SCENE_013",
    Name = "Arctic Morning 013",
    Description = "arctic morning lighting preset",
    Brightness = 1.0,
    ClockTime = 8.1,
    Exposure = 0.105,
    Ambient = rgb(203, 232, 246),
    OutdoorAmbient = rgb(157, 194, 213),
    FogColor = rgb(156, 193, 212),
    FogStart = 178,
    FogEnd = 1159,
    Diffuse = 0.9,
    Specular = 0.3,
    Tint = rgb(212, 241, 255),
    Contrast = 0.02,
    Saturation = -0.075,
    AtmosphereDensity = 0.26,
    Haze = 0.75,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_013")

AWE.Catalog.Scenes["SCENE_014"] = {
    Key = "SCENE_014",
    Name = "Aquamarine Noon 014",
    Description = "aquamarine noon lighting preset",
    Brightness = 1.1,
    ClockTime = 12.87,
    Exposure = -0.055,
    Ambient = rgb(161, 234, 243),
    OutdoorAmbient = rgb(106, 171, 194),
    FogColor = rgb(116, 181, 204),
    FogStart = 189,
    FogEnd = 1207,
    Diffuse = 0.85,
    Specular = 0.25,
    Tint = rgb(152, 225, 234),
    Contrast = 0.08,
    Saturation = 0.1,
    AtmosphereDensity = 0.116,
    Haze = 1.08,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_014")

AWE.Catalog.Scenes["SCENE_015"] = {
    Key = "SCENE_015",
    Name = "Silver Sunset 015",
    Description = "silver sunset lighting preset",
    Brightness = 1.2,
    ClockTime = 18.14,
    Exposure = -0.01,
    Ambient = rgb(229, 183, 171),
    OutdoorAmbient = rgb(165, 130, 154),
    FogColor = rgb(160, 125, 149),
    FogStart = 40,
    FogEnd = 1095,
    Diffuse = 0.8,
    Specular = 0.9,
    Tint = rgb(223, 177, 165),
    Contrast = 0.14,
    Saturation = -0.1,
    AtmosphereDensity = 0.2,
    Haze = 1.41,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_015")

AWE.Catalog.Scenes["SCENE_016"] = {
    Key = "SCENE_016",
    Name = "Cloud Cathedral 016",
    Description = "cloud cathedral lighting preset",
    Brightness = 1.0,
    ClockTime = 14.71,
    Exposure = 0.035,
    Ambient = rgb(220, 232, 252),
    OutdoorAmbient = rgb(156, 182, 222),
    FogColor = rgb(162, 188, 228),
    FogStart = 51,
    FogEnd = 1143,
    Diffuse = 0.75,
    Specular = 0.85,
    Tint = rgb(217, 229, 249),
    Contrast = -0.04,
    Saturation = 0.075,
    AtmosphereDensity = 0.284,
    Haze = 1.74,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_016")

AWE.Catalog.Scenes["SCENE_017"] = {
    Key = "SCENE_017",
    Name = "Blue Hour 017",
    Description = "blue hour lighting preset",
    Brightness = 0.7,
    ClockTime = 20.08,
    Exposure = -0.04,
    Ambient = rgb(91, 112, 164),
    OutdoorAmbient = rgb(67, 82, 133),
    FogColor = rgb(58, 73, 124),
    FogStart = 62,
    FogEnd = 1191,
    Diffuse = 0.7,
    Specular = 0.8,
    Tint = rgb(91, 112, 164),
    Contrast = 0.02,
    Saturation = 0.25,
    AtmosphereDensity = 0.14,
    Haze = 0.2,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_017")

AWE.Catalog.Scenes["SCENE_018"] = {
    Key = "SCENE_018",
    Name = "Lavender Fog 018",
    Description = "lavender fog lighting preset",
    Brightness = 1.1,
    ClockTime = 5.12,
    Exposure = 0.105,
    Ambient = rgb(196, 183, 226),
    OutdoorAmbient = rgb(132, 124, 179),
    FogColor = rgb(133, 125, 180),
    FogStart = 73,
    FogEnd = 1239,
    Diffuse = 0.65,
    Specular = 0.75,
    Tint = rgb(199, 186, 229),
    Contrast = 0.08,
    Saturation = 0.05,
    AtmosphereDensity = 0.224,
    Haze = 0.53,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_018")

AWE.Catalog.Scenes["SCENE_019"] = {
    Key = "SCENE_019",
    Name = "Glacier Cave 019",
    Description = "glacier cave lighting preset",
    Brightness = 0.6,
    ClockTime = 0.49,
    Exposure = -0.05,
    Ambient = rgb(128, 192, 213),
    OutdoorAmbient = rgb(60, 105, 138),
    FogColor = rgb(73, 118, 151),
    FogStart = 84,
    FogEnd = 1287,
    Diffuse = 0.6,
    Specular = 0.7,
    Tint = rgb(134, 198, 219),
    Contrast = 0.14,
    Saturation = 0.225,
    AtmosphereDensity = 0.08,
    Haze = 0.86,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_019")

AWE.Catalog.Scenes["SCENE_020"] = {
    Key = "SCENE_020",
    Name = "Warm Pearl 020",
    Description = "warm pearl lighting preset",
    Brightness = 1.0,
    ClockTime = 9.86,
    Exposure = 0.105,
    Ambient = rgb(232, 221, 202),
    OutdoorAmbient = rgb(178, 161, 144),
    FogColor = rgb(176, 159, 142),
    FogStart = 95,
    FogEnd = 1335,
    Diffuse = 0.55,
    Specular = 0.65,
    Tint = rgb(241, 230, 211),
    Contrast = -0.04,
    Saturation = 0.025,
    AtmosphereDensity = 0.164,
    Haze = 1.19,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_020")

AWE.Catalog.Scenes["SCENE_021"] = {
    Key = "SCENE_021",
    Name = "Pearl Dawn 021",
    Description = "pearl dawn lighting preset",
    Brightness = 1.2,
    ClockTime = 6.23,
    Exposure = -0.015,
    Ambient = rgb(187, 221, 241),
    OutdoorAmbient = rgb(114, 155, 187),
    FogColor = rgb(122, 163, 195),
    FogStart = 106,
    FogEnd = 1383,
    Diffuse = 0.5,
    Specular = 0.6,
    Tint = rgb(178, 212, 232),
    Contrast = 0.02,
    Saturation = 0.2,
    AtmosphereDensity = 0.248,
    Haze = 1.52,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_021")

AWE.Catalog.Scenes["SCENE_022"] = {
    Key = "SCENE_022",
    Name = "Moonlit Harbor 022",
    Description = "moonlit harbor lighting preset",
    Brightness = -0.1,
    ClockTime = 0.3,
    Exposure = -0.13,
    Ambient = rgb(79, 109, 159),
    OutdoorAmbient = rgb(58, 78, 117),
    FogColor = rgb(51, 71, 110),
    FogStart = 117,
    FogEnd = 1431,
    Diffuse = 0.45,
    Specular = 0.55,
    Tint = rgb(73, 103, 153),
    Contrast = 0.08,
    Saturation = 0.0,
    AtmosphereDensity = 0.104,
    Haze = 1.85,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_022")

AWE.Catalog.Scenes["SCENE_023"] = {
    Key = "SCENE_023",
    Name = "Arctic Morning 023",
    Description = "arctic morning lighting preset",
    Brightness = 1.0,
    ClockTime = 8.27,
    Exposure = 0.005,
    Ambient = rgb(209, 238, 252),
    OutdoorAmbient = rgb(154, 191, 210),
    FogColor = rgb(158, 195, 214),
    FogStart = 128,
    FogEnd = 1479,
    Diffuse = 0.4,
    Specular = 0.5,
    Tint = rgb(206, 235, 249),
    Contrast = 0.14,
    Saturation = 0.175,
    AtmosphereDensity = 0.188,
    Haze = 0.31,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_023")

AWE.Catalog.Scenes["SCENE_024"] = {
    Key = "SCENE_024",
    Name = "Aquamarine Noon 024",
    Description = "aquamarine noon lighting preset",
    Brightness = 1.1,
    ClockTime = 13.04,
    Exposure = 0.02,
    Ambient = rgb(136, 209, 218),
    OutdoorAmbient = rgb(118, 183, 206),
    FogColor = rgb(107, 172, 195),
    FogStart = 139,
    FogEnd = 1527,
    Diffuse = 0.35,
    Specular = 0.45,
    Tint = rgb(136, 209, 218),
    Contrast = -0.04,
    Saturation = -0.025,
    AtmosphereDensity = 0.272,
    Haze = 0.64,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_024")

AWE.Catalog.Scenes["SCENE_025"] = {
    Key = "SCENE_025",
    Name = "Silver Sunset 025",
    Description = "silver sunset lighting preset",
    Brightness = 1.2,
    ClockTime = 18.31,
    Exposure = 0.065,
    Ambient = rgb(235, 189, 177),
    OutdoorAmbient = rgb(162, 127, 151),
    FogColor = rgb(162, 127, 151),
    FogStart = 150,
    FogEnd = 1575,
    Diffuse = 0.9,
    Specular = 0.4,
    Tint = rgb(238, 192, 180),
    Contrast = 0.02,
    Saturation = 0.15,
    AtmosphereDensity = 0.128,
    Haze = 0.97,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_025")

AWE.Catalog.Scenes["SCENE_026"] = {
    Key = "SCENE_026",
    Name = "Cloud Cathedral 026",
    Description = "cloud cathedral lighting preset",
    Brightness = 1.0,
    ClockTime = 14.88,
    Exposure = 0.11,
    Ambient = rgb(226, 238, 255),
    OutdoorAmbient = rgb(153, 179, 219),
    FogColor = rgb(164, 190, 230),
    FogStart = 161,
    FogEnd = 1623,
    Diffuse = 0.85,
    Specular = 0.35,
    Tint = rgb(232, 244, 255),
    Contrast = 0.08,
    Saturation = -0.05,
    AtmosphereDensity = 0.212,
    Haze = 1.3,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_026")

AWE.Catalog.Scenes["SCENE_027"] = {
    Key = "SCENE_027",
    Name = "Blue Hour 027",
    Description = "blue hour lighting preset",
    Brightness = 0.7,
    ClockTime = 18.72,
    Exposure = 0.035,
    Ambient = rgb(97, 118, 170),
    OutdoorAmbient = rgb(64, 79, 130),
    FogColor = rgb(60, 75, 126),
    FogStart = 172,
    FogEnd = 1671,
    Diffuse = 0.8,
    Specular = 0.3,
    Tint = rgb(106, 127, 179),
    Contrast = 0.14,
    Saturation = 0.125,
    AtmosphereDensity = 0.296,
    Haze = 1.63,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_027")

AWE.Catalog.Scenes["SCENE_028"] = {
    Key = "SCENE_028",
    Name = "Lavender Fog 028",
    Description = "lavender fog lighting preset",
    Brightness = 1.1,
    ClockTime = 5.29,
    Exposure = 0.005,
    Ambient = rgb(202, 189, 232),
    OutdoorAmbient = rgb(129, 121, 176),
    FogColor = rgb(135, 127, 182),
    FogStart = 183,
    FogEnd = 1719,
    Diffuse = 0.75,
    Specular = 0.25,
    Tint = rgb(193, 180, 223),
    Contrast = -0.04,
    Saturation = -0.075,
    AtmosphereDensity = 0.152,
    Haze = 1.96,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_028")

AWE.Catalog.Scenes["SCENE_029"] = {
    Key = "SCENE_029",
    Name = "Glacier Cave 029",
    Description = "glacier cave lighting preset",
    Brightness = 0.6,
    ClockTime = 0.66,
    Exposure = -0.15,
    Ambient = rgb(103, 167, 188),
    OutdoorAmbient = rgb(73, 118, 151),
    FogColor = rgb(64, 109, 142),
    FogStart = 194,
    FogEnd = 1767,
    Diffuse = 0.7,
    Specular = 0.9,
    Tint = rgb(97, 161, 182),
    Contrast = 0.02,
    Saturation = 0.1,
    AtmosphereDensity = 0.236,
    Haze = 0.42,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_029")

AWE.Catalog.Scenes["SCENE_030"] = {
    Key = "SCENE_030",
    Name = "Warm Pearl 030",
    Description = "warm pearl lighting preset",
    Brightness = 1.0,
    ClockTime = 10.03,
    Exposure = 0.005,
    Ambient = rgb(238, 227, 208),
    OutdoorAmbient = rgb(175, 158, 141),
    FogColor = rgb(178, 161, 144),
    FogStart = 45,
    FogEnd = 1655,
    Diffuse = 0.65,
    Specular = 0.85,
    Tint = rgb(235, 224, 205),
    Contrast = 0.08,
    Saturation = -0.1,
    AtmosphereDensity = 0.092,
    Haze = 0.75,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_030")

AWE.Catalog.Scenes["SCENE_031"] = {
    Key = "SCENE_031",
    Name = "Pearl Dawn 031",
    Description = "pearl dawn lighting preset",
    Brightness = 1.2,
    ClockTime = 6.4,
    Exposure = 0.06,
    Ambient = rgb(162, 196, 216),
    OutdoorAmbient = rgb(126, 167, 199),
    FogColor = rgb(114, 155, 187),
    FogStart = 56,
    FogEnd = 1703,
    Diffuse = 0.6,
    Specular = 0.8,
    Tint = rgb(162, 196, 216),
    Contrast = 0.14,
    Saturation = 0.075,
    AtmosphereDensity = 0.176,
    Haze = 1.08,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_031")

AWE.Catalog.Scenes["SCENE_032"] = {
    Key = "SCENE_032",
    Name = "Moonlit Harbor 032",
    Description = "moonlit harbor lighting preset",
    Brightness = -0.1,
    ClockTime = 0.47,
    Exposure = -0.055,
    Ambient = rgb(85, 115, 165),
    OutdoorAmbient = rgb(55, 75, 114),
    FogColor = rgb(53, 73, 112),
    FogStart = 67,
    FogEnd = 1751,
    Diffuse = 0.55,
    Specular = 0.75,
    Tint = rgb(88, 118, 168),
    Contrast = -0.04,
    Saturation = 0.25,
    AtmosphereDensity = 0.26,
    Haze = 1.41,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_032")

AWE.Catalog.Scenes["SCENE_033"] = {
    Key = "SCENE_033",
    Name = "Arctic Morning 033",
    Description = "arctic morning lighting preset",
    Brightness = 1.0,
    ClockTime = 8.44,
    Exposure = 0.08,
    Ambient = rgb(215, 244, 255),
    OutdoorAmbient = rgb(151, 188, 207),
    FogColor = rgb(160, 197, 216),
    FogStart = 78,
    FogEnd = 1799,
    Diffuse = 0.5,
    Specular = 0.7,
    Tint = rgb(221, 250, 255),
    Contrast = 0.02,
    Saturation = 0.05,
    AtmosphereDensity = 0.116,
    Haze = 1.74,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_033")

AWE.Catalog.Scenes["SCENE_034"] = {
    Key = "SCENE_034",
    Name = "Aquamarine Noon 034",
    Description = "aquamarine noon lighting preset",
    Brightness = 1.1,
    ClockTime = 13.21,
    Exposure = 0.095,
    Ambient = rgb(142, 215, 224),
    OutdoorAmbient = rgb(115, 180, 203),
    FogColor = rgb(109, 174, 197),
    FogStart = 89,
    FogEnd = 1847,
    Diffuse = 0.45,
    Specular = 0.65,
    Tint = rgb(151, 224, 233),
    Contrast = 0.08,
    Saturation = 0.225,
    AtmosphereDensity = 0.2,
    Haze = 0.2,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_034")

AWE.Catalog.Scenes["SCENE_035"] = {
    Key = "SCENE_035",
    Name = "Silver Sunset 035",
    Description = "silver sunset lighting preset",
    Brightness = 1.2,
    ClockTime = 18.48,
    Exposure = -0.035,
    Ambient = rgb(241, 195, 183),
    OutdoorAmbient = rgb(159, 124, 148),
    FogColor = rgb(164, 129, 153),
    FogStart = 100,
    FogEnd = 1895,
    Diffuse = 0.4,
    Specular = 0.6,
    Tint = rgb(232, 186, 174),
    Contrast = 0.14,
    Saturation = 0.025,
    AtmosphereDensity = 0.284,
    Haze = 0.53,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_035")

AWE.Catalog.Scenes["SCENE_036"] = {
    Key = "SCENE_036",
    Name = "Cloud Cathedral 036",
    Description = "cloud cathedral lighting preset",
    Brightness = 1.0,
    ClockTime = 13.52,
    Exposure = 0.01,
    Ambient = rgb(201, 213, 233),
    OutdoorAmbient = rgb(166, 192, 232),
    FogColor = rgb(156, 182, 222),
    FogStart = 111,
    FogEnd = 1943,
    Diffuse = 0.35,
    Specular = 0.55,
    Tint = rgb(195, 207, 227),
    Contrast = -0.04,
    Saturation = 0.2,
    AtmosphereDensity = 0.14,
    Haze = 0.86,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_036")

AWE.Catalog.Scenes["SCENE_037"] = {
    Key = "SCENE_037",
    Name = "Blue Hour 037",
    Description = "blue hour lighting preset",
    Brightness = 0.7,
    ClockTime = 18.89,
    Exposure = -0.065,
    Ambient = rgb(103, 124, 176),
    OutdoorAmbient = rgb(61, 76, 127),
    FogColor = rgb(62, 77, 128),
    FogStart = 122,
    FogEnd = 1991,
    Diffuse = 0.9,
    Specular = 0.5,
    Tint = rgb(100, 121, 173),
    Contrast = 0.02,
    Saturation = 0.0,
    AtmosphereDensity = 0.224,
    Haze = 1.19,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_037")

AWE.Catalog.Scenes["SCENE_038"] = {
    Key = "SCENE_038",
    Name = "Lavender Fog 038",
    Description = "lavender fog lighting preset",
    Brightness = 1.1,
    ClockTime = 5.46,
    Exposure = 0.08,
    Ambient = rgb(208, 195, 238),
    OutdoorAmbient = rgb(126, 118, 173),
    FogColor = rgb(137, 129, 184),
    FogStart = 133,
    FogEnd = 2039,
    Diffuse = 0.85,
    Specular = 0.45,
    Tint = rgb(208, 195, 238),
    Contrast = 0.08,
    Saturation = 0.175,
    AtmosphereDensity = 0.08,
    Haze = 1.52,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_038")

AWE.Catalog.Scenes["SCENE_039"] = {
    Key = "SCENE_039",
    Name = "Glacier Cave 039",
    Description = "glacier cave lighting preset",
    Brightness = 0.6,
    ClockTime = 0.83,
    Exposure = -0.075,
    Ambient = rgb(109, 173, 194),
    OutdoorAmbient = rgb(70, 115, 148),
    FogColor = rgb(66, 111, 144),
    FogStart = 144,
    FogEnd = 2087,
    Diffuse = 0.8,
    Specular = 0.4,
    Tint = rgb(112, 176, 197),
    Contrast = 0.14,
    Saturation = -0.025,
    AtmosphereDensity = 0.164,
    Haze = 1.85,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_039")

AWE.Catalog.Scenes["SCENE_040"] = {
    Key = "SCENE_040",
    Name = "Warm Pearl 040",
    Description = "warm pearl lighting preset",
    Brightness = 1.0,
    ClockTime = 10.2,
    Exposure = 0.08,
    Ambient = rgb(244, 233, 214),
    OutdoorAmbient = rgb(172, 155, 138),
    FogColor = rgb(180, 163, 146),
    FogStart = 155,
    FogEnd = 2135,
    Diffuse = 0.75,
    Specular = 0.35,
    Tint = rgb(250, 239, 220),
    Contrast = -0.04,
    Saturation = 0.15,
    AtmosphereDensity = 0.248,
    Haze = 0.31,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_040")

AWE.Catalog.Scenes["SCENE_041"] = {
    Key = "SCENE_041",
    Name = "Pearl Dawn 041",
    Description = "pearl dawn lighting preset",
    Brightness = 1.2,
    ClockTime = 6.57,
    Exposure = 0.135,
    Ambient = rgb(168, 202, 222),
    OutdoorAmbient = rgb(123, 164, 196),
    FogColor = rgb(116, 157, 189),
    FogStart = 166,
    FogEnd = 2183,
    Diffuse = 0.7,
    Specular = 0.3,
    Tint = rgb(177, 211, 231),
    Contrast = 0.02,
    Saturation = -0.05,
    AtmosphereDensity = 0.104,
    Haze = 0.64,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_041")

AWE.Catalog.Scenes["SCENE_042"] = {
    Key = "SCENE_042",
    Name = "Moonlit Harbor 042",
    Description = "moonlit harbor lighting preset",
    Brightness = -0.1,
    ClockTime = 0.64,
    Exposure = -0.155,
    Ambient = rgb(91, 121, 171),
    OutdoorAmbient = rgb(52, 72, 111),
    FogColor = rgb(55, 75, 114),
    FogStart = 177,
    FogEnd = 2231,
    Diffuse = 0.65,
    Specular = 0.25,
    Tint = rgb(82, 112, 162),
    Contrast = 0.08,
    Saturation = 0.125,
    AtmosphereDensity = 0.188,
    Haze = 0.97,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_042")

AWE.Catalog.Scenes["SCENE_043"] = {
    Key = "SCENE_043",
    Name = "Arctic Morning 043",
    Description = "arctic morning lighting preset",
    Brightness = 1.0,
    ClockTime = 8.61,
    Exposure = -0.02,
    Ambient = rgb(190, 219, 233),
    OutdoorAmbient = rgb(164, 201, 220),
    FogColor = rgb(152, 189, 208),
    FogStart = 188,
    FogEnd = 2279,
    Diffuse = 0.6,
    Specular = 0.9,
    Tint = rgb(184, 213, 227),
    Contrast = 0.14,
    Saturation = -0.075,
    AtmosphereDensity = 0.272,
    Haze = 1.3,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_043")

AWE.Catalog.Scenes["SCENE_044"] = {
    Key = "SCENE_044",
    Name = "Aquamarine Noon 044",
    Description = "aquamarine noon lighting preset",
    Brightness = 1.1,
    ClockTime = 13.38,
    Exposure = -0.005,
    Ambient = rgb(148, 221, 230),
    OutdoorAmbient = rgb(112, 177, 200),
    FogColor = rgb(111, 176, 199),
    FogStart = 39,
    FogEnd = 2167,
    Diffuse = 0.55,
    Specular = 0.85,
    Tint = rgb(145, 218, 227),
    Contrast = -0.04,
    Saturation = 0.1,
    AtmosphereDensity = 0.128,
    Haze = 1.63,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_044")

AWE.Catalog.Scenes["SCENE_045"] = {
    Key = "SCENE_045",
    Name = "Silver Sunset 045",
    Description = "silver sunset lighting preset",
    Brightness = 1.2,
    ClockTime = 17.12,
    Exposure = 0.04,
    Ambient = rgb(247, 201, 189),
    OutdoorAmbient = rgb(156, 121, 145),
    FogColor = rgb(166, 131, 155),
    FogStart = 50,
    FogEnd = 2215,
    Diffuse = 0.5,
    Specular = 0.8,
    Tint = rgb(247, 201, 189),
    Contrast = 0.02,
    Saturation = -0.1,
    AtmosphereDensity = 0.212,
    Haze = 1.96,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_045")

AWE.Catalog.Scenes["SCENE_046"] = {
    Key = "SCENE_046",
    Name = "Cloud Cathedral 046",
    Description = "cloud cathedral lighting preset",
    Brightness = 1.0,
    ClockTime = 13.69,
    Exposure = 0.085,
    Ambient = rgb(207, 219, 239),
    OutdoorAmbient = rgb(163, 189, 229),
    FogColor = rgb(158, 184, 224),
    FogStart = 61,
    FogEnd = 2263,
    Diffuse = 0.45,
    Specular = 0.75,
    Tint = rgb(210, 222, 242),
    Contrast = 0.08,
    Saturation = 0.075,
    AtmosphereDensity = 0.296,
    Haze = 0.42,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_046")

AWE.Catalog.Scenes["SCENE_047"] = {
    Key = "SCENE_047",
    Name = "Blue Hour 047",
    Description = "blue hour lighting preset",
    Brightness = 0.7,
    ClockTime = 19.06,
    Exposure = 0.01,
    Ambient = rgb(109, 130, 182),
    OutdoorAmbient = rgb(58, 73, 124),
    FogColor = rgb(64, 79, 130),
    FogStart = 72,
    FogEnd = 2311,
    Diffuse = 0.4,
    Specular = 0.7,
    Tint = rgb(115, 136, 188),
    Contrast = 0.14,
    Saturation = 0.25,
    AtmosphereDensity = 0.152,
    Haze = 0.75,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_047")

AWE.Catalog.Scenes["SCENE_048"] = {
    Key = "SCENE_048",
    Name = "Lavender Fog 048",
    Description = "lavender fog lighting preset",
    Brightness = 1.1,
    ClockTime = 5.63,
    Exposure = 0.155,
    Ambient = rgb(183, 170, 213),
    OutdoorAmbient = rgb(138, 130, 185),
    FogColor = rgb(129, 121, 176),
    FogStart = 83,
    FogEnd = 2359,
    Diffuse = 0.35,
    Specular = 0.65,
    Tint = rgb(192, 179, 222),
    Contrast = -0.04,
    Saturation = 0.05,
    AtmosphereDensity = 0.236,
    Haze = 1.08,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_048")

AWE.Catalog.Scenes["SCENE_049"] = {
    Key = "SCENE_049",
    Name = "Glacier Cave 049",
    Description = "glacier cave lighting preset",
    Brightness = 0.6,
    ClockTime = 1.0,
    Exposure = -0.175,
    Ambient = rgb(115, 179, 200),
    OutdoorAmbient = rgb(67, 112, 145),
    FogColor = rgb(68, 113, 146),
    FogStart = 94,
    FogEnd = 2407,
    Diffuse = 0.9,
    Specular = 0.6,
    Tint = rgb(106, 170, 191),
    Contrast = 0.02,
    Saturation = 0.225,
    AtmosphereDensity = 0.092,
    Haze = 1.41,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_049")

AWE.Catalog.Scenes["SCENE_050"] = {
    Key = "SCENE_050",
    Name = "Warm Pearl 050",
    Description = "warm pearl lighting preset",
    Brightness = 1.0,
    ClockTime = 10.37,
    Exposure = -0.02,
    Ambient = rgb(250, 239, 220),
    OutdoorAmbient = rgb(169, 152, 135),
    FogColor = rgb(182, 165, 148),
    FogStart = 105,
    FogEnd = 2455,
    Diffuse = 0.85,
    Specular = 0.55,
    Tint = rgb(244, 233, 214),
    Contrast = 0.08,
    Saturation = 0.025,
    AtmosphereDensity = 0.176,
    Haze = 1.74,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_050")

AWE.Catalog.Scenes["SCENE_051"] = {
    Key = "SCENE_051",
    Name = "Pearl Dawn 051",
    Description = "pearl dawn lighting preset",
    Brightness = 1.2,
    ClockTime = 6.74,
    Exposure = 0.035,
    Ambient = rgb(174, 208, 228),
    OutdoorAmbient = rgb(120, 161, 193),
    FogColor = rgb(118, 159, 191),
    FogStart = 116,
    FogEnd = 2503,
    Diffuse = 0.8,
    Specular = 0.5,
    Tint = rgb(171, 205, 225),
    Contrast = 0.14,
    Saturation = 0.2,
    AtmosphereDensity = 0.26,
    Haze = 0.2,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_051")

AWE.Catalog.Scenes["SCENE_052"] = {
    Key = "SCENE_052",
    Name = "Moonlit Harbor 052",
    Description = "moonlit harbor lighting preset",
    Brightness = -0.1,
    ClockTime = 0.81,
    Exposure = -0.08,
    Ambient = rgb(97, 127, 177),
    OutdoorAmbient = rgb(49, 69, 108),
    FogColor = rgb(57, 77, 116),
    FogStart = 127,
    FogEnd = 2551,
    Diffuse = 0.75,
    Specular = 0.45,
    Tint = rgb(97, 127, 177),
    Contrast = -0.04,
    Saturation = 0.0,
    AtmosphereDensity = 0.116,
    Haze = 0.53,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_052")

AWE.Catalog.Scenes["SCENE_053"] = {
    Key = "SCENE_053",
    Name = "Arctic Morning 053",
    Description = "arctic morning lighting preset",
    Brightness = 1.0,
    ClockTime = 8.78,
    Exposure = 0.055,
    Ambient = rgb(196, 225, 239),
    OutdoorAmbient = rgb(161, 198, 217),
    FogColor = rgb(154, 191, 210),
    FogStart = 138,
    FogEnd = 2599,
    Diffuse = 0.7,
    Specular = 0.4,
    Tint = rgb(199, 228, 242),
    Contrast = 0.02,
    Saturation = 0.175,
    AtmosphereDensity = 0.2,
    Haze = 0.86,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_053")

AWE.Catalog.Scenes["SCENE_054"] = {
    Key = "SCENE_054",
    Name = "Aquamarine Noon 054",
    Description = "aquamarine noon lighting preset",
    Brightness = 1.1,
    ClockTime = 12.02,
    Exposure = 0.07,
    Ambient = rgb(154, 227, 236),
    OutdoorAmbient = rgb(109, 174, 197),
    FogColor = rgb(113, 178, 201),
    FogStart = 149,
    FogEnd = 2647,
    Diffuse = 0.65,
    Specular = 0.35,
    Tint = rgb(160, 233, 242),
    Contrast = 0.08,
    Saturation = -0.025,
    AtmosphereDensity = 0.284,
    Haze = 1.19,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_054")

AWE.Catalog.Scenes["SCENE_055"] = {
    Key = "SCENE_055",
    Name = "Silver Sunset 055",
    Description = "silver sunset lighting preset",
    Brightness = 1.2,
    ClockTime = 17.29,
    Exposure = 0.115,
    Ambient = rgb(222, 176, 164),
    OutdoorAmbient = rgb(168, 133, 157),
    FogColor = rgb(157, 122, 146),
    FogStart = 160,
    FogEnd = 695,
    Diffuse = 0.6,
    Specular = 0.3,
    Tint = rgb(231, 185, 173),
    Contrast = 0.14,
    Saturation = 0.15,
    AtmosphereDensity = 0.14,
    Haze = 1.52,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_055")

AWE.Catalog.Scenes["SCENE_056"] = {
    Key = "SCENE_056",
    Name = "Cloud Cathedral 056",
    Description = "cloud cathedral lighting preset",
    Brightness = 1.0,
    ClockTime = 13.86,
    Exposure = -0.015,
    Ambient = rgb(213, 225, 245),
    OutdoorAmbient = rgb(160, 186, 226),
    FogColor = rgb(160, 186, 226),
    FogStart = 171,
    FogEnd = 743,
    Diffuse = 0.55,
    Specular = 0.25,
    Tint = rgb(204, 216, 236),
    Contrast = -0.04,
    Saturation = -0.05,
    AtmosphereDensity = 0.224,
    Haze = 1.85,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_056")

AWE.Catalog.Scenes["SCENE_057"] = {
    Key = "SCENE_057",
    Name = "Blue Hour 057",
    Description = "blue hour lighting preset",
    Brightness = 0.7,
    ClockTime = 19.23,
    Exposure = -0.09,
    Ambient = rgb(115, 136, 188),
    OutdoorAmbient = rgb(55, 70, 121),
    FogColor = rgb(66, 81, 132),
    FogStart = 182,
    FogEnd = 791,
    Diffuse = 0.5,
    Specular = 0.9,
    Tint = rgb(109, 130, 182),
    Contrast = 0.02,
    Saturation = 0.125,
    AtmosphereDensity = 0.08,
    Haze = 0.31,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_057")

AWE.Catalog.Scenes["SCENE_058"] = {
    Key = "SCENE_058",
    Name = "Lavender Fog 058",
    Description = "lavender fog lighting preset",
    Brightness = 1.1,
    ClockTime = 5.8,
    Exposure = 0.055,
    Ambient = rgb(189, 176, 219),
    OutdoorAmbient = rgb(135, 127, 182),
    FogColor = rgb(131, 123, 178),
    FogStart = 193,
    FogEnd = 839,
    Diffuse = 0.45,
    Specular = 0.85,
    Tint = rgb(186, 173, 216),
    Contrast = 0.08,
    Saturation = -0.075,
    AtmosphereDensity = 0.164,
    Haze = 0.64,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_058")

AWE.Catalog.Scenes["SCENE_059"] = {
    Key = "SCENE_059",
    Name = "Glacier Cave 059",
    Description = "glacier cave lighting preset",
    Brightness = 0.6,
    ClockTime = 1.17,
    Exposure = -0.1,
    Ambient = rgb(121, 185, 206),
    OutdoorAmbient = rgb(64, 109, 142),
    FogColor = rgb(70, 115, 148),
    FogStart = 44,
    FogEnd = 727,
    Diffuse = 0.4,
    Specular = 0.8,
    Tint = rgb(121, 185, 206),
    Contrast = 0.14,
    Saturation = 0.1,
    AtmosphereDensity = 0.248,
    Haze = 0.97,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_059")

AWE.Catalog.Scenes["SCENE_060"] = {
    Key = "SCENE_060",
    Name = "Warm Pearl 060",
    Description = "warm pearl lighting preset",
    Brightness = 1.0,
    ClockTime = 10.54,
    Exposure = 0.055,
    Ambient = rgb(225, 214, 195),
    OutdoorAmbient = rgb(182, 165, 148),
    FogColor = rgb(173, 156, 139),
    FogStart = 55,
    FogEnd = 775,
    Diffuse = 0.35,
    Specular = 0.75,
    Tint = rgb(228, 217, 198),
    Contrast = -0.04,
    Saturation = -0.1,
    AtmosphereDensity = 0.104,
    Haze = 1.3,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_060")

AWE.Catalog.Scenes["SCENE_061"] = {
    Key = "SCENE_061",
    Name = "Pearl Dawn 061",
    Description = "pearl dawn lighting preset",
    Brightness = 1.2,
    ClockTime = 6.91,
    Exposure = 0.11,
    Ambient = rgb(180, 214, 234),
    OutdoorAmbient = rgb(117, 158, 190),
    FogColor = rgb(120, 161, 193),
    FogStart = 66,
    FogEnd = 823,
    Diffuse = 0.9,
    Specular = 0.7,
    Tint = rgb(186, 220, 240),
    Contrast = 0.02,
    Saturation = 0.075,
    AtmosphereDensity = 0.188,
    Haze = 1.63,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_061")

AWE.Catalog.Scenes["SCENE_062"] = {
    Key = "SCENE_062",
    Name = "Moonlit Harbor 062",
    Description = "moonlit harbor lighting preset",
    Brightness = -0.1,
    ClockTime = 0.98,
    Exposure = -0.005,
    Ambient = rgb(72, 102, 152),
    OutdoorAmbient = rgb(61, 81, 120),
    FogColor = rgb(49, 69, 108),
    FogStart = 77,
    FogEnd = 871,
    Diffuse = 0.85,
    Specular = 0.65,
    Tint = rgb(81, 111, 161),
    Contrast = 0.08,
    Saturation = 0.25,
    AtmosphereDensity = 0.272,
    Haze = 1.96,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_062")

AWE.Catalog.Scenes["SCENE_063"] = {
    Key = "SCENE_063",
    Name = "Arctic Morning 063",
    Description = "arctic morning lighting preset",
    Brightness = 1.0,
    ClockTime = 7.42,
    Exposure = -0.045,
    Ambient = rgb(202, 231, 245),
    OutdoorAmbient = rgb(158, 195, 214),
    FogColor = rgb(156, 193, 212),
    FogStart = 88,
    FogEnd = 919,
    Diffuse = 0.8,
    Specular = 0.6,
    Tint = rgb(193, 222, 236),
    Contrast = 0.14,
    Saturation = 0.05,
    AtmosphereDensity = 0.128,
    Haze = 0.42,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_063")

AWE.Catalog.Scenes["SCENE_064"] = {
    Key = "SCENE_064",
    Name = "Aquamarine Noon 064",
    Description = "aquamarine noon lighting preset",
    Brightness = 1.1,
    ClockTime = 12.19,
    Exposure = -0.03,
    Ambient = rgb(160, 233, 242),
    OutdoorAmbient = rgb(106, 171, 194),
    FogColor = rgb(115, 180, 203),
    FogStart = 99,
    FogEnd = 967,
    Diffuse = 0.75,
    Specular = 0.55,
    Tint = rgb(154, 227, 236),
    Contrast = -0.04,
    Saturation = 0.225,
    AtmosphereDensity = 0.212,
    Haze = 0.75,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_064")

AWE.Catalog.Scenes["SCENE_065"] = {
    Key = "SCENE_065",
    Name = "Silver Sunset 065",
    Description = "silver sunset lighting preset",
    Brightness = 1.2,
    ClockTime = 17.46,
    Exposure = 0.015,
    Ambient = rgb(228, 182, 170),
    OutdoorAmbient = rgb(165, 130, 154),
    FogColor = rgb(159, 124, 148),
    FogStart = 110,
    FogEnd = 1015,
    Diffuse = 0.7,
    Specular = 0.5,
    Tint = rgb(225, 179, 167),
    Contrast = 0.02,
    Saturation = 0.025,
    AtmosphereDensity = 0.296,
    Haze = 1.08,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_065")

AWE.Catalog.Scenes["SCENE_066"] = {
    Key = "SCENE_066",
    Name = "Cloud Cathedral 066",
    Description = "cloud cathedral lighting preset",
    Brightness = 1.0,
    ClockTime = 14.03,
    Exposure = 0.06,
    Ambient = rgb(219, 231, 251),
    OutdoorAmbient = rgb(157, 183, 223),
    FogColor = rgb(162, 188, 228),
    FogStart = 121,
    FogEnd = 1063,
    Diffuse = 0.65,
    Specular = 0.45,
    Tint = rgb(219, 231, 251),
    Contrast = 0.08,
    Saturation = 0.2,
    AtmosphereDensity = 0.152,
    Haze = 1.41,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_066")

AWE.Catalog.Scenes["SCENE_067"] = {
    Key = "SCENE_067",
    Name = "Blue Hour 067",
    Description = "blue hour lighting preset",
    Brightness = 0.7,
    ClockTime = 19.4,
    Exposure = -0.015,
    Ambient = rgb(90, 111, 163),
    OutdoorAmbient = rgb(68, 83, 134),
    FogColor = rgb(58, 73, 124),
    FogStart = 132,
    FogEnd = 1111,
    Diffuse = 0.6,
    Specular = 0.4,
    Tint = rgb(93, 114, 166),
    Contrast = 0.14,
    Saturation = 0.0,
    AtmosphereDensity = 0.236,
    Haze = 1.74,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_067")

AWE.Catalog.Scenes["SCENE_068"] = {
    Key = "SCENE_068",
    Name = "Lavender Fog 068",
    Description = "lavender fog lighting preset",
    Brightness = 1.1,
    ClockTime = 5.97,
    Exposure = 0.13,
    Ambient = rgb(195, 182, 225),
    OutdoorAmbient = rgb(132, 124, 179),
    FogColor = rgb(133, 125, 180),
    FogStart = 143,
    FogEnd = 1159,
    Diffuse = 0.55,
    Specular = 0.35,
    Tint = rgb(201, 188, 231),
    Contrast = -0.04,
    Saturation = 0.175,
    AtmosphereDensity = 0.092,
    Haze = 0.2,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_068")

AWE.Catalog.Scenes["SCENE_069"] = {
    Key = "SCENE_069",
    Name = "Glacier Cave 069",
    Description = "glacier cave lighting preset",
    Brightness = 0.6,
    ClockTime = 1.34,
    Exposure = -0.025,
    Ambient = rgb(127, 191, 212),
    OutdoorAmbient = rgb(61, 106, 139),
    FogColor = rgb(72, 117, 150),
    FogStart = 154,
    FogEnd = 1207,
    Diffuse = 0.5,
    Specular = 0.3,
    Tint = rgb(136, 200, 221),
    Contrast = 0.02,
    Saturation = -0.025,
    AtmosphereDensity = 0.176,
    Haze = 0.53,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_069")

AWE.Catalog.Scenes["SCENE_070"] = {
    Key = "SCENE_070",
    Name = "Warm Pearl 070",
    Description = "warm pearl lighting preset",
    Brightness = 1.0,
    ClockTime = 10.71,
    Exposure = -0.045,
    Ambient = rgb(231, 220, 201),
    OutdoorAmbient = rgb(179, 162, 145),
    FogColor = rgb(175, 158, 141),
    FogStart = 165,
    FogEnd = 1255,
    Diffuse = 0.45,
    Specular = 0.25,
    Tint = rgb(222, 211, 192),
    Contrast = 0.08,
    Saturation = 0.15,
    AtmosphereDensity = 0.26,
    Haze = 0.86,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_070")

AWE.Catalog.Scenes["SCENE_071"] = {
    Key = "SCENE_071",
    Name = "Pearl Dawn 071",
    Description = "pearl dawn lighting preset",
    Brightness = 1.2,
    ClockTime = 7.08,
    Exposure = 0.01,
    Ambient = rgb(186, 220, 240),
    OutdoorAmbient = rgb(114, 155, 187),
    FogColor = rgb(122, 163, 195),
    FogStart = 176,
    FogEnd = 1303,
    Diffuse = 0.4,
    Specular = 0.9,
    Tint = rgb(180, 214, 234),
    Contrast = 0.14,
    Saturation = -0.05,
    AtmosphereDensity = 0.116,
    Haze = 1.19,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_071")

AWE.Catalog.Scenes["SCENE_072"] = {
    Key = "SCENE_072",
    Name = "Moonlit Harbor 072",
    Description = "moonlit harbor lighting preset",
    Brightness = -0.1,
    ClockTime = 23.62,
    Exposure = -0.105,
    Ambient = rgb(78, 108, 158),
    OutdoorAmbient = rgb(58, 78, 117),
    FogColor = rgb(51, 71, 110),
    FogStart = 187,
    FogEnd = 1351,
    Diffuse = 0.35,
    Specular = 0.85,
    Tint = rgb(75, 105, 155),
    Contrast = -0.04,
    Saturation = 0.125,
    AtmosphereDensity = 0.2,
    Haze = 1.52,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_072")

AWE.Catalog.Scenes["SCENE_073"] = {
    Key = "SCENE_073",
    Name = "Arctic Morning 073",
    Description = "arctic morning lighting preset",
    Brightness = 1.0,
    ClockTime = 7.59,
    Exposure = 0.03,
    Ambient = rgb(208, 237, 251),
    OutdoorAmbient = rgb(155, 192, 211),
    FogColor = rgb(158, 195, 214),
    FogStart = 38,
    FogEnd = 1239,
    Diffuse = 0.9,
    Specular = 0.8,
    Tint = rgb(208, 237, 251),
    Contrast = 0.02,
    Saturation = -0.075,
    AtmosphereDensity = 0.284,
    Haze = 1.85,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_073")

AWE.Catalog.Scenes["SCENE_074"] = {
    Key = "SCENE_074",
    Name = "Aquamarine Noon 074",
    Description = "aquamarine noon lighting preset",
    Brightness = 1.1,
    ClockTime = 12.36,
    Exposure = 0.045,
    Ambient = rgb(135, 208, 217),
    OutdoorAmbient = rgb(119, 184, 207),
    FogColor = rgb(107, 172, 195),
    FogStart = 49,
    FogEnd = 1287,
    Diffuse = 0.85,
    Specular = 0.75,
    Tint = rgb(138, 211, 220),
    Contrast = 0.08,
    Saturation = 0.1,
    AtmosphereDensity = 0.14,
    Haze = 0.31,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_074")

AWE.Catalog.Scenes["SCENE_075"] = {
    Key = "SCENE_075",
    Name = "Silver Sunset 075",
    Description = "silver sunset lighting preset",
    Brightness = 1.2,
    ClockTime = 17.63,
    Exposure = 0.09,
    Ambient = rgb(234, 188, 176),
    OutdoorAmbient = rgb(162, 127, 151),
    FogColor = rgb(161, 126, 150),
    FogStart = 60,
    FogEnd = 1335,
    Diffuse = 0.8,
    Specular = 0.7,
    Tint = rgb(240, 194, 182),
    Contrast = 0.14,
    Saturation = -0.1,
    AtmosphereDensity = 0.224,
    Haze = 0.64,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_075")

AWE.Catalog.Scenes["SCENE_076"] = {
    Key = "SCENE_076",
    Name = "Cloud Cathedral 076",
    Description = "cloud cathedral lighting preset",
    Brightness = 1.0,
    ClockTime = 14.2,
    Exposure = 0.135,
    Ambient = rgb(225, 237, 255),
    OutdoorAmbient = rgb(154, 180, 220),
    FogColor = rgb(164, 190, 230),
    FogStart = 71,
    FogEnd = 1383,
    Diffuse = 0.75,
    Specular = 0.65,
    Tint = rgb(234, 246, 255),
    Contrast = -0.04,
    Saturation = 0.075,
    AtmosphereDensity = 0.08,
    Haze = 0.97,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_076")

AWE.Catalog.Scenes["SCENE_077"] = {
    Key = "SCENE_077",
    Name = "Blue Hour 077",
    Description = "blue hour lighting preset",
    Brightness = 0.7,
    ClockTime = 19.57,
    Exposure = -0.115,
    Ambient = rgb(96, 117, 169),
    OutdoorAmbient = rgb(65, 80, 131),
    FogColor = rgb(60, 75, 126),
    FogStart = 82,
    FogEnd = 1431,
    Diffuse = 0.7,
    Specular = 0.6,
    Tint = rgb(87, 108, 160),
    Contrast = 0.02,
    Saturation = 0.25,
    AtmosphereDensity = 0.164,
    Haze = 1.3,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_077")

AWE.Catalog.Scenes["SCENE_078"] = {
    Key = "SCENE_078",
    Name = "Lavender Fog 078",
    Description = "lavender fog lighting preset",
    Brightness = 1.1,
    ClockTime = 6.14,
    Exposure = 0.03,
    Ambient = rgb(201, 188, 231),
    OutdoorAmbient = rgb(129, 121, 176),
    FogColor = rgb(135, 127, 182),
    FogStart = 93,
    FogEnd = 1479,
    Diffuse = 0.65,
    Specular = 0.55,
    Tint = rgb(195, 182, 225),
    Contrast = 0.08,
    Saturation = 0.05,
    AtmosphereDensity = 0.248,
    Haze = 1.63,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_078")

AWE.Catalog.Scenes["SCENE_079"] = {
    Key = "SCENE_079",
    Name = "Glacier Cave 079",
    Description = "glacier cave lighting preset",
    Brightness = 0.6,
    ClockTime = 1.51,
    Exposure = -0.125,
    Ambient = rgb(102, 166, 187),
    OutdoorAmbient = rgb(73, 118, 151),
    FogColor = rgb(64, 109, 142),
    FogStart = 104,
    FogEnd = 1527,
    Diffuse = 0.6,
    Specular = 0.5,
    Tint = rgb(99, 163, 184),
    Contrast = 0.14,
    Saturation = 0.225,
    AtmosphereDensity = 0.104,
    Haze = 1.96,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_079")

AWE.Catalog.Scenes["SCENE_080"] = {
    Key = "SCENE_080",
    Name = "Warm Pearl 080",
    Description = "warm pearl lighting preset",
    Brightness = 1.0,
    ClockTime = 10.88,
    Exposure = 0.03,
    Ambient = rgb(237, 226, 207),
    OutdoorAmbient = rgb(176, 159, 142),
    FogColor = rgb(177, 160, 143),
    FogStart = 115,
    FogEnd = 1575,
    Diffuse = 0.55,
    Specular = 0.45,
    Tint = rgb(237, 226, 207),
    Contrast = -0.04,
    Saturation = 0.025,
    AtmosphereDensity = 0.188,
    Haze = 0.42,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_080")

AWE.Catalog.Scenes["SCENE_081"] = {
    Key = "SCENE_081",
    Name = "Pearl Dawn 081",
    Description = "pearl dawn lighting preset",
    Brightness = 1.2,
    ClockTime = 5.72,
    Exposure = 0.085,
    Ambient = rgb(192, 226, 246),
    OutdoorAmbient = rgb(111, 152, 184),
    FogColor = rgb(124, 165, 197),
    FogStart = 126,
    FogEnd = 1623,
    Diffuse = 0.5,
    Specular = 0.4,
    Tint = rgb(195, 229, 249),
    Contrast = 0.02,
    Saturation = 0.2,
    AtmosphereDensity = 0.272,
    Haze = 0.75,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_081")

AWE.Catalog.Scenes["SCENE_082"] = {
    Key = "SCENE_082",
    Name = "Moonlit Harbor 082",
    Description = "moonlit harbor lighting preset",
    Brightness = -0.1,
    ClockTime = 23.79,
    Exposure = -0.03,
    Ambient = rgb(84, 114, 164),
    OutdoorAmbient = rgb(55, 75, 114),
    FogColor = rgb(53, 73, 112),
    FogStart = 137,
    FogEnd = 1671,
    Diffuse = 0.45,
    Specular = 0.35,
    Tint = rgb(90, 120, 170),
    Contrast = 0.08,
    Saturation = 0.0,
    AtmosphereDensity = 0.128,
    Haze = 1.08,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_082")

AWE.Catalog.Scenes["SCENE_083"] = {
    Key = "SCENE_083",
    Name = "Arctic Morning 083",
    Description = "arctic morning lighting preset",
    Brightness = 1.0,
    ClockTime = 7.76,
    Exposure = 0.105,
    Ambient = rgb(214, 243, 255),
    OutdoorAmbient = rgb(152, 189, 208),
    FogColor = rgb(160, 197, 216),
    FogStart = 148,
    FogEnd = 1719,
    Diffuse = 0.4,
    Specular = 0.3,
    Tint = rgb(223, 252, 255),
    Contrast = 0.14,
    Saturation = 0.175,
    AtmosphereDensity = 0.212,
    Haze = 1.41,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_083")

AWE.Catalog.Scenes["SCENE_084"] = {
    Key = "SCENE_084",
    Name = "Aquamarine Noon 084",
    Description = "aquamarine noon lighting preset",
    Brightness = 1.1,
    ClockTime = 12.53,
    Exposure = -0.055,
    Ambient = rgb(141, 214, 223),
    OutdoorAmbient = rgb(116, 181, 204),
    FogColor = rgb(109, 174, 197),
    FogStart = 159,
    FogEnd = 1767,
    Diffuse = 0.35,
    Specular = 0.25,
    Tint = rgb(132, 205, 214),
    Contrast = -0.04,
    Saturation = -0.025,
    AtmosphereDensity = 0.296,
    Haze = 1.74,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_084")

AWE.Catalog.Scenes["SCENE_085"] = {
    Key = "SCENE_085",
    Name = "Silver Sunset 085",
    Description = "silver sunset lighting preset",
    Brightness = 1.2,
    ClockTime = 17.8,
    Exposure = -0.01,
    Ambient = rgb(240, 194, 182),
    OutdoorAmbient = rgb(159, 124, 148),
    FogColor = rgb(163, 128, 152),
    FogStart = 170,
    FogEnd = 1815,
    Diffuse = 0.9,
    Specular = 0.9,
    Tint = rgb(234, 188, 176),
    Contrast = 0.02,
    Saturation = 0.15,
    AtmosphereDensity = 0.152,
    Haze = 0.2,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_085")

AWE.Catalog.Scenes["SCENE_086"] = {
    Key = "SCENE_086",
    Name = "Cloud Cathedral 086",
    Description = "cloud cathedral lighting preset",
    Brightness = 1.0,
    ClockTime = 14.37,
    Exposure = 0.035,
    Ambient = rgb(200, 212, 232),
    OutdoorAmbient = rgb(166, 192, 232),
    FogColor = rgb(155, 181, 221),
    FogStart = 181,
    FogEnd = 1863,
    Diffuse = 0.85,
    Specular = 0.85,
    Tint = rgb(197, 209, 229),
    Contrast = 0.08,
    Saturation = -0.05,
    AtmosphereDensity = 0.236,
    Haze = 0.53,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_086")

AWE.Catalog.Scenes["SCENE_087"] = {
    Key = "SCENE_087",
    Name = "Blue Hour 087",
    Description = "blue hour lighting preset",
    Brightness = 0.7,
    ClockTime = 19.74,
    Exposure = -0.04,
    Ambient = rgb(102, 123, 175),
    OutdoorAmbient = rgb(62, 77, 128),
    FogColor = rgb(62, 77, 128),
    FogStart = 192,
    FogEnd = 1911,
    Diffuse = 0.8,
    Specular = 0.8,
    Tint = rgb(102, 123, 175),
    Contrast = 0.14,
    Saturation = 0.125,
    AtmosphereDensity = 0.092,
    Haze = 0.86,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_087")

AWE.Catalog.Scenes["SCENE_088"] = {
    Key = "SCENE_088",
    Name = "Lavender Fog 088",
    Description = "lavender fog lighting preset",
    Brightness = 1.1,
    ClockTime = 6.31,
    Exposure = 0.105,
    Ambient = rgb(207, 194, 237),
    OutdoorAmbient = rgb(126, 118, 173),
    FogColor = rgb(137, 129, 184),
    FogStart = 43,
    FogEnd = 1799,
    Diffuse = 0.75,
    Specular = 0.75,
    Tint = rgb(210, 197, 240),
    Contrast = -0.04,
    Saturation = -0.075,
    AtmosphereDensity = 0.176,
    Haze = 1.19,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_088")

AWE.Catalog.Scenes["SCENE_089"] = {
    Key = "SCENE_089",
    Name = "Glacier Cave 089",
    Description = "glacier cave lighting preset",
    Brightness = 0.6,
    ClockTime = 1.68,
    Exposure = -0.05,
    Ambient = rgb(108, 172, 193),
    OutdoorAmbient = rgb(70, 115, 148),
    FogColor = rgb(66, 111, 144),
    FogStart = 54,
    FogEnd = 1847,
    Diffuse = 0.7,
    Specular = 0.7,
    Tint = rgb(114, 178, 199),
    Contrast = 0.02,
    Saturation = 0.1,
    AtmosphereDensity = 0.26,
    Haze = 1.52,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_089")

AWE.Catalog.Scenes["SCENE_090"] = {
    Key = "SCENE_090",
    Name = "Warm Pearl 090",
    Description = "warm pearl lighting preset",
    Brightness = 1.0,
    ClockTime = 9.52,
    Exposure = 0.105,
    Ambient = rgb(243, 232, 213),
    OutdoorAmbient = rgb(173, 156, 139),
    FogColor = rgb(179, 162, 145),
    FogStart = 65,
    FogEnd = 1895,
    Diffuse = 0.65,
    Specular = 0.65,
    Tint = rgb(252, 241, 222),
    Contrast = 0.08,
    Saturation = -0.1,
    AtmosphereDensity = 0.116,
    Haze = 1.85,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_090")

AWE.Catalog.Scenes["SCENE_091"] = {
    Key = "SCENE_091",
    Name = "Pearl Dawn 091",
    Description = "pearl dawn lighting preset",
    Brightness = 1.2,
    ClockTime = 5.89,
    Exposure = -0.015,
    Ambient = rgb(167, 201, 221),
    OutdoorAmbient = rgb(124, 165, 197),
    FogColor = rgb(115, 156, 188),
    FogStart = 76,
    FogEnd = 1943,
    Diffuse = 0.6,
    Specular = 0.6,
    Tint = rgb(158, 192, 212),
    Contrast = 0.14,
    Saturation = 0.075,
    AtmosphereDensity = 0.2,
    Haze = 0.31,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_091")

AWE.Catalog.Scenes["SCENE_092"] = {
    Key = "SCENE_092",
    Name = "Moonlit Harbor 092",
    Description = "moonlit harbor lighting preset",
    Brightness = -0.1,
    ClockTime = 23.96,
    Exposure = -0.13,
    Ambient = rgb(90, 120, 170),
    OutdoorAmbient = rgb(52, 72, 111),
    FogColor = rgb(55, 75, 114),
    FogStart = 87,
    FogEnd = 1991,
    Diffuse = 0.55,
    Specular = 0.55,
    Tint = rgb(84, 114, 164),
    Contrast = -0.04,
    Saturation = 0.25,
    AtmosphereDensity = 0.284,
    Haze = 0.64,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_092")

AWE.Catalog.Scenes["SCENE_093"] = {
    Key = "SCENE_093",
    Name = "Arctic Morning 093",
    Description = "arctic morning lighting preset",
    Brightness = 1.0,
    ClockTime = 7.93,
    Exposure = 0.005,
    Ambient = rgb(189, 218, 232),
    OutdoorAmbient = rgb(164, 201, 220),
    FogColor = rgb(152, 189, 208),
    FogStart = 98,
    FogEnd = 2039,
    Diffuse = 0.5,
    Specular = 0.5,
    Tint = rgb(186, 215, 229),
    Contrast = 0.02,
    Saturation = 0.05,
    AtmosphereDensity = 0.14,
    Haze = 0.97,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_093")

AWE.Catalog.Scenes["SCENE_094"] = {
    Key = "SCENE_094",
    Name = "Aquamarine Noon 094",
    Description = "aquamarine noon lighting preset",
    Brightness = 1.1,
    ClockTime = 12.7,
    Exposure = 0.02,
    Ambient = rgb(147, 220, 229),
    OutdoorAmbient = rgb(113, 178, 201),
    FogColor = rgb(111, 176, 199),
    FogStart = 109,
    FogEnd = 2087,
    Diffuse = 0.45,
    Specular = 0.45,
    Tint = rgb(147, 220, 229),
    Contrast = 0.08,
    Saturation = 0.225,
    AtmosphereDensity = 0.224,
    Haze = 1.3,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_094")

AWE.Catalog.Scenes["SCENE_095"] = {
    Key = "SCENE_095",
    Name = "Silver Sunset 095",
    Description = "silver sunset lighting preset",
    Brightness = 1.2,
    ClockTime = 17.97,
    Exposure = 0.065,
    Ambient = rgb(246, 200, 188),
    OutdoorAmbient = rgb(156, 121, 145),
    FogColor = rgb(165, 130, 154),
    FogStart = 120,
    FogEnd = 2135,
    Diffuse = 0.4,
    Specular = 0.4,
    Tint = rgb(249, 203, 191),
    Contrast = 0.14,
    Saturation = 0.025,
    AtmosphereDensity = 0.08,
    Haze = 1.63,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_095")

AWE.Catalog.Scenes["SCENE_096"] = {
    Key = "SCENE_096",
    Name = "Cloud Cathedral 096",
    Description = "cloud cathedral lighting preset",
    Brightness = 1.0,
    ClockTime = 14.54,
    Exposure = 0.11,
    Ambient = rgb(206, 218, 238),
    OutdoorAmbient = rgb(163, 189, 229),
    FogColor = rgb(157, 183, 223),
    FogStart = 131,
    FogEnd = 2183,
    Diffuse = 0.35,
    Specular = 0.35,
    Tint = rgb(212, 224, 244),
    Contrast = -0.04,
    Saturation = 0.2,
    AtmosphereDensity = 0.164,
    Haze = 1.96,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_096")

AWE.Catalog.Scenes["SCENE_097"] = {
    Key = "SCENE_097",
    Name = "Blue Hour 097",
    Description = "blue hour lighting preset",
    Brightness = 0.7,
    ClockTime = 19.91,
    Exposure = 0.035,
    Ambient = rgb(108, 129, 181),
    OutdoorAmbient = rgb(59, 74, 125),
    FogColor = rgb(64, 79, 130),
    FogStart = 142,
    FogEnd = 2231,
    Diffuse = 0.9,
    Specular = 0.3,
    Tint = rgb(117, 138, 190),
    Contrast = 0.02,
    Saturation = 0.0,
    AtmosphereDensity = 0.248,
    Haze = 0.42,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_097")

AWE.Catalog.Scenes["SCENE_098"] = {
    Key = "SCENE_098",
    Name = "Lavender Fog 098",
    Description = "lavender fog lighting preset",
    Brightness = 1.1,
    ClockTime = 6.48,
    Exposure = 0.005,
    Ambient = rgb(182, 169, 212),
    OutdoorAmbient = rgb(139, 131, 186),
    FogColor = rgb(129, 121, 176),
    FogStart = 153,
    FogEnd = 2279,
    Diffuse = 0.85,
    Specular = 0.25,
    Tint = rgb(173, 160, 203),
    Contrast = 0.08,
    Saturation = 0.175,
    AtmosphereDensity = 0.104,
    Haze = 0.75,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_098")

AWE.Catalog.Scenes["SCENE_099"] = {
    Key = "SCENE_099",
    Name = "Glacier Cave 099",
    Description = "glacier cave lighting preset",
    Brightness = 0.6,
    ClockTime = 0.32,
    Exposure = -0.15,
    Ambient = rgb(114, 178, 199),
    OutdoorAmbient = rgb(67, 112, 145),
    FogColor = rgb(68, 113, 146),
    FogStart = 164,
    FogEnd = 2327,
    Diffuse = 0.8,
    Specular = 0.9,
    Tint = rgb(108, 172, 193),
    Contrast = 0.14,
    Saturation = -0.025,
    AtmosphereDensity = 0.188,
    Haze = 1.08,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_099")

AWE.Catalog.Scenes["SCENE_100"] = {
    Key = "SCENE_100",
    Name = "Warm Pearl 100",
    Description = "warm pearl lighting preset",
    Brightness = 1.0,
    ClockTime = 9.69,
    Exposure = 0.005,
    Ambient = rgb(249, 238, 219),
    OutdoorAmbient = rgb(170, 153, 136),
    FogColor = rgb(181, 164, 147),
    FogStart = 175,
    FogEnd = 2375,
    Diffuse = 0.75,
    Specular = 0.85,
    Tint = rgb(246, 235, 216),
    Contrast = -0.04,
    Saturation = 0.15,
    AtmosphereDensity = 0.272,
    Haze = 1.41,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_100")

AWE.Catalog.Scenes["SCENE_101"] = {
    Key = "SCENE_101",
    Name = "Pearl Dawn 101",
    Description = "pearl dawn lighting preset",
    Brightness = 1.2,
    ClockTime = 6.06,
    Exposure = 0.06,
    Ambient = rgb(173, 207, 227),
    OutdoorAmbient = rgb(121, 162, 194),
    FogColor = rgb(117, 158, 190),
    FogStart = 186,
    FogEnd = 2423,
    Diffuse = 0.7,
    Specular = 0.8,
    Tint = rgb(173, 207, 227),
    Contrast = 0.02,
    Saturation = -0.05,
    AtmosphereDensity = 0.128,
    Haze = 1.74,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_101")

AWE.Catalog.Scenes["SCENE_102"] = {
    Key = "SCENE_102",
    Name = "Moonlit Harbor 102",
    Description = "moonlit harbor lighting preset",
    Brightness = -0.1,
    ClockTime = 0.13,
    Exposure = -0.055,
    Ambient = rgb(96, 126, 176),
    OutdoorAmbient = rgb(49, 69, 108),
    FogColor = rgb(57, 77, 116),
    FogStart = 37,
    FogEnd = 2311,
    Diffuse = 0.65,
    Specular = 0.75,
    Tint = rgb(99, 129, 179),
    Contrast = 0.08,
    Saturation = 0.125,
    AtmosphereDensity = 0.212,
    Haze = 0.2,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_102")

AWE.Catalog.Scenes["SCENE_103"] = {
    Key = "SCENE_103",
    Name = "Arctic Morning 103",
    Description = "arctic morning lighting preset",
    Brightness = 1.0,
    ClockTime = 8.1,
    Exposure = 0.08,
    Ambient = rgb(195, 224, 238),
    OutdoorAmbient = rgb(161, 198, 217),
    FogColor = rgb(154, 191, 210),
    FogStart = 48,
    FogEnd = 2359,
    Diffuse = 0.6,
    Specular = 0.7,
    Tint = rgb(201, 230, 244),
    Contrast = 0.14,
    Saturation = -0.075,
    AtmosphereDensity = 0.296,
    Haze = 0.53,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_103")

AWE.Catalog.Scenes["SCENE_104"] = {
    Key = "SCENE_104",
    Name = "Aquamarine Noon 104",
    Description = "aquamarine noon lighting preset",
    Brightness = 1.1,
    ClockTime = 12.87,
    Exposure = 0.095,
    Ambient = rgb(153, 226, 235),
    OutdoorAmbient = rgb(110, 175, 198),
    FogColor = rgb(113, 178, 201),
    FogStart = 59,
    FogEnd = 2407,
    Diffuse = 0.55,
    Specular = 0.65,
    Tint = rgb(162, 235, 244),
    Contrast = -0.04,
    Saturation = 0.1,
    AtmosphereDensity = 0.152,
    Haze = 0.86,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_104")

AWE.Catalog.Scenes["SCENE_105"] = {
    Key = "SCENE_105",
    Name = "Silver Sunset 105",
    Description = "silver sunset lighting preset",
    Brightness = 1.2,
    ClockTime = 18.14,
    Exposure = -0.035,
    Ambient = rgb(221, 175, 163),
    OutdoorAmbient = rgb(169, 134, 158),
    FogColor = rgb(157, 122, 146),
    FogStart = 70,
    FogEnd = 2455,
    Diffuse = 0.5,
    Specular = 0.6,
    Tint = rgb(212, 166, 154),
    Contrast = 0.02,
    Saturation = -0.1,
    AtmosphereDensity = 0.236,
    Haze = 1.19,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_105")

AWE.Catalog.Scenes["SCENE_106"] = {
    Key = "SCENE_106",
    Name = "Cloud Cathedral 106",
    Description = "cloud cathedral lighting preset",
    Brightness = 1.0,
    ClockTime = 14.71,
    Exposure = 0.01,
    Ambient = rgb(212, 224, 244),
    OutdoorAmbient = rgb(160, 186, 226),
    FogColor = rgb(159, 185, 225),
    FogStart = 81,
    FogEnd = 2503,
    Diffuse = 0.45,
    Specular = 0.55,
    Tint = rgb(206, 218, 238),
    Contrast = 0.08,
    Saturation = 0.075,
    AtmosphereDensity = 0.092,
    Haze = 1.52,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_106")

AWE.Catalog.Scenes["SCENE_107"] = {
    Key = "SCENE_107",
    Name = "Blue Hour 107",
    Description = "blue hour lighting preset",
    Brightness = 0.7,
    ClockTime = 20.08,
    Exposure = -0.065,
    Ambient = rgb(114, 135, 187),
    OutdoorAmbient = rgb(56, 71, 122),
    FogColor = rgb(66, 81, 132),
    FogStart = 92,
    FogEnd = 2551,
    Diffuse = 0.4,
    Specular = 0.5,
    Tint = rgb(111, 132, 184),
    Contrast = 0.14,
    Saturation = 0.25,
    AtmosphereDensity = 0.176,
    Haze = 1.85,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_107")

AWE.Catalog.Scenes["SCENE_108"] = {
    Key = "SCENE_108",
    Name = "Lavender Fog 108",
    Description = "lavender fog lighting preset",
    Brightness = 1.1,
    ClockTime = 5.12,
    Exposure = 0.08,
    Ambient = rgb(188, 175, 218),
    OutdoorAmbient = rgb(136, 128, 183),
    FogColor = rgb(131, 123, 178),
    FogStart = 103,
    FogEnd = 2599,
    Diffuse = 0.35,
    Specular = 0.45,
    Tint = rgb(188, 175, 218),
    Contrast = -0.04,
    Saturation = 0.05,
    AtmosphereDensity = 0.26,
    Haze = 0.31,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_108")

AWE.Catalog.Scenes["SCENE_109"] = {
    Key = "SCENE_109",
    Name = "Glacier Cave 109",
    Description = "glacier cave lighting preset",
    Brightness = 0.6,
    ClockTime = 0.49,
    Exposure = -0.075,
    Ambient = rgb(120, 184, 205),
    OutdoorAmbient = rgb(64, 109, 142),
    FogColor = rgb(70, 115, 148),
    FogStart = 114,
    FogEnd = 647,
    Diffuse = 0.9,
    Specular = 0.4,
    Tint = rgb(123, 187, 208),
    Contrast = 0.02,
    Saturation = 0.225,
    AtmosphereDensity = 0.116,
    Haze = 0.64,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_109")

AWE.Catalog.Scenes["SCENE_110"] = {
    Key = "SCENE_110",
    Name = "Warm Pearl 110",
    Description = "warm pearl lighting preset",
    Brightness = 1.0,
    ClockTime = 9.86,
    Exposure = 0.08,
    Ambient = rgb(224, 213, 194),
    OutdoorAmbient = rgb(182, 165, 148),
    FogColor = rgb(173, 156, 139),
    FogStart = 125,
    FogEnd = 695,
    Diffuse = 0.85,
    Specular = 0.35,
    Tint = rgb(230, 219, 200),
    Contrast = 0.08,
    Saturation = 0.025,
    AtmosphereDensity = 0.2,
    Haze = 0.97,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_110")

AWE.Catalog.Scenes["SCENE_111"] = {
    Key = "SCENE_111",
    Name = "Pearl Dawn 111",
    Description = "pearl dawn lighting preset",
    Brightness = 1.2,
    ClockTime = 6.23,
    Exposure = 0.135,
    Ambient = rgb(179, 213, 233),
    OutdoorAmbient = rgb(118, 159, 191),
    FogColor = rgb(119, 160, 192),
    FogStart = 136,
    FogEnd = 743,
    Diffuse = 0.8,
    Specular = 0.3,
    Tint = rgb(188, 222, 242),
    Contrast = 0.14,
    Saturation = 0.2,
    AtmosphereDensity = 0.284,
    Haze = 1.3,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_111")

AWE.Catalog.Scenes["SCENE_112"] = {
    Key = "SCENE_112",
    Name = "Moonlit Harbor 112",
    Description = "moonlit harbor lighting preset",
    Brightness = -0.1,
    ClockTime = 0.3,
    Exposure = -0.155,
    Ambient = rgb(102, 132, 182),
    OutdoorAmbient = rgb(46, 66, 105),
    FogColor = rgb(59, 79, 118),
    FogStart = 147,
    FogEnd = 791,
    Diffuse = 0.75,
    Specular = 0.25,
    Tint = rgb(93, 123, 173),
    Contrast = -0.04,
    Saturation = 0.0,
    AtmosphereDensity = 0.14,
    Haze = 1.63,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_112")

AWE.Catalog.Scenes["SCENE_113"] = {
    Key = "SCENE_113",
    Name = "Arctic Morning 113",
    Description = "arctic morning lighting preset",
    Brightness = 1.0,
    ClockTime = 8.27,
    Exposure = -0.02,
    Ambient = rgb(201, 230, 244),
    OutdoorAmbient = rgb(158, 195, 214),
    FogColor = rgb(156, 193, 212),
    FogStart = 158,
    FogEnd = 839,
    Diffuse = 0.7,
    Specular = 0.9,
    Tint = rgb(195, 224, 238),
    Contrast = 0.02,
    Saturation = 0.175,
    AtmosphereDensity = 0.224,
    Haze = 1.96,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_113")

AWE.Catalog.Scenes["SCENE_114"] = {
    Key = "SCENE_114",
    Name = "Aquamarine Noon 114",
    Description = "aquamarine noon lighting preset",
    Brightness = 1.1,
    ClockTime = 13.04,
    Exposure = -0.005,
    Ambient = rgb(159, 232, 241),
    OutdoorAmbient = rgb(107, 172, 195),
    FogColor = rgb(115, 180, 203),
    FogStart = 169,
    FogEnd = 887,
    Diffuse = 0.65,
    Specular = 0.85,
    Tint = rgb(156, 229, 238),
    Contrast = 0.08,
    Saturation = -0.025,
    AtmosphereDensity = 0.08,
    Haze = 0.42,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_114")

AWE.Catalog.Scenes["SCENE_115"] = {
    Key = "SCENE_115",
    Name = "Silver Sunset 115",
    Description = "silver sunset lighting preset",
    Brightness = 1.2,
    ClockTime = 18.31,
    Exposure = 0.04,
    Ambient = rgb(227, 181, 169),
    OutdoorAmbient = rgb(166, 131, 155),
    FogColor = rgb(159, 124, 148),
    FogStart = 180,
    FogEnd = 935,
    Diffuse = 0.6,
    Specular = 0.8,
    Tint = rgb(227, 181, 169),
    Contrast = 0.14,
    Saturation = 0.15,
    AtmosphereDensity = 0.164,
    Haze = 0.75,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_115")

AWE.Catalog.Scenes["SCENE_116"] = {
    Key = "SCENE_116",
    Name = "Cloud Cathedral 116",
    Description = "cloud cathedral lighting preset",
    Brightness = 1.0,
    ClockTime = 14.88,
    Exposure = 0.085,
    Ambient = rgb(218, 230, 250),
    OutdoorAmbient = rgb(157, 183, 223),
    FogColor = rgb(161, 187, 227),
    FogStart = 191,
    FogEnd = 983,
    Diffuse = 0.55,
    Specular = 0.75,
    Tint = rgb(221, 233, 253),
    Contrast = -0.04,
    Saturation = -0.05,
    AtmosphereDensity = 0.248,
    Haze = 1.08,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_116")

AWE.Catalog.Scenes["SCENE_117"] = {
    Key = "SCENE_117",
    Name = "Blue Hour 117",
    Description = "blue hour lighting preset",
    Brightness = 0.7,
    ClockTime = 18.72,
    Exposure = 0.01,
    Ambient = rgb(89, 110, 162),
    OutdoorAmbient = rgb(68, 83, 134),
    FogColor = rgb(57, 72, 123),
    FogStart = 42,
    FogEnd = 871,
    Diffuse = 0.5,
    Specular = 0.7,
    Tint = rgb(95, 116, 168),
    Contrast = 0.02,
    Saturation = 0.125,
    AtmosphereDensity = 0.104,
    Haze = 1.41,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_117")

AWE.Catalog.Scenes["SCENE_118"] = {
    Key = "SCENE_118",
    Name = "Lavender Fog 118",
    Description = "lavender fog lighting preset",
    Brightness = 1.1,
    ClockTime = 5.29,
    Exposure = 0.155,
    Ambient = rgb(194, 181, 224),
    OutdoorAmbient = rgb(133, 125, 180),
    FogColor = rgb(133, 125, 180),
    FogStart = 53,
    FogEnd = 919,
    Diffuse = 0.45,
    Specular = 0.65,
    Tint = rgb(203, 190, 233),
    Contrast = 0.08,
    Saturation = -0.075,
    AtmosphereDensity = 0.188,
    Haze = 1.74,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_118")

AWE.Catalog.Scenes["SCENE_119"] = {
    Key = "SCENE_119",
    Name = "Glacier Cave 119",
    Description = "glacier cave lighting preset",
    Brightness = 0.6,
    ClockTime = 0.66,
    Exposure = -0.175,
    Ambient = rgb(126, 190, 211),
    OutdoorAmbient = rgb(61, 106, 139),
    FogColor = rgb(72, 117, 150),
    FogStart = 64,
    FogEnd = 967,
    Diffuse = 0.4,
    Specular = 0.6,
    Tint = rgb(117, 181, 202),
    Contrast = 0.14,
    Saturation = 0.1,
    AtmosphereDensity = 0.272,
    Haze = 0.2,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_119")

AWE.Catalog.Scenes["SCENE_120"] = {
    Key = "SCENE_120",
    Name = "Warm Pearl 120",
    Description = "warm pearl lighting preset",
    Brightness = 1.0,
    ClockTime = 10.03,
    Exposure = -0.02,
    Ambient = rgb(230, 219, 200),
    OutdoorAmbient = rgb(179, 162, 145),
    FogColor = rgb(175, 158, 141),
    FogStart = 75,
    FogEnd = 1015,
    Diffuse = 0.35,
    Specular = 0.55,
    Tint = rgb(224, 213, 194),
    Contrast = -0.04,
    Saturation = -0.1,
    AtmosphereDensity = 0.128,
    Haze = 0.53,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_120")

AWE.Catalog.Scenes["SCENE_121"] = {
    Key = "SCENE_121",
    Name = "Pearl Dawn 121",
    Description = "pearl dawn lighting preset",
    Brightness = 1.2,
    ClockTime = 6.4,
    Exposure = 0.035,
    Ambient = rgb(185, 219, 239),
    OutdoorAmbient = rgb(115, 156, 188),
    FogColor = rgb(121, 162, 194),
    FogStart = 86,
    FogEnd = 1063,
    Diffuse = 0.9,
    Specular = 0.5,
    Tint = rgb(182, 216, 236),
    Contrast = 0.02,
    Saturation = 0.075,
    AtmosphereDensity = 0.212,
    Haze = 0.86,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_121")

AWE.Catalog.Scenes["SCENE_122"] = {
    Key = "SCENE_122",
    Name = "Moonlit Harbor 122",
    Description = "moonlit harbor lighting preset",
    Brightness = -0.1,
    ClockTime = 0.47,
    Exposure = -0.08,
    Ambient = rgb(77, 107, 157),
    OutdoorAmbient = rgb(59, 79, 118),
    FogColor = rgb(50, 70, 109),
    FogStart = 97,
    FogEnd = 1111,
    Diffuse = 0.85,
    Specular = 0.45,
    Tint = rgb(77, 107, 157),
    Contrast = 0.08,
    Saturation = 0.25,
    AtmosphereDensity = 0.296,
    Haze = 1.19,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_122")

AWE.Catalog.Scenes["SCENE_123"] = {
    Key = "SCENE_123",
    Name = "Arctic Morning 123",
    Description = "arctic morning lighting preset",
    Brightness = 1.0,
    ClockTime = 8.44,
    Exposure = 0.055,
    Ambient = rgb(207, 236, 250),
    OutdoorAmbient = rgb(155, 192, 211),
    FogColor = rgb(158, 195, 214),
    FogStart = 108,
    FogEnd = 1159,
    Diffuse = 0.8,
    Specular = 0.4,
    Tint = rgb(210, 239, 253),
    Contrast = 0.14,
    Saturation = 0.05,
    AtmosphereDensity = 0.152,
    Haze = 1.52,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_123")

AWE.Catalog.Scenes["SCENE_124"] = {
    Key = "SCENE_124",
    Name = "Aquamarine Noon 124",
    Description = "aquamarine noon lighting preset",
    Brightness = 1.1,
    ClockTime = 13.21,
    Exposure = 0.07,
    Ambient = rgb(134, 207, 216),
    OutdoorAmbient = rgb(119, 184, 207),
    FogColor = rgb(107, 172, 195),
    FogStart = 119,
    FogEnd = 1207,
    Diffuse = 0.75,
    Specular = 0.35,
    Tint = rgb(140, 213, 222),
    Contrast = -0.04,
    Saturation = 0.225,
    AtmosphereDensity = 0.236,
    Haze = 1.85,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_124")

AWE.Catalog.Scenes["SCENE_125"] = {
    Key = "SCENE_125",
    Name = "Silver Sunset 125",
    Description = "silver sunset lighting preset",
    Brightness = 1.2,
    ClockTime = 18.48,
    Exposure = 0.115,
    Ambient = rgb(233, 187, 175),
    OutdoorAmbient = rgb(163, 128, 152),
    FogColor = rgb(161, 126, 150),
    FogStart = 130,
    FogEnd = 1255,
    Diffuse = 0.7,
    Specular = 0.3,
    Tint = rgb(242, 196, 184),
    Contrast = 0.02,
    Saturation = 0.025,
    AtmosphereDensity = 0.092,
    Haze = 0.31,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_125")

AWE.Catalog.Scenes["SCENE_126"] = {
    Key = "SCENE_126",
    Name = "Cloud Cathedral 126",
    Description = "cloud cathedral lighting preset",
    Brightness = 1.0,
    ClockTime = 13.52,
    Exposure = -0.015,
    Ambient = rgb(224, 236, 255),
    OutdoorAmbient = rgb(154, 180, 220),
    FogColor = rgb(163, 189, 229),
    FogStart = 141,
    FogEnd = 1303,
    Diffuse = 0.65,
    Specular = 0.25,
    Tint = rgb(215, 227, 246),
    Contrast = 0.08,
    Saturation = 0.2,
    AtmosphereDensity = 0.176,
    Haze = 0.64,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_126")

AWE.Catalog.Scenes["SCENE_127"] = {
    Key = "SCENE_127",
    Name = "Blue Hour 127",
    Description = "blue hour lighting preset",
    Brightness = 0.7,
    ClockTime = 18.89,
    Exposure = -0.09,
    Ambient = rgb(95, 116, 168),
    OutdoorAmbient = rgb(65, 80, 131),
    FogColor = rgb(59, 74, 125),
    FogStart = 152,
    FogEnd = 1351,
    Diffuse = 0.6,
    Specular = 0.9,
    Tint = rgb(89, 110, 162),
    Contrast = 0.14,
    Saturation = 0.0,
    AtmosphereDensity = 0.26,
    Haze = 0.97,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_127")

AWE.Catalog.Scenes["SCENE_128"] = {
    Key = "SCENE_128",
    Name = "Lavender Fog 128",
    Description = "lavender fog lighting preset",
    Brightness = 1.1,
    ClockTime = 5.46,
    Exposure = 0.055,
    Ambient = rgb(200, 187, 230),
    OutdoorAmbient = rgb(130, 122, 177),
    FogColor = rgb(135, 127, 182),
    FogStart = 163,
    FogEnd = 1399,
    Diffuse = 0.55,
    Specular = 0.85,
    Tint = rgb(197, 184, 227),
    Contrast = -0.04,
    Saturation = 0.175,
    AtmosphereDensity = 0.116,
    Haze = 1.3,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_128")

AWE.Catalog.Scenes["SCENE_129"] = {
    Key = "SCENE_129",
    Name = "Glacier Cave 129",
    Description = "glacier cave lighting preset",
    Brightness = 0.6,
    ClockTime = 0.83,
    Exposure = -0.1,
    Ambient = rgb(101, 165, 186),
    OutdoorAmbient = rgb(74, 119, 152),
    FogColor = rgb(64, 109, 142),
    FogStart = 174,
    FogEnd = 1447,
    Diffuse = 0.5,
    Specular = 0.8,
    Tint = rgb(101, 165, 186),
    Contrast = 0.02,
    Saturation = -0.025,
    AtmosphereDensity = 0.2,
    Haze = 1.63,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_129")

AWE.Catalog.Scenes["SCENE_130"] = {
    Key = "SCENE_130",
    Name = "Warm Pearl 130",
    Description = "warm pearl lighting preset",
    Brightness = 1.0,
    ClockTime = 10.2,
    Exposure = 0.055,
    Ambient = rgb(236, 225, 206),
    OutdoorAmbient = rgb(176, 159, 142),
    FogColor = rgb(177, 160, 143),
    FogStart = 185,
    FogEnd = 1495,
    Diffuse = 0.45,
    Specular = 0.75,
    Tint = rgb(239, 228, 209),
    Contrast = 0.08,
    Saturation = 0.15,
    AtmosphereDensity = 0.284,
    Haze = 1.96,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_130")

AWE.Catalog.Scenes["SCENE_131"] = {
    Key = "SCENE_131",
    Name = "Pearl Dawn 131",
    Description = "pearl dawn lighting preset",
    Brightness = 1.2,
    ClockTime = 6.57,
    Exposure = 0.11,
    Ambient = rgb(191, 225, 245),
    OutdoorAmbient = rgb(112, 153, 185),
    FogColor = rgb(123, 164, 196),
    FogStart = 36,
    FogEnd = 1383,
    Diffuse = 0.4,
    Specular = 0.7,
    Tint = rgb(197, 231, 251),
    Contrast = 0.14,
    Saturation = -0.05,
    AtmosphereDensity = 0.14,
    Haze = 0.42,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_131")

AWE.Catalog.Scenes["SCENE_132"] = {
    Key = "SCENE_132",
    Name = "Moonlit Harbor 132",
    Description = "moonlit harbor lighting preset",
    Brightness = -0.1,
    ClockTime = 0.64,
    Exposure = -0.005,
    Ambient = rgb(83, 113, 163),
    OutdoorAmbient = rgb(56, 76, 115),
    FogColor = rgb(52, 72, 111),
    FogStart = 47,
    FogEnd = 1431,
    Diffuse = 0.35,
    Specular = 0.65,
    Tint = rgb(92, 122, 172),
    Contrast = -0.04,
    Saturation = 0.125,
    AtmosphereDensity = 0.224,
    Haze = 0.75,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_132")

AWE.Catalog.Scenes["SCENE_133"] = {
    Key = "SCENE_133",
    Name = "Arctic Morning 133",
    Description = "arctic morning lighting preset",
    Brightness = 1.0,
    ClockTime = 8.61,
    Exposure = -0.045,
    Ambient = rgb(213, 242, 255),
    OutdoorAmbient = rgb(152, 189, 208),
    FogColor = rgb(160, 197, 216),
    FogStart = 58,
    FogEnd = 1479,
    Diffuse = 0.9,
    Specular = 0.6,
    Tint = rgb(204, 233, 246),
    Contrast = 0.02,
    Saturation = -0.075,
    AtmosphereDensity = 0.08,
    Haze = 1.08,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_133")

AWE.Catalog.Scenes["SCENE_134"] = {
    Key = "SCENE_134",
    Name = "Aquamarine Noon 134",
    Description = "aquamarine noon lighting preset",
    Brightness = 1.1,
    ClockTime = 13.38,
    Exposure = -0.03,
    Ambient = rgb(140, 213, 222),
    OutdoorAmbient = rgb(116, 181, 204),
    FogColor = rgb(109, 174, 197),
    FogStart = 69,
    FogEnd = 1527,
    Diffuse = 0.85,
    Specular = 0.55,
    Tint = rgb(134, 207, 216),
    Contrast = 0.08,
    Saturation = 0.1,
    AtmosphereDensity = 0.164,
    Haze = 1.41,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_134")

AWE.Catalog.Scenes["SCENE_135"] = {
    Key = "SCENE_135",
    Name = "Silver Sunset 135",
    Description = "silver sunset lighting preset",
    Brightness = 1.2,
    ClockTime = 17.12,
    Exposure = 0.015,
    Ambient = rgb(239, 193, 181),
    OutdoorAmbient = rgb(160, 125, 149),
    FogColor = rgb(163, 128, 152),
    FogStart = 80,
    FogEnd = 1575,
    Diffuse = 0.8,
    Specular = 0.5,
    Tint = rgb(236, 190, 178),
    Contrast = 0.14,
    Saturation = -0.1,
    AtmosphereDensity = 0.248,
    Haze = 1.74,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_135")

AWE.Catalog.Scenes["SCENE_136"] = {
    Key = "SCENE_136",
    Name = "Cloud Cathedral 136",
    Description = "cloud cathedral lighting preset",
    Brightness = 1.0,
    ClockTime = 13.69,
    Exposure = 0.06,
    Ambient = rgb(199, 211, 231),
    OutdoorAmbient = rgb(167, 193, 233),
    FogColor = rgb(155, 181, 221),
    FogStart = 91,
    FogEnd = 1623,
    Diffuse = 0.75,
    Specular = 0.45,
    Tint = rgb(199, 211, 231),
    Contrast = -0.04,
    Saturation = 0.075,
    AtmosphereDensity = 0.104,
    Haze = 0.2,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_136")

AWE.Catalog.Scenes["SCENE_137"] = {
    Key = "SCENE_137",
    Name = "Blue Hour 137",
    Description = "blue hour lighting preset",
    Brightness = 0.7,
    ClockTime = 19.06,
    Exposure = -0.015,
    Ambient = rgb(101, 122, 174),
    OutdoorAmbient = rgb(62, 77, 128),
    FogColor = rgb(61, 76, 127),
    FogStart = 102,
    FogEnd = 1671,
    Diffuse = 0.7,
    Specular = 0.4,
    Tint = rgb(104, 125, 177),
    Contrast = 0.02,
    Saturation = 0.25,
    AtmosphereDensity = 0.188,
    Haze = 0.53,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_137")

AWE.Catalog.Scenes["SCENE_138"] = {
    Key = "SCENE_138",
    Name = "Lavender Fog 138",
    Description = "lavender fog lighting preset",
    Brightness = 1.1,
    ClockTime = 5.63,
    Exposure = 0.13,
    Ambient = rgb(206, 193, 236),
    OutdoorAmbient = rgb(127, 119, 174),
    FogColor = rgb(137, 129, 184),
    FogStart = 113,
    FogEnd = 1719,
    Diffuse = 0.65,
    Specular = 0.35,
    Tint = rgb(212, 199, 242),
    Contrast = 0.08,
    Saturation = 0.05,
    AtmosphereDensity = 0.272,
    Haze = 0.86,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_138")

AWE.Catalog.Scenes["SCENE_139"] = {
    Key = "SCENE_139",
    Name = "Glacier Cave 139",
    Description = "glacier cave lighting preset",
    Brightness = 0.6,
    ClockTime = 1.0,
    Exposure = -0.025,
    Ambient = rgb(107, 171, 192),
    OutdoorAmbient = rgb(71, 116, 149),
    FogColor = rgb(66, 111, 144),
    FogStart = 124,
    FogEnd = 1767,
    Diffuse = 0.6,
    Specular = 0.3,
    Tint = rgb(116, 180, 201),
    Contrast = 0.14,
    Saturation = 0.225,
    AtmosphereDensity = 0.128,
    Haze = 1.19,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_139")

AWE.Catalog.Scenes["SCENE_140"] = {
    Key = "SCENE_140",
    Name = "Warm Pearl 140",
    Description = "warm pearl lighting preset",
    Brightness = 1.0,
    ClockTime = 10.37,
    Exposure = -0.045,
    Ambient = rgb(242, 231, 212),
    OutdoorAmbient = rgb(173, 156, 139),
    FogColor = rgb(179, 162, 145),
    FogStart = 135,
    FogEnd = 1815,
    Diffuse = 0.55,
    Specular = 0.25,
    Tint = rgb(233, 222, 203),
    Contrast = -0.04,
    Saturation = 0.025,
    AtmosphereDensity = 0.212,
    Haze = 1.52,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_140")

AWE.Catalog.Scenes["SCENE_141"] = {
    Key = "SCENE_141",
    Name = "Pearl Dawn 141",
    Description = "pearl dawn lighting preset",
    Brightness = 1.2,
    ClockTime = 6.74,
    Exposure = 0.01,
    Ambient = rgb(166, 200, 220),
    OutdoorAmbient = rgb(124, 165, 197),
    FogColor = rgb(115, 156, 188),
    FogStart = 146,
    FogEnd = 1863,
    Diffuse = 0.5,
    Specular = 0.9,
    Tint = rgb(160, 194, 214),
    Contrast = 0.02,
    Saturation = 0.2,
    AtmosphereDensity = 0.296,
    Haze = 1.85,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_141")

AWE.Catalog.Scenes["SCENE_142"] = {
    Key = "SCENE_142",
    Name = "Moonlit Harbor 142",
    Description = "moonlit harbor lighting preset",
    Brightness = -0.1,
    ClockTime = 0.81,
    Exposure = -0.105,
    Ambient = rgb(89, 119, 169),
    OutdoorAmbient = rgb(53, 73, 112),
    FogColor = rgb(54, 74, 113),
    FogStart = 157,
    FogEnd = 1911,
    Diffuse = 0.45,
    Specular = 0.85,
    Tint = rgb(86, 116, 166),
    Contrast = 0.08,
    Saturation = 0.0,
    AtmosphereDensity = 0.152,
    Haze = 0.31,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_142")

AWE.Catalog.Scenes["SCENE_143"] = {
    Key = "SCENE_143",
    Name = "Arctic Morning 143",
    Description = "arctic morning lighting preset",
    Brightness = 1.0,
    ClockTime = 8.78,
    Exposure = 0.03,
    Ambient = rgb(219, 248, 255),
    OutdoorAmbient = rgb(149, 186, 205),
    FogColor = rgb(162, 199, 218),
    FogStart = 168,
    FogEnd = 1959,
    Diffuse = 0.4,
    Specular = 0.8,
    Tint = rgb(219, 248, 255),
    Contrast = 0.14,
    Saturation = 0.175,
    AtmosphereDensity = 0.236,
    Haze = 0.64,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_143")

AWE.Catalog.Scenes["SCENE_144"] = {
    Key = "SCENE_144",
    Name = "Aquamarine Noon 144",
    Description = "aquamarine noon lighting preset",
    Brightness = 1.1,
    ClockTime = 12.02,
    Exposure = 0.045,
    Ambient = rgb(146, 219, 228),
    OutdoorAmbient = rgb(113, 178, 201),
    FogColor = rgb(111, 176, 199),
    FogStart = 179,
    FogEnd = 2007,
    Diffuse = 0.35,
    Specular = 0.75,
    Tint = rgb(149, 222, 231),
    Contrast = -0.04,
    Saturation = -0.025,
    AtmosphereDensity = 0.092,
    Haze = 0.97,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_144")

AWE.Catalog.Scenes["SCENE_145"] = {
    Key = "SCENE_145",
    Name = "Silver Sunset 145",
    Description = "silver sunset lighting preset",
    Brightness = 1.2,
    ClockTime = 17.29,
    Exposure = 0.09,
    Ambient = rgb(245, 199, 187),
    OutdoorAmbient = rgb(157, 122, 146),
    FogColor = rgb(165, 130, 154),
    FogStart = 190,
    FogEnd = 2055,
    Diffuse = 0.9,
    Specular = 0.7,
    Tint = rgb(251, 205, 193),
    Contrast = 0.02,
    Saturation = 0.15,
    AtmosphereDensity = 0.176,
    Haze = 1.3,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_145")

AWE.Catalog.Scenes["SCENE_146"] = {
    Key = "SCENE_146",
    Name = "Cloud Cathedral 146",
    Description = "cloud cathedral lighting preset",
    Brightness = 1.0,
    ClockTime = 13.86,
    Exposure = 0.135,
    Ambient = rgb(205, 217, 237),
    OutdoorAmbient = rgb(164, 190, 230),
    FogColor = rgb(157, 183, 223),
    FogStart = 41,
    FogEnd = 1943,
    Diffuse = 0.85,
    Specular = 0.65,
    Tint = rgb(214, 226, 246),
    Contrast = 0.08,
    Saturation = -0.05,
    AtmosphereDensity = 0.26,
    Haze = 1.63,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_146")

AWE.Catalog.Scenes["SCENE_147"] = {
    Key = "SCENE_147",
    Name = "Blue Hour 147",
    Description = "blue hour lighting preset",
    Brightness = 0.7,
    ClockTime = 19.23,
    Exposure = -0.115,
    Ambient = rgb(107, 128, 180),
    OutdoorAmbient = rgb(59, 74, 125),
    FogColor = rgb(63, 78, 129),
    FogStart = 52,
    FogEnd = 1991,
    Diffuse = 0.8,
    Specular = 0.6,
    Tint = rgb(98, 119, 171),
    Contrast = 0.14,
    Saturation = 0.125,
    AtmosphereDensity = 0.116,
    Haze = 1.96,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_147")

AWE.Catalog.Scenes["SCENE_148"] = {
    Key = "SCENE_148",
    Name = "Lavender Fog 148",
    Description = "lavender fog lighting preset",
    Brightness = 1.1,
    ClockTime = 5.8,
    Exposure = 0.03,
    Ambient = rgb(181, 168, 211),
    OutdoorAmbient = rgb(139, 131, 186),
    FogColor = rgb(128, 120, 175),
    FogStart = 63,
    FogEnd = 2039,
    Diffuse = 0.75,
    Specular = 0.55,
    Tint = rgb(175, 162, 205),
    Contrast = -0.04,
    Saturation = -0.075,
    AtmosphereDensity = 0.2,
    Haze = 0.42,
    Glare = 0.0,
    AtmosphereOn = false,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_148")

AWE.Catalog.Scenes["SCENE_149"] = {
    Key = "SCENE_149",
    Name = "Glacier Cave 149",
    Description = "glacier cave lighting preset",
    Brightness = 0.6,
    ClockTime = 1.17,
    Exposure = -0.125,
    Ambient = rgb(113, 177, 198),
    OutdoorAmbient = rgb(68, 113, 146),
    FogColor = rgb(68, 113, 146),
    FogStart = 74,
    FogEnd = 2087,
    Diffuse = 0.7,
    Specular = 0.5,
    Tint = rgb(110, 174, 195),
    Contrast = 0.02,
    Saturation = 0.1,
    AtmosphereDensity = 0.284,
    Haze = 0.75,
    Glare = 0.125,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_149")

AWE.Catalog.Scenes["SCENE_150"] = {
    Key = "SCENE_150",
    Name = "Warm Pearl 150",
    Description = "warm pearl lighting preset",
    Brightness = 1.0,
    ClockTime = 10.54,
    Exposure = 0.03,
    Ambient = rgb(248, 237, 218),
    OutdoorAmbient = rgb(170, 153, 136),
    FogColor = rgb(181, 164, 147),
    FogStart = 85,
    FogEnd = 2135,
    Diffuse = 0.65,
    Specular = 0.45,
    Tint = rgb(248, 237, 218),
    Contrast = 0.08,
    Saturation = -0.1,
    AtmosphereDensity = 0.14,
    Haze = 1.08,
    Glare = 0.0,
    AtmosphereOn = true,
}
table.insert(AWE.Catalog.SceneOrder, "SCENE_150")


-- Theme presets: all color roles are consumed by AWE:ApplyTheme.
AWE.Catalog.ThemeOrder = {}
AWE.Catalog.Themes["THEME_001"] = {
    Key = "THEME_001",
    Name = "White Pearl Default",
    Description = "white pearl default white glass palette",
    Window = rgb(248, 252, 255),
    Panel = rgb(239, 247, 252),
    Card = rgb(255, 255, 255),
    Text = rgb(30, 48, 61),
    Muted = rgb(103, 126, 142),
    Accent = rgb(87, 220, 234),
    Accent2 = rgb(172, 245, 254),
    Border = rgb(198, 230, 238),
    Selected = rgb(223, 249, 252),
    Track = rgb(220, 235, 241),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_001")

AWE.Catalog.Themes["THEME_002"] = {
    Key = "THEME_002",
    Name = "Ice Glass 002",
    Description = "ice glass white glass palette",
    Window = rgb(246, 253, 255),
    Panel = rgb(229, 246, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(25, 55, 70),
    Muted = rgb(95, 132, 147),
    Accent = rgb(69, 211, 239),
    Accent2 = rgb(170, 246, 255),
    Border = rgb(180, 226, 239),
    Selected = rgb(220, 250, 255),
    Track = rgb(211, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_002")

AWE.Catalog.Themes["THEME_003"] = {
    Key = "THEME_003",
    Name = "Silver Pearl 003",
    Description = "silver pearl white glass palette",
    Window = rgb(248, 249, 252),
    Panel = rgb(235, 239, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(45, 51, 64),
    Muted = rgb(112, 121, 140),
    Accent = rgb(137, 180, 208),
    Accent2 = rgb(198, 222, 235),
    Border = rgb(200, 213, 225),
    Selected = rgb(229, 240, 247),
    Track = rgb(222, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_003")

AWE.Catalog.Themes["THEME_004"] = {
    Key = "THEME_004",
    Name = "Aurora Mint 004",
    Description = "aurora mint white glass palette",
    Window = rgb(246, 255, 252),
    Panel = rgb(230, 249, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(27, 60, 53),
    Muted = rgb(97, 131, 123),
    Accent = rgb(73, 213, 183),
    Accent2 = rgb(164, 242, 223),
    Border = rgb(186, 231, 220),
    Selected = rgb(217, 251, 241),
    Track = rgb(215, 235, 228),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_004")

AWE.Catalog.Themes["THEME_005"] = {
    Key = "THEME_005",
    Name = "Rose Opal 005",
    Description = "rose opal white glass palette",
    Window = rgb(255, 249, 253),
    Panel = rgb(250, 236, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(70, 42, 61),
    Muted = rgb(145, 112, 133),
    Accent = rgb(224, 144, 187),
    Accent2 = rgb(248, 203, 227),
    Border = rgb(236, 198, 219),
    Selected = rgb(252, 230, 243),
    Track = rgb(241, 220, 234),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_005")

AWE.Catalog.Themes["THEME_006"] = {
    Key = "THEME_006",
    Name = "Lilac Snow 006",
    Description = "lilac snow white glass palette",
    Window = rgb(250, 248, 255),
    Panel = rgb(239, 234, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(49, 43, 72),
    Muted = rgb(119, 111, 151),
    Accent = rgb(165, 151, 237),
    Accent2 = rgb(216, 208, 255),
    Border = rgb(217, 207, 241),
    Selected = rgb(237, 232, 255),
    Track = rgb(225, 220, 242),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_006")

AWE.Catalog.Themes["THEME_007"] = {
    Key = "THEME_007",
    Name = "Deep Ocean Light 007",
    Description = "deep ocean light white glass palette",
    Window = rgb(241, 250, 255),
    Panel = rgb(222, 239, 248),
    Card = rgb(255, 255, 255),
    Text = rgb(24, 48, 68),
    Muted = rgb(89, 120, 143),
    Accent = rgb(46, 176, 228),
    Accent2 = rgb(158, 231, 255),
    Border = rgb(173, 213, 234),
    Selected = rgb(214, 244, 255),
    Track = rgb(205, 225, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_007")

AWE.Catalog.Themes["THEME_008"] = {
    Key = "THEME_008",
    Name = "Champagne Glow 008",
    Description = "champagne glow white glass palette",
    Window = rgb(255, 252, 245),
    Panel = rgb(247, 241, 226),
    Card = rgb(255, 255, 255),
    Text = rgb(66, 56, 41),
    Muted = rgb(133, 120, 101),
    Accent = rgb(223, 181, 110),
    Accent2 = rgb(252, 221, 167),
    Border = rgb(235, 217, 182),
    Selected = rgb(254, 241, 213),
    Track = rgb(236, 226, 206),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_008")

AWE.Catalog.Themes["THEME_009"] = {
    Key = "THEME_009",
    Name = "Mono Frost 009",
    Description = "mono frost white glass palette",
    Window = rgb(249, 250, 252),
    Panel = rgb(236, 239, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(34, 39, 48),
    Muted = rgb(108, 116, 130),
    Accent = rgb(129, 174, 208),
    Accent2 = rgb(199, 226, 245),
    Border = rgb(205, 215, 228),
    Selected = rgb(229, 240, 250),
    Track = rgb(219, 226, 235),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_009")

AWE.Catalog.Themes["THEME_010"] = {
    Key = "THEME_010",
    Name = "Coral Mist 010",
    Description = "coral mist white glass palette",
    Window = rgb(255, 249, 247),
    Panel = rgb(249, 237, 233),
    Card = rgb(255, 255, 255),
    Text = rgb(71, 46, 44),
    Muted = rgb(145, 110, 107),
    Accent = rgb(233, 141, 127),
    Accent2 = rgb(249, 200, 188),
    Border = rgb(237, 203, 196),
    Selected = rgb(253, 230, 223),
    Track = rgb(243, 223, 217),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_010")

AWE.Catalog.Themes["THEME_011"] = {
    Key = "THEME_011",
    Name = "White Pearl Default 011",
    Description = "white pearl default white glass palette",
    Window = rgb(248, 252, 255),
    Panel = rgb(239, 247, 252),
    Card = rgb(255, 255, 255),
    Text = rgb(30, 48, 61),
    Muted = rgb(103, 126, 142),
    Accent = rgb(89, 222, 236),
    Accent2 = rgb(174, 247, 255),
    Border = rgb(199, 231, 239),
    Selected = rgb(224, 250, 253),
    Track = rgb(220, 235, 241),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_011")

AWE.Catalog.Themes["THEME_012"] = {
    Key = "THEME_012",
    Name = "Ice Glass 012",
    Description = "ice glass white glass palette",
    Window = rgb(246, 253, 255),
    Panel = rgb(229, 246, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(25, 55, 70),
    Muted = rgb(95, 132, 147),
    Accent = rgb(71, 213, 241),
    Accent2 = rgb(172, 248, 255),
    Border = rgb(180, 226, 239),
    Selected = rgb(220, 250, 255),
    Track = rgb(211, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_012")

AWE.Catalog.Themes["THEME_013"] = {
    Key = "THEME_013",
    Name = "Silver Pearl 013",
    Description = "silver pearl white glass palette",
    Window = rgb(248, 249, 252),
    Panel = rgb(235, 239, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(45, 51, 64),
    Muted = rgb(112, 121, 140),
    Accent = rgb(139, 182, 210),
    Accent2 = rgb(200, 224, 237),
    Border = rgb(201, 214, 226),
    Selected = rgb(230, 241, 248),
    Track = rgb(222, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_013")

AWE.Catalog.Themes["THEME_014"] = {
    Key = "THEME_014",
    Name = "Aurora Mint 014",
    Description = "aurora mint white glass palette",
    Window = rgb(246, 255, 252),
    Panel = rgb(230, 249, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(27, 60, 53),
    Muted = rgb(97, 131, 123),
    Accent = rgb(75, 215, 185),
    Accent2 = rgb(166, 244, 225),
    Border = rgb(186, 231, 220),
    Selected = rgb(217, 251, 241),
    Track = rgb(215, 235, 228),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_014")

AWE.Catalog.Themes["THEME_015"] = {
    Key = "THEME_015",
    Name = "Rose Opal 015",
    Description = "rose opal white glass palette",
    Window = rgb(255, 249, 253),
    Panel = rgb(250, 236, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(70, 42, 61),
    Muted = rgb(145, 112, 133),
    Accent = rgb(226, 146, 189),
    Accent2 = rgb(250, 205, 229),
    Border = rgb(237, 199, 220),
    Selected = rgb(253, 231, 244),
    Track = rgb(241, 220, 234),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_015")

AWE.Catalog.Themes["THEME_016"] = {
    Key = "THEME_016",
    Name = "Lilac Snow 016",
    Description = "lilac snow white glass palette",
    Window = rgb(250, 248, 255),
    Panel = rgb(239, 234, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(49, 43, 72),
    Muted = rgb(119, 111, 151),
    Accent = rgb(167, 153, 239),
    Accent2 = rgb(218, 210, 255),
    Border = rgb(217, 207, 241),
    Selected = rgb(237, 232, 255),
    Track = rgb(225, 220, 242),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_016")

AWE.Catalog.Themes["THEME_017"] = {
    Key = "THEME_017",
    Name = "Deep Ocean Light 017",
    Description = "deep ocean light white glass palette",
    Window = rgb(241, 250, 255),
    Panel = rgb(222, 239, 248),
    Card = rgb(255, 255, 255),
    Text = rgb(24, 48, 68),
    Muted = rgb(89, 120, 143),
    Accent = rgb(31, 161, 213),
    Accent2 = rgb(143, 216, 241),
    Border = rgb(168, 208, 229),
    Selected = rgb(209, 239, 250),
    Track = rgb(205, 225, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_017")

AWE.Catalog.Themes["THEME_018"] = {
    Key = "THEME_018",
    Name = "Champagne Glow 018",
    Description = "champagne glow white glass palette",
    Window = rgb(255, 252, 245),
    Panel = rgb(247, 241, 226),
    Card = rgb(255, 255, 255),
    Text = rgb(66, 56, 41),
    Muted = rgb(133, 120, 101),
    Accent = rgb(225, 183, 112),
    Accent2 = rgb(254, 223, 169),
    Border = rgb(235, 217, 182),
    Selected = rgb(254, 241, 213),
    Track = rgb(236, 226, 206),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_018")

AWE.Catalog.Themes["THEME_019"] = {
    Key = "THEME_019",
    Name = "Mono Frost 019",
    Description = "mono frost white glass palette",
    Window = rgb(249, 250, 252),
    Panel = rgb(236, 239, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(34, 39, 48),
    Muted = rgb(108, 116, 130),
    Accent = rgb(131, 176, 210),
    Accent2 = rgb(201, 228, 247),
    Border = rgb(206, 216, 229),
    Selected = rgb(230, 241, 251),
    Track = rgb(219, 226, 235),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_019")

AWE.Catalog.Themes["THEME_020"] = {
    Key = "THEME_020",
    Name = "Coral Mist 020",
    Description = "coral mist white glass palette",
    Window = rgb(255, 249, 247),
    Panel = rgb(249, 237, 233),
    Card = rgb(255, 255, 255),
    Text = rgb(71, 46, 44),
    Muted = rgb(145, 110, 107),
    Accent = rgb(235, 143, 129),
    Accent2 = rgb(251, 202, 190),
    Border = rgb(237, 203, 196),
    Selected = rgb(253, 230, 223),
    Track = rgb(243, 223, 217),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_020")

AWE.Catalog.Themes["THEME_021"] = {
    Key = "THEME_021",
    Name = "White Pearl Default 021",
    Description = "white pearl default white glass palette",
    Window = rgb(248, 252, 255),
    Panel = rgb(239, 247, 252),
    Card = rgb(255, 255, 255),
    Text = rgb(30, 48, 61),
    Muted = rgb(103, 126, 142),
    Accent = rgb(91, 224, 238),
    Accent2 = rgb(176, 249, 255),
    Border = rgb(200, 232, 240),
    Selected = rgb(225, 251, 254),
    Track = rgb(220, 235, 241),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_021")

AWE.Catalog.Themes["THEME_022"] = {
    Key = "THEME_022",
    Name = "Ice Glass 022",
    Description = "ice glass white glass palette",
    Window = rgb(246, 253, 255),
    Panel = rgb(229, 246, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(25, 55, 70),
    Muted = rgb(95, 132, 147),
    Accent = rgb(56, 198, 226),
    Accent2 = rgb(157, 233, 248),
    Border = rgb(175, 221, 234),
    Selected = rgb(215, 245, 251),
    Track = rgb(211, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_022")

AWE.Catalog.Themes["THEME_023"] = {
    Key = "THEME_023",
    Name = "Silver Pearl 023",
    Description = "silver pearl white glass palette",
    Window = rgb(248, 249, 252),
    Panel = rgb(235, 239, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(45, 51, 64),
    Muted = rgb(112, 121, 140),
    Accent = rgb(141, 184, 212),
    Accent2 = rgb(202, 226, 239),
    Border = rgb(202, 215, 227),
    Selected = rgb(231, 242, 249),
    Track = rgb(222, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_023")

AWE.Catalog.Themes["THEME_024"] = {
    Key = "THEME_024",
    Name = "Aurora Mint 024",
    Description = "aurora mint white glass palette",
    Window = rgb(246, 255, 252),
    Panel = rgb(230, 249, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(27, 60, 53),
    Muted = rgb(97, 131, 123),
    Accent = rgb(77, 217, 187),
    Accent2 = rgb(168, 246, 227),
    Border = rgb(187, 232, 221),
    Selected = rgb(218, 252, 242),
    Track = rgb(215, 235, 228),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_024")

AWE.Catalog.Themes["THEME_025"] = {
    Key = "THEME_025",
    Name = "Rose Opal 025",
    Description = "rose opal white glass palette",
    Window = rgb(255, 249, 253),
    Panel = rgb(250, 236, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(70, 42, 61),
    Muted = rgb(145, 112, 133),
    Accent = rgb(228, 148, 191),
    Accent2 = rgb(252, 207, 231),
    Border = rgb(238, 200, 221),
    Selected = rgb(254, 232, 245),
    Track = rgb(241, 220, 234),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_025")

AWE.Catalog.Themes["THEME_026"] = {
    Key = "THEME_026",
    Name = "Lilac Snow 026",
    Description = "lilac snow white glass palette",
    Window = rgb(250, 248, 255),
    Panel = rgb(239, 234, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(49, 43, 72),
    Muted = rgb(119, 111, 151),
    Accent = rgb(169, 155, 241),
    Accent2 = rgb(220, 212, 255),
    Border = rgb(218, 208, 242),
    Selected = rgb(238, 233, 255),
    Track = rgb(225, 220, 242),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_026")

AWE.Catalog.Themes["THEME_027"] = {
    Key = "THEME_027",
    Name = "Deep Ocean Light 027",
    Description = "deep ocean light white glass palette",
    Window = rgb(241, 250, 255),
    Panel = rgb(222, 239, 248),
    Card = rgb(255, 255, 255),
    Text = rgb(24, 48, 68),
    Muted = rgb(89, 120, 143),
    Accent = rgb(33, 163, 215),
    Accent2 = rgb(145, 218, 243),
    Border = rgb(169, 209, 230),
    Selected = rgb(210, 240, 251),
    Track = rgb(205, 225, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_027")

AWE.Catalog.Themes["THEME_028"] = {
    Key = "THEME_028",
    Name = "Champagne Glow 028",
    Description = "champagne glow white glass palette",
    Window = rgb(255, 252, 245),
    Panel = rgb(247, 241, 226),
    Card = rgb(255, 255, 255),
    Text = rgb(66, 56, 41),
    Muted = rgb(133, 120, 101),
    Accent = rgb(227, 185, 114),
    Accent2 = rgb(255, 225, 171),
    Border = rgb(236, 218, 183),
    Selected = rgb(255, 242, 214),
    Track = rgb(236, 226, 206),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_028")

AWE.Catalog.Themes["THEME_029"] = {
    Key = "THEME_029",
    Name = "Mono Frost 029",
    Description = "mono frost white glass palette",
    Window = rgb(249, 250, 252),
    Panel = rgb(236, 239, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(34, 39, 48),
    Muted = rgb(108, 116, 130),
    Accent = rgb(133, 178, 212),
    Accent2 = rgb(203, 230, 249),
    Border = rgb(206, 216, 229),
    Selected = rgb(230, 241, 251),
    Track = rgb(219, 226, 235),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_029")

AWE.Catalog.Themes["THEME_030"] = {
    Key = "THEME_030",
    Name = "Coral Mist 030",
    Description = "coral mist white glass palette",
    Window = rgb(255, 249, 247),
    Panel = rgb(249, 237, 233),
    Card = rgb(255, 255, 255),
    Text = rgb(71, 46, 44),
    Muted = rgb(145, 110, 107),
    Accent = rgb(237, 145, 131),
    Accent2 = rgb(253, 204, 192),
    Border = rgb(238, 204, 197),
    Selected = rgb(254, 231, 224),
    Track = rgb(243, 223, 217),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_030")

AWE.Catalog.Themes["THEME_031"] = {
    Key = "THEME_031",
    Name = "White Pearl Default 031",
    Description = "white pearl default white glass palette",
    Window = rgb(248, 252, 255),
    Panel = rgb(239, 247, 252),
    Card = rgb(255, 255, 255),
    Text = rgb(30, 48, 61),
    Muted = rgb(103, 126, 142),
    Accent = rgb(93, 226, 240),
    Accent2 = rgb(178, 251, 255),
    Border = rgb(200, 232, 240),
    Selected = rgb(225, 251, 254),
    Track = rgb(220, 235, 241),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_031")

AWE.Catalog.Themes["THEME_032"] = {
    Key = "THEME_032",
    Name = "Ice Glass 032",
    Description = "ice glass white glass palette",
    Window = rgb(246, 253, 255),
    Panel = rgb(229, 246, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(25, 55, 70),
    Muted = rgb(95, 132, 147),
    Accent = rgb(58, 200, 228),
    Accent2 = rgb(159, 235, 250),
    Border = rgb(176, 222, 235),
    Selected = rgb(216, 246, 252),
    Track = rgb(211, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_032")

AWE.Catalog.Themes["THEME_033"] = {
    Key = "THEME_033",
    Name = "Silver Pearl 033",
    Description = "silver pearl white glass palette",
    Window = rgb(248, 249, 252),
    Panel = rgb(235, 239, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(45, 51, 64),
    Muted = rgb(112, 121, 140),
    Accent = rgb(143, 186, 214),
    Accent2 = rgb(204, 228, 241),
    Border = rgb(202, 215, 227),
    Selected = rgb(231, 242, 249),
    Track = rgb(222, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_033")

AWE.Catalog.Themes["THEME_034"] = {
    Key = "THEME_034",
    Name = "Aurora Mint 034",
    Description = "aurora mint white glass palette",
    Window = rgb(246, 255, 252),
    Panel = rgb(230, 249, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(27, 60, 53),
    Muted = rgb(97, 131, 123),
    Accent = rgb(62, 202, 172),
    Accent2 = rgb(153, 231, 212),
    Border = rgb(182, 227, 216),
    Selected = rgb(213, 247, 237),
    Track = rgb(215, 235, 228),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_034")

AWE.Catalog.Themes["THEME_035"] = {
    Key = "THEME_035",
    Name = "Rose Opal 035",
    Description = "rose opal white glass palette",
    Window = rgb(255, 249, 253),
    Panel = rgb(250, 236, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(70, 42, 61),
    Muted = rgb(145, 112, 133),
    Accent = rgb(230, 150, 193),
    Accent2 = rgb(254, 209, 233),
    Border = rgb(238, 200, 221),
    Selected = rgb(254, 232, 245),
    Track = rgb(241, 220, 234),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_035")

AWE.Catalog.Themes["THEME_036"] = {
    Key = "THEME_036",
    Name = "Lilac Snow 036",
    Description = "lilac snow white glass palette",
    Window = rgb(250, 248, 255),
    Panel = rgb(239, 234, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(49, 43, 72),
    Muted = rgb(119, 111, 151),
    Accent = rgb(171, 157, 243),
    Accent2 = rgb(222, 214, 255),
    Border = rgb(219, 209, 243),
    Selected = rgb(239, 234, 255),
    Track = rgb(225, 220, 242),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_036")

AWE.Catalog.Themes["THEME_037"] = {
    Key = "THEME_037",
    Name = "Deep Ocean Light 037",
    Description = "deep ocean light white glass palette",
    Window = rgb(241, 250, 255),
    Panel = rgb(222, 239, 248),
    Card = rgb(255, 255, 255),
    Text = rgb(24, 48, 68),
    Muted = rgb(89, 120, 143),
    Accent = rgb(35, 165, 217),
    Accent2 = rgb(147, 220, 245),
    Border = rgb(169, 209, 230),
    Selected = rgb(210, 240, 251),
    Track = rgb(205, 225, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_037")

AWE.Catalog.Themes["THEME_038"] = {
    Key = "THEME_038",
    Name = "Champagne Glow 038",
    Description = "champagne glow white glass palette",
    Window = rgb(255, 252, 245),
    Panel = rgb(247, 241, 226),
    Card = rgb(255, 255, 255),
    Text = rgb(66, 56, 41),
    Muted = rgb(133, 120, 101),
    Accent = rgb(229, 187, 116),
    Accent2 = rgb(255, 227, 173),
    Border = rgb(237, 219, 184),
    Selected = rgb(255, 243, 215),
    Track = rgb(236, 226, 206),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_038")

AWE.Catalog.Themes["THEME_039"] = {
    Key = "THEME_039",
    Name = "Mono Frost 039",
    Description = "mono frost white glass palette",
    Window = rgb(249, 250, 252),
    Panel = rgb(236, 239, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(34, 39, 48),
    Muted = rgb(108, 116, 130),
    Accent = rgb(118, 163, 197),
    Accent2 = rgb(188, 215, 234),
    Border = rgb(201, 211, 224),
    Selected = rgb(225, 236, 246),
    Track = rgb(219, 226, 235),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_039")

AWE.Catalog.Themes["THEME_040"] = {
    Key = "THEME_040",
    Name = "Coral Mist 040",
    Description = "coral mist white glass palette",
    Window = rgb(255, 249, 247),
    Panel = rgb(249, 237, 233),
    Card = rgb(255, 255, 255),
    Text = rgb(71, 46, 44),
    Muted = rgb(145, 110, 107),
    Accent = rgb(239, 147, 133),
    Accent2 = rgb(255, 206, 194),
    Border = rgb(239, 205, 198),
    Selected = rgb(255, 232, 225),
    Track = rgb(243, 223, 217),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_040")

AWE.Catalog.Themes["THEME_041"] = {
    Key = "THEME_041",
    Name = "White Pearl Default 041",
    Description = "white pearl default white glass palette",
    Window = rgb(248, 252, 255),
    Panel = rgb(239, 247, 252),
    Card = rgb(255, 255, 255),
    Text = rgb(30, 48, 61),
    Muted = rgb(103, 126, 142),
    Accent = rgb(95, 228, 242),
    Accent2 = rgb(180, 253, 255),
    Border = rgb(201, 233, 241),
    Selected = rgb(226, 252, 255),
    Track = rgb(220, 235, 241),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_041")

AWE.Catalog.Themes["THEME_042"] = {
    Key = "THEME_042",
    Name = "Ice Glass 042",
    Description = "ice glass white glass palette",
    Window = rgb(246, 253, 255),
    Panel = rgb(229, 246, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(25, 55, 70),
    Muted = rgb(95, 132, 147),
    Accent = rgb(60, 202, 230),
    Accent2 = rgb(161, 237, 252),
    Border = rgb(177, 223, 236),
    Selected = rgb(217, 247, 253),
    Track = rgb(211, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_042")

AWE.Catalog.Themes["THEME_043"] = {
    Key = "THEME_043",
    Name = "Silver Pearl 043",
    Description = "silver pearl white glass palette",
    Window = rgb(248, 249, 252),
    Panel = rgb(235, 239, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(45, 51, 64),
    Muted = rgb(112, 121, 140),
    Accent = rgb(145, 188, 216),
    Accent2 = rgb(206, 230, 243),
    Border = rgb(203, 216, 228),
    Selected = rgb(232, 243, 250),
    Track = rgb(222, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_043")

AWE.Catalog.Themes["THEME_044"] = {
    Key = "THEME_044",
    Name = "Aurora Mint 044",
    Description = "aurora mint white glass palette",
    Window = rgb(246, 255, 252),
    Panel = rgb(230, 249, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(27, 60, 53),
    Muted = rgb(97, 131, 123),
    Accent = rgb(64, 204, 174),
    Accent2 = rgb(155, 233, 214),
    Border = rgb(183, 228, 217),
    Selected = rgb(214, 248, 238),
    Track = rgb(215, 235, 228),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_044")

AWE.Catalog.Themes["THEME_045"] = {
    Key = "THEME_045",
    Name = "Rose Opal 045",
    Description = "rose opal white glass palette",
    Window = rgb(255, 249, 253),
    Panel = rgb(250, 236, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(70, 42, 61),
    Muted = rgb(145, 112, 133),
    Accent = rgb(232, 152, 195),
    Accent2 = rgb(255, 211, 235),
    Border = rgb(239, 201, 222),
    Selected = rgb(255, 233, 246),
    Track = rgb(241, 220, 234),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_045")

AWE.Catalog.Themes["THEME_046"] = {
    Key = "THEME_046",
    Name = "Lilac Snow 046",
    Description = "lilac snow white glass palette",
    Window = rgb(250, 248, 255),
    Panel = rgb(239, 234, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(49, 43, 72),
    Muted = rgb(119, 111, 151),
    Accent = rgb(173, 159, 245),
    Accent2 = rgb(224, 216, 255),
    Border = rgb(219, 209, 243),
    Selected = rgb(239, 234, 255),
    Track = rgb(225, 220, 242),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_046")

AWE.Catalog.Themes["THEME_047"] = {
    Key = "THEME_047",
    Name = "Deep Ocean Light 047",
    Description = "deep ocean light white glass palette",
    Window = rgb(241, 250, 255),
    Panel = rgb(222, 239, 248),
    Card = rgb(255, 255, 255),
    Text = rgb(24, 48, 68),
    Muted = rgb(89, 120, 143),
    Accent = rgb(37, 167, 219),
    Accent2 = rgb(149, 222, 247),
    Border = rgb(170, 210, 231),
    Selected = rgb(211, 241, 252),
    Track = rgb(205, 225, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_047")

AWE.Catalog.Themes["THEME_048"] = {
    Key = "THEME_048",
    Name = "Champagne Glow 048",
    Description = "champagne glow white glass palette",
    Window = rgb(255, 252, 245),
    Panel = rgb(247, 241, 226),
    Card = rgb(255, 255, 255),
    Text = rgb(66, 56, 41),
    Muted = rgb(133, 120, 101),
    Accent = rgb(231, 189, 118),
    Accent2 = rgb(255, 229, 175),
    Border = rgb(237, 219, 184),
    Selected = rgb(255, 243, 215),
    Track = rgb(236, 226, 206),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_048")

AWE.Catalog.Themes["THEME_049"] = {
    Key = "THEME_049",
    Name = "Mono Frost 049",
    Description = "mono frost white glass palette",
    Window = rgb(249, 250, 252),
    Panel = rgb(236, 239, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(34, 39, 48),
    Muted = rgb(108, 116, 130),
    Accent = rgb(120, 165, 199),
    Accent2 = rgb(190, 217, 236),
    Border = rgb(202, 212, 225),
    Selected = rgb(226, 237, 247),
    Track = rgb(219, 226, 235),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_049")

AWE.Catalog.Themes["THEME_050"] = {
    Key = "THEME_050",
    Name = "Coral Mist 050",
    Description = "coral mist white glass palette",
    Window = rgb(255, 249, 247),
    Panel = rgb(249, 237, 233),
    Card = rgb(255, 255, 255),
    Text = rgb(71, 46, 44),
    Muted = rgb(145, 110, 107),
    Accent = rgb(241, 149, 135),
    Accent2 = rgb(255, 208, 196),
    Border = rgb(239, 205, 198),
    Selected = rgb(255, 232, 225),
    Track = rgb(243, 223, 217),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_050")

AWE.Catalog.Themes["THEME_051"] = {
    Key = "THEME_051",
    Name = "White Pearl Default 051",
    Description = "white pearl default white glass palette",
    Window = rgb(248, 252, 255),
    Panel = rgb(239, 247, 252),
    Card = rgb(255, 255, 255),
    Text = rgb(30, 48, 61),
    Muted = rgb(103, 126, 142),
    Accent = rgb(80, 213, 227),
    Accent2 = rgb(165, 238, 247),
    Border = rgb(196, 228, 236),
    Selected = rgb(221, 247, 250),
    Track = rgb(220, 235, 241),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_051")

AWE.Catalog.Themes["THEME_052"] = {
    Key = "THEME_052",
    Name = "Ice Glass 052",
    Description = "ice glass white glass palette",
    Window = rgb(246, 253, 255),
    Panel = rgb(229, 246, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(25, 55, 70),
    Muted = rgb(95, 132, 147),
    Accent = rgb(62, 204, 232),
    Accent2 = rgb(163, 239, 254),
    Border = rgb(177, 223, 236),
    Selected = rgb(217, 247, 253),
    Track = rgb(211, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_052")

AWE.Catalog.Themes["THEME_053"] = {
    Key = "THEME_053",
    Name = "Silver Pearl 053",
    Description = "silver pearl white glass palette",
    Window = rgb(248, 249, 252),
    Panel = rgb(235, 239, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(45, 51, 64),
    Muted = rgb(112, 121, 140),
    Accent = rgb(147, 190, 218),
    Accent2 = rgb(208, 232, 245),
    Border = rgb(204, 217, 229),
    Selected = rgb(233, 244, 251),
    Track = rgb(222, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_053")

AWE.Catalog.Themes["THEME_054"] = {
    Key = "THEME_054",
    Name = "Aurora Mint 054",
    Description = "aurora mint white glass palette",
    Window = rgb(246, 255, 252),
    Panel = rgb(230, 249, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(27, 60, 53),
    Muted = rgb(97, 131, 123),
    Accent = rgb(66, 206, 176),
    Accent2 = rgb(157, 235, 216),
    Border = rgb(183, 228, 217),
    Selected = rgb(214, 248, 238),
    Track = rgb(215, 235, 228),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_054")

AWE.Catalog.Themes["THEME_055"] = {
    Key = "THEME_055",
    Name = "Rose Opal 055",
    Description = "rose opal white glass palette",
    Window = rgb(255, 249, 253),
    Panel = rgb(250, 236, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(70, 42, 61),
    Muted = rgb(145, 112, 133),
    Accent = rgb(234, 154, 197),
    Accent2 = rgb(255, 213, 237),
    Border = rgb(240, 202, 223),
    Selected = rgb(255, 234, 247),
    Track = rgb(241, 220, 234),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_055")

AWE.Catalog.Themes["THEME_056"] = {
    Key = "THEME_056",
    Name = "Lilac Snow 056",
    Description = "lilac snow white glass palette",
    Window = rgb(250, 248, 255),
    Panel = rgb(239, 234, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(49, 43, 72),
    Muted = rgb(119, 111, 151),
    Accent = rgb(158, 144, 230),
    Accent2 = rgb(209, 201, 248),
    Border = rgb(214, 204, 238),
    Selected = rgb(234, 229, 252),
    Track = rgb(225, 220, 242),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_056")

AWE.Catalog.Themes["THEME_057"] = {
    Key = "THEME_057",
    Name = "Deep Ocean Light 057",
    Description = "deep ocean light white glass palette",
    Window = rgb(241, 250, 255),
    Panel = rgb(222, 239, 248),
    Card = rgb(255, 255, 255),
    Text = rgb(24, 48, 68),
    Muted = rgb(89, 120, 143),
    Accent = rgb(39, 169, 221),
    Accent2 = rgb(151, 224, 249),
    Border = rgb(171, 211, 232),
    Selected = rgb(212, 242, 253),
    Track = rgb(205, 225, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_057")

AWE.Catalog.Themes["THEME_058"] = {
    Key = "THEME_058",
    Name = "Champagne Glow 058",
    Description = "champagne glow white glass palette",
    Window = rgb(255, 252, 245),
    Panel = rgb(247, 241, 226),
    Card = rgb(255, 255, 255),
    Text = rgb(66, 56, 41),
    Muted = rgb(133, 120, 101),
    Accent = rgb(233, 191, 120),
    Accent2 = rgb(255, 231, 177),
    Border = rgb(238, 220, 185),
    Selected = rgb(255, 244, 216),
    Track = rgb(236, 226, 206),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_058")

AWE.Catalog.Themes["THEME_059"] = {
    Key = "THEME_059",
    Name = "Mono Frost 059",
    Description = "mono frost white glass palette",
    Window = rgb(249, 250, 252),
    Panel = rgb(236, 239, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(34, 39, 48),
    Muted = rgb(108, 116, 130),
    Accent = rgb(122, 167, 201),
    Accent2 = rgb(192, 219, 238),
    Border = rgb(203, 213, 226),
    Selected = rgb(227, 238, 248),
    Track = rgb(219, 226, 235),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_059")

AWE.Catalog.Themes["THEME_060"] = {
    Key = "THEME_060",
    Name = "Coral Mist 060",
    Description = "coral mist white glass palette",
    Window = rgb(255, 249, 247),
    Panel = rgb(249, 237, 233),
    Card = rgb(255, 255, 255),
    Text = rgb(71, 46, 44),
    Muted = rgb(145, 110, 107),
    Accent = rgb(243, 151, 137),
    Accent2 = rgb(255, 210, 198),
    Border = rgb(240, 206, 199),
    Selected = rgb(255, 233, 226),
    Track = rgb(243, 223, 217),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_060")

AWE.Catalog.Themes["THEME_061"] = {
    Key = "THEME_061",
    Name = "White Pearl Default 061",
    Description = "white pearl default white glass palette",
    Window = rgb(248, 252, 255),
    Panel = rgb(239, 247, 252),
    Card = rgb(255, 255, 255),
    Text = rgb(30, 48, 61),
    Muted = rgb(103, 126, 142),
    Accent = rgb(82, 215, 229),
    Accent2 = rgb(167, 240, 249),
    Border = rgb(197, 229, 237),
    Selected = rgb(222, 248, 251),
    Track = rgb(220, 235, 241),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_061")

AWE.Catalog.Themes["THEME_062"] = {
    Key = "THEME_062",
    Name = "Ice Glass 062",
    Description = "ice glass white glass palette",
    Window = rgb(246, 253, 255),
    Panel = rgb(229, 246, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(25, 55, 70),
    Muted = rgb(95, 132, 147),
    Accent = rgb(64, 206, 234),
    Accent2 = rgb(165, 241, 255),
    Border = rgb(178, 224, 237),
    Selected = rgb(218, 248, 254),
    Track = rgb(211, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_062")

AWE.Catalog.Themes["THEME_063"] = {
    Key = "THEME_063",
    Name = "Silver Pearl 063",
    Description = "silver pearl white glass palette",
    Window = rgb(248, 249, 252),
    Panel = rgb(235, 239, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(45, 51, 64),
    Muted = rgb(112, 121, 140),
    Accent = rgb(149, 192, 220),
    Accent2 = rgb(210, 234, 247),
    Border = rgb(204, 217, 229),
    Selected = rgb(233, 244, 251),
    Track = rgb(222, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_063")

AWE.Catalog.Themes["THEME_064"] = {
    Key = "THEME_064",
    Name = "Aurora Mint 064",
    Description = "aurora mint white glass palette",
    Window = rgb(246, 255, 252),
    Panel = rgb(230, 249, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(27, 60, 53),
    Muted = rgb(97, 131, 123),
    Accent = rgb(68, 208, 178),
    Accent2 = rgb(159, 237, 218),
    Border = rgb(184, 229, 218),
    Selected = rgb(215, 249, 239),
    Track = rgb(215, 235, 228),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_064")

AWE.Catalog.Themes["THEME_065"] = {
    Key = "THEME_065",
    Name = "Rose Opal 065",
    Description = "rose opal white glass palette",
    Window = rgb(255, 249, 253),
    Panel = rgb(250, 236, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(70, 42, 61),
    Muted = rgb(145, 112, 133),
    Accent = rgb(236, 156, 199),
    Accent2 = rgb(255, 215, 239),
    Border = rgb(240, 202, 223),
    Selected = rgb(255, 234, 247),
    Track = rgb(241, 220, 234),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_065")

AWE.Catalog.Themes["THEME_066"] = {
    Key = "THEME_066",
    Name = "Lilac Snow 066",
    Description = "lilac snow white glass palette",
    Window = rgb(250, 248, 255),
    Panel = rgb(239, 234, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(49, 43, 72),
    Muted = rgb(119, 111, 151),
    Accent = rgb(160, 146, 232),
    Accent2 = rgb(211, 203, 250),
    Border = rgb(215, 205, 239),
    Selected = rgb(235, 230, 253),
    Track = rgb(225, 220, 242),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_066")

AWE.Catalog.Themes["THEME_067"] = {
    Key = "THEME_067",
    Name = "Deep Ocean Light 067",
    Description = "deep ocean light white glass palette",
    Window = rgb(241, 250, 255),
    Panel = rgb(222, 239, 248),
    Card = rgb(255, 255, 255),
    Text = rgb(24, 48, 68),
    Muted = rgb(89, 120, 143),
    Accent = rgb(41, 171, 223),
    Accent2 = rgb(153, 226, 251),
    Border = rgb(171, 211, 232),
    Selected = rgb(212, 242, 253),
    Track = rgb(205, 225, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_067")

AWE.Catalog.Themes["THEME_068"] = {
    Key = "THEME_068",
    Name = "Champagne Glow 068",
    Description = "champagne glow white glass palette",
    Window = rgb(255, 252, 245),
    Panel = rgb(247, 241, 226),
    Card = rgb(255, 255, 255),
    Text = rgb(66, 56, 41),
    Muted = rgb(133, 120, 101),
    Accent = rgb(218, 176, 105),
    Accent2 = rgb(247, 216, 162),
    Border = rgb(233, 215, 180),
    Selected = rgb(252, 239, 211),
    Track = rgb(236, 226, 206),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_068")

AWE.Catalog.Themes["THEME_069"] = {
    Key = "THEME_069",
    Name = "Mono Frost 069",
    Description = "mono frost white glass palette",
    Window = rgb(249, 250, 252),
    Panel = rgb(236, 239, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(34, 39, 48),
    Muted = rgb(108, 116, 130),
    Accent = rgb(124, 169, 203),
    Accent2 = rgb(194, 221, 240),
    Border = rgb(203, 213, 226),
    Selected = rgb(227, 238, 248),
    Track = rgb(219, 226, 235),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_069")

AWE.Catalog.Themes["THEME_070"] = {
    Key = "THEME_070",
    Name = "Coral Mist 070",
    Description = "coral mist white glass palette",
    Window = rgb(255, 249, 247),
    Panel = rgb(249, 237, 233),
    Card = rgb(255, 255, 255),
    Text = rgb(71, 46, 44),
    Muted = rgb(145, 110, 107),
    Accent = rgb(245, 153, 139),
    Accent2 = rgb(255, 212, 200),
    Border = rgb(241, 207, 200),
    Selected = rgb(255, 234, 227),
    Track = rgb(243, 223, 217),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_070")

AWE.Catalog.Themes["THEME_071"] = {
    Key = "THEME_071",
    Name = "White Pearl Default 071",
    Description = "white pearl default white glass palette",
    Window = rgb(248, 252, 255),
    Panel = rgb(239, 247, 252),
    Card = rgb(255, 255, 255),
    Text = rgb(30, 48, 61),
    Muted = rgb(103, 126, 142),
    Accent = rgb(84, 217, 231),
    Accent2 = rgb(169, 242, 251),
    Border = rgb(197, 229, 237),
    Selected = rgb(222, 248, 251),
    Track = rgb(220, 235, 241),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_071")

AWE.Catalog.Themes["THEME_072"] = {
    Key = "THEME_072",
    Name = "Ice Glass 072",
    Description = "ice glass white glass palette",
    Window = rgb(246, 253, 255),
    Panel = rgb(229, 246, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(25, 55, 70),
    Muted = rgb(95, 132, 147),
    Accent = rgb(66, 208, 236),
    Accent2 = rgb(167, 243, 255),
    Border = rgb(179, 225, 238),
    Selected = rgb(219, 249, 255),
    Track = rgb(211, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_072")

AWE.Catalog.Themes["THEME_073"] = {
    Key = "THEME_073",
    Name = "Silver Pearl 073",
    Description = "silver pearl white glass palette",
    Window = rgb(248, 249, 252),
    Panel = rgb(235, 239, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(45, 51, 64),
    Muted = rgb(112, 121, 140),
    Accent = rgb(134, 177, 205),
    Accent2 = rgb(195, 219, 232),
    Border = rgb(199, 212, 224),
    Selected = rgb(228, 239, 246),
    Track = rgb(222, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_073")

AWE.Catalog.Themes["THEME_074"] = {
    Key = "THEME_074",
    Name = "Aurora Mint 074",
    Description = "aurora mint white glass palette",
    Window = rgb(246, 255, 252),
    Panel = rgb(230, 249, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(27, 60, 53),
    Muted = rgb(97, 131, 123),
    Accent = rgb(70, 210, 180),
    Accent2 = rgb(161, 239, 220),
    Border = rgb(185, 230, 219),
    Selected = rgb(216, 250, 240),
    Track = rgb(215, 235, 228),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_074")

AWE.Catalog.Themes["THEME_075"] = {
    Key = "THEME_075",
    Name = "Rose Opal 075",
    Description = "rose opal white glass palette",
    Window = rgb(255, 249, 253),
    Panel = rgb(250, 236, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(70, 42, 61),
    Muted = rgb(145, 112, 133),
    Accent = rgb(238, 158, 201),
    Accent2 = rgb(255, 217, 241),
    Border = rgb(241, 203, 224),
    Selected = rgb(255, 235, 248),
    Track = rgb(241, 220, 234),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_075")

AWE.Catalog.Themes["THEME_076"] = {
    Key = "THEME_076",
    Name = "Lilac Snow 076",
    Description = "lilac snow white glass palette",
    Window = rgb(250, 248, 255),
    Panel = rgb(239, 234, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(49, 43, 72),
    Muted = rgb(119, 111, 151),
    Accent = rgb(162, 148, 234),
    Accent2 = rgb(213, 205, 252),
    Border = rgb(216, 206, 240),
    Selected = rgb(236, 231, 254),
    Track = rgb(225, 220, 242),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_076")

AWE.Catalog.Themes["THEME_077"] = {
    Key = "THEME_077",
    Name = "Deep Ocean Light 077",
    Description = "deep ocean light white glass palette",
    Window = rgb(241, 250, 255),
    Panel = rgb(222, 239, 248),
    Card = rgb(255, 255, 255),
    Text = rgb(24, 48, 68),
    Muted = rgb(89, 120, 143),
    Accent = rgb(43, 173, 225),
    Accent2 = rgb(155, 228, 253),
    Border = rgb(172, 212, 233),
    Selected = rgb(213, 243, 254),
    Track = rgb(205, 225, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_077")

AWE.Catalog.Themes["THEME_078"] = {
    Key = "THEME_078",
    Name = "Champagne Glow 078",
    Description = "champagne glow white glass palette",
    Window = rgb(255, 252, 245),
    Panel = rgb(247, 241, 226),
    Card = rgb(255, 255, 255),
    Text = rgb(66, 56, 41),
    Muted = rgb(133, 120, 101),
    Accent = rgb(220, 178, 107),
    Accent2 = rgb(249, 218, 164),
    Border = rgb(234, 216, 181),
    Selected = rgb(253, 240, 212),
    Track = rgb(236, 226, 206),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_078")

AWE.Catalog.Themes["THEME_079"] = {
    Key = "THEME_079",
    Name = "Mono Frost 079",
    Description = "mono frost white glass palette",
    Window = rgb(249, 250, 252),
    Panel = rgb(236, 239, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(34, 39, 48),
    Muted = rgb(108, 116, 130),
    Accent = rgb(126, 171, 205),
    Accent2 = rgb(196, 223, 242),
    Border = rgb(204, 214, 227),
    Selected = rgb(228, 239, 249),
    Track = rgb(219, 226, 235),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_079")

AWE.Catalog.Themes["THEME_080"] = {
    Key = "THEME_080",
    Name = "Coral Mist 080",
    Description = "coral mist white glass palette",
    Window = rgb(255, 249, 247),
    Panel = rgb(249, 237, 233),
    Card = rgb(255, 255, 255),
    Text = rgb(71, 46, 44),
    Muted = rgb(145, 110, 107),
    Accent = rgb(247, 155, 141),
    Accent2 = rgb(255, 214, 202),
    Border = rgb(241, 207, 200),
    Selected = rgb(255, 234, 227),
    Track = rgb(243, 223, 217),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_080")

AWE.Catalog.Themes["THEME_081"] = {
    Key = "THEME_081",
    Name = "White Pearl Default 081",
    Description = "white pearl default white glass palette",
    Window = rgb(248, 252, 255),
    Panel = rgb(239, 247, 252),
    Card = rgb(255, 255, 255),
    Text = rgb(30, 48, 61),
    Muted = rgb(103, 126, 142),
    Accent = rgb(86, 219, 233),
    Accent2 = rgb(171, 244, 253),
    Border = rgb(198, 230, 238),
    Selected = rgb(223, 249, 252),
    Track = rgb(220, 235, 241),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_081")

AWE.Catalog.Themes["THEME_082"] = {
    Key = "THEME_082",
    Name = "Ice Glass 082",
    Description = "ice glass white glass palette",
    Window = rgb(246, 253, 255),
    Panel = rgb(229, 246, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(25, 55, 70),
    Muted = rgb(95, 132, 147),
    Accent = rgb(68, 210, 238),
    Accent2 = rgb(169, 245, 255),
    Border = rgb(179, 225, 238),
    Selected = rgb(219, 249, 255),
    Track = rgb(211, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_082")

AWE.Catalog.Themes["THEME_083"] = {
    Key = "THEME_083",
    Name = "Silver Pearl 083",
    Description = "silver pearl white glass palette",
    Window = rgb(248, 249, 252),
    Panel = rgb(235, 239, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(45, 51, 64),
    Muted = rgb(112, 121, 140),
    Accent = rgb(136, 179, 207),
    Accent2 = rgb(197, 221, 234),
    Border = rgb(200, 213, 225),
    Selected = rgb(229, 240, 247),
    Track = rgb(222, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_083")

AWE.Catalog.Themes["THEME_084"] = {
    Key = "THEME_084",
    Name = "Aurora Mint 084",
    Description = "aurora mint white glass palette",
    Window = rgb(246, 255, 252),
    Panel = rgb(230, 249, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(27, 60, 53),
    Muted = rgb(97, 131, 123),
    Accent = rgb(72, 212, 182),
    Accent2 = rgb(163, 241, 222),
    Border = rgb(185, 230, 219),
    Selected = rgb(216, 250, 240),
    Track = rgb(215, 235, 228),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_084")

AWE.Catalog.Themes["THEME_085"] = {
    Key = "THEME_085",
    Name = "Rose Opal 085",
    Description = "rose opal white glass palette",
    Window = rgb(255, 249, 253),
    Panel = rgb(250, 236, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(70, 42, 61),
    Muted = rgb(145, 112, 133),
    Accent = rgb(223, 143, 186),
    Accent2 = rgb(247, 202, 226),
    Border = rgb(236, 198, 219),
    Selected = rgb(252, 230, 243),
    Track = rgb(241, 220, 234),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_085")

AWE.Catalog.Themes["THEME_086"] = {
    Key = "THEME_086",
    Name = "Lilac Snow 086",
    Description = "lilac snow white glass palette",
    Window = rgb(250, 248, 255),
    Panel = rgb(239, 234, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(49, 43, 72),
    Muted = rgb(119, 111, 151),
    Accent = rgb(164, 150, 236),
    Accent2 = rgb(215, 207, 254),
    Border = rgb(216, 206, 240),
    Selected = rgb(236, 231, 254),
    Track = rgb(225, 220, 242),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_086")

AWE.Catalog.Themes["THEME_087"] = {
    Key = "THEME_087",
    Name = "Deep Ocean Light 087",
    Description = "deep ocean light white glass palette",
    Window = rgb(241, 250, 255),
    Panel = rgb(222, 239, 248),
    Card = rgb(255, 255, 255),
    Text = rgb(24, 48, 68),
    Muted = rgb(89, 120, 143),
    Accent = rgb(45, 175, 227),
    Accent2 = rgb(157, 230, 255),
    Border = rgb(173, 213, 234),
    Selected = rgb(214, 244, 255),
    Track = rgb(205, 225, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_087")

AWE.Catalog.Themes["THEME_088"] = {
    Key = "THEME_088",
    Name = "Champagne Glow 088",
    Description = "champagne glow white glass palette",
    Window = rgb(255, 252, 245),
    Panel = rgb(247, 241, 226),
    Card = rgb(255, 255, 255),
    Text = rgb(66, 56, 41),
    Muted = rgb(133, 120, 101),
    Accent = rgb(222, 180, 109),
    Accent2 = rgb(251, 220, 166),
    Border = rgb(234, 216, 181),
    Selected = rgb(253, 240, 212),
    Track = rgb(236, 226, 206),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_088")

AWE.Catalog.Themes["THEME_089"] = {
    Key = "THEME_089",
    Name = "Mono Frost 089",
    Description = "mono frost white glass palette",
    Window = rgb(249, 250, 252),
    Panel = rgb(236, 239, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(34, 39, 48),
    Muted = rgb(108, 116, 130),
    Accent = rgb(128, 173, 207),
    Accent2 = rgb(198, 225, 244),
    Border = rgb(205, 215, 228),
    Selected = rgb(229, 240, 250),
    Track = rgb(219, 226, 235),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_089")

AWE.Catalog.Themes["THEME_090"] = {
    Key = "THEME_090",
    Name = "Coral Mist 090",
    Description = "coral mist white glass palette",
    Window = rgb(255, 249, 247),
    Panel = rgb(249, 237, 233),
    Card = rgb(255, 255, 255),
    Text = rgb(71, 46, 44),
    Muted = rgb(145, 110, 107),
    Accent = rgb(232, 140, 126),
    Accent2 = rgb(248, 199, 187),
    Border = rgb(236, 202, 195),
    Selected = rgb(252, 229, 222),
    Track = rgb(243, 223, 217),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_090")

AWE.Catalog.Themes["THEME_091"] = {
    Key = "THEME_091",
    Name = "White Pearl Default 091",
    Description = "white pearl default white glass palette",
    Window = rgb(248, 252, 255),
    Panel = rgb(239, 247, 252),
    Card = rgb(255, 255, 255),
    Text = rgb(30, 48, 61),
    Muted = rgb(103, 126, 142),
    Accent = rgb(88, 221, 235),
    Accent2 = rgb(173, 246, 255),
    Border = rgb(199, 231, 239),
    Selected = rgb(224, 250, 253),
    Track = rgb(220, 235, 241),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_091")

AWE.Catalog.Themes["THEME_092"] = {
    Key = "THEME_092",
    Name = "Ice Glass 092",
    Description = "ice glass white glass palette",
    Window = rgb(246, 253, 255),
    Panel = rgb(229, 246, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(25, 55, 70),
    Muted = rgb(95, 132, 147),
    Accent = rgb(70, 212, 240),
    Accent2 = rgb(171, 247, 255),
    Border = rgb(180, 226, 239),
    Selected = rgb(220, 250, 255),
    Track = rgb(211, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_092")

AWE.Catalog.Themes["THEME_093"] = {
    Key = "THEME_093",
    Name = "Silver Pearl 093",
    Description = "silver pearl white glass palette",
    Window = rgb(248, 249, 252),
    Panel = rgb(235, 239, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(45, 51, 64),
    Muted = rgb(112, 121, 140),
    Accent = rgb(138, 181, 209),
    Accent2 = rgb(199, 223, 236),
    Border = rgb(201, 214, 226),
    Selected = rgb(230, 241, 248),
    Track = rgb(222, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_093")

AWE.Catalog.Themes["THEME_094"] = {
    Key = "THEME_094",
    Name = "Aurora Mint 094",
    Description = "aurora mint white glass palette",
    Window = rgb(246, 255, 252),
    Panel = rgb(230, 249, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(27, 60, 53),
    Muted = rgb(97, 131, 123),
    Accent = rgb(74, 214, 184),
    Accent2 = rgb(165, 243, 224),
    Border = rgb(186, 231, 220),
    Selected = rgb(217, 251, 241),
    Track = rgb(215, 235, 228),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_094")

AWE.Catalog.Themes["THEME_095"] = {
    Key = "THEME_095",
    Name = "Rose Opal 095",
    Description = "rose opal white glass palette",
    Window = rgb(255, 249, 253),
    Panel = rgb(250, 236, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(70, 42, 61),
    Muted = rgb(145, 112, 133),
    Accent = rgb(225, 145, 188),
    Accent2 = rgb(249, 204, 228),
    Border = rgb(237, 199, 220),
    Selected = rgb(253, 231, 244),
    Track = rgb(241, 220, 234),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_095")

AWE.Catalog.Themes["THEME_096"] = {
    Key = "THEME_096",
    Name = "Lilac Snow 096",
    Description = "lilac snow white glass palette",
    Window = rgb(250, 248, 255),
    Panel = rgb(239, 234, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(49, 43, 72),
    Muted = rgb(119, 111, 151),
    Accent = rgb(166, 152, 238),
    Accent2 = rgb(217, 209, 255),
    Border = rgb(217, 207, 241),
    Selected = rgb(237, 232, 255),
    Track = rgb(225, 220, 242),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_096")

AWE.Catalog.Themes["THEME_097"] = {
    Key = "THEME_097",
    Name = "Deep Ocean Light 097",
    Description = "deep ocean light white glass palette",
    Window = rgb(241, 250, 255),
    Panel = rgb(222, 239, 248),
    Card = rgb(255, 255, 255),
    Text = rgb(24, 48, 68),
    Muted = rgb(89, 120, 143),
    Accent = rgb(47, 177, 229),
    Accent2 = rgb(159, 232, 255),
    Border = rgb(173, 213, 234),
    Selected = rgb(214, 244, 255),
    Track = rgb(205, 225, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_097")

AWE.Catalog.Themes["THEME_098"] = {
    Key = "THEME_098",
    Name = "Champagne Glow 098",
    Description = "champagne glow white glass palette",
    Window = rgb(255, 252, 245),
    Panel = rgb(247, 241, 226),
    Card = rgb(255, 255, 255),
    Text = rgb(66, 56, 41),
    Muted = rgb(133, 120, 101),
    Accent = rgb(224, 182, 111),
    Accent2 = rgb(253, 222, 168),
    Border = rgb(235, 217, 182),
    Selected = rgb(254, 241, 213),
    Track = rgb(236, 226, 206),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_098")

AWE.Catalog.Themes["THEME_099"] = {
    Key = "THEME_099",
    Name = "Mono Frost 099",
    Description = "mono frost white glass palette",
    Window = rgb(249, 250, 252),
    Panel = rgb(236, 239, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(34, 39, 48),
    Muted = rgb(108, 116, 130),
    Accent = rgb(130, 175, 209),
    Accent2 = rgb(200, 227, 246),
    Border = rgb(205, 215, 228),
    Selected = rgb(229, 240, 250),
    Track = rgb(219, 226, 235),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_099")

AWE.Catalog.Themes["THEME_100"] = {
    Key = "THEME_100",
    Name = "Coral Mist 100",
    Description = "coral mist white glass palette",
    Window = rgb(255, 249, 247),
    Panel = rgb(249, 237, 233),
    Card = rgb(255, 255, 255),
    Text = rgb(71, 46, 44),
    Muted = rgb(145, 110, 107),
    Accent = rgb(234, 142, 128),
    Accent2 = rgb(250, 201, 189),
    Border = rgb(237, 203, 196),
    Selected = rgb(253, 230, 223),
    Track = rgb(243, 223, 217),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_100")

AWE.Catalog.Themes["THEME_101"] = {
    Key = "THEME_101",
    Name = "White Pearl Default 101",
    Description = "white pearl default white glass palette",
    Window = rgb(248, 252, 255),
    Panel = rgb(239, 247, 252),
    Card = rgb(255, 255, 255),
    Text = rgb(30, 48, 61),
    Muted = rgb(103, 126, 142),
    Accent = rgb(90, 223, 237),
    Accent2 = rgb(175, 248, 255),
    Border = rgb(199, 231, 239),
    Selected = rgb(224, 250, 253),
    Track = rgb(220, 235, 241),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_101")

AWE.Catalog.Themes["THEME_102"] = {
    Key = "THEME_102",
    Name = "Ice Glass 102",
    Description = "ice glass white glass palette",
    Window = rgb(246, 253, 255),
    Panel = rgb(229, 246, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(25, 55, 70),
    Muted = rgb(95, 132, 147),
    Accent = rgb(55, 197, 225),
    Accent2 = rgb(156, 232, 247),
    Border = rgb(175, 221, 234),
    Selected = rgb(215, 245, 251),
    Track = rgb(211, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_102")

AWE.Catalog.Themes["THEME_103"] = {
    Key = "THEME_103",
    Name = "Silver Pearl 103",
    Description = "silver pearl white glass palette",
    Window = rgb(248, 249, 252),
    Panel = rgb(235, 239, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(45, 51, 64),
    Muted = rgb(112, 121, 140),
    Accent = rgb(140, 183, 211),
    Accent2 = rgb(201, 225, 238),
    Border = rgb(201, 214, 226),
    Selected = rgb(230, 241, 248),
    Track = rgb(222, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_103")

AWE.Catalog.Themes["THEME_104"] = {
    Key = "THEME_104",
    Name = "Aurora Mint 104",
    Description = "aurora mint white glass palette",
    Window = rgb(246, 255, 252),
    Panel = rgb(230, 249, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(27, 60, 53),
    Muted = rgb(97, 131, 123),
    Accent = rgb(76, 216, 186),
    Accent2 = rgb(167, 245, 226),
    Border = rgb(187, 232, 221),
    Selected = rgb(218, 252, 242),
    Track = rgb(215, 235, 228),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_104")

AWE.Catalog.Themes["THEME_105"] = {
    Key = "THEME_105",
    Name = "Rose Opal 105",
    Description = "rose opal white glass palette",
    Window = rgb(255, 249, 253),
    Panel = rgb(250, 236, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(70, 42, 61),
    Muted = rgb(145, 112, 133),
    Accent = rgb(227, 147, 190),
    Accent2 = rgb(251, 206, 230),
    Border = rgb(237, 199, 220),
    Selected = rgb(253, 231, 244),
    Track = rgb(241, 220, 234),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_105")

AWE.Catalog.Themes["THEME_106"] = {
    Key = "THEME_106",
    Name = "Lilac Snow 106",
    Description = "lilac snow white glass palette",
    Window = rgb(250, 248, 255),
    Panel = rgb(239, 234, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(49, 43, 72),
    Muted = rgb(119, 111, 151),
    Accent = rgb(168, 154, 240),
    Accent2 = rgb(219, 211, 255),
    Border = rgb(218, 208, 242),
    Selected = rgb(238, 233, 255),
    Track = rgb(225, 220, 242),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_106")

AWE.Catalog.Themes["THEME_107"] = {
    Key = "THEME_107",
    Name = "Deep Ocean Light 107",
    Description = "deep ocean light white glass palette",
    Window = rgb(241, 250, 255),
    Panel = rgb(222, 239, 248),
    Card = rgb(255, 255, 255),
    Text = rgb(24, 48, 68),
    Muted = rgb(89, 120, 143),
    Accent = rgb(32, 162, 214),
    Accent2 = rgb(144, 217, 242),
    Border = rgb(168, 208, 229),
    Selected = rgb(209, 239, 250),
    Track = rgb(205, 225, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_107")

AWE.Catalog.Themes["THEME_108"] = {
    Key = "THEME_108",
    Name = "Champagne Glow 108",
    Description = "champagne glow white glass palette",
    Window = rgb(255, 252, 245),
    Panel = rgb(247, 241, 226),
    Card = rgb(255, 255, 255),
    Text = rgb(66, 56, 41),
    Muted = rgb(133, 120, 101),
    Accent = rgb(226, 184, 113),
    Accent2 = rgb(255, 224, 170),
    Border = rgb(236, 218, 183),
    Selected = rgb(255, 242, 214),
    Track = rgb(236, 226, 206),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_108")

AWE.Catalog.Themes["THEME_109"] = {
    Key = "THEME_109",
    Name = "Mono Frost 109",
    Description = "mono frost white glass palette",
    Window = rgb(249, 250, 252),
    Panel = rgb(236, 239, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(34, 39, 48),
    Muted = rgb(108, 116, 130),
    Accent = rgb(132, 177, 211),
    Accent2 = rgb(202, 229, 248),
    Border = rgb(206, 216, 229),
    Selected = rgb(230, 241, 251),
    Track = rgb(219, 226, 235),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_109")

AWE.Catalog.Themes["THEME_110"] = {
    Key = "THEME_110",
    Name = "Coral Mist 110",
    Description = "coral mist white glass palette",
    Window = rgb(255, 249, 247),
    Panel = rgb(249, 237, 233),
    Card = rgb(255, 255, 255),
    Text = rgb(71, 46, 44),
    Muted = rgb(145, 110, 107),
    Accent = rgb(236, 144, 130),
    Accent2 = rgb(252, 203, 191),
    Border = rgb(238, 204, 197),
    Selected = rgb(254, 231, 224),
    Track = rgb(243, 223, 217),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_110")

AWE.Catalog.Themes["THEME_111"] = {
    Key = "THEME_111",
    Name = "White Pearl Default 111",
    Description = "white pearl default white glass palette",
    Window = rgb(248, 252, 255),
    Panel = rgb(239, 247, 252),
    Card = rgb(255, 255, 255),
    Text = rgb(30, 48, 61),
    Muted = rgb(103, 126, 142),
    Accent = rgb(92, 225, 239),
    Accent2 = rgb(177, 250, 255),
    Border = rgb(200, 232, 240),
    Selected = rgb(225, 251, 254),
    Track = rgb(220, 235, 241),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_111")

AWE.Catalog.Themes["THEME_112"] = {
    Key = "THEME_112",
    Name = "Ice Glass 112",
    Description = "ice glass white glass palette",
    Window = rgb(246, 253, 255),
    Panel = rgb(229, 246, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(25, 55, 70),
    Muted = rgb(95, 132, 147),
    Accent = rgb(57, 199, 227),
    Accent2 = rgb(158, 234, 249),
    Border = rgb(176, 222, 235),
    Selected = rgb(216, 246, 252),
    Track = rgb(211, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_112")

AWE.Catalog.Themes["THEME_113"] = {
    Key = "THEME_113",
    Name = "Silver Pearl 113",
    Description = "silver pearl white glass palette",
    Window = rgb(248, 249, 252),
    Panel = rgb(235, 239, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(45, 51, 64),
    Muted = rgb(112, 121, 140),
    Accent = rgb(142, 185, 213),
    Accent2 = rgb(203, 227, 240),
    Border = rgb(202, 215, 227),
    Selected = rgb(231, 242, 249),
    Track = rgb(222, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_113")

AWE.Catalog.Themes["THEME_114"] = {
    Key = "THEME_114",
    Name = "Aurora Mint 114",
    Description = "aurora mint white glass palette",
    Window = rgb(246, 255, 252),
    Panel = rgb(230, 249, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(27, 60, 53),
    Muted = rgb(97, 131, 123),
    Accent = rgb(78, 218, 188),
    Accent2 = rgb(169, 247, 228),
    Border = rgb(187, 232, 221),
    Selected = rgb(218, 252, 242),
    Track = rgb(215, 235, 228),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_114")

AWE.Catalog.Themes["THEME_115"] = {
    Key = "THEME_115",
    Name = "Rose Opal 115",
    Description = "rose opal white glass palette",
    Window = rgb(255, 249, 253),
    Panel = rgb(250, 236, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(70, 42, 61),
    Muted = rgb(145, 112, 133),
    Accent = rgb(229, 149, 192),
    Accent2 = rgb(253, 208, 232),
    Border = rgb(238, 200, 221),
    Selected = rgb(254, 232, 245),
    Track = rgb(241, 220, 234),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_115")

AWE.Catalog.Themes["THEME_116"] = {
    Key = "THEME_116",
    Name = "Lilac Snow 116",
    Description = "lilac snow white glass palette",
    Window = rgb(250, 248, 255),
    Panel = rgb(239, 234, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(49, 43, 72),
    Muted = rgb(119, 111, 151),
    Accent = rgb(170, 156, 242),
    Accent2 = rgb(221, 213, 255),
    Border = rgb(218, 208, 242),
    Selected = rgb(238, 233, 255),
    Track = rgb(225, 220, 242),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_116")

AWE.Catalog.Themes["THEME_117"] = {
    Key = "THEME_117",
    Name = "Deep Ocean Light 117",
    Description = "deep ocean light white glass palette",
    Window = rgb(241, 250, 255),
    Panel = rgb(222, 239, 248),
    Card = rgb(255, 255, 255),
    Text = rgb(24, 48, 68),
    Muted = rgb(89, 120, 143),
    Accent = rgb(34, 164, 216),
    Accent2 = rgb(146, 219, 244),
    Border = rgb(169, 209, 230),
    Selected = rgb(210, 240, 251),
    Track = rgb(205, 225, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_117")

AWE.Catalog.Themes["THEME_118"] = {
    Key = "THEME_118",
    Name = "Champagne Glow 118",
    Description = "champagne glow white glass palette",
    Window = rgb(255, 252, 245),
    Panel = rgb(247, 241, 226),
    Card = rgb(255, 255, 255),
    Text = rgb(66, 56, 41),
    Muted = rgb(133, 120, 101),
    Accent = rgb(228, 186, 115),
    Accent2 = rgb(255, 226, 172),
    Border = rgb(236, 218, 183),
    Selected = rgb(255, 242, 214),
    Track = rgb(236, 226, 206),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_118")

AWE.Catalog.Themes["THEME_119"] = {
    Key = "THEME_119",
    Name = "Mono Frost 119",
    Description = "mono frost white glass palette",
    Window = rgb(249, 250, 252),
    Panel = rgb(236, 239, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(34, 39, 48),
    Muted = rgb(108, 116, 130),
    Accent = rgb(117, 162, 196),
    Accent2 = rgb(187, 214, 233),
    Border = rgb(201, 211, 224),
    Selected = rgb(225, 236, 246),
    Track = rgb(219, 226, 235),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_119")

AWE.Catalog.Themes["THEME_120"] = {
    Key = "THEME_120",
    Name = "Coral Mist 120",
    Description = "coral mist white glass palette",
    Window = rgb(255, 249, 247),
    Panel = rgb(249, 237, 233),
    Card = rgb(255, 255, 255),
    Text = rgb(71, 46, 44),
    Muted = rgb(145, 110, 107),
    Accent = rgb(238, 146, 132),
    Accent2 = rgb(254, 205, 193),
    Border = rgb(238, 204, 197),
    Selected = rgb(254, 231, 224),
    Track = rgb(243, 223, 217),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_120")

AWE.Catalog.Themes["THEME_121"] = {
    Key = "THEME_121",
    Name = "White Pearl Default 121",
    Description = "white pearl default white glass palette",
    Window = rgb(248, 252, 255),
    Panel = rgb(239, 247, 252),
    Card = rgb(255, 255, 255),
    Text = rgb(30, 48, 61),
    Muted = rgb(103, 126, 142),
    Accent = rgb(94, 227, 241),
    Accent2 = rgb(179, 252, 255),
    Border = rgb(201, 233, 241),
    Selected = rgb(226, 252, 255),
    Track = rgb(220, 235, 241),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_121")

AWE.Catalog.Themes["THEME_122"] = {
    Key = "THEME_122",
    Name = "Ice Glass 122",
    Description = "ice glass white glass palette",
    Window = rgb(246, 253, 255),
    Panel = rgb(229, 246, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(25, 55, 70),
    Muted = rgb(95, 132, 147),
    Accent = rgb(59, 201, 229),
    Accent2 = rgb(160, 236, 251),
    Border = rgb(176, 222, 235),
    Selected = rgb(216, 246, 252),
    Track = rgb(211, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_122")

AWE.Catalog.Themes["THEME_123"] = {
    Key = "THEME_123",
    Name = "Silver Pearl 123",
    Description = "silver pearl white glass palette",
    Window = rgb(248, 249, 252),
    Panel = rgb(235, 239, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(45, 51, 64),
    Muted = rgb(112, 121, 140),
    Accent = rgb(144, 187, 215),
    Accent2 = rgb(205, 229, 242),
    Border = rgb(203, 216, 228),
    Selected = rgb(232, 243, 250),
    Track = rgb(222, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_123")

AWE.Catalog.Themes["THEME_124"] = {
    Key = "THEME_124",
    Name = "Aurora Mint 124",
    Description = "aurora mint white glass palette",
    Window = rgb(246, 255, 252),
    Panel = rgb(230, 249, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(27, 60, 53),
    Muted = rgb(97, 131, 123),
    Accent = rgb(63, 203, 173),
    Accent2 = rgb(154, 232, 213),
    Border = rgb(182, 227, 216),
    Selected = rgb(213, 247, 237),
    Track = rgb(215, 235, 228),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_124")

AWE.Catalog.Themes["THEME_125"] = {
    Key = "THEME_125",
    Name = "Rose Opal 125",
    Description = "rose opal white glass palette",
    Window = rgb(255, 249, 253),
    Panel = rgb(250, 236, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(70, 42, 61),
    Muted = rgb(145, 112, 133),
    Accent = rgb(231, 151, 194),
    Accent2 = rgb(255, 210, 234),
    Border = rgb(239, 201, 222),
    Selected = rgb(255, 233, 246),
    Track = rgb(241, 220, 234),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_125")

AWE.Catalog.Themes["THEME_126"] = {
    Key = "THEME_126",
    Name = "Lilac Snow 126",
    Description = "lilac snow white glass palette",
    Window = rgb(250, 248, 255),
    Panel = rgb(239, 234, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(49, 43, 72),
    Muted = rgb(119, 111, 151),
    Accent = rgb(172, 158, 244),
    Accent2 = rgb(223, 215, 255),
    Border = rgb(219, 209, 243),
    Selected = rgb(239, 234, 255),
    Track = rgb(225, 220, 242),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_126")

AWE.Catalog.Themes["THEME_127"] = {
    Key = "THEME_127",
    Name = "Deep Ocean Light 127",
    Description = "deep ocean light white glass palette",
    Window = rgb(241, 250, 255),
    Panel = rgb(222, 239, 248),
    Card = rgb(255, 255, 255),
    Text = rgb(24, 48, 68),
    Muted = rgb(89, 120, 143),
    Accent = rgb(36, 166, 218),
    Accent2 = rgb(148, 221, 246),
    Border = rgb(170, 210, 231),
    Selected = rgb(211, 241, 252),
    Track = rgb(205, 225, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_127")

AWE.Catalog.Themes["THEME_128"] = {
    Key = "THEME_128",
    Name = "Champagne Glow 128",
    Description = "champagne glow white glass palette",
    Window = rgb(255, 252, 245),
    Panel = rgb(247, 241, 226),
    Card = rgb(255, 255, 255),
    Text = rgb(66, 56, 41),
    Muted = rgb(133, 120, 101),
    Accent = rgb(230, 188, 117),
    Accent2 = rgb(255, 228, 174),
    Border = rgb(237, 219, 184),
    Selected = rgb(255, 243, 215),
    Track = rgb(236, 226, 206),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_128")

AWE.Catalog.Themes["THEME_129"] = {
    Key = "THEME_129",
    Name = "Mono Frost 129",
    Description = "mono frost white glass palette",
    Window = rgb(249, 250, 252),
    Panel = rgb(236, 239, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(34, 39, 48),
    Muted = rgb(108, 116, 130),
    Accent = rgb(119, 164, 198),
    Accent2 = rgb(189, 216, 235),
    Border = rgb(202, 212, 225),
    Selected = rgb(226, 237, 247),
    Track = rgb(219, 226, 235),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_129")

AWE.Catalog.Themes["THEME_130"] = {
    Key = "THEME_130",
    Name = "Coral Mist 130",
    Description = "coral mist white glass palette",
    Window = rgb(255, 249, 247),
    Panel = rgb(249, 237, 233),
    Card = rgb(255, 255, 255),
    Text = rgb(71, 46, 44),
    Muted = rgb(145, 110, 107),
    Accent = rgb(240, 148, 134),
    Accent2 = rgb(255, 207, 195),
    Border = rgb(239, 205, 198),
    Selected = rgb(255, 232, 225),
    Track = rgb(243, 223, 217),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_130")

AWE.Catalog.Themes["THEME_131"] = {
    Key = "THEME_131",
    Name = "White Pearl Default 131",
    Description = "white pearl default white glass palette",
    Window = rgb(248, 252, 255),
    Panel = rgb(239, 247, 252),
    Card = rgb(255, 255, 255),
    Text = rgb(30, 48, 61),
    Muted = rgb(103, 126, 142),
    Accent = rgb(96, 229, 243),
    Accent2 = rgb(181, 254, 255),
    Border = rgb(201, 233, 241),
    Selected = rgb(226, 252, 255),
    Track = rgb(220, 235, 241),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_131")

AWE.Catalog.Themes["THEME_132"] = {
    Key = "THEME_132",
    Name = "Ice Glass 132",
    Description = "ice glass white glass palette",
    Window = rgb(246, 253, 255),
    Panel = rgb(229, 246, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(25, 55, 70),
    Muted = rgb(95, 132, 147),
    Accent = rgb(61, 203, 231),
    Accent2 = rgb(162, 238, 253),
    Border = rgb(177, 223, 236),
    Selected = rgb(217, 247, 253),
    Track = rgb(211, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_132")

AWE.Catalog.Themes["THEME_133"] = {
    Key = "THEME_133",
    Name = "Silver Pearl 133",
    Description = "silver pearl white glass palette",
    Window = rgb(248, 249, 252),
    Panel = rgb(235, 239, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(45, 51, 64),
    Muted = rgb(112, 121, 140),
    Accent = rgb(146, 189, 217),
    Accent2 = rgb(207, 231, 244),
    Border = rgb(203, 216, 228),
    Selected = rgb(232, 243, 250),
    Track = rgb(222, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_133")

AWE.Catalog.Themes["THEME_134"] = {
    Key = "THEME_134",
    Name = "Aurora Mint 134",
    Description = "aurora mint white glass palette",
    Window = rgb(246, 255, 252),
    Panel = rgb(230, 249, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(27, 60, 53),
    Muted = rgb(97, 131, 123),
    Accent = rgb(65, 205, 175),
    Accent2 = rgb(156, 234, 215),
    Border = rgb(183, 228, 217),
    Selected = rgb(214, 248, 238),
    Track = rgb(215, 235, 228),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_134")

AWE.Catalog.Themes["THEME_135"] = {
    Key = "THEME_135",
    Name = "Rose Opal 135",
    Description = "rose opal white glass palette",
    Window = rgb(255, 249, 253),
    Panel = rgb(250, 236, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(70, 42, 61),
    Muted = rgb(145, 112, 133),
    Accent = rgb(233, 153, 196),
    Accent2 = rgb(255, 212, 236),
    Border = rgb(239, 201, 222),
    Selected = rgb(255, 233, 246),
    Track = rgb(241, 220, 234),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_135")

AWE.Catalog.Themes["THEME_136"] = {
    Key = "THEME_136",
    Name = "Lilac Snow 136",
    Description = "lilac snow white glass palette",
    Window = rgb(250, 248, 255),
    Panel = rgb(239, 234, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(49, 43, 72),
    Muted = rgb(119, 111, 151),
    Accent = rgb(157, 143, 229),
    Accent2 = rgb(208, 200, 247),
    Border = rgb(214, 204, 238),
    Selected = rgb(234, 229, 252),
    Track = rgb(225, 220, 242),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_136")

AWE.Catalog.Themes["THEME_137"] = {
    Key = "THEME_137",
    Name = "Deep Ocean Light 137",
    Description = "deep ocean light white glass palette",
    Window = rgb(241, 250, 255),
    Panel = rgb(222, 239, 248),
    Card = rgb(255, 255, 255),
    Text = rgb(24, 48, 68),
    Muted = rgb(89, 120, 143),
    Accent = rgb(38, 168, 220),
    Accent2 = rgb(150, 223, 248),
    Border = rgb(170, 210, 231),
    Selected = rgb(211, 241, 252),
    Track = rgb(205, 225, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_137")

AWE.Catalog.Themes["THEME_138"] = {
    Key = "THEME_138",
    Name = "Champagne Glow 138",
    Description = "champagne glow white glass palette",
    Window = rgb(255, 252, 245),
    Panel = rgb(247, 241, 226),
    Card = rgb(255, 255, 255),
    Text = rgb(66, 56, 41),
    Muted = rgb(133, 120, 101),
    Accent = rgb(232, 190, 119),
    Accent2 = rgb(255, 230, 176),
    Border = rgb(238, 220, 185),
    Selected = rgb(255, 244, 216),
    Track = rgb(236, 226, 206),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_138")

AWE.Catalog.Themes["THEME_139"] = {
    Key = "THEME_139",
    Name = "Mono Frost 139",
    Description = "mono frost white glass palette",
    Window = rgb(249, 250, 252),
    Panel = rgb(236, 239, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(34, 39, 48),
    Muted = rgb(108, 116, 130),
    Accent = rgb(121, 166, 200),
    Accent2 = rgb(191, 218, 237),
    Border = rgb(202, 212, 225),
    Selected = rgb(226, 237, 247),
    Track = rgb(219, 226, 235),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_139")

AWE.Catalog.Themes["THEME_140"] = {
    Key = "THEME_140",
    Name = "Coral Mist 140",
    Description = "coral mist white glass palette",
    Window = rgb(255, 249, 247),
    Panel = rgb(249, 237, 233),
    Card = rgb(255, 255, 255),
    Text = rgb(71, 46, 44),
    Muted = rgb(145, 110, 107),
    Accent = rgb(242, 150, 136),
    Accent2 = rgb(255, 209, 197),
    Border = rgb(240, 206, 199),
    Selected = rgb(255, 233, 226),
    Track = rgb(243, 223, 217),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_140")

AWE.Catalog.Themes["THEME_141"] = {
    Key = "THEME_141",
    Name = "White Pearl Default 141",
    Description = "white pearl default white glass palette",
    Window = rgb(248, 252, 255),
    Panel = rgb(239, 247, 252),
    Card = rgb(255, 255, 255),
    Text = rgb(30, 48, 61),
    Muted = rgb(103, 126, 142),
    Accent = rgb(81, 214, 228),
    Accent2 = rgb(166, 239, 248),
    Border = rgb(196, 228, 236),
    Selected = rgb(221, 247, 250),
    Track = rgb(220, 235, 241),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_141")

AWE.Catalog.Themes["THEME_142"] = {
    Key = "THEME_142",
    Name = "Ice Glass 142",
    Description = "ice glass white glass palette",
    Window = rgb(246, 253, 255),
    Panel = rgb(229, 246, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(25, 55, 70),
    Muted = rgb(95, 132, 147),
    Accent = rgb(63, 205, 233),
    Accent2 = rgb(164, 240, 255),
    Border = rgb(178, 224, 237),
    Selected = rgb(218, 248, 254),
    Track = rgb(211, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_142")

AWE.Catalog.Themes["THEME_143"] = {
    Key = "THEME_143",
    Name = "Silver Pearl 143",
    Description = "silver pearl white glass palette",
    Window = rgb(248, 249, 252),
    Panel = rgb(235, 239, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(45, 51, 64),
    Muted = rgb(112, 121, 140),
    Accent = rgb(148, 191, 219),
    Accent2 = rgb(209, 233, 246),
    Border = rgb(204, 217, 229),
    Selected = rgb(233, 244, 251),
    Track = rgb(222, 231, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_143")

AWE.Catalog.Themes["THEME_144"] = {
    Key = "THEME_144",
    Name = "Aurora Mint 144",
    Description = "aurora mint white glass palette",
    Window = rgb(246, 255, 252),
    Panel = rgb(230, 249, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(27, 60, 53),
    Muted = rgb(97, 131, 123),
    Accent = rgb(67, 207, 177),
    Accent2 = rgb(158, 236, 217),
    Border = rgb(184, 229, 218),
    Selected = rgb(215, 249, 239),
    Track = rgb(215, 235, 228),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_144")

AWE.Catalog.Themes["THEME_145"] = {
    Key = "THEME_145",
    Name = "Rose Opal 145",
    Description = "rose opal white glass palette",
    Window = rgb(255, 249, 253),
    Panel = rgb(250, 236, 245),
    Card = rgb(255, 255, 255),
    Text = rgb(70, 42, 61),
    Muted = rgb(145, 112, 133),
    Accent = rgb(235, 155, 198),
    Accent2 = rgb(255, 214, 238),
    Border = rgb(240, 202, 223),
    Selected = rgb(255, 234, 247),
    Track = rgb(241, 220, 234),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_145")

AWE.Catalog.Themes["THEME_146"] = {
    Key = "THEME_146",
    Name = "Lilac Snow 146",
    Description = "lilac snow white glass palette",
    Window = rgb(250, 248, 255),
    Panel = rgb(239, 234, 251),
    Card = rgb(255, 255, 255),
    Text = rgb(49, 43, 72),
    Muted = rgb(119, 111, 151),
    Accent = rgb(159, 145, 231),
    Accent2 = rgb(210, 202, 249),
    Border = rgb(215, 205, 239),
    Selected = rgb(235, 230, 253),
    Track = rgb(225, 220, 242),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_146")

AWE.Catalog.Themes["THEME_147"] = {
    Key = "THEME_147",
    Name = "Deep Ocean Light 147",
    Description = "deep ocean light white glass palette",
    Window = rgb(241, 250, 255),
    Panel = rgb(222, 239, 248),
    Card = rgb(255, 255, 255),
    Text = rgb(24, 48, 68),
    Muted = rgb(89, 120, 143),
    Accent = rgb(40, 170, 222),
    Accent2 = rgb(152, 225, 250),
    Border = rgb(171, 211, 232),
    Selected = rgb(212, 242, 253),
    Track = rgb(205, 225, 239),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_147")

AWE.Catalog.Themes["THEME_148"] = {
    Key = "THEME_148",
    Name = "Champagne Glow 148",
    Description = "champagne glow white glass palette",
    Window = rgb(255, 252, 245),
    Panel = rgb(247, 241, 226),
    Card = rgb(255, 255, 255),
    Text = rgb(66, 56, 41),
    Muted = rgb(133, 120, 101),
    Accent = rgb(234, 192, 121),
    Accent2 = rgb(255, 232, 178),
    Border = rgb(238, 220, 185),
    Selected = rgb(255, 244, 216),
    Track = rgb(236, 226, 206),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_148")

AWE.Catalog.Themes["THEME_149"] = {
    Key = "THEME_149",
    Name = "Mono Frost 149",
    Description = "mono frost white glass palette",
    Window = rgb(249, 250, 252),
    Panel = rgb(236, 239, 244),
    Card = rgb(255, 255, 255),
    Text = rgb(34, 39, 48),
    Muted = rgb(108, 116, 130),
    Accent = rgb(123, 168, 202),
    Accent2 = rgb(193, 220, 239),
    Border = rgb(203, 213, 226),
    Selected = rgb(227, 238, 248),
    Track = rgb(219, 226, 235),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_149")

AWE.Catalog.Themes["THEME_150"] = {
    Key = "THEME_150",
    Name = "Coral Mist 150",
    Description = "coral mist white glass palette",
    Window = rgb(255, 249, 247),
    Panel = rgb(249, 237, 233),
    Card = rgb(255, 255, 255),
    Text = rgb(71, 46, 44),
    Muted = rgb(145, 110, 107),
    Accent = rgb(244, 152, 138),
    Accent2 = rgb(255, 211, 199),
    Border = rgb(240, 206, 199),
    Selected = rgb(255, 233, 226),
    Track = rgb(243, 223, 217),
    Danger = rgb(231, 103, 132),
}
table.insert(AWE.Catalog.ThemeOrder, "THEME_150")


-- Catalog index helpers
local function sortCatalogKeys(order, registry)
    table.sort(order, function(a,b)
        local left = registry[a] and registry[a].Name or a
        local right = registry[b] and registry[b].Name or b
        return left < right
    end)
end
sortCatalogKeys(AWE.Catalog.EffectOrder, AWE.Catalog.Effects)
sortCatalogKeys(AWE.Catalog.SceneOrder, AWE.Catalog.Scenes)
sortCatalogKeys(AWE.Catalog.ThemeOrder, AWE.Catalog.Themes)

local function renderPresetList(config)
    local registry = config.Registry
    local order = config.Order
    local container = config.Container
    local query = config.Search and config.Search.Text or ""
    local offset = config.Offset()
    clearChildren(container)
    local filtered = {}
    for _, key in ipairs(order) do
        local value = registry[key]
        if value and matches(query, value.Name, value.Description, value.Category or "") then table.insert(filtered, key) end
    end
    config.CountLabel.Text = string.format("%d results · %d available", #filtered, #order)
    local shown = 0
    local startAt = math.clamp(offset + 1, 1, math.max(1,#filtered))
    for index = startAt, math.min(#filtered, startAt + 9) do
        local key = filtered[index]
        local value = registry[key]
        if value then
            shown = shown + 1
            local swatch = value.Color1 or value.Accent or value.FogColor or PALETTE.Accent
            local subtitle = value.Description or value.Category or "Preset"
            presetCard(container, value.Name, subtitle, swatch, function()
                if config.Kind == "Effect" then
                    AWE:SetEffectProfile(key)
                    activeProfileLabel.Text = "Active profile: " .. value.Name
                elseif config.Kind == "Theme" then
                    AWE:ApplyTheme(key)
                elseif config.Kind == "Scene" then
                    AWE:ApplyScene(key)
                end
            end)
        end
    end
    if shown == 0 then label(container, "No presets matched this search.", 24) end
end

local function countResults(registry, order, query)
    local total = 0
    for _, key in ipairs(order) do
        local value = registry[key]
        if value and matches(query, value.Name, value.Description, value.Category or "") then total = total + 1 end
    end
    return total
end
local function renderEffects() renderPresetList({ Registry=AWE.Catalog.Effects, Order=AWE.Catalog.EffectOrder, Container=effectResults, Search=effectSearch, CountLabel=effectCount, Offset=function() return effectPageOffset end, Kind="Effect" }) end
local function renderThemes() renderPresetList({ Registry=AWE.Catalog.Themes, Order=AWE.Catalog.ThemeOrder, Container=themeResults, Search=themeSearch, CountLabel=themeCount, Offset=function() return themeOffset end, Kind="Theme" }) end
local function renderScenes() renderPresetList({ Registry=AWE.Catalog.Scenes, Order=AWE.Catalog.SceneOrder, Container=sceneResults, Search=sceneSearch, CountLabel=sceneCount, Offset=function() return sceneOffset end, Kind="Scene" }) end

connect(effectSearch:GetPropertyChangedSignal("Text"), function() effectPageOffset=0; renderEffects() end)
connect(themeSearch:GetPropertyChangedSignal("Text"), function() themeOffset=0; renderThemes() end)
connect(sceneSearch:GetPropertyChangedSignal("Text"), function() sceneOffset=0; renderScenes() end)
-- Page buttons cycle through the next ten matching results.
connect(effectNextButton.Activated, function() local total=countResults(AWE.Catalog.Effects,AWE.Catalog.EffectOrder,effectSearch.Text); local pages=math.max(1,math.ceil(total/10)); effectPageOffset=((math.floor(effectPageOffset/10)+1)%pages)*10; renderEffects() end)
connect(themeNextButton.Activated, function() local total=countResults(AWE.Catalog.Themes,AWE.Catalog.ThemeOrder,themeSearch.Text); local pages=math.max(1,math.ceil(total/10)); themeOffset=((math.floor(themeOffset/10)+1)%pages)*10; renderThemes() end)
connect(sceneNextButton.Activated, function() local total=countResults(AWE.Catalog.Scenes,AWE.Catalog.SceneOrder,sceneSearch.Text); local pages=math.max(1,math.ceil(total/10)); sceneOffset=((math.floor(sceneOffset/10)+1)%pages)*10; renderScenes() end)

-- Apply an existing selected theme after widgets have registered their theme roles.
local defaultThemeKey = "THEME_001"
local saved = false
-- Loading a default profile is deterministic, avoiding randomized startup visuals.
AWE.Active.Effect = "FX_001"
AWE.Active.Theme = defaultThemeKey
AWE.Active.Scene = nil
AWE:ApplyTheme(defaultThemeKey)
local settingsLoaded = AWE:LoadSettings()
if not settingsLoaded and AWE.Active.Theme and AWE.Catalog.Themes[AWE.Active.Theme] then AWE:ApplyTheme(AWE.Active.Theme) end
if AWE.Active.Effect and AWE.Catalog.Effects[AWE.Active.Effect] then AWE:SetEffectProfile(AWE.Active.Effect) end
if AWE.Active.Scene and AWE.Catalog.Scenes[AWE.Active.Scene] then AWE:ApplyScene(AWE.Active.Scene) end
renderEffects(); renderThemes(); renderScenes()
AWE:SelectTab("HOME")
applyResponsiveScale()
AWE:RefreshLightingFx()

-- Live orbit animator: one connection updates all local orbit motes, not one connection per part.
local elapsed = 0
connect(RunService.Heartbeat, function(dt)
    if AWE.Destroyed then return end
    local root = AWE:GetRootPart()
    local profile = AWE:GetProfile()
    elapsed = elapsed + math.min(dt, 0.1) * AWE.State.OrbitSpeed * (profile and profile.OrbitSpeed or 1)
    local motes = AWE.EffectInstances.OrbitMotes
    if root and type(motes) == "table" and #motes > 0 then
        local radius = profile and profile.AuraRadius or 2
        for index, mote in ipairs(motes) do
            if mote and mote.Parent then
                local angle = elapsed + ((index-1) * (math.pi*2/#motes))
                local bob = math.sin(elapsed*1.5 + index*0.7) * 0.25
                local offset = Vector3.new(math.cos(angle)*radius, 0.25+bob+math.sin(angle*2)*0.15, math.sin(angle)*radius)
                mote.CFrame = root.CFrame + offset
            end
        end
    end
    if AWE.State.Glow and AWE.TopGlow and AWE.TopGlow.Parent and not AWE.State.ReducedMotion then
        local gradient = AWE.TopGlow:FindFirstChildOfClass("UIGradient")
        if gradient then gradient.Rotation = (elapsed*22)%360 end
    end
    if AWE.DecorMotes then
        AWE.DecorLayer.Visible = AWE.State.BackgroundParticles
        for _, entry in ipairs(AWE.DecorMotes) do
            local mote = entry.Object
            if mote and mote.Parent then
                if AWE.State.ReducedMotion then
                    mote.Position = UDim2.fromScale(entry.X, entry.Y)
                else
                    local driftX = math.sin(elapsed*0.24 + entry.Phase) * 0.018
                    local driftY = math.cos(elapsed*0.31 + entry.Phase) * 0.025
                    mote.Position = UDim2.fromScale(math.clamp(entry.X+driftX,0.02,0.98), math.clamp(entry.Y+driftY,0.04,0.96))
                end
                mote.BackgroundColor3 = entry.Phase % 2 > 1 and PALETTE.Accent2 or Color3.fromRGB(255,255,255)
            end
        end
    end
end)

connect(LocalPlayer.CharacterAdded, function()
    task.wait(0.8)
    if AWE.Destroyed then return end
    AWE:RefreshAllAvatarEffects()
end)

-- Runtime diagnostics update sparingly.
task.spawn(function()
    while not AWE.Destroyed do
        task.wait(4)
        if diagText and diagText.Parent then
            local camera = Workspace.CurrentCamera
            local size = camera and camera.ViewportSize or Vector2.new(0,0)
            local effectCountValue = 0
            for _ in pairs(AWE.EffectInstances) do effectCountValue=effectCountValue+1 end
            diagText.Text = string.format("Version: %s\nViewport: %d × %d\nTracked effect groups: %d\nCatalog: %d FX / %d scenes / %d themes",
                AWE.Version, size.X, size.Y, effectCountValue,
                #AWE.Catalog.EffectOrder, #AWE.Catalog.SceneOrder, #AWE.Catalog.ThemeOrder)
            budgetLabel.Text = "Active profile: " .. AWE.State.Performance .. " · effect multiplier " .. tostring(AWE.State.ParticleBudget)
            statusLine.Text = "Ready · " .. #AWE.Catalog.EffectOrder .. " effect profiles · " .. #AWE.Catalog.ThemeOrder .. " themes"
        end
    end
end)

function AWE:Destroy()
    if self.Destroyed then return end
    self.Destroyed = true
    disconnectAll()
    self:DestroyAllEffects()
    self:RestoreLighting()
    if self.Gui then pcall(function() self.Gui:Destroy() end) end
    if ENV.__AQUAMARINE_WHITE_EDITION_V4 == self then ENV.__AQUAMARINE_WHITE_EDITION_V4 = nil end
end

ENV.__AQUAMARINE_WHITE_EDITION_V4 = AWE
showNotice("Aquamarine White Edition loaded", 2.5)
print(string.format("[Aquamarine White Edition] v%s ready | %d effect profiles | %d scenes | %d themes",
    AWE.Version, #AWE.Catalog.EffectOrder, #AWE.Catalog.SceneOrder, #AWE.Catalog.ThemeOrder))
