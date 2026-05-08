
-- PROJECT: Northwind Sales Analysis
-- Author:  Eduardo Torres
-- Date:    2026
-- Tool:    PostgreSQL
-- Dataset: Northwind Database
--
-- Description:
--   End-to-end sales analysis covering monthly trends,
--   category performance, employee rankings, and top customer
--   behavior. Built to demonstrate practical use of CTEs,
--   Window Functions, and aggregations for business reporting.




-- QUERY 1: Monthly Sales Trend with MoM Growth

-- Business question:
--   Is the business growing or declining month over month?
--
-- Approach:
--   1. Aggregate revenue per month using a CTE
--   2. Use LAG() to pull the previous month's revenue
--   3. Calculate MoM growth % using the standard formula:
--      (current - previous) / previous * 100
--
-- Why this matters:
--   MoM growth is the most common KPI in sales reporting.
--   A negative trend for 2+ consecutive months is a red flag
--   that management needs to act on immediately.


WITH monthly_revenue AS (
    -- Step 1: Calculate total revenue per month
    -- Revenue formula: unit_price * quantity * (1 - discount)
    -- Discount is stored as a decimal (0.05 = 5%), so we subtract from 1
    SELECT
        TO_CHAR(o.order_date, 'YYYY-MM') AS month,
        ROUND(
            CAST(SUM(od.unit_price * od.quantity * (1 - od.discount)) AS NUMERIC)
        , 2) AS revenue
    FROM orders o
    INNER JOIN order_details od ON od.order_id = o.order_id
    GROUP BY TO_CHAR(o.order_date, 'YYYY-MM')
)
-- Step 2: Apply LAG() to get previous month's revenue,
-- then calculate the growth percentage
SELECT
    month,
    revenue,
    -- Pull revenue from the previous row (1 month back)
    LAG(revenue, 1) OVER (ORDER BY month) AS prev_month_revenue,
    -- MoM growth %: (current - previous) / previous * 100
    -- NULLIF avoids division by zero for the first row (no previous month)
    ROUND(
        CAST(
            (revenue - LAG(revenue, 1) OVER (ORDER BY month)) * 100.0
            / NULLIF(LAG(revenue, 1) OVER (ORDER BY month), 0)
        AS NUMERIC)
    , 2) AS mom_growth_pct
FROM monthly_revenue
ORDER BY month;



-- QUERY 2: Cumulative Sales by Category — 1997

-- Business question:
--   How did each product category progress through 1997?
--   Which categories built momentum and which stalled?
--
-- Approach:
--   1. Aggregate revenue by category and month using a CTE
--   2. Apply SUM() OVER with PARTITION BY category to get a
--      running total that resets for each category
--
-- Why this matters:
--   A cumulative view reveals which categories had strong
--   early-year starts vs. which ones gained traction later.
--   This informs inventory planning and promotional timing.


