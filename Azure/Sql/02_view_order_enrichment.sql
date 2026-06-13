/* =====================================================================
   02_view_order_enrichment.sql  ->  Vista dbo.order_enrichment
   ---------------------------------------------------------------------
   Un pedido (order) por fila, enriquecido con: cliente real
   (customer_unique_id), valor, nº items, categoria dominante, pago,
   resena, metricas de entrega y distancia vendedor-cliente.

   Estados excluidos: 'canceled' y 'unavailable' (sin senal de compra).
   Equivale a la funcion pandas build_order_enrichment() del Sprint 2.

   Requiere: vistas de 01_support_views.sql.
   Uso:      SELECT * FROM dbo.order_enrichment;
   ===================================================================== */
CREATE OR ALTER VIEW dbo.order_enrichment AS
SELECT
    o.order_id,
    c.customer_unique_id,
    c.customer_state,
    c.customer_zip_code_prefix,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,

    /* valor monetario e items */
    it.n_items,
    it.price,
    it.freight_value,
    it.order_value,
    it.n_sellers,

    /* categoria dominante del pedido */
    cat.top_category,

    /* pago */
    pay.payment_type,
    pay.payment_installments,
    pay.payment_value,

    /* resena (variable de control) */
    rev.review_score,

    /* metricas de entrega (variables de control). delay_days > 0 = tardio */
    DATEDIFF(SECOND, o.order_purchase_timestamp,
             o.order_delivered_customer_date) / 86400          AS delivery_days,
    DATEDIFF(SECOND, o.order_estimated_delivery_date,
             o.order_delivered_customer_date) / 86400          AS delay_days,
    CASE
        WHEN o.order_delivered_customer_date IS NULL THEN NULL
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
             THEN 1 ELSE 0
    END                                                        AS is_late,

    /* distancia vendedor-cliente (H5) */
    dist.distance_km

FROM dbo.orders o
LEFT JOIN dbo.customers            c    ON c.customer_id = o.customer_id
LEFT JOIN dbo.vw_order_items_agg    it  ON it.order_id   = o.order_id
LEFT JOIN dbo.vw_order_category     cat ON cat.order_id  = o.order_id
LEFT JOIN dbo.vw_order_payments_agg pay ON pay.order_id  = o.order_id
LEFT JOIN dbo.vw_order_reviews_agg  rev ON rev.order_id  = o.order_id
LEFT JOIN dbo.vw_order_distance     dist ON dist.order_id = o.order_id
WHERE o.order_status NOT IN ('canceled', 'unavailable');
GO
