/* Проект «Секреты Тёмнолесья»
 * Цель проекта: изучить влияние характеристик игроков и их игровых персонажей 
 * на покупку внутриигровой валюты «райские лепестки», а также оценить 
 * активность игроков при совершении внутриигровых покупок
 * 
 * Автор: Головин Евгений
 * Дата: 18.02.2025
*/

-- Часть 1. Исследовательский анализ данных
-- Задача 1. Исследование доли платящих игроков

-- 1.1. Доля платящих пользователей по всем данным:

SELECT 
	COUNT(*) AS cnt_u -- общее количество игроков
	,COUNT(*) FILTER(WHERE payer = 1) AS cnt_u_payers -- количество платящих
	,ROUND((COUNT(*) FILTER(WHERE payer = 1)) / CAST(COUNT(*) AS NUMERIC), 3) AS payers_segment -- доля платящих
FROM fantasy.users; 
-- Доля платящих пользователей по всем данным: 17.7%

-- Еще интересный вариант, сохраню.
--SELECT 
--    COUNT(payer) AS total_users, -- общее количество игроков
--    SUM(payer) AS total_payers, -- количество платящих (сумма единичек)
--    ROUND(AVG(payer), 3) AS payers_share -- доля платящих (среднее значение)
--FROM fantasy.users;

-- В fantasy.users у нас уникальные пользователи, т.е. COUNT(*) = COUNT(DISTINCT id) .
--SELECT  -- убедимся, что payer содержит только два значения: 1 и 0.
--	payer
--	,COUNT(*)
--FROM fantasy.users
--GROUP BY 1;
-- Можно использовать конструкцию CASE — (CASE WHEN payer = 1 THEN 1 ELSE 0 END)

-- 1.2. Доля платящих пользователей в разрезе расы персонажа:

SELECT 
	r.race
	,COUNT(*) AS cnt_u_r -- кол-во всех игроков расы
	,COUNT(*) FILTER(WHERE u.payer = 1) AS cnt_u_r_payers -- кол-во платящих игроков расы
	,ROUND((COUNT(*) FILTER(WHERE u.payer = 1)) / CAST(COUNT(*) AS NUMERIC), 3) AS payers_segment -- доля платящих по расам
FROM fantasy.users u
JOIN fantasy.race r USING(race_id)
GROUP BY 1;

-- Задача 2. Исследование внутриигровых покупок
-- 2.1. Статистические показатели по полю amount:

SELECT
	COUNT(amount) AS amount_cnt
	,SUM(amount) AS amount_sum
	,MAX(amount) AS max_amount
	,MIN(amount) AS min_amount
	,ROUND(AVG(amount)::NUMERIC, 2) AS avg_amount
	,ROUND(CAST(percentile_cont(0.5) WITHIN GROUP (ORDER BY amount) AS NUMERIC), 2) AS mediana_amount
	,ROUND(STDDEV(amount)::NUMERIC, 2) AS stddev_amount
FROM fantasy.events;
-- общее количество покупок: 1307678
-- суммарная стоимость всех покупок: 686615040
-- максимальная стоимость покупки: 486615.1
-- минимальная стоимость покупки: 0
-- средняя стоимость покупки: 525.69
-- медианная стоимость покупки: 74.86
-- стандартное отклонение стоимости покупки: 2517.35

-- 2.2: Аномальные нулевые покупки:

SELECT 
	COUNT(amount) FILTER(WHERE amount = 0)
	,ROUND((COUNT(amount) FILTER(WHERE amount = 0)) / CAST(COUNT(amount) AS NUMERIC), 4) AS payers_segment
FROM fantasy.events;
-- Альтернативный вариант подсета доли нулевых покупок AVG(CASE WHEN amount = 0 THEN 1 ELSE 0 END) 
-- кол-во покупок с нулевой стоимостью: 907
-- доля нулевых покупок от общего числа покупок: 0.07%
-- покупки с нулевой стоимостью не помогают зарабатывать внутриигровую 
-- валюту «райские лепестки», и их следует исключить при решении следующих задач.

-- 2.3: Сравнительный анализ активности платящих и неплатящих игроков:
-- Игроки покупают предметы за "райские лепестки". Но часть игроков покупает "райские лепестки" 
-- за реальные деньги - платящие игроки, у них payer=1. Остальные совершают покупки, но лепестки за 
-- реальные деньги не покупают - не платящие, у них payer=0.

