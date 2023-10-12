USE [master]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.sp_spaceused2
 @objname nvarchar(776) = NULL
, @ds sysname = NULL -- -1 means > 1
, @sch sysname = NULL
, @not sysname = NULL
, @viw char(2) = NULL -- 'U', 'V'
, @minrow bigint = 0 
, @Ord int = 0
, @date datetime = NULL
, @debug bit = 0
AS 
SET NOCOUNT ON 
DECLARE @ver varchar(500) = @@VERSION, @ci int , @ver2 int
SELECT @ci = CHARINDEX('20', @ver, 1), @ver2 = TRY_CONVERT(int, SUBSTRING(@ver,@ci, 4)) --SELECT @ver2
DECLARE @dbname sysname, @dsid int, @sid int, @objid int --, @obct int , @clix int
DECLARE @D1 datetime = GETDATE(), @D2 datetime, @df int, @rc int, @StartTime DATETIME = GETDATE() -- execution time 

DECLARE @obj TABLE(schema_id int, object_id int primary key, [type] char(2), [Object] sysname
, pt int, pp int, uPgC bigint, rct bigint, create_date datetime)
IF @objname IS NULL AND @ds IS NULL AND @sch IS NULL 
  INSERT @obj 
  SELECT o.schema_id, o.object_id, o.type, o.name, 0,0,0,0, o.create_date 
  FROM sys.objects o WITH(NOLOCK)  WHERE o.type IN ('S','IT','U','V') AND (o.type <> 'V' OR is_schema_published = 1)
  AND (@date IS NULL OR o.modify_date >= @date)
  AND (@not IS NULL OR CHARINDEX(@not,o.name,1) = 0)
ELSE 
 INSERT @obj
 exec dbo.sp_parseobjects @objname, @ds, @sch, @not
SELECT @rc=@@ROWCOUNT,@D2=GETDATE(),@df=DATEDIFF(ms,@D1,@D2),@D1=@D2; 
IF @debug=1 PRINT CONCAT('-- ',CONVERT(varchar(23),GETDATE(),121),', Mk01: ',STR(@df,7,0),' ms, ',STR(@rc,6,0),' rows, ','obj ct')

--DECLARE @j TABLE (object_id int, key_ordinal int, column_id int)
DECLARE @j TABLE (object_id int, index_id int, key_ordinal int, column_id int, is_descending_key bit)
INSERT @j
SELECT o.object_id, j.index_id, j.key_ordinal, j.column_id, j.is_descending_key
FROM @obj o JOIN sys.index_columns j ON j.object_id = o.object_id AND j.index_id = 1 WHERE o.object_id > 1000
SELECT @rc=@@ROWCOUNT,@D2=GETDATE(),@df=DATEDIFF(ms,@D1,@D2),@D1=@D2; 
IF @debug=1 PRINT CONCAT('-- ',CONVERT(varchar(23),GETDATE(),121),', Mk02: ',STR(@df,7,0),' ms, ',STR(@rc,6,0),' rows, ','ins j')

DECLARE @ClK TABLE( object_id int primary key , ClKey varchar(4000) , ct int) 
 -- for version 2016 and earlier -- prior to STRING_AGG
;WITH j1 AS ( 
  SELECT j.object_id, j.index_id, j.key_ordinal, c.column_id, c.name, is_descending_key 
  FROM @j j INNER JOIN sys.columns c ON c.object_id = j.object_id AND c.column_id = j.column_id 
) 
INSERT @ClK (object_id, ClKey, ct)
SELECT c.object_id , ISNULL(STUFF(( SELECT ', ' + name + CASE is_descending_key WHEN 1 THEN '-' ELSE '' END 
  FROM j1 WHERE j1.object_id = c.object_id AND j1.index_id = 1 AND j1.key_ordinal > 0 
  ORDER BY j1.key_ordinal FOR XML PATH(''), TYPE, ROOT).value( 'root[1]', 'nvarchar(max)'),1, 2,'') ,'') as ClKey
  , x.ct
