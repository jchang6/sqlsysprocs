USE [master]
GO
/*
exec dbo.sp_DbSpaceUsage 256

SELECT * FROM master.sys.procedures WHERE name LIKE 'sp_DbSpaceUsage%'
IF EXISTS ( 
  SELECT * FROM sys.procedures WHERE object_id = OBJECT_ID('sp_DbSpaceUsage') 
) DROP procedure dbo.sp_DbSpaceUsage

*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.sp_DbSpaceUsage
 @size bigint = 256 
, @name nvarchar(250) = ''
, @pending int = 0
AS 
SET NOCOUNT ON 
DECLARE @Log TABLE(dbi int, DatabaseName sysname, RecoveryModel int, DataSize bigint, LogSize bigint, DataFileCt int, LogFileCt int
, DatGrowth bigint, LogGrowth bigint
, TotLogSpace bigint, UsedLogSpace bigint, UsdLgPercent int
, TotPgMB bigint, AllPgMB bigint, UnAllPgMB bigint, MixExtPgCt bigint, ModExtPgCt bigint
)
DECLARE @dbi int, @dn sysname, @rm int, @dsz bigint, @lsz bigint, @dfct int, @lfct int, @dgr bigint, @lgr bigint
, @tls bigint, @uls bigint, @ulp int /**/, @TotPgMB bigint, @AllPgMB bigint, @UnAllPgMB bigint, @MixExtPgCt bigint, @ModExtPgCt bigint
, @Sql1 nvarchar(1000), @Sql2 nvarchar(1000)
, @Par1 nvarchar(1000) = N'@tls bigint OUTPUT, @uls bigint OUTPUT, @ulp int OUTPUT'
, @Par2 nvarchar(1000) = N'@TotPgMB bigint OUTPUT, @AllPgMB bigint OUTPUT, @UnAllPgMB bigint OUTPUT, @MixExtPgCt bigint OUTPUT, @ModExtPgCt bigint OUTPUT'

DECLARE d CURSOR FOR 
 SELECT m.database_id, d.name, d.recovery_model
 , SUM(CASE data_space_id WHEN 0 THEN 0 ELSE size END)/128 dsize, SUM(CASE data_space_id WHEN 0 THEN size ELSE 0 END)/128 lsize
 , SUM(CASE data_space_id WHEN 0 THEN 0 ELSE 1 END) dfilect , SUM(CASE data_space_id WHEN 0 THEN 1 ELSE 0 END) lfilect 
 , SUM(CASE data_space_id WHEN 0 THEN 0 ELSE CASE is_percent_growth WHEN 0 THEN growth/128 ELSE -growth END END) dgr
 , SUM(CASE data_space_id WHEN 0 THEN CASE is_percent_growth WHEN 0 THEN growth/128 ELSE -growth END ELSE 0 END) lgr
 FROM sys.master_files m JOIN sys.databases d ON d.database_id = m.database_id
 WHERE d.state = 0 AND HAS_DBACCESS(d.Name) = 1 --AND replica_id IS NULL 
 AND (@name = '' OR d.name LIKE @name) -- CONCAT('%',@name,'%'))
 GROUP BY m.database_id, d.name, d.recovery_model HAVING SUM(size) > @size*128 -- 128 pages - 1MB
 ORDER BY d.name 

