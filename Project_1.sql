
 * Цель проекта: изучить влияние характеристик игроков и их игровых персонажей 
 * на покупку внутриигровой валюты «райские лепестки», а также оценить 
 * активность игроков при совершении внутриигровых покупок

-- Часть 1. Исследовательский анализ данных
-- Задача 1. Исследование доли платящих игроков

-- 1.1. Доля платящих пользователей по всем данным:
-- Напишите ваш запрос здесь
SELECT 
	COUNT(DISTINCT id) AS all_players,
	COUNT(DISTINCT CASE WHEN payer = 1 THEN id END) AS payer_players,
	COUNT(DISTINCT CASE WHEN payer = 1 THEN id END) / COUNT(DISTINCT id)::NUMERIC AS counts
FROM
	fantasy.users;
-- 1.2. Доля платящих пользователей в разрезе расы персонажа:

	SELECT 
		r.race,
		COUNT(DISTINCT e.id) AS all_players_events,
		COUNT(DISTINCT u.id) AS all_players,
		COUNT(DISTINCT e.id) / COUNT(DISTINCT u.id)::NUMERIC AS counts
	FROM
		fantasy.events e 
	RIGHT JOIN
		fantasy.users u USING(id)
	LEFT JOIN 
		fantasy.race r USING(race_id)
	GROUP BY
		r.race;


-- Задача 2. Исследование внутриигровых покупок
-- 2.1. Статистические показатели по полю amount:
	SELECT 
		COUNT(*) AS count_orders,
		SUM(amount) AS sum_orders,
		MIN(amount) AS min_amount,
		MAX(amount) AS max_amount,
		AVG(amount) AS avg_amount,
		percentile_disc(0.5) WITHIN GROUP (ORDER BY amount) AS mediana,
		STDDEV(amount) AS stand_dev
	FROM 
		fantasy.events;


-- 2.2: Аномальные нулевые покупки:
WITH stat_amount AS (
	SELECT 
		COUNT(*) AS count_orders,
		SUM(amount) AS sum_orders,
		MIN(amount) AS min_amount,
		MAX(amount) AS max_amount,
		AVG(amount) AS avg_amount,
		percentile_disc(0.5) WITHIN GROUP (ORDER BY amount) AS mediana,
		STDDEV(amount) AS stand_dev,
		(SELECT 
			COUNT(*)
		 FROM
			 fantasy.events
		 WHERE 
			 amount = 0) AS free_orders
	FROM 
		fantasy.events
)
SELECT
	free_orders,
	free_orders / count_orders::NUMERIC AS share
FROM stat_amount;

-- 2.3: Сравнительный анализ активности платящих и неплатящих игроков:
WITH stat_events_players AS(
	SELECT
		u.payer,
		COUNT(DISTINCT u.*) AS all_players,
		COUNT(e.transaction_id) AS all_trans,
        SUM(e.amount) AS total_amount,  
        COUNT(e.transaction_id) / COUNT(DISTINCT u.id)::NUMERIC AS avg_ords_player, 
        SUM(e.amount) / COUNT(DISTINCT u.id)::NUMERIC AS avg_amount_player
	FROM	
		fantasy.users u
	LEFT JOIN
		fantasy.events e USING(id)
	WHERE
		e.amount > 0
	GROUP BY u.payer
)
SELECT 
	payer,
	all_players,
	avg_ords_player,
	avg_amount_player
FROM stat_events_players;


-- 2.4: Популярные эпические предметы:
	WITH stat_items AS(
	SELECT
		i.game_items,
		i.item_code,
		COUNT(e.*) AS count_items,
		COUNT(DISTINCT e.id) AS count_players
	FROM
		fantasy.items i
	LEFT JOIN
		fantasy.events e USING(item_code)
	WHERE
		e.amount > 0
	GROUP BY 
		i.game_items,
		i.item_code
),
stat_players AS(
	SELECT 
		i.game_items,
		i.count_items,
		count_players,
		count_players / (SELECT COUNT(*) FROM fantasy.users)::NUMERIC AS proc_players,
		CASE 
			WHEN count_items = 0 THEN 0
			ELSE count_items / SUM(count_items) OVER()::NUMERIC
		END AS proc_items
	FROM 
		stat_items i 
	LEFT JOIN
		fantasy.events e USING(item_code)		
	WHERE 
		i.game_items IS NOT NULL
	GROUP BY 
		i.game_items,
		i.count_items,
		i.count_players
)
SELECT 
	*
FROM stat_players
ORDER BY 
	count_players DESC;

-- Часть 2. Решение ad hoc-задач
-- Задача 1. Зависимость активности игроков от расы персонажа:
WITH all_players AS(
	SELECT
		r.race,
		r.race_id,
		COUNT(DISTINCT u.*) AS all_players
	FROM
		fantasy.users u 
	LEFT JOIN
		fantasy.race r USING(race_id)
	GROUP BY
		r.race,
		r.race_id
),
all_stats AS(
	SELECT
		a.race,
		all_players,
		COUNT(DISTINCT e.id) AS events_players,
		COUNT(DISTINCT CASE WHEN u.payer = 1 THEN u.id END) AS payer_players,
		COUNT(e.id) AS count_ords,
		AVG(e.amount) AS avg_ords,
		SUM(e.amount) AS sum_ords
	FROM 
		all_players a
	LEFT JOIN
		fantasy.users u USING(race_id)
	LEFT JOIN
		fantasy.events e ON u.id = e.id
	WHERE
		e.amount > 0
	GROUP BY 
		a.race,
		all_players
)
SELECT 
	race,
	all_players,
	events_players / all_players::NUMERIC AS proc_events_players,
	payer_players / all_players::NUMERIC AS proc_payer_players,
	count_ords / all_players::NUMERIC AS avg_ords,
	avg_ords,
	sum_ords / all_players::NUMERIC AS avg_sum_ords
FROM all_stats;

-- Задача 2: Частота покупок
WITH all_ords AS(SELECT 
	DISTINCT u.id,
	u.payer,
	COUNT(e.transaction_id) OVER(PARTITION BY u.id) AS count_ords
FROM 
	fantasy.users u 
LEFT JOIN
	fantasy.events e USING(id)
WHERE amount != 0
),
diff AS (
	SELECT 
		*,
		date::DATE - LAG(date::DATE) OVER(PARTITION BY id ORDER BY date ASC) AS diff_ords
	FROM
		all_ords o
	LEFT JOIN 
		fantasy.events e USING(id)
	WHERE count_ords > 24
),
stat_table AS(
	SELECT
		DISTINCT id,
		count_ords,
		payer,
		AVG(diff_ords) OVER(PARTITION BY id) AS avg_days
	FROM
		diff
),
rank_users AS(
	SELECT
		*,
		NTILE(3) OVER(ORDER BY avg_days ASC) AS rank
	FROM stat_table
),
A AS(
	SELECT 
		rank,
		COUNT(id) AS all_players,
		AVG(count_ords) AS avg_ords,
		AVG(avg_days) AS avg_days,
		COUNT(CASE WHEN payer = 1 THEN 1 END) AS paying_users		
	FROM
		rank_users
	GROUP BY 
		rank
)
SELECT 
	CASE
		WHEN rank = 1 THEN 'высокая частота'
		WHEN rank = 2 THEN 'умеренная частота'
		ELSE 'низкая частота'
	END AS rank,
	all_players,
	paying_users,
	paying_users / all_players::NUMERIC AS proc_payer,
	avg_ords,
	avg_days
FROM A;

	
