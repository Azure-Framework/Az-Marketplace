Config = Config or {}

Config.Debug = (Config.Debug == true)

-- Commands / keybind
Config.Command = 'market'
Config.Keybind = 'L'

-- Listing limits
Config.MaxImages = 4
Config.MaxImageBytes = 900000      -- ~0.9MB per image (base64 payload bytes)
Config.MaxDescription = 800
Config.MaxTitle = 64
Config.MaxMessage = 900

-- Approx location label shown in UI
Config.DefaultLocationLabel = 'Los Santos'
Config.AdminCanModerate = true
-- Main marketplace categories
Config.Categories = {
  { id = 'all',          label = 'Browse all',      icon = 'fa-store' },
  { id = 'vehicles',     label = 'Vehicles',        icon = 'fa-car' },
  { id = 'property',     label = 'Property',        icon = 'fa-house' },
  { id = 'rentals',      label = 'Property Rentals',icon = 'fa-key' },
  { id = 'electronics',  label = 'Electronics',     icon = 'fa-tv' },
  { id = 'apparel',      label = 'Apparel',         icon = 'fa-shirt' },
  { id = 'classifieds',  label = 'Classifieds',     icon = 'fa-tags' },
}

-- Listing types
Config.ListingTypes = {
  item    = { label = 'Item',    icon='fa-tag' },
  vehicle = { label = 'Vehicle', icon='fa-car' },
  house   = { label = 'House',   icon='fa-house' },
  rental  = { label = 'Rental',  icon='fa-key' },
}

-- Condition options
Config.Conditions = {
  'New',
  'Used - Like New',
  'Used - Good',
  'Used - Fair'
}

-- Table names (your dump shows these)
Config.DB = Config.DB or {}
Config.DB.ListingsTable = 'az_marketplace_listings'
Config.DB.MessagesTable = 'az_marketplace_messages'

Config.DB.VehiclesTable = 'user_vehicles'
Config.DB.HousesTable   = 'az_houses'
Config.DB.RentalsTable  = 'az_house_rentals'

-- House ownership column; value may be discord id, 'discord:<id>', or charid depending on your setup.
Config.DB.HouseOwnerColumn = 'owner_identifier'

-- UI + listing sorting
Config.DefaultSort = 'newest'  -- newest | price_low | price_high

-- Map radius filter (km) - purely cosmetic (distance between player and listing coords)
Config.DefaultRadiusKm = 65
Config.MaxRadiusKm = 250

-- Screenshot capture
Config.Screenshot = Config.Screenshot or {}
Config.Screenshot.Enabled = true
Config.Screenshot.Format = 'jpeg' -- screenshot-basic typically returns jpeg

-- Message notifications
Config.NotifyOnNewMessage = true

