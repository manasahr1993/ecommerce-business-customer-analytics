-- Olist E-Commerce Business & Customer Analytics
-- Complete project SQL reference
-- Schema: s_manasarenuka

-- ========================================================================
-- 1. Initial row counts
-- ========================================================================
SELECT 'olist_geolocation_dataset' AS table_name, COUNT(*) AS row_count FROM s_manasarenuka.olist_geolocation_dataset
UNION ALL SELECT 'olist_order_items_dataset', COUNT(*) FROM s_manasarenuka.olist_order_items_dataset
UNION ALL SELECT 'olist_order_reviews_dataset', COUNT(*) FROM s_manasarenuka.olist_order_reviews_dataset
UNION ALL SELECT 'olist_order_payments_dataset', COUNT(*) FROM s_manasarenuka.olist_order_payments_dataset
UNION ALL SELECT 'olist_orders_dataset', COUNT(*) FROM s_manasarenuka.olist_orders_dataset
UNION ALL SELECT 'olist_customers_dataset', COUNT(*) FROM s_manasarenuka.olist_customers_dataset
UNION ALL SELECT 'olist_products_dataset', COUNT(*) FROM s_manasarenuka.olist_products_dataset
UNION ALL SELECT 'olist_sellers_dataset', COUNT(*) FROM s_manasarenuka.olist_sellers_dataset
UNION ALL SELECT 'product_category_name_translation', COUNT(*) FROM s_manasarenuka.product_category_name_translation
ORDER BY table_name;

-- ========================================================================
-- 2. Remove exact duplicates
-- NOTE: Only exact duplicate rows were removed. Multiple review records for the same order were retained.
-- ========================================================================
DROP TABLE IF EXISTS s_manasarenuka.olist_order_items_clean;
CREATE TABLE s_manasarenuka.olist_order_items_clean AS
SELECT DISTINCT * FROM s_manasarenuka.olist_order_items_dataset;

DROP TABLE IF EXISTS s_manasarenuka.olist_payments_clean;
CREATE TABLE s_manasarenuka.olist_payments_clean AS
SELECT DISTINCT * FROM s_manasarenuka.olist_order_payments_dataset;

DROP TABLE IF EXISTS s_manasarenuka.olist_reviews_clean;
CREATE TABLE s_manasarenuka.olist_reviews_clean AS
SELECT DISTINCT * FROM s_manasarenuka.olist_order_reviews_dataset;

DROP TABLE IF EXISTS s_manasarenuka.olist_geolocation_clean;
CREATE TABLE s_manasarenuka.olist_geolocation_clean AS
SELECT DISTINCT * FROM s_manasarenuka.olist_geolocation_dataset;

-- ========================================================================
-- 3. Check multiple reviews
-- ========================================================================
SELECT order_id, COUNT(*) AS review_count
FROM s_manasarenuka.olist_reviews_clean
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY review_count DESC;

-- ========================================================================
-- 4. Revenue, orders and AOV
-- NOTE: Product revenue is calculated from order items; orders are counted at order_id level.
-- ========================================================================
SELECT
    COUNT(*) AS total_orders,
    ROUND(SUM(order_total)::numeric, 2) AS total_revenue,
    ROUND(AVG(order_total)::numeric, 2) AS average_order_value
FROM (
    SELECT order_id, SUM(price) AS order_total
    FROM s_manasarenuka.olist_order_items_clean
    GROUP BY order_id
) AS order_values;

-- ========================================================================
-- 5. Monthly revenue
-- ========================================================================
SELECT
    DATE_TRUNC('month', o.order_purchase_timestamp::timestamp) AS order_month,
    ROUND(SUM(oi.price)::numeric, 2) AS monthly_revenue
FROM s_manasarenuka.olist_orders_dataset o
JOIN s_manasarenuka.olist_order_items_clean oi
    ON o.order_id = oi.order_id
GROUP BY DATE_TRUNC('month', o.order_purchase_timestamp::timestamp)
ORDER BY order_month;

-- ========================================================================
-- 6. Top 10 categories by revenue
-- ========================================================================
SELECT
    p.product_category_name,
    ROUND(SUM(oi.price)::numeric, 2) AS total_revenue
FROM s_manasarenuka.olist_order_items_clean oi
JOIN s_manasarenuka.olist_products_dataset p
    ON oi.product_id = p.product_id
WHERE p.product_category_name IS NOT NULL
GROUP BY p.product_category_name
ORDER BY total_revenue DESC
LIMIT 10;

