#!/usr/bin/env bash
# catana: Infrastructure Red Team Bootstrapper for Kali Linux
# ----------------------------------------------------------
# Dependencies: dialog. Installs itself into /usr/local/bin/catana,
# sets up an alias, then launches the interactive menu.

# Ensure we’re root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or via sudo."
  exit 1
fi

# Install 'dialog' if missing
if ! command -v dialog &> /dev/null; then
  echo "Installing 'dialog' dependency..."
  apt update && apt install -y dialog
fi

# Self-install into /usr/local/bin/catana
if [[ "$(basename "$0")" != "catana" ]]; then
  echo "Installing Catana to /usr/local/bin/catana..."
  cp "$0" /usr/local/bin/catana
  chmod +x /usr/local/bin/catana
  exec /usr/local/bin/catana "$@"
fi

# Auto-alias setup
SCRIPT_PATH="$(realpath "$0")"
BASHRC="$HOME/.bashrc"
if ! grep -q "alias catana=" "$BASHRC"; then
  echo "Setting up alias in $BASHRC..."
  echo "alias catana='bash $SCRIPT_PATH'" >> "$BASHRC"
  # shellcheck disable=SC1090
  source "$BASHRC"
fi

# ASCII HEADER
cat << 'EOF'
           _                    
          | |                   
  ___ __ _| |_ __ _ _ __   __ _ 
 / __/ _` | __/ _` | '_ \ / _` |
