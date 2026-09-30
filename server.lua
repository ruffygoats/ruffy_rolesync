------------------------------------------------------------
-- RIVAL DISCORD ROLESYNC + VIP
------------------------------------------------------------

local RESOURCE_NAME = GetCurrentResourceName()

local ESX = nil
local QBCore = nil

local PlayerCache = {}


------------------------------------------------------------
-- FRAMEWORK INITIALIZATION
------------------------------------------------------------

CreateThread(function()

    Wait(500)

    if RIVAL.framework == "esx" then

        if GetResourceState("es_extended") ~= "started" then

            print("^1[RIVAL RoleSync] ESX wurde nicht gefunden!^0")

            return

        end

        ESX = exports["es_extended"]:getSharedObject()

        print("^2[RIVAL RoleSync] ESX erfolgreich geladen.^0")


    elseif RIVAL.framework == "qbcore" then

        if GetResourceState("qb-core") ~= "started" then

            print("^1[RIVAL RoleSync] QBCore wurde nicht gefunden!^0")

            return

        end

        QBCore = exports["qb-core"]:GetCoreObject()

        print("^2[RIVAL RoleSync] QBCore erfolgreich geladen.^0")


    else

        print(
            "^1[RIVAL RoleSync] Ungültiges Framework: " ..
            tostring(RIVAL.framework) ..
            "^0"
        )

    end

end)


------------------------------------------------------------
-- DEBUG
------------------------------------------------------------

local function Debug(message)

    if not RIVAL.debug then
        return
    end

    print(
        "^5[RIVAL RoleSync]^7 " ..
        tostring(message)
    )

end


------------------------------------------------------------
-- GET DISCORD IDENTIFIER
------------------------------------------------------------

local function GetDiscordIdentifier(source)

    local identifiers =
        GetPlayerIdentifiers(source)

    for _, identifier in ipairs(identifiers) do

        if identifier:sub(1, 8) == "discord:" then

            return identifier:sub(9)

        end

    end

    return nil

end


------------------------------------------------------------
-- DISCORD API
------------------------------------------------------------

local function GetDiscordMember(discordId)

    if not discordId then

        return nil, "NO_DISCORD"

    end


    if not RIVAL.botToken or
       RIVAL.botToken == "" or
       RIVAL.botToken == "DEIN_NEUER_BOT_TOKEN" then

        print(
            "^1[RIVAL RoleSync] " ..
            "Kein Discord Bot Token eingetragen!^0"
        )

        return nil, "NO_TOKEN"

    end


    local url =
        "https://discord.com/api/v10/guilds/" ..
        tostring(RIVAL.guildId) ..
        "/members/" ..
        tostring(discordId)


    local finished = false

    local statusCode = nil
    local responseBody = nil
    local errorData = nil


    PerformHttpRequest(
        url,

        function(
            status,
            body,
            headers,
            err
        )

            statusCode = status
            responseBody = body
            errorData = err

            finished = true

        end,

        "GET",

        "",

        {
            ["Authorization"] =
                "Bot " .. RIVAL.botToken,

            ["Content-Type"] =
                "application/json",

            ["User-Agent"] =
                "RIVAL-RoleSync/2.0"
        }
    )


    while not finished do

        Wait(0)

    end


    --------------------------------------------------------
    -- SUCCESS
    --------------------------------------------------------

    if statusCode == 200 then

        local success, data =
            pcall(
                json.decode,
                responseBody
            )


        if not success or not data then

            print(
                "^1[RIVAL RoleSync] " ..
                "Ungültige Discord API Antwort.^0"
            )

            return nil, "INVALID_JSON"

        end


        return data, nil

    end


    --------------------------------------------------------
    -- NOT IN GUILD
    --------------------------------------------------------

    if statusCode == 404 then

        return nil, "NOT_IN_GUILD"

    end


    --------------------------------------------------------
    -- INVALID TOKEN
    --------------------------------------------------------

    if statusCode == 401 then

        print(
            "^1[RIVAL RoleSync] " ..
            "Discord Bot Token ist ungültig!^0"
        )

        return nil, "INVALID_TOKEN"

    end


    --------------------------------------------------------
    -- FORBIDDEN
    --------------------------------------------------------

    if statusCode == 403 then

        print(
            "^1[RIVAL RoleSync] " ..
            "Discord Bot hat keinen Zugriff auf die Guild.^0"
        )

        return nil, "FORBIDDEN"

    end


    --------------------------------------------------------
    -- RATE LIMIT
    --------------------------------------------------------

    if statusCode == 429 then

        print(
            "^3[RIVAL RoleSync] " ..
            "Discord API Rate Limit erreicht.^0"
        )

        return nil, "RATE_LIMIT"

    end


    --------------------------------------------------------
    -- OTHER ERROR
    --------------------------------------------------------

    print(
        "^1[RIVAL RoleSync] Discord API Fehler: HTTP " ..
        tostring(statusCode) ..
        " | " ..
        tostring(errorData) ..
        "^0"
    )

    return nil, "HTTP_ERROR"