-- ========================================================================
-- 7. Customer repeat rate
-- ========================================================================
SELECT
    COUNT(*) AS total_customers,
    COUNT(*) FILTER (WHERE order_count > 1) AS repeat_customers,
    ROUND(100.0 * COUNT(*) FILTER (WHERE order_count > 1) / COUNT(*), 2)
        AS repeat_customer_rate
FROM (
    SELECT c.customer_unique_id,
           COUNT(DISTINCT o.order_id) AS order_count
    FROM s_manasarenuka.olist_customers_dataset c
    JOIN s_manasarenuka.olist_orders_dataset o
      ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
) AS customer_orders;

-- ========================================================================
-- 8. Payment methods
-- ========================================================================
SELECT
    payment_type,
    COUNT(*) AS payment_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS payment_share_pct
FROM s_manasarenuka.olist_payments_clean
GROUP BY payment_type
ORDER BY payment_count DESC;

-- ========================================================================
-- 9. Delivery performance
-- NOTE: Expected categories: On Time, Late, Not Delivered.
-- ========================================================================
SELECT
    delivery_status,
    COUNT(DISTINCT order_id) AS order_count,
    ROUND(
        100.0 * COUNT(DISTINCT order_id)
        / SUM(COUNT(DISTINCT order_id)) OVER (), 2
    ) AS percentage
FROM s_manasarenuka.ecommerce_master
GROUP BY delivery_status
ORDER BY order_count DESC;

-- ========================================================================
-- 10. Delivery vs review score
-- NOTE: Use this as an association/relationship, not a causal claim.
-- ========================================================================
SELECT
    delivery_status,
    ROUND(AVG(review_score)::numeric, 2) AS average_review_score,
    COUNT(*) AS review_records
FROM s_manasarenuka.ecommerce_master
WHERE review_score IS NOT NULL
GROUP BY delivery_status
ORDER BY delivery_status;

-- ========================================================================
-- 11. Top sellers
-- ========================================================================
SELECT
    seller_id,
    ROUND(SUM(price)::numeric, 2) AS total_revenue
FROM s_manasarenuka.olist_order_items_clean
GROUP BY seller_id
ORDER BY total_revenue DESC
LIMIT 10;

-- ========================================================================
-- 12. Top-10 seller revenue share
-- ========================================================================
WITH seller_revenue AS (
    SELECT seller_id, SUM(price) AS total_revenue
    FROM s_manasarenuka.olist_order_items_clean
    GROUP BY seller_id
),
ranked AS (
    SELECT seller_id, total_revenue,
           ROW_NUMBER() OVER (ORDER BY total_revenue DESC) AS seller_rank
    FROM seller_revenue
)
SELECT ROUND(
    100.0 * SUM(CASE WHEN seller_rank <= 10 THEN total_revenue ELSE 0 END)
    / SUM(total_revenue), 2
) AS top_10_seller_revenue_share_pct
FROM ranked;

-- ========================================================================
-- 13. Customer historical value
-- NOTE: This is historical spend, not predictive CLV.
-- ========================================================================
SELECT
    c.customer_unique_id,
    COUNT(DISTINCT o.order_id) AS order_count,
    ROUND(SUM(oi.price)::numeric, 2) AS total_customer_value
FROM s_manasarenuka.olist_customers_dataset c
JOIN s_manasarenuka.olist_orders_dataset o
  ON c.customer_id = o.customer_id
JOIN s_manasarenuka.olist_order_items_clean oi
  ON o.order_id = oi.order_id
GROUP BY c.customer_unique_id
ORDER BY total_customer_value DESC;

-- ========================================================================
-- 14. One-time vs repeat customers
-- ========================================================================
WITH customer_value AS (
    SELECT c.customer_unique_id,
           COUNT(DISTINCT o.order_id) AS order_count,
           SUM(oi.price) AS total_value
    FROM s_manasarenuka.olist_customers_dataset c
    JOIN s_manasarenuka.olist_orders_dataset o
      ON c.customer_id = o.customer_id
    JOIN s_manasarenuka.olist_order_items_clean oi
      ON o.order_id = oi.order_id
    GROUP BY c.customer_unique_id
)
SELECT
    CASE WHEN order_count > 1 THEN 'Repeat' ELSE 'One-Time' END AS customer_type,
    COUNT(*) AS customer_count,
    ROUND(AVG(total_value)::numeric, 2) AS average_customer_value,
    ROUND(SUM(total_value)::numeric, 2) AS total_revenue
