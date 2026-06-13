/* =====================================================================
   03_sp_build_master_table.sql  ->  dbo.sp_build_master_table(@cutoff_date, @horizon_days)
   ---------------------------------------------------------------------
   Procedimiento almacenado que construye la TABLA MAESTRA a nivel de
   cliente (customer_unique_id) para una fecha de corte @cutoff_date y
   un horizonte @horizon_days. Lee de dbo.order_enrichment.

   SIN FUGA DE INFORMACION:
     - Features: solo pedidos con order_purchase_timestamp <= @cutoff_date.
     - Targets : solo pedidos en (@cutoff_date, @cutoff_date + @horizon_days].

   Targets devueltos:
     - purchased_next_h : 1 si el cliente compra en (t, t+H].
     - is_churn         : 1 - purchased_next_h (indicador de negocio;
                          degenerado como target de modelado en Olist).
     - is_repeat        : target del MVP. Definido sobre clientes con
                          frequency = 1 en t (primer pedido ya realizado):
                          1 si hacen su 2ª compra en (t, t+H]; 0 si no;
                          NULL para clientes ya recurrentes en t.

   Uso:
     EXEC dbo.sp_build_master_table @cutoff_date = '2018-05-31',
                                    @horizon_days = 90;

   Requiere: 01_support_views.sql y 02_view_order_enrichment.sql.
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.sp_build_master_table
    @cutoff_date  DATE,
    @horizon_days INT = 90
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @t     DATETIME2 = CAST(@cutoff_date AS DATETIME2);
    DECLARE @t_end DATETIME2 = DATEADD(DAY, @horizon_days, @t);

    ;WITH
    /* obs = ventana de observacion: pedidos <= t (features, sin fuga) */
    obs AS (
        SELECT *
        FROM   dbo.order_enrichment
        WHERE  order_purchase_timestamp <= @t
    ),

    /* fut = clientes que compran en (t, t+H] (define los targets) */
    fut AS (
        SELECT DISTINCT customer_unique_id
        FROM   dbo.order_enrichment
        WHERE  order_purchase_timestamp >  @t
          AND  order_purchase_timestamp <= @t_end
    ),

    /* agg = RFM + features de comportamiento por cliente a fecha t.
       Dias enteros (segundos/86400) para igualar (t - fecha).dt.days
       de pandas. */
    agg AS (
        SELECT
            customer_unique_id,
            DATEDIFF(SECOND, MAX(order_purchase_timestamp), @t) / 86400 AS recency_days,
            COUNT(DISTINCT order_id)                                    AS frequency,
            SUM(order_value)                                            AS monetary,
            DATEDIFF(SECOND, MIN(order_purchase_timestamp), @t) / 86400 AS tenure_days,
            AVG(CAST(n_items AS float))                                 AS avg_items,
            AVG(order_value)                                            AS avg_order_value,
            AVG(freight_value)                                          AS avg_freight_value,
            MAX(CAST(payment_installments AS float))                    AS max_installments,
            AVG(CAST(review_score AS float))                            AS avg_review_score,
            AVG(CAST(delay_days   AS float))                            AS avg_delay_days,
            AVG(CAST(is_late      AS float))                            AS pct_late_deliveries,
            AVG(distance_km)                                            AS avg_distance_km
        FROM   obs
        GROUP  BY customer_unique_id
    ),

    /* valores dominantes (modales) por cliente. Empates -> alfabeticamente
       el ultimo (replica drop_duplicates(keep='last') de pandas). */
    dom_state AS (
        SELECT customer_unique_id, customer_state
        FROM (
            SELECT customer_unique_id, customer_state,
                   ROW_NUMBER() OVER (PARTITION BY customer_unique_id
                        ORDER BY COUNT(*) DESC, customer_state DESC) AS rn
            FROM   obs
            WHERE  customer_state IS NOT NULL
            GROUP  BY customer_unique_id, customer_state
        ) z WHERE rn = 1
    ),
    dom_category AS (
        SELECT customer_unique_id, top_category
        FROM (
            SELECT customer_unique_id, top_category,
                   ROW_NUMBER() OVER (PARTITION BY customer_unique_id
                        ORDER BY COUNT(*) DESC, top_category DESC) AS rn
            FROM   obs
            WHERE  top_category IS NOT NULL
            GROUP  BY customer_unique_id, top_category
        ) z WHERE rn = 1
    ),
    dom_payment AS (
        SELECT customer_unique_id, payment_type
        FROM (
            SELECT customer_unique_id, payment_type,
                   ROW_NUMBER() OVER (PARTITION BY customer_unique_id
                        ORDER BY COUNT(*) DESC, payment_type DESC) AS rn
            FROM   obs
            WHERE  payment_type IS NOT NULL
            GROUP  BY customer_unique_id, payment_type
        ) z WHERE rn = 1
    )

    SELECT
        @cutoff_date                                   AS snapshot_date,
        @horizon_days                                  AS horizon_days,
        a.customer_unique_id,

        /* --- features (solo informacion <= t) --- */
        a.recency_days,
        a.frequency,
        a.monetary,
        a.tenure_days,
        a.avg_items,
        a.avg_order_value,
        a.avg_freight_value,
        a.max_installments,
        ds.customer_state,
        dc.top_category,
        dp.payment_type,
        a.avg_review_score,        /* variable de control */
        a.avg_delay_days,          /* variable de control */
        a.pct_late_deliveries,     /* variable de control */
        a.avg_distance_km,

        /* --- targets (solo informacion > t) --- */
        CASE WHEN f.customer_unique_id IS NULL THEN 0 ELSE 1 END AS purchased_next_h,
        CASE WHEN f.customer_unique_id IS NULL THEN 1 ELSE 0 END AS is_churn,
        CASE WHEN a.frequency = 1
             THEN CASE WHEN f.customer_unique_id IS NULL THEN 0 ELSE 1 END
             ELSE NULL
        END                                                      AS is_repeat

    FROM agg a
    LEFT JOIN dom_state    ds ON ds.customer_unique_id = a.customer_unique_id
    LEFT JOIN dom_category dc ON dc.customer_unique_id = a.customer_unique_id
    LEFT JOIN dom_payment  dp ON dp.customer_unique_id = a.customer_unique_id
    LEFT JOIN fut          f  ON f.customer_unique_id  = a.customer_unique_id;
END
GO
