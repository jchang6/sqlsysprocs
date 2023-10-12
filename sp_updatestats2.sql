-- drop obsolete zstats tables in each user database
IF EXISTS ( 
SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.zstats') 
) BEGIN
 IF (SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID('dbo.zstats') ) < 24
 DROP TABLE dbo.zstats 
END
-- ALTER TABLE dbo.zstats ADD  no_recompute bit 
-- UPDATE dbo.zstats SET no_recompute = 0 WHERE no_recompute IS NULL 
GO
-- sp_spaceused , sp_helpindex2 , sp_partitions , sp_updatestats2 
/* -- 
-- updates 2018-04-10 
test version implement incremental statistics 
see: 
Incremental statistics ... by Chris Lound, April 3, 2016 
https://blogs.technet.microsoft.com/dataplatform/2016/04/03/incremental-statistics-how-to-update-statistics-on-100tb-database/ 
this is an alternative to the SQL Server sp_updatestats. 
The internal statistics update is based on all rows from a random sample of pages. 
There are adverse effects for indexes in which the lead key is not unique 
and can be especially severe if compounded. 
sp_updatestats2 does fullscan on indexes excluding identity or single key column unique. 
Note: 
1) it may necessary to drop zstats table from previous version 
2) consider PERSIST_SAMPLE_PERCENT = ON 
for SQL Server 2016 SP1 CU4 and SQL Server 2017 CU1. 
*/ 
USE [master] 
GO 
/*IF EXISTS ( 
 SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.sp_updatestats2') 
) DROP PROCEDURE dbo.sp_updatestats2 */
GO 
CREATE OR ALTER PROCEDURE dbo.sp_updatestats2 
 @modratio bigint = 20 -- low row count tables (<4M)
, @mode int = 0 -- default night time run, fullscan for lead key not unique, except date columns
, @job int = 0
-- @mode = 1 -- only do default sample stats
-- @mode = 2 -- reset everything to default
--, @small int = 0 -- 1: only do small tables < 100,000 rows
-- @resample char(8)='NO', 
as 
 declare @dbsid varbinary(85) 
 , @modratio2 int = 25 * @modratio * @modratio -- used in threshold for tables of > 4M rows
 , @incr1 bit 
 select @dbsid = owner_sid -- , @incr1 = is_auto_create_stats_incremental_on 
 from sys.databases 
 where name = db_name() 
 -- Check the user sysadmin 
 if not is_srvrolemember('sysadmin') = 1 and suser_sid() <> @dbsid 
 begin 
  raiserror(15247,-1,-1) 
  return (1) 
 end 
 -- cannot execute against R/O databases 
 if DATABASEPROPERTYEX(db_name(), 'Updateability')=N'READ_ONLY' 
 begin 
  raiserror(15635,-1, -1,N'sp_updatestats') 
  return (1) 
 end /*
 if upper(@resample)<>'RESAMPLE' and upper(@resample)<>'NO' 
 begin 
  raiserror(14138, -1, -1, @resample) 
  return (1) 
 end */
 -- required so it can update stats on ICC/IVs 
 set ansi_warnings on 
 set ansi_padding on 
 set arithabort on 
 set concat_null_yields_null on 
 set numeric_roundabort off 

-- drop obsolete zstats tables in each user database
IF EXISTS ( 
SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.zstats') 
) BEGIN
 IF (SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID('dbo.zstats') ) < 24
 DROP TABLE dbo.zstats 
END
 
IF NOT EXISTS ( 
SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.zstats') 
) -- DROP TABLE zstats 
BEGIN 
 CREATE TABLE dbo.zstats ( dd smallint, rn int , [object] varchar(255), [index] varchar(255) 
 , row_count bigint, user_updates bigint, has_filter bit , leadcol varchar(255)
 , system_type_id smallint  , is_identity bit, is_rowguidcol bit, is_unique bit 
 , kct tinyint , rw_delta bigint, rows_sampled bigint, unfiltered_rows bigint 
 , mod_ctr bigint, steps int , updated datetime, otype char(2) 
 , no_recompute bit, is_incremental bit, partition_number int, persisted_sample_percent float 
 ) 
 IF NOT EXISTS ( 
 SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.zstats') AND index_id = 1 
 ) 
 CREATE UNIQUE CLUSTERED INDEX CX ON dbo.zstats(dd, rn) 
 WITH (IGNORE_DUP_KEY = ON) -- , DROP_EXISTING = ON) 