FROM customer_value
GROUP BY CASE WHEN order_count > 1 THEN 'Repeat' ELSE 'One-Time' END
ORDER BY customer_type;

-- ========================================================================
-- 15. Revenue by customer state
-- ========================================================================
SELECT
    c.customer_state,
    COUNT(DISTINCT c.customer_unique_id) AS customers,
    ROUND(SUM(oi.price)::numeric, 2) AS revenue,
    ROUND(SUM(oi.price)::numeric / COUNT(DISTINCT c.customer_unique_id), 2)
        AS revenue_per_customer
FROM s_manasarenuka.olist_customers_dataset c
JOIN s_manasarenuka.olist_orders_dataset o
  ON c.customer_id = o.customer_id
JOIN s_manasarenuka.olist_order_items_clean oi
  ON o.order_id = oi.order_id
GROUP BY c.customer_state
ORDER BY revenue DESC;

-- ========================================================================
-- 16. Category volume and revenue
-- ========================================================================
SELECT
    p.product_category_name,
    COUNT(*) AS items_sold,
    ROUND(SUM(oi.price)::numeric, 2) AS revenue,
    ROUND(AVG(oi.price)::numeric, 2) AS average_item_price
FROM s_manasarenuka.olist_order_items_clean oi
JOIN s_manasarenuka.olist_products_dataset p
  ON oi.product_id = p.product_id
WHERE p.product_category_name IS NOT NULL
GROUP BY p.product_category_name
ORDER BY revenue DESC;

-- ========================================================================
-- 17. Freight analysis
-- ========================================================================
SELECT
    ROUND(SUM(freight_value)::numeric, 2) AS total_freight,
    ROUND(AVG(freight_value)::numeric, 2) AS average_freight,
    ROUND(SUM(price)::numeric, 2) AS total_product_value,
    ROUND(100.0 * SUM(freight_value) / NULLIF(SUM(price),0), 2)
        AS freight_to_product_value_pct
FROM s_manasarenuka.olist_order_items_clean;

-- ========================================================================
-- 18. RFM customer table
-- NOTE: RFM uses delivered orders. Recency uses CURRENT_DATE when executed.
-- ========================================================================
DROP TABLE IF EXISTS s_manasarenuka.customer_rfm;

