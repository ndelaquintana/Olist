-- Carga de las tablas Olist en Azure SQL (OlistDB) desde el blob storage publico
-- Origen: https://oliststorage40548.blob.core.windows.net/olist-data (acceso anonimo de lectura)
-- Ejecutar conectado a OlistDB (no a master)

IF NOT EXISTS (SELECT 1 FROM sys.external_data_sources WHERE name = 'OlistBlob')
    CREATE EXTERNAL DATA SOURCE OlistBlob
    WITH (TYPE = BLOB_STORAGE, LOCATION = 'https://oliststorage40548.blob.core.windows.net/olist-data');
GO

-------------------------------------------------------------------------------
DROP TABLE IF EXISTS dbo.customers;
CREATE TABLE dbo.customers (
    customer_id              CHAR(32)      NOT NULL PRIMARY KEY,
    customer_unique_id       CHAR(32)      NOT NULL,
    customer_zip_code_prefix VARCHAR(5)    NOT NULL,
    customer_city            NVARCHAR(100) NULL,
    customer_state           CHAR(2)       NULL
);
BULK INSERT dbo.customers FROM 'olist_customers_dataset.csv'
WITH (DATA_SOURCE = 'OlistBlob', FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);
GO

-------------------------------------------------------------------------------
DROP TABLE IF EXISTS dbo.geolocation;
CREATE TABLE dbo.geolocation (
    geolocation_zip_code_prefix VARCHAR(5)    NOT NULL,
    geolocation_lat             FLOAT         NULL,
    geolocation_lng             FLOAT         NULL,
    geolocation_city            NVARCHAR(100) NULL,
    geolocation_state           CHAR(2)       NULL
);
BULK INSERT dbo.geolocation FROM 'olist_geolocation_dataset.csv'
WITH (DATA_SOURCE = 'OlistBlob', FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);
GO

-------------------------------------------------------------------------------
DROP TABLE IF EXISTS dbo.geolocation_zip_lookup;
CREATE TABLE dbo.geolocation_zip_lookup (
    geolocation_zip_code_prefix VARCHAR(5)    NOT NULL PRIMARY KEY,
    lat                         FLOAT         NULL,
    lng                         FLOAT         NULL,
    state                       CHAR(2)       NULL,
    city                        NVARCHAR(100) NULL
);
BULK INSERT dbo.geolocation_zip_lookup FROM 'geolocation_zip_lookup.csv'
WITH (DATA_SOURCE = 'OlistBlob', FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);
GO

-------------------------------------------------------------------------------
DROP TABLE IF EXISTS dbo.orders;
CREATE TABLE dbo.orders (
    order_id                      CHAR(32)     NOT NULL PRIMARY KEY,
    customer_id                   CHAR(32)     NOT NULL,
    order_status                  VARCHAR(20)  NULL,
    order_purchase_timestamp      DATETIME2(0) NULL,
    order_approved_at             DATETIME2(0) NULL,
    order_delivered_carrier_date  DATETIME2(0) NULL,
    order_delivered_customer_date DATETIME2(0) NULL,
    order_estimated_delivery_date DATETIME2(0) NULL
);
BULK INSERT dbo.orders FROM 'olist_orders_dataset.csv'
WITH (DATA_SOURCE = 'OlistBlob', FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);
GO

-------------------------------------------------------------------------------
DROP TABLE IF EXISTS dbo.order_items;
CREATE TABLE dbo.order_items (
    order_id            CHAR(32)      NOT NULL,
    order_item_id       INT           NOT NULL,
    product_id          CHAR(32)      NOT NULL,
    seller_id           CHAR(32)      NOT NULL,
    shipping_limit_date DATETIME2(0)  NULL,
    price               DECIMAL(10,2) NULL,
    freight_value       DECIMAL(10,2) NULL,
    PRIMARY KEY (order_id, order_item_id)
);
BULK INSERT dbo.order_items FROM 'olist_order_items_dataset.csv'
WITH (DATA_SOURCE = 'OlistBlob', FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);
GO

-------------------------------------------------------------------------------
DROP TABLE IF EXISTS dbo.order_payments;
CREATE TABLE dbo.order_payments (
    order_id             CHAR(32)      NOT NULL,
    payment_sequential   INT           NOT NULL,
    payment_type         VARCHAR(30)   NULL,
    payment_installments INT           NULL,
    payment_value        DECIMAL(10,2) NULL,
    PRIMARY KEY (order_id, payment_sequential)
);
BULK INSERT dbo.order_payments FROM 'olist_order_payments_dataset.csv'
WITH (DATA_SOURCE = 'OlistBlob', FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);
GO

-------------------------------------------------------------------------------
-- Sin PRIMARY KEY: el dataset original contiene review_id duplicados
DROP TABLE IF EXISTS dbo.order_reviews;
CREATE TABLE dbo.order_reviews (
    review_id               CHAR(32)      NOT NULL,
    order_id                CHAR(32)      NOT NULL,
    review_score            INT           NULL,
    review_comment_title    NVARCHAR(200) NULL,
    review_comment_message  NVARCHAR(MAX) NULL,
    review_creation_date    DATETIME2(0)  NULL,
    review_answer_timestamp DATETIME2(0)  NULL
);
BULK INSERT dbo.order_reviews FROM 'olist_order_reviews_dataset.csv'
WITH (DATA_SOURCE = 'OlistBlob', FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, CODEPAGE = '65001', TABLOCK);
GO

-------------------------------------------------------------------------------
DROP TABLE IF EXISTS dbo.products;
CREATE TABLE dbo.products (
    product_id                 CHAR(32)      NOT NULL PRIMARY KEY,
    product_category_name      NVARCHAR(100) NULL,
    product_name_lenght        INT           NULL,
    product_description_lenght INT           NULL,
    product_photos_qty         INT           NULL,
    product_weight_g           INT           NULL,
    product_length_cm          INT           NULL,
    product_height_cm          INT           NULL,
    product_width_cm           INT           NULL
);
BULK INSERT dbo.products FROM 'olist_products_dataset.csv'
WITH (DATA_SOURCE = 'OlistBlob', FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);
GO

-------------------------------------------------------------------------------
DROP TABLE IF EXISTS dbo.sellers;
CREATE TABLE dbo.sellers (
    seller_id              CHAR(32)      NOT NULL PRIMARY KEY,
    seller_zip_code_prefix VARCHAR(5)    NOT NULL,
    seller_city            NVARCHAR(100) NULL,
    seller_state           CHAR(2)       NULL
);
BULK INSERT dbo.sellers FROM 'olist_sellers_dataset.csv'
WITH (DATA_SOURCE = 'OlistBlob', FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);
GO

-------------------------------------------------------------------------------
DROP TABLE IF EXISTS dbo.product_category_name_translation;
CREATE TABLE dbo.product_category_name_translation (
    product_category_name         NVARCHAR(100) NOT NULL PRIMARY KEY,
    product_category_name_english NVARCHAR(100) NULL
);
BULK INSERT dbo.product_category_name_translation FROM 'product_category_name_translation.csv'
WITH (DATA_SOURCE = 'OlistBlob', FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, CODEPAGE = '65001', TABLOCK);
GO

-------------------------------------------------------------------------------
SELECT t.name AS tabla, SUM(p.rows) AS filas
FROM sys.tables t
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
GROUP BY t.name
ORDER BY t.name;
GO
