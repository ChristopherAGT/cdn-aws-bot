#!/bin/bash

clear

RED='\e[1;91m'
GREEN='\e[1;92m'
YELLOW='\e[1;93m'
BLUE='\e[1;94m'
CYAN='\e[1;96m'
WHITE='\e[1;97m'
RESET='\e[0m'

REPO="https://github.com/ChristopherAGT/cdn-aws-bot.git"
FOLDER="cdn-aws-bot"

divider(){
echo -e "${BLUE}════════════════════════════════════════════════════${RESET}"
}

error_exit(){
echo -e "${RED}❌ $1${RESET}"
exit 1
}

success(){
echo -e "${GREEN}✔ $1${RESET}"
}

info(){
echo -e "${CYAN}➜ $1${RESET}"
}

spinner() {
    local pid=$!
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %10 ))
        printf "\r${CYAN}[%c]${RESET} " "${spin:$i:1}"
        sleep .15
    done
    printf "\r"
}

progress(){
echo -ne "${GREEN}[#####               ] 25%\r"
sleep 0.2
echo -ne "${GREEN}[##########          ] 50%\r"
sleep 0.2
echo -ne "${GREEN}[###############     ] 75%\r"
sleep 0.2
echo -ne "${GREEN}[####################] 100%${RESET}\n"
}

wait_for_apt(){
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1
do
echo -e "${YELLOW}Esperando desbloqueo de apt...${RESET}"
sleep 3
done
}

check_python(){
command -v python3 >/dev/null || error_exit "Python3 no está instalado"
}

check_pip(){
python3 -m pip --version >/dev/null || error_exit "pip no funciona"
}

check_github(){
curl -s https://github.com >/dev/null || error_exit "GitHub no responde"
}

validate_token(){
if [[ ! "$TELEGRAM_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
error_exit "TOKEN inválido"
fi
}

save_token(){
echo "export TELEGRAM_TOKEN=\"$TELEGRAM_TOKEN\"" >> ~/.bashrc
}

divider
echo -e "${WHITE}🚀 Instalador Bot AWS CloudFront${RESET}"
divider

if [[ $EUID -ne 0 ]]; then
error_exit "Ejecuta el script como ROOT"
fi

info "Verificando conexión con GitHub..."
(check_github) &
spinner
success "GitHub accesible"

divider

info "Esperando disponibilidad de apt..."
wait_for_apt

info "Actualizando repositorios..."
(apt update -y >/dev/null 2>&1) &
spinner
progress
success "Repositorios actualizados"

divider

info "Instalando dependencias..."
(apt install python3 python3-pip git curl -y >/dev/null 2>&1) &
spinner
progress
success "Dependencias instaladas"

divider

info "Verificando Python..."
check_python
success "Python instalado correctamente"

info "Verificando pip..."
check_pip
success "pip funcionando correctamente"

divider

if [ -d "$FOLDER" ]; then
info "Repositorio ya existe"
else
info "Clonando repositorio..."
(git clone $REPO >/dev/null 2>&1) &
spinner
progress
success "Repositorio clonado"
fi

cd $FOLDER || error_exit "No se pudo acceder al directorio"

success "Ubicación actual: $(pwd)"

divider

echo -e "${YELLOW}🔑 Ingresa el TOKEN de tu bot de Telegram${RESET}"
echo -e "${CYAN}(puedes obtenerlo desde @BotFather en Telegram)${RESET}"

read -p "TOKEN: " TELEGRAM_TOKEN

validate_token
export TELEGRAM_TOKEN="$TELEGRAM_TOKEN"
save_token

success "TOKEN guardado correctamente"

divider

info "Actualizando pip..."
(pip3 install --upgrade pip --root-user-action=ignore >/dev/null 2>&1) &
spinner
progress
success "pip actualizado"

divider

info "Instalando dependencias Python..."
(pip3 install -r requirements.txt --root-user-action=ignore >/dev/null 2>&1) &
spinner
progress
success "Dependencias instaladas"

divider

if [ ! -f "bot.py" ]; then
error_exit "No se encontró bot.py"
fi

success "Archivo bot.py detectado"

divider

info "Iniciando bot en segundo plano..."

nohup python3 bot.py > bot.log 2>&1 &

sleep 2

PID=$(pgrep -f bot.py)

if [ -n "$PID" ]; then
success "Bot iniciado correctamente (PID $PID)"
else
error_exit "El bot no se pudo iniciar"
fi

divider

echo -e "${GREEN}"
echo "╔════════════════════════════════════════════╗"
echo "║         INSTALACIÓN COMPLETADA             ║"
echo "║   El bot se iniciará automáticamente       ║"
echo "╚════════════════════════════════════════════╝"
echo -e "${RESET}"

divider

echo -e "${CYAN}Comandos útiles:${RESET}"

echo -e "${WHITE}Ver logs:${RESET} tail -f bot.log"
echo -e "${WHITE}Ver proceso:${RESET} ps aux | grep bot.py"
echo -e "${WHITE}Detener bot:${RESET} kill $PID"

divider
