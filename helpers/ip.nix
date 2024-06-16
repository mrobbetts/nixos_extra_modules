# Thanks to infinisil!!
#
# https://discourse.nixos.org/t/manipulate-ip-addresses-in-nix-lang/33363/2
# https://github.com/infinisil/system/blob/f41c1437aa146fcfd038694d92a077a02f01f142/deploy/lib/ip.nix

lib: rec {

  splitParts = str: builtins.split "/" str;
  parseIp = str: map lib.toInt (builtins.match "([0-9]+)\\.([0-9]+)\\.([0-9]+)\\.([0-9]+)" str);
  ipListToInt = builtins.foldl' (x: y: x * 256 + y) 0;
  prettyIp = ip: lib.concatMapStringsSep "." toString ip;
  prettyIpReverse = ip: prettyIp (lib.lists.reverseList ip);
  prettySubnet = ip: "${prettyIp ip.addr}/${toString ip.cidr}";
  prettySubnetReverse = ip: lib.concatStringsSep "." (lib.filter lib.isString (lib.lists.reverseList (builtins.split "\\." (prettySubnet ip))));
  to = subnet: lib.zipListsWith (b: m: 255 - m + b) subnet.addr (cidrToMask subnet.cidr);

  cidrToNumAddresses = cidr: pow (32 - cidr) 2;

  parse = str:
  let
    addr = parseIp (lib.elemAt (splitParts str) 0);
    cidr = lib.toInt (lib.elemAt (splitParts str) 2);
  in checkSubnet {
    inherit addr;
    inherit cidr;
  };

  makeIp = addr: cidr: { inherit addr cidr; };

  checkSubnet = ipAddr:
  let
    derivedAddr = lib.zipListsWith lib.bitAnd ipAddr.addr (cidrToMask ipAddr.cidr);
    warn = if derivedAddr == ipAddr.addr then lib.id else lib.warn
        ( "subnet ${prettySubnet ipAddr} has too specific a base address ${prettyIp ipAddr.addr}, "
        + "which will get masked to ${prettyIp derivedAddr}, which should be used instead");
  in warn ipAddr;

/*
  prettySubnet = subnet:
    let s = parseSubnet subnet;
    in "${prettyIp s.subnet}/${s.cidr}";
*/

  pow = exp: x: if exp == 0 then 1
                else x * (pow (exp - 1) x);

  # Implementation of intToIPList.
  intToIpList = ipInt:
    let
      # Get the least significant tuple.
      LSBits = lib.mod ipInt 256;
    in
      # Concatenate the least significant tuple with the rest.
      #if ipInt > 256 then [LSBits] ++ intToIPList(ipInt / 256)
      if ipInt > 256 then intToIpList(ipInt / 256) ++ [LSBits]
                     else [LSBits];

  # Given a 32-bit collapsed integer version of an IP address,
  # convert it back to its 4-tuple.
  #intToIPList = i: lib.lists.reverseList (intToIPList_impl i);

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
/*
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
*/
/*
  newSubnet = ipSpace: numBitsForSubnets: networkIndex:
    let 
      #ipStuff = import ./helpers/ip.nix lib;
      parsedIP = parseSubnet ipSpace;
      subnetScale = 32 - (parsedIP.cidr + numBitsForSubnets);
      #intIp = ipListToInt parsedIP.baseIp;
      newSubnet = intToIPList ((ipListToInt parsedIP.baseIp) + (networkIndex * (pow subnetScale 2)));
      newCidr = parsedIP.cidr + numBitsForSubnets;
    in
      #"New Subnet: ${toString newSubnet}/${toString newCidr}";
      (parseSubnet "${prettyIp newSubnet}/${toString newCidr}").subnet;
*/

/*
  subnetIn = ipSpace: networkIndex:
    let 
      parsedIP = parseSubnet ipSpace;
      subnetScale = 32 - parsedIP.cidr;
      newSubnet = intToIPList ((ipListToInt parsedIP.baseIp) + (networkIndex * (pow subnetScale 2)));
    in
      (parseSubnet "${prettyIp newSubnet}/${toString parsedIP.cidr}").subnet;
*/
  subnetIn = ipSpace: networkIndex:
    let 
      subnet = parse ipSpace;
      subnetScale = 32 - subnet.cidr;
      newSubnetAddr = intToIpList ((ipListToInt subnet.addr) + (networkIndex * (pow subnetScale 2)));
    in
      #prettyIp (check parse "${prettyIp newSubnetAddr}/${toString subnet.cidr}");
      checkSubnet (makeIp newSubnetAddr subnet.cidr);

  prettySubnetIn = ipSpace: networkIndex:
    prettySubnet (subnetIn ipSpace networkIndex);

/*
  nthAddressIn = ipSpace: networkIndex: n:
    let
      parsedIP = parseSubnet (subnetIn ipSpace networkIndex);
    in
      "${prettyIp (intToIPList ((ipListToInt parsedIP.baseIp) + n))}";
*/
  nthAddressIn = ipSpace: networkIndex: n:
    let
      subnet = subnetIn ipSpace networkIndex;
    in
      makeIp (intToIpList ((ipListToInt subnet.addr) + n)) subnet.cidr;
  
  prettyNthAddressIn = ipSpace: networkIndex: n:
    prettyIp (nthAddressIn ipSpace networkIndex n).addr;

}
