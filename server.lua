local RESOURCE_NAME = GetCurrentResourceName()

local ESX = nil
local QBCore = nil

local PlayerCache = {}

------------------------------------------------------------
-- FRAMEWORK
------------------------------------------------------------

CreateThread(function()

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

        print("^1[RIVAL RoleSync] Ungültiges Framework: " ..
            tostring(RIVAL.framework) .. "^0")

    end

end)


------------------------------------------------------------
-- DEBUG
------------------------------------------------------------

local function Debug(message)

    if not RIVAL.debug then
        return
    end

    print("^5[RIVAL RoleSync]^7 " .. tostring(message))

end


------------------------------------------------------------
-- DISCORD IDENTIFIER
------------------------------------------------------------

local function GetDiscordIdentifier(source)

    local identifiers = GetPlayerIdentifiers(source)

    for _, identifier in ipairs(identifiers) do

        if identifier:sub(1, 8) == "discord:" then

            return identifier:sub(9)

        end

    end

    return nil

end


------------------------------------------------------------
-- DISCORD API REQUEST
------------------------------------------------------------

local function GetDiscordMember(discordId)

    if not discordId then
        return nil, "NO_DISCORD"
    end

    if not RIVAL.botToken or
       RIVAL.botToken == "" or
       RIVAL.botToken == "DEIN_NEUER_BOT_TOKEN" then

        print("^1[RIVAL RoleSync] Kein Discord Bot Token eingetragen!^0")

        return nil, "NO_TOKEN"

    end

    local url =
        "https://discord.com/api/v10/guilds/" ..
        RIVAL.guildId ..
        "/members/" ..
        discordId

    local statusCode = nil
    local responseBody = nil
    local errorData = nil

    local finished = false

    PerformHttpRequest(
        url,
        function(status, body, headers, err)

            statusCode = status
            responseBody = body
            errorData = err

            finished = true

        end,
        "GET",
        "",
        {
            ["Authorization"] = "Bot " .. RIVAL.botToken,
            ["Content-Type"] = "application/json",
            ["User-Agent"] = "RIVAL-RoleSync/1.0"
        }
    )

    while not finished do
        Wait(0)
    end

    if statusCode == 200 then

        local success, data = pcall(json.decode, responseBody)

        if not success or not data then

            Debug("Discord API JSON konnte nicht gelesen werden.")

            return nil, "INVALID_JSON"

        end

        return data, nil

    elseif statusCode == 404 then

        Debug("Discord User " .. discordId .. " ist nicht auf dem Discord.")

        return nil, "NOT_IN_GUILD"

    elseif statusCode == 401 then

        print("^1[RIVAL RoleSync] Discord Bot Token ist ungültig!^0")

        return nil, "INVALID_TOKEN"

    elseif statusCode == 403 then

        print("^1[RIVAL RoleSync] Discord Bot hat keine Berechtigung für die Guild.^0")

        return nil, "FORBIDDEN"

    elseif statusCode == 429 then

        print("^3[RIVAL RoleSync] Discord API Rate Limit erreicht.^0")

        return nil, "RATE_LIMIT"

    else

        print(
            "^1[RIVAL RoleSync] Discord API Fehler: HTTP " ..
            tostring(statusCode) ..
            " | " ..
            tostring(errorData) ..
            "^0"
        )

        return nil, "HTTP_ERROR"

    end

end


------------------------------------------------------------
-- ROLE CHECK
------------------------------------------------------------

local function HasRole(discordRoles, roleId)

    if not discordRoles then
        return false
    end

    for _, playerRoleId in ipairs(discordRoles) do

        if tostring(playerRoleId) == tostring(roleId) then
            return true
        end

    end

    return false

end


------------------------------------------------------------
-- GET HIGHEST ROLE
------------------------------------------------------------

local function GetHighestRivalRole(discordRoles)

    if not discordRoles then
        return nil
    end

    -- Die Config wird von oben nach unten geprüft.
    -- Deshalb gewinnt automatisch die erste passende Rolle.

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
-- ESX GROUP
------------------------------------------------------------

local function SetESXGroup(source, group)

    if not ESX then
        return false
    end

    local xPlayer = ESX.GetPlayerFromId(source)

    if not xPlayer then
        return false
    end

    if xPlayer.setGroup then

        xPlayer.setGroup(group)

        return true

    end

    Debug("ESX xPlayer.setGroup wurde nicht gefunden.")

    return false

end


------------------------------------------------------------
-- QBCORE GROUP
------------------------------------------------------------

local function SetQBGroup(source, group)

    if not QBCore then
        return false
    end

    local Player = QBCore.Functions.GetPlayer(source)

    if not Player then
        return false
    end

    --------------------------------------------------------
    -- Variante 1
    --------------------------------------------------------

    if Player.Functions and Player.Functions.SetPermission then

        Player.Functions.SetPermission(group)

        return true

    end

    --------------------------------------------------------
    -- Variante 2
    --------------------------------------------------------

    if QBCore.Functions.SetPermission then

        QBCore.Functions.SetPermission(source, group)

        return true

    end

    --------------------------------------------------------
    -- Variante 3
    --------------------------------------------------------

    if QBCore.Functions.AddPermission then

        QBCore.Functions.AddPermission(source, group)

        return true

    end

    Debug("Keine passende QBCore Permission-Funktion gefunden.")

    return false

end


------------------------------------------------------------
-- SET GROUP
------------------------------------------------------------

local function SetPlayerGroup(source, group)

    if RIVAL.framework == "esx" then

        return SetESXGroup(source, group)

    elseif RIVAL.framework == "qbcore" then

        return SetQBGroup(source, group)

    end

    return false

