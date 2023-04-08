{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.zramBlocks;

#  devices = map (nr: "zram${toString nr}") (range 0 (cfg.numDevices - 1));

  modprobe = "${pkgs.kmod}/bin/modprobe";

  numberEntries = entries:
    let
      numberEntries' = e_s:
        [((builtins.head e_s) // { index = (builtins.length e_s) - 1; })] ++ (optionals ((builtins.length e_s) > 1) (numberEntries' (builtins.tail e_s)));
    in 
      reverseList (numberEntries' (reverseList entries));

  devs = numberEntries cfg.devices;

  blockDevs = filter (dev: dev.type == "block") devs;
  swapDevs = filter (dev: dev.type == "swap") devs;

  makeRule = dev: ''
    KERNEL=="zram${toString dev.index}", SUBSYSTEM=="block", ACTION=="add", SYMLINK+="${dev.name}", TAG+="systemd", ATTR{disksize}="${dev.size}", OWNER="${dev.owner}", GROUP="${dev.group}"
  '';

#  makeRule = dev: ''
#    KERNEL=="zram${toString dev.index}", SUBSYSTEM=="block", ACTION=="add",    SYMLINK+="${dev.name}", TAG+="systemd", ATTR{disksize}="${dev.size}", OWNER="${dev.owner}", GROUP="${dev.group}"
#    #KERNEL=="zram${toString dev.index}", SUBSYSTEM=="block", ACTION=="add",    SYMLINK+="${dev.name}", TAG+="systemd", ATTR{disksize}=="0", ATTR{disksize}="${dev.size}", ENV{SYSTEMD_WANTS}="zram-nbd-init.service" OWNER="${cfg.nbduser}", GROUP="${cfg.nbdgroup}"
#    #KERNEL=="zram${toString dev.index}", SUBSYSTEM=="block", ACTION=="remove", SYMLINK-="${dev.name}", TAG-="systemd"
#  '';

  rules = concatStringsSep "" (map makeRule devs);

  # Serialize a device.
  printDevice = dev: "${dev.name}${toString dev.index}${dev.size}";

  toExportSection = devv: ''
    [${devv.name}]
    exportname = /dev/${devv.name}
    trim = true
  '';

# toDev = devv: "dev-zram${toString devv.index}.device";
  toDev = devv: "dev-${devv.name}.device";

in

{

  ###### interface

  options = {

    zramBlocks = {

      enable = mkOption {
        default = false;
        type = types.bool;
        description = lib.mdDoc ''
          Enable in-memory compressed block devices and/or swap space provided by the zram kernel
          module.
          See https://www.kernel.org/doc/Documentation/blockdev/zram.txt
        '';
      };

      nbduser = mkOption {
        type = types.str;
        default = "nbd";
        description = lib.mdDoc "User to run the nbd daemon as.";
      };

      nbdgroup = mkOption {
        type = types.str;
        default = "nbd";
        description = lib.mdDoc "Group to run the nbd daemon as.";
      };

      devices = mkOption {
        default = [];
        type = types.listOf types.attrs;
        description = lib.mdDoc ''
          A list of attribute sets each containing { name, size, type } and describing one
          ZRAM block device.
        '';
      };

#      numDevices = mkOption {
#        default = 1;
#        type = types.int;
#        description = ''
#          Number of zram swap devices to create.
#        '';
#      };

#      memoryPercent = mkOption {
#        default = 50;
#        type = types.int;
#        description = ''
#          Maximum amount of memory that can be used by the zram swap devices
#          (as a percentage of your total memory). Defaults to 1/2 of your total
#          RAM.
#        '';
#      };

#      priority = mkOption {
#        default = 5;
#        type = types.int;
#        description = ''
#          Priority of the zram swap devices. It should be a number higher than
#          the priority of your disk-based swap devices (so that the system will
#          fill the zram swap devices before falling back to disk swap).
#        '';
#      };

    };

  };

  config = mkIf cfg.enable {

    system.requiredKernelConfig = with config.lib.kernelConfig; [
      (isModule "ZRAM")
    ];

    # Disabling this for the moment, as it would create and mkswap devices twice,
    # once in stage 2 boot, and again when the zram-reloader service starts.
    # boot.kernelModules = [ "zram" ];

#    boot.kernelModules = [ "zram" ];

    boot.extraModprobeConfig = ''
      options zram num_devices=${toString (builtins.length cfg.devices)}
      #options nbd nbds_max=${toString (builtins.length cfg.devices)}
    '';

#   services.udev.extraRules = rules;
    services.udev.packages = [
      (pkgs.writeTextFile {
        name = "extra-zram-rules";
        text = rules;
        destination = "/etc/udev/rules.d/98_1-zram.rules";
      })
    ];

    systemd.services =
/*
        createZramInitService = dev:
          nameValuePair "zram-init-${dev}" {
            description = "Init swap on zram-based device ${dev}";
            bindsTo = [ "dev-${dev}.swap" ];
            after = [ "dev-${dev}.device" "zram-reloader.service" ];
            requires = [ "dev-${dev}.device" "zram-reloader.service" ];
            before = [ "dev-${dev}.swap" ];
            requiredBy = [ "dev-${dev}.swap" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStop = "${pkgs.runtimeShell} -c 'echo 1 > /sys/class/block/${dev}/reset'";
            };
            script = ''
              set -u
              set -o pipefail
              
              # Calculate memory to use for zram
              totalmem=$(${pkgs.gnugrep}/bin/grep 'MemTotal: ' /proc/meminfo | ${pkgs.gawk}/bin/awk '{print $2}')
              mem=$(((totalmem * ${toString cfg.memoryPercent} / 100 / ${toString cfg.numDevices}) * 1024))

              echo $mem > /sys/class/block/${dev}/disksize
              ${pkgs.utillinux}/sbin/mkswap /dev/${dev}
            '';
            restartIfChanged = false;
          };
      in listToAttrs ((map createZramInitService devices) 

      [(nameValuePair "zram-init-${dev}" {
            description = "Init swap on zram-based device ${dev}";
            bindsTo = [ "dev-${dev}.swap" ];
            after = [ "dev-${dev}.device" "zram-reloader.service" ];
            requires = [ "dev-${dev}.device" "zram-reloader.service" ];
            before = [ "dev-${dev}.swap" ];
            requiredBy = [ "dev-${dev}.swap" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStop = "${pkgs.runtimeShell} -c 'echo 1 > /sys/class/block/${dev}/reset'";
            };
            script = ''
              set -u
              set -o pipefail

              # Calculate memory to use for zram
              totalmem=$(${pkgs.gnugrep}/bin/grep 'MemTotal: ' /proc/meminfo | ${pkgs.gawk}/bin/awk '{print $2}')
              mem=$(((totalmem * ${toString cfg.memoryPercent} / 100 / ${toString cfg.numDevices}) * 1024))

              echo $mem > /sys/class/block/${dev}/disksize
              ${pkgs.utillinux}/sbin/mkswap /dev/${dev}
            '';
            restartIfChanged = false;
      }]
      ++
      [(nameValuePair "zram-reloader"
        {
          description = "Reload zram kernel module when number of devices changes";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStartPre = "${modprobe} -r zram";
            ExecStart = "${modprobe} zram";
            ExecStop = "${modprobe} -r zram";
          };
          restartTriggers = [ cfg.numDevices ];
          restartIfChanged = true;
        })]);
   in
*/
    {
/*
      zram-nbd-init = {
        description = "Serve zram block devices over NBD.";
        bindsTo  = (map toDev devs);
        after    = (map toDev devs) ++ [ "zram-reloader.service" ];
        requires = (map toDev devs) ++ [ "zram-reloader.service" ];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "forking";
          ExecStart = "${pkgs.nbd}/bin/nbd-server -C ${pkgs.writeText "nbd-server.conf" ''
                        [generic]
                        allowlist = true
                        group = nbd
                        user = nbd
                        ${lib.concatStrings (map toExportSection devs)}
                      ''}";
          Restart = "on-failure";
        };
        restartTriggers = map (builtins.hashString "sha256") (map printDevice devs);
        restartIfChanged = true;
      };
*/      
      zram-reloader = {
        description = "Reload zram kernel module when devices configuration changes";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStartPre = "${modprobe} -r zram";
          ExecStart = "${modprobe} zram";
          ExecStop = "${modprobe} -r zram";
        };
        restartTriggers = map (builtins.hashString "sha256") (map printDevice devs);
        restartIfChanged = true;
      };
    };
/*
    users.users = [
      { name = cfg.nbduser;
        group = cfg.nbdgroup;
        #home = "${cfg.statePath}/home";
        #shell = "${pkgs.bash}/bin/bash";
        #uid = config.ids.uids.gitlab;
      }
    ];

    users.groups = [
      { name = cfg.nbdgroup;
        #gid = config.ids.gids.gitlab;
      }
    ];
*/
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
