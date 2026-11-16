# Anchal for Nix and NixOS, on Intel and ARM. scripts/release.sh copies this
# file, with sources.json (the newest release's builds and their hashes), to
# the public releases repo, so it is used from there:
#
#   inputs.anchal.url = "github:mukhtharcm/anchal-releases";
#
#   environment.systemPackages = [ anchal.packages.${pkgs.system}.anchal ];
#
#   imports = [ anchal.nixosModules.anchald ];
#   services.anchald = { enable = true; openFirewall = true; };
#
# or, to try the app: nix run github:mukhtharcm/anchal-releases
#
# Both wrap the release's own builds. Neither updates itself: the Nix store
# cannot be written to, so the app opens the release's page instead, and a
# new release arrives with `nix flake update`.
{
  description = "Anchal, a WhatsApp and Telegram client, and anchald, its server";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      sources = builtins.fromJSON (builtins.readFile ./sources.json);
      arch = { x86_64-linux = "x64"; aarch64-linux = "arm64"; };
      goArch = { x86_64-linux = "amd64"; aarch64-linux = "arm64"; };
      forAll = f: nixpkgs.lib.genAttrs (builtins.attrNames arch) (system: f nixpkgs.legacyPackages.${system} system);
      fetch = pkgs: name: pkgs.fetchurl {
        url = "https://github.com/mukhtharcm/anchal-releases/releases/download/v${sources.version}/${name}";
        hash = sources.hashes.${name};
      };
    in
    {
      packages = forAll (pkgs: system: rec {
        anchal = pkgs.stdenv.mkDerivation {
          pname = "anchal";
          inherit (sources) version;
          src = fetch pkgs "anchal-${sources.version}-linux-${arch.${system}}.tar.gz";
          sourceRoot = ".";
          nativeBuildInputs = with pkgs; [ autoPatchelfHook makeWrapper copyDesktopItems ];
          buildInputs = with pkgs; [ gtk3 glib pango cairo harfbuzz atk gdk-pixbuf libepoxy fontconfig stdenv.cc.cc.lib ];
          # Flutter opens EGL at run time; libglvnd finds the machine's driver.
          runtimeDependencies = [ pkgs.libGL ];
          # pactl, parec and pacat for calls and voice notes, notify-send for
          # notifications, xdg-open for links and files.
          installPhase = ''
            runHook preInstall
            mkdir -p $out/lib/anchal $out/bin $out/share/icons/hicolor/512x512/apps
            cp -r . $out/lib/anchal
            cp anchal.png $out/share/icons/hicolor/512x512/apps/com.mukhtharcm.anchal.png
            # Flutter opens the core, libwa.so, by its bare name, which the
            # bundle's $ORIGIN found before autoPatchelf rewrote the paths.
            makeWrapper $out/lib/anchal/anchal $out/bin/anchal \
              --prefix LD_LIBRARY_PATH : $out/lib/anchal/lib \
              --prefix PATH : ${pkgs.lib.makeBinPath (with pkgs; [ pulseaudio libnotify xdg-utils dbus ])} \
              --prefix XDG_DATA_DIRS : ${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}:${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}
            runHook postInstall
          '';
          desktopItems = [
            (pkgs.makeDesktopItem {
              name = "com.mukhtharcm.anchal";
              desktopName = "Anchal";
              comment = "WhatsApp and Telegram in one place";
              exec = "anchal";
              icon = "com.mukhtharcm.anchal";
              categories = [ "Network" "InstantMessaging" ];
              startupWMClass = "com.mukhtharcm.anchal";
            })
          ];
          meta = {
            description = "A personal WhatsApp and Telegram client";
            homepage = "https://github.com/mukhtharcm/anchal-releases";
            mainProgram = "anchal";
            platforms = builtins.attrNames arch;
            sourceProvenance = [ pkgs.lib.sourceTypes.binaryNativeCode ];
          };
        };

        anchald = pkgs.stdenv.mkDerivation {
          pname = "anchald";
          inherit (sources) version;
          src = fetch pkgs "anchald-${sources.version}-server-${goArch.${system}}.gz";
          dontUnpack = true;
          nativeBuildInputs = [ pkgs.autoPatchelfHook ];
          buildInputs = [ pkgs.stdenv.cc.cc.lib ];
          installPhase = ''
            install -d $out/bin
            gzip -dc $src > $out/bin/anchald
            chmod 755 $out/bin/anchald
          '';
          meta = {
            description = "Anchal's server: keeps accounts connected for every paired device";
            mainProgram = "anchald";
            platforms = builtins.attrNames arch;
            sourceProvenance = [ pkgs.lib.sourceTypes.binaryNativeCode ];
          };
        };

        default = anchal;
      });

      nixosModules.anchald = { config, lib, pkgs, ... }:
        let cfg = config.services.anchald; in
        {
          options.services.anchald = {
            enable = lib.mkEnableOption "anchald, the Anchal server";
            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.anchald;
              description = "The anchald to run.";
            };
            port = lib.mkOption { type = lib.types.port; default = 7443; description = "The port to listen on."; };
            url = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "https://203.0.113.5:7443";
              description = "Where devices reach the server; by default https:// and this machine's address.";
            };
            openFirewall = lib.mkOption { type = lib.types.bool; default = false; description = "Open the port in the firewall."; };
            extraFlags = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              example = [ "-name" "home" ];
              description = "More of anchald's flags (anchald -h lists them).";
            };
          };

          config = lib.mkIf cfg.enable {
            # `sudo anchald pair`, `devices` and `unpair ID` manage the paired
            # devices, as after scripts/install.sh.
            environment.systemPackages = [
              (pkgs.writeShellScriptBin "anchald" ''
                exec ${pkgs.util-linux}/bin/runuser -u anchald -- ${lib.getExe cfg.package} -data /var/lib/anchald "$@"
              '')
            ];
            users.users.anchald = { isSystemUser = true; group = "anchald"; home = "/var/lib/anchald"; };
            users.groups.anchald = { };
            networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
            systemd.services.anchald = {
              description = "Anchal server";
              wantedBy = [ "multi-user.target" ];
              after = [ "network-online.target" ];
              wants = [ "network-online.target" ];
              serviceConfig = {
                ExecStart = lib.escapeShellArgs ([ (lib.getExe cfg.package) "-data" "/var/lib/anchald" "-addr" ":${toString cfg.port}" ]
                  ++ lib.optionals (cfg.url != null) [ "-url" cfg.url ] ++ cfg.extraFlags);
                User = "anchald";
                Group = "anchald";
                StateDirectory = "anchald";
                Restart = "on-failure";
              };
            };
          };
        };
    };
}
