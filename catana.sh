#!/usr/bin/env bash
# catana: Infrastructure Red Team Bootstrapper for Kali Linux
# ----------------------------------------------------------
# Dependencies: standard utilities.

# Ensure we’re root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or via sudo."
  exit 1
fi

# Self-install into /usr/local/bin/catana if needed
if [[ "$(basename "$0")" != "catana" ]]; then
  echo "Installing Catana to /usr/local/bin/catana..."
  cp "$0" /usr/local/bin/catana
  chmod +x /usr/local/bin/catana
  exec /usr/local/bin/catana "$@"
fi

# Utility: run a command with a description and show completion status
run() {
  local desc="$1"
  shift
  echo -e "
==> $desc"
  "$@"
  local rc=$?
  if [ $rc -eq 0 ]; then
    echo "==> Completed: $desc"
  else
    echo "==> FAILED: $desc (exit code $rc)"
  fi
  return $rc
}

# Utility: install if missing, else skip
check_and_install() {
  local name="$1" desc="$2"
  shift 2
  if command -v "$name" &> /dev/null; then
    echo -e "
==> Skipping $desc (already installed)"
  else
    run "Installing $desc" "$@"
  fi
}

# 1) Update package list
update_system() {
  run "Updating package list" apt update
}

# 2) Upgrade installed packages
upgrade_system() {
  run "Upgrading installed packages" apt upgrade -y
  handle_restarts
  read -rp $'\nSystem upgrade complete. Reboot now? [y/N]: ' reboot_choice
  if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
    echo "Rebooting..."
    reboot
  fi
}
# Detect and handle service/library restarts
handle_restarts() {
  if ! command -v needrestart &> /dev/null; then
    echo -e "\n==> Installing needrestart to manage restarts"
    apt install -y needrestart
  fi

  echo "\$nrconf{restart} = 'a';" > /etc/needrestart/conf.d/catana.conf
  echo "\$nrconf{restart_notify} = 0;" >> /etc/needrestart/conf.d/catana.conf

  echo -e "\n==> Checking for services or libraries to restart"
  needrestart -q -r a
  if [ $? -ne 0 ]; then
    echo -e "\n==> Some updates require a full reboot. Please reboot when convenient." >&2
  else
    echo -e "\n==> All services have been restarted successfully."
  fi
}

# 3) Install base red-team tools & env
install_base_tools() {
  echo -e "\n==> Installing base red-team tools & environment"
  check_and_install gedit Gedit apt install -y gedit
  check_and_install nmap Nmap apt install -y nmap
  check_and_install gcc build-essential apt install -y build-essential
  check_and_install go Golang apt install -y golang
  fix_golang_env
  ensure_venv
  ensure_rockyou
  install_peass
}

# VENV, rockyou, PEASS suite
VENV_DIR="$HOME/.catana_venv"
ensure_venv() {
  echo -e "\n==> Setting up Python venv"
  check_and_install python3 Python3 apt install -y python3
  check_and_install python3 python3-venv apt install -y python3-venv
  if [ ! -d "$VENV_DIR" ]; then
    run "Creating Python virtualenv" python3 -m venv "$VENV_DIR"
    run "Upgrading pip in venv" bash -c "source '$VENV_DIR/bin/activate' && pip install --upgrade pip"
  else
    echo -e "\n==> Virtualenv already exists, skipping."
  fi
}
ensure_rockyou() {
  echo -e "\n==> Ensuring rockyou wordlist"
  local LISTDIR="/usr/share/wordlists"
  if [ -f "$LISTDIR/rockyou.txt.gz" ] && [ ! -f "$LISTDIR/rockyou.txt" ]; then
    run "Unzipping rockyou wordlist" gunzip -k "$LISTDIR/rockyou.txt.gz"
  else
    echo -e "\n==> rockyou wordlist already available."
  fi
}
install_peass() {
  echo -e "\n==> Installing PEASS-ng suite"
  if [ ! -d "/opt/PEASS-ng" ]; then
    run "Cloning PEASS-ng suite" git clone https://github.com/carlospolop/PEASS-ng.git /opt/PEASS-ng
  else
    echo -e "\n==> PEASS-ng suite already present."
  fi
}

# 4) Fix Samba config
fix_samba() {
  echo -e "\n==> Fixing Samba configuration"
  run "Configuring Samba protocols" bash -c \
    "grep -q 'client min protocol' /etc/samba/smb.conf || echo -e '\tclient min protocol = SMB2\n\tclient max protocol = SMB3' >> /etc/samba/smb.conf"
}

