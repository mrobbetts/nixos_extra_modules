{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.networking.siteNetwork;

  # Helper stuff.
  toVirIfName = n: v: "vl_${n}";

  toIfName = n: v: if (isVLAN n v) then (toVirIfName n v) else v.interface;
  toName = n: v: n;

  phyIfNameList = lib.mapAttrsToList (n: v: v.interface);
  virIfNameList = lib.mapAttrsToList toVirIfName;
  hasInternetAccess = n: v: v.hasInternetAccess;

  isVLAN = n: {isVLAN ? false, ...}: isVLAN;
  isNotVLAN = n: v: ! isVLAN n v;

  # Convert a network entry to a nameValuePair to live in networking.vlans.
  toVLANSpec = n: v: lib.nameValuePair (toVirIfName n v) { id = v.vid; interface = v.interface; };

  # Convert a network entry to a nameValuePair to live in networking.interfaces.
  toInterfaceSpec = n: v: lib.nameValuePair (toVirIfName n v) { ipv4.addresses = [{
                                                                  address = "10.${cfg.networkDefs.ipBase}.${toString v.ip}.1";
                                                                  prefixLength = 24;
                                                                }];
                                                              };

in
{

  ###### interface

  options = {
    networking.siteNetwork = {

      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to enable siteNetwork.
        '';
      };

      lanIF = mkOption {
        type = types.str;
        default = "lan";
        description = ''
          The name of the LAN-side interface.
        '';
      };

      wanIF = mkOption {
        type = types.str;
        default = "wan";
        description = ''
          The name of the WAN-side interface.
        '';
      };

      networkDefs = mkOption {
        # type = types.submodule;
        default = {};
        description = ''
          The desired network topology.
        '';
        example = ''
          rec {

            mDNSReflectors = with networks; [
              { inherit trusted; inherit IoT; }
              { inherit local;   inherit IoT; }
            ];

            networks = rec {
              # Physical lan0 interface.
              local = {
                ip  = 1;
                interface = "lan0";
                hasInternetAccess = true;
                mayInitiateWith = { inherit IoT; inherit trusted; };
                #isVLAN = false;
              };

              # Management, VLAN
              mgmt = {
                vid = 2;
                ip  = 2;
                interface = "lan0";
                hasInternetAccess = true;
                mayInitiateWith = { inherit IoT; inherit trusted; inherit local; };
                isVLAN = true;
              };

              #IoT VLAN; restricted access.
              IoT = {
                vid = 10;
                ip  = 10;
                interface = "lan0";
                hasInternetAccess = true;
                mayInitiateWith = { inherit trusted; }; ## Temporarily allow this.
                isVLAN = true;
              };

              # Trusted vlan. Access to everything except mgmt.
              trusted = {
                vid = 20;
                ip  = 20;
                interface = "lan0";
                hasInternetAccess = true;
                mayInitiateWith = { inherit IoT; inherit local; };
                isVLAN = true;
              };
            };
          };
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    # assertions = [{
    #   assertion = config.networking.firewall.enable == false;
    #   message = "You can not use nftables and iptables at the same time. networking.firewall.enable must be set to false.";
    # }];
    # boot.blacklistedKernelModules = [ "ip_tables" ];
    # environment.systemPackages = [ pkgs.nftables ];
    # networking.networkmanager.firewallBackend = mkDefault "nftables";

    #######

    networking = {

      # Set up VLAN interfaces
      interfaces = {
        # wan = {
        #   useDHCP = true;
        # };
        "${cfg.lanIF}" = {
          useDHCP = false;
          ipv4.addresses = [{
            address = "10.${cfg.networkDefs.ipBase}.1.1";
            prefixLength = 24;
          }];
        };
      } // (builtins.listToAttrs (lib.mapAttrsToList toInterfaceSpec (lib.filterAttrs isVLAN cfg.networkDefs.networks)));

      # Set up VLANs.
      vlans = builtins.listToAttrs (lib.mapAttrsToList toVLANSpec (lib.filterAttrs isVLAN cfg.networkDefs.networks));

      # Add our routing rules.
      nftables = {
        enable = true;
        ruleset =
        let
          #enquote = n: ''"vlan_${n}"'';
          enquote = n: ''"${n}"'';

          toInterSubnetFWRule = n: v:
            if ((builtins.length (builtins.attrNames v.mayInitiateWith)) > 0) then ''
              # Rule for ${n}
              iifname { ${enquote (toIfName n v)} } oifname { ${builtins.concatStringsSep ", " (map enquote (lib.mapAttrsToList toIfName v.mayInitiateWith))} } counter accept comment "Allow ${n} to communicate with ${builtins.concatStringsSep ", " (lib.mapAttrsToList toName v.mayInitiateWith)}"
            ''
            else ''
              # No rules for ${n}
            '';
          toMDNSReflectRule = l: let
            fstn = builtins.elemAt (builtins.attrNames l) 0;
            sndn = builtins.elemAt (builtins.attrNames l) 1;
          in ''
            # Reflect mDNS traffic between [${fstn}] and [${sndn}]
            ip daddr 224.0.0.251 iifname { ${enquote (toIfName fstn l."${fstn}")} } counter ip saddr set 10.${cfg.networkDefs.ipBase}.${toString l."${sndn}".ip}.1 dup to 224.0.0.251 device ${enquote (toIfName sndn l."${sndn}")} notrack comment "Reflect mDNS traffic from [${fstn}] to [${sndn}]"
            ip daddr 224.0.0.251 iifname { ${enquote (toIfName sndn l."${sndn}")} } counter ip saddr set 10.${cfg.networkDefs.ipBase}.${toString l."${fstn}".ip}.1 dup to 224.0.0.251 device ${enquote (toIfName fstn l."${fstn}")} notrack comment "Reflect mDNS traffic from [${sndn}] to [${fstn}]"
          '';
        in ''
          # See https://francis.begyn.be/blog/nixos-home-router
          table ip filter {
            chain output {
              type filter hook output priority 100;
              policy accept;
              counter
            }

            chain input {
              type filter hook input priority 0;
              policy drop;

              # Allow internal networks to access the router
              iifname { ${builtins.concatStringsSep ", " (["lo" "${cfg.lanIF}"] ++ (virIfNameList cfg.networkDefs.networks))} } counter accept comment "Allow internal networks to access the router"

              # icmp
              icmp type echo-request accept

              # Accept traffic on specific ports.
              iifname "${cfg.wanIF}" tcp dport { ssh, http, https, 2022, 22000 } accept

              # Allow returning traffic from wan and drop everthing else
              iifname "${cfg.wanIF}" ct state { established, related } counter accept
            }

            chain forward {
              type filter hook forward priority 0;
              policy drop;

              # enable flow offloading for better throughput
              #ip protocol { tcp, udp } flow offload @f

              #icmp type echo-request accept

              # Allow all established traffic; including between restricted VLANs.
              ct state { established, related } counter accept comment "Allow all established traffic"

              #iifname { "vlan_trusted" } oifname { "${cfg.lanIF}" } counter accept

              # Allow trusted network WAN access
              iifname { ${builtins.concatStringsSep ", " (lib.mapAttrsToList toIfName (lib.filterAttrs hasInternetAccess cfg.networkDefs.networks))} } oifname { "${cfg.wanIF}" } counter accept comment "Allow trusted LAN to WAN"
              #iifname { "${cfg.wanIF}" } oifname { ${builtins.concatStringsSep ", " (lib.mapAttrsToList toIfName (lib.filterAttrs hasInternetAccess cfg.networkDefs.networks))} } ct state { established, related } counter accept comment "Allow WAN back to trusted LAN"

              # Allow trusted inter-subnet routing
              ${builtins.concatStringsSep "\n    " (lib.mapAttrsToList toInterSubnetFWRule cfg.networkDefs.networks)}

              # Allow established WAN to return
              #iifname { "${cfg.wanIF}" } oifname { ${builtins.concatStringsSep ", "  (["${cfg.lanIF}"] ++ (virIfNameList (lib.filterAttrs hasInternetAccess cfg.networkDefs.networks)))} } ct state { established, related } counter accept comment "Allow established back to LANs"

              counter
            }

            #chain prerouting {
            #  type nat hook prerouting priority 0;
            #  policy accept;
            #}

            chain mdnsreflect {
              type filter hook prerouting priority 0;
              policy accept;
            
              ${builtins.concatStringsSep "\n    " (builtins.map toMDNSReflectRule cfg.networkDefs.mDNSReflectors) }
              ip daddr 224.0.0.251 counter comment "mDNS packets not yet accepted"
            }

            # Setup NAT masquerading on the wan interface
            chain postrouting {
              type nat hook postrouting priority 100;
              policy accept;
              oifname "${cfg.wanIF}" masquerade
            }
          }
        '';
      };
    };

    services = {
      # Add our DNS.
      bind = {
        enable = true;
        forwarders = [ "192.168.1.3" /*"8.8.8.8" "1.1.1.1"*/ ];
        cacheNetworks = [
          "127.0.0.0/24"
          "10.${cfg.networkDefs.ipBase}.0.0/16"
          "192.168.1.0/24"
        ];
        listenOn = [
          "any"    # These should be the IP addresses of the interfaces,
  #        "lan0"  # not the names(!)
  #        "vlan10"
  #        "vlan20"
  #        "vlan30"
  #        "vlan40"
  #        "vlan50"
        ];
        extraOptions = ''
          dnssec-validation no;

          # Try to prevent the `dumping master file: /nix/store/tmp-2if8Kjjd5z: open: unexpected error`
          dump-file "/run/named/cache_dump.db";
        '';
        zones =
        let f = n: v:
          {
            master = true;
            file = pkgs.writeText "db.${n}.lan" ''
              $TTL 2d    ; 172800 secs default TTL for zone
              $ORIGIN ${n}.lan.
              @             IN      SOA   ns1.${n}.lan. hostmaster.${n}.lan. (
                                      2003080801 ; se = serial number
                                      12h        ; ref = refresh
                                      15m        ; ret = update retry
                                      3w         ; ex = expiry
                                      3h         ; min = minimum
                                    )
                            IN      NS      ns1.${n}.lan.
                            IN      A       10.${cfg.networkDefs.ipBase}.${toString v.ip}.1
              ns1           IN      A       10.${cfg.networkDefs.ipBase}.${toString v.ip}.1
              twist         IN      A       10.${cfg.networkDefs.ipBase}.${toString v.ip}.1
            '';
            extraConfig = ''
              //allow-update { 127.0.0.1; 10.${cfg.networkDefs.ipBase}.${toString v.ip}.1; }; // DDNS this host only
              allow-update { cacheNetworks; };
              journal "/run/named/${n}.lan.jnl";
            '';
          };
          toDNSSpec = n: v: lib.nameValuePair "${n}.lan" (f n v);
        in
  /*
          {
            "local.lan"  = (f "local"  "1");
            "ten.lan"    = (f "ten"    "10");
            "twenty.lan" = (f "twenty" "20");
          };
  */
          lib.listToAttrs ([(toDNSSpec "local" { ip = 1; })] ++ (lib.mapAttrsToList toDNSSpec cfg.networkDefs.networks));
          #lib.listToAttrs (lib.mapAttrsToList toDNSSpec networkDefs.networks);
      };

      # Add our DHCPD stuff.
      dhcpd4 = {
        enable = true;
        #interfaces = [ "lan0" "vlan10" "vlan20" /* "vlan30" "vlan40" "vlan50" */ ];
        #interfaces = (["lan0"] ++ (virIfNameList (filter isVLAN networkDefs.networks)));
        #interfaces = (phyIfNameList (lib.filterAttrs (x: ! (isVLAN x)) networkDefs.networks)) ++ (virIfNameList (lib.filterAttrs isVLAN networkDefs.networks));
        interfaces = virIfNameList (lib.filterAttrs isVLAN cfg.networkDefs.networks) ++ (phyIfNameList (lib.filterAttrs isNotVLAN cfg.networkDefs.networks));
        authoritative  = true;

        extraConfig = let
          dhcpZone = n: v: ''
            # Forward zone for network [${toString v.ip}] ("${n}")
            zone ${n}.lan. {                                           # Name of your forward DNS zone
              primary 10.${cfg.networkDefs.ipBase}.${toString v.ip}.1; # DNS server IP address here
              #key key-name;
            }

            # Reverse zone for network [${toString v.ip}] ("${n}")
            zone ${toString v.ip}.${cfg.networkDefs.ipBase}.10.in-addr.arpa. { # Name of your reverse DNS zone
              primary 10.${cfg.networkDefs.ipBase}.${toString v.ip}.1;         # DNS server IP address here
              #key key-name;
            }

            # Subnet definition for network [${toString v.ip}] ("${n}")
            subnet 10.${cfg.networkDefs.ipBase}.${toString v.ip}.0 netmask 255.255.255.0 {
              range 10.${cfg.networkDefs.ipBase}.${toString v.ip}.128 10.${cfg.networkDefs.ipBase}.${toString v.ip}.254;
              authoritative;
              # Allows clients to request up to a week (although they won't)
              max-lease-time              604800;
              # By default a lease will expire in 24 hours.
              default-lease-time          86400;
              option subnet-mask          255.255.255.0;
              option broadcast-address    10.${cfg.networkDefs.ipBase}.${toString v.ip}.255;
              option routers              10.${cfg.networkDefs.ipBase}.${toString v.ip}.1;
              option domain-name-servers  10.${cfg.networkDefs.ipBase}.${toString v.ip}.1;
              option domain-name          "${n}.lan";
              option netbios-name-servers 10.${cfg.networkDefs.ipBase}.${toString v.ip}.1;
            }
          '';
        in ''
          ddns-update-style standard;
          ddns-rev-domainname "in-addr.arpa.";
          deny client-updates;
          do-forward-updates on;
          update-optimization off;
          update-conflict-detection off;

          ${builtins.concatStringsSep "\n" (lib.mapAttrsToList dhcpZone cfg.networkDefs.networks)}
        '';
      };
    };

    #######

    # systemd.services.nftables = {
    #   description = "nftables firewall";
    #   before = [ "network-pre.target" ];
    #   wants = [ "network-pre.target" ];
    #   wantedBy = [ "multi-user.target" ];
    #   reloadIfChanged = true;
    #   serviceConfig = let
    #     rulesScript = pkgs.writeScript "nftables-rules" ''
    #       #! ${pkgs.nftables}/bin/nft -f
    #       flush ruleset
    #       include "${cfg.rulesetFile}"
    #     '';
    #     checkScript = pkgs.writeScript "nftables-check" ''
    #       #! ${pkgs.runtimeShell} -e
    #       if $(${pkgs.kmod}/bin/lsmod | grep -q ip_tables); then
    #         echo "Unload ip_tables before using nftables!" 1>&2
    #         exit 1
    #       else
    #         ${rulesScript}
    #       fi
    #     '';
    #   in {
    #     Type = "oneshot";
    #     RemainAfterExit = true;
    #     ExecStart = checkScript;
    #     ExecReload = checkScript;
    #     ExecStop = "${pkgs.nftables}/bin/nft flush ruleset";
    #   };
    # };
  };
}
