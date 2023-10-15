#!/bin/bash

set -e

welcome_install() {
  local build_dir="$1"
  local data_dir="$2"

  [[ ! -e "$build_dir/lpm" ]] && curl --insecure -L "https://github.com/lite-xl/lite-xl-plugin-manager/releases/download/latest/lpm.$(get_platform_tuple)" -o $build_dir/lpm && chmod +x $build_dir/lpm
  $build_dir/lpm install --datadir $data_dir --userdir $data_dir --platform $(get_platform_tuple) install welcome && $build_dir/lpm purge --datadir $data_dir --userdir $data_dir
}

get_platform_name() {
  if [[ "$OSTYPE" == "msys" ]]; then
    echo "windows"
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo "darwin"
  elif [[ "$OSTYPE" == "linux"* || "$OSTYPE" == "freebsd"* ]]; then
    echo "linux"
  else
    echo "UNSUPPORTED-OS"
  fi
}

get_platform_arch() {
  arch=${CROSS_ARCH:-$(uname -m)}
  if [[ $MSYSTEM != "" ]]; then
    if [[ $MSYSTEM == "MINGW64" ]]; then
      arch=x86_64
    else
      arch=x86
    fi
  fi
  echo "$arch"
}

get_platform_tuple() {
  platform="$(get_platform_name)"
  arch="$(get_platform_arch)"
  echo "$arch-$platform"
}

get_default_build_dir() {
  platform="${1:-$(get_platform_name)}"
  arch="${2:-$(get_platform_arch)}"
  echo "build-$arch-$platform"
}

if [[ $(get_platform_name) == "UNSUPPORTED-OS" ]]; then
  echo "Error: unknown OS type: \"$OSTYPE\""
  exit 1
fi
