#!/bin/bash

# SDREAM - by B3LZ3BU - rymstudio 2025 - v1.1
# Gestisce file immagine Dreamcast per GDEMU da riga di comando

set -euo pipefail  # Uscita immediata su errori, variabili non definite, pipe rotte

VERSION="1.3"
# Risolve il path reale dell'utente anche quando lo script gira con sudo
# sudo imposta SUDO_USER con il nome dell'utente originale
_REAL_USER="${SUDO_USER:-$USER}"
_REAL_HOME=$(getent passwd "$_REAL_USER" 2>/dev/null | cut -d: -f6 || echo "$HOME")
CONFIG_DIR="$_REAL_HOME/.gdemu_mini"
CONFIG_FILE="$CONFIG_DIR/config.conf"
SD_PATH=""
TEMP_DIR="/tmp/gdemu_mini_$$"      # PID nel nome per file davvero temporanei
# GAMES_LIST_FILE e' persistente tra invocazioni diverse: salvato in CONFIG_DIR
# cosi' scan/remove/rename trovano sempre lo stesso file indipendentemente dal PID
GAMES_LIST_FILE="$CONFIG_DIR/games_list.txt"

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Pulizia automatica all'uscita ────────────────────────────────────────────
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# ── Inizializza directory ────────────────────────────────────────────────────
mkdir -p "$CONFIG_DIR"
mkdir -p "$TEMP_DIR"

# ── Carica configurazione ────────────────────────────────────────────────────
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# ── Validazione percorsi ─────────────────────────────────────────────────────
validate_path() {
    local path="$1"
    # FIX: aggiunto controllo su caratteri pericolosi aggiuntivi
    if [[ "$path" == *".."* ]] || [[ "$path" == *"|"* ]] || \
       [[ "$path" == *";"* ]] || [[ "$path" == *"$"* && "$path" != *"$HOME"* ]]; then
        echo -e "${RED}Errore: Percorso non valido o potenzialmente pericoloso!${NC}" >&2
        return 1
    fi
    return 0
}

# ── Salva configurazione ─────────────────────────────────────────────────────
save_config() {
    {
        echo "# SDREAM - Configurazione"
        echo "SD_PATH=\"$SD_PATH\""
        echo "# Configurazione salvata il $(date)"
    } > "$CONFIG_FILE"
}

# ── Formatta dimensione file ─────────────────────────────────────────────────
format_size() {
    local size="$1"
    local units=("B" "KB" "MB" "GB" "TB")
    local unit=0
    while (( size >= 1024 && unit < 4 )); do
        size=$(( size / 1024 ))
        unit=$(( unit + 1 ))
    done
    echo "$size ${units[$unit]}"
}

# ── Verifica SD impostata ────────────────────────────────────────────────────
require_sd() {
    if [[ -z "$SD_PATH" || ! -d "$SD_PATH" ]]; then
        echo -e "${RED}Errore: SD Card non impostata! Usa prima: $0 set-sd <percorso>${NC}" >&2
        exit 1
    fi
}

# ── Imposta SD Card ──────────────────────────────────────────────────────────
set_sd() {
    local path="$1"
    validate_path "$path" || exit 1

    if [ ! -d "$path" ]; then
        echo -e "${RED}Errore: Il percorso '$path' non esiste o non è una directory!${NC}" >&2
        exit 1
    fi

    SD_PATH="$path"
    save_config
    echo -e "${GREEN}SD Card impostata: $SD_PATH${NC}"
    scan_sd
}

# ── Scansiona SD Card ────────────────────────────────────────────────────────
scan_sd() {
    require_sd

    echo -e "${CYAN}Scansione della SD Card in corso...${NC}"

    # FIX: uso di processo null-separato per gestire nomi con spazi/newline in modo sicuro
    > "$GAMES_LIST_FILE"

    local folders=()
    while IFS= read -r -d $'\0' folder; do
        local fname
        fname=$(basename "$folder")
        # Ignora cartelle di sistema (Trash, spotlight, ecc.)
        [[ "$fname" == .* ]] && continue
        [[ "$fname" == "System Volume Information" ]] && continue
        [[ "$fname" == "RECYCLER" || "$fname" == '$RECYCLE.BIN' ]] && continue
        folders+=("$folder")
    done < <(find "$SD_PATH" -maxdepth 1 -mindepth 1 -type d -print0 | sort -z)

    local total_folders=${#folders[@]}
    local current=0

    for folder in "${folders[@]}"; do
        current=$(( current + 1 ))
        local folder_name
        folder_name=$(basename "$folder")

        echo -ne "${CYAN}Scansione ($current/$total_folders): $folder_name        ${NC}\r"

        # Determina numero cartella
        local folder_num=999
        if [[ "$folder_name" =~ ^[0-9]+$ ]]; then
            folder_num="$folder_name"
        fi

        # FIX: ricerca file con find null-safe, priorità su .gdi
        local game_file=""
        local game_type="N/A"
        for ext in gdi cdi iso ccd mds chd; do
            local found
            found=$(find "$folder" -maxdepth 1 -iname "*.$ext" -print -quit 2>/dev/null)
            if [[ -n "$found" ]]; then
                game_file="$found"
                game_type="${ext^^}"
                break
            fi
        done

        if [[ -n "$game_file" ]]; then
            local game_title
            game_title=$(basename "$game_file" | sed 's/\.[^.]*$//')

            # Legge titolo da info.txt se presente
            if [[ -f "$folder/info.txt" ]]; then
                local t
                t=$(grep -i "^Title:" "$folder/info.txt" | sed 's/^Title:[[:space:]]*//i' | head -1)
                [[ -n "$t" ]] && game_title="$t"
            fi

            local folder_size
            folder_size=$(du -sk "$folder" | awk '{print $1}')
            folder_size=$(( folder_size * 1024 ))
            local size_str
            size_str=$(format_size "$folder_size")

            # FIX: pipe nei campi del record sostituita con carattere sicuro
            printf '%s|%s|%s|%s|%s|%s|%s\n' \
                "$folder_num" "$folder" "$game_title" "$game_type" \
                "$folder_size" "$size_str" "$game_file" >> "$GAMES_LIST_FILE"
        fi
    done

    local game_count
    game_count=$(wc -l < "$GAMES_LIST_FILE")
    echo -e "\n${GREEN}Trovati $game_count giochi nella SD Card.${NC}"
}

# ── Elenca giochi ────────────────────────────────────────────────────────────
list_games() {
    if [[ ! -f "$GAMES_LIST_FILE" || ! -s "$GAMES_LIST_FILE" ]]; then
        echo -e "${YELLOW}Nessun gioco trovato. Esegui prima: $0 scan${NC}"
        return 1
    fi

    echo ""
    printf "${BOLD}${CYAN}%-5s %-42s %-10s %-6s${NC}\n" "#" "TITOLO" "DIM." "TIPO"
    printf '%0.s─' {1..67}; echo ""

    while IFS='|' read -r number path title type size size_str file; do
        printf "%-5s %-42s %-10s %-6s\n" "$number" "${title:0:40}" "$size_str" "$type"
    done < <(sort -t'|' -k1,1n "$GAMES_LIST_FILE")

    echo ""
    local count
    count=$(wc -l < "$GAMES_LIST_FILE")
    echo -e "${GREEN}Totale: $count giochi${NC}"
}

# ── Helper: prossimo numero disponibile ─────────────────────────────────────
get_next_number() {
    local next=2  # 01 riservata per GDMenu
    if [[ -f "$GAMES_LIST_FILE" ]]; then
        while IFS='|' read -r num _rest; do
            if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= next )); then
                next=$(( num + 1 ))
            fi
        done < "$GAMES_LIST_FILE"
    fi
    # FIX: controlla anche le cartelle fisiche sulla SD per sicurezza
    while [[ -d "$SD_PATH/$(printf '%02d' $next)" ]]; do
        next=$(( next + 1 ))
    done
    echo "$next"
}

