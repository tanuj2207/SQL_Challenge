use dannys_diner;

-- 1. What is the total amount each customer spent at the restaurant?
select sales.customer_id, sum(menu.price) as Total_Amount from sales
join menu on sales.product_id = menu.product_id
group by sales.customer_id;

-- 2. How many days has each customer visited the restaurant?
select s.customer_id, count(distinct s.order_date) as No_of_Days_Visited from sales as s
group by s.customer_id;

-- 3. What was the first item from the menu purchased by each customer?
with cte_first_order as( 
select s.customer_id, m.product_name, row_number() over ( partition by s.customer_id order by s.order_date)as rn
from sales as s
JOIN menu AS m ON s.product_id = m.product_id
)
select customer_id, product_name
from cte_first_order 
where rn = 1;

-- 4. What is the most purchased item on the menu and how many times was it purchased by all customers?
select m.product_name, count(s.product_id) as n_purchased from menu as m
join sales as s on m.product_id = s.product_id
group by product_name
order by n_purchased desc
limit 1;

-- 5. Which item was the most popular for each customer?
WITH cte_most_popular as(
select s.customer_id, m.product_name, rank() over(partition by s.customer_id order by count(m.product_id) desc) as rnk
from sales as s
join menu as m on s.product_id = m.product_id
group by s.customer_id, m.product_name
)
select * from cte_most_popular
WHERE rnk = 1;

-- 6. Which item was purchased first by the customer after they became a member?
with first_item_purchased_after_membership as(
Select mem.customer_id, m.product_name, s.order_date, dense_rank() over(partition by mem.customer_id order by s.order_date asc) as rnk 
from members as mem
join sales as s on mem.customer_id = s.customer_id
join menu as m on s.product_id = m.product_id
where s.order_date >= mem.join_date
)
select customer_id, product_name from first_item_purchased_after_membership 
where rnk = 1;

-- 7. Which item was purchased just before the customer became a member?
with first_item_purchased_before_membership as(
Select mem.customer_id, m.product_name, s.order_date, dense_rank() over(partition by mem.customer_id order by s.order_date desc) as rnk 
from members as mem
join sales as s on mem.customer_id = s.customer_id
join menu as m on s.product_id = m.product_id
where s.order_date < mem.join_date
)
select customer_id, product_name from first_item_purchased_before_membership 
where rnk = 1;

-- 8. What is the total items and amount spent for each member before they became a member?
Select mem.customer_id, count(m.product_name) as Total_product, sum(m.price) as Total_spent
from members as mem
join sales as s on mem.customer_id = s.customer_id
join menu as m on s.product_id = m.product_id
where s.order_date < mem.join_date
group by mem.customer_id
order by mem.customer_id;

-- 9. If each $1 spent equates to 10 points and sushi has a 2x points multiplier - how many points would each customer have?

select s.customer_id as Customer, 
sum( 
Case 
    when m.product_name = "Sushi" THEN (m.price *20)
    else (m.price*10)
END
) as Customer_points
from sales as s
join menu as m on s.product_id = m.product_id
group by Customer;
 
 
-- 10. In the first week after a customer joins the program (including their join date) they earn 2x points on all items, not just sushi - how many points do customer A and B have at the end of January?
WITH cte_jan_member_points AS (
	SELECT m.customer_id AS customer,
		SUM(
			CASE
				WHEN s.order_date < m.join_date THEN 
					CASE
						WHEN m2.product_name = 'sushi' THEN (m2.price * 20)
						ELSE (m2.price * 10)
					END
				WHEN s.order_date > (m.join_date + 6) THEN 
					CASE
						WHEN m2.product_name = 'sushi' THEN (m2.price * 20)
						ELSE (m2.price * 10)
					END
				ELSE (m2.price * 20)
			END
		) AS member_points
	FROM members AS m
		JOIN sales AS s ON s.customer_id = m.customer_id
		JOIN menu AS m2 ON s.product_id = m2.product_id
	WHERE s.order_date <= '2021-01-31'
	GROUP BY customer
)
SELECT *
FROM cte_jan_member_points
ORDER BY customer;


