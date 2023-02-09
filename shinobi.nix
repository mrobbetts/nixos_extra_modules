{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.services.shinobi;
  settingsFormat = pkgs.formats.json {};
  runtimeDirBase = "/var/lib/shinobi";

in

{

  ###### interface

  options = {

    services.shinobi = {

      enable = mkOption {
        default = false;
        type = types.bool;
        description = "Enable the Shinobi server.";
      };

      package = mkOption {
        type = types.package;
        default = pkgs.shinobi;
        defaultText = literalExpression "pkgs.shinobi";
        description = lib.mdDoc "Which Shinobi package to use.";
      };

      ffmpegPackage = mkOption {
        type = types.package;
        default = pkgs.ffmpeg;
        defaultText = literalExpression "pkgs.ffmpeg";
        description = lib.mdDoc "Which ffmpeg package to use.";
      };

      user = mkOption {
        type = types.str;
        default = "shinobi";
        description = "User to run the Shinobi daemon as.";
      };

      group = mkOption {
        type = types.str;
        default = "shinobi";
        description = "Group to run the Shinobi daemon as.";
      };

      superUsers = mkOption {
        description = "The list of superuser accounts";
        type = types.listOf (types.submodule { 
          options = {
            mail = mkOption { type = types.str; description = "The username for login."; };
            pass = mkOption { type = types.str; description = "The password for login."; };
          };
        });
      };

      settings = mkOption {
        description = lib.mdDoc "The freeform/attrset contents of conf.json, to be merged with the conf.sample.json provided by the package.";
        type = lib.types.submodule {

          freeformType = settingsFormat.type;

          options = {
            port = mkOption { 
              type = types.port;
              default = 8080;
              description = lib.mdDoc "The port to listen on";
            };

            videosDir = mkOption {
              type = types.str;
              default = "${runtimeDirBase}/videos";
              description = "Storage path for the videos.";
            };

            binDir = mkOption {
              type = types.str;
              default = "${runtimeDirBase}/binDir";
              description = "Storage path for the binDir.";
            };

            databaseType = mkOption {
              type = types.str; 
              default = "sqlite3";
              description = "Database type to use.";
            };

            db = {
              filename = mkOption {
                type = types.str;
                default = "${runtimeDirBase}/shinobi.sqlite";
                description = "The path to store/find the database file.";
              };
            };
          };
        };
        default = { };
        example = {
          port = 8081;
          databaseType = "sqlite3";
          db.filename = "/path/to/database.sqlite";
        };
      };
    };
  };


  ###### implementation

  config = mkIf cfg.enable {

    environment.systemPackages = [ cfg.package cfg.ffmpegPackage pkgs.nodejs ];

    users.users = mkIf (cfg.user == "shinobi") {
      shinobi = {
        group = cfg.group;
        createHome = false;
        #uid = config.ids.uids.shinobi;
        description = "shinobi daemon user";
        isSystemUser = true;
      };
    };

    users.groups = mkIf (cfg.group == "shinobi") {
      #shinobi.gid = config.ids.gids.shinobi;
      shinobi = {};
    };

    systemd.services.shinobi = {
      path = [ "/run/wrappers" pkgs.nodejs ];

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
            let upstreamJSON = builtins.fromJSON(builtins.readFile "${pkgs.shinobi}/lib/node_modules/shinobi/conf.sample.json");
              # We take the package/upstream JSON file, we add a JSON-ified copy of the contents of cfg.settings, and then we also insert the path to ffmpeg under the correct key name.
              # recursiveUpdate is used in place of //, because the upstream JSON includes an incomplate db value that we want to add fields to, and // clobbers instead of merges.
              # Note that, we can't define the default ffmpeg path as an entry in settings, because default values end up in documentation, and they aren't allowed to reference pkgs.
              # So, here we are.
            in  settingsFormat.generate "shinobi-conf.json" (lib.recursiveUpdate (builtins.removeAttrs upstreamJSON ["addStorage"]) cfg.settings // {ffmpegDir = "${cfg.ffmpegPackage}/bin/ffmpeg";} );
          superUsersFile =
            settingsFormat.generate "shinobi-super.json" cfg.superUsers;
        in 
      {
        ExecStart = "${cfg.package}/bin/shinobi ${configJSONFile} ${superUsersFile}";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = "${cfg.package}/lib/node_modules/shinobi";
        RuntimeDirectory = "shinobi";
        StateDirectory = "shinobi";
      };
    };
  };
}