SELECT 
	 CASE 
	 	WHEN payer = 0
		THEN 'Неплатящие'
		WHEN payer = 1
		THEN 'Платящие'
	 END AS payer -- две группы пользователей: платящие(1) и неплатящие(0) покупатели предметов
	,COUNT(id) AS cnt_users -- кол-во юзеров, совершивших хоть одну сделку
	,ROUND(AVG(cnt_amount)) AS avg_cnt_amount -- среднее кол-во покупок
	,ROUND(AVG(sum_amount)::NUMERIC, 2) AS avg_sum_amount -- средняя сумма покупки на одного игрока
FROM (
	SELECT 
		u.id
		,u.payer
		,COUNT(e.amount) AS cnt_amount
		,SUM(e.amount) AS sum_amount
	FROM fantasy.events e 
	JOIN fantasy.users u USING(id)
	WHERE e.amount <> 0
	GROUP BY u.id, u.payer ) _ 
GROUP BY payer;

-- 2.4: Популярные эпические предметы:

SELECT 
	i.game_items
	-- кол-во покупок каждого предмета
	,COUNT(e.transaction_id) AS cnt_purchases
	-- доля продаж предмета от всех покупок
	,ROUND(COUNT(e.transaction_id)::NUMERIC / 
	 (SELECT COUNT(*) FROM fantasy.events WHERE amount <> 0), 4) AS slice_all_purchases
	 -- доля игроков, кто купил предмет хоть раз, от всех игроков-покупателей
	,ROUND(COUNT(DISTINCT e.id)::NUMERIC / (SELECT COUNT(DISTINCT id) FROM fantasy.events WHERE amount > 0), 4) AS pop_items_users
FROM fantasy.events e
JOIN fantasy.items i USING(item_code)
WHERE e.amount <> 0
GROUP BY i.item_code, i.game_items
ORDER BY pop_items_users DESC;

-- Часть 2. Решение ad hoc-задач
-- Задача 1. Зависимость активности игроков от расы персонажа:

WITH stat_by_user AS (
-- Считаем в разере по каждому юзеру с ненулевой ценой покупки: кол-во покупок, среднюю стоимость покупки, 
-- сумму всех покупок 
	SELECT 
		id
		,COUNT(transaction_id) AS cnt_purch_per_u
--		,AVG(amount) AS avg_am_per_u
		,SUM(amount) AS sum_am_per_u
	FROM fantasy.events
	WHERE amount <> 0
	GROUP BY id
) 
SELECT 
	r.race
	-- общее количество зарегистрированных игроков рас
	,COUNT(u.id) AS cnt_u
	-- количество игроков рас, соверершавших ненулевые внутриигровые покупки
	,COUNT(sbu.id) AS cnt_u_purch
	-- соотношение игроков рас, соверершавших ненулевые внутриигровые покупки ко всем внутри расы
	,ROUND(COUNT(sbu.id) / CAST(COUNT(u.id) AS NUMERIC), 3) AS cnt_u_purch_slice
	-- в разрезе расы доля платящих игроков от количества игроков, которые совершили ненулевые покупки 
	,ROUND((COUNT(sbu.id) FILTER(WHERE payer = 1)) / CAST(COUNT(sbu.id) AS NUMERIC), 3) AS slice_payers
	-- в разрезе расы среднее количество покупок на одного игрока
	,ROUND(AVG(sbu.cnt_purch_per_u)) AS avg_cnt_purch_per_u
	-- в разрезе расы средняя стоимость одной покупки на одного игрока
	,ROUND((AVG(sbu.sum_am_per_u)::NUMERIC / AVG(sbu.cnt_purch_per_u)), 2) AS avg_am_per_u
	-- в разрезе расы средняя суммарная стоимость всех покупок на одного игрока
	,ROUND(AVG(sbu.sum_am_per_u)::NUMERIC, 2) AS avg_sum_am_per_u
FROM fantasy.users u
LEFT JOIN stat_by_user sbu USING(id)
LEFT JOIN fantasy.race r USING(race_id)
GROUP BY r.race
ORDER BY cnt_u_purch;

