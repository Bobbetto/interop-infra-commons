#!/bin/bash
set -euo pipefail

help()
{
    echo "Usage: 
        [ -u | --untar ] Untar downloaded charts
        [ -v | --verbose ] Show debug messages
        [ -h | --help ] This help" 
    exit 2
}

PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"

# Determina ROOT_DIR in modo statico (senza git)
if [[ -f "$PROJECT_DIR/Chart.yaml" ]]; then
    ROOT_DIR="$PROJECT_DIR"
elif [[ -f "$PROJECT_DIR/chart/Chart.yaml" ]]; then
    ROOT_DIR="$PROJECT_DIR/chart"
else
    echo "[ERROR] Chart.yaml not found in either $PROJECT_DIR or $PROJECT_DIR/chart"
    exit 1
fi

SCRIPTS_FOLDER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

function setupHelmDeps() 
{
    local untar=$1

    cd "$ROOT_DIR"

    # Pulizia e creazione directory temporanea
    rm -rf charts_temp
    mkdir -p charts_temp

    # Copia Chart.yaml nella directory temporanea
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
        helm search repo interop-eks-microservice-chart
        helm search repo interop-eks-cronjob-chart
    else
        helm search repo interop-eks-microservice-chart > /dev/null
        helm search repo interop-eks-cronjob-chart > /dev/null
    fi

    echo "-- Build chart dependencies --"
    cd charts_temp

    if [[ $verbose == true ]]; then
        helm dep list | awk '{printf "%-35s %-15s %-20s\n", $1, $2, $3}'
    fi

    dep_up_result=$(helm dep up)
    if [[ $verbose == true ]]; then
        echo "$dep_up_result"
    fi

    # Ora gestiamo la directory charts finale
    cd "$ROOT_DIR"
    rm -rf charts
    mkdir -p charts

    if [[ $untar == true ]]; then
        # Estrai i chart nella directory charts finale con i nomi corretti
        if compgen -G "charts_temp/*.tgz" > /dev/null; then
            for filename in charts_temp/*.tgz; do 
                basename_file=$(basename "$filename" .tgz)
                
                # Determina il nome corretto della directory basandosi sul nome del file
                if [[ "$basename_file" == interop-eks-microservice-chart-* ]]; then
                    target_dir="charts/interop-eks-microservice-chart"
                elif [[ "$basename_file" == interop-eks-cronjob-chart-* ]]; then
                    target_dir="charts/interop-eks-cronjob-chart"
                else
                    # Fallback: usa il nome del file senza versione
                    target_dir="charts/$basename_file"
                fi
                
                echo "Extracting $filename to $target_dir"
                rm -rf "$target_dir"
                mkdir -p "$target_dir"
                tar -xzf "$filename" -C "$target_dir" --strip-components=1
            done
        fi
        
        # Copia anche Chart.yaml e Chart.lock nella directory charts
        cp charts_temp/Chart.yaml charts/
        cp charts_temp/Chart.lock charts/
        
        echo "-- Debugging extracted chart directories --"
        ls -la "$ROOT_DIR/charts"
        
        if [[ -d "$ROOT_DIR/charts/interop-eks-microservice-chart" ]]; then
            echo "Microservice chart contents:"
            ls -la "$ROOT_DIR/charts/interop-eks-microservice-chart" | head -10
        fi
        
        if [[ -d "$ROOT_DIR/charts/interop-eks-cronjob-chart" ]]; then
            echo "Cronjob chart contents:"
            ls -la "$ROOT_DIR/charts/interop-eks-cronjob-chart" | head -10
        fi
    else
        # Se non untar, sposta i .tgz nella directory charts
        mv charts_temp/*.tgz charts/ 2>/dev/null || true
        cp charts_temp/Chart.yaml charts/
        cp charts_temp/Chart.lock charts/
    fi

    # Pulizia directory temporanea
    rm -rf charts_temp

    set +e
    if ! helm plugin list | grep -q "diff"; then
        helm plugin install https://github.com/databus23/helm-diff
        diff_plugin_result=$?
    else
        diff_plugin_result=0
    fi
    if [[ $verbose == true ]]; then
        echo "Helm-Diff plugin install result: $diff_plugin_result"
    fi
    set -e

    echo "-- Helm dependencies setup ended --"
    exit 0
}

setupHelmDeps $untar