FROM @obj o JOIN sys.indexes c ON c.object_id = o.object_id
JOIN (SELECT object_id, COUNT(*) ct FROM @j GROUP BY object_id ) x ON x.object_id = c.object_id
WHERE c. index_id = 1 
/*
-- SQL Server version 2017 and later
INSERT @ClK (object_id, ClKey, ct)
SELECT j.object_id, STRING_AGG(c.name,',') WITHIN GROUP(ORDER BY j.key_ordinal) ClKey, COUNT(*) ct
FROM @j j LEFT JOIN sys.columns c ON c.object_id = j.object_id AND c.column_id = j.column_id 
GROUP BY j.object_id
*/

SELECT @rc=@@ROWCOUNT,@D2=GETDATE(),@df=DATEDIFF(ms,@D1,@D2),@D1=@D2; 
IF @debug=1 PRINT CONCAT('-- ',CONVERT(varchar(23),GETDATE(),121),', Mk03: ',STR(@df,7,0),' ms, ',STR(@rc,6,0),' rows, ','Clk count')

-- space used 
DECLARE @i TABLE( object_id int, index_id int, data_space_id int, itype smallint
, is_unique bit, fill_factor smallint, is_disabled bit, is_hypothetical bit, has_filter bit ) 

IF @dsid IS NULL OR @dsid = 0
 INSERT @i SELECT i.object_id, index_id, data_space_id, i.type, is_unique, fill_factor, is_disabled, is_hypothetical, has_filter 
 FROM sys.indexes i WITH(NOLOCK) JOIN @obj o ON o.object_id = i.object_id -- WHERE @dsid IS NULL OR @dsid = 0
ELSE IF @dsid > 0 
 INSERT @i SELECT object_id, index_id, data_space_id, type, is_unique, fill_factor, is_disabled, is_hypothetical, has_filter 
 FROM sys.indexes WITH(NOLOCK) WHERE /*@dsid > 0 AND*/ data_space_id = @dsid
ELSE IF @dsid = -1
 INSERT @i SELECT object_id, index_id, data_space_id, type, is_unique, fill_factor, is_disabled, is_hypothetical, has_filter 
 FROM sys.indexes WITH(NOLOCK) WHERE data_space_id BETWEEN 2 AND 65600 
ELSE IF @dsid = -2
 INSERT @i SELECT object_id, index_id, data_space_id, type, is_unique, fill_factor, is_disabled, is_hypothetical, has_filter 
 FROM sys.indexes WITH(NOLOCK) WHERE data_space_id >= 65600 
SELECT @rc=@@ROWCOUNT,@D2=GETDATE(),@df=DATEDIFF(ms,@D1,@D2),@D1=@D2; 
IF @debug=1 PRINT CONCAT('-- ',CONVERT(varchar(23),GETDATE(),121),', Mk04: ',STR(@df,7,0),' ms, ',STR(@rc,6,0),' rows, ','ins i')

DECLARE @a TABLE( object_id int, otype varchar(2), index_id int, data_space_id int 
, reserved_page_count bigint, used_page_count bigint
, in_row_data_page_count bigint, lob_used_page_count bigint, row_overflow_used_page_count  bigint, row_count bigint
, data_compression smallint, partition_number int, itype smallint
, is_unique bit, fill_factor smallint, is_disabled bit, is_hypothetical bit, has_filter bit ) 
INSERT @a 
SELECT CASE WHEN o.schema_id = 4 THEN
 CASE WHEN o.type = 'S' THEN 1 WHEN o.type = 'IT' THEN 2 ELSE 3 END 
 ELSE o.object_id END AS object_id 
, o.type AS otype, d.index_id , i.data_space_id , d.reserved_page_count, d.used_page_count
, d.in_row_data_page_count, d.lob_used_page_count, d.row_overflow_used_page_count, d.row_count 
, r.data_compression, r.partition_number, i.itype itype
, i.is_unique, i.fill_factor, i.is_disabled, i.is_hypothetical, i.has_filter 
FROM @obj a JOIN sys.objects o WITH(NOLOCK) ON o.object_id = a.object_id
INNER JOIN @i /*sys.indexes i WITH(NOLOCK) */ i ON i.object_id = o.object_id 
LEFT JOIN sys.partitions r WITH(NOLOCK) ON r.object_id = i.object_id AND r.index_id = i.index_id 
LEFT JOIN sys.dm_db_partition_stats d WITH(NOLOCK) ON d.partition_id = r.partition_id 
WHERE (@minrow = 0 OR row_count >= @minrow) 
OPTION (RECOMPILE)
SELECT @rc=@@ROWCOUNT,@D2=GETDATE(),@df=DATEDIFF(ms,@D1,@D2),@D1=@D2; 
IF @debug=1 PRINT CONCAT('-- ',CONVERT(varchar(23),GETDATE(),121),', Mk05: ',STR(@df,7,0),' ms, ',STR(@rc,6,0),' rows, ','ins a')

