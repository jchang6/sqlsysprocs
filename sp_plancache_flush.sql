-- SQL Scripts , sp_spaceused2 , sp_helpindex2 , sp_partitions , sp_updatestats2 , sp_vas , sp_plancache_flush 
-- update 2018-07-09 
-- update 2019-01-09 considering option to use dm_exec_query_stats in place of dm_exec_cached_plans 
-- update 2019-04-07, SQL Server 2016 has ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE [plan_handle]? I will look into this 
USE [master]
GO 
IF EXISTS ( 
  SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.sp_plancache_flush') 
) DROP PROCEDURE dbo.sp_plancache_flush 
GO 
CREATE PROCEDURE dbo.sp_plancache_flush @number int = 1000 
AS 
SET NOCOUNT ON 
DECLARE @tb TABLE ( cacheobjtype varchar(128), objtype varchar(20) 
  , Total_ct int, SingleUse int, TwiceUse int, TotSz_KB bigint, Single_KB bigint, Twice_KB bigint 
  , usecounts bigint -- , server_name sysname , DT datetime 
) 
-- DECLARE @DT datetime = GETDATE() 
INSERT @tb( cacheobjtype, objtype, Total_ct,SingleUse, TwiceUse,TotSz_KB, Single_KB,Twice_KB 
, usecounts -- , server_name, DT 
) 
SELECT cacheobjtype, objtype, COUNT(*) Total_ct 
, SUM(CASE WHEN usecounts = 1 THEN 1 ELSE 0 END) SingleUse 
, SUM(CASE WHEN usecounts = 2 THEN 1 ELSE 0 END) TwiceUse 
, SUM(CONVERT( bigint, size_in_bytes))/1024 TotSz_KB 
, SUM(CASE WHEN usecounts = 1 THEN CONVERT(bigint, size_in_bytes) ELSE 0 END)/1024 Single_KB 
, SUM(CASE WHEN usecounts = 2 THEN CONVERT(bigint, size_in_bytes) ELSE 0 END)/1024 Twice_KB 
, SUM(CONVERT( bigint, usecounts)) usecounts 
-- , @@SERVERNAME, @DT 
FROM sys.dm_exec_cached_plans 
WHERE cacheobjtype = 'Compiled Plan' 
GROUP BY cacheobjtype , objtype 
ORDER BY cacheobjtype , objtype 
-- display dm_exec_cached_plans summary 
SELECT * FROM @tb 
 
DECLARE @planhandle varbinary(64), @SQL nvarchar(200), @RC int= 0, @lp int= 0 
DECLARE @ph TABLE(ID int identity, plan_handle varbinary(64) ) 
-- first batch 
-- One option, use dm_exec_cached_plans to identify single use plans INSERT @ph (plan_handle) 
SELECT TOP (@number) plan_handle 
FROM sys.dm_exec_cached_plans 
WHERE cacheobjtype = 'Compiled Plan' AND objtype IN ('Adhoc' ,'Prepared') AND usecounts <= 2 -- Change to 1 for single use only 
/* 
-- Alternate option, use dm_exec_query_stats to identify execution count and time since last execution 
INSERT @ph(plan_handle) 
SELECT TOP (@number) plan_handle 
FROM sys.dm_exec_query_stats 
WHERE execution_count = 1 
AND last_execution_time < DATEADD(MI,-600, GETDATE()) -- time since last execution could be implemented as input parameter 
GROUP BY plan_handle 
*/ 
SELECT @RC =@@ROWCOUNT 
-- Outer loop: one batch of 100 per iteration 
WHILE @RC > 100 
BEGIN 
  DECLARE planh CURSOR FOR 
  SELECT plan_handle FROM @ph 
  OPEN planh 
  FETCH NEXT FROM planh INTO @planhandle 
  -- Inner loop: one plan handle at a time 
  WHILE @@FETCH_STATUS = 0 
  BEGIN 
   SET @SQL = CONCAT( 'DBCC FREEPROCCACHE(', CONVERT(nvarchar(200), @planhandle), ')') 
   exec sp_executesql N'DBCC FREEPROCCACHE(@P1) WITH NO_INFOMSGS ', N'@P1 varbinary(200)', @planhandle 
   FETCH NEXT FROM planh INTO @planhandle 
  END 
  CLOSE planh 
  DEALLOCATE planh 
  -- reload for next batch 
  DELETE @ph 
  INSERT @ph(plan_handle) 
  SELECT TOP (@number) plan_handle 
  FROM sys.dm_exec_cached_plans 
  WHERE cacheobjtype = 'Compiled Plan' AND objtype IN ('Adhoc', 'Prepared') AND usecounts <= 2 
  SELECT @RC = @@ROWCOUNT, @lp = @lp + 1 
-- PRINT CONCAT('Loop ', @lp,', rc ', @rc)
END
 
-- PRINT CONVERT( varchar(23) ,@DT,121) 
SELECT cacheobjtype, objtype, COUNT(*) Total_ct 
, SUM(CASE WHEN usecounts = 1 THEN 1 ELSE 0 END) SingleUse 
, SUM(CASE WHEN usecounts = 2 THEN 1 ELSE 0 END) TwiceUse 
, SUM(CONVERT(bigint, size_in_bytes))/1024 TotSz_KB 
, SUM(CASE WHEN usecounts = 1 THEN CONVERT(bigint,size_in_bytes) ELSE 0 END)/1024 Single_KB 
, SUM(CASE WHEN usecounts = 2 THEN CONVERT(bigint,size_in_bytes) ELSE 0 END)/1024 Twice_KB 
, SUM( CONVERT(bigint, usecounts)) usecounts 
-- , @@SERVERNAME, @DT 
FROM sys.dm_exec_cached_plans 
WHERE cacheobjtype = 'Compiled Plan' 
GROUP BY cacheobjtype , objtype 
ORDER BY cacheobjtype , objtype 
return 0 
GO 
IF NOT EXISTS(SELECT * FROM master.sys.objects WHERE is_ms_shipped = 1 AND type = 'P' AND name = 'sp_plancache_flush'
) 
EXEC sp_MS_marksystemobject 'sp_plancache_flush' 
GO 
SELECT * FROM master.sys.objects WHERE is_ms_shipped = 1 AND type = 'P' AND name NOT LIKE 'sp_MS%'

GO 
-- exec sp_plancache_flush 10000 
 