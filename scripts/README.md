# Build Scripts

## Introduction

These scripts simplify some tasks for building iAPS and other DIY code from the GitHub repositories.

The code that these scripts help you download, build or modify is provided as open source (OS), and it is your responsibility to review the code and understand how each app works. This code is experimental and intended for testing, research, and educational purposes; it is not approved for therapy. Patches or customizations are even more experimental. You take full responsibility for building and running an OS app, and you do so at your own risk.

## Developer Tips

When these scripts are being modified and tested, the developers will be working in a feature or development (dev) branch. In addition, they can use some special flags to simplify and speed up testing.

In order to test with a different branch, first configure that branch in Terminal with the export command. If using a branch other than dev, then modify the command with that branch name:

```
export SCRIPT_BRANCH=dev
```

Then for all commands found earlier in this README, replace the word main with $SCRIPT_BRANCH.

When testing locally, there are other test variables you can configure. Be sure to read these two files:

- `custom_config.sh`
- `clear_custom_config.sh`

### Inlining Scripts

This project uses a script inlining system to generate executable scripts from source files. The source files for each script are located in the src directory, and the generated scripts are output to the root directory. All inline scripts are in the inline_functions folder.

To modify a script, simply edit the corresponding source file in the src directory, and then run the build script (`./build.sh`) to regenerate all the scripts. The build script will inline any required files and generate the final executable scripts. By adding an argument after `./build.sh`, you can limit the rebuild to the indicated script.

To test a script during development, this command is helpful (example shown is for CustomatizationScript, but works for any script.)

1. Modify `src/CustomizationScript.sh`
1. Execute this command to rebuild and execute:

- `./build.sh CustomizationScript.sh && ./CustomizationScript.sh`

Note that the build system uses special comments to indicate which files should be inlined. Any line in a script that starts with #!inline will be replaced with the contents of the specified file. The build system will inline files up to a maximum depth of 10, to prevent infinite recursion.

To learn more about the inlining process and how it works, please see the comments in the `build.sh` script.

### Environment Variable

The available environment variables used by the scripts are set using the `export` command and cleared with the `unset` command.

Once you use an export command, that environment variable stays set in that Terminal and will be used by the script.

- You can use the unset command to stay in the same Terminal
- You can use CMD-N while in any Terminal window to open a new Terminal window, then switch to the new window
