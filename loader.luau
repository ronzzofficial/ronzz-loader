--==================================================
-- ZANJI PUBLIC LOADER - LIVE SESSION REFRESH v3
-- Put this file in your public GitHub repository.
-- The actual ZANJI source is never stored in this file.
--==================================================

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer =
    Players.LocalPlayer
    or Players.PlayerAdded:Wait()

--==================================================
-- LEGACY ALLOWED PLACE IDS
--==================================================

local LEGACY_ALLOWED_PLACE_IDS = {
    [126884695634066] =
        true,

    [129954712878723] =
        true,
}

--==================================================
-- ENVIRONMENT
--==================================================

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

--==================================================
-- EXECUTE ONCE PER JOB
-- Clears a stopped/expired/paused runtime so the
-- loader can be executed again without rejoining.
--==================================================

local existingLoaderRuntime =
    Environment.ZANJI_LOADER_RUNTIME

local existingRuntimeRoot =
    Environment.ZANJI_RUNTIME_ROOT
    or _G.ZANJI_RUNTIME_ROOT

if type(existingLoaderRuntime) == "table"
and existingLoaderRuntime.JobId == game.JobId
and existingLoaderRuntime.Loaded == true then

    local existingSession =
        Environment.ZANJI_AUTH_SESSION
        or _G.ZANJI_AUTH_SESSION

    local authorizationGone =
        Environment.ZANJI_LOADER_AUTHORIZED ~= true

    local sessionGone =
        type(existingSession) ~= "table"
        or type(existingSession.Token) ~= "string"
        or existingSession.Token == ""

    local licenseRuntimeDead =
        type(existingRuntimeRoot) == "table"
        and existingRuntimeRoot.LicenseValid == false

    if authorizationGone
    or sessionGone
    or licenseRuntimeDead then

        Environment.ZANJI_LOADER_RUNTIME = nil
        _G.ZANJI_LOADER_RUNTIME = nil

        existingLoaderRuntime = nil
    end
end

if type(existingLoaderRuntime) == "table"
and existingLoaderRuntime.JobId == game.JobId
and (
    existingLoaderRuntime.Loading == true
    or existingLoaderRuntime.Loaded == true
) then

    warn(
        "[ZANJI]",
        "ZANJI is already loading or loaded.",
        "Channel:",
        tostring(
            existingLoaderRuntime.Channel
            or "unknown"
        )
    )

    return
end

Environment.ZANJI_LOADER_RUNTIME = {
    JobId = game.JobId,
    Loading = true,
    Loaded = false,
    Channel = "public",
}

local API =
    "https://zanji-license-api.ronzz191002.workers.dev"

local PRODUCT =
    "zanji_v2"

local SOURCE_ROUTE =
    "/v1/source/zanji_v2"

local VALIDATE_ROUTE =
    "/v1/license/validate"

local WHITELIST_ACTIVATE_ROUTE =
    "/v1/whitelist/activate"

local CONFIG_ROUTE =
    "/v1/config/zanji_v2"

local USAGE_TRACK_ROUTE =
    "/v1/usage/track"

local KEY_FILE =
    "ZanjiHub_Key.txt"

-- This value comes from the Worker. Do not change it in a public loader;
-- set the Worker variable ZANJI_KEY_SYSTEM_ENABLED instead.
local ZANJI_KEY_SYSTEM_ENABLED =
    true

local ZANJI_ACCESS_MODE =
    "key"

--==================================================
-- CLEAN
--==================================================

local function Clean(value)
    return tostring(value or "")
        :gsub("^%s+", "")
        :gsub("%s+$", "")
end

--==================================================
-- REQUEST
--==================================================

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

    local requestFunction =
        GetRequestFunction()

    if type(requestFunction) ~= "function" then

        return nil,
            "Your executor does not support request/http_request."
    end

    local ok, response =
        pcall(
            requestFunction,
            options
        )

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

    local success =
        response.Success

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

--==================================================
-- JSON
--==================================================

local function DecodeJson(body)

    if type(body) ~= "string"
    or body == "" then

        return nil
    end

    local ok, result =
        pcall(function()

            return HttpService:
                JSONDecode(body)
        end)

    if ok
    and type(result) == "table" then

        return result
    end

    return nil
end

--==================================================
-- RELEASE MODE
--==================================================

