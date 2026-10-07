# shellcheck shell=bash
# Гарантированная очистка временных файлов
trap 'rm -f "${TEMP_KP_PATH}"' EXIT


# Задержка перед выходом
# 1 - код работы программы
pause_and_exit() {
    echo ; read -rp "Нажмите Enter, чтобы выйти..."
    exit "${1:-0}"
}


# Проверки перед основной работой скрипта
check_dependencies() {
    # Проверка наличия необходимых утилит
    local deps=("adb" "keepassxc-cli" "7z")
    local missing=()
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    if [ ${#missing[@]} -ne 0 ]; then
        echo "[E] Отсутствуют необходимые утилиты: ${missing[*]}"
        pause_and_exit 1
    fi
    mkdir -p "$BACKUPS_KP_PATH"
    mkdir -p "$BACKUPS_AEGIS_PATH"
}


# Проверка подключения abd
check_adb() {
    if ! adb -d get-state >/dev/null 2>&1; then
        echo "[E] Устройство не подключено по adb -d или не авторизовано."
        pause_and_exit 1
    fi
}


# Извлечение файлов с обработкой ошибок
# 1 - сообщение; 2 - путь на телефоне; 3 - путь на пк.
adb_pull_new() {
    check_adb
    echo "[N] ${1}..."
    if ! adb -d pull "${2}" "${3}"; then
        echo "[E] Ошибка при скачивании файлов через adb -d."
        pause_and_exit 1
    fi
}


# Очистка старых файлов
# 1 - каталог; 2 - начало имени файлов; 3 - конец имени файлов.
clear_old_files() {
    mkdir -p "$1"
    # Включаем nullglob, чтобы при отсутствии файлов массив оставался пустым
    shopt -s nullglob
    local files=("${1}/${2}"*"${3}")
    shopt -u nullglob
    local total_files=${#files[@]}
    if [ "$total_files" -gt "$KEEP_COUNT" ]; then
        for (( i=0; i<total_files-KEEP_COUNT; i++ )); do
            rm -f "${files[$i]}"
        done
    fi
}


# Синхронизация бэкапов Aegis
sync_aegis() {
    check_adb
    adb_pull_new "Копирование бэкапов Aegis на пк" "$PHONE_AEGIS_PATH/." "$BACKUPS_AEGIS_PATH/"
    clear_old_files "$BACKUPS_AEGIS_PATH" "aegis-backup-" ".json"
}


# Слияние баз KeePass на пк
sync_keepass_1() {
    check_adb
    adb_pull_new "Скачивание базы KeePass с телефона" "$PHONE_KP_PATH" "$TEMP_KP_PATH"
    echo "[N] Сохранение старой базы KeePass на пк..."
    cp -v "$PC_KP_PATH" "${PC_KP_PATH%.*}.old.${PC_KP_PATH##*.}"
    echo "[N] Слияние баз KeePass..."
    while true; do
        # Исправить: вызывать break после конкретной ошибки и возвращать exit 1
        if keepassxc-cli merge -s "$PC_KP_PATH" "$TEMP_KP_PATH"; then
            break
        fi
    done
}


# Синхронизация базы KeePass на телефон и создание бэкапа
sync_keepass_2() {
    check_adb
    echo "[N] Сохранение старой базы KeePass на телефоне..."
    if ! adb -d shell cp -v "$PHONE_KP_PATH" "${PHONE_KP_PATH%.*}.old.${PHONE_KP_PATH##*.}"; then
        echo "[E] Ошибка при записи на телефон."
        pause_and_exit 1
    fi
    echo "[N] Синхронизация базы KeePass на телефон..."
    if ! adb -d push "$PC_KP_PATH" "$PHONE_KP_PATH"; then
        echo "[E] Ошибка при записи на телефон."
        pause_and_exit 1
    fi
    echo "[N] Создание бэкапа KeePass..."
    cp -v "$PC_KP_PATH" "$BACKUPS_KP_PATH/keepass-backup-$(date +%Y%m%d-%H%M%S).kdbx"
    clear_old_files "$BACKUPS_KP_PATH" "keepass-backup-" ".kdbx"
}


# Слияние и синхронизация KeePass
sync_keepass() {
    sync_keepass_1
    read -r -p "Нажмите Enter, чтобы продолжить..."
    sync_keepass_2
}


# Создание канарейки
create_canary() {
    local pass
    local pass_confirm
    read -rsp "Задайте пароль для архива: " pass ; echo
    read -rsp "Повторите пароль: " pass_confirm ; echo
    if [[ "${pass}" != "${pass_confirm}" ]]; then
        echo "[E] Введённые пароли не совпадают."
        pause_and_exit 1
    fi
    PASSPHRASE="${pass}" openssl enc -aes-256-cbc -pbkdf2 -iter 100000 \
        -pass env:PASSPHRASE \
        -in <(echo -n "${CANARY_TOKEN}") \
        -out "${CANARY_FILE}"
    chmod 600 "${CANARY_FILE}"
    echo "Файл канарейки создан в ${CANARY_FILE}"
}


# Архивирование бэкапов
create_archive() {
    if [[ ! -f "$CANARY_FILE" ]]; then
        echo "[N] Пароль не задан, задайте его."
        create_canary
    fi
    local pass
    while true; do
        read -rsp "Введите пароль для архива: " pass ; echo
        # Проверка пароля на корректность
        local decrypted
        decrypted=$(PASSPHRASE="${pass}" openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
            -pass env:PASSPHRASE -in "$CANARY_FILE" 2>/dev/null | LC_ALL=C tr -d '\0' || true)
        if [[ "$decrypted" == "$CANARY_TOKEN" ]]; then
            break
        else
            echo "[N] Введён неверный пароль, попробуйте снова."
        fi
    done
    printf '%s\n' "$pass" | 7z a -mhe=on -p "${BACKUPS_PATH}/backups-archive-$(date +%Y%m%d-%H%M%S).7z" \
        "$BACKUPS_PATH"/*/ >/dev/null
    clear_old_files "$BACKUPS_PATH" "backups-archive-" ".7z"
}