END 
-- DECLARE @modratio bigint = 20 , @modratio2 int = 25 * 20 * 20
DECLARE @dd int, @rc1 int 
SELECT @dd = ISNULL(MAX(dd), 0) + 1 FROM dbo.zstats 
--SELECT @dd
DECLARE @b TABLE(object_id int, index_id int, row_count bigint)
INSERT @b SELECT d.object_id , d.index_id , row_count = SUM(d.row_count) 
FROM sys.dm_db_partition_stats d WITH(NOLOCK) GROUP BY d.object_id, d.index_id 
DECLARE @k TABLE(object_id int, index_id int, kct int)
INSERT @k SELECT object_id, index_id, COUNT(*) kct FROM sys.index_columns WITH(NOLOCK) WHERE key_ordinal > 0 GROUP BY object_id, index_id 
DECLARE @y TABLE(object_id int, index_id int, user_updates bigint)
INSERT @y SELECT object_id, index_id, user_updates
FROM sys.dm_db_index_usage_stats y WHERE y.database_id = DB_ID() 

INSERT dbo.zstats 
SELECT @dd dd, ROW_NUMBER() OVER(ORDER BY s.name, o.name, i.index_id) rn 
, QUOTENAME(s.name) + '.' + QUOTENAME(o.name) [object] 
, i.name [index], b.row_count, y.user_updates, i.has_filter 
, c.name [leadcol], c.system_type_id, c.is_identity, c.is_rowguidcol, i.is_unique, k.kct 
, rw_delta = b.row_count - t.rows 
, t.rows_sampled, t.unfiltered_rows, t.modification_counter mod_ctr, t.steps 
, CONVERT(datetime, CONVERT(varchar, t.last_updated, 120)) updated 
, o.type, d.no_recompute, d.is_incremental, 0 partition_number, t.persisted_sample_percent
FROM sys.objects o WITH(NOLOCK) 
JOIN sys.schemas s WITH(NOLOCK) ON s.schema_id = o.schema_id 
JOIN sys.indexes i WITH(NOLOCK) ON i.object_id = o.object_id 
LEFT JOIN sys.stats d WITH(NOLOCK) ON d.object_id = i.object_id AND d.stats_id = i.index_id 
JOIN sys.index_columns j WITH(NOLOCK) ON j.object_id = i.object_id AND j. index_id = i.index_id AND j.key_ordinal = 1 
JOIN sys.columns c WITH(NOLOCK) ON c.object_id = i.object_id AND c.column_id = j.column_id AND j.key_ordinal = 1 
JOIN @b b ON b.object_id = i.object_id AND b.index_id = i.index_id 
JOIN @k k ON k.object_id = i.object_id AND k.index_id = i.index_id 
LEFT JOIN @y y ON y.object_id = i.object_id AND y.index_id = i.index_id -- AND y.database_id = DB_ID() 
OUTER APPLY sys.dm_db_stats_properties( i.object_id, i.index_id) t 
WHERE o.type IN ('U', 'V') AND i.index_id > 0 AND i.type <= 2 AND i.is_disabled = 0 
AND d.is_incremental = 0 AND b.row_count > 0 AND s.name <> 'cdc' 
AND (
	( @modratio*t.modification_counter > t.rows )			-- the old statistics update 
 OR ( t.modification_counter*t.modification_counter > @modratio2*t.rows ) -- high row count criterea (>4M rows?)
 OR ( 2* t.rows_sampled < b.row_count AND ( k.kct > 1 OR is_unique = 0) AND is_identity = 0 ) 
 OR ( is_unique = 1 AND k.kct = 1 AND t.modification_counter > 0 ) -- lead column unique, any mod rows
 OR ( c.system_type_id IN (40,42,58,61) AND t.modification_counter > 0 ) 
 -- any change in indexes with lead col of type: date, datetime2, smalldatetime, datetime
 OR ( c.name = 'PayrollPeriodEndDates' AND t.modification_counter > 0 ) 
 -- any change in indexes with lead col name: PayrollPeriodEndDates
 OR ( b.row_count> 0 AND t.rows_sampled IS NULL )			-- > 0 rows, no stats
 OR ( b.row_count> 0 AND @mode = 2 )						-- resets everything to default
 )
-- AND (@small = 0 OR b.row_count < 100000) 
SELECT @rc1 = @@ROWCOUNT 

