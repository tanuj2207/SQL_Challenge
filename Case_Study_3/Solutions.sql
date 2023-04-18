Use Pizza_Runner;

-- Note: The customer_order table has inconsistent data types. We must first clean the data before answering any questions. 
-- The exclusions and extras columns contain values that are either 'null' (text), null (data type) or '' (empty). 
-- We will create a temporary table where all forms of null will be transformed to null (data type).

Select * from customer_orders;

DROP TABLE IF EXISTS new_customer_orders;
CREATE TEMPORARY TABLE new_customer_orders AS (
	SELECT order_id,
		customer_id,
		pizza_id,
		CASE
			WHEN exclusions = ''
			OR exclusions LIKE 'null' THEN null
			ELSE exclusions
		END AS exclusions,
		CASE
			WHEN extras = ''
			OR extras LIKE 'null' THEN null
			ELSE extras
		END AS extras,
		order_time
	FROM customer_orders
);
      
SELECT * FROM new_customer_orders;

SELECT * from runner_orders;
-- The runner_order table has inconsistent data types. We must first clean the data before answering any questions. 
-- The distance and duration columns have text and numbers. We will remove the text values and convert to numeric values. 
-- We will convert all 'null' (text) and 'NaN' values in the cancellation column to null (data type). 
-- We will convert the pickup_time (varchar) column to a timestamp data type.

DROP TABLE IF EXISTS new_runner_orders;
CREATE TEMPORARY TABLE new_runner_orders AS (
	SELECT order_id,
		runner_id,
		CASE
			WHEN pickup_time LIKE 'null' THEN NULL
			ELSE Cast(pickup_time AS DATETIME)
		END AS pickup_time, 
		-- Return null value if both arguments are equal
		-- Use regex to match only numeric values and decimal point.
		-- Convert to numeric datatype
		Cast(NULLIF(regexp_replace(distance, '[^0-9.]', ''), '') as Decimal) as Distance, 
		CAST(NULLIF(regexp_replace(duration, '[^0-9.]', ''), '') as unsigned integer) as Duration,
		CASE
			WHEN cancellation LIKE 'null'
			OR cancellation LIKE 'NaN'
			OR cancellation LIKE '' THEN NULL
			ELSE cancellation
		END AS cancellation
	FROM runner_orders
);


----------------------------------------------------------- A. PIZZA METRICS ----------------------------------------------------------------------

-- 1. How many pizzas were ordered?
Select count(order_id) AS Total_Orders from new_customer_orders;

-- 2. How many unique customer orders were made?
Select count(distinct order_id) as distinct_orders from new_customer_orders;

-- 3. How many successful orders were delivered by each runner?
SELECT runner_id,
	count(order_id) AS n_orders
FROM new_runner_orders
WHERE cancellation IS NULL
GROUP BY runner_id
ORDER BY n_orders DESC;

-- 4. How many of each type of pizza was delivered?
SELECT p.pizza_name, count(c.customer_id) AS n_pizza_type
FROM new_customer_orders AS c
	JOIN pizza_names AS p ON p.pizza_id = c.pizza_id
	JOIN new_runner_orders AS r ON c.order_id = r.order_id
WHERE cancellation IS NULL
GROUP BY p.pizza_name
ORDER BY n_pizza_type DESC;

-- 5. How many Vegetarian and Meatlovers were ordered by each customer?
select customer_id, 
sum( Case
       when pizza_id = 1 then 1
       Else 0
	 END
     ) as meat_lovers,
sum( case
       when pizza_id = 2 then 1
       else 0
     end   
	) as Vegetarian
from new_customer_orders
group by customer_id
order by customer_id;


-- 6. What was the maximum number of pizzas delivered in a single order?
WITH cte_order_count AS (
	SELECT c.order_id,
		count(c.pizza_id) AS n_orders
	FROM new_customer_orders AS c
		JOIN new_runner_orders AS r ON c.order_id = r.order_id
	WHERE r.cancellation IS NULL
	GROUP BY c.order_id
)
SELECT max(n_orders) AS max_n_orders
FROM cte_order_count;

-- 7. For each customer, how many delivered pizzas had at least 1 change and how many had no changes?
SELECT c.customer_id,
	sum(
		CASE
			WHEN c.exclusions IS NOT NULL
			OR c.extras IS NOT NULL THEN 1
			ELSE 0
		END
	) AS has_changes,
	sum(
		CASE
			WHEN c.exclusions IS NULL
			OR c.extras IS NULL THEN 1
			ELSE 0
		END
	) AS no_changes
FROM new_customer_orders AS c
	JOIN new_runner_orders AS r ON c.order_id = r.order_id
