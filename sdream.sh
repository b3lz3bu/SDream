#!/bin/bash

# SDREAM - by B3LZ3BU - rymstudio 2025 - v0.1
# Gestisce file immagine Dreamcast per GDEMU da riga di comando

VERSION="1.0"
CONFIG_DIR="$HOME/.gdemu_mini"
CONFIG_FILE="$CONFIG_DIR/config.conf"
SD_PATH=""
TEMP_DIR="/tmp/gdemu_mini"
GAMES_LIST_FILE="$TEMP_DIR/games_list.txt"

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Inizializza
mkdir -p "$CONFIG_DIR"
mkdir -p "$TEMP_DIR"

# Carica configurazione
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Validazione percorsi
validate_path() {
    local path="$1"
    if [[ "$path" == *".."* ]] || [[ "$path" == *"|"* ]] || [[ "$path" == *";"* ]]; then
        echo -e "${RED}Errore: Percorso non valido o potenzialmente pericoloso!${NC}"
        return 1
    fi
    return 0
}

# Salva configurazione
save_config() {
    echo "# DREAMSD - Configurazione" > "$CONFIG_FILE"
    echo "SD_PATH=\"$SD_PATH\"" >> "$CONFIG_FILE"
    echo "# Configurazione salvata il $(date)" >> "$CONFIG_FILE"
}

# Formatta dimensione file
format_size() {
    local size="$1"
    local units=("B" "KB" "MB" "GB" "TB")
    local unit=0
    
    while [ "$size" -ge 1024 ] && [ "$unit" -lt 4 ]; do
        size=$((size / 1024))
        unit=$((unit + 1))
    done
    
    echo "$size ${units[$unit]}"
}

# Imposta SD Card
set_sd() {
    local path="$1"

    validate_path "$path" || exit 1
    
    if [ ! -d "$path" ]; then
        echo -e "${RED}Errore: Il percorso non esiste o non è una directory!${NC}"
        exit 1
    fi
    
    SD_PATH="$path"
    save_config
    echo -e "${GREEN}SD Card impostata: $SD_PATH${NC}"
    scan_sd
}

