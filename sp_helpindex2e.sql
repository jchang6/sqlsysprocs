-- SQL Scripts , sp_spaceused2 , sp_helpindex2 , sp_partitions , sp_updatestats2 , sp_vas , sp_plancache_flush 
-- updates 2018-03-06 
-- 2018-04-08 sys.stats is_incremental 
-- 2018-10-25 list of tables as input 
--  uses function introduced in SQL Server 2016
-- 2019-01-01 calculations with data from dm_db_stats_histogram
-- 2019-04-02 gets current max value for index lead columns
USE master -- skip this for Azure 
GO 
/*IF EXISTS ( 
  SELECT * FROM sys.procedures WHERE object_id = OBJECT_ID('sp_helpindex3') 
) DROP procedure dbo.sp_helpindex3
DROP procedure dbo.sp_helpindex2t
SELECT * FROM sys.data_spaces
SELECT * FROM sys.filegroups
SELECT * FROM sys.database_files
SELECT * FROM sys.tables
exec sp_spaceused2
DECLARE @ds sysname = 'TP_Scheme' --
IF isnumeric(@ds) = 1 
	SELECT dsid = data_space_id FROM sys.data_spaces WHERE data_space_id = @ds
ELSE IF @ds IS NOT NULL
	SELECT dsid = data_space_id FROM sys.data_spaces WHERE name = @ds
DECLARE @objname nvarchar(4000) = 'DynamicColsValues_TP%', @sch sysname = 'tpc', @not sysname = 'task'
	SELECT o.schema_id, o.object_id, o.type, o.name, 0
	FROM sys.objects o JOIN sys.schemas s ON s.schema_id = o.schema_id
	WHERE o.name LIKE @objname AND o.type IN ('U', 'V') AND (@sch IS NULL OR s.name = @sch)
	AND (@not IS NULL OR CHARINDEX(@not,o.name,1) = 0)
*/
GO 
CREATE OR 
ALTER PROCEDURE dbo.sp_helpindex2 
 @objname nvarchar(4000) = NULL
, @ds sysname = NULL --  can be dataspace _id or dataspace name, either filegroup or partition scheme
, @sch sysname = NULL
, @not sysname = NULL
, @stats int = 0
AS 
SET NOCOUNT ON
DECLARE @objct int
DECLARE @ver varchar(500) = @@VERSION, @ci int , @ver2 int
SELECT @ci = CHARINDEX('20', @ver, 1), @ver2 = TRY_CONVERT(int, SUBSTRING(@ver,@ci, 4))
--SELECT @ver2

DECLARE @obj TABLE(schema_id int, object_id int primary key, [type] char(2), [Object] sysname, pt int, pp int, uPgC bigint, rct bigint, create_date datetime)
INSERT @obj
exec dbo.sp_parseobjects @objname, @ds, @sch, @not
SELECT @objct = @@ROWCOUNT

if @objct < 1 begin 
 raiserror(15009,-1,-1) return (1) 
end 

-- table level sys.dm_db_partition_stats 
 UPDATE o SET uPgC = d.uPgC --, pt = d.pt, pp = d.pp, rct = d.rct 
 FROM @obj o OUTER APPLY ( 
	SELECT COUNT(*) pt, SUM(CASE d.row_count WHEN 0 THEN 0 ELSE 1 END) pp , SUM(d.used_page_count) uPgC, SUM(d.row_count) rct
	FROM sys.dm_db_partition_stats d WHERE d.object_id = o.object_id AND d.index_id IN (0,1) 
) d -- SELECT * FROM @obj

-- index level sys.dm_db_partition_stats 
DECLARE @b TABLE(object_id int, index_id int, part int, pop int, reserved bigint, used bigint, in_row_data bigint
, in_row_used bigint, lob_used bigint, overflow bigint, row_count bigint, notcompressed int, compressed int
, PRIMARY KEY (object_id, index_id) )
INSERT @b SELECT d.object_id, d.index_id, part = COUNT(*) , pop = SUM(CASE row_count WHEN 0 THEN 0 ELSE 1 END) 
 , reserved = 8*SUM(d.reserved_page_count) , used = 8*SUM(d.used_page_count) 
 , in_row_data = 8*SUM(d.in_row_data_page_count) 
 , in_row_used = 8*SUM(d.in_row_used_page_count) -- , in_row_rese = 8*SUM(d.in_row_reserved_page_count) 
 , lob_used = 8*SUM(d.lob_used_page_count) -- , lob_rese = 8*SUM(d.lob_reserved_page_count) 
 , overflow = 8*SUM(d.row_overflow_used_page_count) -- , overfl_r = 8*SUM(d.row_overflow_reserved_page_count) 
 , row_count = SUM(row_count) 
 , notcompressed = SUM(CASE data_compression WHEN 0 THEN 1 ELSE 0 END) 
 , compressed = SUM(CASE data_compression WHEN 0 THEN 0 ELSE 1 END) -- change to 0 for SQL Server 2005 
 FROM @obj o JOIN sys.dm_db_partition_stats d WITH(NOLOCK) ON d.object_id = o.object_id 
 JOIN sys.partitions r WITH(NOLOCK) ON r.partition_id = d.partition_id 
 GROUP BY d.object_id, d.index_id 

