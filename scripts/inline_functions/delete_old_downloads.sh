# Flag to skip all deletions
SKIP_ALL=false
folder_count=0
app_pattern_count=0

# Default if environment variable is not set
: ${DELETE_SELECTED_FOLDERS:="1"}

function list_build_folders_when_testing() {
    # only echo pattern when testing
    if [ ${DELETE_SELECTED_FOLDERS} == 0 ]; then
        echo
        echo -e "  ${INFO_FONT}Environment variable DELETE_SELECTED_FOLDERS is set to 0"
        echo -e "  This is the list of all patterns that will be searched${NC}"
        echo
        for pattern in "${patterns[@]}"; do
            echo "    $pattern"
        done
        section_divider
    fi
}

function delete_folders_except_latest() {
    local pattern="$1"
    local total_size=0
    local unsorted_folders=()

    # First loop for case-sensitive matching
    for entry in ~/Downloads/$pattern; do
        [ -d "$entry" ] && unsorted_folders+=("$entry")
    done

    # Second loop for case-insensitive matching, but only if "main" is in the pattern
    if [[ $pattern == *main* ]]; then
        for entry in ~/Downloads/${pattern//main/Main}; do
            [ -d "$entry" ] && unsorted_folders+=("$entry")
        done
    fi

    # Sort the folders array by date (newest first)
    IFS=$'\n' folders=($(sort -r <<<"${unsorted_folders[*]}"))
    IFS=$' \t\n' # Reset IFS to default value.

    if [ ${#folders[@]} -eq 0 ]; then
        return
    fi

    # increment because folders were found
    ((app_pattern_count=app_pattern_count+1))

    if [ ${#folders[@]} -eq 1 ]; then
        echo "Only one download found for app pattern: '$pattern'"
        return
    fi

    section_divider

    echo "More than one download found for app pattern:"
    echo "  '$pattern':"
    echo
    echo "Download Folder to Keep:"
    echo "  ${folders[0]/#$HOME/~}"
    echo

    echo "Download Folder(s) that can be deleted:"

    for folder in "${folders[@]:1}"; do
        echo "  ${folder/#$HOME/~}"
        total_size=$(($total_size + $(du -s "$folder" | awk '{print $1}')))
    done

    echo
    echo -e "  If Xcode is open in a folder you plan to delete,"
    echo -e "    ${INFO_FONT}Quit Xcode${NC} before deleting"

    total_size_mb=$(echo "scale=2; $total_size / 1024" | bc)
    echo
    echo "Total size to be deleted: $total_size_mb MB"
    section_divider

    options=(
        "Delete these Folders"
        "Skip delete at this location"
        "$(exit_or_return_menu)")
    actions=(
        "delete_selected_folders \"$pattern\""
        "return"
        "exit_script")
    menu_select "${options[@]}" "${actions[@]}"
}

function delete_selected_folders() {
    local pattern="$1"
    local unsorted_folders=()

    # First loop for case-sensitive matching
    for entry in ~/Downloads/$pattern; do
        [ -d "$entry" ] && unsorted_folders+=("$entry")
    done

    # Second loop for case-insensitive matching, but only if "main" is in the pattern
    if [[ $pattern == *main* ]]; then
        for entry in ~/Downloads/${pattern//main/Main}; do
            [ -d "$entry" ] && unsorted_folders+=("$entry")
        done
    fi

    # Sort the folders array by date (newest first)
    IFS=$'\n' folders=($(sort -r <<<"${unsorted_folders[*]}"))
    IFS=$' \t\n' # Reset IFS to default value.
    echo

    this_pattern_count=0

    for folder in "${folders[@]:1}"; do
        if [ ${DELETE_SELECTED_FOLDERS} == 1 ]; then
            rm -rf "$folder"
        fi
        echo "  Removed $folder"
        ((folder_count=folder_count+1))
        ((this_pattern_count=this_pattern_count+1))
    done

    echo -e "✅ ${SUCCESS_FONT}Deleted ${this_pattern_count} download folders for this app pattern${NC}"
    if [ ${DELETE_SELECTED_FOLDERS} == 0 ]; then
        echo
        echo -e "  ${INFO_FONT}Environment variable DELETE_SELECTED_FOLDERS is set to 0"
        echo -e "  So folders marked successfully deleted are still there${NC}"
    fi
    echo
    return_when_ready
}

function skip_all() {
    SKIP_ALL=true
}

function delete_old_downloads() {
    patterns=(
        "BuildxDrip4iOS/xDrip4iOS*"
        "Build_iAPS/iAPS*"
    )

    list_build_folders_when_testing

    if [ "$SKIP_ALL" = false ] ; then
        section_divider
        echo "For each type of Build provided as a build script, "
        echo "  you will be shown your most recent download"
        echo "  and given the option to remove older downloads."

        for pattern in "${patterns[@]}"; do
            if [ "$SKIP_ALL" = false ] ; then
                delete_folders_except_latest "$pattern"
            else
                break
            fi
        done
    fi

    echo
    echo -e "✅ ${SUCCESS_FONT}Download folders have been examined for all app patterns.${NC}"
    echo -e "   There were ${app_pattern_count} app patterns that contain one or more download"
    if [ ${folder_count} -eq 0 ]; then
        echo -e "   No Download folders deleted"
    else
        echo -e "   Deleted a total of ${folder_count} older download folders"
    fi
    if [ ${DELETE_SELECTED_FOLDERS} == 0 ]; then
        echo
        echo -e "  ${INFO_FONT}Environment variable DELETE_SELECTED_FOLDERS is set to 0"
        echo -e "  So folders marked successfully deleted are still there${NC}"
    fi
}
