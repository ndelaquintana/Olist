# -*- coding: utf-8 -*-
"""
Carga las tablas del proyecto Olist en Azure SQL Database leyendo los CSV desde Azure Blob.

Flujo:  Blob (contenedor 'data')  ->  pandas  ->  Azure SQL (tablas)

Requisitos (una vez):
    pip install pandas sqlalchemy pyodbc azure-storage-blob
    ODBC Driver 18 for SQL Server:  https://aka.ms/odbc18  (o Driver 17)
    az login   (para obtener la cadena de conexión del Blob automáticamente)

Uso:
    python cargar_sql_desde_blob.py
    (te pedirá la contraseña del administrador SQL)
"""
import os, io, sys, time, getpass, subprocess, urllib.parse
import pandas as pd

# ----------------------- Configuración -----------------------
STORAGE_ACCOUNT = "olist24206"     # cuenta de Blob donde están los CSV
CONTAINER       = "data"
RESOURCE_GROUP  = "Olist"

# Datos del servidor SQL (rellénalos con la salida de azure_sql_setup.ps1
# o déjalos y el script intentará leer .\sql_conexion.txt)
SQL_SERVER = ""                    # p.ej. olist-sql-12345.database.windows.net
SQL_DB     = "OlistDB"
SQL_ADMIN  = "olistadmin"

# Mapa  archivo CSV en el Blob  ->  nombre de la tabla en SQL
TABLAS = {
    "olist_orders_dataset.csv":            ("orders",              ["order_purchase_timestamp","order_approved_at",
                                                                     "order_delivered_carrier_date","order_delivered_customer_date",
                                                                     "order_estimated_delivery_date"]),
    "olist_customers_dataset.csv":         ("customers",           []),
    "olist_order_items_dataset.csv":       ("order_items",         ["shipping_limit_date"]),
    "olist_order_payments_dataset.csv":    ("order_payments",      []),
    "olist_order_reviews_dataset.csv":     ("order_reviews",       ["review_creation_date","review_answer_timestamp"]),
    "olist_products_dataset.csv":          ("products",            []),
    "olist_sellers_dataset.csv":           ("sellers",             []),
    "product_category_name_translation.csv": ("category_translation", []),
    "geolocation_zip_lookup.csv":          ("geolocation",         []),   # resumen, NO el crudo de 61 MB
}
# -------------------------------------------------------------

def leer_config_archivo():
    global SQL_SERVER, SQL_DB, SQL_ADMIN
    if not SQL_SERVER and os.path.exists("sql_conexion.txt"):
        for line in open("sql_conexion.txt", encoding="utf-8"):
            if "=" in line:
                k, v = line.strip().split("=", 1)
                if k == "SQL_SERVER": SQL_SERVER = v
                if k == "SQL_DB":     SQL_DB = v
                if k == "SQL_ADMIN":  SQL_ADMIN = v

def conexion_blob():
    from azure.storage.blob import BlobServiceClient
    conn = os.environ.get("AZURE_STORAGE_CONNECTION_STRING")
    if not conn:
        r = subprocess.run(
            f"az storage account show-connection-string --name {STORAGE_ACCOUNT} "
            f"--resource-group {RESOURCE_GROUP} --query connectionString -o tsv",
            shell=True, capture_output=True, text=True)
        conn = (r.stdout or "").strip()
    assert conn.startswith("DefaultEndpoints"), "No se obtuvo la cadena del Blob (¿az login?)."
    return BlobServiceClient.from_connection_string(conn).get_container_client(CONTAINER)

def motor_sql(password):
    from sqlalchemy import create_engine
    # Usa ODBC Driver 18; si no está, prueba el 17
    driver = "ODBC Driver 18 for SQL Server"
    try:
        import pyodbc
        if driver not in pyodbc.drivers():
            driver = "ODBC Driver 17 for SQL Server"
    except Exception:
        pass
    odbc = (
        f"Driver={{{driver}}};Server=tcp:{SQL_SERVER},1433;Database={SQL_DB};"
        f"Uid={SQL_ADMIN};Pwd={password};Encrypt=yes;TrustServerCertificate=no;"
        f"Connection Timeout=60;"
    )
    url = "mssql+pyodbc:///?odbc_connect=" + urllib.parse.quote_plus(odbc)
    return create_engine(url, fast_executemany=True)

def main():
    leer_config_archivo()
    if not SQL_SERVER:
        sys.exit("Falta SQL_SERVER. Edita el script o crea sql_conexion.txt (lo genera azure_sql_setup.ps1).")
    pwd = os.environ.get("AZURE_SQL_PASSWORD") or getpass.getpass(f"Contraseña de '{SQL_ADMIN}' en {SQL_SERVER}: ")

    print("Conectando al Blob…")
    container = conexion_blob()
    print("Conectando a Azure SQL…", SQL_SERVER, "/", SQL_DB)
    engine = motor_sql(pwd)

    for archivo, (tabla, fechas) in TABLAS.items():
        t0 = time.time()
        data = container.download_blob(archivo, max_concurrency=8).readall()
        df = pd.read_csv(io.BytesIO(data), parse_dates=fechas or None)
        df.to_sql(tabla, engine, if_exists="replace", index=False, chunksize=1000, method=None)
        print(f"  {tabla:22s} {len(df):>7,} filas  ({time.time()-t0:5.1f}s)")

    print("\nLISTO. Tablas cargadas en Azure SQL:", ", ".join(t for t,_ in TABLAS.values()))

if __name__ == "__main__":
    main()