end


------------------------------------------------------------
-- CHECK ROLE
------------------------------------------------------------

local function HasRole(
    discordRoles,
    roleId
)

    if not discordRoles then
        return false
    end


    for _, playerRoleId in ipairs(discordRoles) do

        if tostring(playerRoleId) ==
           tostring(roleId) then

            return true

        end

    end


    return false

end


------------------------------------------------------------
-- GET HIGHEST STAFF ROLE
------------------------------------------------------------

local function GetHighestStaffRole(
    discordRoles
)

    if not discordRoles then
        return nil
    end


    --------------------------------------------------------
    -- Config wird von oben nach unten geprüft.
    --------------------------------------------------------

    for _, configuredRole in ipairs(RIVAL.roles) do

        if HasRole(
            discordRoles,
            configuredRole.roleId
        ) then

            return configuredRole

        end

    end


    return nil

end


------------------------------------------------------------
-- GET HIGHEST VIP ROLE
------------------------------------------------------------

local function GetHighestVIPRole(
    discordRoles
)

    if not RIVAL.vip then
        return nil
    end

    if not RIVAL.vip.enabled then
        return nil
    end

    if not RIVAL.vip.roles then
        return nil
    end


    local highestRole = nil


    for _, configuredRole in ipairs(
        RIVAL.vip.roles
    ) do

        if HasRole(
            discordRoles,
            configuredRole.roleId
        ) then

            if not highestRole then

                highestRole = configuredRole

            elseif tonumber(configuredRole.level or 0)
                >
                tonumber(highestRole.level or 0) then

                highestRole = configuredRole

            end

        end

    end


    return highestRole

end


------------------------------------------------------------
-- SET ESX GROUP
------------------------------------------------------------

local function SetESXGroup(
    source,
    group
)

    if not ESX then
        return false
    end


    local xPlayer =
        ESX.GetPlayerFromId(source)


    if not xPlayer then
        return false
    end


    if xPlayer.setGroup then

        xPlayer.setGroup(group)

        return true

    end


    Debug(
        "ESX xPlayer.setGroup wurde nicht gefunden."
    )


    return false

end


------------------------------------------------------------
-- SET QBCORE GROUP
------------------------------------------------------------

local function SetQBGroup(
    source,
    group
)

    if not QBCore then
        return false
    end


    local Player =
        QBCore.Functions.GetPlayer(source)


    if not Player then
        return false
    end


    --------------------------------------------------------
    -- Moderne QBCore Variante
    --------------------------------------------------------

    if Player.Functions and
       Player.Functions.SetPermission then

        Player.Functions.SetPermission(group)

        return true

    end


    --------------------------------------------------------
    -- Alternative
    --------------------------------------------------------

    if QBCore.Functions.SetPermission then

        QBCore.Functions.SetPermission(
            source,
            group
        )

        return true

    end


    --------------------------------------------------------
    -- Alte Variante
    --------------------------------------------------------

    if QBCore.Functions.AddPermission then

        QBCore.Functions.AddPermission(
            source,
            group
        )

        return true

    end


    Debug(
        "Keine QBCore Permission-Funktion gefunden."
    )


    return false

end


------------------------------------------------------------
-- SET PLAYER GROUP
------------------------------------------------------------

local function SetPlayerGroup(
    source,
    group
)

    if RIVAL.framework == "esx" then

        return SetESXGroup(
            source,
            group
        )

    elseif RIVAL.framework == "qbcore" then

        return SetQBGroup(
            source,
            group
        )

    end


    return false

end


------------------------------------------------------------
-- BUILD PLAYER DATA
------------------------------------------------------------

local function BuildPlayerData(
    discordMember
)

    if not discordMember then
        return nil
    end


    local discordRoles =
        discordMember.roles or {}


    local staffRole =
        GetHighestStaffRole(
            discordRoles
        )


    local vipRole =
        GetHighestVIPRole(
            discordRoles
        )


    local data = {

        discordId =
            discordMember.user
            and discordMember.user.id
            or nil,

        username =
            discordMember.user
            and discordMember.user.username
            or nil,

        roles =
            discordRoles,

        staff = {

            active =
                staffRole ~= nil,

            role =
                staffRole,

            group =
                staffRole
                and staffRole.groupName
                or RIVAL.defaultGroup
        },

        vip = {

            active =
                vipRole ~= nil,

            role =
                vipRole,

            level =
                vipRole
                and tonumber(vipRole.level or 0)
                or 0,

            name =
                vipRole
                and vipRole.name
                or nil,

            roleId =
                vipRole
                and vipRole.roleId
                or nil
        }

    }


    return data