WITH category_monthly AS (
    -- Step 1: Revenue per category per month in 1997
    -- We join 3 tables: categories → products → order_details → orders
    SELECT
        c.category_id,
        c.category_name,
        TO_CHAR(o.order_date, 'YYYY-MM') AS month,
        ROUND(
            CAST(SUM(od.unit_price * od.quantity * (1 - od.discount)) AS NUMERIC)
        , 2) AS monthly_revenue
    FROM categories c
    INNER JOIN products p ON p.category_id = c.category_id
    INNER JOIN order_details od ON od.product_id = p.product_id
    INNER JOIN orders o ON o.order_id = od.order_id
    WHERE EXTRACT(YEAR FROM o.order_date) = 1997
    GROUP BY
        c.category_id,
        c.category_name,
        TO_CHAR(o.order_date, 'YYYY-MM')
)
-- Step 2: Calculate cumulative revenue per category
-- PARTITION BY category_id resets the running total for each category
-- ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW is explicit best practice
-- to avoid unexpected behavior with duplicate dates
SELECT
    category_name,
    month,
    monthly_revenue,
    ROUND(
        CAST(
            SUM(monthly_revenue) OVER (
                PARTITION BY category_id
                ORDER BY month
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS NUMERIC)
    , 2) AS cumulative_revenue
FROM category_monthly
ORDER BY category_id, month;



-- QUERY 3: Employee Sales Ranking with Revenue Share

-- Business question:
--   Who are the top-performing employees and what percentage
--   of total company revenue does each one represent?
--
-- Approach:
--   1. Calculate total revenue per employee using a CTE
--   2. Use RANK() to rank employees from highest to lowest
--   3. Use SUM() OVER () (no partition) to get the company total
--      and calculate each employee's revenue share %
--
-- Why this matters:
--   Revenue concentration risk — if 2 employees generate 70%
--   of sales, the business is vulnerable to turnover.


WITH employee_revenue AS (
    -- Step 1: Total revenue attributed to each employee
    -- We join employees to get their names (not just IDs)
    SELECT
        e.employee_id,
        e.first_name || ' ' || e.last_name AS employee_name,
        e.title,
        COUNT(DISTINCT o.order_id) AS total_orders,
        ROUND(
            CAST(SUM(od.unit_price * od.quantity * (1 - od.discount)) AS NUMERIC)
        , 2) AS total_revenue
    FROM employees e
    INNER JOIN orders o ON o.employee_id = e.employee_id
    INNER JOIN order_details od ON od.order_id = o.order_id
    GROUP BY
        e.employee_id,
        e.first_name || ' ' || e.last_name,
        e.title
)
-- Step 2: Add rank and revenue share to each employee row
SELECT
    -- RANK() assigns the same rank to ties and skips the next number
    RANK() OVER (ORDER BY total_revenue DESC) AS sales_rank,
    employee_name,
    title,
    total_orders,
    total_revenue,
    -- Revenue share: employee revenue / company total * 100
    -- SUM() OVER () with no PARTITION BY sums across the entire result set
    ROUND(
        CAST(
            total_revenue * 100.0
            / NULLIF(SUM(total_revenue) OVER (), 0)
        AS NUMERIC)
    , 2) AS revenue_share_pct
FROM employee_revenue
ORDER BY sales_rank;


-- QUERY 4: Top 5 Customers — Order History & Avg Days Between Orders
-- Business question:
--   Who are our most valuable customers, how often do they
--   buy, and how long do they typically go between orders?
--
-- Approach:
--   1. CTE 1 — identify the top 5 customers by total revenue
--   2. CTE 2 — pull the full order history for those 5 customers
--   3. Use LAG() to get the previous order date per customer
--   4. Calculate days between consecutive orders with subtraction
--
-- Why this matters:
--   High-value customers who start buying less frequently
--   are early churn signals. Tracking the gap between orders
--   helps the sales team prioritize follow-up calls.



WITH top_customers AS (
    -- Step 1: Rank all customers by total revenue, keep top 5
    -- We use a subquery-style CTE so we can filter by rank below
    SELECT
        c.customer_id,
        c.company_name,
        ROUND(
            CAST(SUM(od.unit_price * od.quantity * (1 - od.discount)) AS NUMERIC)
        , 2) AS total_revenue
    FROM customers c
    INNER JOIN orders o ON o.customer_id = c.customer_id
    INNER JOIN order_details od ON od.order_id = o.order_id
    GROUP BY c.customer_id, c.company_name
    ORDER BY total_revenue DESC
    LIMIT 5
),
order_history AS (
    -- Step 2: Full order history for the top 5 customers only
    -- We join back to orders and order_details to get per-order revenue
    SELECT
        tc.company_name,
        o.order_id,
        o.order_date,
        ROUND(
            CAST(SUM(od.unit_price * od.quantity * (1 - od.discount)) AS NUMERIC)
        , 2) AS order_revenue
    FROM top_customers tc
    INNER JOIN orders o ON o.customer_id = tc.customer_id
    INNER JOIN order_details od ON od.order_id = o.order_id
    GROUP BY
        tc.company_name,
        o.order_id,
        o.order_date
)
-- Step 3: Add the previous order date and days between orders
-- PARTITION BY company_name ensures LAG resets per customer
SELECT
    company_name,
    order_id,
    order_date,
    order_revenue,
    -- Previous order date for this same customer
    LAG(order_date, 1) OVER (
        PARTITION BY company_name
        ORDER BY order_date
    ) AS prev_order_date,
    -- Days between this order and the previous one
    -- PostgreSQL allows direct date subtraction: date - date = integer (days)
    -- Returns NULL for the first order of each customer (no previous order exists)
    order_date - LAG(order_date, 1) OVER (
        PARTITION BY company_name
        ORDER BY order_date
    ) AS days_since_last_order
FROM order_history
ORDER BY company_name, order_date;
