/* =====================================================================
   05_integrity_constraints.sql  ->  Integridad referencial de OlistDB
   ---------------------------------------------------------------------
   Anade las RELACIONES (FOREIGN KEY) entre las tablas base, completa la
   PRIMARY KEY que falta (order_reviews) y renombra las PK autogeneradas
   a nombres estables. Re-ejecutable: cada paso es idempotente.

   Estado verificado contra los datos (jun-2026) antes de escribirlo:
     - (review_id, order_id) es unico en order_reviews        -> PK compuesta OK
     - orders.customer_id, order_items.order_id/product_id/seller_id,
       order_payments.order_id y order_reviews.order_id       -> 0 huerfanos
       (las seis FK se crean WITH CHECK: quedan CONFIABLES/trusted)
     - products.product_category_name: 13 productos en 2 categorias sin
       traduccion ('pc_gamer', 'portateis_cozinha_e_preparadores_de_
       alimentos')                                            -> FK WITH NOCHECK
     - customers/sellers zip -> geolocation_zip_lookup: 24.264 y 1.032
       huerfanos (cobertura incompleta del lookup y ceros a la izquierda
       perdidos al generarlo)                                 -> SIN FK (ver nota)
     - geolocation (cruda): sin PK a proposito (multiples filas por
       prefijo postal)                                        -> no puede ser destino de FK

   Sin ON DELETE/ON UPDATE CASCADE: base analitica de carga masiva; un
   borrado debe fallar, no propagarse en silencio.

   Orden de despliegue: 04_load_tables.sql -> ESTE script (las vistas
   01..03 son independientes).
   ===================================================================== */

SET NOCOUNT ON;
GO

/* =====================================================================
   1) Renombrar las PRIMARY KEY autogeneradas a nombres estables
      (PK__customer__CD65... -> PK_customers). Solo si el nombre nuevo
      no existe ya; excluye la tabla de sistema sysdiagrams.
   ===================================================================== */
PRINT '== Paso 1: nombres estables para las PRIMARY KEY ==';

DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql += N'EXEC sp_rename N''' + QUOTENAME(SCHEMA_NAME(kc.schema_id))
            + N'.' + QUOTENAME(kc.name) + N''', N''PK_' + t.name + N''';'
            + CHAR(10)
FROM sys.key_constraints kc
JOIN sys.tables t ON t.object_id = kc.parent_object_id
WHERE kc.[type] = 'PK'
  AND kc.name LIKE 'PK\_\_%' ESCAPE '\'
  AND t.name <> 'sysdiagrams'
  AND NOT EXISTS (SELECT 1 FROM sys.key_constraints x
                  WHERE x.name = 'PK_' + t.name);
IF @sql <> N''
BEGIN
    PRINT @sql;
    EXEC sys.sp_executesql @sql;
END
ELSE
    PRINT 'PKs ya tienen nombre estable.';
GO

/* =====================================================================
   2) PRIMARY KEY pendiente: order_reviews
      review_id NO es unico en Olist (una resena puede cubrir varios
      pedidos) -> clave compuesta (review_id, order_id), verificada sin
      duplicados.
   ===================================================================== */
PRINT '== Paso 2: PRIMARY KEY de order_reviews ==';

IF NOT EXISTS (SELECT 1 FROM sys.key_constraints
               WHERE [type] = 'PK'
                 AND parent_object_id = OBJECT_ID('dbo.order_reviews'))
    ALTER TABLE dbo.order_reviews
        ADD CONSTRAINT PK_order_reviews PRIMARY KEY (review_id, order_id);
GO

/* =====================================================================
   3) FOREIGN KEY del nucleo transaccional (WITH CHECK: 0 huerfanos
      verificados -> el optimizador puede confiar en ellas)
   ===================================================================== */