CREATE TABLE s_manasarenuka.customer_rfm AS
WITH customer_metrics AS (
    SELECT
        c.customer_unique_id,
        MAX(o.order_purchase_timestamp::timestamp) AS last_purchase_date,
        COUNT(DISTINCT o.order_id) AS frequency,
        SUM(oi.price) AS monetary
    FROM s_manasarenuka.olist_customers_dataset c
    JOIN s_manasarenuka.olist_orders_dataset o
      ON c.customer_id = o.customer_id
    JOIN s_manasarenuka.olist_order_items_clean oi
      ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
rfm_base AS (
    SELECT customer_unique_id,
           CURRENT_DATE - last_purchase_date::date AS recency,
           frequency, monetary
    FROM customer_metrics
),
rfm_scores AS (
    SELECT *,
           NTILE(5) OVER (ORDER BY recency DESC) AS r_score,
           NTILE(5) OVER (ORDER BY frequency) AS f_score,
           NTILE(5) OVER (ORDER BY monetary) AS m_score
    FROM rfm_base
)
SELECT *,
       CONCAT(r_score, f_score, m_score) AS rfm_score,
       CASE
         WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
         WHEN r_score >= 3 AND f_score >= 4 AND m_score >= 3 THEN 'Loyal Customers'
         WHEN r_score >= 4 AND f_score <= 3 AND m_score <= 3 THEN 'Potential Loyalists'
         WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 3 THEN 'At Risk'
         WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 4 THEN 'High Value At Risk'
         WHEN r_score <= 2 AND f_score <= 2 AND m_score <= 2 THEN 'Lost Customers'
         ELSE 'Other Customers'
       END AS customer_segment
FROM rfm_scores;

-- ========================================================================
-- 19. RFM segment summary
-- ========================================================================
SELECT
    customer_segment,
    COUNT(*) AS customer_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS customer_share_pct,
    ROUND(AVG(monetary)::numeric, 2) AS average_customer_value
FROM s_manasarenuka.customer_rfm
GROUP BY customer_segment
ORDER BY customer_count DESC;

-- ========================================================================
-- 20. Final analytical master view
-- NOTE: LEFT JOINs preserve valid unmatched business states; NULLs are not automatically errors.
-- ========================================================================
DROP VIEW IF EXISTS s_manasarenuka.ecommerce_master;

CREATE VIEW s_manasarenuka.ecommerce_master AS
WITH payment_summary AS (
    SELECT order_id,
           STRING_AGG(DISTINCT payment_type, ', ' ORDER BY payment_type)
               AS payment_methods,
           SUM(payment_value) AS total_payment_value
    FROM s_manasarenuka.olist_order_payments_dataset
    GROUP BY order_id
),
review_summary AS (
    SELECT order_id,
           AVG(review_score) AS review_score,
           COUNT(*) AS review_count
    FROM s_manasarenuka.olist_order_reviews_dataset
    GROUP BY order_id
)
SELECT
    o.order_id,
    o.customer_id,
    c.customer_unique_id,
    c.customer_zip_code_prefix AS customer_zip_code,
    c.customer_city,
    c.customer_state,
    o.order_status,
    o.order_purchase_timestamp::timestamp AS order_purchase_timestamp,
    o.order_approved_at::timestamp AS order_approved_at,
    o.order_delivered_carrier_date::timestamp AS order_delivered_carrier_date,
    o.order_delivered_customer_date::timestamp AS order_delivered_customer_date,
    o.order_estimated_delivery_date::timestamp AS order_estimated_delivery_date,
    DATE_TRUNC('month', o.order_purchase_timestamp::timestamp) AS order_month,
    CASE
      WHEN o.order_delivered_customer_date IS NULL THEN 'Not Delivered'
      WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date
        THEN 'On Time'
      ELSE 'Late'
    END AS delivery_status,
    CASE WHEN o.order_delivered_customer_date IS NOT NULL
      THEN o.order_delivered_customer_date::timestamp
           - o.order_purchase_timestamp::timestamp END AS delivery_days,
    CASE WHEN o.order_delivered_customer_date IS NOT NULL
      THEN o.order_estimated_delivery_date::timestamp
           - o.order_purchase_timestamp::timestamp END AS estimated_delivery_days,
    oi.order_item_id,
    oi.product_id,
    oi.seller_id,
    oi.price,
    oi.freight_value,
    p.product_category_name,
    pct.product_category_name_english,
    s.seller_zip_code_prefix AS seller_zip_code,
    s.seller_city,
    s.seller_state,
    ps.payment_methods,
    ps.total_payment_value,
    rs.review_score,
    rs.review_count
FROM s_manasarenuka.olist_orders_dataset o
LEFT JOIN s_manasarenuka.olist_customers_dataset c ON o.customer_id = c.customer_id
LEFT JOIN s_manasarenuka.olist_order_items_clean oi ON o.order_id = oi.order_id
LEFT JOIN s_manasarenuka.olist_products_dataset p ON oi.product_id = p.product_id
LEFT JOIN s_manasarenuka.product_category_name_translation pct
  ON p.product_category_name = pct.product_category_name
LEFT JOIN s_manasarenuka.olist_sellers_dataset s ON oi.seller_id = s.seller_id
LEFT JOIN payment_summary ps ON o.order_id = ps.order_id
LEFT JOIN review_summary rs ON o.order_id = rs.order_id;

-- ========================================================================
-- 21. Verify master view
-- ========================================================================
SELECT * FROM s_manasarenuka.ecommerce_master LIMIT 20;

SELECT COUNT(*) AS master_rows
FROM s_manasarenuka.ecommerce_master;

-- ========================================================================
-- 22. Final three analytical angles
-- ========================================================================
-- Sales & Product Performance
SELECT product_category_name_english,
       ROUND(SUM(price)::numeric,2) AS revenue,
       COUNT(DISTINCT order_id) AS orders
FROM s_manasarenuka.ecommerce_master
WHERE product_category_name_english IS NOT NULL
GROUP BY product_category_name_english
ORDER BY revenue DESC
LIMIT 10;

-- Customer Behaviour & Retention
SELECT customer_segment,
       COUNT(*) AS customers,
       ROUND(AVG(monetary)::numeric,2) AS average_value
FROM s_manasarenuka.customer_rfm
GROUP BY customer_segment
ORDER BY customers DESC;

-- Delivery & Customer Experience
SELECT delivery_status,
       ROUND(AVG(review_score)::numeric,2) AS average_review_score,
       COUNT(DISTINCT order_id) AS orders
FROM s_manasarenuka.ecommerce_master
WHERE review_score IS NOT NULL
GROUP BY delivery_status
ORDER BY delivery_status;

