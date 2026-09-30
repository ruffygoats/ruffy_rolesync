local RESOURCE_NAME = GetCurrentResourceName()

local ESX = nil
local QBCore = nil

local PlayerCache = {}

if not Config then
    Config = {
        framework = "esx",
        defaultGroup = "user",
        enforceDiscordPermissions = false,
        syncInterval = 0,
        debug = false,
        roles = {},
        vip = {
            enabled = false,
            roles = {}
        },
        locales = {}
    }

    print("^1[r_rolesync]^0 Config missing or not loaded. Check config.lua and fxmanifest.lua.")
end

CreateThread(function()
    Wait(500)

    if Config.framework == "esx" then
        if GetResourceState("es_extended") ~= "started" then
            return
        end

        ESX = exports["es_extended"]:getSharedObject()
        print("^0[^3RUFFY ^0ROLESYNC] ^2Loaded Rolesync.^0")

    elseif Config.framework == "qbcore" then
        if GetResourceState("qb-core") ~= "started" then
            return
        end

        QBCore = exports["qb-core"]:GetCoreObject()
    else
    end
end)

local function Debug(message)
    if not Config.debug then
        return
    end
    return
end

local function NotifyPlayer(source, message, notifyType, title, timeout)
    notifyType = notifyType or "info"

    local hudType = "info"

    if notifyType == "success" then
        hudType = "success"
    elseif notifyType == "error" then
        hudType = "error"
    end

    TriggerClientEvent(
        "hex_4_hud:notify",
        source,
        tostring(title or "RUFFY"),
        tostring(message),
        hudType,
        tonumber(timeout) or 5000
    )
end

local function GetDiscordIdentifier(source)
    local identifiers = GetPlayerIdentifiers(source)

    for _, identifier in ipairs(identifiers) do
        if identifier:sub(1, 8) == "discord:" then
            return identifier:sub(9)
        end
    end

    return nil
end

local function GetDiscordMember(discordId)
    if not discordId then
        return nil, "NO_DISCORD"
    end

    if not Config.botToken or
       Config.botToken == "" or
       Config.botToken == "DEIN_NEUER_BOT_TOKEN" then
        return nil, "NO_TOKEN"
    end

    local url =
        "https://discord.com/api/v10/guilds/" ..
        tostring(Config.guildId) ..
        "/members/" ..
        tostring(discordId)

    local finished = false
    local statusCode = nil
    local responseBody = nil
    local errorData = nil

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
            ["Authorization"] = "Bot " .. Config.botToken,
            ["Content-Type"] = "application/json",
            ["User-Agent"] = "Ruffy-RoleSync/2.0"
        }
    )

    while not finished do
        Wait(0)
    end

    if statusCode == 200 then
        local success, data = pcall(json.decode, responseBody)

        if not success or not data then
            return nil, "INVALID_JSON"
        end

        return data, nil
    end

    if statusCode == 404 then
        return nil, "NOT_IN_GUILD"
    end

    if statusCode == 401 then
        return nil, "INVALID_TOKEN"
    end

    if statusCode == 403 then
        return nil, "FORBIDDEN"
    end

    if statusCode == 429 then
        return nil, "RATE_LIMIT"
    end

    return nil, "HTTP_ERROR"
end

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

local function GetHighestStaffRole(discordRoles)
    if not discordRoles then
        return nil
    end

    for _, configuredRole in ipairs(Config.roles) do
        if HasRole(discordRoles, configuredRole.roleId) then
            return configuredRole
        end
    end

    return nil
end

local function GetHighestVIPRole(discordRoles)
    if not Config.vip then
        return nil
    end

    if not Config.vip.enabled then
        return nil
    end

    if not Config.vip.roles then
        return nil
    end

    local highestRole = nil

    for _, configuredRole in ipairs(Config.vip.roles) do
        if HasRole(discordRoles, configuredRole.roleId) then
            if not highestRole then
                highestRole = configuredRole
            elseif tonumber(configuredRole.level or 0) > tonumber(highestRole.level or 0) then
                highestRole = configuredRole
            end
        end
    end

    return highestRole
end

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

local function SetQBGroup(source, group)
    if not QBCore then
        return false
    end

    local Player = QBCore.Functions.GetPlayer(source)

    if not Player then
        return false
    end

    if Player.Functions and Player.Functions.SetPermission then
        Player.Functions.SetPermission(group)
        return true
    end

    if QBCore.Functions.SetPermission then
        QBCore.Functions.SetPermission(source, group)
        return true
    end

    if QBCore.Functions.AddPermission then
        QBCore.Functions.AddPermission(source, group)
        return true
    end

    Debug("Keine QBCore Permission-Funktion gefunden.")
    return false
end

local function SetPlayerGroup(source, group)
    if Config.framework == "esx" then
        return SetESXGroup(source, group)
    elseif Config.framework == "qbcore" then
        return SetQBGroup(source, group)
    end

    return false
end

