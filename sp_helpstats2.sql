-- SQL Scripts , sp_spaceused2 , sp_helpindex2 , sp_partitions , sp_updatestats2 , sp_vas , sp_plancache_flush 
-- updates 2018-11-06 
-- 2018-04-08 sys.stats is_incremental 
-- 2018-10-25 list of tables as input 
-- 2018-12-06  dm_db_stats_histogram
USE master -- skip this for Azure 
GO 
/*IF EXISTS ( 
  SELECT * FROM sys.procedures WHERE object_id = OBJECT_ID('sp_helpstats2') 
) DROP procedure dbo.sp_helpstats2 */
GO 
CREATE OR ALTER PROCEDURE dbo.sp_helpstats2 
 @objname nvarchar(4000) = NULL
, @ds sysname = NULL --  can be dataspace _id or dataspace name, either filegroup or partition scheme
, @sch sysname = NULL
, @not sysname = NULL
, @col int = NULL
AS 
DECLARE @objct int

-- table/view list -- for use with SQL Server 2016 and later, or substitute STRING_SPLIT function 
DECLARE @obj TABLE(schema_id int, object_id int primary key, [type] char(2), [Object] sysname, pt int, pp int, uPgC bigint, rct bigint, create_date datetime)
INSERT @obj
exec dbo.sp_parseobjects @objname, @ds, @sch, @not
SELECT @objct = @@ROWCOUNT 

if @objct < 1 begin 
 raiserror(15009, -1,-1) --, @objname , @dbname ) 
 return ( 1 ) 
end 

 UPDATE o  SET pt = d.pt, pp = d.pp, uPgC = d.uPgC, rct = d.rct 
 FROM @obj o OUTER APPLY ( 
	SELECT COUNT(*) pt, SUM(CASE d.row_count WHEN 0 THEN 0 ELSE 1 END) pp , SUM(d.used_page_count) uPgC, SUM(d.row_count) rct
	FROM sys.dm_db_partition_stats d WHERE d.object_id = o.object_id AND d.index_id IN (0,1) ) d -- SELECT * FROM @obj
/*
 SELECT j.object_id, j.stats_id, STRING_AGG(c.name+CASE partition_ordinal WHEN 1 THEN '*' ELSE '' END,',') WITHIN GROUP(ORDER BY k.key_ordinal, stats_column_id) Cols
 FROM sys.stats_columns j INNER JOIN sys.columns c ON c.object_id = j.object_id AND c.column_id = j.column_id 
 AND (@col IS NULL OR (j.column_id = @col AND j.stats_column_id=1))
 LEFT JOIN sys.index_columns k ON k.object_id = j.object_id AND k.index_id = j.stats_id AND k.index_column_id = j.stats_column_id
 GROUP BY  j.object_id, j.stats_id
*/
DECLARE @j TABLE (object_id int, stats_id int, stats_column_id int, column_id int, key_ordinal int, partition_ordinal int)
INSERT @j(object_id, stats_id, stats_column_id, column_id, key_ordinal, partition_ordinal)
SELECT o.object_id, s.stats_id, j.stats_column_id, j.column_id, k.key_ordinal, k.partition_ordinal
FROM @obj o JOIN sys.stats s ON s.object_id = o.object_id
JOIN sys.stats_columns j ON j.object_id = s.object_id AND j.stats_id = s.stats_id 
LEFT JOIN sys.index_columns k ON k.object_id = j.object_id AND k.index_id = j.stats_id AND k.index_column_id = j.stats_column_id
WHERE o.object_id > 1000

DECLARE @sc TABLE(object_id int, stats_id int, Cols varchar(4000))
 -- for version 2016 and earlier -- prior to STRING_AGG
;WITH j1 AS ( 
  SELECT j.object_id, j.stats_id, j.key_ordinal, c.column_id, c.name, partition_ordinal
  FROM @j j INNER JOIN sys.columns c ON c.object_id = j.object_id AND c.column_id = j.column_id 
) 
INSERT @sc(object_id, stats_id, Cols)
SELECT c.object_id , c.stats_id
, ISNULL(STUFF(( SELECT CONCAT(', ', name, CASE partition_ordinal WHEN 1 THEN '*' ELSE '' END) 
  FROM j1 WHERE j1.object_id = c.object_id AND j1.stats_id = c.stats_id
  ORDER BY j1.key_ordinal FOR XML PATH(''), TYPE, ROOT).value( 'root[1]', 'nvarchar(max)'),1, 2,'') ,'') as Cols --  , c.ct
