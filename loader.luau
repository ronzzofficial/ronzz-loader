--==================================================
-- ZANJI PUBLIC LOADER
-- ZANJIHUB STYLE LOADER
--==================================================

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")

local LocalPlayer =
    Players.LocalPlayer
    or Players.PlayerAdded:Wait()

local API =
    "https://zanji-license-api.ronzz191002.workers.dev"

local PRODUCT =
    "zanji_v2"

local SOURCE_ROUTE =
    "/v1/source/zanji_v2"

local KEY_FILE =
    "ZANJI_Key.txt"

--==================================================
-- COLORS
--==================================================

local COLORS = {
    Background = Color3.fromRGB(7, 7, 12),
    Sidebar = Color3.fromRGB(9, 9, 15),
    Panel = Color3.fromRGB(10, 10, 17),
    Card = Color3.fromRGB(10, 10, 17),

    Input = Color3.fromRGB(12, 12, 21),
    InputHover = Color3.fromRGB(16, 14, 27),

    Border = Color3.fromRGB(72, 45, 118),
    BorderSoft = Color3.fromRGB(45, 32, 72),

    Purple = Color3.fromRGB(154, 82, 255),
    PurpleBright = Color3.fromRGB(174, 100, 255),
    PurpleDark = Color3.fromRGB(105, 54, 175),

    White = Color3.fromRGB(238, 238, 245),
    Text = Color3.fromRGB(220, 220, 230),
    Muted = Color3.fromRGB(125, 125, 140),
    Muted2 = Color3.fromRGB(90, 90, 105),

    Success = Color3.fromRGB(130, 255, 175),
    Error = Color3.fromRGB(255, 105, 125),
}

--==================================================
-- HELPERS
--==================================================

local function Clean(value)
    return tostring(value or "")
        :gsub("^%s+", "")
        :gsub("%s+$", "")
end

local function GetEnvironment()
    if type(getgenv) == "function" then
        local ok, env = pcall(getgenv)

        if ok and type(env) == "table" then
            return env
        end
    end

    return _G
end

local Environment = GetEnvironment()

local function GetRequestFunction()

    if type(syn) == "table"
    and type(syn.request) == "function" then
        return syn.request
    end

    if type(http_request) == "function" then
        return http_request
    end

    if type(request) == "function" then
        return request
    end

    if type(fluxus) == "table"
    and type(fluxus.request) == "function" then
        return fluxus.request
    end

    if type(Environment.request) == "function" then
        return Environment.request
    end

    if type(Environment.http_request) == "function" then
        return Environment.http_request
    end

    return nil
end

local function SendRequest(options)

    local requestFunction = GetRequestFunction()

    if type(requestFunction) ~= "function" then
        return nil,
            "Your executor does not support request/http_request."
    end

    local ok, response =
        pcall(requestFunction, options)

    if not ok then
        return nil, tostring(response)
    end

    if type(response) == "string" then
        return {
            Success = true,
            StatusCode = 200,
            Body = response,
        }
    end

    if type(response) ~= "table" then
        return nil,
            "Executor returned an invalid HTTP response."
    end

    local statusCode =
        tonumber(
            response.StatusCode
            or response.Status
            or response.status_code
            or response.status
            or 0
        ) or 0

    local success = response.Success

    if success == nil then
        success =
            statusCode >= 200
            and statusCode < 300
    end

    return {
        Success = success == true,
        StatusCode = statusCode,
        Body =
            tostring(
                response.Body
                or response.body
                or response.ResponseBody
                or response.responseBody
                or ""
            ),
    }
end

local function DecodeJson(body)

    if type(body) ~= "string"
    or body == "" then
        return nil
    end

    local ok, result =
        pcall(function()
            return HttpService:JSONDecode(body)
        end)

    if ok and type(result) == "table" then
        return result
    end

    return nil
end

local function ReadSavedKey()

    if type(readfile) ~= "function" then
        return ""
    end

    local ok, value =
        pcall(readfile, KEY_FILE)

    if not ok then
        return ""
    end

    return Clean(value):upper()
end