# Scansiona SD Card
scan_sd() {
    if [ -z "$SD_PATH" ] || [ ! -d "$SD_PATH" ]; then
        echo -e "${RED}Errore: SD Card non impostata!${NC}"
        exit 1
    fi
    
    echo -e "${CYAN}Scansione della SD Card in corso...${NC}"
    
    # Crea file temporaneo per la lista giochi
    >"$GAMES_LIST_FILE"
    
   # Memorizza l'IFS originale
    OLD_IFS="$IFS"
    # Imposta IFS a newline per gestire correttamente i nomi file con spazi
    IFS=$'\n'

    # Trova tutte le cartelle nella SD Card
    folders=($(find "$SD_PATH" -maxdepth 1 -type d | sort))
    total_folders=${#folders[@]}
    current=0

    # Ripristina l'IFS originale
    IFS="$OLD_IFS"

    for folder in "${folders[@]}"; do
        if [ "$folder" = "$SD_PATH" ]; then
            continue
        fi
        
        current=$((current + 1))
        folder_name=$(basename "$folder")
        
        echo -ne "${CYAN}Scansione ($current/$total_folders): $folder_name${NC}\r"
        
        # Controlla se è una cartella numerica
        folder_num=999
        if [[ "$folder_name" =~ ^[0-9]+$ ]]; then
            folder_num="$folder_name"
        fi
        
        # Cerca file di gioco nelle estensioni supportate
        game_file=""
        game_type="N/A"
        for ext in ".gdi" ".cdi" ".iso" ".ccd" ".mds" ".chd"; do
            if [ -n "$(find "$folder" -maxdepth 1 -name "*$ext" -print -quit)" ]; then
                game_file=$(find "$folder" -maxdepth 1 -name "*$ext" -print -quit)
                game_type="${ext:1}"
                break
            fi
        done
        
        # Se abbiamo trovato un file di gioco
        if [ -n "$game_file" ]; then
            game_title=$(basename "$game_file" | sed 's/\.[^.]*$//i')
            
            # Cerca info.txt per il titolo
            if [ -f "$folder/info.txt" ]; then
                title_from_info=$(grep -i "^Title:" "$folder/info.txt" | sed 's/^Title:[[:space:]]*//i')
                if [ -n "$title_from_info" ]; then
                    game_title="$title_from_info"
                fi
            fi
            
            # Calcola dimensione
            folder_size=$(du -s "$folder" | awk '{print $1}')
            folder_size=$((folder_size * 1024))
            size_str=$(format_size "$folder_size")
            
            # Aggiungi alla lista
            echo "$folder_num|$folder|$game_title|${game_type^^}|$folder_size|$size_str|$game_file" >> "$GAMES_LIST_FILE"
        fi
    done
    
    # Conta i giochi trovati
    game_count=$(wc -l < "$GAMES_LIST_FILE")
    echo -e "\n${GREEN}Trovati $game_count giochi nella SD Card.${NC}"
}

# Elenca giochi
list_games() {
    if [ ! -f "$GAMES_LIST_FILE" ] || [ ! -s "$GAMES_LIST_FILE" ]; then
        echo -e "${RED}Nessun gioco trovato. Esegui prima 'scan'.${NC}"
        return 1
    fi
    
    # Stampa intestazione
    printf "${CYAN}%-5s %-40s %-10s %-6s${NC}\n" "#" "TITOLO" "DIMENSIONE" "TIPO"
    echo "----------------------------------------------------------------------"
    
    # Stampa ogni gioco
    while IFS='|' read -r number path title type size size_str file; do
        printf "%-5s %-40s %-10s %-6s\n" "$number" "${title:0:38}" "$size_str" "$type"
    done < "$GAMES_LIST_FILE"
}

# Aggiungi un gioco
add_game() {
    if [ -z "$SD_PATH" ] || [ ! -d "$SD_PATH" ]; then
        echo -e "${RED}Errore: SD Card non impostata!${NC}"
        exit 1
    fi
    
    local file="$1"

    validate_path "$file" || return 1

    local numbered="$2"  # true/false
    
    if [ -z "$file" ] || [ ! -f "$file" ]; then
        echo -e "${RED}Errore: File non valido!${NC}"
        return 1
    fi
    
    # Estrai informazioni sul file
    filename=$(basename "$file")
    extension="${filename##*.}"
    basename="${filename%.*}"
    
    echo -e "${CYAN}Aggiunta di $filename...${NC}"
    
    # Determina il nome della cartella
    folder_name="$basename"
    if [ "$numbered" = "true" ]; then
        
        # Inizia sempre dalla cartella 02 (01 è riservata per GDMenu)
        next_number=2
        if [ -f "$GAMES_LIST_FILE" ]; then
            while IFS='|' read -r num path title type size size_str file_path; do
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge "$next_number" ]; then
                    next_number=$((num + 1))
                fi
            done < "$GAMES_LIST_FILE"
        fi
        
        folder_name=$(printf "%02d" "$next_number")
    fi
    
    # Crea la cartella di destinazione
    dest_folder="$SD_PATH/$folder_name"
    mkdir -p "$dest_folder"
    
   # Copia il file principale rinominandolo come "disc.estensione" per compatibilità GDEMU
    cp "$file" "$dest_folder/disc.${extension,,}"
    echo "File principale rinominato in disc.${extension,,}"
    
    # Copia i file associati (per GDI, CCD, MDS)
    base_path="${file%.*}"
    source_dir=$(dirname "$file")
    
    # Per CCD+IMG
    if [ "${extension,,}" = "ccd" ]; then
        for ext in ".img" ".sub"; do
            if [ -f "$base_path$ext" ]; then
                echo "Copia file associato: $(basename "$base_path$ext")"
                cp "$base_path$ext" "$dest_folder/"
            fi
        done
    fi
    
    # Per MDS+MDF
    if [ "${extension,,}" = "mds" ]; then
        mdf_file="$base_path.mdf"
        if [ -f "$mdf_file" ]; then
            echo "Copia file associato: $(basename "$mdf_file")"
            cp "$mdf_file" "$dest_folder/"
        fi
    fi
    
    # Per GDI, copia le tracce
    if [ "${extension,,}" = "gdi" ] && [ -f "$file" ]; then
        track_count=$(head -n 1 "$file" | tr -d "\r")
        
        if [[ "$track_count" =~ ^[0-9]+$ ]]; then
            echo "Copia delle $track_count tracce GDI..."
            line_number=0
            while IFS= read -r line || [ -n "$line" ]; do
                line_number=$((line_number + 1))
                
                # Salta la prima riga (numero di tracce)
                if [ $line_number -eq 1 ]; then
                    continue
                fi
                
                # Estrai il nome del file dalla riga
                track_file=$(echo "$line" | awk '{print $5}')
                
                if [ -n "$track_file" ]; then
                    # Gestisci sia percorsi relativi che assoluti
                    if [[ "$track_file" != /* ]]; then
                        # È un percorso relativo
                        track_path="$source_dir/$track_file"
                    else
                        # È un percorso assoluto
                        track_path="$track_file"
                    fi
                    
                    if [ -f "$track_path" ]; then
                        cp "$track_path" "$dest_folder/"
                    fi
                fi
                
                # Termina se abbiamo processato tutte le tracce
                if [ $line_number -gt $track_count ]; then
                    break
                fi
            done < "$file"
        fi
    fi
    
    # Crea file info.txt
    echo "Title: $basename" > "$dest_folder/info.txt"
    echo "Original: $filename" >> "$dest_folder/info.txt"
    echo "Type: ${extension^^}" >> "$dest_folder/info.txt"
    echo "Added: $(date)" >> "$dest_folder/info.txt"
    
    echo -e "${GREEN}Gioco aggiunto con successo nella cartella $folder_name!${NC}"

    # Rigenera il menu GDMenu
    update_gdmenu_list

    # Aggiorna la lista dei giochi
    scan_sd
}

# Aggiungi giochi da una cartella
add_folder() {
    if [ -z "$SD_PATH" ] || [ ! -d "$SD_PATH" ]; then
        echo -e "${RED}Errore: SD Card non impostata!${NC}"
        exit 1
    fi
    
    local source_dir="$1"

    validate_path "$source_dir" || return 1

    local numbered="$2"  # true/false
    
    if [ -z "$source_dir" ] || [ ! -d "$source_dir" ]; then
        echo -e "${RED}Errore: Cartella sorgente non valida!${NC}"
        return 1
    fi
    
    echo -e "${CYAN}Ricerca di file immagine in $source_dir...${NC}"
    
    # Memorizza l'IFS (Internal Field Separator) originale
    local OLD_IFS="$IFS"
    # Imposta IFS a newline per manipolare correttamente i nomi file con spazi
    IFS=$'\n'

    #  Trova tutti i file supportati
    local gdi_files=($(find "$source_dir" -type f -name "*.gdi" 2>/dev/null))
    local cdi_files=($(find "$source_dir" -type f -name "*.cdi" 2>/dev/null))
    local iso_files=($(find "$source_dir" -type f -name "*.iso" 2>/dev/null))
    local ccd_files=($(find "$source_dir" -type f -name "*.ccd" 2>/dev/null))
    local mds_files=($(find "$source_dir" -type f -name "*.mds" 2>/dev/null))
    local chd_files=($(find "$source_dir" -type f -name "*.chd" 2>/dev/null))

    # Unisci tutti i file trovati in un array
    local all_files=("${gdi_files[@]}" "${cdi_files[@]}" "${iso_files[@]}" "${ccd_files[@]}" "${mds_files[@]}" "${chd_files[@]}")

    # Conta i file
    local file_count=${#all_files[@]}

    # Ripristina l'IFS originale
    IFS="$OLD_IFS"
    
    if [ $file_count -eq 0 ]; then
        echo -e "${YELLOW}Nessun file immagine trovato nella cartella.${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Trovati $file_count file immagine.${NC}"
    echo ""
    
    # Inizializza il contatore per le cartelle numerate, partendo da 02 (01 è riservata per GDMenu)
    local next_number=2
    echo -e "${YELLOW}La cartella 01 è riservata per GDMenu, i giochi partiranno da 02${NC}"
    if [ -f "$GAMES_LIST_FILE" ]; then
        while IFS='|' read -r num path title type size size_str file_path; do
            if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge "$next_number" ]; then
                next_number=$((num + 1))
            fi
        done < "$GAMES_LIST_FILE"
    fi
    
    # Processa ogni file
    local added=0
    for file in "${all_files[@]}"; do
        echo -e "${CYAN}Processando: $(basename "$file")${NC}"
        
        # Estrai informazioni sul file
        local filename=$(basename "$file")
        local extension="${filename##*.}"
        local basename="${filename%.*}"
        
        # Determina il nome della cartella sempre numerata come richiesto da GDEMU
        local folder_name=$(printf "%02d" "$next_number")
        next_number=$((next_number + 1))
        
        # Crea la cartella di destinazione
        local dest_folder="$SD_PATH/$folder_name"
        mkdir -p "$dest_folder"

        # Copia il file principale rinominandolo come "disc.estensione" per compatibilità GDEMU
        cp "$file" "$dest_folder/disc.${extension,,}"
        echo "  File principale rinominato in disc.${extension,,}"
        
        # Copia i file associati (per GDI, CCD, MDS)
        local base_path="${file%.*}"
        local source_dir=$(dirname "$file")
        
        # Per CCD+IMG
        if [ "${extension,,}" = "ccd" ]; then
            for ext in ".img" ".sub"; do
                if [ -f "$base_path$ext" ]; then
                    echo "  Copia file associato: $(basename "$base_path$ext")"
                    cp "$base_path$ext" "$dest_folder/"
                fi
            done
        fi
        
        # Per MDS+MDF
        if [ "${extension,,}" = "mds" ]; then
            local mdf_file="$base_path.mdf"
            if [ -f "$mdf_file" ]; then
                echo "  Copia file associato: $(basename "$mdf_file")"
                cp "$mdf_file" "$dest_folder/"
            fi
        fi
        
        # Per GDI, copia le tracce
        if [ "${extension,,}" = "gdi" ] && [ -f "$file" ]; then
            local track_count=$(head -n 1 "$file" | tr -d "\r\n")
            
            if [[ "$track_count" =~ ^[0-9]+$ ]]; then
                echo "  Copia delle $track_count tracce GDI..."
                local line_number=0
                while IFS= read -r line || [ -n "$line" ]; do
                    line_number=$((line_number + 1))
                    
                    # Salta la prima riga (numero di tracce)
                    if [ $line_number -eq 1 ]; then
                        continue
                    fi
                    
                    # Estrai il nome del file dalla riga
                    track_file=$(echo "$line" | awk '{print $5}')
                    
                    if [ -n "$track_file" ]; then
                        # Gestisci sia percorsi relativi che assoluti
                        if [[ "$track_file" != /* ]]; then
                            # È un percorso relativo
                            track_path="$source_dir/$track_file"
                        else
                            # È un percorso assoluto
                            track_path="$track_file"
                        fi
                        
                        if [ -f "$track_path" ]; then
                            cp "$track_path" "$dest_folder/"
                        fi
                    fi
                    
                    # Termina se abbiamo processato tutte le tracce
                    if [ $line_number -gt $track_count ]; then
                        break
                    fi
                done < "$file"
            fi
        fi
        
        # Crea file info.txt
        echo "Title: $basename" > "$dest_folder/info.txt"
        echo "Original: $filename" >> "$dest_folder/info.txt"
        echo "Type: ${extension^^}" >> "$dest_folder/info.txt"
        echo "Added: $(date)" >> "$dest_folder/info.txt"
        
        echo -e "${GREEN}  Aggiunto nella cartella $folder_name${NC}"
        added=$((added + 1))
    done
    
    echo -e "\n${GREEN}Aggiunti $added giochi con successo!${NC}"

    # Rigenera il menu GDMenu
    update_gdmenu_list
    
    # Aggiorna la lista dei giochi
    scan_sd
}

# Rimuovi un gioco
remove_game() {
    if [ ! -f "$GAMES_LIST_FILE" ] || [ ! -s "$GAMES_LIST_FILE" ]; then
        echo -e "${RED}Nessun gioco trovato. Esegui prima 'scan'.${NC}"
        return 1
    fi
    
    local number="$1"
    
    if [ -z "$number" ]; then
        echo -e "${RED}Errore: Numero di gioco non specificato!${NC}"
        return 1
    fi
    
    # Trova il gioco
    game_found=false
    while IFS='|' read -r num path title type size size_str file; do
        if [ "$num" = "$number" ]; then
            game_found=true
            
            echo -e "${RED}Sei sicuro di voler rimuovere il gioco: $title?${NC}"
            echo -n "Continua? [s/N]: "
            read -r confirm
            
            if [[ "${confirm,,}" == "s" ]]; then
                echo "Rimozione dei file..."
                if [ -d "$path" ] && [ "$(basename "$path")" != "/" ]; then
                    rm -rf "$path"/*
                    echo -e "${GREEN}Gioco rimosso con successo!${NC}"
                    
                    # Rigenera il menu GDMenu
                    update_gdmenu_list
                else
                    echo -e "${RED}Errore: Percorso non valido o troppo pericoloso per la rimozione!${NC}"
                fi
                scan_sd
            else
                echo "Operazione annullata."
            fi
            
            break
        fi
    done < "$GAMES_LIST_FILE"
    
    if [ "$game_found" = false ]; then
        echo -e "${RED}Errore: Nessun gioco trovato con il numero $number!${NC}"
    fi
}

# Rinomina un gioco
rename_game() {
    if [ ! -f "$GAMES_LIST_FILE" ] || [ ! -s "$GAMES_LIST_FILE" ]; then
        echo -e "${RED}Nessun gioco trovato. Esegui prima 'scan'.${NC}"
        return 1
    fi
    
    local number="$1"
    local new_title="$2"
    
    if [ -z "$number" ] || [ -z "$new_title" ]; then
        echo -e "${RED}Errore: Parametri insufficienti!${NC}"
        return 1
    fi
    
    # Trova il gioco
    game_found=false
    while IFS='|' read -r num path title type size size_str file; do
        if [ "$num" = "$number" ]; then
            game_found=true
            
            if [ -f "$path/info.txt" ]; then
                sed -i "s/^Title:.*$/Title: $new_title/i" "$path/info.txt"
            else
                echo "Title: $new_title" > "$path/info.txt"
            fi
            
            echo -e "${GREEN}Gioco rinominato da '$title' a '$new_title'!${NC}"
            
            # Rigenera il menu GDMenu
            update_gdmenu_list
            
            scan_sd
            break
        fi
    done < "$GAMES_LIST_FILE"
    
    if [ "$game_found" = false ]; then
        echo -e "${RED}Errore: Nessun gioco trovato con il numero $number!${NC}"
    fi
}

# Riorganizza numericamente i giochi
reorder_games() {
    if [ -z "$SD_PATH" ] || [ ! -d "$SD_PATH" ]; then
        echo -e "${RED}Errore: SD Card non impostata!${NC}"
        exit 1
    fi
    
    if [ ! -f "$GAMES_LIST_FILE" ] || [ ! -s "$GAMES_LIST_FILE" ]; then
        echo -e "${RED}Nessun gioco trovato. Esegui prima 'scan'.${NC}"
        return 1
    fi
    
    echo -e "${CYAN}Riordinamento delle cartelle...${NC}"
    
    # Directory temporanea per il riordinamento
    tmp_dir="$TEMP_DIR/reorder_tmp"
    mkdir -p "$tmp_dir"
    
    # Memorizza l'IFS originale
    local OLD_IFS="$IFS"
    # Imposta IFS a newline per gestire correttamente i nomi file con spazi
    IFS=$'\n'

    # Leggi i giochi e assegna nuovi numeri
    counter=2  # Inizia da 02, 01 riservata per GDMenu
    while IFS='|' read -r num path title type size size_str file; do
       
        # Ignora la cartella 01 (GDMenu)
        if [ "$num" = "01" ]; then
            continue
        fi
        
        new_num=$(printf "%02d" $counter)
        new_path="$tmp_dir/$new_num"
        
        echo -e "Spostamento $num -> $new_num: $title"
        
        # Sposta nella directory temporanea
        mkdir -p "$new_path"
        mv "$path"/* "$new_path/" 2>/dev/null || true
        
        counter=$((counter + 1))
    done < "$GAMES_LIST_FILE"

    # Ripristina l'IFS originale
    IFS="$OLD_IFS"

    # Rimuovi le vecchie cartelle
    while IFS='|' read -r num path title type size size_str file; do
        if [ -d "$path" ]; then
            rmdir "$path"
        fi
    done < "$GAMES_LIST_FILE"
    
    # Sposta le nuove cartelle ordinate
    find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | while read dir; do
        new_num=$(basename "$dir")
        mv "$dir" "$SD_PATH/$new_num"
    done
    
    # Pulisci
    rm -rf "$tmp_dir"
    
    echo -e "${GREEN}Riordinamento completato con successo!${NC}"

    # Rigenera il menu GDMenu
    update_gdmenu_list

    scan_sd
}

# Converti tutte le cartelle in formato numerico
convert_to_numbered() {
    if [ -z "$SD_PATH" ] || [ ! -d "$SD_PATH" ]; then
        echo -e "${RED}Errore: SD Card non impostata!${NC}"
        exit 1
    fi
    
    echo -e "${CYAN}Conversione delle cartelle in formato numerico...${NC}"
    
    # Memorizza l'IFS originale
    local OLD_IFS="$IFS"
    # Imposta IFS a newline per gestire correttamente i nomi file con spazi
    IFS=$'\n'
    
    # Crea directory temporanea
    local tmp_dir="$TEMP_DIR/numbered_tmp"
    mkdir -p "$tmp_dir"
    
    # Trova tutte le cartelle
    local folders=($(find "$SD_PATH" -maxdepth 1 -type d -not -path "$SD_PATH"))
    local count=${#folders[@]}
    
    if [ $count -eq 0 ]; then
        echo -e "${YELLOW}Nessuna cartella trovata nella SD Card.${NC}"
        rm -rf "$tmp_dir"
        return 1
    fi
    
    # Processa le cartelle
    local counter=2  # Inizia da 02, 01 riservata per GDMenu
    echo -e "${YELLOW}La cartella 01 è riservata per GDMenu, la conversione inizierà da 02${NC}"
    for folder in "${folders[@]}"; do
        
        # Ignora la cartella principale e la cartella 01 se esiste
        if [ "$folder" = "$SD_PATH" ] || [ "$(basename "$folder")" = "01" ]; then
            continue
        fi
        
        local folder_name=$(basename "$folder")
        local new_folder=$(printf "%02d" $counter)
        
        echo -e "Conversione: $folder_name -> $new_folder"
        
        # Crea la cartella temporanea e sposta i contenuti
        mkdir -p "$tmp_dir/$new_folder"
        
        # Copia tutti i file
        cp -r "$folder"/* "$tmp_dir/$new_folder/" 2>/dev/null || true
        
        # Se c'è un file info.txt, aggiorna il titolo
        if [ -f "$tmp_dir/$new_folder/info.txt" ]; then
            sed -i "s/^Title:.*$/Title: $folder_name/i" "$tmp_dir/$new_folder/info.txt"
        else
            echo "Title: $folder_name" > "$tmp_dir/$new_folder/info.txt"
        fi
        
        counter=$((counter + 1))
    done
    
    # Rimuovi tutte le cartelle originali
    for folder in "${folders[@]}"; do
        if [ -d "$folder" ]; then
            rm -rf "$folder"
        fi
    done
    
    # Sposta le nuove cartelle numerate
    cp -r "$tmp_dir"/* "$SD_PATH/"
    
    # Pulisci
    rm -rf "$tmp_dir"
    
    # Ripristina l'IFS originale
    IFS="$OLD_IFS"
    
    echo -e "${GREEN}Conversione completata con successo!${NC}"

    # Rigenera il menu GDMenu
    update_gdmenu_list

    scan_sd
}

# Installazione di GDMenu
install_openmenu() {
    if [ -z "$SD_PATH" ] || [ ! -d "$SD_PATH" ]; then
        echo -e "${RED}Errore: SD Card non impostata!${NC}"
        exit 1
    fi
    
    local openmenu_archive="gdmenu.tar.gz"
    
    if [ ! -f "$openmenu_archive" ]; then
        echo -e "${RED}Errore: File $openmenu_archive non trovato nella directory corrente!${NC}"
        return 1
    fi
    
    echo -e "${CYAN}Installazione di GDMenu nella cartella 01...${NC}"
    
    # Crea una directory temporanea per l'estrazione
    local temp_extract="$TEMP_DIR/openmenu_extract"
    mkdir -p "$temp_extract"
    
    # Estrai l'archivio
    tar -xzf "$openmenu_archive" -C "$temp_extract"
    
    # Verifica se la cartella 01 esiste nell'archivio
    if [ -d "$temp_extract/01" ]; then
        # Crea o pulisci la cartella 01 sulla SD
        mkdir -p "$SD_PATH/01"
        rm -rf "$SD_PATH/01/*"
        
        # Copia i contenuti
        cp -r "$temp_extract/01/"* "$SD_PATH/01/"
        echo -e "${GREEN}GDMenu installato con successo nella cartella 01!${NC}"
    else
        echo -e "${RED}Errore: Struttura imprevista nell'archivio. La cartella 01 non è stata trovata.${NC}"
        ls -la "$temp_extract"
    fi
    
    # Pulisci la directory temporanea
    rm -rf "$temp_extract"
}

# Funzione per creare il file GDEMU.ini
create_gdemu_ini() {
    if [ -z "$SD_PATH" ] || [ ! -d "$SD_PATH" ]; then
        echo -e "${RED}Errore: SD Card non impostata!${NC}"
        exit 1
    fi
    
    echo -e "${CYAN}Creazione del file GDEMU.ini...${NC}"
    
    # Crea il file GDEMU.ini con le impostazioni standard
    cat > "$SD_PATH/GDEMU.ini" << EOF
[GDEMU]
FastBootS=1
FastBootK=0
SlowCardO=0
LoaderIn=1
LoaderCA=1
HideGDGA=1
AlphaSrt=0
NameSrt=1
RegionPS=0
AutoBoot=0
MemCardC=0
ScreenDi=0
VisMenuL=0
EOF
    
    echo -e "${GREEN}File GDEMU.ini creato con successo!${NC}"
}

# Funzione per generare menu.lst (mantenuta per compatibilità)
generate_menu_lst() {
    if [ -z "$SD_PATH" ] || [ ! -d "$SD_PATH" ]; then
        echo -e "${RED}Errore: SD Card non impostata!${NC}"
        exit 1
    fi
    
    echo -e "${CYAN}Generazione del file menu.lst...${NC}"
    
    # Crea o sovrascrivi il file menu.lst - assicurati che sia vuoto
    > "$SD_PATH/menu.lst"
    
    # Salva in UTF-8 senza BOM e con terminazioni di riga DOS (CR+LF)
    # Aggiungi GDMenu come prima voce
    if [ -d "$SD_PATH/01" ]; then
        echo -e "01 GDMenu\r" > "$SD_PATH/menu.lst"
    fi
    
    # Scansiona tutte le cartelle numerate in ordine
    for folder in $(find "$SD_PATH" -maxdepth 1 -type d -name "[0-9][0-9]" | sort); do
        if [ -d "$folder" ]; then
            folder_num=$(basename "$folder")
            
            # Salta la cartella 01 (già aggiunta)
            if [ "$folder_num" = "01" ]; then
                continue
            fi
            
            # Ottieni il titolo dal file info.txt o usa il nome della cartella
            title=""
            if [ -f "$folder/info.txt" ]; then
                title=$(grep -i "^Title:" "$folder/info.txt" | sed 's/^Title:[[:space:]]*//i')
            fi
            
            if [ -z "$title" ]; then
                # Cerca di ottenere il titolo dal nome del file principale
                game_file=$(find "$folder" -maxdepth 1 -name "disc.*" -print -quit)
                if [ -n "$game_file" ]; then
                    title=$(basename "$game_file" | sed 's/disc\.//' | sed 's/\.[^.]*$//')
                else
                    title="Game $folder_num"
                fi
            fi
            
            # Pulisci il titolo completamente
            # Rimuovi tutti i caratteri speciali, lasciando solo lettere, numeri e alcuni segni
            title=$(echo "$title" | iconv -f utf-8 -t ascii//TRANSLIT 2>/dev/null || echo "$title" | tr -cd 'A-Za-z0-9 .-')
            
            # Limita la lunghezza del titolo a 32 caratteri
            title="${title:0:32}"
            
            # Aggiungi la voce al menu.lst con terminazione di riga DOS (CR+LF)
            echo -e "$folder_num $title\r" >> "$SD_PATH/menu.lst"
            
            echo "Aggiunta voce: $folder_num $title"
        fi
    done
    
    echo -e "${GREEN}File menu.lst generato con successo!${NC}"
    echo -e "${YELLOW}Verificare il file menu.lst...${NC}"
    cat "$SD_PATH/menu.lst"
}

# Monta il file track01.iso per modificare i contenuti
mount_gdmenu_iso() {
    local mount_point="$TEMP_DIR/gdmenu_mount"
    local iso_file="$SD_PATH/01/track01.iso"
    
    if [ ! -f "$iso_file" ]; then
        echo -e "${RED}Errore: File track01.iso non trovato nella cartella 01!${NC}"
        return 1
    fi
    
    # Crea punto di montaggio
    mkdir -p "$mount_point"
    
    # Monta l'ISO (potrebbe richiedere sudo)
    if ! sudo mount -o loop "$iso_file" "$mount_point" 2>/dev/null; then
        echo -e "${RED}Errore: Impossibile montare track01.iso. Potrebbero essere necessari privilegi amministratore.${NC}"
        return 1
    fi
    
    echo "$mount_point"
    return 0
}

# Smonta il file ISO
umount_gdmenu_iso() {
    local mount_point="$1"
    
    if [ -n "$mount_point" ] && mountpoint -q "$mount_point" 2>/dev/null; then
        sudo umount "$mount_point"
        rmdir "$mount_point" 2>/dev/null
    fi
}

# Aggiorna il file list.ini all'interno del track01.iso
update_gdmenu_list() {

echo "DEBUG: Funzione update_gdmenu_list chiamata"
    
    if [ -z "$SD_PATH" ] || [ ! -d "$SD_PATH" ]; then
        echo -e "${RED}Errore: SD Card non impostata!${NC}"
        exit 1
    fi
    
    echo "DEBUG: SD_PATH = $SD_PATH"
    
    if [ ! -f "$SD_PATH/01/track01.iso" ]; then
        echo -e "${RED}Errore: File track01.iso non trovato!${NC}"
        return 1
    fi
    
    echo "DEBUG: File track01.iso trovato"
    
    if [ -z "$SD_PATH" ] || [ ! -d "$SD_PATH" ]; then
        echo -e "${RED}Errore: SD Card non impostata!${NC}"
        exit 1
    fi
    
    echo -e "${CYAN}Aggiornamento del menu GDMenu...${NC}"
    
    # Crea una copia temporanea del track01.iso per modificarlo
    local temp_iso="$TEMP_DIR/track01_temp.iso"
    local temp_mount="$TEMP_DIR/gdmenu_temp"
    local temp_files="$TEMP_DIR/gdmenu_files"
    
    cp "$SD_PATH/01/track01.iso" "$temp_iso"
    
    # Monta l'ISO temporaneo
    mkdir -p "$temp_mount"
    mkdir -p "$temp_files"
    
    if ! sudo mount -o loop "$temp_iso" "$temp_mount" 2>/dev/null; then
        echo -e "${RED}Errore: Impossibile montare l'ISO temporaneo${NC}"
        return 1
    fi
    
    # Copia i file esistenti
    cp -r "$temp_mount"/* "$temp_files/"
    
    # Smonta l'ISO temporaneo
    sudo umount "$temp_mount"
    
    # Genera il nuovo list.ini
    cat > "$temp_files/list.ini" << EOF
[GDMENU]
01.name=GDMENU
01.disc=1/1
01.vga=1
01.region=JUE
01.version=V0.6.0
01.date=20160812

EOF
    
    # Scansiona tutte le cartelle numerate e aggiungi le voci
    for folder in $(find "$SD_PATH" -maxdepth 1 -type d -name "[0-9][0-9]" | sort); do
        if [ -d "$folder" ]; then
            folder_num=$(basename "$folder")
            
            # Salta la cartella 01 (GDMenu stesso)
            if [ "$folder_num" = "01" ]; then
                continue
            fi
            
            # Ottieni informazioni sul gioco
            local game_title=""
            local game_region="U"
            local game_version="V1.000"
            local game_date=$(date +%Y%m%d)
            
            # Leggi il titolo dal file info.txt
            if [ -f "$folder/info.txt" ]; then
                game_title=$(grep -i "^Title:" "$folder/info.txt" | sed 's/^Title:[[:space:]]*//i')
            fi
            
            # Se non c'è titolo, usa il nome del file disc
            if [ -z "$game_title" ]; then
                local game_file=$(find "$folder" -maxdepth 1 -name "disc.*" -print -quit)
                if [ -n "$game_file" ]; then
                    game_title=$(basename "$game_file" | sed 's/disc\.//' | sed 's/\.[^.]*$//')
                else
                    game_title="Game $folder_num"
                fi
            fi
            
            # Pulisci il titolo (solo caratteri ASCII, max 32 caratteri, maiuscolo)
            game_title=$(echo "$game_title" | tr -cd 'A-Za-z0-9 .-' | tr '[:lower:]' '[:upper:]')
            game_title="${game_title:0:32}"
            
            # Determina la regione dal nome del file o cartella
            if [[ "$game_title" == *"(USA)"* ]] || [[ "$game_title" == *"[USA]"* ]]; then
                game_region="U"
            elif [[ "$game_title" == *"(EUR)"* ]] || [[ "$game_title" == *"[EUR]"* ]]; then
                game_region="E"
            elif [[ "$game_title" == *"(JAP)"* ]] || [[ "$game_title" == *"[JAP]"* ]] || [[ "$game_title" == *"(Japan)"* ]]; then
                game_region="J"
            else
                game_region="JUE"  # Multi-region
            fi
            
            # Aggiungi la voce al list.ini
            cat >> "$temp_files/list.ini" << EOF
$folder_num.name=$game_title
$folder_num.disc=1/1
$folder_num.vga=1
$folder_num.region=$game_region
$folder_num.version=$game_version
$folder_num.date=$game_date

EOF
            
            echo "Aggiunta voce menu: $folder_num - $game_title"
        fi
    done
    
    # Aggiorna il file gdemuinfo.txt
    echo "Generated using DREAMSD Games Manager v$VERSION" > "$temp_files/gdemuinfo.txt"
    
    # Crea un nuovo ISO con i file aggiornati
    if command -v genisoimage >/dev/null 2>&1; then
        genisoimage -o "$SD_PATH/01/track01.iso" -r -J "$temp_files/"
    elif command -v mkisofs >/dev/null 2>&1; then
        mkisofs -o "$SD_PATH/01/track01.iso" -r -J "$temp_files/"
    else
        echo -e "${RED}Errore: Nessun comando per creare ISO trovato (genisoimage o mkisofs)${NC}"
        echo -e "${YELLOW}Installa genisoimage: sudo apt-get install genisoimage${NC}"
        return 1
    fi
    
    # Pulisci i file temporanei
    rm -rf "$temp_files" "$temp_mount" "$temp_iso"
    
    echo -e "${GREEN}Menu GDMenu aggiornato con successo!${NC}"
}

# Funzione per inizializzare la SD Card per GDEMU
init_sd() {
    if [ -z "$SD_PATH" ] || [ ! -d "$SD_PATH" ]; then
        echo -e "${RED}Errore: SD Card non impostata!${NC}"
        exit 1
    fi
    
    echo -e "${CYAN}Inizializzazione della SD Card per GDEMU...${NC}"
    
    # Installa GDMenu
    install_openmenu
    
    # Crea il file GDEMU.ini
    create_gdemu_ini

    # Genera il menu GDMenu
    update_gdmenu_list
    
    echo -e "${GREEN}Inizializzazione completata!${NC}"
    scan_sd
}

# Mostra la guida
show_help() {
    echo -e "${CYAN}SDREAM -  Games Manager v${VERSION}${NC}"
    echo "Gestione minimale per file immagine Dreamcast per GDEMU"
    echo ""
    echo "Comandi:"
    echo "  set-sd <percorso>              Imposta la directory della SD Card"
    echo "  scan                           Scansiona la SD Card"
    echo "  init                           Inizializza la SD Card con GDMenu"
    echo "  list                           Mostra la lista dei giochi"
    echo "  add <file> [numbered]          Aggiunge un gioco"
    echo "  add-folder <dir> [numbered]    Aggiunge tutti i giochi da una cartella"
    echo "  remove <numero>                Rimuove un gioco"
    echo "  rename <numero> \"Nome\"         Rinomina un gioco"
    echo "  reorder                        Riordina numericamente le cartelle"
    echo "  numbered                       Converte cartelle in formato numerico"
    echo "  menu                           Rigenera il menu GDMenu"
    echo "  help                           Mostra questa guida"
    echo ""
    echo "Esempi:"
    echo "  ./dreamsd_gdemu.sh set-sd /media/sdcard"
    echo "  ./dreamsd_gdemu.sh init"
    echo "  ./dreamsd_gdemu.sh add-folder /path/games true"
    echo "  sudo ./dreamsd_gdemu.sh menu"
    echo ""
    echo "Note:"
    echo "  - I file vengono rinominati in 'disc.estensione' per compatibilità GDEMU"
    echo "  - La cartella 01 è riservata per GDMenu"
    echo "  - I comandi 'menu' e 'init' richiedono privilegi sudo"
    echo "  - Richiesti: genisoimage o mkisofs per creare file ISO"
}

# Gestisci comandi
case "$1" in
    set-sd)
        set_sd "$2"
        ;;
    init)
        init_sd
        ;;
    scan)
        scan_sd
        ;;
    list)
        list_games
        ;;
    add)
        if [ -z "$2" ]; then
            echo -e "${RED}Errore: File non specificato!${NC}"
            exit 1
        fi
        add_game "$2" "${3:-false}"
        ;;
    add-folder)
        if [ -z "$2" ]; then
            echo -e "${RED}Errore: Cartella non specificata!${NC}"
            exit 1
        fi
        add_folder "$2" "${3:-false}"
        ;;
    remove)
        remove_game "$2"
        ;;
    rename)
        rename_game "$2" "$3"
        ;;
    reorder)
        reorder_games
        ;;
    numbered)
        convert_to_numbered
        ;;
    menu)
        update_gdmenu_list
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        show_help
        ;;
esac