local function BuildPlayerData(discordMember)
    if not discordMember then
        return nil
    end

    local discordRoles = discordMember.roles or {}

    local staffRole = GetHighestStaffRole(discordRoles)
    local vipRole = GetHighestVIPRole(discordRoles)

    local data = {
        discordId = discordMember.user and discordMember.user.id or nil,
        username = discordMember.user and discordMember.user.username or nil,
        roles = discordRoles,
        staff = {
            active = staffRole ~= nil,
            role = staffRole,
            group = staffRole and staffRole.groupName or Config.defaultGroup
        },
        vip = {
            active = vipRole ~= nil,
            role = vipRole,
            level = vipRole and tonumber(vipRole.level or 0) or 0,
            name = vipRole and vipRole.name or nil,
            roleId = vipRole and vipRole.roleId or nil
        }
    }

    return data
end

local function SyncPlayer(source, force)
    source = tonumber(source)

    if not source then
        return false, "INVALID_SOURCE"
    end

    if not GetPlayerName(source) then
        return false, "PLAYER_NOT_FOUND"
    end

    local discordId = GetDiscordIdentifier(source)

    if not discordId then
        Debug(GetPlayerName(source) .. " hat keinen Discord Identifier.")

        if Config.enforceDiscordPermissions then
            SetPlayerGroup(source, Config.defaultGroup)
        end

        PlayerCache[source] = {
            discordId = nil,
            staff = {
                active = false,
                group = Config.defaultGroup
            },
            vip = {
                active = false,
                level = 0
            },
            timestamp = os.time()
        }

        return false, "NO_DISCORD"
    end

    if not force and PlayerCache[source] then
        local cache = PlayerCache[source]

        if cache.discordId == discordId and
           cache.timestamp and
           os.time() - cache.timestamp < 30 then
            return true, cache
        end
    end

    local member, errorCode = GetDiscordMember(discordId)

    if not member then
        if errorCode == "NOT_IN_GUILD" then
            Debug(GetPlayerName(source) .. " ist nicht auf dem Discord.")

            if Config.enforceDiscordPermissions then
                SetPlayerGroup(source, Config.defaultGroup)
            end

            PlayerCache[source] = {
                discordId = discordId,
                staff = {
                    active = false,
                    group = Config.defaultGroup
                },
                vip = {
                    active = false,
                    level = 0
                },
                timestamp = os.time()
            }

            return false, "NOT_IN_GUILD"
        end

        return false, errorCode
    end

    local playerData = BuildPlayerData(member)

    if not playerData then
        return false, "DATA_ERROR"
    end

    if playerData.staff.active then
        local group = playerData.staff.group
        local success = SetPlayerGroup(source, group)

        if success then
            Debug(
                "^4" .. GetPlayerName(source) .. "^0" ..
                " -> group: " ..
                "^2" .. group .. "^0" ..
                "^0"
            )
        else
            Debug("Staff-Gruppe konnte nicht gesetzt werden: " .. group)
        end
    else
        if Config.enforceDiscordPermissions then
            SetPlayerGroup(source, Config.defaultGroup)

            Debug(
                GetPlayerName(source) ..
                " -> group: " ..
                Config.defaultGroup
            )
        end
    end

    if playerData.vip.active then
        Debug(
            "^4" .. GetPlayerName(source) .. "^0" ..
            " -> " ..
            "^2" .. playerData.vip.name .. "^0" ..
            "^0"
        )
    else
        Debug(
            GetPlayerName(source) ..
            " -> VIP: " ..
            "^1" .. "nicht aktiv" .. "^0"
        )
    end

    playerData.timestamp = os.time()
    PlayerCache[source] = playerData

    return true, playerData
end

exports("IsVIP", function(source)
    source = tonumber(source)

    if not source then
        return false
    end

    local cache = PlayerCache[source]

    if cache and cache.vip then
        return cache.vip.active == true
    end

    local success, data = SyncPlayer(source, true)

    if not success or not data then
        return false
    end

    return data.vip and data.vip.active == true or false
end)

exports("GetVIPLevel", function(source)
    source = tonumber(source)

    if not source then
        return 0
    end

    local cache = PlayerCache[source]

    if cache and cache.vip then
        return tonumber(cache.vip.level or 0)
    end

    local success, data = SyncPlayer(source, true)

    if not success or not data then
        return 0
    end

    return tonumber(data.vip.level or 0)
end)

exports("GetVIPName", function(source)
    source = tonumber(source)

    if not source then
        return nil
    end

    local cache = PlayerCache[source]

    if cache and cache.vip then
        return cache.vip.name
    end

    local success, data = SyncPlayer(source, true)

    if not success or not data then
        return nil
    end

    return data.vip.name
end)

exports("GetStaffGroup", function(source)
    source = tonumber(source)

    if not source then
        return Config.defaultGroup
    end

    local cache = PlayerCache[source]

    if cache and cache.staff then
        return cache.staff.group
    end

    local success, data = SyncPlayer(source, true)

    if not success or not data then
        return Config.defaultGroup
    end

    return data.staff.group
end)

