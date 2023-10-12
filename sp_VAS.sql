-- SQL Scripts , sp_spaceused2 , sp_helpindex2 , sp_partitions , sp_updatestats2 , sp_vas , sp_plancache_flush 
-- update 2018-07-09 
/*
SELECT * FROM dbo.zVAS
SELECT * FROM dbo.zPlanC
SELECT * FROM sys.configurations
exec sp_configure 'max server memory (MB)', 10240 --	24576
exec sp_configure 'cost threshold for parallelism', 20
RECONFIGURE
exec sp_running

*/
USE [master]
GO 
IF EXISTS ( 
  SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.sp_VAS') 
) DROP PROCEDURE dbo.sp_VAS 
GO 
CREATE PROCEDURE dbo.sp_VAS 
AS 
SET NOCOUNT ON 
IF NOT EXISTS ( 
  SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.zVAS') 
) 
BEGIN 
  CREATE TABLE dbo.zVAS ( DT datetime, vas_res bigint, vas_com bigint, phy_mem bigint 
  , sqlserver_start_time datetime , server_name sysname , cpu_count int, HTR int 
  , CompiledPlan_KB bigint, ExtendedProc_KB bigint, ParseTree_KB bigint 
  , Xmlhd int, OrDocSz int, DormDur int, Cursors int, NetPk8K int, ClrCt int, Clr_time bigint ) 
  IF NOT EXISTS ( 
   SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.zVAS') AND index_id = 1 
  ) 
   CREATE CLUSTERED INDEX CX ON dbo.zVAS(DT) 
END 
IF NOT EXISTS ( 
  SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.zPlanC') 
) 
BEGIN 
  CREATE TABLE dbo.zPlanC ( cacheobjtype varchar(128), objtype varchar(20) 
  , Total_ct int, SingleUse int, TwiceUse int, TotSz_KB bigint, Single_KB bigint, Twice_KB bigint 
  , usecounts bigint , server_name sysname , DT datetime ) 
  IF NOT EXISTS ( 
   SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.zPlanC') AND index_id = 1 
  ) 
   CREATE CLUSTERED INDEX CX ON dbo.zPlanC(DT) 
END 
DECLARE @DT datetime = GETDATE(), @CP bigint, @EP bigint, @PT bigint 
INSERT dbo.zPlanC( cacheobjtype, objtype, Total_ct,SingleUse, TwiceUse,TotSz_KB, Single_KB,Twice_KB 
, usecounts , server_name, DT) 
SELECT cacheobjtype, objtype, COUNT(*) Total_ct 
, SUM(CASE WHEN usecounts = 1 THEN 1 ELSE 0 END) SingleUse 
, SUM(CASE WHEN usecounts = 2 THEN 1 ELSE 0 END) TwiceUse 
, SUM(CONVERT(bigint, size_in_bytes))/1024 TotSz_KB 
, SUM(CASE WHEN usecounts = 1 THEN CONVERT(bigint,size_in_bytes) ELSE 0 END)/1024 Single_KB 
, SUM(CASE WHEN usecounts = 2 THEN CONVERT(bigint, size_in_bytes) ELSE 0 END)/1024 Twice_KB 
, SUM(CONVERT(bigint,usecounts)) usecounts 
, @@SERVERNAME, @DT 
FROM sys.dm_exec_cached_plans 
GROUP BY cacheobjtype , objtype 
ORDER BY cacheobjtype , objtype 
SELECT @CP = [Compiled Plan], @EP = [Extended Proc], @PT = [Parse Tree] 
FROM ( SELECT cacheobjtype, TotSz_KB FROM dbo.zPlanC WHERE DT = @DT ) p 
PIVOT ( SUM (TotSz_KB) FOR cacheobjtype IN ( [Compiled Plan], [Extended Proc], [Parse Tree] ) 
) AS pvt 
 
DECLARE @xmlhd int, @OrDocSz bigint, @DormDur bigint, @cursors int, @netpkt8k int, @clr_ct int, @clr_time bigint 
SELECT @xmlhd = COUNT(*) , @OrDocSz = SUM(original_document_size_bytes) , @DormDur = SUM(dormant_duration_ms) 
FROM sys.dm_exec_xml_handles(0)
SELECT @cursors = COUNT(*) FROM sys.dm_exec_cursors(0) 
SELECT @netpkt8k = COUNT(*) FROM sys.dm_exec_connections WHERE net_packet_size > 8060 
SELECT @clr_ct = COUNT(*) , @clr_time = SUM(total_clr_time) 
FROM sys.dm_exec_query_stats WHERE total_clr_time > 0
 
INSERT dbo.zVAS( DT, vas_res, vas_com, phy_mem, sqlserver_start_time, server_name, cpu_count, HTR 
, CompiledPlan_KB, ExtendedProc_KB, ParseTree_KB, Xmlhd, OrDocSz, DormDur, Cursors, NetPk8K, ClrCt, Clr_time) 
SELECT @DT DT, b.virtual_address_space_reserved_kb vas_res, b.virtual_address_space_committed_kb vas_com 
, b.physical_memory_in_use_kb phy_mem 
, c.sqlserver_start_time, @@SERVERNAME server_name 
, c.cpu_count, c.hyperthread_ratio HTR 
, @CP CompiledPlan_KB, @EP ExtendedProc_KB, @PT ParseTree_KB 
, @xmlhd Xmlhd, @OrDocSz OrDocSz, @DormDur DormDur 
, @cursors Cursors, @netpkt8k NetPk8K, @clr_ct ClrCt, @clr_time Clr_time 
FROM sys.dm_os_process_memory b 
CROSS JOIN sys.dm_os_sys_info c 
 
PRINT CONVERT( varchar(23) ,@DT,121) 
return 0 
GO 
IF NOT EXISTS(SELECT * FROM master.sys.objects WHERE is_ms_shipped = 1 AND type = 'P' AND name = 'sp_VAS'
) 
EXEC sp_MS_marksystemobject 'sp_VAS' 
GO 
SELECT NAME, IS_MS_SHIPPED FROM SYS.OBJECTS WHERE NAME LIKE 'sp_VAS%' 
SELECT name, is_ms_shipped FROM sys.objects WHERE schema_id = 1 AND type = 'P' AND name NOT LIKE 'sp_MS%'

GO 
 
 /*
 SELECT * FROM dbo.zVAS
 */
SELECT * FROM sys.dm_os_process_memory b 
SELECT physical_memory_in_use_kb/1024 pm, available_commit_limit_kb/1024 acl FROM sys.dm_os_process_memory b 

SELECT physical_memory_kb, committed_kb FROM sys.dm_os_sys_info c 
