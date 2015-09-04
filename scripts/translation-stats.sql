# get all the missing changed stats for all locales and groups
SELECT (mx.total_keys - lcs.total) missing, lcs.changed, lcs.locale, lcs.`group`
FROM
    (SELECT sum(total) total, sum(changed) changed, `group`, locale
     FROM
         (SELECT count(value) total, sum(status) changed, `group`, locale
          FROM ltm_translations lt
          GROUP BY `group`, locale
          UNION ALL
          SELECT DISTINCT 0, 0, `group`, locale
          FROM (SELECT DISTINCT locale
                FROM ltm_translations) lc
              CROSS JOIN (SELECT DISTINCT `group`
                          FROM ltm_translations) lg) a
     GROUP BY `group`, locale) lcs
    JOIN (SELECT count(DISTINCT `key`) total_keys, `group`
          FROM ltm_translations
          GROUP BY `group`) mx
        ON lcs.`group` = mx.`group`
WHERE lcs.total < mx.total_keys OR lcs.changed > 0
;


# return # of keys per group
SELECT count(DISTINCT `key`) max_keys, `group`
FROM ltm_translations
GROUP BY `group`
;

# returns # of translations and changes per group, locale
SELECT sum(total) total, sum(changed) changed, `group`, locale
FROM
    (SELECT count(value) total, sum(status) changed, `group`, locale
     FROM ltm_translations lt
     GROUP BY `group`, locale
     UNION ALL
     SELECT DISTINCT 0, 0, `group`, locale
     FROM (SELECT DISTINCT locale
           FROM ltm_translations) lc CROSS JOIN (SELECT DISTINCT `group`
                                                 FROM ltm_translations) lg) a
GROUP BY `group`, locale
;


# returns all the missing locale, group, key combinations, that need to be inserted, they are missing from the table
SELECT *
FROM ((SELECT DISTINCT locale
       FROM ltm_translations) lc
    CROSS JOIN
    (SELECT DISTINCT `group`, `key`
     FROM ltm_translations) lg)
WHERE NOT exists(SELECT *
                 FROM ltm_translations lt
                 WHERE lt.locale = lc.locale AND lt.`group` = lg.`group` AND lt.`key` = lg.`key`)
;

# returns all the missing locale, group, key combinations, that need to be translated, ie. value is null or missing
SELECT *
FROM ((SELECT DISTINCT locale
       FROM ltm_translations) lc
    CROSS JOIN
    (SELECT DISTINCT `group`, `key`
     FROM ltm_translations) lg)
WHERE NOT exists(SELECT *
                 FROM ltm_translations lt
                 WHERE lt.locale = lc.locale AND lt.`group` = lg.`group` AND lt.`key` = lg.`key` AND lt.value IS NOT NULL)
;


# pivot locales
SELECT lt.`group`, lt.`key`, group_concat(CASE lt.locale WHEN 'en' THEN VALUE ELSE NULL END) en, group_concat(CASE lt.locale WHEN 'ru' THEN VALUE ELSE NULL END) ru
FROM (SELECT value, `group`, `key`, locale
      FROM ltm_translations
      UNION ALL
      SELECT NULL, `group`, `key`, locale
      FROM ((SELECT DISTINCT locale
             FROM ltm_translations) lc
          CROSS JOIN (SELECT DISTINCT `group`, `key`
                      FROM ltm_translations) lg)
     ) lt
GROUP BY `group`, `key`
;