WHERE r.cancellation IS NULL
GROUP BY c.customer_id
ORDER BY c.customer_id;

-- 8. How many pizzas were delivered that had both exclusions and extras?
Select c.customer_id, 
Sum(Case
       when c.exclusions is not null
       and c.extras is not null
       then 1
       else 0
	END) as had_exclusions_extras
from new_customer_orders as c
JOIN new_runner_orders AS r ON c.order_id = r.order_id
WHERE r.cancellation IS NULL;

-- 9. What was the total volume of pizzas ordered for each hour of the day?
SELECT
	extract(hour FROM order_time) AS hour_of_day_24h,
	date_format(order_time, '%r') AS hour_of_day_12h,
	count(*) AS n_pizzas
FROM new_customer_orders
WHERE order_time IS NOT NULL
GROUP BY 
	hour_of_day_24h
	
ORDER BY hour_of_day_24h;

-- 10. What was the volume of orders for each day of the week?
SELECT dayname(order_time) AS day_of_week,
	count(*) AS n_pizzas
FROM new_customer_orders
GROUP BY day_of_week
ORDER BY day_of_week;


-------------------------------------------- B. Runner and Customer Experience ----------------------------------------------------------------------

-- 1. How many runners signed up for each 1 week period? (i.e. week starts 2021-01-01)  
WITH runner_signups AS (
	SELECT runner_id,
		registration_date,
		registration_date - (((registration_date - str_to_date('2021-01-01', '%Y-%m-%d')) % 7)) AS starting_week
	FROM runners
)
SELECT date_format(starting_week,'%Y-%m-%d') as starting_week,
	count(runner_id) AS n_runners
from runner_signups
GROUP BY starting_week
ORDER BY starting_week;

-- 2. What was the average time in minutes it took for each runner to arrive at the Pizza Runner HQ to pickup the order?
WITH runner_time AS (
	SELECT r.runner_id,
		r.order_id,
		r.pickup_time,
		c.order_time,
		timediff(r.pickup_time, c.order_time) AS runner_arrival_time
	FROM new_runner_orders AS r
	JOIN new_customer_orders AS c ON r.order_id = c.order_id
)
SELECT runner_id,
      extract( minute from
	   avg(runner_arrival_time)) as avg_arrival_time
FROM runner_time
GROUP BY runner_id
ORDER BY runner_id;


-- 3. Is there any relationship between the number of pizzas and how long the order takes to prepare?
WITH number_of_pizzas AS (
	SELECT	
		order_id,
		order_time,
		count(pizza_id) AS n_pizzas
	FROM new_customer_orders
	GROUP BY 
		order_id,
		order_time	
),
preperation_time AS (
	SELECT
		r.runner_id,
		r.pickup_time,
		n.order_time,
		n.n_pizzas,
		timediff(r.pickup_time, n.order_time) AS runner_arrival_time
	FROM new_runner_orders AS r
	JOIN number_of_pizzas AS n
	ON r.order_id = n.order_id
	WHERE r.pickup_time IS NOT null
)
SELECT
	n_pizzas,
	time(avg(runner_arrival_time)) AS avg_order_time
FROM preperation_time
GROUP BY n_pizzas
ORDER BY n_pizzas;


-- 4a. What was the average distance traveled for each customer?
SELECT c.customer_id,
	floor(avg(r.distance)) AS avg_distance_rounded_down,
	round(avg(r.distance), 2) AS avg_distance,
	ceil(avg(r.distance)) AS avg_distance_rounded_up
FROM new_runner_orders AS r
JOIN new_customer_orders AS c ON c.order_id = r.order_id
GROUP BY customer_id
ORDER BY customer_id;

-- 4b. What was the average distance travelled for each runner?
SELECT runner_id,
	floor(avg(distance)) AS avg_distance_rounded_down,
	round(avg(distance), 2) AS avg_distance,
	ceil(avg(distance)) AS avg_distance_rounded_up
FROM new_runner_orders
GROUP BY runner_id
ORDER BY runner_id;

-- 5. What was the difference between the longest and shortest delivery times for all orders?
SELECT
	min(duration) AS min_time,
	max(duration) AS max_time,
	max(duration) - min(duration) AS time_diff
FROM new_runner_orders;

-- 6. What was the average speed for each runner for each delivery and do you notice any trend for these values?
WITH customer_order_count AS (
	SELECT customer_id,
		order_id,
		order_time,
		count(pizza_id) AS n_pizzas
	FROM new_customer_orders
	GROUP BY customer_id,
		order_id,
		order_time
)
SELECT c.customer_id,
	r.order_id,
	r.runner_id,
	c.n_pizzas,
	r.distance,
	r.duration,
	round(60 * r.distance / r.duration, 2) AS runner_speed
