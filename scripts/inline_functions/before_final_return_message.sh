function before_final_return_message() {
    echo ""
    echo -e "${INFO_FONT}BEFORE you hit return:${NC}"
    echo " *** Unlock your phone and plug it into your computer"
    echo "     Trust computer if asked"
    echo ""
    echo -e "${INFO_FONT}AFTER you hit return, Xcode will open automatically${NC}"
    echo "  For new phone or new watch (never used with Xcode),"
    echo "    review Developer Mode Information:"
    echo -e "  https://loopkit.github.io/loopdocs/build/step14/#prepare-your-phone-and-watch"
    echo ""
    echo "  For phones that have Developer Mode enabled continue with these steps"
    echo "  Upper middle of Xcode:"
    echo "    Confirm your phone or simulator choice is selected"
    echo "  Upper right of Xcode:"
    echo "    Wait for packages to finish being copied or downloaded"
    echo "    When you see indexing, you can start the build"
    echo "  Click on Play button to build and run on the selected device"
}

function after_final_return_message() {
    section_divider
    echo "If you need to find this download in a terminal, copy and paste the next line:"
    echo ""
    echo "cd ${LOCAL_DIR}/${REPO_NAME}"
}