exports("GetRoleData", function(source)
    source = tonumber(source)

    if not source then
        return nil
    end

    local cache = PlayerCache[source]

    if cache then
        return cache
    end

    local success, data = SyncPlayer(source, true)

    if not success then
        return nil
    end

    return data
end)

AddEventHandler("playerConnecting", function(playerName, setKickReason, deferrals)
    local source = source

    deferrals.defer()
    Wait(0)
    deferrals.update(Config.locales.deferMessage)
    Wait(0)

    local discordId = GetDiscordIdentifier(source)

    if not discordId then
        if Config.enforceDiscordPermissions then
            deferrals.done(Config.locales.noDiscord)
            return
        end

        deferrals.done()
        return
    end

    local member, errorCode = GetDiscordMember(discordId)

    if not member then
        if errorCode == "NOT_IN_GUILD" then
            if Config.enforceDiscordPermissions then
                deferrals.done(Config.locales.notInGuild)
                return
            end

            deferrals.done()
            return
        end

        deferrals.done()
        return
    end

    local staffRole = GetHighestStaffRole(member.roles)

    if not staffRole and Config.enforceDiscordPermissions then
        deferrals.done(Config.locales.noRole)
        return
    end

    local vipRole = GetHighestVIPRole(member.roles)

    local group = staffRole and staffRole.groupName or Config.defaultGroup

    deferrals.update(
        string.format(
            Config.locales.authenticatedAsGroup,
            group
        )
    )

    Wait(300)

    if vipRole then
        deferrals.update("Discord VIP erkannt...")
        Wait(300)
    end

    deferrals.done()
end)

AddEventHandler("playerJoining", function()
    local source = source

    CreateThread(function()
        Wait(2000)

        if GetPlayerName(source) then
            SyncPlayer(source, true)
        end
    end)
end)

AddEventHandler("playerDropped", function()
    local source = source
    PlayerCache[source] = nil
end)

RegisterCommand("rolesync", function(source)
    if source == 0 then
        return
    end

    local success, data = SyncPlayer(source, true)

    if not success then
        TriggerClientEvent(
            "chat:addMessage",
            source,
            {
                args = {
                    "Ruffy",
                    "Synchronisierung fehlgeschlagen: " .. tostring(data)
                }
            }
        )
        return
    end

    local staffText = data.staff.active and data.staff.group or Config.defaultGroup

    local vipText

    if data.vip.active then
        vipText =
            "VIP: " ..
            tostring(data.vip.name) ..
            " (Level " ..
            tostring(data.vip.level) ..
            ")"
    else
        vipText = "VIP: nicht aktiv"
    end

    TriggerClientEvent(
        "chat:addMessage",
        source,
        {
            args = {
                "Ruffy",
                "group: " .. staffText .. " | " .. vipText
            }
        }
    )
end, false)

RegisterCommand("vipstatus", function(source)
    if source == 0 then
        return
    end

    local success, data = SyncPlayer(source, true)

    if not success or not data then
        TriggerClientEvent(
            "chat:addMessage",
            source,
            {
                args = {
                    "Ruffy",
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
                    "Ruffy",
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
                    "Ruffy",
                    "Du hast aktuell kein VIP."
                }
            }
        )
    end
end, false)

RegisterCommand("stats", function(source)
    if source == 0 then
        return
    end

    local success, data = SyncPlayer(source, true)

    if not success or not data then
        NotifyPlayer(
            source,
            "Deine Gruppe konnte nicht geprüft werden.",
            "error",
            "STATS"
        )
        return
    end

    local currentGroup = data.staff and data.staff.group or Config.defaultGroup

    NotifyPlayer(
        source,
        "Deine aktuelle Gruppe ist: " .. tostring(currentGroup),
        "success",
        "STATS"
    )

    if data.vip and data.vip.active then
        NotifyPlayer(
            source,
            "" ..
            tostring(data.vip.name) ..
            " (Level " ..
            tostring(data.vip.level) ..
            ")",
            "info",
            "VIP"
        )
    else
        NotifyPlayer(
            source,
            "Du hast aktuell kein VIP.",
            "info",
            "VIP"
        )
    end
end, false)

RegisterCommand("checkvip", function(source)
    if source == 0 then
        return
    end

    local success, data = SyncPlayer(source, true)

    if not success or not data then
        NotifyPlayer(
            source,
            "VIP-Status konnte nicht geprüft werden.",
            "error"
        )
        return
    end

    if data.vip and data.vip.active then
        NotifyPlayer(
            source,
            "Ja, du hast VIP: " ..
            tostring(data.vip.name) ..
            " (Level " ..
            tostring(data.vip.level) ..
            ")",
            "success"
        )
    else
        NotifyPlayer(
            source,
            "Du hast aktuell kein VIP.",
            "info"
        )
    end
end, false)

CreateThread(function()
    while true do
        if Config.syncInterval and Config.syncInterval > 0 then
            Wait(Config.syncInterval)

            local players = GetPlayers()

            for _, playerId in ipairs(players) do
                local source = tonumber(playerId)

                if source then
                    SyncPlayer(source, true)
                    Wait(500)
                end
            end
        else
            Wait(10000)
        end
    end
end)