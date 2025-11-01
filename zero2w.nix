{
  lib,
  modulesPath,
  pkgs,
  ...
}: {
  imports = [
    ./sd-image.nix
  ];

  nixpkgs.overlays = [
    # Some packages (ahci fail... this bypasses that) https://discourse.nixos.org/t/does-pkgs-linuxpackages-rpi3-build-all-required-kernel-modules/42509
    (final: super: {
      makeModulesClosure = x: super.makeModulesClosure (x // {allowMissing = true;});
    })

    (final: super: {
      python3 = super.python3.override {
        packageOverrides = python-self: python-super: {
          gst-python = python-super.gst-python.overrideAttrs (old: {
            mesonFlags =
              (old.mesonFlags or [])
              ++ [
                # Don't even try to build the testsuite
                "-Dtests=disabled"
              ];
            doCheck = false;
          });
        };
      };
    })

    (final: prev: {
      python3Packages = prev.python3Packages.overrideScope (python-final: python-prev: {
        tidalapi = python-prev.tidalapi.overrideAttrs (attrs: rec {
          version = "0.8.6";
          src = prev.fetchFromGitHub {
            owner = "EbbLabs";
            repo = "python-tidal";
            tag = "v${version}";
            hash = "sha256-SsyO0bh2ayHfGzINBW1BTTPS/ICvIymIhQ1HUPRFOwU=";
          };
        });
      });
      mopidy-tidal = prev.mopidy-tidal.overrideAttrs (_: rec {
        pname = "latest-mopidy-tidal";
        version = "0.3.11";
        src = prev.fetchFromGitHub {
          owner = "EbbLabs";
          repo = "mopidy-tidal";
          rev = "v${version}";
          hash = "sha256-wqx/30UQVm1fEwP/bZeW7TtzGfn/wI0klQnFr9E3AOs=";
        };
      });
    })

  ];

  nixpkgs.hostPlatform = "aarch64-linux";
  # ! Need a trusted user for deploy-rs.
  nix.settings.trusted-users = ["@wheel"];
  nix.settings.experimental-features = ["nix-command" "flakes"];
  system.stateVersion = "24.05";

  zramSwap = {
    enable = true;
    algorithm = "zstd";
  };

  # TODO does the rest need to move into this namespace?
  image = {
    fileName = "zero2.img";
  };
  sdImage = {
    # bzip2 compression takes loads of time with emulation, skip it. Enable this if you're low on space.
    compressImage = false;
    # imageName = "zero2.img";

    extraFirmwareConfig = {
      # Give up VRAM for more Free System Memory
      # - Disable camera which automatically reserves 128MB VRAM
      start_x = 0;
      # - Reduce allocation of VRAM to 16MB minimum for non-rotated (32MB for rotated)
      gpu_mem = 16;

      # Configure display to 800x600 so it fits on most screens
      # * See: https://elinux.org/RPi_Configuration
      hdmi_group = 2;
      hdmi_mode = 8;
    };
  };

  hardware = {
    enableRedistributableFirmware = lib.mkForce false;
    firmware = [pkgs.raspberrypiWirelessFirmware]; # Keep this to make sure wifi works
    i2c.enable = true;

    deviceTree = {
      enable = true;
      kernelPackage = pkgs.linuxKernel.packages.linux_rpi3.kernel;
      filter = "*2837*";

      overlays = [
        {
          name = "enable-i2c";
          dtsFile = ./dts/i2c.dts;
        }
        {
          name = "pwm-2chan";
          dtsFile = ./dts/pwm.dts;
        }
      ];
    };
  };

  boot = {
    kernelPackages = pkgs.linuxPackages_rpi02w;

    initrd.availableKernelModules = [
      "xhci_pci"
      "usbhid"
      "usb_storage"
    ];
    loader = {
      grub.enable = false;
      generic-extlinux-compatible.enable = true;
    };

    # Avoids warning: mdadm: Neither MAILADDR nor PROGRAM has been set. This will cause the `mdmon` service to crash.
    # See: https://github.com/NixOS/nixpkgs/issues/254807
    swraid.enable = lib.mkForce false;
  };

  networking = {
    interfaces."wlan0".useDHCP = true;
    wireless = {
      enable = true;
      interfaces = ["wlan0"];
      # ! Change the following to connect to your own network
      networks = {
        "Livebox-6300" = {
          psk = "tAyZq95Rn4L5eGEdvZ";
        };
      };
    };
  };

  # Enable OpenSSH out of the box.
  services.sshd.enable = true;

  # NTP time sync.
  services.timesyncd.enable = true;

  # ! Change the following configuration
  users.mutableUsers = false;
  users.users.mopidy.extraGroups = [ "pipewire" ];
  users.users.john = {
    isNormalUser = true;
    home = "/home/john";
    description = "John";
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    hashedPassword = "$y$j9T$eKhMANNrwREak4/HLP77I/$8Uz7HqZXKVnGoM1YRLIaDJUdNygA6cWv8C/bZSDf6ND";
    # ! Be sure to put your own public key here
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGPxIqAr93XSYcZMA+AMpH8txaQjCHS03Trb+6KAB8tJ john@nixos"
    ];
  };

  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };
  # ! Be sure to change the autologinUser.
  services.getty.autologinUser = "john";

  # ! change the host name if you like
  networking.hostName = "reepicheep";

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
      domain = true;
      workstation = true;
    };
  };

  environment.systemPackages = [
    pkgs.btop
    pkgs.vim
    pkgs.tmux
    pkgs.alsa-utils
    pkgs.ncpamixer
    pkgs.git
    # pkgs.git-annex
  ];

  services.mopidy = {
    enable = true;
    extensionPackages = with pkgs; [
      mopidy-local
      mopidy-iris
      mopidy-mpd
      mopidy-mpris
      mopidy-tidal
    ];
    settings = {
      local.media_dir = "/var/lib/mopidy/Library";
      m3u = {
        playlists_dir = "/var/lib/mopidy/playlists/playlists";
        base_dir = "/var/lib/mopidy/Library";
      };
      tidal.quality = "LOSSLESS";
      tidal.auth_method = "PKCE";
      http.hostname = "0.0.0.0";
    };
  };

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    systemWide = true;
  };

  networking.firewall.enable = true;
  # services.ssh opens it's own port
  networking.firewall.allowedTCPPorts = [
    6680 # mopidy
    8989 # mopidy login
  ];

  programs.bash.shellInit = ''
  set -o vi
  '';
}
