{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.networking.siteNetwork;
  hostname = config.networking.hostName;

  # Helper stuff.
  ip = import ./helpers/ip.nix lib;

  toName = n: v: n;

  padWithSpacesToLength = n: s:
#  let
#    length = stringLength s;
#    numSpaces = length - n;
#  in
    if (stringLength s) - n >= 0 then s
                                 else (padWithSpacesToLength n (s + " "));

  isVLAN = n: {isVLAN ? false, ...}: isVLAN;
  isNotVLAN = n: v: ! isVLAN n v;

  # Convert a given network definition into its interface name, taking into account the interface's type.
  toIfName = n: v:
    if v.kind == "eth"       then n                else
    if v.kind == "wireguard" then "wireguard_${n}" else
    if v.kind == "vlan"      then "vl_${n}"        else
    error "Unknown interface type: ${v.kind}";

  # Convert a set of network definitions into a list of interface names.
  toIfNameList = networks: lib.mapAttrsToList toIfName networks;

  # Convert a set of network definitions into a list of interface IP address bases.
  #toIfIPAddrBaseList = netDefs: lib.mapAttrsToList (n: v: v.ip) netDefs;

  # Convert the top-level site definition into a list of interface IP addresses.
  #toIfIPAddrList = networkDefs: map (s: "10.${networkDefs.ipBase}.${toString s}.1") (toIfIPAddrBaseList networkDefs.networks.lan.vlans);
  toIfIPAddrList = networkDefs: lib.mapAttrsToList (n: v: ip.prettyNthAddressIn cfg.networkDefs.ipSpace v.ip 1) networkDefs.networks.lan.vlans;

  networkDefToPrettySubnet = n: v: ip.prettySubnet (ip.subnetIn cfg.networkDefs.ipSpace v.ip);

  # Convert a network name into an IP subnet string (e.g. "10.2.10/24").
  #
  # networkToSubnetString :: String -> String
  #networkToSubnetString = networkName: "10.${cfg.networkDefs.ipBase}.${toString (getAttr networkName cfg.networkDefs.networks).ip}/24";
  #networkToSubnetString = networkName: ip.prettySubnet (ip.subnetIn cfg.networkDefs.ipSpace (getAttr networkName cfg.networkDefs.networks).ip);
  networkNameToPrettySubnet = networkName: networkDefToPrettySubnet networkName (getAttr networkName cfg.networkDefs.networks);

  # Determine whether the network `{fromn, fromv}` is allowed to initiate with the network `n`.
  # (Does `from.mayInitiateWith` (which is an attrset) contain an attrset named `n`?)
  #
  # canInitiateTo :: String -> String -> Any -> Bool
  canInitiateTo = n: fromn: fromv: hasAttr n fromv.mayInitiateWith;

  # Convert the network `n` and the set of networks `networks` into a list of network
  # names which can initiate with the network `n`.
  #
  # initiatorListFor :: String -> AttrSet -> [String]
  initiatorListFor = n: networks: attrNames (filterAttrs (canInitiateTo n) networks);

/*
  ###
  # Thanks to infinisil!!
  #
  # https://discourse.nixos.org/t/manipulate-ip-addresses-in-nix-lang/33363/2
  # https://github.com/infinisil/system/blob/f41c1437aa146fcfd038694d92a077a02f01f142/deploy/lib/ip.nix
  parseIp = str: map lib.toInt (builtins.match "([0-9]+)\\.([0-9]+)\\.([0-9]+)\\.([0-9]+)" str);
  prettyIp = lib.concatMapStringsSep "." toString;

  ipListToInt = ipList: foldl' (x: y: x * 256 + y) 0 ipList;
  #intToIPList = 

  cidrToMask =
    let
      # Generate a partial mask for an integer from 0 to 7
      #   part 1 = 128
      #   part 7 = 254
      part = n:
        if n == 0 then 0
        else part (n - 1) / 2 + 128;
    in cidr:
      let
        # How many initial parts of the mask are full (=255)
        fullParts = cidr / 8;
      in lib.genList (i:
        # Fill up initial full parts
        if i < fullParts then 255
        # If we're above the first non-full part, fill with 0
        else if fullParts < i then 0
        # First non-full part generation
        else part (lib.mod cidr 8)
      ) 4;

  parseSubnet = str:
    let
      splitParts = builtins.split "/" str;
      givenIp = parseIp (lib.elemAt splitParts 0);
      cidr = lib.toInt (lib.elemAt splitParts 2);
      mask = cidrToMask cidr;
      baseIp = lib.zipListsWith lib.bitAnd givenIp mask;
      range = {
        from = baseIp;
        to = lib.zipListsWith (b: m: 255 - m + b) baseIp mask;
      };
      check = ip: baseIp == lib.zipListsWith (b: m: lib.bitAnd b m) ip mask;
      warn = if baseIp == givenIp then lib.id else lib.warn
        ( "subnet ${str} has a too specific base address ${prettyIp givenIp}, "
        + "which will get masked to ${prettyIp baseIp}, which should be used instead");
    in warn {
      inherit baseIp cidr mask range check;
      subnet = "${prettyIp baseIp}/${toString cidr}";
    };
  ###
*/
  #ipStuff = import ./helpers/ip.nix lib;

  # Compute subnet string: e.g. "10.1.10.1/24".
  # Examples:
  # (toSubnetInCIDR "192.168.0.0/23" 3 2) -> "192.168.0.128/26";

/*
  toSubnetInCIDR = ipSpace: numBitsForSubnets: networkIndex:
    let 
      parsedIP = ipStuff.parseSubnet ipSpace;
      subnetScale = 32 - (parsedIP.cidr + numBitsForSubnets);
      intIp = ipStuff.ipListToInt parsedIP.baseIp;
      newSubnet = ipStuff.intToIPList (intIp + (networkIndex * (ipStuff.pow subnetScale 2)));
      newCidr = parsedIP.cidr + numBitsForSubnets;
    in
      #"${parsedIP.baseIp}/${toString (parsedIP.cidr + numBitsForSubnets)}";
      #"${(parseSubnet ipSpace).baseIp}/${toString ((parseSubnet ipSpace).cidr + numBitsForSubnets)}";
      #"${ipStuff.prettyIp parsedIP.baseIp}/${toString (parsedIP.cidr + numBitsForSubnets)} Integer version: ${toString intIp}. And back, as: ${ipStuff.prettyIp (ipStuff.intToIPList intIp)}";
      "New Subnet: ${toString newSubnet}/${toString newCidr}";
*/

  # Convert a physical interface definition to a systemd-networkd "link".
  physicalToLink = n: v:
    lib.nameValuePair ("09-" + (toIfName n v)) {
      matchConfig.MACAddress = v.macAddress;

      # Needed so that this link definition won't match all the vlans associated with this interface
      # (which all share the same MAC address).
      matchConfig.Type = "!vlan";

      linkConfig.Name = n;
    };

  # Convert a wireguard interface definition to a systemd-networkd "netdev".
  wireguardToNetdev = n: v:
    lib.nameValuePair ("09-" + (toIfName n v)) {
      netdevConfig = {
        Kind = "wireguard";
        Name = toIfName n v;
      };
      wireguardConfig = {
        ListenPort = v.listenPort;
        PrivateKeyFile = v.privateKeyFile;
      };
      wireguardPeers = v.peers;
    };

  # Convert a vlan interface definition to a systemd-networkd "netdev".
  vlanToNetdev = n: v:
    lib.nameValuePair ("09-" + (toIfName n v)) {
      netdevConfig = {
        Name = toIfName n v;
        Kind = "vlan";
      };
      vlanConfig = {
        Id = v.vid;
      };
    };

  # Convert a vlan interface definition to a systemd-networkd "network".
  vlanToNetwork = n: v:
    lib.nameValuePair ("11-" + (toIfName n v)) {
      #address = [ "10.${cfg.networkDefs.ipBase}.${toString v.ip}.1/24" ];
      address = [ "${ip.prettySubnet (ip.nthAddressIn cfg.networkDefs.ipSpace v.ip 1)}" ];
      DHCP = "no";
      matchConfig = {
        Name = toIfName n v;
      };
      linkConfig = {
        RequiredForOnline = "yes";
      };
      networkConfig = {
        Domains = [ "${n}.${cfg.siteName}" ];

        # Set the DNS resolver for addresses in this domain/link to be us. Used
        # when the router wants to look up local addresses managed by BIND/Kea.
        #DNS = "10.${cfg.networkDefs.ipBase}.${toString v.ip}.1:53";
        DNS = "${ip.prettyNthAddressIn cfg.networkDefs.ipSpace v.ip 1}:53";

        Description = v.description;
      };
    };

  wireguardToNetwork = n: v:
    lib.nameValuePair ("11-" + (toIfName n v)) {
      matchConfig = {
        Name = toIfName n v;
      };
      address = v.address; # Note, this should be a list of address strings.
    };

  physicalToNetwork = n: v:
    lib.nameValuePair ("10-" + (toIfName n v)) ({
      matchConfig = {
        Name = (toIfName n v);
      };
      networkConfig = {
        Description = v.description;
      };
      #vlan = lib.optionalAttrs (hasAttr "vlans" v) (lib.mapAttrsToList toIfName v.vlans);
      vlan = if (hasAttr "vlans" v) then (lib.mapAttrsToList toIfName v.vlans) else [];
    } // (if (hasAttr "networkdNetworkExtras" v) then v.networkdNetworkExtras else {}));

  netDefToNetwork = n: v:
    if v.kind == "eth"  then physicalToNetwork n v else
    if v.kind == "vlan" then vlanToNetwork n v else
    abort "Unknown netdef type for: ${v.kind}";

  netDefToLink = n: v:
    if v.kind == "eth" then physicalToLink n v else
    abort "Unknown netdef type for: ${v.kind}";

  netDefsToNetdevs  = networks: builtins.listToAttrs ((lib.mapAttrsToList vlanToNetdev       (filterAttrs (n: v: v.kind == "vlan")      networks))
                                                   ++ (lib.mapAttrsToList wireguardToNetdev  (filterAttrs (n: v: v.kind == "wireguard") networks)));
  netDefsToNetworks = networks: builtins.listToAttrs ((lib.mapAttrsToList physicalToNetwork  (filterAttrs (n: v: v.kind == "eth")       networks))
                                                   ++ (lib.mapAttrsToList wireguardToNetwork (filterAttrs (n: v: v.kind == "wireguard") networks))
                                                   ++ (lib.mapAttrsToList vlanToNetwork      (filterAttrs (n: v: v.kind == "vlan")      networks)));

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

      siteName = mkOption {
        type = types.str;
        default = "lan";
        description = "The string to use as the final section of all domains.";
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
                vid = 1;
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

  config = 

    let dhcp4Config = config.systemd.services.dhcpd4.unitConfig.After; in

    (mkIf cfg.enable {
    # assertions = [{
    #   assertion = config.networking.firewall.enable == false;
    #   message = "You can not use nftables and iptables at the same time. networking.firewall.enable must be set to false.";
    # }];
    # boot.blacklistedKernelModules = [ "ip_tables" ];
    # environment.systemPackages = [ pkgs.nftables ];
    # networking.networkmanager.firewallBackend = mkDefault "nftables";

    #######

    systemd = {
      network = {
        enable = true;
        netdevs  = netDefsToNetdevs cfg.networkDefs.networks;
        networks = netDefsToNetworks cfg.networkDefs.networks;
        links    = builtins.listToAttrs (lib.mapAttrsToList netDefToLink    (filterAttrs (n: v: v.kind == "eth") cfg.networkDefs.networks));
      };

      services = 
      let
        nameToDeviceName = n: "sys-subsystem-net-devices-${n}.device";
      in
      {
        #nftables.unitConfig.After = lib.mkOverride 0 [ "network.target" "network-online.target" ];
        #nftables.unitConfig.Wants = lib.mkOverride 0 [ "network.target" "network-online.target" ];
        #nftables.unitConfig.BindsTo = map nameToDeviceName (virIfNameList cfg.networkDefs.networks);
        #nftables.unitConfig.After = map nameToDeviceName (virIfNameList cfg.networkDefs.networks);
        #dhcpd4.unitConfig.BindsTo = map nameToDeviceName (virIfNameList cfg.networkDefs.networks);
        dhcpd4.unitConfig.After = lib.mkOverride 0 [ "network.target" "network-online.target" ];
        dhcpd4.unitConfig.Wants = lib.mkOverride 0 [ "network.target" "network-online.target" ];
        #dhcpd4.unitConfig.After = lib.mkOverride 0 ((map nameToDeviceName (virIfNameList cfg.networkDefs.networks)) ++ [ "network.target" ]);
      };
/*
      services = lib.mkMerge
      let
        nameToDeviceName = n: "sys-subsystem-net-devices-${n}.device";
      in
      {
        nftables.unitConfig.BindsTo = map nameToDeviceName (virIfNameList cfg.networkDefs.networks);
        nftables.unitConfig.After = map nameToDeviceName (virIfNameList cfg.networkDefs.networks);
        dhcpd4.unitConfig.BindsTo = map nameToDeviceName (virIfNameList cfg.networkDefs.networks);
        dhcpd4.unitConfig.After = lib.mkMerge [ config.systemd.services.dhcpd4.unitConfig.After (lib.mkAfter (map nameToDeviceName (virIfNameList cfg.networkDefs.networks))) ];
      };
*/
    };

    networking = {
      useNetworkd = mkDefault true;
      firewall.enable = mkDefault false;
      nat.enable = mkDefault false;
/*
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
      };
#     // (builtins.listToAttrs (lib.mapAttrsToList toInterfaceSpec (lib.filterAttrs isVLAN cfg.networkDefs.networks)));

      # Set up VLANs.
      #vlans = builtins.listToAttrs (lib.mapAttrsToList toVLANSpec (lib.filterAttrs isVLAN cfg.networkDefs.networks));
*/
      # Add our routing rules.
      nftables = {
        enable = true;
        ruleset =
        let
          #enquote = n: ''"vlan_${n}"'';
          enquote = n: ''"${n}"'';

          listOfIfNamesOfKind = k: networks: builtins.concatStringsSep ", " (toIfNameList (filterAttrs (n: v: v.kind == k) networks));

          toInterSubnetFWRule = n: v:
            if ((builtins.length (builtins.attrNames v.mayInitiateWith)) > 0) then ''
              # Routing allowances rule for ${n}
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
            #ip daddr 224.0.0.251 iifname { ${enquote (toIfName fstn l."${fstn}")} } counter ip saddr set 10.${cfg.networkDefs.ipBase}.${toString l."${sndn}".ip}.1 dup to 224.0.0.251 device ${enquote (toIfName sndn l."${sndn}")} notrack comment "Reflect mDNS traffic from [${fstn}] to [${sndn}]"
            #ip daddr 224.0.0.251 iifname { ${enquote (toIfName sndn l."${sndn}")} } counter ip saddr set 10.${cfg.networkDefs.ipBase}.${toString l."${fstn}".ip}.1 dup to 224.0.0.251 device ${enquote (toIfName fstn l."${fstn}")} notrack comment "Reflect mDNS traffic from [${sndn}] to [${fstn}]"
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
              iifname { lo, ${listOfIfNamesOfKind "vlan" cfg.networkDefs.networks} } counter accept comment "Allow internal networks to access the router"
              iifname { ${listOfIfNamesOfKind "wireguard" cfg.networkDefs.networks} } counter accept comment "Allow wireguard networks to access the router"

              # icmp
              icmp type echo-request accept

              # Accept traffic on specific ports.
              iifname "${cfg.wanIF}" tcp dport { ssh, http, https, 2022, 22000 } accept
              #iifname "${cfg.wanIF}" accept

              # Allow returning traffic from wan and drop everything else
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

              iifname { ${listOfIfNamesOfKind "wireguard" cfg.networkDefs.networks} } counter accept comment "Forward traffic from the wireguard network"
              oifname { ${listOfIfNamesOfKind "wireguard" cfg.networkDefs.networks} } counter accept comment "Forward traffic to the wireguard network"

              # Allow trusted inter-subnet routing (note, this includes WAN access)
              ${builtins.concatStringsSep "\n    " (lib.mapAttrsToList toInterSubnetFWRule cfg.networkDefs.networks.lan.vlans)}

              counter
            }

            #chain prerouting {
            #  type nat hook prerouting priority 0;
            #  policy accept;
            #}

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

### Snippet storage...
            #chain mdnsreflect {
            #  type filter hook prerouting priority 0;
            #  policy accept;
            
            #  ${builtins.concatStringsSep "\n    " (builtins.map toMDNSReflectRule cfg.networkDefs.mDNSReflectors) }
            #  ip daddr 224.0.0.251 counter comment "mDNS packets not yet accepted"
            #}



    services = {

      kea = {
        ctrl-agent = {
          enable = false;
        };

        dhcp4 = {
          enable = true;
          settings = {

            # A lease must be renewed within 7 days.
            valid-lifetime = 604800;

            # By default a lease will expire in 24 hours.
            renew-timer = 86400;

            # By default a lease will expire in 30 minutes.            
            #renew-timer = 1800;

            # A lease should be renewed at 3 days.
            rebind-timer = 259200;

            # A lease should be renewed at 2 hours.
            #rebind-timer = 7200;

            interfaces-config = {
              ##interfaces = [ ... ]; # All interfaces to listen on (vlan interface names).
              interfaces = toIfNameList cfg.networkDefs.networks.lan.vlans;
            };

            dhcp-ddns = {
              enable-updates = true;
              server-ip = "127.0.0.1";
              server-port = 53001;
              ncr-protocol = "UDP";
              ncr-format = "JSON";
            };

            ddns-send-updates = true;
            ddns-update-on-renew = true;

            lease-database = {
              type = "memfile";
              persist = true;
              name = "/var/lib/kea/dhcp4.leases";
            };

            control-socket = {
              socket-type = "unix";
              #socket-name = "/path/to/the/unix/socket";
              socket-name = "/run/kea/kea-dhcp4.socket";
              #socket-name = "/run/kea-dhcp4/kea-dhcp4.socket";
            };

            subnet4 = 
            let toSubnetSpec = n: v: {
              #subnet = "10.${cfg.networkDefs.ipBase}.${toString v.ip}.1/24";
              subnet = ip.prettySubnetIn cfg.networkDefs.ipSpace v.ip; # e.g. "10.1.4.1/24"
              id = v.ip + 1;
              ddns-qualifying-suffix = "${n}.${cfg.siteName}";
              pools = 
              let
                routerAddress = ip.nthAddressIn cfg.networkDefs.ipSpace v.ip 1;
                broadcastAddress = ip.to (ip.subnetIn cfg.networkDefs.ipSpace v.ip);
                lastHostAddress = ip.prettyIp (ip.intToIpList ((ip.ipListToInt broadcastAddress) - 1));
                dhcpStartAddress = ip.prettyIp (ip.intToIpList ((ip.ipListToInt routerAddress.addr) + (ip.cidrToNumAddresses routerAddress.cidr) / 4));
              in
              [{
                #pool = "10.${cfg.networkDefs.ipBase}.${toString v.ip}.128 - 10.${cfg.networkDefs.ipBase}.${toString v.ip}.250";
                pool = "${dhcpStartAddress} - ${lastHostAddress}";
              #}];

              #option subnet-mask          255.255.255.0;
              #option broadcast-address    10.${cfg.networkDefs.ipBase}.${toString v.ip}.255;
              #option routers              10.${cfg.networkDefs.ipBase}.${toString v.ip}.1;
              #option domain-name-servers  10.${cfg.networkDefs.ipBase}.${toString v.ip}.1;
              #option domain-name          "${toIfName n v}.${cfg.siteName}";
              #option netbios-name-servers 10.${cfg.networkDefs.ipBase}.${toString v.ip}.1;

                option-data = 
                # We include the "routers" element here only if endpoints on the network in
                # question may initiate traffic with another network. If not, we provide no
                # routers, and the endpoints will not setup a default route through it.
                (if (v.mayInitiateWith != {}) then 
                [{
                  name = "routers";
                  #data = "10.${cfg.networkDefs.ipBase}.${toString v.ip}.1";
                  data = ip.prettyIp routerAddress.addr;
                }]
                else [])
                ++
                [
/*
                {
                  name = "routers";
                  data = "10.${cfg.networkDefs.ipBase}.${toString v.ip}.1";
                }
*/
                {
                  name = "domain-name-servers";
                  #data = "10.${cfg.networkDefs.ipBase}.${toString v.ip}.1";
                  data = ip.prettyIp routerAddress.addr;
                }
                {
                  name = "domain-name";
                  #data = "${n}.lan";
                  data = "${n}.${cfg.siteName}";
                }
                {
                  name = "broadcast-address";
                  #data = "10.${cfg.networkDefs.ipBase}.${toString v.ip}.255";
                  data = ip.prettyIp broadcastAddress;
                }
                {
                  name = "subnet-mask";
                  #data = "255.255.255.0";
                  data = ip.prettyIp (ip.cidrToMask (ip.subnetIn cfg.networkDefs.ipSpace v.ip).cidr);
                }
                {
                  name = "ntp-servers";
                  #data = "10.${cfg.networkDefs.ipBase}.${toString v.ip}.1";
                  data = ip.prettyIp routerAddress.addr;
                }];
              }];
            };
            in
              lib.mapAttrsToList toSubnetSpec cfg.networkDefs.networks.lan.vlans;
          };
        };

        dhcp-ddns = {
          enable = true;
          settings = {
            ip-address = "127.0.0.1";
            port = 53001;
            dns-server-timeout = 100;
            ncr-protocol = "UDP";
            ncr-format = "JSON";
            tsig-keys = [ ];
            forward-ddns = {
              #ddns-domains = [ ];
              ddns-domains = 
              let toForwardDomain = n: v: {
                #name = "${n}.lan.";
                name = "${n}.${cfg.siteName}.";
                dns-servers = [{
                  #ip-address = "10.${cfg.networkDefs.ipBase}.${toString v.ip}.1";
                  #ip-address = ip.prettyNthAddressIn cfg.networkDefs.ipSpace v.ip 1;
                  ip-address = "127.0.0.1";
                }];
              };
              in
                lib.mapAttrsToList toForwardDomain cfg.networkDefs.networks.lan.vlans;
            };
            reverse-ddns = {
              #ddns-domains = [ ];
              ddns-domains = 
/*
              let toReverseDomain = n: v: {
                #name = "${toString v.ip}.${cfg.networkDefs.ipBase}.10.in-addr.arpa.";
                name = "${ip.prettyIpReverse (ip.subnetIn cfg.networkDefs.ipSpace v.ip).addr}.in-addr.arpa.";
                dns-servers = [{
                  #ip-address = "10.${cfg.networkDefs.ipBase}.${toString v.ip}.1";
                  ip-address = ip.prettyNthAddressIn cfg.networkDefs.ipSpace v.ip 1;
                }];
              };
              in
                lib.mapAttrsToList toReverseDomain cfg.networkDefs.networks.lan.vlans;
*/
              [{
                #name = "${toString v.ip}.${cfg.networkDefs.ipBase}.10.in-addr.arpa.";
                #name = "${ip.prettyIpReverse (ip.subnetIn cfg.networkDefs.ipSpace v.ip).addr}.in-addr.arpa.";
                name = "168.192.in-addr.arpa.";
                dns-servers = [{
                  #ip-address = ip.prettyNthAddressIn cfg.networkDefs.ipSpace 0 1;
                  ip-address = "127.0.0.1";
                }];
              }];
            };
/*
            # Forward zone for network [${toString v.ip}] ("${n}")
            zone ${toIfName n v}.lan. {                                           # Name of your forward DNS zone
              primary 10.${cfg.networkDefs.ipBase}.${toString v.ip}.1; # DNS server IP address here
              #key key-name;
            }

            # Reverse zone for network [${toString v.ip}] ("${n}")
            zone ${toString v.ip}.${cfg.networkDefs.ipBase}.10.in-addr.arpa. { # Name of your reverse DNS zone
              primary 10.${cfg.networkDefs.ipBase}.${toString v.ip}.1;         # DNS server IP address here
              #key key-name;
            }
*/
          };
        };
      };

      # Add our DNS.
      bind = {
        enable = true;
        ipv4Only = true;
        #forwarders = [ "192.168.1.3" /*"8.8.8.8" "1.1.1.1"*/ ];

        cacheNetworks = [ "127.0.0.0/24" ] ++ lib.mapAttrsToList networkDefToPrettySubnet cfg.networkDefs.networks.lan.vlans;

/*
        listenOn = [
          "any"    # These should be the IP addresses of the interfaces,
  #        "lan0"  # not the names(!)
  #        "vlan10"
  #        "vlan20"
  #        "vlan30"
  #        "vlan40"
  #        "vlan50"
        ];
*/
        # We want to listen-on all of the vlans associated with our internal-facing interfaces.
        listenOn = ["127.0.0.1"] ++ toIfIPAddrList cfg.networkDefs;
        listenOnIpv6 = [];

        extraOptions = ''
          dnssec-validation no;

          # Try to prevent the `dumping master file: /nix/store/tmp-2if8Kjjd5z: open: unexpected error`
          dump-file "/run/named/cache_dump.db";
        '';
        extraConfig = ''
          statistics-channels {
            inet 127.0.0.1 port 8053 allow { 127.0.0.1; };
          };
        '';
        zones =
        let
          # Render zone text for the zone `{n, v}`.
          forwardZone = n: v: networks:
          {
            #allowQuery = [ "127.0.0.0/24" ] ++ (map networkToSubnetString ([n] ++ initiatorListFor n networks));
            allowQuery = [ "127.0.0.0/24" ] ++ (map networkNameToPrettySubnet ([n] ++ initiatorListFor n networks));
            master = true;
            # Old owner/IN line:               IN      A       10.${cfg.networkDefs.ipBase}.${toString v.ip}.1
            file = pkgs.writeText "db.${n}.${cfg.siteName}.zone" ''
              $TTL 2d    ; 172800 secs default TTL for zone
              $ORIGIN ${n}.${cfg.siteName}.
              @             IN      SOA   ns1.${n}.${cfg.siteName}. hostmaster.${n}.${cfg.siteName}. (
                                      2003080801 ; se = serial number
                                      12h        ; ref = refresh
                                      15m        ; ret = update retry
                                      3w         ; ex = expiry
                                      3h         ; min = minimum
                                    )
                            IN      NS      ns1.${n}.${cfg.siteName}.
                            IN      A       ${ip.prettyNthAddressIn cfg.networkDefs.ipSpace v.ip 1}
              ns1           IN      A       ${ip.prettyNthAddressIn cfg.networkDefs.ipSpace v.ip 1}
              gateway       IN      A       ${ip.prettyNthAddressIn cfg.networkDefs.ipSpace v.ip 1}
              ${padWithSpacesToLength 14 hostname}IN      A       ${ip.prettyNthAddressIn cfg.networkDefs.ipSpace v.ip 1}
            '';
            extraConfig = ''
              //TEST: ${ip.prettySubnetIn cfg.networkDefs.ipSpace 0}
              //TEST: ${ip.prettyNthAddressIn cfg.networkDefs.ipSpace 0 1}
              //TEST: ${ip.prettyNthAddressIn cfg.networkDefs.ipSpace 0 16}
              //TEST: ${ip.prettySubnetIn cfg.networkDefs.ipSpace 1}
              //TEST: ${ip.prettySubnetIn cfg.networkDefs.ipSpace 2}
              //TEST: ${ip.prettySubnetIn cfg.networkDefs.ipSpace 3}
              //TEST: ${ip.prettySubnetIn cfg.networkDefs.ipSpace 4}
              //TEST: ${ip.prettyNthAddressIn cfg.networkDefs.ipSpace 4 1}
              //TEST: ${ip.prettyNthAddressIn cfg.networkDefs.ipSpace 4 16}
              //TEST: ${ip.prettyNthAddressIn cfg.networkDefs.ipSpace 4 129}
              //TEST: ${ip.prettySubnetIn cfg.networkDefs.ipSpace 5}
              //TEST: ${ip.prettySubnetIn cfg.networkDefs.ipSpace 6}
              //TEST: ${ip.prettySubnetIn cfg.networkDefs.ipSpace 7}
              ////allow-update { 127.0.0.1; 10.${cfg.networkDefs.ipBase}.${toString v.ip}.1; }; // DDNS this host only
              //allow-update { 127.0.0.1; ${ip.prettyNthAddressIn cfg.networkDefs.ipSpace v.ip 1}; }; // DDNS this host only
              //allow-update { cacheNetworks; };
              allow-update { 127.0.0.0/24; ${concatStringsSep "; " (map networkNameToPrettySubnet ([n] ++ initiatorListFor n networks))}; };

              // Allow addresses on this subnet to be resolved only by:
              // - Hosts on this netowork, and 
              // - Hosts on those networks that are allowed to "initiate-with" us.
              //allow-query { 127.0.0.0/24; ${concatStringsSep "; " (map networkNameToPrettySubnet ([n] ++ initiatorListFor n networks))}; };
              journal "/run/named/${n}.${cfg.siteName}.jnl";
            '';
          };
          # 1.2.0.192.in-addr.arpa IN CNAME 1.0-63.2.0.192.in-addr.arpa.
          #let extraCNameEntry = ipReverse: "${ipReverse}.in-addr.arpa IN CNAME 1.0-63.2.0.192.in-addr.arpa."
/*
          reverseZone = n: v: networks:
          {
            #allowQuery = [ "127.0.0.0/24" ] ++ (map networkToSubnetString ([n] ++ initiatorListFor n networks));
            allowQuery = [ "127.0.0.0/24" ] ++ (map networkNameToPrettySubnet ([n] ++ initiatorListFor n networks));
            master = true;        
            #file = pkgs.writeText "${toString v.ip}.${cfg.networkDefs.ipBase}.10.in-addr.arpa.zone" ''
            #Old SOA line... ${toString v.ip}.${cfg.networkDefs.ipBase}.10.in-addr.arpa.     IN      SOA   ns1.${n}.${cfg.siteName}. hostmaster.${n}.${cfg.siteName}. (
            file = let
              zoneLabel = "z${ip.prettyIpReverse (ip.subnetIn cfg.networkDefs.ipSpace v.ip).addr}.in-addr.arpa.";
            in
            pkgs.writeText "${ip.prettyIpReverse (ip.subnetIn cfg.networkDefs.ipSpace v.ip).addr}.in-addr.arpa.zone" ''
              $TTL 2d    ; 172800 secs default TTL for zone
              ${ip.prettyIpReverse (ip.subnetIn cfg.networkDefs.ipSpace v.ip).addr}.in-addr.arpa.     IN      SOA   ns1.${n}.${cfg.siteName}. hostmaster.${n}.${cfg.siteName}. (
                                      2003080801 ; se = serial number
                                      12h        ; ref = refresh
                                      15m        ; ret = update retry
                                      3w         ; ex = expiry
                                      3h         ; min = minimum
                                    )
                            IN      NS      ns1.${n}.${cfg.siteName}.
              1             IN      PTR     gateway.${n}.${cfg.siteName}.
            '';
            extraConfig = ''
              ////allow-update { 127.0.0.1; 10.${cfg.networkDefs.ipBase}.${toString v.ip}.1; }; // DDNS this host only
              //allow-update { 127.0.0.1; ${ip.prettyNthAddressIn cfg.networkDefs.ipSpace v.ip 1}; }; // DDNS this host only
              allow-update { cacheNetworks; };

              //allow-query { 127.0.0.0/24; ${concatStringsSep "; " (map networkNameToPrettySubnet ([n] ++ initiatorListFor n networks))}; };
              //journal "/run/named/${toString v.ip}.${cfg.networkDefs.ipBase}.10.in-addr.arpa.jnl";
              journal "/run/named/${ip.prettyIpReverse (ip.subnetIn cfg.networkDefs.ipSpace v.ip).addr}.in-addr.arpa.jnl";
            '';
          };
*/
/*
          reverseZone = networkDefs:
          let
            zoneLabel = "168.192.in-addr.arpa.";
            #ipSpace  = networkDefs.ipSpace;
            ipSpace  = "192.168.0.0/16"; # Hard-code to a boundary for now...
            networks = networkDefs.networks.lan.vlans;
          in
          {
            #allowQuery = [ "127.0.0.0/24" ] ++ (map networkNameToPrettySubnet ([n] ++ initiatorListFor n networks));
            master = true;
            #file = pkgs.writeText "${toString v.ip}.${cfg.networkDefs.ipBase}.10.in-addr.arpa.zone" ''
            #Old SOA line... ${toString v.ip}.${cfg.networkDefs.ipBase}.10.in-addr.arpa.     IN      SOA   ns1.${n}.${cfg.siteName}. hostmaster.${n}.${cfg.siteName}. (
            file = let
              #zoneLabel = networkIndex: "${ip.prettySubnetReverse (ip.subnetIn cfg.networkDefs.ipSpace networkIndex)}.in-addr.arpa.";
              zoneLabelFor = networkIndex: "${ip.prettySubnetReverse (ip.subnetIn cfg.networkDefs.ipSpace networkIndex)}.in-addr.arpa.";
              extraCNameEntry = networkIndex: n: "${ip.prettyIpReverse (ip.nthAddressIn networkDefs.ipSpace networkIndex n).addr}.in-addr.arpa. IN CNAME ${toString n}.${zoneLabelFor networkIndex}";
            in
            pkgs.writeText "${zoneLabel}.zone" ''
              $TTL 2d    ; 172800 secs default TTL for zone
              ${zoneLabel}     IN      SOA   ns1.${cfg.siteName}. hostmaster.${cfg.siteName}. (
                                      2003080801 ; se = serial number
                                      12h        ; ref = refresh
                                      15m        ; ret = update retry
                                      3w         ; ex = expiry
                                      3h         ; min = minimum
                                    )
                            IN      NS      ns1.${cfg.siteName}.
              ;1.0           IN      PTR     gateway.${cfg.siteName}.

              ${lib.concatMapStringsSep "\n" (networkIndex: concatStringsSep "\n" (map (extraCNameEntry networkIndex) (genList (x: x + 1) ((ip.cidrToNumAddresses (ip.subnetIn networkDefs.ipSpace networkIndex).cidr) - 1)))) (lib.mapAttrsToList (n: v: v.ip) networks)}
            '';
            extraConfig = ''
              allow-update { cacheNetworks; };
              journal "/run/named/${zoneLabel}.jnl";
            '';
          };
*/
          reverseZone = networkDefs:
          let
            zoneLabel = "168.192.in-addr.arpa.";
            #ipSpace  = networkDefs.ipSpace;
            ipSpace  = "192.168.0.0/16"; # Hard-code to a boundary for now...
            networks = networkDefs.networks.lan.vlans;
          in
          {
            #allowQuery = [ "127.0.0.0/24" ] ++ (map networkNameToPrettySubnet ([n] ++ initiatorListFor n networks));
            master = true;
            #file = pkgs.writeText "${toString v.ip}.${cfg.networkDefs.ipBase}.10.in-addr.arpa.zone" ''
            #Old SOA line... ${toString v.ip}.${cfg.networkDefs.ipBase}.10.in-addr.arpa.     IN      SOA   ns1.${n}.${cfg.siteName}. hostmaster.${n}.${cfg.siteName}. (
            file = let
              #zoneLabel = networkIndex: "${ip.prettySubnetReverse (ip.subnetIn cfg.networkDefs.ipSpace networkIndex)}.in-addr.arpa.";
              zoneLabelFor = networkIndex: "${ip.prettySubnetReverse (ip.subnetIn cfg.networkDefs.ipSpace networkIndex)}.in-addr.arpa.";
              extraCNameEntry = networkIndex: n: "${ip.prettyIpReverse (ip.nthAddressIn networkDefs.ipSpace networkIndex n).addr}.in-addr.arpa. IN CNAME ${toString n}.${zoneLabelFor networkIndex}";
            in
            pkgs.writeText "${zoneLabel}.zone" ''
              $TTL 2d    ; 172800 secs default TTL for zone
              ${zoneLabel}     IN      SOA   ns1.${cfg.siteName}. hostmaster.${cfg.siteName}. (
                                      2003080801 ; se = serial number
                                      12h        ; ref = refresh
                                      15m        ; ret = update retry
                                      3w         ; ex = expiry
                                      3h         ; min = minimum
                                    )
                            IN      NS      ns1.${cfg.siteName}.
              ;1.0           IN      PTR     gateway.${cfg.siteName}.
            '';
            extraConfig = ''
              allow-update { cacheNetworks; };
              journal "/run/named/${zoneLabel}.jnl";
            '';
          };
          reverseZoneProxy = n: v: networks:
          let            
              zoneLabel = "${ip.prettySubnetReverse (ip.subnetIn cfg.networkDefs.ipSpace v.ip)}.in-addr.arpa.";
          in
          {
            allowQuery = [ "127.0.0.0/24" ] ++ (map networkNameToPrettySubnet ([n] ++ initiatorListFor n networks));
            master = true;        
            #file = pkgs.writeText "${toString v.ip}.${cfg.networkDefs.ipBase}.10.in-addr.arpa.zone" ''
            file = let
              extraCNameEntry = n: "${ip.prettyIpReverse (ip.nthAddressIn cfg.networkDefs.ipSpace v.ip n).addr}.in-addr.arpa. IN CNAME ${toString n}.${zoneLabel}";
            in
            pkgs.writeText "${zoneLabel}.zone" ''
              $TTL 2d    ; 172800 secs default TTL for zone
              ${zoneLabel}     IN      SOA   ns1.${n}.${cfg.siteName}. hostmaster.${n}.${cfg.siteName}. (
                                      2003080801 ; se = serial number
                                      12h        ; ref = refresh
                                      15m        ; ret = update retry
                                      3w         ; ex = expiry
                                      3h         ; min = minimum
                                    )
                            IN      NS      ns1.${n}.${cfg.siteName}.
              1             IN      PTR     gateway.${n}.${cfg.siteName}.
              ;${ip.prettyIpReverse (ip.nthAddressIn cfg.networkDefs.ipSpace v.ip 1).addr}.in-addr.arpa.   IN      PTR     gateway.${n}.${cfg.siteName}. 
            '';
            extraConfig = ''
              ////allow-update { 127.0.0.1; 10.${cfg.networkDefs.ipBase}.${toString v.ip}.1; }; // DDNS this host only
              //allow-update { 127.0.0.1; ${ip.prettyNthAddressIn cfg.networkDefs.ipSpace v.ip 1}; }; // DDNS this host only
              allow-update { cacheNetworks; };

              //allow-query { 127.0.0.0/24; ${concatStringsSep "; " (map networkNameToPrettySubnet ([n] ++ initiatorListFor n networks))}; };
              //journal "/run/named/${toString v.ip}.${cfg.networkDefs.ipBase}.10.in-addr.arpa.jnl";
              //journal "/run/named/${ip.prettyIpReverse (ip.subnetIn cfg.networkDefs.ipSpace v.ip).addr}.in-addr.arpa.jnl";
              journal "/run/named/${zoneLabel}.jnl";
            '';
          };

          toForwardZone      = networks: n: v: lib.nameValuePair "${n}.${cfg.siteName}" (forwardZone n v networks);
          #toReverseZone     = networks: n: v: lib.nameValuePair "${toString v.ip}.${cfg.networkDefs.ipBase}.10.in-addr.arpa" (reverseZone n v networks);
          toReverseZoneProxy = networks: n: v: lib.nameValuePair "${ip.prettySubnetReverse (ip.subnetIn cfg.networkDefs.ipSpace v.ip)}.in-addr.arpa" (reverseZoneProxy n v networks);
          toReverseZone      = networkDefs:    lib.nameValuePair "168.192.in-addr.arpa" (reverseZone networkDefs);
        in
          ##lib.listToAttrs ([(toDNSSpec "local" { ip = 1; })] ++ (lib.mapAttrsToList toDNSSpec cfg.networkDefs.networks));
          #lib.listToAttrs ((lib.mapAttrsToList (toForwardZone cfg.networkDefs.networks.lan.vlans) cfg.networkDefs.networks.lan.vlans) ++ (lib.mapAttrsToList (toReverseZone cfg.networkDefs.networks.lan.vlans) cfg.networkDefs.networks.lan.vlans));
          lib.listToAttrs ((lib.mapAttrsToList (toForwardZone      cfg.networkDefs.networks.lan.vlans) cfg.networkDefs.networks.lan.vlans) 
#                        ++ (lib.mapAttrsToList (toReverseZoneProxy cfg.networkDefs.networks.lan.vlans) cfg.networkDefs.networks.lan.vlans)
                        ++                     [(toReverseZone      cfg.networkDefs)]
          );
      };
/*
      # Add our DHCPD stuff.
      dhcpd4 = {
        enable = false;
        ##interfaces = [
          "lan0"
          "vlan10"
          "vlan20"
          #"vlan30"
          #"vlan40"
          #"vlan50"
        ];
        ##interfaces = (["lan0"] ++ (virIfNameList (filter isVLAN networkDefs.networks)));
        interfaces = (toIfNameList cfg.networkDefs.networks.lan.vlans);
        authoritative  = true;

        extraConfig = let
          dhcpZone = n: v: ''
            # Forward zone for network [${toString v.ip}] ("${n}")
            zone ${toIfName n v}.${cfg.siteName}. {                    # Name of your forward DNS zone
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
              option domain-name          "${toIfName n v}.${cfg.siteName}";
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
*/
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
  });
}
