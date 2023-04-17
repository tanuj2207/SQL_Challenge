-- Solutions for "A. Customer Nodes Exploration"

-- 1. How many unique nodes are there on the Data Bank system?
select count(distinct(node_id)) from customer_nodes;

-- 2.What is the number of nodes per region?
select c.region_id, r.region_name, count(c.node_id) as No_of_node_id 
from customer_nodes as c
join regions as r on c.region_id = r.region_id
group by region_id
order by No_of_node_id desc;

-- 3. How many customers are allocated to each region?
select c.region_id, r.region_name, count(c.customer_id) as No_of_customers 
from customer_nodes as c
join regions as r on c.region_id = r.region_id
group by region_id
order by No_of_customers desc;

-- 4. How many days on average are customers reallocated to a different node?
		-- UPDATE customer_nodes SET end_date = '2020-08-31' WHERE end_date = '9999-12-31';
WITH get_start_and_end_dates as (
	SELECT
		customer_id,
		node_id,
		start_date,
		end_date,
		LAG(node_id) OVER (PARTITION BY customer_id ORDER BY start_date) AS prev_node
	FROM
		customer_nodes
	WHERE 
		end_date != '2020-08-31'
	ORDER BY
		customer_id,
		start_date
)
SELECT
	floor(avg(end_date - start_date)) AS rounded_down,
	round(avg(end_date - start_date), 1) AS avg_days,
	CEIL(avg(end_date - start_date)) AS rounded_up
FROM
	get_start_and_end_dates
WHERE
	prev_node != node_id;
    
-- 5. What is the median, 80th and 95th percentile for this same reallocation days metric for each region?

with get_all_days as(
select r.region_name,
		cn.customer_id,
		cn.node_id,
		cn.start_date,
		cn.end_date,
        lag(cn.node_id)Over(partition by cn.customer_id order by cn.start_date) as prev_node
FROM
		customer_nodes AS cn
	JOIN regions AS r
	ON r.region_id = cn.region_id
	ORDER BY
		cn.customer_id,
		cn.start_date
),
perc_reallocation AS (
SELECT
	region_name,
    -- ROUP_CONCAT(PERCENTILE_CONT(0.5) ORDER BY end_date - start_date DESC SEPARATOR ', ') AS "50th_perc"
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY end_date - start_date) AS "50th_perc",
	PERCENTILE_CONT(0.8) WITHIN GROUP(ORDER BY end_date - start_date) AS "80th_perc",
	PERCENTILE_CONT(0.95) WITHIN GROUP(ORDER BY end_date - start_date) AS "95th_perc"
FROM
	get_all_days
WHERE
	prev_node != node_id
GROUP BY 
	region_name
)
SELECT
	region_name,
	CEIL("50th_perc") AS median
	CEIL("80th_perc") AS "80th_percentile",
	CEIL("95th_perc") AS "95th_percentile"
FROM
	perc_reallocation;
    
    
    
-- B. Customer Transactions

-- 1. What is the unique count and total amount for each transaction type?
Select distinct txn_type as transaction_type, count(*) as transaction_count, sum(txn_amount) as total_amount
from customer_transactions
group by txn_type;

-- 2. What is the average total historical deposit counts and amounts for all customers?
with total_deposit_amounts as(
select customer_id, count(*) as deposit_count, sum(txn_amount) as total_deposit_amount
from customer_transactions
where txn_type = 'deposit'
group by customer_id
)
select round(avg(deposit_count)) as avg_deposit_count,
       round(avg(total_deposit_amount)) as avg_deposit_amount
from total_deposit_amounts;

-- 3. For each month - how many Data Bank customers make more than 1 deposit and either 1 purchase or 1 withdrawal in a single month?
WITH get_all_transactions_count AS (
SELECT
		DISTINCT customer_id,
        month(txn_date) as month_no,
		monthname(txn_date) AS current_month,
		sum(
			CASE
				WHEN txn_type = 'purchase' THEN 1
				ELSE NULL
			END  
		) AS purchase_count,
		sum(
			CASE
				WHEN txn_type = 'withdrawal' THEN 1
				ELSE NULL
			END  
		) AS withdrawal_count,
		sum(
			CASE
				WHEN txn_type = 'deposit' THEN 1
				ELSE NULL
			END  
		) AS deposit_count
	FROM
		customer_transactions
	GROUP BY
		customer_id,
		current_month
)
SELECT
	current_month,
	count(customer_id) AS customer_count
FROM
	get_all_transactions_count
WHERE
	deposit_count > 1
	AND (purchase_count >= 1
		OR withdrawal_count >= 1)
GROUP BY
	current_month
ORDER BY
	month_no;


-- 4. What is the closing balance for each customer at the end of the month?
DROP TABLE IF EXISTS closing_balance;

CREATE temporary TABLE closing_balance AS (
	SELECT
		customer_id, txn_amount, monthname(txn_date) AS txn_month,
		SUM(
			CASE
	        	WHEN txn_type = 'deposit' THEN txn_amount
	        	ELSE -txn_amount  -- Subtract transaction if not a deposit
	              
			END
		) AS transaction_amount
	FROM
		customer_transactions
	GROUP BY
		customer_id,
		txn_month,
		txn_amount
	ORDER BY
		customer_id,
        month(txn_date)
);
WITH get_all_transactions_per_month AS (
	SELECT customer_id,
	       txn_month,
	       transaction_amount,
	       sum(transaction_amount) over(PARTITION BY customer_id ORDER BY txn_month ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS closing_balance,
	       row_number() OVER (PARTITION BY customer_id, txn_month ORDER BY txn_month desc) AS rn
	FROM closing_balance
	ORDER BY 
		customer_id, txn_month
)
SELECT 
	customer_id, txn_month, transaction_amount, closing_balance
from
	get_all_transactions_per_month
WHERE rn = 1
LIMIT 15;

-- 5. What is the percentage of customers who increase their closing balance by more than 5%?
WITH get_all_transactions_per_month AS (
	SELECT customer_id,
	       txn_month,
	       transaction_amount,
	       sum(transaction_amount) over(PARTITION BY customer_id ORDER BY txn_month ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS closing_balance,
	       row_number() OVER (PARTITION BY customer_id, txn_month ORDER BY txn_month desc) AS rn
	FROM closing_balance
	ORDER BY 
		customer_id,
		txn_month
),
get_last_balance AS (
	SELECT 
		customer_id,
		txn_month,
		transaction_amount,
		closing_balance,
		round(100 * Cast((closing_balance - LAG(closing_balance) over()) / LAG(closing_balance) over() as decimal), 2) AS month_to_month,
		RANK() OVER (PARTITION BY customer_id ORDER BY txn_month desc) AS rnk
	from
		get_all_transactions_per_month
	WHERE rn = 1
)
SELECT
	round(100 * count(customer_id) / Cast((SELECT count(customer_id) FROM customer_transactions) as decimal), 2) AS over_5_percent_increase
FROM
	get_last_balance
WHERE month_to_month > 5.0
AND rnk = 1;










































