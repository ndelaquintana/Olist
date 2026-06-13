# Azure Databricks — Olist

Workspace y pipeline automático de entrenamiento del modelo de churn / 2ª compra.

## Objetos en Azure (grupo de recursos `olist-group`)

| Objeto | Nombre | Detalle |
|---|---|---|
| Workspace Databricks | `olist-databricks-workspace` | SKU Premium (Standard deprecado), westus3 |
| Grupo administrado | `olist-databricks-managed-rg` | Lo crea Databricks para sus VMs/red/storage |
| URL | https://adb-7405608765888145.5.azuredatabricks.net | Entrar con la cuenta de Azure |

## Objetos dentro del workspace

| Objeto | Nombre | Detalle |
|---|---|---|
| Notebooks | `/Olist/sprint2_eda_churn`, `/Olist/sprint2_pipeline` | Subidos desde `Notebooks/` |
| Notebook de entrenamiento | `/Olist/olist_train_pipeline` | Fuente: `Azure/Databricks/olist_train_pipeline.py` |
| Clúster interactivo | `olist-cluster-interactivo` | Single node `Standard_DS3_v2` (4 cores/14 GB, única familia con cuota en la suscripción de estudiante), runtime ML 17.3 LTS, **auto-apagado a los 30 min sin uso**. Queda terminado: arrancarlo al usarlo |
| Job programado | `olist-job-entrenamiento-churn` | Día 1 de cada mes 06:00 UTC. Clúster efímero single node que **se apaga solo al terminar** (timeout 1 h) |
| Experimento MLflow | `/Shared/olist-churn-experiment` | Métricas de validación y backtest por ejecución |
| Modelo registrado | `olist-churn-model` | Pipeline sklearn completo (preprocesado + clasificador) |

## Pipeline de entrenamiento (`olist_train_pipeline`)

1. Lee los 9 CSV del blob público `https://oliststorage40548.blob.core.windows.net/olist-data/` (sin credenciales).
2. Construye `order_enrichment` y la tabla maestra por snapshots mensuales (sin fuga: features ≤ t, target en (t, t+H]).
3. Población MVP: clientes primerizos; partición out-of-time train/validation/backtest.
4. Entrena regresión logística y HistGradientBoosting, elige por AUC en validación.
5. **Hiperparametriza** el modelo ganador con `RandomizedSearchCV` y **validación cruzada walk-forward** sobre los snapshots del train (cada fold valida el mes siguiente); adopta los hiperparámetros solo si no empeoran la AUC out-of-time. Registra `cv_auc_walkforward`, `valid_auc_tuned` y los mejores parámetros en MLflow.
6. Reentrena con train+valid, evalúa una única vez en backtest y registra todo en MLflow.

Parámetros del job (widgets): `horizon_days` (90), `snapshot_start`, `snapshot_end`.

## Costos / auto-apagado

- El job usa un clúster efímero: existe solo durante la ejecución mensual.
- El clúster interactivo se auto-termina a los 30 minutos de inactividad.
- Terminados no facturan cómputo; solo queda el costo fijo despreciable del storage administrado.
