#!/bin/bash

#!inline common.sh

section_separator
echo -e "${INFO_FONT}If you did not quit Xcode before selecting, you might see errors${NC}"
echo -e "\n\n🕒 Please be patient. On older computers and virtual machines, this may take 5-10 minutes or longer to run.\n"
echo -e "✅ Cleaning Derived Data files.\n"
rm -rf ~/Library/Developer/Xcode/DerivedData
echo -e "✅ Done Cleaning"
echo -e "   If Xcode was open, you may see a 'Permission denied' statement."
echo -e "   In that case, quit out of Xcode and run the script again\n"
exit_script
