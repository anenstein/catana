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
  echo -e "
${BLUE}==> $desc${NC}"
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
    echo -e "
${YELLOW}==> Skipping $desc (already installed)${NC}"
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
  read -rp $'\n'"System upgrade complete. Reboot now? [y/N]:" reboot_choice
  if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}Rebooting...${NC}"
    reboot
  fi
}
# Detect and handle service/library restarts
handle_restarts() {
  if ! command -v needrestart &> /dev/null; then
    echo -e "
${BLUE}==> Installing needrestart to manage restarts${NC}"
    apt install -y needrestart
  fi

  echo "\$nrconf{restart} = 'a';" > /etc/needrestart/conf.d/catana.conf
  echo "\$nrconf{restart_notify} = 0;" >> /etc/needrestart/conf.d/catana.conf

  echo -e "
${BLUE}==> Checking for services or libraries to restart${NC}"
  needrestart -q -r a
  if [ $? -ne 0 ]; then
    echo -e "
${RED}==> Some updates require a full reboot. Please reboot when convenient.${NC}" >&2
  else
    echo -e "
${GREEN}==> All services have been restarted successfully.${NC}"
  fi
}

# 3) Configuring and installing prerequisites and basic tools
install_base_tools() {
  echo -e "
${BLUE}==> Configuring and installing prerequisites & basic tools${NC}"
  check_and_install gedit Gedit apt install -y gedit
  check_and_install nmap Nmap apt install -y nmap
  check_and_install gcc build-essential apt install -y build-essential
  check_and_install jq JQ apt install -y jq

  fix_golang_env
  ensure_venv
  ensure_rockyou
  install_peass
}

# VENV, rockyou, PEASS suite
VENV_DIR="$HOME/.catana_venv"
ensure_venv() {
  echo -e "
${BLUE}==> Setting up Python venv${NC}"
  check_and_install python3 Python3 apt install -y python3
  check_and_install python3 python3-venv apt install -y python3-venv
  if [ ! -d "$VENV_DIR" ]; then
    run "Creating Python virtualenv" python3 -m venv "$VENV_DIR"
    run "Upgrading pip in venv" bash -c "source '$VENV_DIR/bin/activate' && pip install --upgrade pip"
  else
    echo -e "
${YELLOW}==> Virtualenv already exists, skipping.${NC}"
  fi
}
ensure_rockyou() {
  echo -e "
${BLUE}==> Ensuring rockyou wordlist${NC}"
  local LISTDIR="/usr/share/wordlists"
  if [ -f "$LISTDIR/rockyou.txt.gz" ] && [ ! -f "$LISTDIR/rockyou.txt" ]; then
    run "Unzipping rockyou wordlist" gunzip -k "$LISTDIR/rockyou.txt.gz"
  else
    echo -e "
${YELLOW}==> rockyou wordlist already available.${NC}"
  fi
}
install_peass() {
  echo -e "
${BLUE}==> Installing PEASS-ng suite${NC}"
  if [ ! -d "/opt/PEASS-ng" ]; then
    run "Cloning PEASS-ng suite" git clone https://github.com/carlospolop/PEASS-ng.git /opt/PEASS-ng
  else
    echo -e "
${YELLOW}==> PEASS-ng suite already present.${NC}"
  fi
}

# 4) Fix Samba config
fix_samba() {
  echo -e "
${BLUE}==> Fixing Samba configuration${NC}"
  run "Configuring Samba protocols" bash -c \
    "grep -q 'client min protocol' /etc/samba/smb.conf || echo -e '\tclient min protocol = SMB2\n\tclient max protocol = SMB3' >> /etc/samba/smb.conf"
}

# 5) Fix Golang env
fix_golang_env() {
  echo -e "
${BLUE}==> Ensuring Golang environment${NC}"

  local did_install=0

  if ! command -v go &>/dev/null; then
    check_and_install go Golang apt install -y golang
    [[ $? -eq 0 ]] && did_install=1
  else
    echo -e "${GREEN}==> Golang is already installed.${NC}"
  fi

  if ! grep -q "export GOPATH" ~/.bashrc; then
    echo "export GOPATH=\$HOME/go" >> ~/.bashrc
    echo -e "
${GREEN}==> GOPATH added to ~/.bashrc${NC}"
  else
    echo -e "
${YELLOW}==> GOPATH already configured.${NC}"
  fi

  if [[ $did_install -eq 1 ]]; then
    handle_restarts
  fi
}

# 6) Install Impacket
install_impacket() {
  local did_install=0
  if python3 - << 'PYCODE' &> /dev/null; then
import impacket
PYCODE
    echo -e "
${GREEN}==> Impacket found system-wide.${NC}"
  else
    ensure_venv
    run "Installing Impacket in venv" bash -c \
      "source '$VENV_DIR/bin/activate' && pip install --upgrade impacket"
    did_install=1
  fi
  if [[ $did_install -eq 1 ]]; then
    handle_restarts
  fi
}

# 7) Fix Docker/Compose
fix_docker_compose() {
  local did_install=0
  if ! command -v docker &>/dev/null; then
    check_and_install docker Docker apt install -y docker.io
    [[ $? -eq 0 ]] && did_install=1
  else
    echo -e "${GREEN}==> Docker is already installed.${NC}"
  fi
  if ! command -v docker-compose &>/dev/null; then
    check_and_install docker-compose Docker-Compose apt install -y docker-compose
    [[ $? -eq 0 ]] && did_install=1
  else
    echo -e "${GREEN}==> Docker Compose is already installed.${NC}"
  fi
  if [[ $did_install -eq 1 ]]; then
    handle_restarts
  fi
}

