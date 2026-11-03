#!inline common.sh

############################################################
# Common functions used by multiple build scripts
#    - Explanation of variables, Default values
############################################################

# Variables set by BuildXXX script that calls this inline script
#
# Required: BUILD_DIR
#    it is where the download folder will be created
#    For example: BUILD_DIR=~/Downloads/Build{app_name}
#
# Required: OVERRIDE_FILE
#    name of the automatic signing file
#    For example: OVERRIDE_FILE=LoopConfigOverride.xcconfig

# Required: DEVELOPER_TEAM
#    keyword used in the automatic signing file
#    e.g., ${DEVELOPER_TEAM} = Apple Developer TeamID

# Default: some projects create or use the override file in the BUILD_DIR
# Some, like iAPS, use a file in the downloaded clone itself
#    in that case, set USE_OVERRIDE_IN_REPO to 1 in the src/Build script
: ${USE_OVERRIDE_IN_REPO:="0"}

# Default: some projects use submodules (and need --recurse-submodule)
: ${CLONE_SUB_MODULES:="1"}

# Accept build_warning before creating folders
#!inline build_warning.sh

# Messages prior to opening xcode
#!inline before_final_return_message.sh

# clean provisioning profiles saved on disk
#!inline clean_profiles.sh

############################################################
# Common functions used by multiple build scripts
#    - Start of build_functions.sh common code
############################################################

SCRIPT_DIR="${BUILD_DIR}/Scripts"

if [ ! -d "${BUILD_DIR}" ]; then
    mkdir "${BUILD_DIR}"
fi

############################################################
# set up nominal values
#   these can be later overwritten by flags
#   for convenience when testing (or for advanced users)
############################################################

# FRESH_CLONE
#   Default value is 1, which means:
#     Download fresh clone every time script is run
: ${FRESH_CLONE:="1"}
# CLONE_STATUS used to test error messages
#   Default value is 0, which means no errors with clone
: ${CLONE_STATUS:="0"}

# Prepare date-time stamp for folder
DOWNLOAD_DATE=$(date +'%y%m%d-%H%M')

# This enables the selection of a custom branch via enviroment variable
# It can also be passed in as argument $1
#   If passed in, it overwrites the environment variable
#   When CUSTOM_BRANCH is set, the menu which asks which branch is skipped
CUSTOM_BRANCH=${1:-$CUSTOM_BRANCH}

############################################################
# Define the rest of the functions (usage defined above):
############################################################

#!inline building_verify_version.sh
#!inline building_config_override.sh

function standard_build_train() { 
    verify_xcode_path
    check_versions
    clone_repo
    automated_clone_download_error_check
    check_config_override_existence_offer_to_configure
    ensure_a_year
}

function ensure_a_year() {
    section_separator

    echo -e "${INFO_FONT}Ensure a year by deleting old provisioning profiles${NC}"
    echo -e "  Unless you have a specific reason, choose option 1\n"
    options=("Ensure a Year" "Skip" "$(exit_or_return_menu)")
    select opt in "${options[@]}"
    do
        case $opt in
            "Ensure a Year")
                clean_profiles
                break
                ;;
            "Skip")
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

function clone_repo() {
    section_divider
    if [ "$SUPPRESS_BRANCH" == "true" ]; then
        LOCAL_DIR="${BUILD_DIR}/${APP_NAME}-${DOWNLOAD_DATE}"
    else
        LOCAL_DIR="${BUILD_DIR}/${APP_NAME}_${BRANCH//\//-}-${DOWNLOAD_DATE}"
    fi
    if [ ${FRESH_CLONE} == 1 ]; then
        mkdir "${LOCAL_DIR}"
    else
        LOCAL_DIR="${STARTING_DIR}"
    fi
    cd "${LOCAL_DIR}"
    if [ ${FRESH_CLONE} == 1 ]; then
        if [ "$SUPPRESS_BRANCH" == "true" ]; then
            echo -e " -- Downloading ${APP_NAME} to your Downloads folder --"
        else
            echo -e " -- Downloading ${APP_NAME} ${BRANCH} to your Downloads folder --"
        fi
        echo -e "      ${LOCAL_DIR}\n"
        echo -e "Issuing this command:"
        if [[ $CLONE_SUB_MODULES == "1" ]]; then
            echo -e "    git clone --branch=${BRANCH} --recurse-submodules ${REPO}"
            git clone --branch=$BRANCH --recurse-submodules $REPO
        else
            echo -e "    git clone --branch=${BRANCH} ${REPO}"
            git clone --branch=$BRANCH $REPO
        fi
        clone_exit_status=$?
    else
        clone_exit_status=${CLONE_STATUS}
    fi
}