-- Work in progress: Incremental Stats code 
DECLARE @a TABLE ( rn int, [object] varchar(255), [index] varchar(255), [object_id] int, index_id int 
 , user_updates bigint, has_filter bit , leadcol varchar(255), system_type_id smallint 
 , is_identity bit, is_rowguidcol bit, is_unique bit , kct tinyint 
 , [rows] bigint, rows_sampled bigint, unfiltered_rows bigint , mod_ctr bigint, steps int 
 , updated datetime, otype char(2) , no_recompute bit, is_incremental bit, partition_number int 
) 
INSERT @a 
SELECT ROW_NUMBER() OVER(ORDER BY s.name, o.name, i.index_id, t.partition_number ) rn 
, QUOTENAME(s.name) + '.' + QUOTENAME(o.name) [object], i.name [index] , i.object_id, i.index_id 
, y.user_updates, i.has_filter , c.name [leadcol], c.system_type_id, c.is_identity, c.is_rowguidcol
, i.is_unique, k.kct , t.rows, t.rows_sampled, t.unfiltered_rows, t.modification_counter mod_ctr
, t.steps, CONVERT(datetime, CONVERT(varchar, t.last_updated, 120)) updated 
, o.type, d.no_recompute, d.is_incremental, t.partition_number
FROM sys.objects o WITH(NOLOCK) 
JOIN sys.schemas s WITH(NOLOCK) ON s.schema_id = o.schema_id 
JOIN sys.indexes i WITH(NOLOCK) ON i.object_id = o.object_id 
LEFT JOIN sys.stats d WITH(NOLOCK) ON d.object_id = i.object_id AND d.stats_id = i.index_id 
JOIN sys.index_columns j WITH(NOLOCK) ON j.object_id = i.object_id AND j. index_id = i.index_id AND j.key_ordinal = 1 
JOIN sys.columns c WITH(NOLOCK) ON c.object_id = i.object_id AND c.column_id = j.column_id AND j.key_ordinal = 1 
JOIN @k k ON k.object_id = i.object_id AND k.index_id = i.index_id 
LEFT JOIN sys.dm_db_index_usage_stats y ON y.object_id = i.object_id AND y.index_id = i.index_id 
 AND y.database_id = DB_ID() 
OUTER APPLY sys.dm_db_incremental_stats_properties( i.object_id, i.index_id) t 
WHERE o.type IN ('U', 'V') AND i.index_id > 0 AND i.type <= 2 AND i.is_disabled = 0 
AND d.is_incremental = 1 AND s.name <> 'cdc' 
AND ( @modratio*t.modification_counter > t.rows 
 OR ( t.modification_counter*t.modification_counter > @modratio2*t.rows ) 
 OR ( is_unique = 1 AND k.kct = 1 AND t.modification_counter > 0 ) 
 OR t.rows_sampled IS NULL 
) 
  
INSERT dbo.zstats 
SELECT @dd dd, a.rn + @rc1 AS rn , a.[object] , a.[index] , b.row_count , a.user_updates , a.has_filter 
, a.leadcol , a.system_type_id , a.is_identity , a.is_rowguidcol , a.is_unique , a.kct 
, rw_delta = b.row_count - a.rows , a.rows_sampled , a.unfiltered_rows , a.mod_ctr , a.steps 
, a.updated, a.otype, a.no_recompute, a.is_incremental, a.partition_number, 0 persisted_sample_percent
FROM @a a 
JOIN sys.dm_db_partition_stats b WITH(NOLOCK) ON b.object_id = a.object_id AND b.index_id = a.index_id 
AND b.partition_number = a.partition_number 
WHERE b.row_count > 0 
ORDER BY a.rn 
-- End: Incremental Stats code 
IF @Job = 0 
SELECT dd, rn, [object], [index], row_count, user_updates, has_filter filt
, leadcol , system_type_id, is_identity ident, is_rowguidcol rgc, is_unique uni , kct
, rw_delta, rows_sampled /*, unfiltered_rows uf_rows,*/ , mod_ctr, updated, steps
, otype, no_recompute nr, is_incremental incr , partition_number pn, persisted_sample_percent per_smp_pct
FROM dbo.zstats 
WHERE dd= @dd 
 
DECLARE @object varchar(255), @index varchar(255), @SQL varchar(1000) 
, @ident bit, @uni bit, @kct tinyint, @nr bit, @icr bit, @pn int 
, @Inc varchar(50), @FS varchar(100), @Re varchar(50) = '', @rwct bigint
, @leadcol varchar(255), @systype smallint, @skip int, @psp float
DECLARE s CURSOR FOR 
 SELECT [object], [index], leadcol, system_type_id, is_identity, is_unique, kct, no_recompute
 , is_incremental, partition_number, row_count, persisted_sample_percent
 FROM dbo.zstats WHERE dd = @dd 