DECLARE @ixs TABLE (object_id int, index_id int, ctyp int, [Schema] sysname, [Object] sysname, [Index] sysname, LeadCol sysname
, MaxCol sql_variant, filter_definition nvarchar(3000), PRIMARY KEY (object_id,index_id))
INSERT @ixs
SELECT o.object_id, i.index_id, c.system_type_id, s.name [Schema], o.[Object], i.name [Index], c.name [LeadCol], NULL MaxCol, i.filter_definition
--, CONCAT(N'SELECT @MaxO = MAX(',c.name,N') FROM [', s.name,N'].[',o.[Object],N'] WITH(INDEX([',i.name,N']))')
FROM @obj o JOIN sys.schemas s ON s.schema_id = o.schema_id
JOIN sys.indexes i ON i.object_id = o.object_id 
JOIN sys.index_columns j ON j.object_id = i.object_id AND j.index_id = i.index_id AND j.key_ordinal = 1
JOIN sys.columns c ON c.object_id = j.object_id AND c.column_id = j.column_id
WHERE i.is_disabled = 0 AND i.is_hypothetical = 0 AND i.filter_definition IS NULL

IF @stats > 1
BEGIN
DECLARE @oid int, @ind int, @SQL nvarchar(1000), @P nvarchar(250) = N'@MaxO sql_variant OUTPUT', @Max sql_variant
DECLARE c CURSOR FOR 
 SELECT object_id, index_id, CONCAT(N'SELECT @MaxO = MAX(',QUOTENAME(LeadCol),N') FROM ', QUOTENAME([Schema]),N'.',QUOTENAME([Object]),N' --WITH(INDEX([',[Index],N']))'
 , CASE WHEN filter_definition IS NOT NULL THEN ' WHERE ' + filter_definition ELSE '' END ) AS SQL1
 FROM @ixs WHERE ctyp <> 104
OPEN c
FETCH NEXT FROM c INTO @oid, @ind, @SQL
WHILE (@@FETCH_STATUS = 0) BEGIN
-- SELECT @oid, @ind, @SQL
 exec sp_executesql @SQL, @P, @MaxO = @Max OUTPUT
 UPDATE @ixs SET MaxCol = @Max WHERE object_id = @oid AND index_id = @ind
 FETCH NEXT FROM c INTO @oid, @ind, @SQL
END
CLOSE c 
DEALLOCATE c
END

DECLARE @j  TABLE(object_id int, index_id int, key_ordinal int, column_id int, partition_ordinal int, is_descending_key bit)
DECLARE @ik TABLE(object_id int, index_id int, Keys varchar(4000), ct int)
DECLARE @ii TABLE(object_id int, index_id int, Incl varchar(4000), ct int)

INSERT @j(object_id, index_id, key_ordinal, column_id, partition_ordinal, is_descending_key)
SELECT o.object_id, j.index_id, j.key_ordinal, j.column_id, j.partition_ordinal, j.is_descending_key
FROM @obj o JOIN sys.index_columns j ON j.object_id = o.object_id AND j.index_id = 1 WHERE o.object_id > 1000

 -- for version 2016 and earlier -- prior to STRING_AGG
 ;WITH j1 AS ( 
  SELECT j.object_id, j.index_id, j.key_ordinal, c.column_id, c.name, partition_ordinal, is_descending_key 
  FROM @j j INNER JOIN sys.columns c ON c.object_id = j.object_id AND c.column_id = j.column_id WHERE j.key_ordinal > 0
) 
INSERT @ik (object_id, index_id, Keys, ct)
SELECT c.object_id , c.index_id
, ISNULL(STUFF(( SELECT CONCAT(', ', name, CASE is_descending_key WHEN 1 THEN '-' ELSE '' END, CASE partition_ordinal WHEN 1 THEN '*' ELSE '' END) 
  FROM j1 WHERE j1.object_id = c.object_id AND j1.index_id = 1 AND j1.key_ordinal > 0 
  ORDER BY j1.key_ordinal FOR XML PATH(''), TYPE, ROOT).value( 'root[1]', 'nvarchar(max)'),1, 2,'') ,'') as Keys, c.ct
