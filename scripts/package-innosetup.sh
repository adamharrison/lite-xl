#!/bin/bash
set -e

if [ ! -e "src/api/api.h" ]; then
  echo "Please run this script from the root directory of Lite XL."; exit 1
fi

source scripts/common.sh

show_help() {
  echo
  echo "Usage: $0 <OPTIONS>"
  echo
  echo "Available options:"
  echo
  echo "-b --builddir DIRNAME     Sets the name of the build directory (not path)."
  echo "                          Default: '$(get_default_build_dir)'."
  echo "-v --version VERSION      Sets the version on the package name."
  echo "   --debug                Debug this script."
  echo
}

main() {
  local build_dir=$(get_default_build_dir)
  local addons=false
  local arch
  local arch_file
  local version
  local output

  if [[ $MSYSTEM == "MINGW64" ]]; then
    arch=x64
    arch_file=x86_64
  else
    arch=i686;
    arch_file=x86
  fi

  initial_arg_count=$#

  for i in "$@"; do
    case $i in
      -h|--help)
        show_help
        exit 0
        ;;
      -b|--builddir)
        build_dir="$2"
        shift
        shift
        ;;
      -v|--version)
        if [[ -n $2 ]]; then version="-$2"; fi
        shift
        shift
        ;;
      --debug)
        set -x
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

  [[ ! -e $build_dir ]] && scripts/build.sh $@

  output="lite-xl-${version}-${arch_file}-windows-setup"

  "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" -dARCH=$arch //F"${output}" "${build_dir}/scripts/innosetup.iss"
  pushd "${build_dir}/scripts"; mv lite-xl*.exe "./../../"; popd
}

main "$@"