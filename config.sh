# shellcheck shell=bash
DEFAULT_BACKUPS_PATH="${HOME}/Backups"
DEFAULT_PC_KP_PATH="${HOME}/.keepass/keepassdb.kdbx"
DEFAULT_PHONE_KP_PATH="/sdcard/.keepass/keepassdb.kdbx"
DEFAULT_PHONE_AEGIS_PATH="/sdcard/aegis_backups"
DEFAULT_KEEP_COUNT=5

CONFIG_DIR="${HOME}/.config/sync-aegis-keepass"
CONFIG_FILE="${CONFIG_DIR}/config"


create_default_config() {
    mkdir -p "$CONFIG_DIR"
    cat << EOF > "$CONFIG_FILE"
# Путь к каталогу со всеми бэкапами
BACKUPS_PATH="${DEFAULT_BACKUPS_PATH}"

# Путь к базе паролей keepass на пк
PC_KP_PATH="${DEFAULT_PC_KP_PATH}"

# Путь к базе паролей keepass на android
PHONE_KP_PATH="${DEFAULT_PHONE_KP_PATH}"

# Путь к каталогу с бэкапами Aegis на android
PHONE_AEGIS_PATH="${DEFAULT_PHONE_AEGIS_PATH}"

# Кол-во сохраняемых файлов (если их больше, то самые старые - удаляются)
KEEP_COUNT=${DEFAULT_KEEP_COUNT}
EOF
}


# Задать конфигу значения по умолчанию
reset_config() {
    read -p "Сбросить настройки? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        create_default_config
        echo "[N] Файл config сброшен!"
    else
        echo "[N] Сброс файла config отменён!"
    fi
}


# Вызвать редактор для редактирования конфига
edit_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        create_default_config
    fi

    local oldtime
    oldtime=$(stat -c %Y "$CONFIG_FILE")
    "${EDITOR:-nano}" "$CONFIG_FILE"

    if [[ $(stat -c %Y "$CONFIG_FILE") -gt $oldtime ]]; then
        echo "[N] Файл config отредактирован!"
    else
        echo "[N] Файл config не был отредактирован!"
    fi
}


# Загрузить конфиг
load_config() {
    if [[ -f "${CONFIG_FILE}" ]]; then
        . "${CONFIG_FILE}"
    else
        BACKUPS_PATH="${DEFAULT_BACKUPS_PATH}"
        PC_KP_PATH="${DEFAULT_PC_KP_PATH}"
        PHONE_KP_PATH="${DEFAULT_PHONE_KP_PATH}"
        PHONE_AEGIS_PATH="${DEFAULT_PHONE_AEGIS_PATH}"
        KEEP_COUNT=${DEFAULT_KEEP_COUNT}
    fi

    BACKUPS_AEGIS_PATH="${BACKUPS_PATH}/Aegis"
    BACKUPS_KP_PATH="${BACKUPS_PATH}/KeePass"
    TEMP_KP_PATH="${BACKUPS_PATH}/temp.kdbx"
    CANARY_FILE="${BACKUPS_PATH}/.canary.enc"
    CANARY_TOKEN="VERIFY_SECRET_TOKEN_V1"
}