local function SaveKey(key)

    if type(writefile) ~= "function" then
        return false
    end

    local ok =
        pcall(
            writefile,
            KEY_FILE,
            Clean(key):upper()
        )

    return ok
end

--==================================================
-- API ERROR
--==================================================

local function FormatApiError(decoded, fallback)

    if type(decoded) ~= "table" then
        return tostring(
            fallback
            or "Unknown API error."
        )
    end

    local messages = {

        invalid_key =
            "The ZANJI key is invalid.",

        key_not_found =
            "The ZANJI key is invalid.",

        missing_key =
            "Enter your ZANJI key.",

        license_expired =
            "This ZANJI key has expired.",

        license_revoked =
            "This ZANJI key has been revoked.",

        license_paused =
            "This ZANJI key is paused.",

        account_limit_reached =
            "This key has no Roblox account slots remaining.",

        account_not_linked =
            "This Roblox account is not linked to this key.",

        product_not_allowed =
            "This key cannot access ZANJI V2.",

        invalid_access_token =
            "The temporary access token was rejected.",

        access_token_expired =
            "The temporary access token expired.",

        unsupported_place =
            "ZANJI does not support this Roblox experience.",

        source_not_configured =
            "The private ZANJI source is not configured.",

        source_fetch_failed =
            "The private ZANJI source could not be downloaded.",

        internal_server_error =
            "The ZANJI license service had a server error.",
    }

    local code =
        Clean(
            decoded.error
            or decoded.code
        ):lower()

    return
        messages[code]
        or Clean(decoded.message)
        or code
        or tostring(
            fallback
            or "Unknown API error."
        )
end

--==================================================
-- LICENSE ACTIVATION
--==================================================

local function ActivateKey(key)

    key = Clean(key):upper()

    if key == "" then
        return nil,
            "Enter your ZANJI Premium key."
    end

    local body =
        HttpService:JSONEncode({

            Key = key,

            Product = PRODUCT,

            RobloxUserId =
                tonumber(LocalPlayer.UserId)
                or 0,

            RobloxUsername =
                tostring(LocalPlayer.Name),

            PlaceId =
                tostring(game.PlaceId),

            UniverseId =
                tostring(game.GameId),
        })

    local response, requestError =
        SendRequest({

            Url =
                API
                .. "/v1/license/activate",

            Method = "POST",

            Headers = {
                ["Content-Type"] =
                    "application/json",

                ["Accept"] =
                    "application/json",

                ["Accept-Encoding"] =
                    "identity",

                ["Cache-Control"] =
                    "no-cache",
            },

            Body = body,
        })

    if not response then
        return nil,
            "Activation request failed: "
            .. tostring(requestError)
    end

    local decoded =
        DecodeJson(response.Body)

    if not response.Success
    or type(decoded) ~= "table"
    or decoded.ok ~= true then

        return nil,
            FormatApiError(
                decoded,

                "Activation failed with HTTP "
                .. tostring(response.StatusCode)
            )
    end

    local token =
        Clean(
            decoded.accessToken
            or decoded.access_token
            or decoded.token
        )

    if token == "" then
        return nil,
            "The API did not return an access token."
    end

    return {
        Token = token,
        Activation = decoded,
    }
end

--==================================================
-- DOWNLOAD PRIVATE SOURCE
--==================================================

