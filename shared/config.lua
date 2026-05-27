Config = Config or {}

Config.Debug = (Config.Debug == true)


Config.Command = 'market'
Config.Keybind = 'L'


Config.MaxImages = 4
Config.MaxImageBytes = 900000      
Config.MaxDescription = 800
Config.MaxTitle = 64
Config.MaxMessage = 900


Config.DefaultLocationLabel = 'Los Santos'
Config.AdminCanModerate = true

Config.Categories = {
  { id = 'all',          label = 'Browse all',      icon = 'fa-store' },
  { id = 'vehicles',     label = 'Vehicles',        icon = 'fa-car' },
  { id = 'property',     label = 'Property',        icon = 'fa-house' },
  { id = 'rentals',      label = 'Property Rentals',icon = 'fa-key' },
  { id = 'electronics',  label = 'Electronics',     icon = 'fa-tv' },
  { id = 'apparel',      label = 'Apparel',         icon = 'fa-shirt' },
  { id = 'classifieds',  label = 'Classifieds',     icon = 'fa-tags' },
}


Config.ListingTypes = {
  item    = { label = 'Item',    icon='fa-tag' },
  vehicle = { label = 'Vehicle', icon='fa-car' },
  house   = { label = 'House',   icon='fa-house' },
  rental  = { label = 'Rental',  icon='fa-key' },
}


Config.Conditions = {
  'New',
  'Used - Like New',
  'Used - Good',
  'Used - Fair'
}


Config.DB = Config.DB or {}
Config.DB.ListingsTable = 'az_marketplace_listings'
Config.DB.MessagesTable = 'az_marketplace_messages'

Config.DB.VehiclesTable = 'user_vehicles'
Config.DB.HousesTable   = 'az_houses'
Config.DB.RentalsTable  = 'az_house_rentals'


Config.DB.HouseOwnerColumn = 'owner_identifier'


Config.DefaultSort = 'newest'  


Config.DefaultRadiusKm = 65
Config.MaxRadiusKm = 250


Config.Screenshot = Config.Screenshot or {}
Config.Screenshot.Enabled = true
Config.Screenshot.Format = 'jpeg' 


Config.NotifyOnNewMessage = true

