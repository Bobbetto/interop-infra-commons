#!/bin/bash
set -euo pipefail

help() {
    echo "Usage: 
        [ -u | --untar ] Untar downloaded charts
        [ -v | --verbose ] Show debug messages
        [ -h | --help ] This help" 
    exit 2
}

PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
ROOT_DIR="$PROJECT_DIR"


echo "Using ROOT_DIR: $ROOT_DIR"
echo "Using PROJECT_DIR: $PROJECT_DIR"

SCRIPTS_FOLDER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Using SCRIPTS_FOLDER: $SCRIPTS_FOLDER"


args=$#
untar=false
step=1
verbose=false

for (( i=0; i<$args; i+=$step ))
do
    case "$1" in
        -u| --untar )
            untar=true
          step=1
          shift 1
            ;;
        -v| --verbose )
            verbose=true
          step=1
          shift 1
            ;;
        -h | --help )
            help
            ;;
        *)
            echo "Unexpected option: $1"
            help

            ;;
    esac
done

setupHelmDeps() {
    local untar=$1

    cd "$ROOT_DIR"

    rm -rf charts_temp
    echo "Creating temporary directory for charts"
    mkdir -p charts_temp
    echo "Copying Chart.yaml to charts_temp"
    cp Chart.yaml charts_temp/


    echo "# Helm dependencies setup #"
    echo "-- Add PagoPA eks repos --"
    helm repo add interop-eks-microservice-chart https://pagopa.github.io/interop-eks-microservice-chart > /dev/null
    helm repo add interop-eks-cronjob-chart https://pagopa.github.io/interop-eks-cronjob-chart > /dev/null

    echo "-- Update PagoPA eks repo --"
    helm repo update interop-eks-microservice-chart > /dev/null
    helm repo update interop-eks-cronjob-chart > /dev/null

    if [[ $verbose == true ]]; then
        echo "-- Search PagoPA charts in repo --"
        #helm search repo interop-eks-microservice-chart
        #helm search repo interop-eks-cronjob-chart
    else
        helm search repo interop-eks-microservice-chart > /dev/null
        helm search repo interop-eks-cronjob-chart > /dev/null
    fi

    echo "-- Build chart dependencies --"
    cd charts_temp

    if [[ $verbose == true ]]; then
        helm dep list | awk '{printf "%-35s %-15s %-20s\n", $1, $2, $3}'
    fi

    helm dep up

    cd "$ROOT_DIR"
    rm -rf charts
    mkdir -p charts

    if [[ $untar == true ]]; then
        echo "Files in charts_temp after helm dep up:"
        ls -la charts_temp/charts

        for filename in charts_temp/charts/*.tgz; do
            [ -e "$filename" ] || continue
            echo "Processing file: $filename"
            basename_file=$(basename "$filename" .tgz)

            if [[ "$basename_file" == interop-eks-microservice-chart-* ]]; then
                target_dir="charts/interop-eks-microservice-chart"
            elif [[ "$basename_file" == interop-eks-cronjob-chart-* ]]; then
                target_dir="charts/interop-eks-cronjob-chart"
            else
                target_dir="charts/$basename_file"
            fi

            echo "Extracting $filename to $target_dir"
            mkdir -p "$target_dir"
            tar -xzf "$filename" -C "$target_dir" --strip-components=1

            echo "Contents of $target_dir:"
            ls -la "$target_dir"
        done

        cp charts_temp/Chart.yaml charts/
        cp charts_temp/Chart.lock charts/

        echo "-- Final charts directory --"
        ls -laR "$ROOT_DIR/charts"
    else
        mv charts_temp/*.tgz charts/ 2>/dev/null || true
        cp charts_temp/Chart.yaml charts/
        cp charts_temp/Chart.lock charts/
    fi

    rm -rf charts_temp

    # Optional: install helm diff plugin if not present
    set +e
    if ! helm plugin list | grep -q "diff"; then
        helm plugin install https://github.com/databus23/helm-diff
    fi
    set -e

    echo "-- Helm dependencies setup ended --"
    exit 0
}

setupHelmDeps $untar
