USE [master]
GO
/****** Object:  StoredProcedure [dbo].[sp_MonitorJobs]    Script Date: 05/07/2014 14:15:21 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_MonitorJobs]
AS  
BEGIN
	--This is for SQL2k servers
	SET NOCOUNT ON
	DECLARE @SQL NVARCHAR(4000)
	--Getting information from sp_help_job
	SET @SQL='SELECT 
		job_id, 
		name AS job_name,
		CASE enabled 
			WHEN 1 THEN ''Enabled'' 
			ELSE ''Disabled'' 
			END AS job_status,
		CASE last_run_outcome WHEN 0 THEN ''Failed''
			WHEN 1 THEN ''Succeeded''
			WHEN 2 THEN ''Retry''
			WHEN 3 THEN ''Cancelled''
			WHEN 4 THEN ''In Progress'' 
			ELSE ''Unknown'' 
			END AS  last_run_status,
	CASE RTRIM(last_run_date) WHEN 0 THEN 19000101 ELSE last_run_date END last_run_date,
	CASE RTRIM(last_run_time) WHEN 0 THEN 235959 ELSE last_run_time END last_run_time, 
	CASE RTRIM(next_run_date) WHEN 0 THEN 19000101 ELSE next_run_date END next_run_date, 
	CASE RTRIM(next_run_time) WHEN 0 THEN 235959 ELSE next_run_time END next_run_time,
	last_run_date AS lrd, last_run_time AS lrt
	INTO ##nagios_jobdetails
	FROM OPENROWSET(''sqloledb'', ''server=(local);trusted_connection=yes'', ''set fmtonly off exec msdb.dbo.sp_help_job'')
	WHERE enabled = 1'
	EXECUTE sp_executesql @SQL
	
	--Merging run date & time format, adding run duration and adding step description
	select 
		Convert(varchar(20),SERVERPROPERTY('ServerName')) AS ServerName,
		jd.job_name,
		jd.job_status,
		jd.last_run_status,
		jd.lrd,
		jd.lrt,
	CONVERT(DATETIME,RTRIM(jd.last_run_date)) +(jd.last_run_time * 9 + jd.last_run_time % 10000 * 6 + jd.last_run_time % 100 * 10) / 216e4 AS last_run_date,
	CONVERT(VARCHAR(10),CONVERT(DATETIME,RTRIM(19000101))+(jh.run_duration * 9 + jh.run_duration % 10000 * 6 + jh.run_duration % 100 * 10) / 216e4,108) AS run_duration,
	CONVERT(DATETIME,RTRIM(jd.next_run_date)) +(jd.next_run_time * 9 + jd.next_run_time % 10000 * 6 + jd.next_run_time % 100 * 10) / 216e4 AS next_scheduled_run_date,
	CONVERT(VARCHAR(500),jh.message) AS step_description
	from (##nagios_jobdetails jd  LEFT JOIN  msdb.dbo.sysjobhistory jh ON jd.job_id=jh.job_id AND jd.lrd=jh.run_date AND jd.lrt=jh.run_time) where step_id=0 or step_id is null
	order by jd.job_name,jd.job_status
	
	-- Clean-Up
	DROP TABLE ##nagios_jobdetails
END