-- Main queries 
DECLARE @c TABLE( otype varchar(2) , object_id int , Ord int , data_space_id int 
, [Rows] bigint , Reserved bigint , Used bigint , [Data] bigint 
, index2 bigint , index3 bigint , in_row_data bigint , lob bigint , ovrflw bigint 
, Cmpr int , Part int , Pop int , Ppz int , Cnt int 
, Clus int , IxCt int , XmlC int , SpaC int , CoSC int 
, ncs int , Uniq int , disa int , hypo int , filt int 
, rn int
, PRIMARY KEY( object_id,data_space_id) ) 

;WITH b AS ( -- second CTE 
 SELECT object_id, index_id, otype, itype, data_space_id -- MAX(CASE WHEN index_id <= 1 THEN data_space_id ELSE 0 END) data_space_id 
 , CASE WHEN COUNT(*) > 1 THEN 1 ELSE 0 END Part, COUNT(*) AS Cnt 
 , reserved = 8*SUM(reserved_page_count) , used = 8*SUM(used_page_count) 
 , in_row_data = 8*SUM(in_row_data_page_count) , lob_used = 8*SUM(lob_used_page_count) 
 , row_overflow_used = 8*SUM(row_overflow_used_page_count) , row_count = SUM(row_count) 
 , compressed = SUM(data_compression) -- change to 0 for SQL Server 2005 
 , Pop = SUM(CASE WHEN row_count = 0 OR index_id > 1 THEN 0 ELSE 1 END) 
 , Ppz = SUM(CASE WHEN row_count = 0 AND index_id <= 1 THEN 1 ELSE 0 END) 
 , Clus = MAX(CASE a.index_id WHEN 1 THEN 1 ELSE 0 END) , IxCt = MAX(CASE itype WHEN 2 THEN 1 ELSE 0 END) 
 , XmlC = MAX(CASE itype WHEN 3 THEN 1 ELSE 0 END), SpaC = MAX(CASE itype WHEN 4 THEN 1 ELSE 0 END) 
 , CoSC = MAX(CASE itype WHEN 5 THEN 1 ELSE 0 END) 
 , ncs  = MAX(CASE itype WHEN 6 THEN -1 ELSE 0 END) 
 , MO   = MAX(CASE itype WHEN 7 THEN 1 ELSE 0 END) 
 , Uniq = MAX(CASE is_unique WHEN 1 THEN 1 ELSE 0 END) 
 , disa = MAX(CASE is_disabled WHEN 1 THEN 1 ELSE 0 END) , hypo = MAX(CASE is_hypothetical WHEN 1 THEN 1 ELSE 0 END) 
 , filt = MAX(CASE has_filter WHEN 1 THEN 1 ELSE 0 END) 
 FROM @a a GROUP BY object_id, index_id, otype, itype , data_space_id 
) , c AS (
SELECT CASE WHEN otype IS NULL THEN 'A' ELSE otype END otype 
 , CASE WHEN b.object_id IS NULL THEN 0 ELSE b.object_id END AS object_id 
 , CASE WHEN b.object_id IS NULL THEN 0 WHEN b.object_id IN (1,2) THEN b.object_id ELSE 3 END Ord --, data_space_id 
 , MAX(CASE WHEN index_id <= 1 THEN data_space_id ELSE 0 END) data_space_id 
 , [Rows] = SUM(CASE WHEN b.index_id < 2 THEN b.row_count ELSE 0 END) , Reserved = SUM(b.reserved), Used = SUM(b.used) 
 , Data = SUM(CASE WHEN (b.index_id < 2) THEN (b.in_row_data + b.lob_used + b.row_overflow_used) ELSE b.lob_used + b.row_overflow_used END) 
 , index2 = SUM(CASE WHEN b.index_id > 1 AND itype=2 THEN (b.in_row_data) ELSE 0 END) 
 , index3 = SUM(CASE WHEN b.index_id > 1 AND itype>2 THEN (b.used) ELSE 0 END) 
 , in_row_data = SUM(in_row_data), lob = SUM(lob_used), ovrflw = SUM(row_overflow_used) 
 , SUM(CASE compressed WHEN 0 THEN 0 ELSE 1 END) Cmpr 
 , SUM(CASE WHEN b.object_id > 10 AND Part > 0 THEN 1 ELSE 0 END) AS Part 
 , SUM(Pop) Pop, SUM(Ppz) Ppz 
 , MAX(CASE WHEN b.object_id < 10 AND disa = 0 THEN Cnt ELSE 0 END) AS Cnt 
 , SUM(Clus) Clus, SUM(IxCt) IxCt, SUM(XmlC) XmlC, SUM(SpaC) SpaC 
 , SUM(CoSC) CoSC, SUM(ncs) ncs, SUM(Uniq) Uniq, SUM(disa) disa, SUM(hypo) hypo, SUM(filt) filt --, SUM(MO) MO 
 FROM b GROUP BY b.object_id, otype -- , data_space_id 
 WITH ROLLUP HAVING (b.object_id IS NOT NULL AND otype IS NOT NULL /*AND data_space_id IS NOT NULL*/ ) OR b.object_id IS NULL 
)
INSERT @c   
SELECT otype, object_id, Ord, data_space_id, [Rows], Reserved, Used, [Data], index2, index3
, in_row_data, lob, ovrflw, Cmpr, Part, Pop, Ppz, Cnt, Clus, IxCt, XmlC, SpaC, CoSC, ncs, Uniq, disa, hypo, filt
, rn = ROW_NUMBER() OVER (ORDER BY CASE @Ord WHEN 2 THEN [Rows] ELSE Reserved END DESC)
FROM c
SELECT @rc=@@ROWCOUNT,@D2=GETDATE(),@df=DATEDIFF(ms,@D1,@D2),@D1=@D2; 
IF @debug=1 PRINT CONCAT('-- ',CONVERT(varchar(23),GETDATE(),121),', Mk06: ',STR(@df,7,0),' ms, ',STR(@rc,6,0),' rows, ','ins c')

