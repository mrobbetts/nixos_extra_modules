# nixos extra modules
A few custom modules for NixOS.

Check this folder out somewhere (e.g. `/etc/nixos/extra-modules`), then include the files in `configuration.nix` as part of the `imports` list.

Also, Infinisil's super-useful little [helper](https://github.com/Infinisil/system/blob/382406251e10412baa6b0fda40bbe22aafd4a86d/config/new-modules/default.nix) can make this neater if you have many. Include `/etc/nixos/extra-modules` into the `imports` list instead, then drop that `default.nix` into this folder.