end


------------------------------------------------------------
-- UPDATE PLAYER
------------------------------------------------------------

local function SyncPlayer(
    source,
    force
)

    source = tonumber(source)


    if not source then
        return false, "INVALID_SOURCE"
    end


    if not GetPlayerName(source) then
        return false, "PLAYER_NOT_FOUND"
    end


    --------------------------------------------------------
    -- DISCORD ID
    --------------------------------------------------------

    local discordId =
        GetDiscordIdentifier(source)


    if not discordId then

        Debug(
            GetPlayerName(source) ..
            " hat keinen Discord Identifier."
        )


        if RIVAL.enforceDiscordPermissions then

            SetPlayerGroup(
                source,
                RIVAL.defaultGroup
            )

        end


        PlayerCache[source] = {

            discordId = nil,

            staff = {
                active = false,
                group = RIVAL.defaultGroup
            },

            vip = {
                active = false,
                level = 0
            },

            timestamp = os.time()

        }


        return false, "NO_DISCORD"

    end


    --------------------------------------------------------
    -- CACHE
    --------------------------------------------------------

    if not force and
       PlayerCache[source] then

        local cache =
            PlayerCache[source]


        if cache.discordId ==
               discordId
           and
           cache.timestamp
           and
           os.time() -
               cache.timestamp < 30 then

            return true, cache

        end

    end


    --------------------------------------------------------
    -- DISCORD API
    --------------------------------------------------------

    local member, errorCode =
        GetDiscordMember(discordId)


    if not member then

        ----------------------------------------------------
        -- NOT IN GUILD
        ----------------------------------------------------

        if errorCode ==
           "NOT_IN_GUILD" then

            Debug(
                GetPlayerName(source) ..
                " ist nicht auf dem Discord."
            )


            if RIVAL.enforceDiscordPermissions then

                SetPlayerGroup(
                    source,
                    RIVAL.defaultGroup
                )

            end


            PlayerCache[source] = {

                discordId =
                    discordId,

                staff = {

                    active = false,

                    group =
                        RIVAL.defaultGroup

                },

                vip = {

                    active = false,

                    level = 0

                },

                timestamp = os.time()

            }


            return false, "NOT_IN_GUILD"

        end


        ----------------------------------------------------
        -- API ERROR
        ----------------------------------------------------

        return false, errorCode

    end


    --------------------------------------------------------
    -- PLAYER DATA
    --------------------------------------------------------

    local playerData =
        BuildPlayerData(member)


    if not playerData then

        return false, "DATA_ERROR"

    end


    --------------------------------------------------------
    -- STAFF GROUP
    --------------------------------------------------------

    if playerData.staff.active then

        local group =
            playerData.staff.group


        local success =
            SetPlayerGroup(
                source,
                group
            )


        if success then

            Debug(
                GetPlayerName(source) ..
                " -> Staff: " ..
                group ..
                " (" ..
                playerData.staff.role.label ..
                ")"
            )

        else

            Debug(
                "Staff-Gruppe konnte nicht gesetzt werden: " ..
                group
            )

        end

    else

        ----------------------------------------------------
        -- NO STAFF ROLE
        ----------------------------------------------------

        if RIVAL.enforceDiscordPermissions then

            SetPlayerGroup(
                source,
                RIVAL.defaultGroup
            )


            Debug(
                GetPlayerName(source) ..
                " -> Staff: " ..
                RIVAL.defaultGroup
            )

        end

    end


    --------------------------------------------------------
    -- VIP
    --------------------------------------------------------

    if playerData.vip.active then

        Debug(
            GetPlayerName(source) ..
            " -> VIP: " ..
            tostring(playerData.vip.name) ..
            " | Level " ..
            tostring(playerData.vip.level)
        )

    else

        Debug(
            GetPlayerName(source) ..
            " -> VIP: nicht aktiv"
        )

    end


    --------------------------------------------------------
    -- CACHE
    --------------------------------------------------------

    playerData.timestamp =
        os.time()


    PlayerCache[source] =
        playerData


    return true, playerData

end


------------------------------------------------------------
-- EXPORT: IS VIP
------------------------------------------------------------