DECLARE @y TABLE(object_id int primary key, lob_data_space_id int)
INSERT @y SELECT object_id, lob_data_space_id FROM sys.tables
-- For name order
DECLARE @o TABLE( object_id int primary key , [Schema] sysname, [Table] sysname, lobds int, create_date datetime, rn int) 
;WITH d AS (
SELECT c.object_id, CASE WHEN t.schema_id IS NULL THEN '' ELSE t.name END [Schema] 
, CASE c.object_id WHEN 0 THEN '_Total' WHEN 1 THEN '_sys' WHEN 2 THEN '_IT' ELSE o.[Object] END [Table] 
, CASE y.lob_data_space_id WHEN 0 THEN NULL ELSE y.lob_data_space_id END lobds  , o.create_date
FROM @c c  
LEFT JOIN @obj o ON o.object_id = c.object_id --LEFT JOIN sys.objects o WITH(NOLOCK) ON o.object_id = c.object_id 
LEFT JOIN /*sys.tables y WITH(NOLOCK) */ @y y ON y.object_id = c.object_id 
LEFT JOIN sys.schemas t WITH(NOLOCK) ON t.schema_id = o.schema_id 
)
INSERT @o SELECT object_id, [Schema], [Table], lobds, create_date, rn = ROW_NUMBER() OVER (ORDER BY [Schema], [Table]) FROM d
SELECT @rc=@@ROWCOUNT,@D2=GETDATE(),@df=DATEDIFF(ms,@D1,@D2),@D1=@D2; 
IF @debug=1 PRINT CONCAT('-- ',CONVERT(varchar(23),GETDATE(),121),', Mk07: ',STR(@df,7,0),' ms, ',STR(@rc,6,0),' rows, ','ins o')

