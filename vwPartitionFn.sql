
IF EXISTS (
  SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.vwPartitionFn') 
 ) DROP VIEW dbo.vwPartitionFn
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/*
-- Start from sys.partition_functions
-- destination_data_spaces & partition_range_values
-- dm_db_partition_stats
-- purpose is to see whether the extra destination_data_spaces exists to support partition split
*/

CREATE OR ALTER VIEW dbo.vwPartitionFn
AS
SELECT f.function_id , f.name pfn, s.data_space_id dsid, s.name psn
, o.object_id, i.index_id, o.name tabl, u.name sch, i.name indx
, e.destination_id pn
, r.value
 , d.in_row_data_page_count page_cnt
 , d.row_overflow_used_page_count ovr_cnt
 , d.lob_used_page_count lob_cnt
 , d.reserved_page_count res_cnt
 , d.row_overflow_reserved_page_count ovr_res
 , d.lob_reserved_page_count lob_res
 , d.row_count row_cnt
 , CASE d.row_count WHEN 0 THEN 0 ELSE CONVERT(decimal(18,1),(8192.*d.in_row_data_page_count)/d.row_count) END RwSz
 , CASE d.row_count WHEN 0 THEN 0 ELSE CONVERT(decimal(18,1),(8192.*d.lob_used_page_count)/d.row_count) END LbSz
, p.data_compression cmp
, i.fill_factor ff
--, f.fanout, f.boundary_value_on_right 
FROM sys.partition_functions f WITH(NOLOCK)
LEFT JOIN sys.partition_schemes s WITH(NOLOCK) ON s.function_id = f.function_id
LEFT JOIN sys.destination_data_spaces e WITH(NOLOCK) ON e.partition_scheme_id = s.data_space_id
LEFT JOIN sys.partition_range_values r WITH(NOLOCK) ON r.function_id = s.function_id AND r.boundary_id = e.destination_id - f.boundary_value_on_right
LEFT JOIN sys.indexes i WITH(NOLOCK) ON i.data_space_id = s.data_space_id
LEFT JOIN sys.dm_db_partition_stats d WITH(NOLOCK) ON d.object_id = i.object_id AND d.index_id = i.index_id AND d.partition_number = e.destination_id
LEFT JOIN sys.partitions p WITH(NOLOCK) ON p.object_id = d.object_id AND p.index_id = d.index_id AND p.partition_number = d.partition_number --  AND p.hobt_id
LEFT JOIN sys.objects o WITH(NOLOCK) ON o.object_id = i.object_id
LEFT JOIN sys.schemas u WITH(NOLOCK) ON u.schema_id = o.schema_id
--WHERE f.function_id = 65536
GO

/*
SELECT * FROM dbo.vwPartitionFn WHERE function_id = 65536
SELECT * FROM dbo.vwPartitionFn WHERE function_id = 65537

SELECT ps.name, ds.mxd, pf.fanout, prv.bid
FROM sys.partition_schemes ps JOIN sys.partition_functions pf ON pf.function_id = ps.function_id
OUTER APPLY (SELECT MAX(destination_id) mxd FROM sys.destination_data_spaces WHERE partition_scheme_id = ps.data_space_id ) ds
OUTER APPLY (SELECT MAX(boundary_id) bid FROM sys.partition_range_values ) prv
WHERE data_space_id = 65602

SELECT * FROM sys.partition_functions
SELECT * FROM sys.partition_schemes

ALTER PARTITION SCHEME psDtR NEXT USED [PRIMARY]

ALTER PARTITION FUNCTION pfDtR()  
{   
    SPLIT RANGE ( boundary_value )  
  | MERGE RANGE ( boundary_value )   
} [ ; ] 

-- test partitions and tables
CREATE PARTITION FUNCTION pfDtL(date) AS RANGE LEFT FOR VALUES 
( '2022-01-01', '2022-02-01', '2022-03-01', '2022-04-01', '2022-05-01', '2022-06-01'
, '2022-07-01', '2022-08-01', '2022-09-01', '2022-10-01', '2022-11-01', '2022-12-01')
CREATE PARTITION FUNCTION pfDtR(date) AS RANGE RIGHT FOR VALUES 
( '2022-01-01', '2022-02-01', '2022-03-01', '2022-04-01', '2022-05-01', '2022-06-01'
, '2022-07-01', '2022-08-01', '2022-09-01', '2022-10-01', '2022-11-01', '2022-12-01')

CREATE PARTITION SCHEME psDtL AS PARTITION pfDtL ALL TO ([PRIMARY])
CREATE PARTITION SCHEME psDtR AS PARTITION pfDtR ALL TO ([PRIMARY])

CREATE TABLE dbo.PL (ID int IDENTITY, Dt DATE) ON psDtL(Dt)
CREATE TABLE dbo.PR (ID int IDENTITY, Dt DATE) ON psDtR(Dt)

INSERT dbo.PL(Dt) VALUES ('2021-01-01'),('2022-01-01'), ('2022-01-02')
INSERT dbo.PR(Dt) VALUES ('2021-01-01'),('2022-01-01'), ('2022-01-02')
INSERT dbo.PL(Dt) VALUES ('2022-12-01'), ('2022-12-02')
INSERT dbo.PR(Dt) VALUES ('2022-12-01'), ('2022-12-02')


SELECT index_id, [indx], psn, pn, value, page_cnt, row_cnt, CASE row_cnt WHEN 0 THEN 0 ELSE CONVERT(decimal(18,1),(8192.*page_cnt)/row_cnt) END RwSz, dsid 
FROM dbo.vwPartition a WHERE a.object_id=OBJECT_ID('dbo.PL') AND index_id <= 1 ORDER BY a.object_id, a.index_id, a.pn

SELECT * FROM dbo.vwPartition WHERE object_id = OBJECT_ID('dbo.PL')
SELECT * FROM dbo.vwPartition WHERE object_id = OBJECT_ID('dbo.PR')

*/