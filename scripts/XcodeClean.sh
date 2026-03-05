#!/bin/bash
# -----------------------------------------------------------------------------
# This file is GENERATED. DO NOT EDIT directly.
# If you want to modify this file, edit the corresponding file in the src/
# directory and then run the build script to regenerate this output file.
# -----------------------------------------------------------------------------


# *** Start of inlined file: inline_functions/common.sh ***
STARTING_DIR="${PWD}"

############################################################
# define some font styles and colors
############################################################

# remove special font
NC='\033[0m'
# add special font
#INFO_FONT='\033[1;36m'
INFO_FONT='\033[1m'
SUCCESS_FONT='\033[1;32m'
ERROR_FONT='\033[1;31m'

function section_divider() {
    echo -e ""
    echo -e "--------------------------------"
    echo -e ""
}

function section_separator() {
    # Clears the screen without clearing the scrollback buffer, suppressing any error messages
    echo -e "\033[2J\033[H" 2>/dev/null
    section_divider
}

function return_when_ready() {
    echo -e "${INFO_FONT}Return when ready to continue${NC}"
    read -p "" dummy
}

# Skip if this script is called from another script, then this has already been displayed
if [ "$0" != "_" ]; then
    # Inform the user about env variables set
    # Variables definition
    variables=(
        "SCRIPT_BRANCH: Indicates the lnl-scripts branch in use."
        "LOCAL_SCRIPT: Set to 1 to run scripts from the local directory."
        "FRESH_CLONE: Lets you use an existing clone (saves time)."
        "CLONE_STATUS: Can be set to 0 for success (default) or 1 for error."
        "SKIP_OPEN_SOURCE_WARNING: If set, skips the open source warning for build scripts."
        "CUSTOM_URL: Overrides the repo url."
        "CUSTOM_BRANCH: Overrides the branch used for git clone."
        "CUSTOM_MACOS_VER: Overrides the detected macOS version."
        "CUSTOM_XCODE_VER: Overrides the detected Xcode version."
        "DELETE_SELECTED_FOLDERS: Echoes folder names but does not delete them"
        "PATCH_BRANCH: Indicates the source branch for patches."
        "PATCH_REPO: Specifies the URL of the patch source repository."
        "LOCAL_PATCH_FOLDER: Defines a local directory for sourcing patches."
        "CUSTOMIZATION_DEBUG: Determines the verbosity of the customization debug output."
    )

    # Flag to check if any variable is set
    any_variable_set=false

    # Iterate over each variable
    for var in "${variables[@]}"; do
        # Split the variable name and description
        IFS=":" read -r name description <<<"$var"

        # Check if the variable is set
        if [ -n "${!name}" ]; then
            # If this is the first variable set, print the initial message
            if ! $any_variable_set; then
                section_separator
                echo -e "For your information, you are running this script in customized mode"
                echo -e "You might be using a branch other than main, and using SCRIPT_BRANCH"
                echo -e "Developers might have additional environment variables set:"
                any_variable_set=true
            fi

            # Print the variable name, value, and description
            echo "  - $name: ${!name}"
            echo "    $description"
        fi
    done
    if $any_variable_set; then
        echo
        echo "To clear the values, close this terminal and start a new one."
        echo "Sleeping for 2 sec then continuing"
        sleep 2
    fi
fi

function choose_option() {
    echo -e "Type a number from the list below and return to proceed."
    section_divider
}

function invalid_entry() {
    echo -e "\n${ERROR_FONT}Invalid option${NC}\n"
}

function do_continue() {
    :
}

function menu_select() {
    choose_option

    local options=("${@:1:$#/2}")
    local actions=("${@:$(($# + 1))/2+1}")

    while true; do
        select opt in "${options[@]}"; do
            for i in $(seq 0 $((${#options[@]} - 1))); do
                if [ "$opt" = "${options[$i]}" ]; then
                    eval "${actions[$i]}"
                    return
                fi
            done
            invalid_entry
            break
        done
    done
}

function exit_or_return_menu() {
    if [ "$0" != "_" ]; then
        # Called directly
        echo "Exit Script"
    else
        # Called from BuildSelectScript
        echo "Return to Menu"
    fi
}

function exit_script() {
    if [ "$0" != "_" ]; then
        # Called directly
        exit_message
    else
        # Called from BuildSelectScript
        exit 0
    fi
}

function exit_message() {
    section_divider
    echo -e "${INFO_FONT}Exit from Script${NC}\n"
    echo -e "  You may close the terminal"
    echo -e "or"
    echo -e "  You can press the up arrow ⬆️  on the keyboard"
    echo -e "    and return to repeat script from beginning"
    section_divider
    exit 0
}

function erase_previous_line {
    if [ -n "$TERM" ]; then
        (tput cuu1 && tput el) 2>/dev/null || true
    fi
}
# *** End of inlined file: inline_functions/common.sh ***


section_separator
echo -e "${INFO_FONT}If you did not quit Xcode before selecting, this might not clean everything${NC}"

echo -e "\n\n🕒 Please be patient. On older computers and virtual machines, this may take 5-10 minutes or longer to run.\n"

echo -e "\n\n✅ Removing Developer iOS DeviceSupport Library\n"
rm -rf "$HOME/Library/Developer/Xcode/iOS\ DeviceSupport"

echo -e "✅ Removing Developer watchOS DeviceSupport Library\n"
rm -rf "$HOME/Library/Developer/Xcode/watchOS\ DeviceSupport"

echo -e "✅ Removing Developer DerivedData\n"
rm -rf "$HOME/Library/Developer/Xcode/DerivedData"

echo -e "   If Xcode was open, you may see a 'Permission denied' statement."
echo -e "   In that case, quit out of Xcode and run the script again before rebooting\n"

echo -e "🛑  Please Reboot Now\n\n";
exit_script
# *** End of inlined file: src/XcodeClean.sh ***

