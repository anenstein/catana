#!/usr/bin/env bash
# catana: CLI-only Infrastructure Red Team Bootstrapper for Kali Linux
# ----------------------------------------------------------
# Dependencies: none beyond standard utilities.
# Provides a simple text menu with ASCII header and progress bars.

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
  sudo ln -sf ~/catana/catana.sh /usr/local/bin/catana
fi

# Utility: run a command with two-stage progress bar via dialog
run_with_progress() {
  local desc="$1"; shift
  (
    echo "20"; echo "# $desc"
    "$@" &> /dev/null
    echo "100"; echo "# Done"
  ) | dialog --title "Catana Installer" --gauge "" 10 70 0
}

# VENV, rockyou, PEASS suite
VENV_DIR="$HOME/.catana_venv"
ensure_venv() {
  run_with_progress "Installing Python3 and venv" apt update && apt install -y python3 python3-venv
  if [ ! -d "$VENV_DIR" ]; then
    run_with_progress "Creating Python virtualenv" python3 -m venv "$VENV_DIR"
    run_with_progress "Upgrading pip in venv" bash -c "source '$VENV_DIR/bin/activate' && pip install --upgrade pip"
  else
    echo "Virtualenv already exists, skipping."
  fi
}
ensure_rockyou() {
  local LISTDIR="/usr/share/wordlists"
  if [ -f "$LISTDIR/rockyou.txt.gz" ] && [ ! -f "$LISTDIR/rockyou.txt" ]; then
    run_with_progress "Unzipping rockyou wordlist" gunzip -k "$LISTDIR/rockyou.txt.gz"
  else
    echo "rockyou wordlist already available."
  fi
}
install_peass() {
  if [ ! -d "/opt/PEASS-ng" ]; then
    run_with_progress "Cloning PEASS-ng suite" git clone https://github.com/carlospolop/PEASS-ng.git /opt/PEASS-ng
  else
    echo "PEASS-ng suite already present."
  fi
}

# Fix/install functions
fix_missing_tools() {
  run_with_progress "Updating apt" apt update
  run_with_progress "Upgrading packages" apt upgrade -y
  run_with_progress "Installing essentials" apt install -y gedit nmap build-essential golang
  fix_golang_env; ensure_venv; ensure_rockyou; install_peass
}
fix_samba() {
  run_with_progress "Configuring Samba protocols" bash -c \
    "grep -q 'client min protocol' /etc/samba/smb.conf || echo -e '\tclient min protocol = SMB2\n\tclient max protocol = SMB3' >> /etc/samba/smb.conf"
}
fix_golang_env() {
  run_with_progress "Installing Golang" apt install -y golang
  if ! grep -q "export GOPATH" ~/.bashrc; then
    echo "export GOPATH=\$HOME/go" >> ~/.bashrc
    echo "GOPATH added to ~/.bashrc"
  else
    echo "GOPATH already configured."
  fi
}
install_impacket() {
  if python3 - << 'PYCODE' &> /dev/null
import impacket
PYCODE
  then
    echo "Impacket found system-wide."
  else
    ensure_venv
    run_with_progress "Installing Impacket in venv" bash -c \
      "source '$VENV_DIR/bin/activate' && pip install --upgrade impacket"
  fi
}
enable_root_login() {
  run_with_progress "Enabling SSH root login" bash -c \
    "sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && systemctl restart sshd"
}
fix_docker_compose() {
  run_with_progress "Installing Docker and Compose" apt install -y docker.io docker-compose
}
run_upgrade_tools() {
  run_with_progress "Full upgrade and cleanup" apt full-upgrade -y && apt autoremove -y
}
fix_grub_mitigation() {
  run_with_progress "Disabling grub mitigations" grubby --update-kernel=ALL --remove-args=mitigations=off || true
}
fix_nmap_scripts() {
  run_with_progress "Updating Nmap scripts DB" nmap --script-updatedb
}

