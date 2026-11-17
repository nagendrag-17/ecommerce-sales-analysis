/*
Project: Olist E-Commerce Sales Analysis
Database: ecommerce_analysis
SQL dialect: MySQL 8+

Tables expected:
olist_customers
olist_orders
olist_order_items
olist_order_payments
olist_order_reviews
olist_products
olist_sellers
olist_geolocation
product_category_name_translation

Run this file after importing the Olist CSV files and creating the tables.
*/

USE ecommerce_analysis;

-- 1. Basic table row counts
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM olist_customers
UNION ALL SELECT 'orders', COUNT(*) FROM olist_orders
UNION ALL SELECT 'order_items', COUNT(*) FROM olist_order_items
UNION ALL SELECT 'payments', COUNT(*) FROM olist_order_payments
UNION ALL SELECT 'reviews', COUNT(*) FROM olist_order_reviews
UNION ALL SELECT 'products', COUNT(*) FROM olist_products
UNION ALL SELECT 'sellers', COUNT(*) FROM olist_sellers;

-- 2. Order status distribution
SELECT order_status, COUNT(*) AS total_orders
FROM olist_orders
GROUP BY order_status
ORDER BY total_orders DESC;

-- 3. Overall business KPIs
-- Revenue is calculated from product price and excludes freight.
WITH order_revenue AS (
    SELECT oi.order_id, SUM(oi.price) AS product_revenue
    FROM olist_order_items oi
    GROUP BY oi.order_id
),
delivered_orders AS (
    SELECT order_id, customer_id, order_purchase_timestamp
    FROM olist_orders
    WHERE order_status = 'delivered'
)
SELECT
    COUNT(DISTINCT d.order_id) AS total_delivered_orders,
    ROUND(SUM(r.product_revenue), 2) AS total_product_revenue,
    COUNT(DISTINCT d.customer_id) AS unique_customers,
    ROUND(AVG(r.product_revenue), 2) AS average_order_value
FROM delivered_orders d
JOIN order_revenue r ON d.order_id = r.order_id;

-- 4. Monthly product revenue trend (delivered orders)
SELECT
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month,
    ROUND(SUM(oi.price), 2) AS monthly_revenue,
    COUNT(DISTINCT o.order_id) AS total_orders
FROM olist_orders o
JOIN olist_order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
ORDER BY order_month;

-- 5. Revenue by product category
SELECT
    COALESCE(t.product_category_name_english, p.product_category_name, 'Unknown') AS product_category,
    ROUND(SUM(oi.price), 2) AS total_revenue,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    SUM(oi.order_item_id) AS item_rows
FROM olist_order_items oi
JOIN olist_orders o ON oi.order_id = o.order_id
JOIN olist_products p ON oi.product_id = p.product_id
LEFT JOIN product_category_name_translation t
    ON p.product_category_name = t.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY COALESCE(t.product_category_name_english, p.product_category_name, 'Unknown')
ORDER BY total_revenue DESC;

-- 6. Payment method distribution
SELECT
    payment_type,
    COUNT(*) AS payment_records,
    ROUND(SUM(payment_value), 2) AS total_payment_value,
    ROUND(AVG(payment_value), 2) AS average_payment_value
FROM olist_order_payments
GROUP BY payment_type
ORDER BY total_payment_value DESC;

-- 7. Delivery performance (delivered orders only)
SELECT
    COUNT(*) AS delivered_orders,
    ROUND(AVG(DATEDIFF(order_delivered_customer_date, order_purchase_timestamp)), 2)
        AS average_delivery_days,
    SUM(CASE
        WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 1
        ELSE 0
    END) AS late_deliveries,
    ROUND(
        100.0 * SUM(CASE
            WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 1
            ELSE 0
        END) / COUNT(*), 2
    ) AS late_delivery_percentage
FROM olist_orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
  AND order_estimated_delivery_date IS NOT NULL;

-- 8. Customer review score distribution
SELECT
    review_score,
    COUNT(*) AS review_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS review_percentage
FROM olist_order_reviews
GROUP BY review_score
ORDER BY review_score;

-- 9. Average review score by product category
SELECT
    COALESCE(t.product_category_name_english, p.product_category_name, 'Unknown') AS product_category,
    ROUND(AVG(r.review_score), 2) AS average_review_score,
    COUNT(r.review_id) AS review_count
FROM olist_order_reviews r
JOIN olist_order_items oi ON r.order_id = oi.order_id
JOIN olist_products p ON oi.product_id = p.product_id
LEFT JOIN product_category_name_translation t
    ON p.product_category_name = t.product_category_name
GROUP BY COALESCE(t.product_category_name_english, p.product_category_name, 'Unknown')
HAVING COUNT(r.review_id) >= 10
ORDER BY average_review_score DESC, review_count DESC;

-- 10. Repeat customers (delivered orders)
SELECT
    c.customer_unique_id,
    COUNT(DISTINCT o.order_id) AS delivered_order_count
FROM olist_customers c
JOIN olist_orders o ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_unique_id
HAVING COUNT(DISTINCT o.order_id) > 1
ORDER BY delivered_order_count DESC;

-- 11. Top 10 product categories by number of items sold
SELECT
    COALESCE(t.product_category_name_english, p.product_category_name, 'Unknown') AS product_category,
    COUNT(*) AS items_sold
FROM olist_order_items oi
JOIN olist_products p ON oi.product_id = p.product_id
LEFT JOIN product_category_name_translation t
    ON p.product_category_name = t.product_category_name
GROUP BY COALESCE(t.product_category_name_english, p.product_category_name, 'Unknown')
ORDER BY items_sold DESC
LIMIT 10;

-- 12. Top 10 sellers by product revenue (delivered orders)
SELECT
    oi.seller_id,
    COUNT(DISTINCT oi.order_id) AS delivered_orders,
    ROUND(SUM(oi.price), 2) AS product_revenue
FROM olist_order_items oi
JOIN olist_orders o ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY oi.seller_id
ORDER BY product_revenue DESC
LIMIT 10;

-- 13. Revenue by customer state (delivered orders)
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS delivered_orders,
    ROUND(SUM(oi.price), 2) AS product_revenue
FROM olist_customers c
JOIN olist_orders o ON c.customer_id = o.customer_id
JOIN olist_order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY product_revenue DESC;

-- 14. High-value customers by lifetime product spend
SELECT
    c.customer_unique_id,
    COUNT(DISTINCT o.order_id) AS delivered_orders,
    ROUND(SUM(oi.price), 2) AS lifetime_product_spend
FROM olist_customers c
JOIN olist_orders o ON c.customer_id = o.customer_id
JOIN olist_order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_unique_id
ORDER BY lifetime_product_spend DESC
LIMIT 20;