FROM new_runner_orders AS r
JOIN customer_order_count AS c 
ON r.order_id = c.order_id
WHERE r.pickup_time IS NOT NULL
ORDER BY runner_speed DESC;

-- 7. What is the successful delivery percentage for each runner?
SELECT runner_id,
	count(pickup_time) AS delivered_pizzas,
	count(order_id) AS total_orders,
	(
		round(100 * count(pickup_time) / count(order_id))
	) AS delivered_percentage
FROM new_runner_orders
GROUP BY runner_id
ORDER BY runner_id;

----------------------------- C. Ingredient Optimisation ------------------------------------

-- We will create a temporary table with the unnested array of pizza toppings in pizza_recipe table.
Use Pizza_Runner;
DROP TABLE IF EXISTS recipe_toppings;
CREATE temporary TABLE recipe_toppings AS (
	SELECT
        pn.pizza_name,
		pr.pizza_id,
		Cast(SUBSTRING_INDEX(SUBSTRING_INDEX(pr.toppings, ',', numbers.n), ',', -1) as unsigned) AS toppings
        FROM (
  SELECT 1 n UNION ALL
  SELECT 2 UNION ALL
  SELECT 3 Union ALL
  SELECT 4 Union ALL
  SELECT 5  Union ALL  
  SELECT 6  Union ALL
  SELECT 7 Union ALL
  SELECT 8 Union ALL
  SELECT 9 
) numbers
	JOIN pizza_recipes AS pr
	ON CHAR_LENGTH(pr.toppings) - CHAR_LENGTH(REPLACE(pr.toppings, ',', '')) >= numbers.n - 1
    join pizza_names as pn
    on pr.pizza_id = pn.pizza_id
ORDER BY pr.pizza_id, toppings
);
select * from recipe_toppings;


-- 1. What are the standard ingredients for each pizza?
SELECT rt.pizza_name,
	pt.topping_name
FROM recipe_toppings AS rt
JOIN pizza_toppings AS pt 
ON rt.toppings = pt.topping_id
ORDER BY rt.pizza_name;

-- Or flattened list of all toppings per pizza type.
WITH pizza_toppings_recipe AS (
	SELECT
		rt.pizza_name,
		pt.topping_name
	FROM recipe_toppings AS rt
	JOIN pizza_toppings AS pt
	ON rt.toppings = pt.topping_id
	ORDER BY rt.pizza_name
)
SELECT
	pizza_name,
	group_concat(topping_name separator ',') AS all_toppings
FROM
	pizza_toppings_recipe
GROUP BY
	pizza_name;
    
    
-- 2. What was the most commonly added extra?
WITH get_extras AS (
	SELECT extras,
           RANK() OVER (ORDER BY count(extras) desc) AS rnk_extras
	       from(SELECT Cast(trim(SUBSTRING_INDEX(SUBSTRING_INDEX(c.extras, ',', n), ',', -1)) as unsigned) AS extras
				FROM new_customer_orders c
				INNER JOIN (
				SELECT 1 n UNION ALL
				SELECT 2 UNION ALL
				SELECT 3
				) as numbers ON CHAR_LENGTH(c.extras) - CHAR_LENGTH(REPLACE(c.extras, ',', '')) >= n - 1
		   ) as extras
		   GROUP BY extras
)
SELECT
	topping_name
FROM pizza_toppings
WHERE topping_id = (SELECT extras FROM get_extras WHERE rnk_extras = 1);


--  3. What was the most common exclusion?
WITH get_exclusions AS (
	SELECT exclusions,
           RANK() OVER (ORDER BY count(exclusions) desc) AS rnk_exclusions
	       from(SELECT Cast(trim(SUBSTRING_INDEX(SUBSTRING_INDEX(c.exclusions, ',', n), ',', -1)) as unsigned) AS exclusions
				FROM new_customer_orders c
				INNER JOIN (
				SELECT 1 n UNION ALL
				SELECT 2 
				) as numbers ON CHAR_LENGTH(c.exclusions) - CHAR_LENGTH(REPLACE(c.exclusions, ',', '')) >= n - 1
		   ) as exclusions
		   GROUP BY exclusions
)
SELECT
	topping_id,
	topping_name
FROM pizza_toppings
WHERE topping_id in (SELECT exclusions FROM get_exclusions WHERE rnk_exclusions = 1);


