#!/usr/bin/env bash
# catana: Infrastructure Red Team Bootstrapper for Kali Linux
# ----------------------------------------------------------
# Dependencies: standard utilities.

# Color definitions
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Ensure we’re root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root or via sudo.${NC}"
  exit 1
fi

# Path to installed version
TARGET_BIN="/usr/local/bin/catana"

# If running as a script, ensure latest version is installed
if [[ "$(realpath "$0")" != "$TARGET_BIN" ]]; then
  if ! cmp -s "$0" "$TARGET_BIN"; then
    echo -e "${BLUE}Updating installed Catana to latest version...${NC}"
    cp "$0" "$TARGET_BIN"
    chmod +x "$TARGET_BIN"
  fi
  exec "$TARGET_BIN" "$@"
fi

# Utility: run a command with a description and show completion status
run() {
  local desc="$1"
  shift
  echo -e "\n${BLUE}==> $desc${NC}"
  "$@"
  local rc=$?
  if [ $rc -eq 0 ]; then
    echo -e "${GREEN}==> Completed: $desc${NC}"
  else
    echo -e "${RED}==> FAILED: $desc (exit code $rc)${NC}"
  fi
  return $rc
}

# Utility: install if missing, else skip
check_and_install() {
  local name="$1" desc="$2"
  shift 2
  if command -v "$name" &> /dev/null; then
    echo -e "\n${YELLOW}==> Skipping $desc (already installed)${NC}"
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
  read -rp $'\n'"${YELLOW}System upgrade complete. Reboot now? [y/N]: ${NC}" reboot_choice
  if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}Rebooting...${NC}"
    reboot
  fi
}
# Detect and handle service/library restarts
handle_restarts() {
  if ! command -v needrestart &> /dev/null; then
    echo -e "\n${BLUE}==> Installing needrestart to manage restarts${NC}"
    apt install -y needrestart
  fi

  echo "\$nrconf{restart} = 'a';" > /etc/needrestart/conf.d/catana.conf
  echo "\$nrconf{restart_notify} = 0;" >> /etc/needrestart/conf.d/catana.conf

  echo -e "\n${BLUE}==> Checking for services or libraries to restart${NC}"
  needrestart -q -r a
  if [ $? -ne 0 ]; then
    echo -e "\n${RED}==> Some updates require a full reboot. Please reboot when convenient.${NC}" >&2
  else
    echo -e "\n${GREEN}==> All services have been restarted successfully.${NC}"
  fi
}

# 3) Install base red-team tools & env
install_base_tools() {
  echo -e "\n${BLUE}==> Installing base red-team tools & environment${NC}"
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
  echo -e "\n${BLUE}==> Setting up Python venv${NC}"
  check_and_install python3 Python3 apt install -y python3
  check_and_install python3 python3-venv apt install -y python3-venv
  if [ ! -d "$VENV_DIR" ]; then
    run "Creating Python virtualenv" python3 -m venv "$VENV_DIR"
    run "Upgrading pip in venv" bash -c "source '$VENV_DIR/bin/activate' && pip install --upgrade pip"
  else
    echo -e "\n${YELLOW}==> Virtualenv already exists, skipping.${NC}"
  fi
}
ensure_rockyou() {
  echo -e "\n${BLUE}==> Ensuring rockyou wordlist${NC}"
  local LISTDIR="/usr/share/wordlists"
  if [ -f "$LISTDIR/rockyou.txt.gz" ] && [ ! -f "$LISTDIR/rockyou.txt" ]; then
    run "Unzipping rockyou wordlist" gunzip -k "$LISTDIR/rockyou.txt.gz"
  else
    echo -e "\n${YELLOW}==> rockyou wordlist already available.${NC}"
  fi
}
install_peass() {
  echo -e "\n${BLUE}==> Installing PEASS-ng suite${NC}"
  if [ ! -d "/opt/PEASS-ng" ]; then
    run "Cloning PEASS-ng suite" git clone https://github.com/carlospolop/PEASS-ng.git /opt/PEASS-ng
  else
    echo -e "\n${YELLOW}==> PEASS-ng suite already present.${NC}"
  fi
}

# 4) Fix Samba config
fix_samba() {
  echo -e "\n${BLUE}==> Fixing Samba configuration${NC}"
  run "Configuring Samba protocols" bash -c \
    "grep -q 'client min protocol' /etc/samba/smb.conf || echo -e '\tclient min protocol = SMB2\n\tclient max protocol = SMB3' >> /etc/samba/smb.conf"
}

# 5) Fix Golang env
fix_golang_env() {
  echo -e "\n${BLUE}==> Fixing Golang environment${NC}"
  check_and_install go Golang apt install -y golang
  if ! grep -q "export GOPATH" ~/.bashrc; then
    echo "export GOPATH=\$HOME/go" >> ~/.bashrc
    echo -e "\n${GREEN}==> GOPATH added to ~/.bashrc${NC}"
  else
    echo -e "\n${YELLOW}==> GOPATH already configured.${NC}"
  fi
  handle_restarts
}

