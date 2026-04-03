#!/bin/bash

#!inline common.sh

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
