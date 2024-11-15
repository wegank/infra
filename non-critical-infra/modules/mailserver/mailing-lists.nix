# This module provides the mailing list definitions for `@nixos.org`.
#
# Simply change the `lists` attribute set below to create new mailing lists or
# edit membership of existing lists.
#
# If you wish to hide your email address, you can encrypt it with SOPS. Just
# run `nix run .#encrypt-email-address -- --help` and follow the instructions.

{ config, lib, ... }:

let
  # Mailing lists go here.
  # TODO: replace with the real `nixos.org` mailing lists.
  listsWithSecretFiles = {
    "test-list@mail-test.nixos.org" = [
      "jfly@playground.jflei.com"
      ../../secrets/jfly-email.umbriel
      "jeremyfleischman+subscriber@gmail.com"
    ];
  };

  fileToSecretId = file: builtins.baseNameOf file;

  listsWithSecretPlaceholders = lib.mapAttrs' (name: members: {
    name = name;
    value = map (
      member:
      if builtins.isString member then member else config.sops.placeholder.${fileToSecretId member}
    ) members;
  }) listsWithSecretFiles;

  secretFiles = lib.pipe listsWithSecretFiles [
    (lib.mapAttrsToList (_name: members: members))
    lib.flatten
    (builtins.filter (member: !builtins.isString member))
  ];
in

{
  # Declare secrets for every secret email in the lists above.
  sops.secrets = builtins.listToAttrs (
    map (file: {
      name = fileToSecretId file;
      value = {
        format = "binary";
        sopsFile = file;
      };
    }) secretFiles
  );

  sops.templates."postfix-virtual-mailing-lists" = {
    content = lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        name: members: "${name} ${lib.concatStringsSep ", " members}"
      ) listsWithSecretPlaceholders
    );

    # Need to restart postfix-setup to rerun `postmap` and generate updated `.db`
    # files whenever mailing list membership changes.
    # This could go away if sops-nix gets support for "input addressed secret
    # paths": https://github.com/Mic92/sops-nix/issues/648
    restartUnits = [ "postfix-setup.service" ];
  };

  services.postfix.mapFiles.virtual-mailing-lists =
    config.sops.templates."postfix-virtual-mailing-lists".path;

  services.postfix.config.virtual_alias_maps = [ "hash:/etc/postfix/virtual-mailing-lists" ];
}