# 6) Install Impacket
install_impacket() {
  echo -e "\n${BLUE}==> Installing Impacket${NC}"
  if python3 - << 'PYCODE' &> /dev/null; then
import impacket
PYCODE
    echo -e "\n${GREEN}==> Impacket found system-wide.${NC}"
  else
    ensure_venv
    run "Installing Impacket in venv" bash -c \
      "source '$VENV_DIR/bin/activate' && pip install --upgrade impacket"
  fi
  handle_restarts
}

# 7) Fix Docker/Compose
fix_docker_compose() {
  echo -e "\n${BLUE}==> Ensuring Docker & Compose${NC}"
  check_and_install docker Docker apt install -y docker.io
  check_and_install docker-compose Docker-Compose apt install -y docker-compose
  handle_restarts
}

# 8) Update Nmap scripts
fix_nmap_scripts() {
  echo -e "\n${BLUE}==> Updating Nmap scripts DB${NC}"
  run "Updating Nmap scripts DB" nmap --script-updatedb
}

# Extra tools (check_and_install)
install_proxychains()   { check_and_install proxychains4 Proxychains apt install -y proxychains4; }
install_filezilla() {
  check_and_install filezilla FileZilla apt install -y filezilla
  handle_restarts
}
install_rlwrap()        { check_and_install rlwrap rlwrap apt install -y rlwrap; }
install_nuclei()        { check_and_install nuclei Nuclei apt install -y nuclei; }
install_subfinder()     { check_and_install subfinder Subfinder apt install -y subfinder; }
install_feroxbuster()   { check_and_install feroxbuster Feroxbuster apt install -y feroxbuster; }
install_ncat()          { check_and_install ncat Ncat apt install -y ncat; }
install_remmina() {
  check_and_install remmina Remmina apt install -y remmina
  handle_restarts
}
# Setup BloodHound
install_bloodhound() {
  echo -e "\n${BLUE}==> Launching BloodHound in a new tmux session${NC}"

  if ! command -v tmux &>/dev/null; then
    echo -e "${RED}ERROR: tmux is not installed. Please install it with: sudo apt install tmux${NC}"
    return 1
  fi

  if tmux has-session -t bloodhound 2>/dev/null; then
    echo -e "${YELLOW}==> Killing existing 'bloodhound' tmux session${NC}"
    tmux kill-session -t bloodhound
  fi

  tmux new-session -s bloodhound 'sudo docker compose up'
}

install_enum4linux()    { check_and_install enum4linux Enum4linux apt install -y enum4linux; }

# Main menu loop with ASCII header
while true; do
  clear
  # Header
  echo -e "${BLUE}"
  cat << 'ASCII'
           _                    
          | |                   
  ___ __ _| |_ __ _ _ __   __ _ 
 / __/ _` | __/ _` | '_ \ / _` |
| (_| (_| | || (_| | | | | (_| |
 \___\__,_|\__\__,_|_| |_|\__,_|
         @anenstein
                                
ASCII
  echo -e "${NC}"

  # Menu
  echo -e "${BLUE}"
  cat << 'MENU'
--------------------
1) Update package list
2) Upgrade installed packages
3) Install base red-team tools & env
4) Fix Samba config
5) Fix Golang env
6) Install Impacket
7) Install Docker/Compose
8) Update Nmap scripts
A) Install Proxychains
B) Install FileZilla
C) Install rlwrap
D) Install Nuclei
E) Install Subfinder
F) Install Feroxbuster
G) Install Ncat
H) Install Remmina
I) Setup BloodHound
J) Install Enum4linux
Q) Quit
MENU
  echo -e "${NC}"
  read -rp "${BLUE}Enter choice: ${NC}" choice
  case "$choice" in
    1) update_system ;;
    2) upgrade_system ;;
    3) install_base_tools ;;
    4) fix_samba ;;
    5) fix_golang_env ;;
    6) install_impacket ;;
    7) fix_docker_compose ;;
    8) fix_nmap_scripts ;;
    [Aa]) install_proxychains ;;
    [Bb]) install_filezilla ;;
    [Cc]) install_rlwrap ;;
    [Dd]) install_nuclei ;;
    [Ee]) install_subfinder ;;
    [Ff]) install_feroxbuster ;;
    [Gg]) install_ncat ;;
    [Hh]) install_remmina ;;
    [Ii]) install_bloodhound ;;
    [Jj]) install_enum4linux ;;
    [Qq]) echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
    *) echo -e "${RED}Invalid choice.${NC}"; sleep 1 ;;
  esac
  # Pause so user can read output before menu refresh
  read -rp "${YELLOW}Press Enter to return to menu...${NC}" dummy
done