# ── Copia tracce GDI ─────────────────────────────────────────────────────────
copy_gdi_tracks() {
    local gdi_file="$1"
    local dest_folder="$2"
    local source_dir
    source_dir=$(dirname "$gdi_file")

    local track_count
    track_count=$(head -n 1 "$gdi_file" | tr -d '\r\n')

    if ! [[ "$track_count" =~ ^[0-9]+$ ]]; then
        echo -e "${YELLOW}  Attenzione: impossibile leggere il numero di tracce GDI.${NC}"
        return 1
    fi

    echo "  Copia delle $track_count tracce GDI..."

    local line_number=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_number=$(( line_number + 1 ))
        [[ $line_number -eq 1 ]] && continue  # salta header

        # FIX: il campo 5 del GDI è il nome file (con possibili virgolette)
        local track_file
        track_file=$(echo "$line" | awk '{print $5}' | tr -d '"')

        if [[ -n "$track_file" ]]; then
            local track_path
            if [[ "$track_file" == /* ]]; then
                track_path="$track_file"
            else
                track_path="$source_dir/$track_file"
            fi

            if [[ -f "$track_path" ]]; then
                echo "  → $(basename "$track_path")"
                cp "$track_path" "$dest_folder/"
            else
                echo -e "${YELLOW}  Traccia non trovata: $track_path${NC}"
            fi
        fi

        [[ $line_number -gt $(( track_count + 1 )) ]] && break
    done < "$gdi_file"
}

# ── Aggiungi un gioco ────────────────────────────────────────────────────────
add_game() {
    require_sd

    local file="$1"
    local numbered="${2:-true}"  # FIX: default true, GDEMU richiede cartelle numerate

    validate_path "$file" || return 1

    if [[ -z "$file" || ! -f "$file" ]]; then
        echo -e "${RED}Errore: File non valido: '$file'${NC}" >&2
        return 1
    fi

    local filename extension basename_no_ext
    filename=$(basename "$file")
    extension="${filename##*.}"
    basename_no_ext="${filename%.*}"

    echo -e "${CYAN}Aggiunta di '$filename'...${NC}"

    local folder_name
    if [[ "$numbered" == "true" ]]; then
        local next
        next=$(get_next_number)
        folder_name=$(printf "%02d" "$next")
    else
        folder_name="$basename_no_ext"
    fi

    local dest_folder="$SD_PATH/$folder_name"

    # FIX: se la cartella esiste già, non sovrascrivere silenziosamente
    if [[ -d "$dest_folder" ]]; then
        echo -e "${RED}Errore: La cartella '$dest_folder' esiste già!${NC}" >&2
        return 1
    fi

    mkdir -p "$dest_folder"

    # Copia il file principale come disc.<ext>
    cp "$file" "$dest_folder/disc.${extension,,}"
    echo "  → disc.${extension,,}"

    local base_path="${file%.*}"

    case "${extension,,}" in
        ccd)
            for ext in img sub; do
                [[ -f "$base_path.$ext" ]] && cp "$base_path.$ext" "$dest_folder/" && echo "  → $base_path.$ext"
            done
            ;;
        mds)
            [[ -f "$base_path.mdf" ]] && cp "$base_path.mdf" "$dest_folder/" && echo "  → $base_path.mdf"
            ;;
        gdi)
            copy_gdi_tracks "$file" "$dest_folder"
            # FIX: aggiorna il .gdi copiato per usare percorsi relativi
            cp "$file" "$dest_folder/disc.gdi"
            ;;
    esac

    # Crea info.txt
    {
        echo "Title: $basename_no_ext"
        echo "Original: $filename"
        echo "Type: ${extension^^}"
        echo "Added: $(date)"
    } > "$dest_folder/info.txt"

    echo -e "${GREEN}Gioco aggiunto con successo nella cartella '$folder_name'!${NC}"

    update_gdmenu_list
    scan_sd
}

# ── Aggiungi giochi da una cartella ─────────────────────────────────────────
#
# Gestisce due layout sorgente:
#   A) File flat nella root:  /sorgente/SonicAdventure.cdi
#   B) Sottocartelle per gioco: /sorgente/Gauntlet Legends/game.cdi
#
# I due casi vengono rilevati automaticamente e non si duplicano.
# ─────────────────────────────────────────────────────────────────────────────
add_folder() {
    require_sd

    local source_dir="$1"
    local numbered="${2:-true}"

    validate_path "$source_dir" || return 1

    if [[ -z "$source_dir" || ! -d "$source_dir" ]]; then
        echo -e "${RED}Errore: Cartella sorgente non valida!${NC}" >&2
        return 1
    fi

    echo -e "${CYAN}Analisi della struttura in '$source_dir'...${NC}"

    # ── Raccoglie le "unità di gioco" da processare ──────────────────────────
    # Un'unità è o un file immagine nella root, oppure una sottocartella che
    # contiene almeno un file immagine.  Le due liste si escludono a vicenda:
    # se un file sta in una sottocartella viene contato con la sua cartella,
    # NON come file singolo.

    local -a units_type=()   # "file" o "dir"
    local -a units_path=()   # percorso assoluto

    # Prima: sottocartelle con almeno un immagine dentro (qualsiasi profondità)
    local -A subdir_seen=()
    while IFS= read -r -d $'\0' imgfile; do
        local subdir
        subdir=$(dirname "$imgfile")
        # Risali fino al figlio diretto di source_dir
        while [[ "$(dirname "$subdir")" != "$source_dir" && "$subdir" != "$source_dir" ]]; do
            subdir=$(dirname "$subdir")
        done
        if [[ "$subdir" != "$source_dir" && -z "${subdir_seen[$subdir]+x}" ]]; then
            subdir_seen["$subdir"]=1
            units_type+=("dir")
            units_path+=("$subdir")
        fi
    done < <(find "$source_dir" -mindepth 2 -type f \( \
        -iname "*.gdi" -o -iname "*.cdi" -o -iname "*.iso" \
        -o -iname "*.ccd" -o -iname "*.mds" -o -iname "*.chd" \
        \) -print0 2>/dev/null | sort -z)

    # Poi: file immagine direttamente nella root (maxdepth 1)
    while IFS= read -r -d $'\0' imgfile; do
        units_type+=("file")
        units_path+=("$imgfile")
    done < <(find "$source_dir" -maxdepth 1 -type f \( \
        -iname "*.gdi" -o -iname "*.cdi" -o -iname "*.iso" \
        -o -iname "*.ccd" -o -iname "*.mds" -o -iname "*.chd" \
        \) -print0 2>/dev/null | sort -z)

    local total=${#units_path[@]}

    if (( total == 0 )); then
        echo -e "${YELLOW}Nessun file immagine trovato nella cartella.${NC}"
        return 1
    fi

    echo -e "${GREEN}Trovati $total giochi da importare.${NC}"
    echo -e "${YELLOW}La cartella 01 è riservata per GDMenu, i giochi partiranno da 02.${NC}"
    echo ""

    local added=0 skipped=0
    local next_number
    next_number=$(get_next_number)

    for (( i=0; i<total; i++ )); do
        local unit_type="${units_type[$i]}"
        local unit_path="${units_path[$i]}"

        # Calcola il numero cartella destinazione (sempre fresco, nessun buco)
        while [[ -d "$SD_PATH/$(printf '%02d' $next_number)" ]]; do
            next_number=$(( next_number + 1 ))
        done
        local folder_name
        folder_name=$(printf "%02d" "$next_number")
        local dest_folder="$SD_PATH/$folder_name"

        echo -e "${CYAN}[$((i+1))/$total] $(basename "$unit_path") → $folder_name${NC}"

        mkdir -p "$dest_folder"

        if [[ "$unit_type" == "dir" ]]; then
            # ── Layout B: sottocartella già organizzata ──────────────────────
            # Trova il file immagine principale dentro la sottocartella
            local main_file="" main_ext=""
            for ext in gdi cdi iso ccd mds chd; do
                main_file=$(find "$unit_path" -maxdepth 2 -iname "*.$ext" -print -quit 2>/dev/null)
                [[ -n "$main_file" ]] && main_ext="$ext" && break
            done

            if [[ -z "$main_file" ]]; then
                echo -e "${YELLOW}  Nessun file immagine trovato in '$(basename "$unit_path")', salto.${NC}"
                rm -rf "$dest_folder"
                skipped=$(( skipped + 1 ))
                continue
            fi

            # Copia tutto il contenuto della sottocartella
            cp -r "$unit_path/." "$dest_folder/"

            # Rinomina il file principale in disc.<ext>
            local main_basename
            main_basename=$(basename "$main_file")
            if [[ "$main_basename" != "disc.$main_ext" ]]; then
                mv "$dest_folder/$main_basename" "$dest_folder/disc.$main_ext" 2>/dev/null || true
            fi

            # Titolo = nome della sottocartella
            local title_from_dir
            title_from_dir=$(basename "$unit_path")
            if [[ ! -f "$dest_folder/info.txt" ]]; then
                {
                    echo "Title: $title_from_dir"
                    echo "Original: $main_basename"
                    echo "Type: ${main_ext^^}"
                    echo "Added: $(date)"
                } > "$dest_folder/info.txt"
            fi

        else
            # ── Layout A: file flat nella root ───────────────────────────────
            local filename extension basename_no_ext
            filename=$(basename "$unit_path")
            extension="${filename##*.}"
            basename_no_ext="${filename%.*}"
            local base_path="${unit_path%.*}"

            cp "$unit_path" "$dest_folder/disc.${extension,,}"
            echo "  → disc.${extension,,}"

            case "${extension,,}" in
                ccd)
                    for ext in img sub; do
                        [[ -f "$base_path.$ext" ]] && cp "$base_path.$ext" "$dest_folder/" && echo "  → $(basename "$base_path.$ext")"
                    done
                    ;;
                mds)
                    [[ -f "$base_path.mdf" ]] && cp "$base_path.mdf" "$dest_folder/" && echo "  → $(basename "$base_path.mdf")"
                    ;;
                gdi)
                    copy_gdi_tracks "$unit_path" "$dest_folder"
                    cp "$unit_path" "$dest_folder/disc.gdi"
                    ;;
            esac

            {
                echo "Title: $basename_no_ext"
                echo "Original: $filename"
                echo "Type: ${extension^^}"
                echo "Added: $(date)"
            } > "$dest_folder/info.txt"
        fi

        echo -e "${GREEN}  ✓ Aggiunto in '$folder_name'${NC}"
        added=$(( added + 1 ))
        next_number=$(( next_number + 1 ))
    done

    echo ""
    echo -e "${GREEN}Importati $added giochi con successo!${NC}"
    (( skipped > 0 )) && echo -e "${YELLOW}Saltati: $skipped${NC}"

    update_gdmenu_list
    scan_sd
}

# ── Rimuovi un gioco ─────────────────────────────────────────────────────────
remove_game() {
    if [[ ! -f "$GAMES_LIST_FILE" || ! -s "$GAMES_LIST_FILE" ]]; then
        echo -e "${YELLOW}Nessun gioco trovato. Esegui prima: $0 scan${NC}"
        return 1
    fi

    local number="$1"

    if [[ -z "$number" ]]; then
        echo -e "${RED}Errore: Numero di gioco non specificato!${NC}" >&2
        return 1
    fi

    local game_found=false
    while IFS='|' read -r num path title type size size_str file; do
        if [[ "$num" == "$number" ]]; then
            game_found=true

            echo -e "${YELLOW}Rimozione: [$num] $title${NC}"

            # Rimozione diretta senza conferma interattiva
            # FIX: controllo che il path sia dentro SD_PATH prima di rm -rf
            local real_sd real_path
            real_sd=$(realpath "$SD_PATH")
            real_path=$(realpath "$path" 2>/dev/null || echo "")

            if [[ -n "$real_path" && "$real_path" == "$real_sd"/* && "$(basename "$real_path")" != "/" ]]; then
                rm -rf "$path"
                echo -e "${GREEN}Gioco rimosso con successo!${NC}"
                update_gdmenu_list
            else
                echo -e "${RED}Errore: Percorso non sicuro, operazione annullata!${NC}" >&2
            fi
            scan_sd
            break
        fi
    done < "$GAMES_LIST_FILE"

    [[ "$game_found" == false ]] && echo -e "${RED}Errore: Nessun gioco trovato con numero $number!${NC}" >&2
}

# ── Rinomina un gioco ────────────────────────────────────────────────────────
rename_game() {
    if [[ ! -f "$GAMES_LIST_FILE" || ! -s "$GAMES_LIST_FILE" ]]; then
        echo -e "${YELLOW}Nessun gioco trovato. Esegui prima: $0 scan${NC}"
        return 1
    fi

    local number="$1"
    local new_title="$2"

    if [[ -z "$number" || -z "$new_title" ]]; then
        echo -e "${RED}Errore: Parametri insufficienti! Uso: $0 rename <numero> \"Nuovo Titolo\"${NC}" >&2
        return 1
    fi

    local game_found=false
    while IFS='|' read -r num path title type size size_str file; do
        if [[ "$num" == "$number" ]]; then
            game_found=true

            if [[ -f "$path/info.txt" ]]; then
                sed -i "s/^Title:.*$/Title: $new_title/" "$path/info.txt"
            else
                echo "Title: $new_title" > "$path/info.txt"
            fi

            echo -e "${GREEN}Gioco rinominato: '$title' → '$new_title'${NC}"
            update_gdmenu_list
            scan_sd
            break
        fi
    done < "$GAMES_LIST_FILE"

    [[ "$game_found" == false ]] && echo -e "${RED}Errore: Nessun gioco trovato con numero $number!${NC}" >&2
}

# ── Riorganizza numericamente i giochi ──────────────────────────────────────
reorder_games() {
    require_sd

    if [[ ! -f "$GAMES_LIST_FILE" || ! -s "$GAMES_LIST_FILE" ]]; then
        echo -e "${YELLOW}Nessun gioco trovato. Esegui prima: $0 scan${NC}"
        return 1
    fi

    echo -e "${CYAN}Riordinamento delle cartelle in corso...${NC}"

    local tmp_dir="$TEMP_DIR/reorder_tmp"
    mkdir -p "$tmp_dir"

    local counter=2
    while IFS='|' read -r num path title type size size_str file; do
        [[ "$num" == "01" ]] && continue

        local new_num
        new_num=$(printf "%02d" $counter)
        local new_path="$tmp_dir/$new_num"

        echo -e "  $num → $new_num: $title"
        mkdir -p "$new_path"

        # FIX: usa cp + rm invece di mv per evitare cross-device issues
        cp -a "$path/." "$new_path/"

        counter=$(( counter + 1 ))
    done < <(sort -t'|' -k1,1n "$GAMES_LIST_FILE")

    # FIX: rimuovi solo le cartelle dei giochi, non la 01
    while IFS='|' read -r num path _rest; do
        [[ "$num" == "01" ]] && continue
        [[ -d "$path" ]] && rm -rf "$path"
    done < "$GAMES_LIST_FILE"

    # Sposta le cartelle riordinate
    while IFS= read -r -d $'\0' dir; do
        local new_num
        new_num=$(basename "$dir")
        cp -a "$dir/." "$SD_PATH/$new_num/"
        rm -rf "$dir"
    done < <(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

    rm -rf "$tmp_dir"

    echo -e "${GREEN}Riordinamento completato!${NC}"
    update_gdmenu_list
    scan_sd
}

# ── Converti cartelle in formato numerico ────────────────────────────────────
convert_to_numbered() {
    require_sd

    echo -e "${CYAN}Conversione delle cartelle in formato numerico...${NC}"
    echo -e "${YELLOW}La cartella 01 è riservata per GDMenu.${NC}"

    local tmp_dir="$TEMP_DIR/numbered_tmp"
    mkdir -p "$tmp_dir"

    local folders=()
    while IFS= read -r -d $'\0' folder; do
        local fname
        fname=$(basename "$folder")
        # Ignora cartelle di sistema (Trash, spotlight, ecc.)
        [[ "$fname" == .* ]] && continue
        [[ "$fname" == "System Volume Information" ]] && continue
        [[ "$fname" == "RECYCLER" || "$fname" == '$RECYCLE.BIN' ]] && continue
        folders+=("$folder")
    done < <(find "$SD_PATH" -maxdepth 1 -mindepth 1 -type d -print0 | sort -z)

    if (( ${#folders[@]} == 0 )); then
        echo -e "${YELLOW}Nessuna cartella trovata nella SD Card.${NC}"
        return 1
    fi

    local counter=2
    for folder in "${folders[@]}"; do
        local folder_name
        folder_name=$(basename "$folder")

        # Salta 01 e cartelle già in formato numerico a 2 cifre sequenziali
        [[ "$folder_name" == "01" ]] && continue

        local new_folder
        new_folder=$(printf "%02d" $counter)
        echo -e "  $folder_name → $new_folder"

        mkdir -p "$tmp_dir/$new_folder"
        cp -a "$folder/." "$tmp_dir/$new_folder/"

        # Preserva o crea info.txt con il titolo originale
        if [[ -f "$tmp_dir/$new_folder/info.txt" ]]; then
            sed -i "s/^Title:.*$/Title: $folder_name/" "$tmp_dir/$new_folder/info.txt"
        else
            echo "Title: $folder_name" > "$tmp_dir/$new_folder/info.txt"
        fi

        counter=$(( counter + 1 ))
    done

    # Rimuovi cartelle originali (esclusa 01)
    for folder in "${folders[@]}"; do
        [[ "$(basename "$folder")" == "01" ]] && continue
        rm -rf "$folder"
    done

    # Copia le nuove cartelle
    find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | sort | while read -r dir; do
        cp -a "$dir/." "$SD_PATH/$(basename "$dir")/"
    done

    rm -rf "$tmp_dir"

    echo -e "${GREEN}Conversione completata!${NC}"
    update_gdmenu_list
    scan_sd
}

# ── Installazione di GDMenu ──────────────────────────────────────────────────
install_openmenu() {
    require_sd

    local openmenu_archive="gdmenu.tar.gz"

    if [[ ! -f "$openmenu_archive" ]]; then
        echo -e "${RED}Errore: File '$openmenu_archive' non trovato nella directory corrente!${NC}" >&2
        return 1
    fi

    echo -e "${CYAN}Installazione di GDMenu nella cartella 01...${NC}"

    local temp_extract="$TEMP_DIR/openmenu_extract"
    mkdir -p "$temp_extract"

    if ! tar -xzf "$openmenu_archive" -C "$temp_extract"; then
        echo -e "${RED}Errore durante l'estrazione dell'archivio!${NC}" >&2
        return 1
    fi

    if [[ -d "$temp_extract/01" ]]; then
        mkdir -p "$SD_PATH/01"
        rm -rf "${SD_PATH:?}/01/"*   # FIX: aggiunto :? per sicurezza con rm -rf
        cp -r "$temp_extract/01/"* "$SD_PATH/01/"
        echo -e "${GREEN}GDMenu installato nella cartella 01!${NC}"
    else
        echo -e "${RED}Errore: Struttura imprevista nell'archivio. La cartella 01 non è stata trovata.${NC}" >&2
        ls -la "$temp_extract"
        return 1
    fi
}

# ── Crea GDEMU.ini ───────────────────────────────────────────────────────────
create_gdemu_ini() {
    require_sd

    echo -e "${CYAN}Creazione del file GDEMU.ini...${NC}"

    cat > "$SD_PATH/GDEMU.ini" << 'EOF'
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

    echo -e "${GREEN}File GDEMU.ini creato!${NC}"
}

# ── Ricava il titolo leggibile di una cartella gioco ────────────────────────
# Priorità: 1) info.txt  2) nome file disc.EXT originale (non "disc")
#            3) nome cartella genitore nella sorgente (se disponibile)
#            4) fallback "Game NN"
get_game_title() {
    local folder="$1"
    local folder_num
    folder_num=$(basename "$folder")
    local title=""

    # 1. Leggi info.txt
    if [[ -f "$folder/info.txt" ]]; then
        title=$(grep -i "^Title:" "$folder/info.txt" | sed 's/^Title:[[:space:]]*//i' | head -1 | tr -d '\r')
        # Ignora il titolo se è solo il nome del file disc (es. "disc" o "disc.gdi")
        [[ "$title" =~ ^[Dd]isc(\.[a-zA-Z]+)?$ ]] && title=""
    fi

    # 2. Cerca il campo "Original:" in info.txt (nome file prima della copia)
    if [[ -z "$title" && -f "$folder/info.txt" ]]; then
        local orig
        orig=$(grep -i "^Original:" "$folder/info.txt" | sed 's/^Original:[[:space:]]*//i' | head -1 | tr -d '\r')
        if [[ -n "$orig" ]]; then
            # Rimuovi estensione
            title="${orig%.*}"
            # Rimuovi tag come [RDC], [DCCM], [DCRES], [replayers.org] ecc.
            title=$(echo "$title" | sed 's/\[[^]]*\]//g' | sed 's/(USA)//i' | sed 's/(EUR)//i' | sed 's/(JAP)//i' | sed 's/(Europe)//i' | sed 's/(Japan)//i' | xargs)
        fi
    fi

    # 3. Fallback al numero cartella
    [[ -z "$title" ]] && title="Game $folder_num"

    # Sanifica: solo ASCII, max 32 caratteri, maiuscolo
    title=$(echo "$title" | iconv -f utf-8 -t ascii//TRANSLIT 2>/dev/null | tr -cd 'A-Za-z0-9 .()\-_' | sed 's/  */ /g' | xargs)
    title=$(echo "$title" | tr '[:lower:]' '[:upper:]')
    title="${title:0:32}"

    echo "$title"
}

# ── Genera list.ini per GDMenu ───────────────────────────────────────────────
#
# NOTA CRITICA sul formato ISO:
#   GDMenu legge list.ini dall'ISO con filesystem ISO9660 + Joliet (-J).
#   Senza -J i nomi vengono convertiti in 8.3 maiuscolo e list.ini diventa
#   "LIST.INI" che alcune versioni di GDMenu non trovano.
#   Con -J i nomi lunghi vengono preservati correttamente.
#   NON usare -r (Rock Ridge) perché aggiunge estensioni POSIX non necessarie.
# ─────────────────────────────────────────────────────────────────────────────
update_gdmenu_list() {
    require_sd

    if [[ ! -f "$SD_PATH/01/track01.iso" ]]; then
        echo -e "${YELLOW}Attenzione: File track01.iso non trovato in 01/, salto aggiornamento menu.${NC}"
        echo -e "${YELLOW}Esegui prima 'init' per installare GDMenu.${NC}"
        return 1
    fi

    echo -e "${CYAN}Aggiornamento del menu GDMenu...${NC}"

    local temp_iso="$TEMP_DIR/track01_temp.iso"
    local temp_mount="$TEMP_DIR/gdmenu_temp"
    local temp_files="$TEMP_DIR/gdmenu_files"

    cp "$SD_PATH/01/track01.iso" "$temp_iso"
    mkdir -p "$temp_mount" "$temp_files"

    if ! sudo mount -o loop "$temp_iso" "$temp_mount" 2>/dev/null; then
        echo -e "${RED}Errore: Impossibile montare l'ISO. Servono privilegi sudo.${NC}" >&2
        echo -e "${YELLOW}Riprova con: sudo $0 menu${NC}"
        rm -f "$temp_iso"
        return 1
    fi

    # Copia tutti i file esistenti dell'ISO con permessi scrivibili
    # (i file nell'ISO montato sono read-only; senza chmod list.ini non è sovrascrivibile)
    cp -r "$temp_mount"/. "$temp_files/"
    sudo umount "$temp_mount"
    rmdir "$temp_mount" 2>/dev/null || true
    # Rendi tutto scrivibile nella directory temporanea
    chmod -R u+w "$temp_files/" 2>/dev/null || true

    # ── Genera list.ini ──────────────────────────────────────────────────────
    # Il file DEVE avere line endings Unix (LF), non CRLF
    {
        printf '[GDMENU]\n'
        printf '01.name=GDMENU\n'
        printf '01.disc=1/1\n'
        printf '01.vga=1\n'
        printf '01.region=JUE\n'
        printf '01.version=V0.6.0\n'
        printf '01.date=20160812\n'
        printf '\n'
    } > "$temp_files/list.ini"

    local entry_count=0

    while IFS= read -r -d $'\0' folder; do
        local folder_num
        folder_num=$(basename "$folder")
        [[ "$folder_num" == "01" ]] && continue

        # Assicurati che la cartella abbia un info.txt aggiornato
        # (le cartelle GDI aggiunte manualmente o copiate potrebbero non averlo)
        if [[ ! -f "$folder/info.txt" ]]; then
            local disc_file
            disc_file=$(find "$folder" -maxdepth 1 -name "disc.*" -print -quit 2>/dev/null)
            if [[ -n "$disc_file" ]]; then
                local disc_ext="${disc_file##*.}"
                {
                    echo "Title: $(basename "$disc_file")"
                    echo "Original: $(basename "$disc_file")"
                    echo "Type: ${disc_ext^^}"
                    echo "Added: $(date)"
                } > "$folder/info.txt"
            fi
        fi

        local game_title
        game_title=$(get_game_title "$folder")

        # Regione (controllata sul titolo originale non-maiuscolo per sicurezza)
        local raw_title=""
        [[ -f "$folder/info.txt" ]] && raw_title=$(grep -i "^Original:" "$folder/info.txt" | head -1)
        local game_region="JUE"
        [[ "$raw_title" =~ [Uu][Ss][Aa] ]]                        && game_region="U"
        [[ "$raw_title" =~ [Ee][Uu][Rr] || "$raw_title" =~ [Ee]urope ]] && game_region="E"
        [[ "$raw_title" =~ [Jj][Aa][Pp] || "$raw_title" =~ [Jj]apan ]]  && game_region="J"

        {
            printf '%s.name=%s\n'    "$folder_num" "$game_title"
            printf '%s.disc=1/1\n'  "$folder_num"
            printf '%s.vga=1\n'     "$folder_num"
            printf '%s.region=%s\n' "$folder_num" "$game_region"
            printf '%s.version=V1.000\n' "$folder_num"
            printf '%s.date=%s\n'   "$folder_num" "$(date +%Y%m%d)"
            printf '\n'
        } >> "$temp_files/list.ini"

        echo "  → $folder_num: $game_title  [$game_region]"
        entry_count=$(( entry_count + 1 ))

    done < <(find "$SD_PATH" -maxdepth 1 -mindepth 1 -type d -name "[0-9][0-9]*" -print0 | sort -z)

    printf 'Generated by SDREAM v%s\n' "$VERSION" > "$temp_files/gdemuinfo.txt"

    # ── Ricrea track01.iso ───────────────────────────────────────────────────
    local iso_tool=""
    command -v genisoimage &>/dev/null && iso_tool="genisoimage"
    command -v mkisofs    &>/dev/null && iso_tool="${iso_tool:-mkisofs}"

    if [[ -z "$iso_tool" ]]; then
        echo -e "${RED}Errore: genisoimage o mkisofs non trovati!${NC}" >&2
        echo -e "${YELLOW}Installa con: sudo apt-get install genisoimage${NC}"
        rm -rf "$temp_files" "$temp_iso"
        return 1
    fi

    # Flag:
    #  -J          = Joliet (nomi lunghi, preserva "list.ini" minuscolo)
    #  -iso-level 2 = nomi fino a 31 caratteri in ISO9660 base
    #  -input-charset utf-8 = evita corruzione nomi con caratteri speciali
    #  NON usare -r (Rock Ridge) — non necessario per Dreamcast
    if ! "$iso_tool" -quiet \
            -J \
            -iso-level 2 \
            -input-charset utf-8 \
            -o "$SD_PATH/01/track01.iso" \
            "$temp_files/" 2>/tmp/iso_err_$$; then
        echo -e "${RED}Errore nella creazione dell'ISO:${NC}" >&2
        cat /tmp/iso_err_$$ >&2
        rm -f /tmp/iso_err_$$
        rm -rf "$temp_files" "$temp_iso"
        return 1
    fi
    rm -f /tmp/iso_err_$$

    rm -rf "$temp_files" "$temp_iso"

    echo -e "${GREEN}Menu GDMenu aggiornato: $entry_count giochi.${NC}"
}

# ── Monta ISO GDMenu (utility interna) ───────────────────────────────────────
mount_gdmenu_iso() {
    local mount_point="$TEMP_DIR/gdmenu_mount"
    local iso_file="$SD_PATH/01/track01.iso"

    [[ ! -f "$iso_file" ]] && echo -e "${RED}Errore: track01.iso non trovato!${NC}" >&2 && return 1

    mkdir -p "$mount_point"
    if ! sudo mount -o loop "$iso_file" "$mount_point" 2>/dev/null; then
        echo -e "${RED}Errore: Impossibile montare track01.iso (sudo richiesto).${NC}" >&2
        return 1
    fi
    echo "$mount_point"
}

umount_gdmenu_iso() {
    local mount_point="$1"
    if [[ -n "$mount_point" ]] && mountpoint -q "$mount_point" 2>/dev/null; then
        sudo umount "$mount_point"
        rmdir "$mount_point" 2>/dev/null || true
    fi
}

# ── Genera menu.lst (compatibilità) ─────────────────────────────────────────
generate_menu_lst() {
    require_sd

    echo -e "${CYAN}Generazione del file menu.lst...${NC}"
    > "$SD_PATH/menu.lst"

    [[ -d "$SD_PATH/01" ]] && printf '01 GDMenu\r\n' > "$SD_PATH/menu.lst"

    while IFS= read -r -d $'\0' folder; do
        local folder_num
        folder_num=$(basename "$folder")
        [[ "$folder_num" == "01" ]] && continue

        local title=""
        [[ -f "$folder/info.txt" ]] && title=$(grep -i "^Title:" "$folder/info.txt" | sed 's/^Title:[[:space:]]*//i' | head -1)

        if [[ -z "$title" ]]; then
            local gf
            gf=$(find "$folder" -maxdepth 1 -name "disc.*" -print -quit 2>/dev/null)
            [[ -n "$gf" ]] && title=$(basename "$gf" | sed 's/^disc\.//' | sed 's/\.[^.]*$//') || title="Game $folder_num"
        fi

        title=$(echo "$title" | iconv -f utf-8 -t ascii//TRANSLIT 2>/dev/null | tr -cd 'A-Za-z0-9 .()\-')
        title="${title:0:32}"

        printf '%s %s\r\n' "$folder_num" "$title" >> "$SD_PATH/menu.lst"
        echo "  → $folder_num $title"

    done < <(find "$SD_PATH" -maxdepth 1 -mindepth 1 -type d -name "[0-9][0-9]*" -print0 | sort -z)

    echo -e "${GREEN}File menu.lst generato!${NC}"
}

# ── Inizializza SD Card ──────────────────────────────────────────────────────
init_sd() {
    require_sd

    echo -e "${CYAN}Inizializzazione della SD Card per GDEMU...${NC}"
    install_openmenu
    create_gdemu_ini
    update_gdmenu_list
    echo -e "${GREEN}Inizializzazione completata!${NC}"
    scan_sd
}


# ── Ripara info.txt mancanti o con titoli "disc" ────────────────────────────
fix_titles() {
    require_sd

    echo -e "${CYAN}Verifica e riparazione dei titoli nella SD Card...${NC}"
    local fixed=0 ok=0

    while IFS= read -r -d $'\0' folder; do
        local folder_num
        folder_num=$(basename "$folder")
        [[ "$folder_num" == "01" ]] && continue

        local needs_fix=false reason=""

        if [[ ! -f "$folder/info.txt" ]]; then
            needs_fix=true; reason="info.txt mancante"
        else
            local current_title
            current_title=$(grep -i "^Title:" "$folder/info.txt" | sed 's/^Title:[[:space:]]*//i' | head -1 | tr -d '\r')
            if [[ -z "$current_title" || "$current_title" =~ ^[Dd]isc(\.[a-zA-Z]+)?$ ]]; then
                needs_fix=true; reason="titolo non valido: '$current_title'"
            fi
        fi

        if [[ "$needs_fix" == true ]]; then
            local disc_file="" ext=""
            disc_file=$(find "$folder" -maxdepth 1 -name "disc.*" -print -quit 2>/dev/null)
            ext="${disc_file##*.}"

            local orig_title=""
            [[ -f "$folder/info.txt" ]] && orig_title=$(grep -i "^Original:" "$folder/info.txt" | sed 's/^Original:[[:space:]]*//i' | head -1 | tr -d '\r' | sed 's/\.[^.]*$//' | sed 's/\[[^]]*\]//g' | xargs)

            local new_title="${orig_title:-Game $folder_num}"

            if [[ -f "$folder/info.txt" ]]; then
                if grep -qi "^Title:" "$folder/info.txt"; then
                    sed -i "s/^[Tt]itle:.*$/Title: $new_title/" "$folder/info.txt"
                else
                    sed -i "1s/^/Title: $new_title\n/" "$folder/info.txt"
                fi
            else
                {
                    echo "Title: $new_title"
                    echo "Original: $(basename "${disc_file:-disc}")"
                    echo "Type: ${ext^^}"
                    echo "Added: $(date)"
                } > "$folder/info.txt"
            fi

            echo -e "  ${YELLOW}$folder_num${NC}: $reason → ${GREEN}$new_title${NC}"
            fixed=$(( fixed + 1 ))
        else
            local t
            t=$(grep -i "^Title:" "$folder/info.txt" | sed 's/^Title:[[:space:]]*//i' | head -1 | tr -d '\r')
            echo -e "  ${GREEN}$folder_num${NC}: OK → $t"
            ok=$(( ok + 1 ))
        fi

    done < <(find "$SD_PATH" -maxdepth 1 -mindepth 1 -type d -name "[0-9][0-9]*" -print0 | sort -z)

    echo ""
    echo -e "${GREEN}OK: $ok  Corretti: $fixed${NC}"
    (( fixed > 0 )) && update_gdmenu_list
}

# ── Guida ────────────────────────────────────────────────────────────────────
show_help() {
    echo ""
    echo -e "${BOLD}${CYAN}  SDREAM v${VERSION}${NC} — Gestore immagini Dreamcast per GDEMU"
    echo -e "  by B3LZ3BU · rymstudio 2025"
    echo ""
    echo -e "${BOLD}  Comandi disponibili:${NC}"
    echo ""
    printf "  ${GREEN}%-30s${NC} %s\n" "set-sd <percorso>"         "Imposta la directory della SD Card"
    printf "  ${GREEN}%-30s${NC} %s\n" "scan"                      "Scansiona la SD Card"
    printf "  ${GREEN}%-30s${NC} %s\n" "list"                      "Mostra la lista dei giochi"
    printf "  ${GREEN}%-30s${NC} %s\n" "init"                      "Inizializza la SD Card con GDMenu"
    printf "  ${GREEN}%-30s${NC} %s\n" "add <file> [true|false]"   "Aggiunge un gioco (default: numerato)"
    printf "  ${GREEN}%-30s${NC} %s\n" "add-folder <dir> [true]"   "Aggiunge tutti i giochi da una cartella"
    printf "  ${GREEN}%-30s${NC} %s\n" "remove <numero>"           "Rimuove un gioco"
    printf "  ${GREEN}%-30s${NC} %s\n" "rename <numero> \"Nome\""  "Rinomina un gioco"
    printf "  ${GREEN}%-30s${NC} %s\n" "reorder"                   "Riordina numericamente le cartelle"
    printf "  ${GREEN}%-30s${NC} %s\n" "numbered"                  "Converte cartelle in formato numerico"
    printf "  ${GREEN}%-30s${NC} %s\n" "menu"                      "Rigenera il menu GDMenu (richiede sudo)"
    printf "  ${GREEN}%-30s${NC} %s\n" "fix-titles"                "Ripara titoli mancanti o non validi"
    printf "  ${GREEN}%-30s${NC} %s\n" "help"                      "Mostra questa guida"
    echo ""
    echo -e "${BOLD}  Esempi:${NC}"
    echo "    $0 set-sd /media/sdcard"
    echo "    $0 init"
    echo "    $0 add \"/path/to/SonicAdventure.gdi\" true"
    echo "    $0 add-folder /path/games/"
    echo "    sudo $0 menu"
    echo ""
    echo -e "${BOLD}  Note:${NC}"
    echo "    · I file principali vengono rinominati in 'disc.ext' per GDEMU"
    echo "    · La cartella 01 è riservata per GDMenu"
    echo "    · I comandi 'menu' e 'init' richiedono sudo (montaggio ISO)"
    echo "    · 'fix-titles' ripara SD preparate senza info.txt corretti"
    echo "    · Dipendenze: genisoimage oppure mkisofs"
    echo ""
}

# ── Dispatcher ───────────────────────────────────────────────────────────────
case "${1:-}" in
    set-sd)
        [[ -z "${2:-}" ]] && echo -e "${RED}Errore: Percorso non specificato!${NC}" && exit 1
        set_sd "$2"
        ;;
    init)
        init_sd
        ;;
    scan)
        scan_sd
        ;;
    list)
        scan_sd
        list_games
        ;;
    add)
        [[ -z "${2:-}" ]] && echo -e "${RED}Errore: File non specificato!${NC}" && exit 1
        add_game "$2" "${3:-true}"
        ;;
    add-folder)
        [[ -z "${2:-}" ]] && echo -e "${RED}Errore: Cartella non specificata!${NC}" && exit 1
        add_folder "$2" "${3:-true}"
        ;;
    remove)
        remove_game "${2:-}"
        ;;
    rename)
        rename_game "${2:-}" "${3:-}"
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
    fix-titles)
        fix_titles
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        show_help
        ;;
esac