local function DownloadSource(session)

    local response, requestError =
        SendRequest({

            Url =
                API
                .. SOURCE_ROUTE,

            Method = "GET",

            Headers = {

                ["Authorization"] =
                    "Bearer "
                    .. tostring(session.Token),

                ["Accept"] =
                    "text/plain",

                ["Accept-Encoding"] =
                    "identity",

                ["Cache-Control"] =
                    "no-cache",
            },
        })

    if not response then
        return nil,
            "Source request failed: "
            .. tostring(requestError)
    end

    if not response.Success then
        return nil,
            FormatApiError(
                DecodeJson(response.Body),

                "Source request failed with HTTP "
                .. tostring(response.StatusCode)
            )
    end

    local source =
        tostring(response.Body or "")

    if source == "" then
        return nil,
            "The private source was empty."
    end

    local marker =
        "-- ZANJI PRIVATE SOURCE"

    if source:sub(1, #marker) ~= marker then
        return nil,
            "The private source marker is missing."
    end

    local endMarker =
        "-- ZANJI_PRIVATE_END_MARKER"

    if source:find(
        endMarker,
        1,
        true
    ) == nil then

        return nil,
            "The private source is incomplete."
    end

    return source
end

--==================================================
-- INSTALL AUTH
--==================================================

local function InstallAuth(session)

    local activation =
        session.Activation or {}

    local features = {}

    if type(activation.features) == "table" then

        for name, enabled
        in pairs(activation.features) do

            features[name] =
                enabled == true
        end
    end

    Environment.ZANJI_LOADER_AUTHORIZED =
        true

    Environment.ZANJI_LOADER_OWNER =
        tostring(
            activation.owner
            or "License"
        )

    Environment.ZANJI_LOADER_PLAN =
        tostring(
            activation.role
            or "premium"
        )

    Environment.ZANJI_LOADER_EXPIRES_AT =
        tonumber(
            activation.expiresAt
            or 0
        ) or 0

    Environment.ZANJI_LOADER_MAX_ACCOUNTS =
        tonumber(
            activation.maxAccounts
            or 1
        ) or 1

    Environment.ZANJI_LOADER_SLOTS_USED =
        tonumber(
            activation.accountsUsed
            or 1
        ) or 1

    Environment.ZANJI_LOADER_FEATURES =
        features

    _G.ZANJI_LOADER_AUTHORIZED =
        true

    _G.ZANJI_LOADER_OWNER =
        Environment.ZANJI_LOADER_OWNER

    _G.ZANJI_LOADER_PLAN =
        Environment.ZANJI_LOADER_PLAN

    _G.ZANJI_LOADER_EXPIRES_AT =
        Environment.ZANJI_LOADER_EXPIRES_AT

    _G.ZANJI_LOADER_MAX_ACCOUNTS =
        Environment.ZANJI_LOADER_MAX_ACCOUNTS

    _G.ZANJI_LOADER_SLOTS_USED =
        Environment.ZANJI_LOADER_SLOTS_USED

    _G.ZANJI_LOADER_FEATURES =
        features
end

--==================================================
-- COMPILE / RUN
--==================================================

local function CompileAndRun(source)

    local compiler =
        loadstring
        or load

    if type(compiler) ~= "function" then
        return false,
            "loadstring/load is unavailable."
    end

    local ok, chunk, compileError =
        pcall(
            compiler,
            source
        )

    if not ok
    or type(chunk) ~= "function" then

        return false,
            "Compile failed: "
            .. tostring(
                compileError
                or chunk
            )
    end

    local runOk, runError =
        pcall(chunk)

    if not runOk then

        return false,
            "Runtime failed: "
            .. tostring(runError)
    end

    return true
end

local function RunWithKey(key)

    local session, activationError =
        ActivateKey(key)

    if not session then
        return false,
            activationError
    end

    local source, sourceError =
        DownloadSource(session)

    session.Token = nil

    if not source then
        return false,
            sourceError
    end

    InstallAuth(session)

    SaveKey(key)

    return CompileAndRun(source)
end

--==================================================
-- UI HELPERS
--==================================================

local function GetUiParent()

    if type(gethui) == "function" then

        local ok, result =
            pcall(gethui)

        if ok
        and typeof(result) == "Instance" then
            return result
        end
    end

    if typeof(CoreGui) == "Instance" then
        return CoreGui
    end

    return LocalPlayer:
        WaitForChild("PlayerGui")
end

local function AddCorner(instance, radius)

    local corner =
        Instance.new("UICorner")

    corner.CornerRadius =
        UDim.new(0, radius)

    corner.Parent = instance

    return corner
end

local function AddStroke(
    instance,
    color,
    thickness,
    transparency
)

    local stroke =
        Instance.new("UIStroke")

    stroke.Color = color
    stroke.Thickness = thickness or 1
    stroke.Transparency =
        transparency or 0

    stroke.Parent = instance

    return stroke
end

local function CreateLabel(
    parent,
    text,
    size,
    position,
    font,
    textSize,
    color
)

    local label =
        Instance.new("TextLabel")

    label.BackgroundTransparency = 1

    label.Position = position
    label.Size = size

    label.Font =
        font
        or Enum.Font.Gotham

    label.Text =
        tostring(text or "")

    label.TextSize =
        textSize
        or 13

    label.TextColor3 =
        color
        or COLORS.Text

    label.TextXAlignment =
        Enum.TextXAlignment.Left

    label.TextYAlignment =
        Enum.TextYAlignment.Center

    label.Parent = parent

    return label
end

local function CreateLine(parent, position)

    local line =
        Instance.new("Frame")

    line.Position = position

    line.Size =
        UDim2.new(
            1,
            0,
            0,
            1
        )

    line.BackgroundColor3 =
        COLORS.BorderSoft

    line.BorderSizePixel = 0

    line.Parent = parent

    return line
end

--==================================================
-- SIDEBAR ITEM
--==================================================

local function CreateSidebarItem(
    parent,
    text,
    icon,
    y,
    selected
)

    local item =
        Instance.new("Frame")

    item.Position =
        UDim2.fromOffset(
            10,
            y
        )

    item.Size =
        UDim2.new(
            1,
            -20,
            0,
            38
        )

    item.BackgroundColor3 =
        selected
        and Color3.fromRGB(
            24,
            16,
            39
        )
        or Color3.fromRGB(
            9,
            9,
            15
        )

    item.BorderSizePixel = 0

    item.Parent = parent

    AddCorner(item, 6)

    if selected then

        local indicator =
            Instance.new("Frame")

        indicator.Position =
            UDim2.fromOffset(
                0,
                7
            )

        indicator.Size =
            UDim2.fromOffset(
                2,
                24
            )

        indicator.BackgroundColor3 =
            COLORS.Purple

        indicator.BorderSizePixel = 0

        indicator.Parent = item

        AddCorner(indicator, 2)
    end

    local iconLabel =
        CreateLabel(
            item,
            icon,
            UDim2.fromOffset(
                28,
                38
            ),
            UDim2.fromOffset(
                10,
                0
            ),
            Enum.Font.Gotham,
            15,
            selected
            and COLORS.PurpleBright
            or COLORS.Muted
        )

    iconLabel.TextXAlignment =
        Enum.TextXAlignment.Center

    local textLabel =
        CreateLabel(
            item,
            text,
            UDim2.new(
                1,
                -50,
                1,
                0
            ),
            UDim2.fromOffset(
                43,
                0
            ),
            Enum.Font.Gotham,
            13,
            selected
            and COLORS.White
            or COLORS.Muted
        )

    return item
end

--==================================================
-- KEY WINDOW
--==================================================

local function CreateKeyWindow(
    initialKey,
    initialMessage
)

    local parent = GetUiParent()

    local old =
        parent:FindFirstChild(
            "ZANJI_Public_Key_UI"
        )

    if old then
        old:Destroy()
    end

    --==================================================
    -- SCREEN GUI
    --==================================================

    local gui =
        Instance.new("ScreenGui")

    gui.Name =
        "ZANJI_Public_Key_UI"

    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 999999

    gui.Parent = parent

    --==================================================
    -- MAIN WINDOW
    --==================================================

    local window =
        Instance.new("Frame")

    window.AnchorPoint =
        Vector2.new(
            0.5,
            0.5
        )

    window.Position =
        UDim2.fromScale(
            0.5,
            0.5
        )

    window.Size =
        UDim2.fromOffset(
            720,
            455
        )

    window.BackgroundColor3 =
        COLORS.Background

    window.BorderSizePixel = 0

    window.Active = true

    window.Parent = gui

    AddCorner(
        window,
        8
    )

    AddStroke(
        window,
        COLORS.Border,
        1,
        0
    )

    --==================================================
    -- SIDEBAR
    --==================================================

    local sidebar =
        Instance.new("Frame")

    sidebar.Position =
        UDim2.fromOffset(
            0,
            0
        )

    sidebar.Size =
        UDim2.new(
            0,
            180,
            1,
            0
        )

    sidebar.BackgroundColor3 =
        COLORS.Sidebar

    sidebar.BorderSizePixel = 0

    sidebar.Parent = window

    AddCorner(
        sidebar,
        8
    )

    -- cover right side of sidebar corner
    local sidebarCover =
        Instance.new("Frame")

    sidebarCover.Position =
        UDim2.fromOffset(
            170,
            0
        )

    sidebarCover.Size =
        UDim2.new(
            0,
            10,
            1,
            0
        )

    sidebarCover.BackgroundColor3 =
        COLORS.Sidebar

    sidebarCover.BorderSizePixel = 0

    sidebarCover.Parent = sidebar

    --==================================================
    -- LOGO
    --==================================================

    local logo =
        CreateLabel(
            sidebar,
            "ZANJIHUB",
            UDim2.new(
                1,
                -30,
                0,
                42
            ),
            UDim2.fromOffset(
                18,
                10
            ),
            Enum.Font.GothamBold,
            21,
            COLORS.PurpleBright
        )

    logo.TextStrokeTransparency = 0.65
    logo.TextStrokeColor3 =
        Color3.fromRGB(
            255,
            110,
            210
        )

    logo.TextXAlignment =
        Enum.TextXAlignment.Left

    CreateLine(
        sidebar,
        UDim2.fromOffset(
            0,
            57
        )
    )

    --==================================================
    -- SIDEBAR ITEMS
    --==================================================

    CreateSidebarItem(
        sidebar,
        "Home",
        "⌂",
        68,
        false
    )

    CreateSidebarItem(
        sidebar,
        "Transfer",
        "♧",
        110,
        true
    )

    CreateSidebarItem(
        sidebar,
        "Pick Place",
        "⇄",
        152,
        false
    )

    CreateSidebarItem(
        sidebar,
        "Visuals",
        "◉",
        194,
        false
    )

    CreateSidebarItem(
        sidebar,
        "Webhook",
        "↗",
        236,
        false
    )

    CreateSidebarItem(
        sidebar,
        "Settings",
        "⚙",
        278,
        false
    )

    --==================================================
    -- SIDEBAR FOOTER
    --==================================================

    local footer =
        CreateLabel(
            sidebar,
            "ZANJIHUB",
            UDim2.new(
                1,
                -20,
                0,
                22
            ),
            UDim2.fromOffset(
                10,
                420
            ),
            Enum.Font.Gotham,
            10,
            COLORS.Muted2
        )

    footer.TextXAlignment =
        Enum.TextXAlignment.Center

    --==================================================
    -- SIDEBAR DIVIDER
    --==================================================

    local divider =
        Instance.new("Frame")

    divider.Position =
        UDim2.fromOffset(
            179,
            0
        )

    divider.Size =
        UDim2.new(
            0,
            1,
            1,
            0
        )

    divider.BackgroundColor3 =
        COLORS.BorderSoft

    divider.BorderSizePixel = 0

    divider.Parent = window

    --==================================================
    -- CONTENT AREA
    --==================================================

    local content =
        Instance.new("Frame")

    content.Position =
        UDim2.fromOffset(
            180,
            0
        )

    content.Size =
        UDim2.new(
            1,
            -180,
            1,
            0
        )

    content.BackgroundTransparency = 1

    content.Parent = window

    --==================================================
    -- TOP HEADER
    --==================================================

    local header =
        Instance.new("Frame")

    header.Position =
        UDim2.fromOffset(
            0,
            0
        )

    header.Size =
        UDim2.new(
            1,
            0,
            0,
            58
        )

    header.BackgroundTransparency = 1

    header.Parent = content

    local headerTitle =
        CreateLabel(
            header,
            "Premium Access",
            UDim2.new(
                1,
                -40,
                0,
                25
            ),
            UDim2.fromOffset(
                16,
                8
            ),
            Enum.Font.Code,
            15,
            COLORS.White
        )

    local headerSubtitle =
        CreateLabel(
            header,
            "Enter your license key to access ZANJIHUB.",
            UDim2.new(
                1,
                -40,
                0,
                20
            ),
            UDim2.fromOffset(
                16,
                31
            ),
            Enum.Font.Code,
            10,
            COLORS.Muted
        )

    CreateLine(
        content,
        UDim2.fromOffset(
            0,
            58
        )
    )

    --==================================================
    -- ACCESS CARD
    --==================================================

    local card =
        Instance.new("Frame")

    card.Position =
        UDim2.fromOffset(
            14,
            72
        )

    card.Size =
        UDim2.new(
            1,
            -28,
            0,
            265
        )

    card.BackgroundColor3 =
        COLORS.Card

    card.BorderSizePixel = 0

    card.Parent = content

    AddCorner(
        card,
        7
    )

    AddStroke(
        card,
        COLORS.Border,
        1,
        0
    )

    --==================================================
    -- CARD TITLE
    --==================================================

    local cardTitle =
        CreateLabel(
            card,
            "🔐  ZANJI PREMIUM LICENSE",
            UDim2.new(
                1,
                -28,
                0,
                28
            ),
            UDim2.fromOffset(
                14,
                10
            ),
            Enum.Font.Code,
            14,
            COLORS.White
        )

    local cardDescription =
        CreateLabel(
            card,
            "Authenticate your account to continue.",
            UDim2.new(
                1,
                -28,
                0,
                20
            ),
            UDim2.fromOffset(
                14,
                35
            ),
            Enum.Font.Code,
            10,
            COLORS.Muted
        )

    CreateLine(
        card,
        UDim2.fromOffset(
            0,
            61
        )
    )

    --==================================================
    -- KEY LABEL
    --==================================================

    local keyLabel =
        CreateLabel(
            card,
            "License Key",
            UDim2.new(
                1,
                -28,
                0,
                20
            ),
            UDim2.fromOffset(
                14,
                72
            ),
            Enum.Font.Code,
            11,
            COLORS.Text
        )

    --==================================================
    -- KEY BOX
    --==================================================

    local keyBox =
        Instance.new("TextBox")

    keyBox.Position =
        UDim2.fromOffset(
            14,
            96
        )

    keyBox.Size =
        UDim2.new(
            1,
            -28,
            0,
            42
        )

    keyBox.BackgroundColor3 =
        COLORS.Input

    keyBox.BorderSizePixel = 0

    keyBox.ClearTextOnFocus = false

    keyBox.Font =
        Enum.Font.Code

    keyBox.PlaceholderText =
        "ZANJI-XXXX-XXXX-XXXX"

    keyBox.PlaceholderColor3 =
        COLORS.Muted2

    keyBox.Text =
        Clean(initialKey):upper()

    keyBox.TextColor3 =
        COLORS.White

    keyBox.TextSize = 13

    keyBox.TextXAlignment =
        Enum.TextXAlignment.Left

    keyBox.Parent = card

    AddCorner(
        keyBox,
        5
    )

    AddStroke(
        keyBox,
        COLORS.BorderSoft,
        1,
        0
    )

    --==================================================
    -- ACTIVATE BUTTON
    --==================================================

    local button =
        Instance.new("TextButton")

    button.Position =
        UDim2.fromOffset(
            14,
            150
        )

    button.Size =
        UDim2.new(
            1,
            -28,
            0,
            40
        )

    button.BackgroundColor3 =
        COLORS.PurpleDark

    button.BorderSizePixel = 0

    button.AutoButtonColor = false

    button.Font =
        Enum.Font.Code

    button.Text =
        "ACTIVATE ZANJI KEY"

    button.TextColor3 =
        COLORS.White

    button.TextSize = 12

    button.Parent = card

    AddCorner(
        button,
        5
    )

    AddStroke(
        button,
        COLORS.Purple,
        1,
        0
    )

    button.MouseEnter:Connect(function()

        if button.Active then

            TweenService:Create(
                button,
                TweenInfo.new(
                    0.12
                ),
                {
                    BackgroundColor3 =
                        COLORS.Purple
                }
            ):Play()
        end
    end)

    button.MouseLeave:Connect(function()

        if button.Active then

            TweenService:Create(
                button,
                TweenInfo.new(
                    0.12
                ),
                {
                    BackgroundColor3 =
                        COLORS.PurpleDark
                }
            ):Play()
        end
    end)

    --==================================================
    -- STATUS BOX
    --==================================================

    local statusBox =
        Instance.new("Frame")

    statusBox.Position =
        UDim2.fromOffset(
            14,
            202
        )

    statusBox.Size =
        UDim2.new(
            1,
            -28,
            0,
            45
        )

    statusBox.BackgroundColor3 =
        Color3.fromRGB(
            9,
            9,
            15
        )

    statusBox.BorderSizePixel = 0

    statusBox.Parent = card

    AddCorner(
        statusBox,
        5
    )

    AddStroke(
        statusBox,
        COLORS.BorderSoft,
        1,
        0
    )

    local statusDot =
        Instance.new("Frame")

    statusDot.Position =
        UDim2.fromOffset(
            10,
            17
        )

    statusDot.Size =
        UDim2.fromOffset(
            8,
            8
        )

    statusDot.BackgroundColor3 =
        COLORS.Purple

    statusDot.BorderSizePixel = 0

    statusDot.Parent = statusBox

    AddCorner(
        statusDot,
        10
    )

    local status =
        CreateLabel(
            statusBox,
            tostring(
                initialMessage
                or "Ready to authenticate."
            ),
            UDim2.new(
                1,
                -32,
                1,
                0
            ),
            UDim2.fromOffset(
                28,
                0
            ),
            Enum.Font.Code,
            10,
            COLORS.Muted
        )

    status.TextTruncate =
        Enum.TextTruncate.AtEnd

    --==================================================
    -- INFORMATION CARDS
    --==================================================

    local info =
        Instance.new("Frame")

    info.Position =
        UDim2.fromOffset(
            14,
            351
        )

    info.Size =
        UDim2.new(
            1,
            -28,
            0,
            66
        )

    info.BackgroundTransparency = 1

    info.Parent = content

    local info1 =
        Instance.new("Frame")

    info1.Size =
        UDim2.new(
            0.5,
            -5,
            1,
            0
        )

    info1.BackgroundColor3 =
        COLORS.Card

    info1.BorderSizePixel = 0

    info1.Parent = info

    AddCorner(
        info1,
        6
    )

    AddStroke(
        info1,
        COLORS.BorderSoft,
        1,
        0
    )

    CreateLabel(
        info1,
        "●  SECURE",
        UDim2.new(
            1,
            -20,
            0,
            24
        ),
        UDim2.fromOffset(
            10,
            7
        ),
        Enum.Font.Code,
        10,
        COLORS.Success
    )

    CreateLabel(
        info1,
        "License verification",
        UDim2.new(
            1,
            -20,
            0,
            20
        ),
        UDim2.fromOffset(
            10,
            30
        ),
        Enum.Font.Code,
        9,
        COLORS.Muted
    )

    local info2 =
        Instance.new("Frame")

    info2.Position =
        UDim2.new(
            0.5,
            5,
            0,
            0
        )

    info2.Size =
        UDim2.new(
            0.5,
            -5,
            1,
            0
        )

    info2.BackgroundColor3 =
        COLORS.Card

    info2.BorderSizePixel = 0

    info2.Parent = info

    AddCorner(
        info2,
        6
    )

    AddStroke(
        info2,
        COLORS.BorderSoft,
        1,
        0
    )

    CreateLabel(
        info2,
        "◈  ZANJI V2",
        UDim2.new(
            1,
            -20,
            0,
            24
        ),
        UDim2.fromOffset(
            10,
            7
        ),
        Enum.Font.Code,
        10,
        COLORS.PurpleBright
    )

    CreateLabel(
        info2,
        "Premium access",
        UDim2.new(
            1,
            -20,
            0,
            20
        ),
        UDim2.fromOffset(
            10,
            30
        ),
        Enum.Font.Code,
        9,
        COLORS.Muted
    )

    --==================================================
    -- DRAGGING
    --==================================================

    local dragging = false
    local dragStart
    local startPosition

    local function UpdateDrag(input)

        local delta =
            input.Position
            - dragStart

        window.Position =
            UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset
                    + delta.X,

                startPosition.Y.Scale,
                startPosition.Y.Offset
                    + delta.Y
            )
    end

    header.InputBegan:Connect(function(input)

        if input.UserInputType ==
            Enum.UserInputType.MouseButton1
        then

            dragging = true

            dragStart =
                input.Position

            startPosition =
                window.Position

            input.Changed:Connect(
                function()

                    if input.UserInputState ==
                        Enum.UserInputState.End
                    then
                        dragging = false
                    end
                end
            )
        end
    end)

    header.InputChanged:Connect(function(input)

        if input.UserInputType ==
            Enum.UserInputType.MouseMovement
        then

            -- handled by global input
        end
    end)

    game:GetService("UserInputService")
        .InputChanged:Connect(function(input)

            if dragging
            and input.UserInputType ==
                Enum.UserInputType.MouseMovement
            then

                UpdateDrag(input)
            end
        end)

    --==================================================
    -- SUBMIT
    --==================================================

    local busy = false

    local function SetStatus(
        text,
        state
    )

        status.Text =
            tostring(text or "")

        if state == "success" then

            status.TextColor3 =
                COLORS.Success

            statusDot.BackgroundColor3 =
                COLORS.Success

        elseif state == "error" then

            status.TextColor3 =
                COLORS.Error

            statusDot.BackgroundColor3 =
                COLORS.Error

        elseif state == "loading" then

            status.TextColor3 =
                COLORS.PurpleBright

            statusDot.BackgroundColor3 =
                COLORS.PurpleBright

        else

            status.TextColor3 =
                COLORS.Muted

            statusDot.BackgroundColor3 =
                COLORS.Purple
        end
    end

    local function submit()

        if busy then
            return
        end

        local key =
            Clean(
                keyBox.Text
            ):upper()

        if key == "" then

            SetStatus(
                "Enter your ZANJI key.",
                "error"
            )

            return
        end

        busy = true

        button.Active = false

        button.Text =
            "AUTHENTICATING..."

        button.BackgroundColor3 =
            COLORS.PurpleDark

        SetStatus(
            "Checking license...",
            "loading"
        )

        task.spawn(function()

            local success, err =
                RunWithKey(key)

            if success then

                SetStatus(
                    "Authenticated. Loading ZANJIHUB...",
                    "success"
                )

                button.Text =
                    "ACCESS GRANTED"

                button.BackgroundColor3 =
                    Color3.fromRGB(
                        35,
                        110,
                        70
                    )

                task.wait(0.15)

                gui:Destroy()

                return
            end

            busy = false

            button.Active = true

            button.Text =
                "ACTIVATE ZANJI KEY"

            button.BackgroundColor3 =
                COLORS.PurpleDark

            SetStatus(
                tostring(err),
                "error"
            )

            warn(
                "[ZANJI]",
                tostring(err)
            )
        end)
    end

    button.MouseButton1Click:Connect(
        submit
    )

    keyBox.FocusLost:Connect(
        function(enterPressed)

            if enterPressed then
                submit()
            end
        end
    )

    --==================================================
    -- WINDOW FADE IN
    --==================================================

    window.BackgroundTransparency = 1

    task.spawn(function()

        TweenService:Create(
            window,
            TweenInfo.new(
                0.18,
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.Out
            ),
            {
                BackgroundTransparency = 0
            }
        ):Play()
    end)
end

--==================================================
-- START LOADER
--==================================================

local savedKey =
    ReadSavedKey()

if savedKey ~= "" then

    local success, err =
        RunWithKey(savedKey)

    if success then
        return
    end

    warn(
        "[ZANJI] Saved key failed:",
        tostring(err)
    )

    CreateKeyWindow(
        savedKey,
        tostring(err)
    )

    return
end

CreateKeyWindow(
    "",
    "Ready to authenticate."
)
