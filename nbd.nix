{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.nbd;

  blockDevExports = filter (e: e.type == "block") cfg.exports;
  zramExports     = filter (e: e.type == "zram" ) cfg.exports;

  makeRule = e: ''
    ACTION=="add", SYMLINK=="${e.name}", ENV{SYSTEMD_WANTS}="nbd-init.service"
  '';

  rules = concatStringsSep "" (map makeRule cfg.exports);

  # Serialize a device.
  printExport = e: "${e.name}${e.size}${e.type}";

  toExportSection = e: ''
    [${e.name}]
    exportname = /dev/${e.name}
    trim = true
  '';

  toDev = e: "dev-${e.name}.device";


  toZramDeviceEntry = e: e // { owner = cfg.user; group = cfg.group; };

#  toZramDeviceEntry = e: {
#    name = e.name;
#    size = e.size;
#    owner = cfg.user;
#    group = cfg.group;
#  };

in

{

  ###### interface

  options = {

    nbd = {

      enable = mkOption {
        default = false;
        type = types.bool;
        description = lib.mdDoc ''
          Enable the sharing of block devices over the network via NBD.
          See https://www.kernel.org/doc/Documentation/blockdev/zram.txt
        '';
      };

      user = mkOption {
        type = types.str;
        default = "nbd";
        description = lib.mdDoc "User to run the nbd daemon as.";
      };

      group = mkOption {
        type = types.str;
        default = "nbd";
        description = lib.mdDoc "Group to run the nbd daemon as.";
      };

      exports = mkOption {
        default = [];
        type = types.listOf types.attrs;
        description = lib.mdDoc ''
          A list of attribute sets each containing { name, size, type } and describing one
          nbd export device.
        '';
      };
    };
  };

  config = mkIf cfg.enable {

    # Disabling this for the moment, as it would create and mkswap devices twice,
    # once in stage 2 boot, and again when the zram-reloader service starts.
    # boot.kernelModules = [ "zram" ];

#   services.udev.extraRules = rules;
    services.udev.packages = [
      (pkgs.writeTextFile {
        name = "extra-nbd-rules";
        text = rules;
        destination = "/etc/udev/rules.d/98_2-nbd.rules";
      })
    ];

    # Add the necessary entries to the zramBlocks module.
    zramBlocks.enable = true;
    zramBlocks.devices = map toZramDeviceEntry zramExports;

    systemd.services = {
      nbd-init = {
        description = "Serve block devices over NBD.";
        bindsTo  = (map toDev cfg.exports);
        after    = (map toDev cfg.exports) ++ [ "zram-reloader.service" ];
        requires = (map toDev cfg.exports) ++ [ "zram-reloader.service" ];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "forking";
          ExecStart = "${pkgs.nbd}/bin/nbd-server -C ${pkgs.writeText "nbd-server.conf" ''
                        [generic]
                        allowlist = true
                        group = ${cfg.group}
                        user = ${cfg.user}
                        
                        ${lib.concatStringsSep "\n" (map toExportSection cfg.exports)}
                      ''}";
          Restart = "on-failure";
          User = cfg.user;
          Group = cfg.group;
        };
        restartTriggers = [ (builtins.hashString "md5" (lib.concatStrings (map printExport cfg.exports))) ];
        restartIfChanged = true;
      };
    };
/*
    users.users = [
      { name = cfg.user;
        group = cfg.group;
      }
    ];
*/
    users.users = {
      "${cfg.user}" = {
        group = cfg.group;
      };
    };
/*
    users.groups = [
      { name = cfg.group; }
    ];
*/
    users.groups = {
      "{$cfg.group}" = {};
    };

/*
    swapDevices =
      let
        useZramSwap = dev:
          {
            device = "/dev/${dev}";
            priority = cfg.priority;
          };
      in map useZramSwap devices;

*/

  };

}
