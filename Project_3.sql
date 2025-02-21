-- Временной интервал
SELECT
	MIN(first_day_exposition),
	MAX(first_day_exposition)
FROM real_estate.advertisement;

-- Типы населённых пунктов
SELECT
	t.type,
	COUNT(distinct f.city_id) AS count_type,
	COUNT(f.id) AS count_ann
FROM real_estate.flats f 
LEFT JOIN real_estate.type t USING (type_id)
GROUP BY t.type;

--Время активности объявления
SELECT
	MIN(days_exposition),
	MAX(days_exposition),
	ROUND(AVG(days_exposition::NUMERIC), 2),
	percentile_cont(0.5) WITHIN GROUP(ORDER BY days_exposition) AS mediana 
FROM real_estate.advertisement;

--Доля снятых с публикации объявлений
SELECT ROUND(((SELECT COUNT(*)
FROM real_estate.advertisement
WHERE days_exposition IS NOT NULL) / COUNT(*)::numeric) * 100, 2)
FROM real_estate.advertisement;

--Объявления Санкт-Петербурга 6X8I
SELECT ROUND(
	((SELECT COUNT(*)
	 FROM real_estate.flats
	 WHERE city_id = '6X8I') / COUNT (*)::numeric) * 100 , 2)
FROM real_estate.flats;

--Стоимость квадратного метра
WITH price AS(
	SELECT
		f.id,
		f.total_area,
		a.last_price / f.total_area AS price_per_meter
	FROM real_estate.flats f 
	LEFT JOIN real_estate.advertisement a USING(id)
)
SELECT
	MIN(price_per_meter),
	MAX(price_per_meter),
	ROUND(AVG(price_per_meter::NUMERIC), 2),
	percentile_cont(0.5) WITHIN GROUP(ORDER BY price_per_meter) AS mediana 
FROM price;

--Статистические показатели
SELECT
	MIN(total_area),
	MAX(total_area),
	ROUND(AVG(total_area::NUMERIC), 2),
	percentile_cont(0.5) WITHIN GROUP(ORDER BY total_area) AS mediana,
	ROUND(percentile_cont(0.99) WITHIN GROUP(ORDER BY total_area)::NUMERIC, 1) AS perc_99
FROM real_estate.flats;

--фильтрация
--Задача 1. Время активности объявлений

WITH limits AS (
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id    
    FROM real_estate.flats
    WHERE
        total_area < (SELECT total_area_limit FROM limits)
        AND rooms < (SELECT rooms_limit FROM limits)
        AND balcony < (SELECT balcony_limit FROM limits)
        AND ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)
    ),
range_activity AS(
	SELECT
		id,
		CASE
			WHEN days_exposition BETWEEN 1 AND 30 
				THEN 'До месяца'
			WHEN days_exposition BETWEEN 31 AND 90 
				THEN 'До трёх месяцев'
			WHEN days_exposition BETWEEN 91 AND 180 
				THEN 'Менее полугода'
			WHEN days_exposition > 180 
				THEN 'Более полугода'
			WHEN days_exposition IS NULL 
				THEN 'Ещё актуально'
		END AS active,
		days_exposition,
		last_price AS price
	FROM real_estate.advertisement
	WHERE DATE_TRUNC('year', first_day_exposition) BETWEEN '2015-01-01' AND '2018-12-31'
),
-- Выведем объявления без выбросов:
info AS(
	SELECT 
		*,
		CASE
			WHEN city_id = '6X8I' THEN 'Санкт-Петербург'
			ELSE 'ЛенОбл'
		END AS name_city,
		price / total_area AS price_per_metr
	FROM real_estate.flats f
	LEFT JOIN range_activity a USING(id)
	WHERE id IN (SELECT * FROM filtered_id)
)
SELECT 
	name_city,
	active,
	COUNT(id),
	AVG(COALESCE(total_area, 0)) AS "Средняя площадь недвижимости",
	AVG(COALESCE(price_per_metr, 0)) AS "Средняя стоимость за один квадратный метр",
	AVG(COALESCE(rooms, 0)) AS "Комнаты",
	AVG(COALESCE(balcony, 0)) AS "Балконы"