-- index usage stats 
DECLARE @l TABLE( object_id int primary key , CIxSk bigint , IxSk bigint , Scans bigint , lkup bigint , upd bigint , ZrIx int ) 
INSERT @l 
SELECT d.object_id , SUM(CASE index_id WHEN 1 THEN user_seeks ELSE 0 END) CIxSk 
 , SUM( CASE WHEN index_id < 2 THEN 0 ELSE user_seeks END) IxSk 
 , SUM( CASE WHEN index_id < 2 THEN user_scans ELSE 0 END) Scans 
 , SUM( CASE WHEN index_id < 2 THEN 0 ELSE user_lookups END) lkup 
 , SUM( CASE WHEN index_id < 2 THEN 0 ELSE user_updates END) upd 
 , SUM( CASE WHEN index_id > 1 AND user_seeks = 0 THEN 1 ELSE user_updates END) ZrIx 
 FROM @obj o JOIN sys.dm_db_index_usage_stats d WITH(NOLOCK) ON d.object_id = o.object_id
 WHERE database_id = DB_ID() GROUP BY d.object_id 
SELECT @rc=@@ROWCOUNT,@D2=GETDATE(),@df=DATEDIFF(ms,@D1,@D2),@D1=@D2; 
IF @debug=1 PRINT CONCAT('-- ',CONVERT(varchar(23),GETDATE(),121),', Mk08: ',STR(@df,7,0),' ms, ',STR(@rc,6,0),' rows, ','ins l')

-- 2023-04 additional table variables
 DECLARE @s TABLE(object_id int primary key, Stct int)
 INSERT @s SELECT s.object_id, COUNT(*) Stct FROM sys.stats s WITH(NOLOCK) 
 JOIN @o o ON o.object_id = s.object_id WHERE s.object_id > 3 /* skip low values */ GROUP BY s.object_id 
 DECLARE @k TABLE(object_id int primary key, kct int)
 INSERT @k SELECT object_id, COUNT(*) kct FROM sys.index_columns WITH(NOLOCK) WHERE index_id = 1 GROUP BY object_id

 DECLARE @e TABLE(object_id int primary key, cols int, guids int, ngu int)
 INSERT @e
 SELECT CASE WHEN c.object_id IS NULL THEN 0 ELSE c.object_id END object_id, COUNT(*) cols 
  , SUM(CASE system_type_id WHEN 36 THEN 1 ELSE 0 END) guids 
  , SUM(CASE WHEN system_type_id = 36 AND is_nullable = 1 THEN 1 ELSE 0 END) ngu 
 FROM sys.columns c WITH(NOLOCK) JOIN @o o ON o.object_id = c.object_id  GROUP BY c.object_id 
 DECLARE @r TABLE(referenced_object_id int primary key, rkey int)
 DECLARE @f TABLE(parent_object_id int primary key, fkey int)
 INSERT @r SELECT referenced_object_id, COUNT(*) rkey FROM sys.foreign_keys WITH(NOLOCK) GROUP BY referenced_object_id 
 INSERT @f SELECT parent_object_id, COUNT(*) fkey FROM sys.foreign_keys WITH(NOLOCK) GROUP BY parent_object_id 
 DECLARE @d TABLE(parent_object_id int primary key, def int)
 INSERT @d SELECT parent_object_id, COUNT(*) def FROM sys.default_constraints WITH(NOLOCK) GROUP BY parent_object_id 
 SELECT @rc=@@ROWCOUNT,@D2=GETDATE(),@df=DATEDIFF(ms,@D1,@D2),@D1=@D2; 
 IF @debug=1 PRINT CONCAT('-- ',CONVERT(varchar(23),GETDATE(),121),', Mk09: ',STR(@df,7,0),' ms, ',STR(@rc,6,0),' rows, ','ins d')

