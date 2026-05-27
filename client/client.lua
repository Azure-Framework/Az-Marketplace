local RESOURCE = GetCurrentResourceName()

Config = Config or {}
local DEBUG = (Config.Debug == true)

local fw = exports['Az-Framework']

local uiOpen = false
local reqSeq = 0
local pending = {} 

local function dprint(...)
  if not DEBUG then return end
  print(('^3[%s:client]^7'):format(RESOURCE), ...)
end

local function nui(msg)
  SendNUIMessage(msg)
end

local function isInputBusy()
  if IsPauseMenuActive() then return true end
  if IsNuiFocused and IsNuiFocused() then return true end

  if LocalPlayer and LocalPlayer.state then
    if LocalPlayer.state.azChatOpen == true then return true end
    if LocalPlayer.state.azUiBusy == true then return true end
  end

  return false
end

local function setUI(state)
  uiOpen = state and true or false

  SetNuiFocus(uiOpen, uiOpen)
  if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end

  if LocalPlayer and LocalPlayer.state then
    LocalPlayer.state:set('azMarketplaceOpen', uiOpen, false)
    LocalPlayer.state:set('azUiBusy', uiOpen, false)
  end
end

CreateThread(function()
  while true do
    if uiOpen then
      DisableControlAction(0, 24, true)  
      DisableControlAction(0, 25, true)  
      DisableControlAction(0, 257, true) 
      DisableControlAction(0, 140, true) 
      DisableControlAction(0, 141, true) 
      DisableControlAction(0, 142, true) 
      DisableControlAction(0, 143, true) 
      DisableControlAction(0, 263, true) 
      DisableControlAction(0, 21, true)  
      DisableControlAction(0, 22, true)  
      DisableControlAction(0, 37, true)  
      DisablePlayerFiring(PlayerId(), true)
      Wait(0)
    else
      Wait(250)
    end
  end
end)




local function rpc(action, data, timeoutMs)
  reqSeq = reqSeq + 1
  local id = reqSeq
  local p = promise.new()
  pending[id] = p
  if DEBUG then
    dprint('RPC send', id, action)
  end
  TriggerServerEvent('az_marketplace:sv:request', id, action, data or {})

  
  
  timeoutMs = tonumber(timeoutMs) or (Config and Config.NuiTimeoutMs) or 15000
  SetTimeout(timeoutMs, function()
    if pending[id] == p then
      pending[id] = nil
      print(('^1[%s:client]^7 RPC TIMEOUT id=%s action=%s'):format(RESOURCE, tostring(id), tostring(action)))
      if uiOpen then
        nui({ type = 'push', event = 'notify', payload = { type = 'error', title = 'Marketplace', message = ('Request timeout (%s)'):format(tostring(action)) } })
      end
      p:resolve({ ok = false, data = { error = 'Request timeout' } })
    end
  end)

  local res = Citizen.Await(p)
  return res
end

RegisterNetEvent('az_marketplace:cl:response', function(id, ok, payload)
  local p = pending[id]
  if not p then return end
  pending[id] = nil
  p:resolve({ ok = ok, data = payload })
end)


RegisterNetEvent('az_marketplace:cl:push', function(eventName, payload)
  if not uiOpen then return end
  nui({ type = 'push', event = eventName, payload = payload })
end)




local function captureScreenshot()
  if not (Config.Screenshot and Config.Screenshot.Enabled) then
    return nil, 'Screenshot capture disabled'
  end

  if GetResourceState('screenshot-basic') ~= 'started' then
    return nil, 'screenshot-basic missing'
  end

  local p = promise.new()

  exports['screenshot-basic']:requestScreenshot(function(data)
    
    if not data or data == '' then
      p:resolve(nil)
      return
    end

    if type(data) == 'string' then
      if data:find('^data:image') then
        p:resolve(data)
      else
        p:resolve(('data:image/%s;base64,%s'):format(Config.Screenshot.Format or 'jpeg', data))
      end
    else
      p:resolve(nil)
    end
  end)

  local out = Citizen.Await(p)
  if not out then
    return nil, 'Failed to capture screenshot'
  end
  return out, nil
end




local function openMarket()
  if uiOpen then return end
  if isInputBusy() then return end

  setUI(true)
  nui({ type = 'open' })

  
  local res = rpc('bootstrap', {})
  if res.ok then
    nui({ type = 'bootstrap', ok = true, data = res.data })
  else
    
    
    nui({ type = 'bootstrap', ok = true, data = {
      me = {
        discord = nil,
        charid = nil,
        name = GetPlayerName(PlayerId()) or 'Player',
        isAdmin = false,
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
        bootstrapError = (res.data and res.data.error) or 'Bootstrap failed',
      }
    }})

    
    nui({ type = 'push', event = 'notify', payload = { type = 'error', title = 'Marketplace', message = (res.data and res.data.error) or 'Server bootstrap failed' } })
  end
end

local function closeMarket()
  if not uiOpen then return end
  setUI(false)
  nui({ type = 'close' })
end

RegisterCommand(Config.Command or 'market', function()
  openMarket()
end)

RegisterKeyMapping(Config.Command or 'market', 'Open Marketplace', 'keyboard', Config.Keybind or 'L')




RegisterNUICallback('close', function(_, cb)
  closeMarket()
  cb({ ok = true })
end)

RegisterNUICallback('request', function(body, cb)
  local action = body and body.action
  local data = body and body.data or {}

  if not action or action == '' then
    cb({ ok = false, error = 'Missing action' })
    return
  end

  local res = rpc(action, data)
  cb(res)
end)

RegisterNUICallback('addPhoto', function(_, cb)
  local shot, err = captureScreenshot()
  if not shot then
    cb({ ok = false, error = err or 'Screenshot failed' })
    return
  end
  cb({ ok = true, data = { image = shot } })
end)


AddEventHandler('onResourceStop', function(res)
  if res ~= RESOURCE then return end
  if uiOpen then
    SetNuiFocus(false, false)
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    TriggerScreenblurFadeOut(0)
  end
  if LocalPlayer and LocalPlayer.state then
    LocalPlayer.state:set('azMarketplaceOpen', false, false)
    LocalPlayer.state:set('azUiBusy', false, false)
  end
end)
