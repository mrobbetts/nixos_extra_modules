{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.services.aes67-daemon;
  settingsFormat = pkgs.formats.json {};
  runtimeDirBase = "/var/lib/aes67-daemon";

in

{

  ###### interface

  options = {

    services.aes67-daemon = {

      enable = mkOption {
        default = false;
        type = types.bool;
        description = "Enable the AES67 daemon.";
      };

      package = mkOption {
        type = types.package;
        default = pkgs.aes67-linux-daemon;
        defaultText = literalExpression "pkgs.aes67-linux-daemon";
        description = lib.mdDoc "Which aes67-daemon package to use.";
      };

      user = mkOption {
        type = types.str;
        default = "aes67-daemon";
        description = "User as whom to run the aes67-daemon.";
      };

      group = mkOption {
        type = types.str;
        default = "aes67-daemon";
        description = "Group under which to run the aes67-daemon.";
      };

      interface = mkOption {
        type = types.str;
        default = "lo";
        description = "Network interface on which to host the web interface";
      };

      multicastBaseAddress = mkOption {
        type = types.int;
        default = 1;
        description = ''
          The base multicast address component to use for RTP streams. For a given 
          value x, a base multicast address of 239.x.0.1 will be used.
        '';
      };

      # Freeform options to merge directly into the provided upstream JSON config.
      settings = mkOption {
        description = lib.mdDoc "The freeform/attrset configuration, to be merged with the daemon.conf provided by the package.";
        type = lib.types.submodule {

          freeformType = settingsFormat.type;

          options = {
            status_file = mkOption {
              type = types.str;
              default = "${runtimeDirBase}/status.json";
              description = "Path to the status.json file.";
            };

            http_port = mkOption { 
              type = types.port;
              default = 8080;
              description = lib.mdDoc "The port at which the webui will be hosted";
            };
          };
        };
        default = { };
        example = {
          custom_node_id = "My AES67 Endpoint";
        };
      };
    };
  };


  ###### implementation

  config = mkIf cfg.enable {

#    environment.systemPackages = [ cfg.package cfg.ffmpegPackage pkgs.nodejs ];
    environment.systemPackages = [ cfg.package pkgs.aes67-linux-daemon-webui ];

    users.users = mkIf (cfg.user == "aes67-daemon") {
      aes67-daemon = {
        group = cfg.group;
        createHome = false;
        description = "aes67-daemon user";
        isSystemUser = true;
      };
    };

    users.groups = mkIf (cfg.group == "aes67-daemon") {
      aes67-daemon = {};
    };

    systemd.services.aes67-daemon = {

      wantedBy = [ "multi-user.target" ];
/*
      preStart = ''
        if [[ ! -f ${runtimeDirBase}/db/shinobi.sqlite ]]; then
          echo "No database found; copying default into place"
          mkdir -p ${runtimeDirBase}/db
          cp ${cfg.package}/lib/node_modules/shinobi/sql/shinobi.sample.sqlite ${runtimeDirBase}/shinobi.sqlite
          chmod 644 ${runtimeDirBase}/shinobi.sqlite
        else
          echo "Database exists; not copying default"
        fi

        #echo "Generating conf.json"
        #cat JSON: ${builtins.toJSON cfg.settings}
        #cat ${cfg.package}/lib/node_modules/shinobi/conf.sample.json | ${pkgs.jq}/bin/jq 'del(.addStorage) * $settings' --argjson settings '{"port":"8081", "ffmpegDir": "${pkgs.ffmpeg}/bin/ffmpeg", "videosDir":"${runtimeDirBase}/videos" , "binDir": "${runtimeDirBase}/binDir", "databaseType": "sqlite3", "db":{"filename":"${runtimeDirBase}/db/shinobi.sqlite"}}' > ${runtimeDirBase}/conf.json

        #if [[ ! -f ${runtimeDirBase}/super.json ]]; then
        #  echo "No superuser file found; copying default into place"
        #  cp ${cfg.package}/lib/node_modules/shinobi/super.sample.json ${runtimeDirBase}/super.json
        #  chmod 664 ${runtimeDirBase}/super.json
        #else
        #  echo "Superuser exists; not copying default"
        #fi
      '';
*/
      serviceConfig =
        let
          configJSONFile = 
            let
              upstreamJSON = builtins.fromJSON(builtins.readFile "${cfg.package}/etc/daemon.conf");
              baseAddrToAddr = x: "239.${toString x}.0.1";
              # We take the package/upstream JSON file, we add a JSON-ified copy of the contents of cfg.settings, and then we also insert the path to ffmpeg under the correct key name.
              # recursiveUpdate is used in place of //, because the upstream JSON includes an incomplate db value that we want to add fields to, and // clobbers instead of merges.
              # Note that, we can't define the default ffmpeg path as an entry in settings, because default values end up in documentation, and they aren't allowed to reference pkgs.
              # So, here we are.
            #in  settingsFormat.generate "shinobi-conf.json" (lib.recursiveUpdate (builtins.removeAttrs upstreamJSON ["addStorage"]) cfg.settings // {ffmpegDir = "${cfg.ffmpegPackage}/bin/ffmpeg";} );
            in  settingsFormat.generate "aes67-daemon.conf" (lib.recursiveUpdate upstreamJSON cfg.settings // { http_base_dir = "${pkgs.aes67-linux-daemon-webui}/lib/node_modules/aes67-daemon-webui/dist";
                                                                                                                rtp_mcast_base = baseAddrToAddr cfg.multicastBaseAddress;
                                                                                                                ptp_status_script = "${cfg.package}/scripts/ptp_status.sh";
                                                                                                                interface_name = cfg.interface;
                                                                                                              });
        in
      {
        Type = "notify";

        # Will be adjusted by service during startup
        WatchdogSec = 10;

        ExecStart = "${cfg.package}/bin/aes67-daemon --config ${configJSONFile}";
        User = cfg.user;
        Group = cfg.group;
        RuntimeDirectory = "aes67-daemon";
        StateDirectory = "aes67-daemon";

        Wants = "sys-devices-virtual-net-${cfg.interface}.device";
        BindsTo = "sys-devices-virtual-net-${cfg.interface}.device";

        ###
        # Taken from upstream.
        CapabilityBoundingSet = "";
        DevicePolicy = "closed";
        LockPersonality = "yes";

        MemoryDenyWriteExecute = "yes";
        NoNewPrivileges = "yes";
        PrivateDevices = "yes";
        PrivateMounts = "yes";
        PrivateTmp = "yes";
        PrivateUsers = "yes";
        ProcSubset = "all";
        ProtectClock = "yes";
        ProtectControlGroups = "yes";
        ProtectHome = "yes";
        ProtectHostname = "yes";
        ProtectKernelLogs = "yes";
        ProtectKernelModules = "yes";
        ProtectKernelTunables = "yes";
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RemoveIPC = "yes";
        RestrictAddressFamilies = "AF_INET AF_NETLINK AF_UNIX";
        RestrictNamespaces = "yes";
        RestrictRealtime = "yes";
        RestrictSUIDSGID = "yes";
        SystemCallArchitectures = "native";

        SystemCallFilter = [
          "~@clock"
          "~@clock"
          "~@cpu-emulation"
          "~@debug"
          "~@module"
          "~@mount"
          "~@obsolete"
          "~@privileged"
          "~@raw-io"
          "~@reboot"
          "~@resources"
          "~@swap"
        ];
        UMask = "077";

        # Paths matching daemon.conf
        ReadOnlyPaths = configJSONFile;
        ReadWritePaths = cfg.settings.status_file;
      };
    };
  };
}
