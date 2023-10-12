-- SQL Scripts , sp_spaceused2 , sp_helpindex2 , sp_partitions , sp_updatestats2 , sp_vas
-- update 2018-02-25
USE master
GO
IF EXISTS (
 SELECT * FROM sys.procedures WHERE object_id = OBJECT_ID('sp_partitions')
) DROP PROCEDURE dbo.sp_partitions
GO
CREATE PROCEDURE dbo.sp_partitions
 @objname nvarchar(4000) = NULL
, @ds sysname = NULL --  can be dataspace _id or dataspace name, either filegroup or partition scheme
, @sch sysname = NULL
, @not sysname = NULL
AS
SET NOCOUNT ON

DECLARE @objct int
DECLARE @obj TABLE(schema_id int, object_id int primary key, [type] char(2), [Object] sysname, pt int, pp int, uPgC bigint, rct bigint, create_date datetime)
INSERT @obj
exec dbo.sp_parseobjects @objname, @ds, @sch, @not
SELECT @objct = @@ROWCOUNT

if @objct < 1
begin
 raiserror(15250 ,-1 ,-1)  
 return (1)
end

SELECT i.object_id, i.index_id, u.name sch, o.[Object] tabl, i.name[indx]
 , f.name pfn, f.function_id, s.name psn, i.data_space_id psi
 , d.partition_number pn, r.value
 , d.in_row_data_page_count page_cnt
 , d.row_overflow_used_page_count ovr_cnt
 , d.lob_used_page_count lob_cnt
 , d.reserved_page_count res_cnt
 , d.row_count row_cnt
 , CASE d.row_count WHEN 0 THEN 0 ELSE CONVERT(decimal(18,1 ), (8192.*d.in_row_data_page_count)/ d.row_count) END RwSz
 , CASE d.row_count WHEN 0 THEN 0 ELSE CONVERT(decimal(18,1),(8192.*d.lob_used_page_count)/d.row_count) END LbSz
 , e.data_space_id dsid
 , p.data_compression cmp
 , i.fill_factor ff
 , i.is_disabled
 , i.is_hypothetical
FROM sys.indexes i WITH(NOLOCK)
--INNER JOIN sys.objects o WITH(NOLOCK) ON o.object_id = i.object_id
INNER JOIN @obj o ON o.object_id = i.object_id
INNER JOIN sys.schemas u ON u.schema_id = o.schema_id
INNER JOIN sys.dm_db_partition_stats d WITH(NOLOCK) ON d.object_id = i.object_id AND d.index_id = i.index_id
LEFT JOIN sys.partition_schemes s WITH(NOLOCK) ON s.data_space_id = i.data_space_id 
LEFT JOIN sys.partition_functions f WITH(NOLOCK) ON f.function_id = s.function_id

LEFT JOIN sys.destination_data_spaces e WITH(NOLOCK) ON e.partition_scheme_id = i.data_space_id
AND e.destination_id = d.partition_number

LEFT JOIN sys.partition_range_values r WITH(NOLOCK) ON r.function_id = s.function_id 
AND r.boundary_id = e.destination_id - f.boundary_value_on_right

LEFT JOIN sys.partitions p WITH(NOLOCK) ON p.object_id = d.object_id AND p.index_id = d.index_id
AND p.partition_number = d.partition_number
--WHERE i.object_id = @objid -- i.type <= 2 AND i.is_disabled = 0 AND i.is_hypothetical = 0
GO

EXEC sys.sp_MS_marksystemobject 'sp_partitions'
GO
--SELECT name, is_ms_shipped FROM sys.objects WHERE name LIKE 'sp_partitions%'
SELECT * FROM master.sys.objects WHERE is_ms_shipped = 1 AND type = 'P' AND name NOT LIKE 'sp_MS%'
GO

/*
USE Test

SELECT * FROM dbo.vwPartition WHERE object_id = OBJECT_ID('dbo.PL')
exec dbo.sp_partitions 'dbo.PL'
exec dbo.sp_partitions @ds='psDtL'
exec dbo.sp_partitions @ds='-2'

*/
/*
DECLARE @objname nvarchar(776) = 'dbo.A'
, @ds sysname = NULL
, @sch sysname = NULL
, @not sysname = NULL

DECLARE @objid int, @dbname sysname, @objn varchar(250), @chixcom int
SELECT @objn=PARSENAME(@objname,1), @sch=PARSENAME(@objname,2), @dbname = parsename(@objname,3)
SELECT @objn, @sch, @dbname
*/
/*

*/