exports(
    "IsVIP",

    function(source)

        source = tonumber(source)

        if not source then
            return false
        end


        local cache =
            PlayerCache[source]


        if cache and
           cache.vip then

            return cache.vip.active == true

        end


        local success, data =
            SyncPlayer(
                source,
                true
            )


        if not success or not data then
            return false
        end


        return data.vip
            and data.vip.active == true
            or false

    end
)


------------------------------------------------------------
-- EXPORT: GET VIP LEVEL
------------------------------------------------------------

exports(
    "GetVIPLevel",

    function(source)

        source = tonumber(source)

        if not source then
            return 0
        end


        local cache =
            PlayerCache[source]


        if cache and
           cache.vip then

            return tonumber(
                cache.vip.level or 0
            )

        end


        local success, data =
            SyncPlayer(
                source,
                true
            )


        if not success or not data then
            return 0
        end


        return tonumber(
            data.vip.level or 0
        )

    end
)


------------------------------------------------------------
-- EXPORT: GET VIP NAME
------------------------------------------------------------

exports(
    "GetVIPName",

    function(source)

        source = tonumber(source)

        if not source then
            return nil
        end


        local cache =
            PlayerCache[source]


        if cache and
           cache.vip then

            return cache.vip.name

        end


        local success, data =
            SyncPlayer(
                source,
                true
            )


        if not success or not data then
            return nil
        end


        return data.vip.name

    end
)


------------------------------------------------------------
-- EXPORT: GET STAFF GROUP
------------------------------------------------------------

exports(
    "GetStaffGroup",

    function(source)

        source = tonumber(source)

        if not source then
            return RIVAL.defaultGroup
        end


        local cache =
            PlayerCache[source]


        if cache and
           cache.staff then

            return cache.staff.group

        end


        local success, data =
            SyncPlayer(
                source,
                true
            )


        if not success or not data then
            return RIVAL.defaultGroup
        end


        return data.staff.group

    end
)


------------------------------------------------------------
-- EXPORT: GET PLAYER ROLE DATA
------------------------------------------------------------

exports(
    "GetRoleData",

    function(source)

        source = tonumber(source)

        if not source then
            return nil
        end


        local cache =
            PlayerCache[source]


        if cache then
            return cache
        end


        local success, data =
            SyncPlayer(
                source,
                true
            )


        if not success then
            return nil
        end


        return data

    end
)


------------------------------------------------------------
-- PLAYER CONNECTING
------------------------------------------------------------

AddEventHandler(
    "playerConnecting",

    function(
        playerName,
        setKickReason,
        deferrals
    )

        local source = source


        deferrals.defer()


        Wait(0)


        deferrals.update(
            RIVAL.locales.deferMessage
        )


        Wait(0)


        ----------------------------------------------------
        -- DISCORD ID
        ----------------------------------------------------

        local discordId =
            GetDiscordIdentifier(source)


        if not discordId then

            if RIVAL.enforceDiscordPermissions then

                deferrals.done(
                    RIVAL.locales.noDiscord
                )

                return

            end


            deferrals.done()

            return

        end


        ----------------------------------------------------
        -- DISCORD MEMBER
        ----------------------------------------------------

        local member, errorCode =
            GetDiscordMember(
                discordId
            )


        if not member then

            if errorCode ==
               "NOT_IN_GUILD" then

                if RIVAL.enforceDiscordPermissions then

                    deferrals.done(
                        RIVAL.locales.notInGuild
                    )

                    return

                end


                deferrals.done()

                return

            end


            ------------------------------------------------
            -- API ERROR
            ------------------------------------------------

            print(
                "^1[RIVAL RoleSync] " ..
                "Discord API Fehler beim Join von " ..
                playerName ..
                ": " ..
                tostring(errorCode) ..
                "^0"
            )


            -- Bei einem API-Fehler Spieler nicht
            -- automatisch aussperren.

            deferrals.done()

            return

        end


        ----------------------------------------------------
        -- STAFF ROLE
        ----------------------------------------------------

        local staffRole =
            GetHighestStaffRole(
                member.roles
            )


        if not staffRole and
           RIVAL.enforceDiscordPermissions then

            deferrals.done(
                RIVAL.locales.noRole
            )

            return

        end


        ----------------------------------------------------
        -- VIP
        ----------------------------------------------------

        local vipRole =
            GetHighestVIPRole(
                member.roles
            )


        ----------------------------------------------------
        -- MESSAGE
        ----------------------------------------------------

        local group =
            staffRole
            and staffRole.groupName
            or RIVAL.defaultGroup


        deferrals.update(
            string.format(
                RIVAL.locales.authenticatedAsGroup,
                group
            )
        )


        Wait(300)


        if vipRole then

            deferrals.update(
                "Discord VIP erkannt..."
            )

            Wait(300)

        end


        deferrals.done()

    end
)


