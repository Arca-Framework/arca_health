fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'arca_health'
author 'Arca'
description 'Medical core for the Arca framework: last stand, death screen, injuries, bleeding and EMS'
version '0.1.0'

shared_scripts {
    '@arca_core/shared/import.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
    'client/injuries.lua',
    'client/ems.lua',
}

server_scripts {
    'server/main.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
}

dependencies {
    'arca_core',
}
