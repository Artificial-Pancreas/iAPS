############################################################
# warning used by all scripts that build an app
############################################################

function open_source_warning() {
    # Skip open source warning if opted out using env variable or this script is run from another script
    if [ "${SKIP_OPEN_SOURCE_WARNING}" = "1" ] || [ "$0" = "_" ]; then return; fi

    local documentation_link="${1:-}"

    section_separator

    echo -e "${INFO_FONT}*** IMPORTANT ***${NC}\n"
    echo -e "This project is:"
    echo -e "${INFO_FONT}  Open Source software"
    echo -e "  Not \"approved\" for therapy${NC}"
    echo -e ""
    echo -e "  You take full responsibility when you build"
    echo -e "  or run an open source app, and"
    echo -e "  ${INFO_FONT}you do so at your own risk.${NC}"
    echo -e ""
    echo -e "To increase (decrease) font size"
    echo -e "  Hold down the CMD key and hit + (-)"
    echo -e "\n${INFO_FONT}By typing 1 and ENTER, you indicate you understand"
    echo -e "\n--------------------------------\n${NC}"

    options=("Agree" "Cancel")
    select opt in "${options[@]}"; do
        case $opt in
        "Agree")
            break
            ;;
        "Cancel")
            echo -e "\n${INFO_FONT}User did not agree to terms of use.${NC}\n\n"
            exit_script
            ;;
        *)
            echo -e "\n${INFO_FONT}User did not agree to terms of use.${NC}\n\n"
            invalid_entry
            exit_script
            ;;
        esac
    done

    # Warning has been issued
    SKIP_OPEN_SOURCE_WARNING=1

    echo -e "${NC}\n\n\n\n"
}
