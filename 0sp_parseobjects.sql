USE master -- skip this for Azure 
GO 
/*IF EXISTS ( 
  SELECT * FROM sys.procedures WHERE object_id = OBJECT_ID('sp_parseobjects') 
) DROP procedure dbo.sp_parseobjects
*/
-- @objname : 
--  1) can be single schema qualified name
--  2) can be like match dbo.Table%, only on object name, not schema
--  3) can comma separated list
-- @objname takes precedence, overrides @ds and @sch
-- if and only if @objname is NULL
-- @ds : can be dataspace_id or data_space/partition scheme name, overrides @sch
--  1) -1 means all filegroups other than primary, but not partition schemes, < 65601
--  2) -2 means all partition schemes, >= 65601
-- @sch : only used if @objname and @ds are NULL
-- @not : name only, exclude like matches
GO

CREATE OR 
ALTER PROCEDURE dbo.sp_parseobjects 
 @objname nvarchar(4000) = NULL -- was 776
, @ds sysname = NULL
, @sch sysname = NULL
, @not sysname = NULL
AS
SET NOCOUNT ON
DECLARE @objid int, @dbname sysname, @objn varchar(250), @chixper int, @chixcom int, @objs int, @dsid int, @sid int
DECLARE @obj TABLE(schema_id int, object_id int primary key, [type] char(2), [Object] sysname, pt int, pp int, uPgC bigint, rct bigint, create_date datetime)

-- objname should not be schema qualified
IF @objname IS NOT NULL BEGIN
 select @dbname = parsename(@objname ,3) 
 if @dbname is null 
	select @dbname = db_name() 
 else if @dbname <> db_name() 
 begin 
	raiserror(15250, -1,-1) 
	return (1) 
 end 
END

SELECT @chixper = CHARINDEX('%',@objname,1)
, @chixcom = CHARINDEX(',',@objname,1)

IF @chixper > 0 AND @chixcom > 0
--BEGIN
 PRINT 'Cannot have both % pattern match and , separated list'
--END
ELSE IF @chixper > 0
BEGIN
	IF @sch IS NULL SELECT @sch = PARSENAME(@objname,2), @objn=PARSENAME(@objname,1)

	INSERT @obj ([schema_id], [object_id], [type], [Object], pt, pp, uPgC, rct, create_date)
	SELECT o.schema_id, o.object_id, o.type, o.name, 0, 0, 0, 0, o.create_date
	FROM sys.objects o JOIN sys.schemas s ON s.schema_id = o.schema_id
	WHERE o.name LIKE @objn AND o.type IN ('U', 'V') 
	AND (@sch IS NULL OR s.name = @sch)
	AND (@not IS NULL OR CHARINDEX(@not,o.name,1) = 0)
END
ELSE IF @chixcom > 0
--BEGIN
 INSERT @obj([schema_id], [object_id], [type], [Object], pt, pp, uPgC, rct, create_date)
 SELECT o.schema_id, o.object_id, o.type, o.name, 0, 0, 0, 0, o.create_date
 FROM (
  SELECT OBJECT_ID(TRIM(value)) AS object_id FROM STRING_SPLIT(@objname, ',') --WHERE OBJECT_ID(value) IS NOT NULL 
  ) a JOIN sys.objects o ON o.object_id = a.object_id
--END
ELSE IF @objname IS NOT NULL 
--BEGIN
 INSERT @obj([schema_id], object_id, [type], [Object], pt, pp, uPgC, rct, create_date)
 SELECT o.schema_id, o.object_id, o.type, o.name, 0, 0, 0, 0, o.create_date
 FROM sys.objects o WHERE o.object_id = OBJECT_ID(@objname)
