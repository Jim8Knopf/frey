# WiFi Access Point Role

This role configures a Raspberry Pi to act as a WiFi Access Point while maintaining its existing WiFi client connection. This dual-interface setup allows the Pi to both connect to an existing WiFi network (via wlan0) and provide its own WiFi network (via wlan1).

## Network Architecture

### Interface Configuration

- **wlan0**: Client interface (connects to existing WiFi)
  - Maintains your primary internet connection
  - Uses existing WiFi settings and WPA supplicant
  - Currently on 5GHz band (channel 40)
  - connect via this wifi to the PI

- **wlan1**: Access Point interface
  - Creates a new WiFi network
  - Uses 2.4GHz band (channel 6) to avoid interference with client connection
  - Network: 10.20.30.0/24
  - AP IP: 10.20.30.1

### Network Features

- Separate subnet for AP network (10.20.30.0/24)
- DHCP range: 10.20.30.50 - 10.20.30.150
- Local DNS resolution (.frey domain)
- Internet passthrough from wlan0 to AP clients
- Integration with frey's service discovery


## Implementation Details

### Safety Features

- Preserves existing WiFi connection on wlan0
- Uses different frequency bands for client and AP to avoid interference
- Includes checks to prevent disruption of primary connection
- Graceful handling of interface states and IP assignments

### Integration with Frey

- Part of the networking stack
- Compatible with other frey services
- Uses standard 10.20.x.x network scheme
- Supports service discovery and local DNS resolution

## Dependencies

- Requires two WiFi interfaces (wlan0 and wlan1)
- Needs hostapd and dnsmasq packages
- Requires root privileges for network configuration
- Compatible with Raspberry Pi hardware

## Usage Notes

1. Primary connection (wlan0) must remain active for internet connectivity
2. AP interface (wlan1) operates independently
3. Local services are accessible via .frey domain
4. Network configuration preserves existing connectivity