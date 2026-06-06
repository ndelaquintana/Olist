# =============================================================================
#  Crear Azure SQL Database (Serverless General Purpose) para el proyecto Olist
#  - Servidor lógico SQL + base serverless (auto-pausa) en el grupo de recursos Olist
#  - Regla de firewall para tu IP pública (para poder cargar datos desde tu PC)
#
#  Uso:   az login   (si aún no lo hiciste)
#         .\azure_sql_setup.ps1
# =============================================================================
$ErrorActionPreference = "Stop"

# ---------- Parámetros editables ----------
$RG       = "Olist"
$LOCATION = "westus3"                                  # región permitida por tu política
$SERVER   = "olist-sql-$(Get-Random -Minimum 10000 -Maximum 99999)"  # único global, minúsculas
$DB       = "OlistDB"
$ADMIN    = "olistadmin"
# ------------------------------------------

Write-Host "==> 0) Registrar el proveedor Microsoft.Sql (una sola vez por suscripción)" -ForegroundColor Cyan
$state = az provider show --namespace Microsoft.Sql --query registrationState -o tsv 2>$null
if ($state -ne "Registered") {
    az provider register --namespace Microsoft.Sql --only-show-errors | Out-Null
    Write-Host "    Registrando Microsoft.Sql... (puede tardar unos minutos)" -ForegroundColor DarkGray
    do {
        Start-Sleep -Seconds 10
        $state = az provider show --namespace Microsoft.Sql --query registrationState -o tsv 2>$null
        Write-Host "    estado: $state"
    } while ($state -ne "Registered")
}
Write-Host "    Microsoft.Sql: Registered" -ForegroundColor DarkGray

Write-Host "`n==> Contraseña del administrador SQL" -ForegroundColor Cyan
Write-Host "    (mínimo 8 caracteres, con mayúscula, minúscula y número o símbolo)" -ForegroundColor DarkGray
$sec = Read-Host "Define la contraseña para '$ADMIN'" -AsSecureString
$PWD_PLAIN = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))

Write-Host "`n==> 1) Crear servidor lógico SQL '$SERVER' en $LOCATION" -ForegroundColor Cyan
az sql server create `
  --name $SERVER --resource-group $RG --location $LOCATION `
  --admin-user $ADMIN --admin-password $PWD_PLAIN --only-show-errors | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "Falló la creación del servidor (¿región o contraseña?)." -ForegroundColor Red; exit 1 }

Write-Host "==> 2) Crear base de datos '$DB' (Serverless General Purpose, auto-pausa 60 min)" -ForegroundColor Cyan
az sql db create `
  --resource-group $RG --server $SERVER --name $DB `
  --edition GeneralPurpose --compute-model Serverless --family Gen5 --capacity 2 `
  --min-capacity 0.5 --auto-pause-delay 60 `
  --backup-storage-redundancy Local --only-show-errors | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "Falló la creación de la base de datos." -ForegroundColor Red; exit 1 }

Write-Host "==> 3) Regla de firewall para tu IP pública" -ForegroundColor Cyan
$myip = (Invoke-RestMethod -Uri "https://api.ipify.org").Trim()
az sql server firewall-rule create `
  --resource-group $RG --server $SERVER --name "AllowMyIP" `
  --start-ip-address $myip --end-ip-address $myip --only-show-errors | Out-Null
Write-Host "    IP permitida: $myip" -ForegroundColor DarkGray

$FQDN = "$SERVER.database.windows.net"
Write-Host "`n==> LISTO. Base de datos creada:" -ForegroundColor Green
Write-Host "   Servidor : $FQDN"
Write-Host "   Base     : $DB"
Write-Host "   Usuario  : $ADMIN"
Write-Host "`nGuarda estos datos. Para cargar las tablas, usa cargar_sql_desde_blob.py con estos valores."
Write-Host "Para borrar todo al terminar:  az group delete --name $RG --yes" -ForegroundColor Yellow

# Deja los datos de conexión (sin contraseña) en un archivo para el cargador
@"
SQL_SERVER=$FQDN
SQL_DB=$DB
SQL_ADMIN=$ADMIN
"@ | Set-Content -Path ".\sql_conexion.txt" -Encoding UTF8
Write-Host "`nDatos de conexión guardados en .\sql_conexion.txt"