--END
ELSE IF @ds IS NOT NULL 
BEGIN
 DECLARE @dst TABLE (dsid int primary key)
 IF isnumeric(@ds) = 0 
  INSERT @dst SELECT data_space_id FROM sys.data_spaces WHERE name = @ds
 ELSE IF CONVERT(int,@ds) >= 1
  INSERT @dst SELECT data_space_id FROM sys.data_spaces WHERE data_space_id = @ds

 ELSE IF CONVERT(int,@ds) = -1
  INSERT @dst SELECT data_space_id FROM sys.data_spaces WHERE data_space_id BETWEEN 2 AND 65600 -- all secondary file groups
 ELSE IF CONVERT(int,@ds) = -2
  INSERT @dst SELECT data_space_id FROM sys.data_spaces WHERE data_space_id >= 65601 -- all partition schemes

 INSERT @obj([schema_id], [object_id], [type], [Object], pt, pp, uPgC, rct, create_date)
 SELECT o.schema_id, o.object_id , o.type, o.name, 0, 0, 0, 0, o.create_date
 FROM sys.objects o WITH(NOLOCK) WHERE o.type IN ('U','V') -- o.type <> 'TF' AND o.type <> 'IT' 
 AND EXISTS(SELECT * FROM sys.indexes i WITH(NOLOCK) 
	JOIN @dst d ON d.dsid = i.data_space_id WHERE i.object_id = o.object_id )
 AND (@not IS NULL OR CHARINDEX(@not,o.name,1) = 0)

END
ELSE IF @sch IS NOT NULL 
--BEGIN
 INSERT @obj([schema_id], [object_id], [type], [Object], pt, pp, uPgC, rct, create_date)
 SELECT o.schema_id, o.object_id, o.type, o.name, 0, 0, 0, 0, o.create_date
 FROM sys.objects o JOIN sys.schemas s ON s.schema_id = o.schema_id
 WHERE o.type IN ('U') AND s.name = @sch
 AND (@not IS NULL OR CHARINDEX(@not,o.name,1) = 0)
 UNION ALL
 SELECT o.schema_id, o.object_id, o.type, o.name, 0, 0, 0, 0, o.create_date
 FROM sys.objects o JOIN sys.schemas s ON s.schema_id = o.schema_id
 WHERE o.type IN ('V') AND s.name = @sch
 AND EXISTS(SELECT * FROM sys.indexes i WHERE i.object_id = o.object_id)
--END
SELECT @objs = @@ROWCOUNT 
SELECT @objs = COUNT(*) FROM @obj

SELECT [schema_id], [object_id], [type], [Object], pt, pp, uPgC, rct, create_date FROM @obj ORDER  BY [Object]
GO
-- Then mark the procedure as a system procedure. 
EXEC sys.sp_MS_marksystemobject 'sp_parseobjects' -- skip this for Azure 
GO 
SELECT * FROM master.sys.objects WHERE is_ms_shipped = 1 AND type = 'P' AND name NOT LIKE 'sp_MS%'
GO
/*
USE Test
SELECT * FROM Test.sys.partition_schemes
SELECT * FROM sys.partition_schemes
exec dbo.sp_parseobjects 'A1'
exec dbo.sp_parseobjects 'AD%'
exec dbo.sp_parseobjects 'AH%'
exec dbo.sp_parseobjects 'AH,AJ'
exec dbo.sp_parseobjects @sch='dbo',@not='stat'
exec dbo.sp_parseobjects @ds = '1',@not='stat'
exec dbo.sp_parseobjects @ds = 'psDtL'
exec dbo.sp_parseobjects @ds = 'psDtR'
*/
/*
DECLARE @ver varchar(500) = @@VERSION, @ci int , @ver2 int
SELECT @ci = CHARINDEX('20', @ver, 1), @ver2 = TRY_CONVERT(int, SUBSTRING(@ver,@ci, 4))
SELECT @ver, @ci, @ver2
-- Microsoft SQL Server 2022 (RTM) - 16.0.1000.6 (X64)   Oct  8 2022 05:58:25   
-- Copyright (C) 2022 Microsoft Corporation  Developer Edition (64-bit) on Windows 10 Pro 10.0 <X64> (Build 22623: ) 
*/

/*
DECLARE @objname nvarchar(776) = 'dbo.A,dbo.T1'
--  SELECT OBJECT_ID(TRIM(value)) AS object_id , TRIM(value)
SELECT o.object_id, o.schema_id
FROM ( SELECT sch = parsename(val,2), objn = parsename(val,1) 
	FROM (SELECT TRIM(value) val FROM STRING_SPLIT(@objname, ',')) a
) b JOIN sys.objects o ON o.name = b.objn 
JOIN sys.schemas s ON s.schema_id = o.schema_id AND (s.name = b.sch OR b.sch IS NULL)

*/

