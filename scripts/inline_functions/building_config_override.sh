function check_config_override_existence_offer_to_configure() {
    section_separator

    # Automatic signing functionality:
    # 1) Use existing Override file
    # 2) Copy team from latest provisioning profile
    # 3) Enter team manually with option to skip

    # Options for USE_OVERRIDE_IN_REPO
    #  0 means copy file in repo up 2 levels and use that
    #  1 create the file in the repo and add development team
    #  2 create the file in the repo with extra line(s) and the team
    if [[ $USE_OVERRIDE_IN_REPO -ge 1 ]]; then
        OVERRIDE_FULLPATH="${LOCAL_DIR}/$REPO_NAME/${OVERRIDE_FILE}"
    else
        OVERRIDE_FULLPATH="${BUILD_DIR}/${OVERRIDE_FILE}"
    fi

    if [ -f ${OVERRIDE_FULLPATH} ] && \
        grep -q "^$DEV_TEAM_SETTING_NAME" ${OVERRIDE_FULLPATH}; then
        # how_to_find_your_id
        report_persistent_config_override
    else
        PROFILES_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"

        if [ -d "${PROFILES_DIR}" ]; then
            latest_file=$(find "${PROFILES_DIR}" -type f -name "*.mobileprovision" -print0 | xargs -0 ls -t | head -n1)
            if [ -n "$latest_file" ]; then
                # Decode the .mobileprovision file using the security command
                decoded_xml=$(security cms -D -i "$latest_file")

                # Extract the Team ID from the XML
                DEVELOPMENT_TEAM=$(echo "$decoded_xml" | awk -F'[<>]' '/<key>TeamIdentifier<\/key>/ { getline; getline; print $3 }')
            fi
        fi

        if [ -n "$DEVELOPMENT_TEAM" ]; then
            echo -e "Using TeamIdentifier from the latest provisioning profile\n"
            set_development_team "$DEVELOPMENT_TEAM"
            report_persistent_config_override
        else
            echo -e "Choose 1 to Sign Automatically or "
            echo -e "       2 to Sign Manually (later in Xcode)"
            echo -e "\nIf you choose Sign Automatically, script guides you"
            echo -e "  to create a permanent signing file"
            echo -e "  containing your Apple Developer ID"
            choose_option
            options=("Sign Automatically" "Sign Manually" "$(exit_or_return_menu)")
            select opt in "${options[@]}"
            do
                case $opt in
                    "Sign Automatically")
                        create_persistent_config_override
                        break
                        ;;
                    "Sign Manually")
                        break
                        ;;
                    "$(exit_or_return_menu)")
                        exit_script
                        ;;
                    *) # Invalid option
                        invalid_entry
                        ;;
                esac
            done
        fi
    fi
}

function report_persistent_config_override() {
    echo -e "Your Apple Developer ID was found automatically:"
    grep "^$DEV_TEAM_SETTING_NAME" ${OVERRIDE_FULLPATH}
    echo -e "\nIf that is correct your app will be automatically signed\n"
    options=("ID is OK" "Editing Instructions" "$(exit_or_return_menu)")
    select opt in "${options[@]}"
    do
        case $opt in
            "ID is OK")
                break
                ;;
            "Editing Instructions")
                section_divider
                echo -e " Part 1: How to find your Apple Developer ID"
                echo -e ""
                how_to_find_your_id
                echo -e ""
                echo -e " Part 2: Edit the automatic signing file before hitting return"
                echo -e "   step 1: open finder, "
                echo -e "   step 2: locate and double click on"
                echo -e "           ${OVERRIDE_FULLPATH/$HOME/~}"
                echo -e "           to open that file in Xcode"
                echo -e "   step 3: find the line that starts with "
                echo -e "           ${DEV_TEAM_SETTING_NAME}="
                echo -e "           and modify the value to be your "
                echo -e "           Apple Developer ID"
                echo -e "   step 4: save the file"
                echo -e ""
                echo -e " When ready to proceed, hit return"
                return_when_ready
                break
                ;;
            "$(exit_or_return_menu)")
                exit_script
                ;;
            *) # Invalid option
                invalid_entry
                ;;
        esac
    done
}

function how_to_find_your_id() {
    echo -e "Your Apple Developer ID is the 10-character Team ID"
    echo -e "  found on the Membership page after logging into your account at:"
    echo -e "   https://developer.apple.com/account/#!/membership\n"
    echo -e "It may be necessary to click on the Membership Details icon"
}

function create_persistent_config_override() {
    section_separator
    echo -e "The Apple Developer page will open when you hit return\n"
    how_to_find_your_id
    echo -e "That page will be opened for you."
    echo -e "  Once you get your ID, you will enter it in this terminal window"
    return_when_ready
    #
    open "https://developer.apple.com/account/#!/membership"
    echo -e "\n *** \nClick in terminal window so you can"
    read -p "Enter the ID and return: " devID
    #
    section_separator
    if [ ${#devID} -ne 10 ]; then
        echo -e "Something was wrong with the entry"
        echo -e "You can manually sign each target in Xcode"
    else 
        echo -e "Creating ${OVERRIDE_FULLPATH}"
        echo -e "   with your Apple Developer ID\n"
        # Create file with developer ID
        set_development_team $devID
        report_persistent_config_override
        echo -e "\nXcode uses the permanent file to automatically sign your targets"
    fi
}

set_development_team() {
    team_id="$1"
    if [[ $USE_OVERRIDE_IN_REPO == "0" ]] && 
       [[ -f "${LOCAL_DIR}/$REPO_NAME/${OVERRIDE_FILE}" ]]; then
        cp -p "${LOCAL_DIR}/$REPO_NAME/${OVERRIDE_FILE}" "${OVERRIDE_FULLPATH}"
    elif [[ $USE_OVERRIDE_IN_REPO == "1" ]] || \
         [[ $USE_OVERRIDE_IN_REPO == "2" ]]; then
        echo "// Automatic Signing File" > ${OVERRIDE_FULLPATH}
    fi
    if [[ $USE_OVERRIDE_IN_REPO == "2" ]]; then
        for str in ${ADDED_LINE_FOR_OVERRIDE[@]}; do
            echo "$str" >> ${OVERRIDE_FULLPATH}
         done
    fi
    echo "$DEV_TEAM_SETTING_NAME = $team_id" >> ${OVERRIDE_FULLPATH}
}

