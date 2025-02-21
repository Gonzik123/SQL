-- Создание CTE с необходимой информацией о курсах и придметах
WITH info_courses AS(
    SELECT 
        c.id AS id_course,  -- Поле с id курса
        c.name AS course,   -- Поле с названием курса
        s.name AS subject,    -- Поле с названием предмета
        s.project AS type_subjects,    -- Поле с типом предмета
        ct.name AS course_type,    -- Поле с типом курса 
        starts_at::DATE AS date_start_courses    -- Поле с датой начала курса  
    FROM courses c
    -- Выгрузка необходимых полей из таблицы subjects (предмет, тип предмета)
    LEFT JOIN
        (SELECT id, name, project  
        FROM subjects ) s ON c.subject_id = s.id
    -- Выгрузка таблицы с типом курсов
    LEFT JOIN 
        course_types ct ON c.course_type_id = ct.id
), 
-- Создание CTE с необходимой информацией об ученике
info_users AS (
    SELECT 
        u.id AS id_user, -- Поле с id ученика
        u.last_name AS last_name_user, -- Поле с фамилией ученика
        c.name AS city -- Поле с названием города ученика
    FROM users u
    -- Выгрузка необходимых полей из таблицы cities (название города) 
    LEFT JOIN
        (SELECT id, name FROM cities) c ON c.id = u.city_id
),
-- Создание CTE с необходимой информацией о домашних заданиях
info_homework AS (
    SELECT 
        hd.id, -- id домашнего задания
        hd.user_id, -- Учник, который делал домашнее задание
        l.course_id -- Курс, на котором задали домашнее задание
    FROM 
        homework_done hd
    LEFT JOIN
        homework_lessons hl USING(homework_id)
    LEFT JOIN
        lessons l ON l.id = hl.lesson_id
)
SELECT DISTINCT
    ic.*,   -- Вывод CTE info_courses
    iu.*,   -- Вывод CTE info_users
    cu.active,   -- Поле с информацией об отчисление с курса
    cu.created_at::DATE AS date_join_user,    -- Поле с информацей о присоединение ученика на курс
    CASE    -- Вычисляем интервал между сегоднящней датой и датой начала курса
        WHEN AGE(CURRENT_DATE, cu.created_at::DATE) > INTERVAL '1 month'    -- Если прошло больше месяца
        THEN EXTRACT(month FROM AGE(CURRENT_DATE, cu.created_at::DATE))     -- То возвращаем количество полных месяцев
        ELSE 0      -- Если меньше, то возращаем 0
    END AS quantity_full_months,
    -- Количество выполненных домашних заданий
    COUNT(h.id) OVER(PARTITION BY ic.id_course, iu.id_user) AS count_done_homework
FROM course_users cu
-- Объединение трёх CTE в одну таблицу
LEFT JOIN
    info_courses ic ON cu.course_id = ic.id_course
LEFT JOIN
    info_users iu ON cu.user_id = iu.id_user
LEFT JOIN 
    info_homework h ON h.user_id = iu.id_user AND h.course_id = ic.id_course