-- 4. Generate an order item for each record in the customers_orders table in the format of one of the following:
--          *Meat Lovers
--          *Meat Lovers - Exclude Beef
--          *Meat Lovers - Extra Bacon
--          *Meat Lovers - Exclude Cheese, Bacon - Extra Mushroom, Peppers

-- Create a temp table and give customer orders a unique id using row_number
DROP TABLE IF EXISTS id_customer_orders;
CREATE TEMPORARY TABLE id_customer_orders AS (
	SELECT
		row_number() OVER (ORDER BY order_id) AS row_id,
		order_id,
		customer_id,
		pizza_id,
		exclusions,
		extras,
		order_time
FROM
	new_customer_orders
);

-- Create a temp table and unnest the exclusions array.
DROP TABLE IF EXISTS get_exclusions;
CREATE TEMPORARY TABLE get_exclusions AS (
	SELECT
		row_id,
		order_id,
		Cast(trim(SUBSTRING_INDEX(SUBSTRING_INDEX(exclusions, ',', numbers.n), ',', -1)) as unsigned) AS single_exclusions
	FROM id_customer_orders
    inner JOIN (
        SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
    ) AS numbers
     WHERE
    numbers.n <= 1 + (LENGTH(exclusions) - LENGTH(REPLACE(exclusions, ',', '')))
	
);
select * from get_exclusions;

-- Create a temp table and unnest the extras array.
DROP TABLE IF EXISTS get_extras;
CREATE TEMPORARY TABLE get_extras AS (
	SELECT
		row_id,
		order_id,
		Cast(trim(SUBSTRING_INDEX(SUBSTRING_INDEX(extras, ',', numbers.n), ',', -1)) as unsigned) AS single_extras
	FROM id_customer_orders
    inner JOIN (
        SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
    ) AS numbers
     WHERE
    numbers.n <= 1 + (LENGTH(extras) - LENGTH(REPLACE(extras, ',', '')))
	
);
select * from get_extras;

WITH get_exlusions_and_extras AS (
	SELECT
		c.row_id,
		c.order_id,
		pn.pizza_name,
		CASE
			WHEN c.exclusions IS NULL AND c.extras IS NULL THEN NULL
			ELSE 
				(SELECT
					group_concat((SELECT topping_name FROM pizza_toppings WHERE topping_id = get_exc.single_exclusions) separator ', ')
				FROM
					get_exclusions AS get_exc
				WHERE order_id =c.order_id)
		END AS all_exclusions,
		CASE
			WHEN c.exclusions IS NULL AND c.extras IS NULL THEN NULL
			ELSE
				(SELECT
					group_concat((SELECT topping_name FROM pizza_toppings WHERE topping_id = get_ext.single_extras) separator ', ')
				FROM
					get_extras AS get_ext
				WHERE order_id =c.order_id)
		END AS all_extras
	FROM pizza_names AS pn
    JOIN id_customer_orders AS c
	ON c.pizza_id = pn.pizza_id
    LEFT JOIN get_extras AS get_ext
	ON get_ext.order_id = c.order_id AND c.extras IS NOT NULL
	LEFT JOIN get_exclusions AS get_exc
	ON get_exc.order_id = c.order_id AND c.exclusions IS NOT NULL
	GROUP BY 
		c.row_id,
		c.order_id,
		pn.pizza_name,
		c.exclusions,
		c.extras
	ORDER BY c.row_id
    
)
SELECT
	CASE
		WHEN all_exclusions IS NOT NULL AND all_extras IS NULL THEN concat(pizza_name, ' - ', 'Exclude: ', all_exclusions)
		WHEN all_exclusions IS NULL AND all_extras IS NOT NULL THEN concat(pizza_name, ' - ', 'Extra: ', all_extras)
		WHEN all_exclusions IS NOT NULL AND all_extras IS NOT NULL THEN concat(pizza_name, ' - ', 'Exclude: ', all_exclusions, ' - ', 'Extra: ', all_extras)
		ELSE pizza_name
	END AS pizza_type
FROM get_exlusions_and_extras;



--------------------------------------------------   D. Pricing & Ratings --------------------------------------------------------------

-- 1. If a Meat Lovers pizza costs $12 and Vegetarian costs $10 and there were no charges for changes - how much money has Pizza Runner made so far if there are no delivery fees?

