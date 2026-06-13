/* =====================================================================
   01_support_views.sql  ->  Vistas de soporte para dbo.order_enrichment
   ---------------------------------------------------------------------
   Una fila por pedido (order_id) en cada vista. Nombres de columnas en
   ingles, siguiendo el estilo de los CSV de Olist.

   Tablas base esperadas en Azure SQL (OlistDB):
     dbo.orders, dbo.customers, dbo.order_items, dbo.order_payments,
     dbo.order_reviews, dbo.products, dbo.product_category_name_translation,
     dbo.sellers, dbo.geolocation_zip_lookup

   Re-ejecutable: CREATE OR ALTER recrea cada vista sin soltarla.
   Orden de despliegue: 01 -> 02 -> 03.
   ===================================================================== */

/* ---------------------------------------------------------------------
   1) vw_order_items_agg: valor monetario y nº de items por pedido.
      order_value = SUM(price) + SUM(freight_value)
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_order_items_agg AS
SELECT  order_id,
        MAX(order_item_id)                          AS n_items,
        SUM(price)                                  AS price,
        SUM(freight_value)                          AS freight_value,
        SUM(price) + SUM(freight_value)             AS order_value,
        COUNT(DISTINCT seller_id)                   AS n_sellers
FROM    dbo.order_items
GROUP BY order_id;
GO

/* ---------------------------------------------------------------------
   2) vw_order_category: categoria dominante del pedido (en ingles si
      existe traduccion; si no, el nombre original en portugues).
      Dominante = la categoria con mayor gasto (price) dentro del pedido.
      Empates -> alfabeticamente la ultima (replica keep='last' de pandas).
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_order_category AS
SELECT  order_id,
        product_category AS top_category
FROM (
    SELECT  oi.order_id,
            COALESCE(t.product_category_name_english,
                     p.product_category_name)           AS product_category,
            ROW_NUMBER() OVER (
                PARTITION BY oi.order_id
                ORDER BY SUM(oi.price) DESC,
                         COALESCE(t.product_category_name_english,
                                  p.product_category_name) DESC) AS rn
    FROM    dbo.order_items oi
    LEFT JOIN dbo.products p  ON p.product_id = oi.product_id
    LEFT JOIN dbo.product_category_name_translation t
           ON t.product_category_name = p.product_category_name
    GROUP BY oi.order_id,
             COALESCE(t.product_category_name_english, p.product_category_name)
) z
WHERE z.rn = 1;
GO

/* ---------------------------------------------------------------------
   3) vw_order_payments_agg: pago por pedido.
      payment_type = tipo de la fila con mayor payment_value (dominante).
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_order_payments_agg AS
SELECT  tot.order_id,
        tot.payment_value,
        tot.payment_installments,
        dom.payment_type
FROM (
    SELECT  order_id,
            SUM(payment_value)        AS payment_value,
            MAX(payment_installments) AS payment_installments
    FROM    dbo.order_payments
    GROUP BY order_id
) tot
LEFT JOIN (
    SELECT order_id, payment_type
    FROM (
        SELECT  order_id, payment_type,
                ROW_NUMBER() OVER (PARTITION BY order_id
                                   ORDER BY payment_value DESC) AS rn
        FROM    dbo.order_payments
    ) p
    WHERE p.rn = 1
) dom ON dom.order_id = tot.order_id;
GO

/* ---------------------------------------------------------------------
   4) vw_order_reviews_agg: review_score medio por pedido
      (un pedido puede tener mas de una resena).
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_order_reviews_agg AS
SELECT  order_id,
        AVG(CAST(review_score AS float)) AS review_score
FROM    dbo.order_reviews
GROUP BY order_id;
GO

/* ---------------------------------------------------------------------
   5) vw_order_distance: distancia media vendedor-cliente por pedido (km),
      formula de haversine sobre las coordenadas medianas por prefijo
      postal de dbo.geolocation_zip_lookup (lat, lng).
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_order_distance AS
SELECT  oi.order_id,
        AVG(
            2.0 * 6371.0 * ASIN(SQRT(
                POWER(SIN(RADIANS(gc.lat - gs.lat) / 2.0), 2) +
                COS(RADIANS(gs.lat)) * COS(RADIANS(gc.lat)) *
                POWER(SIN(RADIANS(gc.lng - gs.lng) / 2.0), 2)
            ))
        ) AS distance_km
FROM    dbo.order_items oi
JOIN    dbo.orders    o  ON o.order_id    = oi.order_id
JOIN    dbo.customers c  ON c.customer_id = o.customer_id
JOIN    dbo.sellers   s  ON s.seller_id   = oi.seller_id
JOIN    dbo.geolocation_zip_lookup gc
           ON gc.geolocation_zip_code_prefix = c.customer_zip_code_prefix
JOIN    dbo.geolocation_zip_lookup gs
           ON gs.geolocation_zip_code_prefix = s.seller_zip_code_prefix
GROUP BY oi.order_id;
GO
