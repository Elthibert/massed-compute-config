#!/bin/bash

# ====================================================================
# Script de démarrage ComfyUI pour Massed Compute
# Installe tout en arrière-plan et prépare la configuration finale.
# ====================================================================

# --- CONFIGURATION ---
# !!! MODIFIEZ CETTE LIGNE pour pointer vers votre propre fichier de config !!!
MODELS_CONFIG_URL="https://raw.githubusercontent.com/Elthibert/massed-compute-config/main/models_config.txt"
# ---------------------

# Redirige toute la sortie vers un fichier de log pour le débogage
LOG_FILE="$HOME/comfyui_install_log.txt"
exec > >(tee -a ${LOG_FILE}) 2>&1

echo "--- Démarrage de l'installation ComfyUI $(date) ---"

# On s'assure que les variables d'environnement pour l'interface graphique sont définies
export DISPLAY=:0
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

# --- FONCTIONS ---

function install_dependencies() {
    echo "📦 Installation des dépendances système..."
    # Met à jour et installe sans poser de questions
    sudo apt-get update -qq
    sudo apt-get install -y -qq \
        python3-pip python3-venv python3-dev \
        build-essential libgl1-mesa-glx libglib2.0-0 \
        libsm6 libxext6 librender1 libgomp1 \
        wget curl git ffmpeg \
        xterm zenity 2>/dev/null || true
}

function install_comfyui() {
    echo "📥 Téléchargement de ComfyUI..."
    [ ! -d "$HOME/ComfyUI" ] && git clone https://github.com/comfyanonymous/ComfyUI.git "$HOME/ComfyUI"
    
    cd "$HOME/ComfyUI"
    
    echo "🐍 Configuration Python et bibliothèques de performance..."
    python3 -m venv venv
    source venv/bin/activate
    
    pip install --upgrade pip setuptools wheel
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
    pip install -r requirements.txt
    pip install opencv-python transformers accelerate safetensors omegaconf einops torchsde kornia spandrel soundfile
    pip install xformers --index-url https://download.pytorch.org/whl/cu121
    pip install sageattention
    pip install triton
    pip install flash-attn --no-build-isolation
    pip install gguf
    
    echo "🔧 Installation des extensions de base (Manager, GGUF, VHS)..."
    cd custom_nodes
    [ ! -d "ComfyUI-Manager" ] && git clone https://github.com/ltdrdata/ComfyUI-Manager.git
    [ ! -d "ComfyUI-GGUF" ] && git clone https://github.com/city96/ComfyUI-GGUF.git
    [ ! -d "ComfyUI-VideoHelperSuite" ] && git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git
    cd ..
    
    # Créer les dossiers de modèles
    mkdir -p models/{checkpoints,vae,loras,embeddings,controlnet,clip,upscale_models,unet} input temp output
}

function download_models() {
    echo "📥 Téléchargement des modèles depuis la configuration..."
    wget -O "$HOME/ComfyUI/models_config.txt" "$MODELS_CONFIG_URL"
    
    MODELS_DIR="$HOME/ComfyUI/models"
    CONFIG_FILE="$HOME/ComfyUI/models_config.txt"
    
    while IFS='|' read -r TYPE URL FILENAME || [ -n "$line" ]; do
        [[ "$TYPE" =~ ^#.*$ ]] || [ -z "$TYPE" ] && continue
        case $TYPE in
            CHECKPOINT) DEST="$MODELS_DIR/checkpoints" ;; VAE) DEST="$MODELS_DIR/vae" ;; LORA) DEST="$MODELS_DIR/loras" ;;
            UNET) DEST="$MODELS_DIR/unet" ;; CLIP) DEST="$MODELS_DIR/clip" ;; *) DEST="$MODELS_DIR/other" ;;
        esac
        mkdir -p "$DEST"
        FILEPATH="$DEST/$FILENAME"
        if [ ! -f "$FILEPATH" ]; then
            echo "  -> Téléchargement de $FILENAME..."
            wget -q --show-progress -c "$URL" -O "$FILEPATH"
        fi
    done < "$CONFIG_FILE"
}