-- Задача 2: Частота покупок
-- Маркетологи решили выяснить, как часто игроки пользуются внутриигровой валютой для покупки эпических предметов. 
-- Их интересует общее количество покупок на одного игрока и средний интервал в днях между этими покупками. Коллеги 
-- просят для каждого игрока посчитать эти значения и разделить всех игроков на три примерно равные группы по частоте 
-- покупки
-- Для каждой группы нужно посчитать:
-- количество игроков, которые совершили покупки;
-- количество платящих игроков, совершивших покупки, и их доля от общего количества игроков, совершивших покупку;
-- среднее количество покупок на одного игрока;
-- среднее количество дней между покупками на одного игрока.
-- При расчётах исключите покупки с нулевой стоимостью. Коллеги из маркетинга также просят учитывать только активных 
-- клиентов, которые совершили 25 или более покупок. Результат представьте в виде одной сводной таблицы со всеми 
-- необходимыми полями.

WITH stat_by_user AS (
-- Считаем в разере по каждому юзеру с ненулевой ценой покупки: кол-во покупок, среднее количество 
-- дней между покупками на одного игрока
	SELECT
		DISTINCT id
		,cnt_purch_per_u
		-- среднее количество дней между покупками на одного игрока
		,AVG(COALESCE(purch_dt, '0 days'::INTERVAL)) OVER(PARTITION BY id) AS avg_d_between_purch
	FROM (	
		SELECT 
			id
			-- количество покупок на одного игрока
			,COUNT(transaction_id) OVER(PARTITION BY id) AS cnt_purch_per_u
			-- разница между 
			,AGE(date::date, LAG(date::date) OVER(PARTITION BY id ORDER BY date::date)) AS purch_dt
		FROM fantasy.events
		WHERE amount <> 0 ) _
), 
-- разбиваем всех игроков на три примерно равные группы по частоте покупки
-- (по среднему времени между покупками)
users_by_segments AS (
	SELECT
		id
		,cnt_purch_per_u
		,avg_d_between_purch
		,NTILE(3) OVER(ORDER BY avg_d_between_purch) AS users_segments
	FROM stat_by_user
	WHERE cnt_purch_per_u >= 25 -- нам интересны пользователи с кол-вом покупок не менее 25
)
-- считаем статистику в разбивке по 3-м группам активностей покупателей
SELECT 
	CASE 
		WHEN users_segments = 1
		THEN 'Высокая частота'
		WHEN users_segments = 2
		THEN 'Умеренная частота'
		WHEN users_segments = 3
		THEN 'Низкая частота'	
	END AS groups_by_activity
	-- количество игроков, которые совершили покупки по сегментам(получилось равное кол-во игроков в каждом сегменте)
	,COUNT(ubs.id) AS cnt_u_with_purch
	-- количество платящих игроков, совершивших покупки, по сегментам
	,COUNT(u.id) FILTER(WHERE payer = 1) AS cnt_payers
	-- доля платящих игроков от общего количества игроков, совершивших покупку по сегментам
	,ROUND((COUNT(u.id) FILTER(WHERE payer = 1)) / COUNT(ubs.id)::NUMERIC, 3) AS payers_slice
	-- среднее количество покупок на одного игрока по сегментам
	,ROUND(AVG(cnt_purch_per_u)::NUMERIC) AS avg_cnt_purch_per_u
	-- среднее количество дней между покупками на одного игрока по сегментам
	,DATE_TRUNC('day', justify_interval(AVG(avg_d_between_purch))) AS avg_d_between_purch
FROM users_by_segments ubs
JOIN fantasy.users u USING(id)
GROUP BY groups_by_activity;	




--------------------------- Доп расчет----------------------------
SELECT 
	COUNT(DISTINCT id) FILTER (WHERE amount = 0) cnt_0
	,COUNT(DISTINCT id) FILTER (WHERE amount <> 0) cnt_1
	,CAST(COUNT(DISTINCT id) FILTER (WHERE amount = 0) AS NUMERIC) / COUNT(DISTINCT id) FILTER (WHERE amount <> 0) AS dt_cnt
FROM fantasy.events;

SELECT amount FROM fantasy.events ORDER BY 1 DESC LIMIT 100;

SELECT (SUM(amount) - 486615.1 - 449183.16) / (COUNT(amount) -2)
FROM fantasy.events ORDER BY 1 DESC LIMIT 100;