function automated_clone_download_error_check() {
    # Check if the clone was successful
    if [ $clone_exit_status -eq 0 ]; then
        # Use this flag to modify exit_or_return_menu
        echo -e "✅ ${SUCCESS_FONT}Successful Download. Proceed to the next step...${NC}"
        return_when_ready
    else
        echo -e "❌ ${ERROR_FONT}An error occurred during download. Please investigate the issue.${NC}"
        exit_message
    fi
}

function verify_xcode_path() {
    section_divider

    echo -e "Verifying xcode-select path...\n"

    # Get the path set by xcode-select
    xcode_path=$(xcode-select -p)

    # Check if the path contains "Xcode.app"
    if [[ -x "$xcode_path/usr/bin/xcodebuild" ]]; then
        echo -e "✅ ${SUCCESS_FONT}xcode-select path correctly set: $xcode_path${NC}"
        echo -e "Continuing the script..."
    else
        echo -e "❌ ${ERROR_FONT}xcode-select is not pointing to the correct Xcode path."
        echo -e "     It is set to: $xcode_path${NC}"
        echo -e "Please choose an option below to proceed:\n"
        options=("Correct xcode-select path" "Skip" "$(exit_or_return_menu)")
        select opt in "${options[@]}"
        do
            case $opt in
                "Correct xcode-select path")
                    xcode_path=$(mdfind -name Xcode.app 2>/dev/null)
                    if [ -z "$xcode_path" ]; then
                        echo -e "❌ ${ERROR_FONT}Xcode.app not found.${NC}"
                        echo -e "Please use this guide to set the xcode-select path: https://loopkit.github.io/loopdocs/build/step9/#command-line-tools"
                        exit_message
                    else
                        echo -e "Using this location: $xcode_path"
                        DEVELOPER_DIR_PATH="$xcode_path/Contents/Developer"

                        if [ ! -d "$DEVELOPER_DIR_PATH" ]
                        then
                            echo -e "❌ ${ERROR_FONT}Developer directory not found in Xcode.app. Please ensure you have the correct version of Xcode installed..${NC}"
                            echo -e "Please use this guide to set the xcode-select path: https://loopkit.github.io/loopdocs/build/step9/#command-line-tools"
                            exit_message
                        else
                            echo -e "You might be prompted for your password."
                            echo -e "  Use the password for logging into your Mac."
                            sudo xcode-select -s "$DEVELOPER_DIR_PATH"

                            # Check if the path was corrected successfully
                            xcode_path=$(xcode-select -p)
                            if [[ "$xcode_path" == *Xcode.app* ]]; then
                                echo -e "✅ ${SUCCESS_FONT}xcode-select path has been corrected.${NC}"
                                return_when_ready
                                break
                            else
                                echo -e "❌ ${ERROR_FONT}Failed to set xcode-select path correctly.${NC}"
                                exit_message
                            fi
                        fi
                    fi
                    ;;
                "Skip")
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
}

function branch_select() {
    local url=$1
    local branch=$2
    local repo_name=$(basename $url .git)
    local app_name=${3:-$(basename $url .git)}
    local suppress_branch=${3:+true}

    REPO=$url
    BRANCH=$branch
    REPO_NAME=$repo_name
    APP_NAME=$app_name
    SUPPRESS_BRANCH=$suppress_branch
}

############################################################
# End of functions used by script
#    - end of build_functions.sh common code
############################################################
