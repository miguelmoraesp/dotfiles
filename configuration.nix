{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Hostname and basic user settings
  networking = {
    hostName = "nix";
    networkmanager.enable = true;  # Pre-configured NetworkManager
  };

  # Set time zone and locale
  time.timeZone = "America/Sao_Paulo";
  i18n = {
    defaultLocale = "en_US.UTF-8";
    supportedLocales = [ "en_US.UTF-8" ];
  };

  # User configuration
  users.users.zmigueel = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];  # User on sudo (wheel group)
    packages = with pkgs; [ vim git firefox discord spotify hyprland vesktop curl sddm ];
  };

  # Display protocol (Xwayland and login session: SDDM)
  services.xserver = {
    enable = true;
    layout = "us";
    windowManager.hypr.enable = true;
  };

  services.pipewire = {
    audio.enable = true;
  };

  services.displayManager = {
    sddm.enable = true;
    sddm.wayland.enable = true;
  };

  programs = {
    kitty.enable = true;
    hyprland.enable = true;
    hyprland.xwayland.enable = true;
  }

  # Swapfile configuration
  swapDevices = [
    { device = "/swapfile"; size = 4096; }  # Swap file size (in MB)
  ];

  # Boot loader configuration (GRUB)
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    useOSProber = true;
    device = "/dev/nvme0n1p1";  # Update as per your disk
  };

  # AMD graphics drivers
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
  };

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # Sudo access for wheel group
  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;  # Optional: passwordless sudo
  };

  # Miscellaneous settings
  environment.systemPackages = with pkgs; [ vim firefox curl git discord hyprland vesktop spotify kitty ];
}
