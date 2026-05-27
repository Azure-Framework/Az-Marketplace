fx_version 'cerulean'
game 'gta5'

name 'az_marketplace'
author 'Azure Framework'
description 'Marketplace-style NUI for player listings + PM chat (Az-Framework)'
version '1.0.0'

lua54 'yes'

ui_page 'html/index.html'

shared_scripts {
  'shared/config.lua'
}

client_scripts {
  'client/client.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/server.lua'
}

files {
  'html/index.html',
  'html/style.css',
  'html/app.js'
}

dependency 'oxmysql'
dependency 'Az-Framework'