------------------------------------------------------------
-- PLAYER JOINING
------------------------------------------------------------

AddEventHandler(
    "playerJoining",

    function()

        local source = source


        CreateThread(function()

            Wait(2000)


            if GetPlayerName(source) then

                SyncPlayer(
                    source,
                    true
                )

            end

        end)

    end
)


------------------------------------------------------------
-- PLAYER DROPPED
------------------------------------------------------------

AddEventHandler(
    "playerDropped",

    function()

        local source = source

        PlayerCache[source] = nil

    end
)


------------------------------------------------------------
-- /rolesync
------------------------------------------------------------

RegisterCommand(
    "rolesync",

    function(source)

        if source == 0 then

            print(
                "^3[RIVAL RoleSync] " ..
                "Dieser Command kann nicht über die " ..
                "Server Console verwendet werden.^0"
            )

            return

        end


        local success, data =
            SyncPlayer(
                source,
                true
            )


        if not success then

            TriggerClientEvent(
                "chat:addMessage",
                source,
                {
                    args = {
                        "RIVAL",
                        "Synchronisierung fehlgeschlagen: " ..
                        tostring(data)
                    }
                }
            )

            return

        end


        local staffText =
            data.staff.active
            and data.staff.group
            or RIVAL.defaultGroup


        local vipText


        if data.vip.active then

            vipText =
                "VIP: " ..
                tostring(data.vip.name) ..
                " (Level " ..
                tostring(data.vip.level) ..
                ")"

        else

            vipText =
                "VIP: nicht aktiv"

        end


        TriggerClientEvent(
            "chat:addMessage",
            source,
            {
                args = {
                    "RIVAL",
                    "Staff: " ..
                    staffText ..
                    " | " ..
                    vipText
                }
            }
        )

    end,

    false
)


------------------------------------------------------------
-- /vipstatus
------------------------------------------------------------

RegisterCommand(
    "vipstatus",

    function(source)

        if source == 0 then

            print(
                "^3[RIVAL RoleSync] " ..
                "Dieser Command kann nicht über die " ..
                "Server Console verwendet werden.^0"
            )

            return

        end


        local success, data =
            SyncPlayer(
                source,
                true
            )


        if not success or not data then

            TriggerClientEvent(
                "chat:addMessage",
                source,
                {
                    args = {
                        "RIVAL",
                        "VIP-Status konnte nicht geprüft werden."
                    }
                }
            )

            return

        end


        if data.vip.active then

            TriggerClientEvent(
                "chat:addMessage",
                source,
                {
                    args = {
                        "RIVAL",
                        "VIP aktiv: " ..
                        tostring(data.vip.name) ..
                        " | Level " ..
                        tostring(data.vip.level)
                    }
                }
            )

        else

            TriggerClientEvent(
                "chat:addMessage",
                source,
                {
                    args = {
                        "RIVAL",
                        "Du hast aktuell kein VIP."
                    }
                }
            )

        end

    end,

    false
)


------------------------------------------------------------
-- AUTOMATIC SYNC
------------------------------------------------------------

CreateThread(function()

    while true do

        if RIVAL.syncInterval and
           RIVAL.syncInterval > 0 then

            Wait(
                RIVAL.syncInterval
            )


            local players =
                GetPlayers()


            for _, playerId in ipairs(players) do

                local source =
                    tonumber(playerId)


                if source then

                    SyncPlayer(
                        source,
                        true
                    )


                    -- Kleine Pause zwischen den
                    -- Discord API Requests.
                    --
                    -- Wichtig gegen Rate Limits.

                    Wait(500)

                end

            end

        else

            Wait(10000)

        end

    end

end)


------------------------------------------------------------
-- RESOURCE START
------------------------------------------------------------

CreateThread(function()

    Wait(1000)


    print("")
    print("^5============================================^0")
    print("^5        RIVAL DISCORD ROLESYNC 2.0^0")
    print("^5============================================^0")
    print("^7Framework:^0 " ..
        tostring(RIVAL.framework))

    print("^7Guild:^0 " ..
        tostring(RIVAL.guildId))

    print("^7Staff Enforcement:^0 " ..
        tostring(RIVAL.enforceDiscordPermissions))

    print("^7VIP System:^0 " ..
        tostring(
            RIVAL.vip
            and RIVAL.vip.enabled
            or false
        ))

    print("^7Sync Interval:^0 " ..
        tostring(RIVAL.syncInterval) ..
        "ms")

    print("^5============================================^0")
    print("")

end)