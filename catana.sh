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

# Utility: run a command with a description
run() {
  echo -e "\n==> $1"
  shift
  "$@"
}

# Utility: install if missing, else skip
check_and_install() {
  local name="$1" desc="$2"
  shift 2
  if command -v "$name" &> /dev/null; then
    echo -e "\n==> Skipping $desc (already installed)"
  else
    run "Installing $desc" "$@"
  fi
}

# Basic system maintenance: update & upgrade
update_system() {
  run "Updating package list" apt update
  run "Upgrading installed packages" apt upgrade -y
}

# Install base red-team essentials
install_base_tools() {
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
  run "Installing Python3 & venv package" apt install -y python3 python3-venv
  if [ ! -d "$VENV_DIR" ]; then
    run "Creating Python virtualenv" python3 -m venv "$VENV_DIR"
    run "Upgrading pip in venv" bash -c "source '$VENV_DIR/bin/activate' && pip install --upgrade pip"
  else
    echo -e "\n==> Virtualenv already exists, skipping."
  fi
}
ensure_rockyou() {
  local LISTDIR="/usr/share/wordlists"
  if [ -f "$LISTDIR/rockyou.txt.gz" ] && [ ! -f "$LISTDIR/rockyou.txt" ]; then
    run "Unzipping rockyou wordlist" gunzip -k "$LISTDIR/rockyou.txt.gz"
  else
    echo -e "\n==> rockyou wordlist already available."
  fi
}
install_peass() {
  if [ ! -d "/opt/PEASS-ng" ]; then
    run "Cloning PEASS-ng suite" git clone https://github.com/carlospolop/PEASS-ng.git /opt/PEASS-ng
  else
    echo -e "\n==> PEASS-ng suite already present."
  fi
}

# Other fixes/configurations
fix_samba() {
  run "Configuring Samba protocols" bash -c \
    "grep -q 'client min protocol' /etc/samba/smb.conf || echo -e '\tclient min protocol = SMB2\n\tclient max protocol = SMB3' >> /etc/samba/smb.conf"
}
fix_golang_env() {
  check_and_install go Golang apt install -y golang
  if ! grep -q "export GOPATH" ~/.bashrc; then
    echo "export GOPATH=\$HOME/go" >> ~/.bashrc
    echo -e "\n==> GOPATH added to ~/.bashrc"
  else
    echo -e "\n==> GOPATH already configured."
  fi
}
install_impacket() {
  if python3 - << 'PYCODE' &> /dev/null; then
import impacket
PYCODE
    echo -e "\n==> Impacket found system-wide."
  else
    ensure_venv
    run "Installing Impacket in venv" bash -c \
      "source '$VENV_DIR/bin/activate' && pip install --upgrade impacket"
  fi
}
enable_root_login() {
  run "Enabling SSH root login" bash -c \
    "sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && systemctl restart sshd"
}
fix_docker_compose() {
  check_and_install docker Docker apt install -y docker.io
  check_and_install docker-compose Docker-Compose apt install -y docker-compose
}
run_upgrade_tools() {
  run "Full upgrade and cleanup" bash -c \
    "apt full-upgrade -y && apt autoremove -y"
}
fix_grub_mitigation() {
  run "Disabling grub mitigations" grubby --update-kernel=ALL --remove-args=mitigations=off || true
}
fix_nmap_scripts() {
  run "Updating Nmap scripts DB" nmap --script-updatedb
}

# Extra tools with check_and_install
install_proxychains()   { check_and_install proxychains4 Proxychains apt install -y proxychains4; }
install_filezilla()     { check_and_install filezilla FileZilla apt install -y filezilla; }
install_rlwrap()        { check_and_install rlwrap rlwrap apt install -y rlwrap; }
install_nuclei()        { check_and_install nuclei Nuclei bash -c "go install -v github.com/projectdiscovery/nuclei/v2/cmd/nuclei@latest"; }
install_subfinder()     { check_and_install subfinder Subfinder bash -c "go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"; }
install_feroxbuster()   { check_and_install feroxbuster Feroxbuster apt install -y feroxbuster; }
install_ncat()          { check_and_install ncat Ncat apt install -y ncat; }
install_remmina()       { check_and_install remmina Remmina apt install -y remmina; }
install_xfreerdp()      { check_and_install xfreerdp FreeRDP apt install -y freerdp2-x11; }
install_bloodhound() {
  check_and_install docker Docker apt install -y docker.io
  run "Pulling BloodHound image" docker pull bloodhound
  run "Launching BloodHound container" docker run -d --name bloodhound -p 7474:7474 -p 7687:7687 bloodhound
}
install_enum4linux()    { check_and_install enum4linux Enum4linux apt install -y enum4linux; }
install_linpeas()       { install_peass; check_and_install linpeas LinPEAS ln -sf /opt/PEASS-ng/linpeas/linpeas.sh /usr/local/bin/linpeas; }
install_winpeas()       { install_peass; check_and_install winpeas WinPEAS ln -sf /opt/PEASS-ng/winPEAS/bin/winPEASexe.exe /usr/local/bin/winpeas; }

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
8) Fix Docker/Compose
9) Update Nmap scripts
A) Fix Grub mitigations
B) Install Proxychains
C) Install FileZilla
D) Install rlwrap
E) Install Nuclei
F) Install Subfinder
G) Install Feroxbuster
H) Install Ncat
I) Install Remmina
J) Install FreeRDP
K) Setup BloodHound
L) Install Enum4linux
M) Install LinPEAS
N) Install WinPEAS
Q) Quit
MENU
  read -rp "Enter choice: " choice
  case "$choice" in
    1) run "Updating package list" apt update ;; 2) run "Upgrading packages" apt upgrade -y ;; 3) install_base_tools ;; 4) fix_samba ;;
    5) fix_golang_env ;; 6) install_impacket ;; 7) enable_root_login ;; 8) fix_docker_compose ;;
    9) fix_nmap_scripts ;; [Aa]) fix_grub_mitigation ;; [Bb]) install_proxychains ;; [Cc]) install_filezilla ;;
    [Dd]) install_rlwrap ;; [Ee]) install_nuclei ;; [Ff]) install_subfinder ;; [Gg]) install_feroxbuster ;;
    [Hh]) install_ncat ;; [Ii]) install_remmina ;; [Jj]) install_xfreerdp ;; [Kk]) install_bloodhound ;;
    [Ll]) install_enum4linux ;; [Mm]) install_linpeas ;; [Nn]) install_winpeas ;; [Qq]) echo "Goodbye!"; exit 0 ;;
    *) echo "Invalid choice."; sleep 1 ;;
  esac
done