# Extra tools
install_proxychains()   { run_with_progress "Installing Proxychains" apt install -y proxychains4; }
install_filezilla()     { run_with_progress "Installing FileZilla" apt install -y filezilla; }
install_rlwrap()        { run_with_progress "Installing rlwrap" apt install -y rlwrap; }
install_nuclei()        { run_with_progress "Installing Nuclei" bash -c "go install -v github.com/projectdiscovery/nuclei/v2/cmd/nuclei@latest"; }
install_subfinder()     { run_with_progress "Installing Subfinder" bash -c "go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"; }
install_feroxbuster()   { run_with_progress "Installing Feroxbuster" apt install -y feroxbuster; }
install_ncat()          { run_with_progress "Installing Ncat" apt install -y ncat; }
install_remmina()       { run_with_progress "Installing Remmina" apt install -y remmina; }
install_xfreerdp()      { run_with_progress "Installing FreeRDP" apt install -y freerdp2-x11; }
install_bloodhound() {
  run_with_progress "Installing Docker for BloodHound" apt install -y docker.io
  run_with_progress "Pulling BloodHound image" docker pull bloodhound
  run_with_progress "Launching BloodHound container" docker run -d --name bloodhound -p 7474:7474 -p 7687:7687 bloodhound
}
install_enum4linux()    { run_with_progress "Installing Enum4linux" apt install -y enum4linux; }
install_linpeas()       { install_peass; run_with_progress "Linking LinPEAS" ln -sf /opt/PEASS-ng/linpeas/linpeas.sh /usr/local/bin/linpeas; }
install_winpeas()       { install_peass; run_with_progress "Linking WinPEAS" ln -sf /opt/PEASS-ng/winPEAS/bin/winPEASexe.exe /usr/local/bin/winpeas; }

# Main menu loop with ASCII header
while true; do
  clear
  cat << 'MENU'
           _                    
          | |                   
  ___ __ _| |_ __ _ _ __   __ _ 
 / __/ _` | __/ _` | '_ \ / _` |
| (_| (_| | || (_| | | | | (_| |
 \___\__,_|\__\__,_|_| |_|\__,_|
                                
--------------------
1) Fix missing tools
2) Fix Samba config
3) Fix Golang env
4) Fix Grub mitigations
5) Install Impacket
6) Enable Root Login
7) Fix Docker/Compose
8) Fix Nmap scripts
9) Upgrade System
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
M) Install Enum4linux
N) Install LinPEAS
O) Install WinPEAS
K) Install ALL
X) Quit
MENU
  read -p $'Enter choice: ' choice
  case "$choice" in
    1) fix_missing_tools ;; 2) fix_samba ;; 3) fix_golang_env ;; 4) fix_grub_mitigation ;;
    5) install_impacket ;; 6) enable_root_login ;; 7) fix_docker_compose ;; 8) fix_nmap_scripts ;;
    9) run_upgrade_tools ;;
    [Aa]) install_proxychains ;; [Bb]) install_filezilla ;; [Cc]) install_rlwrap ;;
    [Dd]) install_nuclei ;; [Ee]) install_subfinder ;; [Ff]) install_feroxbuster ;;
    [Gg]) install_ncat ;; [Hh]) install_remmina ;; [Ii]) install_xfreerdp ;;
    [Jj]) install_bloodhound ;; [Mm]) install_enum4linux ;; [Nn]) install_linpeas ;;
    [Oo]) install_winpeas ;; [Kk])
      for func in fix_missing_tools fix_samba fix_golang_env install_impacket enable_root_login fix_docker_compose fix_nmap_scripts run_upgrade_tools install_proxychains install_filezilla install_rlwrap install_nuclei install_subfinder install_feroxbuster install_ncat install_remmina install_xfreerdp install_bloodhound install_enum4linux install_linpeas install_winpeas; do
        "$func"
      done
      ;;
    [Xx]) echo "Goodbye!"; exit 0 ;;
    *) echo "Invalid choice."; sleep 1 ;;
  esac
done
