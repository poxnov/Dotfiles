local cache      = {
  vpnEnabled = hs.settings.get('vpnEnabled') or false,
  vpnName    = hs.settings.get('vpnName') or controlplane.vpns[1]
}
local module     = { cache = cache }

local vpnTimeout = 10 -- timeout before re-connecting to VPN

local notify     = require('utils.controlplane.notify')

local iconOff    = os.getenv('HOME') .. '/.hammerspoon/assets/vpn-off.png'
local iconOn     = os.getenv('HOME') .. '/.hammerspoon/assets/vpn-on.png'

local openVPNSettings = function()
  local name = cache.vpnName

  hs.applescript.applescript([[
    tell application "System Preferences"
      activate
      set the current pane to pane id "com.apple.preference.network"
      reveal anchor "]] .. name .. [[" of pane id "com.apple.preference.network"
    end tell
  ]])
end

local isVPNConnected = function()
  local name = cache.vpnName

  local _, res = hs.applescript.applescript([[
    tell application "System Events"
      tell current location of network preferences
        set connection to the service "]] .. name .. [["
        set config to the current configuration of connection

        if config is connected then
          return 1
        else
          return 0
        end if
      end tell
    end tell
  ]])

  return res == 1
end

local connectVPN = function()
  local name = cache.vpnName

  hs.applescript.applescript([[
    tell application "System Events"
      tell current location of network preferences
        connect the service "]] .. name .. [["
      end tell
    end tell
  ]])

  -- give VPN some time to connect
  cache.connecting = true
  hs.timer.doAfter(vpnTimeout, function()
    cache.connecting = false
  end)

  notify('Connecting to ' .. name .. '...')
end

local disconnectVPN = function()
  local name = cache.vpnName

  hs.applescript.applescript([[
    tell application "System Events"
      tell current location of network preferences
        disconnect the service "]] .. name .. [["
      end tell
    end tell
  ]])

  cache.connecting = false

  notify('Disconnecting from ' .. name .. '...')
end

local updateMenuItem = function(isConnected)
  if isConnected then
    cache.menuItem
      :setMenu({
        {
          title = cache.vpnName .. ': Connected',
          disabled = true
        },
        {
          title = 'Disconnect',
          fn = function() cache.vpnEnabled = false end
        },
        { title = '-' },
        {
          title = 'Open VPN Preferences...',
          fn = openVPNSettings
        }
      })
  else
    local vpnSubmenu = {}

    hs.fnutils.each(controlplane.vpns, function(vpn)
      table.insert(vpnSubmenu, {
        title = vpn,
        fn = function()
          cache.vpnName    = vpn
          cache.vpnEnabled = true
        end
      })
    end)

    cache.menuItem
      :setMenu({
        {
          title = 'VPN: Disconnected',
          disabled = true
        },
        {
          title = 'Connect',
          menu = vpnSubmenu
        },
        { title = '-' },
        {
          title = 'Open VPN Preferences...',
          fn = openVPNSettings
        }
      })
  end

  cache.menuItem:setIcon(isConnected and iconOn or iconOff)
end

local checkTrustedNetwork = function()
  local currrentNetwork = hs.wifi.currentNetwork()

  if not currrentNetwork then return end

  local isInTrustedNetwork = hs.fnutils.some(controlplane.trustedNetworks, function(network)
    return network == currrentNetwork
  end)

  cache.vpnEnabled = not isInTrustedNetwork
end

module.start = function()
  -- create menu icon
  cache.menuItem = hs.menubar.new()

  -- setup
  checkTrustedNetwork()
  updateMenuItem(isVPNConnected())

  -- watch for updates - would be great if we could get notifications on VPN change
  cache.timerHandle = hs.timer.doEvery(1, function()
    local isOnline    = hs.network.reachability.internet():status() == 2
    local updateMenu  = false
    local isConnected = isVPNConnected()
    local vpnEnabled  = cache.vpnEnabled

    -- we don't care about VPN if there's no internet connection
    if not isOnline and not cache.wasOnline then
      return
    end

    -- if something changed then update menu to be safe
    if cache.wasOnline ~= isOnline or cache.wasConnected ~= isConnected then
      updateMenu = true
    end

    -- connect if not connected and should be
    if isOnline and vpnEnabled and not (cache.connecting or isConnected) then
      connectVPN()
      updateMenu = true
    end

    -- disconnected if connected and shouldn't be
    if isOnline and not vpnEnabled and isConnected then
      disconnectVPN()
      updateMenu = true
    end

    -- update menu if needed
    if updateMenu then
      updateMenuItem(isConnected)
    end

    -- save previous status
    cache.wasOnline    = isOnline
    cache.wasConnected = isConnected
  end)

  -- auto connect on untrusted networks
  cache.wifiWatcher = hs.wifi.watcher.new(checkTrustedNetwork):start()
end

module.stop = function()
  -- store last vpn status
  hs.settings.set('vpnEnabled', cache.vpnEnabled)
  hs.settings.set('vpnName', cache.vpnName)

  cache.timerHandle:stop()
  cache.wifiWatcher:stop()
end

return module