# this query gives a list of mismatched translations
# 3
SELECT DISTINCT lt.`group`, lt.id, ft.*
FROM ltm_translations lt
    JOIN
    (SELECT DISTINCT mt.`key`, mt.ru ru, mt.en en
     FROM (SELECT lt.`group`, lt.`key`, group_concat(CASE lt.locale WHEN 'en' THEN VALUE ELSE NULL END) en, group_concat(CASE lt.locale WHEN 'ru' THEN VALUE ELSE NULL END) ru
           FROM (SELECT value, `group`, `key`, locale FROM ltm_translations
                 UNION ALL
                 SELECT NULL, `group`, `key`, locale FROM ((SELECT DISTINCT locale FROM ltm_translations) lc
                     CROSS JOIN (SELECT DISTINCT `group`, `key` FROM ltm_translations) lg)
                ) lt
           GROUP BY `group`, `key`) mt
         JOIN (SELECT lt.`group`, lt.`key`, group_concat(CASE lt.locale WHEN 'en' THEN VALUE ELSE NULL END) en, group_concat(CASE lt.locale WHEN 'ru' THEN VALUE ELSE NULL END) ru
               FROM (SELECT value, `group`, `key`, locale FROM ltm_translations
                     UNION ALL
                     SELECT NULL, `group`, `key`, locale FROM ((SELECT DISTINCT locale FROM ltm_translations) lc
                         CROSS JOIN (SELECT DISTINCT `group`, `key` FROM ltm_translations) lg)
                    ) lt
               GROUP BY `group`, `key`) ht ON mt.`key` = ht.`key`
     WHERE (mt.ru not like binary ht.ru AND mt.en like binary ht.en) or (mt.ru like binary ht.ru AND mt.en not like binary ht.en)
    ) ft
        ON (lt.locale = 'ru' AND lt.value LIKE BINARY ft.ru) AND lt.`key` = ft.key
ORDER BY `key`, `group`
;

# TODO: implement pivot and have it maintained, either with triggers or in php
# same as above but with temp tables, no benefit, however with a pivot table it is 3x faster but pivot needs to be maintained
# and updated. However if for every key, group change a single row is deleted and inserted with updates then
# the impact is spread to the changes while the benefits are accrued for every page refresh.

# 2
# DROP TABLE IF EXISTS ltm_trans_pivot;
# CREATE TABLE ltm_trans_pivot AS
TRUNCATE ltm_trans_pivot;
INSERT INTO ltm_trans_pivot
SELECT lt.`group`, lt.`key`, group_concat(CASE lt.locale WHEN 'en' THEN VALUE ELSE NULL END) en, group_concat(CASE lt.locale WHEN 'ru' THEN VALUE ELSE NULL END) ru
FROM (SELECT value, `group`, `key`, locale FROM ltm_translations
      UNION ALL
      SELECT NULL, `group`, `key`, locale FROM ((SELECT DISTINCT locale FROM ltm_translations) lc
          CROSS JOIN (SELECT DISTINCT `group`, `key` FROM ltm_translations) lg)
     ) lt
GROUP BY `group`, `key`;

# DROP TEMPORARY TABLE IF EXISTS ltm_trans_pivot2;
# CREATE TEMPORARY TABLE ltm_trans_pivot2 AS
#     SELECT * FROM ltm_trans_pivot;

# 3a
SELECT DISTINCT lt.`group`, lt.id, ft.*
FROM ltm_translations lt
    JOIN
    (SELECT DISTINCT mt.`key`, mt.ru ru, mt.en en
     FROM ltm_trans_pivot mt
         JOIN ltm_trans_pivot ht ON mt.`key` = ht.`key`
     WHERE (mt.ru not like binary ht.ru AND mt.en like binary ht.en) or (mt.ru like binary ht.ru AND mt.en not like binary ht.en)
    ) ft
        ON (lt.locale = 'ru' AND lt.value LIKE BINARY ft.ru) AND lt.`key` = ft.key
ORDER BY `key`, `group`
;
















# 1
SELECT NULL, `group`, `key`, locale FROM ((SELECT DISTINCT locale FROM ltm_translations) lc
    CROSS JOIN (SELECT DISTINCT `group`, `key` FROM ltm_translations) lg);

DROP TEMPORARY TABLE IF EXISTS ltm_locales;
CREATE TEMPORARY TABLE ltm_locales AS
    SELECT DISTINCT locale FROM ltm_translations;

DROP TEMPORARY TABLE IF EXISTS ltm_groups_keys;
CREATE TEMPORARY TABLE ltm_groups_keys AS
    SELECT DISTINCT `group`, `key` FROM ltm_translations;

# 1a
SELECT NULL, `group`, `key`, locale FROM ltm_locales lc
    CROSS JOIN ltm_groups_keys lg;