FROM info
WHERE active IS NOT NULL
GROUP BY active, name_city
ORDER BY name_city DESC;	


--Задача 2. Сезонность объявлений

-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits) 
        AND rooms < (SELECT rooms_limit FROM limits) 
        AND balcony < (SELECT balcony_limit FROM limits) 
        AND ceiling_height < (SELECT ceiling_height_limit_h FROM limits) 
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)
    ),
-- Выведем объявления без выбросов:
adds_date AS (
	SELECT 
		*,
		EXTRACT(YEAR FROM first_day_exposition) AS year,
		EXTRACT(MONTH FROM first_day_exposition) AS month,
		DATE(first_day_exposition + INTERVAL '1 day' * days_exposition) AS end_date,
		last_price / total_area AS price_per_metr
	FROM real_estate.advertisement a
	LEFT JOIN (SELECT id, total_area FROM real_estate.flats) f USING(id)
	WHERE id IN (SELECT * FROM filtered_id) 
		AND 
		DATE_TRUNC('year', first_day_exposition) BETWEEN '2015-01-01' AND '2018-12-31'
	ORDER BY first_day_exposition ASC
),
month_end_ads AS(
	SELECT
		EXTRACT(MONTH FROM end_date) AS end_ads,
		COUNT(EXTRACT(MONTH FROM end_date)) AS count_end_ads
	FROM adds_date 
	WHERE end_date IS NOT NULL
	GROUP BY end_ads
)
SELECT
	month,
	COUNT(first_day_exposition) AS count_ads, -- Количетсво поданных объявлений
	count_end_ads, -- Количество снятых объявлений
	ROUND((COUNT(first_day_exposition) / count_end_ads::numeric), 2) AS diff,
	AVG(price_per_metr),
	AVG(total_area)
FROM adds_date d
LEFT JOIN month_end_ads m ON m.end_ads = d.month 
GROUP BY month, count_end_ads;

--Задача 3. Анализ рынка недвижимости Ленобласти

WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits) 
        AND rooms < (SELECT rooms_limit FROM limits) 
        AND balcony < (SELECT balcony_limit FROM limits) 
        AND ceiling_height < (SELECT ceiling_height_limit_h FROM limits) 
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)
    ),
-- Выведем объявления без выбросов:
adds_date AS (
	SELECT 
		*,
		last_price / total_area AS price_per_metr
	FROM real_estate.advertisement a
	LEFT JOIN (SELECT id, total_area, city_id, city
	FROM real_estate.flats
	LEFT JOIN real_estate.city USING(city_id)) f USING(id)
	WHERE id IN (SELECT * FROM filtered_id) 
		AND 
		DATE_TRUNC('year', first_day_exposition) BETWEEN '2015-01-01' AND '2018-12-31'
		AND 
		city_id <> '6X8I'
	ORDER BY first_day_exposition ASC
),
perc_ads AS (
	SELECT 
		city,
		COUNT(id) AS end_ads
	FROM adds_date
	WHERE days_exposition IS NOT NULL
	GROUP BY city
),
all_info AS (
SELECT 
	a.city,
	COUNT(a.id) AS count_ads,
	COALESCE(p.end_ads::NUMERIC / COUNT(a.id), 0) AS prec_end_ads,
	AVG(price_per_metr) AS avg_price,
	AVG(total_area) AS avg_area,
	COALESCE(AVG(days_exposition), 0) AS avg_days_exposition
FROM adds_date a
LEFT JOIN perc_ads p ON a.city = p.city
WHERE days_exposition IS NOT NULL
GROUP BY a.city, p.end_ads
ORDER BY avg_days_exposition
)
SELECT *,
	NTILE(4) OVER(ORDER BY avg_days_exposition) AS rank
FROM all_info
WHERE count_ads >= 20;
/*количество объявлений по населённым пунктам,
доля снятых с публикаций объявлений,
средняя стоимость 1 кв. метра,
средняя площадь квартиры,
среднее количество дней продолжительность публикации объявлений*/