USE [master]
GO
/*
USE master
IF EXISTS ( 
  SELECT * FROM sys.procedures WHERE object_id = OBJECT_ID('sp_VolumeIO') 
) DROP procedure dbo.sp_VolumeIO
exec dbo.sp_VolumeIO 

*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.sp_VolumeIO
 @flag int = 0
, @pending int = 0
AS 
SET NOCOUNT ON 

DECLARE @dv TABLE(database_id int, file_id int, ftype int, volume_mount_point nvarchar(250), total_bytes bigint, available_bytes bigint)
INSERT @dv
SELECT f.database_id, f.file_id, f.type, volume_mount_point, total_bytes, available_bytes 
FROM sys.master_files AS f 
CROSS APPLY sys.dm_os_volume_stats (f.database_id, f.file_id)
WHERE (@flag = 0) OR (@flag = 1 AND f.database_id >= 5) OR (@flag = 2 AND f.database_id = 2)

DECLARE @vmt TABLE(volume_mount_point nvarchar(250), total_bytes bigint, available_bytes bigint)
INSERT @vmt
SELECT DISTINCT volume_mount_point, total_bytes, available_bytes FROM @dv

DECLARE @iov TABLE(database_id int, file_id int, filect int, sample_ms bigint --, UpDays bigint
, Reads bigint, bytes_rd bigint, ios_read bigint, Writes bigint, bytes_wr bigint, ios_write bigint
, size_on_disk_bytes bigint, file_handle varbinary(250))
INSERT @iov
SELECT database_id, file_id, COUNT(*) filect, MAX(sample_ms) sample_ms --, MAX(sample_ms)/1000/86400 UpDays
, SUM(num_of_reads) Reads, SUM(num_of_bytes_read) byte_rd, SUM(io_stall_read_ms) ios_read
, SUM(num_of_writes) Writes, SUM(num_of_bytes_written) bytes_wr, SUM(io_stall_write_ms) ios_write
, SUM(size_on_disk_bytes) size_on_disk_bytes
, file_handle
FROM sys.dm_io_virtual_file_stats(NULL, NULL) v 
GROUP BY v.database_id, v.file_id, file_handle
--SELECT * FROM @iov
DECLARE @IoPending TABLE(io_handle varbinary(250), IOPenCnt int, io_pending_ms_ticks bigint, io_pending bigint)
IF @pending = 1
 INSERT @IoPending
 SELECT io_handle, COUNT(*) IOPenCnt, SUM(io_pending_ms_ticks) io_pending_ms_ticks, SUM(io_pending) io_pending 
 FROM sys.dm_io_pending_io_requests WITH (NOLOCK) GROUP BY io_handle 

CREATE TABLE #vfsio(volume_mount_point nvarchar(250), ftype int, filect int
, Reads bigint, bytes_rd bigint, ios_read bigint, Writes bigint, bytes_wr bigint, ios_write bigint
, sample_ms bigint --, UpDays bigint --, UpHours bigint
, SizeMB bigint, IOPenCnt int, io_pending_ms_ticks bigint, io_pending bigint)

INSERT #vfsio
SELECT m.volume_mount_point, m.ftype, COUNT(*) 
, SUM(Reads) Reads, SUM(bytes_rd) bytes_rd, SUM(ios_read) ios_read
, SUM(Writes) Writes, SUM(bytes_wr) bytes_wr, SUM(ios_write) ios_write
, MAX(sample_ms) sample_ms --, MAX(UpDays) UpDays --, MAX((sample_ms - UpDays*1000*86400)/1000/3600) UpHours
, SUM(size_on_disk_bytes)/1048576 SizeMB
, SUM(p.IOPenCnt) IOPenCnt, SUM(p.io_pending) io_pending, SUM(p.io_pending_ms_ticks) io_pending_ms_ticks
FROM @iov v 
INNER JOIN @dv m ON m.database_id = v.database_id AND m.file_id = v.file_id 
LEFT JOIN @IoPending p ON p.io_handle = v.file_handle
GROUP BY m.volume_mount_point, m.ftype

SELECT f.volume_mount_point, d.filect DataFileCt, l.filect LogFileCt
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
, d.sample_ms --, d.UpDays
, CONCAT(d.sample_ms/1000/86400,'D ', d.sample_ms/1000/3600%24,'Hr ', d.sample_ms/1000/60%60,'Mi ') UpTime

, d.SizeMB dSizeMB, l.SizeMB lSizeMB
, d.IOPenCnt dIOPenCnt, d.io_pending dIO_pending, d.io_pending_ms_ticks dIO_pending_ms_ticks
, l.IOPenCnt lIOPenCnt, l.io_pending lIO_pending, l.io_pending_ms_ticks lIO_pending_ms_ticks
FROM @vmt f
LEFT JOIN #vfsio d ON d.volume_mount_point = f.volume_mount_point AND d.ftype = 0
LEFT JOIN #vfsio l ON l.volume_mount_point = f.volume_mount_point AND l.ftype = 1

IF (OBJECT_ID('tempdb..#vfsio') IS NOT NULL) DROP TABLE #vfsio

GO
-- Then mark the procedure as a system procedure. 
IF NOT EXISTS(SELECT * FROM master.sys.objects WHERE is_ms_shipped = 1 AND type = 'P' AND name = 'sp_VolumeIO'
) 
EXEC sys.sp_MS_marksystemobject 'sp_VolumeIO' -- skip this for Azure 
GO 
--SELECT name, is_ms_shipped FROM sys.objects WHERE name LIKE 'sp_VolumeIO%' 
SELECT * FROM master.sys.objects WHERE is_ms_shipped = 1 AND type = 'P' AND name NOT LIKE 'sp_MS%'
GO
/*
exec dbo.sp_VolumeIO 0, 1
exec dbo.sp_VolumeIO 
exec dbo.sp_VolumeIO 1
exec dbo.sp_VolumeIO 2

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
-- sys.dm_io_virtual_file_stats
-- database_id, file_id, sample_ms, num_of_reads, num_of_bytes_read, io_stall_read_ms, io_stall_queued_read_ms
-- , num_of_writes, num_of_bytes_written, io_stall_write_ms, io_stall_queued_write_ms
-- , io_stall, size_on_disk_bytes, file_handle, num_of_pushed_reads, num_of_pushed_bytes_returned

*/
