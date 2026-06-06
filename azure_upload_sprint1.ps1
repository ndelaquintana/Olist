# =============================================================================
#  Subir el proyecto Olist a Azure (Blob Storage) con la CLI de Azure - PowerShell
#  - Grupo de recursos: Olist
#  - Sube los CSV de Data/      -> contenedor "data"
#  - Sube el notebook Sprint 1  -> contenedor "notebooks"
#
#  Uso (desde la carpeta del proyecto Olist):
#     az login --tenant 8839e3cd-80cc-418d-8eec-2c837be914d9   # si aún no lo hiciste
#     .\azure_upload_sprint1.ps1
#
#  Si PowerShell bloquea el script, primero:
#     Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
# =============================================================================

$ErrorActionPreference = "Stop"

# ---------- Parámetros editables ----------
$RG            = "Olist"                          # grupo de recursos (se crea en westus3)
# brazilsouth está bloqueada por la política de Azure for Students.
# westus3 SÍ está permitida (tus otros grupos ya la usan).
$LOCATION      = "westus3"
# Nombre de la cuenta de storage: ÚNICO GLOBAL, 3-24, solo minúsculas y números
$STORAGE       = "olist$(Get-Random -Minimum 10000 -Maximum 99999)"
$CONTAINER_DATA = "data"
$CONTAINER_NB   = "notebooks"
$DATA_DIR       = ".\Data"
$NOTEBOOK       = ".\Notebooks\sprint1_eda_churn.ipynb"
# ------------------------------------------

Write-Host "==> Suscripción activa:" -ForegroundColor Cyan
az account show --output table

Write-Host "`n==> 1) Usar el grupo de recursos '$RG' (lo crea si no existe)" -ForegroundColor Cyan
az group create --name $RG --location $LOCATION --only-show-errors | Out-Null

Write-Host "==> 2) Crear cuenta de almacenamiento '$STORAGE' (Standard LRS, la más barata)" -ForegroundColor Cyan
az storage account create `
  --name $STORAGE --resource-group $RG --location $LOCATION `
  --sku Standard_LRS --kind StorageV2 --only-show-errors | Out-Null

if ($LASTEXITCODE -ne 0) {
  Write-Host "`nNo se pudo crear la cuenta de almacenamiento en '$LOCATION'." -ForegroundColor Red
  Write-Host "Probablemente la región está bloqueada por la política de tu suscripción." -ForegroundColor Red
  Write-Host "Edita `$LOCATION arriba y prueba otra: eastus, westus2, centralus o westeurope." -ForegroundColor Yellow
  exit 1
}

# Clave de la cuenta para autenticar las subidas
$KEY = az storage account keys list --account-name $STORAGE --resource-group $RG `
       --query "[0].value" -o tsv
if ([string]::IsNullOrWhiteSpace($KEY)) {
  Write-Host "No se obtuvo la clave de la cuenta; abortando." -ForegroundColor Red
  exit 1
}

Write-Host "==> 3) Crear contenedores '$CONTAINER_DATA' y '$CONTAINER_NB'" -ForegroundColor Cyan
az storage container create --name $CONTAINER_DATA --account-name $STORAGE --account-key $KEY --only-show-errors | Out-Null
az storage container create --name $CONTAINER_NB   --account-name $STORAGE --account-key $KEY --only-show-errors | Out-Null

Write-Host "==> 4) Subir todos los CSV de $DATA_DIR -> contenedor '$CONTAINER_DATA'" -ForegroundColor Cyan
az storage blob upload-batch `
  --account-name $STORAGE --account-key $KEY `
  --destination $CONTAINER_DATA --source $DATA_DIR `
  --pattern "*.csv" --overwrite

Write-Host "==> 5) Subir el notebook del Sprint 1 -> contenedor '$CONTAINER_NB'" -ForegroundColor Cyan
az storage blob upload `
  --account-name $STORAGE --account-key $KEY `
  --container-name $CONTAINER_NB `
  --file $NOTEBOOK --name "sprint1_eda_churn.ipynb" --overwrite

Write-Host "`n==> LISTO. Archivos en el contenedor '$CONTAINER_DATA':" -ForegroundColor Green
az storage blob list --account-name $STORAGE --account-key $KEY `
  --container-name $CONTAINER_DATA --query "[].name" -o tsv
Write-Host "   notebooks/sprint1_eda_churn.ipynb"

Write-Host "`nCuenta de almacenamiento: $STORAGE" -ForegroundColor Yellow
Write-Host "Para borrar TODO al terminar y no gastar crédito:" -ForegroundColor Yellow
Write-Host "   az group delete --name $RG --yes"
