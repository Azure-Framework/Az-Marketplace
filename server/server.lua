local RESOURCE = GetCurrentResourceName()

local fw = exports['Az-Framework']

Config = Config or {}
local DEBUG = (Config.Debug == true)

local function dprint(...)
  if not DEBUG then return end
  print(('^3[%s:server]^7'):format(RESOURCE), ...)
end


local function eprint(...)
  print(('^1[%s:server]^7'):format(RESOURCE), ...)
end



local function fwCall(method, ...)
  if not fw then return nil end
  local fn = fw[method]
  if type(fn) ~= 'function' then return nil end
  local ok, res = pcall(fn, fw, ...)
  if ok then return res end
  return nil
end




local function hasOx()
  
  local s = GetResourceState('oxmysql')
  if s ~= 'started' and s ~= 'starting' then
    return false
  end
  return exports ~= nil and exports.oxmysql ~= nil
end



local function oxTimeoutMs()
  return tonumber(Config and Config.DB and Config.DB.TimeoutMs) or 6000
end

local function awaitWithTimeout(fn, label)
  local p = promise.new()
  local done = false

  local function resolve(v)
    if done then return end
    done = true
    p:resolve(v)
  end

  SetTimeout(oxTimeoutMs(), function()
    resolve({ __timeout = true, __label = label })
  end)

  local ok, err = pcall(fn, resolve)
  if not ok then
    resolve({ __error = true, __label = label, __message = tostring(err) })
  end

  return Citizen.Await(p)
end

local function awaitQuery(query, params)
  params = params or {}
  return awaitWithTimeout(function(resolve)
    exports.oxmysql:query(query, params, function(res)
      resolve(res)
    end)
  end, 'query')
end

local function awaitInsert(query, params)
  params = params or {}
  return awaitWithTimeout(function(resolve)
    
    if exports.oxmysql.insert then
      exports.oxmysql:insert(query, params, function(insertId)
        resolve(insertId)
      end)
      return
    end

    
    exports.oxmysql:query(query, params, function(res)
      resolve(res)
    end)
  end, 'insert')
end

local function awaitUpdate(query, params)
  params = params or {}
  return awaitWithTimeout(function(resolve)
    if exports.oxmysql.update then
      exports.oxmysql:update(query, params, function(affected)
        resolve(affected)
      end)
      return
    end
    exports.oxmysql:query(query, params, function(res)
      resolve(res)
    end)
  end, 'update')
end



local function awaitExecute(query, params)
  
  return awaitQuery(query, params)
end

local function safeJsonDecode(str, fallback)
  if not str or str == '' then return fallback end
  local ok, v = pcall(json.decode, str)
  if ok then return v end
  return fallback
end

local function safeJsonEncode(v)
  local ok, out = pcall(json.encode, v)
  if ok then return out end
  return '[]'
end

local function clampInt(v, a, b)
  v = tonumber(v) or a
  if v < a then return a end
  if v > b then return b end
  return math.floor(v)
end


local function isDbTimeout(res)
  return type(res) == 'table' and res.__timeout == true
end

local function isDbError(res)
  return type(res) == 'table' and res.__error == true
end

local function strTrim(s)
  s = tostring(s or '')
  s = s:gsub('^%s+', ''):gsub('%s+$', '')
  return s
end





local T_LIST = (Config.DB and Config.DB.ListingsTable) or 'az_marketplace_listings'
local T_MSG  = (Config.DB and Config.DB.MessagesTable) or 'az_marketplace_messages'
local T_VEH  = (Config.DB and Config.DB.VehiclesTable) or 'user_vehicles'
local T_HOU  = (Config.DB and Config.DB.HousesTable) or 'az_houses'
local T_RENT = (Config.DB and Config.DB.RentalsTable) or 'az_house_rentals'
local H_OWNER_COL = (Config.DB and Config.DB.HouseOwnerColumn) or 'owner_identifier'






local function columnExists(tableName, columnName)
  local rows = awaitQuery([[
    SELECT COUNT(*) AS c
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?
  ]], { tableName, columnName })

  
  if type(rows) == 'table' and (rows.__timeout or rows.__error) then
    return false
  end

  local c = rows and rows[1] and tonumber(rows[1].c) or 0
  return c > 0
end

