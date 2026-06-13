# Azure/Sql — Objetos SQL del Sprint 2 (OlistDB)

Orden de despliegue (re-ejecutables, `CREATE OR ALTER` / `IF NOT EXISTS`):

1. `04_load_tables.sql` — crea y carga las tablas base desde el blob público (`BULK INSERT`).
2. `05_integrity_constraints.sql` — integridad referencial: PK de `order_reviews` (compuesta), 7 `FOREIGN KEY` (6 `WITH CHECK` verificadas sin huérfanos + catálogo de categorías `WITH NOCHECK`), renombra las PK autogeneradas a nombres estables y documenta las relaciones no forzadas (zip → lookup, geolocation cruda).
3. `01_support_views.sql` — vistas de soporte por pedido: `vw_order_items_agg`, `vw_order_category`, `vw_order_payments_agg`, `vw_order_reviews_agg`, `vw_order_distance`.
4. `02_view_order_enrichment.sql` — vista `order_enrichment` (un pedido por fila, enriquecido; excluye `canceled`/`unavailable`).
5. `03_sp_build_master_table.sql` — `sp_build_master_table @cutoff_date, @horizon_days=90`: tabla maestra por `customer_unique_id` con features ≤ t y targets en (t, t+H] (`purchased_next_h`, `is_churn`, `is_repeat`), sin fuga de información.

Nota: el notebook `Notebooks/sprint2_eda_churn_sql.ipynb` **no** usa las vistas ni el SP (lleva sus propias consultas analíticas inline); los objetos 01–03 quedan como espejo versionado para otros consumidores.

Uso:

```sql
EXEC dbo.sp_build_master_table @cutoff_date = '2018-05-31', @horizon_days = 90;
```

Tablas base esperadas: `orders`, `customers`, `order_items`, `order_payments`, `order_reviews`, `products`, `product_category_name_translation`, `sellers`, `geolocation_zip_lookup`.

Credenciales: `sql_conexion.txt` (no versionar la contraseña).
