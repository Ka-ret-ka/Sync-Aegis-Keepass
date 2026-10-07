#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEBUG=0

. "${SCRIPT_DIR}/config.sh"


show_help() {
    cat << EOF
Использование: $(basename "$0") [ОПЦИИ]

Sync-Aegis-Keepass - программа для синхронизации бэкапов Aegis Authenticator,
базы данных KeePass и создания архива со всеми бэкапами. Для того, чтобы в
архив попадали пользовательские данные, необходимо сохранить их в
пользовательских каталогах с любым названием (в основном каталоге бэкапов, он
определяется в переменной BACKUPS_PATH).

Опции:
  -h, --help            Показать эту справку
  -d, --debug           Подробный вывод (пока не реализован)
  -e, --edit-config     Открыть файл настроек в текстовом редакторе
  -r, --reset-config    Сбросить настройки к значениям по умолчанию
EOF
}


while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--debug)
            DEBUG=1
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -e|--edit-config)
            edit_config
            exit 0
            ;;
        -r|--reset-config)
            reset_config
            exit 0
            ;;
        *)
            echo "[E] Неизвестный параметр $1" >&2
            echo "Используйте '$(basename "$0") --help' для справки." >&2
            exit 1
            ;;
    esac
    shift
done


load_config
. "${SCRIPT_DIR}/utils.sh"


run_menu() {
    check_dependencies

    echo "Меню:"
    echo "  1    Полная синхронизация"
    echo "  2    Синхронизация Aegis"
    echo "  3    Слияние KeePass"
    echo "  4    Синхронизация KeePass"
    echo "  5    Слияние и синхронизация KeePass"
    echo "  6    Задать пароль для архива"
    echo "  7    Архивирование бэкапов"
    echo "  8    Редактирование config"
    echo "  9    Сброс config"
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
        8) edit_config ;;
        9) reset_config ;;
        0) exit 0 ;;
        *) echo "[E] Нет пункта с номером $choice" ; pause_and_exit 1 ;;
    esac

    pause_and_exit 0
}


run_menu
