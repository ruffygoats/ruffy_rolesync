RIVAL = {
    framework = "esx", -- can be "qbcore" or "esx"
    botToken = "MTU0OTE2MTUyNzI0Njg1NjI4Mg.Go2Rrl.-bkxmLffsBAidyMttf4tZ_sNncJh1i3A5_Anb8", --https://discord.com/developers/applications
    guildId = "1516625087246106715",
    enforceDiscordPermissions = true, -- This will enforce discord permission (player joins on the server, has superadmin in database, but no roles in guild, means he gets set to "user")
    roles = { -- this needs to be in the right order (higher ranks -> higher priority)
    {
        roleId = "1517601695948079154",
        groupName = "pl",
        label = "*"
    },
    {
        roleId = "1517601698305282108",
        groupName = "pl",
        label = "Projektleitung"
    },
    {
        roleId = "1517601701010473101",
        groupName = "manage",
        label = "Management"
    },
    {
        roleId = "1517601712464990330",
        groupName = "dev",
        label = "Developer"
    },
    {
        roleId = "1551781386543824927",
        groupName = "billionaire",
        label = "Billionaire"
    },
    {
        roleId = "1517601709130518639",
        groupName = "admin",
        label = "Administration"
    },
    {
        roleId = "1517601709894144180",
        groupName = "admin",
        label = "Jr. Administration"
    },
    {
        roleId = "1517601720383836250",
        groupName = "fv",
        label = "Fraktionsverwaltung"
    },
    {
        roleId = "1517601721298452501",
        groupName = "fv",
        label = "Jr. Fraktionsverwaltung"
    },
    {
        roleId = "1517601722443235568",
        groupName = "uv",
        label = "Unternehmensverwaltung"
    },
    {
        roleId = "1517601725907730472",
        groupName = "mod",
        label = "Sr. Moderation"
    },
    {
        roleId = "1517601727170347009",
        groupName = "mod",
        label = "Moderation"
    },
    {
        roleId = "1517601728084574320",
        groupName = "mod",
        label = "Jr. Moderation"
    },
    {
        roleId = "1517601729150189719",
        groupName = "support",
        label = "Sr. Supporter"
    },
    {
        roleId = "1517601729963626637",
        groupName = "support",
        label = "Supporter"
    },
    {
        roleId = "1517601737492664432",
        groupName = "analyst",
        label = "Analyst"
    },
    {
        roleId = "1517601758933815296",
        groupName = "creator",
        label = "Creator+"
    },

    },
    locales = {
        notInGuild = "Du bist nicht im Team",
        discordNotFound = "Wir konnten dir keinen Discord Identifier zuweisen",
        authenticatedAsGroup = "identifiziert als %s",
        deferMessage = "Checken deiner Permissions dies dauert nicht lange",
        welcomeBack = "Willkommen zurück, %s#%s",
    }
}