OPEN s 
FETCH NEXT FROM s INTO @object, @index, @leadcol, @systype, @ident, @uni, @kct, @nr, @icr, @pn, @rwct, @psp
WHILE @@FETCH_STATUS = 0 
BEGIN 
 SET @skip = 0
 IF ( @ident = 1 OR (@uni =1 AND @kct = 1) ) BEGIN 
  SET @FS = '' --IF (@nr = 1 AND @rwct > 100000) SET @Re = 'WITH NORECOMPUTE' ELSE SET @Re = '' 
 END 
 ELSE IF ( @mode = 2 OR @leadcol = 'PayrollPeriodEndDates' OR @systype IN (40,42,58,61) ) BEGIN 
  IF @psp = 0 SET @FS = '' 
  ELSE SET @FS = 'WITH SAMPLE 10 PERCENT, PERSIST_SAMPLE_PERCENT = OFF' -- I don't know how to set to default, 
  -- but this will set to 10% if persist is on, reverts to default on second execute
 END 
 ELSE BEGIN 
  SET @FS = ' WITH FULLSCAN ' --, PERSIST_SAMPLE_PERCENT = ON'    -- IF (@nr = 1) SET @Re = ', NORECOMPUTE' --ELSE SET @Re = '' 
  IF ( @icr = 1 ) SET @FS = CONCAT( 'WITH RESAMPLE ON PARTITIONS (' ,@pn , ')') 
  IF @mode = 1 SET @skip = 1
 END 
 IF @skip = 0 BEGIN
  SELECT @SQL = CONCAT('UPDATE STATISTICS ', @object, '(', QUOTENAME(@index),') ', @FS, @Re) 
  PRINT @SQL + ' -- ' + CONVERT(varchar(50), getdate(),120) 
  EXEC (@SQL) 
 END
 FETCH NEXT FROM s INTO @object, @index, @leadcol, @systype, @ident, @uni, @kct, @nr, @icr, @pn, @rwct, @psp
END 
CLOSE s 
DEALLOCATE s 
 
PRINT '' 
PRINT 'start column stats' 
DECLARE s CURSOR FOR 
 SELECT QUOTENAME(s.name) + '.' + QUOTENAME(o.name) [object], i.name [index] , i.is_incremental 
 FROM sys.objects o WITH(NOLOCK) 
 JOIN sys.schemas s WITH(NOLOCK) ON s.schema_id = o.schema_id 
 JOIN sys.stats i WITH(NOLOCK) ON i.object_id = o.object_id 
 LEFT JOIN sys.indexes x WITH(NOLOCK) ON x.object_id = o.object_id AND x.index_id = i.stats_id 
 OUTER APPLY sys.dm_db_stats_properties(i.object_id , i.stats_id) t 
 WHERE o.type IN ('U','V') 
 AND i.stats_id > 0 AND i.auto_created = 1  AND i.no_recompute = 0 
 AND x.index_id IS NULL 
 AND ( 20*t.modification_counter> t.rows 
  OR ( t.modification_counter*t.modification_counter > 1000*t.rows AND s.name <> 'dbo' ) 
 ) 
 ORDER BY s.name, o.name, i.stats_id 
OPEN s 
FETCH NEXT FROM s INTO @object, @index, @icr 
WHILE @@FETCH_STATUS = 0 
BEGIN 
 SELECT @SQL = CONCAT('UPDATE STATISTICS ' , @object, '(', QUOTENAME(@index),') ' ) 
 PRINT @SQL + ' -- ' + CONVERT(varchar(50), getdate(),120) 
 EXEC (@SQL) 
 FETCH NEXT FROM s INTO @object, @index, @icr 
END 
CLOSE s 
DEALLOCATE s 
return 0 
GO 
IF NOT EXISTS(SELECT * FROM master.sys.objects WHERE is_ms_shipped = 1 AND type = 'P' AND name = 'sp_updatestats2'
) 
EXEC sp_MS_marksystemobject 'sp_updatestats2' 
GO 
--SELECT name, is_ms_shipped FROM sys.objects WHERE name LIKE 'sp_updatestats%' 
--SELECT * FROM master.sys.objects WHERE schema_id = 1 AND type = 'P' AND name NOT LIKE 'sp_MS%'
SELECT name, create_date, modify_date, is_ms_shipped FROM master.sys.objects WHERE schema_id = 1 AND type = 'P' AND name NOT LIKE 'sp_MS%'
GO 
/* 
USE yourdb 
GO 
exec dbo.sp_updatestats2 @modratio = 20 
SELECT * FROM zstats 
WHERE dd >= (SELECT dd1 = ISNULL(MAX(dd),0) - 1 FROM dbo.zstats ) 
SELECT t.name, QUOTENAME(i.name), i.* 
FROM sys.tables t JOIN  sys.indexes i ON i.object_id = t.object_id 
WHERE t.object_id > 1000 
AND CHARINDEX('-', i.name) > 0 
SELECT QUOTENAME([object]),  QUOTENAME([index]) 
FROM zstats 
*/ 

