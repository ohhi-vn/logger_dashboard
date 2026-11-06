#!/bin/bash

Prepare()
{
   echo "Prepare dependencies"
}

Build_ARM()
{
    echo "Build assets on host"
    mix assets.deploy

    podman build -t logger-dashboard:latest . && podman save -o logger_dashboard_image_arm.tar logger-dashboard:latest
}

Build_X86()
{
    echo "Build assets on host"
    mix assets.deploy

    podman build  --platform="linux/amd64" -t logger-dashboard:latest . && podman save -o logger_dashboard_image_x64.tar logger-dashboard:latest
}

Clean()
{
   rm -rf ./int_deps/*
  echo "Clean DONE"
}

Help()
{
   # Display Help
   echo "Build podman image for logger-dashboard"
   echo
   echo "Syntax: start_app [-h|a|x]"
   echo "options:"
   echo "x     build podman image for AMD64"
   echo "a     build podman image for ARM"
   echo
   echo "h     Print this Help."
   echo "========== Have fun =========="
   echo
}


while getopts "hax" option; do
   echo "option: $option"
   case $option in
      h) # display Help
         Help
         exit
         ;;
      a) # Enter a name
        echo "Build podman image for ARM"
        Prepare
        Build_ARM
        Clean
         exit
        ;;
      x) # Enter a name
        echo "Build podman image for AMD64"
        Prepare
        Build_X86
        Clean
        exit
        ;;
     \?) # Invalid option
      echo "Invalid option: -${OPTARG}." >&2
      exit 1
      ;;
   esac
done
shift $((OPTIND - 1))

Help