local function FetchAccessMode()

    local response, requestError =
        SendRequest({

            Url =
                API
                .. CONFIG_ROUTE,

            Method = "GET",

            Headers = {
                ["Accept"] =
                    "application/json",

                ["Accept-Encoding"] =
                    "identity",

                ["Cache-Control"] =
                    "no-cache",
            },
        })

    if not response then
        return nil,
            "Could not read the ZANJI release mode: "
            .. tostring(requestError)
    end

    local decoded =
        DecodeJson(
            response.Body
        )

    if not response.Success
    or type(decoded) ~= "table"
    or type(decoded.keySystemEnabled) ~= "boolean" then

        return nil,
            "Could not read the ZANJI release mode (HTTP "
            .. tostring(
                response.StatusCode
            )
            .. ")."
    end

    local mode =
        Clean(decoded.accessMode):lower()

    if mode ~= "whitelist"
    and mode ~= "key"
    and mode ~= "public" then
        mode = decoded.keySystemEnabled
            and "key"
            or "public"
    end

    return decoded.keySystemEnabled,
        nil,
        mode
end

--==================================================
-- KEY FILE
--==================================================

local function ReadSavedKey()

    if type(readfile) ~= "function" then
        return ""
    end

    local ok, value =
        pcall(
            readfile,
            KEY_FILE
        )

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

local function FormatApiError(
    decoded,
    fallback
)

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

        whitelist_not_found =
            "This Roblox account is not whitelisted. Complete payment using your exact username.",

        whitelist_not_activated =
            "Your paid access is waiting for activation. Execute the loader again.",

        whitelist_expired =
            "Your ZANJI whitelist access has expired.",

        whitelist_revoked =
            "Your ZANJI whitelist access was revoked.",

        whitelist_mode_disabled =
            "Whitelist mode is currently unavailable.",

        product_not_allowed =
            "This key cannot access ZanjiHub.",

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
-- ACTIVATE KEY
--==================================================