# 8) Update Nmap scripts
fix_nmap_scripts() {
  echo -e "
${BLUE}==> Updating Nmap scripts DB${NC}"
  run "Updating Nmap scripts DB" nmap --script-updatedb
}

# Extra tools (check_and_install)
install_proxychains()   { check_and_install proxychains4 Proxychains apt install -y proxychains4; }
install_filezilla() {
  local did_install=0
  if ! command -v filezilla &>/dev/null; then
    check_and_install filezilla FileZilla apt install -y filezilla
    [[ $? -eq 0 ]] && did_install=1
  else
    echo -e "${GREEN}==> FileZilla is already installed.${NC}"
  fi
  if [[ $did_install -eq 1 ]]; then
    handle_restarts
  fi
}
install_rlwrap()        { check_and_install rlwrap rlwrap apt install -y rlwrap; }
install_nuclei()        { check_and_install nuclei Nuclei apt install -y nuclei; }
install_ncat()          { check_and_install ncat Ncat apt install -y ncat; }
install_remmina() {
  local did_install=0
  if ! command -v remmina &>/dev/null; then
    check_and_install remmina Remmina apt install -y remmina
    [[ $? -eq 0 ]] && did_install=1
  else
    echo -e "${GREEN}==> Remmina is already installed.${NC}"
  fi
  if [[ $did_install -eq 1 ]]; then
    handle_restarts
  fi
}
install_bloodhound() {
  echo -e "
${BLUE}==> Launching BloodHound in a new tmux session${NC}"
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

# -- New additions -- #

# Ensure Node.js and npm
ensure_nodejs() {
  echo -e "
${BLUE}==> Ensuring Node.js and npm${NC}"
  check_and_install nodejs Node.js apt install -y nodejs npm
}

# Install Recon tools (requires Go)
install_recon_tools() {
  echo -e "
${BLUE}==> Installing Recon tools${NC}"
  # GitHub Subdomains
  check_and_install github-subdomains GitHub-Subdomains bash -lc "go install github.com/gwen001/github-subdomains@latest"
  # Subfinder
  check_and_install subfinder Subfinder bash -lc "apt install -y subfinder"
  # Assetfinder
  check_and_install assetfinder Assetfinder bash -lc "go install github.com/tomnomnom/assetfinder@latest"
  # Sublist3r (Python)
  ensure_venv
  check_and_install sublist3r Sublist3r bash -lc "source '$VENV_DIR/bin/activate' && pip install sublist3r"
  # DNSx
  check_and_install dnsx DNSx bash -lc "go install -v github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
  # HTTPX
  check_and_install httpx HTTPX bash -lc "go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest"

  check_and_install feroxbuster Feroxbuster bash -lc "apt install -y feroxbuster"
}

# Install Frontend SAST tools (Node.js)
install_frontend_sast() {
  echo -e "
${BLUE}==> Installing Frontend SAST tools${NC}"
  ensure_nodejs
  run "Installing js-beautify" npm install -g js-beautify
  run "Installing sourcemapper" go install github.com/denandz/sourcemapper@latest
}

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

  # Organized multi-column menu
  echo -e "${YELLOW}              MENU${NC}"
  echo -e "${GREEN} SYSTEM${NC}"
  printf "  %-3s %-28s  %-3s %-28s\n" "1)" "Update package list" "2)" "Upgrade installed packages"

  echo -e "${GREEN} RED-TEAM CORE${NC}"
  printf "  %-3s %-28s  %-3s %-28s\n" "3)" "Install base tools & env" "4)" "Fix Samba config"
  printf "  %-3s %-28s  %-3s %-28s\n" "5)" "Fix Golang env"            "6)" "Install Impacket"
  printf "  %-3s %-28s  %-3s %-28s\n" "7)" "Install Docker/Compose"      "8)" "Update Nmap scripts"

  echo -e "${GREEN} TOOLS${NC}"
  printf "  %-3s %-15s %-3s %-15s %-3s %-15s\n" \
    "A)" "Proxychains4"  "B)" "FileZilla"  "C)" "rlwrap"
  printf "  %-3s %-15s %-3s %-15s %-3s %-15s\n" \
    "D)" "Nuclei"  "E)" "Ncat"  "F)" "Remmina"  
  printf "  %-3s %-15s %-3s %-15s %-3s %-15s\n" \
    "G)" "BloodHound"  "H)" "Enum4linux" "I)" "Recon tools"
  printf "  %-3s %-15s %-3s %-15s %-3s %-15s\n" \
    "J)" "Frontend SAST"

  echo ""
  echo -e "${YELLOW}  Q) Quit${NC}"

  # Prompt
  read -rp "Enter choice: " choice
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
    [Ee]) install_ncat ;;
    [Ff]) install_remmina ;;
    [Gg]) install_bloodhound ;;
    [Hh]) install_enum4linux ;;
    [Ii]) install_recon_tools ;;
    [Jj]) install_frontend_sast ;;
    [Qq]) echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
    *) echo -e "${RED}Invalid choice.${NC}"; sleep 1 ;;
  esac
  # Pause so user can read output before menu refresh
  echo " "
  read -rp "Press Enter to return to menu..." dummy
done