local function ensureListingSchema()
  local tbl = T_LIST
  if not tbl or tbl == '' then return end

  local function addCol(name, def)
    if not columnExists(tbl, name) then
      dprint('Migrating listings table: adding column', name)
      awaitExecute(('ALTER TABLE `%s` ADD COLUMN %s'):format(tbl, def), {})
    end
  end

  
  addCol('listing_type', "`listing_type` varchar(16) NOT NULL DEFAULT 'item'")
  addCol('currency', "`currency` varchar(8) NOT NULL DEFAULT '$'")
  addCol('condition', "`condition` varchar(32) NOT NULL DEFAULT 'Used - Good'")
  addCol('description', "`description` varchar(800) DEFAULT NULL")
  addCol('images', "`images` longtext DEFAULT NULL")
  addCol('location_x', "`location_x` double NOT NULL DEFAULT 0")
  addCol('location_y', "`location_y` double NOT NULL DEFAULT 0")
  addCol('location_z', "`location_z` double NOT NULL DEFAULT 0")
  addCol('location_label', "`location_label` varchar(64) NOT NULL DEFAULT ''")
  addCol('seller_discord', "`seller_discord` varchar(64) NOT NULL DEFAULT ''")
  addCol('seller_charid', "`seller_charid` varchar(64) DEFAULT NULL")
  addCol('seller_name', "`seller_name` varchar(100) DEFAULT NULL")
  addCol('source_ref', "`source_ref` varchar(64) DEFAULT NULL")
  addCol('source_json', "`source_json` longtext DEFAULT NULL")
  addCol('status', "`status` varchar(16) NOT NULL DEFAULT 'active'")

  
  if columnExists(tbl, 'owner') and columnExists(tbl, 'seller_discord') then
    
    awaitExecute(("UPDATE `%s` SET seller_discord = owner " ..
      "WHERE (seller_discord IS NULL OR seller_discord = '') " ..
      "AND owner IS NOT NULL AND owner <> ''"):format(tbl), {})
  end

  if columnExists(tbl, 'item_condition') and columnExists(tbl, 'condition') then
    awaitExecute(("UPDATE `%s` SET `condition` = item_condition " ..
      "WHERE (`condition` IS NULL OR `condition` = '') " ..
      "AND item_condition IS NOT NULL AND item_condition <> ''"):format(tbl), {})
  end

  if columnExists(tbl, 'image') and columnExists(tbl, 'images') then
    
    awaitExecute(("UPDATE `%s` SET images = CONCAT('[', JSON_QUOTE(image), ']') " ..
      "WHERE (images IS NULL OR images = '' OR images = '[]') " ..
      "AND image IS NOT NULL AND image <> ''"):format(tbl), {})
  end
end





local T_LIST = (Config.DB and Config.DB.ListingsTable) or 'az_marketplace_listings'
local T_MSG  = (Config.DB and Config.DB.MessagesTable) or 'az_marketplace_messages'
local T_VEH  = (Config.DB and Config.DB.VehiclesTable) or 'user_vehicles'
local T_HOU  = (Config.DB and Config.DB.HousesTable) or 'az_houses'
local T_RENT = (Config.DB and Config.DB.RentalsTable) or 'az_house_rentals'
local H_OWNER_COL = (Config.DB and Config.DB.HouseOwnerColumn) or 'owner_identifier'