function create_final_setup_script() {
    echo "🏁 Création du script de configuration finale..."
    
    # Dossier pour les scripts de contrôle
    SCRIPTS_DIR="$HOME/.config/comfyui_scripts"
    mkdir -p "$SCRIPTS_DIR"
    DESKTOP_DIR="$HOME/Desktop"
    mkdir -p "$DESKTOP_DIR"

    # --- Script de configuration (Étape 2) ---
    cat > "$SCRIPTS_DIR/setup_stage2.sh" << 'SETUP_STAGE2'
#!/bin/bash
export DISPLAY=:0
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
SCRIPTS_DIR="$HOME/.config/comfyui_scripts"
DESKTOP_DIR="$HOME/Desktop"

zenity --question --text="Voulez-vous synchroniser le dossier de sortie de ComfyUI avec un dossier de votre PC ?" --width=400
if [ $? = 0 ]; then
    SYNC_PATH=$(zenity --file-selection --directory --title="Choisissez votre dossier de sortie (ex: dans thinclient_drives)")
    if [ -n "$SYNC_PATH" ]; then
        echo "🔄 Configuration de la synchronisation..."
        mkdir -p "$SYNC_PATH"
        OUTPUT_DIR="$HOME/ComfyUI/output"
        if [ -d "$OUTPUT_DIR" ] && [ ! -L "$OUTPUT_DIR" ]; then
            mv "$OUTPUT_DIR"/* "$SYNC_PATH/" 2>/dev/null || true
            rm -rf "$OUTPUT_DIR"
            ln -s "$SYNC_PATH" "$OUTPUT_DIR"
        elif [ ! -e "$OUTPUT_DIR" ]; then
             ln -s "$SYNC_PATH" "$OUTPUT_DIR"
        fi
        zenity --info --text="Synchronisation configurée pour:\n$SYNC_PATH" --width=400
    fi
fi

# --- Création des icônes finales ---
cat > "$SCRIPTS_DIR/start_comfyui.sh" << 'STARTER'
#!/bin/bash
cd "$HOME/ComfyUI"
source venv/bin/activate
PORT=8188
python main.py --listen 0.0.0.0 --port $PORT --cuda-device 0 --use-pytorch-cross-attention
STARTER
chmod +x "$SCRIPTS_DIR/start_comfyui.sh"

cat > "$DESKTOP_DIR/Lancer_ComfyUI.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=✅ Lancer ComfyUI
Comment=Démarrer le serveur ComfyUI
Exec=xterm -title "ComfyUI Server" -hold -e "$SCRIPTS_DIR/start_comfyui.sh"
Icon=applications-graphics
Terminal=false
EOF
chmod +x "$DESKTOP_DIR/Lancer_ComfyUI.desktop"

cat > "$SCRIPTS_DIR/stop_comfyui.sh" << 'STOPPER'
#!/bin/bash
pkill -f "python main.py --listen"
killall xterm
STOPPER
chmod +x "$SCRIPTS_DIR/stop_comfyui.sh"

cat > "$DESKTOP_DIR/Stopper_ComfyUI.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=🛑 Stopper ComfyUI
Comment=Arrêter le serveur ComfyUI
Exec=$SCRIPTS_DIR/stop_comfyui.sh
Icon=process-stop
Terminal=false
EOF
chmod +x "$DESKTOP_DIR/Stopper_ComfyUI.desktop"

# Auto-suppression du script de configuration
rm "$DESKTOP_DIR/Configurer_ComfyUI.desktop"

zenity --info --text="Configuration terminée !\n\nVous pouvez maintenant utiliser les icônes 'Lancer ComfyUI' et 'Stopper ComfyUI'." --width=400
SETUP_STAGE2
    chmod +x "$SCRIPTS_DIR/setup_stage2.sh"

    # --- Icône pour lancer l'étape 2 ---
    cat > "$DESKTOP_DIR/Configurer_ComfyUI.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=✨ Configurer ComfyUI
Comment=Finaliser l'installation et la synchronisation
Exec=$SCRIPTS_DIR/setup_stage2.sh
Icon=system-run
Terminal=false
EOF
    chmod +x "$DESKTOP_DIR/Configurer_ComfyUI.desktop"
    
    # Rendre l'icône fiable
    gio set "$DESKTOP_DIR/Configurer_ComfyUI.desktop" metadata::trusted true 2>/dev/null || true
}


# --- SÉQUENCE D'EXÉCUTION ---
install_dependencies
install_comfyui
download_models
create_final_setup_script

echo "--- Installation en arrière-plan terminée ---"
echo "Quand vous vous connecterez, double-cliquez sur l'icône 'Configurer ComfyUI' sur le bureau."
