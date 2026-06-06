#!/usr/bin/env bash
# =============================================================================
#  Subir el proyecto Olist a Azure (Blob Storage) con la CLI de Azure
#  - Grupo de recursos: Olist
#  - Sube los CSV de Data/  -> contenedor "data"
#  - Sube el notebook Sprint 1 -> contenedor "notebooks"
#
#  Requisitos: Azure CLI (az). Ejecuta en Git Bash, WSL o Azure Cloud Shell.
#  Instalar az:  https://learn.microsoft.com/cli/azure/install-azure-cli
# =============================================================================
set -euo pipefail

# ---------- Parámetros editables ----------
RG="Olist"                                  # grupo de recursos
LOCATION="brazilsouth"                       # región (Olist es de Brasil)
# El nombre de la cuenta de storage debe ser ÚNICO GLOBAL, 3-24, minúsculas/números:
STORAGE="olist$RANDOM"                        # p.ej. olist12345
CONTAINER_DATA="data"
CONTAINER_NB="notebooks"
DATA_DIR="./Data"
NOTEBOOK="./Notebooks/sprint1_eda_churn.ipynb"
# ------------------------------------------

echo "==> 1) Login (se abrirá el navegador)"
az login --only-show-errors >/dev/null

echo "==> 2) Crear grupo de recursos '$RG' en $LOCATION"
az group create --name "$RG" --location "$LOCATION" --only-show-errors >/dev/null

echo "==> 3) Crear cuenta de almacenamiento '$STORAGE' (Standard LRS, la más barata)"
az storage account create \
  --name "$STORAGE" --resource-group "$RG" --location "$LOCATION" \
  --sku Standard_LRS --kind StorageV2 --only-show-errors >/dev/null

# Clave de la cuenta para autenticar las subidas
KEY=$(az storage account keys list --account-name "$STORAGE" --resource-group "$RG" \
      --query "[0].value" -o tsv)

echo "==> 4) Crear contenedores '$CONTAINER_DATA' y '$CONTAINER_NB'"
az storage container create --name "$CONTAINER_DATA" \
  --account-name "$STORAGE" --account-key "$KEY" --only-show-errors >/dev/null
az storage container create --name "$CONTAINER_NB" \
  --account-name "$STORAGE" --account-key "$KEY" --only-show-errors >/dev/null

echo "==> 5) Subir todos los CSV de $DATA_DIR -> contenedor '$CONTAINER_DATA'"
az storage blob upload-batch \
  --account-name "$STORAGE" --account-key "$KEY" \
  --destination "$CONTAINER_DATA" --source "$DATA_DIR" \
  --pattern "*.csv" --overwrite

echo "==> 6) Subir el notebook del Sprint 1 -> contenedor '$CONTAINER_NB'"
az storage blob upload \
  --account-name "$STORAGE" --account-key "$KEY" \
  --container-name "$CONTAINER_NB" \
  --file "$NOTEBOOK" --name "sprint1_eda_churn.ipynb" --overwrite

echo ""
echo "==> LISTO. Recursos creados en el grupo '$RG':"
az storage blob list --account-name "$STORAGE" --account-key "$KEY" \
  --container-name "$CONTAINER_DATA" --query "[].name" -o tsv | sed 's/^/   data\//'
echo "   notebooks/sprint1_eda_churn.ipynb"
echo ""
echo "Cuenta de almacenamiento: $STORAGE"
echo "Para borrar TODO al terminar y no gastar crédito:  az group delete --name $RG --yes"