| (_| (_| | || (_| | | | | (_| |
 \___\__,_|\__\__,_|_| |_|\__,_|
                                
                                
EOF

# GLOBALS
VENV_DIR="$HOME/.catana_venv"
TOTAL_STEPS=0
CURRENT_STEP=0

# UTILITY FUNCTIONS
step_start() {
  (( CURRENT_STEP++ ))
  PERCENT=$(( CURRENT_STEP * 100 / TOTAL_STEPS ))
  echo "$PERCENT"
  echo "# $1"
}
run_with_progress() {
  { step_start "$1"; "${@:2}" &> /dev/null; } \
    | dialog --title "Catana Installer" --gauge "" 10 70 0
}
check_and_install() {
  local name="$1" desc="$2" cmd="$3"
  if ! command -v "$name" &> /dev/null; then
    run_with_progress "Installing $desc..." ${cmd}
  else
    run_with_progress "Skipping $desc (already installed)" true
  fi
}

# VENV, ROCKYOU & PEASS SETUP
ensure_venv() {
  check_and_install python3 "Python3" apt install -y python3
  check_and_install python3-venv "python3-venv" apt install -y python3-venv
  if [ ! -d "$VENV_DIR" ]; then
    run_with_progress "Creating Python virtualenv" bash -c "python3 -m venv '$VENV_DIR'"
    run_with_progress "Upgrading pip in venv" bash -c "source '$VENV_DIR/bin/activate' && pip install --upgrade pip"
  else
    run_with_progress "Virtual environment already exists" true
  fi
}
ensure_rockyou() {
  WORDLIST_DIR="/usr/share/wordlists"
  if [ -f "$WORDLIST_DIR/rockyou.txt.gz" ] && [ ! -f "$WORDLIST_DIR/rockyou.txt" ]; then
    run_with_progress "Unzipping rockyou wordlist" bash -c "gunzip -k '$WORDLIST_DIR/rockyou.txt.gz'"
  else
    run_with_progress "Rockyou wordlist already unzipped" true
  fi
}
install_peass_suite() {
  if [ ! -d "/opt/PEASS-ng" ]; then
    run_with_progress "Cloning PEASS-ng suite" bash -c \
      "git clone https://github.com/carlospolop/PEASS-ng.git /opt/PEASS-ng"
  else
    run_with_progress "PEASS-ng suite already present" true
  fi
}

# FIX/INSTALL FUNCTIONS
fix_missing_tools() {
  run_with_progress "apt update & upgrade" bash -c "apt update && apt upgrade -y"
  check_and_install gedit "Gedit editor" apt install -y gedit
  check_and_install nmap "Nmap" apt install -y nmap
  check_and_install build-essential "build-essential" apt install -y build-essential
  fix_golang_env
  ensure_venv
  ensure_rockyou
  install_peass_suite
}
fix_samba() {
  run_with_progress "Configuring Samba protocols" bash -c \
    "sed -i '/client min protocol/!c\tclient min protocol = SMB2\nclient max protocol = SMB3' /etc/samba/smb.conf || true"
}
fix_golang_env() {
  check_and_install go "Golang runtime" apt install -y golang
  if ! grep -q "export GOPATH" ~/.bashrc; then
    run_with_progress "Configuring GOPATH in ~/.bashrc" bash -c \
      "echo 'export GOPATH=\$HOME/go' >> ~/.bashrc"
  else
    run_with_progress "GOPATH already set" true
  fi
}
install_impacket() {
  if python3 - << 'PYTEST' &> /dev/null
import impacket
PYTEST
  then
    run_with_progress "Impacket already installed system-wide" true
  else
    ensure_venv
    run_with_progress "Installing Impacket in venv" bash -c \
      "source '$VENV_DIR/bin/activate' && pip install --upgrade impacket"
  fi
}
enable_root_login() {
  run_with_progress "Enabling root login" bash -c \
    "sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && systemctl restart sshd"
}
fix_docker_compose() {
  check_and_install docker-compose "Docker Compose" apt install -y docker-compose
  check_and_install docker "Docker.io" apt install -y docker.io
}
run_upgrade_tools() {
  run_with_progress "Running apt full-upgrade and cleaning" bash -c \
    "apt full-upgrade -y && apt autoremove -y"
}
fix_grub_mitigation() {
  run_with_progress "Disabling grub mitigations" bash -c \
    "grubby --update-kernel=ALL --remove-args=mitigations=off || true"
}
fix_nmap_scripts() {
  run_with_progress "Updating Nmap scripts" bash -c "nmap --script-updatedb"
}

# EXTRA TOOLS
install_proxychains()   { check_and_install proxychains4 "Proxychains" apt install -y proxychains4; }
install_filezilla()     { check_and_install filezilla   "FileZilla"   apt install -y filezilla; }
install_rlwrap()        { check_and_install rlwrap      "rlwrap"      apt install -y rlwrap; }
install_nuclei()        { check_and_install nuclei      "Nuclei"      bash -c "go install -v github.com/projectdiscovery/nuclei/v2/cmd/nuclei@latest"; }
install_subfinder()     { check_and_install subfinder   "Subfinder"   bash -c "go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"; }
install_feroxbuster()   { check_and_install feroxbuster "Feroxbuster" apt install -y feroxbuster; }
install_ncat()          { check_and_install ncat        "Ncat"        apt install -y ncat; }
install_remmina()       { check_and_install remmina     "Remmina"     apt install -y remmina; }
install_xfreerdp()      { check_and_install xfreerdp    "FreeRDP"     apt install -y freerdp2-x11; }
install_bloodhound() {
  check_and_install docker "Docker.io" apt install -y docker.io
  run_with_progress "Pulling BloodHound Docker image" docker pull bloodhound
  run_with_progress "Launching BloodHound container" bash -c \
    "docker run -d --name bloodhound -p 7474:7474 -p 7687:7687 bloodhound"
}
install_enum4linux()    { check_and_install enum4linux "Enum4linux"  apt install -y enum4linux; }
install_linpeas()       {
  install_peass_suite
  run_with_progress "Linking LinPEAS script" bash -c \
    "ln -sf /opt/PEASS-ng/linpeas/linpeas.sh /usr/local/bin/linpeas"
}
install_winpeas()       {
  install_peass_suite
  run_with_progress "Linking WinPEAS executable" bash -c \
    "ln -sf /opt/PEASS-ng/winPEAS/bin/winPEASexe.exe /usr/local/bin/winpeas"
}

# MENU & DISPATCH
show_menu() {
  dialog --clear --title "Catana Main Menu" \
    --menu "Choose an option:" 26 70 16 \
    1 "Fix Missing Tools" \
    2 "Fix Samba config" \
    3 "Fix Golang env" \
    4 "Fix Grub mitigations" \
    5 "Install Impacket (venv)" \
    6 "Enable Root Login" \
    7 "Fix Docker/Compose" \
    8 "Fix Nmap scripts" \
    9 "Upgrade" \
    A "Install Proxychains" \
    B "Install Filezilla" \
    C "Install rlwrap" \
    D "Install Nuclei" \
    E "Install Subfinder" \
    F "Install Feroxbuster" \
    G "Install Ncat" \
    H "Install Remmina" \
    I "Install xfreerdp" \
    J "Setup BloodHound" \
    M "Install Enum4linux" \
    N "Install LinPEAS" \
    O "Install WinPEAS" \
    K "Install ALL selected" \
    X "Quit" 2> /tmp/catana.choice

  CHOICE=$(< /tmp/catana.choice)
}

install_all() {
  ALL_FUNCS=(
    fix_missing_tools fix_samba fix_golang_env install_impacket
    enable_root_login fix_docker_compose fix_nmap_scripts
    run_upgrade_tools install_proxychains install_filezilla
    install_rlwrap install_nuclei install_subfinder
    install_feroxbuster install_ncat install_remmina
    install_xfreerdp install_bloodhound install_enum4linux
    install_linpeas install_winpeas
  )
  TOTAL_STEPS=${#ALL_FUNCS[@]}
  CURRENT_STEP=0
  for func in "${ALL_FUNCS[@]}"; do
    "$func"
  done
  dialog --msgbox "All selected tools have been processed." 8 40
}

# MAIN LOOP
while true; do
  show_menu
  case "$CHOICE" in
    1) fix_missing_tools ;;
    2) fix_samba ;;
    3) fix_golang_env ;;
    4) fix_grub_mitigation ;;
    5) install_impacket ;;
    6) enable_root_login ;;
    7) fix_docker_compose ;;
    8) fix_nmap_scripts ;;
    9) run_upgrade_tools ;;
    A) install_proxychains ;;
    B) install_filezilla ;;
    C) install_rlwrap ;;
    D) install_nuclei ;;
    E) install_subfinder ;;
    F) install_feroxbuster ;;
    G) install_ncat ;;
    H) install_remmina ;;
    I) install_xfreerdp ;;
    J) install_bloodhound ;;
    M) install_enum4linux ;;
    N) install_linpeas ;;
    O) install_winpeas ;;
    K) install_all ;;
    X) clear; exit 0 ;;
    *) dialog --msgbox "Invalid option." 6 30 ;;
  esac
done