-- final query 
SELECT otype , /*CASE WHEN t.schema_id IS NULL THEN '' ELSE t.name END*/ o.[Schema] 
, /*CASE c.object_id WHEN 0 THEN '_Total' WHEN 1 THEN '_sys' WHEN 2 THEN '_IT' ELSE o.name END*/ o.[Table] 
, j.ClKey 
, /*CASE is_memory_optimized WHEN 1 THEN x2.rows_returned ELSE [Rows] END*/[Rows] 
, /*CASE is_memory_optimized WHEN 1 THEN memory_allocated_for_table_kb ELSE Reserved END*/ Reserved 
, /*CASE is_memory_optimized WHEN 1 THEN memory_used_by_table_kb ELSE [Data] END*/ [Data] 
, lob --, ovrflw 
, /*CASE is_memory_optimized WHEN 1 THEN memory_used_by_indexes_kb ELSE*/ index2 /*END*/[Index] --, newIx = index3 
, /*CASE is_memory_optimized WHEN 1 THEN memory_allocated_for_table_kb+memory_allocated_for_indexes_kb-memory_used_by_table_kb 
 -memory_used_by_indexes_kb ELSE*/ Reserved - Used /*END*/ Unused 
, AvBR = CASE [Rows] WHEN 0 THEN 0 ELSE 1024*[Data]/ [Rows]END 
, CASE WHEN c.object_id IN (1,2,3) THEN Cnt ELSE Clus END Clus , IxCt, Uniq , XmlC Xm, SpaC Sp, CoSC + ncs cs 
, /*CASE is_memory_optimized WHEN 1 THEN 1 ELSE 0 END*/ 0 MO 
, Stct, kct, Cmpr , Part, Pop, Ppz -- , Cnt 
, CIxSk, IxSk, Scans, lkup, upd , cols, guids, ngu 
, c.data_space_id dsid , /*CASE y.lob_data_space_id WHEN 0 THEN NULL ELSE y.lob_data_space_id END*/ o.lobds  --, fif.ftct, fif.ftsz 
, rkey, fkey, def, trg --, cols 
, disa --, hypo 
, filt , o.create_date 
FROM @c c  
LEFT JOIN @ClK j ON j.object_id = c.object_id 
LEFT JOIN @o o ON o.object_id = c.object_id 
--LEFT JOIN sys.dm_db_xtp_table_memory_stats x ON x.object_id = y.object_id 
--LEFT JOIN sys.dm_db_xtp_index_stats x2 ON x2.object_id = y.object_id AND x2.index_id = 0 
LEFT JOIN @s s ON s.object_id = c.object_id 
LEFT JOIN ( 
 SELECT table_id, SUM(data_size)/1024 ftsz , COUNT(*) ftct 
 FROM sys.fulltext_index_fragments WITH(NOLOCK) WHERE [status] = 4 GROUP BY table_id  ) fif ON fif.table_id = c.object_id 
LEFT JOIN @k k ON k.object_id = c.object_id 
LEFT JOIN @e e  ON e.object_id = c.object_id 
LEFT JOIN @r r ON r.referenced_object_id = c.object_id 
LEFT JOIN @f f ON f.parent_object_id = c.object_id 
LEFT JOIN @d d ON d.parent_object_id = c.object_id 
LEFT JOIN ( SELECT CASE WHEN parent_id IS NULL THEN 0 ELSE parent_id END parent_id, COUNT(*) trg 
 FROM sys.triggers WITH(NOLOCK) WHERE parent_id > 0 GROUP BY parent_id 
) g ON g.parent_id = c.object_id 
LEFT JOIN @l l ON l.object_id = c.object_id 
--WHERE (c.object_id IS NOT NULL ) 
ORDER BY Ord , CASE @Ord WHEN 0 THEN c.rn ELSE o.rn END
OPTION (RECOMPILE) 
SELECT @rc=@@ROWCOUNT,@D2=GETDATE(),@df=DATEDIFF(ms,@D1,@D2),@D1=@D2; 
IF @debug=1 PRINT CONCAT('-- ',CONVERT(varchar(23),GETDATE(),121),', Mk10: ',STR(@df,7,0),' ms, ',STR(@rc,6,0),' rows, ','final')

SELECT @D2=GETDATE(),@df=DATEDIFF(ms,@StartTime,@D2); IF @Debug=1 PRINT CONCAT('-- ',CONVERT(varchar(23),GETDATE(),121),', End:  ',STR(@df,7,0),' ms, ')