#2a
SELECT lt.`group`, lt.`key`, group_concat(CASE lt.locale WHEN 'en' THEN VALUE ELSE NULL END) en, group_concat(CASE lt.locale WHEN 'ru' THEN VALUE ELSE NULL END) ru
FROM (SELECT value, `group`, `key`, locale FROM ltm_translations
      UNION ALL
      SELECT NULL, `group`, `key`, locale FROM ltm_locales lc
          CROSS JOIN ltm_groups_keys lg
     ) lt
GROUP BY `group`, `key`;





























SELECT DISTINCT mt.`key`, BINARY mt.ru ru, BINARY mt.en en
FROM (SELECT lt.`group`, lt.`key`, group_concat(CASE lt.locale WHEN 'en' THEN VALUE ELSE NULL END) en, group_concat(CASE lt.locale WHEN 'ru' THEN VALUE ELSE NULL END) ru
      FROM (SELECT value, `group`, `key`, locale FROM ltm_translations
            UNION ALL
            SELECT NULL, `group`, `key`, locale FROM ((SELECT DISTINCT locale FROM ltm_translations) lc
                CROSS JOIN (SELECT DISTINCT `group`, `key` FROM ltm_translations) lg)
           ) lt
      GROUP BY `group`, `key`) mt
    JOIN (SELECT lt.`group`, lt.`key`, group_concat(CASE lt.locale WHEN 'en' THEN VALUE ELSE NULL END) en, group_concat(CASE lt.locale WHEN 'ru' THEN VALUE ELSE NULL END) ru
          FROM (SELECT value, `group`, `key`, locale FROM ltm_translations
                UNION ALL
                SELECT NULL, `group`, `key`, locale FROM ((SELECT DISTINCT locale FROM ltm_translations) lc
                    CROSS JOIN (SELECT DISTINCT `group`, `key` FROM ltm_translations) lg)
               ) lt
          GROUP BY `group`, `key`) ht ON mt.`key` = ht.`key`
WHERE (mt.ru not like binary ht.ru AND mt.en like binary ht.en) or (mt.ru like binary ht.ru AND mt.en not like binary ht.en)
;


DROP TEMPORARY TABLE IF EXISTS pvt_translations
;

CREATE TEMPORARY TABLE pvt_translations AS
    SELECT lt.`group`, lt.`key`, group_concat(CASE lt.locale WHEN 'en' THEN VALUE ELSE NULL END) en, group_concat(CASE lt.locale WHEN 'ru' THEN VALUE ELSE NULL END) ru
    FROM (SELECT value, `group`, `key`, locale
          FROM ltm_translations
          UNION ALL
          SELECT NULL, `group`, `key`, locale
          FROM ((SELECT DISTINCT locale
                 FROM ltm_translations) lc
              CROSS JOIN (SELECT DISTINCT `group`, `key`
                          FROM ltm_translations) lg)
         ) lt
    GROUP BY `group`, `key`
;

DROP TEMPORARY TABLE IF EXISTS pvt_translations2
;

CREATE TEMPORARY TABLE pvt_translations2 AS SELECT * FROM pvt_translations
;

SELECT DISTINCT mt.`key`, mt.ru, mt.en, ht.ru, ht.en
FROM pvt_translations2 mt
    JOIN pvt_translations ht ON mt.`key` = ht.`key`
WHERE mt.ru IS NULL AND ht.ru IS NOT NULL
      AND mt.en like BINARY ht.en
;

SELECT DISTINCT mt.`key`, mt.ru ru, mt.en en
FROM pvt_translations2 mt
    JOIN pvt_translations ht ON mt.`key` = ht.`key`
WHERE (mt.ru <> ht.ru AND mt.en = ht.en)
ORDER BY `key`
;


SELECT mt.`key`, mt.ru, mt.en, count(mt.ru) ru_appears, count(distinct mt.ru) ru_variations
FROM pvt_translations mt
GROUP BY `key`, mt.ru
HAVING ru_appears > 1
;

SELECT mt.`key`, mt.ru, mt.en, count(mt.en) en_appears, count(distinct mt.en) en_variations
FROM pvt_translations mt
GROUP BY `key`, mt.en
HAVING appears > 1
;