FROM (SELECT object_id, index_id, COUNT(*) ct FROM @j GROUP BY object_id, index_id ) c

;WITH j1 AS ( 
  SELECT j.object_id, j.index_id, j.key_ordinal, c.column_id, c.name, partition_ordinal, is_descending_key 
  FROM @j j INNER JOIN sys.columns c ON c.object_id = j.object_id AND c.column_id = j.column_id WHERE j.key_ordinal = 0
) 
INSERT @ii (object_id, index_id, Incl, ct)
SELECT c.object_id , c.index_id
, ISNULL(STUFF(( SELECT CONCAT(', ', name, CASE partition_ordinal WHEN 1 THEN '*' ELSE '' END) 
  FROM j1 WHERE j1.key_ordinal = 0  --j1.object_id = c.object_id AND j1.index_id = 1 AND 
  ORDER BY j1.column_id FOR XML PATH(''), TYPE, ROOT).value( 'root[1]', 'nvarchar(max)'),1, 2,'') ,'') as Incl, c.ct
FROM (SELECT object_id, index_id, COUNT(*) ct FROM @j WHERE key_ordinal = 0 GROUP BY object_id, index_id ) c 

-- SQL Server version 2017 and later
/*	INSERT @ik (object_id, index_id, Keys, ct)
	SELECT j.object_id, j.index_id, STRING_AGG(CONCAT(c.name,CASE is_descending_key WHEN 1 THEN '-' ELSE '' END 
	, CASE partition_ordinal WHEN 1 THEN '*' ELSE '' END) ,',') WITHIN GROUP(ORDER BY j.key_ordinal) Keys, COUNT(*) ct
	FROM @j j JOIN sys.columns c ON c.object_id = j.object_id AND c.column_id = j.column_id 
	WHERE j.key_ordinal > 0
	GROUP BY j.object_id, j.index_id

	INSERT @ii (object_id, index_id, Incl, ct)
	SELECT j.object_id, j.index_id, STRING_AGG(CONCAT(c.name, CASE partition_ordinal WHEN 1 THEN '*' ELSE '' END)
	,',') WITHIN GROUP(ORDER BY j.column_id) Incl, COUNT(*) ct
	FROM @j j JOIN sys.columns c ON c.object_id = j.object_id AND c.column_id = j.column_id 
	WHERE j.key_ordinal = 0
	GROUP BY j.object_id, j.index_id
*/
SELECT o.[Object], ISNULL(i.name, '')[index] , k.Keys, CASE WHEN i.is_disabled = 1 THEN NULL ELSE ISNULL(l.Incl,'') END Incl, i.index_id 
, CASE WHEN i.is_primary_key = 1 THEN 'PK'  WHEN i.is_unique_constraint= 1 THEN 'UC' WHEN i.is_unique = 1 THEN 'U'  WHEN i.type = 0 THEN 'heap' 
 WHEN i.type = 3 THEN 'X'  WHEN i.type = 4 THEN 'S' ELSE CONVERT(char, i.type) END typ , i.data_space_id dsi 
