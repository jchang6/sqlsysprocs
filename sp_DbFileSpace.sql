USE [master]
GO
/*
USE master
  SELECT * FROM sys.system_objects WHERE type = 'P' ORDER BY name
  SELECT * FROM sys.procedures WHERE name LIKE 'sp_DbFileSpace%'
IF EXISTS ( 
  SELECT * FROM sys.procedures WHERE object_id = OBJECT_ID('sp_DbFileSpace') 
) DROP procedure dbo.sp_DbFileSpace
exec dbo.sp_DbFileSpace @name = 'Test'

*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.sp_DbFileSpace
 @size bigint = 256 
, @name nvarchar(250) = ''
, @pending int = 0
AS 
SET NOCOUNT ON 
CREATE TABLE #Files(dbi int, DatabaseName sysname --, RecoveryModel int
, Fid int, FG int, fname sysname, Size bigint
, TotPgMB bigint, AllocPgMB bigint, UnAllPgMB bigint, MixExtPgCt bigint, ModExtPgCt bigint
, Growth bigint, phys_name nvarchar(1000)
)
--CREATE TABLE #vfsio(database_id int, file_id int, num_of_reads bigint, num_of_bytes_read bigint, io_stall_read_ms bigint, num_of_writes bigint, num_of_bytes_written bigint, io_stall_write_ms bigint)
CREATE TABLE #vfsio(database_id int, file_id int, sample_ms bigint
, Reads bigint, bytes_rd bigint, ios_read decimal(28,1), Writes bigint, bytes_wr bigint, ios_write decimal(28,1)
, size_on_disk_bytes bigint, file_handle varbinary(250)
)
DECLARE @dbi int, @dn sysname, @rm int, @Sql1 nvarchar(1000), @Par1 nvarchar(1000) = N'@dbi int, @dn nvarchar(250)'

DECLARE d CURSOR FOR 
 SELECT m.database_id, d.name, d.recovery_model
 FROM sys.master_files m JOIN sys.databases d ON d.database_id = m.database_id
 WHERE d.state = 0 AND HAS_DBACCESS(d.Name) = 1 AND replica_id IS NULL 
 AND (@name = '' OR d.name LIKE @name ) --CONCAT('%',@name,'%'))
 GROUP BY m.database_id, d.name, d.recovery_model 
 HAVING SUM(size) > @size*128 -- 256MB+
 ORDER BY d.name 

OPEN d
FETCH NEXT FROM d INTO @dbi, @dn, @rm
WHILE @@FETCH_STATUS = 0 
BEGIN 
	SELECT @Sql1 = CONCAT(N'SELECT @dbi dbi, QUOTENAME(@dn) dbname, f.file_id, f.data_space_id FG, f.name fname, f.size/128 size
, CASE data_space_id WHEN 0 THEN total_log_size_in_bytes/1024/1024 ELSE u.total_page_count/128 END tot_pg_MB
, CASE data_space_id WHEN 0 THEN used_log_space_in_bytes/1024/1024 ELSE allocated_extent_page_count/128 END Alloc_pg_MB
, unallocated_extent_page_count/128 UnAll_pg_MB, mixed_extent_page_count/128 MxEPC
, modified_extent_page_count/128 MoEPC
, CASE is_percent_growth WHEN 0 THEN growth/128 ELSE -growth END grow
, f.physical_name 
FROM ', QUOTENAME(@dn),'.sys.database_files f 
LEFT JOIN ', QUOTENAME(@dn),'.sys.dm_db_file_space_usage u ON f.file_id = u.file_id
LEFT JOIN ',  QUOTENAME(@dn),'.sys.dm_db_log_space_usage l ON f.data_space_id = 0 
ORDER BY u.filegroup_id,u.file_id')
	INSERT #Files
	exec sp_executesql @Sql1, @Par1, @dbi, @dn

	INSERT #vfsio
	SELECT database_id, file_id, sample_ms, num_of_reads, num_of_bytes_read, io_stall_read_ms, num_of_writes, num_of_bytes_written, io_stall_write_ms 
	, size_on_disk_bytes, file_handle
	FROM sys.dm_io_virtual_file_stats(@dbi, NULL) v 

	FETCH NEXT FROM d INTO @dbi, @dn, @rm
END
CLOSE d
DEALLOCATE d

DECLARE @IoPending TABLE(io_handle varbinary(250), IOPenCnt int, io_pending_ms_ticks bigint, io_pending bigint)
IF @pending = 1
 INSERT @IoPending
 SELECT io_handle, COUNT(*) IOPenCnt, SUM(io_pending_ms_ticks) io_pending_ms_ticks, SUM(io_pending) io_pending 
 FROM sys.dm_io_pending_io_requests WITH (NOLOCK) GROUP BY io_handle 

--DECLARE @z decimal(18,2) = 0
SELECT dbi, DatabaseName, Fid, FG, fname, Size, TotPgMB, AllocPgMB , UnAllPgMB, MixExtPgCt, ModExtPgCt, Growth
, v.reads, v.writes --, v.bytes_rd/1048576 RdMB, v.bytes_wr/1048576 WrMB
, CASE WHEN ISNULL(v.Reads,0)=0 THEN 0 ELSE CONVERT(DECIMAL(18,2),v.ios_read/v.Reads) END [IoMs/Rd]
, CASE WHEN ISNULL(v.Writes,0)=0 THEN 0 ELSE CONVERT(DECIMAL(18,2),v.ios_write/v.Writes) END [IoMs/Wr]
, CASE WHEN ISNULL(ios_read,0)=0 THEN 0 ELSE CONVERT(DECIMAL(18,2),ios_read/v.reads) END [IoMs/Rd]
, CASE WHEN ISNULL(ios_write,0)=0 THEN 0 ELSE CONVERT(DECIMAL(18,2),ios_write/v.writes) END [IoMs/Wr]
, phys_name
, v.sample_ms
, CONCAT(v.sample_ms/1000/86400,'D ', v.sample_ms/1000/3600%24,'Hr ', v.sample_ms/1000/60%60,'Mi ') UpTime
, v.size_on_disk_bytes/1048576 SzOnDiskMB
, p.IOPenCnt, p.io_pending, p.io_pending_ms_ticks
FROM #Files f
LEFT JOIN #vfsio v ON v.database_id = f.dbi AND v.file_id = f.Fid
LEFT JOIN @IoPending p ON p.io_handle = v.file_handle

IF (OBJECT_ID('tempdb..#Files') IS NOT NULL) DROP TABLE #Files
IF (OBJECT_ID('tempdb..#vfsio') IS NOT NULL) DROP TABLE #vfsio

GO
--SELECT 1024*1024
-- Then mark the procedure as a system procedure. 
IF NOT EXISTS(SELECT * FROM master.sys.objects WHERE is_ms_shipped = 1 AND type = 'P' AND name = 'sp_DbFileSpace'
) 
EXEC sys.sp_MS_marksystemobject 'sp_DbFileSpace' -- skip this for Azure 
GO 
--SELECT name, is_ms_shipped FROM sys.objects WHERE name LIKE 'sp_DbFileSpace%' 
SELECT * FROM master.sys.objects WHERE is_ms_shipped = 1 AND type = 'P' AND name NOT LIKE 'sp_MS%'
GO
/*
exec dbo.sp_DbFileSpace 0, '', 1
exec dbo.sp_DbFileSpace
exec dbo.sp_DbFileSpace 0, 'tempdb'
exec dbo.sp_DbFileSpace 256
*/
/*
*****Any SQL advice included in this communication may not contain a full description of all relevant facts 
or a complete analysis of all relevant SQL issues or authorities. 
This communication is solely for the intended recipient's benefit and may not be relied upon by any other person or entity. ***** 
This message (including any attachments) contains confidential information intended for a specific individual and purpose, and is protected by law. 
If you are not the intended recipient, you should delete this message and any disclosure, copying, or distribution of this message, 
or the taking of any action based on it, by you is strictly prohibited.
*/