FROM (SELECT object_id, stats_id, COUNT(*) ct FROM @j GROUP BY object_id, stats_id ) c 
/*
-- SQL Server version 2017 and later
INSERT @sc(object_id, stats_id, Cols)
 SELECT j.object_id, j.stats_id, STRING_AGG(c.name+CASE partition_ordinal WHEN 1 THEN '*' ELSE '' END,',') WITHIN GROUP(ORDER BY j.key_ordinal, stats_column_id) Cols
 FROM @j j INNER JOIN sys.columns c ON c.object_id = j.object_id AND c.column_id = j.column_id 
 AND (@col IS NULL OR (j.column_id = @col AND j.stats_column_id=1))
-- LEFT JOIN sys.index_columns k ON k.object_id = j.object_id AND k.index_id = j.stats_id AND k.index_column_id = j.stats_column_id
 GROUP BY  j.object_id, j.stats_id
*/
--;WITH j AS (  ) 
SELECT t.stats_id, ISNULL(t.name, '') [stat], j.Cols as Keys , s.rows srows, s.rows_sampled --, s.unfiltered_rows 
, s.modification_counter mod_ctr, s.steps , CONVERT(varchar, s.last_updated,120) updated 
, t.auto_created autoc, t.user_created usrc, t.no_recompute no_rcp , t.has_filter filt, t.is_temporary tmp, t.is_incremental incr
, '' pers -- , s.persisted_sample_percent pers
, h.steps + h.DRR AS DistRw
, CONVERT(real, CASE h.steps WHEN 0 THEN 0 ELSE 1.E0/(h.steps + h.DRR) END) Den1
, CONVERT(real,CASE a.uPgC WHEN 0 THEN 0 ELSE CASE h.steps WHEN 0 THEN 0 ELSE 1.0*(h.RgRw + h.EqRw)/((h.steps + h.DRR)*a.uPgC) END END) RwPg
, h.lbd LowerBd, h.ubd UpperBd, t.filter_definition
, CASE WHEN h.RgRw + h.EqRw > 100000 THEN CONVERT(bigint,h.RgRw + h.EqRw) ELSE h.RgRw + h.EqRw END  AS rwh
--, h.RgRw + h.EqRw AS rwh
FROM @obj a JOIN sys.objects o ON o.object_id = a.object_id
LEFT JOIN sys.stats t ON t.object_id = o.object_id 
OUTER APPLY sys.dm_db_stats_properties( t.object_id, t.stats_id) s 
OUTER APPLY (
 SELECT COUNT(*) steps
 , MIN(h.range_high_key) lbd, MAX(h.range_high_key) ubd /* range_high_key is sql_variant */
 , SUM(h.range_rows) RgRw, SUM(h.equal_rows) EqRw, SUM(h.distinct_range_rows) DRR
 FROM sys.dm_db_stats_histogram (t.object_id, t.stats_id) h
) h
LEFT JOIN @sc j ON j.object_id = t.object_id AND j.stats_id = t.stats_id
WHERE @col IS NULL OR j.stats_id IS NOT NULL
ORDER BY o.name, t.auto_created, t.stats_id
GO 
-- Then mark the procedure as a system procedure. 
IF NOT EXISTS(SELECT * FROM master.sys.objects WHERE is_ms_shipped = 1 AND type = 'P' AND name = 'sp_helpstats2'
) 
EXEC sys.sp_MS_marksystemobject 'sp_helpstats2' -- skip this for Azure 
GO 
--SELECT name, is_ms_shipped FROM master.sys.objects WHERE name LIKE 'sp_helpstats2%' 
SELECT * FROM master.sys.objects WHERE is_ms_shipped = 1 AND type = 'P' AND name NOT LIKE 'sp_MS%'
GO 
/*
USE Test

exec sp_helpstats2 'dbo.T0'
exec sp_helpstats2 'T0'
exec sp_helpstats2 'A'
exec sp_helpstats2 'A%'
exec sp_helpstats2 'A,A1'

sp_helpindex2 'LINEITEM,PART'

SELECT * FROM sys.dm_db_partition_stats d WHERE d.object_id = OBJECT_ID('ORDERS') 
SELECT * FROM sys.dm_db_partition_stats d WHERE d.object_id = OBJECT_ID('LINEITEM') 
*/
/*
*/