end


------------------------------------------------------------
-- DISCORD SYNC
------------------------------------------------------------

local function SyncPlayer(source, force)

    source = tonumber(source)

    if not source then
        return false
    end

    if not GetPlayerName(source) then
        return false
    end

    local discordId = GetDiscordIdentifier(source)

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
            group = RIVAL.defaultGroup,
            roleId = nil
        }

        return false, "NO_DISCORD"

    end

    --------------------------------------------------------
    -- CACHE
    --------------------------------------------------------

    if not force and PlayerCache[source] then

        local cache = PlayerCache[source]

        if cache.discordId == discordId and
           cache.timestamp and
           os.time() - cache.timestamp < 30 then

            return true

        end

    end

    --------------------------------------------------------
    -- DISCORD API
    --------------------------------------------------------

    local member, errorCode =
        GetDiscordMember(discordId)

    if not member then

        if errorCode == "NOT_IN_GUILD" then

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
                discordId = discordId,
                group = RIVAL.defaultGroup,
                roleId = nil,
                timestamp = os.time()
            }

            return false, "NOT_IN_GUILD"

        end

        return false, errorCode

    end

    --------------------------------------------------------
    -- ROLE
    --------------------------------------------------------

    local selectedRole =
        GetHighestRivalRole(member.roles)

    if not selectedRole then

        Debug(
            GetPlayerName(source) ..
            " hat keine konfigurierte Team-Rolle."
        )

        if RIVAL.enforceDiscordPermissions then

            SetPlayerGroup(
                source,
                RIVAL.defaultGroup
            )

        end

        PlayerCache[source] = {
            discordId = discordId,
            group = RIVAL.defaultGroup,
            roleId = nil,
            timestamp = os.time()
        }

        return false, "NO_ROLE"

    end

    --------------------------------------------------------
    -- SET GROUP
    --------------------------------------------------------

    local success =
        SetPlayerGroup(
            source,
            selectedRole.groupName
        )

    if not success then

        print(
            "^1[RIVAL RoleSync] Gruppe konnte nicht gesetzt werden: " ..
            tostring(selectedRole.groupName) ..
            "^0"
        )

        return false, "GROUP_FAILED"

    end

    --------------------------------------------------------
    -- CACHE
    --------------------------------------------------------

    PlayerCache[source] = {

        discordId = discordId,

        group = selectedRole.groupName,

        roleId = selectedRole.roleId,

        label = selectedRole.label,

        timestamp = os.time()

    }

    Debug(
        GetPlayerName(source) ..
        " -> " ..
        selectedRole.groupName ..
        " (" ..
        selectedRole.label ..
        ")"
    )

    return true, selectedRole

end


------------------------------------------------------------
-- PLAYER CONNECTING
------------------------------------------------------------

AddEventHandler(
    "playerConnecting",
    function(playerName, setKickReason, deferrals)

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
            GetDiscordMember(discordId)

        if not member then

            if errorCode == "NOT_IN_GUILD" then

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
                "^1[RIVAL RoleSync] Discord API Fehler beim Join von " ..
                playerName ..
                ": " ..
                tostring(errorCode) ..
                "^0"
            )

            -- Bei einem API-/Token-Fehler nicht automatisch
            -- Spieler aussperren.

            deferrals.done()

            return

        end

        ----------------------------------------------------
        -- ROLE CHECK
        ----------------------------------------------------

        local selectedRole =
            GetHighestRivalRole(member.roles)

        if not selectedRole then

            if RIVAL.enforceDiscordPermissions then

                deferrals.done(
                    RIVAL.locales.noRole
                )

                return

            end

        end

        ----------------------------------------------------
        -- ALLOW
        ----------------------------------------------------

        deferrals.update(
            string.format(
                RIVAL.locales.authenticatedAsGroup,
                selectedRole and selectedRole.groupName
                    or RIVAL.defaultGroup
            )
        )

        Wait(500)

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

        -- Kleine Verzögerung damit ESX/QBCore
        -- den Player vollständig erstellt hat.

        CreateThread(function()

            Wait(1500)

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
-- MANUAL SYNC COMMAND
------------------------------------------------------------

RegisterCommand(
    "rolesync",
    function(source)

        if source == 0 then

            print(
                "^3[RIVAL RoleSync] Dieser Command kann " ..
                "nicht über die Server Console verwendet werden.^0"
            )

            return

        end

        local success, result =
            SyncPlayer(
                source,
                true
            )

        if success then

            TriggerClientEvent(
                "chat:addMessage",
                source,
                {
                    args = {
                        "RIVAL",
                        "Deine Discord-Gruppe wurde synchronisiert."
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
                        "Synchronisierung fehlgeschlagen: " ..
                        tostring(result)
                    }
                }
            )

        end

    end,
    false
)


------------------------------------------------------------
-- AUTOMATIC ROLE UPDATE
------------------------------------------------------------

CreateThread(function()

    while true do

        if RIVAL.syncInterval and
           RIVAL.syncInterval > 0 then

            Wait(RIVAL.syncInterval)

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

                    Wait(250)

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
    print("^5========================================^0")
    print("^5       RIVAL DISCORD ROLESYNC^0")
    print("^5========================================^0")
    print("^7Framework:^0 " .. tostring(RIVAL.framework))
    print("^7Guild ID:^0 " .. tostring(RIVAL.guildId))
    print("^7Permission Enforcement:^0 " ..
        tostring(RIVAL.enforceDiscordPermissions))
    print("^7Auto Sync:^0 " ..
        tostring(RIVAL.syncInterval) .. "ms")
    print("^5========================================^0")
    print("")

end)