# 5) Fix Golang env
fix_golang_env() {
  echo -e "\n==> Fixing Golang environment"
  check_and_install go Golang apt install -y golang
  if ! grep -q "export GOPATH" ~/.bashrc; then
    echo "export GOPATH=\$HOME/go" >> ~/.bashrc
    echo -e "\n==> GOPATH added to ~/.bashrc"
  else
    echo -e "\n==> GOPATH already configured."
  fi
  handle_restarts
}

# 6) Install Impacket
install_impacket() {
  echo -e "\n==> Installing Impacket"
  if python3 - << 'PYCODE' &> /dev/null; then
import impacket
PYCODE
    echo -e "\n==> Impacket found system-wide."
  else
    ensure_venv
    run "Installing Impacket in venv" bash -c \
      "source '$VENV_DIR/bin/activate' && pip install --upgrade impacket"
  fi
  handle_restarts
}

# 7) Fix Docker/Compose
fix_docker_compose() {
  echo -e "\n==> Ensuring Docker & Compose"
  check_and_install docker Docker apt install -y docker.io
  check_and_install docker-compose Docker-Compose apt install -y docker-compose
  handle_restarts
}

# 8) Update Nmap scripts
fix_nmap_scripts() {
  echo -e "\n==> Updating Nmap scripts DB"
  run "Updating Nmap scripts DB" nmap --script-updatedb
}

# Extra tools (check_and_install)
install_proxychains()   { check_and_install proxychains4 Proxychains apt install -y proxychains4; }
install_filezilla() {
  check_and_install filezilla FileZilla apt install -y filezilla
  handle_restarts
}
install_rlwrap()        { check_and_install rlwrap rlwrap apt install -y rlwrap; }
# Install Nuclei
install_nuclei()        { check_and_install nuclei Nuclei apt install -y nuclei; }
# Install Subfinder
install_subfinder()     { check_and_install subfinder Subfinder apt install -y subfinder; }
install_feroxbuster()   { check_and_install feroxbuster Feroxbuster apt install -y feroxbuster; }
install_ncat()          { check_and_install ncat Ncat apt install -y ncat; }
install_remmina() {
  check_and_install remmina Remmina apt install -y remmina
  handle_restarts
}
# Setup BloodHound
install_bloodhound() {
  echo -e "
==> Setting up BloodHound via Docker Compose"
  sudo docker compose up
    echo "BloodHound containers launched via docker-compose."
}

install_enum4linux()    { check_and_install enum4linux Enum4linux apt install -y enum4linux; }

# Main menu loop with ASCII header
while true; do
  clear
  cat << 'ASCII'
           _                    
          | |                   
  ___ __ _| |_ __ _ _ __   __ _ 
 / __/ _` | __/ _` | '_ \ / _` |
| (_| (_| | || (_| | | | | (_| |
 \___\__,_|\__\__,_|_| |_|\__,_|
                                
ASCII
  echo
  cat << 'MENU'
--------------------
1) Update package list
2) Upgrade installed packages
3) Install base red-team tools & env
4) Fix Samba config
5) Fix Golang env
6) Install Impacket
7) Enable Root Login
8) Install Docker/Compose
9) Update Nmap scripts
A) Install Proxychains
B) Install FileZilla
C) Install rlwrap
D) Install Nuclei
E) Install Subfinder
F) Install Feroxbuster
G) Install Ncat
H) Install Remmina
I) Install FreeRDP
J) Setup BloodHound
K) Install Enum4linux
Q) Quit
MENU
  read -rp "Enter choice: " choice
  case "$choice" in
    1) update_system ;;
    2) upgrade_system ;;
    3) install_base_tools ;;
    4) fix_samba ;;
    5) fix_golang_env ;;
    6) install_impacket ;;
    7) enable_root_login ;;
    8) fix_docker_compose ;;
    9) fix_nmap_scripts ;;
    [Aa]) install_proxychains ;;
    [Bb]) install_filezilla ;;
    [Cc]) install_rlwrap ;;
    [Dd]) install_nuclei ;;
    [Ee]) install_subfinder ;;
    [Ff]) install_feroxbuster ;;
    [Gg]) install_ncat ;;
    [Hh]) install_remmina ;;
    [Ii]) install_xfreerdp ;;
    [Jj]) install_bloodhound ;;
    [Kk]) install_enum4linux ;;
    [Qq]) echo "Goodbye!"; exit 0 ;;
    *) echo "Invalid choice."; sleep 1 ;;
  esac
  # Pause so user can read output before menu refresh
  read -rp "Press Enter to return to menu..." dummy
done
