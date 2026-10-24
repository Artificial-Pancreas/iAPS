#!/bin/sh -e

#  copy-plugins.sh
#  Loop
#
#  Copyright © 2019 LoopKit Authors. All rights reserved.


shopt -s nullglob

# Frameworks and plugins from the OmniBLE and OmniKit submodules, which were replaced by OmnipodKit.
# Their build products can linger in DerivedData after updating from an older version without a clean
# build. If they end up in the app, PluginManager picks them up for an existing "Omnipod-Dash"/"Omnipod"
# pump instead of handing it over to OmnipodKit, and the stale binaries, built against an older LoopKit,
# dispatch PumpManager calls to the wrong methods (e.g. enactTempBasal runs suspendDelivery).
retired_frameworks="OmniBLE OmniBLEPlugin OmniKit OmniKitUI OmniKitPlugin"

function is_retired {
    case " $retired_frameworks " in
      *" $1 "*) return 0 ;;
    esac
    return 1
}

# Remove retired frameworks left in the app by previous builds
function remove_retired_frameworks {
    for name in $retired_frameworks; do
      framework_path="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/${name}.framework"
      if [ -e "$framework_path" ]; then
        echo "Removing retired framework: $framework_path"
        rm -rf "$framework_path"
      fi
    done
}

# Copy device plugins
function copy_plugins {
    echo "Looking for plugins in $1"
    for f in "$1"/*.loopplugin; do
      plugin=$(basename "$f")
      if is_retired "${plugin%.*}"; then
        echo "Skipping retired plugin: $plugin"
        continue
      fi
      echo Copying plugin: $plugin to frameworks directory in app
      plugin_path="$(readlink -f "$f" || echo "$f")"
      plugin_as_framework_path="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/${plugin%.*}.framework"
      rsync -va --exclude=Frameworks "$plugin_path/." "${plugin_as_framework_path}"
      # Rename .plugin to .framework
      if [ "$EXPANDED_CODE_SIGN_IDENTITY" != "-" ] && [ "$EXPANDED_CODE_SIGN_IDENTITY" != "" ]; then
        export CODESIGN_ALLOCATE=${DT_TOOLCHAIN_DIR}/usr/bin/codesign_allocate
        echo "Signing ${plugin} with ${EXPANDED_CODE_SIGN_IDENTITY_NAME}"
        /usr/bin/codesign --force --sign ${EXPANDED_CODE_SIGN_IDENTITY} --timestamp=none --preserve-metadata=identifier,entitlements,flags "$plugin_as_framework_path"
      else
        echo "Skipping signing, no identity set"
      fi
      for framework_path in "${f}"/Frameworks/*.framework; do
        framework=$(basename "$framework_path")
        echo "Copying plugin's framework $framework_path to ${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/."
        cp -avf "$framework_path" "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/."
        plugin_path="$(readlink -f "$f" || echo "$f")"
        if [ "$EXPANDED_CODE_SIGN_IDENTITY" != "-" ] && [ "$EXPANDED_CODE_SIGN_IDENTITY" != "" ]; then
          echo "Signing $framework for $plugin with $EXPANDED_CODE_SIGN_IDENTITY_NAME"
          /usr/bin/codesign --force --sign ${EXPANDED_CODE_SIGN_IDENTITY} --timestamp=none --preserve-metadata=identifier,entitlements,flags "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/${framework}"
        fi
      done
    done
}

remove_retired_frameworks
copy_plugins "$BUILT_PRODUCTS_DIR"
