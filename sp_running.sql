USE master -- skip this for Azure 
GO 
CREATE OR 
ALTER PROCEDURE dbo.sp_running @Plan int = 0
AS
SET NOCOUNT ON -- DECLARE @Plan int = 0
DECLARE @dt datetime = DATEADD(ss,-3,getdate()) --SELECT @dt
DECLARE @blk TABLE(blocking_session_id int) INSERT @blk SELECT blocking_session_id FROM sys.dm_exec_requests r WITH(NOLOCK) WHERE blocking_session_id > 0 -- SELECT * FROM @blk
SELECT r.session_id sid, r.request_id rid, r.start_time, DATEDIFF(ss,r.start_time,@dt) diff, r. status r_status, l. status s_status
, r.blocking_session_id blck, r.command, r.statement_start_offset AS start , r.open_transaction_count otc , r.cpu_time/1000 rcpu, l.cpu_time/1000 scpu 
, r.total_elapsed_time/1000 elapsed, r.reads, r.writes, r.row_count rwct, r.database_id db, r.wait_time --, query_hash, query_plan_hash
 , CASE WHEN r.statement_end_offset = -1 THEN SUBSTRING(s.text, r.statement_start_offset/2+1, 8000) ELSE SUBSTRING(s. text , r.statement_start_offset/2+1, (r.statement_end_offset - r.statement_start_offset)/2+1) END AS [Current SQL]
, r.estimated_completion_time/1000 ect, r.percent_complete pc, SUBSTRING(program_name,1,20) prog_name
, SUBSTRING( LTRIM(s. text ),1,100) AS [Full SQL] --, t.query_plan, t.encrypted
, CASE @Plan WHEN 0 THEN NULL ELSE t.query_plan END query_plan
, l.login_name--, s.objectid --, t.objectid
FROM sys.dm_exec_requests r WITH(NOLOCK) 
LEFT JOIN sys.dm_exec_sessions l WITH(NOLOCK) ON l.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) s OUTER APPLY sys.dm_exec_query_plan (r.plan_handle) t
LEFT JOIN @blk b ON b.blocking_session_id = r.session_id
WHERE (r.session_id > 50
AND r.start_time < @dt AND statement_start_offset <> 168 )
OR r.command = 'KILLED/ROLLBACK' OR r.blocking_session_id > 0
OR b.blocking_session_id IS NOT NULL 
GO 
-- Then mark the procedure as a system procedure. 
IF NOT EXISTS(SELECT * FROM master.sys.objects WHERE is_ms_shipped = 1 AND type = 'P' AND name = 'sp_running'
) 
EXEC sys.sp_MS_marksystemobject 'sp_running' -- skip this for Azure 
GO 
--SELECT name, is_ms_shipped FROM sys.objects WHERE name LIKE 'sp_helpindex%' 
--SELECT name, is_ms_shipped, create_date, modify_date FROM sys.objects WHERE schema_id = 1 AND type = 'P'  AND name LIKE 'sp_helpindex%' 
SELECT * FROM master.sys.objects WHERE is_ms_shipped = 1 AND type = 'P' AND name NOT LIKE 'sp_MS%'

exec sp_running
--(r.session_id IN (SELECT blocking_session_id FROM sys.dm_exec_requests r WITH(NOLOCK) WHERE blocking_session_id > 0)) OR r.session_id = 129
GO

/*
exec sp_running
sp_who2 
kill 117
DBCC INPUTBUFFER(91)
Deloitte.Tax.Database.TaxPortalHTSF9255_Meena.lem.UpdateDynamicLegalEntity;1
*/