OPEN d
FETCH NEXT FROM d INTO @dbi, @dn, @rm, @dsz, @lsz, @dfct, @lfct, @dgr, @lgr
WHILE @@FETCH_STATUS = 0 
BEGIN 
	SELECT @Sql1 = CONCAT(N'SELECT @tls = total_log_size_in_bytes/1024/1024 , @uls = used_log_space_in_bytes/1024/1024 , @ulp = used_log_space_in_percent
FROM ', QUOTENAME(@dn),'.sys.dm_db_log_space_usage')
	exec sp_executesql @Sql1, @Par1, @tls OUTPUT, @uls OUTPUT, @ulp OUTPUT

	SELECT @Sql2 = CONCAT(N'SELECT @TotPgMB = SUM(total_page_count)/128, @AllPgMB = SUM(allocated_extent_page_count)/128, @UnAllPgMB = SUM(unallocated_extent_page_count)/128 
, @MixExtPgCt = SUM(mixed_extent_page_count)/128, @ModExtPgCt = SUM(modified_extent_page_count)/128 
FROM ', QUOTENAME(@dn), '.sys.dm_db_file_space_usage u')
	exec sp_executesql @Sql2, @Par2, @TotPgMB OUTPUT, @AllPgMB OUTPUT, @UnAllPgMB OUTPUT, @MixExtPgCt OUTPUT, @ModExtPgCt OUTPUT

	INSERT @Log VALUES (@dbi, @dn,@rm, @dsz, @lsz, @dfct, @lfct, @dgr, @lgr /**/,  @tls, @uls, @ulp, /**/ @TotPgMB, @AllPgMB, @UnAllPgMB, @MixExtPgCt, @ModExtPgCt)
	FETCH NEXT FROM d INTO @dbi, @dn, @rm, @dsz, @lsz, @dfct, @lfct, @dgr, @lgr
END
CLOSE d
DEALLOCATE d

DECLARE @iov TABLE(database_id int, file_id int, filect int, sample_ms bigint
, Reads bigint, bytes_rd bigint, ios_read bigint, Writes bigint, bytes_wr bigint, ios_write bigint
, size_on_disk_bytes bigint, file_handle varbinary(250)
)
INSERT @iov
SELECT database_id, file_id, COUNT(*) filect, MAX(sample_ms) sample_ms
, SUM(num_of_reads) Reads, SUM(num_of_bytes_read) byte_rd, SUM(io_stall_read_ms) ios_read
, SUM(num_of_writes) Writes, SUM(num_of_bytes_written) bytes_wr, SUM(io_stall_write_ms) ios_write
, SUM(size_on_disk_bytes) size_on_disk_bytes, file_handle
FROM sys.dm_io_virtual_file_stats(NULL, NULL) v 
GROUP BY v.database_id, v.file_id, file_handle

DECLARE @IoPending TABLE(io_handle varbinary(250), IOPenCnt int, io_pending_ms_ticks bigint, io_pending bigint)
IF @pending = 1
 INSERT @IoPending
 SELECT io_handle, COUNT(*) IOPenCnt, SUM(io_pending_ms_ticks) io_pending_ms_ticks, SUM(io_pending) io_pending 
 FROM sys.dm_io_pending_io_requests WITH (NOLOCK) GROUP BY io_handle 

/*
CREATE TABLE #vfsio(database_id int, file_id int, sample_ms bigint
, Reads bigint, bytes_rd bigint, ios_read decimal(28,1), Writes bigint, bytes_wr bigint, ios_write decimal(28,1)
, size_on_disk_bytes bigint, file_handle varbinary(250)
)
*/
CREATE TABLE #vfsio(database_id int, ftype int, sample_ms bigint 
, Reads bigint, bytes_rd bigint, ios_read decimal(28,1), Writes bigint, bytes_wr bigint, ios_write decimal(28,1)
, SizeMB bigint, IOPenCnt int, io_pending_ms_ticks bigint, io_pending bigint
)
INSERT #vfsio
SELECT v.database_id, m.type ftype, MAX(v.sample_ms) sample_ms 
, SUM(Reads) Reads, SUM(bytes_rd) bytes_rd, SUM(ios_read) ios_read
, SUM(Writes) Writes, SUM(bytes_wr) bytes_wr, SUM(ios_write) ios_write
, SUM(v.size_on_disk_bytes)/1048576 SizeMB
, SUM(p.IOPenCnt) IOPenCnt, SUM(p.io_pending) io_pending, SUM(p.io_pending_ms_ticks) io_pending_ms_ticks
FROM @iov v 
INNER JOIN sys.master_files m WITH (NOLOCK) ON m.database_id = v.database_id AND m.file_id = v.file_id 
LEFT JOIN @IoPending p ON p.io_handle = v.file_handle
GROUP BY v.database_id, m.type

SELECT dbi, QUOTENAME(DatabaseName) DatabaseName, RecoveryModel RecovM
, DataSize, TotPgMB, AllPgMB, UnAllPgMB
, LogSize, TotLogSpace, UsedLogSpace UsedLogSp, UsdLgPercent
, DatGrowth, LogGrowth, MixExtPgCt, ModExtPgCt, DataFileCt, LogFileCt
, d.Reads, d.Writes --, d.bytes_rd/1048576 RdMB , d.bytes_wr/1048576 WrMB
, CASE WHEN ISNULL(d.Reads,0)=0 THEN 0 ELSE d.bytes_rd/d.Reads END [Bytes/dRd]
, CASE WHEN ISNULL(d.Writes,0)=0 THEN 0 ELSE d.bytes_wr/d.Writes END [Bytes/dWr]
, CASE WHEN ISNULL(d.Reads,0)=0 THEN 0 ELSE CONVERT(DECIMAL(18,2),d.ios_read/d.Reads) END [IoMs/dRd]
, CASE WHEN ISNULL(d.Writes,0)=0 THEN 0 ELSE CONVERT(DECIMAL(18,2),d.ios_write/d.Writes) END [IoMs/dWr]
, l.Reads lReads , l.Writes lWrites --, l.bytes_rd/1048576 lRdMB , l.bytes_wr/1048576 lWrMB
, CASE WHEN ISNULL(l.Reads,0)=0 THEN 0 ELSE l.bytes_rd/l.Reads END [Bytes/lRd]
, CASE WHEN ISNULL(l.Writes,0)=0 THEN 0 ELSE l.bytes_wr/l.Writes END [Bytes/lWr]
, CASE WHEN ISNULL(l.Reads,0)=0 THEN 0 ELSE CONVERT(DECIMAL(18,2),l.ios_read/l.Reads) END [IoMs/lRd]
, CASE WHEN ISNULL(l.Writes,0)=0 THEN 0 ELSE CONVERT(DECIMAL(18,2),l.ios_write/l.Writes) END [IoMs/lWr]
, d.sample_ms
, CONCAT(d.sample_ms/1000/86400,'D ', d.sample_ms/1000/3600%24,'Hr ', d.sample_ms/1000/60%60,'Mi ') UpTime
, d.IOPenCnt, d.io_pending, d.io_pending_ms_ticks
FROM @Log f
LEFT JOIN #vfsio d ON d.database_id = f.dbi AND d.ftype = 0
LEFT JOIN #vfsio l ON l.database_id = f.dbi AND l.ftype = 1

IF (OBJECT_ID('tempdb..#vfsio') IS NOT NULL) DROP TABLE #vfsio

GO
-- Then mark the procedure as a system procedure. 
IF NOT EXISTS(SELECT * FROM master.sys.objects WHERE is_ms_shipped = 1 AND type = 'P' AND name = 'sp_DbSpaceUsage'
) 
EXEC sys.sp_MS_marksystemobject 'sp_DbSpaceUsage' -- skip this for Azure 
GO 
--SELECT name, is_ms_shipped FROM sys.objects WHERE name LIKE 'sp_DbSpaceUsage%' 
SELECT * FROM master.sys.objects WHERE is_ms_shipped = 1 AND type = 'P' AND name NOT LIKE 'sp_MS%'
GO
/*
exec dbo.sp_DbSpaceUsage
exec dbo.sp_DbSpaceUsage 0, '', 0

*/
/*
*****Any SQL advice included in this communication may not contain a full description of all relevant facts 
or a complete analysis of all relevant SQL issues or authorities. 
This communication is solely for the intended recipient's benefit and may not be relied upon by any other person or entity. ***** 
This message (including any attachments)contains confidential information intended for a specific individual and purpose, and is protected by law. 
If you are not the intended recipient, you should delete this message and any disclosure, copying, or distribution of this message, 
or the taking of any action based on it, by you is strictly prohibited.
*/

/*
*/

