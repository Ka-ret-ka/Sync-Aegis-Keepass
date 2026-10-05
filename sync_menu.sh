#!/bin/bash
set -euo pipefail

# Путь к каталогу со всеми бэкапами
BACKUPS_PATH="${HOME}/Backups" 
# Путь к базе паролей keepass на пк
PC_KP_PATH="${HOME}/.keepass/keepassdb.kdbx"
# Путь к базе паролей keepass на android
PHONE_KP_PATH="/sdcard/.keepass/keepassdb.kdbx"
# Путь к каталогу с бэкапами Aegis на android
PHONE_AEGIS_PATH="/sdcard/aegis_backups"
# Кол-во сохраняемых файлов (если их больше, то самые старые - удаляются)
KEEP_COUNT=5

BACKUPS_AEGIS_PATH="${BACKUPS_PATH}/Aegis"
BACKUPS_KP_PATH="${BACKUPS_PATH}/KeePass"
TEMP_KP_PATH="${BACKUPS_PATH}/temp.kdbx"
CANARY_FILE="${BACKUPS_PATH}/.canary.enc"
CANARY_TOKEN="VERIFY_SECRET_TOKEN_V1"

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
    # Проверка подключения abd
    if ! adb -d get-state >/dev/null 2>&1; then
        echo "[E] Устройство не подключено по adb -d или не авторизовано."
        pause_and_exit 1
    fi
    mkdir -p "$BACKUPS_KP_PATH"
    mkdir -p "$BACKUPS_AEGIS_PATH"
}


# Извлечение файлов с обработкой ошибок
# 1 - сообщение; 2 - путь на телефоне; 3 - путь на пк.
adb_pull_new() {
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
    adb_pull_new "Копирование бэкапов Aegis на пк" "$PHONE_AEGIS_PATH/." "$BACKUPS_AEGIS_PATH/"
    clear_old_files "$BACKUPS_AEGIS_PATH" "aegis-backup-" ".json"
}


# Слияние баз KeePass на пк
sync_keepass_1() {
    adb_pull_new "Скачивание базы KeePass с телефона" "$PHONE_KP_PATH" "$TEMP_KP_PATH"
    echo "[N] Сохранение старой базы KeePass на пк..."
    cp -v "$PC_KP_PATH" "${PC_KP_PATH%.*}.old.${PC_KP_PATH##*.}"
    echo "[N] Слияние баз KeePass..."
    while true; do
        if keepassxc-cli merge -s "$PC_KP_PATH" "$TEMP_KP_PATH"; then
            break
        fi
    done
}


# Синхронизация базы KeePass на телефон и создание бэкапа
sync_keepass_2() {
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


check_dependencies

echo "Меню:"
echo "  1    Полная синхронизация"
echo "  2    Синхронизация Aegis"
echo "  3    Слияние KeePass"
echo "  4    Синхронизация KeePass"
echo "  5    Слияние и синхронизация KeePass"
echo "  6    Задать пароль для архива"
echo "  7    Архивирование бэкапов"
echo "  0    Выход"
read -rp "Введите номер: " choice
echo

case "$choice" in
    1) sync_aegis ; sync_keepass ; create_archive ; echo "[N] Полная синхронизация успешно завершена!" ;;
    2) sync_aegis ; echo "[N] Синхронизация бэкапов Aegis успешно завершена!" ;;
    3) sync_keepass_1 ; echo "[N] Слияние баз KeePass успешно завершено!" ;;
    4) sync_keepass_2 ; echo "[N] Синхронизация базы KeePass успешно завершена!" ;;
    5) sync_keepass ; echo "[N] Слияние и синхронизация баз KeePass успешно завершены!" ;;
    6) create_canary ; echo "[N] Пароль успешно задан!" ;;
    7) create_archive ; echo "[N] Архив успешно создан!" ;;
    0) exit 0 ;;
    *) echo "[E] Нет пункта с номером $choice" ; pause_and_exit 1 ;;
esac

pause_and_exit 0
