{ config, lib, pkgs, utils, ... }:

# TODO:
#
# asserts
#   ensure that the nl80211 module is loaded/compiled in the kernel
#   wpa_supplicant and hostapd on the same wireless interface doesn't make any sense

with lib;

let

  cfg = config.services.hostapd;

  generateConfigFile = AP: pkgs.writeText "hostapd-${AP.interface}.conf" ''
    interface=${AP.interface}
    driver=${AP.driver}
    ssid=${AP.ssid}
    hw_mode=${AP.hwMode}
    channel=${toString AP.channel}
    ${optionalString (cfg.countryCode != null) ''country_code=${cfg.countryCode}''}
    ${optionalString (cfg.countryCode != null) ''ieee80211d=1''}

    ${optionalString (AP.bridge != null) "bridge=${AP.bridge}"}

    # logging (debug level)
    logger_syslog=-1
    logger_syslog_level=${toString cfg.logLevel}
    logger_stdout=-1
    logger_stdout_level=${toString cfg.logLevel}

    ctrl_interface=/run/hostapd
    ctrl_interface_group=${AP.group}

    ${optionalString AP.wpa ''
      wpa=2
      wpa_passphrase=${AP.wpaPassphrase}
    ''}

    ${optionalString AP.noScan "noscan=1"}

    ${AP.extraConfig}
  '' ;

  generateUnit = AP: nameValuePair "hostapd-${AP.interface}" {
    description = "hostapd wireless AP on ${AP.interface}";

    path = [ pkgs.hostapd ];
#    wantedBy = [ "network.target" ];

    after   = [ "sys-subsystem-net-devices-${utils.escapeSystemdPath AP.interface}.device" (optionalString (AP.bridge != null) "sys-subsystem-net-devices-${AP.bridge}.device") ];
    bindsTo = [ "sys-subsystem-net-devices-${utils.escapeSystemdPath AP.interface}.device" (optionalString (AP.bridge != null) "sys-subsystem-net-devices-${AP.bridge}.device") ];
    requiredBy = [ "network-link-${AP.interface}.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStart = "${pkgs.hostapd}/bin/hostapd ${generateConfigFile AP}";
      Restart = "always";
    };
  };

in

{

  # We are overriding an upstream module here. So, disable that.
  disabledModules = [ "services/networking/hostapd.nix" ];

  ###### interface

  options = {

    services.hostapd = {

      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable putting a wireless interface into infrastructure mode,
          allowing other wireless devices to associate with the wireless
          interface and do wireless networking. A simple access point will
          <option>enable hostapd.wpa</option>,
          <option>hostapd.wpaPassphrase</option>, and
          <option>hostapd.ssid</option>, as well as DHCP on the wireless
          interface to provide IP addresses to the associated stations, and
          NAT (from the wireless interface to an upstream interface).
        '';
      };

      logLevel = mkOption {
        default = 2;
        type = types.int;
        description = ''
          Levels (minimum value for logged events):
          0 = verbose debugging
          1 = debugging
          2 = informational messages
          3 = notification
          4 = warning
        '';
      };

      countryCode = mkOption {
        default = null;
        example = "US";
        type = with types; nullOr str;
        description = ''
          Country code (ISO/IEC 3166-1). Used to set regulatory domain.
          Set as needed to indicate country in which device is operating.
          This can limit available channels and transmit power.
          These two octets are used as the first two octets of the Country String
          (dot11CountryString).
          If set this enables IEEE 802.11d. This advertises the countryCode and
          the set of allowed channels and transmit power levels based on the
          regulatory limits.
        '';
      };

      APs = mkOption {
        default = [];
        description = ''
          A list of complete hostapd configurations (one per network interface/AP
          you want to run).
        '';

        type = with types; listOf (submodule {

          options = {

            interface = mkOption {
              default = "";
              example = "wlp2s0";
              description = ''
                The interfaces <command>hostapd</command> will use.
              '';
            };

            noScan = mkOption {
              default = false;
              description = ''
                Do not scan for overlapping BSSs in HT40+/- mode.
                Caution: turning this on will violate regulatory requirements!
              '';
            };

            bridge = mkOption {
              default = null;
              type = types.nullOr types.str;
              example = "br0";
              description = ''
                The (optional) name of the bridge to add this AP to.
              '';
            };

            driver = mkOption {
              default = "nl80211";
              example = "hostapd";
              type = types.str;
              description = ''
                Which driver <command>hostapd</command> will use.
                Most applications will probably use the default.
              '';
            };

            ssid = mkOption {
              default = "nixos";
              example = "mySpecialSSID";
              type = types.str;
              description = "SSID to be used in IEEE 802.11 management frames.";
            };

            hwMode = mkOption {
              default = "g";
              type = types.enum [ "a" "b" "g" ];
              description = ''
                Operation mode.
                (a = IEEE 802.11a, b = IEEE 802.11b, g = IEEE 802.11g).
              '';
            };

            channel = mkOption {
              default = 7;
              example = 11;
              type = types.int;
              description = ''
                Channel number (IEEE 802.11)
                Please note that some drivers do not use this value from
                <command>hostapd</command> and the channel will need to be configured
                separately with <command>iwconfig</command>.
              '';
            };

            group = mkOption {
              default = "wheel";
              example = "network";
              type = types.str;
              description = ''
                Members of this group can control <command>hostapd</command>.
              '';
            };

            wpa = mkOption {
              default = true;
              description = ''
                Enable WPA (IEEE 802.11i/D3.0) to authenticate with the access point.
              '';
            };

            wpaPassphrase = mkOption {
              default = "my_sekret";
              example = "any_64_char_string";
              type = types.str;
              description = ''
                WPA-PSK (pre-shared-key) passphrase. Clients will need this
                passphrase to associate with this access point.
                Warning: This passphrase will get put into a world-readable file in
                the Nix store!
              '';
            };

            extraConfig = mkOption {
              default = "";
              example = ''
                auth_algo=0
                ieee80211n=1
                ht_capab=[HT40-][SHORT-GI-40][DSSS_CCK-40]
                '';
              type = types.lines;
              description = "Extra configuration options to put in hostapd.conf.";
            };
          };
        });
      };
    };
  };


  ###### implementation

  config = mkIf cfg.enable {

    environment.systemPackages = [ pkgs.hostapd ];

    services.udev.packages = optional (cfg.countryCode != null) [ pkgs.crda ];

    systemd.services = listToAttrs (map generateUnit cfg.APs); 
  };
}