PRINT '== Paso 3: FOREIGN KEY del nucleo ==';

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_orders_customers')
    ALTER TABLE dbo.orders WITH CHECK
        ADD CONSTRAINT FK_orders_customers
        FOREIGN KEY (customer_id) REFERENCES dbo.customers (customer_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_order_items_orders')
    ALTER TABLE dbo.order_items WITH CHECK
        ADD CONSTRAINT FK_order_items_orders
        FOREIGN KEY (order_id) REFERENCES dbo.orders (order_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_order_items_products')
    ALTER TABLE dbo.order_items WITH CHECK
        ADD CONSTRAINT FK_order_items_products
        FOREIGN KEY (product_id) REFERENCES dbo.products (product_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_order_items_sellers')
    ALTER TABLE dbo.order_items WITH CHECK
        ADD CONSTRAINT FK_order_items_sellers
        FOREIGN KEY (seller_id) REFERENCES dbo.sellers (seller_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_order_payments_orders')
    ALTER TABLE dbo.order_payments WITH CHECK
        ADD CONSTRAINT FK_order_payments_orders
        FOREIGN KEY (order_id) REFERENCES dbo.orders (order_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_order_reviews_orders')
    ALTER TABLE dbo.order_reviews WITH CHECK
        ADD CONSTRAINT FK_order_reviews_orders
        FOREIGN KEY (order_id) REFERENCES dbo.orders (order_id);
GO

/* =====================================================================
   4) FOREIGN KEY de catalogo: products -> category_translation
      WITH NOCHECK: 13 productos en 2 categorias sin traduccion en el
      dataset original. No valida las filas existentes (is_not_trusted=1)
      pero SI exige traduccion a toda categoria nueva que se inserte.
      Alternativa documentada: insertar las 2 traducciones faltantes y
      promover con  ALTER TABLE ... WITH CHECK CHECK CONSTRAINT ...
   ===================================================================== */
PRINT '== Paso 4: FOREIGN KEY de catalogo (WITH NOCHECK) ==';

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_products_category_translation')
    ALTER TABLE dbo.products WITH NOCHECK
        ADD CONSTRAINT FK_products_category_translation
        FOREIGN KEY (product_category_name)
        REFERENCES dbo.product_category_name_translation (product_category_name);
GO

/* =====================================================================
   5) Relaciones documentadas pero NO forzadas (a proposito)
   ---------------------------------------------------------------------
   - customers.customer_zip_code_prefix  -> geolocation_zip_lookup
   - sellers.seller_zip_code_prefix      -> geolocation_zip_lookup
     El lookup es una tabla DERIVADA (centroide por prefijo, Sprint 1):
     no cubre todos los prefijos usados por clientes/vendedores (24.264 y
     1.032 filas sin correspondencia) y sus claves perdieron los ceros a
     la izquierda al generarse ('1037' vs '01037'). Un FK aqui impediria
     ademas registrar clientes de prefijos nuevos. Los consumidores usan
     LEFT JOIN y toleran la ausencia (distance_km NULL).
   - geolocation (cruda): sin PK (multiples filas por prefijo); no puede
     ser destino de FK.
   ===================================================================== */

/* =====================================================================
   6) Verificacion: relaciones creadas y si son confiables (trusted)
   ===================================================================== */
PRINT '== Paso 6: verificacion ==';

SELECT fk.name                                  AS foreign_key,
       OBJECT_NAME(fk.parent_object_id)         AS tabla_hija,
       OBJECT_NAME(fk.referenced_object_id)     AS tabla_padre,
       fk.is_not_trusted                        AS no_confiable
FROM sys.foreign_keys fk
ORDER BY tabla_hija, foreign_key;

SELECT kc.name                                  AS primary_key,
       OBJECT_NAME(kc.parent_object_id)         AS tabla
FROM sys.key_constraints kc
JOIN sys.tables t ON t.object_id = kc.parent_object_id
WHERE kc.[type] = 'PK' AND t.name <> 'sysdiagrams'
ORDER BY tabla;
GO

/* =====================================================================
   APENDICE — Diagnostico previo (consultas usadas para validar)
   ---------------------------------------------------------------------
   -- Duplicados que impedirian la PK de order_reviews:
   --   SELECT review_id, order_id, COUNT(*) FROM dbo.order_reviews
   --   GROUP BY review_id, order_id HAVING COUNT(*) > 1;
   -- Huerfanos de cada FK (ejemplo order_items -> orders):
   --   SELECT COUNT(*) FROM dbo.order_items i
   --   LEFT JOIN dbo.orders o ON o.order_id = i.order_id
   --   WHERE o.order_id IS NULL;
   -- Categorias de products sin traduccion:
   --   SELECT DISTINCT p.product_category_name FROM dbo.products p
   --   LEFT JOIN dbo.product_category_name_translation t
   --     ON t.product_category_name = p.product_category_name
   --   WHERE p.product_category_name IS NOT NULL
   --     AND t.product_category_name IS NULL;
   -- Promover la FK de catalogo a confiable tras completar traducciones:
   --   INSERT INTO dbo.product_category_name_translation VALUES
   --       ('pc_gamer', 'pc_gamer'),
   --       ('portateis_cozinha_e_preparadores_de_alimentos',
   --        'kitchen_portables_and_food_preparers');
   --   ALTER TABLE dbo.products WITH CHECK
   --       CHECK CONSTRAINT FK_products_category_translation;
   ===================================================================== */
