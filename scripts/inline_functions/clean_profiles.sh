############################################################
# clean_profiles function
#   Action: deletes saved mobileprovisions from Mac
#   Information:
#     If Xcode is open, *.mobileprovisions are deleted and new ones generated
#     The path changed between Xcode 15 and Xcode 16, delete both folders
############################################################

clean_profiles() {
    xcode15_path=${HOME}/Library/MobileDevice/Provisioning\ Profiles
    xcode16_path=${HOME}/Library/Developer/Xcode/UserData/Provisioning\ Profiles

    echo -e "\n✅ Cleaning Profiles"
    echo -e "     This ensures the next app you build with Xcode will last a year."
    if [[ -d "$xcode15_path" ]]; then
        rm -rf "$xcode15_path"
    fi
    if [[ -d "$xcode16_path" ]]; then
        rm -rf "$xcode16_path"
    fi
    echo -e "✅ Profiles are cleaned."
}
