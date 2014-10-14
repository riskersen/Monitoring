--This is for SQL2kX servers
USE [master]
GO
/****** Object:  StoredProcedure [dbo].[sp_MonitorJobs]    Script Date: 05/06/2014 18:52:59 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_MonitorJobs]
AS  
BEGIN
	SET NOCOUNT ON
	DECLARE @SQL NVARCHAR(4000)
	--Getting information from sp_help_job
	SET @SQL='SELECT 
				Convert(varchar(20),SERVERPROPERTY(''ServerName'')) AS ServerName,
				j.name AS job_name,
				CASE j.enabled 
					WHEN 1 THEN ''Enabled'' 
					Else ''Disabled'' 
					END AS job_status,
				CASE jh.run_status WHEN 0 THEN ''Failed''
					WHEN 1 THEN ''Succeeded''
					WHEN 2 THEN ''Retry''
					WHEN 3 THEN ''Cancelled''
					WHEN 4 THEN ''In Progress'' 
					ELSE ''Unknown'' 
				END AS ''last_run_status'',
		ja.run_requested_date AS last_run_date,
		CONVERT(VARCHAR(10),CONVERT(DATETIME,RTRIM(19000101))+(jh.run_duration * 9 + jh.run_duration % 10000 * 6 + jh.run_duration % 100 * 10) / 216e4,108) AS run_duration,
		ja.next_scheduled_run_date,
		CONVERT(VARCHAR(500),jh.message) AS step_description
		FROM
			(msdb.dbo.sysjobactivity ja LEFT JOIN msdb.dbo.sysjobhistory jh ON ja.job_history_id = jh.instance_id)
			JOIN msdb.dbo.sysjobs_view j ON ja.job_id = j.job_id
		WHERE 
			ja.session_id=(SELECT MAX(session_id)	FROM msdb.dbo.sysjobactivity)
		AND	
			j.enabled = 1
		ORDER BY job_name,job_status'
	EXECUTE sp_executesql @SQL
END