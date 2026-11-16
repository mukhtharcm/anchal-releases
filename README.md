# Anchal releases

Builds of Anchal. The app looks here for a newer version; the latest one is under Releases.

## Linux

Download `anchal-<version>-linux-x64.tar.gz` (Intel) or `-linux-arm64.tar.gz`
(ARM) from the latest release, unpack it anywhere, and run `install.sh` inside
to add Anchal to the app menu. Calls and voice notes use PulseAudio or
PipeWire.

The server, anchald, installs on any Linux machine with systemd:

```sh
curl -fsSL https://github.com/mukhtharcm/anchal-releases/releases/latest/download/install.sh | sudo sh
```

## NixOS

This repository is a flake, for Intel and ARM. To try the app:

```sh
nix run github:mukhtharcm/anchal-releases
```

To install it, add the input to your system's `flake.nix`:

```nix
inputs.anchal.url = "github:mukhtharcm/anchal-releases";
```

and, in its configuration:

```nix
environment.systemPackages = [ anchal.packages.${pkgs.system}.anchal ];
```

The server comes with a NixOS module:

```nix
imports = [ anchal.nixosModules.anchald ];
services.anchald = {
  enable = true;
  openFirewall = true;
  # url = "https://203.0.113.5:7443";  # where devices reach it, if not this machine's address
  # port = 7443;
  # extraFlags = [ ];                  # more of anchald's flags (anchald -h)
};
```

Then `sudo anchald pair` makes a link that pairs a device, `sudo anchald devices`
lists them, and `sudo anchald unpair ID` lets one go.

On Nix neither updates itself: `nix flake update` brings in a new release.
