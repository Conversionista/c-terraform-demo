-- Orders and revenue per day and status, from theLook.
SELECT
  DATE(o.created_at)            AS order_date,
  o.status,
  COUNT(DISTINCT o.order_id)    AS orders,
  COUNT(oi.id)                  AS items,
  ROUND(SUM(oi.sale_price), 2)  AS revenue
FROM `${source}.orders` AS o
JOIN `${source}.order_items` AS oi
  ON oi.order_id = o.order_id
GROUP BY order_date, status