GO
-- Then mark the procedure as a system procedure. 
IF NOT EXISTS(SELECT * FROM master.sys.objects WHERE is_ms_shipped = 1 AND type = 'P' AND name = 'sp_spaceused2'
) EXEC sys.sp_MS_marksystemobject 'sp_spaceused2' -- skip this for Azure 
GO 
SELECT * FROM master.sys.objects WHERE is_ms_shipped = 1 AND type = 'P' AND name NOT LIKE 'sp_MS%'
GO
/*
USE master
  SELECT * FROM sys.procedures WHERE name LIKE 'sp_spaceused%'
IF EXISTS ( 
  SELECT * FROM sys.procedures WHERE object_id = OBJECT_ID('sp_spaceused2') 
) DROP procedure dbo.sp_spaceused2
SELECT * FROM sys.partition_schemes
*/

/*
USE Test

exec sp_spaceused2 
exec sp_spaceused3

exec sp_spaceused2 @objname = 'stat%', @Ord=1
exec sp_spaceused2 @ds = '-1'
exec sp_spaceused2 @ds = '-2'
exec sp_spaceused2 @ds = 'psDtL'
exec sp_spaceused2 @ds = 'dbo'

exec sp_spaceused2 @sch = 'dbo'
exec sp_spaceused2 @minrow = 1000
exec sp_spaceused2

SELECT name, is_ms_shipped, * FROM sys.objects WHERE name LIKE 'sp_spaceused2%' 

*****Any SQL advice included in this communication may not contain a full description of all relevant facts 
or a complete analysis of all relevant SQL issues or authorities. 
This communication is solely for the intended recipient's benefit and may not be relied upon by any other person or entity. ***** 
This message (including any attachments)contains confidential information intended for a specific individual and purpose, and is protected by law. 
If you are not the intended recipient, you should delete this message and any disclosure, copying, or distribution of this message, 
or the taking of any action based on it, by you is strictly prohibited.
*/

/*
--( SELECT CASE WHEN referenced_object_id IS NULL THEN 0 ELSE referenced_object_id END referenced_object_id, COUNT(*) rkey FROM sys.foreign_keys WITH(NOLOCK) GROUP BY referenced_object_id  ) 
--( SELECT CASE WHEN parent_object_id IS NULL THEN 0 ELSE parent_object_id END parent_object_id, COUNT(*) fkey FROM sys.foreign_keys WITH(NOLOCK) GROUP BY parent_object_id )
--( SELECT CASE WHEN parent_object_id IS NULL THEN 0 ELSE parent_object_id END parent_object_id, COUNT(*) def  FROM sys.default_constraints WITH(NOLOCK) GROUP BY parent_object_id ) 

SELECT o.object_id, STRING_AGG(c.name,',') WITHIN GROUP(ORDER BY j.key_ordinal) ClKey, COUNT(*) ct
FROM @obj o JOIN sys.indexes i ON i.object_id = o.object_id 
LEFT JOIN sys.index_columns j ON j.object_id = i.object_id AND j.index_id = i.index_id 
LEFT JOIN sys.columns c ON c.object_id = j.object_id AND c.column_id = j.column_id 
WHERE i.index_id = 1 
GROUP BY o.object_id
*/
/*( 
 SELECT CASE WHEN object_id IS NULL THEN 0 ELSE object_id END object_id, COUNT(*) Stct FROM sys.stats WITH(NOLOCK) 
 WHERE object_id > 3 /* skip low values */ GROUP BY object_id 
 WITH ROLLUP HAVING object_id IS NOT NULL OR object_id IS NULL )
 */
 --(SELECT object_id, COUNT(*) kct FROM sys.index_columns WITH(NOLOCK) WHERE index_id = 1 GROUP BY object_id) 
/*( 
  SELECT CASE WHEN object_id IS NULL THEN 0 ELSE object_id END object_id, COUNT(*) cols 
  , SUM(CASE system_type_id WHEN 36 THEN 1 ELSE 0 END) guids 
  , SUM(CASE WHEN system_type_id = 36 AND is_nullable = 1 THEN 1 ELSE 0 END) ngu 
 FROM sys.columns WITH(NOLOCK) GROUP BY object_id */
