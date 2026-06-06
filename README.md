# Olist — Análisis de Churn

Análisis exploratorio y modelo baseline de churn de clientes sobre el dataset público de **Olist** (e-commerce brasileño).

**Autor:** Nelson De La Quintana

## Estructura

```
Data/                          Datasets crudos de Olist (CSV)
Notebooks/
  sprint1_eda_churn*.ipynb     EDA y definición de churn (Sprint 1)
  sprint2_pipeline_sql.ipynb   Pipeline de modelado (Sprint 2)
  olist_analisis.ipynb         Análisis general
  pipeline_churn_sprint2.pkl   Pipeline serializado
  cargar_sql_desde_blob.py     Carga de datos desde Azure Blob a SQL
  azure_sql_setup.ps1          Setup de Azure SQL
azure_upload_sprint1.{sh,ps1}  Subida de datasets/notebook a Azure Blob
Presentacion_Churn_Olist.pptx  Presentación de resultados
```

## Cómo correrlo

```bash
cd Notebooks
python -m venv .venv
.venv\Scripts\activate          # Windows
pip install -r requirements.txt
jupyter lab
```

## Dataset

Brazilian E-Commerce Public Dataset by Olist (Kaggle).
