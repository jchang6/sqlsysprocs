IF EXISTS (
  SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.vwPartition') 
 ) DROP VIEW dbo.vwPartition
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/*
-- Start from sys.indexes, objects and schemas
-- dm_db_partition_stats for data info by partition_numbers
-- then destination_data_spaces for partition values
*/
GO
CREATE OR ALTER VIEW dbo.vwPartition
AS
 SELECT i.object_id, i.index_id, u.name sch, o.name tabl, i.name [indx]
 , f.name pfn, f.function_id
 , s.name psn, i.data_space_id psi
 , d.partition_number pn
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
 , e.data_space_id dsid
 , p.data_compression cmp
 , i.fill_factor ff
 FROM sys.indexes i WITH(NOLOCK) 
 INNER JOIN sys.objects o WITH(NOLOCK) ON o.object_id = i.object_id
 JOIN sys.schemas u ON u.schema_id = o.schema_id
 LEFT JOIN sys.dm_db_partition_stats d WITH(NOLOCK) ON d.object_id = i.object_id AND d.index_id = i.index_id 
 LEFT JOIN sys.partition_schemes s WITH(NOLOCK) ON s.data_space_id = i.data_space_id  
 LEFT JOIN sys.partition_functions f WITH(NOLOCK) ON f.function_id = s.function_id
 LEFT JOIN sys.destination_data_spaces e WITH(NOLOCK) ON e.partition_scheme_id = i.data_space_id AND e.destination_id = d.partition_number 
 LEFT JOIN sys.partition_range_values r WITH(NOLOCK) ON r.function_id = s.function_id AND r.boundary_id = e.destination_id - f.boundary_value_on_right
 LEFT JOIN sys.partitions p WITH(NOLOCK) ON p.object_id = d.object_id AND p.index_id = d.index_id AND p.partition_number = d.partition_number
 WHERE i.type IN (0,1,2,5) AND i.is_disabled = 0 AND i.is_hypothetical = 0
GO
