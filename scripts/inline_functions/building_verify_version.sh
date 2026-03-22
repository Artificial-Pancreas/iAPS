#This should be the latest iOS version
#This is the highest version we expect users to have on their iPhones
LATEST_IOS_VER="26.2"

#This should be the lowest xcode version required to build to LATEST_IOS_VER
LOWEST_XCODE_VER="16.4"

#This should be the latest known xcode version
#LOWEST_XCODE_VER and LATEST_XCODE_VER will probably be equal but we should have suport for a span of these
LATEST_XCODE_VER="26.2"

#This is the lowest version of macOS required to run LOWEST_XCODE_VER
LOWEST_MACOS_VER="15.3"

# The compare_versions function takes two version strings as input arguments,
# sorts them in ascending order using the sort command with the -V flag (version sorting),
# and returns the first version (i.e., the lowest one) using head -n1.
#
# Example:
# compare_versions "1.2.3" "1.1.0" will return "1.1.0"
function compare_versions() {
    printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1
}

function check_versions() {
    section_divider
    echo "Verifying Xcode and macOS versions..."

    if ! command -v xcodebuild >/dev/null; then
        echo "  Xcode not found. Please install Xcode and try again."
        exit_or_return_menu
    fi

    if [ -n "$CUSTOM_XCODE_VER" ]; then
        XCODE_VER="$CUSTOM_XCODE_VER"
    else
        XCODE_VER=$(xcodebuild -version | awk '/Xcode/{print $NF}')
    fi

    if [ -n "$CUSTOM_MACOS_VER" ]; then
        MACOS_VER="$CUSTOM_MACOS_VER"
    else
        MACOS_VER=$(sw_vers -productVersion)
    fi

    echo "  Xcode found: Version $XCODE_VER"

    # Check if Xcode version is greater than the latest known version
    if [ "$(compare_versions "$XCODE_VER" "$LATEST_XCODE_VER")" = "$LATEST_XCODE_VER" ] && [ "$XCODE_VER" != "$LATEST_XCODE_VER" ]; then
        echo ""
        echo "You have a newer Xcode version ($XCODE_VER) than"
        echo "  the latest released version known by this script ($LATEST_XCODE_VER)."
        echo "You can probably continue; but if you have problems, refer to"
        echo "    https://developer.apple.com/support/xcode/"

        options=("Continue" "$(exit_or_return_menu)")
        actions=("return" "exit_script")
        menu_select "${options[@]}" "${actions[@]}"
    # Check if Xcode version is less than the lowest required version
    elif [ "$(compare_versions "$XCODE_VER" "$LOWEST_XCODE_VER")" = "$XCODE_VER" ] && [ "$XCODE_VER" != "$LOWEST_XCODE_VER" ]; then
        if [ "$(compare_versions "$MACOS_VER" "$LOWEST_MACOS_VER")" != "$LOWEST_MACOS_VER" ]; then
            echo ""
            echo "Your macOS version ($MACOS_VER) is lower than $LOWEST_MACOS_VER"
            echo "  required to build for iOS $LATEST_IOS_VER."
            echo "Please update macOS to version $LOWEST_MACOS_VER or later."
            echo ""
            echo "If you can't update, follow the GitHub build option here:"
            echo "  https://loopkit.github.io/loopdocs/gh-actions/gh-overview/"
        fi

        echo ""
        echo "You need to upgrade Xcode to version $LOWEST_XCODE_VER or later to build for iOS $LATEST_IOS_VER."
        echo "If your iOS is at a lower version, refer to the compatibility table in LoopDocs"
        echo "  https://loopkit.github.io/loopdocs/build/xcode-version/#compatible-versions"

        options=("Continue with lower iOS version" "$(exit_or_return_menu)")
        actions=("return" "exit_script")
        menu_select "${options[@]}" "${actions[@]}"
    else 
        echo "Your Xcode version can build up to iOS $LATEST_IOS_VER."
    fi
}