local function ensureTables()
  if not hasOx() then
    print(('^1[%s]^7 oxmysql is required.'):format(RESOURCE))
    return
  end

  awaitExecute(([[
    CREATE TABLE IF NOT EXISTS `%s` (
      `id` int(11) NOT NULL AUTO_INCREMENT,
      `listing_type` varchar(16) NOT NULL DEFAULT 'item',
      `category` varchar(32) NOT NULL DEFAULT 'classifieds',
      `title` varchar(64) NOT NULL,
      `price` int(11) NOT NULL DEFAULT 0,
      `currency` varchar(8) NOT NULL DEFAULT '$',
      `condition` varchar(24) NOT NULL DEFAULT 'Used - Good',
      `description` varchar(800) DEFAULT NULL,
      `images` longtext DEFAULT NULL,
      `location_x` double NOT NULL DEFAULT 0,
      `location_y` double NOT NULL DEFAULT 0,
      `location_z` double NOT NULL DEFAULT 0,
      `location_label` varchar(64) NOT NULL DEFAULT '',
      `seller_discord` varchar(64) NOT NULL,
      `seller_charid` varchar(64) DEFAULT NULL,
      `seller_name` varchar(100) DEFAULT NULL,
      `source_ref` varchar(64) DEFAULT NULL,
      `source_json` longtext DEFAULT NULL,
      `status` varchar(16) NOT NULL DEFAULT 'active',
      `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
      `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp(),
      PRIMARY KEY (`id`),
      KEY `idx_status` (`status`),
      KEY `idx_category` (`category`),
      KEY `idx_listing_type` (`listing_type`),
      KEY `idx_seller` (`seller_discord`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]]):format(T_LIST))

  awaitExecute(([[
    CREATE TABLE IF NOT EXISTS `%s` (
      `id` int(11) NOT NULL AUTO_INCREMENT,
      `listing_id` int(11) NOT NULL,
      `seller_discord` varchar(64) NOT NULL,
      `buyer_discord` varchar(64) NOT NULL,
      `sender_discord` varchar(64) NOT NULL,
      `message` varchar(1000) NOT NULL,
      `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
      PRIMARY KEY (`id`),
      KEY `idx_listing` (`listing_id`),
      KEY `idx_pair` (`seller_discord`,`buyer_discord`),
      KEY `idx_sender` (`sender_discord`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]]):format(T_MSG))

  
  ensureListingSchema()

  dprint('Tables ensured:', T_LIST, T_MSG)
end

CreateThread(function()
  Wait(1000)
  ensureTables()
end)













local function getCharId(src) end
local function getDiscordId(src) end
local function getCharName(src) end

getCharId = function(src)
  local cid = fwCall('GetPlayerCharacter', src)
  if cid == nil then return nil end
  cid = tostring(cid)
  if cid == '' then return nil end
  return cid
end

getDiscordId = function(src)
  
  for _, id in ipairs(GetPlayerIdentifiers(src)) do
    if type(id) == 'string' and id:sub(1, 8) == 'discord:' then
      local did = id:sub(9):gsub('%s+', '')
      if did ~= '' then return did end
    end
  end

  
  local did
  local ok, v = pcall(function() return fw:getDiscordID(src) end)
  if ok and v then
    did = tostring(v):gsub('^discord:', ''):gsub('%s+', '')
    if did ~= '' then return did end
  end

  
  return ''
end

getCharName = function(src)
  
  if exports['Az-Framework'] and exports['Az-Framework'].GetPlayerCharacterNameSync then
    local ok, name, err = pcall(function()
      local n, e = exports['Az-Framework']:GetPlayerCharacterNameSync(src)
      return n, e
    end)
    if ok and name and tostring(name) ~= '' then
      return tostring(name)
    end
    if DEBUG then
      dprint('GetPlayerCharacterNameSync failed', 'name='..tostring(name), 'err='..tostring(err))
    end
  end

  
  if fw and type(fw.GetPlayerCharacterName) == 'function' then
    local p = promise.new()
    local done = false

    local function resolve(v)
      if done then return end
      done = true
      p:resolve(v)
    end

    SetTimeout(1200, function()
      resolve(nil)
    end)

    local ok = pcall(function()
      fw:GetPlayerCharacterName(src, function(err, name)
        if err then
          resolve(nil)
          return
        end
        resolve(name)
      end)
    end)

    if ok then
      local name = Citizen.Await(p)
      if name and tostring(name) ~= '' then
        return tostring(name)
      end
    end
  end

  return GetPlayerName(src) or 'Unknown'
end


local fw = nil

local function getFw()
  if fw then return fw end
  local res = 'Az-Framework'
  if GetResourceState(res) ~= 'started' then return nil end
  fw = exports[res]
  return fw
end



local function isAdmin(src, cb)
  local afw = getFw()
  if not afw or not afw.isAdmin then
    if cb then cb(false) end
    return false
  end

  
  if cb then
    return afw:isAdmin(src, cb)
  end

  
  local done, result = false, false
  afw:isAdmin(src, function(ok)
    result = (ok == true)
    done = true
  end)

  local timeoutMs = 1500
  local start = GetGameTimer()
  while not done and (GetGameTimer() - start) < timeoutMs do
    Wait(0)
  end

  return result
end


local function playerIdentifiersForHouse(src)
  local did = getDiscordId(src)
  local cid = getCharId(src)
  local list = {}
  if did and did ~= '' then
    list[#list+1] = did
    
    if not did:find(':') then
      list[#list+1] = 'discord:' .. did
    elseif did:find('^discord:') == 1 then
      list[#list+1] = did:gsub('^discord:', '')
    end
  end
  if cid and cid ~= '' then
    list[#list+1] = cid
  end
  return list
end




local function getMyVehicles(src)
  local did = getDiscordId(src)
  if did == '' then return {} end

  local rows = awaitQuery(('SELECT id, plate, model, parked FROM `%s` WHERE discordid = ? ORDER BY id DESC LIMIT 200'):format(T_VEH), { did })
  rows = rows or {}

  for _, r in ipairs(rows) do
    r.plate = tostring(r.plate or '')
    r.model = tostring(r.model or '')
    r.parked = (tonumber(r.parked) or 0) == 1
  end

  return rows
end

local function getMyHousesAndRentals(src)
  local vals = playerIdentifiersForHouse(src)
  if #vals == 0 then return { houses = {}, rentals = {} } end

  
  local q = ('SELECT id, name, label, price, interior, locked, %s as owner_identifier FROM `%s` WHERE %s IN (%s) ORDER BY id DESC LIMIT 200')
    :format(H_OWNER_COL, T_HOU, H_OWNER_COL, table.concat((function()
      local t = {}
      for i = 1, #vals do t[i] = '?' end
      return t
    end)(), ','))

  local rows = awaitQuery(q, vals) or {}

  local houseIds = {}
  for _, r in ipairs(rows) do
    houseIds[#houseIds+1] = tonumber(r.id)
  end

  local rentals = {}
  if #houseIds > 0 then
    local ph = {}
    for i = 1, #houseIds do ph[i] = '?' end
    local rq = ('SELECT r.house_id, r.is_listed, r.rent_per_week, r.deposit, r.tenant_identifier, r.agent_identifier, r.status, h.name, h.label, h.price FROM `%s` r JOIN `%s` h ON h.id = r.house_id WHERE r.house_id IN (%s) ORDER BY r.house_id DESC')
      :format(T_RENT, T_HOU, table.concat(ph, ','))
    rentals = awaitQuery(rq, houseIds) or {}
  end

  return { houses = rows, rentals = rentals }
end




local function normalizeImages(images)
  if type(images) ~= 'table' then return {} end
  local out = {}
  local max = clampInt(Config.MaxImages or 4, 1, 8)
  local maxBytes = clampInt(Config.MaxImageBytes or 900000, 200000, 2000000)

  for _, img in ipairs(images) do
    if #out >= max then break end
    if type(img) == 'string' and img:find('^data:image') then
      
      if #img <= (maxBytes * 1.6) then
        out[#out+1] = img
      end
    end
  end

  return out
end

local function makeListingSummary(row)
  local images = safeJsonDecode(row.images, {})
  local first = images and images[1] or nil

  return {
    id = tonumber(row.id),
    listing_type = row.listing_type,
    category = row.category,
    title = row.title,
    price = tonumber(row.price) or 0,
    currency = row.currency or '$',
    location_label = row.location_label or '',
    seller_name = row.seller_name or 'Seller',
    created_at = row.created_at,
    status = row.status,
    image = first,
  }
end

local function listListings(src, filters)
  filters = filters or {}

  
  local ped = GetPlayerPed(src)
  local pcoords = ped and GetEntityCoords(ped) or vector3(0, 0, 0)
  local radiusKm = tonumber(filters.radiusKm or filters.radius_km or filters.radius or Config.DefaultRadiusKm or 65) or 65
  local maxRadius = tonumber(Config.MaxRadiusKm or 250) or 250
  if radiusKm < 1 then radiusKm = 1 end
  if radiusKm > maxRadius then radiusKm = maxRadius end
  local radiusMeters = radiusKm * 1000.0
  local radiusSq = radiusMeters * radiusMeters

  local q = 'SELECT id, listing_type, category, title, price, currency, images, location_label, seller_name, created_at, status, location_x, location_y FROM `' .. T_LIST .. '` WHERE status = "active"'
  local params = {}

  local cat = tostring(filters.category or 'all')
  if cat ~= 'all' then
    if cat == 'vehicles' then
      q = q .. ' AND listing_type = "vehicle"'
    elseif cat == 'property' then
      q = q .. ' AND listing_type = "house"'
    elseif cat == 'rentals' then
      q = q .. ' AND listing_type = "rental"'
    else
      q = q .. ' AND category = ?'
      params[#params+1] = cat
    end
  end

  local search = strTrim(filters.search or '')
  if search ~= '' then
    q = q .. ' AND (title LIKE ? OR description LIKE ?)'
    params[#params+1] = '%' .. search .. '%'
    params[#params+1] = '%' .. search .. '%'
  end

  local sort = tostring(filters.sort or Config.DefaultSort or 'newest')
  if sort == 'price_low' then
    q = q .. ' ORDER BY price ASC, id DESC'
  elseif sort == 'price_high' then
    q = q .. ' ORDER BY price DESC, id DESC'
  else
    q = q .. ' ORDER BY id DESC'
  end

  q = q .. ' LIMIT 200'

  local rows = awaitQuery(q, params) or {}
  local out = {}

  for _, r in ipairs(rows) do
    
    local lx = tonumber(r.location_x) or 0
    local ly = tonumber(r.location_y) or 0
    local dx = (lx - (pcoords.x or 0))
    local dy = (ly - (pcoords.y or 0))
    local distSq = (dx * dx) + (dy * dy)
    if distSq <= radiusSq then
      out[#out+1] = makeListingSummary(r)
    end
  end

  return out
end

local function getListing(id, viewerDiscord)
  id = tonumber(id)
  if not id then return nil end
  local rows = awaitQuery(('SELECT * FROM `%s` WHERE id = ? LIMIT 1'):format(T_LIST), { id })
  local row = rows and rows[1] or nil
  if not row then return nil end

  local images = safeJsonDecode(row.images, {})
  local source = safeJsonDecode(row.source_json, {})

  local sellerDiscord = tostring(row.seller_discord or '')
  local isMe = (viewerDiscord and viewerDiscord ~= '' and sellerDiscord ~= '' and sellerDiscord == tostring(viewerDiscord)) and true or false

  return {
    id = tonumber(row.id),
    listing_type = row.listing_type,
    category = row.category,
    title = row.title,
    price = tonumber(row.price) or 0,
    currency = row.currency or '$',
    condition = row.condition,
    description = row.description,
    images = images,
    location = { x = tonumber(row.location_x) or 0, y = tonumber(row.location_y) or 0, z = tonumber(row.location_z) or 0 },
    location_label = row.location_label or '',

    
    seller_discord = sellerDiscord,
    seller_charid = row.seller_charid,
    seller_name = row.seller_name or 'Seller',
    is_me = isMe,

    
    seller = {
      discord = sellerDiscord,
      charid = row.seller_charid,
      name = row.seller_name or 'Seller'
    },

    source_ref = row.source_ref,
    source = source,
    status = row.status,
    created_at = row.created_at,
    updated_at = row.updated_at,
  }
end

local function createListing(src, data)
  data = data or {}

  
  eprint('createListing:start', 'src='..tostring(src))

  local did = getDiscordId(src)
  if did == '' then
    return false, 'Discord not linked'
  end

  eprint('createListing:ident', 'did='..tostring(did), 'cid='..tostring(getCharId(src) or ''))

  local cid = getCharId(src)
  local cname = getCharName(src) or GetPlayerName(src) or 'Unknown'

  local ltype = tostring(data.listing_type or 'item')
  if not (ltype == 'item' or ltype == 'vehicle' or ltype == 'house' or ltype == 'rental') then
    ltype = 'item'
  end

  local category = tostring(data.category or 'classifieds')
  local title = strTrim(data.title)
  local price = clampInt(data.price or 0, 0, 2147483647)
  local cond = tostring(data.condition or 'Used - Good')
  local desc = strTrim(data.description)

  if #title < 2 or #title > clampInt(Config.MaxTitle or 64, 16, 96) then
    return false, 'Invalid title'
  end

  if #desc > clampInt(Config.MaxDescription or 800, 200, 2000) then
    desc = desc:sub(1, clampInt(Config.MaxDescription or 800, 200, 2000))
  end

  local images = normalizeImages(data.images or {})
  local imagesJson = safeJsonEncode(images)

  local ped = GetPlayerPed(src)
  local coords = GetEntityCoords(ped)
  local locLabel = strTrim(data.location_label or Config.DefaultLocationLabel or 'Los Santos')

  local sourceRef = nil
  local source = {}

  
if ltype == 'vehicle' then
  local vehId = tonumber(data.source_ref or data.vehicle_id)
  if not vehId then return false, 'Missing vehicle id' end

  eprint('createListing:vehicle', 'vehId='..tostring(vehId), 'did='..tostring(did))

  local okOwn = false
  if isAdmin(src) then okOwn = true end

  if not okOwn then
    local rows = awaitQuery(
      ('SELECT id, plate, model FROM `%s` WHERE discordid = ? AND id = ? LIMIT 1'):format(T_VEH),
      { did, vehId }
    )
    if isDbTimeout(rows) then return false, 'Database timeout (vehicles)' end
    if isDbError(rows) then return false, 'Database error (vehicles)' end

    local r = rows and rows[1]
    if r then
      okOwn = true
      source = { vehicle_id = tonumber(r.id), plate = tostring(r.plate), model = tostring(r.model) }
      sourceRef = tostring(r.plate) 
    end
  end


  if not okOwn then return false, 'You do not own that vehicle' end
  sourceRef = plate


  elseif ltype == 'house' then
    local houseId = tonumber(data.source_ref or data.house_id)
    if not houseId then return false, 'Missing house id' end

    eprint('createListing:house', 'houseId='..tostring(houseId))

    eprint('createListing:house', 'house_id='..tostring(houseId))

    local okOwn = false
    if isAdmin(src) then okOwn = true end
    if not okOwn then
      local vals = playerIdentifiersForHouse(src)
      if #vals > 0 then
        local ph = {}
        for i = 1, #vals do ph[i] = '?' end
        local q = ('SELECT id, name, label, price FROM `%s` WHERE id = ? AND %s IN (%s) LIMIT 1'):format(T_HOU, H_OWNER_COL, table.concat(ph, ','))
        local params = { houseId }
        for i = 1, #vals do params[#params+1] = vals[i] end
        eprint('createListing:db', 'check house ownership')
        local rows = awaitQuery(q, params)
        if isDbTimeout(rows) then return false, 'Database timeout (houses)' end
        if isDbError(rows) then return false, 'Database error (houses)' end
        local r = rows and rows[1]
        if r then
          okOwn = true
          source = { house_id = tonumber(r.id), name = tostring(r.name), label = tostring(r.label or ''), price = tonumber(r.price) or 0 }
        end
      end
    end

    if not okOwn then return false, 'You do not own that house' end
    sourceRef = tostring(houseId)

  elseif ltype == 'rental' then
    local houseId = tonumber(data.source_ref or data.house_id)
    if not houseId then return false, 'Missing house id' end

    eprint('createListing:rental', 'houseId='..tostring(houseId))

    eprint('createListing:rental', 'houseId='..tostring(houseId))

    eprint('createListing:rental', 'house_id='..tostring(houseId))

    local okOwn = false
    if isAdmin(src) then okOwn = true end
    local vals = playerIdentifiersForHouse(src)

    if not okOwn and #vals > 0 then
      local ph = {}
      for i = 1, #vals do ph[i] = '?' end

      local q = ('SELECT h.id, h.name, h.label, h.price, r.is_listed, r.rent_per_week, r.deposit, r.status FROM `%s` h LEFT JOIN `%s` r ON r.house_id = h.id WHERE h.id = ? AND h.%s IN (%s) LIMIT 1')
        :format(T_HOU, T_RENT, H_OWNER_COL, table.concat(ph, ','))

      local params = { houseId }
      for i = 1, #vals do params[#params+1] = vals[i] end

      eprint('createListing:db', 'check rental ownership')
      local rows = awaitQuery(q, params)
      if isDbTimeout(rows) then return false, 'Database timeout (rentals)' end
      if isDbError(rows) then return false, 'Database error (rentals)' end
      local r = rows and rows[1]
      if r then
        okOwn = true
        source = {
          house_id = tonumber(r.id),
          name = tostring(r.name),
          label = tostring(r.label or ''),
          rent_per_week = tonumber(r.rent_per_week) or 0,
          deposit = tonumber(r.deposit) or 0,
          rental_status = tostring(r.status or 'available'),
          is_listed = (tonumber(r.is_listed) or 0) == 1
        }
      end
    end

    if not okOwn then return false, 'You do not own that rental' end
    sourceRef = tostring(houseId)
  end

  local sourceJson = safeJsonEncode(source)

  eprint('createListing:db', 'insert listing')
  eprint('createListing:insert', 'type='..ltype, 'cat='..category, 'seller='..tostring(did))
  dprint('createListing: inserting row', 'type='..ltype, 'cat='..category, 'seller='..tostring(did))
  local ins = awaitInsert(([[
    INSERT INTO `%s`
      (listing_type, category, title, price, currency, `condition`, description, images,
       location_x, location_y, location_z, location_label,
       seller_discord, seller_charid, seller_name,
       source_ref, source_json, status)
    VALUES
      (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active')
  ]]):format(T_LIST), {
    ltype, category, title, price, '$', cond, desc, imagesJson,
    coords.x, coords.y, coords.z, locLabel,
    did, cid, cname,
    sourceRef, sourceJson
  })

  if isDbTimeout(ins) then return false, 'Database timeout (create listing)' end
  if isDbError(ins) then return false, 'Database error (create listing)' end

  local newId
  if type(ins) == 'number' then newId = ins end
  if type(ins) == 'table' and ins.insertId then newId = ins.insertId end

  
  newId = tonumber(newId) or tonumber(ins and ins.insertId) or nil

  if not newId then
    
    local r = awaitQuery('SELECT LAST_INSERT_ID() as id', {})
    newId = r and tonumber(r[1] and r[1].id)
  end

  if not newId then
    eprint('createListing:fail', 'no insert id')
    return false, 'Failed to create listing'
  end

  eprint('createListing:ok', 'id='..tostring(newId))

  
  TriggerClientEvent('az_marketplace:cl:push', -1, 'listingCreated', { id = newId })

  return true, { id = newId }
end

local function deleteListing(src, listingId)
  listingId = tonumber(listingId)
  if not listingId then return false, 'Invalid id' end

  local did = getDiscordId(src)
  if did == '' then return false, 'Discord not linked' end

  local row = getListing(listingId)
  if not row then return false, 'Not found' end

local allowAdmin = (Config.AdminCanModerate ~= false) 
local admin = (allowAdmin and isAdmin(src)) == true

if row.seller.discord ~= did and not admin then
  return false, 'No permission'
end

  awaitExecute(('UPDATE `%s` SET status = "removed" WHERE id = ?'):format(T_LIST), { listingId })
  TriggerClientEvent('az_marketplace:cl:push', -1, 'listingDeleted', { id = listingId })
  return true, true
end

local function markSold(src, listingId)
  listingId = tonumber(listingId)
  if not listingId then return false, 'Invalid id' end

  local did = getDiscordId(src)
  if did == '' then return false, 'Discord not linked' end

  local row = getListing(listingId)
  if not row then return false, 'Not found' end

local allowAdmin = (Config.AdminCanModerate ~= false) 
local admin = (allowAdmin and isAdmin(src)) == true

if row.seller.discord ~= did and not admin then
  return false, 'No permission'
end
  awaitExecute(('UPDATE `%s` SET status = "sold" WHERE id = ?'):format(T_LIST), { listingId })
  TriggerClientEvent('az_marketplace:cl:push', -1, 'listingSold', { id = listingId })
  return true, true
end

local function listMyListings(src)
  local did = getDiscordId(src)
  if did == '' then return {} end
  local rows = awaitQuery(('SELECT id, listing_type, category, title, price, currency, images, location_label, seller_name, created_at, status FROM `%s` WHERE seller_discord = ? ORDER BY id DESC LIMIT 200'):format(T_LIST), { did }) or {}
  local out = {}
  for _, r in ipairs(rows) do
    out[#out+1] = makeListingSummary(r)
  end
  return out
end




local function sendPushToDiscord(discordId, eventName, payload)
  
  for _, pid in ipairs(GetPlayers()) do
    local src = tonumber(pid)
    if src then
      local did = getDiscordId(src)
      if did == discordId then
        TriggerClientEvent('az_marketplace:cl:push', src, eventName, payload)
      end
    end
  end
end

local function inboxList(src)
  local did = getDiscordId(src)
  if did == '' then return {} end

  
  local q = ([[
    SELECT
      m.listing_id,
      m.seller_discord,
      m.buyer_discord,
      MAX(m.id) as last_id,
      MAX(m.created_at) as last_at
    FROM `%s` m
    WHERE m.seller_discord = ? OR m.buyer_discord = ?
    GROUP BY m.listing_id, m.seller_discord, m.buyer_discord
    ORDER BY last_id DESC
    LIMIT 200
  ]]):format(T_MSG)

  local rows = awaitQuery(q, { did, did }) or {}

  local out = {}
  for _, r in ipairs(rows) do
    local seller = tostring(r.seller_discord)
    local buyer  = tostring(r.buyer_discord)
    local other  = (seller == did) and buyer or seller

    
    local last = awaitQuery(('SELECT message, sender_discord, created_at FROM `%s` WHERE id = ? LIMIT 1'):format(T_MSG), { tonumber(r.last_id) })
    local lastRow = last and last[1]

    local listing = awaitQuery(('SELECT id, title, price, currency, images, listing_type, category, status FROM `%s` WHERE id = ? LIMIT 1'):format(T_LIST), { tonumber(r.listing_id) })
    local lrow = listing and listing[1]

    local img = nil
    if lrow then
      local imgs = safeJsonDecode(lrow.images, {})
      img = imgs and imgs[1] or nil
    end

    out[#out+1] = {
      listing_id = tonumber(r.listing_id),
      seller_discord = seller,
      buyer_discord = buyer,
      other_discord = other,
      last_message = lastRow and lastRow.message or '',
      last_sender = lastRow and lastRow.sender_discord or '',
      last_at = lastRow and lastRow.created_at or r.last_at,
      listing = lrow and {
        id = tonumber(lrow.id),
        title = lrow.title,
        price = tonumber(lrow.price) or 0,
        currency = lrow.currency or '$',
        image = img,
        listing_type = lrow.listing_type,
        category = lrow.category,
        status = lrow.status,
      } or nil
    }
  end

  return out
end

local function inboxThread(src, listingId, otherDiscord)
  local did = getDiscordId(src)
  if did == '' then return false, 'Discord not linked' end
  listingId = tonumber(listingId)
  if not listingId then return false, 'Invalid listing id' end
  otherDiscord = tostring(otherDiscord or '')
  if otherDiscord == '' then return false, 'Missing other user' end

  
  local listing = getListing(listingId)
  if not listing then return false, 'Listing not found' end

  local seller = listing.seller.discord
  local buyer  = (seller == did) and otherDiscord or did

  
  if not ((did == seller and otherDiscord == buyer) or (did == buyer and otherDiscord == seller)) then
    return false, 'Not allowed'
  end

  local rows = awaitQuery(([[
    SELECT id, listing_id, seller_discord, buyer_discord, sender_discord, message, created_at
    FROM `%s`
    WHERE listing_id = ? AND seller_discord = ? AND buyer_discord = ?
    ORDER BY id ASC
    LIMIT 500
  ]]):format(T_MSG), { listingId, seller, buyer }) or {}

  return true, {
    listing = listing,
    seller_discord = seller,
    buyer_discord = buyer,
    messages = rows
  }
end

local function inboxSend(src, listingId, message)
  local did = getDiscordId(src)
  if did == '' then return false, 'Discord not linked' end

  listingId = tonumber(listingId)
  if not listingId then return false, 'Invalid listing id' end

  message = strTrim(message)
  if message == '' then return false, 'Empty message' end
  message = message:sub(1, clampInt(Config.MaxMessage or 900, 200, 2000))

  local listing = getListing(listingId)
  if not listing then return false, 'Listing not found' end

  local seller = listing.seller.discord
  local buyer = (did == seller) and tostring(listing.source and listing.source.last_contact or '') or did

  
  
  return false, 'Use inboxSendTo for seller replies'
end

local function inboxSendTo(src, listingId, targetDiscord, message)
  local did = getDiscordId(src)
  if did == '' then return false, 'Discord not linked' end

  listingId = tonumber(listingId)
  if not listingId then return false, 'Invalid listing id' end

  targetDiscord = tostring(targetDiscord or '')
  if targetDiscord == '' then return false, 'Missing target' end

  message = strTrim(message)
  if message == '' then return false, 'Empty message' end
  message = message:sub(1, clampInt(Config.MaxMessage or 900, 200, 2000))

  local listing = getListing(listingId)
  if not listing then return false, 'Listing not found' end

  local seller = listing.seller.discord
  local buyer

  if did == seller then
    buyer = targetDiscord
  else
    buyer = did
  end

  
  if did ~= seller and did ~= buyer then
    return false, 'Not allowed'
  end

  if seller == buyer then
    return false, 'Invalid thread'
  end

  awaitExecute(([[
    INSERT INTO `%s` (listing_id, seller_discord, buyer_discord, sender_discord, message)
    VALUES (?, ?, ?, ?, ?)
  ]]):format(T_MSG), { listingId, seller, buyer, did, message })

  local payload = {
    listing_id = listingId,
    seller_discord = seller,
    buyer_discord = buyer,
    sender_discord = did,
    message = message,
    created_at = os.date('!%Y-%m-%d %H:%M:%S')
  }

  
  sendPushToDiscord(seller, 'messageNew', payload)
  sendPushToDiscord(buyer, 'messageNew', payload)

  return true, true
end




RegisterNetEvent('az_marketplace:sv:request', function(reqId, action, data)
  local src = source
  local t0 = GetGameTimer()
  local replied = false

  if not hasOx() then
    TriggerClientEvent('az_marketplace:cl:response', src, reqId, false, { error = 'oxmysql missing' })
    return
  end

  local function reply(success, out)
    if replied then return end
    replied = true
    TriggerClientEvent('az_marketplace:cl:response', src, reqId, success, out)
    if DEBUG then
      dprint('RPC reply', reqId, action, 'ok='..tostring(success), ('%dms'):format(GetGameTimer() - t0))
    end
  end

  
  
  local watchdogMs = tonumber(Config and Config.ServerRpcTimeoutMs) or 8000
  SetTimeout(watchdogMs, function()
    if replied then return end
    eprint('RPC TIMEOUT', 'reqId='..tostring(reqId), 'action='..tostring(action), 'src='..tostring(src))
    reply(false, { error = 'Server request timed out (check oxmysql/DB). See server console for details.' })
  end)

  action = tostring(action or '')
  data = data or {}

  if DEBUG then
    dprint('RPC recv', reqId, action, 'src='..tostring(src))
  end

  
  if action == 'createListing' then action = 'listings:create' end
  if action == 'getListing' then action = 'listings:get' end
  if action == 'listListings' then action = 'listings:list' end

  local s, err = pcall(function()
    if action == 'bootstrap' then
      local did = getDiscordId(src)
      local cid = getCharId(src)
      local name = getCharName(src) or GetPlayerName(src) or 'Unknown'
      local admin = isAdmin(src)

      reply(true, {
        me = {
          discord = did,
          charid = cid,
          name = name,
          isAdmin = admin
        },
        config = {
          categories = Config.Categories or {},
          conditions = Config.Conditions or {},
          listingTypes = Config.ListingTypes or {},
          defaultSort = Config.DefaultSort or 'newest',
          defaultRadiusKm = Config.DefaultRadiusKm or 65,
          maxRadiusKm = Config.MaxRadiusKm or 250,
          maxImages = Config.MaxImages or 4,
          defaultLocationLabel = Config.DefaultLocationLabel or 'Los Santos',
          screenshotsEnabled = (Config.Screenshot and Config.Screenshot.Enabled) and true or false,
          adminCanModerate = (Config.AdminCanModerate ~= false),

        }
      })

    elseif action == 'listings:list' then
      local out = listListings(src, data)
      reply(true, out)

    elseif action == 'listings:get' then
      local l = getListing(data.id, getDiscordId(src))
      if not l then reply(false, { error = 'Not found' }) return end
      reply(true, l)

    elseif action == 'listings:mine' then
      reply(true, listMyListings(src))

    elseif action == 'listings:create' then
      local ok2, out = createListing(src, data)
      if not ok2 then reply(false, { error = out }) return end
      reply(true, out)

    elseif action == 'listings:delete' then
      local ok2, out = deleteListing(src, data.id)
      if not ok2 then reply(false, { error = out }) return end
      reply(true, out)

    elseif action == 'listings:sold' then
      local ok2, out = markSold(src, data.id)
      if not ok2 then reply(false, { error = out }) return end
      reply(true, out)

    elseif action == 'sources:vehicles' then
      reply(true, getMyVehicles(src))

    elseif action == 'sources:houses' then
      reply(true, getMyHousesAndRentals(src))

    elseif action == 'inbox:list' then
      reply(true, inboxList(src))

    elseif action == 'inbox:thread' then
      local ok2, out = inboxThread(src, data.listing_id, data.other_discord)
      if not ok2 then reply(false, { error = out }) return end
      reply(true, out)

    elseif action == 'inbox:send' then
      local ok2, out = inboxSendTo(src, data.listing_id, data.target_discord, data.message)
      if not ok2 then reply(false, { error = out }) return end
      reply(true, out)

    else
      reply(false, { error = 'Unknown action: ' .. action })
    end
  end)

  if not s then
    dprint('RPC error', action, err)
    reply(false, { error = 'Server error' })
  end
end)
