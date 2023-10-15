#!/bin/env bash
set -e

if [ ! -e "src/api/api.h" ]; then
  echo "Please run this script from the root directory of Lite XL."
  exit 1
fi

source scripts/common.sh

ARCH="$(uname -m)"
BUILD_DIR="$(get_default_build_dir)"
RUN_BUILD=true
ADDONS=false

show_help(){
  echo
  echo "Usage: $0 <OPTIONS>"
  echo
  echo "Available options:"
  echo
  echo "-h --help                 Show this help and exits."
  echo "-b --builddir DIRNAME     Sets the name of the build dir (no path)."
  echo "                          Default: '${BUILD_DIR}'."
  echo "   --debug                Debug this script."
  echo "-n --nobuild              Skips the build step, use existing files."
  echo "-v --version VERSION      Specify a version, non whitespace separated string."
  echo
}

initial_arg_count=$#

for i in "$@"; do
  case $i in
    -h|--help)
      show_help
      exit 0
      ;;
    -b|--builddir)
      BUILD_DIR="$2"
      shift
      shift
      ;;
    --debug)
      set -x
      shift
      ;;
    -n|--nobuild)
      RUN_BUILD=false
      shift
      ;;
    -v|--version)
      VERSION="$2"
      shift
      shift
      ;;
    *)
      # unknown option
      ;;
  esac
done

# show help if no valid argument was found
if [ $initial_arg_count -eq $# ]; then
  show_help
  exit 1
fi

setup_appimagetool() {
  if [ ! -e appimagetool ]; then
    if ! wget -O appimagetool "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-${ARCH}.AppImage" ; then
      echo "Could not download the appimagetool for the arch '${ARCH}'."
      exit 1
    else
      chmod 0755 appimagetool
    fi
  fi
}

download_appimage_apprun() {
  if [ ! -e AppRun ]; then
    if ! wget -O AppRun "https://github.com/AppImage/AppImageKit/releases/download/continuous/AppRun-${ARCH}" ; then
      echo "Could not download AppRun for the arch '${ARCH}'."
      exit 1
    else
      chmod 0755 AppRun
    fi
  fi
}

build_litexl() {
  if [ -e ${BUILD_DIR} ]; then
    rm -rf ${BUILD_DIR}
  fi

  echo "Build lite-xl..."
  meson setup --wrap-mode=forcefallback --buildtype=release --prefix=/usr\
      ${BUILD_DIR}
  meson compile -C ${BUILD_DIR}
}

generate_appimage() {
  if [ -e LiteXL.AppDir ]; then
    rm -rf LiteXL.AppDir
  fi

  echo "Creating LiteXL.AppDir..."

  DESTDIR="$(realpath LiteXL.AppDir)" meson install -C ${BUILD_DIR}
  mv AppRun LiteXL.AppDir/
  # These could be symlinks but it seems they doesn't work with AppimageLauncher
  cp resources/icons/lite-xl.svg LiteXL.AppDir/
  cp resources/linux/com.lite_xl.LiteXL.desktop LiteXL.AppDir/

  welcome_install "${BUILD_DIR}" "LiteXL.AppDir/usr/share/lite-xl"

  echo "Generating AppImage..."
  local version=""
  if [ -n "$VERSION" ]; then
    version="-$VERSION"
  fi

  ./appimagetool --appimage-extract-and-run LiteXL.AppDir LiteXL${version}-${ARCH}.AppImage
}

setup_appimagetool
download_appimage_apprun
build_litexl
generate_appimage $1