local function ActivateKey(key)

    key =
        Clean(key):upper()

    if key == "" then

        return nil,
            "Enter your ZANJI Premium key."
    end

    local body =
        HttpService:JSONEncode({

            Key = key,

            Product = PRODUCT,

            RobloxUserId =
                tonumber(
                    LocalPlayer.UserId
                ) or 0,

            RobloxUsername =
                tostring(
                    LocalPlayer.Name
                ),

            PlaceId =
                tostring(
                    game.PlaceId
                ),

            UniverseId =
                tostring(
                    game.GameId
                ),
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
        DecodeJson(
            response.Body
        )

    if not response.Success
    or type(decoded) ~= "table"
    or decoded.ok ~= true then

        return nil,
            FormatApiError(
                decoded,

                "Activation failed with HTTP "
                .. tostring(
                    response.StatusCode
                )
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
-- ACTIVATE WHITELIST
--==================================================

local function ActivateWhitelist()
    local body =
        HttpService:JSONEncode({
            Product = PRODUCT,
            RobloxUserId =
                tostring(LocalPlayer.UserId),
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
                .. WHITELIST_ACTIVATE_ROUTE,
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
            "Whitelist check failed: "
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
                "Whitelist check failed with HTTP "
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
            "The whitelist service returned no access token."
    end

    return {
        Token = token,
        Activation = decoded,
    }
end

--==================================================
-- DOWNLOAD SOURCE
--==================================================

local function DownloadSource(session)

    local headers = {
        ["X-Zanji-Place-Id"] =
            tostring(
                game.PlaceId
            ),

        ["Accept"] =
            "text/plain",

        ["Accept-Encoding"] =
            "identity",

        ["Cache-Control"] =
            "no-cache",
    }

    if ZANJI_KEY_SYSTEM_ENABLED then
        headers["Authorization"] =
            "Bearer "
            .. tostring(
                session
                and session.Token
                or ""
            )
    end

    local response, requestError =
        SendRequest({

            Url =
                API
                .. SOURCE_ROUTE,

            Method = "GET",

            Headers = headers,
        })

    if not response then

        return nil,
            "Source request failed: "
            .. tostring(requestError)
    end

    if not response.Success then

        return nil,
            FormatApiError(
                DecodeJson(
                    response.Body
                ),

                "Source request failed with HTTP "
                .. tostring(
                    response.StatusCode
                )
            )
    end

    local source =
        tostring(
            response.Body
            or ""
        )

    if source == "" then

        return nil,
            "The private source was empty."
    end

    local marker =
        "-- ZANJI PRIVATE SOURCE"

    if source:sub(
        1,
        #marker
    ) ~= marker then

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

local loadedKeySystemMode,
    keySystemModeError,
    loadedAccessMode =
    FetchAccessMode()

if type(loadedKeySystemMode) ~= "boolean" then

    Environment.ZANJI_LOADER_RUNTIME = {
        JobId = game.JobId,
        Loading = false,
        Loaded = false,
        Channel = "public",
    }

    _G.ZANJI_LOADER_RUNTIME =
        Environment.ZANJI_LOADER_RUNTIME

    warn(
        "[ZANJI]",
        tostring(
            keySystemModeError
            or "Unable to determine the release mode."
        )
    )

    return
end

ZANJI_KEY_SYSTEM_ENABLED =
    loadedKeySystemMode

ZANJI_ACCESS_MODE =
    tostring(
        loadedAccessMode
        or (
            loadedKeySystemMode
            and "key"
            or "public"
        )
    )

Environment.ZANJI_ACCESS_MODE =
    ZANJI_ACCESS_MODE

_G.ZANJI_ACCESS_MODE =
    ZANJI_ACCESS_MODE

Environment.ZANJI_KEY_SYSTEM_ENABLED =
    ZANJI_KEY_SYSTEM_ENABLED

_G.ZANJI_KEY_SYSTEM_ENABLED =
    ZANJI_KEY_SYSTEM_ENABLED

--==================================================
-- PUBLIC USAGE TRACKING
-- Records one best-effort launch in D1 when the release is public.
-- Tracking failures never prevent ZANJI from loading.
--==================================================

local function TrackPublicUsage()

    if ZANJI_KEY_SYSTEM_ENABLED then
        return true
    end

    local body =
        HttpService:JSONEncode({
            RobloxUserId =
                tostring(
                    LocalPlayer.UserId
                ),

            RobloxUsername =
                tostring(
                    LocalPlayer.Name
                ),

            PlaceId =
                tostring(
                    game.PlaceId
                ),
        })

    local response =
        SendRequest({

            Url =
                API
                .. USAGE_TRACK_ROUTE,

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

    return response ~= nil
    and response.Success == true
end

--==================================================
-- REFRESH LIVE SESSION
--
-- The Worker lease is short-lived. Source download can consume part of
-- that lease, especially when GitHub is slow. Refresh the token AFTER
-- the source has downloaded so the private source always starts with a
-- fresh lease.
--==================================================

local function RefreshLiveSession(session)

    if type(session) ~= "table"
    or Clean(session.Token) == "" then

        return false,
            "Live session token is missing."
    end

    local response,
        requestError =
        SendRequest({

            Url =
                API
                .. VALIDATE_ROUTE,

            Method = "POST",

            Headers = {
                ["Authorization"] =
                    "Bearer "
                    .. tostring(
                        session.Token
                    ),

                ["Content-Type"] =
                    "application/json",

                ["Accept"] =
                    "application/json",

                ["Accept-Encoding"] =
                    "identity",

                ["Cache-Control"] =
                    "no-cache",
            },

            Body = "{}",
        })

    if not response then
        return false,
            "Session refresh failed: "
            .. tostring(requestError)
    end

    local decoded =
        DecodeJson(
            response.Body
        )

    if not response.Success
    or type(decoded) ~= "table"
    or decoded.ok ~= true then

        return false,
            FormatApiError(
                decoded,
                "Session refresh failed with HTTP "
                    .. tostring(
                        response.StatusCode
                    )
            )
    end

    local newToken =
        Clean(
            decoded.accessToken
            or decoded.access_token
            or decoded.token
        )

    if newToken == "" then
        return false,
            "Session refresh returned no access token."
    end

    session.Token =
        newToken

    session.Activation =
        session.Activation
        or {}

    if tonumber(decoded.expiresAt) then
        session.Activation.expiresAt =
            tonumber(decoded.expiresAt)
    end

    if decoded.lifetime ~= nil then
        session.Activation.lifetime =
            decoded.lifetime == true
    end

    if tonumber(decoded.heartbeatSeconds) then
        session.Activation.heartbeatSeconds =
            tonumber(decoded.heartbeatSeconds)
    end

    return true
end

--==================================================
-- INSTALL AUTH
--==================================================

local function InstallAuth(session)

    local activation =
        session.Activation
        or {}

    local features = {}

    if type(
        activation.features
    ) == "table" then

        for name, enabled
        in pairs(
            activation.features
        ) do

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

    Environment.ZANJI_LOADER_LIFETIME =
        activation.lifetime == true

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

    -- Keep the short-lived access token only in memory so the
    -- private source can continuously validate expiration while
    -- the user stays in the same Roblox server.
    local authSession = {
        Token = tostring(session.Token or ""),
        API = API,
        ValidateRoute = VALIDATE_ROUTE,
        Product = PRODUCT,
        JobId = tostring(game.JobId),
        LastValidationAt = os.clock(),
        HeartbeatSeconds =
            math.max(
                60,
                tonumber(activation.heartbeatSeconds)
                or 1800
            ),
        Lifetime =
            Environment.ZANJI_LOADER_LIFETIME,
    }

    Environment.ZANJI_AUTH_SESSION =
        authSession

    _G.ZANJI_AUTH_SESSION =
        authSession

    _G.ZANJI_LOADER_AUTHORIZED =
        true

    _G.ZANJI_LOADER_OWNER =
        Environment.ZANJI_LOADER_OWNER

    _G.ZANJI_LOADER_PLAN =
        Environment.ZANJI_LOADER_PLAN

    _G.ZANJI_LOADER_EXPIRES_AT =
        Environment.ZANJI_LOADER_EXPIRES_AT

    _G.ZANJI_LOADER_LIFETIME =
        Environment.ZANJI_LOADER_LIFETIME

    _G.ZANJI_LOADER_MAX_ACCOUNTS =
        Environment.ZANJI_LOADER_MAX_ACCOUNTS

    _G.ZANJI_LOADER_SLOTS_USED =
        Environment.ZANJI_LOADER_SLOTS_USED

    _G.ZANJI_LOADER_FEATURES =
        features
end

local function InstallPublicMode()

    Environment.ZANJI_KEY_SYSTEM_ENABLED =
        false

    _G.ZANJI_KEY_SYSTEM_ENABLED =
        false

    Environment.ZANJI_LOADER_AUTHORIZED =
        false

    _G.ZANJI_LOADER_AUTHORIZED =
        false

    Environment.ZANJI_AUTH_SESSION = nil
    _G.ZANJI_AUTH_SESSION = nil

    Environment.ZANJI_LOADER_OWNER =
        "Public"

    Environment.ZANJI_LOADER_PLAN =
        "public"

    Environment.ZANJI_LOADER_EXPIRES_AT =
        0

    Environment.ZANJI_LOADER_MAX_ACCOUNTS =
        0

    Environment.ZANJI_LOADER_SLOTS_USED =
        0

    Environment.ZANJI_LOADER_FEATURES =
        {}

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
        Environment.ZANJI_LOADER_FEATURES
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
            .. tostring(
                runError
            )
    end

    return true
end

--==================================================
-- RUN WITH KEY
--==================================================

local function RunWithKey(key)

    local session, activationError =
        ActivateKey(key)

    if not session then

        return false,
            activationError
    end

    local source, sourceError =
        DownloadSource(session)

    -- IMPORTANT: do not erase session.Token here.
    -- The private source uses it for the live expiration heartbeat.

    if not source then

        return false,
            sourceError
    end

    -- Source delivery may take long enough to consume most of the
    -- short-lived Worker lease. Refresh it now, immediately before
    -- installing auth and starting the private source.
    local refreshed,
        refreshError =
        RefreshLiveSession(
            session
        )

    if not refreshed then

        -- If the lease already expired during source delivery, the key
        -- itself may still be perfectly valid. Reactivate once to obtain
        -- a fresh lease instead of starting ZANJI with a dead token.
        local replacementSession,
            replacementError =
            ActivateKey(
                key
            )

        if not replacementSession then
            return false,
                replacementError
                or refreshError
                or "Unable to refresh the ZANJI session."
        end

        session =
            replacementSession
    end

    InstallAuth(session)

    SaveKey(key)

    local success, errorMessage =
        CompileAndRun(source)

    if success then

        Environment.ZANJI_LOADER_RUNTIME = {
            JobId = game.JobId,
            Loading = false,
            Loaded = true,
            Channel = "public",
        }

    else

        -- A failed private-source execution must not leave an
        -- authorized session behind.
        Environment.ZANJI_AUTH_SESSION = nil
        _G.ZANJI_AUTH_SESSION = nil
        Environment.ZANJI_LOADER_AUTHORIZED = false
        _G.ZANJI_LOADER_AUTHORIZED = false

        -- Allow retry if loading failed.
        Environment.ZANJI_LOADER_RUNTIME = {
            JobId = game.JobId,
            Loading = false,
            Loaded = false,
            Channel = "public",
        }
    end

    return success, errorMessage
end

--==================================================
-- RUN WITH WHITELIST
--==================================================

local function RunWithWhitelist()
    local session, activationError =
        ActivateWhitelist()

    if not session then
        return false,
            activationError
    end

    local source, sourceError =
        DownloadSource(session)

    if not source then
        return false,
            sourceError
    end

    local refreshed, refreshError =
        RefreshLiveSession(session)

    if not refreshed then
        local replacementSession,
            replacementError =
            ActivateWhitelist()

        if not replacementSession then
            return false,
                replacementError
                or refreshError
                or "Unable to refresh the ZANJI whitelist session."
        end

        session = replacementSession
    end

    InstallAuth(session)

    local success, errorMessage =
        CompileAndRun(source)

    if success then
        Environment.ZANJI_LOADER_RUNTIME = {
            JobId = game.JobId,
            Loading = false,
            Loaded = true,
            Channel = "whitelist",
        }
    else
        Environment.ZANJI_AUTH_SESSION = nil
        _G.ZANJI_AUTH_SESSION = nil
        Environment.ZANJI_LOADER_AUTHORIZED = false
        _G.ZANJI_LOADER_AUTHORIZED = false

        Environment.ZANJI_LOADER_RUNTIME = {
            JobId = game.JobId,
            Loading = false,
            Loaded = false,
            Channel = "whitelist",
        }
    end

    _G.ZANJI_LOADER_RUNTIME =
        Environment.ZANJI_LOADER_RUNTIME

    return success, errorMessage
end

--==================================================
-- RUN WITHOUT KEY
--==================================================

local function RunWithoutKey()

    local source, sourceError =
        DownloadSource(nil)

    if not source then
        return false,
            sourceError
    end

    InstallPublicMode()

    TrackPublicUsage()

    local success, errorMessage =
        CompileAndRun(source)

    Environment.ZANJI_LOADER_RUNTIME = {
        JobId = game.JobId,
        Loading = false,
        Loaded = success == true,
        Channel = "public-no-key",
    }

    _G.ZANJI_LOADER_RUNTIME =
        Environment.ZANJI_LOADER_RUNTIME

    return success, errorMessage
end

--==================================================
-- UI PARENT
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
        WaitForChild(
            "PlayerGui"
        )
end

--==================================================
-- UI CORNER
--==================================================

local ZANJI_UI = {
    Background = Color3.fromRGB(5, 9, 15),
    Surface = Color3.fromRGB(8, 14, 23),
    Field = Color3.fromRGB(10, 18, 29),
    Border = Color3.fromRGB(38, 56, 77),
    Accent = Color3.fromRGB(39, 140, 255),
    AccentHover = Color3.fromRGB(62, 154, 255),
    Text = Color3.fromRGB(232, 237, 245),
    Muted = Color3.fromRGB(135, 147, 163),
}

local function AddCorner(
    instance,
    radius
)

    local corner =
        Instance.new(
            "UICorner"
        )

    corner.CornerRadius =
        UDim.new(
            0,
            radius
        )

    corner.Parent =
        instance
end

local function AddStroke(
    instance,
    color,
    thickness,
    transparency
)
    local stroke = Instance.new("UIStroke")
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Color = color or ZANJI_UI.Border
    stroke.Thickness = thickness or 1
    stroke.Transparency = transparency or 0
    stroke.Parent = instance
    return stroke
end

--==================================================
-- KEY WINDOW
--==================================================

local function CreateKeyWindow(
    initialKey,
    initialMessage
)

    local parent =
        GetUiParent()

    local old =
        parent:FindFirstChild(
            "ZANJI_Public_Key_UI"
        )

    if old then
        old:Destroy()
    end

    local gui =
        Instance.new(
            "ScreenGui"
        )

    gui.Name =
        "ZANJI_Public_Key_UI"

    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 999999

    gui.Parent =
        parent

    --==================================================
    -- WINDOW
    --==================================================

    local window =
        Instance.new(
            "Frame"
        )

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
            470,
            275
        )

    window.BackgroundColor3 =
        ZANJI_UI.Surface

    window.BorderSizePixel = 0
    window.Active = true
    window.Draggable = true
    window.ClipsDescendants = true

    window.Parent =
        gui

    AddCorner(
        window,
        9
    )

    AddStroke(window, ZANJI_UI.Border, 1, 0.05)

    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 68)
    header.BackgroundColor3 = ZANJI_UI.Background
    header.BorderSizePixel = 0
    header.Parent = window

    local headerDivider = Instance.new("Frame")
    headerDivider.Name = "Divider"
    headerDivider.Position = UDim2.new(0, 0, 1, -1)
    headerDivider.Size = UDim2.new(1, 0, 0, 1)
    headerDivider.BackgroundColor3 = ZANJI_UI.Border
    headerDivider.BorderSizePixel = 0
    headerDivider.Parent = header

    local accent = Instance.new("Frame")
    accent.Name = "Accent"
    accent.Position = UDim2.fromOffset(18, 20)
    accent.Size = UDim2.fromOffset(3, 27)
    accent.BackgroundColor3 = ZANJI_UI.Accent
    accent.BorderSizePixel = 0
    accent.Parent = header
    AddCorner(accent, 2)

    local secureLabel = Instance.new("TextLabel")
    secureLabel.Name = "SecureLabel"
    secureLabel.AnchorPoint = Vector2.new(1, 0.5)
    secureLabel.Position = UDim2.new(1, -20, 0.5, 0)
    secureLabel.Size = UDim2.fromOffset(112, 26)
    secureLabel.BackgroundColor3 = ZANJI_UI.Field
    secureLabel.BorderSizePixel = 0
    secureLabel.Font = Enum.Font.GothamMedium
    secureLabel.Text = "SECURE ACCESS"
    secureLabel.TextColor3 = ZANJI_UI.Accent
    secureLabel.TextSize = 11
    secureLabel.Parent = header
    AddCorner(secureLabel, 5)
    AddStroke(secureLabel, ZANJI_UI.Border, 1, 0.15)

    --==================================================
    -- TITLE
    --==================================================

    local title =
        Instance.new(
            "TextLabel"
        )

    title.Position =
        UDim2.fromOffset(
            31,
            13
        )

    title.Size =
        UDim2.new(
            1,
            -170,
            0,
            24
        )

    title.BackgroundTransparency = 1

    title.Font =
        Enum.Font.GothamBold

    title.Text =
        "ZANJIHUB PREMIUM ACCESS"

    title.TextColor3 =
        ZANJI_UI.Text

    title.TextSize = 18

    title.TextXAlignment =
        Enum.TextXAlignment.Left

    title.Parent =
        header

    local titleHint = Instance.new("TextLabel")
    titleHint.Position = UDim2.fromOffset(31, 37)
    titleHint.Size = UDim2.new(1, -190, 0, 17)
    titleHint.BackgroundTransparency = 1
    titleHint.Font = Enum.Font.Gotham
    titleHint.Text = "License authentication"
    titleHint.TextColor3 = ZANJI_UI.Muted
    titleHint.TextSize = 11
    titleHint.TextXAlignment = Enum.TextXAlignment.Left
    titleHint.Parent = header

    --==================================================
    -- SUBTITLE
    --==================================================

    local subtitle =
        Instance.new(
            "TextLabel"
        )

    subtitle.Position =
        UDim2.fromOffset(
            24,
            80
        )

    subtitle.Size =
        UDim2.new(
            1,
            -48,
            0,
            32
        )

    subtitle.BackgroundTransparency = 1

    subtitle.Font =
        Enum.Font.Gotham

    subtitle.Text =
        "Enter your ZANJI key. A valid key is saved automatically."

    subtitle.TextColor3 =
        ZANJI_UI.Muted

    subtitle.TextSize = 13

    subtitle.TextWrapped = true

    subtitle.TextXAlignment =
        Enum.TextXAlignment.Left

    subtitle.Parent =
        window

    --==================================================
    -- KEY BOX
    --==================================================

    local keyBox =
        Instance.new(
            "TextBox"
        )

    keyBox.Position =
        UDim2.fromOffset(
            24,
            116
        )

    keyBox.Size =
        UDim2.new(
            1,
            -48,
            0,
            44
        )

    keyBox.BackgroundColor3 =
        ZANJI_UI.Field

    keyBox.BorderSizePixel = 0

    keyBox.ClearTextOnFocus = false

    keyBox.Font =
        Enum.Font.Code

    keyBox.PlaceholderText =
        "ZANJI-XXXX-XXXX-XXXX"

    keyBox.PlaceholderColor3 =
        ZANJI_UI.Muted

    keyBox.Text =
        Clean(
            initialKey
        ):upper()

    keyBox.TextColor3 =
        ZANJI_UI.Text

    keyBox.TextSize = 15

    keyBox.Parent =
        window

    AddCorner(
        keyBox,
        6
    )

    local keyBoxStroke = AddStroke(keyBox, ZANJI_UI.Border, 1, 0.05)

    keyBox.Focused:Connect(function()
        keyBoxStroke.Color = ZANJI_UI.Accent
        keyBoxStroke.Transparency = 0
    end)

    keyBox.FocusLost:Connect(function()
        keyBoxStroke.Color = ZANJI_UI.Border
        keyBoxStroke.Transparency = 0.05
    end)

    --==================================================
    -- BUTTON
    --==================================================

    local button =
        Instance.new(
            "TextButton"
        )

    button.Position =
        UDim2.fromOffset(
            24,
            172
        )

    button.Size =
        UDim2.new(
            1,
            -48,
            0,
            42
        )

    button.BackgroundColor3 =
        ZANJI_UI.Accent

    button.BorderSizePixel = 0

    button.Font =
        Enum.Font.GothamBold

    button.Text =
        "ACTIVATE ZANJI KEY"

    button.TextColor3 =
        Color3.fromRGB(
            255,
            255,
            255
        )

    button.TextSize = 14

    button.Parent =
        window

    AddCorner(
        button,
        6
    )

    AddStroke(button, Color3.fromRGB(94, 176, 255), 1, 0.35)

    button.MouseEnter:Connect(function()
        if button.Active then
            button.BackgroundColor3 = ZANJI_UI.AccentHover
        end
    end)

    button.MouseLeave:Connect(function()
        button.BackgroundColor3 = ZANJI_UI.Accent
    end)

    --==================================================
    -- STATUS
    --==================================================

    local status =
        Instance.new(
            "TextLabel"
        )

    status.Position =
        UDim2.fromOffset(
            24,
            225
        )

    status.Size =
        UDim2.new(
            1,
            -48,
            0,
            24
        )

    status.BackgroundTransparency = 1

    status.Font =
        Enum.Font.Gotham

    status.Text =
        tostring(
            initialMessage
            or ""
        )

    status.TextColor3 =
        ZANJI_UI.Muted

    status.TextSize = 12

    status.TextTruncate =
        Enum.TextTruncate.AtEnd

    status.TextXAlignment =
        Enum.TextXAlignment.Left

    status.Parent =
        window

    --==================================================
    -- SUBMIT
    --==================================================

    local busy = false

    local function submit()

        if busy then
            return
        end

        local key =
            Clean(
                keyBox.Text
            ):upper()

        if key == "" then

            status.Text =
                "Enter your ZANJI key."

            return
        end

        busy = true

        button.Active = false

        button.Text =
            "AUTHENTICATING..."

        status.Text =
            "Checking license..."

        task.spawn(function()

            local success, err =
                RunWithKey(key)

            if success then

                status.Text =
                    "Authenticated. Loading ZANJI..."

                task.wait(0.1)

                gui:Destroy()

                return
            end

            busy = false

            button.Active = true

            button.Text =
                "ACTIVATE ZANJI KEY"

            status.Text =
                tostring(err)

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
end


local function CreateWhitelistWindow(initialMessage)
    local parent = GetUiParent()
    local old =
        parent:FindFirstChild(
            "ZANJI_Whitelist_UI"
        )

    if old then
        old:Destroy()
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "ZANJI_Whitelist_UI"
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 999999
    gui.Parent = parent

    local window = Instance.new("Frame")
    window.AnchorPoint = Vector2.new(0.5, 0.5)
    window.Position = UDim2.fromScale(0.5, 0.5)
    window.Size = UDim2.fromOffset(440, 205)
    window.BackgroundColor3 = ZANJI_UI.Surface
    window.BorderSizePixel = 0
    window.Active = true
    window.Draggable = true
    window.Parent = gui
    AddCorner(window, 9)
    AddStroke(window, ZANJI_UI.Border, 1, 0.05)

    local title = Instance.new("TextLabel")
    title.Position = UDim2.fromOffset(22, 18)
    title.Size = UDim2.new(1, -44, 0, 24)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.Text = "ZANJIHUB WHITELIST ACCESS"
    title.TextColor3 = ZANJI_UI.Text
    title.TextSize = 17
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = window

    local account = Instance.new("TextLabel")
    account.Position = UDim2.fromOffset(22, 47)
    account.Size = UDim2.new(1, -44, 0, 20)
    account.BackgroundTransparency = 1
    account.Font = Enum.Font.Gotham
    account.Text = "Roblox account: @" .. tostring(LocalPlayer.Name)
    account.TextColor3 = ZANJI_UI.Muted
    account.TextSize = 12
    account.TextXAlignment = Enum.TextXAlignment.Left
    account.Parent = window

    local status = Instance.new("TextLabel")
    status.Position = UDim2.fromOffset(22, 76)
    status.Size = UDim2.new(1, -44, 0, 50)
    status.BackgroundTransparency = 1
    status.Font = Enum.Font.Gotham
    status.Text = tostring(
        initialMessage
        or "Complete PayMongo payment using your exact Roblox username."
    )
    status.TextColor3 = ZANJI_UI.Muted
    status.TextSize = 12
    status.TextWrapped = true
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextYAlignment = Enum.TextYAlignment.Top
    status.Parent = window

    local button = Instance.new("TextButton")
    button.Position = UDim2.fromOffset(22, 143)
    button.Size = UDim2.new(1, -44, 0, 40)
    button.BackgroundColor3 = ZANJI_UI.Accent
    button.BorderSizePixel = 0
    button.Font = Enum.Font.GothamBold
    button.Text = "CHECK WHITELIST AGAIN"
    button.TextColor3 = Color3.fromRGB(255, 255, 255)
    button.TextSize = 13
    button.Parent = window
    AddCorner(button, 6)

    local busy = false

    button.MouseButton1Click:Connect(function()
        if busy then
            return
        end

        busy = true
        button.Active = false
        button.Text = "CHECKING..."
        status.Text = "Checking paid whitelist access..."

        task.spawn(function()
            local success, err =
                RunWithWhitelist()

            if success then
                status.Text = "Access confirmed. Loading ZANJI..."
                task.wait(0.1)
                gui:Destroy()
                return
            end

            busy = false
            button.Active = true
            button.Text = "CHECK WHITELIST AGAIN"
            status.Text = tostring(err)
        end)
    end)
end


--==================================================
-- AUTO RE-EXECUTE / REOPEN KEY UI
-- Called by the private source after a live license
-- becomes expired or paused.
--
-- Behavior:
-- 1. Retry the saved key one time.
-- 2. If still expired/paused, open the normal key UI.
-- 3. If the key was renewed/unpaused already, ZANJI loads again.
--==================================================

local ZanjiAutoReexecuteBusy =
    false

local function ResetLoaderRuntimeForRetry(stopReason)

    local runtime = {
        JobId = game.JobId,
        Loading = false,
        Loaded = false,
        Channel = "public",
        StopReason = tostring(stopReason or ""),
    }

    Environment.ZANJI_LOADER_RUNTIME =
        runtime

    _G.ZANJI_LOADER_RUNTIME =
        runtime
end

local function ReexecutePublicLoader(
    stopReason,
    fallbackMessage
)

    if ZanjiAutoReexecuteBusy then
        return false,
            "ZANJI key UI is already reopening."
    end

    ZanjiAutoReexecuteBusy =
        true

    if ZANJI_ACCESS_MODE == "whitelist" then
        ResetLoaderRuntimeForRetry(
            stopReason
        )

        local success, err =
            RunWithWhitelist()

        ZanjiAutoReexecuteBusy =
            false

        if success then
            return true
        end

        local message =
            tostring(
                err
                or fallbackMessage
                or "ZANJI whitelist access is unavailable."
            )

        CreateWhitelistWindow(message)

        return false,
            message
    end

    if not ZANJI_KEY_SYSTEM_ENABLED then

        ResetLoaderRuntimeForRetry(
            stopReason
        )

        local success, err =
            RunWithoutKey()

        ZanjiAutoReexecuteBusy =
            false

        if success then
            return true
        end

        return false,
            tostring(
                err
                or fallbackMessage
                or "Unable to load the public ZANJI build."
            )
    end

    -- Make sure a dead private runtime cannot trigger the
    -- loader's "already loading or loaded" guard.
    ResetLoaderRuntimeForRetry(
        stopReason
    )

    local savedKey =
        ReadSavedKey()

    if savedKey ~= "" then

        local loadingRuntime = {
            JobId = game.JobId,
            Loading = true,
            Loaded = false,
            Channel = "public",
            StopReason = tostring(stopReason or ""),
        }

        Environment.ZANJI_LOADER_RUNTIME =
            loadingRuntime

        _G.ZANJI_LOADER_RUNTIME =
            loadingRuntime

        local success, err =
            RunWithKey(
                savedKey
            )

        if success then

            ZanjiAutoReexecuteBusy =
                false

            return true
        end

        -- Activation/source failed. Unlock the loader so the
        -- user can press ACTIVATE again after renewal/unpause.
        ResetLoaderRuntimeForRetry(
            stopReason
        )

        local message =
            tostring(
                err
                or fallbackMessage
                or "ZANJI access is unavailable."
            )

        CreateKeyWindow(
            savedKey,
            message
        )

        ZanjiAutoReexecuteBusy =
            false

        return false,
            message
    end

    ResetLoaderRuntimeForRetry(
        stopReason
    )

    CreateKeyWindow(
        "",
        tostring(
            fallbackMessage
            or "Paste your ZANJI Premium key to continue."
        )
    )

    ZanjiAutoReexecuteBusy =
        false

    return false,
        tostring(
            fallbackMessage
            or "No saved key."
        )
end

-- Keep this closure alive after the public loader chunk finishes.
-- Both split private builds can call it without downloading the
-- public loader script again.
Environment.ZANJI_REEXECUTE_PUBLIC_LOADER =
    ReexecutePublicLoader

_G.ZANJI_REEXECUTE_PUBLIC_LOADER =
    ReexecutePublicLoader

--==================================================
-- START
--==================================================

if ZANJI_ACCESS_MODE == "whitelist" then
    local success, err =
        RunWithWhitelist()

    if success then
        return
    end

    warn(
        "[ZANJI] Whitelist check failed:",
        tostring(err)
    )

    CreateWhitelistWindow(
        tostring(err)
    )

    return
end

if not ZANJI_KEY_SYSTEM_ENABLED then

    local success, err =
        RunWithoutKey()

    if not success then
        warn(
            "[ZANJI] Public build failed:",
            tostring(err)
        )
    end

    return
end

local savedKey =
    ReadSavedKey()

if savedKey ~= "" then

    local success, err =
        RunWithKey(
            savedKey
        )

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
    "Paste your ZANJI Premium key to continue."
)