DROP TABLE IF EXISTS pizza_income;
CREATE TEMPORARY TABLE pizza_income AS (
	SELECT
		sum(total_meatlovers) | sum(total_veggie) AS total_income
	from
		(SELECT 
			c.order_id,
			c.pizza_id,
			sum(
				CASE
					WHEN pizza_id = 1 THEN 12
					ELSE 0
				END
			) AS total_meatlovers,
			sum(
				CASE
					WHEN pizza_id = 2 THEN 10
					ELSE 0
				END
			) AS total_veggie
		FROM new_customer_orders AS c
		JOIN new_runner_orders AS r
		ON r.order_id = c.order_id
		WHERE 
			r.cancellation IS NULL
		GROUP BY 
			c.order_id,
			c.pizza_id,
			c.extras) AS tmp);
		
SELECT * FROM pizza_income;


-- 2. What if there was an additional $1 charge for any pizza extras?

DROP TABLE IF EXISTS get_extras_cost;
CREATE TEMPORARY TABLE get_extras_cost AS (
	SELECT order_id,
		count(each_extra) AS total_extras
	from (
			SELECT order_id,
				Cast(trim(SUBSTRING_INDEX(SUBSTRING_INDEX(extras, ',', numbers.n), ',', -1)) as unsigned) AS each_extra
			FROM new_customer_orders
            inner JOIN (
				SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
            ) AS numbers
                  WHERE
                      numbers.n <= 1 + (LENGTH(extras) - LENGTH(REPLACE(extras, ',', '')))
		) AS tmp
	GROUP BY order_id
);
with calculate_totals as (
	SELECT 
		c.order_id,
		c.pizza_id,
		sum(
			CASE
				WHEN pizza_id = 1 THEN 12
				ELSE 0
			END
		) AS total_meatlovers,
		sum(
			CASE
				WHEN pizza_id = 2 THEN 10
				ELSE 0
			END
		) AS total_veggie,
		gec.total_extras
	FROM new_customer_orders AS c
	JOIN new_runner_orders AS r ON r.order_id = c.order_id
	LEFT JOIN get_extras_cost AS gec ON gec.order_id = c.order_id
	WHERE r.cancellation IS NULL
	GROUP BY c.order_id,
		c.pizza_id,
		c.extras,
		gec.total_extras
)
SELECT sum(total_meatlovers) | sum(total_veggie) | sum(total_extras) AS total_income
FROM calculate_totals;


-- 3. The Pizza Runner team now wants to add an additional ratings system that allows customers to rate their runner, how would you design an additional table for this new dataset
--    - generate a schema for this new table and insert your own data for ratings for each successful customer order between 1 to 5.

DROP TABLE IF EXISTS runner_rating_system;
CREATE TABLE runner_rating_system (
	rating_id INTEGER,
	customer_id INTEGER,
	order_id INTEGER,
	runner_id INTEGER,
	rating INTEGER
);
INSERT INTO runner_rating_system (
		rating_id,
		customer_id,
		order_id,
		runner_id,
		rating
	)
VALUES ('1', '101', '1', '1', '3'),
	('2', '103', '4', '2', '4'),
	('3', '102', '5', '3', '5'),
	('4', '102', '8', '2', '2'),
	('5', '104', '10', '1', '5');

Select * from runner_rating_system;

-- 4. Using your newly generated table - can you join all of the information together to form a table which has the following information for successful deliveries?
--  *customer_id --  *order_id -- *runner_id -- *rating -- *order_time  -- *pickup_time  -- *Time between order and pickup -- *Delivery duration -- *Average speed -- *Total number of pizzas 

SELECT co.customer_id,
	co.order_id,
	ro.runner_id,
	rrs.rating,
	co.order_time,
	ro.pickup_time,
	(
		timediff(ro.pickup_time, co.order_time)
	) AS time_diff,
	ro.duration,
	round(60 * ro.distance / ro.duration, 2) AS avg_speed,
	count(ro.pickup_time) AS total_delivered
FROM new_customer_orders AS co
	JOIN new_runner_orders AS ro ON ro.order_id = co.order_id
	LEFT JOIN runner_rating_system AS rrs ON ro.order_id = rrs.order_id
WHERE ro.cancellation IS NULL
GROUP BY co.customer_id,
	co.order_id,
	ro.runner_id,
	rrs.rating,
	co.order_time,
	ro.pickup_time,
	time_diff,
	ro.duration,
	avg_speed
ORDER BY co.order_id


-- 5. If a Meat Lovers pizza was $12.00 and Vegetarian $10.00 fixed prices with no cost for extras and each runner is paid $0.30 per kilometre traveled 
--    - how much money does Pizza Runner have left over after these deliveries?

WITH total_payout AS (
	SELECT
		(sum(distance*2) * .30) AS payout
	FROM new_runner_orders
	WHERE cancellation IS NULL
)
SELECT
	total_income - payout AS profit
from
	total_payout,
	pizza_income;