, b.row_count , b.used
, b.in_row_data in_row , b.overflow ovf , b.lob_used lob 
, b.reserved - b.in_row_data - b.overflow - b.lob_used unu 
, 'ABR' = CASE row_count WHEN 0 THEN 0 ELSE CONVERT(numeric(18,2), 1024.*used/row_count) END 
, 'ABL' = CASE row_count WHEN 0 THEN 0 ELSE CONVERT(numeric(18,2), 1024.*lob_used/row_count) END 
, in_row_used - in_row_data u_d
, y.user_seeks, y.user_scans u_scan, y.user_lookups u_look, y.user_updates u_upd 
, b.notcompressed ncm , b.compressed cmp , b.pop, b.part 
, rw_delta = b.row_count - s.rows, s.rows_sampled --, s.unfiltered_rows 
, s.modification_counter mod_ctr, s.steps , CONVERT(varchar, s.last_updated,120) updated 
, i.is_disabled dis, i.is_hypothetical hyp, ISNULL(i.filter_definition, '') filt 
, t.no_recompute no_rcp , t.is_incremental incr, INDEXPROPERTY(i.object_id,i.name,'IndexDepth') depth
, h.steps + h.DRR AS DistRw
, CONVERT(real, CASE h.steps WHEN 0 THEN 0 ELSE 1.E0/(h.steps + h.DRR) END) Den1
, CONVERT(real,CASE o.uPgC WHEN 0 THEN 0 ELSE CASE h.steps WHEN 0 THEN 0 ELSE 1.0*(h.RgRw + h.EqRw)/((h.steps + h.DRR)*o.uPgC) END END) RwPg
, CASE WHEN s.rows - h.RgRw - h.EqRw < 1 THEN 0 ELSE s.rows - h.RgRw - h.EqRw END [null]
, h.blk0, h.heq, h.hrr, CONVERT(bigint, h.lrw) leq -- , CASE WHEN h.lrw > 10000 THEN CONVERT(bigint, h.lrw) ELSE h.lrw END leq
, h.lbd LowerBd, h.ubd UpperBd
, x.MaxCol 
, CONVERT(bigint,h.RgRw + h.EqRw) rwh, o.uPgC
--, CASE WHEN h.RgRw + h.EqRw > 100000 THEN CONVERT(bigint,h.RgRw + h.EqRw) ELSE h.RgRw + h.EqRw END  AS rwh 
FROM @obj o JOIN sys.indexes i ON i.object_id = o.object_id 
LEFT JOIN @ik k ON k.object_id = i.object_id AND k.index_id = i.index_id 
LEFT JOIN @ii l ON l.object_id = i.object_id AND l.index_id = i.index_id
LEFT JOIN sys.stats t ON t.object_id = o.object_id AND t.stats_id = i.index_id 
LEFT JOIN @b b ON b.object_id = i.object_id AND b.index_id = i.index_id 
LEFT JOIN sys.dm_db_index_usage_stats y ON y.object_id = i.object_id AND y.index_id = i.index_id AND y.database_id = DB_ID() 
OUTER APPLY sys.dm_db_stats_properties( i.object_id, i.index_id) s 
OUTER APPLY ( SELECT COUNT(*) steps, MIN(h.range_high_key) lbd, MAX(h.range_high_key) ubd /* range_high_key is sql_variant */
, SUM(h.range_rows) RgRw, SUM(h.equal_rows) EqRw, SUM(h.distinct_range_rows) DRR
, SUM(CASE WHEN h.range_high_key IN ('0','') THEN h.equal_rows ELSE 0 END) blk0
, SUM(CASE WHEN 3*h.equal_rows > x.uPgC THEN 1 ELSE 0 END) heq 
, SUM(CASE WHEN 3*h.equal_rows < x.uPgC THEN equal_rows ELSE 0 END + CASE WHEN 3*h.range_rows < x.uPgC*h.distinct_range_rows THEN h.distinct_range_rows ELSE 0 END) lrw
, SUM(CASE h.distinct_range_rows WHEN 0 THEN 0 ELSE CASE WHEN 3*h.range_rows > x.uPgC*h.distinct_range_rows THEN 1 ELSE 0 END END) hrr 
, SUM(CASE h.distinct_range_rows WHEN 0 THEN 0 ELSE CASE WHEN 3*h.range_rows > x.uPgC*h.distinct_range_rows THEN h.distinct_range_rows ELSE 0 END END) hdr 
FROM sys.dm_db_stats_histogram (i.object_id, i.index_id) h JOIN @obj x ON x.object_id = o.object_id ) h
LEFT JOIN @ixs x ON x.object_id = i.object_id AND x.index_id = i.index_id
ORDER BY o.[Object], i.is_disabled, i.has_filter , i.index_id
GO 
-- Then mark the procedure as a system procedure. 
EXEC sys.sp_MS_marksystemobject 'sp_helpindex2' -- skip this for Azure 
GO 
--SELECT name, is_ms_shipped FROM sys.objects WHERE name LIKE 'sp_helpindex%' 
--SELECT name, is_ms_shipped, create_date, modify_date FROM sys.objects WHERE schema_id = 1 AND type = 'P'  AND name LIKE 'sp_helpindex%' 
SELECT * FROM master.sys.objects WHERE is_ms_shipped = 1 AND type = 'P' AND name NOT LIKE 'sp_MS%'
GO
/*
-- DROP PROCEDURE sp_helpindex2
USE Test

exec dbo.sp_helpindex2 @objname = 'A'
exec dbo.sp_helpindex2 @objname = 'A%'
exec dbo.sp_helpindex2 @objname = 'AH,AI'
exec dbo.sp_helpindex2 @ds = 'psDtL'
exec dbo.sp_helpindex2 @ds = '-2'
*/
